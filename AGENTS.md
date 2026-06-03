# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory hosts one CommandPost plugin repo for applying a dynamic Transform-keyframe
stabilization workflow to a selected Final Cut Pro timeline clip.

Primary action:

- `Stabilizer: Transform Keyframes`

The plugin intentionally does not use Final Cut Pro's built-in `Stabilization`, because
that effect applies its own internal crop/scale. It uses Final Cut Pro's `Transform`
controls instead. A local Python estimator reads the selected clip's pasteboard media
path/range, analyzes source-frame motion with `ffmpeg`/`ffprobe`, and produces Transform
Position/Rotation/Scale keyframe values.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  init.lua
  stabilizer.lua
  scripts/
  docs/
  installed_backups/
```

Keep `init.lua` as the CommandPost entry point and keep workflow logic in
`stabilizer.lua`. Keep source-media analysis helpers in `scripts/`.

## Test Project

Use this local Final Cut Pro library for manual end-to-end testing:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/test.fcpbundle
```

It is a shared workspace test fixture, outside this plugin repo. Use it when checking
the Stabilizer actions against real selected timeline clips in Final Cut Pro.

## Installed CommandPost Layout

Use a small installed bootstrap at:

```text
/Users/justadev/Library/Application Support/CommandPost/Plugins/Stabilizer/init.lua
```

The bootstrap should load this repo's `init.lua`. Keep implementation files in the repo,
not in the installed CommandPost plugin folder.

Do not add a repo source watcher.

## Version Visibility

Keep `PLUGIN_VERSION` in `init.lua`, expose it through the returned module as `_version`,
and bump it for user-visible behavior changes.

## Verification

After Lua edits, run:

```sh
luac -p init.lua stabilizer.lua
python3 -m py_compile scripts/estimate_stabilization_scale.py
git diff --check -- init.lua stabilizer.lua scripts/estimate_stabilization_scale.py AGENTS.md README.md docs/usage.md
```
