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
  Unsupported schema candidates are reported in the Inspector and left on disk.
- Streams in-progress Host Analysis motion directly through Metal and keeps only the
  previous luma buffer needed for the next frame-to-frame motion search. It does not write
  per-frame `.luma` scratch files.
- Stores prepared motion paths, frame timing, blur values, search-radius edge-hit counts,
  and fingerprints in new
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

- `Micro Jitter X Strength`: direct amount for horizontal micro-jitter correction. The
  default is `0.5`; `1.0` fully removes the detected impulse, and higher values are clamped
  during render to avoid inverse shake.
- `Micro Jitter Y Strength`: direct amount for vertical micro-jitter correction. The default
  is `0.5`. Micro Jitter uses an outer-frame linear prediction that skips the center shock
  region for X/Y/rotation, so footstep landing shock is treated as a frame-level impulse
  instead of being averaged back into the smooth path. `1.0` fully removes the detected
  impulse, and higher values are clamped during render to avoid inverse shake.
- `Micro Jitter Rotation Strength`: direct amount for roll micro-jitter correction. The
  default is `0.35`; `1.0` fully removes the detected impulse, and higher values are
  clamped during render to avoid inverse shake.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- `Panning X/Y Strength`: controls how strongly the stabilizer corrects large intentional
  pans in X/Y translation only. It does not change roll. At `0`, long-window correction is
  bypassed; at `1`, long-window correction is strongest. The pan band is measured from the
  Micro Jitter baseline, and the Y pan band is measured after removing Y Axis
  Stabilization, so short landing shock is not reintroduced by the pan correction.
- `Panning X/Y Window`: centered panning window. In Host Analysis mode this slider
  is evaluated during render against the prepared analysis path, so changing it does not
  require rebuilding analysis.
- `Y Axis Stabilization Window`: Y-axis-only window for footstep bob and vertical shake
  between micro jitter and large panning. It corrects the Y band between the Micro Jitter
  baseline and this Y stabilization smooth path, which is also computed from the Micro
  Jitter baseline without changing X or roll. Use shorter values around `0.4-1.0` seconds
  for visible footstep bounce and larger values for slower vertical sway.
- `Y Axis Stabilization Strength`: direct amount for the Y-only correction. `1.0` fully
  removes the detected Y-axis band, and higher values are clamped during render to avoid
  adding inverse vertical shake.
- `Sample Size`: analysis image size as a percentage of the original clip dimensions.
  Options are `100%`, `75%`, `50%`, `25%`, and `10%`; `100%` analyzes at the original clip
  size. Host Analysis reads this value once when the analysis pass starts. The actual pixel
  size is shown in `Stabilizer Info`.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available.
- `Edge Display Mode`: chooses whether transformed pixels outside the source image stretch
  edge pixels or draw black.
- Host Analysis is always used. It requests GPU analysis frames from the host. Incomplete
  host analysis renders identity for that source instead of silently switching modes.
  Proxy media is rejected for Host Analysis input and for unvalidated persisted-cache
  validation, but a validated analysis continues to render during proxy playback.
- `Debug Overlay` shows labeled top-left diagnostics while checking runtime behavior.
- `Start Host Analysis`: clears the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis. If a saved cache uses an unsupported schema,
  the Inspector shows `Cache Unsupported - Run Host Analysis`; the file remains on disk and
  the next start requests new analysis for the current build.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared` in `Host Analysis Status`.
- `Stabilizer Info`: scrollable read-only Inspector value showing the loaded FxPlug
  version, active correction bands (`Jitter impulse`, `Y Axis Stabilization <= Ys`,
  `Panning X/Y Y-Zs`), plus latest
  analysis time, frame count, actual sample image size, source frame size, and pixel
  transform scale when analysis is available.
- `Debug Overlay`: normally off. When enabled, the labeled top-left bars show `X`, `Y`,
  `ROLL`, `TURN`, `STEP`, `BOB`, `SMTH`, confidence (`F Q`, `S Q`, `B Q`, `W Q`), and
  tracking-quality (`TRK`, `BLUR`, `RES`, `HIT`) diagnostics so Final Cut Pro runtime
  analysis can be checked. It also writes current render correction values into `Host
  Analysis Status`, including tracking/motion quality, edge-hit counts, and the Y correction
  split into footstep, stride, and walking-bob components.
