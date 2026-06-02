# Usage

1. Select exactly one video clip in the Final Cut Pro timeline.
2. Export an FCPXML for the current timeline/project.
3. Run `Stabilizer: Dynamic Strength Scale`.
4. Choose a keyframe interval when prompted. Use `5` or `10` frames when the clip has
   fine gimbal jitter.
5. Choose the exported `.fcpxml` or `.fcpxmld` when prompted.
6. If Final Cut Pro is still analyzing stabilization, wait for analysis to finish and run
   the action again if the plugin reports disabled controls.

## Behavior

- The plugin analyzes source-frame motion from the FCPXML media reference.
- It separates global translation, fine gimbal jitter, compensated residual motion,
  and uneven pan/rotation movement.
- It converts the estimated gimbal jitter into Translation Smooth keyframes.
- It converts the estimated pan/rotation irregularity into Rotation Smooth keyframes.
- It keyframes Transform Scale All from the strongest required stabilization margin.
- Low-motion sections stay close to 100% scale.
- High-motion sections scale up more to hide edges created by stabilization.

## Controls

- Stabilization: enabled
- Method: SmoothCam
- Translation Smooth: keyframed from estimated gimbal jitter
- Rotation Smooth: keyframed from estimated uneven pan/rotation motion
- Scale Smooth: keyframed from the estimated stabilization margin
- Transform Scale All: keyframed from the estimated stabilization margin
- Rolling Shutter: unchanged
