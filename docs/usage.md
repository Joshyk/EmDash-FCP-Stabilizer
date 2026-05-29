# Usage

1. Select one or more video clips in the Final Cut Pro timeline.
2. Run one of these CommandPost actions:
   - `Stabilizer: Walking Gimbal Shake`
   - `Stabilizer: Walking Gimbal Pan Smooth`
3. If Final Cut Pro is still analyzing stabilization, wait for analysis to finish and run
   the action again if the plugin reports disabled controls.

## Presets

### Walking Gimbal Shake

For walking shots where the gimbal removed the big movement but footsteps still create
bounce or jitter.

- Stabilization: enabled
- Method: SmoothCam
- Translation Smooth: 2.4
- Rotation Smooth: 1.1
- Scale Smooth: 0.8
- Rolling Shutter: medium

### Walking Gimbal Pan Smooth

For gimbal walking shots with a pan that should feel smoother without locking the camera
like a tripod.

- Stabilization: enabled
- Method: InertiaCam
- Smoothing: 1.1
- Tripod Mode: off
- Rolling Shutter: low
