# Stabilizer FxPlug

FxPlug 4 source for the native Final Cut Pro / Motion `Tokyo Walking Stabilizer` effect.

This project is FxPlug-only. Do not add separate automation runtime files, standalone
estimators, or Transform-keyframe writers back into this target.

## Current Scope

- Adds an FxPlug 4 tileable effect named `Tokyo Walking Stabilizer`.
- Uses Metal to render a transformed source texture.
- Exposes auto stabilization controls without manual transform trim parameters.
- Renders from prepared analysis written by the local Stabilizer Event Analyzer support tool. New
  effect instances do not expose `Sample Size`, `Start Host Analysis`,
  `Clear Host Analysis Cache`, or `Queue`, and render callbacks do not auto-start analysis.
- Reads completed analysis frame sets from the active Final Cut Pro `.fcpbundle`, scoped to
  the Event that owns the current project/media folder. The cache lives under
  `Analysis Files/TokyoWalkingStabilizerHostAnalysis/` so analysis files are unique to that
  Event and are not exposed as top-level library content. If the host reports a library temp
  folder, the resolver uses a single Event with `Analysis Files`, or a unique Final Cut Pro
  `Analysis Files/Stabilization` range match when multiple Events are candidates.
- Reuses saved analysis across FxPlug runtime version updates when the cache schema,
  exact analyzed source range, sample size, saved fingerprints, and current source-frame
  validation still match. Unsupported schema candidates are reported in the Inspector and
  left on disk.
- Stores prepared motion paths, frame timing, blur values, search-radius edge-hit counts,
  and fingerprints in new
  persistent cache files instead of embedding every frame's luma sample in JSON.
- Uses schema 19 chunked frame fingerprints and higher precision block motion evidence for
  persisted-cache validation, while keeping compatible schema 17/18 caches readable.
- Reuses persisted analysis only after the current source frame validates against saved
  frame fingerprints.
- Maps trimmed-clip render time back to Host Analysis time by matching the current render
  frame fingerprint against the analyzed frame set before sampling prepared motion paths.
  If Final Cut Pro reports a render/timeline range that differs from the saved source
  analysis range, render accepts the active cache only after that source-frame fingerprint
  validation succeeds.
- Refuses proxy-scaled frames for unvalidated persisted-cache validation. Once original-media
  validation succeeds, proxy playback can render from the prepared analysis path.
- Renders from prepared motion paths instead of re-running block matching on every frame.
- Combines per-frame Footstep Jitter, fixed-window Stride Wobble, Far-field Warp, and
  broader Turn Smoothing bands so walking-gimbal shake is separated by
  time scale without rerunning Host Analysis. Footstep Jitter keeps the current render
  frame's raw impulse after `1.20` second zero-phase smoothing; Far-field Warp uses a
  shorter `0.36` second in-range smoothing window so ridge-line correction stays responsive.
  Clip-edge smoothing skips out-of-range neighboring samples instead of duplicating the first
  or last analysis frame.
- New schema 19 analysis writes higher precision prepared paths from denser far-field
  motion blocks and sub-pixel block shift refinement while keeping older complete schema
  17/18 caches readable.
- `Remove Black Edges` is on by default and applies dynamic Auto Crop framing during
  render. Turning it off skips Auto Crop window sampling and framing entirely, so
  `Edge Display Mode` directly switches preview edges between stretched source edges and
  black outside-source pixels. New effect instances default `Edge Display Mode` to
  `Black Outside`.
- Updates a hidden render revision parameter when persisted cache state changes so Final
  Cut Pro refreshes the preview from the prepared motion paths.
- Monitors the bundle-local persistent cache location from render/preview instances and
  publishes that hidden revision when the local analyzer writes a compatible cache.
- Publishes cache-monitor status/info/render revision updates from
  the FxPlug main queue so Final Cut Pro invalidates stale preview frames.
- Keeps rejected cache candidates on disk for other clips.
- Requests only the current render frame through `scheduleInputs`; stabilization is driven
  by prepared analysis paths.
- Shows `Project Bundle Cache Unavailable` instead of falling back to a shared user cache
  when the runtime cannot resolve a writable Event `Analysis Files` cache root. If Final Cut
  Pro reports a library temp folder instead of an Event folder, the runtime uses an
  unambiguous top-level Event resolver. If Final Cut Pro reports no media folder for a
  library saved without Collect Media, the runtime can use Final Cut Pro's active library
  bookmarks, try security-scoped resolution first, log regular-bookmark resolution when
  needed, start security-scoped access when the resolved URL grants it, and then run that same
  Event resolver. When multiple libraries are active, existing Final Cut Pro
  `Analysis Files/Stabilization` range names may disambiguate the Event only when the active
  Host Analysis range matches exactly one Event across active libraries. If no range match
  exists, the runtime may use Final Cut Pro's `FFSidebarModuleLibrary` media sidebar selection
  only when its UUIDs match one active library and resolve to an existing top-level Event
  through `CurrentVersion.flexolibrary`; stale import-target UUIDs are not used. Multiple active libraries with no unique selected Event, unreadable active-library state, unwritable Event roots, and ambiguous
  Events fail visibly instead of writing to a shared fallback, including
  `Project Bundle Cache Unavailable - Ambiguous Event`.
- Estimates low-resolution global X/Y motion and roll from requested frames.
- Is tuned for walking-gimbal footage: the render path corrects softened X/Y translation,
  roll, and optional small-clamp Far-field Warp while keeping render scale fixed at 1.0.
- Includes a minimal wrapper app source/resource set under `WrapperApp/`.

The current effect implementation reads current render frames as Metal textures, validates
persisted analysis when original frames are available, and keeps CPU work limited to
orchestration, smoothing math, validation, and cache JSON I/O.

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
  -project fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj \
  -scheme TokyoWalkingStabilizer \
  -configuration Debug \
  -derivedDataPath /tmp/TokyoWalkingStabilizerDerived \
  build
```

The `TokyoWalkingStabilizer` shared scheme runs a build post-action after every successful build.
It installs a persistent copy of the Debug app to:

```text
/Applications/TokyoWalkingStabilizer.app
```

and registers the embedded FxPlug with PluginKit and LaunchServices. If Final Cut Pro is
already running during a rebuild, restart Final Cut Pro before checking for the updated
effect in the Effects browser.

The intermediate Debug app is written to:

```text
/tmp/TokyoWalkingStabilizerDerived/Build/Products/Debug/TokyoWalkingStabilizer.app
```

The app embeds:

```text
Contents/PlugIns/TokyoWalkingStabilizer XPC Service.pluginkit
```

To rerun the install/registration step without rebuilding:

```sh
fxplug/TokyoWalkingStabilizer/scripts/install_debug_app.sh \
  /tmp/TokyoWalkingStabilizerDerived/Build/Products/Debug/TokyoWalkingStabilizer.app
```

## Stabilization Model

- `Footstep Jitter X Strength`: direct amount for horizontal frame-local footstep correction.
  The default is `5.0`; values above `1.0` can compensate for weak frame confidence but are
  clamped during render to avoid inverse shake. The maximum is `10.0`. The walking-band confidence response is more
  assertive than TURN and WARP for medium-confidence frame evidence, but zero confidence
  still produces zero correction.
  Confidence also checks local baseline support and surrounding footstep noise, with the
  surrounding-noise floor capped below full response so repeated walking motion does not bury
  a real center-frame landing impulse.
- `Footstep Jitter Y Strength`: direct amount for vertical frame-local footstep correction.
  The default is `5.0`, and the maximum is `10.0`.
  Footstep Jitter uses a seconds-based outer-frame linear prediction that skips the center
  `0.10` second shock region and predicts from outer samples up to `1.0` second away for
  X/Y/rotation, so landing shock is treated as a frame-level impulse instead of being
  averaged back into the smooth path. Moderate landing impulses now reach useful confidence
  a little sooner, while zero evidence and noisy unsupported frames still produce zero
  correction.
- `Footstep Jitter Rotation Strength`: direct amount for roll footstep correction. It
  defaults to `0.2` to protect the horizon in walking footage. Values above `1.0` can
  compensate when frame-local confidence makes the detected impulse visibly under-corrected,
  but output remains clamped at full detected-impulse removal.
- `Stride Wobble X/Y/Rotation Strength`: direct amount for medium-period walking wobble. The
  render-time window is fixed at `2.0` seconds; there is no user-facing SWOB window. It is
  measured from the footstep-cleaned path, not the raw or jerk-limited broad path, so it does
  not erase FJIT twice. Residual gating uses robust window percentiles instead of the single
  worst frame. Medium SWOB bands reach full confidence earlier than the broad control scale.
  X and Y default to `5.0` and run up to `10.0`; the rotation default is `0.2` to protect
  the horizon while step follow-through is handled by the stride stage. FJIT and SWOB use a
  count-aware walking-band tracking gate; WARP and TURN keep the stricter tracking gate.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- `Far-field Warp Strength`: bundled small-clamp WARP correction for distant ridge-line
  shake. It uses a `0.10`/`1.0` second outer-frame linear warp baseline and applies shear,
  yaw/pitch proxy, and perspective trim from the current frame's local deviation. Render
  gates warp with walking-footage tracking quality and search-radius headroom, starts the
  tracking gate early enough for moderate 25% Host Analysis evidence, reaches full response
  more gradually, uses short local tracking support and a `0.36` second render smoothing
  window to reduce single-frame gate flicker, then
  applies a tiny deadband and small render-only clamps so weak frames do not create wave-like
  image distortion. Render-time window lookup uses the sorted Host Analysis times directly,
  so long prepared caches do not require repeated full-cache scans during playback.
- `Turn Smoothing Strength`: controls large segmented walking turns in X translation only.
  It does not change Y or roll, and the macro correction is soft-limited to a small
  output-edge budget.
- `Turn Detection Window`: centered TURN window evaluated during render against prepared
  motion paths. The UI value is used as the TURN window, and the UI minimum is the fixed
  `2.0` second Stride Wobble window so TURN cannot run shorter than SWOB.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available. The render
  path accepts the active range-matched cache identity in this state even before Final Cut Pro
  returns the hidden cache identity parameter. If a stale saved identity points at a different
  range, render drops it and reloads a compatible saved cache in the same callback before
  giving up, then keeps the hidden preview revision, `Host Analysis Status`, and `Stabilizer
  Info` current so Final Cut Pro shows the stabilized proxy preview and reports
  `Original Analysis - Proxy Preview` without switching back to original media first. If
  Final Cut Pro still reports an older hidden revision value, the runtime retries publishing
  the current token instead of treating a plug-in-local publish record as enough.
  When original-media validation maps a trimmed timeline render time back to the analyzed
  source time, the runtime saves that offset with the Host Analysis cache identity so
  proxy-only render instances can sample the same prepared motion path.
  When Final Cut Pro reports a different render/timeline duration during scaled/proxy
  playback, a range-mismatched active cache is used for preview only if the saved start
  matches the current clip and the render time is inside the saved analysis range.
  Proxy/scaled media is detected when the source pixel transform differs from original
  `1.0x/1.0x` in either direction, so reduced-resolution proxy frames do not validate
  against and reject a good original-media cache.
- If Final Cut Pro is set to proxy playback but the proxy file is missing, render receives
  the Missing Proxy placeholder rather than original footage. The plug-in reports
  `Source Media Unavailable - Check FCP Proxy`, keeps the saved cache intact, and suppresses
  Debug Overlay diagnostics over the placeholder. Switch Viewer playback to
  Original/Optimized or create proxy media to inspect the stabilized image.
- `Edge Display Mode`: defaults to `Black Outside` and chooses whether transformed pixels
  outside the source image stretch edge pixels or draw black.
- The effect uses prepared analysis from the local Event Analyzer support tool. Incomplete or missing
  persisted analysis renders identity for that source instead of silently switching modes.
  Proxy media is rejected for unvalidated persisted-cache validation, but a validated
  analysis continues to render during proxy playback.
- `Debug Overlay` shows labeled top-left diagnostics while checking runtime behavior.
- Existing timeline instances from older builds may still contain hidden `Start Host
  Analysis`, `Clear Host Analysis Cache`, `Sample Size`, or `Queue` parameters. New effect
  instances do not publish them. The old Start button only reloads a compatible persisted
  cache; it does not request a new Final Cut Pro Host Analysis run. The old Clear button does
  not delete Event Analyzer cache files and reports `External Cache Managed - Use Event
  Analyzer`.
- `Remove Black Edges`: default on. Applies dynamic Auto Crop framing so stabilized
  frames avoid outside-source pixels. Turn it off to bypass Auto Crop crop-safe
  framing while checking playback cost; `Edge Display Mode`
  then decides whether outside-source pixels are stretched or black.
- `Auto Crop Transition Duration`: default `5` seconds, range `0...30` seconds. This is the
  actual S-curve transition time for unified zoom and position framing. Longer values begin
  the crop adjustment earlier, retain recent high zoom demands while releasing, and make the
  visible framing change slower. With `Remove Black Edges` on, final zoom is still clamped to
  the current frame's required safe crop so outside-source black is not exposed during the
  transition. High-quality render uses the full 17-sample Auto Crop lead window; proxy,
  low/medium-quality playback, or scaled preview uses a very light non-quantized
  zoom-only lead profile so playback keeps the stabilizer motion visible without the
  old coarse zoom-envelope steps.
- `Host Analysis Status`: read-only analysis/cache state. It appends the current FxPlug
  runtime version when Final Cut Pro accepts status parameter updates. `Persisted Analysis
  Loaded` and `Ready (... frames)` mean the effect is using a completed Event Analyzer cache.
  Missing or unusable caches show `External Analysis Required - Run Event Analyzer`,
  `Cache Unsupported - Run Event Analyzer`, `Cache Incomplete - Run Event Analyzer`, or
  `Cache Rejected - Run Event Analyzer`.
- `Sample Info`: read-only Inspector row built from the structured cache snapshot as
  `Sample: <percent or unknown> -> <WxH> | Analysis: <N>f`. It does not fall back to hidden
  `Sample Size` or parse status strings. `Clip Range` and `Queue` are deprecated from the
  visible Inspector metadata. Older saved timeline instances may keep stale saved Inspector
  strings, so use the compact runtime/source row in `Debug Overlay` to confirm the active
  render runtime.
- `Debug Overlay`: normally off. When enabled, the labeled top-left bars show `X`, `Y`,
  `ROLL`, `FJIT`, `SWOB`, `WARP`, `TURN`, confidence (`F Q`, `S Q`, `W Q`,
  `T Q`), `SMTH`, tracking-quality (`TRK`, `SHRP`, `RES`, `HIT`), walking-band gate `WLK`, and compact
  runtime/source diagnostics so Final Cut Pro runtime analysis can be checked. `R361` means
  FxPlug `0.3.61` is rendering original/optimized frames, and `P361` means proxy playback is
  using the saved Host Analysis path. The overlay scales from the current render output with
  a lower proxy minimum so proxy playback keeps roughly the same viewer footprint as original
  media, while staying larger than the old compact panel. These labels are raw English control/diagnostic
  abbreviations and should not be translated in the preview. It also writes current FxPlug version and render
  correction values into `Host Analysis Status`, including strict tracking, walking-band tracking, motion quality, turn
  confidence, applied warp confidence, edge-hit counts, and the Y correction split into footstep,
  and stride components.
  The labels mean:
  `X` final horizontal correction,
  `Y` final vertical correction,
  `ROLL` final roll correction,
  `FJIT` Footstep Jitter correction activity from the fixed second-based impulse range,
  `SWOB` Stride Wobble correction activity from the fixed internal stride-wobble window,
  `WARP` Far-field Warp correction activity from shear, yaw/pitch proxy, and perspective trim,
  `TURN` X-only Turn Smoothing,
  `SMTH` temporal smoothing delta,
  `F Q` Footstep Jitter confidence,
  `S Q` Stride Wobble confidence,
  `W Q` applied Far-field Warp confidence after tracking and search-radius safety gates,
  `T Q` Turn Smoothing confidence,
  `WLK` walking-band tracking gate for FJIT/SWOB,
  `TRK` current frame tracking quality,
  `SHRP` frame sharpness/clarity quality where higher means less blur,
  `RES` residual quality where higher means lower block-matching error, and
  `HIT` search-radius headroom quality where higher means fewer searches hit the radius edge.
  `TRK`, `SHRP`, `RES`, and `HIT` all use the same high-is-good direction.

## Feedback CLI

Use `scripts/stabilizer_feedback.sh` to compare a review note against the saved
Host Analysis cache without launching Final Cut Pro:

```sh
scripts/stabilizer_feedback.sh \
  --cache "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json" \
  --time 5.0 \
  --note "notable unremoved shake"
```

Run `scripts/stabilizer_feedback.sh --list-caches --cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"`
to inspect saved cache readiness before assessing a note. It lists the latest bundle cache
and range-specific files as `READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE`
without repairing, promoting, or deleting them.

`--time` is clip-relative to the saved Host Analysis range. The tool ranks likely
remaining shake from the prepared motion paths and tracking diagnostics, then
prints `FJIT`, `SWOB`, `WARP`, and `TURN` in render-stage order. Pass
`--turn-window` when the Inspector `Turn Detection Window` is not the default `6.0`.
It uses the same footstep-first band split as render, so `SWOB` and `TURN`
diagnostics are computed from the footstep-cleaned path rather than the raw footstep path. `WARP` `q` matches the
applied `W Q` confidence shown by Debug Overlay. The report includes strict and walking-band
tracking confidence, FJIT per-axis and SWOB per-axis confidence, residual quality, blur quality, block coverage, edge quality, stable WARP tracking support, and WARP
tracking/edge gate values so gating causes are visible. It fails visibly on unsupported or
mismatched cache data instead of repairing it; rerun Host Analysis with the
current FxPlug when that happens.
