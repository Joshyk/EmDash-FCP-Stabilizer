# Usage

## Final Cut Pro

1. Build the FxPlug wrapper app.
2. Restart Final Cut Pro if it was already open.
3. Apply `Stabilizer Transform` from the `Emdash Studios` effects group.
4. Click `Start Host Analysis` if the Inspector status says `Needs Analysis`,
   `Cache Rejected - Run Host Analysis`, or `Cache Unsupported - Run Host Analysis`.
5. Wait for `Host Analysis Status` to show `Ready (... frames)`.

`Start Host Analysis` requests the active effect clip from Final Cut Pro. If Final Cut Pro
reports that another analysis is already requested or running, the Inspector shows that
host state instead of starting an internal plug-in queue.
Debug installs clean stale `Stabilizer Transform copy...` Motion Template folders in the
`Emdash Studios` group so Final Cut Pro does not list duplicate Stabilizer effects.

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
  not produce a strong correction by itself. Values above `1.0` can compensate when that
  frame-local score makes the detected impulse visibly under-corrected, but render output
  still clamps at full detected-impulse removal to avoid inverse shake.
- `Footstep Jitter Rotation Strength`: direct amount for roll footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Values above `1.0` can compensate when
  frame-local confidence makes the detected impulse visibly under-corrected, but render
  output still clamps at full detected-impulse removal to avoid inverse shake.
- `Stride Wobble X Strength`: direct amount for medium-period horizontal walking wobble that
  is longer than Footstep Jitter but shorter than broad Turn Smoothing. The default is
  `0.65` and the maximum is `4.0`.
- `Stride Wobble Y Strength`: direct amount for medium-period vertical walking wobble. The
  default is `0.35` because Walking Bob remains the main longer vertical-cycle correction.
  Stride Wobble uses a fixed internal `2.0` second render-time window; there is no
  user-facing Stride Wobble window. Its residual gate uses robust window percentiles instead
  of the single worst residual in the window.
- `Stride Wobble Rotation Strength`: direct amount for medium-period roll wobble. The default
  is `0.75` and the maximum is `4.0`. The correction is measured from the
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
  quality and search-radius headroom, then applies a tiny deadband so weak frames do not
  create wave-like image distortion. Pull this down if close grass, roads, water, or frame
  edges start to swim.
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
  `Cache Unsupported - Run Host Analysis`; the file remains on disk and the button starts a
  new Host Analysis run for the current build.
- Persistent analysis reuse is based on cache schema and current source-frame validation,
  not the loaded FxPlug runtime version. Render-only runtime updates should reuse the saved
  Host Analysis cache.
- Host Analysis uses a process-wide shared render store inside the active FxPlug runtime.
  Setup, frame analysis, cleanup, and render read/write that shared store when Final Cut Pro
  uses different FxPlug instances in the same process. Completed analysis is also persisted
  to the shared user Application Support cache so analyzer and preview/render processes can
  hand off the prepared motion path through validated cache files. Preview/render callbacks
  detect cache file changes when they have no prepared analysis, then reload candidates
  without starting Host Analysis. `Start Host Analysis` is the only path that requests Host
  Analysis from Final Cut Pro. If Final Cut Pro reports that Host Analysis is already
  requested or running, the Inspector shows that state instead of queueing another start
  inside the plug-in.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared`.
- `Host Analysis Status`: read-only status for analysis and cache reuse. It appends
  the current FxPlug runtime version when Final Cut Pro accepts status parameter
  updates.
- `Stabilizer Info`: scrollable read-only runtime and analysis metadata. It shows the
  loaded FxPlug version, active correction bands (`Footstep jitter`, `Stride wobble`,
  `Walking Bob`, `Far-field Warp`, `Turn Smoothing`), plus completed analysis time, frame
  count, actual sample image size, source frame size, and pixel transform scale when analysis
  is available.
  Older saved timeline instances can keep stale saved Inspector strings, so check the
  compact `V04` row in `Debug Overlay` when confirming the active render runtime.
- `Debug Overlay`: labeled top-left diagnostics for final `X`/`Y`/`ROLL`, `FJIT`, `SWOB`,
  `BOB`, `WARP`, `TURN`, live `F Q`/`S Q`/`B Q`/`W Q`/`T Q` confidence, plus `SMTH`,
  `TRK`, `SHRP`, `RES`, search-radius `HIT`, and compact runtime `V04` bars while
  checking runtime behavior.
  `TRK`, `SHRP`, `RES`, and `HIT` are quality bars: higher is better and lower means weaker
  tracking evidence.
  Labels use raw English control/diagnostic abbreviations and should not be translated in the preview. When
  enabled, `Host Analysis Status` also shows the current FxPlug version, the raw center-frame transform, the
  smoothed transform delta, tracking/motion confidence, blur, residual, the raw `foot q`,
  the effective Footstep Jitter X/Y/R correction strength, `stride q`, the effective Stride
  Wobble X/Y/R correction strength, `turn q`, applied `warp q`, shear, yaw/pitch proxy, perspective,
  edge-hit counts, the X turn and stride components plus Y footstep, stride, and walking-bob
  components, plus separate `bob q` confidence.
- Strength values above `1.0` still compensate low-confidence Footstep, Stride Wobble, and
  Walking Bob detections. The render-time confidence response is more assertive for
  medium-confidence frame evidence, but zero confidence still produces zero correction.

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
  is not averaged out by temporal smoothing. Stride, Bob, and Turn confidence use robust
  residual percentiles rather than the single worst frame in the smoothing window.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available.
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
  quality and search-radius headroom before applying warp, curves medium-confidence gates
  upward, and drops tiny warp deltas through a deadband to avoid wave-like image distortion
  while tuning micro jitter.
- Host Analysis cache schema `14` stores the original-size-percentage sample path with the
  far-field-prioritized, zero-phase jerk-limited multi-block motion path, separate raw
  Footstep Jitter X/Y/roll impulse paths, warp paths, confidence, accepted-block counts,
  blur values, and search-radius edge-hit counts. Older prepared caches are marked
  unsupported and require a new Host Analysis run.
- Host Analysis/cache state changes update a hidden render revision parameter so Final Cut
  Pro invalidates cached preview frames and redraws from the prepared motion path.
- Trimmed clips are supported by matching the current render frame fingerprint against the
  analyzed Host Analysis frame set. If Final Cut Pro reports render time in a different time
  domain than analysis time, the effect applies that offset before reading the prepared
  motion paths.

## Host Analysis Cache

The latest Host Analysis cache is written to:

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

Range-specific cache files are stored under:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/
```

On load, the effect validates the current source frame against saved frame fingerprints
before using a persisted cache. If a lightweight cache frame no longer has retained
validation pixels, the effect only accepts the nearest cached frame when it is within the
tight render-time tolerance and logs that path explicitly. Rejected cache candidates are
visible in logs/status and left on disk for other clips. Unsupported schema candidates are
also left on disk, but the Inspector shows `Cache Unsupported - Run Host Analysis` so a
current-build analysis is explicitly required.

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

Verify with:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
```
