# Final Cut Pro E2E Control Patterns

This note is the quick command index for Tokyo Walking Stabilizer FCP Preview
screen-capture verification. It intentionally points at the existing
terminal-first scripts instead of adding a second UI automation path.

## Current Control Surface

- `scripts/fcp_e2e_control.sh` is the stable wrapper for main-agent use.
- `scripts/stabilizer_fcp_screen_capture_e2e.sh` is the lower-level harness for
  FCP UI prepare, Proxy Only setup, Viewer ROI recording, evidence checks, and
  video evaluation.
- The fixed cases are:
  - `p1000307`: `tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json`
  - `p1000304`: `tests/stabilizer_e2e_cases/p1000304_ridge_4m23_4m43.json`
- Both cases target `/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/stabilizer_super_smoother.fcpbundle`
  and require `playbackMode: "Proxy Only"` plus `removeBlackEdges: true`.

## Fixed Regression Patterns

Print the repo-local command set:

```sh
scripts/fcp_e2e_control.sh patterns
```

P1000307 turn window:

```sh
scripts/fcp_e2e_control.sh recover-case --case p1000307
scripts/fcp_e2e_control.sh warmup-proxy --case p1000307 --assume-current-fcp-state
STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS=3600 \
STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS=3600 \
scripts/fcp_e2e_control.sh run --case p1000307 \
  --capture-backend avfoundation-roi \
  --visual-review not-reviewed \
  --assume-current-fcp-state
```

P1000304 ridge window:

```sh
scripts/fcp_e2e_control.sh recover-case --case p1000304
scripts/fcp_e2e_control.sh warmup-proxy --case p1000304 --assume-current-fcp-state
STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS=3600 \
STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS=3600 \
scripts/fcp_e2e_control.sh run --case p1000304 \
  --capture-backend avfoundation-roi \
  --visual-review not-reviewed \
  --assume-current-fcp-state
```

Strict ROI replay, useful after layout drift is ruled out:

```sh
STABILIZER_E2E_DYNAMIC_VIEWER_ROI=0 \
STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS=3600 \
STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS=3600 \
scripts/fcp_e2e_control.sh run --case p1000307 \
  --capture-backend avfoundation-roi \
  --viewer-roi 1458,506,1120,600 \
  --visual-review not-reviewed \
  --assume-current-fcp-state
```

## Recovery And Warmup

Recover the case library without deleting analysis or transcoded media:

```sh
scripts/fcp_e2e_control.sh recover-case --case p1000307
```

Recover after moving only generated Event Render Files out of the library. FCP
must be quit for this operation; the script refuses to move while FCP is running.

```sh
scripts/fcp_e2e_control.sh recover-case --case p1000307 --clear-render-files
```

Warm a black or uninitialized Proxy Only Viewer by reasserting the prepared case
state. The lower-level harness may temporarily switch to Optimized/Original only
as warmup, then restore Proxy Only before recordability is accepted.

```sh
scripts/fcp_e2e_control.sh warmup-proxy --case p1000307 --assume-current-fcp-state
```

## Proxy Only Evidence

There is no standalone post-hoc Proxy Only command in the wrapper. `capture` and
`run` enforce Proxy Only evidence after recording by checking FxPlug logs for the
target clip. Use a stable output directory when another agent needs to inspect the
evidence files:

```sh
out=/tmp/stabilizer_e2e/p1000307_latest
video="$out/p1000307.mov"
scripts/fcp_e2e_control.sh run --case p1000307 \
  --video "$video" \
  --output-dir "$out" \
  --capture-backend avfoundation-roi \
  --visual-review not-reviewed \
  --assume-current-fcp-state
rg "proxy yes|proxy no|prepared yes|Proxy Only" "$out/proxy_render_evidence.log"
rg "Playback fallback evidence verified|fallback|not ready" "$out/playback_fallback_evidence.log"
```

The capture is not valid evidence for a Proxy Only case unless the log check
matches the target clip and reports proxy rendering with the prepared path active.

## Existing Gaps

- Viewer media playback selection still depends on FCP UI geometry for the Viewer
  Options popover. If Apple changes the layout, use the helper dump flow and
  update the coordinate calculation rather than switching to Computer Use first.
- `warmup-proxy` is a wrapper around `assert-prepared`; the actual warmup toggle
  happens only when the lower-level harness detects a black or uninitialized
  Proxy Only Viewer.
- Smoothness acceptance is still video-first. `--visual-review not-reviewed`
  should remain a failure for final acceptance until someone watches the recorded
  FCP Preview and reruns/evaluates with `--visual-review passed` or `failed`.
