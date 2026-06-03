# Usage

1. Select exactly one video clip in the Final Cut Pro timeline.
2. Run `Stabilizer: Transform Keyframes`.
3. Choose a keyframe interval from `1,2,3,4,5,6` when prompted. Use `1` or `2`
   frames when the clip has fine gimbal jitter.
4. CommandPost selects the clip, runs Final Cut Pro's Edit > Copy, and reads the selected
   clip range plus source media path from the pasteboard.
5. The action turns Final Cut Pro's built-in Stabilization off and writes Transform
   keyframes instead.
6. Progress alerts appear while the action reads the clip, runs the estimator, and writes
   each Transform keyframe sample.

## Behavior

- The plugin analyzes source-frame motion from the selected clip's pasteboard media reference.
- It builds a smoothed camera path and keyframes Transform Position/Rotation to counter
  the difference between the original path and the smoothed path.
- It detects black strips in source frames, recenters the visible content with Transform
  Position, and keyframes Transform Scale All from the strongest required visible-edge
  or black-strip margin.
- It smooths Transform Scale All over about 4 seconds so zoom changes ramp instead of
  stepping between keyframes.
- Low-motion sections stay close to 100% scale.
- High-motion sections scale up only as needed to hide Transform-created edges.
- Black-strip removal is source-frame based. If a Final Cut Pro effect creates black
  after rendering, the CommandPost log's `blackScale` and `blackOffset` values show
  whether the estimator saw it.

## Controls

- Stabilization: disabled
- Transform Position: keyframed from estimated translation compensation plus black-strip recentering
- Transform Rotation: keyframed from estimated uneven roll/pan compensation
- Transform Scale All: keyframed from the estimated edge margin
- Rolling Shutter: unchanged

## Error Logging

- If Transform keyframe creation cannot be confirmed, the action stops instead of reporting
  success.
- The CommandPost Console log includes the failed stage, sample index, target timecode, and
  the Final Cut Pro row button summaries exposed through accessibility.

## Development Reload

CommandPost does not auto reload this repo when Lua or Python files change. After a
programming update, manually reload or restart CommandPost before running the action.

CommandPost reload shortcut exists now.

On this machine, run `cpr` or `cmdpost-reload` to request a CommandPost reload quickly. It
lives at `/usr/local/bin/cmdpost-reload`, with `/usr/local/bin/cpr` symlinked to it.

It calls:

```sh
/Applications/CommandPost.app/Contents/Frameworks/hs/cmdpost -A -q -t 1 -c 'hs.reload()'
```

Important: the command returns quickly after requesting reload, but CommandPost itself can
take tens of seconds before IPC is reachable again. To verify it came back:

```sh
/Applications/CommandPost.app/Contents/Frameworks/hs/cmdpost -q -t 6 -c 'return hs.application.nameForBundleID("org.latenitefilms.CommandPost")'
```

Expected output:

```text
CommandPost
```
