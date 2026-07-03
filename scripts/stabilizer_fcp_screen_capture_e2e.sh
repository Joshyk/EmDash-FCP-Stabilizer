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
  --capture-backend NAME       screencapture or avfoundation-roi. Default: screencapture.
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
	project_db="$(case_project_db_path "$case_file")"
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

dismiss_fcp_modal_alerts() {
	/usr/bin/osascript <<'APPLESCRIPT'
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
}

dismiss_known_screen_blockers() {
	/usr/bin/osascript <<'APPLESCRIPT'
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
							click button "OK" of targetWindow
							return "dismissed-" & processName
						end if
					end try
				end repeat
				try
					if frontmost is true then
						set visible to false
						return "hid-" & processName
					end if
				end try
			end tell
		end if
	end repeat
end tell
return "none"
APPLESCRIPT
}

set_viewer_zoom_to_fit() {
	/usr/bin/osascript >/dev/null <<'APPLESCRIPT'
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
}

set_fcp_viewer_media_playback() {
	local playback_mode="$1"
	[[ -n "$playback_mode" ]] || return 0
	/usr/bin/osascript - "$playback_mode" <<'APPLESCRIPT'
on run argv
	set playbackMode to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set targetButton to my firstMenuButtonWithDescription(frontWindow, "View Options Menu Button", 16)
			if targetButton is missing value then error "View Options Menu Button not found"
			click targetButton
			delay 0.7
			try
				click menu item playbackMode of menu 1 of targetButton
			on error directError
				try
					click menu item playbackMode of menu 1
					log "Used process-level Viewer media playback menu fallback for " & playbackMode & ": " & directError
				on error processMenuError
					key code 53
					error "Viewer media playback menu item not found: " & playbackMode & " | direct=" & directError & " | process=" & processMenuError
				end try
			end try
			delay 0.4
			return "set"
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

on firstMenuButtonWithDescription(rootElement, requiredDescription, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			if (role of rootElement as text) is "AXMenuButton" then
				try
					if (description of rootElement as text) contains requiredDescription then return rootElement
				end try
			end if
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstMenuButtonWithDescription(childElement, requiredDescription, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstMenuButtonWithDescription
APPLESCRIPT
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
	/usr/bin/osascript >/dev/null <<'APPLESCRIPT'
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		click menu item "Timeline" of menu 1 of menu item "Go To" of menu "Window" of menu bar 1
	end tell
end tell
APPLESCRIPT
}

set_fcp_toolbar_checkbox() {
	local checkbox_description="$1"
	local desired_value="$2"
	/usr/bin/osascript - "$checkbox_description" "$desired_value" <<'APPLESCRIPT'
on run argv
	set targetDescription to item 1 of argv
	set desiredValue to item 2 of argv as integer
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			repeat with targetWindow in windows
				try
					set toolbarItems to checkboxes of toolbar 1 of targetWindow
					repeat with toolbarItem in toolbarItems
						set itemDescription to ""
						try
							set itemDescription to description of toolbarItem as text
						end try
						if itemDescription contains targetDescription then
							try
								if (value of toolbarItem as integer) is not desiredValue then
									click toolbarItem
									delay 0.3
								end if
								if (value of toolbarItem as integer) is not desiredValue then error "checkbox value did not change"
								return "set"
							on error errText
								error "Found toolbar checkbox " & targetDescription & " but could not set it: " & errText
							end try
						end if
					end repeat
				end try
			end repeat
		end tell
	end tell
	error "Could not find Final Cut Pro toolbar checkbox: " & targetDescription
end run
APPLESCRIPT
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
	printf 'Known screen-blocking dialog state before layout normalize: %s\n' "$blocker_result"
	set_fcp_toolbar_checkbox "Show or hide the Browser" 0 >/dev/null
	set_fcp_toolbar_checkbox "Show or hide the Inspector" 0 >/dev/null
	set_viewer_zoom_to_fit
	focus_timeline
}

select_playhead_clip() {
	"${ROOT_DIR}/scripts/fcp_ui_test.sh" select-playhead-clip
}

assert_inspector_contains_case_effect() {
	local expected_effect="$1"
	local remove_black_edges="$2"
	/usr/bin/osascript - "$expected_effect" "$remove_black_edges" <<'APPLESCRIPT'
on run argv
	set expectedEffect to item 1 of argv
	set requireRemoveBlackEdges to item 2 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to window 1
			set allText to my collectedElementText(frontWindow, 0, 12)
			if allText does not contain expectedEffect then error "Expected effect is not visible in the Final Cut Pro Inspector: " & expectedEffect
			if requireRemoveBlackEdges is "true" and allText does not contain "Remove Black Edges" then error "Remove Black Edges control is not visible in the Final Cut Pro Inspector."
		end tell
	end tell
	return "inspector-ok"
end run

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
	snapshot="$(/usr/bin/osascript - "$project_name" <<'APPLESCRIPT'
on run argv
	set expectedProjectName to ""
	if (count of argv) > 0 then set expectedProjectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set textParts to my collectedElementText(my frontFinalCutProWindow(), 0, 8)
		end tell
	end tell
	return textParts as text
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
	if currentDepth > maxDepth then return {}
	set textParts to {}
	tell application "System Events"
		try
			set elementRole to role of elementRef as text
		on error
			set elementRole to ""
		end try
		try
			set elementName to name of elementRef as text
			if elementName is not "" then set end of textParts to elementName
		end try
		try
			set elementValue to value of elementRef as text
			if elementValue is not "" then set end of textParts to elementValue
		end try
		if elementRole is "AXTextField" or elementRole is "AXStaticText" then
			try
				set elementDescription to description of elementRef as text
				if elementDescription is not "" then set end of textParts to elementDescription
			end try
		end if
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
)"
	if printf '%s\n' "$snapshot" | /usr/bin/grep -qi "Nothing Loaded"; then
		fail "Final Cut Pro Viewer is showing Nothing Loaded; refusing to record a static/unloaded E2E video"
	fi
	if [[ -n "$project_name" ]]; then
		if printf '%s\n' "$snapshot" | /usr/bin/grep -Fq "$project_name"; then
			printf 'FCP UI text includes expected project: %s\n' "$project_name"
		else
			printf 'FCP UI text did not expose expected project name "%s"; continuing after clip/effect assertions.\n' "$project_name"
		fi
	fi
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

wait_for_viewer_roi_recordable() {
	local viewer_roi="$1"
	local timecode_entry="$2"
	local last_output=""
	local proxy_warmup_done=0
	for attempt in $(seq 1 18); do
		dismiss_fcp_modal_alerts >/dev/null
		dismiss_known_screen_blockers >/dev/null
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
	printf 'Known screen-blocking dialog preflight: %s\n' "$dismiss_result"
	sleep 0.2
	press_stop_playback
	seek_timecode "$timecode_entry"
	sleep 0.6
	dismiss_result="$(dismiss_fcp_modal_alerts)"
	printf 'FCP alert state before recording: %s\n' "$dismiss_result"
	dismiss_result="$(dismiss_known_screen_blockers)"
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
	click_point="$(/usr/bin/osascript - "$event_name" <<'APPLESCRIPT'
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
)"
	[[ "$click_point" =~ ^[0-9]+,[0-9]+$ ]] || fail "visible Event sidebar row click point was not usable: $click_point"
	click_screen_point "${click_point%,*}" "${click_point#*,}"
	sleep 0.8
	printf 'selected visible Final Cut Pro Event %s via CGEvent click at %s\n' "$event_name" "$click_point"
}

open_visible_browser_project_by_text() {
	local project_name="$1"
	local open_point
	open_point="$(/usr/bin/osascript - "$project_name" <<'APPLESCRIPT'
on run argv
	set projectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			set frontWindow to my frontFinalCutProWindow()
			set openableElement to my firstRowContainingExactText(frontWindow, projectName, 18)
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
)"
	[[ "$open_point" =~ ^[0-9]+,[0-9]+$ ]] || fail "visible Browser project open point was not usable: $open_point"
	double_click_screen_point "${open_point%,*}" "${open_point#*,}"
	sleep 0.8
	printf 'opened visible Browser project %s via CGEvent double-click at %s\n' "$project_name" "$open_point"
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
	sleep 2
	/usr/bin/osascript /Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript handle-e2e-import-prompts 6 "$library" >/dev/null

	if [[ "$assume_current" == "1" ]]; then
		printf 'Using current FCP project/state for case: %s\n' "$project"
		return
	fi

	set_fcp_toolbar_checkbox "Show or hide the Browser" 1 >/dev/null
	if ! set_fcp_window_checkbox "Show or hide the Libraries sidebar" 1 >/dev/null; then
		printf 'FCP Libraries sidebar toggle was not visible; continuing because Event selection is the authoritative preflight.\n'
	fi
	select_visible_sidebar_event_by_text "$event_name"
	sleep 0.8
	if "${ROOT_DIR}/scripts/fcp_ui_test.sh" open-project "$project"; then
		:
	elif open_visible_browser_project_by_text "$project"; then
		printf 'Opened Final Cut Pro project via visible Browser fallback: %s\n' "$project"
	else
		fail "could not open Final Cut Pro project '${project}' by name; select it in FCP and retry with --assume-current-fcp-state"
	fi
	sleep 1
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
	printf 'Known screen-blocking dialog state during prepare: %s\n' "$blocker_result"
	dismiss_fcp_modal_alerts >/dev/null
	normalize_fcp_layout
	seek_timecode "$timecode_entry"
	sleep 0.8
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
		assert_case_prepared "$case_file" "$viewer_roi"
	else
		open_case_project "$case_file" "$assume_current"
		normalize_fcp_layout
		assert_case_prepared "$case_file" "$viewer_roi"
	fi
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	printf 'Known screen-blocking dialog state before seek: %s\n' "$blocker_result"
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.6
	preflight_playback_alerts "$timecode_entry"
	assert_fcp_viewer_not_nothing_loaded "$(json_value "$case_file" project)"
	if ! assert_viewer_roi_playback_motion "$viewer_roi" "$timecode_entry"; then
		fail "FCP Viewer playback preflight did not show motion; refusing to record a static E2E video"
	fi
	assert_fcp_viewer_not_nothing_loaded "$(json_value "$case_file" project)"
	press_stop_playback
	focus_timeline

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
		*)
			fail "unknown capture backend: $capture_backend"
			;;
	esac
	local capture_pid=$!
	sleep 0.8
	focus_timeline
	press_space
	wait "$capture_pid"
	press_stop_playback

	[[ -s "$video_path" ]] || fail "screen recording was not written: $video_path"
	printf 'Captured: %s\n' "$video_path"
}

evaluate_case() {
	local case_file="$1"
	local video_path="$2"
	local viewer_roi="$3"
	local output_dir="$4"
	[[ -f "$video_path" ]] || fail "video does not exist: $video_path"

	local args=(
		python3
		"${ROOT_DIR}/tests/stabilizer_video_quality.py"
		--case "$case_file"
		--video "$video_path"
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

case_file="$DEFAULT_CASE"
video_path=""
viewer_roi=""
output_dir=""
assume_current=0
assume_prepared=0
capture_backend="${STABILIZER_E2E_CAPTURE_BACKEND:-screencapture}"

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

if [[ -z "$viewer_roi" ]]; then
	viewer_roi="$(case_viewer_roi "$case_file")"
fi

if [[ -z "$video_path" ]]; then
	case_id="$(json_value "$case_file" caseId)"
	stamp="$(date +%Y%m%d_%H%M%S)"
	video_path="${ARTIFACT_ROOT}/${case_id}_${stamp}.mov"
fi

case "$command_name" in
	set-proxy-only)
		set_fcp_proxy_only
		;;
	prepare)
		prepare_case "$case_file" "$assume_current" "$viewer_roi"
		;;
	assert-prepared)
		assert_case_prepared "$case_file" "$viewer_roi"
		;;
	capture)
		total_start="$(now_epoch_seconds)"
		capture_start="$(now_epoch_seconds)"
		if capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend" "$assume_prepared"; then
			capture_end="$(now_epoch_seconds)"
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
		if [[ "$capture_backend" == "avfoundation-roi" && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_start="$(now_epoch_seconds)"
		if evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir"; then
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
		else
			status=$?
			capture_end="$(now_epoch_seconds)"
			write_e2e_benchmark "$output_dir" "$case_file" "$video_path" "$command_name" "$capture_backend" "$total_start" "$capture_start" "$capture_end" "" "" "$status"
			exit "$status"
		fi
		evaluation_viewer_roi="$viewer_roi"
		if [[ "$capture_backend" == "avfoundation-roi" && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_start="$(now_epoch_seconds)"
		if evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir"; then
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
