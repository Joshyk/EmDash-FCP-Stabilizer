#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/TokyoWalkingStabilizerDebugOverlayDiagnosticsTests"

xcrun swiftc \
    "${ROOT_DIR}/fxplug/TokyoWalkingStabilizer/Plugin/DebugOverlayDiagnostics.swift" \
    "${ROOT_DIR}/tests/DebugOverlayDiagnosticsTests.swift" \
    -o "${OUTPUT}"
"${OUTPUT}"
python3 "${ROOT_DIR}/tests/test_debug_overlay_contract.py"
