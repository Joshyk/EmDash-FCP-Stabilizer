# Final Cut Pro Stabilizer

CommandPost plugin for applying one Transform-keyframe stabilization workflow to a
selected Final Cut Pro timeline clip.

## Action

- `Stabilizer: Transform Keyframes`
  - Copies the selected timeline clip and analyzes its source media from Final Cut Pro's pasteboard metadata.
  - Estimates global motion, fine gimbal jitter, and uneven pan/rotation movement.
  - Detects source-frame black strips and folds the required correction into
    Transform Position and Scale All keyframes.
  - Turns Final Cut Pro's built-in Stabilization off for the selected clip.
  - Keyframes Transform Position and Rotation to counter estimated camera motion.
  - Keyframes Transform Scale All only as much as needed to hide exposed edges.
  - Shows progress alerts while reading, estimating, and writing Transform keyframes.

The action uses Final Cut Pro's built-in Transform controls, not Final Cut Pro's
Stabilization effect. Select exactly one timeline clip, then run the action from
CommandPost. The plugin does not export or import XML; it uses Final Cut Pro's Edit >
Copy pasteboard data for the selected clip.

If a Transform keyframe button cannot be confirmed, the action stops with an alert and
logs the active stage, sample, target timecode, and exposed Final Cut Pro row buttons.

## Install

This repo is intended to be loaded by a small CommandPost bootstrap:

```lua
return dofile("/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer/init.lua")
```

Installed bootstrap path:

```text
/Users/justadev/Library/Application Support/CommandPost/Plugins/Stabilizer/init.lua
```
