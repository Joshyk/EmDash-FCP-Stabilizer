# Stabilizer FxPlug

FxPlug 4 source for the native Final Cut Pro / Motion `Tokyo Walking Stabilizer` effect.

This project is FxPlug-only. Do not add separate automation runtime files, standalone
estimators, or Transform-keyframe writers back into this target.

## Current Scope

- Adds an FxPlug 4 tileable effect named `Tokyo Walking Stabilizer`.
- Uses Metal to render a transformed source texture.
- Exposes auto stabilization controls without manual transform trim parameters.
- Always uses Final Cut Pro's FxPlug Host Analysis infrastructure, requesting a
  forward GPU analysis, then using Metal compute in the plug-in runtime to downsample luma
  samples and run frame-to-frame block matching while preparing the motion paths. Metal
  analysis failures are reported as Host Analysis failures instead of silently falling back
  to CPU analysis.
- Persists completed Host Analysis frame sets inside the active Final Cut Pro `.fcpbundle`,
  scoped to the Event that owns the current project/media folder. The cache lives under
  `Analysis Files/TokyoWalkingStabilizerHostAnalysis/` so analysis files are unique to that Event
  and are not exposed as top-level library content. If the host reports a library temp folder,
  the resolver uses a single Event with `Analysis Files`, or a unique Final Cut Pro
  `Analysis Files/Stabilization` range match when multiple Events are candidates.
- Reuses saved Host Analysis across FxPlug runtime version updates when the persisted analysis schema,
  exact analyzed source range, sample size, saved fingerprints, and current source-frame
  validation still match. Unsupported schema candidates are reported in the Inspector and
  left on disk.
- Streams in-progress Host Analysis motion directly through Metal and keeps only the
  previous luma buffer needed for the next frame-to-frame motion search. It does not write
  per-frame `.luma` scratch files.
- Isolates concurrent in-progress Host Analysis callbacks with a process-wide session
  registry, so different clips and actual sample sizes do not share a streaming builder.
  Ambiguous callbacks fail visibly instead of being appended to an arbitrary active clip.
- Stores prepared motion paths, frame timing, blur values, search-radius edge-hit counts,
  and fingerprints in new
  persisted analysis files instead of embedding every frame's luma sample in JSON.
- Reuses persisted analysis only after the current source frame validates against saved
  frame fingerprints.
- Maps trimmed-clip render time back to Host Analysis time by matching the current render
  frame fingerprint against the analyzed frame set before sampling prepared motion paths.
  If Final Cut Pro reports a render/timeline range that differs from the saved source
  analysis range, render accepts the active persisted analysis only after that source-frame fingerprint
  validation succeeds.
- Refuses proxy-scaled frames for Host Analysis. Analysis is always based on original
  media; switch Final Cut Pro back to original media before starting Host Analysis.
- Renders from prepared motion paths instead of re-running block matching on every frame.
- Combines per-frame Footstep Jitter, fixed-window Stride Wobble, Far-field Warp, and
  broader Turn Smoothing bands so walking-gimbal shake is separated by
  time scale without rerunning Host Analysis. Footstep Jitter keeps the current render
  frame's raw impulse after `1.20` second zero-phase smoothing; Far-field Warp uses a
  shorter `0.36` second in-range smoothing window so ridge-line correction stays responsive.
  Clip-edge smoothing skips out-of-range neighboring samples instead of duplicating the first
  or last analysis frame.
- `Remove Black Edges` is on by default and applies dynamic Auto Crop framing during
  render. Turning it off skips Auto Crop window sampling and framing entirely, so
  `Edge Display Mode` directly switches preview edges between stretched source edges and
  black outside-source pixels. New effect instances default `Edge Display Mode` to
  `Black Outside`.
- Updates a hidden render revision parameter when Host Analysis/persisted-analysis state changes so Final
  Cut Pro refreshes the preview from the prepared motion paths.
- Monitors the bundle-local persisted analysis location from render/preview instances and
  publishes that hidden revision when an analyzer instance in another process finishes a
  compatible persisted analysis.
- Publishes analyzer-completion and persisted-analysis-monitor status/info/render revision updates from
  the FxPlug main queue so Final Cut Pro invalidates stale preview frames.
- Shares the in-process Host Analysis store across FxPlug analyzer/render instances so a
  completed analysis can drive smoothing in playback.
- Keeps rejected persisted analysis candidates on disk for other clips.
- Requests only the current render frame through `scheduleInputs`; stabilization is driven
  by prepared Host Analysis paths.
- Shows `Project Persisted Analysis Unavailable` instead of falling back to a shared user location
  when the runtime cannot resolve a writable Event `Analysis Files` persisted analysis root. A live Final
  Cut Pro Host Analysis pass may still complete in memory as `Ready Memory Only - Project
  Persisted Analysis Unavailable`; that result can drive the current viewer/render session, but it
  is only persisted later if the Event persisted analysis root becomes available. If Final Cut Pro reports
  a library temp folder instead of an Event folder, the runtime uses an unambiguous top-level
  Event resolver. If Final Cut Pro reports no media folder for a library saved without
  Collect Media, the runtime can use Final Cut Pro's active library bookmarks, try
  security-scoped resolution first, log regular-bookmark resolution when needed, start
  security-scoped access when the resolved URL grants it, and then run that same Event
  resolver. When multiple libraries are active, existing Final Cut Pro
  `Analysis Files/Stabilization` range names may disambiguate the Event only when the active
  Host Analysis range matches exactly one Event across active libraries. If no range match
  exists, the runtime may use Final Cut Pro's `FFSidebarModuleLibrary` media sidebar selection
  only when its UUIDs match one active library and resolve to an existing top-level Event
  through `CurrentVersion.flexolibrary`; stale import-target UUIDs are not used. Multiple active libraries with no unique selected Event, unreadable active-library state, unwritable Event roots, and ambiguous
  Events fail visibly instead of writing to a shared fallback, including
  `Project Persisted Analysis Unavailable - Ambiguous Event`.
- Estimates low-resolution global X/Y motion and roll from requested frames.
- Is tuned for walking-gimbal footage: the render path corrects softened X/Y translation,
  roll, and optional small-clamp Far-field Warp while keeping render scale fixed at 1.0.
- Includes a minimal wrapper app source/resource set under `WrapperApp/`.

The current implementation reads host frames as Metal textures, performs analysis
downsampling and shift scoring on Metal, and keeps CPU work limited to orchestration, small
result reduction, smoothing math, validation, and persisted analysis JSON I/O.

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
  The default is `1.0`; values above `1.0` can compensate for weak frame confidence but are
  clamped during render to avoid inverse shake. The walking-band confidence response is more
  assertive than TURN and WARP for medium-confidence frame evidence, but zero confidence
  still produces zero correction.
  Confidence also checks local baseline support and surrounding footstep noise, with the
  surrounding-noise floor capped below full response so repeated walking motion does not bury
  a real center-frame landing impulse.
- `Footstep Jitter Y Strength`: direct amount for vertical frame-local footstep correction.
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
  worst frame. Medium SWOB bands reach full confidence earlier than the broad control scale,
  the Y default is `0.70`, and the rotation default is `0.2` to protect the horizon while
  step follow-through is handled by the stride stage. FJIT and SWOB use a
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
  so long prepared persisted analyses do not require repeated full-analysis scans during playback.
- `Turn Smoothing Strength`: controls large segmented walking turns in X translation only.
  It does not change Y or roll, and the macro correction is soft-limited to a small
  output-edge budget.
- `Turn Detection Window`: centered TURN window evaluated during render against prepared
  motion paths. The UI value is used as the TURN window, and the UI minimum is the fixed
  `2.0` second Stride Wobble window so TURN cannot run shorter than SWOB.
- `Sample Size`: analysis image size as a percentage of the original clip dimensions.
  Options are `100%`, `75%`, `50%`, `25%`, and `10%`; the default is `100%` for full source
  detail. Choose a smaller value only when you want a faster debug pass. Host Analysis reads
  this value once when the analysis pass starts. The actual pixel size and frame count are
  shown in `Sample Info`.
- If a saved Host Analysis persisted analysis is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded persisted analysis immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available. The render
  path accepts the active range-matched persisted analysis identity in this state even before Final Cut Pro
  returns the hidden persisted analysis identity parameter. If a stale saved identity points at a different
  range, render drops it and reloads a compatible saved persisted analysis in the same callback before
  giving up, then keeps the hidden preview revision, `Host Analysis Status`, and `Stabilizer
  Info` current so Final Cut Pro shows the stabilized proxy preview while continuing to
  report the original-media analysis as ordinary ready/persisted-analysis-loaded analysis. If
  Final Cut Pro still reports an older hidden revision value, the runtime retries publishing
  the current token instead of treating a plug-in-local publish record as enough.
  When original-media validation maps a trimmed timeline render time back to the analyzed
  source time, the runtime saves that offset with the Host Analysis persisted analysis identity so
  proxy-only render instances can sample the same prepared motion path.
  When Final Cut Pro reports a different render/timeline duration during scaled/proxy
  playback, a range-mismatched active persisted analysis is used for preview only if the saved start
  matches the current clip and the render time is inside the saved analysis range.
  Proxy/scaled media is detected when the source pixel transform differs from original
  `1.0x/1.0x` in either direction, so reduced-resolution proxy frames do not validate
  against and reject a good original-media persisted analysis.
- If Final Cut Pro is set to proxy playback but the proxy file is missing, render receives
  the Missing Proxy placeholder rather than original footage. The plug-in reports
  `Source Media Unavailable - Check FCP Proxy`, keeps the saved persisted analysis intact, and suppresses
  Debug Overlay diagnostics over the placeholder. Switch Viewer playback to
  Original/Optimized or create proxy media to inspect the stabilized image.
- `Edge Display Mode`: defaults to `Black Outside` and chooses whether transformed pixels
  outside the source image stretch edge pixels or draw black.
- Host Analysis is always used. It requests GPU analysis frames from the host. Incomplete
  host analysis renders identity for that source instead of silently switching modes.
  Proxy media is rejected for Host Analysis input and for unvalidated persisted-cache
  validation, but a validated analysis continues to render during proxy playback.
  Completed persisted analysis writes use the prepared analysis frame set as the authoritative timeline,
  so a reduced retained source-frame map does not block persistence.
- `Debug Overlay` shows labeled top-left diagnostics while checking runtime behavior.
- `Start Host Analysis`: clears the current in-memory host-analysis frames, reloads a saved
  persisted analysis only when it matches the current clip range, selected `Sample Size`, and
  actual analysis pixel size when source dimensions are already known, and asks Final Cut Pro
  to start a forward GPU analysis when no matching persisted analysis can be loaded. Saved
  persisted analysis files remain available for later reuse, so changing `Sample Size` makes
  the button analysis-runnable again while preserving the previous pixel-size result. If the
  previous persisted analysis was rejected for the current clip,
  the next start skips that rejected file and requests a new analysis. If the button callback cannot see `FxProjectAPI`,
  it still requests Host Analysis and lets analyzer `setupAnalysis` resolve the Event persisted analysis
  root through either the host media folder or, when Collect Media is off, Final Cut Pro's
  active library bookmarks and the same Event resolver. If setup still cannot resolve a writable Event persisted analysis root,
  the analyzer finishes the active pass in memory only and the Inspector shows `Ready Memory
  Only - Project Persisted Analysis Unavailable` after completion until a later callback can
  resolve the Event persisted analysis root and save the completed result. The installed plug-in bundle is
  signed with sandbox, security-scoped file entitlements, and a read-only home-relative
  exception for Final Cut Pro's preference plist so the Host Analysis runtime can open the
  `FxProjectAPI.mediaFolderURL()` security-scoped URL when Final Cut Pro provides one, or
  read the active library bookmark when Final Cut Pro reports no media folder. Active library
  bookmarks are resolved with security scope first, then resolved as regular bookmarks with
  visible logs when Final Cut Pro stored a regular bookmark; access is retained only when the
  resolved URL grants a security-scoped lease. The debug-signed bundle also carries explicit
  read-write entitlements for the shared local test fixture libraries so Codex-driven FCP tests
  can persist Event-scoped caches when Final Cut Pro exposes only a regular active-library
  bookmark. For this local editing setup, it also carries a read-write exception for
  `/Volumes/WDBLUE1TB/` so regular active-library bookmarks for external libraries can still
  be inspected and saved inside their Event-scoped `.fcpbundle` persisted analysis roots. The in-progress
  Host Analysis
  session registry is process-wide and contains per-session stores, so setup, frame
  analysis, and cleanup callbacks can arrive through different FxPlug instances without
  losing or mixing the active analysis session. If a saved persisted analysis uses an unsupported schema,
  the Inspector shows `Persisted Analysis Unsupported - Run Host Analysis`; if a supported-schema persisted analysis has
  incomplete prepared paths or too few frames for its saved analysis range, it shows
  `Persisted Analysis Incomplete - Run Host Analysis`. The file remains on disk and the next start
  requests new analysis for the current build. Those stale unusable states do not block later
  preview/render consumers from rechecking the persisted analysis signature and loading a newly
  written compatible persisted analysis. If another Stabilizer Host Analysis run is active or reserved in
  the plug-in process, the request is kept in `Queued Host Analysis` until that run's cleanup
  callback finishes and a retry pass can hand the next queued request to Final Cut Pro.
  Pressing `Start Host Analysis` again on the same queued effect instance replaces that
  instance's older queued request, while requests for other effect instances stay queued.
  The queue keeps the
  `FxAnalysisAPI` obtained when Start was pressed, so retry drain does not need to reacquire
  it from a later callback context. If the Event persisted analysis root is unavailable and
  analysis completes memory-only, completed memory-only analyses are retained by analyzed
  timeline range plus sample/fingerprint identity for the current process so another queued
  clip does not discard the earlier clip's viewer result or collide with another clip that
  has the same source-time range.
- `Reanalyze Host Analysis`: explicitly ignores the currently loaded persisted analysis and
  requests a fresh Host Analysis using the current `Sample Size`. Existing persisted analysis
  files remain on disk; the newly completed analysis is saved as a new candidate.
- `Remove Black Edges`: default on. Applies dynamic Auto Crop framing so stabilized
  frames avoid outside-source pixels. Turn it off to bypass Auto Crop render-time
  sampling and binary-search framing while checking playback cost; `Edge Display Mode`
  then decides whether outside-source pixels are stretched or black.
- `Host Analysis Status`: read-only analysis/persisted-analysis state. It appends the current FxPlug
  runtime version when Final Cut Pro accepts status parameter updates. During a real analysis
  run, the status advances as `Analyzing Host Frames (N)`. If Final Cut Pro restores an
  in-progress analysis state while a compatible saved persisted analysis is already present, the plug-in
  prefers the saved persisted analysis and keeps the shared Ready/persisted-analysis status visible instead of letting
  transient analyzer callback status mask it. When the analyzer callback is the active
  state, `Host Analysis Status`, `Sample Info`, and `Queue` come from that same in-progress
  analysis store instead of mixing `Analyzing Host Frames (N)` with stale persisted analysis metadata
  from another clip. When `Start Host Analysis` is disabled because the viewer is currently
  using scaled/proxy media, the status stays actionable as
  `Ready (...) - Original Media Required to Start Analysis`. Range mismatches from stale
  persisted analysis candidates show `Persisted Analysis Range Mismatch - Run Host Analysis` and keep `Start Host
  Analysis` enabled. Start/Reanalyze button state is refreshed when the input range changes
  and periodically from plugin-state/render callbacks, so trim changes do not leave stale
  button flags behind.
- `Sample Info`: read-only Inspector row showing the actual analyzed pixel sample size and
  frame count, for example `Sample: 573x302 | Analysis: 10500f`. `Clip Range` is deprecated
  from the visible Inspector metadata. Older saved timeline instances may keep stale saved Inspector strings,
  so use the compact runtime/source row in `Debug Overlay` to confirm the active render
  runtime.
- `Queue`: read-only Inspector row showing the serial queue position as `#N of M` and
  compact queue reason while this clip is waiting. Repeated starts on the same effect
  instance keep only that instance's latest pending request.
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
Host Analysis persisted analysis without launching Final Cut Pro:

```sh
scripts/stabilizer_feedback.sh \
  --cache "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json" \
  --time 5.0 \
  --note "notable unremoved shake"
```

Run `scripts/stabilizer_feedback.sh --list-caches --cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"`
to inspect saved persisted analysis readiness before assessing a note. It lists the latest bundle persisted analysis
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
