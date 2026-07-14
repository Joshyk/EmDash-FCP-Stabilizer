#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/TokyoWalkingStabilizerAutoCropScalePolicyTests"

xcrun swiftc \
    "${ROOT_DIR}/fxplug/TokyoWalkingStabilizer/Plugin/AutoCropScalePolicy.swift" \
    "${ROOT_DIR}/tests/AutoCropScalePolicyTests.swift" \
    -o "${OUTPUT}"
"${OUTPUT}"
