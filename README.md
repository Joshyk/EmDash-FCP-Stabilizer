# Final Cut Pro Stabilizer

Native FxPlug 4 effect for Final Cut Pro and Motion, tuned for walking footage
shot on a gimbal.

This repo contains the FxPlug effect plus the local Stabilizer Event Analyzer
support tool. The FxPlug target remains native FxPlug/Metal code and does not
contain a CommandPost runtime or Transform-keyframe writer.

## What It Does

`Tokyo Walking Stabilizer` renders the source clip through Metal and applies
automatic stabilization inside the FxPlug render path. It avoids Final Cut Pro's
built-in Stabilization effect because that effect applies its own internal crop
and scale.

The effect is designed for outdoor walking shots where the camera is already on
a gimbal but still has step shock, short wobble, segmented turns, and distant
ridge-line shake.

Version `1.2.12` reuses schema 52 all-axis Camera Jitter analysis. It applies
validated high-frequency X after TURN concatenation and reserves accepted X crop
coverage across the configured zoom interval. Accepted render-space translation X
is not amplitude- or step-limited in TURN, Camera Jitter, Camera Rigid, or Lens/Far-field paths.
Far-field Pan Band X no longer uses the 5px limiter, Macro X is excluded only by the
explicit tracking-outlier decision, and Auto Crop required scale has no fixed 128x ceiling. It stores
frame-local Camera Rigid X/Y/roll targets, scale-aware top/ridge agreement,
independent forward/backward evidence, and frame-local dominant-mesh residuals.
The render trajectory uses each axis support once, keeps coherent
fine X/Y/roll outside the 2.2-second Turn/Macro Jitter smoother, and records validated
original-media provenance. Turn owns only broad X; Camera Jitter owns short
whole-frame X/Y/roll correction.
Camera Rigid Y remains limited by its explicit Inspector percentage (0...5% of the
render output), and roll remains limited to 0...2 degrees. Camera Rigid X uses its
Inspector strength without a render-space amplitude cap.
Schema 52 removes a centered one-second quadratic X baseline before storing the
Camera Rigid X target, so sustained pan curvature remains Turn-owned without
suppressing two-to-five-frame X reversals.
During a TURN event, the final composed Viewer X path uses one constant cruising
velocity with quintic easing limited to up to 0.30 seconds at each endpoint. TURN macro travel remains the distance authority, while Camera
Jitter and continuity X cannot reintroduce pauses or speed steps inside the curve.
Endpoint correction carries through a continuous handoff, but during a true idle span
it releases with the configured `Auto Crop Zoom-Out Time` quintic duration (clamped by the available idle span) back to the underlying X path so
Crop Off does not retain a stationary black edge. The Window caps each accumulation event
from its first active sample. If that cap alone splits uninterrupted
same-direction activity, the bounded events share one constant-velocity render
chain instead of stopping and restarting at the Window boundary. Brief
opposite-sign activity is absorbed using travel-based reversal hysteresis that
increases with Turn Smoothing Strength, while diagnostic X components remain
visible.
Future tuning should preserve that seconds-based detector, avoid fixed-frame
shake windows, and keep the rendered correction coherent enough that mountains,
clouds, and horizons do not locally pulse or swim.

The main correction stages are:

- `Camera Jitter`: unified frame-local, medium-period, and coherent global X/Y/roll cleanup.
  TURN owns only broad X motion.
- `Far-field Warp Strength`: small-clamp deskew, yaw/pitch proxy, and
  perspective trim for distant background shake.
- `LENS`: source-space far-field stabilization for short ridge/cloud/horizon
  shake. Current analysis first tries a two-way far-field rigid path so clouds,
  ridge lines, and mountains move as one plane instead of being locally warped
  into a visible pulse.
- `Turn Smoothing`: X-only smoothing for stop-and-go walking turns.

`Remove Black Edges` is on by default and applies dynamic Auto Crop framing during
render so stabilized pixels stay inside the source image. Turn it off when you need
to temporarily bypass the Auto Crop work for playback diagnosis; edge fill then
comes from `Edge Display Mode`, which switches between stretched source edges and
black outside-source pixels. `Edge Display Mode` defaults to `Black Outside`.

## Basic Workflow

1. Export the Event or Project from Final Cut Pro as FCPXMLD.
2. Run the local Stabilizer Event Analyzer in `Stabilizer-Event-Analyzer/` on
   the exported FCPXMLD. It
   analyzes the Event media full length and writes the Event-scoped persisted
   cache.
3. Import the generated FCPXMLD back into Final Cut Pro and open its generated
   `Stabilized Review` project.
4. Keep the pre-applied `Tokyo Walking Stabilizer` effect on the review timeline
   clip and wait for `Host Analysis Status` to show `Persisted Analysis Loaded`
   or `Ready (... frames)`.
5. Tune the strength controls while watching the preview.

New effect instances no longer expose `Sample Size`, `Start Host Analysis`,
`Clear Host Analysis Cache`, or `Queue` in the Final Cut Pro Inspector. Analysis
is managed by the local Event Analyzer. Preview and render callbacks only
read completed analysis or a validated persistent cache; they do not start
analysis on their own.

## Optional Final Cut Pro Shortcuts

The shared workspace script `../scripts/fcp_stabilizer_shortcuts.applescript`
provides UI-scripted helper actions for Keyboard Maestro, Automator Quick
Actions, or manual `osascript` runs:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript apply
osascript ../scripts/fcp_stabilizer_shortcuts.applescript toggle-debug-overlay
osascript ../scripts/fcp_stabilizer_shortcuts.applescript focus-inspector
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-selected-project
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-project "stab test - gh6"
osascript ../scripts/fcp_stabilizer_shortcuts.applescript select-playhead-clip
```

These actions use Final Cut Pro Accessibility UI scripting. Grant Accessibility
permission to the app that runs the script. `toggle-debug-overlay` fails visibly
if the selected clip does not have `Tokyo Walking Stabilizer` applied or the
Inspector control is not accessible.
`open-project PROJECT_NAME` opens a named Browser project, `open-selected-project`
opens the selected Browser project, and `select-playhead-clip` reselects the
timeline clip under the playhead before analysis. Project open commands select
the Browser item and run `Clip > Open Clip`, which has been more reliable than
repeated AppleScript clicks in Final Cut Pro.

## Inspector Controls

Analysis sample size is selected in the local Stabilizer Event Analyzer and
shown in the read-only `Sample Info` row after a cache is loaded. The row uses
`Sample: <percent or unknown> -> <WxH> | Analysis: <N>f`. The Final Cut Pro
effect no longer exposes a `Sample Size` control.

`Overall Strength` controls the full automatic transform. Setting it to `0`
bypasses prepared motion-path sampling, crop-safety motion, and debug overlay
output, producing an identity transform.

`Micro Jitter` strengths are direct removal amounts for frame-local X, Y, and
roll impulses. X and Y default to `4.0` and run up to `10.0`; rotation defaults
to `1.0` and runs up to `4.0`. X uses the requested amount directly, without a
tracking-confidence multiplier, continuity limiter, or correction-amplitude cap.
Y and roll retain their evidence-qualified response. The
baseline uses seconds, not frame counts: it skips the center `0.10` second shock
region and predicts from outer samples up to `1.0` second away. Confidence is
based on current tracking evidence, local baseline support, and the center
frame's impulse relative to surrounding micro noise. After those safety signals are
combined, the same unbiased finite-value check and linear `0...1` clamp used by TURN,
MAJIT, and WARP is applied. Zero evidence and noisy unsupported frames therefore still
produce zero correction. The surrounding-noise floor is capped below the full-response point
so repeated walking motion does not bury a real center-frame landing shock.
MIJIT and MAJIT Y/roll use a walking-band tracking gate that slightly eases block coverage only
when enough motion blocks were accepted; WARP and TURN keep the stricter tracking gate to
avoid swimming or false turn smoothing. X keeps its full detected Micro and Macro
Jitter correction during monotonic turns. TURN is built from the low-frequency macro
path first; the finite high-frequency X residual is then added without clipping, so
fine shake removal does not weaken the turn distance, direction, or endpoint.

`Macro Jitter` removes step follow-through shake using a fixed internal
`2.0` second render-time window. The Inspector exposes only X, Y, and rotation
strengths. It is measured from the micro-cleaned path, then longer Turn
Smoothing is measured from the macro-jitter-smoothed path so the same motion is not
removed twice. It does not use the raw or jerk-limited
broad path as its band input. Its residual gate uses robust window percentiles
instead of letting a single bad frame suppress the whole band. Macro Jitter evidence uses
the same unbiased finite-value check and linear `0...1` clamp as the other correction
bands. X and Y default to `4.0` and run
up to `10.0`; the rotation default is `1.0`. The X band bypasses the former
turn-ownership gate; frequency separation keeps it distinct from broad Turn Smoothing.
Macro confidence can still be lower on a real frame because it measures the smaller
post-Micro residual, uses `0.75` px / `0.16` degree full-response evidence instead of
Micro's `0.35` px / `0.08` degree thresholds, and reports the X/Y/roll mean. Those are
evidence differences, not a Macro-only confidence bias.

`Turn Smoothing Strength` is the single X-turn correction-amplitude control. It defaults
to `12.0` and ranges from `0.00...36.00`; `0` disables TURN correction and `36`
requests the maximum confidence-qualified X correction. `Turn Transition Window (s)`
independently selects the `0.5...8.0` second maximum accumulation span measured from
the first active sample. Same-direction turn bursts, pauses, and pan-speed changes
inside that fixed span are accumulated monotonically and redistributed through one
constant-velocity path with short quintic endpoint ramps, so intermediate pauses or speed steps do not survive as separate viewport
transitions. Strength scales TURN travel before that redistribution; it is not
reapplied to the unsmoothed macro path afterward. A reversal or activity beyond the first-sample Window starts a new event;
directly adjacent same-direction events remain one render chain. A curve may
pre-roll by up to 30% of its known Turn X travel. Camera Jitter X is made mean-free within
that Window so it cannot become a
second low-frequency pan owner. Actual
correction still requires tracking evidence and real X-turn travel.
With `Remove Black Edges` off, Auto Crop is completely bypassed: scale is exactly `1.0`
and its look-ahead position reservation is not mixed into TURN. The uncovered edge is
therefore the direct result of Camera Jitter and TURN only. When on, Auto Crop zoom hides
that same edge according to `Zoom-In Time`, `Hold Time`, and `Zoom-Out Time`.
For overlapping intervals whose next peak needs less scale, the previous Hold now hands
zoom and crop X down together over the shorter of `Zoom-Out Time` and the time
remaining to that next peak. They share one linear constant-speed progress with no endpoint
easing, and stop at the next turn's protected scale and X reservation instead of returning
to `1.0x` and center. Coverage, planned-position, and
final framing-repair floors remain absolute. Equal or higher next peaks retain existing
look-ahead behavior, and the last peak retains its ordinary release.
TURN confidence now requires both tracking evidence and a real X turn band, so
low-evidence frames do not get a hidden minimum turn correction.

`Far-field Warp Strength` bundles small-clamp shear, yaw/pitch proxy, and
perspective trim for distant background motion. It is applied from the current
frame's local deviation from its own `1.0` second outer-frame linear baseline,
so long-term drift does not become a fixed deskew. The default is `1.0`, the
previous `4.0` strength response is unchanged, and the maximum is now `12.0`.
The render path gates warp with walking-footage tracking quality and
search-radius headroom. The tracking gate starts early enough for moderate
25% Host Analysis evidence but reaches full response more gradually, uses short
local tracking support to reduce single-frame gate flicker, then drops tiny warp
deltas through a deadband so useful ridge-line correction is less likely to
disappear while high-side gate jumps and low-confidence warp evidence are
suppressed instead of producing a wavy image.
Short-period source shake detected on the ridge/horizon band is stored as a
separate source-space path and rendered as a narrow upper-frame sample-coordinate
warp. This keeps sub-second lens/camera/OIS-style residuals out of the final X/Y
trajectory and avoids using Auto Crop zoom to hide the motion. The correction is
weighted toward the ridge/cloud/horizon area and fades before the near ground, so
road, grass, and water parallax are not used as the stability target.

`Remove Black Edges` controls dynamic Auto Crop framing. When it is off, the render
path skips Auto Crop crop-safe framing completely, so
`Edge Display Mode` directly controls whether outside-source pixels are stretched
or black. New effect instances default that menu to `Black Outside`.
`Auto Crop Zoom-In Time`, `Auto Crop Zoom-Out Time`, and `Auto Crop Hold Time`
remain visible for parameter compatibility. With `Remove Black Edges` on, the
render path builds a cached Auto Crop zoom keypoint plan from the prepared
analysis instead of recalculating final zoom every render frame. Each local peak
safe-crop demand becomes an internal zoom keypoint. `Auto Crop Zoom-In Time`,
`Auto Crop Hold Time`, and `Auto Crop Zoom-Out Time` define the lead, hold, and
release durations directly in seconds, with no hidden scale-based duration
shrink. The visible crop zoom and center position follow the same ease-in/out
keypoint curve, while the current
render frame is used only to clamp the crop center inside the planned scale.
A coverage repair pass checks the
prepared analysis against that curve and adds only the keypoints needed to keep
the curve above black-edge safety demand, so occasional outside-source boxes do
not force frame-by-frame zoom calculation. Low-demand coverage misses are folded
back into the smooth keypoint plan so subtle black-edge fixes do not become
per-frame crop wobble. Low-demand keypoints that sit near identity halve their
zoom delta and use shorter keypoint timing, so subtle or nearly idle sections do
not remain as visibly cropped while strong turn peaks keep their full planned zoom.
Auto Crop does not add fixed base-crop padding. A truly idle transform retains
only the boundary sampler's one-pixel black-edge guard (about `1.0019x` at
1080p), without adaptive padding. Larger measured transform demand retains its
adaptive safety margin, and the coverage repair pass remains authoritative for
black-edge protection.
After coverage repair, micro zoom keypoints at demand scale `<= 1.03` are merged
when their windows touch and their crop centers stay close, then coverage is
checked again before the merged plan is accepted. The Host Analysis status shown
while `Debug Overlay` is enabled includes short Auto Crop telemetry (`crop z`,
`miss`, `worst`, `merge`), and the log summary prints raw/merged keypoint counts
plus worst coverage deficit. This render-time merge does not change Host
Analysis cache schemas or prepared stabilization paths. When no
keypoint is active and the transform stays quiet for a couple seconds, Auto Crop
returns to identity so idle shots settle near zero crop zoom.

`Debug Overlay` shows labeled top-left diagnostics for the active correction
bands and tracking state. It also includes a compact runtime/source row for the
active render runtime and current source mode: `ORIGINAL <version>` means the current FxPlug
runtime is rendering original/optimized frames, and `PROXY <version>` means proxy playback
is using the saved analysis path. The version is derived from the active FxPlug runtime.
It does not control black outside-source pixels; `Edge Display Mode`
controls that separately.
The overlay scales from the current render output so the top-left panel occupies
roughly half of the viewer height in original, optimized, and proxy playback.
Its correction rows are ordered from final rigid/crop motion through lower-frequency walking
bands to higher-frequency and spatial correction. `X OFFSET`, `Y OFFSET`, `ROLL`, `MACRO JITTER`,
`MICRO JITTER`, `FAR WARP`, and `SMOOTHING` use final values that are actually handed to Metal,
after their applicable limits and Master Strength.
`Mesh Overlay` is separate from `Debug Overlay`: it can show the far-field mesh,
lens-local mesh, band guides, or all meshes without drawing the top-left bars.
Mesh families use distinct thicker colors so source-space cell boundaries remain
visible during FCP preview review.

`Host Analysis Status` appends the current FxPlug version when Final Cut Pro
accepts status parameter updates. For existing timeline instances that keep
stale saved Inspector strings, `Debug Overlay` is the live render-runtime
indicator. `Sample Info` is built from the structured cache snapshot as
`Sample: <percent or unknown> -> <WxH> | Analysis: <N>f`; it does not fall back
to hidden `Sample Size` or parse status strings. `Clip Range` and `Queue` are not
part of the visible Inspector metadata for new effect instances. Older saved
timeline instances may still display stale saved info strings until the effect
is reapplied.

## Host Analysis

Analysis generation now happens in the local Stabilizer Event Analyzer. The
Final Cut Pro effect is a cache consumer: it validates Event-scoped persisted
analysis, loads the prepared motion path, and renders from that path. New effect
instances do not expose `Start Host Analysis`, `Clear Host Analysis Cache`,
`Sample Size`, or `Queue`, and preview/render callbacks do not auto-start
analysis.

The local analyzer uses Metal block matching, writes the same
`host-analysis-v2.json`, `host-analysis-index-v2.json`, render-offset map, and
range-specific cache files under the Event `Analysis Files` cache root, and
keeps sample-size-specific results independent. If the effect cannot find a
compatible cache it shows `External Analysis Required - Run Event Analyzer`.
Rejected, unsupported, or incomplete candidates are left on disk and surfaced as
`Cache Rejected - Run Event Analyzer`,
`Cache Unsupported - Run Event Analyzer`, or
`Cache Incomplete - Run Event Analyzer`.

Older timeline instances may still contain the now-hidden Host Analysis controls.
The old Start button only attempts to reload a compatible Event Analyzer cache;
it no longer asks Final Cut Pro to start a forward Host Analysis pass. The old
Clear button does not delete Event Analyzer cache files and reports
`External Cache Managed - Use Event Analyzer`.

Viewer-side render instances monitor the shared persistent cache location. When
the local analyzer writes a compatible cache and the FCPXMLD import connects
it to the timeline clip, the viewer-side instance loads the completed cache and
publishes the hidden render revision so stale preview frames redraw from the
prepared motion path. If Final Cut Pro rejects a hidden revision update, the
plug-in does not mark it as published, so a later monitor tick or callback can
retry.

Prepared paths are post-processed with a zero-phase jerk limiter before caching.
The limiter clamps isolated acceleration spikes in X/Y/roll while preserving
path endpoints and total analyzed turn amount. Raw X/Y/roll impulse paths are
stored separately so Micro Jitter can still correct frame-level shake at
render time.

Render-time smoothing samples neighboring render times symmetrically across a
`1.20` second zero-phase window and blends the automatic transform. At clip
edges it averages only in-range neighboring samples instead of duplicating the
first or last analysis frame. It smooths Macro Jitter and Turn Smoothing bands
without averaging away the current frame's Micro Jitter
impulse. Far-field Warp uses a separate short `0.20` second in-range smoothing
window so distant ridge-line correction stays responsive without amplifying
single-frame gate flicker. Render-time frame lookup uses the sorted Host Analysis
times directly, so long analysis caches do not require repeated full-cache scans
for every preview frame.

Trimmed clips are handled by matching the current render frame fingerprint back
to the analyzed frame set and applying that time offset before sampling the
prepared motion paths. A validated analysis continues to drive preview/render
when Final Cut Pro plays proxy media; proxy media is rejected only for Host
Analysis input and for validating an unvalidated cache. When proxy playback uses
a loaded cache before original-media validation, the render path uses the active
range-matched cache identity even if Final Cut Pro has not yet returned the
hidden cache identity parameter. If a stale saved identity points at a different
range, the same render callback drops it and reloads a compatible saved cache
before giving up, then keeps the hidden preview revision, `Host Analysis Status`,
and split read-only info rows current so Final Cut Pro shows the stabilized proxy preview
and reports `Original Analysis - Proxy Preview`.
If Final Cut Pro reports a render/timeline range that differs from the saved
source analysis range, the render path accepts that active cache only after the
current source-frame fingerprint validates against the saved frame set. During
scaled/proxy playback, where that original-frame validation is not available, a
range-mismatched cache is used for preview only when its saved start matches the
current clip and the current render time is inside the saved analysis range.
When original-media validation has mapped a trimmed timeline render time back to
the analyzed source time, that offset is saved with the Host Analysis cache identity
so a separate proxy render instance can sample the same prepared motion path.
Proxy/scaled media is detected when the source pixel transform differs from original
`1.0x/1.0x` in either direction, so reduced-resolution proxy frames do not get treated as
ordinary original frames and reject a good saved cache.
If Final Cut Pro is set to proxy playback but the proxy media is missing, the
host supplies a Missing Proxy placeholder rather than the original footage. The
effect now reports `Source Media Unavailable - Check FCP Proxy`, keeps the saved
analysis cache intact, and suppresses debug overlay diagnostics over that
placeholder. Switch Viewer playback back to Original/Optimized or create proxy
media to see the stabilized source frame.

## Cache Behavior

Completed analysis is written inside the active Final Cut Pro library bundle, scoped to
the Event that owns the current project/media folder. If Final Cut Pro reports a library temp
folder instead of an Event folder, the runtime uses an unambiguous top-level Event resolver,
such as the single Event that already has Final Cut Pro `Analysis Files`. If multiple Events
have `Analysis Files`, the resolver compares the active Host Analysis range against Final Cut
Pro `Analysis Files/Stabilization` range folder names and only selects a unique match. The
resolver starts access to the host-provided media folder before inspecting the library bundle,
then verifies the selected Event by creating the `TokyoWalkingStabilizerHostAnalysis` cache root.
If `FxProjectAPI.mediaFolderURL()` reports that the library has no media folder because it
was saved without Collect Media, the resolver reads Final Cut Pro's active library bookmarks
from `FFActiveLibraries`, resolves each bookmark with security scope, requires that URL to grant
a security-scoped lease, and then applies the same Event selection rules. A bookmark that does
not grant a lease is rejected instead of being accessed through a hardcoded volume or fixture
path. If multiple libraries are active, existing Final Cut
Pro `Analysis Files/Stabilization` range names may disambiguate the Event only when the
active Host Analysis range matches exactly one Event across active libraries. If no range
match exists, the resolver may use Final Cut Pro's `FFSidebarModuleLibrary` media sidebar
selection only when the selection UUIDs match exactly one active library and the selected
Event UUID resolves through `CurrentVersion.flexolibrary` metadata to an existing top-level
Event folder. Stale import-target UUIDs are not used. Multiple active libraries with no
unique selected Event, unreadable
active-library state, or an unwritable Event cache root remain visible failures; ambiguous active libraries surface as
`Project Bundle Cache Unavailable - Ambiguous Active Libraries`, and the runtime does not write to a shared fallback. It logs the media folder
URL, `documentID`, active-library bookmark candidates when used, bundle root, Event
candidates, selected Event, and rejection reason with public `os_log` fields. It fails
visibly as `Project Bundle Cache Unavailable - Ambiguous Event` when the Event remains
ambiguous. The cache root lives
under that Event's `Analysis Files` directory so analysis files stay unique to the Event and
do not appear as top-level library content:

```text
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-index-v2.json
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/caches/
```

Older top-level bundle caches at `<active library>.fcpbundle/TokyoWalkingStabilizerHostAnalysis/`
and older internal bundle caches at
`<active library>.fcpbundle/__.fcpdata.apple.com/TokyoWalkingStabilizerHostAnalysis/` are moved into
the Event `Analysis Files` cache root when the effect configures the active Event cache.

If the runtime cannot resolve a writable Event cache root, the effect shows
`Project Bundle Cache Unavailable` instead of falling back to a shared user cache or a
library-wide cache. The FCP effect does not create an out-of-bundle fallback cache.
When a library is moved while Final Cut Pro is still open, the effect detects the unavailable
old Event cache root and reconnects the existing timeline effect to the matching standard
Event cache in the bundle location Final Cut Pro exposes. Reconnection requires one unique
saved cache identity and does not rerun analysis, reapply the effect, scan arbitrary disks, or
choose a duplicate cache identity.
Range-specific files under `caches/` include a readable clip label when available, analyzed
start/end, actual `sampleWidth`/`sampleHeight`, frame count, and representative frame
fingerprints in the filename.
`host-analysis-v2.json` is kept as the latest compatibility alias, not as the only retained
cache.

Cache files store prepared paths, frame timing, blur values, search-radius
edge-hit counts, warp values, confidence metadata, source-space ridge shake
paths, two-way far-field rigid shake X/Y/roll paths, far-field `5x9` mesh paths,
fps-derived dominant far-field shake windows up to one second, and fingerprints
instead of every frame's full luma sample. Schema 52 is the current write and
read format so render can use axis-specific far-field evidence plus coherent global
X/Y/roll correction while keeping the visible correction low-order enough to avoid
local mountain/cloud pulsing. Earlier
schemas are intentionally unsupported and must be regenerated by the Event
Analyzer.
Cache writing uses the prepared analysis frame set as the authoritative timeline,
so a reduced retained source-frame map does not prevent a completed prepared path
from being saved.
On 16 GB Apple Silicon and larger machines, the native analyzer keeps three GPU
frame slots in flight per hardware VideoToolbox reader lane. This improves decode
and Metal overlap without reducing sample scale, block density, fingerprints, or
motion-search quality. Lower-memory Apple Silicon machines keep the conservative
two-slot pipeline.

The installed plug-in bundle is signed with sandbox and security-scoped file
entitlements so the effect can inspect the Event-scoped cache root that Final Cut Pro exposes
to the FxPlug runtime. Debug builds use the same security-scoped path and do not embed
volume-specific or fixture-specific read-write exceptions.

Cache reuse is based on cache schema, exact analyzed source range, sample size, saved frame
fingerprints, and current source-frame validation, not the visible FxPlug runtime version.
Render-only version bumps should reuse compatible Host Analysis caches from the active
`.fcpbundle`.

Rejected cache candidates are visible in status/log output and remain on disk for the
local analyzer or older builds. Unsupported schema candidates show
`Cache Unsupported - Run Event Analyzer` instead of being silently ignored or deleted.
Supported-schema caches with incomplete prepared path arrays or too few frames for the saved
analysis range show `Cache Incomplete - Run Event Analyzer` so incomplete analysis is not
silently reused.
Those stale unusable states do not block later preview/render consumers from rechecking the
persistent cache signature and loading a newly written compatible cache.

The active runtime uses bundle-local persistent cache files as the cross-process reuse path.
Preview/render instances with no prepared analysis watch for cache file changes and reload
validated candidates on demand.

## Diagnostics

`Debug Overlay` has one fixed 19-row contract:
`X OFFSET`, `Y OFFSET`, `ROLL`, `CROP`, `TURN`, `MACRO JITTER`, `MICRO JITTER`, `FAR WARP`,
`SMOOTHING`, `TRACKING`, `WALKING`, `SHARPNESS`, `RESIDUAL`, `SEARCH HEADROOM`,
`TURN CONFIDENCE`, `MACRO CONFIDENCE`, `MICRO CONFIDENCE`, `WARP CONFIDENCE`,
then the readable `ORIGINAL <version>`/`PROXY <version>` runtime/source row. All confidence and
quality bars are grouped immediately above the version row. Labels use readable English
diagnostic names and are not translated in the preview.

The overlay bars are normalized magnitudes or quality signals, not signed directions:

- `X OFFSET`: final horizontal automatic correction after TURN separation, Camera Rigid
  limiting, and Master Strength.
- `Y OFFSET`: final vertical automatic correction after Camera Rigid limiting and Master Strength.
- `ROLL`: final automatic roll/rotation correction.
- `CROP`: Auto Crop scale actually sent to the renderer; zero when Remove Black Edges is off.
- `TURN`: Auto Crop viewport-position activity actually sent to the renderer; zero when
  Remove Black Edges is off.
- `MACRO JITTER`: correction activity from the fixed internal macro-jitter window.
- `MICRO JITTER`: short-period activity combining micro, trajectory continuity, and final-limited
  Camera Rigid X/Y/roll correction.
- `FAR WARP`: final shear plus combined perspective/yaw-pitch values sent to Metal.
- `SMOOTHING`: Master-Strength-adjusted render-time temporal smoothing delta.
- `TRACKING`: current frame tracking quality after motion evidence, residual, blur, and block coverage.
- `WALKING`: count-aware walking-band tracking quality used by Micro Jitter and Macro Jitter.
- `SHARPNESS`: frame sharpness/clarity quality; higher means less blur.
- `RESIDUAL`: residual quality; higher means lower block-matching residual/error.
- `SEARCH HEADROOM`: search-radius headroom quality; higher means fewer searches hit the radius edge.
- `TURN CONFIDENCE`: effective Turn Smoothing confidence.
- `MACRO CONFIDENCE`: Macro Jitter confidence.
- `MICRO CONFIDENCE`: Micro Jitter confidence after its safety evidence gates.
- `WARP CONFIDENCE`: effective Far-field Warp confidence after tracking and search-radius safety gates.

`TRACKING`, `WALKING`, `SHARPNESS`, `RESIDUAL`, and `SEARCH HEADROOM` are aligned as quality signals: high is good,
low is bad. Confidence rows remain analysis evidence even when Master Strength is zero.
Unavailable `RESIDUAL` or `SEARCH HEADROOM` evidence is shown as zero and its unavailable reason is logged;
the overlay does not invent a fallback value.

`Host Analysis Status` also reports:

- The current FxPlug runtime version.
- `track q` and `walk q`.
- `micro q` and effective Micro Jitter X/Y/R strength.
- `macro q` and effective Macro Jitter X/Y/R strength.
- `turn q`.
- `warp q`.
- Tracking and motion confidence.
- Blur and residual error.
- Search-radius edge-hit counts.
- Current warp shape values.

TURN, MACRO, MICRO, and WARP all apply the same unbiased finite-value check and
linear `0...1` clamp after their band-specific safety evidence is calculated. Strength
values above `1.0` may still request more correction, but no band has a hidden confidence
floor, rescue lift, display-only maximum, or band-specific response curve.

## Feedback CLI

Use the local feedback CLI when reviewing notes like `at 5 sec there is a
notable unremoved shake` against a saved Host Analysis cache:

```sh
fxplug/TokyoWalkingStabilizer/scripts/stabilizer_feedback.sh \
  --cache "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json" \
  --time 5.0 \
  --note "notable unremoved shake"
```

`--time` is clip-relative: `0.0` is the start of the Host Analysis range saved
in the cache. With `--time`, the CLI reports the highest-score frame inside the
requested `--window` and prints the selected clip time separately from the
requested note time. For bundle-local caches, pass
`--cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"` or
`--cache /path/to/host-analysis-v2.json`. Use `--json` for machine-readable output,
`--turn-strength` to match `Turn Smoothing Strength` when it is not `12.0`, and
`--output-size 1920x1080` when you want pixel estimates scaled to a target preview size.

Use `--list-caches --cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"`
to list the latest bundle cache and range-specific cache files. It reports each file as
`READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE` without repairing or deleting
anything.

The report prints `MIJIT`, `MAJIT`, `WARP`, and `TURN` in render-stage order
bands using the saved prepared paths, tracking confidence, residuals, blur,
block coverage, and search-radius edge-hit counts, while the summary line names
the highest remaining band. The band split mirrors the render path: `MIJIT` is
measured first against the outer-frame baseline, then `MAJIT` and `TURN`
are measured from the micro-cleaned path. `WARP`
uses the same local baseline/gate inputs that are then short-smoothed in render,
and the report includes strict tracking, walking-band tracking, MIJIT and MAJIT
per-axis confidence, residual, blur, block
coverage, edge quality, stable WARP tracking support, and WARP tracking/edge
gate values so over- or under-gating is visible. If a cache has mismatched
frame/path array counts, the CLI fails explicitly and asks for a new Host
Analysis run with the current FxPlug instead of trying to repair the data.

## Build

Build the wrapper app and embedded FxPlug:

```sh
xcodebuild \
  -project fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj \
  -scheme TokyoWalkingStabilizer \
  -configuration Debug \
  -derivedDataPath /tmp/TokyoWalkingStabilizerDerived \
  build
```

The shared scheme installs each successful Debug build to:

```text
/Applications/TokyoWalkingStabilizer.app
```

It also installs the Motion Template under the user's Movies Motion Templates
folder and registers the embedded FxPlug with PluginKit. Debug installs remove
stale `Tokyo Walking Stabilizer copy...` Motion Template folders from the
`Emdash Studios` group so Finder-created duplicates do not appear as extra
effects in Final Cut Pro.

The shared scheme and install script fail if Final Cut Pro is running. Quit
Final Cut Pro before rebuilding or rerunning the install script; building or
replacing a loaded FxPlug can leave Final Cut Pro holding a stale PlugInKit
object and cause `P1000307` helper communication errors.

Verify registration:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.TokyoWalkingStabilizer.Plugin
codesign --verify --deep --strict /Applications/TokyoWalkingStabilizer.app
```

Open Final Cut Pro after the build/install step completes.
