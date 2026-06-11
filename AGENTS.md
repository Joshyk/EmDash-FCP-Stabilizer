# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory hosts the native `Stabilizer Transform` FxPlug project for Final Cut Pro and
Motion. The project is FxPlug-only. Do not add non-FxPlug runtime files, standalone
estimators, timeline automation actions, legacy cache models, or app reload workflows back
into this repo.

The effect intentionally avoids Final Cut Pro's built-in `Stabilization`, because that
effect applies its own internal crop/scale. The native effect renders a transformed source
texture with Metal and applies automatic walking-gimbal stabilization inside the FxPlug
render path.

## Host Analysis And Cache

The FxPlug uses Final Cut Pro's FxPlug `Host Analysis` infrastructure to request GPU
analysis frames from the host. The native analysis path must use Metal compute inside the
plug-in runtime for luma downsampling and frame-to-frame motion search. Do not add a CPU
analysis fallback; if Metal analysis resources are unavailable, fail the Host Analysis path
visibly in logs/status.

Completed Host Analysis frame sets should be persisted inside the active Final Cut Pro
library bundle, scoped to the current Event resolved from `FxProjectAPI.mediaFolderURL()`
when the host-provided folder is inside an Event. If the host-provided folder is a library
temp folder instead of an Event folder, the runtime may use an unambiguous top-level Event
resolver, such as the single writable Event that already has Final Cut Pro `Analysis Files`;
ambiguous Event candidates must fail visibly instead of writing to the wrong Event. Store the
cache under the Event's `Analysis Files/StabilizerFxPlugHostAnalysis/` directory so analysis
files are unique to that Event and do not appear as top-level library content. The runtime
may move older top-level `StabilizerFxPlugHostAnalysis/`, media-folder-local
`StabilizerFxPlugHostAnalysis/`, or `__.fcpdata.apple.com/StabilizerFxPlugHostAnalysis/`
caches into the Event `Analysis Files` cache root, but it must not silently fall back to an
out-of-bundle or library-wide shared cache. The Event cache contains
`host-analysis-v2.json`, `host-analysis-index-v2.json`, `host-analysis-render-offset-v2.json`,
and range-indexed files under `caches/`. If the runtime cannot resolve a writable Event cache
root, fail visibly with `Project Bundle Cache Unavailable` instead of falling back to a shared
Application Support cache or a library-wide cache. Cache candidates must be validated
against the current source frame before reuse. Rejected candidates should be visible in
logs/status and should not be deleted just because they do not match the current clip.
`Start Host Analysis` should first reload and use a saved persistent cache when one exists;
only start a new host analysis when no saved cache can be loaded. It must not delete saved
cache files. If the loaded cache is rejected for the current clip, the next start should skip
that rejected cache and request a new analysis. `Clear Host Analysis Cache` is the explicit
cache-clear path and should show `Cache Cleared`.
If Final Cut Pro restores or reports an in-progress Host Analysis while a compatible saved
cache is already present, the render/cache consumer should still reload and prefer the saved
cache; transient analyzer callback status must not mask the shared ready cache in the
Inspector. When analyzer callback status is the only active state, `Host Analysis Status`
and `Stabilizer Info` should both be published from that same in-progress analysis store;
do not combine `Analyzing Host Frames (N)` with stale shared-cache metadata from a previous
clip. Stale `Cache Unsupported` or `Cache Incomplete` status must not stop later
preview/render consumers from noticing a changed persistent cache signature and loading a
new compatible saved cache.
Persistent cache compatibility is based on cache schema, exact analyzed source range, sample
size, frame fingerprints, and current source-frame validation, not the visible FxPlug runtime
version. Render-only version bumps should reuse saved Host Analysis cache candidates from the
active `.fcpbundle`. Unsupported schema candidates should surface `Cache Unsupported - Run
Host Analysis` in the Inspector, remain on disk, and require an explicit new Host Analysis
run instead of being silently ignored or deleted. Supported-schema
caches with incomplete prepared path arrays or incomplete frame coverage for the saved
analysis range should surface `Cache Incomplete - Run Host Analysis`, remain on disk, and
require a new Host Analysis run.

Host Analysis should read user-controlled `Sample Size` once when analysis starts. The
Inspector default should be `10%` so quick Debug Overlay tuning can start without a full
source-size pass, while still offering `100%`, `75%`, `50%`, `25%`, and `10%` options. The
sample image must always be derived from the original clip dimensions using the selected
percentage option. Long clips should keep that requested percentage. In-progress analysis
should stream frame-to-frame motion in memory and keep only the previous luma buffer needed
for the next Metal motion search; do not write per-frame `.luma` scratch files.
Persistent cache files should store prepared paths, frame timing, blur values, and
fingerprints instead of every frame's full luma sample.
Cache candidates should be sample-size-scoped. Do not collapse different `Sample Size`
outputs into one in-progress builder or one retained cache bucket; the cache index should
retain candidates independently per actual `sampleWidth`/`sampleHeight`.
Cache persistence should treat the prepared analysis frame set as authoritative. The
retained source-frame map may be reduced after Metal preparation and must not prevent a
completed prepared path from being saved.
The feedback CLI under `fxplug/StabilizerFxPlug/scripts/` reads saved Host Analysis cache
files for diagnostics only. It must not become a second stabilization runtime or silently
repair malformed cache data; mismatched frame/path arrays should fail visibly and require a
new Host Analysis run. Its cache inventory mode should list saved cache readiness without
repairing, deleting, or promoting cache files. Feedback band estimates should mirror the
render path's order:
measure Footstep Jitter against the outer-frame baseline first, then compute Stride Wobble,
Walking Bob, and Turn diagnostics from the footstep-cleaned path. Walking Bob diagnostics
should expose tracking evidence and symmetric window support so edge-window gating is visible.
The feedback report should print bands in Debug Overlay/render order (`FJIT`, `SWOB`, `BOB`,
`WARP`, `TURN`) and choose the top remaining band separately. Its `--turn-window` option should
match the Inspector `Turn Detection Window` when that UI value is not the default `6.0`.
Fine jitter analysis should use Metal block matching across multiple source-frame regions,
reject outlier blocks, and expose low block-confidence states in status/debug output instead
of silently falling back to a coarse global shift. Walking landscape analysis should
prioritize upper-frame far-field blocks so distant mountains/background motion is not
dominated by close grass, water, or road parallax. Motion-path algorithm changes that alter
prepared analysis output should bump the Host Analysis cache schema so stale caches are not
reused.

## Diagnostics

Debug/status diagnostics should expose tracking confidence, blur/sharpness, residual error,
raw Footstep Jitter impulse, and search-radius edge-hit counts so fine-shake causes are
visible while tuning walking footage. Debug Overlay correction rows should keep walking
components in order before turn correction: `FJIT`, `SWOB`, `BOB`, `WARP`, then `TURN`;
confidence rows should match as `F Q`, `S Q`, `B Q`, `W Q`, `T Q`. `TRK`, `SHRP`,
`RES`, and `HIT` should all be quality bars where higher means better tracking evidence
and lower means weaker evidence. `WLK` should show the walking-band tracking gate used by
Footstep Jitter, Stride Wobble, and Walking Bob. Debug Overlay should also expose a compact
active runtime/source row so stale saved Inspector strings do not hide which binary is rendering:
`R###` means an original/optimized render frame is using that FxPlug runtime version, while
`P###` means a proxy render frame is using the same saved Host Analysis path.
The overlay panel should scale proportionally to the current render output so Final Cut Pro
original/proxy playback presents one readable viewer footprint; high-resolution original
frames must not make the bars tiny, and proxy output must not make them balloon over the
preview.

## Playback And Render

Host Analysis playback must render from prepared motion paths for the active FxPlug runtime.
`Start Host Analysis` is the only path that should call `startForwardAnalysis`; render and
preview callbacks must not auto-start Host Analysis. If Final Cut Pro reports that another
Host Analysis is already requested or running, queue the requested effect instance for
serial analysis and surface `Queued Host Analysis` in the Inspector instead of failing
silently. In-progress Host Analysis state must be per clip/session so requested clips,
including clips with different actual sample sizes, never share a streaming builder. The
active runtime uses a process-wide shared Host Analysis render/cache store after completion
because Final Cut Pro may call analyzer and preview/render through different FxPlug
instances. Persistent cache files are the cross-process reuse path after source-frame
validation. Completed analysis should be written to the active `.fcpbundle` project cache
directory, not to a shared user Application Support cache or only to the current extension
container. When an analyzer instance saves a completed cache,
render/preview instances and plug-in state callbacks should notice cache file changes, reload
persistent cache candidates on demand, and update the hidden render revision with a
process-independent small numeric token even when they already hold an older prepared
analysis; this keeps the stabilized preview visible after serial queued analysis and when
analyzer and render use different FxPlug processes. Do not use per-process revision
counters as the hidden render invalidation value because analyzer and render processes can
generate the same counter value for different completed clips. Do not repeatedly set the
hidden render revision when Final Cut Pro already holds the same value, because that can keep
the effect in a loading/invalidation loop. Render/preview instances should also monitor the
shared persistent cache location and publish the hidden render revision when a compatible
completed cache appears, because analyzer callbacks may complete in a different FxPlug
instance or process than the stale viewer preview. A failed hidden parameter update should
not be recorded as published; a later valid callback or monitor tick should retry.
Analyzer completion and persistent-cache monitor ticks should dispatch the status/info/render
revision publication onto the FxPlug main queue before calling `FxParameterSettingAPI`, so
Final Cut Pro treats the hidden revision as a real preview invalidation.
Fingerprint mismatches must reject a
candidate instead of accepting a different clip by time proximity alone. If Final Cut Pro keeps
reporting a busy state when the serial queue tries to drain, keep the request queued visibly
and retry later. A queued start request must remain a pending request for that effect
instance; do not let a completed shared render/cache store from another clip satisfy or
skip the queued clip's own Host Analysis start. Because Final Cut Pro can call analysis
setup/analyze/cleanup on a different FxPlug instance than the Inspector button instance,
analysis completion/failure should clear process-wide analysis bookkeeping before queue
drain. Do not use plug-in-local active markers as the authority for blocking another
Inspector `Start Host Analysis` action; the start path should ask Final Cut Pro's
`analysisStateForEffect()` and queue only when the host reports a busy/requested state.
Queue drain should not depend on the FxPlug XPC main queue pumping while Final Cut Pro is
busy. Do not re-run full block matching across
the analyzed frame set on every render frame. Keep `Host Analysis
Status` visible in the Inspector, update it to `Ready (... frames)` after completed
analysis, update `Analyzing Host Frames (N)` during real frame analysis, and include the
active FxPlug version there when Final Cut Pro accepts status parameter updates. Debug
Overlay should remain the live render-runtime indicator because
older saved Inspector strings can remain stale on existing timeline instances.
Render playback must tolerate trimmed clips whose render time differs from Host
Analysis frame time by matching the current render frame fingerprint back to the analyzed
frame set and applying that time offset before sampling the prepared motion paths. Once an
analysis is validated, render playback should keep using the prepared motion path even when
Final Cut Pro is playing proxy media; proxy media is rejected only for Host Analysis input
and for validating an unvalidated persisted cache. If a saved Host Analysis cache is loaded
while Final Cut Pro is currently playing proxy media, render playback should still use the
loaded cache immediately rather than requiring re-analysis, keep the preview invalidation
revision moving so the stabilized proxy preview appears, and let original-media validation
happen later when original frames are available. If Final Cut Pro cannot provide the render
source frame, such as when Viewer playback is set to missing proxy media, render should
surface `Source Media Unavailable - Check FCP Proxy`, leave the saved Host Analysis cache
intact, and avoid drawing Debug Overlay diagnostics over the placeholder frame. When render
uses a saved analysis while the current source is proxy-scaled, status should make that
visible as proxy preview instead of silently promoting the cache to ordinary `Ready`.
Render-time transitions between original/optimized and proxy preview should publish
`Host Analysis Status`, `Stabilizer Info`, and the hidden render revision when the shared
store revision changes, even if the render callback already holds a locally matching hidden
revision value.
When original-media validation maps a trimmed timeline render time back to the analyzed
source time, render instances should persist that offset with the Host Analysis cache
identity so proxy-only render instances and processes can sample the same prepared motion
path instead of falling back to an unmapped timeline time.
Proxy/scaled media detection should treat pixel transforms that deviate from original
`1.0x/1.0x` in either direction as scaled media: Host Analysis must reject those frames,
while render playback with a saved analysis should keep using the prepared original-media
motion path instead of validating fingerprints against the scaled proxy frame.
When the
effective overall transform strength is zero, rendering must
bypass prepared motion-path sampling and output an identity transform with no debug overlay.
Render-time frame/window lookup should use the sorted prepared frame times directly instead
of repeatedly scanning the full analysis frame set on every preview sample.
When Host Analysis/cache state changes, update a hidden render-affecting revision parameter
so Final Cut Pro invalidates the preview/render cache and the viewer reflects the prepared
stabilization immediately. If Final Cut Pro reports a stale hidden revision value after an
attempted publish, keep retrying the same revision instead of treating a plug-in-local
publish record as proof that the host accepted it.
Render playback should favor the smoothest visible pan over low per-frame compute cost:
after calculating the prepared-path transform, sample neighboring render times symmetrically
and blend the final automatic transform with zero phase so the preview does not step between
corrections. Near clip edges, average only in-range neighboring samples instead of clamping
out-of-range samples to the first or last analysis frame, so end frames are not over-weighted.
This render-time smoothing must not require rerunning Host Analysis or changing the cache
schema.
Render-time smoothing must not average away Footstep Jitter impulses or roll jitter needed
to stabilize fine distant ridge-line shake. Smooth Turn Smoothing, Stride Wobble, and Walking
Bob components independently, then recombine them with the current render frame's Footstep
Jitter X/Y/roll correction. Footstep Jitter debug/status output should show the raw confidence
and effective correction strength so low-confidence gating is visible. Far-field Warp should
not use the full broad transform-smoothing window; keep it on a short in-range render-time
smoothing window so ridge-line correction stays responsive while single-frame gate flicker is
still damped.

## Walking Correction Stages

Fine high-frequency shake should be handled by render-time Footstep Jitter strength controls
that compare X/Y/rotation against an outer-frame linear prediction using seconds-based
windows: skip the center `0.10` second shock region and predict from outer samples up to
`1.0` second away. Footstep Jitter should suppress footstep landing shock as a frame-level
impulse rather than treating it as periodic smoothing, and it should not require rerunning
Host Analysis. Do not add or expose a user-facing Footstep Jitter window; fine jitter should
be corrected from the current render frame's impulse against the fixed seconds-based
outer-frame baseline using the multi-block Host Analysis path. Footstep Jitter confidence
should be evaluated per render frame from current tracking quality, accepted block coverage,
blur, local baseline support, surrounding footstep noise, and whether the center frame
departs from its outer-frame baseline; do not force a hidden minimum confidence floor.
Medium-confidence response may be curved upward for a more useful debug pass. Footstep
Jitter, Stride Wobble, and Walking Bob may use a more assertive medium-confidence response
than Turn Smoothing and Far-field Warp, but zero confidence must still produce zero
correction. Moderate landing impulses should not be buried by an overly high
surrounding-noise threshold.
The surrounding-noise floor should be capped below the full impulse response point so repeated
walking motion does not hide a real center-frame landing impulse.
Footstep Jitter strength values should be direct removal amounts with an exposed maximum of
`4.0`. Values above `1.0` may compensate when frame-local confidence makes correction too
weak, but applied correction must clamp at full detected-impulse removal during render so
high slider values do not add inverse shake. Footstep Jitter Rotation Strength should
default to `0.2` so walking footage keeps a stable horizon unless the user explicitly asks
for stronger roll correction.
Medium-period walking shake that is longer than Footstep Jitter but shorter than Walking
Bob should be handled by the render-time `Stride Wobble` stage. Keep its time window fixed
inside the implementation at `2.0` seconds, expose only X/Y/Rotation strength controls with
maximum `4.0`, do not add a user-facing Stride Wobble window, compute it from the
footstep-cleaned baseline, and feed longer Turn Smoothing / Walking Bob bands from the
stride-smoothed path so the same band is not removed twice. Stride Wobble residual gating
should use robust window evidence instead of the single worst frame in the window, so one
bad block-match frame does not suppress the whole medium band. Medium SWOB bands may reach
full confidence sooner than the broad UI scale, and the default Y strength should remain high
enough to remove step follow-through before the longer Walking Bob pass. Stride Wobble
Rotation Strength should default to `0.2` for the same horizon-preserving reason.
Footstep Jitter, Stride Wobble, and Walking Bob may use a count-aware walking-band tracking
gate that eases block coverage only when enough motion blocks were accepted. Far-field Warp
and Turn Smoothing should keep the stricter tracking gate so weak evidence does not create
swimming warp or false turn smoothing.
The render path must not compute Stride Wobble from the raw or jerk-limited broad path,
because that reintroduces Footstep Jitter shock into the medium-period band.
Prepared Host Analysis motion paths should be post-processed with a zero-phase jerk limiter
before caching. The limiter should clamp isolated acceleration spikes in X/Y/roll while
preserving path endpoints so total analyzed turn amount is not lost and real panning is not
delayed into a sliding path. Keep separate raw X/Y/roll impulse paths for Footstep Jitter so
the jerk limiter does not erase frame-level shake before render-time footstep correction.
Because this changes prepared path semantics, bump the Host Analysis cache schema when it
changes.
Large segmented walking turns should be controlled by the render-time `Turn Smoothing
Strength` slider, where higher values concatenate stop-and-go X-axis pan motion into a
smoother monotonic S-curve turn intent instead of a straight-line fit. The exposed maximum is `4.0`;
values above `1.0` may compensate for low-confidence gating when turn correction is too
weak, but applied correction must clamp at full detected turn-band removal. Turn smoothing
must not apply Y or roll correction. Macro X turn correction should be soft-limited to a
small output-edge budget during render so large detected pans do not create stretched-edge
jumps in the preview. `Turn Detection Window` must use the Inspector UI value, and its UI
minimum must be the fixed `2.0` second Stride Wobble window so TURN cannot run shorter than
SWOB. The turn band should be measured from the stride-smoothed path instead of the raw frame
path, and Y correction must stay Footstep Jitter first, Stride Wobble second, and Walking Bob
last so short landing shock is not reintroduced by turn smoothing. TURN confidence should
require both tracking evidence and a real X turn band; do not keep a hidden minimum turn
confidence on low-evidence frames.
Y-axis walking bob that is longer than Stride Wobble but separate from X-only panning should
be handled by the render-time fixed `2.5` second `Walking Bob` and `Walking Bob Removal`
path, which corrects the Y-only band between the fixed `2.0` second stride-smoothed baseline
and the slightly longer walking-bob smoothing window, without changing X or roll and without
rerunning Host Analysis. Do not expose a user-facing Walking Bob window control.
Walking Bob should remain in the same effect as the final Y-only correction stage. It must
use its own confidence/debug value, must not gate or weaken Footstep Jitter Y, and setting
`Walking Bob Removal` to zero must still allow Footstep Jitter Y to work.
Walking Bob confidence should be based on current tracking evidence, symmetric window
support, robust residual evidence, and actual Y-band magnitude so weak block coverage,
one-sided clip-edge windows, or tiny vertical bands do not create large vertical image waves.
Walking Bob removal values should clamp at full
detected-band removal during render so high slider values do not add inverse vertical
shake, while still allowing values above `1.0` to compensate for low-confidence gating.

## Far-Field Warp And Edges

`Far-field Warp Strength` should expose one bundled small-clamp control for deskew/shear,
yaw/pitch proxy, and perspective/distort trim. It is intended only for distant ridge-line
shake in walking landscape footage. Keep the default at `1.0`, expose up to `4.0`, keep each
unit's render clamps small, surface `warp q`, shear, yaw/pitch, and perspective in
debug/status output, and render the correction from the current frame's local deviation from
its own `0.10`/`1.0` second outer-frame linear warp baseline so accumulated long-term drift
does not become a fixed deskew. Low tracking confidence or poor search-radius headroom should
gate Far-field Warp off instead of creating wave-like image distortion. Render should use a
walking-footage tracking gate tuned for 25% Host Analysis samples plus a tiny render-time
deadband so weak warp deltas do not create swimming or wave-like distortion. Medium-confidence
warp gates may be curved upward, and the tracking gate should start early enough that moderate
25% Host Analysis evidence can still correct distant ridge-line shake while reaching full
response gradually enough to avoid high-side gate jumps. The warp gate may use short local
tracking support and short render-time smoothing to avoid single-frame gate flicker, but zero
local tracking or poor current search-radius evidence must still produce zero warp correction.
`W Q` should represent the applied warp confidence after those safety gates. Bump Host
Analysis cache schema when prepared warp path semantics change.
`Edge Display Mode` should control whether transformed source pixels outside the original
image stretch edge pixels or draw black. Do not tie black outside-source pixels to `Debug
Overlay`; debug overlay should only show diagnostics.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  docs/
  fxplug/
```

The Xcode project lives at
`fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj`. Keep FxPlug source under
`fxplug/StabilizerFxPlug/Plugin`, wrapper app source under
`fxplug/StabilizerFxPlug/WrapperApp`, installer scripts under
`fxplug/StabilizerFxPlug/scripts`, and Motion Template resources under
`fxplug/StabilizerFxPlug/MotionTemplates`.

## Test Project

Use this local Final Cut Pro library for manual end-to-end testing:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/test.fcpbundle
```

It is a shared workspace test fixture, outside this plugin repo. Use it when checking the
native effect against real timeline clips in Final Cut Pro.

## Shared Final Cut Pro UI Shortcut Script

The shared local AppleScript helper for Final Cut Pro UI shortcut work lives outside this
repo at:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript
```

For Codex-driven Final Cut Pro UI testing, prefer the repo-local wrapper first:

```sh
scripts/fcp_ui_test.sh env-check
scripts/fcp_ui_test.sh open-test-library
scripts/fcp_ui_test.sh apply-and-analyze-selected
scripts/fcp_ui_test.sh analyze-selected
scripts/fcp_ui_test.sh dump-front-window
scripts/fcp_ui_test.sh list-caches
```

The wrapper keeps the common UI test flow terminal-first and uses the shared AppleScript
under the hood. Use free-form Computer Use only after these explicit commands fail or when a
new UI path has no helper command yet. See `docs/codex-fcp-ui-testing.md` for the expected
selected-clip workflow and cache-backed diagnostics.

From this repo, run it through the parent-relative path:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript apply
osascript ../scripts/fcp_stabilizer_shortcuts.applescript start-analysis
osascript ../scripts/fcp_stabilizer_shortcuts.applescript toggle-debug-overlay
osascript ../scripts/fcp_stabilizer_shortcuts.applescript set-debug-overlay on
osascript ../scripts/fcp_stabilizer_shortcuts.applescript set-debug-overlay off
osascript ../scripts/fcp_stabilizer_shortcuts.applescript focus-inspector
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-selected-project
osascript ../scripts/fcp_stabilizer_shortcuts.applescript dump-front-window
```

Use it from Keyboard Maestro, Automator Quick Actions, or Terminal when manual FCP
validation needs faster access to `Stabilizer Transform`, `Start Host Analysis`, `Debug
Overlay`, selected Browser projects, or the Inspector. Grant Accessibility permission to
the app that runs the script.
For project opening, prefer `open-selected-project` after selecting the project thumbnail
or list row in the Browser. It uses a real CoreGraphics double-click because ordinary
AppleScript click repeats can fail to register as a Final Cut Pro double-click.
If FCP UI labels change, use `dump-front-window` to inspect the accessible roles/names and
update the shared script in the parent workspace. Do not copy a separate version into this
repo unless the user explicitly asks for repo-local divergence.

## Version Visibility

Keep `stabilizerFxPlugVersion` in
`fxplug/StabilizerFxPlug/Plugin/StabilizerFxPlug.swift` aligned with
`CFBundleShortVersionString` in the wrapper app and plug-in plist files. User-visible
FxPlug behavior changes should bump the version value used by `Stabilizer Info`,
`Host Analysis Status`, and the compact Debug Overlay runtime row.

## Verification

After FxPlug edits, run:

```sh
xcodebuild -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj -scheme StabilizerFxPlug -configuration Debug -derivedDataPath /tmp/StabilizerFxPlugDerived build
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
git diff --check -- AGENTS.md README.md docs/usage.md fxplug/StabilizerFxPlug
```

The `StabilizerFxPlug` shared scheme has a pre-build action that fails when Final Cut Pro is
running and a post-build action that runs
`fxplug/StabilizerFxPlug/scripts/install_debug_app.sh`. Final Cut Pro must be quit before
building or installing; touching a loaded FxPlug bundle can leave Final Cut Pro holding a
stale PlugInKit object and produce `P1000307` helper communication errors. A successful
build should install `/Applications/StabilizerFxPlug.app`, copy the Motion Template into
the user's Movies Motion Templates folder, and register its embedded pluginkit for Final
Cut Pro.
