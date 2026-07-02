#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"

usage() {
	cat <<'USAGE'
Usage: scripts/stabilizer_fcp_screen_capture_e2e.sh COMMAND [OPTIONS]

Commands:
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
  - Proxy playback and Remove Black Edges / crop are enabled for the reported scenario.
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

candidates = []
for event_name in event_names:
    candidates.append(library / event_name / project / "CurrentVersion.fcpevent")
if library.exists():
    candidates.extend(library.glob(f"*/{project}/CurrentVersion.fcpevent"))

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
end tell
return "none"
APPLESCRIPT
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

normalize_fcp_layout() {
	printf 'Normalizing FCP layout for screen-capture E2E...\n'
	set_fcp_toolbar_checkbox "Show or hide the Browser" 0 >/dev/null
	set_fcp_toolbar_checkbox "Show or hide the Inspector" 1 >/dev/null
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
mean = float(gray.mean())
std = float(gray.std())
edge = int(np.count_nonzero(gray < 4))
edge_ratio = edge / float(max(1, gray.size))
if mean < 6.0:
    raise SystemExit(f"viewer ROI appears black or unloaded: mean={mean:.2f}, std={std:.2f}, screenshot={image_path}")
if std < 3.0:
    raise SystemExit(f"viewer ROI lacks image detail: mean={mean:.2f}, std={std:.2f}, screenshot={image_path}")
if edge_ratio > 0.80:
    raise SystemExit(f"viewer ROI is mostly black: blackRatio={edge_ratio:.3f}, screenshot={image_path}")
print(f"Viewer ROI ready: mean={mean:.2f}, std={std:.2f}, blackRatio={edge_ratio:.3f}, screenshot={image_path}")
PY
}

wait_for_viewer_roi_recordable() {
	local viewer_roi="$1"
	local timecode_entry="$2"
	local last_output=""
	for attempt in $(seq 1 18); do
		if output="$(assert_viewer_roi_recordable "$viewer_roi" 2>&1)"; then
			printf '%s\n' "$output"
			return 0
		fi
		last_output="$output"
		printf 'Viewer ROI is not ready yet (%s/18): %s\n' "$attempt" "$last_output"
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
	library="$(json_value "$case_file" library)"
	project="$(json_value "$case_file" project)"
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
	if "${ROOT_DIR}/scripts/fcp_ui_test.sh" open-project "$project"; then
		:
	else
		printf 'Named Browser project lookup failed; trying the currently selected Browser item for list-view FCP layouts.\n'
		"${ROOT_DIR}/scripts/fcp_ui_test.sh" open-selected-project
	fi
	sleep 1
}

assert_case_prepared() {
	local case_file="$1"
	local viewer_roi="$2"
	local expected_effect
	local remove_black_edges
	local timecode_entry
	expected_effect="$(json_value "$case_file" expectedEffect)"
	remove_black_edges="$(json_bool_value "$case_file" removeBlackEdges)"
	timecode_entry="$(json_value "$case_file" startTimecodeEntry)"

	assert_case_project_contains_effect "$case_file"
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.4
	select_playhead_clip
	sleep 0.4
	assert_inspector_contains_case_effect_if_readable "$expected_effect" "$remove_black_edges"
	wait_for_viewer_roi_recordable "$viewer_roi" "$timecode_entry"
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
	fi
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	printf 'Known screen-blocking dialog state before seek: %s\n' "$blocker_result"
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.6
	preflight_playback_alerts "$timecode_entry"
	press_stop_playback

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
	prepare)
		prepare_case "$case_file" "$assume_current" "$viewer_roi"
		;;
	assert-prepared)
		assert_case_prepared "$case_file" "$viewer_roi"
		;;
	capture)
		capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend" "$assume_prepared"
		;;
	evaluate)
		evaluation_viewer_roi="$viewer_roi"
		if [[ "$capture_backend" == "avfoundation-roi" && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir"
		;;
	run)
		capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend" "$assume_prepared"
		evaluation_viewer_roi="$viewer_roi"
		if [[ "$capture_backend" == "avfoundation-roi" && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir"
		;;
	-h|--help)
		usage
		;;
	*)
		fail "unknown command: $command_name"
		;;
esac
