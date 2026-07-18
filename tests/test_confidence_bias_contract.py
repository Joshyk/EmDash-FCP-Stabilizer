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
    "var microJitterX: Double { cameraJitterX.isFinite ? max(cameraJitterX, 0.0) : 0.0 }",
    "StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(strengths.microJitterX)",
    "StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(strengths.macroJitterX)",
    "let combinedTurnCorrectionConfidence = StabilizerConfidencePolicy.unbiased(confidence)",
    "StabilizerConfidencePolicy.unbiased(stableWarpConfidence)",
    "private static func turnCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n        StabilizerConfidencePolicy.unbiased(confidence)\n    }",
    "private static func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {\n        StabilizerConfidencePolicy.unbiased(confidence)\n    }",
    "StabilizerTurnTransitionPath.overlayUnrestrictedHighFrequencyX(",
    "let finalPosition = concatenatedTurn.positions[index]",
    "StabilizerConfidencePolicy.trackedXOutlierDecision(",
    "private static let playbackTrajectoryAlgorithmRevision: UInt64 = 105",
    "limited.macroPixelOffset = playbackTrajectoryXUnrestrictedLimitedYVector(",
    "limited.lensShakePixelOffset = playbackTrajectoryXUnrestrictedLimitedYVector(",
    "limited.sourceLensShakeLocalRidgeCenterOffset = playbackTrajectoryXUnrestrictedLimitedYVector(",
    "StabilizerAxisLimitPolicy.xUnrestrictedYStepLimited(",
    "StabilizerAxisLimitPolicy.xUnrestrictedYAmplitudeLimited(",
    "result.pixelOffset.x = -rollingGlobalXEffectiveResidual * rollingGlobalXEffectiveSupport",
    "result.pixelOffset.x = -smoothedResidualX * supportX",
)
for contract in required_estimator_contracts:
    if contract not in estimator:
        fail(f"estimator path does not use the common policy: {contract}")

required_feedback_contracts = (
    "options.strengths.microX = value\n            options.strengths.macroX = value",
    "StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(options.strengths.microX)",
    "StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(options.strengths.macroX)",
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
    "turnOwnedFarFieldXImpulseRescue",
    "turnOwnedFarFieldRigidXTransitionRestoration",
    "playbackTrajectoryTurnOwnedXTransitionRescueMaximumPixels",
    "playbackTrajectoryHorizontalMicroJitterTurnHardGateConfidence",
    "let finalPosition = concatenatedTurn.positions[index] + highFrequencyX[index]",
    "var microJitterX: Double { max(cameraJitterX, 0.0) * 2.0 }",
    "options.strengths.microX = value * 2.0",
    "options.strengths.macroX = value * 2.0",
    "cameraRigidXMaximumOutputFraction",
    "cameraRigidXMaximumCorrectionCeiling",
    "lensShakeRollingGlobalXMaximumCorrection",
    "clamp(-residual.x, min: -lensShakePixelMaximumCorrection",
    "clamp(-0.5 * residual.x, min: -lensShakePixelMaximumCorrection",
    "lowEvidenceLargeMicroXScale",
    "playbackTrajectoryVelocityCollapseGuardedTransforms",
    "playbackTrajectoryVelocityCollapseMinimumPixels",
):
    if forbidden in estimator or forbidden in feedback:
        fail(f"legacy confidence bias remains: {forbidden}")

far_field_x_block = estimator.split("let farFieldPanBandXPath =", 1)[1].split(
    "let farFieldPanBandYPath =", 1
)[0]
if "maximumCorrection:" in far_field_x_block:
    fail("Far-field Pan Band X still has a per-sample correction cap")

macro_filter_block = estimator.split("let broadOffsets =", 1)[1].split(
    "var smoothedTransform =", 1
)[0]
if "medianX" in macro_filter_block or "xLimit" in macro_filter_block:
    fail("Macro X is still excluded by the local median/MAD smoothing filter")

auto_crop_scale_block = plugin.split("private static func requiredAutoCropScale", 1)[1].split(
    "private static func autoCropBoundaryScaleContainsSource", 1
)[0]
if "128.0" in auto_crop_scale_block:
    fail("Auto Crop required-scale calculation still has a fixed 128x cap")
if "Auto Crop required scale rejected | nonfinite" not in auto_crop_scale_block:
    fail("Auto Crop nonfinite scale failure is not logged explicitly")

if "debugOverlayMicroJitterConfidence" in plugin:
    fail("Debug Overlay still has a display-only Micro/Camera Rigid maximum")
if "microJitterConfidence: renderedAutoTransform.microConfidence" not in plugin:
    fail("Debug Overlay does not report the final Micro confidence directly")

print("test_confidence_bias_contract: PASS")
