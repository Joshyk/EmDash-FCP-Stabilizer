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
  --skip-source-diagnostic-videos
                               Write source-resolution CSV/JSON metrics only; skip slow overlay videos.
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
	# fixed ROI note: current MacBook Air Retina display is 1440 × 900; re-measure after display scaling changes.
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

assert_case_project_contains_effect() {
	local project_db
	local expected_effect
	local remove_black_edges
	if ! project_db="$(case_project_db_path "$case_file")"; then
		fail "could not resolve a unique Final Cut Pro project database for case: ${case_file}"
	fi
	[[ -n "$project_db" ]] || fail "resolved Final Cut Pro project database path was empty for case: ${case_file}"
	[[ -f "$project_db" ]] || fail "resolved Final Cut Pro project database is not a file: ${project_db}"
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

set_fcp_source_export_media_playback_original() {
	"$E2E_SCRIPT" set-optimized-original >&2 \
		|| fail "could not set Final Cut Pro Viewer media playback mode to Optimized/Original before source-resolution export; refusing proxy export"
	printf 'Final Cut Pro Viewer media playback mode set for source export: Optimized/Original\n' >&2
}

wait_for_export_file() {
	local output_path="$1"
	local timeout_seconds="${2:-900}"
	local min_duration_seconds="${3:-0.1}"
	local waited=0
	local previous_size=-1
	local stable_count=0
	while (( waited < timeout_seconds )); do
		if [[ -f "$output_path" ]]; then
			local size
			size="$(stat -f '%z' "$output_path")"
			if [[ "$size" -gt 0 && "$size" == "$previous_size" ]]; then
				stable_count=$((stable_count + 1))
				if (( stable_count >= 3 )) && export_video_probe_ok "$output_path" "$min_duration_seconds"; then
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

export_video_probe_ok() {
	local output_path="$1"
	local min_duration_seconds="${2:-0.1}"
	python3 - "$output_path" "$min_duration_seconds" <<'PY' >/dev/null 2>&1
import json
import math
import subprocess
import sys

path = sys.argv[1]
min_duration = float(sys.argv[2])
probe = subprocess.run(
    [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height,nb_frames,r_frame_rate,duration:format=duration",
        "-of",
        "json",
        path,
    ],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
data = json.loads(probe.stdout)
streams = data.get("streams") or []
if not streams:
    raise SystemExit("no video stream")
stream = streams[0]
width = int(stream.get("width") or 0)
height = int(stream.get("height") or 0)
if width <= 0 or height <= 0:
    raise SystemExit("invalid dimensions")

duration_text = (data.get("format") or {}).get("duration") or stream.get("duration") or "0"
duration = float(duration_text)
if duration + 0.05 < min_duration:
    raise SystemExit(f"duration {duration:.3f} below {min_duration:.3f}")

rate_text = stream.get("r_frame_rate") or "0/1"
try:
    numerator, denominator = rate_text.split("/", 1)
    fps = float(numerator) / float(denominator)
except Exception:
    fps = 0.0
nb_frames_text = stream.get("nb_frames") or "0"
try:
    nb_frames = int(nb_frames_text)
except ValueError:
    nb_frames = 0
if fps > 0 and nb_frames > 0:
    min_frames = max(1, int(math.floor(min_duration * fps * 0.95)))
    if nb_frames < min_frames:
        raise SystemExit(f"frames {nb_frames} below {min_frames}")
PY
}

case_export_min_duration_seconds() {
	local file="$1"
	python3 - "$file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    case = json.load(handle)
duration = float(case.get("durationSeconds") or 0.0)
print(f"{max(0.1, duration - 0.25):.3f}")
PY
}

press_fcp_export_file_to_path() {
	local output_path="$1"
	local output_dir
	local output_name
	local output_base_name
	local export_log
	local export_status
	output_dir="$(dirname "$output_path")"
	output_name="$(basename "$output_path")"
	output_base_name="${output_name%.mov}"
	mkdir -p "$output_dir"
	[[ ! -e "$output_path" ]] || fail "refusing to overwrite existing source export: ${output_path}"
	export_log="$(mktemp "${TMPDIR:-/tmp}/stabilizer-fcp-export-ui.XXXXXX")"
	set +e
	timeout 90 /usr/bin/osascript - "$output_dir" "$output_name" "$output_base_name" >"$export_log" 2>&1 <<'APPLESCRIPT'
on run argv
	set outputDir to item 1 of argv
	set outputName to item 2 of argv
	set outputBaseName to item 3 of argv
	tell application "Final Cut Pro" to activate
	tell application "System Events"
		tell process "Final Cut Pro"
			set frontmost to true
			key code 14 using command down
			set exportWindow to my waitForExportFileWindow(30)
			if exportWindow is missing value then error "Final Cut Pro Export File window did not appear. Windows: " & my windowSnapshot()
			set proxyAlert to my proxyMediaAlertDescription(8)
			if proxyAlert is not "" then error "Final Cut Pro proxy media alert appeared before source export save sheet; refusing Continue/proxy export. " & proxyAlert
			set nextButton to my directExportWindowButton(exportWindow, {"Next…", "Next", "Next..."})
			if nextButton is missing value then error "Final Cut Pro Export File window did not expose a direct Next button. " & my buttonSnapshotForElement("Export File window", exportWindow, 6)
			perform action "AXPress" of nextButton
			set saveSheet to my waitForExportSaveSheet(exportWindow, 30)
			if saveSheet is missing value then error "Final Cut Pro Export File Save sheet did not appear after pressing Next. " & my buttonSnapshotForElement("Export File window", exportWindow, 8) & " || " & my sheetButtonSnapshot(exportWindow, 8)
			set saveButton to my directSaveSheetButton(saveSheet, {"Save"})
			if saveButton is missing value then set saveButton to my exactButtonFromList(saveSheet, {"Save"}, 8)
			if saveButton is missing value then error "Final Cut Pro Export File Save sheet did not expose Save. " & my buttonSnapshotForElement("Export File Save sheet", saveSheet, 8)
			set nameField to my filenameFieldInSaveSheet(saveSheet, 10)
			if nameField is missing value then error "Final Cut Pro Export File Save sheet filename field not found. " & my textFieldSnapshotForElement("Export File Save sheet", saveSheet, 10)
			try
				set focused of nameField to true
				set value of nameField to outputBaseName
			on error errMsg
				error "Final Cut Pro Export File Save sheet filename field could not be set through AXValue: " & errMsg
			end try
			delay 0.1
			if my elementValueText(nameField) is not outputBaseName then error "Final Cut Pro Export File Save sheet filename did not update to " & outputBaseName & ". " & my textFieldSnapshotForElement("Export File Save sheet", saveSheet, 10)
			my submitExportSave(saveSheet, saveButton)
		end tell
	end tell
	return outputDir & "/" & outputName
end run

on waitForExportFileWindow(timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		tell application "System Events"
			tell process "Final Cut Pro"
				repeat with candidateWindow in windows
					if my elementTextEquals(candidateWindow, "Export File") then return candidateWindow
				end repeat
			end tell
		end tell
		delay 0.2
	end repeat
	return missing value
end waitForExportFileWindow

on directExportWindowButton(exportWindow, buttonTitles)
	tell application "System Events"
		repeat with buttonTitle in buttonTitles
			try
				return button (buttonTitle as text) of exportWindow
			end try
		end repeat
	end tell
	return missing value
end directExportWindowButton

on directSaveSheetButton(saveSheet, buttonTitles)
	tell application "System Events"
		repeat with buttonTitle in buttonTitles
			try
				return button (buttonTitle as text) of UI element 1 of saveSheet
			end try
			try
				return button (buttonTitle as text) of saveSheet
			end try
		end repeat
	end tell
	return missing value
end directSaveSheetButton

on waitForExportSaveSheet(exportWindow, timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		set proxyAlert to my proxyMediaAlertDescription(8)
		if proxyAlert is not "" then error "Final Cut Pro proxy media alert appeared during source export; refusing Continue/proxy export. " & proxyAlert
		set candidateSheet to my firstElementWithRole(exportWindow, "AXSheet", 10)
		if candidateSheet is not missing value then
			if my exactButtonFromList(candidateSheet, {"Save"}, 8) is not missing value then return candidateSheet
		end if
		delay 0.2
	end repeat
	return missing value
end waitForExportSaveSheet

on proxyMediaAlertDescription(remainingDepth)
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				try
					repeat with candidateSheet in sheets of candidateWindow
						set sheetText to my elementTreeText(candidateSheet, remainingDepth, {})
						if my looksLikeProxyMediaAlert(candidateSheet, sheetText, remainingDepth) then return my truncatedText(sheetText)
					end repeat
				end try
				try
					set windowSubrole to ""
					try
						set windowSubrole to subrole of candidateWindow as text
					end try
					if windowSubrole is not "AXStandardWindow" and not my elementTextEquals(candidateWindow, "Export File") then
						set windowText to my elementTreeText(candidateWindow, remainingDepth, {})
						if my looksLikeProxyMediaAlert(candidateWindow, windowText, remainingDepth) then return my truncatedText(windowText)
					end if
				end try
			end repeat
		end tell
	end tell
	return ""
end proxyMediaAlertDescription

on looksLikeProxyMediaAlert(candidateElement, candidateText, remainingDepth)
	if not my textContainsIgnoringCase(candidateText, "proxy") then return false
	if not my textContainsIgnoringCase(candidateText, "media") then return false
	if my exactButtonFromList(candidateElement, {"Continue", "Continue…", "Continue..."}, remainingDepth) is missing value then return false
	return true
end looksLikeProxyMediaAlert

on textContainsIgnoringCase(haystackText, needleText)
	ignoring case
		if haystackText contains needleText then return true
	end ignoring
	return false
end textContainsIgnoringCase

on elementTreeText(rootElement, remainingDepth, foundTexts)
	if remainingDepth < 0 then return my joinTextList(foundTexts, " | ")
	set elementLabel to my elementText(rootElement)
	if elementLabel is not "" then set end of foundTexts to elementLabel
	tell application "System Events"
		try
			set childElements to UI elements of rootElement
		on error
			return my joinTextList(foundTexts, " | ")
		end try
	end tell
	repeat with childElement in childElements
		set childText to my elementTreeText(childElement, remainingDepth - 1, {})
		if childText is not "" then set end of foundTexts to childText
	end repeat
	return my joinTextList(foundTexts, " | ")
end elementTreeText

on truncatedText(valueText)
	if (length of valueText) > 500 then return (text 1 thru 500 of valueText) & "..."
	return valueText
end truncatedText

on submitExportSave(saveSheet, saveButton)
	tell application "System Events"
		try
			with timeout of 3 seconds
				perform action "AXPress" of saveButton
			end timeout
			log "Submitted Export File Save sheet through AXPress."
			return
		on error pressError
			log "Export File Save AXPress did not return cleanly; continuing only after trying explicit keyboard submit. Error: " & pressError
		end try
		delay 0.2
		try
			click saveButton
			log "Submitted Export File Save sheet through AppleScript element click after AXPress timeout."
			return
		on error clickError
			log "Export File Save element click failed after AXPress timeout: " & clickError
		end try
		try
			set focused of saveSheet to true
		end try
		key code 36
		log "Submitted Export File Save sheet through Return key after AXPress/click did not complete."
	end tell
end submitExportSave

on exactButtonFromList(rootElement, buttonTitles, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXButton" then
			repeat with buttonTitle in buttonTitles
				if my elementTextEquals(rootElement, buttonTitle as text) then return rootElement
			end repeat
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my exactButtonFromList(childElement, buttonTitles, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end exactButtonFromList

on filenameFieldInSaveSheet(saveSheet, remainingDepth)
	tell application "System Events"
		try
			set directField to UI element 11 of UI element 1 of saveSheet
			if (role of directField as text) is "AXTextField" then
				log "Export File Save sheet filename field resolved by direct AX path."
				return directField
			end if
		end try
		try
			log "Export File Save sheet filename field resolved by direct Save As: AX lookup."
			return text field "Save As:" of saveSheet
		end try
	end tell
	set focusedFields to my collectFocusedTextFields(saveSheet, remainingDepth, {})
	if (count of focusedFields) is 1 then
		log "Export File Save sheet filename field resolved by focused text field; direct Save As: AX lookup was unavailable."
		return item 1 of focusedFields
	end if
	set textFields to my collectTextFields(saveSheet, remainingDepth, {})
	if (count of textFields) is 1 then
		log "Export File Save sheet filename field resolved by sole sheet text field; direct Save As: AX lookup was unavailable."
		return item 1 of textFields
	end if
	return missing value
end filenameFieldInSaveSheet

on collectFocusedTextFields(rootElement, remainingDepth, foundFields)
	if remainingDepth < 0 then return foundFields
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXTextField" or roleName is "AXTextArea" then
			try
				if focused of rootElement then set end of foundFields to rootElement
			end try
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return foundFields
		end try
	end tell
	repeat with childElement in childElements
		set foundFields to my collectFocusedTextFields(childElement, remainingDepth - 1, foundFields)
	end repeat
	return foundFields
end collectFocusedTextFields

on collectTextFields(rootElement, remainingDepth, foundFields)
	if remainingDepth < 0 then return foundFields
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXTextField" or roleName is "AXTextArea" then set end of foundFields to rootElement
		try
			set childElements to UI elements of rootElement
		on error
			return foundFields
		end try
	end tell
	repeat with childElement in childElements
		set foundFields to my collectTextFields(childElement, remainingDepth - 1, foundFields)
	end repeat
	return foundFields
end collectTextFields

on windowSnapshot()
	set foundWindows to {}
	tell application "System Events"
		tell process "Final Cut Pro"
			repeat with candidateWindow in windows
				set windowText to my elementText(candidateWindow)
				if windowText is "" then set windowText to "<untitled>"
				set end of foundWindows to windowText
			end repeat
		end tell
	end tell
	if (count of foundWindows) is 0 then return "none"
	return my joinTextList(foundWindows, " | ")
end windowSnapshot

on sheetButtonSnapshot(exportWindow, remainingDepth)
	set snapshots to {}
	set candidateSheet to my firstElementWithRole(exportWindow, "AXSheet", remainingDepth)
	if candidateSheet is missing value then return "Export File sheets: none"
	set end of snapshots to my buttonSnapshotForElement("Export File sheet", candidateSheet, remainingDepth)
	return my joinTextList(snapshots, " || ")
end sheetButtonSnapshot

on buttonSnapshotForElement(rootLabel, rootElement, remainingDepth)
	set foundButtons to my collectButtons(rootElement, remainingDepth, {})
	if (count of foundButtons) is 0 then return rootLabel & " buttons: none"
	return rootLabel & " buttons: " & my joinTextList(foundButtons, " | ")
end buttonSnapshotForElement

on textFieldSnapshotForElement(rootLabel, rootElement, remainingDepth)
	set foundFields to my collectTextFieldDescriptions(rootElement, remainingDepth, {})
	if (count of foundFields) is 0 then return rootLabel & " text fields: none"
	return rootLabel & " text fields: " & my joinTextList(foundFields, " | ")
end textFieldSnapshotForElement

on collectTextFieldDescriptions(rootElement, remainingDepth, foundFields)
	if remainingDepth < 0 then return foundFields
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXTextField" or roleName is "AXTextArea" then set end of foundFields to my textFieldDescription(rootElement)
		try
			set childElements to UI elements of rootElement
		on error
			return foundFields
		end try
	end tell
	repeat with childElement in childElements
		set foundFields to my collectTextFieldDescriptions(childElement, remainingDepth - 1, foundFields)
	end repeat
	return foundFields
end collectTextFieldDescriptions

on textFieldDescription(candidateElement)
	set fieldName to my elementText(candidateElement)
	set fieldValue to my elementValueText(candidateElement)
	if fieldName is "" then set fieldName to "<unnamed>"
	return "name=" & fieldName & ", value=" & fieldValue
end textFieldDescription

on waitForButtonContaining(labels, timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		tell application "System Events"
			tell process "Final Cut Pro"
				set directButton to my firstDirectButtonNamed(labels)
				if directButton is not missing value then return directButton
				repeat with candidateWindow in windows
					set foundButton to my firstButtonContaining(candidateWindow, labels, 14)
					if foundButton is not missing value then return foundButton
					try
						repeat with candidateSheet in sheets of candidateWindow
							set foundButton to my firstButtonContaining(candidateSheet, labels, 14)
							if foundButton is not missing value then return foundButton
						end repeat
					end try
				end repeat
			end tell
		end tell
		delay 0.2
	end repeat
	return missing value
end waitForButtonContaining

on waitForExactWindowButton(buttonTitles, timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		tell application "System Events"
			tell process "Final Cut Pro"
				repeat with candidateWindow in windows
					repeat with buttonTitle in buttonTitles
						try
							return button (buttonTitle as text) of candidateWindow
						end try
					end repeat
					set foundButton to my firstExactButtonFromList(candidateWindow, buttonTitles, 4)
					if foundButton is not missing value then return foundButton
				end repeat
			end tell
		end tell
		delay 0.2
	end repeat
	return missing value
end waitForExactWindowButton

on waitForExactSheetButton(buttonTitle, timeoutSeconds)
	repeat with attempt from 1 to (timeoutSeconds * 5)
		tell application "System Events"
			tell process "Final Cut Pro"
				repeat with candidateWindow in windows
					set candidateSheet to my firstElementWithRole(candidateWindow, "AXSheet", 8)
					if candidateSheet is not missing value then
						set foundButton to my firstExactButton(candidateSheet, buttonTitle, 8)
						if foundButton is not missing value then return foundButton
					end if
				end repeat
			end tell
		end tell
		delay 0.2
	end repeat
	return missing value
end waitForExactSheetButton

on firstElementWithRole(rootElement, requiredRole, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is requiredRole then return rootElement
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstElementWithRole(childElement, requiredRole, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstElementWithRole

on firstExactButtonFromList(rootElement, buttonTitles, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXButton" then
			repeat with buttonTitle in buttonTitles
				if my elementTextEquals(rootElement, buttonTitle as text) then return rootElement
			end repeat
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstExactButtonFromList(childElement, buttonTitles, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstExactButtonFromList

on firstExactButton(rootElement, buttonTitle, remainingDepth)
	if remainingDepth < 0 then return missing value
	tell application "System Events"
		try
			set roleName to role of rootElement as text
		on error
			set roleName to ""
		end try
		if roleName is "AXButton" then
			if my elementTextEquals(rootElement, buttonTitle) then return rootElement
		end if
		try
			set childElements to UI elements of rootElement
		on error
			return missing value
		end try
	end tell
	repeat with childElement in childElements
		set foundElement to my firstExactButton(childElement, buttonTitle, remainingDepth - 1)
		if foundElement is not missing value then return foundElement
	end repeat
	return missing value
end firstExactButton

on firstDirectButtonNamed(labels)
	tell application "System Events"
		tell process "Final Cut Pro"
			set exactLabels to {}
			repeat with targetLabel in labels
				set labelText to targetLabel as text
				set end of exactLabels to labelText
				set end of exactLabels to (labelText & "…")
				set end of exactLabels to (labelText & "...")
			end repeat
			repeat with candidateWindow in windows
				repeat with exactLabel in exactLabels
					try
						return button (exactLabel as text) of candidateWindow
					end try
				end repeat
				try
					repeat with candidateSheet in sheets of candidateWindow
						repeat with exactLabel in exactLabels
							try
								return button (exactLabel as text) of candidateSheet
							end try
						end repeat
					end repeat
				end try
			end repeat
		end tell
	end tell
	return missing value
end firstDirectButtonNamed

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
			repeat with candidateWindow in windows
				try
					set foundButtons to my collectButtons(candidateWindow, remainingDepth, foundButtons)
				end try
				try
					repeat with candidateSheet in sheets of candidateWindow
						set foundButtons to my collectButtons(candidateSheet, remainingDepth, foundButtons)
					end repeat
				end try
			end repeat
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
			repeat with candidateWindow in windows
				set candidateSheet to my firstElementWithRole(candidateWindow, "AXSheet", 8)
				if candidateSheet is not missing value then
					set foundField to my firstTextField(candidateSheet, remainingDepth)
					if foundField is not missing value then return foundField
				end if
				set foundField to my firstTextField(candidateWindow, remainingDepth)
				if foundField is not missing value then return foundField
			end repeat
		end tell
	end tell
	return missing value
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

on elementValueText(candidateElement)
	tell application "System Events"
		try
			return value of candidateElement as text
		end try
	end tell
	return ""
end elementValueText

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

set_fcp_source_export_overlays_off() {
	local remove_black_edges
	remove_black_edges="$(json_value "$case_file" removeBlackEdges | tr '[:upper:]' '[:lower:]')"
	STABILIZER_SOURCE_REMOVE_BLACK_EDGES="$remove_black_edges" swift - <<'SWIFT' \
		|| fail "could not normalize Remove Black Edges, Debug Overlay, and Mesh Overlay before source-resolution export"
import AppKit
import ApplicationServices
import Foundation

func copyAttr(_ element: AXUIElement, _ attr: String) -> AnyObject? {
    var value: AnyObject?
    let status = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return status == .success ? value : nil
}

func textAttr(_ element: AXUIElement, _ attr: String) -> String {
    guard let value = copyAttr(element, attr) else {
        return ""
    }
    return String(describing: value)
}

func combinedText(_ element: AXUIElement) -> String {
    [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
        .map { textAttr(element, $0) }
        .joined(separator: " ")
}

func die(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(2)
}

func boolValue(_ element: AXUIElement) -> Bool {
    let raw = textAttr(element, kAXValueAttribute).lowercased()
    return raw == "1" || raw == "true"
}

@discardableResult
func press(_ element: AXUIElement, label: String) -> Bool {
    let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if status != .success {
        fputs("AXPress failed for \(label): \(status.rawValue)\n", stderr)
        return false
    }
    return true
}

func descendants(of root: AXUIElement, maxDepth: Int = 14) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    while !queue.isEmpty && result.count < 8_000 {
        let (element, depth) = queue.removeFirst()
        result.append(element)
        guard depth < maxDepth,
              let children = copyAttr(element, kAXChildrenAttribute) as? [AXUIElement]
        else {
            continue
        }
        for child in children {
            queue.append((child, depth + 1))
        }
    }
    return result
}

func waitForElement(root: AXUIElement, timeout: TimeInterval, predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let match = descendants(of: root).first(where: predicate) {
            return match
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
}

func waitForMenuItem(root: AXUIElement, named target: String, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for element in descendants(of: root, maxDepth: 16) {
            guard textAttr(element, kAXRoleAttribute) == "AXMenuItem" else {
                continue
            }
            if combinedText(element).localizedCaseInsensitiveContains(target) {
                return element
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
}

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FinalCut")
guard let app = apps.first else {
    die("Final Cut Pro is not running")
}
app.activate()
Thread.sleep(forTimeInterval: 0.15)
let root = AXUIElementCreateApplication(app.processIdentifier)

if let inspectorToggle = waitForElement(root: root, timeout: 3.0, predicate: {
    textAttr($0, kAXRoleAttribute) == "AXCheckBox"
        && combinedText($0).localizedCaseInsensitiveContains("show or hide the inspector")
}) {
    if !boolValue(inspectorToggle) {
        guard press(inspectorToggle, label: "Show or hide the Inspector") else {
            die("could not show Final Cut Pro Inspector")
        }
        Thread.sleep(forTimeInterval: 0.35)
    }
} else {
    die("Final Cut Pro Inspector toolbar toggle not found")
}

let desiredCropText = ProcessInfo.processInfo.environment["STABILIZER_SOURCE_REMOVE_BLACK_EDGES"] ?? "false"
let desiredCrop = desiredCropText == "true" || desiredCropText == "1" || desiredCropText == "yes"
guard let crop = waitForElement(root: root, timeout: 4.0, predicate: {
    textAttr($0, kAXRoleAttribute) == "AXCheckBox"
        && combinedText($0).localizedCaseInsensitiveContains("remove black edges check box")
}) else {
    die("Remove Black Edges checkbox not found")
}
if boolValue(crop) != desiredCrop {
    guard press(crop, label: "Remove Black Edges") else {
        die("press Remove Black Edges failed")
    }
    Thread.sleep(forTimeInterval: 0.25)
}
print("Remove Black Edges set \(desiredCrop ? "On" : "Off")")

guard let debug = waitForElement(root: root, timeout: 4.0, predicate: {
    textAttr($0, kAXRoleAttribute) == "AXCheckBox"
        && combinedText($0).localizedCaseInsensitiveContains("debug overlay check box")
}) else {
    die("Debug Overlay checkbox not found")
}
if boolValue(debug) {
    guard press(debug, label: "Debug Overlay") else {
        die("press Debug Overlay failed")
    }
    Thread.sleep(forTimeInterval: 0.25)
    print("Debug Overlay set Off")
} else {
    print("Debug Overlay already Off")
}

guard let mesh = waitForElement(root: root, timeout: 4.0, predicate: {
    textAttr($0, kAXRoleAttribute) == "AXPopUpButton"
        && combinedText($0).localizedCaseInsensitiveContains("mesh overlay pop up")
}) else {
    die("Mesh Overlay pop-up not found")
}
let currentMesh = textAttr(mesh, kAXValueAttribute)
if !currentMesh.localizedCaseInsensitiveContains("Off") {
    guard press(mesh, label: "Mesh Overlay pop-up") else {
        die("press Mesh Overlay pop-up failed")
    }
    Thread.sleep(forTimeInterval: 0.2)
    guard let offItem = waitForMenuItem(root: root, named: "Off", timeout: 3.0) else {
        die("Mesh Overlay Off menu item not found")
    }
    guard press(offItem, label: "Mesh Overlay Off") else {
        die("press Mesh Overlay Off failed")
    }
    Thread.sleep(forTimeInterval: 0.3)
    print("Mesh Overlay set Off from \(currentMesh)")
} else {
    print("Mesh Overlay already Off")
}
SWIFT
	printf 'Source export controls set to: Remove Black Edges %s, Debug Overlay off, Mesh Overlay Off\n' "$remove_black_edges" >&2
}

select_source_export_timeline_clip() {
	local start_entry
	start_entry="$(case_timecode_entry "$case_file" startTimecodeEntry startTimecode)"
	fcp_seek_timecode_entry "$start_entry" \
		|| fail "could not seek Final Cut Pro to source export start timecode entry ${start_entry}"
	sleep 0.4
	"${ROOT_DIR}/scripts/fcp_ui_test.sh" select-playhead-clip \
		|| fail "could not select the source export timeline clip at ${start_entry}"
	sleep 0.4
}

prepare_fcp_for_source_export() {
	local assume_prepared="$1"
	local assume_current="$2"
	local project
	project="$(json_value "$case_file" project)"
	assert_case_project_contains_effect
	if [[ "$assume_prepared" == "1" || "$assume_current" == "1" ]]; then
		wait_for_fcp_standard_window 15 \
			|| fail "Final Cut Pro standard window is not readable for source export"
		printf 'Using current Final Cut Pro state for source export; forcing Optimized/Original before Export File while preserving Proxy Only for screen-capture E2E: %s\n' "$project" >&2
		select_source_export_timeline_clip
		set_fcp_source_export_overlays_off
		set_fcp_source_export_media_playback_original
		return
	fi
	open_case_project_primary 1 \
		|| fail "could not open Final Cut Pro project for source export without coordinate fallback"
	printf 'Opened Final Cut Pro project for source export; forcing Optimized/Original before Export File while preserving Proxy Only for screen-capture E2E: %s\n' "$project" >&2
	select_source_export_timeline_clip
	set_fcp_source_export_overlays_off
	set_fcp_source_export_media_playback_original
}

export_source_video() {
	local output_path="$1"
	local assume_prepared="$2"
	local assume_current="$3"
	local output_dir
	local output_name
	local staged_output_path
	local min_duration_seconds
	[[ -n "$output_path" ]] || output_path="$(case_export_output_path "$case_file")"
	[[ "$output_path" == *.mov ]] || output_path="${output_path}.mov"
	output_dir="$(dirname "$output_path")"
	output_name="$(basename "$output_path")"
	staged_output_path="${ARTIFACT_ROOT}/${output_name}"
	min_duration_seconds="$(case_export_min_duration_seconds "$case_file")"
	prepare_fcp_for_source_export "$assume_prepared" "$assume_current"
	set_fcp_case_export_range
	printf 'Starting Final Cut Pro source-resolution export: %s\n' "$output_path" >&2
	if [[ "$staged_output_path" != "$output_path" && -e "$staged_output_path" ]]; then
		fail "refusing to overwrite existing staged source export: ${staged_output_path}"
	fi
	press_fcp_export_file_to_path "$output_path" \
		|| fail "Final Cut Pro export UI automation failed before save; no screen-capture fallback will be used"
	if wait_for_export_file "$output_path" 8 "$min_duration_seconds"; then
		:
	elif [[ "$staged_output_path" != "$output_path" ]] && wait_for_export_file "$staged_output_path" 900 "$min_duration_seconds"; then
		mkdir -p "$output_dir"
		mv "$staged_output_path" "$output_path"
		printf 'Moved staged Final Cut Pro source export into requested path:\n  from: %s\n  to:   %s\n' \
			"$staged_output_path" "$output_path" >&2
	else
		fail "Final Cut Pro export did not produce a stable file within timeout: ${output_path}"
	fi
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
	local skip_diagnostic_videos="$7"
	local source_quality_args=()
	if [[ -z "$video_path" ]]; then
		video_path="$(export_source_video "$export_output_path" "$assume_prepared" "$assume_current" | tail -n 1)"
	fi
	[[ -f "$video_path" ]] || fail "source-quality video does not exist: ${video_path}"
	[[ -n "$quality_output_dir" ]] || quality_output_dir="$(case_source_quality_output_dir "$case_file" "$video_path")"
	if [[ "$skip_diagnostic_videos" == "1" ]]; then
		source_quality_args+=("--skip-diagnostic-videos")
	fi
	python3 "$SOURCE_QUALITY_SCRIPT" \
		--case "$case_file" \
		--video "$video_path" \
		--output-dir "$quality_output_dir" \
		--visual-review "$source_visual_review" \
		"${source_quality_args[@]}"
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

open_case_project_via_browser_group_ax() {
	local project="$1"
	local open_status
	set +e
	PROJECT_NAME="$project" swift - <<'SWIFT'
import AppKit
import ApplicationServices
import Foundation

func copyAttr(_ element: AXUIElement, _ attr: String) -> AnyObject? {
    var value: AnyObject?
    let status = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return status == .success ? value : nil
}

func textAttr(_ element: AXUIElement, _ attr: String) -> String {
    guard let value = copyAttr(element, attr) else {
        return ""
    }
    return String(describing: value)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    copyAttr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func die(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(2)
}

let project = ProcessInfo.processInfo.environment["PROJECT_NAME"] ?? ""
if project.isEmpty {
    die("PROJECT_NAME is empty")
}
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FinalCut")
guard let app = apps.first else {
    die("Final Cut Pro is not running")
}
app.activate()
Thread.sleep(forTimeInterval: 0.2)
let root = AXUIElementCreateApplication(app.processIdentifier)
var queue: [(AXUIElement, Int)] = [(root, 0)]
var match: AXUIElement?
while !queue.isEmpty {
    let (element, depth) = queue.removeFirst()
    if textAttr(element, kAXRoleAttribute) == "AXGroup",
       textAttr(element, kAXDescriptionAttribute) == project {
        match = element
        break
    }
    if depth < 14 {
        for child in children(of: element) {
            queue.append((child, depth + 1))
        }
    }
}
guard let projectElement = match else {
    die("Could not find visible Browser project group named \(project)")
}
let selected: AnyObject = kCFBooleanTrue
AXUIElementSetAttributeValue(projectElement, kAXSelectedAttribute as CFString, selected)
AXUIElementSetAttributeValue(projectElement, kAXFocusedAttribute as CFString, selected)
let pressStatus = AXUIElementPerformAction(projectElement, kAXPressAction as CFString)
if pressStatus != .success {
    die("AXPress failed for visible Browser project group \(project): \(pressStatus.rawValue)")
}
Thread.sleep(forTimeInterval: 0.3)
print("Selected visible Browser project group \(project)")
SWIFT
	open_status=$?
	set -e
	if [[ "$open_status" != "0" ]]; then
		return "$open_status"
	fi
	timeout 8 /usr/bin/osascript <<'APPLESCRIPT' >/dev/null
tell application "Final Cut Pro" to activate
tell application "System Events"
	tell process "Final Cut Pro"
		click menu item "Open Clip" of menu "Clip" of menu bar 1
	end tell
end tell
APPLESCRIPT
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
	local forbid_harness_prepare="${1:-0}"
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
	printf 'Selected Browser helper did not expose the target project; trying direct visible Browser project group AX path.\n' >&2
	if open_case_project_via_browser_group_ax "$project" && fcp_project_visible_by_ax "$project"; then
		return 0
	fi
	if [[ "$forbid_harness_prepare" == "1" ]]; then
		printf 'Selected Browser helper did not expose the target project; source export refuses screen-capture harness prepare fallback.\n' >&2
		return 1
	fi
	printf 'Selected Browser helper did not expose the target project; trying screen-capture harness AX/menu prepare path without coordinate fallback.\n' >&2
	if run_harness prepare; then
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
skip_source_diagnostic_videos=0
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
		--skip-source-diagnostic-videos)
			skip_source_diagnostic_videos=1
			shift
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
			run_source_quality "$video_path" "$export_output_path" "$assume_prepared_fcp" "$assume_current_fcp_state" "$source_quality_output_dir" "$source_visual_review" "$skip_source_diagnostic_videos"
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
