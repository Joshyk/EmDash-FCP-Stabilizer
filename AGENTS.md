# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory hosts one CommandPost plugin repo for applying Final Cut Pro stabilization
presets to selected timeline clips.

Primary actions:

- `Stabilizer: Walking Gimbal Shake`
- `Stabilizer: Walking Gimbal Pan Smooth`

The plugin uses Final Cut Pro's built-in Video Inspector `Stabilization` and
`Rolling Shutter` controls. It does not ship a custom video-analysis engine or Motion
effect.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  init.lua
  stabilizer.lua
  docs/
  installed_backups/
```

Keep `init.lua` as the CommandPost entry point and keep workflow logic in
`stabilizer.lua`.

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

## Version Visibility

Keep `PLUGIN_VERSION` in `init.lua`, expose it through the returned module as `_version`,
and bump it for user-visible behavior changes.

Runtime verification target:

```lua
cp.plugins.getPluginModule("finalcutpro.stabilizer")._version
```

## Verification

After Lua edits, run:

```sh
luac -p init.lua stabilizer.lua
git diff --check -- init.lua stabilizer.lua AGENTS.md README.md docs/usage.md
```

If runtime verification is possible, reload CommandPost and query the module version via
`cmdpost`.
