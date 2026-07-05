#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_SCRIPT="${ROOT_DIR}/scripts/stabilizer_fcp_screen_capture_e2e.sh"
FCP_HELPER="${FCP_HELPER:-/Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript}"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"
P1000307_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json"
P1000304_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000304_ridge_4m23_4m43.json"
DEFAULT_CASE="$P1000307_CASE"

usage() {
	cat <<'USAGE'
Usage: scripts/fcp_e2e_control.sh COMMAND [OPTIONS]

Stable Final Cut Pro control entry points for Tokyo Walking Stabilizer E2E.
This script wraps the existing screen-capture harness and keeps open/quit/recover
operations terminal-first through open(1) and osascript.

Commands:
  status          Print FCP process/front-window state and selected case metadata.
  open-case       Open the case library in Final Cut Pro and wait for a standard window.
  quit            Ask Final Cut Pro to quit through AppleScript and wait for exit.
  recover-case    Quit FCP, reopen the case library, then run harness prepare.
  clear-render-files
                  Move only the selected case Event's Render Files out of the FCP bundle.
  viewer-roi      Print the current FCP Viewer ROI as capture-pixel x,y,w,h.
  proxy-only      Set the current FCP Viewer media playback to Proxy Only.
  warmup-proxy    Warm a black/uninitialized Proxy Only Viewer and reassert recordability.
  patterns        Print canonical fixed-regression command patterns.
  prepare         Open/normalize the case through the existing E2E harness.
  assert-prepared Verify Proxy Only, target project/effect, timecode, and Viewer ROI.
  capture         Capture the FCP Viewer through the existing E2E harness.
  evaluate        Evaluate an existing recording through the existing E2E harness.
  assert-recording-progress
                  Check an existing recording for long playback hold/freeze runs.
  run             Capture and evaluate through the existing E2E harness.

Options:
  --case PATH                  Case JSON. Default: P1000307 turn regression.
  --video PATH                 Recording path for capture/evaluate/run.
  --output-dir PATH            Diagnostics output directory.
  --viewer-roi x,y,w,h         Explicit absolute FCP Viewer ROI in capture pixels.
  --capture-backend NAME       screencapture, avfoundation-roi, or screencapturekit-roi.
                                capture/run/assert-recording-progress default to
                                avfoundation-roi unless
                                STABILIZER_E2E_CAPTURE_BACKEND is set.
  --visual-review STATE        passed, failed, or not-reviewed.
  --clear-render-files         For recover-case, move Event Render Files before reopening.
  --assume-current-fcp-state   Pass through to the E2E harness.
  --assume-prepared-fcp        Pass through to the E2E harness.

Notes:
  - --case accepts full paths and aliases: p1000307, p1000304.
  - Proxy Only is required by the checked-in E2E cases; Proxy Preferred is not accepted.
  - Smoothness acceptance still requires the recorded FCP Preview video, full CSV/PTS
    diagnostics, and explicit visual review.
USAGE
}

fail() {
	printf 'fcp_e2e_control.sh: %s\n' "$*" >&2
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

case_event_name() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(case.get("event") or Path(case["originalMedia"]).parent.parent.name)
PY
}

case_render_files_path() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import sys
from pathlib import Path

case = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
library = Path(case["library"])
event_name = case.get("event") or Path(case["originalMedia"]).parent.parent.name
print(library / event_name / "Render Files")
PY
}

resolve_case_path() {
	local requested="$1"
	case "$requested" in
		p1000307|P1000307|307|turn)
			printf '%s\n' "$P1000307_CASE"
			;;
		p1000304|P1000304|304|ridge)
			printf '%s\n' "$P1000304_CASE"
			;;
		*)
			printf '%s\n' "$requested"
			;;
	esac
}

clear_case_render_files() {
	local library
	local event_name
	local render_files
	local case_id
	local backup_root
	local backup_path
	library="$(json_value "$case_file" library)"
	event_name="$(case_event_name "$case_file")"
	render_files="$(case_render_files_path "$case_file")"
	case_id="$(json_value "$case_file" caseId)"
	backup_root="${STABILIZER_E2E_RENDER_FILES_BACKUP_ROOT:-${ARTIFACT_ROOT}/render_files_backups}"

	[[ -d "$library" ]] || fail "case library does not exist: ${library}"
	if /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		fail "Final Cut Pro is running; quit it before moving Render Files for ${case_id}"
	fi
	if [[ ! -e "$render_files" ]]; then
		printf 'Render Files: already absent for %s (%s)\n' "$case_id" "$render_files"
		return 0
	fi
	[[ -d "$render_files" ]] || fail "Render Files path is not a directory: ${render_files}"
	[[ ! -L "$render_files" ]] || fail "refusing to move symlink Render Files path: ${render_files}"
	case "$render_files" in
		"$library"/*"/Render Files")
			;;
		*)
			fail "refusing to move unexpected Render Files path outside the selected case library: ${render_files}"
			;;
	esac
	[[ "$(basename "$render_files")" == "Render Files" ]] \
		|| fail "refusing to move path whose basename is not Render Files: ${render_files}"

	mkdir -p "$backup_root"
	backup_path="${backup_root}/${case_id}_$(date +%Y%m%d_%H%M%S)_Render Files"
	if [[ -e "$backup_path" ]]; then
		fail "render-files backup path already exists: ${backup_path}"
	fi
	mv "$render_files" "$backup_path"
	printf 'Moved FCP generated Render Files for %s / %s:\n  from: %s\n  to:   %s\n' \
		"$case_id" "$event_name" "$render_files" "$backup_path"
	printf 'Left Transcoded Media and Analysis Files untouched.\n'
}

print_case_run_pattern() {
	local alias="$1"
	local file="$2"
	[[ -f "$file" ]] || fail "case file does not exist for ${alias}: ${file}"
	local case_id
	local project
	local start_timecode
	local end_timecode
	local viewer_roi
	case_id="$(json_value "$file" caseId)"
	project="$(json_value "$file" project)"
	start_timecode="$(json_value "$file" startTimecode)"
	end_timecode="$(json_value "$file" endTimecode)"
	viewer_roi="$(case_viewer_roi "$file")"
	cat <<PATTERN
# ${alias}: ${case_id}
# project: ${project}
# range: ${start_timecode} - ${end_timecode}
# fixed case ROI: ${viewer_roi}
scripts/fcp_e2e_control.sh recover-case --case ${alias}
scripts/fcp_e2e_control.sh warmup-proxy --case ${alias} --assume-current-fcp-state
STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS=3600 STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS=3600 scripts/fcp_e2e_control.sh run --case ${alias} --capture-backend avfoundation-roi --visual-review not-reviewed --assume-current-fcp-state
# Strict replay with the checked-in ROI instead of dynamic Viewer ROI:
STABILIZER_E2E_DYNAMIC_VIEWER_ROI=0 STABILIZER_E2E_PLAYBACK_READY_LOOKBACK_SECONDS=3600 STABILIZER_E2E_PROXY_EVIDENCE_LOOKBACK_SECONDS=3600 scripts/fcp_e2e_control.sh run --case ${alias} --viewer-roi ${viewer_roi} --capture-backend avfoundation-roi --visual-review not-reviewed --assume-current-fcp-state

PATTERN
}

print_patterns() {
	cat <<'PATTERN'
# Canonical Tokyo Walking Stabilizer FCP Preview E2E patterns.
# The wrapper defaults capture/run to avfoundation-roi to preserve 50/59.94fps cadence.
# Keep Proxy Only and crop/Remove Black Edges enabled; do not use Proxy Preferred.

PATTERN
	print_case_run_pattern p1000307 "$P1000307_CASE"
	print_case_run_pattern p1000304 "$P1000304_CASE"
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

require_case_proxy_only() {
	local playback_mode
	playback_mode="$(json_value "$case_file" playbackMode)"
	[[ "$playback_mode" == "Proxy Only" ]] \
		|| fail "case playbackMode must be Proxy Only, got: ${playback_mode}"
}

wait_for_fcp_standard_window() {
	local timeout_seconds="${1:-60}"
	local waited=0
	while (( waited < timeout_seconds * 10 )); do
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

wait_for_fcp_exit() {
	local timeout_seconds="${1:-45}"
	local waited=0
	while (( waited < timeout_seconds * 10 )); do
		if ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
			return 0
		fi
		sleep 0.1
		waited=$((waited + 1))
	done
	return 1
}

open_case_library() {
	local library
	library="$(json_value "$case_file" library)"
	[[ -d "$library" ]] || fail "case library does not exist: ${library}"
	/usr/bin/open -a "Final Cut Pro" "$library"
	while ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; do
		sleep 0.25
	done
	wait_for_fcp_standard_window 60 \
		|| fail "Final Cut Pro standard window did not become readable after opening ${library}"
	printf 'Opened FCP case library: %s\n' "$library"
}

quit_fcp() {
	if ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		printf 'Final Cut Pro: not running\n'
		return 0
	fi
	/usr/bin/osascript <<'APPLESCRIPT'
tell application "Final Cut Pro" to quit
APPLESCRIPT
	wait_for_fcp_exit 45 \
		|| fail "Final Cut Pro did not quit within 45s; close save dialogs or quit it manually before retrying"
	printf 'Final Cut Pro: quit\n'
}

print_status() {
	local library
	local project
	local event_name
	local source_clip
	local start_timecode
	local playback_mode
	library="$(json_value "$case_file" library)"
	project="$(json_value "$case_file" project)"
	event_name="$(case_event_name "$case_file")"
	source_clip="$(json_value "$case_file" sourceClip)"
	start_timecode="$(json_value "$case_file" startTimecode)"
	playback_mode="$(json_value "$case_file" playbackMode)"
	printf 'case: %s\n' "$case_file"
	printf 'library: %s\n' "$library"
	printf 'event: %s\n' "$event_name"
	printf 'project: %s\n' "$project"
	printf 'source: %s\n' "$source_clip"
	printf 'start: %s\n' "$start_timecode"
	printf 'playbackMode: %s\n' "$playback_mode"
	if /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		printf 'Final Cut Pro: running\n'
		if wait_for_fcp_standard_window 1; then
			printf 'FCP standard window: ready\n'
		else
			printf 'FCP standard window: not ready\n'
		fi
		/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
	try
		return "frontmost: " & (name of first application process whose frontmost is true)
	end try
end tell
APPLESCRIPT
	else
		printf 'Final Cut Pro: not running\n'
	fi
}

print_viewer_roi() {
	[[ -f "$FCP_HELPER" ]] || fail "missing FCP helper: ${FCP_HELPER}"
	local bounds_json
	bounds_json="$(/usr/bin/osascript "$FCP_HELPER" viewer-bounds-json)"
	viewer_bounds_points_to_pixel_roi "$bounds_json"
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

run_harness() {
	local command="$1"
	shift
	require_case_proxy_only
	if [[ "$command" == "set-proxy-only" ]]; then
		"$E2E_SCRIPT" "$command" "$@"
		return
	fi
	"$E2E_SCRIPT" "$command" "${harness_args[@]}" "$@"
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
	usage
	exit 2
fi
shift

case_file="$DEFAULT_CASE"
harness_args=()
capture_backend_explicit=0
clear_render_files=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--case)
			case_file="$(resolve_case_path "${2:-}")"
			[[ -n "$case_file" ]] || fail "--case requires a path"
			harness_args+=("--case" "$case_file")
			shift 2
			;;
		--video|--output-dir|--viewer-roi|--capture-backend|--visual-review)
			option="$1"
			value="${2:-}"
			[[ -n "$value" ]] || fail "${option} requires a value"
			harness_args+=("$option" "$value")
			if [[ "$option" == "--capture-backend" ]]; then
				capture_backend_explicit=1
			fi
			shift 2
			;;
		--assume-current-fcp-state|--assume-prepared-fcp)
			harness_args+=("$1")
			shift
			;;
		--clear-render-files)
			clear_render_files=1
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

case_file="$(resolve_case_path "$case_file")"
[[ -f "$case_file" ]] || fail "case file does not exist: ${case_file} (aliases: p1000307, p1000304)"

if [[ "$capture_backend_explicit" == "0" && -z "${STABILIZER_E2E_CAPTURE_BACKEND:-}" ]]; then
	case "$command_name" in
		capture|run|assert-recording-progress)
			harness_args+=("--capture-backend" "avfoundation-roi")
			printf 'Defaulting FCP E2E capture backend to avfoundation-roi for cadence-sensitive Proxy Only video evidence.\n' >&2
			;;
	esac
fi

case "$command_name" in
	status)
		print_status
		;;
	open-case)
		require_case_proxy_only
		open_case_library
		;;
	quit)
		quit_fcp
		;;
	recover-case)
		require_case_proxy_only
		quit_fcp
		if [[ "$clear_render_files" == "1" ]]; then
			clear_case_render_files
		fi
		open_case_library
		run_harness prepare
		;;
	clear-render-files)
		require_case_proxy_only
		clear_case_render_files
		;;
	viewer-roi)
		print_viewer_roi
		;;
	proxy-only)
		run_harness set-proxy-only
		;;
	warmup-proxy)
		run_harness assert-prepared
		;;
	patterns)
		print_patterns
		;;
	prepare|assert-prepared|capture|evaluate|assert-recording-progress|run)
		run_harness "$command_name"
		;;
	-h|--help|help)
		usage
		;;
	*)
		usage >&2
		fail "unknown command: ${command_name}"
		;;
esac
