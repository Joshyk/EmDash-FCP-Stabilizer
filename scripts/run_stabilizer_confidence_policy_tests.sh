#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT="${TMPDIR:-/tmp}/TokyoWalkingStabilizerConfidencePolicyTests"

xcrun swiftc \
    "${ROOT_DIR}/fxplug/TokyoWalkingStabilizer/Plugin/StabilizerConfidencePolicy.swift" \
    "${ROOT_DIR}/tests/StabilizerConfidencePolicyTests.swift" \
    -o "$OUTPUT"
"$OUTPUT"
