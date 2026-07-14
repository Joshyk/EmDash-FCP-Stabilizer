#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/StabilizerShaderTypes.h"
METAL = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizerTransform.metal"
SWIFT = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizer.swift"

ROWS = [
    "XOffset",
    "YOffset",
    "Roll",
    "Crop",
    "Turn",
    "StrideWobble",
    "FootstepJitter",
    "FarFieldWarp",
    "Lens",
    "Smoothing",
    "TrackingQuality",
    "WalkingQuality",
    "SharpnessQuality",
    "ResidualQuality",
    "SearchRadiusHeadroomQuality",
    "TurnConfidence",
    "StrideConfidence",
    "FootstepConfidence",
    "WarpConfidence",
    "LensConfidence",
    "Runtime",
]


def fail(message: str) -> None:
    raise SystemExit(f"test_debug_overlay_contract: FAIL: {message}")


header = HEADER.read_text()
metal = METAL.read_text()
swift = SWIFT.read_text()

count_match = re.search(r"#define\s+STABILIZER_DEBUG_OVERLAY_ROW_COUNT\s+(\d+)", header)
if not count_match or int(count_match.group(1)) != len(ROWS):
    fail("shared row count is not 21")

enum_match = re.search(
    r"typedef enum StabilizerDebugOverlayRow \{(?P<body>.*?)\} StabilizerDebugOverlayRow;",
    header,
    re.S,
)
if not enum_match:
    fail("row enum is missing")
enum_rows = re.findall(r"StabilizerDebugOverlayRow(\w+)\s*=\s*\d+", enum_match.group("body"))
if enum_rows != ROWS:
    fail(f"header row order mismatch: {enum_rows}")

label_match = re.search(
    r"static uint debugLabelChar\(.*?\) \{(?P<body>.*?)\n\}",
    metal,
    re.S,
)
if not label_match:
    fail("Metal label switch is missing")
label_rows = re.findall(r"case StabilizerDebugOverlayRow(\w+):", label_match.group("body"))
if label_rows != ROWS:
    fail(f"Metal label order mismatch: {label_rows}")

overlay_match = re.search(
    r"if \(transform->debugOverlay > 0\.5\) \{(?P<body>.*?return outputColor;)",
    metal,
    re.S,
)
if not overlay_match:
    fail("Metal overlay fill switch is missing")
fill_rows = re.findall(r"case StabilizerDebugOverlayRow(\w+): fill", overlay_match.group("body"))
if fill_rows != ROWS:
    fail(f"Metal fill order mismatch: {fill_rows}")

if "Float(STABILIZER_DEBUG_OVERLAY_ROW_COUNT)" not in swift:
    fail("Swift overlay scaling does not use the shared row count")

print("test_debug_overlay_contract: PASS")
