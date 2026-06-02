# Usage

1. Select exactly one video clip in the Final Cut Pro timeline.
2. Export an FCPXML for the current timeline/project.
3. Run `Stabilizer: Dynamic Strength Scale`.
4. Choose a keyframe interval when prompted.
5. Choose the exported `.fcpxml` or `.fcpxmld` when prompted.
6. If Final Cut Pro is still analyzing stabilization, wait for analysis to finish and run
   the action again if the plugin reports disabled controls.

## Behavior

- The plugin analyzes source-frame changes from the FCPXML media reference.
- It converts the estimated motion into keyframes for SmoothCam strength controls.
- It keyframes Transform Scale All from the same strength estimate.
- Low-motion sections stay close to 100% scale.
- High-motion sections scale up more to hide edges created by stabilization.

## Controls

- Stabilization: enabled
- Method: SmoothCam
- Translation Smooth: keyframed from estimated motion
- Rotation Smooth: keyframed from estimated motion
- Scale Smooth: keyframed from estimated motion
- Transform Scale All: keyframed from estimated motion
- Rolling Shutter: unchanged
