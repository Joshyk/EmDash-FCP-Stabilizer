# Final Cut Pro Stabilizer

Native FxPlug 4 effect for walking-gimbal stabilization in Final Cut Pro and Motion.

This repo is FxPlug-only. It no longer contains or supports a separate automation runtime,
standalone estimator, or Transform-keyframe writer.

## Effect

- `Stabilizer Transform`
  - Renders a transformed source texture with Metal.
  - Corrects softened X/Y translation and roll without writing Final Cut Pro Transform
    keyframes.
  - Keeps yaw/pitch/shear/perspective compensation disabled.
  - Keeps render scale fixed at 1.0.
  - Always uses `Host Analysis`.

`Host Analysis` uses Final Cut Pro's FxPlug analysis infrastructure to request GPU analysis
frames from the host. The FxPlug runtime then uses Metal compute to downsample luma samples
and run frame-to-frame block matching while preparing motion paths. If those Metal analysis
resources are unavailable, Host Analysis fails visibly instead of falling back to CPU
analysis.

Host Analysis reads `Sample Size` once when an analysis pass starts. The sample image is
always derived from the original clip dimensions, with options for `100%`, `75%`, `50%`,
`25%`, and `10%`. The default is `100%`, which analyzes at the original clip size.
In-progress analysis streams frame-to-frame motion directly through Metal and keeps only the
previous luma buffer needed for the next motion search, so it no longer writes per-frame
`.luma` scratch files.
The stabilization result is still built from the same prepared motion path.
`Start Host Analysis` requests the active effect clip from Final Cut Pro. If Final Cut Pro
reports that another analysis is already requested or running, the Inspector shows that
host state instead of starting an internal plug-in queue.

Completed Host Analysis frame sets are persisted to
`/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json` as the
latest cache and to range-indexed files under
`/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/`. Reapplying the
effect can reuse a previous Host Analysis run when the analyzed range and current source
frame validate against the saved frame fingerprints. `Start Host Analysis` first reloads a
saved cache when one exists and only starts a new analysis when no saved cache can be loaded.
If that cache was rejected for the current clip, the next start skips it and requests a new
analysis. `Clear Host Analysis Cache` is the explicit delete control and shows
`Cache Cleared` in the Inspector.
Cache compatibility is tied to cache schema and current source-frame validation, not the
visible FxPlug runtime version, so render-only runtime updates should not force a new
analysis pass.

The cache includes prepared motion paths so playback renders from precomputed values instead
of running block matching again on every frame. New cache files store prepared paths, frame
timing, blur values, and fingerprints instead of every frame's luma sample. The Host
Analysis uses a process-wide shared store for the active FxPlug runtime so setup, frame
analysis, cleanup, and render can exchange the prepared path even when Final Cut Pro calls
them through different FxPlug instances. `Start Host Analysis` is the only path that
requests Host Analysis from Final Cut Pro; render/preview callbacks only read completed
analysis or validated persistent cache. If Final Cut Pro reports that Host Analysis is
already requested or running, the Inspector shows that state instead of queueing another
start inside the plug-in. Persistent cache files remain shared reuse candidates after
source-frame validation. When Final Cut Pro renders a trimmed clip with a render time that differs from Host Analysis frame time,
the effect maps the current render frame fingerprint back to the analyzed frame set and uses
that offset before sampling the prepared motion paths. The Inspector shows
`Host Analysis Status`; after a completed analysis it should read `Ready (... frames)`.
Analysis input still requires original media, but a validated analysis continues to drive
the preview/render path when Final Cut Pro plays proxy media.
If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
media, render playback uses that loaded cache immediately instead of requiring re-analysis;
original-media validation can happen later when original frames are available.
Setting `Overall Strength` to `0` fully bypasses the automatic transform path, including
crop-safety motion and debug overlay output.
The plug-in also updates a hidden render revision whenever Host Analysis or cache state
changes so Final Cut Pro refreshes the preview from the prepared motion paths.
Fine high-frequency shake is controlled separately with the Footstep Jitter strength sliders.
Footstep Jitter treats X/Y/rotation shake as a frame-level impulse against an outer-frame
linear prediction that skips the center shock region, so footstep landing shock is not
averaged back into the smooth path. Host Analysis estimates motion from multiple Metal
block-matched regions, prioritizes upper-frame far-field blocks for walking landscape
footage, and rejects outlier blocks before building the per-frame path. This keeps distant
mountain/background motion from being dominated by close grass, water, or road parallax.
Footstep Jitter is evaluated per render frame and is not a windowed or periodic smoothing
control. Strength values run up to `4.0`; values above `1.0` can push through low-confidence
gating, but the applied correction still clamps at full detected-impulse removal so it does
not add inverse shake.
Prepared Host Analysis paths are also post-processed with a zero-phase jerk limiter. The
limiter only clamps isolated acceleration spikes in the saved X/Y/roll motion path while
preserving the total analyzed turn amount, so one bad frame does not create a new snap in
playback and real panning does not become a sliding, delayed path.
Segmented walking turns are controlled with `Turn Smoothing Strength`; higher values
concatenate stop-and-go turn motion into a monotonic S-curve intent instead of fitting a
straight line through the window. The slider runs up to `4.0`; values above `1.0` can push
through low-confidence gating when the turn still looks segmented, while the applied
correction clamps at full detected turn-band removal. Turn smoothing does not change roll.
Y correction is ordered as Footstep Jitter first, Turn Smoothing second, and Walking Bob
last. The Y turn intent is measured from the footstep-cleaned baseline instead of the raw
frame path, so short landing shock is not reintroduced by the turn correction.
Footstep vertical motion is controlled with `Walking Bob Window` and `Walking Bob Removal`,
which remain in the same effect as the final Y-only correction stage. Walking Bob targets
the remaining medium-period vertical band after Footstep Jitter and Turn Smoothing; it does
not gate or reduce Footstep Jitter Y. The default removal is `0.75` to avoid overcorrecting
walking footage. Shorter window values around `0.4-1.0` seconds target visible footstep
bounce. Footstep Jitter and Walking Bob strengths are clamped at full detected-band removal
during render, so high slider values do not add inverse shake. Values above `1.0` are useful
when confidence gating makes the detected correction visibly too weak.
`Debug Overlay` shows top-left diagnostics, including separate `footstep q` and `bob q`
confidence values in Host Analysis status while rendering. `Edge Display Mode` switches
preview edges between
stretched source edges and black outside-source pixels.
`Stabilizer Info` is a scrollable read-only text box. It shows the loaded FxPlug version,
the active correction bands (`Footstep jitter`, `Walking Bob`, `Turn Smoothing`), and analysis
metadata, so the Inspector can confirm which installed runtime Final Cut Pro is using.

## Build

Build the wrapper app and embedded FxPlug:

```sh
xcodebuild \
  -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj \
  -scheme StabilizerFxPlug \
  -configuration Debug \
  -derivedDataPath /tmp/StabilizerFxPlugDerived \
  build
```

The shared scheme installs each successful Debug build to
`/Applications/StabilizerFxPlug.app`, installs the Motion Template under the user's Movies
Motion Templates folder, and registers the embedded FxPlug with PluginKit. Debug installs
remove stale `Stabilizer Transform copy...` Motion Template folders from the `Emdash Studios`
group so Finder-created duplicates do not appear as extra effects in Final Cut Pro.

Verify registration:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
```

Restart Final Cut Pro after rebuilding if it was already open.
