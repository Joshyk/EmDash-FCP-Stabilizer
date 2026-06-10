#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE="${SCRIPT_DIR}/StabilizerFeedback.swift"
CACHE_ROOT="${TMPDIR:-/tmp}/StabilizerFeedback"
SOURCE_HASH=$(shasum -a 256 "$SOURCE" | awk '{print $1}')
BINARY="${CACHE_ROOT}/stabilizer-feedback-${SOURCE_HASH}"

mkdir -p "$CACHE_ROOT"
if [ ! -x "$BINARY" ]; then
	xcrun swiftc "$SOURCE" -o "$BINARY"
fi

exec "$BINARY" "$@"
