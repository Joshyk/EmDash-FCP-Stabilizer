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
  - Keyframes Transform Position and Rotation to counter estimated camera motion,
    using sub-pixel translation refinement so small shakes do not collapse to 0.
  - Keyframes Transform Scale All only as much as needed to hide exposed edges.
  - Keeps progress alerts and routine progress logs off while processing.

The action uses Final Cut Pro's built-in Transform controls, not Final Cut Pro's
Stabilization effect. Select exactly one timeline clip, then run the action from
CommandPost. The plugin does not export or import XML; it uses Final Cut Pro's Edit >
Copy pasteboard data for the selected clip.

Native FxPlug migration work lives under `fxplug/StabilizerFxPlug/`. That buildable Xcode
project is separate from the active CommandPost plugin and applies automatic X/Y/Z-scale
and rotation compensation as a native Final Cut Pro effect without writing Transform
keyframes. The native effect supports `Analysis Source` = `Host Analysis` and `Live Frames`.
`Host Analysis` is the primary long-term path through Final Cut Pro's FxPlug analysis
infrastructure and can be started explicitly with `Start Host Analysis`; `Live Frames`
requests render-time source frames directly. It also evaluates yaw/pitch proxy motion, shear,
perspective warp, crop safety, and blur amount from regional source-frame motion. The shared
Xcode scheme installs each successful Debug build to
`/Applications/StabilizerFxPlug.app` and registers its embedded FxPlug so Final Cut Pro
can load the effect from that persistent app path.

Transform keyframes are created through CommandPost's official video inspector keyframe
API before values are written into the keyframe, then confirmed from the Transform row
controls when Final Cut Pro exposes that state. If Final Cut Pro keeps reporting Add
Keyframe after the API call, the action logs the unconfirmed state and continues, matching
the Auto White Balance keyframe writer's behavior.

## Install

This repo is intended to be loaded by a small CommandPost bootstrap:

```lua
return dofile("/Users/justadev/Developer/EDT/Command-Post-Em_Dash/Stabilizer/init.lua")
```

Installed bootstrap path:

```text
/Users/justadev/Library/Application Support/CommandPost/Plugins/Stabilizer/init.lua
```

## Development Reload

CommandPost does not auto reload this repo when Lua, Swift, or Python files change. After a
programming update, manually reload or restart CommandPost before running the action or
checking runtime version/output.

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
