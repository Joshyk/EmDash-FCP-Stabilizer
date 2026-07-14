#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/StabilizerConfidencePolicy.swift"
ESTIMATOR = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/AutoStabilizationEstimator.swift"
PLUGIN = ROOT / "fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizer.swift"
FEEDBACK = ROOT / "fxplug/TokyoWalkingStabilizer/scripts/StabilizerFeedback.swift"
FEEDBACK_RUNNER = ROOT / "fxplug/TokyoWalkingStabilizer/scripts/stabilizer_feedback.sh"
PROJECT = ROOT / "fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj/project.pbxproj"


def fail(message: str) -> None:
    raise SystemExit(f"test_confidence_bias_contract: FAIL: {message}")


policy = POLICY.read_text()
estimator = ESTIMATOR.read_text()
plugin = PLUGIN.read_text()
feedback = FEEDBACK.read_text()
feedback_runner = FEEDBACK_RUNNER.read_text()
project = PROJECT.read_text()

for contract in (
    "guard evidence.isFinite else",
    "return min(1.0, max(0.0, evidence))",
    "static func unbiasedMean",
):
    if contract not in policy:
        fail(f"common unbiased policy is incomplete: {contract}")

if project.count("StabilizerConfidencePolicy.swift") < 3:
    fail("common policy is not registered as a source in the Xcode project")
if "StabilizerConfidencePolicy.swift" not in feedback_runner:
    fail("Feedback CLI does not compile the common policy")

required_estimator_contracts = (
    "StabilizerConfidencePolicy.unbiased(rawMicroXConfidence * microXTurnGate)",
    "StabilizerConfidencePolicy.unbiased(rawMacroJitterXConfidence * macroJitterXTurnGate)",
    "let combinedTurnCorrectionConfidence = StabilizerConfidencePolicy.unbiased(confidence)",
    "StabilizerConfidencePolicy.unbiased(stableWarpConfidence)",
    "private static func turnCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n        StabilizerConfidencePolicy.unbiased(confidence)\n    }",
    "private static func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n        StabilizerConfidencePolicy.unbiased(confidence)\n    }",
)
for contract in required_estimator_contracts:
    if contract not in estimator:
        fail(f"estimator path does not use the common policy: {contract}")

required_feedback_contracts = (
    "StabilizerConfidencePolicy.unbiased(rawMicroQX * microXTurnGate)",
    "StabilizerConfidencePolicy.unbiased(rawMacroQX * macroXTurnGate)",
    "let turnQ = StabilizerConfidencePolicy.unbiased(rawTurnQ)",
    "StabilizerConfidencePolicy.unbiased(stableWarpConfidence)",
    "private func turnCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n    StabilizerConfidencePolicy.unbiased(confidence)\n}",
    "private func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n    StabilizerConfidencePolicy.unbiased(confidence)\n}",
)
for contract in required_feedback_contracts:
    if contract not in feedback:
        fail(f"Feedback CLI path does not use the common policy: {contract}")

for forbidden in (
    "verticalWalkingMediumConfidenceLift",
    "farFieldMacroJitterVerticalConfidenceFloorScale",
    "farFieldMacroJitterRollConfidenceFloorScale",
    "turnOwnedFarFieldWalkingRescueConfidenceFloor",
    "farFieldMicroConfidenceFloor",
    "turnCorrectionConfidence(",
):
    if forbidden in estimator or forbidden in feedback:
        fail(f"legacy confidence bias remains: {forbidden}")

if "debugOverlayMicroJitterConfidence" in plugin:
    fail("Debug Overlay still has a display-only Micro/Camera Rigid maximum")
if "microJitterConfidence: renderedAutoTransform.microConfidence" not in plugin:
    fail("Debug Overlay does not report the final Micro confidence directly")

print("test_confidence_bias_contract: PASS")
