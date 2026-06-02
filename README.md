# Final Cut Pro Stabilizer

CommandPost plugin for applying one dynamic Final Cut Pro stabilization workflow to a
selected timeline clip.

## Action

- `Stabilizer: Dynamic Strength Scale`
  - Analyzes the selected clip's source media from an exported FCPXML.
  - Estimates global motion, fine gimbal jitter, and uneven pan/rotation movement.
  - Keyframes SmoothCam stabilization strength over time.
  - Keyframes Transform Scale All from the estimated stabilization margin so calmer
    sections use less scale and shakier sections use more scale to hide stabilization
    edges.

The action uses Final Cut Pro's built-in Video Inspector controls. Select exactly one
timeline clip, export an FCPXML for the timeline/project, then run the action from
CommandPost and choose that FCPXML when prompted.

## Install

This repo is intended to be loaded by a small CommandPost bootstrap:

```lua
return dofile("/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer/init.lua")
```

Installed bootstrap path:

```text
/Users/justadev/Library/Application Support/CommandPost/Plugins/Stabilizer/init.lua
```
