#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="${SCRIPT_DIR}/StabilizerFeedback.swift"
TURN_TRANSITION_SOURCE="${SCRIPT_DIR}/../Plugin/TurnTransitionPath.swift"
CONFIDENCE_POLICY_SOURCE="${SCRIPT_DIR}/../Plugin/StabilizerConfidencePolicy.swift"
CACHE_ROOT="${TMPDIR:-/tmp}/StabilizerFeedback"
SOURCE_HASH=$(shasum -a 256 "$SOURCE" "$TURN_TRANSITION_SOURCE" "$CONFIDENCE_POLICY_SOURCE" | shasum -a 256 | awk '{print $1}')
BINARY="${CACHE_ROOT}/stabilizer-feedback-${SOURCE_HASH}"

mkdir -p "$CACHE_ROOT"
if [ ! -x "$BINARY" ]; then
	TMP_BINARY="${BINARY}.$$"
	TMP_BUILD_DIR="${CACHE_ROOT}/build-${SOURCE_HASH}.$$"
	rm -f "$TMP_BINARY"
	rm -rf "$TMP_BUILD_DIR"
	mkdir -p "$TMP_BUILD_DIR"
	cp "$SOURCE" "$TMP_BUILD_DIR/main.swift"
	trap 'rm -f "$TMP_BINARY"; rm -rf "$TMP_BUILD_DIR"' EXIT HUP INT TERM
	xcrun swiftc "$TURN_TRANSITION_SOURCE" "$CONFIDENCE_POLICY_SOURCE" "$TMP_BUILD_DIR/main.swift" -o "$TMP_BINARY"
	chmod +x "$TMP_BINARY"
	mv "$TMP_BINARY" "$BINARY"
	rm -rf "$TMP_BUILD_DIR"
	trap - EXIT HUP INT TERM
fi

exec "$BINARY" "$@"
