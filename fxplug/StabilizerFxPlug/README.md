# Stabilizer FxPlug

FxPlug 4 source for the native Final Cut Pro / Motion `Stabilizer Transform` effect.

This project is FxPlug-only. Do not add separate automation runtime files, standalone
estimators, or Transform-keyframe writers back into this target.

## Current Scope

- Adds an FxPlug 4 tileable effect named `Stabilizer Transform`.
- Uses Metal to render a transformed source texture.
- Exposes auto stabilization controls without manual transform trim parameters.
- Always uses Final Cut Pro's FxPlug Host Analysis infrastructure, requesting a
  forward GPU analysis, then using Metal compute in the plug-in runtime to downsample luma
  samples and run frame-to-frame block matching while preparing the motion paths. Metal
  analysis failures are reported as Host Analysis failures instead of silently falling back
  to CPU analysis.
- Persists completed Host Analysis frame sets to
  `/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json` as
  the latest cache and to range-indexed files under
  `/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/`.
- Reuses saved Host Analysis across FxPlug runtime version updates when the cache schema
  and current source-frame validation still match. The loader checks current and legacy
  Stabilizer container cache locations so bundle-id migrations do not force analysis again.
- Streams in-progress Host Analysis motion directly through Metal and keeps only the
  previous luma buffer needed for the next frame-to-frame motion search. It does not write
  per-frame `.luma` scratch files.
- Stores prepared motion paths, frame timing, blur values, and fingerprints in new
  persistent cache files instead of embedding every frame's luma sample in JSON.
- Reuses persisted analysis only after the current source frame validates against saved
  frame fingerprints.
- Maps trimmed-clip render time back to Host Analysis time by matching the current render
  frame fingerprint against the analyzed frame set before sampling prepared motion paths.
- Refuses proxy-scaled frames for Host Analysis and render-time cache validation. If the
  host supplies proxy media, `Host Analysis Status` shows
  `Proxy Media Rejected - Use Original Media`; switch Final Cut Pro back to original media
  and rerun Host Analysis.
- Renders from prepared motion paths instead of re-running block matching on every frame.
- Combines the long pan smoothing path with a short micro-jitter path and a Y-only walking
  bob path so fine shake and 1-2 second vertical bobbing can be tuned independently from
  large walking-gimbal sway.
- `Edge Display Mode` switches preview edges between stretched source edges and black
  outside-source pixels, making stabilization movement visible when needed.
- Updates a hidden render revision parameter when Host Analysis/cache state changes so Final
  Cut Pro refreshes the preview from the prepared motion paths.
- Shares the in-process Host Analysis store across FxPlug analyzer/render instances so a
  completed analysis can drive smoothing in playback.
- Keeps rejected cache candidates on disk for other clips.
- Requests only the current render frame through `scheduleInputs`; stabilization is driven
  by prepared Host Analysis paths.
- Does not write analysis files into a Final Cut Pro library or project bundle.
- Estimates low-resolution global X/Y motion and roll from requested frames.
- Is tuned for walking-gimbal footage: the render path corrects softened X/Y translation
  and roll only, disables yaw/pitch proxy, shear, perspective compensation, and zoom, and
  keeps render scale fixed at 1.0.
- Includes a minimal wrapper app source/resource set under `WrapperApp/`.

The current implementation reads host frames as Metal textures, performs analysis
downsampling and shift scoring on Metal, and keeps CPU work limited to orchestration, small
result reduction, smoothing math, validation, and cache JSON I/O.

## Local SDK

This machine has:

```text
/Library/Developer/SDKs/FxPlug.sdk
/Library/Developer/Xcode/Templates/FxPlug/FxPlug 4.xctemplate
```

Full Xcode is required. This machine is configured with:

```text
/Applications/Xcode.app/Contents/Developer
```

The Xcode 26.5 Metal toolchain was installed with:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Build Path

Build the wrapper app and embedded pluginkit:

```sh
xcodebuild \
  -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj \
  -scheme StabilizerFxPlug \
  -configuration Debug \
  -derivedDataPath /tmp/StabilizerFxPlugDerived \
  build
```

The `StabilizerFxPlug` shared scheme runs a build post-action after every successful build.
It installs a persistent copy of the Debug app to:

```text
/Applications/StabilizerFxPlug.app
```

and registers the embedded FxPlug with PluginKit and LaunchServices. If Final Cut Pro is
already running during a rebuild, restart Final Cut Pro before checking for the updated
effect in the Effects browser.

The intermediate Debug app is written to:

```text
/tmp/StabilizerFxPlugDerived/Build/Products/Debug/StabilizerFxPlug.app
```

The app embeds:

```text
Contents/PlugIns/StabilizerFxPlug XPC Service.pluginkit
```

To rerun the install/registration step without rebuilding:

```sh
fxplug/StabilizerFxPlug/scripts/install_debug_app.sh \
  /tmp/StabilizerFxPlugDerived/Build/Products/Debug/StabilizerFxPlug.app
```

## Stabilization Model

- `Micro Jitter Window`: short smoothing window for fine shake. The default is `0.12`
  seconds. Values shorter than the analyzed frame interval are raised during render enough
  to include adjacent frames, so old `0.025` values still produce a micro correction.
- `Micro Jitter X Strength`: multiplier for horizontal micro-jitter correction. The default
  is `0.5`.
- `Micro Jitter Y Strength`: multiplier for vertical micro-jitter correction. The default is
  `0.5`.
- `Micro Jitter Rotation Strength`: multiplier for roll micro-jitter correction. The default
  is `0.35`.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- `Pan Stabilization Strength`: controls how strongly the stabilizer corrects large
  intentional pans. At `0`, long-window correction is bypassed; at `1`, long-window
  correction is strongest.
- `Pan Smooth Seconds Slider`: centered panning window. In Host Analysis mode this slider
  is evaluated during render against the prepared analysis path, so changing it does not
  require rebuilding analysis.
- `Walking Bob Window`: Y-axis-only window for footstep bob and vertical shake between
  micro jitter and large panning. It corrects the Y band between the Micro Jitter smooth
  path and this bob smooth path without changing X or roll. Use shorter values around
  `0.4-1.0` seconds for visible footstep bounce and larger values for slower vertical sway.
- `Walking Bob Strength`: multiplier for the Y-only walking-bob correction. The slider
  range extends to `4.0` for footage where footstep bob remains visible at `2.0`.
- `Sample Width`: analysis image width. The sample height is calculated from the source
  frame aspect ratio. Width values above the source frame width use the source frame
  dimensions before Host Analysis runs. Long clips still use the requested width unless it
  exceeds the source frame width. Host Analysis reads this value once when the analysis
  pass starts. The actual size is shown in `Stabilizer Info`.
- `Edge Display Mode`: chooses whether transformed pixels outside the source image stretch
  edge pixels or draw black.
- Host Analysis is always used. It requests GPU analysis frames from the host. Incomplete
  host analysis renders identity for that source instead of silently switching modes.
  Proxy media is rejected for Host Analysis input and for unvalidated persisted-cache
  validation, but a validated analysis continues to render during proxy playback.
- `Debug Overlay` shows top-left diagnostics while checking runtime behavior.
- `Start Host Analysis`: clears the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared` in `Host Analysis Status`.
- `Stabilizer Info`: read-only Inspector value showing the loaded FxPlug version, current
  Micro Jitter, Walking Bob, and Pan Stabilization values, plus latest analysis time, frame
  count, actual sample image size, source frame size, and pixel transform scale when
  analysis is available.
- `Debug Overlay`: normally off. When enabled, the top-left bars visualize automatic X, Y,
  and rotation diagnostics so Final Cut Pro runtime analysis can be checked. It also writes
  current render correction values into `Host Analysis Status`, including the Y correction
  split into macro, micro, and walking-bob components.
