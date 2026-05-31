# Final Cut Pro Stabilizer

CommandPost plugin for applying Final Cut Pro stabilization presets to selected
timeline clips.

## Actions

- `Stabilizer: Walking Gimbal Shake`
  - Uses SmoothCam.
  - Higher translation smoothing for walking bounce and handheld drift.
  - Medium rolling shutter correction.

- `Stabilizer: Walking Gimbal Pan Smooth`
  - Uses InertiaCam.
  - Lower smoothing so intentional gimbal pans stay alive.
  - Low rolling shutter correction.

- `Stabilizer: Dynamic Auto Scale`
  - Uses Final Cut Pro's Automatic stabilization method.
  - Lets Final Cut Pro apply dynamic scaling based on its stabilization analysis.
  - Leaves Rolling Shutter unchanged.

The actions use Final Cut Pro's built-in Video Inspector controls. Select one or more
timeline clips, then run an action from CommandPost.

## Install

This repo is intended to be loaded by a small CommandPost bootstrap:

```lua
return dofile("/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer/init.lua")
```

Installed bootstrap path:

```text
/Users/justadev/Library/Application Support/CommandPost/Plugins/Stabilizer/init.lua
```
