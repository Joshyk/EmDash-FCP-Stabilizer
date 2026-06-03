# Usage

1. Select exactly one video clip in the Final Cut Pro timeline.
2. Run `Stabilizer: Transform Keyframes`.
3. Choose a keyframe interval when prompted. Use `5` or `10` frames when the clip has
   fine gimbal jitter.
4. CommandPost selects the clip, runs Final Cut Pro's Edit > Copy, and reads the selected
   clip range plus source media path from the pasteboard.
5. The action turns Final Cut Pro's built-in Stabilization off and writes Transform
   keyframes instead.

## Behavior

- The plugin analyzes source-frame motion from the selected clip's pasteboard media reference.
- It builds a smoothed camera path and keyframes Transform Position/Rotation to counter
  the difference between the original path and the smoothed path.
- It keyframes Transform Scale All from the strongest required visible-edge margin.
- Low-motion sections stay close to 100% scale.
- High-motion sections scale up only as needed to hide Transform-created edges.

## Controls

- Stabilization: disabled
- Transform Position: keyframed from estimated translation compensation
- Transform Rotation: keyframed from estimated uneven roll/pan compensation
- Transform Scale All: keyframed from the estimated edge margin
- Rolling Shutter: unchanged
