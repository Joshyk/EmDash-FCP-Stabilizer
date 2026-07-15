#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/TokyoWalkingStabilizerAutoCropZoomHandoffTests"

xcrun swiftc \
    "${ROOT_DIR}/fxplug/TokyoWalkingStabilizer/Plugin/AutoCropZoomHandoff.swift" \
    "${ROOT_DIR}/tests/AutoCropZoomHandoffTests.swift" \
    -o "$OUTPUT"
"$OUTPUT"
