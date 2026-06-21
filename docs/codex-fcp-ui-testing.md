# Codex Final Cut Pro UI Testing

Use `scripts/fcp_ui_test.sh` before reaching for free-form pointer control. It
wraps the shared parent AppleScript helper and gives Codex stable,
terminal-first entry points for repetitive Final Cut Pro UI actions.

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

3. Apply the effect and enable `Debug Overlay`:

   ```sh
   scripts/fcp_ui_test.sh apply-selected
   scripts/fcp_ui_test.sh enable-debug
   ```

New effect instances are cache consumers. They do not expose `Sample Size`,
`Start Host Analysis`, `Clear Host Analysis Cache`, or `Queue`, and preview
callbacks must not auto-start analysis. Generate or refresh analysis with the
local Stabilizer Event Analyzer, import its generated FCPXMLD, then check that
`Host Analysis Status` reports `Persisted Analysis Loaded` or `Ready (... frames)`.

If an older saved timeline instance still exposes `Start Host Analysis`, pressing
it is a legacy compatibility check that only reloads a compatible Event Analyzer
cache. It must not be used as the primary way to generate analysis.

## Legacy Host Analysis UI

The following script commands exist only for older timeline instances that still
show hidden Host Analysis controls:

```sh
scripts/fcp_ui_test.sh analyze-selected
scripts/fcp_ui_test.sh start-analysis-at-sample 50
scripts/fcp_ui_test.sh queue-open-timeline-clips 50
scripts/fcp_ui_test.sh queue-current-event-compounds 50
```

Do not use those commands for the current Event Analyzer workflow. If they fail
because the controls are not present, that is expected for new effect instances.

## Diagnostics

When the UI labels have drifted or a command cannot find the expected control,
dump the accessible tree instead of trying random clicks:

```sh
scripts/fcp_ui_test.sh dump-front-window
```

After the local Event Analyzer writes a cache in the shared test library, inspect
readiness and clip-relative review notes without reopening the UI:

```sh
scripts/fcp_ui_test.sh list-caches
scripts/fcp_ui_test.sh feedback-at 5.0 "notable unremoved shake"
```

These cache diagnostics read saved analysis files only. They do not repair,
promote, delete, or generate cache data.
