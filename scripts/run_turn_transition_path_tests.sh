#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/TokyoWalkingStabilizerTurnTransitionPathTests"

xcrun swiftc \
    "${ROOT_DIR}/fxplug/TokyoWalkingStabilizer/Plugin/TurnTransitionPath.swift" \
    "${ROOT_DIR}/tests/TurnTransitionPathTests.swift" \
    -o "${OUTPUT}"
"${OUTPUT}"
