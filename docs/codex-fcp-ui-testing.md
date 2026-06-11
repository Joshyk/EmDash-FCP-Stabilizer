# Codex Final Cut Pro UI Testing

Use `scripts/fcp_ui_test.sh` before reaching for free-form pointer control. It
wraps the shared parent AppleScript helper at
`../scripts/fcp_stabilizer_shortcuts.applescript` and gives Codex stable,
terminal-first entry points for the repetitive Final Cut Pro UI actions.

## First Check

```sh
scripts/fcp_ui_test.sh env-check
```

This verifies the shared AppleScript path, the shared test library, the
feedback tool, and AppleScript compilation. It also reports whether Final Cut
Pro is currently running.

## Quick Selected-Clip Pass

1. Open the test library:

   ```sh
   scripts/fcp_ui_test.sh open-test-library
   scripts/fcp_ui_test.sh open-project "stab test - gh6"
   ```

2. Select the target timeline clip. If the playhead is over the target clip,
   keep this terminal-first:

   ```sh
   scripts/fcp_ui_test.sh select-playhead-clip
   ```

3. Apply the effect, enable `Debug Overlay`, and press `Start Host Analysis`:

   ```sh
   scripts/fcp_ui_test.sh apply-and-analyze-selected
   ```

Use `apply-and-analyze-selected` only for a fresh selected clip. If the clip
already has `Stabilizer Transform`, run:

```sh
scripts/fcp_ui_test.sh analyze-selected
```

## Diagnostics

When the UI labels have drifted or a command cannot find the expected control,
dump the accessible tree instead of trying random clicks:

```sh
scripts/fcp_ui_test.sh dump-front-window
```

After Host Analysis writes a cache in the shared test library, inspect readiness
and clip-relative review notes without reopening the UI:

```sh
scripts/fcp_ui_test.sh list-caches
scripts/fcp_ui_test.sh feedback-at 5.0 "notable unremoved shake"
```

These cache diagnostics read saved Host Analysis files only. They do not repair,
promote, delete, or generate cache data.
