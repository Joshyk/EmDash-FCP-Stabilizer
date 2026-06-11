#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
FCP_HELPER="${PARENT_DIR}/scripts/fcp_stabilizer_shortcuts.applescript"
TEST_LIBRARY="${PARENT_DIR}/test_fcp_project/test.fcpbundle"
CACHE_ROOT="${TEST_LIBRARY}/test/Analysis Files/StabilizerFxPlugHostAnalysis"
FEEDBACK_TOOL="${ROOT_DIR}/fxplug/StabilizerFxPlug/scripts/stabilizer_feedback.sh"

usage() {
	cat <<'USAGE'
Usage: scripts/fcp_ui_test.sh COMMAND [ARGS]

Codex-friendly Final Cut Pro UI test entry points for the Stabilizer FxPlug.
These commands wrap the shared parent AppleScript helper instead of driving FCP
with free-form pointer control.

Commands:
  env-check                 Verify helper paths and AppleScript compilation.
  open-test-library         Open the shared Final Cut Pro test library.
  focus-inspector           Reveal or focus the Final Cut Pro Inspector.
  dump-front-window         Print the accessible tree for the front FCP window.
  apply-selected            Apply Stabilizer Transform to the selected clip.
  enable-debug              Turn Debug Overlay on for the selected effect.
  disable-debug             Turn Debug Overlay off for the selected effect.
  start-analysis            Press Start Host Analysis for the selected effect.
  analyze-selected          Enable Debug Overlay, then press Start Host Analysis.
  apply-and-analyze-selected
                            Apply the effect, enable Debug Overlay, then start analysis.
                            Use only on a fresh selected clip to avoid duplicate effects.
  clear-browser-search      Clear the visible FCP Browser search field.
  open-selected-project     Open the selected FCP Browser project row/thumbnail.
  open-project NAME         Open the named FCP Browser project in the selected Event.
  select-playhead-clip      Select the timeline clip under the playhead.
  list-caches               List saved Host Analysis cache readiness for the test library.
  feedback-at TIME [NOTE]   Run cache-backed feedback diagnostics at clip-relative TIME.

Expected FCP state:
  - Final Cut Pro is running for UI commands.
  - The target timeline clip is selected before apply/analyze commands.
  - Accessibility permission is granted to the terminal app invoking osascript.
USAGE
}

fail() {
	printf 'fcp_ui_test.sh: %s\n' "$*" >&2
	exit 1
}

require_file() {
	local path="$1"
	[[ -f "$path" ]] || fail "missing required file: $path"
}

require_dir() {
	local path="$1"
	[[ -d "$path" ]] || fail "missing required directory: $path"
}

run_helper() {
	require_file "$FCP_HELPER"
	/usr/bin/osascript "$FCP_HELPER" "$@"
}

env_check() {
	require_file "$FCP_HELPER"
	require_dir "$TEST_LIBRARY"
	require_file "$FEEDBACK_TOOL"
	/usr/bin/osacompile -o /tmp/fcp_stabilizer_shortcuts.codex.scpt "$FCP_HELPER"
	printf 'shared helper: %s\n' "$FCP_HELPER"
	printf 'test library: %s\n' "$TEST_LIBRARY"
	printf 'cache root: %s\n' "$CACHE_ROOT"
	printf 'feedback tool: %s\n' "$FEEDBACK_TOOL"
	if /usr/bin/pgrep -x "Final Cut Pro" >/dev/null; then
		printf 'Final Cut Pro: running\n'
	else
		printf 'Final Cut Pro: not running\n'
	fi
}

open_test_library() {
	require_dir "$TEST_LIBRARY"
	/usr/bin/open "$TEST_LIBRARY"
}

open_project() {
	local project_name="${1:-}"
	[[ -n "$project_name" ]] || fail "open-project requires a project name, for example: scripts/fcp_ui_test.sh open-project 'stab test - gh6'"
	run_helper open-project "$project_name"
}

clear_browser_search() {
	run_helper clear-browser-search
}

apply_selected() {
	run_helper apply
}

enable_debug() {
	run_helper set-debug-overlay on
}

disable_debug() {
	run_helper set-debug-overlay off
}

start_analysis() {
	run_helper start-analysis
}

analyze_selected() {
	run_helper select-playhead-clip
	sleep 0.2
	enable_debug
	sleep 0.2
	run_helper start-analysis
}

apply_and_analyze_selected() {
	apply_selected
	sleep 0.8
	analyze_selected
}

list_caches() {
	require_file "$FEEDBACK_TOOL"
	require_dir "$CACHE_ROOT"
	"$FEEDBACK_TOOL" --list-caches --cache-root "$CACHE_ROOT"
}

feedback_at() {
	local time_value="${1:-}"
	[[ -n "$time_value" ]] || fail "feedback-at requires a clip-relative time, for example: scripts/fcp_ui_test.sh feedback-at 5.0"
	shift || true

	local note="${1:-Codex UI test review note}"
	require_file "$FEEDBACK_TOOL"
	require_dir "$CACHE_ROOT"
	"$FEEDBACK_TOOL" --cache-root "$CACHE_ROOT" --time "$time_value" --note "$note"
}

command_name="${1:-}"
if [[ -z "$command_name" ]]; then
	usage
	exit 2
fi
shift

case "$command_name" in
	env-check)
		env_check
		;;
	open-test-library)
		open_test_library
		;;
	focus-inspector)
		run_helper focus-inspector
		;;
	dump-front-window)
		run_helper dump-front-window
		;;
	apply-selected)
		apply_selected
		;;
	enable-debug)
		enable_debug
		;;
	disable-debug)
		disable_debug
		;;
	start-analysis)
		start_analysis
		;;
	analyze-selected)
		analyze_selected
		;;
	apply-and-analyze-selected)
		apply_and_analyze_selected
		;;
	clear-browser-search)
		clear_browser_search
		;;
	open-selected-project)
		run_helper open-selected-project
		;;
	open-project)
		open_project "$@"
		;;
	select-playhead-clip)
		run_helper select-playhead-clip
		;;
	list-caches)
		list_caches
		;;
	feedback-at)
		feedback_at "$@"
		;;
	-h|--help|help)
		usage
		;;
	*)
		usage >&2
		fail "unknown command: $command_name"
		;;
esac
