#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_micro_macro_1m44_1m56.json"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"
FCP_HELPER="${FCP_HELPER:-/Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript}"

usage() {
	cat <<'USAGE'
Usage: scripts/stabilizer_fcp_screen_capture_e2e.sh COMMAND [OPTIONS]

Commands:
  set-proxy-only
             Set the current FCP Viewer media playback to Proxy Only.
  set-optimized-original
             Set the current FCP Viewer media playback to Optimized/Original.
  set-green-channel
             Set the current FCP Viewer channel display to Green.
  prepare    Open and normalize FCP UI state for the configured E2E case.
  assert-prepared
             Verify the current FCP UI state is recordable for the case.
  capture    Record the current FCP Viewer playback for the configured E2E case.
  evaluate   Evaluate an existing screen recording.
  assert-recording-progress
             Verify an existing recording keeps advancing through the case window.
  run        Capture, then evaluate.

Options:
  --case PATH                  Case JSON. Defaults to P1000307 00:01:49 micro/macro E2E.
  --video PATH                 Capture output or existing recording to evaluate.
  --viewer-roi x,y,w,h         Override absolute FCP Viewer ROI in capture pixels.
  --output-dir PATH            Directory for evaluator diagnostics.
  --capture-backend NAME       screencapture, avfoundation-roi, or screencapturekit-roi. Default: screencapture.
  --visual-review STATE        passed, failed, or not-reviewed. Default: not-reviewed.
  --assume-current-fcp-state   Do not open the project by UI helper; use current FCP state.
  --assume-prepared-fcp        Skip prepare and only verify/capture current FCP state.

Capture prerequisites:
  - FCP has Screen Recording and Accessibility permission for the invoking terminal.
  - The case library can be opened from disk.
  - The target project/clip has Tokyo Walking Stabilizer enabled.
  - FCP Viewer media playback is Proxy Only, Viewer Channel is Green, Debug Overlay is visible,
    and Remove Black Edges / crop are enabled for the reported scenario.
USAGE
}

fail() {
	printf 'stabilizer_fcp_screen_capture_e2e.sh: %s\n' "$*" >&2
	exit 2
}

wait_for_ui_osascript() {
	local pid="$1"
	local label="$2"
	local max_ticks="$3"
	local allow_timeout="$4"
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if (( waited >= max_ticks )); then
			printf 'Final Cut Pro UI AppleScript timed out during %s after %.1fs; terminating it.\n' "$label" "$(python3 - "$max_ticks" <<'PY'
import sys
print(float(sys.argv[1]) / 10.0)
PY
)" >&2
			kill -TERM "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			if [[ "$allow_timeout" == "1" ]]; then
				return 0
			fi
			return 1
		fi
		sleep 0.1
		waited=$((waited + 1))
	done
	wait "$pid"
}

wait_for_fcp_standard_window() {
	local max_ticks="${1:-300}"
	local waited=0
	while (( waited < max_ticks )); do
		if timeout 2 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1
tell application "System Events"
	if not (exists process "Final Cut Pro") then error "Final Cut Pro process not found"
	tell process "Final Cut Pro"
		repeat with candidateWindow in windows
			try
				if subrole of candidateWindow is "AXStandardWindow" then return "ready"
			end try
		end repeat
	end tell
end tell
error "Final Cut Pro standard window not ready"
APPLESCRIPT
		then
			return 0
		fi
		sleep 0.1
		waited=$((waited + 1))
	done
	return 1
}

fcp_ax_window_summary() {
	timeout 5 /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
	if not (exists process "Final Cut Pro") then return "process=missing"
	tell process "Final Cut Pro"
		return "frontmost=" & (frontmost as text) & ", visible=" & (visible as text) & ", windows=" & ((count of windows) as text)
	end tell
end tell
APPLESCRIPT
}

fail_if_fcp_windowless() {
	local label="$1"
	local summary
	summary="$(fcp_ax_window_summary)"
	if [[ "$summary" == *"windows=0"* || "$summary" == "process=missing" || -z "$summary" ]]; then
		fail "Final Cut Pro is not in a usable window state during ${label}; AX state: ${summary:-unavailable}. Open FCP visibly, open the target project, then retry with --assume-current-fcp-state."
	fi
}

recover_fcp_standard_window_via_ax() {
	local label="$1"
	printf 'Final Cut Pro AX window recovery: activate/reopen/frontmost during %s.\n' "$label" >&2
	timeout 8 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Final Cut Pro"
	activate
	reopen
end tell
delay 0.5
tell application "System Events"
	if not (exists process "Final Cut Pro") then error "Final Cut Pro process not found"
	tell process "Final Cut Pro"
		set frontmost to true
	end tell
end tell
APPLESCRIPT
}

ensure_fcp_standard_window_after_open() {
	local library="$1"
	local label="$2"
	if wait_for_fcp_standard_window 180; then
		return 0
	fi
	local summary
	summary="$(fcp_ax_window_summary)"
	printf 'Final Cut Pro standard window not readable during %s; AX state: %s\n' "$label" "${summary:-unavailable}" >&2
	if [[ "$summary" == *"windows=0"* || "$summary" == "process=missing" || -z "$summary" ]]; then
		recover_fcp_standard_window_via_ax "$label"
		if wait_for_fcp_standard_window 180; then
			return 0
		fi
		summary="$(fcp_ax_window_summary)"
		printf 'Final Cut Pro standard window still not readable after AX activate/reopen recovery; AX state: %s\n' "${summary:-unavailable}" >&2
		printf 'Final Cut Pro remains windowless after opening %s; refusing same-path LaunchServices reopen. Open FCP visibly or use --assume-current-fcp-state after manual recovery.\n' "$library" >&2
		return 1
	fi
	wait_for_fcp_standard_window 320
}

ensure_current_fcp_standard_window() {
	local label="$1"
	if ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		printf 'Final Cut Pro is not running for assume-current FCP state.\n' >&2
		return 1
	fi
	recover_fcp_standard_window_via_ax "$label"
	if wait_for_fcp_standard_window 180; then
		return 0
	fi
	local summary
	summary="$(fcp_ax_window_summary)"
	printf 'Final Cut Pro standard window not readable for current-state run; AX state: %s\n' "${summary:-unavailable}" >&2
	return 1
}

json_value() {
	local file="$1"
	local key="$2"
	python3 - "$file" "$key" <<'PY'
import json
import sys

path, dotted = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    value = json.load(handle)
for part in dotted.split("."):
    value = value[part]
print(value)
PY
}

case_viewer_roi() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    case = json.load(handle)
roi = case.get("viewerRoi") or {}
try:
    x = int(roi["x"])
    y = int(roi["y"])
    w = int(roi["w"])
    h = int(roi["h"])
except (KeyError, TypeError, ValueError):
    raise SystemExit("case viewerRoi must contain integer x/y/w/h")
if w <= 0 or h <= 0:
    raise SystemExit("case viewerRoi width/height must be positive")
print(f"{x},{y},{w},{h}")
PY
}

current_fcp_viewer_roi() {
	[[ -f "$FCP_HELPER" ]] || fail "missing FCP helper: ${FCP_HELPER}"
	local bounds_json
	bounds_json="$(/usr/bin/osascript "$FCP_HELPER" viewer-bounds-json)"
	viewer_bounds_points_to_pixel_roi "$bounds_json"
}

clamp_viewer_roi_to_screenshot_bounds() {
	local viewer_roi="$1"
	local screenshot_path="$2"
	python3 - "$viewer_roi" "$screenshot_path" <<'PY'
from pathlib import Path
import sys

import cv2

roi_parts = [int(part) for part in sys.argv[1].split(",")]
if len(roi_parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
x, y, w, h = roi_parts
image = cv2.imread(str(Path(sys.argv[2])), cv2.IMREAD_COLOR)
if image is None:
    raise SystemExit(f"could not read screenshot for ROI bounds: {sys.argv[2]}")
height, width = image.shape[:2]
clamped_x = max(0, min(x, width - 1))
clamped_y = max(0, min(y, height - 1))
clamped_w = min(w, width - clamped_x)
clamped_h = min(h, height - clamped_y)
if clamped_w <= 0 or clamped_h <= 0:
    raise SystemExit(
        f"dynamic viewer ROI {x},{y},{w},{h} does not overlap screenshot bounds {width}x{height}"
    )
gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
run_candidates = []
row_start = clamped_y + max(8, min(24, clamped_h // 12))
row_end = clamped_y + max(24, min(clamped_h // 5, 180))
for row_y in range(row_start, min(height, row_end), max(4, clamped_h // 80)):
    row = gray[row_y, clamped_x:clamped_x + clamped_w]
    mask = row > 35
    run_start = None
    for index, active in enumerate(mask):
        at_end = index == len(mask) - 1
        if active and run_start is None:
            run_start = index
        if (not active or at_end) and run_start is not None:
            run_end = index if not active else index + 1
            if run_end - run_start >= max(120, int(clamped_w * 0.35)):
                run_candidates.append((clamped_x + run_start, clamped_x + run_end))
            run_start = None
if run_candidates:
    starts = sorted(start for start, _ in run_candidates)
    ends = sorted(end for _, end in run_candidates)
    refined_x = starts[0]
    refined_end = ends[-1]
    if refined_end - refined_x >= max(120, int(clamped_w * 0.35)):
        clamped_x = refined_x
        clamped_w = refined_end - refined_x
print(f"{clamped_x},{clamped_y},{clamped_w},{clamped_h}")
PY
}

clamp_viewer_roi_to_current_screenshot_bounds() {
	local viewer_roi="$1"
	local screenshot_path
	screenshot_path="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-roi-bounds.XXXXXX.png")"
	/usr/sbin/screencapture -x "$screenshot_path"
	clamp_viewer_roi_to_screenshot_bounds "$viewer_roi" "$screenshot_path"
	local status=$?
	rm -f "$screenshot_path"
	return "$status"
}

viewer_bounds_points_to_pixel_roi() {
	local bounds_json="$1"
	BOUNDS_JSON="$bounds_json" /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import('AppKit')
ObjC.import('Foundation')

const boundsText = $.NSProcessInfo.processInfo.environment.objectForKey('BOUNDS_JSON').js
const bounds = JSON.parse(boundsText)
const x = Number(bounds.x)
const y = Number(bounds.y)
const width = Number(bounds.width)
const height = Number(bounds.height)

if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
  throw new Error(`invalid FCP Viewer bounds: ${boundsText}`)
}

const centerX = x + width / 2.0
const centerY = y + height / 2.0
const screens = $.NSScreen.screens
let screen = $.NSScreen.mainScreen
for (let index = 0; index < screens.count; index++) {
  const candidate = screens.objectAtIndex(index)
  const frame = candidate.frame
  if (
    centerX >= frame.origin.x &&
    centerX <= frame.origin.x + frame.size.width &&
    centerY >= frame.origin.y &&
    centerY <= frame.origin.y + frame.size.height
  ) {
    screen = candidate
    break
  }
}

const frame = screen.frame
const scale = Number(screen.backingScaleFactor)
if (!Number.isFinite(scale) || scale <= 0) {
  throw new Error('could not determine backing scale factor for FCP Viewer screen')
}

const pixelX = Math.round((x - frame.origin.x) * scale)
const pixelY = Math.round((y - frame.origin.y) * scale)
const pixelWidth = Math.round(width * scale)
const pixelHeight = Math.round(height * scale)
if (pixelWidth <= 0 || pixelHeight <= 0) {
  throw new Error(`invalid pixel FCP Viewer ROI: ${pixelX},${pixelY},${pixelWidth},${pixelHeight}`)
}

`${pixelX},${pixelY},${pixelWidth},${pixelHeight}`
JXA
}

viewer_roi_for_current_fcp() {
	local fallback_roi="$1"
	if [[ "${viewer_roi_explicit:-0}" == "1" ]]; then
		printf '%s\n' "$fallback_roi"
		return 0
	fi
	if [[ "${STABILIZER_E2E_DYNAMIC_VIEWER_ROI:-1}" == "0" ]]; then
		printf '%s\n' "$fallback_roi"
		return 0
	fi
	local dynamic_roi
	if ! dynamic_roi="$(current_fcp_viewer_roi)"; then
		fail "could not resolve current FCP Viewer ROI; pass --viewer-roi explicitly to override"
	fi
	local bounded_roi
	if ! bounded_roi="$(clamp_viewer_roi_to_current_screenshot_bounds "$dynamic_roi")"; then
		fail "could not clamp current FCP Viewer ROI to screenshot bounds: ${dynamic_roi}"
	fi
	if [[ "$bounded_roi" != "$dynamic_roi" ]]; then
		printf 'Clamped dynamic FCP Viewer ROI to screenshot bounds: %s -> %s\n' "$dynamic_roi" "$bounded_roi" >&2
	fi
	dynamic_roi="$bounded_roi"
	printf 'Using dynamic FCP Viewer ROI in capture pixels: %s\n' "$dynamic_roi" >&2
	printf '%s\n' "$dynamic_roi"
}

json_bool_value() {
	local file="$1"
	local key="$2"
	python3 - "$file" "$key" <<'PY'
import json
import sys

path, dotted = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    value = json.load(handle)
for part in dotted.split("."):
    value = value[part]
print("true" if bool(value) else "false")
PY
}

case_record_seconds() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import math
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
duration = float(case.get("durationSeconds", 0.0) or 0.0)
recording = case.get("recording") or {}
explicit = recording.get("recordSeconds", case.get("recordSeconds"))
if explicit is None:
    pad = float(recording.get("recordPadSeconds", 2.0))
    value = math.ceil(duration + pad)
else:
    value = float(explicit)
if value <= 0.0:
    raise SystemExit("recordSeconds must be positive")
if duration > 0.0 and value + 1e-9 < duration:
    raise SystemExit(
        f"recordSeconds {value:.3f} must be >= durationSeconds {duration:.3f}"
    )
if abs(value - round(value)) < 1e-9:
    print(str(int(round(value))))
else:
    print(f"{value:.3f}".rstrip("0").rstrip("."))
PY
}

now_epoch_seconds() {
	python3 - <<'PY'
import time
print(f"{time.time():.6f}")
PY
}

log_timestamp_from_epoch() {
	local epoch_seconds="$1"
	local offset_seconds="${2:-0}"
	python3 - "$epoch_seconds" "$offset_seconds" <<'PY'
from datetime import datetime
import sys

epoch = float(sys.argv[1]) + float(sys.argv[2])
print(datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M:%S"))
PY
}

write_e2e_benchmark() {
	local output_dir="$1"
	local case_file="$2"
	local video_path="$3"
	local command_name="$4"
	local capture_backend="$5"
	local total_start="$6"
	local capture_start="${7:-}"
	local capture_end="${8:-}"
	local evaluate_start="${9:-}"
	local evaluate_end="${10:-}"
	local exit_code="${11:-0}"
	[[ -n "$output_dir" ]] || return 0
	mkdir -p "$output_dir"
	python3 - "$output_dir/e2e_benchmark.json" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "$evaluate_start" "$evaluate_end" "$exit_code" <<'PY'
import json
import math
from pathlib import Path
import sys
import time

(
    output_path,
    case_path,
    video_path,
    command_name,
    capture_backend,
    total_start,
    capture_start,
    capture_end,
    evaluate_start,
    evaluate_end,
    exit_code,
) = sys.argv[1:]

def finite_float(raw: str) -> float | None:
    if not raw:
        return None
    try:
        value = float(raw)
    except ValueError:
        return None
    return value if math.isfinite(value) else None

def duration(start: str, end: str) -> float | None:
    start_value = finite_float(start)
    end_value = finite_float(end)
    if start_value is None or end_value is None:
        return None
    return max(0.0, end_value - start_value)

case = json.loads(Path(case_path).read_text(encoding="utf-8"))
metrics_path = Path(output_path).with_name("metrics.json")
metrics = None
if metrics_path.exists():
    try:
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        metrics = None

now = time.time()
payload = {
    "schemaVersion": 1,
    "caseId": case.get("caseId"),
    "project": case.get("project"),
    "command": command_name,
    "captureBackend": capture_backend,
    "videoPath": video_path,
    "metricsPath": str(metrics_path) if metrics_path.exists() else None,
    "exitCode": int(exit_code),
    "finishedAtEpochSeconds": now,
    "totalWallSeconds": duration(total_start, f"{now:.6f}"),
    "captureWallSeconds": duration(capture_start, capture_end),
    "evaluateWallSeconds": duration(evaluate_start, evaluate_end),
    "quality": {
        key: metrics.get(key)
        for key in [
            "passed",
            "operationFailure",
            "fps",
            "capturedFpsRatio",
            "maxAbsScaleResidualPercent",
            "maxFrameTranslationJumpPixels",
            "maxScalePulsePeakToPeakPercent",
            "maxScalePulseDerivativeP95PercentPerFrame",
            "nearDuplicateFrameRatio",
            "cadenceHoldFrameRatio",
        ]
        if isinstance(metrics, dict) and key in metrics
    } if isinstance(metrics, dict) else None,
    "ridge": metrics.get("ridge") if isinstance(metrics, dict) else None,
}
Path(output_path).write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"E2E benchmark: {output_path}")
PY
}

assert_proxy_render_evidence() {
	local case_file="$1"
	local start_epoch="$2"
	local end_epoch="$3"
	local output_dir="$4"
	local playback_mode
	playback_mode="$(json_value "$case_file" playbackMode)"
	if [[ "$playback_mode" != "Proxy Only" ]]; then
		return 0
	fi

	local start_date
	local end_date
	local lookback_seconds="${STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS:-600}"
	start_date="$(log_timestamp_from_epoch "$start_epoch" "$((-lookback_seconds))")"
	end_date="$(log_timestamp_from_epoch "$end_epoch" 3)"
	local evidence_dir
	if [[ -n "$output_dir" ]]; then
		evidence_dir="$output_dir"
	else
		evidence_dir="${ARTIFACT_ROOT}"
	fi
	mkdir -p "$evidence_dir"
	local evidence_path="${evidence_dir}/proxy_render_evidence.log"
	local predicate='(subsystem == "com.justadev.TokyoWalkingStabilizer" OR process == "TokyoWalkingStabilizer XPC Service") AND eventMessage CONTAINS "Render Host Analysis decision"'
	if ! log show --style compact --start "$start_date" --end "$end_date" --predicate "$predicate" >"$evidence_path" 2>&1; then
		fail "could not read FxPlug render-source logs for Proxy Only evidence: $evidence_path"
	fi

	python3 - "$case_file" "$evidence_path" <<'PY'
import json
import re
import sys
from pathlib import Path

case_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])
case = json.loads(case_path.read_text(encoding="utf-8"))
source_clip = Path(case.get("sourceClip", "")).stem
digits = "".join(re.findall(r"\d+", source_clip))
clip_token = digits[-6:] if len(digits) >= 6 else source_clip
frame_count = str(case.get("source", {}).get("frameCount", ""))
frame_token = f"frames {frame_count}" if frame_count else ""

lines = [
    line.rstrip("\n")
    for line in evidence_path.read_text(encoding="utf-8", errors="replace").splitlines()
    if "Render Host Analysis decision" in line
]
relevant = []
if frame_token:
    relevant.extend(line for line in lines if frame_token in line)
else:
    if clip_token:
        relevant.extend(line for line in lines if clip_token in line or source_clip in line)
relevant = list(dict.fromkeys(relevant))

if not relevant:
    raise SystemExit(
        "Proxy Only evidence missing: no FxPlug render decision matched "
        f"clip={source_clip!r} token={clip_token!r} frames={frame_count!r}; log={evidence_path}"
    )

usable_proxy = [
    line
    for line in relevant
    if "proxy yes" in line and "prepared yes" in line and "stabilization active" in line
]
proxy_yes = [line for line in relevant if "proxy yes" in line]
proxy_no = [line for line in relevant if "proxy no" in line]
prepared_no = [line for line in relevant if "prepared no" in line or "stabilization inactive" in line]
if usable_proxy:
    print(
        "Proxy Only render evidence verified: "
        f"{len(usable_proxy)} matching proxy yes + prepared yes + stabilization active log(s)."
    )
    raise SystemExit(0)
if proxy_yes and prepared_no:
    raise SystemExit(
        "Proxy Only evidence failed: FxPlug rendered proxy media for the target clip, "
        "but the Stabilizer prepared path was not active; "
        f"log={evidence_path}"
    )
if proxy_no:
    raise SystemExit(
        "Proxy Only evidence failed: FxPlug rendered the target clip as proxy no; "
        f"log={evidence_path}"
    )
raise SystemExit(
    "Proxy Only evidence failed: matching FxPlug render decision did not report proxy yes; "
    f"log={evidence_path}"
)
PY
}

assert_no_playback_fallbacks() {
	local case_file="$1"
	local start_epoch="$2"
	local end_epoch="$3"
	local output_dir="$4"
	local playback_mode
	playback_mode="$(json_value "$case_file" playbackMode)"
	if [[ "$playback_mode" != "Proxy Only" ]]; then
		return 0
	fi

	local start_date
	local end_date
	start_date="$(log_timestamp_from_epoch "$start_epoch" -3)"
	end_date="$(log_timestamp_from_epoch "$end_epoch" 3)"
	local evidence_dir
	if [[ -n "$output_dir" ]]; then
		evidence_dir="$output_dir"
	else
		evidence_dir="${ARTIFACT_ROOT}"
	fi
	mkdir -p "$evidence_dir"
	local fallback_path="${evidence_dir}/playback_fallback_evidence.log"
	local predicate='(subsystem == "com.justadev.TokyoWalkingStabilizer" OR process == "TokyoWalkingStabilizer XPC Service") AND (eventMessage CONTAINS "Auto Crop playback fallback" OR eventMessage CONTAINS "Auto Crop playback unavailable" OR eventMessage CONTAINS "Auto Crop playback plan deferred" OR eventMessage CONTAINS "Auto Crop playback final framing repair" OR eventMessage CONTAINS "Playback trajectory fallback" OR eventMessage CONTAINS "Playback trajectory not ready")'
	if ! log show --style compact --start "$start_date" --end "$end_date" --predicate "$predicate" >"$fallback_path" 2>&1; then
		fail "could not read FxPlug playback fallback logs: $fallback_path"
	fi
	python3 - "$case_file" "$fallback_path" <<'PY'
import json
import re
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
fallback_path = Path(sys.argv[2])
source_clip = Path(case.get("sourceClip", "")).stem
digits = "".join(re.findall(r"\d+", source_clip))
frame_count = str(case.get("source", {}).get("frameCount", ""))
frame_token = f"frames {frame_count}" if frame_count else ""
tokens = [source_clip]
if digits:
    tokens.append(digits)
    if len(digits) >= 6:
        tokens.append(digits[-6:])
tokens = [token for token in dict.fromkeys(tokens) if token]
fallback_pattern = re.compile(
    r"Auto Crop playback fallback|Auto Crop playback unavailable|"
    r"Auto Crop playback plan deferred|Auto Crop playback final framing repair|"
    r"Playback trajectory fallback|Playback trajectory not ready"
)

def matches_target(line: str) -> bool:
    if "Render Host Analysis decision" in line and frame_token:
        return frame_token in line
    if frame_token and frame_token in line:
        return True
    return any(token in line for token in tokens)

lines = [
    line.rstrip("\n")
    for line in fallback_path.read_text(encoding="utf-8", errors="replace").splitlines()
    if fallback_pattern.search(line)
]
target_lines = [line for line in lines if matches_target(line)]
if target_lines:
    preview = "\n".join(target_lines[-8:])
    raise SystemExit(
        "Playback fallback/unprepared playback plan occurred during Proxy Only capture "
        f"for clip={source_clip!r}; log={fallback_path}\n{preview}"
    )
ignored = len(lines) - len(target_lines)
ambiguous = sum(1 for line in lines if not matches_target(line))
suffix = f"; ignored {ignored} non-target/ambiguous fallback log(s)" if ignored else ""
print(
    "Playback fallback evidence verified: no target Auto Crop or trajectory "
    f"playback fallback/unprepared log(s){suffix}; ambiguousWithoutClip={ambiguous}."
)
PY
}

collect_render_component_diagnostics() {
	local case_file="$1"
	local start_epoch="$2"
	local end_epoch="$3"
	local output_dir="$4"
	local evidence_dir
	if [[ -n "$output_dir" ]]; then
		evidence_dir="$output_dir"
	else
		evidence_dir="${ARTIFACT_ROOT}"
	fi
	mkdir -p "$evidence_dir"

	local start_date
	local end_date
	start_date="$(log_timestamp_from_epoch "$start_epoch" -3)"
	end_date="$(log_timestamp_from_epoch "$end_epoch" 3)"
	local component_log_path="${evidence_dir}/render_components.log"
	local component_csv_path="${evidence_dir}/render_components.csv"
	local component_focus_path="${evidence_dir}/render_components_focus.csv"
	local component_points_path="${evidence_dir}/render_components_focus_points.csv"
	local predicate='(subsystem == "com.justadev.TokyoWalkingStabilizer" OR process == "TokyoWalkingStabilizer XPC Service") AND (eventMessage CONTAINS "Render frame components csv v2" OR eventMessage CONTAINS "Render lens band csv v1" OR eventMessage CONTAINS "Render lens rigid csv v1" OR eventMessage CONTAINS "Render lens local csv v1" OR eventMessage CONTAINS "Render lens ridge line csv v1")'
	local log_attempt
	for log_attempt in 1 2 3; do
		if ! log show --style compact --start "$start_date" --end "$end_date" --predicate "$predicate" >"$component_log_path" 2>&1; then
			fail "could not read FxPlug render component diagnostics: $component_log_path"
		fi
		if grep -q "Render frame components csv v2 |" "$component_log_path"; then
			break
		fi
		if [[ "$log_attempt" != "3" ]]; then
			echo "Render component diagnostics not visible in unified log yet; retrying log show ($log_attempt/3)..." >&2
			sleep 2
		fi
	done

	python3 - "$case_file" "$component_log_path" "$component_csv_path" "$component_focus_path" "$component_points_path" <<'PY'
import csv
import json
import math
import re
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
log_path = Path(sys.argv[2])
csv_path = Path(sys.argv[3])
focus_path = Path(sys.argv[4])
points_path = Path(sys.argv[5])

prefix = "Render frame components csv v2 |"
lens_prefix = "Render lens band csv v1 |"
rigid_prefix = "Render lens rigid csv v1 |"
local_prefix = "Render lens local csv v1 |"
ridge_line_prefix = "Render lens ridge line csv v1 |"
pair_pattern = re.compile(r"([A-Za-z][A-Za-z0-9]*)=([^ |]+)")
idx_pattern = re.compile(r"idx=(\d+)-(\d+)")

def source_frame_rate() -> float:
    raw = str((case.get("source") or {}).get("frameRate", ""))
    if "/" in raw:
        numerator, denominator = raw.split("/", 1)
        try:
            frame_rate = float(numerator) / float(denominator)
        except ValueError:
            raise SystemExit(f"Render component diagnostics cannot parse source frameRate: {raw!r}")
        if frame_rate <= 0.0 or not math.isfinite(frame_rate):
            raise SystemExit(f"Render component diagnostics has invalid source frameRate: {raw!r}")
        return frame_rate
    try:
        frame_rate = float(raw)
    except ValueError:
        raise SystemExit(f"Render component diagnostics cannot parse source frameRate: {raw!r}")
    if frame_rate <= 0.0 or not math.isfinite(frame_rate):
        raise SystemExit(f"Render component diagnostics has invalid source frameRate: {raw!r}")
    return frame_rate

def timecode_seconds(raw: str) -> float:
    match = re.match(r"^(\d+):(\d+):(\d+)[;:](\d+)$", raw or "")
    if not match:
        raise SystemExit(f"Render component diagnostics cannot parse startTimecode: {raw!r}")
    hours, minutes, seconds, _frames = [int(part) for part in match.groups()]
    frame_rate = source_frame_rate()
    nominal_fps = int(round(frame_rate))
    frame_number = (((hours * 3600) + (minutes * 60) + seconds) * nominal_fps) + _frames
    if ";" in raw and nominal_fps in (30, 60):
        drop_frames = 2 if nominal_fps == 30 else 4
        total_minutes = (hours * 60) + minutes
        frame_number -= drop_frames * (total_minutes - (total_minutes // 10))
    return float(frame_number) / frame_rate

source_start_seconds = timecode_seconds(case.get("startTimecode", ""))
frame_rate = source_frame_rate()
case_id = str(case.get("caseId", ""))
diagnostic_contract = case.get("renderComponentDiagnostics")
if case_id == "p1000307_turn_1m26_1m46" and not isinstance(diagnostic_contract, dict):
    raise SystemExit("P1000307 renderComponentDiagnostics contract is required for focus CSV")
diagnostic_contract = diagnostic_contract if isinstance(diagnostic_contract, dict) else {}
focus_start = diagnostic_contract.get("focusStartSeconds")
focus_end = diagnostic_contract.get("focusEndSeconds")
focus_points = diagnostic_contract.get("focusPointsSeconds", [])
has_focus_contract = focus_start is not None and focus_end is not None
if has_focus_contract:
    focus_start = float(focus_start)
    focus_end = float(focus_end)
    if not (math.isfinite(focus_start) and math.isfinite(focus_end) and focus_end > focus_start):
        raise SystemExit(
            f"Render component diagnostics has invalid focus window: {focus_start!r}-{focus_end!r}"
        )
else:
    focus_start = 0.0
    focus_end = -1.0

expected_frame_count = str((case.get("source") or {}).get("frameCount", ""))
expected_proxy = "yes" if case.get("playbackMode") == "Proxy Only" else None
expected_crop = None
if isinstance(case.get("removeBlackEdges"), bool):
    expected_crop = "yes" if case.get("removeBlackEdges") else "no"

rows = []
lens_rows = {}
rigid_rows = {}
local_rows = {}
ridge_line_rows = {}
for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if lens_prefix in line:
        values = dict(pair_pattern.findall(line.split(lens_prefix, 1)[1]))
        if "analysisTime" in values and "sample" in values:
            lens_rows[(values["analysisTime"], values["sample"])] = values
        continue
    if rigid_prefix in line:
        values = dict(pair_pattern.findall(line.split(rigid_prefix, 1)[1]))
        if "analysisTime" in values and "sample" in values:
            rigid_rows[(values["analysisTime"], values["sample"])] = values
        continue
    if local_prefix in line:
        values = dict(pair_pattern.findall(line.split(local_prefix, 1)[1]))
        if "analysisTime" in values and "sample" in values:
            local_rows[(values["analysisTime"], values["sample"])] = values
        continue
    if ridge_line_prefix in line:
        values = dict(pair_pattern.findall(line.split(ridge_line_prefix, 1)[1]))
        if "analysisTime" in values and "sample" in values:
            ridge_line_rows[(values["analysisTime"], values["sample"])] = values
        continue
    if prefix not in line:
        continue
    message = line.split(prefix, 1)[1]
    values = dict(pair_pattern.findall(message))
    idx_match = idx_pattern.search(message)
    if idx_match:
        values["lowerIndex"] = idx_match.group(1)
        values["upperIndex"] = idx_match.group(2)
    try:
        analysis_time = float(values["analysisTime"])
    except (KeyError, ValueError):
        continue
    relative_time = analysis_time - source_start_seconds
    values["analysisTime"] = f"{analysis_time:.5f}"
    values["time"] = f"{relative_time:.5f}"
    values["sourceStartSeconds"] = f"{source_start_seconds:.5f}"
    values["caseId"] = case_id
    rows.append(values)

for row in rows:
    lens_row = lens_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
    if lens_row:
        row.update(lens_row)
    rigid_row = rigid_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
    if rigid_row:
        row.update(rigid_row)
    local_row = local_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
    if local_row:
        row.update(local_row)
    ridge_line_row = ridge_line_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
    if ridge_line_row:
        row.update(ridge_line_row)

source_local_rows = [
    row for row in rows
    if "sourceLocal" in str(row.get("lensBandCorrectionModel", ""))
]
missing_source_local_rows = [
    row for row in source_local_rows
    if row.get("sourceLensShakeLocalApplied", "") == ""
]
if missing_source_local_rows:
    raise SystemExit(
        "Render component diagnostics missing source-local lens rows: "
        f"missing={len(missing_source_local_rows)} sourceLocalRows={len(source_local_rows)} "
        f"localLogRows={len(local_rows)} log={log_path}"
    )

source_ridge_line_rows = [
    row for row in rows
    if "sourceRidgeLine" in str(row.get("lensBandCorrectionModel", ""))
]
missing_source_ridge_line_rows = [
    row for row in source_ridge_line_rows
    if row.get("sourceLensShakeRidgeLineApplied", "") == ""
]
if missing_source_ridge_line_rows:
    raise SystemExit(
        "Render component diagnostics missing source ridge-line lens rows: "
        f"missing={len(missing_source_ridge_line_rows)} sourceRidgeLineRows={len(source_ridge_line_rows)} "
        f"ridgeLineLogRows={len(ridge_line_rows)} log={log_path}"
    )

far_field_rigid_rows = [
    row for row in rows
    if "farFieldRigid" in str(row.get("lensBandCorrectionModel", ""))
]
missing_far_field_rigid_rows = [
    row for row in far_field_rigid_rows
    if row.get("lensFarFieldRigidLocalWarpSuppressed", "") == ""
]
if missing_far_field_rigid_rows:
    raise SystemExit(
        "Render component diagnostics missing far-field rigid lens rows: "
        f"missing={len(missing_far_field_rigid_rows)} farFieldRigidRows={len(far_field_rigid_rows)} "
        f"rigidLogRows={len(rigid_rows)} log={log_path}"
    )

if not rows:
    raise SystemExit(f"Render component diagnostics missing: no '{prefix.strip()}' log rows in {log_path}")

required_stage_fields = [
    "cameraX", "cameraY", "macroX", "macroY", "lensShakeX", "lensShakeY",
    "componentResidualX", "componentResidualY", "turnX", "turnY",
]
missing_stage_fields = [
    field for field in required_stage_fields
    if not any(field in row for row in rows)
]
if missing_stage_fields:
    raise SystemExit(
        "Render component diagnostics is missing unified 3-stage fields: "
        f"{', '.join(missing_stage_fields)} log={log_path}"
    )

obsolete_stage_fields = [
    field for field in ("microX", "microY", "macroX", "macroY", "trajectoryMicroX", "trajectoryMicroY")
    if any(field in row for row in rows)
]
if obsolete_stage_fields:
    raise SystemExit(
        "Render component diagnostics emitted deprecated MIJIT/MAJIT fields: "
        f"{', '.join(obsolete_stage_fields)} log={log_path}"
    )

def float_value(row: dict[str, str], key: str) -> float:
    try:
        value = float(row.get(key, "nan"))
    except ValueError:
        return math.nan
    return value if math.isfinite(value) else math.nan

target_rows = []
for row in rows:
    if expected_frame_count and row.get("frames") != expected_frame_count:
        continue
    if expected_proxy is not None and row.get("proxy") != expected_proxy:
        continue
    if expected_crop is not None and row.get("crop") != expected_crop:
        continue
    target_rows.append(row)
if not target_rows:
    raise SystemExit(
        "Render component diagnostics missing target rows: "
        f"expected frames={expected_frame_count or '<any>'} proxy={expected_proxy or '<any>'} "
        f"crop={expected_crop or '<any>'}; parsedRows={len(rows)} log={log_path}"
    )
rows = target_rows
rows.sort(key=lambda row: (float_value(row, "analysisTime"), float_value(row, "sample")))
columns = [
    "caseId",
    "time",
    "analysisTime",
    "sourceStartSeconds",
    "sample",
    "lowerIndex",
    "upperIndex",
    "frac",
    "frames",
    "pixelOffset.x",
    "pixelOffset.y",
    "macroPixelOffset.x",
    "macroPixelOffset.y",
    "cameraJitterPixelOffset.x",
    "cameraJitterPixelOffset.y",
    "lensShakePixelOffset.x",
    "lensShakePixelOffset.y",
    "lensShakeRotationDegrees",
    "lensShakeYawPitch.x",
    "lensShakeYawPitch.y",
    "lensShakeShear.x",
    "lensShakeShear.y",
    "lensShakePerspective.x",
    "lensShakePerspective.y",
    "lensShakeScore",
    "lensShakeSupport",
    "lensShakeWindowFrames",
    "lensShakeWindowSeconds",
    "lensShakeAxis",
    "lensShakeReason",
    "lensShakeRollingShutterCandidate",
    "lensBandCorrectionModel",
    "lensBandTop.dx",
    "lensBandTop.dy",
    "lensBandRidge.dx",
    "lensBandRidge.dy",
    "lensBandMid.dx",
    "lensBandMid.dy",
    "lensBandTopColumn.dx",
    "lensBandTopColumn.dy",
    "lensBandRidgeColumn.dx",
    "lensBandRidgeColumn.dy",
    "lensBandMidColumn.dx",
    "lensBandMidColumn.dy",
    "lensBandTopRowPhase.dx",
    "lensBandTopRowPhase.dy",
    "lensBandRidgeRowPhase.dx",
    "lensBandRidgeRowPhase.dy",
    "lensBandMidRowPhase.dx",
    "lensBandMidRowPhase.dy",
    "lensBandTopLocalRoll",
    "lensBandRidgeLocalRoll",
    "lensBandMidLocalRoll",
    "lensBandWarpSupport",
    "lensBandWarpApplied",
    "lensBandRollingShutterScore",
    "lensFarFieldRigid.dx",
    "lensFarFieldRigid.dy",
    "lensFarFieldRigidResidual.dx",
    "lensFarFieldRigidResidual.dy",
    "lensFarFieldRigidSupport",
    "lensFarFieldRigidApplied",
    "lensFarFieldRigidShapeConsistency",
    "lensFarFieldRigidForwardBackwardConsistency",
    "lensFarFieldRigidLocalWarpSuppressed",
    "farFieldRigidXQuiverScore",
    "farFieldRigidXBeforeLimiter",
    "farFieldRigidXAfterLimiter",
    "lensFarFieldMeshAvailable",
    "lensFarFieldMesh.dx",
    "lensFarFieldMesh.dy",
    "lensFarFieldMeshSupport",
    "lensFarFieldMeshBlend",
    "lensFarFieldMeshSupportedBins",
    "lensFarFieldMeshMaxBinDelta",
    "lensFarFieldMeshOpposingBins",
    "lensFarFieldMeshDominantWindowFrames",
    "lensFarFieldMeshDominantWindowSeconds",
    "lensFarFieldMeshDominantSupport",
    "lensFarFieldMeshDominantCell",
    "sourceLensShakeRidge.y",
    "sourceLensShakeRidgeSupport",
    "sourceLensShakeRidgeApplied",
    "sourceLensShakeRidgeLine.y",
    "sourceLensShakeRidgeLineRaw.y",
    "sourceLensShakeRidgeLineSupport",
    "sourceLensShakeRidgeLineBandSupported",
    "sourceLensShakeRidgeLineApplied",
    "sourceLensShakeRidgeCombined.y",
    "sourceLensShakeLocalSupport",
    "sourceLensShakeLocalApplied",
    "sourceLensShakeLocalTopLeft.dx",
    "sourceLensShakeLocalTopLeft.dy",
    "sourceLensShakeLocalTopCenter.dx",
    "sourceLensShakeLocalTopCenter.dy",
    "sourceLensShakeLocalTopRight.dx",
    "sourceLensShakeLocalTopRight.dy",
    "sourceLensShakeLocalRidgeLeft.dx",
    "sourceLensShakeLocalRidgeLeft.dy",
    "sourceLensShakeLocalRidgeCenter.dx",
    "sourceLensShakeLocalRidgeCenter.dy",
    "sourceLensShakeLocalRidgeRight.dx",
    "sourceLensShakeLocalRidgeRight.dy",
    "sourceLensShakeLocalMidLeft.dx",
    "sourceLensShakeLocalMidLeft.dy",
    "sourceLensShakeLocalMidCenter.dx",
    "sourceLensShakeLocalMidCenter.dy",
    "sourceLensShakeLocalMidRight.dx",
    "sourceLensShakeLocalMidRight.dy",
    "componentResidual.x",
    "componentResidual.y",
    "turnDetectedPixelOffset.x",
    "turnDetectedPixelOffset.y",
    "rotationDegrees",
    "cameraJitterRotationDegrees",
    "rawRotationDegrees",
    "temporalSmoothingRotationDelta",
    "perspective.x",
    "perspective.y",
    "shear.x",
    "shear.y",
    "yawPitchProxy.x",
    "yawPitchProxy.y",
    "warpConfidence",
    "blurAmount",
    "residual",
    "acceptedBlockCount",
    "totalBlockCount",
    "cropPosition.x",
    "cropPosition.y",
    "cropScale",
    "turnConfidence",
    "trackingQuality",
    "deltaX",
    "deltaY",
    "deltaSeconds",
    "sampleDelta",
    "previewWarming",
    "previewWarmupReason",
    "proxy",
    "crop",
    "identity",
]
source_keys = {
    "pixelOffset.x": "pixelX",
    "pixelOffset.y": "pixelY",
    "macroPixelOffset.x": "macroX",
    "macroPixelOffset.y": "macroY",
    "cameraJitterPixelOffset.x": "cameraX",
    "cameraJitterPixelOffset.y": "cameraY",
    "lensShakePixelOffset.x": "lensShakeX",
    "lensShakePixelOffset.y": "lensShakeY",
    "lensShakeRotationDegrees": "lensShakeRotation",
    "lensShakeYawPitch.x": "lensShakeYaw",
    "lensShakeYawPitch.y": "lensShakePitch",
    "lensShakeShear.x": "lensShakeShearX",
    "lensShakeShear.y": "lensShakeShearY",
    "lensShakePerspective.x": "lensShakePerspectiveX",
    "lensShakePerspective.y": "lensShakePerspectiveY",
    "lensBandCorrectionModel": "lensBandCorrectionModel",
    "lensBandTop.dx": "lensBandTopX",
    "lensBandTop.dy": "lensBandTopY",
    "lensBandRidge.dx": "lensBandRidgeX",
    "lensBandRidge.dy": "lensBandRidgeY",
    "lensBandMid.dx": "lensBandMidX",
    "lensBandMid.dy": "lensBandMidY",
    "lensBandTopColumn.dx": "lensBandTopColumnX",
    "lensBandTopColumn.dy": "lensBandTopColumnY",
    "lensBandRidgeColumn.dx": "lensBandRidgeColumnX",
    "lensBandRidgeColumn.dy": "lensBandRidgeColumnY",
    "lensBandMidColumn.dx": "lensBandMidColumnX",
    "lensBandMidColumn.dy": "lensBandMidColumnY",
    "lensBandTopRowPhase.dx": "lensBandTopRowPhaseX",
    "lensBandTopRowPhase.dy": "lensBandTopRowPhaseY",
    "lensBandRidgeRowPhase.dx": "lensBandRidgeRowPhaseX",
    "lensBandRidgeRowPhase.dy": "lensBandRidgeRowPhaseY",
    "lensBandMidRowPhase.dx": "lensBandMidRowPhaseX",
    "lensBandMidRowPhase.dy": "lensBandMidRowPhaseY",
    "lensBandTopLocalRoll": "lensBandTopLocalRoll",
    "lensBandRidgeLocalRoll": "lensBandRidgeLocalRoll",
    "lensBandMidLocalRoll": "lensBandMidLocalRoll",
    "lensBandWarpSupport": "lensBandWarpSupport",
    "lensBandWarpApplied": "lensBandWarpApplied",
    "lensBandRollingShutterScore": "lensBandRollingShutterScore",
    "lensFarFieldRigid.dx": "lensFarFieldRigidX",
    "lensFarFieldRigid.dy": "lensFarFieldRigidY",
    "lensFarFieldRigidResidual.dx": "lensFarFieldRigidResidualX",
    "lensFarFieldRigidResidual.dy": "lensFarFieldRigidResidualY",
    "lensFarFieldRigidSupport": "lensFarFieldRigidSupport",
    "lensFarFieldRigidApplied": "lensFarFieldRigidApplied",
    "lensFarFieldRigidShapeConsistency": "lensFarFieldRigidShapeConsistency",
    "lensFarFieldRigidForwardBackwardConsistency": "lensFarFieldRigidForwardBackwardConsistency",
    "lensFarFieldRigidLocalWarpSuppressed": "lensFarFieldRigidLocalWarpSuppressed",
    "farFieldRigidXQuiverScore": "farFieldRigidXQuiverScore",
    "farFieldRigidXBeforeLimiter": "farFieldRigidXBeforeLimiter",
    "farFieldRigidXAfterLimiter": "farFieldRigidXAfterLimiter",
    "lensFarFieldMeshAvailable": "lensFarFieldMeshAvailable",
    "lensFarFieldMesh.dx": "lensFarFieldMeshX",
    "lensFarFieldMesh.dy": "lensFarFieldMeshY",
    "lensFarFieldMeshSupport": "lensFarFieldMeshSupport",
    "lensFarFieldMeshBlend": "lensFarFieldMeshBlend",
    "lensFarFieldMeshSupportedBins": "lensFarFieldMeshSupportedBins",
    "lensFarFieldMeshMaxBinDelta": "lensFarFieldMeshMaxBinDelta",
    "lensFarFieldMeshOpposingBins": "lensFarFieldMeshOpposingBins",
    "lensFarFieldMeshDominantWindowFrames": "lensFarFieldMeshDominantWindowFrames",
    "lensFarFieldMeshDominantWindowSeconds": "lensFarFieldMeshDominantWindowSeconds",
    "lensFarFieldMeshDominantSupport": "lensFarFieldMeshDominantSupport",
    "lensFarFieldMeshDominantCell": "lensFarFieldMeshDominantCell",
    "sourceLensShakeRidge.y": "sourceLensShakeRidgeY",
    "sourceLensShakeRidgeSupport": "sourceLensShakeRidgeSupport",
    "sourceLensShakeRidgeApplied": "sourceLensShakeRidgeApplied",
    "sourceLensShakeRidgeLine.y": "sourceLensShakeRidgeLineY",
    "sourceLensShakeRidgeLineRaw.y": "sourceLensShakeRidgeLineRawY",
    "sourceLensShakeRidgeLineSupport": "sourceLensShakeRidgeLineSupport",
    "sourceLensShakeRidgeLineBandSupported": "sourceLensShakeRidgeLineBandSupported",
    "sourceLensShakeRidgeLineApplied": "sourceLensShakeRidgeLineApplied",
    "sourceLensShakeRidgeCombined.y": "sourceLensShakeRidgeCombinedY",
    "sourceLensShakeLocalSupport": "sourceLensShakeLocalSupport",
    "sourceLensShakeLocalApplied": "sourceLensShakeLocalApplied",
    "sourceLensShakeLocalTopLeft.dx": "sourceLensShakeLocalTopLeftX",
    "sourceLensShakeLocalTopLeft.dy": "sourceLensShakeLocalTopLeftY",
    "sourceLensShakeLocalTopCenter.dx": "sourceLensShakeLocalTopCenterX",
    "sourceLensShakeLocalTopCenter.dy": "sourceLensShakeLocalTopCenterY",
    "sourceLensShakeLocalTopRight.dx": "sourceLensShakeLocalTopRightX",
    "sourceLensShakeLocalTopRight.dy": "sourceLensShakeLocalTopRightY",
    "sourceLensShakeLocalRidgeLeft.dx": "sourceLensShakeLocalRidgeLeftX",
    "sourceLensShakeLocalRidgeLeft.dy": "sourceLensShakeLocalRidgeLeftY",
    "sourceLensShakeLocalRidgeCenter.dx": "sourceLensShakeLocalRidgeCenterX",
    "sourceLensShakeLocalRidgeCenter.dy": "sourceLensShakeLocalRidgeCenterY",
    "sourceLensShakeLocalRidgeRight.dx": "sourceLensShakeLocalRidgeRightX",
    "sourceLensShakeLocalRidgeRight.dy": "sourceLensShakeLocalRidgeRightY",
    "sourceLensShakeLocalMidLeft.dx": "sourceLensShakeLocalMidLeftX",
    "sourceLensShakeLocalMidLeft.dy": "sourceLensShakeLocalMidLeftY",
    "sourceLensShakeLocalMidCenter.dx": "sourceLensShakeLocalMidCenterX",
    "sourceLensShakeLocalMidCenter.dy": "sourceLensShakeLocalMidCenterY",
    "sourceLensShakeLocalMidRight.dx": "sourceLensShakeLocalMidRightX",
    "sourceLensShakeLocalMidRight.dy": "sourceLensShakeLocalMidRightY",
    "componentResidual.x": "componentResidualX",
    "componentResidual.y": "componentResidualY",
    "turnDetectedPixelOffset.x": "turnX",
    "turnDetectedPixelOffset.y": "turnY",
    "rotationDegrees": "rotation",
    "cameraJitterRotationDegrees": "cameraRotation",
    "rawRotationDegrees": "rawRotation",
    "temporalSmoothingRotationDelta": "smoothingRotationDelta",
    "perspective.x": "perspectiveX",
    "perspective.y": "perspectiveY",
    "shear.x": "shearX",
    "shear.y": "shearY",
    "yawPitchProxy.x": "yawPitchX",
    "yawPitchProxy.y": "yawPitchY",
    "blurAmount": "blur",
    "acceptedBlockCount": "acceptedBlocks",
    "totalBlockCount": "totalBlocks",
    "cropPosition.x": "cropX",
    "cropPosition.y": "cropY",
}

def output_row(row: dict[str, str]) -> dict[str, str]:
    return {column: row.get(source_keys.get(column, column), "") for column in columns}

def write_csv(path: Path, selected_rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for row in selected_rows:
            writer.writerow(output_row(row))

focus_rows = []
if has_focus_contract:
    focus_rows = [
        row for row in rows
        if focus_start <= float_value(row, "time") <= focus_end
    ]
    if not focus_rows:
        first_time = float_value(rows[0], "time")
        last_time = float_value(rows[-1], "time")
        raise SystemExit(
            "Render component diagnostics missing focus window rows: "
            f"requested {focus_start:.2f}-{focus_end:.2f}s, available {first_time:.2f}-{last_time:.2f}s, "
            f"log={log_path}"
        )
    warming_focus_rows = [row for row in focus_rows if row.get("previewWarming") == "yes"]
    if warming_focus_rows:
        first_warming = float_value(warming_focus_rows[0], "time")
        last_warming = float_value(warming_focus_rows[-1], "time")
        reasons = sorted({row.get("previewWarmupReason", "") for row in warming_focus_rows})
        raise SystemExit(
            "Render component diagnostics focus window contains Preview Warming frames: "
            f"rows={len(warming_focus_rows)} first={first_warming:.5f}s last={last_warming:.5f}s "
            f"reasons={reasons} log={log_path}"
        )
    unique_focus_times = sorted({round(float_value(row, "time"), 5) for row in focus_rows})
    focus_duration = focus_end - focus_start
    expected_focus_frames = max(1, int(math.floor(focus_duration * frame_rate)))
    min_coverage_ratio = float(diagnostic_contract.get("minFocusCoverageRatio", 0.85))
    min_focus_rows = max(1, int(math.floor(expected_focus_frames * min_coverage_ratio)))
    max_focus_gap = float(diagnostic_contract.get("maxFocusGapSeconds", max(0.05, 3.0 / frame_rate)))
    max_observed_gap = 0.0
    if len(unique_focus_times) > 1:
        max_observed_gap = max(
            b - a for a, b in zip(unique_focus_times, unique_focus_times[1:])
        )
    if len(unique_focus_times) < min_focus_rows or max_observed_gap > max_focus_gap:
        raise SystemExit(
            "Render component diagnostics focus coverage failed: "
            f"uniqueRows={len(unique_focus_times)} expected>={min_focus_rows} "
            f"maxGap={max_observed_gap:.5f}s limit={max_focus_gap:.5f}s "
            f"window={focus_start:.2f}-{focus_end:.2f}s log={log_path}"
        )
    identities = {row.get("identity", "") for row in focus_rows if row.get("identity")}
    if len(identities) > 1:
        raise SystemExit(
            "Render component diagnostics focus window has multiple cache identities: "
            f"{sorted(identities)} log={log_path}"
        )

component_residual_rows = focus_rows if focus_rows else rows
max_component_residual = 0.0
component_residual_count = 0
for row in component_residual_rows:
    residual_x = float_value(row, "componentResidualX")
    residual_y = float_value(row, "componentResidualY")
    if math.isfinite(residual_x) and math.isfinite(residual_y):
        max_component_residual = max(max_component_residual, math.hypot(residual_x, residual_y))
        component_residual_count += 1
if component_residual_count > 0:
    max_allowed_component_residual = float(diagnostic_contract.get("maxComponentResidualPixels", 0.02))
    if max_component_residual > max_allowed_component_residual:
        raise SystemExit(
            "Render component diagnostics component residual failed: "
            f"maxResidual={max_component_residual:.5f}px "
            f"limit={max_allowed_component_residual:.5f}px rows={component_residual_count} log={log_path}"
        )
write_csv(csv_path, rows)
write_csv(focus_path, focus_rows)

point_columns = ["targetTime", "timeError"] + columns
with points_path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=point_columns)
    writer.writeheader()
    for point in focus_points:
        point = float(point)
        search_rows = focus_rows if has_focus_contract else rows
        nearest = min(search_rows, key=lambda row: abs(float_value(row, "time") - point))
        time_error = float_value(nearest, "time") - point
        max_point_error = float(diagnostic_contract.get("maxFocusPointTimeErrorSeconds", max(0.025, 1.5 / frame_rate)))
        if abs(time_error) > max_point_error:
            raise SystemExit(
                "Render component diagnostics focus point coverage failed: "
                f"target={point:.5f}s nearest={float_value(nearest, 'time'):.5f}s "
                f"error={time_error:.5f}s limit={max_point_error:.5f}s log={log_path}"
            )
        output = output_row(nearest)
        output["targetTime"] = f"{point:.5f}"
        output["timeError"] = f"{time_error:.5f}"
        writer.writerow(output)

print(
    "Render component diagnostics: "
    f"rows={len(rows)} focusRows={len(focus_rows)} "
    f"componentResidualMax={max_component_residual:.5f}px "
    f"csv={csv_path} focus={focus_path} points={points_path}"
)
PY
}

collect_lens_band_source_diagnostics() {
	local case_file="$1"
	local video_path="$2"
	local output_dir="$3"
	local render_log_path="${output_dir}/render_components.log"
	[[ -f "$render_log_path" ]] || fail "lens band source diagnostics missing render log: $render_log_path"
	local case_id
	case_id="$(python3 - "$case_file" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("caseId", ""))
PY
)"
	if [[ "$case_id" == "p1000307_micro_macro_1m44_1m56" ]]; then
		python3 "${ROOT_DIR}/tests/stabilizer_lens_band_diagnostics.py" \
			--video "$video_path" \
			--render-log "$render_log_path" \
			--output-dir "$output_dir" \
			--forbid-global-lens
		return
	fi
	python3 "${ROOT_DIR}/tests/stabilizer_lens_band_diagnostics.py" \
		--video "$video_path" \
		--render-log "$render_log_path" \
		--output-dir "$output_dir"
}

fail_if_recent_render_mismatches_case() {
	local case_file="$1"
	local context="${2:-prepare}"
	local evidence_path
	evidence_path="$(mktemp "${TMPDIR:-/tmp}/stabilizer_recent_render_evidence.XXXXXX")"
	local predicate='(subsystem == "com.justadev.TokyoWalkingStabilizer" OR process == "TokyoWalkingStabilizer XPC Service") AND eventMessage CONTAINS "Render Host Analysis decision"'
	if ! log show --style compact --last 30s --predicate "$predicate" >"$evidence_path" 2>&1; then
		rm -f "$evidence_path"
		return 0
	fi
	local detail=""
	if ! detail="$(python3 - "$case_file" "$evidence_path" "$context" 2>&1 <<'PY'
import json
import re
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
evidence_path = Path(sys.argv[2])
context = sys.argv[3]
source_clip = Path(case.get("sourceClip", "")).stem
digits = "".join(re.findall(r"\d+", source_clip))
clip_token = digits[-6:] if len(digits) >= 6 else source_clip
frame_count = str(case.get("source", {}).get("frameCount", ""))
frame_token = f"frames {frame_count}" if frame_count else ""
lines = [
    line.rstrip("\n")
    for line in evidence_path.read_text(encoding="utf-8", errors="replace").splitlines()
    if "Render Host Analysis decision" in line
]
if not lines:
    raise SystemExit(0)
target_lines = []
for line in lines:
    if frame_token and frame_token in line:
        target_lines.append(line)
    elif not frame_token and clip_token and (clip_token in line or source_clip in line):
        target_lines.append(line)
if target_lines:
    raise SystemExit(0)
wrong_lines = []
for line in lines:
    wrong_token = re.search(r"\.\.\.(\d{6})", line)
    wrong_frames = re.search(r"frames\s+(\d+)", line)
    if wrong_token or wrong_frames:
        wrong_lines.append(line)
if wrong_lines:
    preview = wrong_lines[-1][-420:]
    raise SystemExit(
        f"{context}: recent FxPlug render evidence is for a different clip than {source_clip} "
        f"(expected token={clip_token}, frames={frame_count}); latest={preview}; log={evidence_path}"
    )
raise SystemExit(0)
PY
)"; then
		printf 'Ignoring non-target recent FxPlug render evidence while preparing this case: %s\n' "$detail" >&2
	fi
	rm -f "$evidence_path"
}

wait_for_target_playback_plan_ready() {
	local case_file="$1"
	local timecode_entry="$2"
	local max_attempts="${STABILIZER_E2E_PLAYBACK_READY_ATTEMPTS:-8}"
	local warm_seconds="${STABILIZER_E2E_PLAYBACK_READY_WARM_SECONDS:-1.2}"
	local lookback_seconds="${STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS:-600}"
	local case_id
	case_id="$(json_value "$case_file" caseId)"
	local last_output=""
	for attempt in $(seq 1 "$max_attempts"); do
		local ready_start
		local ready_end
		local start_date
		local end_date
		local evidence_path
		ready_start="$(now_epoch_seconds)"
		press_stop_playback
		focus_timeline
		seek_timecode "$timecode_entry"
		focus_timeline
		sleep 0.2
		press_start_playback
		sleep "$warm_seconds"
		press_stop_playback
		seek_timecode "$timecode_entry"
		focus_timeline
		sleep 0.2
		ready_end="$(now_epoch_seconds)"
		start_date="$(log_timestamp_from_epoch "$ready_start" "$((-lookback_seconds))")"
		end_date="$(log_timestamp_from_epoch "$ready_end" 1)"
		mkdir -p "$ARTIFACT_ROOT"
		evidence_path="${ARTIFACT_ROOT}/playback_ready_${case_id}_attempt${attempt}_$(date +%Y%m%d_%H%M%S).log"
		local predicate='(subsystem == "com.justadev.TokyoWalkingStabilizer" OR process == "TokyoWalkingStabilizer XPC Service") AND (eventMessage CONTAINS "Render Host Analysis decision" OR eventMessage CONTAINS "Playback trajectory prepared" OR eventMessage CONTAINS "Playback trajectory fallback" OR eventMessage CONTAINS "Playback trajectory not ready" OR eventMessage CONTAINS "Auto Crop playback scale plan prepared async" OR eventMessage CONTAINS "Auto Crop playback fallback" OR eventMessage CONTAINS "Auto Crop playback unavailable" OR eventMessage CONTAINS "Auto Crop playback plan deferred" OR eventMessage CONTAINS "Auto Crop playback final framing repair")'
		if ! log show --style compact --start "$start_date" --end "$end_date" --predicate "$predicate" >"$evidence_path" 2>&1; then
			rm -f "$evidence_path"
			fail "could not read FxPlug playback readiness logs before capture"
		fi
		if output="$(python3 - "$case_file" "$evidence_path" "$attempt" 2>&1 <<'PY'
import json
import re
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
evidence_path = Path(sys.argv[2])
attempt = sys.argv[3]
source_clip = Path(case.get("sourceClip", "")).stem
digits = "".join(re.findall(r"\d+", source_clip))
frame_count = str(case.get("source", {}).get("frameCount", ""))
frame_token = f"frames {frame_count}" if frame_count else ""
sample_token = f"samples {frame_count}" if frame_count else ""
requires_auto_crop = bool(case.get("removeBlackEdges"))
tokens = [source_clip]
if digits:
    tokens.append(digits)
    if len(digits) >= 6:
        tokens.append(digits[-6:])
tokens = [token for token in dict.fromkeys(tokens) if token]
fallback_pattern = re.compile(
    r"Auto Crop playback fallback|Auto Crop playback unavailable|"
    r"Auto Crop playback plan deferred|Auto Crop playback final framing repair|"
    r"Playback trajectory fallback|Playback trajectory not ready"
)

def matches_target(line: str) -> bool:
    if "Render Host Analysis decision" in line and frame_token:
        return frame_token in line
    if frame_token and frame_token in line:
        return True
    return any(token in line for token in tokens)

lines = [
    line.rstrip("\n")
    for line in evidence_path.read_text(encoding="utf-8", errors="replace").splitlines()
]

def render_decision_ready(line: str) -> bool:
    if "Render Host Analysis decision" not in line:
        return False
    if not matches_target(line):
        return False
    if "proxy yes" not in line or "prepared yes" not in line or "stabilization active" not in line:
        return False
    if requires_auto_crop:
        return "auto crop on" in line
    return "auto crop off" in line

target_render_ready = [
    (index, line) for index, line in enumerate(lines)
    if render_decision_ready(line)
]
latest_ready_index = target_render_ready[-1][0] if target_render_ready else None
target_lines_after_ready = (
    lines[latest_ready_index + 1:]
    if latest_ready_index is not None
    else lines
)
target_trajectory_prepared = [
    line for line in lines
    if "Playback trajectory prepared" in line and matches_target(line)
]
target_fallbacks = [
    line for line in lines
    if fallback_pattern.search(line) and matches_target(line)
]
target_fallbacks_after_ready = [
    line for line in target_lines_after_ready
    if fallback_pattern.search(line) and matches_target(line)
]
ambiguous_fallbacks = [
    line for line in lines
    if fallback_pattern.search(line) and not matches_target(line)
]
target_trajectory_unready = [
    line for line in target_fallbacks_after_ready
    if "Playback trajectory" in line
]
target_crop_unready = [
    line for line in target_fallbacks_after_ready
    if "Auto Crop playback" in line
]

# The Auto Crop ready logs currently have sample counts but no clip/cache
# identity. Treat them as target evidence only in this controlled pre-record
# evidence window, and require the sample count to match this case when no
# fresh render decision was logged because Final Cut Pro reused cached frames.
def is_crop_prepared_line(line: str) -> bool:
    if (
        "Auto Crop playback scale plan prepared async" not in line
        and "Auto Crop playback scale plan prepared inline" not in line
    ):
        return False
    return not sample_token or sample_token in line

crop_prepared_in_window = any(is_crop_prepared_line(line) for line in target_lines_after_ready)
target_crop_prepared = [
    (index, line) for index, line in enumerate(lines)
    if is_crop_prepared_line(line)
]
render_ready = bool(target_render_ready)
trajectory_ready = bool(target_trajectory_prepared) or (render_ready and not target_trajectory_unready)
crop_ready = (render_ready and crop_prepared_in_window) or (render_ready and not target_crop_unready)
latest_prepared_index = None
if target_trajectory_prepared and target_crop_prepared:
    trajectory_indexes = [
        index for index, line in enumerate(lines)
        if "Playback trajectory prepared" in line and matches_target(line)
    ]
    latest_prepared_index = max(trajectory_indexes[-1], target_crop_prepared[-1][0])
prepared_only_fallbacks_after_ready = (
    [
        line for line in lines[latest_prepared_index + 1:]
        if fallback_pattern.search(line) and matches_target(line)
    ]
    if latest_prepared_index is not None
    else []
)
prepared_only_ready = latest_prepared_index is not None and not prepared_only_fallbacks_after_ready

if render_ready and trajectory_ready and crop_ready and not target_fallbacks_after_ready:
    print(
        "Playback readiness verified before capture: "
        f"target render prepared/proxy/auto-crop ready for {source_clip}."
    )
    raise SystemExit(0)
if prepared_only_ready:
    print(
        "Playback readiness verified before capture: "
        f"target trajectory/auto-crop prepared for {source_clip}; "
        "no fresh render decision was logged in this cached Viewer pass."
    )
    raise SystemExit(0)

parts = [
    f"attempt={attempt}",
    f"clip={source_clip}",
    f"frames={frame_count}",
    f"targetRenderReady={str(render_ready).lower()}",
    f"trajectoryReady={str(trajectory_ready).lower()}",
    f"cropReady={str(crop_ready).lower()}",
    f"targetFallbacks={len(target_fallbacks_after_ready)}",
    f"ambiguousFallbacks={len(ambiguous_fallbacks)}",
]
if target_fallbacks_after_ready:
    parts.append("latestTargetFallback=" + target_fallbacks_after_ready[-1][-260:])
elif prepared_only_fallbacks_after_ready:
    parts.append("latestPreparedOnlyFallback=" + prepared_only_fallbacks_after_ready[-1][-260:])
if target_render_ready:
    parts.append("latestReadyRender=" + target_render_ready[-1][1][-320:])
render_lines = [line for line in lines if "Render Host Analysis decision" in line]
if render_lines:
    parts.append("latestRender=" + render_lines[-1][-320:])
else:
    parts.append("latestRender=none")
raise SystemExit("; ".join(parts) + f"; log={evidence_path}")
PY
)"; then
			printf '%s\n' "$output"
			rm -f "$evidence_path"
			return 0
		fi
		last_output="$output"
		printf 'Playback readiness not ready yet for %s (%s/%s): %s\n' "$case_id" "$attempt" "$max_attempts" "$last_output"
		sleep 0.6
	done
	fail "target playback trajectory/crop scale plan did not become ready before recording: $last_output"
}

case_project_db_path() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
from pathlib import Path
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    case = json.load(handle)

library = Path(case["library"])
project = case["project"]
source_paths = [case.get("originalMedia"), case.get("proxyMedia")]
event_names = []
for raw_path in source_paths:
    if not raw_path:
        continue
    try:
        relative = Path(raw_path).resolve().relative_to(library.resolve())
    except ValueError:
        continue
    if relative.parts:
        event_names.append(relative.parts[0])

event_candidates = []
for event_name in event_names:
    event_candidates.append(library / event_name / project / "CurrentVersion.fcpevent")

unique = []
seen = set()
for candidate in event_candidates:
    key = str(candidate)
    if key in seen:
        continue
    seen.add(key)
    if candidate.exists():
        unique.append(candidate)

if len(unique) == 1:
    print(unique[0])
    raise SystemExit(0)

candidates = []
if library.exists():
    for candidate in library.glob("*/*/CurrentVersion.fcpevent"):
        if candidate.parent.name == project:
            candidates.append(candidate)

unique = []
seen = set()
for candidate in candidates:
    key = str(candidate)
    if key in seen:
        continue
    seen.add(key)
    if candidate.exists():
        unique.append(candidate)

if len(unique) != 1:
    raise SystemExit(
        "expected exactly one project CurrentVersion.fcpevent for "
        f"{project}, found {len(unique)}"
    )

print(unique[0])
PY
}

case_event_name() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
from pathlib import Path
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    case = json.load(handle)

library = Path(case["library"]).expanduser().absolute()
event_names = []
for key in ("originalMedia", "proxyMedia"):
    raw_path = case.get(key)
    if not raw_path:
        continue
    try:
        relative = Path(raw_path).expanduser().absolute().relative_to(library)
    except ValueError:
        continue
    if relative.parts:
        event_names.append(relative.parts[0])

unique = []
for event_name in event_names:
    if event_name not in unique:
        unique.append(event_name)

if len(unique) != 1:
    raise SystemExit(f"expected exactly one Event name from case media paths, found {len(unique)}")

print(unique[0])
PY
}

assert_case_project_contains_effect() {
	local case_file="$1"
	local project_db
	local expected_effect
	local remove_black_edges
	if ! project_db="$(case_project_db_path "$case_file")"; then
		fail "could not resolve a unique Final Cut Pro project database for case: $case_file"
	fi
	[[ -n "$project_db" ]] || fail "resolved Final Cut Pro project database path was empty for case: $case_file"
	[[ -f "$project_db" ]] || fail "resolved Final Cut Pro project database is not a file: $project_db"
	expected_effect="$(json_value "$case_file" expectedEffect)"
	remove_black_edges="$(json_bool_value "$case_file" removeBlackEdges)"
	python3 - "$project_db" "$expected_effect" "$remove_black_edges" <<'PY'
from pathlib import Path
import sys

db_path = Path(sys.argv[1])
expected_effect = sys.argv[2].encode("utf-8")
require_remove_black_edges = sys.argv[3] == "true"
payload = db_path.read_bytes()
if expected_effect not in payload:
    raise SystemExit(
        f"case project does not contain expected effect {sys.argv[2]!r}: {db_path}"
    )
if require_remove_black_edges and b"Remove Black Edges" not in payload:
    raise SystemExit(
        f"case project does not contain Remove Black Edges parameter: {db_path}"
    )
print(f"Case project contains expected Stabilizer effect metadata: {db_path}")
PY
}

viewer_roi_field() {
	local roi="$1"
	local field="$2"
	python3 - "$roi" "$field" <<'PY'
import sys

parts = sys.argv[1].split(",")
field = int(sys.argv[2])
if len(parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
try:
    values = [int(part) for part in parts]
except ValueError:
    raise SystemExit("viewer ROI values must be integers")
if values[2] <= 0 or values[3] <= 0:
    raise SystemExit("viewer ROI width/height must be positive")
print(values[field])
PY
}

viewer_roi_zero_origin() {
	local roi="$1"
	local width
	local height
	width="$(viewer_roi_field "$roi" 2)"
	height="$(viewer_roi_field "$roi" 3)"
	if (( width % 2 == 1 )); then
		width=$((width - 1))
	fi
	if (( height % 2 == 1 )); then
		height=$((height - 1))
	fi
	printf '0,0,%s,%s\n' "$width" "$height"
}

press_space() {
	/usr/bin/osascript <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		key code 49
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "space key" 30 1
}

press_start_playback() {
	/usr/bin/osascript <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		click menu item "Play" of menu 1 of menu item "Playback" of menu 1 of menu bar item "View" of menu bar 1
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "View > Playback > Play" 30 1
}

press_stop_playback() {
	/usr/bin/osascript <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		key code 40
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "stop playback key" 30 1
}

fcp_playhead_value() {
	/usr/bin/osascript <<'APPLESCRIPT'
on run
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontWindow to my frontFinalCutProWindow()
			set playheadElement to my firstElementByDescription(frontWindow, "Playhead", 12)
			if playheadElement is missing value then return "missing"
			try
				return value of playheadElement as text
			on error
				return "unreadable"
			end try
		end tell
	end tell
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstElementByDescription(elementRef, wantedDescription, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (description of elementRef as text) is wantedDescription then return elementRef
		end try
		try
			set childElements to UI elements of elementRef
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstElementByDescription(childElement, wantedDescription, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementByDescription
APPLESCRIPT
}

assert_fcp_frontmost() {
	local context="${1:-FCP UI operation}"
	local frontmost
	frontmost="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
	return name of first application process whose frontmost is true
end tell
APPLESCRIPT
)"
	[[ "$frontmost" == "Final Cut Pro" ]] \
		|| fail "${context}: Final Cut Pro is not frontmost before recording (frontmost=${frontmost})"
}

dismiss_fcp_modal_alerts() {
	/usr/bin/osascript <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		repeat with targetWindow in windows
			try
				if exists button "OK" of targetWindow then
					click button "OK" of targetWindow
					return "dismissed"
				end if
				if exists sheet 1 of targetWindow then
					if exists button "OK" of sheet 1 of targetWindow then
						click button "OK" of sheet 1 of targetWindow
						return "dismissed"
					end if
				end if
			end try
		end repeat
	end tell
end tell
return "none"
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "dismiss FCP modal alerts" 30 1
}

dismiss_known_screen_blockers() {
	local finder_visible
	finder_visible="$(/usr/bin/osascript -e 'tell application "Finder" to get visible' 2>/dev/null || true)"
	if [[ "$finder_visible" == "true" ]]; then
		/usr/bin/osascript \
			-e 'tell application "Finder" to set visible to false' \
			-e 'tell application "Final Cut Pro" to activate' >/dev/null 2>&1 || true
		printf 'hid-visible-Finder\n'
		return 0
	fi
	/usr/bin/osascript -e 'tell application "Final Cut Pro" to activate' >/dev/null 2>&1 || true
	printf 'none\n'
}

fail_if_known_screen_blocked() {
	local blocker_result="$1"
	if [[ "$blocker_result" == blocked-* ]]; then
		fail "known screen blocker is in front of Final Cut Pro Viewer: ${blocker_result}. Refusing to record a non-FCP E2E video."
	fi
}

set_viewer_zoom_to_fit() {
	/usr/bin/osascript >/dev/null <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		keystroke "3" using {command down}
		delay 0.1
		keystroke "z" using {shift down}
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "viewer zoom to fit" 50 1
}

set_fcp_viewer_channel_green() {
	set_fcp_viewer_channel "Green" >/dev/null \
		|| fail "could not set Final Cut Pro Viewer Channel Green"
	printf 'FCP Viewer Channel set to: Green\n'
}

fcp_viewer_menu_setting() {
	local action="$1"
	local setting_kind="$2"
	local target_value="$3"
	[[ -n "$target_value" ]] || return 0
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-viewer-menu-setting.XXXXXX")"
	/usr/bin/osascript - "$action" "$setting_kind" "$target_value" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set actionName to item 1 of argv
	set settingKind to item 2 of argv
	set targetValue to item 3 of argv
	set menuPaths to my menuPathsFor(settingKind, targetValue)

	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			key code 53
		end tell
	end tell
	delay 0.1

	if actionName is "set" then
		set clickedPath to my clickFirstMenuPath(menuPaths)
		delay 0.25
		set checkedPath to my firstCheckedMenuPath(menuPaths)
		return settingKind & "=" & targetValue & " set via " & clickedPath & "; verified checked via " & checkedPath
	else if actionName is "verify" then
		set checkedPath to my firstCheckedMenuPath(menuPaths)
		return settingKind & "=" & targetValue & " verified checked via " & checkedPath
	else
		error "unsupported viewer menu setting action: " & actionName
	end if
end run

on menuPathsFor(settingKind, targetValue)
	if settingKind is "media-playback" then
		return {{"View", "Media Playback", targetValue}, {"View", "Playback", targetValue}}
	else if settingKind is "channel" then
		return {{"View", "Channels", targetValue}, {"View", "Channel", targetValue}}
	end if
	error "unsupported viewer menu setting kind: " & settingKind
end menuPathsFor

on clickFirstMenuPath(menuPaths)
	set triedPaths to {}
	repeat with menuPathRef in menuPaths
		set menuPath to contents of menuPathRef
		try
			my clickMenuPath(menuPath)
			return my joinedMenuPath(menuPath)
		on error menuError
			set end of triedPaths to my joinedMenuPath(menuPath) & " (" & menuError & ")"
			my closeMenus()
		end try
	end repeat
	error "could not click any menu path. Tried: " & my joinTextList(triedPaths, "; ")
end clickFirstMenuPath

on firstCheckedMenuPath(menuPaths)
	set triedPaths to {}
	repeat with menuPathRef in menuPaths
		set menuPath to contents of menuPathRef
		try
			if my menuPathIsChecked(menuPath) then
				my closeMenus()
				return my joinedMenuPath(menuPath)
			end if
			set end of triedPaths to my joinedMenuPath(menuPath) & " (not checked)"
		on error menuError
			set end of triedPaths to my joinedMenuPath(menuPath) & " (" & menuError & ")"
		end try
		my closeMenus()
	end repeat
	error "target menu item was not verified checked. Tried: " & my joinTextList(triedPaths, "; ")
end firstCheckedMenuPath

on clickMenuPath(menuPath)
	tell application "System Events"
		tell process "Final Cut Pro"
			set currentMenu to menu 1 of menu bar item (item 1 of menuPath) of menu bar 1
			repeat with pathIndex from 2 to count of menuPath
				set currentMenuItem to menu item (item pathIndex of menuPath) of currentMenu
				if pathIndex is (count of menuPath) then
					click currentMenuItem
				else
					set currentMenu to menu 1 of currentMenuItem
				end if
			end repeat
		end tell
	end tell
end clickMenuPath

on menuPathIsChecked(menuPath)
	tell application "System Events"
		tell process "Final Cut Pro"
			set currentMenu to menu 1 of menu bar item (item 1 of menuPath) of menu bar 1
			repeat with pathIndex from 2 to count of menuPath
				set currentMenuItem to menu item (item pathIndex of menuPath) of currentMenu
				if pathIndex is (count of menuPath) then
					return my menuItemLooksChecked(currentMenuItem)
				else
					set currentMenu to menu 1 of currentMenuItem
				end if
			end repeat
		end tell
	end tell
	return false
end menuPathIsChecked

on menuItemLooksChecked(menuItemRef)
	tell application "System Events"
		try
			set markValue to value of attribute "AXMenuItemMarkChar" of menuItemRef
			if markValue is not missing value then
				set markText to markValue as text
				if markText is not "" then return true
			end if
		end try
		try
			set itemValue to value of menuItemRef
			if itemValue is 1 then return true
			if itemValue is "1" then return true
			if itemValue is true then return true
		end try
		try
			if selected of menuItemRef then return true
		end try
	end tell
	return false
end menuItemLooksChecked

on closeMenus()
	tell application "System Events"
		try
			tell process "Final Cut Pro" to key code 53
		end try
	end tell
	delay 0.05
end closeMenus

on joinedMenuPath(menuPath)
	return my joinTextList(menuPath, " > ")
end joinedMenuPath

on joinTextList(textItems, separatorText)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to separatorText
	set joinedText to textItems as text
	set AppleScript's text item delimiters to previousDelimiters
	return joinedText
end joinTextList
APPLESCRIPT
	local osascript_pid=$!
	if wait_for_ui_osascript "$osascript_pid" "Viewer ${setting_kind} ${target_value} ${action}" 100 0; then
		cat "$output_file"
		rm -f "$output_file"
		return 0
	fi
	cat "$output_file" >&2
	rm -f "$output_file"
	return 1
}

normalize_fcp_window_frame() {
	timeout 6 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		set targetWindow to missing value
		repeat with candidateWindow in windows
			try
				if subrole of candidateWindow is "AXStandardWindow" then
					set targetWindow to candidateWindow
					exit repeat
				end if
			end try
		end repeat
		if targetWindow is missing value then return
		try
			set position of targetWindow to {0, 46}
		end try
		try
			set size of targetWindow to {1936, 1050}
		end try
	end tell
end tell
APPLESCRIPT
}

dismiss_fcp_menus() {
	/usr/bin/osascript -e 'tell application "System Events" to tell process "Final Cut Pro" to key code 53' >/dev/null 2>&1 || true
}

set_fcp_viewer_option_via_view_options_ax() {
	local target_value="$1"
	local setting_kind="$2"
	normalize_fcp_window_frame
	timeout 12 /usr/bin/osascript - "$target_value" "$setting_kind" <<'APPLESCRIPT'
on run argv
	set targetValue to item 1 of argv
	set settingKind to item 2 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			key code 53
			delay 0.1
			set optionsButton to my viewOptionsButton()
			if optionsButton is missing value then error "View Options Menu Button not found"
			set menuRef to my showViewOptionsMenu(optionsButton)
			set targetElement to my viewOptionsTargetItem(menuRef, settingKind, targetValue)
			if targetElement is missing value then error "View Options item not found: " & targetValue & ". Visible menu tree: " & my menuTree(menuRef, 0, 4)
			my pressElementOrAncestor(targetElement, targetValue)
			delay 0.25
			key code 53
			delay 0.1
			set verifyMenu to my showViewOptionsMenu(optionsButton)
			set verifyElement to my viewOptionsTargetItem(verifyMenu, settingKind, targetValue)
			if verifyElement is missing value then error "View Options verify item not found: " & targetValue & ". Visible menu tree: " & my menuTree(verifyMenu, 0, 4)
			if not my menuItemLooksChecked(verifyElement) then error "View Options item did not become checked: " & targetValue
			key code 53
		end tell
	end tell
	return settingKind & "=" & targetValue & " set via View Options AX popover"
end run

on viewOptionsButton()
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontWindow to my frontFinalCutProWindow()
			set directButton to my viewOptionsButtonByKnownPath(frontWindow)
			if directButton is not missing value then return directButton
			return my firstMenuButtonByDescription(frontWindow, "View Options Menu Button", 14)
		end tell
	end tell
end viewOptionsButton

on viewOptionsButtonByKnownPath(rootElement)
	tell application "System Events"
		repeat with pathRef in {{1, 1, 1, 2, 1, 4, 2, 4}, {1, 1, 1, 2, 1, 5, 2, 4}}
			try
				set currentElement to rootElement
				repeat with childIndex in pathRef
					set currentElement to UI element childIndex of currentElement
				end repeat
				if (role of currentElement as text) is "AXMenuButton" and (description of currentElement as text) is "View Options Menu Button" then return currentElement
			end try
		end repeat
	end tell
	return missing value
end viewOptionsButtonByKnownPath

on showViewOptionsMenu(optionsButton)
	tell application "System Events"
		try
			perform action "AXShowMenu" of optionsButton
		on error
			perform action "AXPress" of optionsButton
		end try
		delay 0.25
		return menu 1 of optionsButton
	end tell
end showViewOptionsMenu

on viewOptionsTargetItem(menuRef, settingKind, requiredName)
	set directItem to my firstDirectMenuItemNamed(menuRef, requiredName)
	if directItem is not missing value then return directItem
	set parentNames to my viewOptionsParentNames(settingKind)
	tell application "System Events"
		repeat with itemRef in menu items of menuRef
			try
				set parentName to name of itemRef as text
				if my textListContains(parentNames, parentName) then
					set nestedItem to my firstDescendantMenuItemNamed(itemRef, requiredName, 4)
					if nestedItem is not missing value then return nestedItem
				end if
			end try
		end repeat
	end tell
	return missing value
end viewOptionsTargetItem

on viewOptionsParentNames(settingKind)
	if settingKind is "media-playback" then
		return {"Media Playback", "Playback", "Playback Media", "Viewer Media Playback"}
	else if settingKind is "channel" then
		return {"Color Channels", "Channels", "Channel"}
	end if
	return {}
end viewOptionsParentNames

on firstDirectMenuItemNamed(menuRef, requiredName)
	tell application "System Events"
		try
			repeat with itemRef in menu items of menuRef
				try
					if (name of itemRef as text) is requiredName then return itemRef
				end try
			end repeat
		end try
	end tell
	return missing value
end firstDirectMenuItemNamed

on firstDescendantMenuItemNamed(rootItem, requiredName, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (name of rootItem as text) is requiredName then return rootItem
		end try
		try
			set childMenu to menu 1 of rootItem
			repeat with childItem in menu items of childMenu
				set foundItem to my firstDescendantMenuItemNamed(childItem, requiredName, remainingDepth - 1)
				if foundItem is not missing value then return foundItem
			end repeat
		end try
	end tell
	return missing value
end firstDescendantMenuItemNamed

on textListContains(textItems, candidateText)
	repeat with textItem in textItems
		if (textItem as text) is candidateText then return true
	end repeat
	return false
end textListContains

on menuTree(menuRef, depth, remainingDepth)
	if remainingDepth < 0 then return ""
	set indentText to ""
	repeat depth times
		set indentText to indentText & "  "
	end repeat
	set lines to {}
	tell application "System Events"
		try
			repeat with itemRef in menu items of menuRef
				set itemName to "<unnamed>"
				try
					set itemName to name of itemRef as text
				end try
				set end of lines to indentText & itemName
				try
					set childMenu to menu 1 of itemRef
					set childTree to my menuTree(childMenu, depth + 1, remainingDepth - 1)
					if childTree is not "" then set end of lines to childTree
				end try
			end repeat
		end try
	end tell
	return my joinTextList(lines, " | ")
end menuTree

on menuItemLooksChecked(menuItemRef)
	tell application "System Events"
		try
			set markValue to value of attribute "AXMenuItemMarkChar" of menuItemRef
			if markValue is not missing value then
				set markText to markValue as text
				if markText is not "" then return true
			end if
		end try
		try
			set itemValue to value of menuItemRef
			if itemValue is 1 then return true
			if itemValue is "1" then return true
			if itemValue is true then return true
		end try
		try
			if selected of menuItemRef then return true
		end try
	end tell
	return false
end menuItemLooksChecked

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on pressElementOrAncestor(elementReference, labelText)
	set currentElement to elementReference
	repeat with attemptIndex from 1 to 5
		try
			tell application "System Events" to perform action "AXPress" of currentElement
			return true
		end try
		try
			tell application "System Events" to set currentElement to parent of currentElement
		on error
			exit repeat
		end try
	end repeat
	error "could not press View Options item or ancestor: " & labelText
end pressElementOrAncestor

on firstMenuButtonByDescription(rootElement, wantedDescription, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set candidateRole to role of rootElement as text
			set candidateDescription to ""
			try
				set candidateDescription to description of rootElement as text
			end try
			if candidateRole is "AXMenuButton" and candidateDescription is wantedDescription then return rootElement
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstMenuButtonByDescription(childElement, wantedDescription, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstMenuButtonByDescription

on firstElementContainingText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	if my elementContainsText(rootElement, requiredText) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstElementContainingText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementContainingText

on elementContainsText(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) contains requiredText then return true
		end ignoring
	end repeat
	return false
end elementContainsText
APPLESCRIPT
}

set_fcp_viewer_media_playback() {
	local playback_mode="$1"
	[[ -n "$playback_mode" ]] || return 0
	normalize_fcp_window_frame
	if set_fcp_viewer_option_via_view_options_ax "$playback_mode" media-playback; then
		return 0
	fi
	dismiss_fcp_menus
	if fcp_viewer_menu_setting set media-playback "$playback_mode"; then
		return 0
	fi
	dismiss_fcp_menus
	printf 'FCP Viewer media playback View Options AX popover did not confirm "%s"; refusing coordinate fallback.\n' "$playback_mode" >&2
	return 1
}

set_fcp_proxy_only() {
	set_fcp_viewer_media_playback "Proxy Only" >/dev/null \
		|| fail "could not set FCP Viewer media playback mode to Proxy Only"
	printf 'FCP Viewer media playback mode set to: Proxy Only\n'
}

set_fcp_viewer_channel() {
	local channel_name="$1"
	[[ -n "$channel_name" ]] || return 0
	normalize_fcp_window_frame
	if set_fcp_viewer_option_via_view_options_ax "$channel_name" channel; then
		return 0
	fi
	dismiss_fcp_menus
	if fcp_viewer_menu_setting set channel "$channel_name"; then
		return 0
	fi
	dismiss_fcp_menus
	printf 'FCP Viewer channel View Options AX popover did not confirm "%s"; refusing coordinate fallback.\n' "$channel_name" >&2
	return 1
}

set_fcp_green_channel() {
	set_fcp_viewer_channel_green >/dev/null \
		|| fail "could not set FCP Viewer channel to Green"
	printf 'FCP Viewer channel set to: Green\n'
}

debug_overlay_visible_now() {
	local label="${1:-debug overlay precheck}"
	local provided_viewer_roi="${2:-}"
	local viewer_roi
	local screenshot_path
	if [[ -n "$provided_viewer_roi" ]]; then
		viewer_roi="$provided_viewer_roi"
		printf 'Debug Overlay probe: using prepared Viewer ROI (%s): %s\n' "$label" "$viewer_roi"
	else
		printf 'Debug Overlay probe: current Viewer ROI (%s)\n' "$label"
		if ! viewer_roi="$(current_fcp_viewer_roi 2>/dev/null)"; then
			printf 'Debug Overlay probe: could not read current Viewer ROI (%s)\n' "$label" >&2
			return 1
		fi
	fi
	mkdir -p "$ARTIFACT_ROOT"
	screenshot_path="${ARTIFACT_ROOT}/fcp_debug_overlay_probe_$(date +%Y%m%d_%H%M%S).png"
	printf 'Debug Overlay probe: screenshot (%s)\n' "$label"
	/usr/sbin/screencapture -x "$screenshot_path" || return 1
	if ! viewer_roi="$(clamp_viewer_roi_to_screenshot_bounds "$viewer_roi" "$screenshot_path")"; then
		return 1
	fi
	printf 'Debug Overlay probe: image assertion (%s)\n' "$label"
	assert_debug_overlay_visible_in_screenshot "$screenshot_path" "$viewer_roi" "$label"
}

set_fcp_debug_overlay_via_local_ax() {
	local desired_state="$1"
	/usr/bin/osascript - "$desired_state" > /dev/null <<'APPLESCRIPT' &
on run argv
	set desiredStateText to item 1 of argv
	set desiredState to false
	if desiredStateText is "true" then set desiredState to true
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			keystroke "4" using {command down}
				delay 0.25
				my ensureInspectorVisible()
				set frontWindow to my frontFinalCutProWindow()
				set inspectorRoot to my inspectorPanelRoot(frontWindow)
				set overlayCheckbox to my firstDebugOverlayCheckbox(inspectorRoot, 18)
				if overlayCheckbox is missing value then set overlayCheckbox to my checkboxNearInspectorText(inspectorRoot, "Debug Overlay", 18)
				if overlayCheckbox is missing value then set overlayCheckbox to my debugOverlayCheckboxAfterScrolling(inspectorRoot)
				if overlayCheckbox is missing value then error "Debug Overlay checkbox not found by local AX label/row search"
				if my checkboxIsOn(overlayCheckbox) is not desiredState then
					my pressElement(overlayCheckbox)
					delay 0.25
				end if
				if my checkboxIsOn(overlayCheckbox) is not desiredState then error "Debug Overlay checkbox did not reach requested state"
		end tell
	end tell
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on ensureInspectorVisible()
	tell application "System Events"
		tell process "Final Cut Pro"
			try
				set inspectorToggle to first checkbox of toolbar 1 of my frontFinalCutProWindow() whose description is "Show or hide the Inspector"
				if not my checkboxIsOn(inspectorToggle) then
					my pressElement(inspectorToggle)
					delay 0.25
				end if
			end try
		end tell
	end tell
end ensureInspectorVisible

on inspectorPanelRoot(frontWindow)
	tell application "System Events"
		try
			set contentSplit to splitter group 1 of group 2 of splitter group 1 of group 1 of splitter group 1 of frontWindow
			repeat with candidateRoot in groups of contentSplit
				if my elementIsRightInspectorCandidate(candidateRoot, frontWindow) then return candidateRoot
			end repeat
		end try
	end tell
	error "Could not resolve the Final Cut Pro Video Inspector panel."
end inspectorPanelRoot

on elementIsRightInspectorCandidate(elementRef, frontWindow)
	tell application "System Events"
		try
			set rootPosition to position of frontWindow
			set rootSize to size of frontWindow
			set elementPosition to position of elementRef
			set elementSize to size of elementRef
			set rightPanelFloor to (item 1 of rootPosition) + ((item 1 of rootSize) * 0.55)
			if (item 1 of elementPosition) >= rightPanelFloor and (item 1 of elementSize) >= 240 and (item 2 of elementSize) >= 300 then return true
		end try
	end tell
	return false
end elementIsRightInspectorCandidate

on elementHasMinimumSize(elementRef, minWidth, minHeight)
	tell application "System Events"
		try
			set sizeValues to size of elementRef
			if (item 1 of sizeValues) >= minWidth and (item 2 of sizeValues) >= minHeight then return true
		end try
	end tell
	return false
end elementHasMinimumSize

on firstDebugOverlayCheckbox(rootElement, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then
				if my elementContainsText(rootElement, "Debug Overlay") then return rootElement
			end if
		end try
		try
			if my elementContainsText(rootElement, "Debug Overlay") then
				set rowCheckbox to my firstCheckbox(rootElement, 4)
				if rowCheckbox is not missing value then return rowCheckbox
			end if
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstDebugOverlayCheckbox(childElement, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstDebugOverlayCheckbox

on firstCheckbox(rootElement, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then return rootElement
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstCheckbox(childElement, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstCheckbox

on checkboxNearInspectorText(rootElement, labelText, remainingDepth)
	set labelElement to my firstElementWithExactText(rootElement, labelText, remainingDepth)
	if labelElement is missing value then return missing value
	tell application "System Events"
		try
			set labelPosition to position of labelElement
			set labelX to item 1 of labelPosition
			set labelY to item 2 of labelPosition
		on error
			return missing value
		end try
	end tell
	set checkboxPair to my nearestCheckboxNearY(rootElement, labelX, labelY, remainingDepth)
	return item 1 of checkboxPair
end checkboxNearInspectorText

on debugOverlayCheckboxAfterScrolling(inspectorRoot)
	repeat with attemptIndex from 1 to 8
		my scrollInspectorDown(inspectorRoot)
		delay 0.12
		set overlayCheckbox to my firstDebugOverlayCheckbox(inspectorRoot, 18)
		if overlayCheckbox is not missing value then return overlayCheckbox
		set overlayCheckbox to my checkboxNearInspectorText(inspectorRoot, "Debug Overlay", 18)
		if overlayCheckbox is not missing value then return overlayCheckbox
	end repeat
	return missing value
end debugOverlayCheckboxAfterScrolling

on scrollInspectorDown(rootElement)
	set scroller to my firstInspectorScrollArea(rootElement, 12)
	if scroller is missing value then return
	tell application "System Events"
		try
			perform action "AXScrollDown" of scroller
		end try
		try
			repeat with barElement in scroll bars of scroller
				set value of barElement to 1.0
			end repeat
			return
		end try
	end tell
end scrollInspectorDown

on firstInspectorScrollArea(rootElement, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXScrollArea" then
				try
					if (description of rootElement as text) is "inspector" then return rootElement
				end try
			end if
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstInspectorScrollArea(childElement, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstInspectorScrollArea

on firstElementWithExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	if my elementTextEquals(rootElement, requiredText) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstElementWithExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementWithExactText

on nearestCheckboxNearY(rootElement, labelX, labelY, remainingDepth)
	set bestCheckbox to missing value
	set bestScore to 999999
	if remainingDepth < 0 then return {bestCheckbox, bestScore}
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then
				set elementPosition to position of rootElement
				set elementSize to size of rootElement
				set centerX to (item 1 of elementPosition) + ((item 1 of elementSize) / 2)
				set centerY to (item 2 of elementPosition) + ((item 2 of elementSize) / 2)
				set deltaY to centerY - labelY
				if deltaY < 0 then set deltaY to -deltaY
				set deltaX to centerX - labelX
				if deltaX < 0 then set deltaX to -deltaX
				set candidateScore to (deltaY * 100) + deltaX
				if deltaY < 30 and centerX > labelX and candidateScore < bestScore then
					set bestCheckbox to rootElement
					set bestScore to candidateScore
				end if
			end if
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return {bestCheckbox, bestScore}
		end try
	end tell
	repeat with childElement in childElements
		set candidatePair to my nearestCheckboxNearY(childElement, labelX, labelY, remainingDepth - 1)
		if item 1 of candidatePair is not missing value and item 2 of candidatePair < bestScore then
			set bestCheckbox to item 1 of candidatePair
			set bestScore to item 2 of candidatePair
		end if
	end repeat
	return {bestCheckbox, bestScore}
end nearestCheckboxNearY

on pressElement(elementReference)
	tell application "System Events"
		try
			perform action "AXPress" of elementReference
			return
		end try
	end tell
	error "AXPress failed for target element"
end pressElement

on elementContainsText(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) contains requiredText then return true
		end ignoring
	end repeat
	return false
end elementContainsText

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals

on checkboxIsOn(elementReference)
	tell application "System Events"
		try
			set checkboxValue to value of elementReference
			if checkboxValue is 1 then return true
			if checkboxValue is "1" then return true
			if checkboxValue is true then return true
		end try
	end tell
	return false
end checkboxIsOn
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "Debug Overlay ${desired_state} local AX" 300 0
}

set_fcp_debug_overlay_on_via_local_ax() {
	set_fcp_debug_overlay_via_local_ax true
}

warm_debug_overlay_viewer_probe() {
	local viewer_roi="${1:-}"
	local label="${2:-Debug Overlay viewer warmup}"
	printf '%s: playing briefly to force Final Cut Pro Viewer render before overlay recheck.\n' "$label" >&2
	press_start_playback || return 1
	sleep 1.4
	press_stop_playback || true
	sleep 0.4
	debug_overlay_visible_now "$label" "$viewer_roi"
}

set_fcp_debug_overlay_on() {
	local viewer_roi="${1:-}"
	[[ -f "$FCP_HELPER" ]] || fail "missing FCP helper: ${FCP_HELPER}"
	if debug_overlay_visible_now "Debug Overlay precheck" "$viewer_roi"; then
		printf 'Tokyo Walking Stabilizer Debug Overlay already visible in Viewer.\n'
		return 0
	fi
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-debug-overlay.XXXXXX")"
	/usr/bin/osascript "$FCP_HELPER" set-debug-overlay on >"$output_file" 2>&1 &
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "Debug Overlay on" 120 0; then
		local result
		result="$(cat "$output_file")"
		rm -f "$output_file"
		if debug_overlay_visible_now "Debug Overlay after helper failure" "$viewer_roi"; then
			printf 'Tokyo Walking Stabilizer Debug Overlay is visible despite Inspector checkbox failure.\n'
			return 0
		fi
		printf 'Debug Overlay helper failed; retrying with local AX label/row checkbox search. Detail: %s\n' "$result" >&2
		if set_fcp_debug_overlay_on_via_local_ax && debug_overlay_visible_now "Debug Overlay after local AX retry" "$viewer_roi"; then
			printf 'Tokyo Walking Stabilizer Debug Overlay set to: on via local AX retry.\n'
			return 0
		fi
		if warm_debug_overlay_viewer_probe "$viewer_roi" "Debug Overlay after Viewer warmup"; then
			printf 'Tokyo Walking Stabilizer Debug Overlay visible after Viewer warmup.\n'
			return 0
		fi
		fail "could not set Tokyo Walking Stabilizer Debug Overlay on: ${result}"
	fi
	cat "$output_file"
	rm -f "$output_file"
	if ! debug_overlay_visible_now "Debug Overlay after enabling" "$viewer_roi"; then
		if warm_debug_overlay_viewer_probe "$viewer_roi" "Debug Overlay after enabling Viewer warmup"; then
			printf 'Tokyo Walking Stabilizer Debug Overlay visible after Viewer warmup.\n'
			return 0
		fi
		fail "Tokyo Walking Stabilizer Debug Overlay was enabled in Inspector but is not visible in the Viewer"
	fi
	printf 'Tokyo Walking Stabilizer Debug Overlay set to: on\n'
}

force_fcp_debug_overlay_render_pulse() {
	local viewer_roi="${1:-}"
	printf 'Pulsing Debug Overlay off/on to force current FxPlug render diagnostics.\n'
	set_fcp_debug_overlay_via_local_ax false \
		|| fail "could not pulse Debug Overlay off before recording"
	set_fcp_debug_overlay_via_local_ax true \
		|| fail "could not pulse Debug Overlay on before recording"
	if ! debug_overlay_visible_now "Debug Overlay after render pulse" "$viewer_roi"; then
		fail "Debug Overlay render pulse completed but overlay is not visible in the Viewer"
	fi
}

force_fcp_remove_black_edges_render_pulse() {
	local desired_state="$1"
	local opposite_state="true"
	if [[ "$desired_state" == "true" ]]; then
		opposite_state="false"
	fi
	printf 'Pulsing Remove Black Edges %s/%s to force current FxPlug render diagnostics.\n' "$opposite_state" "$desired_state"
	set_fcp_remove_black_edges_via_local_ax "$opposite_state" \
		|| fail "could not pulse Remove Black Edges to ${opposite_state} before recording"
	sleep 0.3
	set_fcp_remove_black_edges_via_local_ax "$desired_state" \
		|| fail "could not restore Remove Black Edges to ${desired_state} before recording"
}

warm_fcp_proxy_only_viewer_render() {
	local timecode_entry="$1"
	printf 'Warming Final Cut Pro Viewer render by toggling Optimized/Original, then restoring Proxy Only before capture.\n'
	set_fcp_viewer_media_playback "Optimized/Original" >/dev/null
	sleep 1.0
	press_stop_playback
	seek_timecode "$timecode_entry"
	sleep 0.4
	set_fcp_viewer_media_playback "Proxy Only" >/dev/null
	sleep 1.0
	set_fcp_green_channel >/dev/null
	press_stop_playback
	seek_timecode "$timecode_entry"
	sleep 0.4
	printf 'Final Cut Pro Viewer media playback mode restored to: Proxy Only; channel restored to: Green\n'
}

focus_timeline() {
	/usr/bin/osascript >/dev/null <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		keystroke "2" using {command down}
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "focus timeline" 50 1
}

set_fcp_toolbar_checkbox() {
	local checkbox_description="$1"
	local desired_value="$2"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-toolbar-checkbox.XXXXXX")"
	/usr/bin/osascript - "$checkbox_description" "$desired_value" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set targetDescription to item 1 of argv
	set desiredValue to item 2 of argv as integer
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set targetWindow to my frontFinalCutProWindow()
			try
				try
					set toolbarItems to checkboxes of toolbar 1 of targetWindow
				on error errText
					error "Could not read Final Cut Pro toolbar checkboxes from the standard window: " & errText
					end try
					repeat with toolbarItem in toolbarItems
						set toolbarItemRef to contents of toolbarItem
						set itemDescription to ""
						try
							set itemDescription to description of toolbarItemRef as text
						end try
						if itemDescription contains targetDescription then
							try
								set currentValue to ((value of toolbarItemRef) as text) as integer
								if currentValue is not desiredValue then
									perform action "AXPress" of toolbarItemRef
									delay 0.3
								end if
								set updatedValue to ((value of toolbarItemRef) as text) as integer
								if updatedValue is not desiredValue then error "checkbox value did not change"
								return "set"
							on error errText
							error "Found toolbar checkbox " & targetDescription & " but could not set it: " & errText
						end try
					end if
				end repeat
			on error errText
				error errText
			end try
		end tell
	end tell
	error "Could not find Final Cut Pro toolbar checkbox: " & targetDescription
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow
APPLESCRIPT
	local osascript_pid=$!
	if wait_for_ui_osascript "$osascript_pid" "toolbar checkbox ${checkbox_description}" 80 0; then
		cat "$output_file"
		rm -f "$output_file"
		return 0
	fi
	cat "$output_file" >&2
	rm -f "$output_file"
	return 1
}

set_fcp_window_checkbox() {
	local checkbox_description="$1"
	local desired_value="$2"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-window-checkbox.XXXXXX")"
	/usr/bin/osascript - "$checkbox_description" "$desired_value" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set targetDescription to item 1 of argv
	set desiredValue to item 2 of argv as integer
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set targetCheckbox to my firstCheckboxContainingDescription(frontWindow, targetDescription, 16)
			if targetCheckbox is missing value then error "Could not find Final Cut Pro window checkbox: " & targetDescription
			try
				if (value of targetCheckbox as integer) is not desiredValue then
					perform action "AXPress" of targetCheckbox
					delay 0.3
				end if
				if (value of targetCheckbox as integer) is not desiredValue then error "checkbox value did not change"
				return "set"
			on error errText
				error "Found window checkbox " & targetDescription & " but could not set it: " & errText
			end try
		end tell
	end tell
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstCheckboxContainingDescription(rootElement, targetDescription, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then
				try
					if (description of rootElement as text) contains targetDescription then return rootElement
				end try
			end if
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstCheckboxContainingDescription(childElement, targetDescription, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstCheckboxContainingDescription
APPLESCRIPT
	local osascript_pid=$!
	if wait_for_ui_osascript "$osascript_pid" "window checkbox ${checkbox_description}" 80 0; then
		cat "$output_file"
		rm -f "$output_file"
		return 0
	fi
	cat "$output_file" >&2
	rm -f "$output_file"
	return 1
}

normalize_fcp_layout() {
	printf 'Normalizing FCP layout for screen-capture E2E...\n'
	printf 'FCP layout normalize: window frame\n'
	normalize_fcp_window_frame
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$blocker_result"
	printf 'Known screen-blocking dialog state before layout normalize: %s\n' "$blocker_result"
	printf 'FCP layout normalize: hide Browser\n'
	if ! set_fcp_toolbar_checkbox "Show or hide the Browser" 0 >/dev/null; then
		printf 'FCP layout normalize: Browser toolbar checkbox was not set; continuing because Viewer ROI/effect preflights remain authoritative.\n' >&2
	fi
	printf 'FCP layout normalize: hide Inspector\n'
	if ! set_fcp_toolbar_checkbox "Show or hide the Inspector" 0 >/dev/null; then
		printf 'FCP layout normalize: Inspector toolbar checkbox was not set; continuing because Viewer ROI/effect preflights remain authoritative.\n' >&2
	fi
	printf 'FCP layout normalize: viewer zoom fit\n'
	set_viewer_zoom_to_fit
	printf 'FCP layout normalize: focus timeline\n'
	focus_timeline
}

select_playhead_clip() {
	"${ROOT_DIR}/scripts/fcp_ui_test.sh" select-playhead-clip
}

ensure_selected_timeline_clip_enabled() {
	local result
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-clip-enabled.XXXXXX")"
	/usr/bin/osascript >"$output_file" 2>&1 <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		tell menu "Clip" of menu bar 1
			if exists menu item "Enable" then
				if enabled of menu item "Enable" then
					click menu item "Enable"
					delay 0.3
					return "enabled"
				end if
			end if
			if exists menu item "Disable" then
				if enabled of menu item "Disable" then return "already-enabled"
			end if
		end tell
	end tell
end tell
return "unknown"
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "selected clip enabled state" 80 0; then
		result="$(cat "$output_file")"
		rm -f "$output_file"
		fail "could not inspect selected Final Cut Pro clip enabled state: ${result}"
	fi
	result="$(cat "$output_file")"
	rm -f "$output_file"
	case "$result" in
		enabled)
			printf 'Enabled selected Final Cut Pro timeline clip through Clip > Enable.\n'
			;;
		already-enabled)
			printf 'Selected Final Cut Pro timeline clip is enabled.\n'
			;;
		*)
			printf 'Could not confirm selected Final Cut Pro timeline clip enabled state through Clip menu: %s. Continuing with Viewer ROI/effect preflight.\n' "$result" >&2
			;;
	esac
}

assert_inspector_contains_case_effect() {
	local expected_effect="$1"
	local remove_black_edges="$2"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-inspector-effect.XXXXXX")"
	/usr/bin/osascript - "$expected_effect" "$remove_black_edges" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set expectedEffect to item 1 of argv
	set requireRemoveBlackEdges to item 2 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			my ensureInspectorVisible()
			set frontWindow to my frontFinalCutProWindow()
			set inspectorRoot to my inspectorPanelRoot(frontWindow)
			if my firstElementContainingText(inspectorRoot, expectedEffect, 0, 14) is missing value then error "Expected effect is not visible in the Final Cut Pro Inspector: " & expectedEffect
			if requireRemoveBlackEdges is "true" and my firstElementContainingText(inspectorRoot, "Remove Black Edges", 0, 14) is missing value then error "Remove Black Edges control is not visible in the Final Cut Pro Inspector."
		end tell
	end tell
	return "inspector-ok"
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on ensureInspectorVisible()
	tell application "System Events"
		tell process "Final Cut Pro"
			try
				set inspectorToggle to first checkbox of toolbar 1 of my frontFinalCutProWindow() whose description is "Show or hide the Inspector"
				if not my checkboxIsOn(inspectorToggle) then
					my pressElement(inspectorToggle)
					delay 0.25
				end if
			end try
		end tell
	end tell
end ensureInspectorVisible

on pressElement(elementReference)
	tell application "System Events"
		try
			perform action "AXPress" of elementReference
			return
		end try
	end tell
	error "AXPress failed for target element"
end pressElement

on checkboxIsOn(elementReference)
	tell application "System Events"
		try
			set checkboxValue to value of elementReference
			if checkboxValue is 1 then return true
			if checkboxValue is "1" then return true
			if checkboxValue is true then return true
		end try
	end tell
	return false
end checkboxIsOn

on inspectorPanelRoot(frontWindow)
	tell application "System Events"
		try
			set contentSplit to splitter group 1 of group 2 of splitter group 1 of group 1 of splitter group 1 of frontWindow
			repeat with candidateRoot in groups of contentSplit
				if my elementIsRightInspectorCandidate(candidateRoot, frontWindow) then return candidateRoot
			end repeat
		end try
	end tell
	error "Could not resolve the Final Cut Pro Video Inspector panel."
end inspectorPanelRoot

on elementIsRightInspectorCandidate(elementRef, frontWindow)
	tell application "System Events"
		try
			set rootPosition to position of frontWindow
			set rootSize to size of frontWindow
			set elementPosition to position of elementRef
			set elementSize to size of elementRef
			set rightPanelFloor to (item 1 of rootPosition) + ((item 1 of rootSize) * 0.55)
			if (item 1 of elementPosition) >= rightPanelFloor and (item 1 of elementSize) >= 240 and (item 2 of elementSize) >= 300 then return true
		end try
	end tell
	return false
end elementIsRightInspectorCandidate

on elementHasMinimumSize(elementRef, minWidth, minHeight)
	tell application "System Events"
		try
			set sizeValues to size of elementRef
			if (item 1 of sizeValues) >= minWidth and (item 2 of sizeValues) >= minHeight then return true
		end try
	end tell
	return false
end elementHasMinimumSize

on firstElementContainingText(elementRef, targetText, currentDepth, maxDepth)
	if currentDepth > maxDepth then return missing value
	tell application "System Events"
		try
			set elementName to name of elementRef as text
			if elementName contains targetText then return elementRef
		end try
		try
			set elementDescription to description of elementRef as text
			if elementDescription contains targetText then return elementRef
		end try
		try
			set elementValue to value of elementRef as text
			if elementValue contains targetText then return elementRef
		end try
		try
			set children to UI elements of elementRef
		on error
			return missing value
		end try
	end tell
	repeat with childElement in children
		set foundElement to my firstElementContainingText(childElement, targetText, currentDepth + 1, maxDepth)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementContainingText
APPLESCRIPT
	local osascript_pid=$!
	if wait_for_ui_osascript "$osascript_pid" "Inspector effect text" 300 0; then
		cat "$output_file"
		rm -f "$output_file"
		return 0
	fi
	cat "$output_file" >&2
	rm -f "$output_file"
	return 1
}

set_fcp_remove_black_edges_via_local_ax() {
	local desired_state="$1"
	/usr/bin/osascript - "$desired_state" > /dev/null <<'APPLESCRIPT' &
on run argv
	set desiredStateText to item 1 of argv
	set desiredState to false
	if desiredStateText is "true" then set desiredState to true
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			my ensureInspectorVisible()
		set frontWindow to my frontFinalCutProWindow()
		set inspectorRoot to my inspectorPanelRoot(frontWindow)
		set cropCheckbox to my firstCheckboxContainingText(inspectorRoot, "Remove Black Edges", 18)
		if cropCheckbox is missing value then set cropCheckbox to my checkboxNearInspectorText(inspectorRoot, "Remove Black Edges", 18)
		if cropCheckbox is missing value then error "Remove Black Edges checkbox not found by local AX label/row search"
		if my checkboxIsOn(cropCheckbox) is not desiredState then
			my pressElement(cropCheckbox)
			delay 0.25
		end if
		if my checkboxIsOn(cropCheckbox) is not desiredState then error "Remove Black Edges checkbox did not reach requested state"
	end tell
end tell
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on ensureInspectorVisible()
	tell application "System Events"
		tell process "Final Cut Pro"
			try
				set inspectorToggle to first checkbox of toolbar 1 of my frontFinalCutProWindow() whose description is "Show or hide the Inspector"
				if not my checkboxIsOn(inspectorToggle) then
					my pressElement(inspectorToggle)
					delay 0.25
				end if
			end try
		end tell
	end tell
end ensureInspectorVisible

on inspectorPanelRoot(frontWindow)
	tell application "System Events"
		try
			set contentSplit to splitter group 1 of group 2 of splitter group 1 of group 1 of splitter group 1 of frontWindow
			repeat with candidateRoot in groups of contentSplit
				if my elementIsRightInspectorCandidate(candidateRoot, frontWindow) then return candidateRoot
			end repeat
		end try
	end tell
	error "Could not resolve the Final Cut Pro Video Inspector panel."
end inspectorPanelRoot

on elementIsRightInspectorCandidate(elementRef, frontWindow)
	tell application "System Events"
		try
			set rootPosition to position of frontWindow
			set rootSize to size of frontWindow
			set elementPosition to position of elementRef
			set elementSize to size of elementRef
			set rightPanelFloor to (item 1 of rootPosition) + ((item 1 of rootSize) * 0.55)
			if (item 1 of elementPosition) >= rightPanelFloor and (item 1 of elementSize) >= 240 and (item 2 of elementSize) >= 300 then return true
		end try
	end tell
	return false
end elementIsRightInspectorCandidate

on elementHasMinimumSize(elementRef, minWidth, minHeight)
	tell application "System Events"
		try
			set sizeValues to size of elementRef
			if (item 1 of sizeValues) >= minWidth and (item 2 of sizeValues) >= minHeight then return true
		end try
	end tell
	return false
end elementHasMinimumSize

on firstCheckboxContainingText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then
				if my elementContainsText(rootElement, requiredText) then return rootElement
			end if
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstCheckboxContainingText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstCheckboxContainingText

on checkboxNearInspectorText(rootElement, labelText, remainingDepth)
	set labelElement to my firstElementWithExactText(rootElement, labelText, remainingDepth)
	if labelElement is missing value then return missing value
	tell application "System Events"
		try
			set labelPosition to position of labelElement
			set labelX to item 1 of labelPosition
			set labelY to item 2 of labelPosition
		on error
			return missing value
		end try
	end tell
	set checkboxPair to my nearestCheckboxNearY(rootElement, labelX, labelY, remainingDepth)
	return item 1 of checkboxPair
end checkboxNearInspectorText

on firstElementWithExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	if my elementTextEquals(rootElement, requiredText) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstElementWithExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementWithExactText

on nearestCheckboxNearY(rootElement, labelX, labelY, remainingDepth)
	set bestCheckbox to missing value
	set bestScore to 999999
	if remainingDepth < 0 then return {bestCheckbox, bestScore}
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXCheckBox" then
				set elementPosition to position of rootElement
				set elementSize to size of rootElement
				set centerX to (item 1 of elementPosition) + ((item 1 of elementSize) / 2)
				set centerY to (item 2 of elementPosition) + ((item 2 of elementSize) / 2)
				set deltaY to centerY - labelY
				if deltaY < 0 then set deltaY to -deltaY
				set deltaX to centerX - labelX
				if deltaX < 0 then set deltaX to -deltaX
				set candidateScore to (deltaY * 100) + deltaX
				if deltaY < 30 and centerX > labelX and candidateScore < bestScore then
					set bestCheckbox to rootElement
					set bestScore to candidateScore
				end if
			end if
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return {bestCheckbox, bestScore}
		end try
	end tell
	repeat with childElement in childElements
		set candidatePair to my nearestCheckboxNearY(childElement, labelX, labelY, remainingDepth - 1)
		if item 1 of candidatePair is not missing value and item 2 of candidatePair < bestScore then
			set bestCheckbox to item 1 of candidatePair
			set bestScore to item 2 of candidatePair
		end if
	end repeat
	return {bestCheckbox, bestScore}
end nearestCheckboxNearY

on pressElement(elementReference)
	tell application "System Events"
		try
			perform action "AXPress" of elementReference
			return
		end try
	end tell
	error "AXPress failed for target element"
end pressElement

on elementContainsText(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) contains requiredText then return true
		end ignoring
	end repeat
	return false
end elementContainsText

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals

on checkboxIsOn(elementReference)
	tell application "System Events"
		try
			set checkboxValue to value of elementReference
			if checkboxValue is 1 then return true
			if checkboxValue is "1" then return true
			if checkboxValue is true then return true
		end try
	end tell
	return false
end checkboxIsOn
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "Remove Black Edges ${desired_state}" 300 0
}

assert_inspector_contains_case_effect_if_readable() {
	local expected_effect="$1"
	local remove_black_edges="$2"
	local inspector_output
	if inspector_output="$(assert_inspector_contains_case_effect "$expected_effect" "$remove_black_edges" 2>&1)"; then
		printf '%s\n' "$inspector_output"
		printf 'Inspector shows expected Stabilizer controls.\n'
	else
		printf 'Inspector effect text was not readable in the current FCP layout; project metadata assertion already verified the effect/crop contract. Detail: %s\n' "$inspector_output"
	fi
}

assert_debug_overlay_visible_in_screenshot() {
	local screenshot_path="$1"
	local viewer_roi="$2"
	local label="$3"
	[[ -n "$screenshot_path" ]] || fail "debug overlay screenshot path is required"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for Debug Overlay assertion"
	python3 - "$screenshot_path" "$viewer_roi" "$label" <<'PY'
from pathlib import Path
import math
import sys

import cv2
import numpy as np

image_path = Path(sys.argv[1])
roi_parts = [int(part) for part in sys.argv[2].split(",")]
label = sys.argv[3]
if len(roi_parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
x, y, w, h = roi_parts
image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
if image is None:
    raise SystemExit(f"{label}: could not read Debug Overlay screenshot: {image_path}")
height, width = image.shape[:2]
if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
    raise SystemExit(f"{label}: viewer ROI {x},{y},{w},{h} is outside screenshot bounds {width}x{height}")
viewer = image[y:y + h, x:x + w]
gray = cv2.cvtColor(viewer, cv2.COLOR_BGR2GRAY)

bits = {
    "A": [0x2, 0x5, 0x7, 0x5, 0x5],
    "B": [0x6, 0x5, 0x6, 0x5, 0x6],
    "C": [0x7, 0x4, 0x4, 0x4, 0x7],
    "D": [0x6, 0x5, 0x5, 0x5, 0x6],
    "E": [0x7, 0x4, 0x6, 0x4, 0x7],
    "F": [0x7, 0x4, 0x6, 0x4, 0x4],
    "G": [0x7, 0x4, 0x5, 0x5, 0x7],
    "H": [0x5, 0x5, 0x7, 0x5, 0x5],
    "I": [0x7, 0x2, 0x2, 0x2, 0x7],
    "J": [0x7, 0x1, 0x1, 0x1, 0x6],
    "K": [0x5, 0x5, 0x6, 0x5, 0x5],
    "L": [0x4, 0x4, 0x4, 0x4, 0x7],
    "M": [0x5, 0x7, 0x7, 0x5, 0x5],
    "N": [0x5, 0x7, 0x7, 0x7, 0x5],
    "O": [0x7, 0x5, 0x5, 0x5, 0x7],
    "P": [0x6, 0x5, 0x6, 0x4, 0x4],
    "Q": [0x7, 0x5, 0x5, 0x7, 0x1],
    "R": [0x6, 0x5, 0x6, 0x5, 0x5],
    "S": [0x7, 0x4, 0x7, 0x1, 0x7],
    "T": [0x7, 0x2, 0x2, 0x2, 0x2],
    "U": [0x5, 0x5, 0x5, 0x5, 0x7],
    "V": [0x5, 0x5, 0x5, 0x5, 0x2],
    "W": [0x5, 0x5, 0x7, 0x7, 0x5],
    "X": [0x5, 0x5, 0x2, 0x5, 0x5],
    "Y": [0x5, 0x5, 0x2, 0x2, 0x2],
    "Z": [0x7, 0x1, 0x2, 0x4, 0x7],
    " ": [0x0, 0x0, 0x0, 0x0, 0x0],
}
labels = [
    "X OFFSET",
    "Y OFFSET",
    "ROLL",
    "CROP",
    "TURN",
    "MACRO JITTER",
    "MICRO JITTER",
    "FAR WARP",
    "SMOOTHING",
    "TRACKING",
    "WALKING",
    "SHARPNESS",
    "RESIDUAL",
    "SEARCH HEADROOM",
    "TURN CONFIDENCE",
    "MACRO CONFIDENCE",
    "MICRO CONFIDENCE",
    "WARP CONFIDENCE",
    "RUNTIME",
]

row_count = float(len(labels))
overlay_scale = max(float(h) * 0.5 / (row_count * 13.0), 0.25)
panel_y = 16.0 * overlay_scale
label_width = 160.0 * overlay_scale
label_gap = 2.0 * overlay_scale
bar_width = 180.0 * overlay_scale
row_height = 13.0 * overlay_scale
panel_width = label_width + label_gap + bar_width
panel_height = row_count * row_height
if panel_y >= h:
    raise SystemExit(f"{label}: predicted Debug Overlay panel origin is outside viewer ROI {w}x{h}")

def fill(target, x0, y0, x1, y1):
    ix0 = max(0, int(math.floor(x0)))
    iy0 = max(0, int(math.floor(y0)))
    ix1 = min(w, int(math.ceil(x1)))
    iy1 = min(h, int(math.ceil(y1)))
    if ix1 > ix0 and iy1 > iy0:
        target[iy0:iy1, ix0:ix1] = 1

def overlay_metrics(candidate_panel_x):
    if candidate_panel_x >= w:
        return None
    mask = np.zeros((h, w), dtype=np.uint8)
    area = np.zeros((h, w), dtype=np.uint8)
    for row, text in enumerate(labels):
        row_top = panel_y + (float(row) * row_height)
        fill(area, candidate_panel_x, row_top, candidate_panel_x + label_width, row_top + row_height)
        text_scale = 2.0 * overlay_scale
        glyph_advance = 4.0 * text_scale
        text_origin_x = candidate_panel_x + 6.0
        text_origin_y = row_top + (1.5 * overlay_scale)
        for index, char in enumerate(text[:12]):
            row_bits = bits.get(char, bits[" "])
            for glyph_y, row_mask in enumerate(row_bits):
                for glyph_x in range(3):
                    if ((row_mask >> (2 - glyph_x)) & 0x1) == 0:
                        continue
                    px0 = text_origin_x + (float(index) * glyph_advance) + (float(glyph_x) * text_scale)
                    py0 = text_origin_y + (float(glyph_y) * text_scale)
                    fill(mask, px0, py0, px0 + text_scale, py0 + text_scale)
    mask_count = int(np.count_nonzero(mask))
    if mask_count < 80:
        return None
    kernel_size = max(3, int(round(overlay_scale)))
    if kernel_size % 2 == 0:
        kernel_size += 1
    kernel = np.ones((kernel_size, kernel_size), dtype=np.uint8)
    label_mask = cv2.dilate(mask, kernel)
    background_kernel = np.ones((max(5, kernel_size + 2), max(5, kernel_size + 2)), dtype=np.uint8)
    background_mask = (area > 0) & (cv2.dilate(mask, background_kernel) == 0)
    label_values = gray[label_mask > 0]
    background_values = gray[background_mask]
    if label_values.size < 80 or background_values.size < 80:
        return None
    label_p95 = float(np.percentile(label_values.astype(np.float32), 95))
    background_median = float(np.percentile(background_values.astype(np.float32), 50))
    contrast = label_p95 - background_median
    bright_threshold = max(78.0, background_median + 32.0)
    bright_ratio = float(np.count_nonzero(label_values >= bright_threshold)) / float(max(1, label_values.size))
    panel_x0 = max(0, int(math.floor(candidate_panel_x)))
    panel_y0 = max(0, int(math.floor(panel_y)))
    panel_x1 = min(w, int(math.ceil(candidate_panel_x + panel_width)))
    panel_y1 = min(h, int(math.ceil(panel_y + panel_height)))
    panel = gray[panel_y0:panel_y1, panel_x0:panel_x1]
    panel_dark_ratio = float(np.count_nonzero(panel < 80)) / float(max(1, panel.size))
    score = contrast + (bright_ratio * 1000.0) + (panel_dark_ratio * 15.0)
    return {
        "panel_x": candidate_panel_x,
        "label_p95": label_p95,
        "background_median": background_median,
        "contrast": contrast,
        "bright_ratio": bright_ratio,
        "panel_dark_ratio": panel_dark_ratio,
        "score": score,
    }

max_scan_x = max(16.0 * overlay_scale, min(float(w) * 0.45, float(w) - panel_width))
step = max(8.0, 12.0 * overlay_scale)
candidate_xs = [16.0 * overlay_scale]
candidate = 0.0
while candidate <= max_scan_x:
    candidate_xs.append(candidate)
    candidate += step

metrics = [result for result in (overlay_metrics(candidate_x) for candidate_x in candidate_xs) if result is not None]
if not metrics:
    raise SystemExit(f"{label}: could not sample enough Debug Overlay label/background pixels for viewer ROI {w}x{h}")
best = max(metrics, key=lambda item: item["score"])
label_p95 = best["label_p95"]
background_median = best["background_median"]
contrast = best["contrast"]
bright_ratio = best["bright_ratio"]
panel_dark_ratio = best["panel_dark_ratio"]
panel_x = best["panel_x"]

if label_p95 < 85.0 or contrast < 25.0 or bright_ratio < 0.025:
    raise SystemExit(
        f"{label}: Debug Overlay bars/labels are not visibly present in viewer ROI: "
        f"labelP95={label_p95:.2f}, backgroundMedian={background_median:.2f}, "
        f"contrast={contrast:.2f}, brightRatio={bright_ratio:.3f}, "
        f"panelDarkRatio={panel_dark_ratio:.3f}, screenshot={image_path}"
    )

print(
    f"{label}: Debug Overlay visible: labelP95={label_p95:.2f}, "
    f"backgroundMedian={background_median:.2f}, contrast={contrast:.2f}, "
    f"brightRatio={bright_ratio:.3f}, panelDarkRatio={panel_dark_ratio:.3f}, "
    f"panelX={panel_x:.1f}, screenshot={image_path}"
)
PY
}

assert_viewer_roi_recordable() {
	local viewer_roi="$1"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for FCP prepare assertion"
	local screenshot_path="${ARTIFACT_ROOT}/fcp_prepare_viewer_$(date +%Y%m%d_%H%M%S).png"
	mkdir -p "$ARTIFACT_ROOT"
	/usr/sbin/screencapture -x "$screenshot_path"
	if python3 - "$screenshot_path" "$viewer_roi" <<'PY'
from pathlib import Path
import sys

import cv2
import numpy as np

image_path = Path(sys.argv[1])
roi_parts = [int(part) for part in sys.argv[2].split(",")]
if len(roi_parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
x, y, w, h = roi_parts
image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
if image is None:
    raise SystemExit(f"could not read prepare screenshot: {image_path}")
height, width = image.shape[:2]
if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
    raise SystemExit(f"viewer ROI {x},{y},{w},{h} is outside screenshot bounds {width}x{height}")
viewer = image[y:y + h, x:x + w]
gray = cv2.cvtColor(viewer, cv2.COLOR_BGR2GRAY)
hsv = cv2.cvtColor(viewer, cv2.COLOR_BGR2HSV)
mean = float(gray.mean())
std = float(gray.std())
edge = int(np.count_nonzero(gray < 4))
edge_ratio = edge / float(max(1, gray.size))
colorful_ratio = float(np.count_nonzero(hsv[:, :, 1] > 12)) / float(max(1, gray.size))
b, g, r = cv2.split(viewer)
red_dominance = r.astype(np.int16) - np.maximum(g, b).astype(np.int16)
placeholder_mask = (red_dominance > 18) & (r > 35) & (g < 75) & (b < 75)
placeholder_ratio = float(np.count_nonzero(placeholder_mask)) / float(max(1, gray.size))
center_placeholder_mask = placeholder_mask[h // 4 : (3 * h) // 4, w // 4 : (3 * w) // 4]
center_placeholder_ratio = float(np.count_nonzero(center_placeholder_mask)) / float(max(1, center_placeholder_mask.size))
if mean < 6.0:
    raise SystemExit(f"viewer ROI appears black or unloaded: mean={mean:.2f}, std={std:.2f}, screenshot={image_path}")
if std < 3.0:
    raise SystemExit(f"viewer ROI lacks image detail: mean={mean:.2f}, std={std:.2f}, screenshot={image_path}")
if edge_ratio > 0.80:
    raise SystemExit(f"viewer ROI is mostly black: blackRatio={edge_ratio:.3f}, screenshot={image_path}")
if mean < 80.0 and placeholder_ratio > 0.55 and center_placeholder_ratio > 0.40:
    raise SystemExit(
        "viewer ROI is showing Final Cut Pro Missing Proxy/source-media placeholder: "
        f"placeholderRatio={placeholder_ratio:.3f}, centerPlaceholderRatio={center_placeholder_ratio:.3f}, "
        f"mean={mean:.2f}, std={std:.2f}, screenshot={image_path}"
    )
if colorful_ratio > 0.35:
    raise SystemExit(
        "viewer ROI is not using Final Cut Pro Viewer Green channel: "
        f"colorRatio={colorful_ratio:.3f}, mean={mean:.2f}, std={std:.2f}, screenshot={image_path}"
    )
print(
    f"Viewer ROI ready: mean={mean:.2f}, std={std:.2f}, "
    f"blackRatio={edge_ratio:.3f}, greenChannelColorRatio={colorful_ratio:.3f}, screenshot={image_path}"
)
PY
	then
		assert_debug_overlay_visible_in_screenshot "$screenshot_path" "$viewer_roi" "viewer ROI prepare"
	else
		return $?
	fi
}

assert_fcp_viewer_not_nothing_loaded() {
	local project_name="${1:-}"
	local helper_output=""
	if [[ -f "$FCP_HELPER" ]]; then
		if helper_output="$(/usr/bin/osascript "$FCP_HELPER" assert-viewer-loaded 2>&1)"; then
			printf 'FCP Viewer helper assertion passed: %s\n' "$helper_output"
			return 0
		fi
		if printf '%s\n' "$helper_output" | /usr/bin/grep -qi "Nothing Loaded"; then
			fail "Final Cut Pro Viewer is showing Nothing Loaded; refusing to record a static/unloaded E2E video"
		fi
		printf 'FCP Viewer helper assertion was inconclusive; falling back to bounded UI text snapshot: %s\n' "$(printf '%s' "$helper_output" | tr '\n' ' ' | cut -c 1-240)" >&2
	fi
	local snapshot
	local snapshot_file
	local error_file
	snapshot_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer_fcp_ui_snapshot.XXXXXX")"
	error_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer_fcp_ui_snapshot_error.XXXXXX")"
	/usr/bin/osascript - "$project_name" >"$snapshot_file" 2>"$error_file" <<'APPLESCRIPT' &
on run argv
	with timeout of 2 seconds
		tell application "Final Cut Pro" to activate
		tell application "System Events"
			tell process "Final Cut Pro"
				set frontmost to true
				set frontWindow to my frontFinalCutProWindow()
				set nothingLoadedVisible to my subtreeContainsExactText(frontWindow, "Nothing Loaded", 6)
			end tell
		end tell
	end timeout
	return "nothingLoaded=" & (nothingLoadedVisible as text)
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on subtreeContainsExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementTextEquals(rootElement, requiredText) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsExactText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsExactText

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "FCP viewer text snapshot" 35 0; then
		local reason="timeout or no readable AX text"
		if [[ -s "$error_file" ]]; then
			reason="AppleScript error: $(tr '\n' ' ' <"$error_file" | cut -c 1-240)"
		fi
		if [[ -s "$snapshot_file" ]]; then
			reason="${reason}; partial stdout: $(tr '\n' ' ' <"$snapshot_file" | cut -c 1-160)"
		fi
		rm -f "$snapshot_file" "$error_file"
		printf 'Final Cut Pro UI text snapshot unavailable while checking Viewer state (%s). This is nonfatal; continuing because Viewer ROI, Proxy/Green setup, Debug Overlay, and playback-motion preflights remain authoritative.\n' "$reason" >&2
		return 0
	fi
	snapshot="$(cat "$snapshot_file")"
	rm -f "$snapshot_file" "$error_file"
	if printf '%s\n' "$snapshot" | /usr/bin/grep -qi "nothingLoaded=true"; then
		fail "Final Cut Pro Viewer is showing Nothing Loaded; refusing to record a static/unloaded E2E video"
	fi
	if [[ -n "$project_name" ]]; then
		if fcp_project_visible "$project_name"; then
			printf 'FCP active timeline/header exposes expected project: %s\n' "$project_name"
		else
			printf 'FCP active timeline/header did not expose expected project name "%s"; continuing after clip/effect assertions.\n' "$project_name"
		fi
	fi
}

assert_fcp_viewer_not_nothing_loaded_with_proxy_warmup() {
	local project_name="$1"
	local timecode_entry="$2"
	if (assert_fcp_viewer_not_nothing_loaded "$project_name"); then
		return 0
	fi
	printf 'Final Cut Pro Viewer reported Nothing Loaded; warming Proxy Only render before recording.\n'
	warm_fcp_proxy_only_viewer_render "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded "$project_name"
}

assert_viewer_roi_playback_motion() {
	local viewer_roi="$1"
	local timecode_entry="$2"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for playback-motion preflight"
	mkdir -p "$ARTIFACT_ROOT"
	local last_status=1
	for attempt in $(seq 1 3); do
		local before_path="${ARTIFACT_ROOT}/fcp_playback_preflight_before_$(date +%Y%m%d_%H%M%S)_${attempt}.png"
		local after_path="${ARTIFACT_ROOT}/fcp_playback_preflight_after_$(date +%Y%m%d_%H%M%S)_${attempt}.png"
		press_stop_playback
		focus_timeline
		seek_timecode "$timecode_entry"
		focus_timeline
		sleep 0.4
		local before_playhead
		local after_playhead
		before_playhead="$(fcp_playhead_value)"
		/usr/sbin/screencapture -x "$before_path"
		press_start_playback
		sleep "${STABILIZER_E2E_PLAYBACK_PREFLIGHT_SECONDS:-0.85}"
		after_playhead="$(fcp_playhead_value)"
		/usr/sbin/screencapture -x "$after_path"
		press_stop_playback
		seek_timecode "$timecode_entry"
		focus_timeline
		sleep 0.4
		if python3 - "$before_path" "$after_path" "$viewer_roi" "$before_playhead" "$after_playhead" <<'PY'
from pathlib import Path
import os
import sys

import cv2
import numpy as np

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
roi_parts = [int(part) for part in sys.argv[3].split(",")]
before_playhead = sys.argv[4]
after_playhead = sys.argv[5]
if len(roi_parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
x, y, w, h = roi_parts
before = cv2.imread(str(before_path), cv2.IMREAD_COLOR)
after = cv2.imread(str(after_path), cv2.IMREAD_COLOR)
if before is None or after is None:
    raise SystemExit(f"could not read playback preflight screenshots: {before_path}, {after_path}")
if before.shape != after.shape:
    raise SystemExit(f"playback preflight screenshot shapes differ: {before.shape} vs {after.shape}")
height, width = before.shape[:2]
if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
    raise SystemExit(f"viewer ROI {x},{y},{w},{h} is outside screenshot bounds {width}x{height}")
before_roi = cv2.cvtColor(before[y:y + h, x:x + w], cv2.COLOR_BGR2GRAY)
after_roi = cv2.cvtColor(after[y:y + h, x:x + w], cv2.COLOR_BGR2GRAY)
before_color = before[y:y + h, x:x + w]
after_color = after[y:y + h, x:x + w]

def placeholder_ratio(frame):
    b, g, r = cv2.split(frame)
    red_dominance = r.astype(np.int16) - np.maximum(g, b).astype(np.int16)
    mask = (red_dominance > 18) & (r > 35) & (g < 75) & (b < 75)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    ratio = float(np.count_nonzero(mask)) / float(max(1, gray.size))
    center_mask = mask[h // 4 : (3 * h) // 4, w // 4 : (3 * w) // 4]
    center_ratio = float(np.count_nonzero(center_mask)) / float(max(1, center_mask.size))
    return ratio, center_ratio, float(gray.mean()), float(gray.std())

for label, frame, path in (("before", before_color, before_path), ("after", after_color, after_path)):
    ratio, center_ratio, mean_value, std_value = placeholder_ratio(frame)
    if mean_value < 80.0 and ratio > 0.55 and center_ratio > 0.40:
        raise SystemExit(
            "FCP Viewer playback preflight is showing Missing Proxy/source-media placeholder "
            f"in {label} screenshot: placeholderRatio={ratio:.3f}, centerPlaceholderRatio={center_ratio:.3f}, "
            f"mean={mean_value:.2f}, std={std_value:.2f}, screenshot={path}"
        )
diff = cv2.absdiff(before_roi, after_roi)
mean_abs = float(diff.mean())
p95_abs = float(np.percentile(diff.astype(np.float32), 95))
min_mean = float(os.environ.get("STABILIZER_E2E_MIN_PLAYBACK_MEAN_DIFF", "0.18"))
min_p95 = float(os.environ.get("STABILIZER_E2E_MIN_PLAYBACK_P95_DIFF", "1.0"))
if mean_abs < min_mean and p95_abs < min_p95:
    if (
        before_playhead
        and after_playhead
        and before_playhead not in {"missing", "unreadable"}
        and after_playhead not in {"missing", "unreadable"}
        and before_playhead != after_playhead
    ):
        print(
            "FCP Viewer playback preflight advanced playhead despite low viewer pixel diff: "
            f"playhead {before_playhead} -> {after_playhead}, "
            f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, "
            f"before={before_path}, after={after_path}. "
            "Recording progress guard and full-frame evaluation remain authoritative."
        )
        raise SystemExit(0)
    raise SystemExit(
        "FCP Viewer did not show playback motion before recording: "
        f"meanAbsDiff={mean_abs:.3f} (<{min_mean:.3f}), "
        f"p95AbsDiff={p95_abs:.3f} (<{min_p95:.3f}), "
        f"playhead={before_playhead}->{after_playhead}, "
        f"before={before_path}, after={after_path}"
    )
print(
    "FCP Viewer playback preflight motion: "
    f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, "
    f"before={before_path}, after={after_path}"
)
PY
		then
			if assert_debug_overlay_visible_in_screenshot "$before_path" "$viewer_roi" "playback preflight before" \
				&& assert_debug_overlay_visible_in_screenshot "$after_path" "$viewer_roi" "playback preflight after"
			then
				return 0
			fi
			last_status=$?
		else
			last_status=$?
		fi
		printf 'FCP Viewer playback motion preflight attempt %s/3 failed; retrying.\n' "$attempt"
		sleep 0.4
	done
	return "$last_status"
}

assert_current_viewer_roi_playback_motion() {
	local viewer_roi="$1"
	local label="${2:-recording-active}"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for recording-motion guard"
	mkdir -p "$ARTIFACT_ROOT"
	local before_path="${ARTIFACT_ROOT}/fcp_${label}_motion_before_$(date +%Y%m%d_%H%M%S).png"
	local after_path="${ARTIFACT_ROOT}/fcp_${label}_motion_after_$(date +%Y%m%d_%H%M%S).png"
	assert_fcp_frontmost "${label} motion guard before screenshot"
	local before_playhead
	local after_playhead
	before_playhead="$(fcp_playhead_value)"
	/usr/sbin/screencapture -x "$before_path"
	sleep "${STABILIZER_E2E_RECORDING_MOTION_GUARD_SECONDS:-0.45}"
	assert_fcp_frontmost "${label} motion guard after screenshot"
	after_playhead="$(fcp_playhead_value)"
	/usr/sbin/screencapture -x "$after_path"
	if python3 - "$before_path" "$after_path" "$viewer_roi" "$label" "$before_playhead" "$after_playhead" <<'PY'
from pathlib import Path
import os
import sys

import cv2
import numpy as np

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
roi_parts = [int(part) for part in sys.argv[3].split(",")]
label = sys.argv[4]
before_playhead = sys.argv[5]
after_playhead = sys.argv[6]
if len(roi_parts) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
x, y, w, h = roi_parts
before = cv2.imread(str(before_path), cv2.IMREAD_COLOR)
after = cv2.imread(str(after_path), cv2.IMREAD_COLOR)
if before is None or after is None:
    raise SystemExit(f"{label}: could not read motion guard screenshots: {before_path}, {after_path}")
if before.shape != after.shape:
    raise SystemExit(f"{label}: motion guard screenshot shapes differ: {before.shape} vs {after.shape}")
height, width = before.shape[:2]
if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
    raise SystemExit(f"{label}: viewer ROI {x},{y},{w},{h} is outside screenshot bounds {width}x{height}")

before_color = before[y:y + h, x:x + w]
after_color = after[y:y + h, x:x + w]
before_roi = cv2.cvtColor(before_color, cv2.COLOR_BGR2GRAY)
after_roi = cv2.cvtColor(after_color, cv2.COLOR_BGR2GRAY)

def frame_state(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    b, g, r = cv2.split(frame)
    red_dominance = r.astype(np.int16) - np.maximum(g, b).astype(np.int16)
    placeholder_mask = (red_dominance > 18) & (r > 35) & (g < 75) & (b < 75)
    center_mask = placeholder_mask[h // 4 : (3 * h) // 4, w // 4 : (3 * w) // 4]
    return {
        "mean": float(gray.mean()),
        "std": float(gray.std()),
        "color": float(np.count_nonzero(hsv[:, :, 1] > 12)) / float(max(1, gray.size)),
        "placeholder": float(np.count_nonzero(placeholder_mask)) / float(max(1, gray.size)),
        "center_placeholder": float(np.count_nonzero(center_mask)) / float(max(1, center_mask.size)),
    }

for state_label, state, path in (
    ("before", frame_state(before_color), before_path),
    ("after", frame_state(after_color), after_path),
):
    if state["mean"] < 6.0 or state["std"] < 3.0:
        raise SystemExit(
            f"{label}: recording ROI is not a recordable FCP Viewer image in {state_label} screenshot: "
            f"mean={state['mean']:.2f}, std={state['std']:.2f}, colorRatio={state['color']:.3f}, screenshot={path}"
        )
    if state["mean"] < 80.0 and state["placeholder"] > 0.55 and state["center_placeholder"] > 0.40:
        raise SystemExit(
            f"{label}: recording ROI is showing Missing Proxy/source-media placeholder in {state_label} screenshot: "
            f"placeholderRatio={state['placeholder']:.3f}, centerPlaceholderRatio={state['center_placeholder']:.3f}, "
            f"mean={state['mean']:.2f}, std={state['std']:.2f}, screenshot={path}"
        )

diff = cv2.absdiff(before_roi, after_roi)
mean_abs = float(diff.mean())
p95_abs = float(np.percentile(diff.astype(np.float32), 95))
min_mean = float(os.environ.get("STABILIZER_E2E_MIN_RECORDING_MEAN_DIFF", "0.18"))
min_p95 = float(os.environ.get("STABILIZER_E2E_MIN_RECORDING_P95_DIFF", "1.0"))
if mean_abs < min_mean and p95_abs < min_p95:
    if (
        before_playhead
        and after_playhead
        and before_playhead not in {"missing", "unreadable"}
        and after_playhead not in {"missing", "unreadable"}
        and before_playhead != after_playhead
    ):
        print(
            f"{label}: FCP playhead advanced despite low recording pixel diff: "
            f"playhead {before_playhead} -> {after_playhead}, "
            f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, "
            f"before={before_path}, after={after_path}. "
            "Recorded playback progress guard and full-frame evaluation remain authoritative."
        )
        raise SystemExit(0)
    raise SystemExit(
        f"{label}: FCP Viewer is not moving while recording: "
        f"meanAbsDiff={mean_abs:.3f} (<{min_mean:.3f}), "
        f"p95AbsDiff={p95_abs:.3f} (<{min_p95:.3f}), "
        f"playhead={before_playhead}->{after_playhead}, before={before_path}, after={after_path}"
    )
print(
    f"FCP Viewer recording motion guard passed: label={label}, "
    f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, before={before_path}, after={after_path}"
)
PY
	then
		assert_debug_overlay_visible_in_screenshot "$before_path" "$viewer_roi" "${label} before" \
			&& assert_debug_overlay_visible_in_screenshot "$after_path" "$viewer_roi" "${label} after"
	else
		return $?
	fi
}

wait_for_viewer_roi_recordable() {
	local case_file="$1"
	local viewer_roi="$2"
	local timecode_entry="$3"
	local last_output=""
	local proxy_warmup_done=0
	for attempt in $(seq 1 18); do
		dismiss_fcp_modal_alerts >/dev/null
		local blocker_result
		blocker_result="$(dismiss_known_screen_blockers)"
		fail_if_known_screen_blocked "$blocker_result"
		if output="$(assert_viewer_roi_recordable "$viewer_roi" 2>&1)"; then
			printf '%s\n' "$output"
			return 0
		fi
		last_output="$output"
		printf 'Viewer ROI is not ready yet (%s/18): %s\n' "$attempt" "$last_output"
		fail_if_recent_render_mismatches_case "$case_file" "viewer ROI prepare"
		if [[ "$last_output" == *"Missing Proxy/source-media placeholder"* ]]; then
			fail "$last_output"
		fi
		local needs_proxy_warmup=0
		if [[ "$last_output" == *"appears black"* ]] \
			|| [[ "$last_output" == *"lacks image detail"* ]] \
			|| [[ "$last_output" == *"mostly black"* ]] \
			|| [[ "$last_output" == *"checkerboard/uninitialized"* ]]
		then
			needs_proxy_warmup=1
		fi
		if (( proxy_warmup_done == 0 && needs_proxy_warmup == 1 )); then
			proxy_warmup_done=1
			if ! warm_fcp_proxy_only_viewer_render "$timecode_entry"; then
				printf 'Final Cut Pro Proxy Only render warmup failed; continuing ordinary retries.\n'
			fi
		fi
		if (( attempt == 1 || attempt == 5 || attempt == 10 )); then
			printf 'Nudging FCP Viewer playback to force a current-frame render...\n'
			press_start_playback
			sleep 0.5
			press_stop_playback
		fi
		sleep 1
	done
	fail "viewer ROI did not become recordable after retries: $last_output"
}

preflight_playback_alerts() {
	local timecode_entry="$1"
	printf 'Preflighting FCP playback alerts before recording...\n'
	press_stop_playback
	press_start_playback
	sleep 1.2
	local dismiss_result
	dismiss_result="$(dismiss_fcp_modal_alerts)"
	printf 'FCP playback alert preflight: %s\n' "$dismiss_result"
	dismiss_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$dismiss_result"
	printf 'Known screen-blocking dialog preflight: %s\n' "$dismiss_result"
	sleep 0.2
	press_stop_playback
	seek_timecode "$timecode_entry"
	sleep 0.6
	dismiss_result="$(dismiss_fcp_modal_alerts)"
	printf 'FCP alert state before recording: %s\n' "$dismiss_result"
	dismiss_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$dismiss_result"
	printf 'Known screen-blocking dialog state before recording: %s\n' "$dismiss_result"
	press_stop_playback
}

select_visible_sidebar_event_by_text() {
	local event_name="$1"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-event-select.XXXXXX")"
	/usr/bin/osascript - "$event_name" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set eventName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set eventRow to my firstRowContainingExactText(frontWindow, eventName, 18)
			if eventRow is missing value then error "visible Event sidebar row not found: " & eventName
			try
				set selected of eventRow to true
			end try
			try
				perform action "AXPress" of eventRow
			end try
		end tell
	end tell
	return "selected"
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstRowContainingExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
	end tell
	if roleName is "AXRow" and my subtreeContainsExactText(rootElement, requiredText, 7) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstRowContainingExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstRowContainingExactText

on subtreeContainsExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementTextEquals(rootElement, requiredText) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsExactText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsExactText

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "visible Event sidebar row ${event_name}" 100 0; then
		local result
		result="$(cat "$output_file")"
		rm -f "$output_file"
		printf 'visible Event sidebar row was not selectable through AX; continuing to project lookup: %s\n' "$result" >&2
		return 1
	fi
	local result
	result="$(cat "$output_file")"
	rm -f "$output_file"
	if [[ "$result" != "selected" ]]; then
		printf 'visible Event sidebar row returned unexpected AX result; continuing to project lookup: %s\n' "$result" >&2
		return 1
	fi
	sleep 0.8
	printf 'selected visible Final Cut Pro Event %s through AX.\n' "$event_name"
}

open_visible_browser_project_by_text() {
	local project_name="$1"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-project-open.XXXXXX")"
	/usr/bin/osascript - "$project_name" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set projectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			keystroke "1" using {command down}
			delay 0.2
			set frontWindow to my frontFinalCutProWindow()
			set openableElement to my firstBrowserOpenableElementContainingExactText(frontWindow, projectName, 18)
			if openableElement is missing value then error "visible Browser row not found: " & projectName
			try
				set selected of openableElement to true
			end try
			try
				set focused of openableElement to true
			end try
			delay 0.15
			if my openWithAXAction(openableElement, "AXShowDefaultUI", projectName) then return "AXShowDefaultUI"
			if my openWithAXAction(openableElement, "AXShowAlternateUI", projectName) then return "AXShowAlternateUI"
			try
				perform action "AXOpen" of openableElement
				delay 0.7
				if my activeProjectVisible(projectName) then return "AXOpen"
				log "AXOpen ran for Browser project row, but active project is not " & projectName
			on error axOpenError
				log "AXOpen unavailable for Browser project row: " & axOpenError
			end try
			try
				key code 36
				delay 0.7
				if my activeProjectVisible(projectName) then return "Return"
				log "Return ran for Browser project row, but active project is not " & projectName
			on error returnError
				log "Return key project open failed: " & returnError
			end try
			try
				click menu item "Open Clip" of menu "Clip" of menu bar 1
				delay 0.7
				if my activeProjectVisible(projectName) then return "Clip > Open Clip"
				log "Clip > Open Clip ran for Browser project row, but active project is not " & projectName
			on error openClipError
				log "Clip > Open Clip failed: " & openClipError
			end try
			try
				click menu item "Open in Timeline" of menu "Clip" of menu bar 1
				delay 0.7
				if my activeProjectVisible(projectName) then return "Clip > Open in Timeline"
				log "Clip > Open in Timeline ran for Browser project row, but active project is not " & projectName
			on error openTimelineError
				log "Clip > Open in Timeline failed: " & openTimelineError
			end try
		end tell
	end tell
	error "non-coordinate Browser project open failed: " & projectName
end run

on openWithAXAction(elementReference, actionName, projectName)
	tell application "System Events"
		try
			perform action actionName of elementReference
			delay 0.8
			if my activeProjectVisible(projectName) then return true
			log actionName & " ran for Browser project row, but active project is not " & projectName
		end try
	end tell
	return false
end openWithAXAction

on activeProjectVisible(projectName)
	try
		set frontWindow to my frontFinalCutProWindow()
		return my subtreeContainsProjectHeaderText(frontWindow, projectName, 10)
	on error
		return false
	end try
end activeProjectVisible

on subtreeContainsProjectHeaderText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementContainsText(rootElement, requiredText) and my elementLooksLikeProjectHeader(rootElement) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsProjectHeaderText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsProjectHeaderText

on elementLooksLikeProjectHeader(candidateElement)
	tell application "System Events"
		try
			set elementPosition to position of candidateElement
			set elementSize to size of candidateElement
			set elementX to item 1 of elementPosition
			set elementY to item 2 of elementPosition
			if elementY < 260 and elementX > 450 and (item 1 of elementSize) > 20 then return true
		end try
	end tell
	return false
end elementLooksLikeProjectHeader

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstRowContainingExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
	end tell
	if roleName is "AXRow" and my subtreeContainsExactText(rootElement, requiredText, 5) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstRowContainingExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstRowContainingExactText

on subtreeContainsExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementTextEquals(rootElement, requiredText) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsExactText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsExactText

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals

on elementContainsText(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) contains requiredText then return true
		end ignoring
	end repeat
	return false
end elementContainsText

on firstBrowserOpenableElementContainingExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
	end tell
	if (roleName is "AXRow" or roleName is "AXCell" or roleName is "AXGroup") and my elementAppearsInsideBrowser(rootElement) and my subtreeContainsExactText(rootElement, requiredText, 7) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstBrowserOpenableElementContainingExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstBrowserOpenableElementContainingExactText

on elementAppearsInsideBrowser(candidateElement)
	tell application "System Events"
		try
			set elementPosition to position of candidateElement
			set elementSize to size of candidateElement
			if (item 1 of elementPosition) < 220 then return false
			if (item 2 of elementPosition) < 180 then return false
			if (item 1 of elementSize) < 40 then return false
			return true
		on error
			return false
	end try
	end tell
end elementAppearsInsideBrowser
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "visible Browser project ${project_name}" 100 0; then
		local result
		result="$(cat "$output_file")"
		rm -f "$output_file"
		printf 'visible Browser project was not openable without coordinates; trying next path: %s\n' "$result" >&2
		return 1
	fi
	local result
	result="$(cat "$output_file")"
	rm -f "$output_file"
	for _ in {1..12}; do
		if fcp_project_visible "$project_name"; then
			printf 'opened visible Browser project %s via non-coordinate path: %s\n' "$project_name" "$result"
			return 0
		fi
		sleep 0.25
	done
	printf 'non-coordinate Browser project open did not make expected project visible: %s (%s)\n' "$project_name" "$result" >&2
	return 1
}

set_visible_browser_search_text() {
	local search_text="$1"
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-search-ax.XXXXXX")"
	/usr/bin/osascript - "$search_text" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set searchText to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			keystroke "1" using {command down}
			delay 0.2
			set frontWindow to my frontFinalCutProWindow()
			set searchField to my firstSearchField(frontWindow, 18)
			if searchField is missing value then error "visible Browser search field not found"
			try
				set focused of searchField to true
			end try
			try
				perform action "AXPress" of searchField
			end try
			delay 0.1
			keystroke "a" using {command down}
			delay 0.05
			keystroke searchText
			delay 0.25
			key code 36
		end tell
	end tell
	return "search-set"
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstSearchField(rootElement, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXTextField" then
				try
					if (description of rootElement as text) is "Search text" then return rootElement
				end try
			end if
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstSearchField(childElement, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstSearchField
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "visible Browser search field" 100 0; then
		local result
		result="$(cat "$output_file")"
		rm -f "$output_file"
		printf 'visible Browser search field was not usable through AX: %s\n' "$result" >&2
		return 1
	fi
	local result
	result="$(cat "$output_file")"
	rm -f "$output_file"
	if [[ "$result" != "search-set" ]]; then
		printf 'visible Browser search returned unexpected AX result: %s\n' "$result" >&2
		return 1
	fi
	sleep 0.8
	printf 'Set visible Final Cut Pro Browser search text through AX: %s\n' "$search_text"
}

open_case_project_via_helper() {
	local project_name="$1"
	local event_name="$2"
	[[ -f "$FCP_HELPER" ]] || return 1
	printf 'Primary project open: selecting Event via local AX path: %s\n' "$event_name"
	if ! select_visible_sidebar_event_by_text "$event_name"; then
		printf 'Primary project open: local AX path could not select Event %s; trying project open in current Browser state.\n' "$event_name" >&2
	fi
	printf 'Primary project open: using helper keyboard search + Clip menu for project: %s\n' "$project_name"
	timeout 30 /usr/bin/osascript "$FCP_HELPER" open-project "$project_name"
}

open_selected_browser_project_via_helper() {
	local project_name="$1"
	[[ -f "$FCP_HELPER" ]] || return 1
	timeout 12 /usr/bin/osascript "$FCP_HELPER" wait-open-selected-project 3 "$project_name"
}

open_case_project_via_keyboard_menu() {
	local project_name="$1"
	timeout 15 /usr/bin/osascript - "$project_name" <<'APPLESCRIPT'
on run argv
	set projectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			keystroke "f" using {command down}
			delay 0.15
			keystroke "a" using {command down}
			keystroke projectName
			key code 36
			delay 0.5
			set frontWindow to my frontFinalCutProWindow()
			set projectRow to my firstBrowserRowContainingExactText(frontWindow, projectName, 18)
			if projectRow is missing value then error "project row not found after keyboard Browser search: " & projectName
			try
				set selected of projectRow to true
			end try
			try
				perform action "AXOpen" of projectRow
				delay 0.7
				if my activeProjectVisible(projectName) then return "opened via AXOpen"
				log "AXOpen ran for project row, but active project is not " & projectName
			on error axOpenError
				log "AXOpen was unavailable for project row: " & axOpenError
			end try
			try
				key code 36
				delay 0.7
				if my activeProjectVisible(projectName) then return "opened via Return"
				log "Return ran for project row, but active project is not " & projectName
			on error returnError
				log "Return key project open failed: " & returnError
			end try
			try
				click menu item "Open Clip" of menu "Clip" of menu bar 1
				delay 0.7
				if my activeProjectVisible(projectName) then return "opened via Clip > Open Clip"
				log "Clip > Open Clip ran for project row, but active project is not " & projectName
			on error openClipError
				log "Clip > Open Clip failed: " & openClipError
			end try
			try
				click menu item "Open in Timeline" of menu "Clip" of menu bar 1
				delay 0.7
				if my activeProjectVisible(projectName) then return "opened via Clip > Open in Timeline"
				log "Clip > Open in Timeline ran for project row, but active project is not " & projectName
			on error openTimelineError
				log "Clip > Open in Timeline failed: " & openTimelineError
			end try
		end tell
	end tell
	error "non-coordinate project open methods failed for " & projectName
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

on firstBrowserRowContainingExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXRow" then
				if my rowAppearsInsideBrowser(rootElement) and my subtreeContainsExactText(rootElement, requiredText, 6) then return rootElement
			end if
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstBrowserRowContainingExactText(childElement, requiredText, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstBrowserRowContainingExactText

on rowAppearsInsideBrowser(rowElement)
	tell application "System Events"
		try
			set rowPosition to position of rowElement
			set rowSize to size of rowElement
			if (item 1 of rowPosition) < 220 then return false
			if (item 2 of rowPosition) < 180 then return false
			if (item 1 of rowSize) < 80 then return false
			return true
		on error
			return false
		end try
	end tell
end rowAppearsInsideBrowser

on subtreeContainsExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementTextEquals(rootElement, requiredText) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsExactText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsExactText

on activeProjectVisible(projectName)
	try
		set frontWindow to my frontFinalCutProWindow()
		return my subtreeContainsProjectHeaderText(frontWindow, projectName, 10)
	on error
		return false
	end try
end activeProjectVisible

on subtreeContainsProjectHeaderText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return false
	if my elementTextEquals(rootElement, requiredText) and my elementLooksLikeProjectHeader(rootElement) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsProjectHeaderText(childElement, requiredText, remainingDepth - 1) then return true
	end repeat
	return false
end subtreeContainsProjectHeaderText

on elementLooksLikeProjectHeader(candidateElement)
	tell application "System Events"
		try
			set elementPosition to position of candidateElement
			set elementSize to size of candidateElement
			set elementX to item 1 of elementPosition
			set elementY to item 2 of elementPosition
			if elementY < 260 and elementX > 450 and (item 1 of elementSize) > 20 then return true
		end try
	end tell
	return false
end elementLooksLikeProjectHeader

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals
APPLESCRIPT
}

fcp_project_visible() {
	local project_name="$1"
	local snapshot
	snapshot="$(/usr/bin/osascript - "$project_name" <<'APPLESCRIPT'
on run argv
	set expectedProjectName to item 1 of argv
	with timeout of 12 seconds
		tell application "Final Cut Pro" to activate
		tell application "System Events"
			tell process "Final Cut Pro"
				set frontmost to true
					set frontWindow to my frontFinalCutProWindow()
					set windowPosition to position of frontWindow
					set windowSize to size of frontWindow
					set projectVisible to my subtreeContainsActiveTimelineHeaderText(frontWindow, expectedProjectName, 12, windowPosition, windowSize)
				end tell
			end tell
		end timeout
	return "projectVisible=" & (projectVisible as text)
end run

on frontFinalCutProWindow()
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					if subrole of candidateWindow is "AXStandardWindow" then return candidateWindow
				end try
			end repeat
			return window 1
		end tell
	end tell
end frontFinalCutProWindow

		on subtreeContainsActiveTimelineHeaderText(rootElement, requiredText, remainingDepth, windowPosition, windowSize)
			if remainingDepth < 0 then return false
			if my elementContainsText(rootElement, requiredText) and my elementLooksLikeActiveTimelineHeader(rootElement, windowPosition, windowSize) then return true
			set childElements to {}
			tell application "System Events"
				try
				set childElements to UI elements of rootElement
		on error
			return false
			end try
			end tell
			repeat with childElement in childElements
				if my subtreeContainsActiveTimelineHeaderText(childElement, requiredText, remainingDepth - 1, windowPosition, windowSize) then return true
			end repeat
			return false
		end subtreeContainsActiveTimelineHeaderText

		on elementLooksLikeActiveTimelineHeader(candidateElement, windowPosition, windowSize)
			tell application "System Events"
				try
					set roleText to role of candidateElement as text
					if roleText is not "AXStaticText" and roleText is not "AXButton" and roleText is not "AXMenuButton" and roleText is not "AXPopUpButton" and roleText is not "AXGroup" then return false
					try
						if visible of candidateElement is false then return false
					end try
					try
						set hiddenValue to value of attribute "AXHidden" of candidateElement
						if hiddenValue is true then return false
					end try
					set elementPosition to position of candidateElement
					set elementSize to size of candidateElement
					set elementX to item 1 of elementPosition
					set elementY to item 2 of elementPosition
					set elementWidth to item 1 of elementSize
					set elementHeight to item 2 of elementSize
					if elementWidth < 20 or elementHeight < 8 then return false
					set centerX to elementX + (elementWidth / 2)
					set centerY to elementY + (elementHeight / 2)
					set windowX to item 1 of windowPosition
					set windowY to item 2 of windowPosition
					set windowWidth to item 1 of windowSize
					set windowHeight to item 2 of windowSize
					set relativeCenterX to centerX - windowX
					set relativeCenterY to centerY - windowY
					if relativeCenterX < (windowWidth * 0.30) then return false
					if relativeCenterX > (windowWidth * 0.92) then return false
					if relativeCenterY < 130 then return true
					if relativeCenterY > (windowHeight * 0.50) and relativeCenterY < (windowHeight * 0.88) then return true
				end try
			end tell
			return false
		end elementLooksLikeActiveTimelineHeader

on elementTextEquals(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) is requiredText then return true
		end ignoring
	end repeat
	return false
end elementTextEquals

on elementContainsText(candidateElement, requiredText)
	set labelsToCheck to {}
	tell application "System Events"
		try
			set end of labelsToCheck to name of candidateElement as text
		end try
		try
			set end of labelsToCheck to description of candidateElement as text
		end try
		try
			set end of labelsToCheck to value of candidateElement as text
		end try
	end tell
	repeat with labelText in labelsToCheck
		ignoring case
			if (labelText as text) contains requiredText then return true
		end ignoring
	end repeat
	return false
end elementContainsText
APPLESCRIPT
)" || return 1
	printf '%s\n' "$snapshot" | /usr/bin/grep -qi "projectVisible=true"
}

assert_fcp_project_visible() {
	local project_name="$1"
	fcp_project_visible "$project_name" \
		|| fail "Final Cut Pro active timeline/header did not expose expected project after open: ${project_name}"
	printf 'FCP active timeline/header exposes expected project: %s\n' "$project_name"
}

seek_timecode() {
	local timecode_entry="$1"
	/usr/bin/osascript - "$timecode_entry" <<'APPLESCRIPT' &
on run argv
	set timecodeEntry to item 1 of argv
	tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		keystroke "2" using {command down}
		delay 0.1
		key code 35 using control down
			delay 0.1
			keystroke timecodeEntry
			key code 36
		end tell
	end tell
end run
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "seek timecode ${timecode_entry}" 80 0
}

open_case_project() {
	local case_file="$1"
	local assume_current="$2"
	local library
	local project
	local event_name
	library="$(json_value "$case_file" library)"
	project="$(json_value "$case_file" project)"
	event_name="$(case_event_name "$case_file")"
	[[ -d "$library" ]] || fail "case library does not exist: $library"

	if [[ "$assume_current" == "1" ]]; then
		ensure_current_fcp_standard_window "assume-current FCP state" \
			|| fail "Final Cut Pro standard window was not readable for --assume-current-fcp-state"
		printf 'Using current FCP project/state for case: %s\n' "$project"
		assert_fcp_project_visible "$project"
		assert_fcp_viewer_not_nothing_loaded "$project"
		return
	fi

	/usr/bin/open -a "Final Cut Pro" "$library"
	while ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; do
		sleep 0.25
	done
	ensure_fcp_standard_window_after_open "$library" "opening ${library}" \
		|| fail "Final Cut Pro standard window did not become readable after opening ${library}"
	sleep 0.5
	[[ -f "$FCP_HELPER" ]] || fail "missing FCP helper: ${FCP_HELPER}"
	/usr/bin/osascript "$FCP_HELPER" handle-e2e-import-prompts 6 "$library" >/dev/null &
	local import_prompt_pid=$!
	if ! wait_for_ui_osascript "$import_prompt_pid" "E2E import prompt handling" 90 1; then
		fail "could not complete E2E import prompt handling"
	fi
	ensure_fcp_standard_window_after_open "$library" "import prompt handling" \
		|| fail "Final Cut Pro standard window was not readable after import prompt handling"

	if open_case_project_via_helper "$project" "$event_name" && fcp_project_visible "$project"; then
		printf 'Opened Final Cut Pro project via helper primary path: %s\n' "$project"
	elif open_selected_browser_project_via_helper "$project" && fcp_project_visible "$project"; then
		printf 'Opened Final Cut Pro project via selected Browser helper menu path: %s\n' "$project"
	elif open_case_project_via_keyboard_menu "$project" && fcp_project_visible "$project"; then
		printf 'Opened Final Cut Pro project via non-coordinate keyboard/menu path: %s\n' "$project"
	else
		printf 'Primary project open paths failed; enabling Browser for explicit AX/menu project-open retry.\n' >&2
		fail_if_fcp_windowless "project-open retry before enabling Browser"
		if ! set_fcp_toolbar_checkbox "Show or hide the Browser" 1 >/dev/null; then
			fail_if_fcp_windowless "project-open retry after Browser toolbar failure"
			sleep 0.5
			wait_for_fcp_standard_window 300 \
				|| fail "Final Cut Pro standard window was not readable while enabling Browser"
			set_fcp_toolbar_checkbox "Show or hide the Browser" 1 >/dev/null \
				|| fail "could not enable Final Cut Pro Browser before opening project ${project}"
		fi
		sleep 0.8
		if ! set_fcp_window_checkbox "Show or hide the Libraries sidebar" 1 >/dev/null; then
			printf 'FCP Libraries sidebar toggle was not visible; continuing because Event selection is the authoritative preflight.\n'
		fi
		if select_visible_sidebar_event_by_text "$event_name"; then
			sleep 0.8
		else
			printf 'FCP Event row was not directly selectable; continuing with visible/current Browser project lookup for Event %s.\n' "$event_name"
		fi
		if set_visible_browser_search_text "$project" && open_visible_browser_project_by_text "$project"; then
			printf 'AX/menu project-open retry opened Final Cut Pro project via visible Browser search: %s\n' "$project"
		elif open_visible_browser_project_by_text "$project"; then
			printf 'AX/menu project-open retry opened Final Cut Pro project via visible Browser row: %s\n' "$project"
		else
			fail "could not open Final Cut Pro project '${project}' by name; select it in FCP and retry with --assume-current-fcp-state"
		fi
	fi
	sleep 1
	assert_fcp_project_visible "$project"
	assert_fcp_viewer_not_nothing_loaded "$project"
}

assert_case_prepared() {
	local case_file="$1"
	local viewer_roi="$2"
	local expected_effect
	local remove_black_edges
	local timecode_entry
	local project
	local playback_mode
	expected_effect="$(json_value "$case_file" expectedEffect)"
	remove_black_edges="$(json_bool_value "$case_file" removeBlackEdges)"
	timecode_entry="$(json_value "$case_file" startTimecodeEntry)"
	project="$(json_value "$case_file" project)"
	playback_mode="$(json_value "$case_file" playbackMode)"
	if [[ "$playback_mode" != "Proxy Only" ]]; then
		fail "E2E playbackMode must be Proxy Only, got: ${playback_mode}"
	fi

	assert_case_project_contains_effect "$case_file"
	focus_timeline
	set_fcp_proxy_only
	set_fcp_green_channel
	seek_timecode "$timecode_entry"
	sleep 0.4
	select_playhead_clip
	sleep 0.4
	ensure_selected_timeline_clip_enabled
	sleep 0.4
	printf 'Checking Inspector for expected Stabilizer controls...\n'
	if assert_inspector_contains_case_effect "$expected_effect" "$remove_black_edges"; then
		printf 'Inspector shows expected Stabilizer controls.\n'
	else
		fail "selected timeline clip Inspector is not showing ${expected_effect}; refusing to toggle Debug Overlay on the wrong item"
	fi
	set_fcp_remove_black_edges_via_local_ax "$remove_black_edges" \
		|| fail "case requires Remove Black Edges ${remove_black_edges}, but the Inspector checkbox could not be set"
	printf 'Remove Black Edges set to: %s\n' "$remove_black_edges"
	set_fcp_debug_overlay_on "$viewer_roi"
	assert_inspector_contains_case_effect_if_readable "$expected_effect" "$remove_black_edges"
	if [[ "$remove_black_edges" == "false" ]]; then
		if [[ "${STABILIZER_E2E_SKIP_REMOVE_BLACK_EDGES_RENDER_PULSE:-0}" == "1" ]]; then
			printf 'Skipping Remove Black Edges render pulse because STABILIZER_E2E_SKIP_REMOVE_BLACK_EDGES_RENDER_PULSE=1; render revision must provide invalidation evidence.\n'
		else
			force_fcp_remove_black_edges_render_pulse "$remove_black_edges"
		fi
	fi
	normalize_fcp_layout
	set_fcp_proxy_only
	set_fcp_green_channel
	seek_timecode "$timecode_entry"
	sleep 0.4
	viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
	recording_viewer_roi="$viewer_roi"
	wait_for_viewer_roi_recordable "$case_file" "$viewer_roi" "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded "$project"
}

prepare_case() {
	local case_file="$1"
	local assume_current="$2"
	local viewer_roi="$3"
	local timecode_entry
	timecode_entry="$(json_value "$case_file" startTimecodeEntry)"

	open_case_project "$case_file" "$assume_current"
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$blocker_result"
	printf 'Known screen-blocking dialog state during prepare: %s\n' "$blocker_result"
	dismiss_fcp_modal_alerts >/dev/null
	normalize_fcp_layout
	seek_timecode "$timecode_entry"
	sleep 0.8
	viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
	recording_viewer_roi="$viewer_roi"
	assert_case_prepared "$case_file" "$viewer_roi"
	printf 'FCP prepared for case %s at %s.\n' "$(json_value "$case_file" caseId)" "$(json_value "$case_file" startTimecode)"
}

capture_case() {
	local case_file="$1"
	local video_path="$2"
	local assume_current="$3"
	local viewer_roi="$4"
	local capture_backend="$5"
	local assume_prepared="$6"
	local case_id
	local duration
	local record_seconds
	local timecode_entry

	case_id="$(json_value "$case_file" caseId)"
	duration="$(json_value "$case_file" durationSeconds)"
	timecode_entry="$(json_value "$case_file" startTimecodeEntry)"
	record_seconds="$(case_record_seconds "$case_file")"

	mkdir -p "$(dirname "$video_path")"
	if [[ "$assume_current" == "0" && "$assume_prepared" == "0" ]]; then
		prepare_case "$case_file" "$assume_current" "$viewer_roi"
	elif [[ "$assume_prepared" == "1" ]]; then
		printf 'Using already prepared FCP state for case: %s\n' "$case_id"
		viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
		recording_viewer_roi="$viewer_roi"
		assert_case_prepared "$case_file" "$viewer_roi"
	else
		open_case_project "$case_file" "$assume_current"
		normalize_fcp_layout
		viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
		recording_viewer_roi="$viewer_roi"
		assert_case_prepared "$case_file" "$viewer_roi"
	fi
	viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
	recording_viewer_roi="$viewer_roi"
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$blocker_result"
	printf 'Known screen-blocking dialog state before seek: %s\n' "$blocker_result"
	set_fcp_proxy_only
	set_fcp_green_channel
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.6
	select_playhead_clip
	sleep 0.2
	set_fcp_debug_overlay_on "$viewer_roi"
	normalize_fcp_layout
	set_fcp_proxy_only
	set_fcp_green_channel
	viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
	recording_viewer_roi="$viewer_roi"
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.4
	wait_for_viewer_roi_recordable "$case_file" "$viewer_roi" "$timecode_entry"
	preflight_playback_alerts "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded_with_proxy_warmup "$(json_value "$case_file" project)" "$timecode_entry"
	if ! assert_viewer_roi_playback_motion "$viewer_roi" "$timecode_entry"; then
		fail "FCP Viewer playback preflight did not show motion; refusing to record a static E2E video"
	fi
	wait_for_target_playback_plan_ready "$case_file" "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded_with_proxy_warmup "$(json_value "$case_file" project)" "$timecode_entry"
	set_fcp_debug_overlay_on "$viewer_roi"
	normalize_fcp_layout
	set_fcp_proxy_only
	set_fcp_green_channel
	viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
	recording_viewer_roi="$viewer_roi"
	press_stop_playback
	focus_timeline
	seek_timecode "$timecode_entry"
	focus_timeline
	sleep 0.2
	wait_for_viewer_roi_recordable "$case_file" "$viewer_roi" "$timecode_entry"
	assert_fcp_frontmost "before starting E2E recording playback"
	printf 'Skipping CoreGraphics cursor movement; ROI recording backends hide the cursor, and UI state stays controlled by AppleScript/AX.\n'

	printf 'Recording FCP Viewer E2E case %s for %ss via %s: %s (target duration %ss)\n' "$case_id" "$record_seconds" "$capture_backend" "$video_path" "$duration"
	case "$capture_backend" in
		screencapture)
			/usr/sbin/screencapture -v -V "$record_seconds" "$video_path" &
			;;
		avfoundation-roi)
			[[ -n "$viewer_roi" ]] || fail "--capture-backend avfoundation-roi requires --viewer-roi"
			local ffmpeg_bin
			ffmpeg_bin="$(command -v ffmpeg || true)"
			[[ -n "$ffmpeg_bin" ]] || fail "ffmpeg is required for --capture-backend avfoundation-roi"
			local crop_x
			local crop_y
			local crop_w
			local crop_h
			crop_x="$(viewer_roi_field "$viewer_roi" 0)"
			crop_y="$(viewer_roi_field "$viewer_roi" 1)"
			crop_w="$(viewer_roi_field "$viewer_roi" 2)"
			crop_h="$(viewer_roi_field "$viewer_roi" 3)"
				if (( crop_w % 2 == 1 )); then
					crop_w=$((crop_w - 1))
				fi
				if (( crop_h % 2 == 1 )); then
					crop_h=$((crop_h - 1))
				fi
				local video_filter="crop=${crop_w}:${crop_h}:${crop_x}:${crop_y}"
				if [[ "${STABILIZER_E2E_NORMALIZE_ROI_CAPTURE_TO_CASE:-1}" == "1" ]]; then
					local case_roi
					local target_w
					local target_h
					case_roi="$(case_viewer_roi "$case_file")"
					target_w="$(viewer_roi_field "$case_roi" 2)"
					target_h="$(viewer_roi_field "$case_roi" 3)"
					if (( target_w % 2 == 1 )); then
						target_w=$((target_w - 1))
					fi
					if (( target_h % 2 == 1 )); then
						target_h=$((target_h - 1))
					fi
					video_filter="${video_filter},scale=${target_w}:${target_h}:flags=lanczos"
					recording_viewer_roi="0,0,${target_w},${target_h}"
					printf 'Normalizing ROI capture from %sx%s to case viewer %sx%s without dropping frames.\n' "$crop_w" "$crop_h" "$target_w" "$target_h"
				else
					recording_viewer_roi="$viewer_roi"
				fi
				"$ffmpeg_bin" -y -hide_banner \
					-f avfoundation \
					-framerate 60 \
					-capture_cursor 0 \
					-pixel_format bgr0 \
					-i "1:none" \
					-t "$record_seconds" \
					-vf "$video_filter" \
					-an \
					-c:v h264_videotoolbox \
				-b:v 8M \
				-allow_sw 0 \
				"$video_path" &
			;;
		screencapturekit-roi)
			[[ -n "$viewer_roi" ]] || fail "--capture-backend screencapturekit-roi requires --viewer-roi"
			local crop_x
			local crop_y
			local crop_w
			local crop_h
			crop_x="$(viewer_roi_field "$viewer_roi" 0)"
			crop_y="$(viewer_roi_field "$viewer_roi" 1)"
			crop_w="$(viewer_roi_field "$viewer_roi" 2)"
			crop_h="$(viewer_roi_field "$viewer_roi" 3)"
			if (( crop_w % 2 == 1 )); then
				crop_w=$((crop_w - 1))
			fi
			if (( crop_h % 2 == 1 )); then
				crop_h=$((crop_h - 1))
			fi
			local sck_capture_bin="${ARTIFACT_ROOT}/screen_capturekit_roi"
			mkdir -p "$ARTIFACT_ROOT"
			xcrun swiftc -parse-as-library "${ROOT_DIR}/scripts/screen_capturekit_roi.swift" -o "$sck_capture_bin" \
				|| fail "could not compile ScreenCaptureKit ROI recorder"
			"$sck_capture_bin" \
				--output "$video_path" \
				--roi "${crop_x},${crop_y},${crop_w},${crop_h}" \
				--duration "$record_seconds" \
				--fps "${STABILIZER_E2E_CAPTURE_FPS:-60}" \
				--cadence "${STABILIZER_E2E_SCK_CADENCE:-source}" \
				--bit-rate "${STABILIZER_E2E_CAPTURE_BITRATE:-8000000}" &
			;;
		*)
			fail "unknown capture backend: $capture_backend"
			;;
	esac
	local capture_pid=$!
	sleep 0.35
	local recording_frontmost
	recording_frontmost="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
	return name of first application process whose frontmost is true
end tell
APPLESCRIPT
)"
	if [[ "$recording_frontmost" != "Final Cut Pro" ]]; then
		kill -TERM "$capture_pid" 2>/dev/null || true
		wait "$capture_pid" 2>/dev/null || true
		press_stop_playback
		fail "Final Cut Pro did not remain frontmost while the E2E recording was active (frontmost=${recording_frontmost})"
	fi
	focus_timeline
	recording_start_epoch="$(now_epoch_seconds)"
	press_start_playback
	if [[ -n "$viewer_roi" ]]; then
		if ! assert_current_viewer_roi_playback_motion "$viewer_roi" "recording-active"; then
			kill -TERM "$capture_pid" 2>/dev/null || true
			wait "$capture_pid" 2>/dev/null || true
			press_stop_playback
			fail "FCP Viewer recording motion/debug-overlay guard failed"
		fi
	fi
	wait "$capture_pid"
	recording_end_epoch="$(now_epoch_seconds)"
	press_stop_playback

	[[ -s "$video_path" ]] || fail "screen recording was not written: $video_path"
	printf 'Captured: %s\n' "$video_path"
}

evaluate_case() {
	local case_file="$1"
	local video_path="$2"
	local viewer_roi="$3"
	local output_dir="$4"
	local visual_review="$5"
	[[ -f "$video_path" ]] || fail "video does not exist: $video_path"

	local args=(
		python3
		"${ROOT_DIR}/tests/stabilizer_video_quality.py"
		--case "$case_file"
		--video "$video_path"
		--visual-review "$visual_review"
	)
	if [[ -n "$viewer_roi" ]]; then
		args+=(--viewer-roi "$viewer_roi")
	fi
	if [[ -n "$output_dir" ]]; then
		args+=(--output-dir "$output_dir")
	fi
	"${args[@]}"
}

assert_recorded_playback_progress() {
	local case_file="$1"
	local video_path="$2"
	local viewer_roi="$3"
	[[ -f "$video_path" ]] || fail "video does not exist for playback-progress guard: $video_path"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for playback-progress guard"
	python3 - "$case_file" "$video_path" "$viewer_roi" <<'PY'
import json
import sys
from pathlib import Path

import cv2
import numpy as np

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
video_path = Path(sys.argv[2])
roi_values = [int(part) for part in sys.argv[3].split(",")]
if len(roi_values) != 4:
    raise SystemExit("viewer ROI must be x,y,w,h")
roi_x, roi_y, roi_w, roi_h = roi_values
if roi_w <= 0 or roi_h <= 0:
    raise SystemExit("viewer ROI width/height must be positive")

quality = case.get("quality") or {}
recording = case.get("recording") or {}
guard = recording.get("progressGuard") or {}
enabled = bool(guard.get("enabled", quality.get("requireEveryCapturedFrame", False)))
if not enabled:
    print("Recorded playback progress guard disabled for this case.")
    raise SystemExit(0)

max_hold_run = int(guard.get("maxHoldRunFrames", quality.get("maxCadenceHoldRunFrames", 0)))
if max_hold_run <= 0:
    print("Recorded playback progress guard has no positive maxHoldRunFrames; skipped.")
    raise SystemExit(0)

mean_threshold = float(
    guard.get(
        "meanAbsDiffThreshold",
        quality.get("cadenceHoldMeanAbsDiffThreshold", quality.get("nearDuplicateMeanAbsDiffThreshold", 0.08)),
    )
)
p95_threshold = float(
    guard.get(
        "p95AbsDiffThreshold",
        quality.get("cadenceHoldP95AbsDiffThreshold", quality.get("nearDuplicateP95AbsDiffThreshold", 0.5)),
    )
)
ignore_start = float(guard.get("ignoreStartSeconds", quality.get("ignoreStartSeconds", 1.0)))
ignore_end = float(guard.get("ignoreEndSeconds", quality.get("ignoreEndSeconds", 0.5)))
case_duration = float(case.get("durationSeconds", 0.0) or 0.0)

cap = cv2.VideoCapture(str(video_path))
if not cap.isOpened():
    raise SystemExit(f"could not open video for playback-progress guard: {video_path}")
fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
if fps <= 1.0:
    raise SystemExit("could not determine video fps for playback-progress guard")
frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
duration = frame_count / fps if frame_count > 0 else 0.0
evaluation_duration = case_duration if case_duration > 0.0 else duration
if duration > 0.0 and evaluation_duration > 0.0:
    evaluation_duration = min(duration, evaluation_duration)
cutoff_end = max(0.0, evaluation_duration - ignore_end) if evaluation_duration > 0.0 else float("inf")

ok, first_frame = cap.read()
if not ok:
    raise SystemExit(f"could not read first frame for playback-progress guard: {video_path}")
height, width = first_frame.shape[:2]
if roi_x == 0 and roi_y == 0 and (roi_w > width or roi_h > height):
    print(
        "Recorded playback progress guard using the full ROI-cropped recording "
        f"frame {width}x{height} instead of configured ROI {roi_w}x{roi_h}.",
        file=sys.stderr,
    )
    roi_w = width
    roi_h = height
if roi_x < 0 or roi_y < 0 or roi_x + roi_w > width or roi_y + roi_h > height:
    raise SystemExit(
        f"viewer ROI {roi_x},{roi_y},{roi_w},{roi_h} is outside recording frame {width}x{height}"
    )
cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

previous_gray = None
previous_frame_index = None
current_run = 0
current_start_frame = None
current_start_time = None
best_run = 0
best_start_frame = None
best_end_frame = None
best_start_time = None
best_end_time = None
sampled_pairs = 0
frame_index = -1
while True:
    ok, frame = cap.read()
    if not ok:
        break
    frame_index += 1
    timestamp = frame_index / fps
    if timestamp < ignore_start or timestamp > cutoff_end:
        continue
    viewer = frame[roi_y : roi_y + roi_h, roi_x : roi_x + roi_w]
    gray = cv2.cvtColor(viewer, cv2.COLOR_BGR2GRAY)
    if previous_gray is not None and previous_frame_index is not None:
        diff = cv2.absdiff(previous_gray, gray)
        mean_diff = float(diff.mean())
        p95_diff = float(np.percentile(diff, 95))
        adjacent = frame_index == previous_frame_index + 1
        hold = adjacent and mean_diff <= mean_threshold and p95_diff <= p95_threshold
        sampled_pairs += 1
        if hold:
            if current_run == 0:
                current_start_frame = frame_index
                current_start_time = timestamp
            current_run += 1
            if current_run > best_run:
                best_run = current_run
                best_start_frame = current_start_frame
                best_end_frame = frame_index
                best_start_time = current_start_time
                best_end_time = timestamp
        else:
            current_run = 0
            current_start_frame = None
            current_start_time = None
    previous_gray = gray
    previous_frame_index = frame_index

if sampled_pairs <= 0:
    raise SystemExit("playback-progress guard could not sample frame pairs in the evaluation window")
if best_run > max_hold_run:
    raise SystemExit(
        "Recorded playback progress guard failed: "
        f"hold/freeze run {best_run} frame(s) from frame {best_start_frame} to {best_end_frame} "
        f"({best_start_time:.3f}-{best_end_time:.3f}s) exceeds limit {max_hold_run}; "
        f"evaluation window {ignore_start:.3f}-{cutoff_end:.3f}s; video={video_path}"
    )
print(
    "Recorded playback progress guard passed: "
    f"max hold/freeze run {best_run} frame(s) <= {max_hold_run}; "
    f"evaluation window {ignore_start:.3f}-{cutoff_end:.3f}s."
)
PY
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
	usage
	exit 2
fi
shift

if [[ "$command_name" == "set-proxy-only" ]]; then
	if [[ $# -gt 0 ]]; then
		fail "set-proxy-only does not accept options"
	fi
	set_fcp_proxy_only
	exit 0
fi

if [[ "$command_name" == "set-optimized-original" ]]; then
	if [[ $# -gt 0 ]]; then
		fail "set-optimized-original does not accept options"
	fi
	set_fcp_viewer_media_playback "Optimized/Original" >/dev/null \
		|| fail "could not set FCP Viewer media playback mode to Optimized/Original"
	printf 'FCP Viewer media playback mode set to: Optimized/Original\n'
	exit 0
fi

if [[ "$command_name" == "set-green-channel" ]]; then
	if [[ $# -gt 0 ]]; then
		fail "set-green-channel does not accept options"
	fi
	set_fcp_green_channel
	exit 0
fi

case_file="$DEFAULT_CASE"
video_path=""
viewer_roi=""
viewer_roi_explicit=0
recording_viewer_roi=""
output_dir=""
assume_current=0
assume_prepared=0
capture_backend="${STABILIZER_E2E_CAPTURE_BACKEND:-screencapture}"
visual_review="${STABILIZER_E2E_VISUAL_REVIEW:-not-reviewed}"
recording_start_epoch=""
recording_end_epoch=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--case)
			case_file="${2:-}"
			[[ -n "$case_file" ]] || fail "--case requires a path"
			shift 2
			;;
		--video)
			video_path="${2:-}"
			[[ -n "$video_path" ]] || fail "--video requires a path"
			shift 2
			;;
		--viewer-roi)
			viewer_roi="${2:-}"
			[[ -n "$viewer_roi" ]] || fail "--viewer-roi requires x,y,w,h"
			viewer_roi_explicit=1
			shift 2
			;;
			--output-dir)
				output_dir="${2:-}"
				[[ -n "$output_dir" ]] || fail "--output-dir requires a path"
				shift 2
				;;
			--capture-backend)
				capture_backend="${2:-}"
				[[ -n "$capture_backend" ]] || fail "--capture-backend requires a backend name"
				shift 2
				;;
			--visual-review)
				visual_review="${2:-}"
				[[ -n "$visual_review" ]] || fail "--visual-review requires passed, failed, or not-reviewed"
				case "$visual_review" in
					passed|failed|not-reviewed) ;;
					*) fail "--visual-review must be passed, failed, or not-reviewed" ;;
				esac
				shift 2
				;;
			--assume-current-fcp-state)
				assume_current=1
				shift
				;;
			--assume-prepared-fcp)
				assume_prepared=1
				shift
				;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "unknown option: $1"
			;;
	esac
done

[[ -f "$case_file" ]] || fail "case file does not exist: $case_file"
case "$visual_review" in
	passed|failed|not-reviewed) ;;
	*) fail "STABILIZER_E2E_VISUAL_REVIEW/--visual-review must be passed, failed, or not-reviewed" ;;
esac

if [[ -z "$viewer_roi" ]]; then
	viewer_roi="$(case_viewer_roi "$case_file")"
fi

if [[ -z "$video_path" ]]; then
	case_id="$(json_value "$case_file" caseId)"
	stamp="$(date +%Y%m%d_%H%M%S)"
	video_path="${ARTIFACT_ROOT}/${case_id}_${stamp}.mov"
fi
if [[ -z "$output_dir" ]]; then
	output_dir="${video_path%.*}"
fi

case "$command_name" in
	prepare)
		prepare_case "$case_file" "$assume_current" "$viewer_roi"
		;;
	assert-prepared)
		viewer_roi="$(viewer_roi_for_current_fcp "$viewer_roi")"
		recording_viewer_roi="$viewer_roi"
		assert_case_prepared "$case_file" "$viewer_roi"
		;;
	capture)
		total_start="$(now_epoch_seconds)"
		capture_start="$(now_epoch_seconds)"
		if capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend" "$assume_prepared"; then
			capture_end="$(now_epoch_seconds)"
			evidence_start="${recording_start_epoch:-$capture_start}"
			evidence_end="${recording_end_epoch:-$capture_end}"
			if assert_proxy_render_evidence "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if assert_no_playback_fallbacks "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if collect_render_component_diagnostics "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if collect_lens_band_source_diagnostics "$case_file" "$video_path" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			progress_viewer_roi="${recording_viewer_roi:-$viewer_roi}"
			if [[ ( "$capture_backend" == "avfoundation-roi" || "$capture_backend" == "screencapturekit-roi" ) && -n "$progress_viewer_roi" ]]; then
				progress_viewer_roi="$(viewer_roi_zero_origin "$progress_viewer_roi")"
			fi
			if assert_recorded_playback_progress "$case_file" "$video_path" "$progress_viewer_roi"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" 0
		else
			status=$?
			capture_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
			exit "$status"
		fi
		;;
	evaluate)
		total_start="$(now_epoch_seconds)"
		evaluation_viewer_roi="$viewer_roi"
		if [[ ( "$capture_backend" == "avfoundation-roi" || "$capture_backend" == "screencapturekit-roi" ) && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_start="$(now_epoch_seconds)"
		if evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir" "$visual_review"; then
			evaluate_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "" "" "$evaluate_start" "$evaluate_end" 0
		else
			status=$?
			evaluate_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "" "" "$evaluate_start" "$evaluate_end" "$status"
			exit "$status"
		fi
		;;
	assert-recording-progress)
		total_start="$(now_epoch_seconds)"
		progress_viewer_roi="$viewer_roi"
		if [[ ( "$capture_backend" == "avfoundation-roi" || "$capture_backend" == "screencapturekit-roi" ) && -n "$progress_viewer_roi" ]]; then
			progress_viewer_roi="$(viewer_roi_zero_origin "$progress_viewer_roi")"
		fi
		if assert_recorded_playback_progress "$case_file" "$video_path" "$progress_viewer_roi"; then
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "" "" "" "" 0
		else
			status=$?
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "" "" "" "" "$status"
			exit "$status"
		fi
		;;
	run)
		total_start="$(now_epoch_seconds)"
		capture_start="$(now_epoch_seconds)"
		if capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend" "$assume_prepared"; then
			capture_end="$(now_epoch_seconds)"
			evidence_start="${recording_start_epoch:-$capture_start}"
			evidence_end="${recording_end_epoch:-$capture_end}"
			if assert_proxy_render_evidence "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if assert_no_playback_fallbacks "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if collect_render_component_diagnostics "$case_file" "$evidence_start" "$evidence_end" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			if collect_lens_band_source_diagnostics "$case_file" "$video_path" "$output_dir"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
			progress_viewer_roi="${recording_viewer_roi:-$viewer_roi}"
			if [[ ( "$capture_backend" == "avfoundation-roi" || "$capture_backend" == "screencapturekit-roi" ) && -n "$progress_viewer_roi" ]]; then
				progress_viewer_roi="$(viewer_roi_zero_origin "$progress_viewer_roi")"
			fi
			if assert_recorded_playback_progress "$case_file" "$video_path" "$progress_viewer_roi"; then
				:
			else
				status=$?
				write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
				exit "$status"
			fi
		else
			status=$?
			capture_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
			exit "$status"
		fi
		evaluation_viewer_roi="${recording_viewer_roi:-$viewer_roi}"
		if [[ ( "$capture_backend" == "avfoundation-roi" || "$capture_backend" == "screencapturekit-roi" ) && -n "$evaluation_viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$evaluation_viewer_roi")"
		fi
		evaluate_start="$(now_epoch_seconds)"
		if evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir" "$visual_review"; then
			evaluate_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "$evaluate_start" "$evaluate_end" 0
		else
			status=$?
			evaluate_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "$evaluate_start" "$evaluate_end" "$status"
			exit "$status"
		fi
		;;
	-h|--help)
		usage
		;;
	*)
		fail "unknown command: $command_name"
		;;
esac
