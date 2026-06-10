# Usage

## Final Cut Pro

1. Build the FxPlug wrapper app.
2. Open Final Cut Pro after the install step completes.
3. Apply `Stabilizer Transform` from the `Emdash Studios` effects group.
4. Click `Start Host Analysis` if the Inspector status says `Needs Analysis`,
   `Cache Rejected - Run Host Analysis`, `Cache Unsupported - Run Host Analysis`, or
   `Cache Incomplete - Run Host Analysis`.
5. Wait for `Host Analysis Status` to show `Ready (... frames)`.

`Start Host Analysis` requests the active effect clip from Final Cut Pro. If Final Cut Pro
reports that another analysis is already requested or running, the Inspector shows
`Queued Host Analysis` and the effect waits in a process-wide serial queue. Queued clips
start one at a time as earlier Host Analysis runs finish. A queued clip remains a real
pending start request until it starts or you clear it; another clip's completed analysis is
not treated as completion for the queued clip.
Debug installs clean stale `Stabilizer Transform copy...` Motion Template folders in the
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
```

- `apply`: reveals the Effects Browser, searches `Stabilizer Transform`, and
  presses the matching result for the selected clip.
- `start-analysis`: reveals the Inspector and presses `Start Host Analysis`.
- `toggle-debug-overlay`: reveals the Inspector and toggles `Debug Overlay`.
- `focus-inspector`: reveals or focuses the Inspector with Command-4.
- `open-selected-project`: opens the selected Browser project thumbnail or list
  row with a CoreGraphics double-click.

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
  default is `0.70`, so medium vertical follow-through is corrected before the longer
  Walking Bob pass while still leaving BOB as the broader vertical-cycle correction.
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
- `Walking Bob`: fixed internal `2.5` second Y-axis-only baseline for footstep bob and
  vertical walking shake left after Footstep Jitter and Stride Wobble. The correction uses
  the Y band between the stride-smoothed baseline and this slightly longer walking-bob
  smooth path without changing X or roll. There is no user-facing window control; `Turn
  Detection Window` has its own Inspector slider. Its confidence uses tracking quality and
  symmetric window support, robust residuals, and actual Y-band magnitude, so weak block
  coverage, one-sided clip-edge windows, or tiny vertical bands do not create large vertical
  waves.
- `Walking Bob Removal`: direct amount for the Y-only correction. Footstep bounce
  can be reduced without changing X or roll. This is the final correction stage inside the
  same effect, and setting it to `0` does not disable Footstep Jitter Y. The default is
  `0.75`, which is intentionally conservative; higher values can push through low-confidence
  gating but are clamped during render to avoid adding inverse vertical shake.
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
- `Sample Size`: analysis image size as a percentage of the original clip dimensions. The
  options are `100%`, `75%`, `50%`, `25%`, and `10%`. The default is `10%` so a debug pass
  can analyze quickly. The actual pixel size is shown in `Stabilizer Info`.
- `Edge Display Mode`: `Stretch Edges` keeps the previous preview behavior by extending
  edge pixels outside the transformed source image. `Black Outside` draws those outside
  pixels black so the viewer shows how far stabilization is moving the image.
- `Start Host Analysis`: resets the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis. Rejected cache file names are remembered in
  the active FxPlug runtime so the same invalid candidate is not immediately reloaded again.
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
  queued and started after the host becomes available. The queued request is retained until
  start or explicit clear, and completed analysis from the previous clip does not make the
  queued clip skip its own Host Analysis. Final Cut Pro may run the analysis callbacks on a
  different FxPlug instance than the Inspector button instance, so completion clears
  process-wide analysis bookkeeping before draining the next queued request. The Inspector
  start path does not use plug-in-local active markers as the blocking authority; it asks
  Final Cut Pro's current analysis state and queues only when the host reports a
  busy/requested state. Queued starts still check Final Cut Pro's actual analysis state
  before starting.
  Completed analysis is then published to the process-wide shared render/cache store and
  persisted to the shared user Application Support cache using the prepared analysis frame
  set, so analyzer and preview/render processes can hand off the prepared motion path
  through validated cache files. Preview/render and plug-in state callbacks detect cache
  file changes even when they already hold an older prepared analysis, then reload
  candidates and update the hidden render revision without starting Host Analysis.
  A cache whose fingerprints do not match the current source frame is
  rejected instead of being accepted by time proximity alone. `Start Host Analysis` is the
  only path that requests Host Analysis from Final Cut Pro.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared`.
- `Host Analysis Status`: read-only status for analysis and cache reuse. It appends
  the current FxPlug runtime version when Final Cut Pro accepts status parameter
  updates. `Queued Host Analysis` means this clip is waiting for the plug-in's serial Host
  Analysis queue to start it after the currently active host run finishes; it should advance
  automatically after the active host run finishes unless Final Cut Pro still reports busy.
  During a real analysis run, the status advances as `Analyzing Host Frames (N)`.
  If Final Cut Pro restores an in-progress analysis state while a compatible saved cache is
  already present, the plug-in prefers the saved cache and keeps the shared Ready/cache
  status visible instead of letting transient analyzer callback status mask it.
- `Stabilizer Info`: scrollable read-only runtime and analysis metadata. It shows the
  loaded FxPlug version, active correction bands (`Footstep jitter`, `Stride wobble`,
  `Walking Bob`, `Far-field Warp`, `Turn Smoothing`), plus completed analysis time, frame
  count, actual sample image size, source frame size, and pixel transform scale when analysis
  is available.
  Older saved timeline instances can keep stale saved Inspector strings, so check the
  compact runtime-version row in `Debug Overlay` when confirming the active render runtime.
- `Debug Overlay`: labeled top-left diagnostics for final `X`/`Y`/`ROLL`, `FJIT`, `SWOB`,
  `BOB`, `WARP`, `TURN`, live `F Q`/`S Q`/`B Q`/`W Q`/`T Q` confidence, plus `SMTH`,
  `TRK`, `SHRP`, `RES`, search-radius `HIT`, walking-band `WLK`, and compact runtime-version bars while
  checking runtime behavior. The overlay scales from the current render output to keep one readable
  viewer footprint across original/proxy playback, while staying larger than the old compact panel.
  `TRK`, `SHRP`, `RES`, and `HIT` are quality bars: higher is better and lower means weaker
  tracking evidence.
  Labels use raw English control/diagnostic abbreviations and should not be translated in the preview. When
  enabled, `Host Analysis Status` also shows the current FxPlug version, the raw center-frame transform, the
  smoothed transform delta, strict tracking, walking-band tracking, motion confidence, blur, residual, the raw `foot q`,
  the effective Footstep Jitter X/Y/R correction strength, `stride q`, the effective Stride
  Wobble X/Y/R correction strength, `turn q`, applied `warp q`, shear, yaw/pitch proxy, perspective,
  edge-hit counts, the X turn and stride components plus Y footstep, stride, and walking-bob
  components, plus separate `bob q` confidence.
- Strength values above `1.0` still compensate low-confidence Footstep, Stride Wobble, and
  Walking Bob detections. Those walking-band controls use a more assertive
  medium-confidence response than TURN and WARP, but zero confidence still produces zero
  correction.

## Feedback CLI

To turn a review note into diagnostics, run the cache-backed feedback tool:

```sh
fxplug/StabilizerFxPlug/scripts/stabilizer_feedback.sh --time 5.0 --note "notable unremoved shake"
```

`--time` is clip-relative, so `5.0` means five seconds after the saved Host
Analysis range starts. The default cache path is
`~/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json`; pass
`--cache` for a range-specific file under the `caches/` directory. Add `--json`
for structured output, `--window 0.5` to inspect the strongest frame near the
note, `--turn-window` to match a non-default Inspector `Turn Detection Window`,
and `--output-size 1920x1080` to scale translation estimates to a preview size.

Use `--list-caches` to inspect saved cache readiness before diagnosing a note:

```sh
fxplug/StabilizerFxPlug/scripts/stabilizer_feedback.sh --list-caches
```

The listing checks the latest shared cache and range-specific cache files under
`~/Library/Application Support/StabilizerFxPlug`, reporting `READY`,
`INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE`. It does not repair, delete, or
promote cache files. Use `--cache-root /path/to/root` only when you explicitly
want to inspect a different cache root.

The CLI does not inspect pixels or start Host Analysis. It reads saved prepared
paths and prints `FJIT`, `SWOB`, `BOB`, `WARP`, and `TURN` in render-stage order,
while the summary line names the highest remaining band. `FJIT` is measured against
the outer-frame baseline, then `SWOB`, `BOB`, and `TURN` are measured from that
footstep-cleaned path. It prints strict tracking and walking-band tracking separately,
FJIT and SWOB per-axis confidence (`qX`, `qY`, `qR`) alongside
the raw impulse or band values, and BOB tracking/window support so short
or one-sided analysis ranges are distinguishable from weak vertical motion. `WARP` `q` matches the applied `W Q` confidence shown by
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
  runtime, persists completed analysis to the FxPlug Application Support cache, and renders
  from that analyzed frame set.
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
  jerk limiter used by broader pan, turn, and bob stages. Those raw footstep paths and their
  baselines are sampled continuously at render time so panning does not snap between nearest
  analyzed frames and frame-level shake is not erased before Footstep Jitter can correct it.
  The final automatic transform is also sampled across a `1.20` second symmetric render-time
  window and blended with zero phase. Near clip edges, out-of-range neighboring samples are
  skipped instead of clamped to the first or last analysis frame, so the end frames are not
  over-weighted. This increases preview compute per frame but makes the pan correction as
  smooth as possible without rerunning Host Analysis. Debug output reports the raw
  center-frame transform and the smoothing delta so visible stepping can be diagnosed from
  the Inspector. Footstep Jitter X/Y and roll keep the current render frame's impulse
  correction after the wider Stride/Turn/Bob smoothing pass, so fine distant ridge-line shake
  is not averaged out by temporal smoothing. Far-field Warp uses a shorter `0.36` second
  in-range smoothing window so ridge-line correction remains responsive without turning
  single-frame gate changes into swimming. Render-time window selection uses the sorted Host
  Analysis frame times directly, so long prepared caches do not require repeated full-cache
  scans during playback. Stride, Bob, and Turn confidence use robust residual percentiles
  rather than the single worst frame in the smoothing window.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available. The render
  path keeps the hidden preview revision current in this state so the stabilized proxy
  preview appears without switching back to original media first.
- Render playback combines `Turn Smoothing Strength` and the long `Turn Detection Window`
  path to build a monotonic S-curve X-only turn intent, then combines it with a per-frame
  Footstep Jitter impulse path, a fixed `2.0` second Stride Wobble band, and a Y-only
  fixed `2.5` second Walking Bob band-pass path. Y correction is handled by Footstep Jitter
  first, Stride Wobble second, and Walking Bob last; Turn Smoothing does not apply to Y.
  This keeps horizontal segmented turns, fine high-frequency shake, medium walking wobble,
  and footstep vertical bobbing independently tunable without rerunning Host Analysis.
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
- Host Analysis/cache state changes update a hidden render revision parameter. Plug-in
  state callbacks also check saved cache changes so Final Cut Pro invalidates cached
  preview frames and redraws from the prepared motion path after a serial analysis finishes.
  The hidden render revision is a process-independent small numeric token, not a local
  analysis counter, so analyzer and render processes cannot publish the same invalidation
  value for different completed clips. The plug-in skips setting that hidden parameter when
  Final Cut Pro already has the same value to avoid repeated effect-load invalidation.
- Trimmed clips are supported by matching the current render frame fingerprint against the
  analyzed Host Analysis frame set. If Final Cut Pro reports render time in a different time
  domain than analysis time, the effect applies that offset before reading the prepared
  motion paths.

## Host Analysis Cache

The latest Host Analysis compatibility alias is written to:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json
```

Completed analysis is written to this shared user Application Support path so Final Cut
Pro's analyzer and preview/render extension processes can reuse the same prepared motion
path. The loader also checks current and legacy Stabilizer container cache locations so a
bundle-id or runtime migration does not require rerunning analysis when the cache schema is
still supported.

The cache index is written to:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-index-v2.json
```

Range-specific, sample-size-scoped cache files are stored under:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/
```

Those filenames include the actual `sampleWidth` and `sampleHeight`, and the cache index
retains entries independently per sample size instead of pruning all sizes through one
global bucket.

On load, the effect validates the current source frame against saved frame fingerprints
before using a persisted cache. If a lightweight cache frame no longer has retained
validation pixels, the effect only accepts the nearest cached frame when it is within the
tight render-time tolerance and logs that path explicitly. Rejected cache candidates are
visible in logs/status and left on disk for other clips. Unsupported schema candidates are
also left on disk, but the Inspector shows `Cache Unsupported - Run Host Analysis` so a
current-build analysis is explicitly required. Supported-schema caches with incomplete
prepared path arrays or incomplete frame coverage show `Cache Incomplete - Run Host
Analysis` for the same reason.

New cache files store prepared motion paths, per-frame timestamps, blur values,
search-radius edge-hit counts, and fingerprints instead of every frame's full luma sample.
This keeps cache reuse available without writing long-clip `Sample Size` pixel buffers into
JSON.

The effect does not store analysis files inside a Final Cut Pro library or project bundle.
The FCP bundle path is host-owned, and moving large scratch files there would still consume
the same disk while risking library corruption.

## Development

Build and install with:

```sh
xcodebuild \
  -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj \
  -scheme StabilizerFxPlug \
  -configuration Debug \
  -derivedDataPath /tmp/StabilizerFxPlugDerived \
  build
```

Quit Final Cut Pro before building or rerunning `install_debug_app.sh`. The shared scheme
and installer fail visibly when Final Cut Pro is running instead of touching a loaded FxPlug
bundle.

Verify with:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
```
