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
- `Walking Bob`: Y-only correction for longer vertical walking bounce.
- `Far-field Warp Strength`: small-clamp deskew, yaw/pitch proxy, and
  perspective trim for distant background shake.
- `Turn Smoothing`: X-only smoothing for stop-and-go walking turns.

The effect keeps render scale fixed at `1.0`. Edge fill is controlled separately
by `Edge Display Mode`, which switches between stretched source edges and black
outside-source pixels.

## Basic Workflow

1. Apply `Stabilizer Transform` to a clip.
2. Keep the default `10%` `Sample Size` for a quick debug pass, or choose a
   larger sample before starting analysis.
3. Click `Start Host Analysis`.
4. Wait for `Host Analysis Status` to show `Ready (... frames)`.
5. Tune the strength controls while watching the preview.

`Start Host Analysis` is the only path that asks Final Cut Pro to analyze the
clip. Preview and render callbacks only read completed analysis or a validated
persistent cache; they do not start analysis on their own.

## Inspector Controls

`Sample Size` is read once when analysis starts. It is always derived from the
original clip dimensions, with `100%`, `75%`, `50%`, `25%`, and `10%` options.
The default is `10%` so Debug Overlay tuning can start quickly. Long clips keep
the requested percentage instead of silently lowering it.

`Overall Strength` controls the full automatic transform. Setting it to `0`
bypasses prepared motion-path sampling, crop-safety motion, and debug overlay
output, producing an identity transform.

`Footstep Jitter` strengths are direct removal amounts for frame-local X, Y, and
roll impulses. They run up to `4.0`; values above `1.0` can compensate when
tracking confidence makes the correction too weak. The applied correction still
clamps at full detected-impulse removal so it does not add inverse shake. The
baseline uses seconds, not frame counts: it skips the center `0.10` second shock
region and predicts from outer samples up to `1.0` second away. Confidence is
based on current tracking evidence, local baseline support, and the center
frame's impulse relative to surrounding footstep noise. Moderate landing impulses now reach
useful confidence a little sooner, while zero evidence and noisy unsupported frames still
produce zero correction.

`Stride Wobble` removes step follow-through shake using a fixed internal
`2.0` second render-time window. The Inspector exposes only X, Y, and rotation
strengths. It is measured from the footstep-cleaned path, then longer Turn
Smoothing and Walking Bob bands are measured from the stride-smoothed path so
the same motion is not removed twice. It does not use the raw or jerk-limited
broad path as its band input. Its residual gate uses robust window percentiles
instead of letting a single bad frame suppress the whole band. Medium stride
bands reach full confidence earlier than the broad UI scale so real walking
follow-through is not left entirely to the longer Walking Bob pass; the Y default
is `0.50`, still lower than X/roll but no longer near-minimal.

`Turn Smoothing Strength` smooths segmented horizontal walking turns into a
more continuous S-curve intent. It applies only to X translation, does not change
Y or roll, and is soft-limited to a small output-edge budget during render.
`Turn Detection Window` comes from the Inspector UI value. Its UI minimum is the
fixed `2.0` second Stride Wobble window, so TURN cannot run shorter than SWOB.
TURN confidence now requires both tracking evidence and a real X turn band, so
low-evidence frames do not get a hidden minimum turn correction.

`Walking Bob` uses a fixed internal `2.5` second Y-only baseline for the remaining
vertical walking bounce after Footstep Jitter and Stride Wobble. The shorter window keeps
BOB from turning weak vertical evidence into a slow image wave. The Inspector
exposes only `Walking Bob Removal`; it does not gate or weaken Footstep Jitter Y.
Its confidence uses current tracking quality, symmetric window support, robust
residuals, and actual Y-band magnitude so weak tracking, one-sided clip-edge
windows, or tiny vertical bands do not create large vertical waves. The default
removal is `0.75`.

`Far-field Warp Strength` bundles small-clamp shear, yaw/pitch proxy, and
perspective trim for distant background motion. It is applied from the current
frame's local deviation from its own `1.0` second outer-frame linear baseline,
so long-term drift does not become a fixed deskew. The default is `1.0`, and the
maximum is `4.0`. The render path gates warp with walking-footage tracking quality and
search-radius headroom. The tracking gate now starts earlier for moderate
25% Host Analysis evidence, then curves medium-confidence gates upward and
drops tiny warp deltas through a deadband so useful ridge-line correction is
less likely to disappear while low-confidence warp evidence is still suppressed
instead of producing a wavy image.

`Debug Overlay` shows labeled top-left diagnostics for the active correction
bands and tracking state. It also includes a compact runtime-version row for the
active render runtime. It does not control black outside-source pixels;
`Edge Display Mode` controls that separately.

`Host Analysis Status` appends the current FxPlug version when Final Cut Pro
accepts status parameter updates. For existing timeline instances that keep
stale saved Inspector strings, `Debug Overlay` is the live render-runtime
indicator. `Stabilizer Info` is a scrollable read-only status box for active
correction bands and analysis metadata; older saved timeline instances may still
display a stale saved info string until the effect is reapplied.

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

Render-time smoothing samples neighboring render times symmetrically across a
`1.20` second zero-phase window and blends the automatic transform. At clip
edges it averages only in-range neighboring samples instead of duplicating the
first or last analysis frame. It smooths Stride Wobble, Walking Bob, Far-field
Warp, and Turn Smoothing bands without averaging away the current frame's
Footstep Jitter impulse.

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
every frame's full luma sample. Cache writing uses the prepared analysis frame
set as the authoritative timeline, so a reduced retained source-frame map does
not prevent a completed prepared path from being saved.

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
for older builds while the current effect asks for a new analysis. Supported-schema
caches with incomplete prepared path arrays show `Cache Incomplete - Run Host Analysis`
so older incomplete analysis is not silently ignored.

The active runtime uses a process-wide shared Host Analysis store because Final
Cut Pro may call setup, frame analysis, cleanup, preview, and render through
different FxPlug instances. Persistent cache files are the cross-process reuse
path. Preview/render instances with no prepared analysis watch for cache file
changes and reload validated candidates on demand.

## Diagnostics

`Debug Overlay` reports final `X`/`Y`/`ROLL`, `FJIT`, `SWOB`, `BOB`, `WARP`, `TURN`,
live `F Q`/`S Q`/`B Q`/`W Q`/`T Q` confidence, `SMTH`, `TRK`, `SHRP`, `RES`, and
search-radius `HIT` bars. Labels use raw English control/diagnostic abbreviations;
do not translate them in the preview.

The overlay bars are normalized magnitudes or quality signals, not signed directions:

- `X`: final horizontal automatic correction.
- `Y`: final vertical automatic correction.
- `ROLL`: final automatic roll/rotation correction.
- `FJIT`: Footstep Jitter correction activity from the fixed second-based impulse range.
- `SWOB`: Stride Wobble correction activity from the fixed internal stride-wobble window.
- `BOB`: Y-only Walking Bob correction.
- `WARP`: Far-field Warp correction activity from shear, yaw/pitch proxy, and perspective trim.
- `TURN`: X-only Turn Smoothing correction for stop-and-go pan motion.
- `SMTH`: render-time temporal smoothing delta.
- `F Q`: Footstep Jitter confidence.
- `S Q`: Stride Wobble confidence.
- `B Q`: Walking Bob confidence.
- `W Q`: applied Far-field Warp confidence after tracking and search-radius safety gates.
- `T Q`: Turn Smoothing confidence.
- `TRK`: current frame tracking quality after motion evidence, residual, blur, and block coverage.
- `SHRP`: frame sharpness/clarity quality; higher means less blur.
- `RES`: residual quality; higher means lower block-matching residual/error.
- `HIT`: search-radius headroom quality; higher means fewer searches hit the radius edge.

`TRK`, `SHRP`, `RES`, and `HIT` are all aligned as quality signals: high is good, low is bad.

`Host Analysis Status` also reports:

- The current FxPlug runtime version.
- `footstep q` and effective Footstep Jitter X/Y/R strength.
- `stride q` and effective Stride Wobble X/Y/R strength.
- `bob q`.
- `turn q`.
- `warp q`.
- Tracking and motion confidence.
- Blur and residual error.
- Search-radius edge-hit counts.
- Current warp shape values.

Values above `1.0` on Footstep, Stride, and Bob controls boost low-confidence
corrections with a curved confidence response. The response is more assertive for
medium-confidence frame evidence, but still has no hidden minimum confidence
floor: zero confidence produces zero correction.

## Feedback CLI

Use the local feedback CLI when reviewing notes like `at 5 sec there is a
notable unremoved shake` against a saved Host Analysis cache:

```sh
fxplug/StabilizerFxPlug/scripts/stabilizer_feedback.sh \
  --time 5.0 \
  --note "notable unremoved shake"
```

`--time` is clip-relative: `0.0` is the start of the Host Analysis range saved
in the cache. The CLI reads
`~/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json` by
default, or another cache with `--cache /path/to/host-analysis-v2.json`. Use
`--json` for machine-readable output and `--output-size 1920x1080` when you want
pixel estimates scaled to a target preview size.

Use `--list-caches` to list the latest shared cache and range-specific cache
files under `~/Library/Application Support/StabilizerFxPlug`. It reports each
file as `READY`, `INCOMPLETE`, `UNSUPPORTED`, or `UNREADABLE` without repairing
or deleting anything; add `--cache-root /path/to/root` to inspect another cache
root explicitly.

The report ranks likely remaining `FJIT`, `SWOB`, `BOB`, `TURN`, and `WARP`
bands using the saved prepared paths, tracking confidence, residuals, blur,
block coverage, and search-radius edge-hit counts. The band split mirrors the
render path: `FJIT` is measured first against the outer-frame baseline, then
`SWOB`, `BOB`, and `TURN` are measured from the footstep-cleaned path. `WARP`
`q` matches the applied `W Q` confidence shown by Debug Overlay, and the report
includes FJIT and SWOB per-axis confidence, residual, blur, block coverage,
edge quality, and WARP tracking/edge gate values so over- or under-gating is visible. If a cache has mismatched
frame/path array counts, the CLI fails explicitly and asks for a new Host
Analysis run with the current FxPlug instead of trying to repair the data.

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
