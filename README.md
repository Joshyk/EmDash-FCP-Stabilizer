# Final Cut Pro Stabilizer

Native FxPlug 4 effect for Final Cut Pro and Motion, tuned for walking footage
shot on a gimbal.

This repo is FxPlug-only. It does not contain or support a CommandPost runtime,
standalone estimator, cache generator, or Transform-keyframe writer.

## What It Does

`Tokyo Walking Stabilizer` renders the source clip through Metal and applies
automatic stabilization inside the FxPlug render path. It avoids Final Cut Pro's
built-in Stabilization effect because that effect applies its own internal crop
and scale.

The effect is designed for outdoor walking shots where the camera is already on
a gimbal but still has step shock, short wobble, segmented turns, and distant
ridge-line shake.

The main correction stages are:

- `Footstep Jitter`: frame-local X/Y/roll impulse removal for landing shock.
- `Stride Wobble`: medium-period X/Y/roll cleanup after footstep shock.
- `Far-field Warp Strength`: small-clamp deskew, yaw/pitch proxy, and
  perspective trim for distant background shake.
- `Turn Smoothing`: X-only smoothing for stop-and-go walking turns.

The effect keeps render scale fixed at `1.0`. Edge fill is controlled separately
by `Edge Display Mode`, which switches between stretched source edges and black
outside-source pixels.

## Basic Workflow

1. Apply `Tokyo Walking Stabilizer` to a clip.
2. Keep the default `100%` `Sample Size` for full source detail, or choose a
   smaller sample before starting analysis when you want a quicker debug pass.
3. Click `Start Host Analysis`.
4. Wait for `Host Analysis Status` to show `Ready (... frames)`.
5. Tune the strength controls while watching the preview.

`Start Host Analysis` is the only path that asks Final Cut Pro to analyze the
clip. Preview and render callbacks only read completed analysis or a validated
persistent cache; they do not start analysis on their own.

## Optional Final Cut Pro Shortcuts

The shared workspace script `../scripts/fcp_stabilizer_shortcuts.applescript`
provides UI-scripted helper actions for Keyboard Maestro, Automator Quick
Actions, or manual `osascript` runs:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript apply
osascript ../scripts/fcp_stabilizer_shortcuts.applescript start-analysis
osascript ../scripts/fcp_stabilizer_shortcuts.applescript toggle-debug-overlay
osascript ../scripts/fcp_stabilizer_shortcuts.applescript focus-inspector
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-selected-project
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-project "stab test - gh6"
osascript ../scripts/fcp_stabilizer_shortcuts.applescript select-playhead-clip
```

These actions use Final Cut Pro Accessibility UI scripting. Grant Accessibility
permission to the app that runs the script. `start-analysis` and
`toggle-debug-overlay` fail visibly if the selected clip does not have
`Tokyo Walking Stabilizer` applied or the Inspector control is not accessible.
`open-project PROJECT_NAME` opens a named Browser project, `open-selected-project`
opens the selected Browser project, and `select-playhead-clip` reselects the
timeline clip under the playhead before analysis. Project open commands select
the Browser item and run `Clip > Open Clip`, which has been more reliable than
repeated AppleScript clicks in Final Cut Pro.

## Inspector Controls

`Sample Size` is read once when analysis starts. It is always derived from the
original clip dimensions, with `100%`, `75%`, `50%`, `25%`, and `10%` options.
The default is `100%`; choose a smaller value only when you want a faster debug pass. Long clips keep
the requested percentage instead of silently lowering it.

`Overall Strength` controls the full automatic transform. Setting it to `0`
bypasses prepared motion-path sampling, crop-safety motion, and debug overlay
output, producing an identity transform.

`Footstep Jitter` strengths are direct removal amounts for frame-local X, Y, and
roll impulses. They run up to `4.0`; values above `1.0` can compensate when
tracking confidence makes the correction too weak. The applied correction still
clamps at full detected-impulse removal so it does not add inverse shake. The
rotation default is `0.2` to keep walking footage from losing a stable horizon. The
baseline uses seconds, not frame counts: it skips the center `0.10` second shock
region and predicts from outer samples up to `1.0` second away. Confidence is
based on current tracking evidence, local baseline support, and the center
frame's impulse relative to surrounding footstep noise. Moderate landing impulses now reach
useful confidence a little sooner, while zero evidence and noisy unsupported frames still
produce zero correction. The surrounding-noise floor is capped below the full-response point
so repeated walking motion does not bury a real center-frame landing shock.
FJIT and SWOB use a walking-band tracking gate that slightly eases block coverage only
when enough motion blocks were accepted; WARP and TURN keep the stricter tracking gate to
avoid swimming or false turn smoothing.

`Stride Wobble` removes step follow-through shake using a fixed internal
`2.0` second render-time window. The Inspector exposes only X, Y, and rotation
strengths. It is measured from the footstep-cleaned path, then longer Turn
Smoothing is measured from the stride-smoothed path so the same motion is not
removed twice. It does not use the raw or jerk-limited
broad path as its band input. Its residual gate uses robust window percentiles
instead of letting a single bad frame suppress the whole band. Medium stride
bands reach full confidence earlier than the broad UI scale so real walking
follow-through is corrected by the stride stage; the Y default is `0.70`.
The rotation default is `0.2` to protect the horizon.

`Turn Smoothing Strength` smooths segmented horizontal walking turns into a
more continuous S-curve intent. It applies only to X translation, does not change
Y or roll, and is soft-limited to a small output-edge budget during render.
`Turn Detection Window` comes from the Inspector UI value. Its UI minimum is the
fixed `2.0` second Stride Wobble window, so TURN cannot run shorter than SWOB.
TURN confidence now requires both tracking evidence and a real X turn band, so
low-evidence frames do not get a hidden minimum turn correction.

`Far-field Warp Strength` bundles small-clamp shear, yaw/pitch proxy, and
perspective trim for distant background motion. It is applied from the current
frame's local deviation from its own `1.0` second outer-frame linear baseline,
so long-term drift does not become a fixed deskew. The default is `1.0`, and the
maximum is `4.0`. The render path gates warp with walking-footage tracking quality and
search-radius headroom. The tracking gate starts early enough for moderate
25% Host Analysis evidence but reaches full response more gradually, uses short
local tracking support to reduce single-frame gate flicker, then drops tiny warp
deltas through a deadband so useful ridge-line correction is less likely to
disappear while high-side gate jumps and low-confidence warp evidence are
suppressed instead of producing a wavy image.

`Debug Overlay` shows labeled top-left diagnostics for the active correction
bands and tracking state. It also includes a compact runtime/source row for the
active render runtime and current source mode: `R360` means FxPlug `0.3.60`
is rendering original/optimized frames, and `P360` means proxy playback is using
the saved Host Analysis path. It does not control black outside-source pixels;
`Edge Display Mode` controls that separately.
The overlay scales from the current render output with a lower proxy minimum so
Final Cut Pro proxy playback keeps roughly the same viewer footprint as original
media, while staying larger than the old compact panel.

`Host Analysis Status` appends the current FxPlug version when Final Cut Pro
accepts status parameter updates. For existing timeline instances that keep
stale saved Inspector strings, `Debug Overlay` is the live render-runtime
indicator. `Accepted Sample`, `Clip Range`, `Analysis Sample`, and `Queue` split
the accepted `Sample Size`, current clip start/end time, actual analysis sample
size, and serial queue position into separate read-only Inspector rows. `Queue`
uses `#N of M`; repeated Start presses on the same effect instance keep only that
instance's latest pending request, while other queued clips remain queued. Older
saved timeline instances may still display stale saved info strings until the
effect is reapplied.
During a real Host Analysis pass the status advances as `Analyzing Host Frames
(N)`. If Final Cut Pro restores an in-progress analysis state while a compatible
saved cache exists, the plug-in prefers the saved cache and keeps the shared
Ready/cache status visible. When an analyzer callback is still the active state,
`Host Analysis Status` and the split read-only info rows are published from that same
in-progress analysis store, so the Inspector does not combine `Analyzing Host
Frames (N)` with stale cache metadata from another clip.

## Host Analysis

Host Analysis uses Final Cut Pro's FxPlug analysis infrastructure to request GPU
analysis frames from the host. The plug-in then uses Metal compute to downsample
luma and run frame-to-frame block matching. If Metal analysis resources are not
available, the Host Analysis path fails visibly in status/log output instead of
falling back to CPU analysis.

Each active Host Analysis run owns its own in-progress session store. Different
clips can be requested while another clip is running, and clips whose selected
`Sample Size` resolves to different actual pixel dimensions do not share the
same streaming builder. The process-wide callback registry resolves analyzer
frames by active session range, owner, source frame, and sample size; if Final
Cut Pro delivers a callback that matches multiple active sessions, the plug-in
fails that callback visibly instead of appending the frame to an arbitrary clip.

When `Start Host Analysis` is pressed on more than one clip, only one clip is
handed to Final Cut Pro at a time. Additional presses enter the plug-in's serial
`Queued Host Analysis` state while another Stabilizer Host Analysis run is active
or reserved. Pressing `Start Host Analysis` again on the same queued effect instance
replaces that instance's older queued request, but requests for other clips remain in
queue order. A completed analysis from an earlier clip does not satisfy a later
queued clip.
Analysis callback instances clear process-wide analysis bookkeeping, because
Final Cut Pro may deliver setup/analyze/cleanup to a different FxPlug instance
than the Inspector button instance that requested the run. The Inspector start
path does not use plug-in-local active markers as the blocking authority; it asks
Final Cut Pro's current analysis state and queues only when the host reports a
busy/requested state. Final Cut Pro's own analysis state remains the authority
before any queued request can start. The queue stores the `FxAnalysisAPI` obtained
when Start was pressed, so retry passes do not drop the request just because the
API cannot be reacquired from a later callback context.
When Final Cut Pro cannot provide a writable Event cache root, completed
memory-only analyses are retained by analyzed timeline range plus sample/fingerprint
identity in the plug-in process, so a later queued clip does not discard stabilization
for an earlier clip or collide with another clip that has the same source-time range
in the same viewer session.
Preview/render and plug-in state callbacks check the persistent cache signature,
so a queued clip that completes in a different FxPlug process can replace an
older prepared path and update the hidden render revision without requiring
another manual start. The hidden render revision uses a process-independent
small numeric token rather than the local analysis counter, so separate
analyzer/render processes do not publish the same invalidation value for
different clips. The plug-in skips setting that hidden parameter when Final Cut
Pro already has the same value, avoiding repeated preview invalidation during
effect load.
Viewer-side render instances also monitor the shared persistent cache location.
If an analyzer instance finishes in another FxPlug process, the viewer-side
instance loads the completed cache and publishes the hidden render revision so
stale preview frames redraw from the prepared motion path.
If Final Cut Pro rejects a hidden revision update, the plug-in does not mark it
as published, so a later monitor tick or callback can retry.
If Final Cut Pro still reports an older hidden revision value, the runtime also
republishes the current token instead of assuming the previous publish reached
the host.
Analyzer completion and cache-monitor ticks publish status/info/render revision
from the FxPlug main queue, which keeps Final Cut Pro's preview invalidation in
the same path as ordinary parameter updates.

The analysis path:

- Streams frame-to-frame motion through Metal.
- Keeps only the previous luma buffer needed for the next motion search.
- Does not write per-frame `.luma` scratch files.
- Prioritizes upper-frame far-field blocks for walking landscape footage.
- Rejects outlier blocks before building the frame path.
- Exposes low tracking confidence instead of hiding it behind coarse fallback
  motion.

Prepared paths are post-processed with a zero-phase jerk limiter before caching.
The limiter clamps isolated acceleration spikes in X/Y/roll while preserving
path endpoints and total analyzed turn amount. Raw X/Y/roll impulse paths are
stored separately so Footstep Jitter can still correct frame-level shake at
render time.

Render-time smoothing samples neighboring render times symmetrically across a
`1.20` second zero-phase window and blends the automatic transform. At clip
edges it averages only in-range neighboring samples instead of duplicating the
first or last analysis frame. It smooths Stride Wobble and Turn Smoothing bands
without averaging away the current frame's Footstep Jitter
impulse. Far-field Warp uses a separate short `0.36` second in-range smoothing
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

Completed Host Analysis is written inside the active Final Cut Pro library bundle, scoped to
the Event that owns the current project/media folder. If Final Cut Pro reports a library temp
folder instead of an Event folder, the runtime uses an unambiguous top-level Event resolver,
such as the single Event that already has Final Cut Pro `Analysis Files`. If multiple Events
have `Analysis Files`, the resolver compares the active Host Analysis range against Final Cut
Pro `Analysis Files/Stabilization` range folder names and only selects a unique match. The
resolver starts access to the host-provided media folder before inspecting the library bundle,
then verifies the selected Event by creating the `TokyoWalkingStabilizerHostAnalysis` cache root.
If `FxProjectAPI.mediaFolderURL()` reports that the library has no media folder because it
was saved without Collect Media, the resolver reads Final Cut Pro's active library bookmarks
from `FFActiveLibraries`, tries security-scoped bookmark resolution first, logs when regular
resolution is used, starts security-scoped access when a resolved URL grants it, and then
applies the same Event selection rules. If multiple libraries are active, existing Final Cut
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
library-wide cache. During a live Final Cut Pro Host Analysis callback, the analyzer can
still finish the current session in memory and show
`Ready Memory Only - Project Bundle Cache Unavailable`; that result is usable for the current
viewer/render session but is not persisted to any shared or out-of-bundle location. If the
Event cache root becomes available later, the completed in-memory analysis is saved into that
Event cache and the Inspector returns to ordinary `Ready (...)` status.
Range-specific files under `caches/` include a readable clip label when available, analyzed
start/end, actual `sampleWidth`/`sampleHeight`, frame count, and representative frame
fingerprints in the filename.
`host-analysis-v2.json` is kept as the latest compatibility alias, not as the only retained
cache.

Cache files store prepared paths, frame timing, blur values, search-radius
edge-hit counts, warp values, confidence metadata, and fingerprints instead of
every frame's full luma sample. Cache writing uses the prepared analysis frame
set as the authoritative timeline, so a reduced retained source-frame map does
not prevent a completed prepared path from being saved.

`Start Host Analysis` first tries to reload a saved cache. It starts a new host
analysis only when no compatible saved cache can be loaded. If the button
callback cannot see `FxProjectAPI`, it still asks Final Cut Pro to start Host
Analysis and lets the analyzer `setupAnalysis` callback resolve the Event cache
root through either the host media folder or Final Cut Pro's active library bookmarks and
the same Event resolver. If setup
still cannot resolve a writable Event cache root, the effect
finishes the active analyzer pass in memory only and shows `Ready Memory Only -
Project Bundle Cache Unavailable` after completion until a later callback can resolve the
Event cache root and save the completed result. It must not delete saved cache files.
The installed plug-in bundle is signed with sandbox, security-scoped file
entitlements, and a read-only home-relative exception for Final Cut Pro's preference plist
so the Host Analysis runtime can open the `FxProjectAPI.mediaFolderURL()` security-scoped
URL when Final Cut Pro provides one, or read the active library bookmark when Final Cut Pro
reports no media folder. Active library bookmarks are resolved with security scope first,
then resolved as regular bookmarks with visible logs when Final Cut Pro stored a regular
bookmark; access is retained only when the resolved URL grants a security-scoped lease.
The debug-signed bundle also carries explicit read-write entitlements for the shared
local test fixture libraries so the no-media-folder active-library resolver can inspect
those fixtures and persist Event-scoped caches during Codex-driven FCP tests.
For this local editing setup it also carries a read-write exception for `/Volumes/WDBLUE1TB/`
so regular active-library bookmarks for external libraries can still be inspected and saved
inside their Event-scoped `.fcpbundle` cache roots.
The in-progress Host Analysis session registry is process-wide and contains
per-session stores, so setup, frame analysis, and cleanup callbacks can arrive
through different FxPlug instances without losing or mixing the active analysis
session.

Cache reuse is based on cache schema, exact analyzed source range, sample size, saved frame
fingerprints, and current source-frame validation, not the visible FxPlug runtime version.
Render-only version bumps should reuse compatible Host Analysis caches from the active
`.fcpbundle`.

Rejected cache candidates are visible in status/log output and are remembered by
file identity inside the active runtime, so the same invalid candidate is not
loaded again on the next start. Rejected files remain on disk. `Clear Host
Analysis Cache` is the explicit delete path and shows `Cache Cleared`.

Unsupported schema candidates show `Cache Unsupported - Run Host Analysis`
instead of being silently ignored or deleted. This keeps stale caches available
for older builds while the current effect asks for a new analysis. Supported-schema
caches with incomplete prepared path arrays or too few frames for the saved analysis range
show `Cache Incomplete - Run Host Analysis` so incomplete analysis is not silently reused.
Those stale unusable states do not block later preview/render consumers from rechecking the
persistent cache signature and loading a newly written compatible cache.

The active runtime uses a process-wide per-clip store for in-progress Host Analysis and a
process-wide shared render/cache store after analysis completes. Bundle-local persistent cache files are
the cross-process reuse path. Preview/render instances with no prepared analysis watch for
cache file changes and reload validated candidates on demand.

## Diagnostics

`Debug Overlay` reports final `X`/`Y`/`ROLL`, `FJIT`, `SWOB`, `WARP`, `TURN`,
live `F Q`/`S Q`/`W Q`/`T Q` confidence, `SMTH`, `TRK`, `SHRP`, `RES`, and
search-radius `HIT`, `WLK`, and compact runtime/source bars. Labels use raw English control/diagnostic abbreviations;
do not translate them in the preview.

The overlay bars are normalized magnitudes or quality signals, not signed directions:

- `X`: final horizontal automatic correction.
- `Y`: final vertical automatic correction.
- `ROLL`: final automatic roll/rotation correction.
- `FJIT`: Footstep Jitter correction activity from the fixed second-based impulse range.
- `SWOB`: Stride Wobble correction activity from the fixed internal stride-wobble window.
- `WARP`: Far-field Warp correction activity from shear, yaw/pitch proxy, and perspective trim.
- `TURN`: X-only Turn Smoothing correction for stop-and-go pan motion.
- `SMTH`: render-time temporal smoothing delta.
- `F Q`: Footstep Jitter confidence.
- `S Q`: Stride Wobble confidence.
- `W Q`: applied Far-field Warp confidence after tracking and search-radius safety gates.
- `T Q`: Turn Smoothing confidence.
- `TRK`: current frame tracking quality after motion evidence, residual, blur, and block coverage.
- `SHRP`: frame sharpness/clarity quality; higher means less blur.
- `RES`: residual quality; higher means lower block-matching residual/error.
- `HIT`: search-radius headroom quality; higher means fewer searches hit the radius edge.
- `WLK`: count-aware walking-band tracking quality used by FJIT and SWOB.

`TRK`, `SHRP`, `RES`, and `HIT` are all aligned as quality signals: high is good, low is bad.

`Host Analysis Status` also reports:

- The current FxPlug runtime version.
- `track q` and `walk q`.
- `footstep q` and effective Footstep Jitter X/Y/R strength.
- `stride q` and effective Stride Wobble X/Y/R strength.
- `turn q`.
- `warp q`.
- Tracking and motion confidence.
- Blur and residual error.
- Search-radius edge-hit counts.
- Current warp shape values.

Values above `1.0` on Footstep and Stride controls boost low-confidence
corrections with a curved confidence response. Those walking-band controls use a
more assertive medium-confidence response than TURN and WARP, but still have no
hidden minimum confidence floor: zero confidence produces zero correction.

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
`--turn-window` to match a non-default Inspector `Turn Detection Window`, and
`--output-size 1920x1080` when you want pixel estimates scaled to a target preview size.

Use `--list-caches --cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"`
to list the latest bundle cache and range-specific cache files. It reports each file as
`READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE` without repairing or deleting
anything.

The report prints `FJIT`, `SWOB`, `WARP`, and `TURN` in render-stage order
bands using the saved prepared paths, tracking confidence, residuals, blur,
block coverage, and search-radius edge-hit counts, while the summary line names
the highest remaining band. The band split mirrors the render path: `FJIT` is
measured first against the outer-frame baseline, then `SWOB` and `TURN`
are measured from the footstep-cleaned path. `WARP`
uses the same local baseline/gate inputs that are then short-smoothed in render,
and the report includes strict tracking, walking-band tracking, FJIT and SWOB
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
