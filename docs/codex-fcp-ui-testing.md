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
already has `Tokyo Walking Stabilizer`, run:

```sh
scripts/fcp_ui_test.sh analyze-selected
```

To force the selected clip's Host Analysis sample before starting:

```sh
scripts/fcp_ui_test.sh start-analysis-at-sample 50
```

## Batch Queueing

For compound-clip batches, select the target Event in Final Cut Pro's Browser,
make the first visible compound clip the selected Browser item, and keep the
Browser list scoped to the compounds you want to process. Then run:

```sh
scripts/fcp_ui_test.sh queue-current-event-compounds 50
```

The batch helper opens each visible Browser item, walks its open timeline from
the beginning, sets `Sample Size` to the requested value, and presses `Start
Host Analysis` for clips where the `Tokyo Walking Stabilizer` controls are
accessible. Clips without accessible Stabilizer controls are logged as skipped.
Pass explicit limits when the Browser status count is not the intended batch:

```sh
scripts/fcp_ui_test.sh queue-current-event-compounds 50 14 200
```

For only the currently open compound timeline:

```sh
scripts/fcp_ui_test.sh queue-open-timeline-clips 50
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
