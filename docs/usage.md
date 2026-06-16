# Usage

## Final Cut Pro

1. Build the FxPlug wrapper app.
2. Open Final Cut Pro after the install step completes.
3. Apply `Tokyo Walking Stabilizer` from the `Emdash Studios` effects group.
4. Click `Start Host Analysis` if the Inspector status says `Needs Analysis`,
   `Cache Rejected - Run Host Analysis`, `Cache Unsupported - Run Host Analysis`, or
   `Cache Incomplete - Run Host Analysis`.
5. Wait for `Host Analysis Status` to show `Ready (... frames)`.

`Start Host Analysis` requests the active effect clip from Final Cut Pro. If another
Stabilizer Host Analysis run is active or reserved in the plug-in process, the selected clip
enters `Queued Host Analysis` instead of being handed to Final Cut Pro immediately. The next
queued clip starts after the active run's cleanup callback finishes. Another clip's completed
analysis is not treated as completion for the queued clip.
Debug installs clean stale `Tokyo Walking Stabilizer copy...` Motion Template folders in the
`Emdash Studios` group so Final Cut Pro does not list duplicate Stabilizer effects.
The Debug scheme and install step fail if Final Cut Pro is running, because building or
replacing a loaded FxPlug can leave Final Cut Pro holding a stale PlugInKit object and
trigger `P1000307` helper communication errors.

## Optional UI Shortcuts

Use the shared workspace script `../scripts/fcp_stabilizer_shortcuts.applescript`
when binding helper actions in Keyboard Maestro, Automator Quick Actions, or
another keyboard shortcut runner:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript apply
osascript ../scripts/fcp_stabilizer_shortcuts.applescript start-analysis
osascript ../scripts/fcp_stabilizer_shortcuts.applescript toggle-debug-overlay
osascript ../scripts/fcp_stabilizer_shortcuts.applescript focus-inspector
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-selected-project
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-project "stab test - gh6"
osascript ../scripts/fcp_stabilizer_shortcuts.applescript select-playhead-clip
```

- `apply`: reveals the Effects Browser, searches `Tokyo Walking Stabilizer`, and
  presses the matching result for the selected clip.
- `start-analysis`: reveals the Inspector and presses `Start Host Analysis`.
- `toggle-debug-overlay`: reveals the Inspector and toggles `Debug Overlay`.
- `focus-inspector`: reveals or focuses the Inspector with Command-4.
- `open-project PROJECT_NAME`: opens a named Browser project through
  `Clip > Open Clip`.
- `open-selected-project`: opens the selected Browser project thumbnail or list
  row through `Clip > Open Clip`.
- `select-playhead-clip`: reselects the timeline clip under the playhead before
  analysis when focus has drifted to the Browser or search field.

The script uses Final Cut Pro Accessibility UI scripting. Grant Accessibility
permission to the app that runs it. If FCP's UI labels are different on the
current machine, run:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript dump-front-window
```

and use the printed roles/names to tune the script instead of adding hidden
fallbacks.

## Controls

- `Footstep Jitter X Strength`: direct amount for horizontal footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Values above `1.0` can push through weak
  frame evidence when the detected impulse is visibly under-corrected, but render output
  still clamps at full detected-impulse removal to avoid inverse shake.
- `Footstep Jitter Y Strength`: direct amount for vertical footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Footstep Jitter uses an outer-frame linear
  prediction with seconds-based windows: it skips the center `0.10` second shock region
  and predicts from outer samples up to `1.0` second away for X/Y/rotation, so footstep
  landing shock is treated as a frame-level impulse instead of being averaged back into the
  smooth path.
  Host Analysis builds that path from multiple Metal block-matched regions with outlier
  blocks rejected before render. Footstep Jitter is gated per frame from current tracking
  quality, block coverage, blur, and whether the center frame actually departs from its
  outer-frame baseline. The gate also requires local baseline support and compares the
  center-frame impulse against surrounding footstep noise, so one unsupported edge frame does
  not produce a strong correction by itself. Moderate landing impulses reach useful
  confidence a little sooner than the surrounding-noise floor, and that surrounding-noise floor
  is capped below the full-response point so repeated walking motion does not hide a real
  center-frame landing shock. Zero evidence remains zero. Walking-band correction eases block coverage only when enough blocks were accepted;
  Far-field Warp and Turn Smoothing keep the stricter gate. Values above `1.0` can compensate when that
  frame-local score makes the detected impulse visibly under-corrected, but render output
  still clamps at full detected-impulse removal to avoid inverse shake.
- `Footstep Jitter Rotation Strength`: direct amount for roll footstep-jitter correction. The
  default is `0.2` and the maximum is `4.0`. The default is intentionally conservative so
  walking footage does not lose a stable horizon. Values above `1.0` can compensate when
  frame-local confidence makes the detected impulse visibly under-corrected, but render
  output still clamps at full detected-impulse removal to avoid inverse shake.
- `Stride Wobble X Strength`: direct amount for medium-period horizontal walking wobble that
  is longer than Footstep Jitter but shorter than broad Turn Smoothing. The default is
  `0.65` and the maximum is `4.0`.
- `Stride Wobble Y Strength`: direct amount for medium-period vertical walking wobble. The
  default is `0.70`, so medium vertical follow-through is handled by the stride stage.
  Stride Wobble uses a fixed internal `2.0` second render-time window; there is no
  user-facing Stride Wobble window. Its residual gate uses robust window percentiles instead
  of the single worst residual in the window, and its confidence reaches full response
  earlier for detected medium bands than for broad pan/turn bands.
- `Stride Wobble Rotation Strength`: direct amount for medium-period roll wobble. The default
  is `0.2` and the maximum is `4.0`. The conservative default protects the horizon in
  walking footage. The correction is measured from the
  footstep-cleaned baseline and clamped at full detected-band removal during render, so high
  values do not add inverse shake. It is not measured from the raw or jerk-limited broad path,
  so Footstep Jitter shock is not removed a second time.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- Prepared Host Analysis motion paths are post-processed with a zero-phase jerk limiter
  before caching. It clamps isolated acceleration spikes in X/Y/roll while preserving the
  total analyzed path endpoint, so real panning is not delayed into a sliding path. Raw
  Footstep Jitter X/Y/roll impulse paths are saved separately before the limiter is applied,
  so fine frame-level shake remains available to render-time correction. Short analyzed
  ranges are kept in bounds during cleanup so the prepared cache can be saved.
- `Far-field Warp Strength`: bundled small-clamp correction for distant ridge-line shake. It
  uses upper-frame residual blocks to estimate deskew/shear, yaw/pitch proxy, and perspective
  trim after translation and roll are removed. Render uses only the current frame's local
  deviation from its own `0.10`/`1.0` second outer-frame linear warp baseline, so
  accumulated drift does not turn into a fixed deskew. The default is `1.0`, the maximum is
  `4.0`, and `0` fully disables warp. Render gates warp with walking-footage tracking
  quality and search-radius headroom. The tracking gate starts early enough for moderate
  25% Host Analysis evidence but reaches full response more gradually, uses short local
  tracking support to reduce single-frame gate flicker, then applies a tiny deadband so
  weak frames and high-side gate jumps do not create wave-like image distortion.
  Pull this down if close grass, roads, water, or frame edges start to swim.
- `Turn Smoothing Strength`: controls how strongly the stabilizer concatenates segmented
  walking turns in X translation only. It does not change Y or roll. At `0`, long-window turn
  correction is bypassed; the default is `1.0` and the maximum is `4.0`. Values above `1.0`
  push through low-confidence gating when stop-and-go panning is still visible, but render
  output still clamps at full detected turn-band removal. The turn intent is a monotonic
  S-curve through the detection window instead of a straight-line fit. The X turn band
  is measured from the stride-smoothed path instead of the raw frame path, so short landing
  shock and medium stride wobble are not reintroduced by turn smoothing. The macro X output
  correction is soft-limited to a small edge budget during render so large detected pans do
  not create stretched-edge jumps in the preview. TURN confidence requires both tracking
  evidence and a real X turn band, so low-evidence frames no longer receive a hidden minimum
  turn correction.
- `Turn Detection Window`: centered smoothing window for walking turns. In Host Analysis
  mode this is evaluated against prepared motion paths during render, so changing the slider
  does not require rebuilding analysis. The UI value is the TURN window, and the UI minimum
  is the fixed `2.0` second Stride Wobble window so TURN cannot run shorter than SWOB.
- `Remove Black Edges`: default on. Applies dynamic Auto Crop framing during render.
  Turn it off to skip Auto Crop window sampling and binary-search framing completely while
  checking playback cost; `Edge Display Mode` then directly controls outside-source pixels.
- `Sample Size`: analysis image size as a percentage of the original clip dimensions. The
  options are `100%`, `75%`, `50%`, `25%`, and `10%`. The default is `100%` for full source
  detail; choose a smaller value only when you want a faster debug pass. The actual pixel
  size and frame count are shown in `Sample Info`.
- `Edge Display Mode`: `Stretch Edges` keeps the previous preview behavior by extending
  edge pixels outside the transformed source image. `Black Outside` draws those outside
  pixels black so the viewer shows how far stabilization is moving the image. New effect
  instances default to `Black Outside`.
- `Start Host Analysis`: resets the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis. Rejected cache file names are remembered in
  the active FxPlug runtime so the same invalid candidate is not immediately reloaded again.
  If the button callback cannot see `FxProjectAPI`, the button still requests Host Analysis
  and lets the analyzer `setupAnalysis` callback resolve the Event cache root. When
  `FxProjectAPI.mediaFolderURL()` reports no media folder for a library saved without Collect
  Media, the resolver can use Final Cut Pro's active library bookmarks, try security-scoped
  resolution first, log regular-bookmark resolution when needed, start security-scoped access
  when the resolved URL grants it, and then apply the same Event selection rules. If
  setup still cannot resolve a writable Event cache root,
  the analyzer finishes the active pass in memory
  only and the Inspector shows `Ready Memory Only - Project Bundle Cache Unavailable` after
  completion until a later callback can resolve the Event cache root and save the completed
  result. The installed plug-in bundle is signed with sandbox, security-scoped file
  entitlements, and a read-only home-relative exception for Final Cut Pro's preference plist
  so the Host Analysis runtime can open the `FxProjectAPI.mediaFolderURL()` security-scoped
  URL when Final Cut Pro provides one, or read the active library bookmark when Final Cut Pro
  reports no media folder. The debug-signed bundle also carries explicit read-write
  entitlements for the shared local test fixture libraries so Codex-driven FCP tests can
  persist Event-scoped caches when Final Cut Pro exposes only a regular active-library bookmark. For
  this local editing setup, it also carries a read-write exception for `/Volumes/WDBLUE1TB/`
  so regular active-library bookmarks for external libraries can still be inspected and saved
  inside their Event-scoped `.fcpbundle` cache roots. The
  in-progress Host Analysis session registry is process-wide and
  contains per-session stores, so setup, frame analysis, and cleanup callbacks can arrive
  through different FxPlug instances without losing or mixing the active analysis session.
  If a saved cache uses an unsupported schema, the Inspector shows
  `Cache Unsupported - Run Host Analysis`; if a supported-schema cache has incomplete prepared
  paths or too few frames for its saved analysis range, the Inspector shows
  `Cache Incomplete - Run Host Analysis`. In both cases the file remains on disk and the
  button starts a new Host Analysis run for the current build.
- Persistent analysis reuse is based on cache schema and current source-frame validation,
  not the loaded FxPlug runtime version. Render-only runtime updates should reuse the saved
  Host Analysis cache.
- In-progress Host Analysis uses a per-clip session store, so requested clips and clips
  whose selected `Sample Size` resolves to different actual pixel dimensions do not share a
  streaming builder. If another Stabilizer Host Analysis is already active, or Final Cut Pro
  is already running Host Analysis when another clip is requested, that effect instance is
  queued and started after the host becomes available. The queue keeps queued requests for
  different effect instances, while repeated `Start Host Analysis` presses on the same
  queued effect instance replace that instance's older pending request. The queued request is
  retained until start or explicit clear, and
  completed analysis from the previous clip does not make the queued clip skip its own Host
  Analysis. Final Cut Pro may run the analysis callbacks on a different FxPlug instance than
  the Inspector button instance, so completion clears process-wide analysis bookkeeping
  before draining the latest queued request. The Inspector
  start path does not use plug-in-local active markers as the blocking authority; it asks
  Final Cut Pro's current analysis state and queues only when the host reports a
  busy/requested state. Queued starts still check Final Cut Pro's actual analysis state
  before starting, and the queued request keeps the `FxAnalysisAPI` obtained when Start
  was pressed so retry drain does not need to reacquire it from a later callback context.
  If the Event cache root is unavailable and analysis completes memory-only, the plug-in
  keeps completed memory-only analyses by analyzed timeline range plus sample/fingerprint
  identity for the current process so serial analysis of another clip does not discard the
  earlier clip's viewer result or collide with another clip that has the same source-time
  range.
  Completed analysis is then published to the process-wide shared render/cache store and
  persisted inside the current Final Cut Pro Event's `Analysis Files` cache root resolved
  from the host-provided media folder. The
  prepared analysis frame set is saved so analyzer and preview/render processes can hand
  off the prepared motion path through validated cache files. Preview/render instances also monitor the persisted bundle cache location and
  detect cache file changes even when they already hold an older prepared analysis, then
  reload candidates and update the hidden render revision without starting Host Analysis.
  A cache whose fingerprints do not match the current source frame is
  rejected instead of being accepted by time proximity alone. `Start Host Analysis` is the
  only path that requests Host Analysis from Final Cut Pro. Concurrent analyzer callbacks
  are routed through a process-wide session registry with per-clip in-progress stores; if a
  callback cannot be assigned unambiguously, the plug-in fails visibly instead of mixing
  frames between clips.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared`.
- `Host Analysis Status`: read-only status for analysis and cache reuse. It appends
  the current FxPlug runtime version when Final Cut Pro accepts status parameter
  updates. `Queued Host Analysis` means this clip is waiting for the plug-in's serial Host
  Analysis queue to hand it to Final Cut Pro after the currently active or reserved run
  finishes. Queue drain runs in retryable passes after analysis callbacks complete; if the
  host is still busy, the latest request remains queued and another pass is scheduled.
  During a real analysis run, the status advances as `Analyzing Host Frames (N)`.
  If Final Cut Pro restores an in-progress analysis state while a compatible saved cache is
  already present, the plug-in prefers the saved cache and keeps the shared Ready/cache
  status visible instead of letting transient analyzer callback status mask it. When the
  analyzer callback is the active state, `Host Analysis Status`, `Sample Info`, and
  `Queue` come from that same in-progress analysis store instead of mixing
  `Analyzing Host Frames (N)` with stale cache metadata from another clip.
- `Sample Info`: read-only Inspector row showing the actual analyzed pixel sample size and
  frame count, for example `Sample: 573x302 | Analysis: 10500f`. `Clip Range` is deprecated
  from the visible Inspector metadata.
- `Queue`: read-only Inspector row showing the serial queue position as `#N of M` and
  compact queue reason while this clip is waiting. Repeated starts on the same effect
  instance keep only that instance's latest pending request.
  Older saved timeline instances can keep stale saved Inspector strings, so check the
  compact runtime/source row in `Debug Overlay` when confirming the active render runtime.
- `Debug Overlay`: labeled top-left diagnostics for final `X`/`Y`/`ROLL`, `FJIT`, `SWOB`,
  `WARP`, `TURN`, live `F Q`/`S Q`/`W Q`/`T Q` confidence, plus `SMTH`,
  `TRK`, `SHRP`, `RES`, search-radius `HIT`, walking-band `WLK`, and compact runtime/source bars while
  checking runtime behavior. `R360` means FxPlug `0.3.60` is rendering original/optimized
  frames, while `P360` means proxy playback is using the saved Host Analysis path.
  The overlay scales from the current render output with a lower proxy minimum so proxy
  playback keeps roughly the same viewer footprint as original media, while staying larger than the old compact panel.
  `TRK`, `SHRP`, `RES`, and `HIT` are quality bars: higher is better and lower means weaker
  tracking evidence.
  Labels use raw English control/diagnostic abbreviations and should not be translated in the preview. When
  enabled, `Host Analysis Status` also shows the current FxPlug version, the raw center-frame transform, the
  smoothed transform delta, strict tracking, walking-band tracking, motion confidence, blur, residual, the raw `foot q`,
  the effective Footstep Jitter X/Y/R correction strength, `stride q`, the effective Stride
  Wobble X/Y/R correction strength, `turn q`, applied `warp q`, shear, yaw/pitch proxy, perspective,
  edge-hit counts, the X turn and stride components plus Y footstep and stride components.
- Strength values above `1.0` still compensate low-confidence Footstep and Stride Wobble
  detections. Those walking-band controls use a more assertive
  medium-confidence response than TURN and WARP, but zero confidence still produces zero
  correction.

## Feedback CLI

To turn a review note into diagnostics, run the cache-backed feedback tool:

```sh
fxplug/TokyoWalkingStabilizer/scripts/stabilizer_feedback.sh \
  --cache "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json" \
  --time 5.0 \
  --note "notable unremoved shake"
```

`--time` is clip-relative, so `5.0` means five seconds after the saved Host
Analysis range starts. For bundle-local caches, pass
`--cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"` or
`--cache` for a range-specific file under that root's `caches/` directory. Add
`--json` for structured output, `--window 0.5` to inspect the strongest frame near
the note, `--turn-window` to match a non-default Inspector `Turn Detection Window`, and
`--output-size 1920x1080` to scale translation estimates to a preview size.

Use `--list-caches` with the bundle cache root to inspect saved cache readiness before
diagnosing a note:

```sh
fxplug/TokyoWalkingStabilizer/scripts/stabilizer_feedback.sh --list-caches \
  --cache-root "/path/to/library.fcpbundle/Event Name/Analysis Files/TokyoWalkingStabilizerHostAnalysis"
```

The listing checks the latest bundle cache and range-specific cache files, reporting
`READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE`. It does not repair, delete, or
promote cache files.

The CLI does not inspect pixels or start Host Analysis. It reads saved prepared
paths and prints `FJIT`, `SWOB`, `WARP`, and `TURN` in render-stage order,
while the summary line names the highest remaining band. `FJIT` is measured against
the outer-frame baseline, then `SWOB` and `TURN` are measured from that
footstep-cleaned path. It prints strict tracking and walking-band tracking separately,
FJIT and SWOB per-axis confidence (`qX`, `qY`, `qR`) alongside
the raw impulse or band values. `WARP` `q` matches the applied `W Q` confidence shown by
Debug Overlay. With `--time`, the report picks the highest-score frame inside
the requested `--window` and prints both the requested note time and selected
clip time. The report also prints residual quality, blur quality, block coverage,
edge quality, stable WARP tracking support, and WARP tracking/edge gate values so conservative gating can be separated
from weak detected motion. If the cache was written by an older build with mismatched frame/path
arrays, it fails visibly and asks for a new Host Analysis run with the current
FxPlug.

## Behavior

- The effect does not write Final Cut Pro Transform keyframes.
- It estimates low-resolution multi-block X/Y motion, roll, and conservative far-field warp
  residuals from FxPlug-requested source frames.
- It is tuned for walking-gimbal footage. The render path corrects softened X/Y translation
  and roll, with optional small-clamp `Far-field Warp Strength` for deskew/shear, yaw/pitch
  proxy, and perspective/distort trim. This warp path is intentionally low because close
  foreground detail can otherwise swim or distort.
- It does not apply Z correction or zoom; render scale stays fixed at 1.0.
- The effect always uses Host Analysis. It asks Final Cut Pro to run a forward GPU
  analysis, uses Metal compute inside the FxPlug runtime to downsample source frames and
  run frame-to-frame block matching, stores prepared frame analysis inside the plug-in
  runtime, persists completed analysis inside the active `.fcpbundle` project cache, and
  renders from that analyzed frame set.
- Host Analysis reads `Sample Size` once when analysis starts. Long-clip analysis keeps the
  requested percentage of the original clip size and streams frame-to-frame motion directly
  through Metal while retaining only the previous luma buffer needed for the next motion
  search. It does not write per-frame `.luma` scratch files.
- Host Analysis refuses proxy-scaled frames. If Final Cut Pro supplies proxy media, the
  Inspector shows `Proxy Media Rejected - Use Original Media`; switch playback/media back
  to original media and run Host Analysis again. After analysis has been validated, playback
  can use proxy media while rendering from the prepared original-media motion path.
- If Metal analysis resources are unavailable, Host Analysis fails visibly instead of
  falling back to CPU analysis.
- Host Analysis uses Metal block matching across multiple regions and prioritizes upper-frame
  far-field blocks for walking landscape footage. This keeps distant mountains and background
  features from being overruled by close grass, water, or road parallax.
- Playback uses prepared motion paths from completed Host Analysis. It must not run full
  frame-to-frame block matching on every rendered playback frame. Host Analysis stores
  separate raw X/Y/roll impulse paths for Footstep Jitter before applying the zero-phase
  jerk limiter used by broader pan and turn stages. Those raw footstep paths and their
  baselines are sampled continuously at render time so panning does not snap between nearest
  analyzed frames and frame-level shake is not erased before Footstep Jitter can correct it.
  The final automatic transform is also sampled across a `1.20` second symmetric render-time
  window and blended with zero phase. Near clip edges, out-of-range neighboring samples are
  skipped instead of clamped to the first or last analysis frame, so the end frames are not
  over-weighted. This increases preview compute per frame but makes the pan correction as
  smooth as possible without rerunning Host Analysis. Debug output reports the raw
  center-frame transform and the smoothing delta so visible stepping can be diagnosed from
  the Inspector. Footstep Jitter X/Y and roll keep the current render frame's impulse
  correction after the wider Stride/Turn smoothing pass, so fine distant ridge-line shake
  is not averaged out by temporal smoothing. Far-field Warp uses a shorter `0.36` second
  in-range smoothing window so ridge-line correction remains responsive without turning
  single-frame gate changes into swimming. Render-time window selection uses the sorted Host
  Analysis frame times directly, so long prepared caches do not require repeated full-cache
  scans during playback. Stride and Turn confidence use robust residual percentiles
  rather than the single worst frame in the smoothing window.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available. The render
  path accepts the active range-matched cache identity in this state even before Final Cut Pro
  returns the hidden cache identity parameter. If a stale saved identity points at a different
  range, render drops it and reloads a compatible saved cache in the same callback before
  giving up, then keeps the hidden preview revision, `Host Analysis Status`, and `Stabilizer
  Info` current so the stabilized proxy preview appears and reports
  `Original Analysis - Proxy Preview` without switching back to original media first. If
  Final Cut Pro still reports an older hidden revision value, the runtime retries publishing
  the current token instead of assuming a previous publish was accepted.
  When original-media validation maps a trimmed timeline render time back to the analyzed
  source time, the runtime saves that offset with the Host Analysis cache identity so
  proxy-only render instances can sample the same prepared motion path.
  When Final Cut Pro reports a different render/timeline duration during scaled/proxy
  playback, a range-mismatched active cache is used for preview only if the saved start
  matches the current clip and the render time is inside the saved analysis range.
  Proxy/scaled media is detected when the source pixel transform differs from original
  `1.0x/1.0x` in either direction, so reduced-resolution proxy frames do not validate
  against and reject a good original-media cache.
- If Final Cut Pro is set to proxy playback and the proxy file is missing, the Viewer sends
  the plug-in a Missing Proxy placeholder instead of the original image. The effect reports
  `Source Media Unavailable - Check FCP Proxy`, leaves the Host Analysis cache on disk, and
  does not draw Debug Overlay diagnostics over that placeholder. Switch Viewer playback to
  Original/Optimized or create proxy media before judging the stabilized preview.
- Render playback combines `Turn Smoothing Strength` and the long `Turn Detection Window`
  path to build a monotonic S-curve X-only turn intent, then combines it with a per-frame
  Footstep Jitter impulse path and a fixed `2.0` second Stride Wobble band. Y correction is
  handled by Footstep Jitter first and Stride Wobble second; Turn Smoothing does not apply to Y.
  This keeps horizontal segmented turns, fine high-frequency shake, medium walking wobble,
  and vertical walking wobble tunable without rerunning Host Analysis.
  Footstep Jitter confidence is evaluated on the current render frame instead of inheriting
  the worst residual from the wider turn-detection window.
- `Far-field Warp Strength` defaults to `1.0` and controls bundled deskew/shear, yaw/pitch
  proxy, and perspective trim. At `0`, warp is fully disabled. At `4`, render clamps cap
  shear at `0.016`, yaw/pitch proxy at `0.010`, and perspective at `0.006`. The applied
  value is the local warp band against its `0.10`/`1.0` second outer-frame linear baseline,
  not the absolute accumulated warp path. Render also requires walking-footage tracking
  quality and search-radius headroom before applying warp, starts its tracking gate earlier
  for moderate 25% Host Analysis evidence, stabilizes that gate with short local tracking
  support, applies only short render-time smoothing, and drops tiny warp deltas through a
  deadband to avoid wave-like image distortion while tuning micro jitter.
- Host Analysis cache schema `14` stores the original-size-percentage sample path with the
  far-field-prioritized, zero-phase jerk-limited multi-block motion path, separate raw
  Footstep Jitter X/Y/roll impulse paths, warp paths, confidence, accepted-block counts,
  blur values, and search-radius edge-hit counts. Older prepared caches are marked
  unsupported and require a new Host Analysis run.
- Host Analysis/cache state changes update a hidden render revision parameter. Viewer-side
  instances also monitor saved cache changes so Final Cut Pro invalidates cached preview
  frames and redraws from the prepared motion path after a serial analysis finishes.
  The hidden render revision is a process-independent small numeric token, not a local
  analysis counter, so analyzer and render processes cannot publish the same invalidation
  value for different completed clips. The plug-in skips setting that hidden parameter when
  Final Cut Pro already has the same value to avoid repeated effect-load invalidation. If
  Final Cut Pro rejects the hidden update, the plug-in does not record it as published, so a
  later cache monitor tick or callback can retry. Analyzer completion and cache-monitor
  ticks dispatch that status/info/render revision publication onto the FxPlug main queue
  before calling Final Cut Pro's parameter-setting API.
- Trimmed clips are supported by matching the current render frame fingerprint against the
  analyzed Host Analysis frame set. If Final Cut Pro reports render time in a different time
  domain than analysis time, the effect applies that offset before reading the prepared
  motion paths. If Final Cut Pro reports a render/timeline range that differs from the saved
  source analysis range, the effect accepts that active cache only after the current
  source-frame fingerprint validates against the saved frame set.

## Host Analysis Cache

The latest Host Analysis compatibility alias is written inside the active Final Cut Pro
library bundle, scoped to the Event that owns the current project/media folder. If Final Cut
Pro reports a library temp folder instead of an Event folder, the runtime uses an
unambiguous top-level Event resolver, such as the single Event that already has Final Cut Pro
`Analysis Files`. If multiple Events have `Analysis Files`, the resolver compares the active
Host Analysis range against Final Cut Pro `Analysis Files/Stabilization` range folder names
and only selects a unique match. It starts access to the host-provided media folder before
inspecting the library bundle, then verifies the selected Event by creating the
`TokyoWalkingStabilizerHostAnalysis` cache root. If the host media folder is unavailable because
the library was saved without Collect Media, the resolver reads Final Cut Pro's active
library bookmarks from `FFActiveLibraries`, tries security-scoped bookmark resolution first,
logs when regular resolution is used, starts security-scoped access when a resolved URL grants
it, and then applies the same Event selection rules. If multiple libraries are active,
existing Final Cut Pro `Analysis Files/Stabilization` range names may disambiguate the Event
only when the active Host Analysis range matches exactly one Event across active libraries.
If no range match exists, the resolver may use Final Cut Pro's `FFSidebarModuleLibrary` media
sidebar selection only when the selection UUIDs match exactly one active library and the
selected Event UUID resolves through `CurrentVersion.flexolibrary` metadata to an existing
top-level Event folder. Stale import-target UUIDs are not used.
Multiple active libraries with no unique selected Event, unreadable active-library state, or an unwritable Event cache root
remain visible failures; ambiguous active libraries surface as
`Project Bundle Cache Unavailable - Ambiguous Active Libraries`. Resolver logs include the media folder URL, `documentID`,
active-library bookmark candidates when used, bundle root, Event candidates, selected Event,
and rejection reason. It fails visibly as
`Project Bundle Cache Unavailable - Ambiguous Event` when the Event remains ambiguous. The
cache root lives under that Event's `Analysis Files` directory so analysis files stay unique
to the Event and do not appear as top-level library content:

```text
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-v2.json
```

Completed analysis is written to this bundle-local path so Final Cut Pro's analyzer and
preview/render extension processes can reuse the same prepared motion path. If the runtime
cannot resolve a writable Event cache root, the Inspector shows
`Project Bundle Cache Unavailable` instead of falling back to a shared user cache or a
library-wide cache. During a live Host Analysis callback, the current pass may still finish
in memory as `Ready Memory Only - Project Bundle Cache Unavailable`; that result can drive
the current viewer/render session, but it is not persisted to any shared or out-of-bundle
location. If the Event cache root becomes available later, the completed in-memory analysis
is saved into that Event cache and the Inspector returns to ordinary `Ready (...)` status.
Older top-level bundle caches at `<active library>.fcpbundle/TokyoWalkingStabilizerHostAnalysis/`
and older internal bundle caches at
`<active library>.fcpbundle/__.fcpdata.apple.com/TokyoWalkingStabilizerHostAnalysis/` are moved into
the Event `Analysis Files` cache root when the effect configures the active Event cache.

The cache index is written to:

```text
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/host-analysis-index-v2.json
```

Range-specific, sample-size-scoped cache files are stored under:

```text
<active library>.fcpbundle/<event>/Analysis Files/TokyoWalkingStabilizerHostAnalysis/caches/
```

Those filenames include a readable clip label when available, analyzed start/end, actual
`sampleWidth` and `sampleHeight`, frame count, and representative saved fingerprints. The
cache index stores the clip label, range start/end, sample size, fingerprints, and cache
identity, and retains entries independently per sample size instead of pruning all sizes
through one global bucket.

On load, the effect validates the current source frame against saved frame fingerprints
before using a persisted cache. If a lightweight cache frame no longer has retained
validation pixels, the effect only accepts the nearest cached frame when it is within the
tight render-time tolerance and logs that path explicitly. Rejected cache candidates are
visible in logs/status and left on disk for other clips. Unsupported schema candidates are
also left on disk, but the Inspector shows `Cache Unsupported - Run Host Analysis` so a
current-build analysis is explicitly required. Supported-schema caches with incomplete
prepared path arrays or incomplete frame coverage show `Cache Incomplete - Run Host
Analysis` for the same reason.
Those stale unusable states do not prevent preview/render consumers from noticing later
persistent cache changes and loading a newly written compatible cache.

New cache files store prepared motion paths, per-frame timestamps, blur values,
search-radius edge-hit counts, and fingerprints instead of every frame's full luma sample.
This keeps bundle-local cache reuse available without writing long-clip `Sample Size` pixel
buffers into JSON.

## Development

Build and install with:

```sh
xcodebuild \
  -project fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj \
  -scheme TokyoWalkingStabilizer \
  -configuration Debug \
  -derivedDataPath /tmp/TokyoWalkingStabilizerDerived \
  build
```

Quit Final Cut Pro before building or rerunning `install_debug_app.sh`. The shared scheme
and installer fail visibly when Final Cut Pro is running instead of touching a loaded FxPlug
bundle.

Verify with:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.TokyoWalkingStabilizer.Plugin
codesign --verify --deep --strict /Applications/TokyoWalkingStabilizer.app
```
