#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/StabilizerShaderTypes.h"
METAL = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizerTransform.metal"
SWIFT = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizer.swift"
ESTIMATOR = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/AutoStabilizationEstimator.swift"
E2E = ROOT / "scripts/stabilizer_fcp_screen_capture_e2e.sh"

ROWS = [
    "XOffset",
    "YOffset",
    "Roll",
    "Crop",
    "Turn",
    "MacroJitter",
    "MicroJitter",
    "FarFieldWarp",
    "Smoothing",
    "TrackingQuality",
    "WalkingQuality",
    "SharpnessQuality",
    "ResidualQuality",
    "SearchRadiusHeadroomQuality",
    "TurnConfidence",
    "MacroConfidence",
    "MicroConfidence",
    "WarpConfidence",
    "Runtime",
]

LABELS = [
    "X OFFSET",
    "Y OFFSET",
    "ROLL",
    "CROP",
    "TURN",
    "MACRO JITTER",
    "MICRO JITTER",
    "FAR WARP",
    "SMOOTHING",
    "TRACKING",
    "WALKING",
    "SHARPNESS",
    "RESIDUAL",
    "SEARCH HEADROOM",
    "TURN CONFIDENCE",
    "MACRO CONFIDENCE",
    "MICRO CONFIDENCE",
    "WARP CONFIDENCE",
    "RUNTIME",
]


def fail(message: str) -> None:
    raise SystemExit(f"test_debug_overlay_contract: FAIL: {message}")


header = HEADER.read_text()
metal = METAL.read_text()
swift = SWIFT.read_text()
estimator = ESTIMATOR.read_text()
e2e = E2E.read_text()

count_match = re.search(r"#define\s+STABILIZER_DEBUG_OVERLAY_ROW_COUNT\s+(\d+)", header)
if not count_match or int(count_match.group(1)) != len(ROWS):
    fail("shared row count is not 19")

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
for label in LABELS[:-1]:
    if f"// {label}" not in metal:
        fail(f"Metal readable label is missing: {label}")

for row, expected_label in zip(ROWS[:-1], LABELS[:-1]):
    encoded_match = re.search(
        rf"case StabilizerDebugOverlayRow{row}:\s*"
        rf"return debugLabelCharAt\(index, (?P<encoded>.*?)\);",
        label_match.group("body"),
        re.S,
    )
    if not encoded_match:
        fail(f"Metal encoded label is missing: {row}")
    code_points = [
        int(value)
        for value in re.findall(r"\b\d+\b", encoded_match.group("encoded"))
    ]
    decoded_label = "".join(" " if value == 0 else chr(value) for value in code_points).rstrip()
    if decoded_label != expected_label:
        fail(
            f"Metal encoded label mismatch for {row}: "
            f"expected {expected_label!r}, found {decoded_label!r}"
        )

if "vector_float4(1.0, 2.0, 2.0, 1_009.0)" not in swift:
    fail("Swift runtime version components do not encode version 1.2.2")
if "patch >= 10 ? debugDigitChar(patch / 10)" not in metal:
    fail("Metal runtime label does not suppress patch-version leading zeroes")
if "// PROXY" not in metal or "// ORIGINAL" not in metal:
    fail("Metal runtime label does not use readable source names")
if "if (index >= 20)" not in metal or "labelWidth = 160.0 * overlayScale" not in metal:
    fail("Metal label layout does not support full readable names")

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

prepared_component_contract = [
    "microPixelOffset: microPixelOffset,",
    "macroJitterPixelOffset: macroJitterPixelOffset,",
    "effectiveMacroJitterStrength: vector_float3(",
    "macroJitterConfidence: playbackMacroJitterConfidence,",
]
for contract in prepared_component_contract:
    if contract not in estimator:
        fail(f"prepared Micro/Macro separation is missing: {contract}")
if "max(playbackMicroConfidence, playbackMacroJitterConfidence)" in estimator:
    fail("prepared Macro confidence is still folded into Micro confidence")

e2e_labels_match = re.search(r"labels = \[(?P<body>.*?)\n\]", e2e, re.S)
if not e2e_labels_match:
    fail("E2E label contract is missing")
e2e_labels = re.findall(r'\s+"([A-Z /]+)",', e2e_labels_match.group("body"))
if e2e_labels != LABELS:
    fail(f"E2E label order mismatch: {e2e_labels}")
if "row_count = float(len(labels))" not in e2e:
    fail("E2E overlay sizing does not derive its row count from labels")

print("test_debug_overlay_contract: PASS")
