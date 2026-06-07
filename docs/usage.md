# Usage

## Final Cut Pro

1. Build the FxPlug wrapper app.
2. Restart Final Cut Pro if it was already open.
3. Apply `Stabilizer Transform` from the `Emdash Studios` effects group.
4. Click `Start Host Analysis` if the Inspector status says `Needs Analysis` or
   `Cache Rejected - Run Host Analysis`.
5. Wait for `Host Analysis Status` to show `Ready (... frames)`.

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
  correction is bypassed; the default is `1.0`, and at `1` long-window turn smoothing is
  strongest. The X/Y turn bands are measured from the Footstep Jitter baseline instead of
  the raw frame path, so short landing shock is not reintroduced by turn smoothing.
- `Turn Detection Window`: centered smoothing window for walking turns. In Host Analysis
  mode this is evaluated against prepared motion paths during render, so changing the slider
  does not require rebuilding analysis.
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
- `Sample Width`: analysis image width. The sample height is calculated from the current
  source frame aspect ratio. The default is `720` pixels. Width values above the current
  source frame width use the source frame size before Host Analysis runs. Long clips still
  use the requested width unless it exceeds the source frame width. The actual size is shown
  in `Stabilizer Info`.
- `Edge Display Mode`: `Stretch Edges` keeps the previous preview behavior by extending
  edge pixels outside the transformed source image. `Black Outside` draws those outside
  pixels black so the viewer shows how far stabilization is moving the image.
- `Start Host Analysis`: resets the current in-memory host-analysis frames, reloads a saved
  persistent cache if one exists, and only asks Final Cut Pro to start a forward GPU
  analysis when no saved cache can be loaded. Saved cache files remain available for later
  reuse. If the previous cache was rejected for the current clip, the next start skips that
  rejected cache and requests a new analysis.
- Persistent analysis reuse is based on cache schema and current source-frame validation,
  not the loaded FxPlug runtime version. Render-only runtime updates should reuse the saved
  Host Analysis cache.
- `Clear Host Analysis Cache`: deletes the saved Host Analysis cache set and shows
  `Cache Cleared`.
- `Host Analysis Status`: read-only status for analysis and cache reuse.
- `Stabilizer Info`: scrollable read-only runtime and analysis metadata. It shows the
  loaded FxPlug version, active correction bands (`Footstep jitter`, `Walking Bob`,
  `Turn Smoothing`), plus completed analysis time, frame count, actual sample image size, source
  frame size, and pixel transform scale when analysis is available.
- `Debug Overlay`: top-left diagnostics for X/Y/rotation while checking runtime behavior.
  When enabled, `Host Analysis Status` also shows the current Y correction split into
  turn, footstep, and walking-bob components plus separate `footstep q` and `bob q`
  confidence values.

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
- Host Analysis reads `Sample Width` once when analysis starts. Long-clip analysis keeps
  the requested sample size and streams frame-to-frame motion directly through Metal while
  retaining only the previous luma buffer needed for the next motion search. It does not
  write per-frame `.luma` scratch files.
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
  frame-to-frame block matching on every rendered playback frame.
- If a saved Host Analysis cache is loaded while Final Cut Pro is currently playing proxy
  media, render playback uses the loaded cache immediately instead of requiring re-analysis;
  original-media validation can happen later when original frames are available.
- Render playback combines `Turn Smoothing Strength` and the long `Turn Detection Window`
  path with a per-frame Footstep Jitter impulse path and a Y-only `Walking Bob Window`
  band-pass path. Y correction is always evaluated as Footstep Jitter first, Turn Smoothing
  second, and Walking Bob last. Turn smoothing uses the footstep-cleaned Y baseline rather
  than the raw frame path, and Walking Bob removes only the remaining medium-period Y band,
  so large walking-gimbal sway, fine high-frequency shake, and footstep vertical bobbing can
  be tuned separately without rerunning Host Analysis.
- Host Analysis cache schema `7` stores the far-field-prioritized multi-block motion path
  with confidence and accepted-block counts. Older prepared caches are ignored and require a
  new Host Analysis run.
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

In sandboxed FxPlug runs, macOS may redirect that Application Support path into the current
plug-in container. The loader also checks current and legacy Stabilizer container cache
locations so a bundle-id or runtime migration does not require rerunning analysis when the
cache schema is still supported.

The cache index is written to:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-index-v2.json
```

Range-specific cache files are stored under:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/
```

On load, the effect validates the current source frame against saved frame fingerprints
before using a persisted cache. Rejected cache candidates are visible in logs/status and
left on disk for other clips.

New cache files store prepared motion paths, per-frame timestamps, blur values, and
fingerprints instead of every frame's full luma sample. This keeps cache reuse available
without writing long-clip `Sample Width` pixel buffers into JSON.

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
