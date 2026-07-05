# Tests

Run the standalone active-library resolver regression tests with:

```sh
scripts/run_active_library_resolver_tests.sh
```

These tests do not open Final Cut Pro, read the user's Final Cut Pro preferences, or touch
real `.fcpbundle` libraries. They create fake `.fcpbundle` directories, fake Event folders,
and `CurrentVersion.flexolibrary` SQLite fixtures under a new temporary directory on each
run. The fixture is intentionally left in place so the test does not delete anything from
the local machine.

Run the Final Cut Pro screen-capture E2E for the reported P1000307 turn with:

```sh
scripts/stabilizer_fcp_screen_capture_e2e.sh run \
  --case tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json
```

To normalize the Final Cut Pro UI without recording, run:

```sh
scripts/stabilizer_fcp_screen_capture_e2e.sh prepare \
  --case tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json
```

`prepare` opens the case library, opens the target project when the Browser exposes it,
selects the playhead clip, verifies the project metadata contains the Stabilizer effect and
Remove Black Edges parameter, seeks to the case start, and checks that the configured Viewer
ROI is recordable. Use `assert-prepared` to re-check the current FCP state, or
`--assume-prepared-fcp` when capturing from a state that was already prepared.

The case uses `/Users/justadev/Desktop/stabilizer_super_smoother.fcpbundle`,
`P1000307 Stabilized Review`, and the `P1000307.mov` `00:01:26` to `00:01:46`
turn section in proxy with Remove Black Edges / crop enabled. The script records the
Final Cut Pro Viewer, then `tests/stabilizer_video_quality.py` evaluates apparent zoom
pulse, black-edge breathing, and tracking confidence from the captured frames.

For far-field mountain ridge-line fine shake, use the P1000304 case around the reported
`00:04:28;32` section:

```sh
scripts/stabilizer_fcp_screen_capture_e2e.sh run \
  --case tests/stabilizer_e2e_cases/p1000304_ridge_4m23_4m43.json
```

This case adds a `ridgeRoi` band over the distant mountain area and fails on high-frequency
ridge motion after subtracting the local rolling pan baseline. It also records per-frame
ridge-line vertical residuals, ridge-line jerk, and lower-content reference deltas so a
ridge-only shimmer can be separated from whole-frame playback/cadence jumps.

The evaluator samples every captured frame when `sampleEveryCapturedFrame` is set. Do not
judge motion regressions from the compact contact sheet alone: each run writes full-frame
CSV diagnostics, a per-frame `diagnostic_overlay.mp4`, and separate contact sheets for
scale, jump, cadence/hold, pulse, edge, and ridge spikes. The contact sheets are visual
indexes into the failure regions; the overlay video is the primary visual artifact for
checking continuous pulsing or ridge-line shake.

Frame translation jump is evaluated separately from Final Cut Pro playback cadence. When
ffprobe PTS intervals show a dropped/held capture frame and the case enables
`excludePtsIrregularFromFrameJump`, that frame pair is excluded from the jump maximum but
the PTS irregular ratio remains its own operation-quality gate in `metrics.json` and the
per-frame CSV/overlay diagnostics. `excludePtsIrregularFromScalePulse` applies the same
separation to zoom-pulse windows by breaking the pulse path around PTS-cadence affected
frames instead of letting capture drops inflate the Stabilizer pulse metric.
`excludePtsIrregularFromRidgeMotion` keeps ridge max/p95 focused on real far-field wobble
instead of the single-frame ridge spikes caused by playback cadence drops.
Near-identical consecutive frames with tiny mean/p95 pixel difference and near-zero
estimated displacement are also classified as cadence holds before frame-jump scoring. Those
holds remain visible as cadence/duplicate operation failures; they are not counted as
Stabilizer transform jumps.

To evaluate an existing recording without driving Final Cut Pro:

```sh
scripts/stabilizer_fcp_screen_capture_e2e.sh evaluate \
  --case tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json \
  --video /tmp/stabilizer_screen_capture/p1000307_turn_129_v1021_proxy_crop_on_fcp.mov
```

If the FCP window layout changes, pass `--viewer-roi x,y,w,h` for the absolute Viewer
rectangle in the screen recording.
