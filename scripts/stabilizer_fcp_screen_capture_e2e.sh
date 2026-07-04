#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"

usage() {
	cat <<'USAGE'
Usage: scripts/stabilizer_fcp_screen_capture_e2e.sh COMMAND [OPTIONS]

Commands:
  set-proxy-only
             Set the current FCP Viewer media playback to Proxy Only.
  prepare    Open and normalize FCP UI state for the configured E2E case.
  assert-prepared
             Verify the current FCP UI state is recordable for the case.
  capture    Record the current FCP Viewer playback for the configured E2E case.
  evaluate   Evaluate an existing screen recording.
  run        Capture, then evaluate.

Options:
  --case PATH                  Case JSON. Defaults to P1000307 turn E2E.
  --video PATH                 Capture output or existing recording to evaluate.
  --viewer-roi x,y,w,h         Override absolute FCP Viewer ROI in the screen recording.
  --output-dir PATH            Directory for evaluator diagnostics.
  --capture-backend NAME       screencapture, avfoundation-roi, or screencapturekit-roi. Default: screencapture.
  --visual-review STATE        passed, failed, or not-reviewed. Default: not-reviewed.
  --assume-current-fcp-state   Do not open the project by UI helper; use current FCP state.
  --assume-prepared-fcp        Skip prepare and only verify/capture current FCP state.

Capture prerequisites:
  - FCP has Screen Recording and Accessibility permission for the invoking terminal.
  - The case library can be opened from disk.
  - The target project/clip has Tokyo Walking Stabilizer enabled.
  - FCP Viewer media playback is Proxy Only, and Remove Black Edges / crop are enabled for the reported scenario.
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
		if /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1
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
	local bounds_json
	bounds_json="$(/usr/bin/osascript /Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript viewer-bounds-json)"
	BOUNDS_JSON="$bounds_json" python3 - <<'PY'
import json
import os

try:
    bounds = json.loads(os.environ["BOUNDS_JSON"])
    x = int(round(float(bounds["x"])))
    y = int(round(float(bounds["y"])))
    w = int(round(float(bounds["width"])))
    h = int(round(float(bounds["height"])))
except Exception as exc:
    raise SystemExit(f"could not parse FCP Viewer bounds: {exc}")

if w <= 0 or h <= 0:
    raise SystemExit(f"invalid FCP Viewer bounds: {bounds!r}")
print(f"{x},{y},{w},{h}")
PY
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
	printf 'Using dynamic FCP Viewer ROI: %s\n' "$dynamic_roi" >&2
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
	start_date="$(log_timestamp_from_epoch "$start_epoch" -3)"
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

lines = [
    line.rstrip("\n")
    for line in evidence_path.read_text(encoding="utf-8", errors="replace").splitlines()
    if "Render Host Analysis decision" in line
]
relevant = []
if clip_token:
    relevant.extend(line for line in lines if clip_token in line or source_clip in line)
if frame_count:
    relevant.extend(line for line in lines if f"frames {frame_count}" in line)
relevant = list(dict.fromkeys(relevant))

if not relevant:
    raise SystemExit(
        "Proxy Only evidence missing: no FxPlug render decision matched "
        f"clip={source_clip!r} token={clip_token!r}; log={evidence_path}"
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
	if grep -Eq "Auto Crop playback fallback|Auto Crop playback unavailable|Auto Crop playback plan deferred|Auto Crop playback final framing repair|Playback trajectory fallback|Playback trajectory not ready" "$fallback_path"; then
		fail "Playback fallback/unprepared playback plan occurred during Proxy Only capture; log=$fallback_path"
	fi
	printf 'Playback fallback evidence verified: no Auto Crop or trajectory playback fallback/unprepared log(s).\n'
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
	/usr/bin/osascript <<'APPLESCRIPT' &
tell application "System Events"
	if exists process "loginwindow" then
		tell process "loginwindow"
			repeat with targetWindow in windows
				try
					if exists button "Cancel" of targetWindow then
						click button "Cancel" of targetWindow
						return "dismissed-loginwindow-cancel"
					end if
				end try
			end repeat
		end tell
	end if
	if exists process "osascript" then
		tell process "osascript"
			repeat with targetWindow in windows
				try
					if (name of targetWindow as text) is "Osmo Pocket Concatenate" then
						if exists button "OK" of targetWindow then
							click button "OK" of targetWindow
							return "dismissed-osmo-pocket-concatenate"
						end if
					end if
				end try
			end repeat
		end tell
	end if
	if exists process "Final Cut Pro" then
		tell process "Final Cut Pro"
			repeat with targetWindow in windows
				try
					if (name of targetWindow as text) is "Open Library" then
						if exists button "Cancel" of targetWindow then
							click button "Cancel" of targetWindow
							return "dismissed-fcp-open-library"
						end if
					end if
				end try
			end repeat
		end tell
	end if
	repeat with processName in {"Disk Utility", "Finder", "Blackmagic Disk Speed Test"}
		if exists process (processName as text) then
			tell process (processName as text)
				repeat with targetWindow in windows
					try
						if exists button "OK" of targetWindow then
							return "blocked-" & processName
						end if
						if exists button "Done" of targetWindow then
							return "blocked-" & processName
						end if
					end try
				end repeat
			end tell
		end if
	end repeat
	if exists process "Final Cut Pro" then
		try
			tell application "Final Cut Pro" to activate
			delay 0.2
		end try
	end if
end tell
return "none"
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "dismiss known screen blockers" 30 1
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
		click menu item "Viewer" of menu 1 of menu item "Go To" of menu "Window" of menu bar 1
		delay 0.1
		click menu item "Zoom to Fit" of menu "View" of menu bar 1
	end tell
end tell
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "viewer zoom to fit" 50 1
}

viewer_options_button_point() {
	/usr/bin/osascript -e 'tell application "Final Cut Pro" to activate' >/dev/null 2>&1 || true
	local window_rect
	if ! window_rect="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "Final Cut Pro" to activate
delay 0.2
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		set bestArea to 0
		set bestRect to missing value
		repeat with candidateWindow in windows
			try
				if subrole of candidateWindow is "AXStandardWindow" then
					set windowPosition to position of candidateWindow
					set windowSize to size of candidateWindow
					set windowX to item 1 of windowPosition
					set windowY to item 2 of windowPosition
					set windowWidth to item 1 of windowSize
					set windowHeight to item 2 of windowSize
					set windowArea to windowWidth * windowHeight
					if windowArea > bestArea then
						set bestArea to windowArea
						set bestRect to {windowX, windowY, windowWidth, windowHeight}
					end if
				end if
			end try
		end repeat
		if bestRect is missing value then error "Final Cut Pro standard window not found"
		set windowX to item 1 of bestRect
		set windowY to item 2 of bestRect
		set windowWidth to item 3 of bestRect
		set windowHeight to item 4 of bestRect
		return (windowX as text) & "," & (windowY as text) & "," & (windowWidth as text) & "," & (windowHeight as text)
	end tell
end tell
APPLESCRIPT
)"; then
		return 1
	fi
	WINDOW_RECT="$window_rect" python3 - <<'PY'
import os

values = [int(float(part.strip())) for part in os.environ["WINDOW_RECT"].split(",")]
if len(values) != 4:
    raise SystemExit("invalid Final Cut Pro window rectangle")
window_x, window_y, window_width, _window_height = values

# Final Cut Pro does not expose the Viewer Options popover as a normal AX menu,
# and broad AX tree dumps can hang on the live Viewer. In the standard FCP
# layout used by these E2E cases, the View Options button is fixed relative to
# the main window and sits just above the Viewer. Keep this geometry localized
# to the Proxy Only setup path.
button_x = window_x + int(round(window_width * 0.759))
button_y = window_y + 52
	print(f"{button_x},{button_y}")
PY
}

fcp_viewer_media_playback_menu_offset_y() {
	local playback_mode="$1"
	case "$playback_mode" in
		Optimized/Original)
			printf '232\n'
			;;
		"Proxy Preferred")
			printf '256\n'
			;;
		"Proxy Only")
			printf '280\n'
			;;
		*)
			fail "unsupported FCP Viewer media playback mode: $playback_mode"
			;;
	esac
}

set_fcp_viewer_media_playback() {
	local playback_mode="$1"
	[[ -n "$playback_mode" ]] || return 0
	local button_point
	button_point="$(viewer_options_button_point)" || return 1
	[[ "$button_point" =~ ^[0-9]+,[0-9]+$ ]] || fail "Viewer Options button point was not usable: $button_point"
	local button_x="${button_point%,*}"
	local button_y="${button_point#*,}"
	local row_offset_y
	row_offset_y="$(fcp_viewer_media_playback_menu_offset_y "$playback_mode")"
	local row_y=$((button_y + row_offset_y))
	/usr/bin/osascript -e 'tell application "Final Cut Pro" to activate' \
		-e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
	click_screen_point "$button_x" "$button_y"
	sleep 0.6
	click_screen_point "$button_x" "$row_y"
	sleep 0.4
}

set_fcp_proxy_only() {
	set_fcp_viewer_media_playback "Proxy Only" >/dev/null \
		|| fail "could not set FCP Viewer media playback mode to Proxy Only"
	printf 'FCP Viewer media playback mode set to: Proxy Only\n'
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
	press_stop_playback
	seek_timecode "$timecode_entry"
	sleep 0.4
	printf 'Final Cut Pro Viewer media playback mode restored to: Proxy Only\n'
}

focus_timeline() {
	/usr/bin/osascript >/dev/null <<'APPLESCRIPT' &
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		click menu item "Timeline" of menu 1 of menu item "Go To" of menu "Window" of menu bar 1
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
									click toolbarItemRef
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
					click targetCheckbox
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
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	fail_if_known_screen_blocked "$blocker_result"
	printf 'Known screen-blocking dialog state before layout normalize: %s\n' "$blocker_result"
	set_fcp_toolbar_checkbox "Show or hide the Browser" 0 >/dev/null
	set_fcp_toolbar_checkbox "Show or hide the Inspector" 0 >/dev/null
	set_viewer_zoom_to_fit
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
	/usr/bin/osascript - "$expected_effect" "$remove_black_edges" <<'APPLESCRIPT' &
on run argv
	set expectedEffect to item 1 of argv
	set requireRemoveBlackEdges to item 2 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set allText to my collectedElementText(frontWindow, 0, 12)
			if allText does not contain expectedEffect then error "Expected effect is not visible in the Final Cut Pro Inspector: " & expectedEffect
			if requireRemoveBlackEdges is "true" and allText does not contain "Remove Black Edges" then error "Remove Black Edges control is not visible in the Final Cut Pro Inspector."
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

on collectedElementText(elementRef, currentDepth, maxDepth)
	if currentDepth > maxDepth then return ""
	set textParts to ""
	tell application "System Events"
		try
			set elementName to name of elementRef as text
			if elementName is not "" then set textParts to textParts & linefeed & elementName
		end try
		try
			set elementDescription to description of elementRef as text
			if elementDescription is not "" then set textParts to textParts & linefeed & elementDescription
		end try
		try
			set elementValue to value of elementRef as text
			if elementValue is not "" then set textParts to textParts & linefeed & elementValue
		end try
		try
			set children to UI elements of elementRef
		on error
			return textParts
		end try
	end tell
	repeat with childElement in children
		set textParts to textParts & my collectedElementText(childElement, currentDepth + 1, maxDepth)
	end repeat
	return textParts
end collectedElementText
APPLESCRIPT
	local osascript_pid=$!
	wait_for_ui_osascript "$osascript_pid" "Inspector effect text" 80 0
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

assert_viewer_roi_recordable() {
	local viewer_roi="$1"
	[[ -n "$viewer_roi" ]] || fail "viewer ROI is required for FCP prepare assertion"
	local screenshot_path="${ARTIFACT_ROOT}/fcp_prepare_viewer_$(date +%Y%m%d_%H%M%S).png"
	mkdir -p "$ARTIFACT_ROOT"
	/usr/sbin/screencapture -x "$screenshot_path"
	python3 - "$screenshot_path" "$viewer_roi" <<'PY'
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
if colorful_ratio < 0.02:
    raise SystemExit(
        f"viewer ROI appears checkerboard/uninitialized: colorRatio={colorful_ratio:.3f}, "
        f"mean={mean:.2f}, std={std:.2f}, screenshot={image_path}"
    )
print(
    f"Viewer ROI ready: mean={mean:.2f}, std={std:.2f}, "
    f"blackRatio={edge_ratio:.3f}, colorRatio={colorful_ratio:.3f}, screenshot={image_path}"
)
PY
}

assert_fcp_viewer_not_nothing_loaded() {
	local project_name="${1:-}"
	local snapshot
	local snapshot_file
	local error_file
	snapshot_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer_fcp_ui_snapshot.XXXXXX")"
	error_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer_fcp_ui_snapshot_error.XXXXXX")"
	/usr/bin/osascript - "$project_name" >"$snapshot_file" 2>"$error_file" <<'APPLESCRIPT' &
on run argv
	set expectedProjectName to ""
	if (count of argv) > 0 then set expectedProjectName to item 1 of argv
	with timeout of 2 seconds
		tell application "Final Cut Pro" to activate
		tell application "System Events"
			tell process "Final Cut Pro"
				set frontmost to true
				set frontWindow to my frontFinalCutProWindow()
				set nothingLoadedVisible to my subtreeContainsExactText(frontWindow, "Nothing Loaded", 6)
				set projectVisible to false
				if expectedProjectName is not "" then set projectVisible to my subtreeContainsExactText(frontWindow, expectedProjectName, 6)
			end tell
		end tell
	end timeout
	return "nothingLoaded=" & (nothingLoadedVisible as text) & linefeed & "projectVisible=" & (projectVisible as text)
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
		local error_text=""
		if [[ -s "$error_file" ]]; then
			error_text=": $(tr '\n' ' ' <"$error_file" | cut -c 1-240)"
		fi
		rm -f "$snapshot_file" "$error_file"
		printf 'Final Cut Pro UI snapshot timed out while checking Viewer state%s; continuing after Viewer ROI/playback preflight.\n' "$error_text" >&2
		return 0
	fi
	snapshot="$(cat "$snapshot_file")"
	rm -f "$snapshot_file" "$error_file"
	if printf '%s\n' "$snapshot" | /usr/bin/grep -qi "nothingLoaded=true"; then
		fail "Final Cut Pro Viewer is showing Nothing Loaded; refusing to record a static/unloaded E2E video"
	fi
	if [[ -n "$project_name" ]]; then
		if printf '%s\n' "$snapshot" | /usr/bin/grep -qi "projectVisible=true"; then
			printf 'FCP UI text includes expected project: %s\n' "$project_name"
		else
			printf 'FCP UI text did not expose expected project name "%s"; continuing after clip/effect assertions.\n' "$project_name"
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
		/usr/sbin/screencapture -x "$before_path"
		press_space
		sleep "${STABILIZER_E2E_PLAYBACK_PREFLIGHT_SECONDS:-0.85}"
		/usr/sbin/screencapture -x "$after_path"
		press_stop_playback
		seek_timecode "$timecode_entry"
		focus_timeline
		sleep 0.4
		if python3 - "$before_path" "$after_path" "$viewer_roi" <<'PY'
from pathlib import Path
import os
import sys

import cv2
import numpy as np

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
roi_parts = [int(part) for part in sys.argv[3].split(",")]
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
    raise SystemExit(
        "FCP Viewer did not show playback motion before recording: "
        f"meanAbsDiff={mean_abs:.3f} (<{min_mean:.3f}), "
        f"p95AbsDiff={p95_abs:.3f} (<{min_p95:.3f}), "
        f"before={before_path}, after={after_path}"
    )
print(
    "FCP Viewer playback preflight motion: "
    f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, "
    f"before={before_path}, after={after_path}"
)
PY
		then
			return 0
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
	/usr/sbin/screencapture -x "$before_path"
	sleep "${STABILIZER_E2E_RECORDING_MOTION_GUARD_SECONDS:-0.45}"
	assert_fcp_frontmost "${label} motion guard after screenshot"
	/usr/sbin/screencapture -x "$after_path"
	python3 - "$before_path" "$after_path" "$viewer_roi" "$label" <<'PY'
from pathlib import Path
import os
import sys

import cv2
import numpy as np

before_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
roi_parts = [int(part) for part in sys.argv[3].split(",")]
label = sys.argv[4]
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
    if state["mean"] < 6.0 or state["std"] < 3.0 or state["color"] < 0.02:
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
    raise SystemExit(
        f"{label}: FCP Viewer is not moving while recording: "
        f"meanAbsDiff={mean_abs:.3f} (<{min_mean:.3f}), "
        f"p95AbsDiff={p95_abs:.3f} (<{min_p95:.3f}), before={before_path}, after={after_path}"
    )
print(
    f"FCP Viewer recording motion guard passed: label={label}, "
    f"meanAbsDiff={mean_abs:.3f}, p95AbsDiff={p95_abs:.3f}, before={before_path}, after={after_path}"
)
PY
}

wait_for_viewer_roi_recordable() {
	local viewer_roi="$1"
	local timecode_entry="$2"
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
			press_space
			sleep 0.5
			press_space
		fi
		sleep 1
	done
	fail "viewer ROI did not become recordable after retries: $last_output"
}

preflight_playback_alerts() {
	local timecode_entry="$1"
	printf 'Preflighting FCP playback alerts before recording...\n'
	press_stop_playback
	press_space
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

double_click_screen_point() {
	local point_x="$1"
	local point_y="$2"
	/usr/bin/swift - "$point_x" "$point_y" <<'SWIFT'
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    fputs("double_click_screen_point requires x and y\n", stderr)
    exit(2)
}

let point = CGPoint(x: x, y: y)
func post(_ type: CGEventType, clickCount: Int) {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        fputs("could not create CGEvent\n", stderr)
        exit(2)
    }
    event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
    event.post(tap: .cghidEventTap)
    usleep(60_000)
}

post(.mouseMoved, clickCount: 1)
post(.leftMouseDown, clickCount: 1)
post(.leftMouseUp, clickCount: 1)
usleep(120_000)
post(.leftMouseDown, clickCount: 2)
post(.leftMouseUp, clickCount: 2)
SWIFT
}

click_screen_point() {
	local point_x="$1"
	local point_y="$2"
	/usr/bin/swift - "$point_x" "$point_y" <<'SWIFT'
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    fputs("click_screen_point requires x and y\n", stderr)
    exit(2)
}

let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        fputs("could not create CGEvent\n", stderr)
        exit(2)
    }
    event.post(tap: .cghidEventTap)
    usleep(80_000)
}
SWIFT
}

select_visible_sidebar_event_by_text() {
	local event_name="$1"
	local click_point
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-event-point.XXXXXX")"
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
			set rowPosition to position of eventRow
			set rowSize to size of eventRow
		end tell
	end tell
	return ((item 1 of rowPosition) + 90 as text) & "," & ((item 2 of rowPosition) + ((item 2 of rowSize) div 2) as text)
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
		click_point="$(cat "$output_file")"
		rm -f "$output_file"
		printf 'visible Event sidebar row click point was not usable; continuing to project lookup: %s\n' "$click_point" >&2
		return 1
	fi
	click_point="$(cat "$output_file")"
	rm -f "$output_file"
	if [[ ! "$click_point" =~ ^[0-9]+,[0-9]+$ ]]; then
		printf 'visible Event sidebar row click point was not usable; continuing to project lookup: %s\n' "$click_point" >&2
		return 1
	fi
	click_screen_point "${click_point%,*}" "${click_point#*,}"
	sleep 0.8
	printf 'selected visible Final Cut Pro Event %s via CGEvent click at %s\n' "$event_name" "$click_point"
}

open_visible_browser_project_by_text() {
	local project_name="$1"
	local open_point
	local output_file
	output_file="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-project-point.XXXXXX")"
	/usr/bin/osascript - "$project_name" >"$output_file" 2>&1 <<'APPLESCRIPT' &
on run argv
	set projectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set openableElement to my firstBrowserRowContainingExactText(frontWindow, projectName, 18)
			if openableElement is missing value then error "visible Browser row not found: " & projectName
			try
				set selected of openableElement to true
			end try
			delay 0.15
			set openPoint to my preferredProjectOpenPoint(frontWindow, openableElement)
		end tell
	end tell
	return (item 1 of openPoint as text) & "," & (item 2 of openPoint as text)
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

on preferredProjectOpenPoint(frontWindow, rowElement)
	set filmstripElement to my firstDescendantWithDescription(frontWindow, "Organizer filmstrip view", 18)
	if filmstripElement is not missing value and my hasUsableBounds(filmstripElement) then
		tell application "System Events"
			set elementPosition to position of filmstripElement
			set elementSize to size of filmstripElement
		end tell
		set targetX to (item 1 of elementPosition) + 80
		set targetY to (item 2 of elementPosition) + 96
		if targetX > (item 1 of elementPosition) + (item 1 of elementSize) - 8 then set targetX to (item 1 of elementPosition) + ((item 1 of elementSize) div 2)
		if targetY > (item 2 of elementPosition) + (item 2 of elementSize) - 8 then set targetY to (item 2 of elementPosition) + ((item 2 of elementSize) div 2)
		return {targetX, targetY}
	end if
	tell application "System Events"
		set rowPosition to position of rowElement
		set rowSize to size of rowElement
	end tell
	return {(item 1 of rowPosition) + 80, (item 2 of rowPosition) + ((item 2 of rowSize) div 2)}
end preferredProjectOpenPoint

on firstBrowserRowContainingExactText(rootElement, requiredText, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
	end tell
	if roleName is "AXRow" and my rowAppearsInsideBrowser(rootElement) and my subtreeContainsExactText(rootElement, requiredText, 5) then return rootElement
	set childElements to {}
	tell application "System Events"
		try
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
			if (item 1 of rowSize) < 80 then return false
			return true
		on error
			return false
		end try
	end tell
end rowAppearsInsideBrowser

on firstDescendantWithDescription(rootElement, requiredDescription, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (description of rootElement as text) is requiredDescription then return rootElement
		end try
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstDescendantWithDescription(childElement, requiredDescription, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstDescendantWithDescription

on hasUsableBounds(elementReference)
	tell application "System Events"
		try
			set elementPosition to position of elementReference
			set elementSize to size of elementReference
			if item 1 of elementPosition < 0 then return false
			if item 2 of elementPosition < 0 then return false
			if item 1 of elementSize < 12 then return false
			if item 2 of elementSize < 12 then return false
			return true
		on error
			return false
		end try
	end tell
end hasUsableBounds
APPLESCRIPT
	local osascript_pid=$!
	if ! wait_for_ui_osascript "$osascript_pid" "visible Browser project ${project_name}" 100 0; then
		open_point="$(cat "$output_file")"
		rm -f "$output_file"
		printf 'visible Browser project open point was not usable; trying next fallback: %s\n' "$open_point" >&2
		return 1
	fi
	open_point="$(cat "$output_file")"
	rm -f "$output_file"
	if [[ ! "$open_point" =~ ^[0-9]+,[0-9]+$ ]]; then
		printf 'visible Browser project open point was not usable; trying next fallback: %s\n' "$open_point" >&2
		return 1
	fi
	double_click_screen_point "${open_point%,*}" "${open_point#*,}"
	sleep 0.8
	printf 'opened visible Browser project %s via CGEvent double-click at %s\n' "$project_name" "$open_point"
}

open_known_e2e_project_tile() {
	local project_name="$1"
	local point_x=""
	local point_y="290"
	case "$project_name" in
		"P1000304 Stabilized Review")
			point_x="430"
			;;
		"P1000307 Stabilized Review")
			point_x="825"
			;;
		*)
			return 1
			;;
	esac
	/usr/bin/osascript -e 'tell application "Final Cut Pro" to activate' >/dev/null 2>&1 || true
	sleep 0.4
	double_click_screen_point "$point_x" "$point_y"
	sleep 1.0
	printf 'opened fixed-regression Browser project tile %s via CGEvent double-click at %s,%s\n' "$project_name" "$point_x" "$point_y"
}

assert_fcp_project_visible() {
	local project_name="$1"
	local snapshot
	snapshot="$(/usr/bin/osascript - "$project_name" <<'APPLESCRIPT'
on run argv
	set expectedProjectName to item 1 of argv
	with timeout of 4 seconds
		tell application "Final Cut Pro" to activate
		tell application "System Events"
			tell process "Final Cut Pro"
				set frontmost to true
				set frontWindow to my frontFinalCutProWindow()
				set projectVisible to my subtreeContainsExactText(frontWindow, expectedProjectName, 8)
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
)" || fail "could not inspect Final Cut Pro project name after opening ${project_name}"
	printf '%s\n' "$snapshot" | /usr/bin/grep -qi "projectVisible=true" \
		|| fail "Final Cut Pro did not expose expected project after open: ${project_name} (${snapshot})"
	printf 'FCP UI text includes expected project: %s\n' "$project_name"
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
			click menu item "Timeline" of menu 1 of menu item "Go To" of menu "Window" of menu bar 1
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

	/usr/bin/open -a "Final Cut Pro" "$library"
	while ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; do
		sleep 0.25
	done
	wait_for_fcp_standard_window 500 \
		|| fail "Final Cut Pro standard window did not become readable after opening ${library}"
	sleep 0.5
	/usr/bin/osascript /Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript handle-e2e-import-prompts 6 "$library" >/dev/null &
	local import_prompt_pid=$!
	if ! wait_for_ui_osascript "$import_prompt_pid" "E2E import prompt handling" 90 1; then
		fail "could not complete E2E import prompt handling"
	fi
	wait_for_fcp_standard_window 300 \
		|| fail "Final Cut Pro standard window was not readable after import prompt handling"

	if [[ "$assume_current" == "1" ]]; then
		printf 'Using current FCP project/state for case: %s\n' "$project"
		return
	fi

	if ! set_fcp_toolbar_checkbox "Show or hide the Browser" 1 >/dev/null; then
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
	if timeout 12 "${ROOT_DIR}/scripts/fcp_ui_test.sh" open-project "$project"; then
		:
	elif open_visible_browser_project_by_text "$project"; then
		printf 'Opened Final Cut Pro project via visible Browser fallback: %s\n' "$project"
	elif open_known_e2e_project_tile "$project"; then
		printf 'Opened Final Cut Pro project via fixed-regression tile fallback: %s\n' "$project"
	else
		fail "could not open Final Cut Pro project '${project}' by name; select it in FCP and retry with --assume-current-fcp-state"
	fi
	sleep 1
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
	seek_timecode "$timecode_entry"
	sleep 0.4
	select_playhead_clip
	sleep 0.4
	ensure_selected_timeline_clip_enabled
	sleep 0.4
	assert_inspector_contains_case_effect_if_readable "$expected_effect" "$remove_black_edges"
	wait_for_viewer_roi_recordable "$viewer_roi" "$timecode_entry"
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
	record_seconds="$(python3 - "$duration" <<'PY'
import math
import sys
print(int(math.ceil(float(sys.argv[1]) + 2.0)))
PY
)"

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
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.6
	preflight_playback_alerts "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded_with_proxy_warmup "$(json_value "$case_file" project)" "$timecode_entry"
	if ! assert_viewer_roi_playback_motion "$viewer_roi" "$timecode_entry"; then
		fail "FCP Viewer playback preflight did not show motion; refusing to record a static E2E video"
	fi
	assert_fcp_viewer_not_nothing_loaded_with_proxy_warmup "$(json_value "$case_file" project)" "$timecode_entry"
	press_stop_playback
	focus_timeline
	seek_timecode "$timecode_entry"
	focus_timeline
	sleep 0.2
	assert_fcp_frontmost "before starting E2E recording playback"

	printf 'Recording FCP Viewer E2E case %s for %ss via %s: %s\n' "$case_id" "$record_seconds" "$capture_backend" "$video_path"
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
			"$ffmpeg_bin" -y -hide_banner \
				-f avfoundation \
				-framerate 60 \
				-capture_cursor 0 \
				-pixel_format bgr0 \
				-i "1:none" \
				-t "$record_seconds" \
				-vf "crop=${crop_w}:${crop_h}:${crop_x}:${crop_y}" \
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
	press_space
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
