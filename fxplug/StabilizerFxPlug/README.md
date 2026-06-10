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
- Combines per-frame Footstep Jitter, fixed-window Stride Wobble, fixed-window Walking Bob,
  Far-field Warp, and broader Turn Smoothing bands so walking-gimbal shake is separated by
  time scale without rerunning Host Analysis. Only Footstep Jitter keeps the current
  render frame's raw impulse after `1.20` second zero-phase smoothing; Stride Wobble stays
  in the wider smoothed transform. Clip-edge smoothing skips out-of-range neighboring
  samples instead of duplicating the first or last analysis frame.
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
- Is tuned for walking-gimbal footage: the render path corrects softened X/Y translation,
  roll, and optional small-clamp Far-field Warp while keeping render scale fixed at 1.0.
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

- `Footstep Jitter X Strength`: direct amount for horizontal frame-local footstep correction.
  The default is `1.0`; values above `1.0` can compensate for weak frame confidence but are
  clamped during render to avoid inverse shake. The confidence response is more assertive for
  medium-confidence frame evidence, but zero confidence still produces zero correction.
  Confidence also checks local baseline support and surrounding footstep noise.
- `Footstep Jitter Y Strength`: direct amount for vertical frame-local footstep correction.
  Footstep Jitter uses a seconds-based outer-frame linear prediction that skips the center
  `0.10` second shock region and predicts from outer samples up to `1.0` second away for
  X/Y/rotation, so landing shock is treated as a frame-level impulse instead of being
  averaged back into the smooth path. Moderate landing impulses now reach useful confidence
  a little sooner, while zero evidence and noisy unsupported frames still produce zero
  correction.
- `Footstep Jitter Rotation Strength`: direct amount for roll footstep correction. Values
  above `1.0` can compensate when frame-local confidence makes the detected impulse visibly
  under-corrected, but output remains clamped at full detected-impulse removal.
- `Stride Wobble X/Y/Rotation Strength`: direct amount for medium-period walking wobble. The
  render-time window is fixed at `2.0` seconds; there is no user-facing SWOB window. It is
  measured from the footstep-cleaned path, not the raw or jerk-limited broad path, so it does
  not erase FJIT twice. Residual gating uses robust window percentiles instead of the single
  worst frame. Medium SWOB bands reach full confidence earlier than the broad control scale,
  and the Y default is `0.50` so step follow-through is not pushed entirely into the longer
  Walking Bob pass. FJIT, SWOB, and BOB use a count-aware walking-band tracking gate; WARP
  and TURN keep the stricter tracking gate.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- `Walking Bob`: fixed internal `2.5` second Y-only walking bob band after FJIT and SWOB.
  There is no user-facing BOB window control; Turn Detection has its own Inspector slider.
  The shorter window keeps BOB from turning weak vertical evidence into a slow image wave.
  Its confidence uses tracking quality, symmetric window support, robust residuals, and
  actual Y-band magnitude so weak tracking, one-sided clip-edge windows, or tiny vertical
  bands do not create large vertical waves.
- `Walking Bob Removal`: direct amount for the Y-only BOB correction. Setting it to `0` does
  not disable Footstep Jitter Y, and higher values are clamped during render to avoid inverse
  vertical shake.
- `Far-field Warp Strength`: bundled small-clamp WARP correction for distant ridge-line
  shake. It uses a `0.10`/`1.0` second outer-frame linear warp baseline and applies shear,
  yaw/pitch proxy, and perspective trim from the current frame's local deviation. Render
  gates warp with walking-footage tracking quality and search-radius headroom, starts the
  tracking gate earlier for moderate 25% Host Analysis evidence, curves medium-confidence
  gates upward, then applies a tiny deadband and small render-only clamps so weak frames do
  not create wave-like image distortion.
- `Turn Smoothing Strength`: controls large segmented walking turns in X translation only.
  It does not change Y or roll, and the macro correction is soft-limited to a small
  output-edge budget.
- `Turn Detection Window`: centered TURN window evaluated during render against prepared
  motion paths. The UI value is used as the TURN window, and the UI minimum is the fixed
  `2.0` second Stride Wobble window so TURN cannot run shorter than SWOB.
- `Sample Size`: analysis image size as a percentage of the original clip dimensions.
  Options are `100%`, `75%`, `50%`, `25%`, and `10%`; the default is `10%` so a debug pass
  can analyze quickly. Host Analysis reads this value once when the analysis pass starts. The
  actual pixel size is shown in `Stabilizer Info`.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available.
- `Edge Display Mode`: chooses whether transformed pixels outside the source image stretch
  edge pixels or draw black.
- Host Analysis is always used. It requests GPU analysis frames from the host. Incomplete
  host analysis renders identity for that source instead of silently switching modes.
  Proxy media is rejected for Host Analysis input and for unvalidated persisted-cache
  validation, but a validated analysis continues to render during proxy playback.
  Completed cache writes use the prepared analysis frame set as the authoritative timeline,
  so a reduced retained source-frame map does not block persistence.
- `Debug Overlay` shows labeled top-left diagnostics while checking runtime behavior.
- `Start Host Analysis`: clears the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis. If a saved cache uses an unsupported schema,
  the Inspector shows `Cache Unsupported - Run Host Analysis`; if a supported-schema cache has
  incomplete prepared paths, it shows `Cache Incomplete - Run Host Analysis`. The file remains
  on disk and the next start requests new analysis for the current build.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared` in `Host Analysis Status`.
- `Host Analysis Status`: read-only analysis/cache state. It appends the current FxPlug
  runtime version when Final Cut Pro accepts status parameter updates.
- `Stabilizer Info`: scrollable read-only Inspector value showing the loaded FxPlug
  version, active correction bands (`Footstep jitter <= 1s`, `Stride wobble <= 2s`,
  `Walking Bob <= 2.5s`, `Far-field Warp <= 1s`, and `Turn Smoothing`), plus latest
  analysis time, frame count, actual sample image size, source frame size, and pixel
  transform scale when analysis is available. Older saved timeline instances may keep
  stale saved Inspector strings, so use the compact runtime-version row in `Debug Overlay`
  to confirm the active render runtime.
- `Debug Overlay`: normally off. When enabled, the labeled top-left bars show `X`, `Y`,
  `ROLL`, `FJIT`, `SWOB`, `BOB`, `WARP`, `TURN`, confidence (`F Q`, `S Q`, `B Q`, `W Q`,
  `T Q`), `SMTH`, tracking-quality (`TRK`, `SHRP`, `RES`, `HIT`), and compact
  runtime-version diagnostics so Final Cut Pro runtime analysis can be checked. These labels are raw English control/diagnostic
  abbreviations and should not be translated in the preview. It also writes current FxPlug version and render
  correction values into `Host Analysis Status`, including tracking/motion quality, turn
  confidence, applied warp confidence, edge-hit counts, and the Y correction split into footstep,
  stride, and walking-bob components.
  The labels mean:
  `X` final horizontal correction,
  `Y` final vertical correction,
  `ROLL` final roll correction,
  `FJIT` Footstep Jitter correction activity from the fixed second-based impulse range,
  `SWOB` Stride Wobble correction activity from the fixed internal stride-wobble window,
  `BOB` Y-only Walking Bob,
  `WARP` Far-field Warp correction activity from shear, yaw/pitch proxy, and perspective trim,
  `TURN` X-only Turn Smoothing,
  `SMTH` temporal smoothing delta,
  `F Q` Footstep Jitter confidence,
  `S Q` Stride Wobble confidence,
  `B Q` Walking Bob confidence,
  `W Q` applied Far-field Warp confidence after tracking and search-radius safety gates,
  `T Q` Turn Smoothing confidence,
  `TRK` current frame tracking quality,
  `SHRP` frame sharpness/clarity quality where higher means less blur,
  `RES` residual quality where higher means lower block-matching error, and
  `HIT` search-radius headroom quality where higher means fewer searches hit the radius edge.
  `TRK`, `SHRP`, `RES`, and `HIT` all use the same high-is-good direction.

## Feedback CLI

Use `scripts/stabilizer_feedback.sh` to compare a review note against the saved
Host Analysis cache without launching Final Cut Pro:

```sh
scripts/stabilizer_feedback.sh --time 5.0 --note "notable unremoved shake"
```

Run `scripts/stabilizer_feedback.sh --list-caches` to inspect saved cache
readiness before assessing a note. It lists the latest shared cache and
range-specific files as `READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE`
without repairing or deleting them; `--cache-root /path/to/root` inspects an
explicit alternate root.

`--time` is clip-relative to the saved Host Analysis range. The tool ranks likely
remaining `FJIT`, `SWOB`, `BOB`, `TURN`, and `WARP` bands from the prepared
motion paths and tracking diagnostics. It uses the same footstep-first band
split as render, so `SWOB`, `BOB`, and `TURN` diagnostics are computed from the
footstep-cleaned path rather than the raw footstep path. `WARP` `q` matches the
applied `W Q` confidence shown by Debug Overlay. The report includes strict and walking-band
tracking confidence, FJIT per-axis and SWOB per-axis confidence, BOB tracking/window support, residual quality, blur quality, block coverage, edge quality, and WARP
tracking/edge gate values so gating causes are visible. It fails visibly on unsupported or
mismatched cache data instead of repairing it; rerun Host Analysis with the
current FxPlug when that happens.
