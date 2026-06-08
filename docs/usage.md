# Usage

## Final Cut Pro

1. Build the FxPlug wrapper app.
2. Restart Final Cut Pro if it was already open.
3. Apply `Stabilizer Transform` from the `Emdash Studios` effects group.
4. Click `Start Host Analysis` if the Inspector status says `Needs Analysis` or
   `Cache Rejected - Run Host Analysis`.
5. Wait for `Host Analysis Status` to show `Ready (... frames)`.

`Start Host Analysis` requests the active effect clip from Final Cut Pro. If Final Cut Pro
reports that another analysis is already requested or running, the Inspector shows that
host state instead of starting an internal plug-in queue.
Debug installs clean stale `Stabilizer Transform copy...` Motion Template folders in the
`Emdash Studios` group so Final Cut Pro does not list duplicate Stabilizer effects.

## Controls

- `Footstep Jitter X Strength`: direct amount for horizontal footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Values above `1.0` push through low-confidence
  gating when the detected impulse is visibly under-corrected, but render output still
  clamps at full detected-impulse removal to avoid inverse shake.
- `Footstep Jitter Y Strength`: direct amount for vertical footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Footstep Jitter uses an outer-frame linear
  prediction that skips the center shock region for X/Y/rotation, so footstep landing shock
  is treated as a frame-level impulse instead of being averaged back into the smooth path.
  Host Analysis builds that path from multiple Metal block-matched regions with outlier
  blocks rejected before render. Values above `1.0` push through low-confidence gating when
  the detected impulse is visibly under-corrected, but render output still clamps at full
  detected-impulse removal to avoid inverse shake.
- `Footstep Jitter Rotation Strength`: direct amount for roll footstep-jitter correction. The
  default is `1.0` and the maximum is `4.0`. Values above `1.0` push through low-confidence
  gating when the detected impulse is visibly under-corrected, but render output still
  clamps at full detected-impulse removal to avoid inverse shake.
- `Overall Strength`: master multiplier for automatic X/Y translation and roll compensation.
  At `0`, the render path bypasses all automatic transform, crop-safety motion, and debug
  overlay output.
- `Turn Smoothing Strength`: controls how strongly the stabilizer concatenates segmented
  walking turns in X/Y translation only. It does not change roll. At `0`, long-window turn
  correction is bypassed; the default is `1.0` and the maximum is `4.0`. Values above `1.0`
  push through low-confidence gating when stop-and-go panning is still visible, but render
  output still clamps at full detected turn-band removal. The turn intent is a monotonic
  S-curve through the detection window instead of a straight-line fit. The X/Y turn bands
  are measured from the Footstep Jitter baseline instead of the raw frame path, so short
  landing shock is not reintroduced by turn smoothing. The macro X/Y output correction is
  soft-limited to a small edge budget during render so large detected pans do not create
  stretched-edge jumps in the preview.
- `Turn Detection Window`: centered smoothing window for walking turns. In Host Analysis
  mode this is evaluated against prepared motion paths during render, so changing the slider
  does not require rebuilding analysis.
- Prepared Host Analysis motion paths are post-processed with a zero-phase jerk limiter
  before caching. It clamps isolated acceleration spikes in X/Y/roll while preserving the
  total analyzed path endpoint, so real panning is not delayed into a sliding path. Short
  analyzed ranges are kept in bounds during cleanup so the prepared cache can be saved.
- `Walking Bob Window`: Y-axis-only window for footstep bob and vertical walking shake
  left after Footstep Jitter and Turn Smoothing. The correction uses the Y band between the
  Footstep Jitter baseline and this walking-bob smooth path, which is computed from the same
  footstep-cleaned baseline without changing X or roll. The default is `1.5` seconds. Use
  shorter values around `0.4-1.0` seconds for visible footstep bounce and larger values for
  slower vertical sway. Values above `Turn Detection Window` are clamped to the turn window
  during render.
- `Walking Bob Removal`: direct amount for the Y-only correction. Footstep bounce
  can be reduced without changing X or roll. This is the final correction stage inside the
  same effect, and setting it to `0` does not disable Footstep Jitter Y. The default is
  `0.75`, which is intentionally conservative; higher values can push through low-confidence
  gating but are clamped during render to avoid adding inverse vertical shake.
- `Sample Size`: analysis image size as a percentage of the original clip dimensions. The
  options are `100%`, `75%`, `50%`, `25%`, and `10%`. The default is `100%`, which analyzes
  at the original clip size. The actual pixel size is shown in `Stabilizer Info`.
- `Edge Display Mode`: `Stretch Edges` keeps the previous preview behavior by extending
  edge pixels outside the transformed source image. `Black Outside` draws those outside
  pixels black so the viewer shows how far stabilization is moving the image.
- `Start Host Analysis`: resets the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis. Rejected cache file names are remembered in
  the active FxPlug runtime so the same invalid candidate is not immediately reloaded again.
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
- `Host Analysis Status`: read-only status for analysis and cache reuse.
- `Stabilizer Info`: scrollable read-only runtime and analysis metadata. It shows the
  loaded FxPlug version, active correction bands (`Footstep jitter`, `Walking Bob`,
  `Turn Smoothing`), plus completed analysis time, frame count, actual sample image size, source
  frame size, and pixel transform scale when analysis is available.
- `Debug Overlay`: top-left diagnostics for final X/Y/rotation, Turn Smoothing, Footstep
  Jitter, Walking Bob, and temporal smoothing delta while checking runtime behavior. When
  enabled, `Host Analysis Status` also shows the current raw center-frame transform, the
  smoothed transform delta, the raw `foot q`, the effective Footstep Jitter X/Y/R correction
  strength, the Y correction split into turn, footstep, and walking-bob components, plus
  separate `bob q` confidence.

## Behavior

- The effect does not write Final Cut Pro Transform keyframes.
- It estimates low-resolution multi-block X/Y motion and roll from FxPlug-requested source
  frames.
- It is tuned for walking-gimbal footage. The render path corrects softened X/Y translation
  and roll only; yaw/pitch proxy, shear, and perspective compensation are disabled.
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
  frame-to-frame block matching on every rendered playback frame. Prepared X/Y/roll paths
  and their footstep baselines are sampled continuously at render time so panning does not
  snap between nearest analyzed frames. The final automatic transform is also sampled across
  a wider symmetric render-time window and blended with zero phase. This increases preview
  compute per frame but makes the pan correction as smooth as possible without rerunning Host
  Analysis. Debug output reports the raw center-frame transform and the smoothing delta so
  visible stepping can be diagnosed from the Inspector. Footstep Jitter X/Y and roll keep
  the current render frame's impulse correction after the wider Turn/Bob smoothing pass, so
  fine distant ridge-line shake is not averaged out by temporal smoothing.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available.
- Render playback combines `Turn Smoothing Strength` and the long `Turn Detection Window`
  path to build a monotonic S-curve X/Y turn intent, then combines it with a per-frame
  Footstep Jitter impulse path and a Y-only `Walking Bob Window` band-pass path. Y
  correction is always evaluated as Footstep Jitter first, Turn Smoothing second, and
  Walking Bob last. Turn smoothing uses the footstep-cleaned Y baseline rather than the raw
  frame path, and Walking Bob removes only the remaining medium-period Y band, so large
  walking-gimbal sway, fine high-frequency shake, and footstep vertical bobbing can be tuned
  separately without rerunning Host Analysis.
- Host Analysis cache schema `11` stores the original-size-percentage sample path with the
  far-field-prioritized, zero-phase jerk-limited multi-block motion path, confidence, and
  accepted-block counts. Older prepared caches are ignored and require a new Host Analysis
  run.
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
visible in logs/status and left on disk for other clips.

New cache files store prepared motion paths, per-frame timestamps, blur values, and
fingerprints instead of every frame's full luma sample. This keeps cache reuse available
without writing long-clip `Sample Size` pixel buffers into JSON.

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
