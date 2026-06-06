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

Host Analysis reads `Sample Width` once when an analysis pass starts. Long clips still use
the requested sample size unless it exceeds the source frame width. In-progress analysis
streams frame-to-frame motion directly through Metal and keeps only the previous luma buffer
needed for the next motion search, so it no longer writes per-frame `.luma` scratch files.
The stabilization result is still built from the same prepared motion path.

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

The cache includes prepared motion paths so playback renders from precomputed values instead
of running block matching again on every frame. New cache files store prepared paths, frame
timing, blur values, and fingerprints instead of every frame's luma sample. The Host
Analysis store is shared across FxPlug analyzer/render instances in the plug-in process, so
the render path can apply the prepared smoothing immediately after analysis completes. When
Final Cut Pro renders a trimmed clip with a render time that differs from Host Analysis frame
time, the effect maps the current render frame fingerprint back to the analyzed frame set and
uses that offset before sampling the prepared motion paths. The Inspector shows
`Host Analysis Status`; after a completed analysis it should read `Ready (... frames)`.
Analysis input still requires original media, but a validated analysis continues to drive
the preview/render path when Final Cut Pro plays proxy media.
Setting `Overall Strength` to `0` fully bypasses the automatic transform path, including
crop-safety motion and debug overlay output.
The plug-in also updates a hidden render revision whenever Host Analysis or cache state
changes so Final Cut Pro refreshes the preview from the prepared motion paths.
Fine high-frequency shake is controlled separately with `Micro Jitter Window`, which defaults
to `0.12` seconds and adds a short-window correction on top of the long pan smoothing path
without rerunning analysis. Values shorter than the analyzed frame interval are raised
during render enough to include adjacent frames, so older `0.025` values still produce
micro correction.
Large intentional pans are controlled with `Pan Stabilization Strength`; higher values
apply stronger long-window correction.
Y-axis walking bob is controlled with `Walking Bob Window` and `Walking Bob Strength`, which
target the Y band between Micro Jitter smoothing and a Y-only bob smoothing window. Shorter
values around `0.4-1.0` seconds target visible footstep bounce, and the strength slider can
be pushed past `2.0` when the bounce remains visible.
`Debug Overlay` shows top-left diagnostics. `Edge Display Mode` switches preview edges
between stretched source edges and black outside-source pixels.
`Stabilizer Info` shows the loaded FxPlug version and current Micro Jitter, Walking Bob,
and Pan Stabilization values before the analysis metadata, so the Inspector can confirm
which installed runtime Final Cut Pro is using.

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
Motion Templates folder, and registers the embedded FxPlug with PluginKit.

Verify registration:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
```

Restart Final Cut Pro after rebuilding if it was already open.
