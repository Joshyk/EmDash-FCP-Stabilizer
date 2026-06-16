# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

## Project

This directory contains the local Event FCPXMLD analyzer for Tokyo Walking
Stabilizer. It is a support tool inside the Stabilizer repository, separate from
the FxPlug bundle/runtime path. It may contain the local Web UI, FCPXMLD
parsing/import builders, and native analysis helpers that prepare Event-scoped
persisted Stabilizer caches.

Do not move these support-tool files into the FxPlug bundle, Motion Template, or
`fxplug/TokyoWalkingStabilizer/Plugin/` runtime path.

Do not write analysis output to a shared fallback directory. Cache output must be
explicitly directed to an Event `Analysis Files/TokyoWalkingStabilizerHostAnalysis`
root or a user-selected staging directory.

## Verification

Use the narrowest practical checks:

- `node --test node_web/test/*.test.js`
- `python3 scripts/list_event_assets.py --fcpxml <package-or-info>`
- `swift build --package-path native_analyzer`
- `node node_web/server.js`
