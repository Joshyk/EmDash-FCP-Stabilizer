# Final Cut Pro Stabilizer

Native FxPlug 4 effect for Final Cut Pro and Motion, tuned for walking footage
shot on a gimbal.

This repo is FxPlug-only. It does not contain or support a CommandPost runtime,
standalone estimator, cache generator, or Transform-keyframe writer.

## What It Does

`Stabilizer Transform` renders the source clip through Metal and applies
automatic stabilization inside the FxPlug render path. It avoids Final Cut Pro's
built-in Stabilization effect because that effect applies its own internal crop
and scale.

The effect is designed for outdoor walking shots where the camera is already on
a gimbal but still has step shock, short wobble, vertical bob, segmented turns,
and distant ridge-line shake.

The main correction stages are:

- `Footstep Jitter`: frame-local X/Y/roll impulse removal for landing shock.
- `Stride Wobble`: medium-period X/Y/roll cleanup between footstep shock and
  broad bob.
- `Turn Smoothing`: X-only smoothing for stop-and-go walking turns.
- `Walking Bob`: Y-only correction for longer vertical walking bounce.
- `Far-field Warp Strength`: small-clamp deskew, yaw/pitch proxy, and
  perspective trim for distant background shake.

The effect keeps render scale fixed at `1.0`. Edge fill is controlled separately
by `Edge Display Mode`, which switches between stretched source edges and black
outside-source pixels.

## Basic Workflow

1. Apply `Stabilizer Transform` to a clip.
2. Choose `Sample Size`.
3. Click `Start Host Analysis`.
4. Wait for `Host Analysis Status` to show `Ready (... frames)`.
5. Tune the strength controls while watching the preview.

`Start Host Analysis` is the only path that asks Final Cut Pro to analyze the
clip. Preview and render callbacks only read completed analysis or a validated
persistent cache; they do not start analysis on their own.

## Inspector Controls

`Sample Size` is read once when analysis starts. It is always derived from the
original clip dimensions, with `100%`, `75%`, `50%`, `25%`, and `10%` options.
Long clips keep the requested percentage instead of silently lowering it.

`Overall Strength` controls the full automatic transform. Setting it to `0`
bypasses prepared motion-path sampling, crop-safety motion, and debug overlay
output, producing an identity transform.

`Footstep Jitter` strengths are direct removal amounts for frame-local X, Y, and
roll impulses. They run up to `4.0`; values above `1.0` can compensate when
tracking confidence makes the correction too weak. The applied correction still
clamps at full detected-impulse removal so it does not add inverse shake.

`Stride Wobble` removes step follow-through shake using a fixed internal
`0.70` second render-time window. The Inspector exposes only X, Y, and rotation
strengths. It is measured from the footstep-cleaned path, then longer Turn
Smoothing and Walking Bob bands are measured from the stride-smoothed path so
the same motion is not removed twice.

`Turn Smoothing Strength` smooths segmented horizontal walking turns into a
more continuous S-curve intent. It applies only to X translation, does not change
Y or roll, and is soft-limited to a small output-edge budget during render.

`Walking Bob Window` and `Walking Bob Removal` target the remaining vertical
walking bounce after Footstep Jitter and Stride Wobble. Walking Bob does not gate
or weaken Footstep Jitter Y. The default removal is `0.75`; shorter windows
around `0.4-1.0` seconds target visible footstep bounce.

`Far-field Warp Strength` bundles small-clamp shear, yaw/pitch proxy, and
perspective trim for distant background motion. It is applied from the current
frame's local deviation from an outer-frame linear baseline, so long-term drift
does not become a fixed deskew. The default is `1.0`, and the maximum is `4.0`.

`Debug Overlay` shows labeled top-left diagnostics for the active correction
bands and tracking state. It does not control black outside-source pixels;
`Edge Display Mode` controls that separately.

`Stabilizer Info` is a scrollable read-only status box. It shows the loaded
FxPlug version, active correction bands, and analysis metadata so Final Cut Pro
can confirm which installed runtime is actually rendering the effect.

## Host Analysis

Host Analysis uses Final Cut Pro's FxPlug analysis infrastructure to request GPU
analysis frames from the host. The plug-in then uses Metal compute to downsample
luma and run frame-to-frame block matching. If Metal analysis resources are not
available, the Host Analysis path fails visibly in status/log output instead of
falling back to CPU analysis.

The analysis path:

- Streams frame-to-frame motion through Metal.
- Keeps only the previous luma buffer needed for the next motion search.
- Does not write per-frame `.luma` scratch files.
- Prioritizes upper-frame far-field blocks for walking landscape footage.
- Rejects outlier blocks before building the frame path.
- Exposes low tracking confidence instead of hiding it behind coarse fallback
  motion.

Prepared paths are post-processed with a zero-phase jerk limiter before caching.
The limiter clamps isolated acceleration spikes in X/Y/roll while preserving
path endpoints and total analyzed turn amount. Raw X/Y/roll impulse paths are
stored separately so Footstep Jitter can still correct frame-level shake at
render time.

Render-time smoothing samples neighboring render times symmetrically and blends
the automatic transform with zero phase. It smooths Turn Smoothing and Walking
Bob bands without averaging away the current frame's Footstep Jitter impulse.

Trimmed clips are handled by matching the current render frame fingerprint back
to the analyzed frame set and applying that time offset before sampling the
prepared motion paths. A validated analysis continues to drive preview/render
when Final Cut Pro plays proxy media; proxy media is rejected only for Host
Analysis input and for validating an unvalidated cache.

## Cache Behavior

Completed Host Analysis is written to the shared user cache:

```text
/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json
/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-index-v2.json
/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/
```

Cache files store prepared paths, frame timing, blur values, search-radius
edge-hit counts, warp values, confidence metadata, and fingerprints instead of
every frame's full luma sample.

`Start Host Analysis` first tries to reload a saved cache. It starts a new host
analysis only when no compatible saved cache can be loaded. It must not delete
saved cache files.

Cache reuse is based on cache schema and current source-frame validation, not
the visible FxPlug runtime version. Render-only version bumps should reuse
compatible Host Analysis caches.

Rejected cache candidates are visible in status/log output and are remembered by
file identity inside the active runtime, so the same invalid candidate is not
loaded again on the next start. Rejected files remain on disk. `Clear Host
Analysis Cache` is the explicit delete path and shows `Cache Cleared`.

Unsupported schema candidates show `Cache Unsupported - Run Host Analysis`
instead of being silently ignored or deleted. This keeps stale caches available
for older builds while the current effect asks for a new analysis.

The active runtime uses a process-wide shared Host Analysis store because Final
Cut Pro may call setup, frame analysis, cleanup, preview, and render through
different FxPlug instances. Persistent cache files are the cross-process reuse
path. Preview/render instances with no prepared analysis watch for cache file
changes and reload validated candidates on demand.

## Diagnostics

`Debug Overlay` reports final `X`/`Y`/`ROLL`, `TURN`, `F+SW`, `BOB`, `SMTH`,
live `F Q`/`S Q`/`B Q`/`W Q` confidence, `TRK`, `BLUR`, `RES`, and
search-radius `HIT` bars. Labels use raw English control/diagnostic abbreviations;
do not translate them in the preview.

The overlay bars are normalized magnitudes or quality signals, not signed directions:

- `X`: final horizontal automatic correction.
- `Y`: final vertical automatic correction.
- `ROLL`: final automatic roll/rotation correction.
- `TURN`: X-only Turn Smoothing correction for stop-and-go pan motion.
- `F+SW`: combined Footstep Jitter plus Stride Wobble correction activity.
- `BOB`: Y-only Walking Bob correction.
- `SMTH`: render-time temporal smoothing delta.
- `F Q`: Footstep Jitter confidence.
- `S Q`: Stride Wobble confidence.
- `B Q`: Walking Bob confidence.
- `W Q`: Far-field Warp confidence.
- `TRK`: current frame tracking quality after motion evidence, residual, blur, and block coverage.
- `BLUR`: frame clarity signal; higher means less blur.
- `RES`: block-matching residual/error signal; higher means noisier tracking evidence.
- `HIT`: share of searches that hit the motion search-radius edge; higher means the search radius may be too tight for that frame.

`Host Analysis Status` also reports:

- `footstep q` and effective Footstep Jitter X/Y/R strength.
- `stride q` and effective Stride Wobble X/Y/R strength.
- `bob q`.
- `warp q`.
- Tracking and motion confidence.
- Blur and residual error.
- Search-radius edge-hit counts.
- Current warp shape values.

Values above `1.0` on Footstep, Stride, and Bob controls boost low-confidence
corrections with a curved confidence response, so saved clips at `4.0` do not
snap medium-confidence frames straight to full correction.

## Build

Build the wrapper app and embedded FxPlug:

```sh
xcodebuild \
  -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj \
  -scheme StabilizerFxPlug \
  -configuration Debug \
  -derivedDataPath /tmp/StabilizerFxPlugDerived \
  build
```

The shared scheme installs each successful Debug build to:

```text
/Applications/StabilizerFxPlug.app
```

It also installs the Motion Template under the user's Movies Motion Templates
folder and registers the embedded FxPlug with PluginKit. Debug installs remove
stale `Stabilizer Transform copy...` Motion Template folders from the
`Emdash Studios` group so Finder-created duplicates do not appear as extra
effects in Final Cut Pro.

Verify registration:

```sh
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
```

Restart Final Cut Pro after rebuilding if it was already open.
