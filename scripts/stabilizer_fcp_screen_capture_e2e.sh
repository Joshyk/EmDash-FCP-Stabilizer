#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"

usage() {
	cat <<'USAGE'
Usage: scripts/stabilizer_fcp_screen_capture_e2e.sh COMMAND [OPTIONS]

Commands:
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
	/usr/bin/osascript <<'APPLESCRIPT'
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		key code 49
	end tell
end tell
APPLESCRIPT
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

preflight_playback_alerts() {
	local timecode_entry="$1"
	printf 'Preflighting FCP playback alerts before recording...\n'
	press_space
	sleep 1.2
	local dismiss_result
	dismiss_result="$(dismiss_fcp_modal_alerts)"
	printf 'FCP playback alert preflight: %s\n' "$dismiss_result"
	dismiss_result="$(dismiss_known_screen_blockers)"
	printf 'Known screen-blocking dialog preflight: %s\n' "$dismiss_result"
	sleep 0.2
	press_space
	seek_timecode "$timecode_entry"
	sleep 0.6
	dismiss_result="$(dismiss_fcp_modal_alerts)"
	printf 'FCP alert state before recording: %s\n' "$dismiss_result"
	dismiss_result="$(dismiss_known_screen_blockers)"
	printf 'Known screen-blocking dialog state before recording: %s\n' "$dismiss_result"
}

seek_timecode() {
	local timecode_entry="$1"
	/usr/bin/osascript - "$timecode_entry" <<'APPLESCRIPT'
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

	if [[ "$assume_current" == "1" ]]; then
		printf 'Using current FCP project/state for case: %s\n' "$project"
		return
	fi

	"${ROOT_DIR}/scripts/fcp_ui_test.sh" open-project "$project"
	sleep 1
}

capture_case() {
	local case_file="$1"
	local video_path="$2"
	local assume_current="$3"
	local viewer_roi="$4"
	local capture_backend="$5"
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
	open_case_project "$case_file" "$assume_current"
	local blocker_result
	blocker_result="$(dismiss_known_screen_blockers)"
	printf 'Known screen-blocking dialog state before seek: %s\n' "$blocker_result"
	focus_timeline
	seek_timecode "$timecode_entry"
	sleep 0.6
	preflight_playback_alerts "$timecode_entry"

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
	press_space

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

if [[ -z "$video_path" ]]; then
	case_id="$(json_value "$case_file" caseId)"
	stamp="$(date +%Y%m%d_%H%M%S)"
	video_path="${ARTIFACT_ROOT}/${case_id}_${stamp}.mov"
fi

case "$command_name" in
	capture)
		capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend"
		;;
	evaluate)
		evaluation_viewer_roi="$viewer_roi"
		if [[ "$capture_backend" == "avfoundation-roi" && -n "$viewer_roi" ]]; then
			evaluation_viewer_roi="$(viewer_roi_zero_origin "$viewer_roi")"
		fi
		evaluate_case "$case_file" "$video_path" "$evaluation_viewer_roi" "$output_dir"
		;;
	run)
		capture_case "$case_file" "$video_path" "$assume_current" "$viewer_roi" "$capture_backend"
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
