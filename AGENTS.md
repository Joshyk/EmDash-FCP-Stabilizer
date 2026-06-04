# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory hosts one CommandPost plugin repo for applying a dynamic Transform-keyframe
stabilization workflow to a selected Final Cut Pro timeline clip.

Primary action:

- `Stabilizer: Transform Keyframes`
- `Stabilizer: Analyze FxPlug Cache`

The plugin intentionally does not use Final Cut Pro's built-in `Stabilization`, because
that effect applies its own internal crop/scale. It uses Final Cut Pro's `Transform`
controls instead. A local Python estimator reads the selected clip's pasteboard media
path/range, analyzes source-frame motion with `ffmpeg`/`ffprobe`, and produces Transform
Position/Rotation/Scale keyframe values. The estimator also detects source-frame black
strips and folds that correction into Transform Position and Scale keyframes.

The workflow must not show progress alerts or routine progress logs during selection,
pasteboard read, estimator execution, or Transform keyframe writing. Keep failure logs and
user-facing errors clear. Keyframe writes must use CommandPost's official video inspector
keyframe API for each Transform row before writing values into that keyframe. If Final Cut
Pro keeps reporting Add Keyframe after the API call, continue AutoWB-style and only surface
that state when a failure path needs diagnostics.

`Stabilizer: Analyze FxPlug Cache` uses the same selected-clip pasteboard source path and
writes the native FxPlug prerender cache here:

```text
/Users/justadev/Library/Application Support/CommandPost/StabilizerFxPlug/current.json
```

The native `Stabilizer Transform` FxPlug reads that cache when `Use Prerender Cache` is
enabled. If the cache is missing, the FxPlug live-analysis path is used; keep that visible
in README/docs when changing behavior. Unlike the Transform keyframe writer, the cache action
may show a compact progress bar because it is an explicit long-running prerender step.
The cache action should use `scripts/estimate_stabilization_gpu.swift`, with
AVFoundation/VideoToolbox decode and Metal compute downsampling/block matching. Do not add
a hidden Python CPU fallback for this cache path.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  init.lua
  stabilizer.lua
  scripts/
  docs/
  fxplug/
  installed_backups/
```

Keep `init.lua` as the CommandPost entry point and keep workflow logic in
`stabilizer.lua`. Keep source-media analysis helpers in `scripts/`.

`fxplug/` is a separate native Final Cut Pro/Motion FxPlug 4 migration scaffold. Do not
mix FxPlug source into the CommandPost runtime path. The FxPlug target requires full Xcode
and the local FxPlug SDK; the CommandPost Lua plugin remains the active runtime until an
FxPlug wrapper app/plugin is validated in Final Cut Pro. The Xcode project lives at
`fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj`.

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

Lua, Swift, Python, or other programming updates should take effect only after a manual CommandPost
reload or restart.

CommandPost reload shortcut exists now.

On this machine, `cpr` or `cmdpost-reload` requests a CommandPost reload quickly. It
lives at `/usr/local/bin/cmdpost-reload`, with `/usr/local/bin/cpr` symlinked to it.

Codex must ask the user before reloading CommandPost. Use a Yes/No confirmation button
when the UI supports it; otherwise ask a clear text question and wait for the answer. Only
run `cpr`, `cmdpost-reload`, or any `cmdpost` command that calls `hs.reload()` after the
user explicitly answers Yes. If the user answers No or does not answer, do not reload and
state that reload-dependent runtime verification was skipped. Treat indirect reload
triggers through aliases, scripts, shell command substitution, or helper commands as reload
attempts that require the same approval.

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

## Version Visibility

Keep `PLUGIN_VERSION` in `init.lua`, expose it through the returned module as `_version`,
and bump it for user-visible behavior changes.

## Verification

After Lua edits, run:

```sh
luac -p init.lua stabilizer.lua
python3 -m py_compile scripts/estimate_stabilization_scale.py
/usr/bin/xcrun swiftc -parse scripts/estimate_stabilization_gpu.swift
git diff --check -- init.lua stabilizer.lua scripts/estimate_stabilization_scale.py scripts/estimate_stabilization_gpu.swift AGENTS.md README.md docs/usage.md
```

After FxPlug edits, also run:

```sh
xcodebuild -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj -scheme StabilizerFxPlug -configuration Debug -derivedDataPath /tmp/StabilizerFxPlugDerived build
pluginkit -m -A -p FxPlug -i com.justadev.CommandPostEmDash.StabilizerFxPlug.Plugin
git diff --check -- fxplug/StabilizerFxPlug
```

The `StabilizerFxPlug` shared scheme has a post-build action that runs
`fxplug/StabilizerFxPlug/scripts/install_debug_app.sh`. A successful build should install
`/Applications/StabilizerFxPlug.app`, copy the Motion Template into the user's Movies
Motion Templates folder, and register its embedded pluginkit for Final Cut Pro.
