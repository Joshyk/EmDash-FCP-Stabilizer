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

The case uses `/Users/justadev/Desktop/stabilizer_super_smoother.fcpbundle`,
`P1000307 Stabilized Review`, and the `P1000307.mov` `00:01:26` to `00:01:46`
turn section in proxy with Remove Black Edges / crop enabled. The script records the
Final Cut Pro Viewer, then `tests/stabilizer_video_quality.py` evaluates apparent zoom
pulse, black-edge breathing, and tracking confidence from the captured frames.

To evaluate an existing recording without driving Final Cut Pro:

```sh
scripts/stabilizer_fcp_screen_capture_e2e.sh evaluate \
  --case tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json \
  --video /tmp/stabilizer_screen_capture/p1000307_turn_129_v1021_proxy_crop_on_fcp.mov
```

If the FCP window layout changes, pass `--viewer-roi x,y,w,h` for the absolute Viewer
rectangle in the screen recording.
