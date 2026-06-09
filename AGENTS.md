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

Completed Host Analysis frame sets should be persisted by the FxPlug runtime at
`/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json`,
`/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-index-v2.json`,
and range-indexed files under
`/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/`. Cache candidates
must be validated against the current source frame before reuse. Rejected candidates should
be visible in logs/status and should not be deleted just because they do not match the
current clip. `Start Host Analysis` should first reload and use a saved persistent cache
when one exists; only start a new host analysis when no saved cache can be loaded. It must
not delete saved cache files. If the loaded cache is rejected for the current clip, the next
start should skip that rejected cache and request a new analysis. `Clear Host Analysis
Cache` is the explicit cache-clear path and should show `Cache Cleared`.
Persistent cache compatibility is based on cache schema and current source-frame
validation, not the visible FxPlug runtime version. Render-only version bumps should reuse
saved Host Analysis cache candidates. The loader should also consider current and legacy
Stabilizer container cache locations so bundle-id migrations do not force a new analysis
when the cache schema is still supported. Unsupported schema candidates should surface
`Cache Unsupported - Run Host Analysis` in the Inspector, remain on disk, and require an
explicit new Host Analysis run instead of being silently ignored or deleted.

Host Analysis should read user-controlled `Sample Size` once when analysis starts. The
Inspector default should be `10%` so quick Debug Overlay tuning can start without a full
source-size pass, while still offering `100%`, `75%`, `50%`, `25%`, and `10%` options. The
sample image must always be derived from the original clip dimensions using the selected
percentage option. Long clips should keep that requested percentage. In-progress analysis should stream frame-to-frame motion in memory and
keep only the previous luma buffer needed for the next Metal motion search; do not write
per-frame `.luma` scratch files or store analysis files inside a Final Cut Pro library/project
bundle.
Persistent cache files should store prepared paths, frame timing, blur values, and
fingerprints instead of every frame's full luma sample.
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
and lower means weaker evidence. Debug Overlay should also expose a compact active runtime
version row so stale saved Inspector strings do not hide which binary is rendering.

## Playback And Render

Host Analysis playback must render from prepared motion paths for the active FxPlug runtime.
`Start Host Analysis` is the only path that should call `startForwardAnalysis`; render and
preview callbacks must not auto-start Host Analysis. The active runtime uses a process-wide
shared Host Analysis store because Final Cut Pro may call setup, frame analysis, cleanup,
and preview/render through different FxPlug instances. Persistent cache files are the
cross-process reuse path after source-frame validation. Completed analysis should be written
to the shared user Application Support cache path, not only to the current extension
container. When an analyzer instance saves a completed cache, render/preview instances with
no prepared analysis should notice cache file changes and reload persistent cache candidates
on demand; this keeps the stabilized preview visible even when analyzer and render use
different FxPlug processes. If Final Cut
Pro reports that Host Analysis is already requested or running, surface that state in
Inspector status instead of queueing another start inside the plug-in. Do not re-run
full block matching across the analyzed frame set on every render frame. Keep `Host Analysis
Status` visible in the Inspector, update it to `Ready (... frames)` after completed
analysis, and include the active FxPlug version there when Final Cut Pro accepts status
parameter updates. Debug Overlay should remain the live render-runtime indicator because
older saved Inspector strings can remain stale on existing timeline instances.
Render playback must tolerate trimmed clips whose render time differs from Host
Analysis frame time by matching the current render frame fingerprint back to the analyzed
frame set and applying that time offset before sampling the prepared motion paths. Once an
analysis is validated, render playback should keep using the prepared motion path even when
Final Cut Pro is playing proxy media; proxy media is rejected only for Host Analysis input
and for validating an unvalidated persisted cache. If a saved Host Analysis cache is loaded
while Final Cut Pro is currently playing proxy media, render playback should still use the
loaded cache immediately rather than requiring re-analysis; original-media validation can
happen later when original frames are available. When the
effective overall transform strength is zero, rendering must
bypass prepared motion-path sampling and output an identity transform with no debug overlay.
When Host Analysis/cache state changes, update a hidden render-affecting revision parameter
so Final Cut Pro invalidates the preview/render cache and the viewer reflects the prepared
stabilization immediately.
Render playback should favor the smoothest visible pan over low per-frame compute cost:
after calculating the prepared-path transform, sample neighboring render times symmetrically
and blend the final automatic transform with zero phase so the preview does not step between
corrections. This render-time smoothing must not require rerunning Host Analysis or changing
the cache schema.
Render-time smoothing must not average away Footstep Jitter impulses or roll jitter needed
to stabilize fine distant ridge-line shake. Smooth Turn Smoothing, Stride Wobble, and Walking
Bob components independently, then recombine them with the current render frame's Footstep
Jitter X/Y/roll correction. Footstep Jitter debug/status output should show the raw confidence
and effective correction strength so low-confidence gating is visible.

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
blur, and whether the center frame departs from its outer-frame baseline; do not force a
hidden minimum confidence floor. Medium-confidence response may be curved upward for a more
useful debug pass, but zero confidence must still produce zero correction.
Footstep Jitter strength values should be direct removal amounts with an exposed maximum of
`4.0`. Values above `1.0` may compensate when frame-local confidence makes correction too
weak, but applied correction must clamp at full detected-impulse removal during render so
high slider values do not add inverse shake.
Medium-period walking shake that is longer than Footstep Jitter but shorter than Walking
Bob should be handled by the render-time `Stride Wobble` stage. Keep its time window fixed
inside the implementation at `2.0` seconds, expose only X/Y/Rotation strength controls with
maximum `4.0`, do not add a user-facing Stride Wobble window, compute it from the
footstep-cleaned baseline, and feed longer Turn Smoothing / Walking Bob bands from the
stride-smoothed path so the same band is not removed twice.
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
last so short landing shock is not reintroduced by turn smoothing.
Y-axis walking bob between micro jitter and panning should be handled by the render-time
fixed `2.5` second `Walking Bob` and `Walking Bob Removal` path, which corrects the Y-only
band between the fixed `2.0` second stride-smoothed baseline and the slightly longer
walking-bob smoothing window, without changing X or roll and without rerunning Host
Analysis. Do not expose a user-facing Walking Bob window control.
Walking Bob should remain in the same effect as the final Y-only correction stage. It must
use its own confidence/debug value, must not gate or weaken Footstep Jitter Y, and setting
`Walking Bob Removal` to zero must still allow Footstep Jitter Y to work.
Walking Bob confidence should be based on current tracking evidence and symmetric window
support so weak block coverage or one-sided clip-edge windows do not create large vertical
image waves.
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
tiny render-time deadband so weak warp deltas do not create swimming or wave-like distortion.
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

The `StabilizerFxPlug` shared scheme has a post-build action that runs
`fxplug/StabilizerFxPlug/scripts/install_debug_app.sh`. A successful build should install
`/Applications/StabilizerFxPlug.app`, copy the Motion Template into the user's Movies
Motion Templates folder, and register its embedded pluginkit for Final Cut Pro.
