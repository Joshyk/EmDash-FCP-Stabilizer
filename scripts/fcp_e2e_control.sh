#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E_SCRIPT="${ROOT_DIR}/scripts/stabilizer_fcp_screen_capture_e2e.sh"
SOURCE_QUALITY_SCRIPT="${ROOT_DIR}/tests/stabilizer_source_frame_quality.py"
FCP_HELPER="${FCP_HELPER:-/Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript}"
ARTIFACT_ROOT="${STABILIZER_E2E_ARTIFACT_DIR:-/tmp/stabilizer_e2e}"
P1000307_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_micro_macro_1m44_1m56.json"
P1000307_CROP_ON_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_micro_macro_1m44_1m56_crop_on.json"
P1000307_TURN_CASE="${ROOT_DIR}/tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json"
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
  open-project    Open the case project via helper/menu/keyboard paths, without coordinate clicks.
  quit            Ask Final Cut Pro to quit through AppleScript and wait for exit.
  recover-case    Quit FCP, reopen the case library, then run harness prepare.
  clear-render-files
                  Move only the selected case Event's Render Files out of the FCP bundle.
  viewer-roi      Print the current FCP Viewer ROI as capture-pixel x,y,w,h.
  proxy-only      Set the current FCP Viewer media playback to Proxy Only.
  green-channel   Set the current FCP Viewer channel display to Green.
  warmup-proxy    Warm a black/uninitialized Proxy Only Viewer and reassert recordability.
  patterns        Print canonical fixed-regression command patterns.
  prepare         Open/normalize the case through the existing E2E harness.
  assert-prepared Verify Proxy Only, Green channel, Debug Overlay, target project/effect, timecode, and Viewer ROI.
  capture         Capture the FCP Viewer through the existing E2E harness.
  evaluate        Evaluate an existing recording through the existing E2E harness.
  assert-recording-progress
                  Check an existing recording for long playback hold/freeze runs.
  run             Capture and evaluate through the existing E2E harness.
  export-source-video
                  Export the prepared case range from Final Cut Pro to source/project-resolution video.
  run-source-quality
                  Export the case range, then evaluate the exported video at source resolution.

Options:
  --case PATH                  Case JSON. Default: P1000307 00:01:49 micro/macro regression.
  --video PATH                 Recording path for capture/evaluate/run.
  --output-dir PATH            Diagnostics output directory.
  --viewer-roi x,y,w,h         Explicit absolute FCP Viewer ROI in capture pixels.
  --capture-backend NAME       screencapture, avfoundation-roi, or screencapturekit-roi.
                                capture/run/assert-recording-progress default to
                                avfoundation-roi unless
                                STABILIZER_E2E_CAPTURE_BACKEND is set.
  --visual-review STATE        passed, failed, or not-reviewed.
  --export-output PATH         Output .mov path for export-source-video/run-source-quality.
  --source-quality-output-dir PATH
                               Directory for source-resolution evaluator artifacts.
  --source-visual-review STATE passed, failed, or not-reviewed for exported-video review.
  --clear-render-files         For recover-case, move Event Render Files before reopening.
  --assume-current-fcp-state   Pass through to the E2E harness.
  --assume-prepared-fcp        Pass through to the E2E harness.

Notes:
  - --case accepts full paths and aliases: p1000307, p1000307-crop-on, p1000307-turn, p1000304.
  - Proxy Only, Viewer Green channel, and visible Debug Overlay are required by
    the checked-in E2E cases; Proxy Preferred is not accepted.
  - Smoothness acceptance still requires the recorded FCP Preview video, full CSV/PTS
    diagnostics, and explicit visual review.
  - Source-resolution quality uses an exported FCP movie, not screen-capture pixels.
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

case_source_frame_evaluation_enabled() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    case = json.load(handle)
raise SystemExit(0 if bool(case.get("sourceFrameEvaluation", {}).get("enabled")) else 1)
PY
}

resolve_case_path() {
	local requested="$1"
	case "$requested" in
		p1000307|P1000307|307|micro|micro-macro|p1000307-micro|p1000307_micro)
			printf '%s\n' "$P1000307_CASE"
			;;
		p1000307-crop-on|p1000307_crop_on|307-crop-on|crop-on)
			printf '%s\n' "$P1000307_CROP_ON_CASE"
			;;
		p1000307-turn|p1000307_turn|307-turn|turn)
			printf '%s\n' "$P1000307_TURN_CASE"
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
PATTERN
	if case_source_frame_evaluation_enabled "$file"; then
		cat <<PATTERN
	scripts/fcp_e2e_control.sh run-source-quality --case ${alias} --source-visual-review not-reviewed --assume-current-fcp-state
PATTERN
	fi
	cat <<PATTERN
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
# Keep Proxy Only, Viewer Green channel, and visible Debug Overlay; do not use Proxy Preferred.

PATTERN
	print_case_run_pattern p1000307 "$P1000307_CASE"
	print_case_run_pattern p1000307-crop-on "$P1000307_CROP_ON_CASE"
	print_case_run_pattern p1000307-turn "$P1000307_TURN_CASE"
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

case_timecode_entry() {
	local file="$1"
	local entry_key="$2"
	local timecode_key="$3"
	python3 - "$file" "$entry_key" "$timecode_key" <<'PY'
import json
import re
import sys

path, entry_key, timecode_key = sys.argv[1:4]
with open(path, encoding="utf-8") as handle:
    case = json.load(handle)
value = case.get(entry_key)
if value:
    print(value)
    raise SystemExit(0)
timecode = str(case.get(timecode_key, ""))
digits = re.sub(r"[^0-9]", "", timecode)
if len(digits) < 8:
    raise SystemExit(f"case {timecode_key} could not be converted to timecode entry: {timecode!r}")
print(digits[:8])
PY
}

case_export_output_path() {
	local file="$1"
	python3 - "$file" "$ARTIFACT_ROOT" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

case_path, artifact_root = sys.argv[1:3]
with open(case_path, encoding="utf-8") as handle:
    case = json.load(handle)
case_id = case["caseId"]
run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
print(Path(artifact_root) / case_id / "exports" / f"{case_id}_{run_id}.mov")
PY
}

case_source_quality_output_dir() {
	local file="$1"
	local video_path="$2"
	python3 - "$file" "$video_path" "$ARTIFACT_ROOT" <<'PY'
import json
import sys
from pathlib import Path

case_path, video_path, artifact_root = sys.argv[1:4]
with open(case_path, encoding="utf-8") as handle:
    case = json.load(handle)
case_id = case["caseId"]
print(Path(artifact_root) / case_id / "source_quality" / Path(video_path).stem)
PY
}

fcp_seek_timecode_entry() {
	local timecode_entry="$1"
	timeout 10 /usr/bin/osascript - "$timecode_entry" <<'APPLESCRIPT' >/dev/null
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
}

set_fcp_case_export_range() {
	local start_entry
	local end_entry
	start_entry="$(case_timecode_entry "$case_file" startTimecodeEntry startTimecode)"
	end_entry="$(case_timecode_entry "$case_file" endTimecodeEntry endTimecode)"
	printf 'Setting Final Cut Pro export range: %s -> %s\n' "$start_entry" "$end_entry" >&2
	timeout 8 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		set frontmost to true
		keystroke "2" using {command down}
		delay 0.1
		key code 7 using option down
	end tell
end tell
APPLESCRIPT
	fcp_seek_timecode_entry "$start_entry" \
		|| fail "could not seek Final Cut Pro to export start timecode entry ${start_entry}"
	sleep 0.2
	timeout 4 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events" to tell process "Final Cut Pro" to key code 34
APPLESCRIPT
	fcp_seek_timecode_entry "$end_entry" \
		|| fail "could not seek Final Cut Pro to export end timecode entry ${end_entry}"
	sleep 0.2
	timeout 4 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events" to tell process "Final Cut Pro" to key code 31
APPLESCRIPT
	fcp_seek_timecode_entry "$start_entry" \
		|| fail "could not restore Final Cut Pro playhead to export start timecode entry ${start_entry}"
}

wait_for_export_file() {
	local output_path="$1"
	local timeout_seconds="${2:-900}"
	local waited=0
	local previous_size=-1
	local stable_count=0
	while (( waited < timeout_seconds )); do
		if [[ -f "$output_path" ]]; then
			local size
			size="$(stat -f '%z' "$output_path")"
			if [[ "$size" -gt 0 && "$size" == "$previous_size" ]]; then
				stable_count=$((stable_count + 1))
				if (( stable_count >= 5 )); then
					return 0
				fi
			else
				stable_count=0
			fi
			previous_size="$size"
		elif ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
			printf 'Final Cut Pro exited before export file appeared: %s\n' "$output_path" >&2
			return 1
		fi
		sleep 1
		waited=$((waited + 1))
	done
	return 1
}

press_fcp_export_file_to_path() {
	local output_path="$1"
	local output_dir
	local output_name
	local export_log
	local export_status
	output_dir="$(dirname "$output_path")"
	output_name="$(basename "$output_path")"
	mkdir -p "$output_dir"
	[[ ! -e "$output_path" ]] || fail "refusing to overwrite existing source export: ${output_path}"
	export_log="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-export-ui.XXXXXX")"
	set +e
	timeout 90 /usr/bin/osascript - "$output_dir" "$output_name" >"$export_log" 2>&1 <<'APPLESCRIPT'
on run argv
	set outputDir to item 1 of argv
	set outputName to item 2 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			key code 14 using command down
			set nextButton to my waitForButtonContaining({"Next", "Continue"}, 30)
			if nextButton is missing value then error "Final Cut Pro export/share dialog did not expose a Next button. Visible buttons: " & my buttonSnapshot(12)
			perform action "AXPress" of nextButton
			set saveButton to my waitForButtonContaining({"Save"}, 30)
			if saveButton is missing value then error "Final Cut Pro export save panel did not expose a Save button. Visible buttons: " & my buttonSnapshot(12)
			keystroke "g" using {command down, shift down}
			delay 0.3
			keystroke outputDir
			key code 36
			delay 0.8
			set nameField to my firstWritableTextField(12)
			if nameField is missing value then error "Final Cut Pro export save panel filename field not found"
			set value of nameField to outputName
			delay 0.1
			perform action "AXPress" of saveButton
		end tell
	end tell
	return outputDir & "/" & outputName
end run

on waitForButtonContaining(labels, timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		tell application "System Events"
			tell process "Final Cut Pro"
				set foundButton to my firstButtonContaining(front window, labels, 12)
				if foundButton is not missing value then return foundButton
			end tell
		end tell
		delay 0.2
	end repeat
	return missing value
end waitForButtonContaining

on firstButtonContaining(rootElement, labels, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXButton" then
			set labelText to my elementText(rootElement)
			repeat with targetLabel in labels
				ignoring case
					if labelText contains (targetLabel as text) then return rootElement
				end ignoring
			end repeat
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstButtonContaining(childElement, labels, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstButtonContaining

on buttonSnapshot(remainingDepth)
	set foundButtons to {}
	tell application "System Events"
		tell process "Final Cut Pro"
			try
				set foundButtons to my collectButtons(front window, remainingDepth, {})
			end try
		end tell
	end tell
	return my joinTextList(foundButtons, " | ")
end buttonSnapshot

on collectButtons(rootElement, remainingDepth, foundButtons)
	if remainingDepth < 0 then return foundButtons
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXButton" then
			set buttonText to my elementText(rootElement)
			if buttonText is not "" then set end of foundButtons to buttonText
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return foundButtons
		end try
	end tell
	repeat with childElement in childElements
		set foundButtons to my collectButtons(childElement, remainingDepth - 1, foundButtons)
	end repeat
	return foundButtons
end collectButtons

on firstWritableTextField(remainingDepth)
	tell application "System Events"
		tell process "Final Cut Pro"
			return my firstTextField(front window, remainingDepth)
		end tell
	end tell
end firstWritableTextField

on firstTextField(rootElement, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXTextField" or roleName is "AXTextArea" then return rootElement
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstTextField(childElement, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstTextField

on elementText(candidateElement)
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
		if (labelText as text) is not "" then return labelText as text
	end repeat
	return ""
end elementText

on joinTextList(textItems, separatorText)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to separatorText
	set joinedText to textItems as text
	set AppleScript's text item delimiters to previousDelimiters
	return joinedText
end joinTextList
APPLESCRIPT
	export_status=$?
	set -e
	if [[ "$export_status" != "0" ]]; then
		cat "$export_log" >&2
		rm -f "$export_log"
		return "$export_status"
	fi
	cat "$export_log" >&2
	rm -f "$export_log"
}

prepare_fcp_for_source_export() {
	local assume_prepared="$1"
	local assume_current="$2"
	local project
	project="$(json_value "$case_file" project)"
	if [[ "$assume_prepared" == "1" || "$assume_current" == "1" ]]; then
		wait_for_fcp_standard_window 15 \
			|| fail "Final Cut Pro standard window is not readable for source export"
		fcp_project_visible_by_ax "$project" \
			|| fail "Final Cut Pro project is not visible for source export: ${project}"
		printf 'Verifying current Final Cut Pro project before source export: %s\n' "$project" >&2
		run_harness assert-prepared
		return
	fi
	open_case_project_primary \
		|| fail "could not open Final Cut Pro project for source export without coordinate fallback"
	run_harness assert-prepared
}

export_source_video() {
	local output_path="$1"
	local assume_prepared="$2"
	local assume_current="$3"
	[[ -n "$output_path" ]] || output_path="$(case_export_output_path "$case_file")"
	[[ "$output_path" == *.mov ]] || output_path="${output_path}.mov"
	prepare_fcp_for_source_export "$assume_prepared" "$assume_current"
	set_fcp_case_export_range
	printf 'Starting Final Cut Pro source-resolution export: %s\n' "$output_path" >&2
	press_fcp_export_file_to_path "$output_path" \
		|| fail "Final Cut Pro export UI automation failed before save; no screen-capture fallback will be used"
	wait_for_export_file "$output_path" 900 \
		|| fail "Final Cut Pro export did not produce a stable file within timeout: ${output_path}"
	printf 'Final Cut Pro source export ready: %s\n' "$output_path" >&2
	printf '%s\n' "$output_path"
}

run_source_quality() {
	local video_path="$1"
	local export_output_path="$2"
	local assume_prepared="$3"
	local assume_current="$4"
	local quality_output_dir="$5"
	local source_visual_review="$6"
	if [[ -z "$video_path" ]]; then
		video_path="$(export_source_video "$export_output_path" "$assume_prepared" "$assume_current")"
	fi
	[[ -f "$video_path" ]] || fail "source-quality video does not exist: ${video_path}"
	[[ -n "$quality_output_dir" ]] || quality_output_dir="$(case_source_quality_output_dir "$case_file" "$video_path")"
	python3 "$SOURCE_QUALITY_SCRIPT" \
		--case "$case_file" \
		--video "$video_path" \
		--output-dir "$quality_output_dir" \
		--visual-review "$source_visual_review"
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

handle_case_import_prompts() {
	local library="$1"
	if [[ ! -f "$FCP_HELPER" ]]; then
		printf 'FCP helper unavailable for import-prompt handling: %s\n' "$FCP_HELPER" >&2
		return 1
	fi
	timeout 12 /usr/bin/osascript "$FCP_HELPER" handle-e2e-import-prompts 6 "$library"
}

select_case_event_via_ax() {
	local event_name="$1"
	timeout 12 /usr/bin/osascript - "$event_name" <<'APPLESCRIPT'
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
}

open_case_project_via_helper() {
	local project
	local event_name
	project="$(json_value "$case_file" project)"
	event_name="$(case_event_name "$case_file")"
	if [[ ! -f "$FCP_HELPER" ]]; then
		printf 'FCP helper unavailable for project open: %s\n' "$FCP_HELPER" >&2
		return 1
	fi

	printf 'Primary project open: selecting Event via local AX path: %s\n' "$event_name"
	if ! select_case_event_via_ax "$event_name"; then
		printf 'Primary project open: local AX path could not select Event %s; trying project open in current Browser state.\n' "$event_name" >&2
	fi
	printf 'Primary project open: using helper keyboard search + Clip menu for project: %s\n' "$project"
	timeout 30 /usr/bin/osascript "$FCP_HELPER" open-project "$project"
}

fcp_project_visible_by_ax() {
	local project="$1"
	timeout 15 /usr/bin/osascript - "$project" <<'APPLESCRIPT' >/dev/null
on run argv
	set projectName to item 1 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontWindow to my frontFinalCutProWindow()
			set windowPosition to position of frontWindow
			set windowSize to size of frontWindow
			if my subtreeContainsProjectHeaderText(frontWindow, projectName, 12, windowPosition, windowSize) then return "visible"
		end tell
	end tell
	error "Final Cut Pro project is not visible: " & projectName
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

on subtreeContainsProjectHeaderText(rootElement, requiredText, remainingDepth, windowPosition, windowSize)
	if remainingDepth < 0 then return false
	if my elementContainsText(rootElement, requiredText) and my elementLooksLikeProjectHeader(rootElement, windowPosition, windowSize) then return true
	set childElements to {}
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return false
		end try
	end tell
	repeat with childElement in childElements
		if my subtreeContainsProjectHeaderText(childElement, requiredText, remainingDepth - 1, windowPosition, windowSize) then return true
	end repeat
	return false
end subtreeContainsProjectHeaderText

on elementLooksLikeProjectHeader(candidateElement, windowPosition, windowSize)
	tell application "System Events"
		try
			set roleText to role of candidateElement as text
			if roleText is not "AXStaticText" and roleText is not "AXButton" and roleText is not "AXMenuButton" and roleText is not "AXPopUpButton" and roleText is not "AXGroup" then return false
			set elementPosition to position of candidateElement
			set elementSize to size of candidateElement
			set elementWidth to item 1 of elementSize
			set elementHeight to item 2 of elementSize
			if elementWidth < 20 or elementHeight < 8 then return false
			set centerX to (item 1 of elementPosition) + (elementWidth / 2)
			set centerY to (item 2 of elementPosition) + (elementHeight / 2)
			set relativeCenterX to centerX - (item 1 of windowPosition)
			set relativeCenterY to centerY - (item 2 of windowPosition)
			set windowWidth to item 1 of windowSize
			set windowHeight to item 2 of windowSize
			if relativeCenterX < (windowWidth * 0.30) then return false
			if relativeCenterX > (windowWidth * 0.92) then return false
			if relativeCenterY < 130 then return true
			if relativeCenterY > (windowHeight * 0.50) and relativeCenterY < (windowHeight * 0.88) then return true
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

open_case_project_primary() {
	local library
	local project
	library="$(json_value "$case_file" library)"
	project="$(json_value "$case_file" project)"
	open_case_library
	handle_case_import_prompts "$library" \
		|| printf 'Continuing after import-prompt helper failure; project open will still be verified by prepare.\n' >&2
	wait_for_fcp_standard_window 60 \
		|| fail "Final Cut Pro standard window was not readable before project open"

	if open_case_project_via_helper && fcp_project_visible_by_ax "$project"; then
		return 0
	fi
	printf 'Primary helper project open did not expose the target project; trying selected Browser project open via helper menu path.\n' >&2
	if timeout 12 /usr/bin/osascript "$FCP_HELPER" wait-open-selected-project 3 "$project" && fcp_project_visible_by_ax "$project"; then
		return 0
	fi
	printf 'Primary helper project open failed or did not make the target project visible; no coordinate fallback will run.\n' >&2
	return 1
}

quit_fcp() {
	if ! /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		printf 'Final Cut Pro: not running\n'
		return 0
	fi
	local quit_status=0
	set +e
	timeout 8 /usr/bin/osascript <<'APPLESCRIPT'
tell application "Final Cut Pro" to quit
APPLESCRIPT
	quit_status=$?
	set -e
	if [[ "$quit_status" != "0" && "$quit_status" != "124" ]]; then
		fail "Final Cut Pro quit AppleScript failed with status ${quit_status}"
	fi
	if [[ "$quit_status" == "124" ]]; then
		fail "Final Cut Pro quit AppleScript timed out; check for save/import dialogs before retrying"
	fi
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
	if [[ "$command" == "set-proxy-only" || "$command" == "set-green-channel" ]]; then
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
video_path=""
export_output_path=""
source_quality_output_dir=""
source_visual_review="${STABILIZER_SOURCE_VISUAL_REVIEW:-not-reviewed}"
assume_current_fcp_state=0
assume_prepared_fcp=0

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
			if [[ "$option" == "--video" ]]; then
				video_path="$value"
			fi
			if [[ "$option" == "--capture-backend" ]]; then
				capture_backend_explicit=1
			fi
			shift 2
			;;
		--export-output)
			export_output_path="${2:-}"
			[[ -n "$export_output_path" ]] || fail "--export-output requires a value"
			shift 2
			;;
		--source-quality-output-dir)
			source_quality_output_dir="${2:-}"
			[[ -n "$source_quality_output_dir" ]] || fail "--source-quality-output-dir requires a value"
			shift 2
			;;
		--source-visual-review)
			source_visual_review="${2:-}"
			[[ "$source_visual_review" == "passed" || "$source_visual_review" == "failed" || "$source_visual_review" == "not-reviewed" ]] \
				|| fail "--source-visual-review must be passed, failed, or not-reviewed"
			shift 2
			;;
		--assume-current-fcp-state|--assume-prepared-fcp)
			harness_args+=("$1")
			if [[ "$1" == "--assume-current-fcp-state" ]]; then
				assume_current_fcp_state=1
			fi
			if [[ "$1" == "--assume-prepared-fcp" ]]; then
				assume_prepared_fcp=1
			fi
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
[[ -f "$case_file" ]] || fail "case file does not exist: ${case_file} (aliases: p1000307, p1000307-crop-on, p1000307-turn, p1000304)"

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
	open-project)
		require_case_proxy_only
		open_case_project_primary
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
		if open_case_project_primary; then
			if run_harness prepare --assume-current-fcp-state; then
				exit 0
			fi
			fail "Non-coordinate project open path did not pass prepare verification; refusing coordinate/browser fallback"
		else
			fail "Non-coordinate project open path failed; refusing coordinate/browser fallback"
		fi
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
	green-channel)
		run_harness set-green-channel
		;;
		warmup-proxy)
			run_harness assert-prepared
			;;
		export-source-video)
			export_source_video "$export_output_path" "$assume_prepared_fcp" "$assume_current_fcp_state"
			;;
		run-source-quality)
			run_source_quality "$video_path" "$export_output_path" "$assume_prepared_fcp" "$assume_current_fcp_state" "$source_quality_output_dir" "$source_visual_review"
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
