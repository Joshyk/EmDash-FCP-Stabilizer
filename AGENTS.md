# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory hosts the native `Stabilizer Transform` FxPlug project for Final Cut Pro and
Motion. The project is FxPlug-only. Do not add non-FxPlug runtime files, standalone
estimators, timeline automation actions, legacy cache models, or app reload workflows back
into this repo.

The effect intentionally avoids Final Cut Pro's built-in `Stabilization`, because that
effect applies its own internal crop/scale. The native effect renders a transformed source
texture with Metal and applies automatic walking-gimbal stabilization inside the FxPlug
render path.

The FxPlug uses Final Cut Pro's FxPlug `Host Analysis` infrastructure to request GPU
analysis frames from the host. The native analysis path must use Metal compute inside the
plug-in runtime for luma downsampling and frame-to-frame motion search. Do not add a CPU
analysis fallback; if Metal analysis resources are unavailable, fail the Host Analysis path
visibly in logs/status.

Completed Host Analysis frame sets should be persisted by the FxPlug runtime at
`/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json`,
`/Users/justadev/Library/Application Support/StabilizerFxPlug/host-analysis-index-v2.json`,
and range-indexed files under
`/Users/justadev/Library/Application Support/StabilizerFxPlug/caches/`. Cache candidates
must be validated against the current source frame before reuse. Rejected candidates should
be visible in logs/status and should not be deleted just because they do not match the
current clip. `Start Host Analysis` should first reload and use a saved persistent cache
when one exists; only start a new host analysis when no saved cache can be loaded. It must
not delete saved cache files. If the loaded cache is rejected for the current clip, the next
start should skip that rejected cache and request a new analysis. `Clear Host Analysis
Cache` is the explicit cache-clear path and should show `Cache Cleared`.
Persistent cache compatibility is based on cache schema and current source-frame
validation, not the visible FxPlug runtime version. Render-only version bumps should reuse
saved Host Analysis cache candidates. The loader should also consider current and legacy
Stabilizer container cache locations so bundle-id migrations do not force a new analysis
when the cache schema is still supported.

Host Analysis should read user-controlled `Sample Width` once when analysis starts. Long
clips should keep that requested sample size unless it exceeds the original source frame
width. In-progress analysis should stream frame-to-frame motion in memory and keep only the
previous luma buffer needed for the next Metal motion search; do not write per-frame `.luma`
scratch files or store analysis files inside a Final Cut Pro library/project bundle.
Persistent cache files should store prepared paths, frame timing, blur values, and
fingerprints instead of every frame's full luma sample.

Host Analysis playback must render from prepared motion paths shared across FxPlug
analyzer/render instances. Do not re-run full block matching across the analyzed frame set
on every render frame. Keep `Host Analysis Status` visible in the Inspector and update it to
`Ready (... frames)` after completed analysis. Render playback must tolerate trimmed clips
whose render time differs from Host Analysis frame time by matching the current render frame
fingerprint back to the analyzed frame set and applying that time offset before sampling the
prepared motion paths. Once an analysis is validated, render playback should keep using the
prepared motion path even when Final Cut Pro is playing proxy media; proxy media is rejected
only for Host Analysis input and for validating an unvalidated persisted cache. When the
effective overall transform strength is zero, rendering must
bypass prepared motion-path sampling and output an identity transform with no debug overlay.
When Host Analysis/cache state changes, update a hidden render-affecting revision parameter
so Final Cut Pro invalidates the preview/render cache and the viewer reflects the prepared
stabilization immediately.
Fine high-frequency shake should be handled by a render-time `Micro Jitter Window` path that
adds short-window correction on top of the long pan smoothing path without rerunning Host
Analysis. The effective micro window should include adjacent analyzed frames even when a
saved effect instance requests a sub-frame value such as `0.025s`, so the micro correction
does not collapse to zero on 29.97fps footage.
Large intentional pans should be controlled by the render-time `Panning X/Y Strength`
slider, where higher values apply stronger long-window X/Y translation correction. Panning
must not apply roll correction. The pan band should be measured after removing the short
Micro Jitter band, and the Y pan band should also remove the Y Axis Stabilization band so
vertical motion is not double-corrected.
Y-axis walking bob between micro jitter and panning should be handled by the render-time
`Y Axis Stabilization Window` and `Y Axis Stabilization Strength` path, which corrects the
Y-only band between the Micro Jitter smooth path and the Y stabilization smoothing window
without changing X or roll and without rerunning Host Analysis. Keep the strength range wide
enough for footstep bob that remains visible at `2.0`.
`Edge Display Mode` should control whether transformed source pixels outside the original
image stretch edge pixels or draw black. Do not tie black outside-source pixels to `Debug
Overlay`; debug overlay should only show diagnostics.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  docs/
  fxplug/
```

The Xcode project lives at
`fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj`. Keep FxPlug source under
`fxplug/StabilizerFxPlug/Plugin`, wrapper app source under
`fxplug/StabilizerFxPlug/WrapperApp`, installer scripts under
`fxplug/StabilizerFxPlug/scripts`, and Motion Template resources under
`fxplug/StabilizerFxPlug/MotionTemplates`.

## Test Project

Use this local Final Cut Pro library for manual end-to-end testing:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/test.fcpbundle
```

It is a shared workspace test fixture, outside this plugin repo. Use it when checking the
native effect against real timeline clips in Final Cut Pro.

## Version Visibility

Keep `stabilizerFxPlugVersion` in
`fxplug/StabilizerFxPlug/Plugin/StabilizerFxPlug.swift` aligned with
`CFBundleShortVersionString` in the wrapper app and plug-in plist files. User-visible
FxPlug behavior changes should bump the version value used by `Stabilizer Info`.

## Verification

After FxPlug edits, run:

```sh
xcodebuild -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj -scheme StabilizerFxPlug -configuration Debug -derivedDataPath /tmp/StabilizerFxPlugDerived build
pluginkit -m -A -p FxPlug -i com.justadev.StabilizerFxPlug.Plugin
codesign --verify --deep --strict /Applications/StabilizerFxPlug.app
git diff --check -- AGENTS.md README.md docs/usage.md fxplug/StabilizerFxPlug
```

The `StabilizerFxPlug` shared scheme has a post-build action that runs
`fxplug/StabilizerFxPlug/scripts/install_debug_app.sh`. A successful build should install
`/Applications/StabilizerFxPlug.app`, copy the Motion Template into the user's Movies
Motion Templates folder, and register its embedded pluginkit for Final Cut Pro.
