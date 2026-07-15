import AppKit
import CoreMedia
import Darwin
import Foundation
import Metal
import os.log
import SQLite3
import simd

private enum ParameterID: UInt32 {
    case strength = 1
    case xStrength = 7
    case rotationStrength = 8
    // ID 9 is retired Turn Detection Window. Do not reuse it; existing FCP
    // projects may still carry saved values for that ID.
    case debugOverlay = 10
    case startHostAnalysis = 14
    case hostAnalysisStatus = 15
    case sampleInfo = 32
    case clearHostAnalysisCache = 17
    case yStrength = 18
    case sampleScale = 19
    case renderRevision = 20
    // ID 23 is the retired legacy turn strength slider. Do not reuse it; ID 46
    // now owns visible Turn Smoothing Strength.
    case edgeDisplayMode = 27
    // ID 28 is retired because existing FCP effect instances can persist the
    // old 0-4 slider range for that parameter ID.
    case legacyFarFieldWarpStrength = 28
    // IDs 29-31 are deprecated Macro Jitter controls. Keep them reserved so
    // saved timelines deserialize safely, but never register or read them.
    case macroJitterXStrength = 29
    case macroJitterYStrength = 30
    case macroJitterRotationStrength = 31
    case hostAnalysisCacheIdentity = 33
    // Reserved for deprecated Clip Range and Analysis Sample rows.
    case clipRangeInfo = 34
    case analysisSampleInfo = 35
    case queueInfo = 36
    // IDs 37-40 are retired Auto Crop speed/smoothness sliders. Do not reuse
    // them; existing FCP projects may still carry saved values for those IDs.
    case autoCropEnabled = 41
    case autoCropTransitionDuration = 42
    case autoCropLeadTime = 43
    case autoCropHoldTime = 44
    case farFieldWarpStrength = 45
    case turnSmoothingZoom = 46
    case meshOverlayMode = 47
    case turnTransitionWindow = 48
}

private struct StabilizerInfoFields {
    let sample: String
    let queue: String
}

private let tokyoWalkingStabilizerVersion = "1.2.9"
private let tokyoWalkingStabilizerDebugBuildNumber: Float = 1_016.0
private let tokyoWalkingStabilizerDebugVersion = vector_float4(1.0, 2.0, 9.0, 1_016.0)
// Bump with render-path algorithm changes so Final Cut Pro discards stale rendered frames.
private let tokyoWalkingStabilizerRenderRevisionSeed = 1_453_000.0
let stabilizerHostAnalysisLog = OSLog(subsystem: "com.justadev.TokyoWalkingStabilizer", category: "HostAnalysis")
private let stabilizerDefaultWalkingTranslationStrength = 2.0
private let stabilizerDefaultWalkingRotationStrength = 0.5
private let stabilizerDefaultFarFieldWarpStrength = 1.0
private let stabilizerDefaultTurnSmoothingZoom = 12.0
private let stabilizerDefaultTurnTransitionWindow = 5.0
private let stabilizerMaximumTurnSmoothingZoom = 36.0
private let stabilizerMaximumTurnSmoothingZoomScale: Float = 1.5
private let stabilizerMaximumFarFieldWarpStrength = 12.0
private let stabilizerDefaultAutoCropTransitionDuration = 6.0
private let stabilizerMaximumAutoCropTransitionDuration = 30.0
private let stabilizerDefaultAutoCropLeadTime = 6.0
private let stabilizerMaximumAutoCropLeadTime = 120.0
private let stabilizerDefaultAutoCropHoldTime = 0.0
private let stabilizerMaximumAutoCropHoldTime = 30.0
private let stabilizerAutoCropKeypointScaleThresholdDelta: Float = 0.006
private let stabilizerAutoCropKeypointCoverageThresholdDelta = StabilizerAutoCropScalePolicy.coverageActivationDelta
private let stabilizerAutoCropMicroMergeScaleThreshold: Float = 1.03
private let stabilizerAutoCropMicroMergeTouchGapSeconds = 0.25
private let stabilizerAutoCropMicroMergeMinimumPositionTolerance: Float = 8.0
private let stabilizerAutoCropMicroMergePositionToleranceFraction: Float = 0.012
private let stabilizerAutoCropKeypointRefineRadiusSeconds = 2.0
private let stabilizerAutoCropKeypointRefineStepSeconds = 0.25
private let stabilizerAutoCropKeypointMaximumCount = 64
private let stabilizerAutoCropKeypointLogLimit = 6
private let stabilizerAutoCropKeypointCoverageToleranceDelta = StabilizerAutoCropScalePolicy.coverageToleranceDelta
private let stabilizerAutoCropKeypointDuplicateSeconds = 0.125
private let stabilizerAutoCropKeypointCoveragePassLimit = 64
private let stabilizerCropOffEdgeGuardMaximumScaleDelta: Float = 0.012
private let stabilizerCropOffEdgeGuardBaseScaleDelta: Float = 0.006
private let stabilizerCropOffEdgeGuardLargeDemandPixels: Float = 20.0
private let stabilizerCropOffEdgeGuardPaddingPixels: Float = 8.0
private let stabilizerAutoCropIdleScaleTolerance: Float = 0.012
private let stabilizerAutoCropIdleReleaseStartSeconds = 1.0
private let stabilizerAutoCropIdleReleaseEndSeconds = 2.5
private let stabilizerAutoCropIdleSampleStepSeconds = 0.25
private let stabilizerAutoCropDemandMinimumStepSeconds = 1.0 / 60.0
private let stabilizerAutoCropPlaybackScalePlanStepSeconds = 1.0 / 60.0
private let stabilizerAutoCropPlaybackScaleQuantization: Float = 0.0001
private let stabilizerAutoCropPlaybackMinimumClipScaleDelta = StabilizerAutoCropScalePolicy.playbackMinimumClipScaleDelta
private let stabilizerAutoCropPlaybackEnvelopeRadiusSeconds = 1.25
private let stabilizerAutoCropPlaybackPositionEnvelopeRadiusSeconds = 1.25
private let stabilizerAutoCropPlaybackPositionRateLimitFractionPerSecond: Float = 0.0
private let stabilizerAutoCropPlaybackPositionMinimumStepPixels: Float = 0.20
private let stabilizerAutoCropPlaybackPositionDemandBlend: Float = 0.0
private let stabilizerAutoCropPlaybackLookaheadMinimumDelta: Float = 0.22
private let stabilizerAutoCropPlaybackLookaheadMaximumDelta: Float = 0.50
private let stabilizerAutoCropPlaybackLookaheadScaleFraction: Float = 0.12
private let stabilizerAutoCropPlaybackCapLeadSeconds = 3.0
private let stabilizerAutoCropPlaybackCapHoldSeconds = 0.25
private let stabilizerAutoCropPlaybackCapReleaseSeconds = 4.0
private let stabilizerAutoCropPlaybackCapSafetyDelta: Float = 0.035
private let stabilizerAutoCropPlaybackStablePositionFloorMaxDelta: Float = 0.003
private let stabilizerAutoCropPlaybackScaleRateLimitPerSecond: Float = 0.0
private let stabilizerAutoCropPlaybackScaleSmoothingMinimumRadiusSeconds = 1.90
private let stabilizerAutoCropPlaybackScaleSmoothingMaximumRadiusSeconds = 2.90
private let stabilizerAutoCropPlaybackScaleSmoothingAdaptiveStartDelta: Float = 0.060
private let stabilizerAutoCropPlaybackScaleSmoothingAdaptiveFullDelta: Float = 0.090
private let stabilizerAutoCropTurnSmoothingZoomStartPixels: Float = 24.0
private let stabilizerAutoCropTurnSmoothingZoomFullPixels: Float = 160.0
private let stabilizerAutoCropTurnSmoothingZoomConfidenceStart: Float = 0.12
private let stabilizerAutoCropTurnSmoothingZoomConfidenceFull: Float = 0.35
private let stabilizerRenderRevisionRetryIntervalSeconds: TimeInterval = 0.5
let stabilizerProjectCacheUnavailableMessage = "Project Bundle Cache Unavailable - Event Analysis Files Unavailable"
let stabilizerAmbiguousEventCacheUnavailableMessage = "Project Bundle Cache Unavailable - Ambiguous Event"
let stabilizerAmbiguousActiveLibrariesCacheUnavailableMessage = "Project Bundle Cache Unavailable - Ambiguous Active Libraries"

private enum StabilizerEdgeDisplayMode: Int32 {
    case stretchEdges = 0
    case blackOutside = 1
}

private enum StabilizerMeshOverlayMode: Int32 {
    case off = 0
    case farFieldMesh = 1
    case lensLocalMesh = 2
    case bandGuides = 3
    case allMeshes = 4

    static let menuEntries = [
        "Off",
        "Far Field Mesh",
        "Lens Local Mesh",
        "Band Guides",
        "All Meshes"
    ]

    static func clampedRawValue(_ rawValue: Int32) -> Int32 {
        guard let mode = StabilizerMeshOverlayMode(rawValue: rawValue) else {
            return StabilizerMeshOverlayMode.off.rawValue
        }
        return mode.rawValue
    }
}

enum StabilizerSampleScale: Int32 {
    case original = 0
    case scale75 = 1
    case scale50 = 2
    case scale25 = 3
    case scale10 = 4

    static let menuEntries = ["100%", "75%", "50%", "25%", "10%"]
    static let defaultScale: StabilizerSampleScale = .original

    var percent: Double {
        switch self {
        case .original:
            return 100.0
        case .scale75:
            return 75.0
        case .scale50:
            return 50.0
        case .scale25:
            return 25.0
        case .scale10:
            return 10.0
        }
    }

    var displayName: String {
        switch self {
        case .original:
            return "100%"
        case .scale75:
            return "75%"
        case .scale50:
            return "50%"
        case .scale25:
            return "25%"
        case .scale10:
            return "10%"
        }
    }

    static func scale(for rawValue: Int32) -> StabilizerSampleScale {
        StabilizerSampleScale(rawValue: rawValue) ?? defaultScale
    }
}

private struct AutoCropFraming {
    var scale: Float
    var positionPixels: vector_float2
    var telemetry: AutoCropCoverageTelemetry
    var cropOffEdgeGuardScale: Float = 1.0
    var cropOffEdgeGuardDemandX: Float = 0.0
    var cropOffEdgeGuardActive: Float = 0.0

    static let identity = AutoCropFraming(
        scale: 1.0,
        positionPixels: vector_float2(0.0, 0.0),
        telemetry: .empty,
        cropOffEdgeGuardScale: 1.0,
        cropOffEdgeGuardDemandX: 0.0,
        cropOffEdgeGuardActive: 0.0
    )
}

private struct AutoCropCoverageSummary {
    let missCount: Int
    let worstSeconds: Double?
    let worstRequiredScale: Float
    let worstPlannedScale: Float
    let worstDeficit: Float

    static let empty = AutoCropCoverageSummary(
        missCount: 0,
        worstSeconds: nil,
        worstRequiredScale: 1.0,
        worstPlannedScale: 1.0,
        worstDeficit: 0.0
    )
}

private struct AutoCropCoverageTelemetry {
    let planCount: Int
    let rawCount: Int
    let mergedCount: Int
    let mergeClusterCount: Int
    let mergeBypassed: Bool
    let missCount: Int
    let worstSeconds: Double?
    let worstRequiredScale: Float
    let worstPlannedScale: Float
    let worstDeficit: Float

    static let empty = AutoCropCoverageTelemetry(
        planCount: 0,
        rawCount: 0,
        mergedCount: 0,
        mergeClusterCount: 0,
        mergeBypassed: false,
        missCount: 0,
        worstSeconds: nil,
        worstRequiredScale: 1.0,
        worstPlannedScale: 1.0,
        worstDeficit: 0.0
    )
}

private struct AutoCropZoomDemandSample {
    let seconds: Double
    let scale: Float
    let positionPixels: vector_float2
    let neutralScale: Float
    let neutralPositionPixels: vector_float2
    let turnZoomScale: Float
    let transform: StabilizerAutoTransform
    let cameraCropScale: Float = 1.0
    let turnOverflowLeftPixels: Float = 0.0
    let turnOverflowRightPixels: Float = 0.0
    let turnViewportPositionX: Float = 0.0
}

private struct AutoCropZoomKeypoint {
    let peakSeconds: Double
    let startSeconds: Double
    let holdEndSeconds: Double
    let endSeconds: Double
    let scale: Float
    let positionPixels: vector_float2
}

private struct AutoCropZoomPlan {
    let keypoints: [AutoCropZoomKeypoint]
    let telemetry: AutoCropCoverageTelemetry
}

private struct AutoCropPlaybackScaleSample {
    let seconds: Double
    let scale: Float
}

private struct AutoCropPlaybackPositionSample {
    let seconds: Double
    let positionPixels: vector_float2
}

private struct AutoCropPlaybackProtectedDemandSample {
    let seconds: Double
    let scale: Float
    let positionPixels: vector_float2
}

private struct AutoCropPlaybackFramingSample {
    let seconds: Double
    let scale: Float
    let positionPixels: vector_float2
}

private struct AutoCropPlaybackFramingBuildResult {
    let samples: [AutoCropPlaybackFramingSample]
    let repairFloorSamples: [AutoCropPlaybackScaleSample]
    let repairCount: Int
    let maxRepairDelta: Float
    let maxRepairDeltaSeconds: Double
}

private struct AutoCropPlaybackScalePlan {
    let samples: [AutoCropPlaybackScaleSample]
    let capSamples: [AutoCropPlaybackScaleSample]
    let positionSamples: [AutoCropPlaybackPositionSample]
    let framingSamples: [AutoCropPlaybackFramingSample]
    let outputSize: vector_float2
    let sampleCount: Int
    let peakSeconds: Double?
    let peakScale: Float

    static let identity = AutoCropPlaybackScalePlan(
        samples: [],
        capSamples: [],
        positionSamples: [],
        framingSamples: [],
        outputSize: vector_float2(1.0, 1.0),
        sampleCount: 0,
        peakSeconds: nil,
        peakScale: 1.0
    )
}

private struct AutoCropZoomPlanSample {
    let scale: Float
    let positionPixels: vector_float2
    let influence: Float
    let peakSeconds: Double?

    static let identity = AutoCropZoomPlanSample(
        scale: 1.0,
        positionPixels: vector_float2(0.0, 0.0),
        influence: 0.0,
        peakSeconds: nil
    )
}

private struct AutoCropLocalScaleSample {
    let seconds: Double
    let influence: Float
}

private enum AutoCropSamplingProfile: Int32 {
    case playback = 0
    case full = 1

    var scaleSearchSampleSteps: Int {
        switch self {
        case .playback:
            return 4
        case .full:
            return 6
        }
    }

    var scaleSearchIterations: Int {
        switch self {
        case .playback:
            return 10
        case .full:
            return 18
        }
    }

    var positionBudgetIterations: Int {
        switch self {
        case .playback:
            return 6
        case .full:
            return 12
        }
    }

    var positionClampIterations: Int {
        switch self {
        case .playback:
            return 8
        case .full:
            return 18
        }
    }

    var scaleSafetyPadding: Float {
        switch self {
        case .playback:
            return 0.0
        case .full:
            return 0.0
        }
    }

    var quantizationStepSeconds: Double {
        switch self {
        case .playback:
            return stabilizerAutoCropPlaybackScalePlanStepSeconds
        case .full:
            return 0.0
        }
    }

    var positionEnvelopeSampleLimit: Int {
        switch self {
        case .playback:
            return 240
        case .full:
            return 240
        }
    }

    var positionEnvelopeStepSeconds: Double {
        switch self {
        case .playback:
            return 1.0 / 60.0
        case .full:
            return 1.0 / 60.0
        }
    }

    var zoomKeypointCoarseStepSeconds: Double {
        switch self {
        case .playback:
            return 2.5
        case .full:
            return 2.0
        }
    }

    var zoomKeypointCoverageStepSeconds: Double {
        switch self {
        case .playback:
            return 0.25
        case .full:
            return 0.20
        }
    }

    var zoomKeypointMinimumSpacingSeconds: Double {
        switch self {
        case .playback:
            return 6.0
        case .full:
            return 6.0
        }
    }

    var usesStabilizedSampleTransforms: Bool {
        false
    }

    var displayName: String {
        switch self {
        case .playback:
            return "playback"
        case .full:
            return "full"
        }
    }
}

private struct AutoCropScaleDemand {
    let currentPositionPixels: vector_float2
    let neutralPositionPixels: vector_float2
}

private struct AutoCropTransformContext {
    let outputSize: vector_float2
    let halfSize: vector_float2
    let marginPixels: Float
    let pixelOffset: vector_float2
    let perspective: vector_float2
    let shear: vector_float2
    let rotationSine: Float
    let rotationCosine: Float

    init(transform: StabilizerAutoTransform, outputSize: vector_float2, masterStrength: Float) {
        self.outputSize = outputSize
        self.halfSize = outputSize * 0.5
        self.marginPixels = min(Float(1.0), max(0.0, min(outputSize.x, outputSize.y) * 0.001))
        self.pixelOffset = transform.pixelOffset * masterStrength
        self.perspective = (transform.perspective + transform.yawPitchProxy) * masterStrength
        self.shear = transform.shear * masterStrength
        let rotationRadians = transform.rotationDegrees * .pi / 180.0 * masterStrength
        self.rotationSine = Darwin.sinf(-rotationRadians)
        self.rotationCosine = Darwin.cosf(-rotationRadians)
    }

    func sourcePixel(outputPixel: vector_float2, scale: Float, cropPositionPixels: vector_float2) -> vector_float2 {
        let framedPixels = (outputPixel / max(scale, 1.0)) + cropPositionPixels
        let rotated = vector_float2(
            (framedPixels.x * rotationCosine) - (framedPixels.y * rotationSine),
            (framedPixels.x * rotationSine) + (framedPixels.y * rotationCosine)
        )

        var stabilizedPixels = rotated - pixelOffset
        let normalizedPixels = stabilizedPixels / outputSize
        let perspectiveDenominator = max(
            Float(0.35),
            1.0 + (perspective.x * normalizedPixels.x) + (perspective.y * normalizedPixels.y)
        )
        stabilizedPixels /= perspectiveDenominator
        stabilizedPixels -= vector_float2(
            shear.x * stabilizedPixels.y,
            shear.y * stabilizedPixels.x
        )
        return stabilizedPixels
    }

    func containsSourcePixel(_ sourcePixel: vector_float2) -> Bool {
        sourcePixel.x >= (-halfSize.x + marginPixels)
            && sourcePixel.x <= (halfSize.x - marginPixels)
            && sourcePixel.y >= (-halfSize.y + marginPixels)
            && sourcePixel.y <= (halfSize.y - marginPixels)
    }
}

private struct AutoCropTransformSignature: Hashable {
    let pixelOffsetX: UInt32
    let pixelOffsetY: UInt32
    let macroPixelOffsetX: UInt32
    let macroPixelOffsetY: UInt32
    let rotationDegrees: UInt32
    let shearX: UInt32
    let shearY: UInt32
    let perspectiveX: UInt32
    let perspectiveY: UInt32
    let yawPitchProxyX: UInt32
    let yawPitchProxyY: UInt32

    init(_ transform: StabilizerAutoTransform) {
        pixelOffsetX = transform.pixelOffset.x.bitPattern
        pixelOffsetY = transform.pixelOffset.y.bitPattern
        macroPixelOffsetX = transform.macroPixelOffset.x.bitPattern
        macroPixelOffsetY = transform.macroPixelOffset.y.bitPattern
        rotationDegrees = transform.rotationDegrees.bitPattern
        shearX = transform.shear.x.bitPattern
        shearY = transform.shear.y.bitPattern
        perspectiveX = transform.perspective.x.bitPattern
        perspectiveY = transform.perspective.y.bitPattern
        yawPitchProxyX = transform.yawPitchProxy.x.bitPattern
        yawPitchProxyY = transform.yawPitchProxy.y.bitPattern
    }
}

private struct AutoCropFramingCacheKey: Hashable {
    let cacheIdentity: String?
    let analysisRevision: UInt64
    let renderTimeValue: Int64
    let renderTimeScale: Int32
    let renderTimeEpoch: Int64
    let outputWidth: Int32
    let outputHeight: Int32
    let analysisFrameCount: Int
    let analysisFirstTime: UInt64
    let analysisLastTime: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let renderQualityLevel: UInt32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let macroJitterX: UInt64
    let macroJitterY: UInt64
    let macroJitterRotation: UInt64
    let farFieldWarp: UInt64
    let turnSmoothingZoom: UInt64
    let turnTransitionWindow: UInt64
    let turnIdleReleaseSeconds: UInt64
    let currentTransform: AutoCropTransformSignature
}

private struct AutoCropScaleDemandCacheKey: Hashable {
    let cacheIdentity: String?
    let analysisRevision: UInt64
    let centerSeconds: UInt64
    let outputWidth: Int32
    let outputHeight: Int32
    let analysisFrameCount: Int
    let analysisFirstTime: UInt64
    let analysisLastTime: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let macroJitterX: UInt64
    let macroJitterY: UInt64
    let macroJitterRotation: UInt64
    let farFieldWarp: UInt64
    let turnSmoothingZoom: UInt64
    let turnTransitionWindow: UInt64
    let centerTransform: AutoCropTransformSignature
}

private struct AutoCropZoomPlanCacheKey: Hashable {
    let cacheIdentity: String?
    let analysisRevision: UInt64
    let outputWidth: Int32
    let outputHeight: Int32
    let analysisFrameCount: Int
    let analysisFirstTime: UInt64
    let analysisLastTime: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let macroJitterX: UInt64
    let macroJitterY: UInt64
    let macroJitterRotation: UInt64
    let farFieldWarp: UInt64
    let turnSmoothingZoom: UInt64
    let turnTransitionWindow: UInt64
}

private struct AutoCropPlaybackScalePlanCacheKey: Hashable {
    let cacheIdentity: String?
    let analysisRevision: UInt64
    let outputWidth: Int32
    let outputHeight: Int32
    let analysisFrameCount: Int
    let analysisFirstTime: UInt64
    let analysisLastTime: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let macroJitterX: UInt64
    let macroJitterY: UInt64
    let macroJitterRotation: UInt64
    let farFieldWarp: UInt64
    let turnSmoothingZoom: UInt64
    let turnTransitionWindow: UInt64
}

private struct AutoCropPlaybackPreparationCallback {
    let scope: UUID?
    let callback: () -> Void
}

private struct StabilizerAutoTransformCacheKey: Hashable {
    let cacheIdentity: String?
    let analysisRevision: UInt64
    let playbackMode: Bool
    let renderTimeValue: Int64
    let renderTimeScale: Int32
    let renderTimeEpoch: Int64
    let outputWidth: Int32
    let outputHeight: Int32
    let analysisFrameCount: Int
    let analysisFirstTime: UInt64
    let analysisLastTime: UInt64
    let analysisSampleWidth: Int32
    let analysisSampleHeight: Int32
    let analysisQualityModel: Int
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let macroJitterX: UInt64
    let macroJitterY: UInt64
    let macroJitterRotation: UInt64
    let farFieldWarp: UInt64
    let turnSmoothingZoom: UInt64
    let turnTransitionWindow: UInt64
}

private struct RenderAnalysisDecisionSignature: Equatable {
    let fxPlugVersion: String
    let transformEnabled: Bool
    let hasCompletedHostAnalysis: Bool
    let configuredProjectBundleCache: Bool
    let renderUsesPreparedAnalysis: Bool
    let stabilizationActive: Bool
    let debugOverlayActive: Bool
    let meshOverlayMode: Int32
    let renderSourceIsProxy: Bool
    let renderSourceFrameInfo: String
    let renderCacheIdentityShort: String
    let autoCropEnabled: Bool
    let autoCropProfileName: String
    let hostAnalysisFrameCount: Int32
}

private struct StabilizerPluginState {
    var strength: Double
    var cameraJitterXStrength: Double
    var cameraJitterYStrength: Double
    var cameraJitterRotationStrength: Double
    var farFieldWarpStrength: Double
    var turnSmoothingZoom: Double
    var turnTransitionWindow: Double
    var autoCropTransitionDuration: Double
    var autoCropLeadTime: Double
    var autoCropHoldTime: Double
    var autoCropEnabled: Bool
    var edgeDisplayMode: Int32
    var debugOverlay: Bool
    var meshOverlayMode: Int32
    var sampleScale: Int32
    var hostAnalysisFrameCount: Int32
    var hostAnalysisRevision: UInt64
    var renderRevision: Double
    var renderQualityLevel: UInt32
    var inputRangeStartSeconds: Double
    var inputRangeDurationSeconds: Double
    var inputFrameDurationSeconds: Double
}

struct HostAnalysisExpectedRange {
    let startSeconds: Double
    let durationSeconds: Double
    let frameDurationSeconds: Double

    var endSeconds: Double {
        startSeconds + durationSeconds
    }

    var isValid: Bool {
        startSeconds.isFinite
            && durationSeconds.isFinite
            && durationSeconds > 0.0
    }
}

private struct ActiveHostAnalysisRoute {
    let sessionID: UUID
    let store: StabilizerHostAnalysisStore
    let sampleSize: (width: Int, height: Int)?
    let canPublishCallbackStatus: Bool
}

private enum ActiveHostAnalysisCleanupRoute {
    case resolved(
        sessionID: UUID,
        store: StabilizerHostAnalysisStore,
        expectedRange: HostAnalysisExpectedRange?,
        canPublishCallbackStatus: Bool
    )
    case failed(reason: String)
}

struct StabilizerSourceFrameInfo {
    let sourceWidth: Int
    let sourceHeight: Int
    let pixelScaleX: Double
    let pixelScaleY: Double

    var sourceSizeDescription: String {
        "\(sourceWidth)x\(sourceHeight)"
    }

    var pixelScaleDescription: String {
        String(format: "%.2fx/%.2fx", pixelScaleX, pixelScaleY)
    }
}

private final class ActiveHostAnalysisSession {
    let id = UUID()
    let ownerObjectID: ObjectIdentifier
    let store: StabilizerHostAnalysisStore
    let range: CMTimeRange
    let frameDuration: CMTime
    let requestedSampleScalePercent: Double

    private let startSeconds: Double
    private let durationSeconds: Double
    private let frameDurationSeconds: Double
    private var observedSourceInfo: StabilizerSourceFrameInfo?
    private var observedSampleSize: (width: Int, height: Int)?
    private var lastFrameTimeKey: Int64?
    private(set) var lastTouchedAt = Date()
    var hasAcceptedFrame: Bool {
        lastFrameTimeKey != nil
    }

    init(
        ownerObjectID: ObjectIdentifier,
        store: StabilizerHostAnalysisStore,
        range: CMTimeRange,
        frameDuration: CMTime,
        requestedSampleScalePercent: Double
    ) {
        self.ownerObjectID = ownerObjectID
        self.store = store
        self.range = range
        self.frameDuration = frameDuration
        self.requestedSampleScalePercent = requestedSampleScalePercent
        startSeconds = CMTimeGetSeconds(range.start)
        durationSeconds = CMTimeGetSeconds(range.duration)
        frameDurationSeconds = CMTimeGetSeconds(frameDuration)
    }

    func score(
        frameTime: CMTime,
        sourceInfo: StabilizerSourceFrameInfo?,
        ownerObjectID: ObjectIdentifier,
        preferredSessionID: UUID?
    ) -> (score: Int, sampleSize: (width: Int, height: Int)?)? {
        let frameSeconds = CMTimeGetSeconds(frameTime)
        guard frameSeconds.isFinite else {
            return nil
        }

        var score = 0
        if isInRange(frameSeconds) {
            score += 10
        } else {
            return nil
        }

        if preferredSessionID == id {
            score += 60
        }
        if ownerObjectID == self.ownerObjectID {
            score += 30
        }

        var expectedSampleSize: (width: Int, height: Int)?
        if let sourceInfo {
            expectedSampleSize = sampleSize(for: sourceInfo)
            if let observedSourceInfo {
                guard sourceInfo.matches(observedSourceInfo) else {
                    return nil
                }
                score += 25
            }
            if let observedSampleSize {
                guard let expectedSampleSize,
                      observedSampleSize.width == expectedSampleSize.width,
                      observedSampleSize.height == expectedSampleSize.height
                else {
                    return nil
                }
                score += 25
            }
        }

        if let lastFrameTimeKey {
            let frameTimeKey = StabilizerHostAnalysisStore.timeKey(frameSeconds)
            guard frameTimeKey >= lastFrameTimeKey else {
                return nil
            }
            score += frameTimeKey == lastFrameTimeKey ? 1 : 8
        } else {
            score += 5
        }

        return (score: score, sampleSize: expectedSampleSize)
    }

    func recordAcceptedFrame(
        frameTime: CMTime,
        sourceInfo: StabilizerSourceFrameInfo,
        sampleSize: (width: Int, height: Int)
    ) {
        observedSourceInfo = sourceInfo
        observedSampleSize = sampleSize
        lastFrameTimeKey = StabilizerHostAnalysisStore.timeKey(CMTimeGetSeconds(frameTime))
        lastTouchedAt = Date()
    }

    func sampleSize(for sourceInfo: StabilizerSourceFrameInfo) -> (width: Int, height: Int) {
        AutoStabilizationEstimator.sampleSize(
            sourceWidth: sourceInfo.sourceWidth,
            sourceHeight: sourceInfo.sourceHeight,
            scalePercent: requestedSampleScalePercent
        )
    }

    func canPublishCallbackStatus(ownerObjectID: ObjectIdentifier, preferredSessionID: UUID?) -> Bool {
        preferredSessionID == id || ownerObjectID == self.ownerObjectID
    }

    var debugDescription: String {
        String(
            format: "%@ %.3f+%.3fs sample %.0f%% frames %d",
            id.uuidString,
            startSeconds,
            durationSeconds,
            requestedSampleScalePercent,
            store.frameCount
        )
    }

    private func isInRange(_ frameSeconds: Double) -> Bool {
        guard startSeconds.isFinite,
              durationSeconds.isFinite,
              durationSeconds > 0.0
        else {
            return true
        }
        let tolerance = max(1.0 / 600.0, frameDurationSeconds.isFinite ? frameDurationSeconds * 1.5 : 1.0 / 30.0)
        return frameSeconds >= startSeconds - tolerance
            && frameSeconds <= startSeconds + durationSeconds + tolerance
    }
}

private extension StabilizerSourceFrameInfo {
    func matches(_ other: StabilizerSourceFrameInfo) -> Bool {
        sourceWidth == other.sourceWidth
            && sourceHeight == other.sourceHeight
            && abs(pixelScaleX - other.pixelScaleX) <= 0.001
            && abs(pixelScaleY - other.pixelScaleY) <= 0.001
    }
}

enum StabilizerOriginalMediaPolicy {
    static let proxyScaleTolerance = 0.05

    struct ValidationIssue {
        let reason: String
        let isScaledProxy: Bool
    }

    static func sourceUnavailableReason(for frame: FxImageTile) -> String? {
        guard let requestError = frame.requestError else {
            return nil
        }
        let message = requestError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Final Cut Pro did not provide a source frame for render."
        }
        return "Final Cut Pro did not provide a source frame for render: \(message)"
    }

    static func proxyRejectionReason(for frame: FxImageTile) -> String? {
        originalMediaValidationIssue(for: frame)?.reason
    }

    static func originalMediaValidationIssue(for frame: FxImageTile) -> ValidationIssue? {
        guard let frameInfo = frameInfo(for: frame) else {
            return ValidationIssue(
                reason: "Host Analysis received a source frame without pixel transform; original media could not be confirmed.",
                isScaledProxy: false
            )
        }
        let scaleX = frameInfo.pixelScaleX
        let scaleY = frameInfo.pixelScaleY
        guard scaleX.isFinite, scaleY.isFinite else {
            return ValidationIssue(
                reason: "Host Analysis received a source frame with invalid pixel transform; original media could not be confirmed.",
                isScaledProxy: false
            )
        }
        let scaleDelta = max(abs(scaleX - 1.0), abs(scaleY - 1.0))
        guard scaleDelta <= proxyScaleTolerance else {
            return ValidationIssue(
                reason: String(
                    format: "Host Analysis received scaled/proxy media (pixel transform %.2fx, %.2fx). Use original media and rerun Host Analysis.",
                    scaleX,
                    scaleY
                ),
                isScaledProxy: true
            )
        }
        return nil
    }

    static func frameInfo(for frame: FxImageTile) -> StabilizerSourceFrameInfo? {
        guard let transform = frame.pixelTransform else {
            return nil
        }
        let origin = transform.transform2DPoint(CGPoint(x: 0.0, y: 0.0))
        let unitX = transform.transform2DPoint(CGPoint(x: 1.0, y: 0.0))
        let unitY = transform.transform2DPoint(CGPoint(x: 0.0, y: 1.0))
        let bounds = frame.imagePixelBounds
        return StabilizerSourceFrameInfo(
            sourceWidth: Int(abs(bounds.right - bounds.left)),
            sourceHeight: Int(abs(bounds.top - bounds.bottom)),
            pixelScaleX: hypot(Double(unitX.x - origin.x), Double(unitX.y - origin.y)),
            pixelScaleY: hypot(Double(unitY.x - origin.x), Double(unitY.y - origin.y))
        )
    }
}

@objc(TokyoWalkingStabilizerPlugIn)
final class TokyoWalkingStabilizerPlugIn: NSObject, FxTileableEffect, FxAnalyzer {
    private static let sharedHostAnalysisStore: StabilizerHostAnalysisStore = {
        let store = StabilizerHostAnalysisStore()
        return store
    }()
    private final class SerialHostAnalysisRequest {
        let plugin: TokyoWalkingStabilizerPlugIn
        let analysisAPI: FxAnalysisAPI
        let requestedSampleScalePercent: Double
        let reason: String

        init(
            plugin: TokyoWalkingStabilizerPlugIn,
            analysisAPI: FxAnalysisAPI,
            requestedSampleScalePercent: Double,
            reason: String
        ) {
            self.plugin = plugin
            self.analysisAPI = analysisAPI
            self.requestedSampleScalePercent = requestedSampleScalePercent
            self.reason = reason
        }
    }

    private struct SerialHostAnalysisQueuePosition {
        let position: Int
        let totalCount: Int
    }

    private struct SerialHostAnalysisQueueStatus {
        let plugin: TokyoWalkingStabilizerPlugIn
        let position: Int
        let totalCount: Int
        let reason: String
        let requestedSampleScalePercent: Double
    }

    private struct RenderMotionDiagnosticState {
        let cacheIdentityShort: String
        let analysisSeconds: Double
        let lowerIndex: Int
        let upperIndex: Int
        let samplePosition: Double
        let pixelOffset: vector_float2
        let cropScale: Float
        let cropPositionPixels: vector_float2
        let tinyStep: Bool
    }

    private struct RenderPreviewWarmupState {
        let cacheIdentityShort: String
        let analysisSeconds: Double
        let samplePosition: Double
        let warmupUntil: TimeInterval
        let stableSequentialFrameCount: Int
        let active: Bool
    }

    private struct RenderPreviewWarmupDecision {
        let active: Bool
        let reason: String
        let analysisSeconds: Double
        let expectedFrameSeconds: Double
        let deltaSeconds: Double
        let samplePosition: Double
        let sampleDelta: Double
        let stableSequentialFrameCount: Int
        let remainingSeconds: Double

        static let inactive = RenderPreviewWarmupDecision(
            active: false,
            reason: "inactive",
            analysisSeconds: 0.0,
            expectedFrameSeconds: 0.0,
            deltaSeconds: 0.0,
            samplePosition: 0.0,
            sampleDelta: 0.0,
            stableSequentialFrameCount: 0,
            remainingSeconds: 0.0
        )
    }

    private static let serialAnalysisQueueLock = NSLock()
    private static var serialAnalysisQueue: [SerialHostAnalysisRequest] = []
    private static let activeAnalysisStoreLock = NSLock()
    private static var activeAnalysisSessions: [UUID: ActiveHostAnalysisSession] = [:]
    private static var hostAnalysisStartReserved = false
    private static let autoCropFramingCacheLock = NSLock()
    private static var autoCropFramingCache: [AutoCropFramingCacheKey: AutoCropFraming] = [:]
    private static var autoCropFramingCacheOrder: [AutoCropFramingCacheKey] = []
    private static let autoCropFramingCacheLimit = 16384
    private static let autoCropScaleDemandCacheLock = NSLock()
    private static var autoCropScaleDemandCache: [AutoCropScaleDemandCacheKey: AutoCropScaleDemand] = [:]
    private static var autoCropScaleDemandCacheOrder: [AutoCropScaleDemandCacheKey] = []
    private static let autoCropScaleDemandCacheLimit = 16384
    private static let autoCropZoomPlanCacheLock = NSLock()
    private static var autoCropZoomPlanCache: [AutoCropZoomPlanCacheKey: AutoCropZoomPlan] = [:]
    private static var autoCropZoomPlanCacheOrder: [AutoCropZoomPlanCacheKey] = []
    private static let autoCropZoomPlanCacheLimit = 16
    private static let autoCropPlaybackScalePlanCacheLock = NSLock()
    private static var autoCropPlaybackScalePlanCache: [AutoCropPlaybackScalePlanCacheKey: AutoCropPlaybackScalePlan] = [:]
    private static var autoCropPlaybackScalePlanCacheOrder: [AutoCropPlaybackScalePlanCacheKey] = []
    private static var autoCropPlaybackScalePlanPreparations: Set<AutoCropPlaybackScalePlanCacheKey> = []
    private static var autoCropPlaybackScalePlanPreparationCallbacks: [AutoCropPlaybackScalePlanCacheKey: [AutoCropPlaybackPreparationCallback]] = [:]
    private static var latestAutoCropPlaybackScalePlanKeyByScope: [UUID: AutoCropPlaybackScalePlanCacheKey] = [:]
    private static var supersededAutoCropPlaybackRequestCount: UInt64 = 0
    private static let autoCropPlaybackScalePlanPreparationQueue = DispatchQueue(
        label: "com.justadev.TokyoWalkingStabilizer.AutoCropPlaybackScalePlanPreparation",
        qos: .userInitiated
    )
    private static let autoCropPlaybackScalePlanCacheLimit = 16
    private static let autoTransformCacheLock = NSLock()
    private static var autoTransformCache: [StabilizerAutoTransformCacheKey: StabilizerAutoTransform] = [:]
    private static var autoTransformCacheOrder: [StabilizerAutoTransformCacheKey] = []
    private static let autoTransformCacheLimit = 32768
    private static let previewWarmupHoldSeconds: TimeInterval = 0.85
    private static let previewWarmupStableSequentialFrameCount = 2
    private static let previewWarmupLogIntervalSeconds: TimeInterval = 0.25
    private let apiManager: PROAPIAccessing
    private let statusLock = NSLock()
    private let cacheIdentityLock = NSLock()
    private let persistentCacheMonitorQueue = DispatchQueue(label: "com.justadev.TokyoWalkingStabilizer.PersistentCacheMonitor")
    private var lastPublishedStatus = ""
    private var lastPublishedSampleInfo = ""
    private var lastPublishedQueueInfo = ""
    private var lastPublishedRenderRevision: Double?
    private var lastRenderRevisionPublishAttemptRevision: Double?
    private var lastRenderRevisionPublishAttemptWallTime: TimeInterval = 0.0
    private var lastPublishedHostAnalysisCacheIdentity: String?
    private var lastScheduledPostAnalysisPublishRevision: Double?
    private var lastRenderAnalysisDecision = ""
    private var lastRenderAnalysisDecisionSignature: RenderAnalysisDecisionSignature?
    private var lastRenderAnalysisDecisionLogWallTime: TimeInterval = 0.0
    private var lastRenderEarlyExitReason = ""
    private let renderDiagnosticsLogLock = NSLock()
    private var lastRenderDiagnosticsLogBucket: Int64?
    private let renderTimingLogLock = NSLock()
    private var lastRenderTimingLogWallTime: TimeInterval = 0.0
    private var lastRenderDiagnosticsLogWallTime: TimeInterval = 0.0
    private var lastRenderMotionDiagnosticLogWallTime: TimeInterval = 0.0
    private var lastRenderDiagnosticStatusWallTime: TimeInterval = 0.0
    private var lastRenderMotionDiagnosticState: RenderMotionDiagnosticState?
    private var lastPreviewWarmupState: RenderPreviewWarmupState?
    private var lastPreviewWarmupLogWallTime: TimeInterval = 0.0
    private var lastScheduledPreviewWarmupExpiry: TimeInterval = 0.0
    private var lastScheduledPreviewWarmupExpiryIdentity = ""
    private var preferredHostAnalysisCacheIdentity: String?
    private var lastPublishedActiveAnalysisFrameCount = 0
    private var activeAnalyzerSessionID: UUID?
    private var persistentCacheMonitor: DispatchSourceTimer?
    private let playbackPreparationScope = UUID()
    private var hostAnalysisStore: StabilizerHostAnalysisStore {
        Self.sharedHostAnalysisStore
    }

    private enum HostAnalysisRequestResult {
        case started
        case skippedCompleted
        case queued
        case failed
    }

    required init?(apiManager: PROAPIAccessing) {
        self.apiManager = apiManager
        super.init()
        _ = Self.sharedHostAnalysisStore
        startPersistentCacheMonitor()
        NSLog("TokyoWalkingStabilizer: runtime initialized version \(tokyoWalkingStabilizerVersion).")
    }

    deinit {
        persistentCacheMonitor?.cancel()
        AutoStabilizationEstimator.cancelPlaybackPreparations(for: playbackPreparationScope)
        Self.cancelAutoCropPlaybackPreparations(for: playbackPreparationScope)
    }

    func addParameters() throws {
        let paramAPI = apiManager.api(for: FxParameterCreationAPI_v5.self) as! FxParameterCreationAPI_v5
        let flags = FxParameterFlags(kFxParameterFlag_DEFAULT)

        paramAPI.addFloatSlider(
            withName: "Overall Strength",
            parameterID: ParameterID.strength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 2.0,
            sliderMin: 0.0,
            sliderMax: 2.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Camera Jitter X Max Correction (%)",
            parameterID: ParameterID.xStrength.rawValue,
            defaultValue: stabilizerDefaultWalkingTranslationStrength,
            parameterMin: 0.0,
            parameterMax: 5.0,
            sliderMin: 0.0,
            sliderMax: 5.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Camera Jitter Y Max Correction (%)",
            parameterID: ParameterID.yStrength.rawValue,
            defaultValue: stabilizerDefaultWalkingTranslationStrength,
            parameterMin: 0.0,
            parameterMax: 5.0,
            sliderMin: 0.0,
            sliderMax: 5.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Camera Jitter ROLL Max Correction (°)",
            parameterID: ParameterID.rotationStrength.rawValue,
            defaultValue: stabilizerDefaultWalkingRotationStrength,
            parameterMin: 0.0,
            parameterMax: 2.0,
            sliderMin: 0.0,
            sliderMax: 2.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Far-field Warp Strength",
            parameterID: ParameterID.farFieldWarpStrength.rawValue,
            defaultValue: stabilizerDefaultFarFieldWarpStrength,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumFarFieldWarpStrength,
            sliderMin: 0.0,
            sliderMax: stabilizerMaximumFarFieldWarpStrength,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Turn Smoothing Strength",
            parameterID: ParameterID.turnSmoothingZoom.rawValue,
            defaultValue: stabilizerDefaultTurnSmoothingZoom,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumTurnSmoothingZoom,
            sliderMin: 0.0,
            sliderMax: stabilizerMaximumTurnSmoothingZoom,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Turn Transition Window (s)",
            parameterID: ParameterID.turnTransitionWindow.rawValue,
            defaultValue: stabilizerDefaultTurnTransitionWindow,
            parameterMin: 0.5,
            parameterMax: 8.0,
            sliderMin: 0.5,
            sliderMax: 8.0,
            delta: 0.05,
            parameterFlags: flags
        )
        paramAPI.addToggleButton(
            withName: "Remove Black Edges",
            parameterID: ParameterID.autoCropEnabled.rawValue,
            defaultValue: true,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Auto Crop Zoom-Out Time",
            parameterID: ParameterID.autoCropTransitionDuration.rawValue,
            defaultValue: stabilizerDefaultAutoCropTransitionDuration,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumAutoCropTransitionDuration,
            sliderMin: 0.0,
            sliderMax: stabilizerMaximumAutoCropTransitionDuration,
            delta: 0.05,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Auto Crop Zoom-In Time",
            parameterID: ParameterID.autoCropLeadTime.rawValue,
            defaultValue: stabilizerDefaultAutoCropLeadTime,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumAutoCropLeadTime,
            sliderMin: 0.0,
            sliderMax: 30.0,
            delta: 0.1,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Auto Crop Hold Time",
            parameterID: ParameterID.autoCropHoldTime.rawValue,
            defaultValue: stabilizerDefaultAutoCropHoldTime,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumAutoCropHoldTime,
            sliderMin: 0.0,
            sliderMax: stabilizerMaximumAutoCropHoldTime,
            delta: 0.1,
            parameterFlags: flags
        )
        let hiddenAnalysisControlFlags = FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_HIDDEN)
        paramAPI.addFloatSlider(
            withName: "Legacy Far-field Warp Strength",
            parameterID: ParameterID.legacyFarFieldWarpStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: hiddenAnalysisControlFlags
        )
        paramAPI.addPopupMenu(
            withName: "Sample Size",
            parameterID: ParameterID.sampleScale.rawValue,
            defaultValue: UInt32(StabilizerSampleScale.defaultScale.rawValue),
            menuEntries: StabilizerSampleScale.menuEntries,
            parameterFlags: hiddenAnalysisControlFlags
        )
        paramAPI.addPopupMenu(
            withName: "Edge Display Mode",
            parameterID: ParameterID.edgeDisplayMode.rawValue,
            defaultValue: UInt32(StabilizerEdgeDisplayMode.blackOutside.rawValue),
            menuEntries: ["Stretch Edges", "Black Outside"],
            parameterFlags: flags
        )
        paramAPI.addPushButton(
            withName: "Start Host Analysis",
            parameterID: ParameterID.startHostAnalysis.rawValue,
            selector: #selector(startHostAnalysis),
            parameterFlags: hiddenAnalysisControlFlags
        )
        paramAPI.addPushButton(
            withName: "Clear Host Analysis Cache",
            parameterID: ParameterID.clearHostAnalysisCache.rawValue,
            selector: #selector(clearHostAnalysisCache),
            parameterFlags: hiddenAnalysisControlFlags
        )
        paramAPI.addStringParameter(
            withName: "Host Analysis Status",
            parameterID: ParameterID.hostAnalysisStatus.rawValue,
            defaultValue: "External Analysis Required - Run Event Analyzer",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE)
        )
        paramAPI.addStringParameter(
            withName: "Sample Info",
            parameterID: ParameterID.sampleInfo.rawValue,
            defaultValue: "Sample: 100% | Analysis: -",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE)
        )
        paramAPI.addStringParameter(
            withName: "Queue",
            parameterID: ParameterID.queueInfo.rawValue,
            defaultValue: "Queue: -",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE | kFxParameterFlag_HIDDEN)
        )
        paramAPI.addFloatSlider(
            withName: "Render Revision",
            parameterID: ParameterID.renderRevision.rawValue,
            defaultValue: 0.0,
            parameterMin: 0.0,
            parameterMax: Double(UInt32.max),
            sliderMin: 0.0,
            sliderMax: Double(UInt32.max),
            delta: 1.0,
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_HIDDEN)
        )
        paramAPI.addStringParameter(
            withName: "Host Analysis Cache Identity",
            parameterID: ParameterID.hostAnalysisCacheIdentity.rawValue,
            defaultValue: "",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_HIDDEN)
        )
        paramAPI.addPopupMenu(
            withName: "Mesh Overlay",
            parameterID: ParameterID.meshOverlayMode.rawValue,
            defaultValue: UInt32(StabilizerMeshOverlayMode.off.rawValue),
            menuEntries: StabilizerMeshOverlayMode.menuEntries,
            parameterFlags: flags
        )
        paramAPI.addToggleButton(
            withName: "Debug Overlay",
            parameterID: ParameterID.debugOverlay.rawValue,
            defaultValue: false,
            parameterFlags: flags
        )
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
    }

    func properties(_ properties: AutoreleasingUnsafeMutablePointer<NSDictionary>?) throws {
        properties?.pointee = [
            kFxPropertyKey_IsThreadSafe: true,
            kFxPropertyKey_NeedsFullBuffer: true,
            kFxPropertyKey_MayRemapTime: true,
            kFxPropertyKey_PixelTransformSupport: NSNumber(value: kFxPixelTransform_Full),
            kFxPropertyKey_VariesWhenParamsAreStatic: true
        ] as NSDictionary
    }

    func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?, at renderTime: CMTime, quality qualityLevel: UInt) throws {
        let paramAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as! FxParameterRetrievalAPI_v6

        var state = StabilizerPluginState(
            strength: 1.0,
            cameraJitterXStrength: stabilizerDefaultWalkingTranslationStrength,
            cameraJitterYStrength: stabilizerDefaultWalkingTranslationStrength,
            cameraJitterRotationStrength: stabilizerDefaultWalkingRotationStrength,
            farFieldWarpStrength: stabilizerDefaultFarFieldWarpStrength,
            turnSmoothingZoom: stabilizerDefaultTurnSmoothingZoom,
            turnTransitionWindow: stabilizerDefaultTurnTransitionWindow,
            autoCropTransitionDuration: stabilizerDefaultAutoCropTransitionDuration,
            autoCropLeadTime: stabilizerDefaultAutoCropLeadTime,
            autoCropHoldTime: stabilizerDefaultAutoCropHoldTime,
            autoCropEnabled: true,
            edgeDisplayMode: StabilizerEdgeDisplayMode.blackOutside.rawValue,
            debugOverlay: false,
            meshOverlayMode: StabilizerMeshOverlayMode.off.rawValue,
            sampleScale: StabilizerSampleScale.defaultScale.rawValue,
            hostAnalysisFrameCount: 0,
            hostAnalysisRevision: 0,
            renderRevision: 0.0,
            renderQualityLevel: UInt32(clamping: qualityLevel),
            inputRangeStartSeconds: .nan,
            inputRangeDurationSeconds: .nan,
            inputFrameDurationSeconds: .nan
        )
        paramAPI.getFloatValue(&state.strength, fromParameter: ParameterID.strength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.cameraJitterXStrength, fromParameter: ParameterID.xStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.cameraJitterYStrength, fromParameter: ParameterID.yStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.cameraJitterRotationStrength, fromParameter: ParameterID.rotationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.farFieldWarpStrength, fromParameter: ParameterID.farFieldWarpStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.turnSmoothingZoom, fromParameter: ParameterID.turnSmoothingZoom.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.turnTransitionWindow, fromParameter: ParameterID.turnTransitionWindow.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.autoCropTransitionDuration, fromParameter: ParameterID.autoCropTransitionDuration.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.autoCropLeadTime, fromParameter: ParameterID.autoCropLeadTime.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.autoCropHoldTime, fromParameter: ParameterID.autoCropHoldTime.rawValue, at: renderTime)
        var autoCropEnabled = ObjCBool(state.autoCropEnabled)
        paramAPI.getBoolValue(&autoCropEnabled, fromParameter: ParameterID.autoCropEnabled.rawValue, at: renderTime)
        state.autoCropEnabled = autoCropEnabled.boolValue
        paramAPI.getIntValue(&state.edgeDisplayMode, fromParameter: ParameterID.edgeDisplayMode.rawValue, at: renderTime)
        var debugOverlay = ObjCBool(state.debugOverlay)
        paramAPI.getBoolValue(&debugOverlay, fromParameter: ParameterID.debugOverlay.rawValue, at: renderTime)
        state.debugOverlay = debugOverlay.boolValue
        paramAPI.getIntValue(&state.meshOverlayMode, fromParameter: ParameterID.meshOverlayMode.rawValue, at: renderTime)
        state.meshOverlayMode = StabilizerMeshOverlayMode.clampedRawValue(state.meshOverlayMode)
        paramAPI.getIntValue(&state.sampleScale, fromParameter: ParameterID.sampleScale.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.renderRevision, fromParameter: ParameterID.renderRevision.rawValue, at: renderTime)
        var cacheIdentityValue = NSString()
        if paramAPI.getStringParameterValue(&cacheIdentityValue, fromParameter: ParameterID.hostAnalysisCacheIdentity.rawValue) {
            updatePreferredHostAnalysisCacheIdentity(cacheIdentityValue as String)
        }
        if let inputRange = currentInputRange() {
            state.inputRangeStartSeconds = inputRange.startSeconds
            state.inputRangeDurationSeconds = inputRange.durationSeconds
            state.inputFrameDurationSeconds = inputRange.frameDurationSeconds
        }
        let expectedRange = Self.expectedInputRange(from: state)
        if configureProjectBundleCacheDirectory(expectedRange: expectedRange) {
            if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
               (hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)
                || hostAnalysisStore.activatePersistentCache(matchingSourceIdentity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)) {
                publishHostAnalysisCacheIdentity(hostAnalysisStore.activeCacheIdentity, force: false)
            } else if hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange, allowRangeMismatch: true) {
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishHostAnalysisCacheIdentity(hostAnalysisStore.activeCacheIdentity, force: false)
                publishRenderRevision(
                    hostAnalysisStore.renderInvalidationToken,
                    currentParameterValue: state.renderRevision,
                    force: true
                )
            }
        }
        let cappedHostFrameCount = min(hostAnalysisStore.frameCount, Int(Int32.max))
        state.hostAnalysisFrameCount = Int32(cappedHostFrameCount)
        state.hostAnalysisRevision = hostAnalysisStore.revision
        publishHostAnalysisStatus()
        publishStabilizerInfo()
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, currentParameterValue: state.renderRevision)

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
    }

    @objc(startHostAnalysis)
    func startHostAnalysis() {
        os_log("Deprecated Start Host Analysis pressed in FxPlug %{public}@; reloading external Event Analyzer cache only.", log: stabilizerHostAnalysisLog, type: .default, tokyoWalkingStabilizerVersion)
        publishHostAnalysisStatus(force: true, statusOverride: "Reloading Event Analyzer Cache")
        publishStabilizerInfo(force: true)
        let expectedRange = currentInputRange()
        if hostAnalysisStore.hasCompletedAnalysis,
           let activeIdentity = hostAnalysisStore.activeCacheIdentity,
           StabilizerHostAnalysisStore.cacheIdentity(activeIdentity, matches: expectedRange) {
            os_log(
                "Start Host Analysis reused active prepared cache %{public}@ without reset or disk reload.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                activeIdentity
            )
            NSLog("TokyoWalkingStabilizer: Start Host Analysis reused active prepared cache \(activeIdentity) without reset or disk reload.")
            publishHostAnalysisCacheIdentity(activeIdentity, force: true)
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return
        }
        hostAnalysisStore.reset()
        let loadedPersistentCache: Bool
        if configureProjectBundleCacheDirectory(markUnavailable: false, expectedRange: expectedRange, forceRefresh: true) {
            if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
               (hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)
                || hostAnalysisStore.activatePersistentCache(matchingSourceIdentity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)) {
                loadedPersistentCache = true
            } else {
                loadedPersistentCache = hostAnalysisStore.loadPersistentCache(expectedRange: expectedRange, allowRangeMismatch: true)
            }
        } else {
            loadedPersistentCache = false
            os_log("Deprecated Start Host Analysis could not resolve Event cache root; external Event Analyzer is required.", log: stabilizerHostAnalysisLog, type: .default)
            NSLog("TokyoWalkingStabilizer: deprecated Start Host Analysis could not resolve the Event cache root; run the Stabilizer Event Analyzer and import its FCPXMLD output.")
        }
        if loadedPersistentCache {
            publishHostAnalysisCacheIdentity(hostAnalysisStore.activeCacheIdentity, force: true)
        } else {
            hostAnalysisStore.markExternalAnalysisRequired(
                reason: "No compatible Event Analyzer cache was found for this clip. Export Event FCPXMLD, run the Stabilizer Event Analyzer, then import the generated FCPXMLD."
            )
        }
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
    }

    @objc(clearHostAnalysisCache)
    func clearHostAnalysisCache() {
        Self.removeQueuedSerialAnalysis(self)
        hostAnalysisStore.markExternalCacheManaged(
            reason: "Persisted caches are now created and managed by the Stabilizer Event Analyzer. Delete or rebuild them from the external tool instead of the FCP effect."
        )
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
    }

    @discardableResult
    private func requestHostAnalysisIfNeeded(
        force: Bool = false,
        allowSerialQueue: Bool = true,
        queuedStartRequest: Bool = false,
        queuedAnalysisAPI: FxAnalysisAPI? = nil,
        acceptedSampleScalePercentOverride: Double? = nil
    ) -> HostAnalysisRequestResult {
        let acceptedSampleScalePercent = acceptedSampleScalePercentOverride ?? requestedSampleScalePercent(for: currentInputRange())
        let isQueuedRequest = queuedStartRequest || Self.isQueuedSerialAnalysis(self)
        if hostAnalysisStore.hasCompletedAnalysis && !(force && isQueuedRequest) {
            Self.removeQueuedSerialAnalysis(self)
            return .skippedCompleted
        }
        guard force || !hostAnalysisStore.hasCompletedAnalysis || isQueuedRequest else {
            Self.removeQueuedSerialAnalysis(self)
            return .skippedCompleted
        }
        guard let analysisAPI = queuedAnalysisAPI ?? (apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI) else {
            os_log("FxAnalysisAPI unavailable; Host Analysis cannot start.", log: stabilizerHostAnalysisLog, type: .error)
            NSLog("TokyoWalkingStabilizer: FxAnalysisAPI is unavailable; Host Analysis cannot start.")
            Self.removeQueuedSerialAnalysis(self)
            hostAnalysisStore.markStartFailed(reason: "FxAnalysisAPI unavailable")
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return .failed
        }
        let analysisState = analysisAPI.analysisStateForEffect()
        let canStart = analysisState == kFxAnalysisState_NotAnalyzing
            || analysisState == kFxAnalysisState_AnalysisInterrupted
            || (force && analysisState == kFxAnalysisState_AnalysisCompleted)
        guard canStart else {
            let reason = Self.analysisStateDescription(analysisState)
            if queuedStartRequest,
               let queuePosition = Self.serialAnalysisQueuePosition(for: self) {
                hostAnalysisStore.markQueued(
                    position: queuePosition.position,
                    totalCount: queuePosition.totalCount,
                    reason: reason,
                    requestedSampleScalePercent: acceptedSampleScalePercent
                )
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                Self.scheduleSerialAnalysisQueueDrain()
                return .queued
            }
            if allowSerialQueue && force {
                let queuePosition = Self.enqueueSerialAnalysis(
                    self,
                    analysisAPI: analysisAPI,
                    requestedSampleScalePercent: acceptedSampleScalePercent,
                    reason: reason
                )
                hostAnalysisStore.markQueued(
                    position: queuePosition.position,
                    totalCount: queuePosition.totalCount,
                    reason: reason,
                    requestedSampleScalePercent: acceptedSampleScalePercent
                )
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                NSLog("TokyoWalkingStabilizer: queued Host Analysis request at position \(queuePosition.position) of \(queuePosition.totalCount) because host state is \(reason).")
                os_log("Queued Host Analysis because host state is %{public}@ at position %{public}d of %{public}d.", log: stabilizerHostAnalysisLog, type: .default, reason, queuePosition.position, queuePosition.totalCount)
                Self.scheduleSerialAnalysisQueueDrain()
                return .queued
            } else if force {
                hostAnalysisStore.markStartFailed(reason: "Host state \(reason)")
            }
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            if force {
                NSLog("TokyoWalkingStabilizer: Host Analysis is already requested or running.")
                os_log("Host Analysis start blocked because host state is %{public}@.", log: stabilizerHostAnalysisLog, type: .error, reason)
            }
            return .failed
        }
        guard Self.reserveHostAnalysisStartIfAvailable() else {
            let reason = "ActiveHostAnalysisSession"
            if queuedStartRequest,
               let queuePosition = Self.serialAnalysisQueuePosition(for: self) {
                hostAnalysisStore.markQueued(
                    position: queuePosition.position,
                    totalCount: queuePosition.totalCount,
                    reason: reason,
                    requestedSampleScalePercent: acceptedSampleScalePercent
                )
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                Self.scheduleSerialAnalysisQueueDrain()
                return .queued
            }
            if allowSerialQueue && force {
                let queuePosition = Self.enqueueSerialAnalysis(
                    self,
                    analysisAPI: analysisAPI,
                    requestedSampleScalePercent: acceptedSampleScalePercent,
                    reason: reason
                )
                hostAnalysisStore.markQueued(
                    position: queuePosition.position,
                    totalCount: queuePosition.totalCount,
                    reason: reason,
                    requestedSampleScalePercent: acceptedSampleScalePercent
                )
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                NSLog("TokyoWalkingStabilizer: queued Host Analysis request at position \(queuePosition.position) of \(queuePosition.totalCount) because another clip has an active or reserved Host Analysis session.")
                os_log("Queued Host Analysis because another clip has an active or reserved session at position %{public}d of %{public}d.", log: stabilizerHostAnalysisLog, type: .default, queuePosition.position, queuePosition.totalCount)
                Self.scheduleSerialAnalysisQueueDrain()
                return .queued
            }
            if force {
                hostAnalysisStore.markStartFailed(reason: reason)
            }
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return .failed
        }
        if queuedStartRequest {
            hostAnalysisStore.reset()
            os_log(
                "Serial Host Analysis queue reset the shared render store before starting the queued clip.",
                log: stabilizerHostAnalysisLog,
                type: .default
            )
        }
        do {
            Self.removeQueuedSerialAnalysis(self)
            try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_GPU)
            NSLog("TokyoWalkingStabilizer: requested GPU Host Analysis for the effect clip.")
            os_log("Requested GPU Host Analysis for the effect clip.", log: stabilizerHostAnalysisLog, type: .default)
            hostAnalysisStore.markRequested(requestedSampleScalePercent: acceptedSampleScalePercent)
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return .started
        } catch {
            NSLog("TokyoWalkingStabilizer: Host Analysis request failed: \(error.localizedDescription)")
            os_log("Host Analysis request failed: %{public}@.", log: stabilizerHostAnalysisLog, type: .error, error.localizedDescription)
            Self.releaseHostAnalysisStartReservation()
            Self.removeQueuedSerialAnalysis(self)
            hostAnalysisStore.markStartFailed(reason: error.localizedDescription)
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return .failed
        }
    }

    @discardableResult
    private static func enqueueSerialAnalysis(
        _ plugin: TokyoWalkingStabilizerPlugIn,
        analysisAPI: FxAnalysisAPI,
        requestedSampleScalePercent: Double,
        reason: String
    ) -> SerialHostAnalysisQueuePosition {
        serialAnalysisQueueLock.lock()
        let originalCount = serialAnalysisQueue.count
        serialAnalysisQueue.removeAll { queuedRequest in queuedRequest.plugin === plugin }
        let replacedCount = originalCount - serialAnalysisQueue.count
        serialAnalysisQueue.append(SerialHostAnalysisRequest(
            plugin: plugin,
            analysisAPI: analysisAPI,
            requestedSampleScalePercent: requestedSampleScalePercent,
            reason: reason
        ))
        let position = serialAnalysisQueue.count
        let totalCount = serialAnalysisQueue.count
        serialAnalysisQueueLock.unlock()
        publishSerialQueueStatuses()
        os_log(
            "Serial Host Analysis queue accepted request at position %{public}d of %{public}d after replacing %{public}d queued request(s) for the same effect instance.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            position,
            totalCount,
            replacedCount
        )
        return SerialHostAnalysisQueuePosition(position: position, totalCount: totalCount)
    }

    private static func removeQueuedSerialAnalysis(_ plugin: TokyoWalkingStabilizerPlugIn) {
        serialAnalysisQueueLock.lock()
        serialAnalysisQueue.removeAll { queuedRequest in queuedRequest.plugin === plugin }
        serialAnalysisQueueLock.unlock()
        publishSerialQueueStatuses()
    }

    private static func isQueuedSerialAnalysis(_ plugin: TokyoWalkingStabilizerPlugIn) -> Bool {
        serialAnalysisQueueLock.lock()
        defer { serialAnalysisQueueLock.unlock() }
        return serialAnalysisQueue.contains { queuedRequest in queuedRequest.plugin === plugin }
    }

    private static func serialAnalysisQueuePosition(for plugin: TokyoWalkingStabilizerPlugIn) -> SerialHostAnalysisQueuePosition? {
        serialAnalysisQueueLock.lock()
        defer { serialAnalysisQueueLock.unlock() }
        guard let index = serialAnalysisQueue.firstIndex(where: { queuedRequest in queuedRequest.plugin === plugin }) else {
            return nil
        }
        return SerialHostAnalysisQueuePosition(position: index + 1, totalCount: serialAnalysisQueue.count)
    }

    private static func nextQueuedSerialAnalysis() -> SerialHostAnalysisRequest? {
        serialAnalysisQueueLock.lock()
        defer { serialAnalysisQueueLock.unlock() }
        return serialAnalysisQueue.first
    }

    private static func publishSerialQueueStatuses() {
        serialAnalysisQueueLock.lock()
        let totalCount = serialAnalysisQueue.count
        let statuses = serialAnalysisQueue.enumerated().map { index, request in
            SerialHostAnalysisQueueStatus(
                plugin: request.plugin,
                position: index + 1,
                totalCount: totalCount,
                reason: request.reason,
                requestedSampleScalePercent: request.requestedSampleScalePercent
            )
        }
        serialAnalysisQueueLock.unlock()

        for status in statuses {
            status.plugin.hostAnalysisStore.markQueued(
                position: status.position,
                totalCount: status.totalCount,
                reason: status.reason,
                requestedSampleScalePercent: status.requestedSampleScalePercent
            )
            status.plugin.publishHostAnalysisStatus(force: true)
            status.plugin.publishStabilizerInfo(force: true)
            status.plugin.publishRenderRevision(status.plugin.hostAnalysisStore.renderInvalidationToken, force: true)
        }
    }

    private static func scheduleSerialAnalysisQueueDrain(after delay: TimeInterval = 1.0) {
        serialAnalysisQueueLock.lock()
        let hasQueuedRequest = !serialAnalysisQueue.isEmpty
        serialAnalysisQueueLock.unlock()

        guard hasQueuedRequest else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.0, delay)) {
            Self.runSerialAnalysisQueueDrainPass()
        }
    }

    private static func runSerialAnalysisQueueDrainPass() {
        serialAnalysisQueueLock.lock()
        let queuedCount = serialAnalysisQueue.count
        serialAnalysisQueueLock.unlock()

        NSLog("TokyoWalkingStabilizer: Serial Host Analysis queue drain pass saw \(queuedCount) queued request(s).")
        os_log(
            "Serial Host Analysis queue drain pass saw %{public}d queued request(s).",
            log: stabilizerHostAnalysisLog,
            type: .default,
            queuedCount
        )
        guard queuedCount > 0 else {
            os_log("Serial Host Analysis queue drain skipped because the queue is empty.", log: stabilizerHostAnalysisLog, type: .debug)
            return
        }

        os_log("Serial Host Analysis queue drain pass starting with %{public}d queued request(s).", log: stabilizerHostAnalysisLog, type: .default, queuedCount)
        startNextQueuedHostAnalysis()
    }

    private static func startNextQueuedHostAnalysis() {
        while let nextRequest = nextQueuedSerialAnalysis() {
            let result = nextRequest.plugin.requestHostAnalysisIfNeeded(
                force: true,
                allowSerialQueue: true,
                queuedStartRequest: true,
                queuedAnalysisAPI: nextRequest.analysisAPI,
                acceptedSampleScalePercentOverride: nextRequest.requestedSampleScalePercent
            )
            switch result {
            case .started, .queued:
                os_log(
                    "Serial Host Analysis queue drain stopped after result %{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    String(describing: result)
                )
                return
            case .skippedCompleted, .failed:
                os_log(
                    "Serial Host Analysis queue skipped one queued request after result %{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    String(describing: result)
                )
                continue
            }
        }
    }

    private static func reserveHostAnalysisStartIfAvailable() -> Bool {
        activeAnalysisStoreLock.lock()
        defer { activeAnalysisStoreLock.unlock() }
        guard !hostAnalysisStartReserved,
              activeAnalysisSessions.isEmpty
        else {
            return false
        }
        hostAnalysisStartReserved = true
        return true
    }

    private static func releaseHostAnalysisStartReservation() {
        activeAnalysisStoreLock.lock()
        hostAnalysisStartReserved = false
        activeAnalysisStoreLock.unlock()
    }

    private static func analysisStateDescription(_ state: FxAnalysisState) -> String {
        switch state {
        case kFxAnalysisState_NotAnalyzing:
            return "NotAnalyzing"
        case kFxAnalysisState_AnalysisRequested:
            return "AnalysisRequested"
        case kFxAnalysisState_AnalysisStarted:
            return "AnalysisStarted"
        case kFxAnalysisState_AnalysisCompleted:
            return "AnalysisCompleted"
        case kFxAnalysisState_AnalysisInterrupted:
            return "AnalysisInterrupted"
        default:
            return "Unknown(\(state))"
        }
    }

    private static func debugOverlayScale(outputWidth _: Int, outputHeight: Int, renderSourceIsProxy _: Bool) -> Float {
        let height = max(1, outputHeight)
        let panelRows = Float(STABILIZER_DEBUG_OVERLAY_ROW_COUNT)
        let rowHeight: Float = 13.0
        return max(Float(height) * 0.5 / (panelRows * rowHeight), 0.25)
    }

    private static func renderSourceAppearsProxy(
        sourceImage: FxImageTile,
        preparedAnalysis: StabilizerPreparedAnalysis?
    ) -> Bool {
        guard let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: sourceImage) else {
            return false
        }
        let pixelScaleDelta = max(abs(frameInfo.pixelScaleX - 1.0), abs(frameInfo.pixelScaleY - 1.0))
        if pixelScaleDelta > StabilizerOriginalMediaPolicy.proxyScaleTolerance {
            return true
        }
        guard let analysisFrame = preparedAnalysis?.frames.first else {
            return false
        }
        let analysisWidth = Float(max(1, analysisFrame.sampleWidth))
        let analysisHeight = Float(max(1, analysisFrame.sampleHeight))
        let sourceWidth = Float(max(1, frameInfo.sourceWidth))
        let sourceHeight = Float(max(1, frameInfo.sourceHeight))
        let widthRatio = sourceWidth / analysisWidth
        let heightRatio = sourceHeight / analysisHeight
        return widthRatio < 0.90 || heightRatio < 0.90
    }

    private static func renderSourceFrameInfoDescription(
        sourceImage: FxImageTile,
        preparedAnalysis: StabilizerPreparedAnalysis?
    ) -> String {
        guard let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: sourceImage) else {
            return "unavailable"
        }
        var description = String(
            format: "%dx%d scale %.3fx%.3f",
            frameInfo.sourceWidth,
            frameInfo.sourceHeight,
            frameInfo.pixelScaleX,
            frameInfo.pixelScaleY
        )
        if let analysisFrame = preparedAnalysis?.frames.first {
            let analysisWidth = Float(max(1, analysisFrame.sampleWidth))
            let analysisHeight = Float(max(1, analysisFrame.sampleHeight))
            let sourceWidth = Float(max(1, frameInfo.sourceWidth))
            let sourceHeight = Float(max(1, frameInfo.sourceHeight))
            description += String(
                format: " ratio %.3fx%.3f",
                sourceWidth / analysisWidth,
                sourceHeight / analysisHeight
            )
        }
        return description
    }

    private static func debugMatchQuality(residual: Float, preparedAnalysis: StabilizerPreparedAnalysis?) -> Float {
        guard residual.isFinite else {
            return 0.0
        }
        switch preparedAnalysis?.qualityModel {
        case .eventAnalyzerCache:
            return max(0.0, min(1.0, 1.0 - (residual / 48.0)))
        case .fxplugHostAnalysis, .none:
            return max(0.0, min(1.0, 1.0 - (residual * 0.7)))
        }
    }

    private static func debugOverlayUniform(
        _ metrics: StabilizerDebugOverlayMetrics
    ) -> StabilizerDebugOverlayDiagnostics {
        var diagnostics = StabilizerDebugOverlayDiagnostics()
        diagnostics.xOffset = metrics.xOffset
        diagnostics.yOffset = metrics.yOffset
        diagnostics.roll = metrics.roll
        diagnostics.crop = metrics.crop
        diagnostics.turn = metrics.turn
        diagnostics.macroJitter = metrics.macroJitter
        diagnostics.microJitter = metrics.microJitter
        diagnostics.farFieldWarp = metrics.farFieldWarp
        diagnostics.smoothing = metrics.smoothing
        diagnostics.trackingQuality = metrics.trackingQuality
        diagnostics.walkingQuality = metrics.walkingQuality
        diagnostics.sharpnessQuality = metrics.sharpnessQuality
        diagnostics.residualQuality = metrics.residualQuality
        diagnostics.searchRadiusHeadroomQuality = metrics.searchRadiusHeadroomQuality
        diagnostics.turnConfidence = metrics.turnConfidence
        diagnostics.macroConfidence = metrics.macroConfidence
        diagnostics.microConfidence = metrics.microConfidence
        diagnostics.warpConfidence = metrics.warpConfidence
        return diagnostics
    }

    private static func analysisRevisionCacheKey(_ revision: UInt64, cacheIdentity: String?) -> UInt64 {
        guard let identity = cacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identity.isEmpty
        else {
            return revision
        }
        // Persistent cache identity includes schema, range, sample size, frame count, and fingerprints.
        // Status-only store revision bumps must not invalidate render sampling caches for the same data.
        return 0
    }

    private static func normalizedAutoTransformRenderTime(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime
    ) -> CMTime {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let frames = preparedAnalysis.frames
        guard renderSeconds.isFinite,
              frames.count > 1
        else {
            return renderTime
        }
        if renderSeconds <= frames[0].time {
            return CMTimeMakeWithSeconds(frames[0].time, preferredTimescale: 60000)
        }
        let lastIndex = frames.count - 1
        if renderSeconds >= frames[lastIndex].time {
            return CMTimeMakeWithSeconds(frames[lastIndex].time, preferredTimescale: 60000)
        }

        var low = 0
        var high = lastIndex
        while high - low > 1 {
            let mid = (low + high) / 2
            if frames[mid].time <= renderSeconds {
                low = mid
            } else {
                high = mid
            }
        }

        let lowerDistance = abs(renderSeconds - frames[low].time)
        let upperDistance = abs(frames[high].time - renderSeconds)
        let frameSeconds = lowerDistance <= upperDistance ? frames[low].time : frames[high].time
        return CMTimeMakeWithSeconds(frameSeconds, preferredTimescale: 60000)
    }

    private static func playbackAutoTransformRenderTime(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime
    ) -> CMTime {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let frames = preparedAnalysis.frames
        guard renderSeconds.isFinite,
              frames.count > 1
        else {
            return renderTime
        }
        if renderSeconds <= frames[0].time {
            return CMTimeMakeWithSeconds(frames[0].time, preferredTimescale: 60000)
        }
        let lastSeconds = frames[frames.count - 1].time
        if renderSeconds >= lastSeconds {
            return CMTimeMakeWithSeconds(lastSeconds, preferredTimescale: 60000)
        }
        return renderTime
    }

    private static func cachedAutoTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        playbackMode: Bool = false,
        playbackPreparationScope: UUID? = nil,
        onPlaybackPreparationReady: (() -> Void)? = nil
    ) -> StabilizerAutoTransform {
        let firstFrame = preparedAnalysis.frames.first
        let qualityModelKey: Int
        switch preparedAnalysis.qualityModel {
        case .fxplugHostAnalysis:
            qualityModelKey = 0
        case .eventAnalyzerCache:
            qualityModelKey = 1
        }
        let cacheRenderTime = playbackMode
            ? playbackAutoTransformRenderTime(
                preparedAnalysis: preparedAnalysis,
                renderTime: renderTime
            )
            : normalizedAutoTransformRenderTime(
                preparedAnalysis: preparedAnalysis,
                renderTime: renderTime
            )
        let key = StabilizerAutoTransformCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            playbackMode: playbackMode,
            renderTimeValue: cacheRenderTime.value,
            renderTimeScale: cacheRenderTime.timescale,
            renderTimeEpoch: cacheRenderTime.epoch,
            outputWidth: Int32(clamping: Int(outputSize.x.rounded())),
            outputHeight: Int32(clamping: Int(outputSize.y.rounded())),
            analysisFrameCount: preparedAnalysis.frames.count,
            analysisFirstTime: firstFrame?.time.bitPattern ?? 0,
            analysisLastTime: preparedAnalysis.frames.last?.time.bitPattern ?? 0,
            analysisSampleWidth: Int32(clamping: firstFrame?.sampleWidth ?? 0),
            analysisSampleHeight: Int32(clamping: firstFrame?.sampleHeight ?? 0),
            analysisQualityModel: qualityModelKey,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            macroJitterX: strengths.macroJitterX.bitPattern,
            macroJitterY: strengths.macroJitterY.bitPattern,
            macroJitterRotation: strengths.macroJitterRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
            turnTransitionWindow: strengths.turnTransitionWindowSeconds.bitPattern,
            turnIdleReleaseSeconds: strengths.turnIdleReleaseSeconds.bitPattern
        )

        autoTransformCacheLock.lock()
        if let cachedTransform = autoTransformCache[key] {
            autoTransformCacheLock.unlock()
            return cachedTransform
        }
        autoTransformCacheLock.unlock()

        let transform: StabilizerAutoTransform
        let shouldCacheTransform: Bool
        if playbackMode {
            if let readyTransform = AutoStabilizationEstimator.playbackEstimateIfReadyOrSchedulePreparation(
                preparedAnalysis: preparedAnalysis,
                renderTime: cacheRenderTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                waitForPreparation: false,
                preparationScope: playbackPreparationScope,
                onPrepared: onPlaybackPreparationReady
            ) {
                transform = readyTransform
                shouldCacheTransform = true
            } else {
                transform = AutoStabilizationEstimator.playbackPreparedPathLookupEstimate(
                    preparedAnalysis: preparedAnalysis,
                    renderSeconds: CMTimeGetSeconds(cacheRenderTime),
                    outputSize: outputSize
                )
                shouldCacheTransform = false
            }
        } else {
            transform = AutoStabilizationEstimator.estimate(
                preparedAnalysis: preparedAnalysis,
                renderTime: cacheRenderTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
            shouldCacheTransform = true
        }

        guard shouldCacheTransform else {
            return transform
        }

        autoTransformCacheLock.lock()
        defer { autoTransformCacheLock.unlock() }
        if let cachedTransform = autoTransformCache[key] {
            return cachedTransform
        }
        autoTransformCache[key] = transform
        autoTransformCacheOrder.append(key)
        while autoTransformCacheOrder.count > autoTransformCacheLimit {
            let oldestKey = autoTransformCacheOrder.removeFirst()
            autoTransformCache.removeValue(forKey: oldestKey)
        }
        return transform
    }

    private static func cachedAutoCropFraming(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDuration: Double,
        leadTime: Double,
        holdTime: Double,
        samplingProfile: AutoCropSamplingProfile,
        renderQualityLevel: UInt32,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        playbackPreparationScope: UUID? = nil,
        onPlaybackPreparationReady: (() -> Void)? = nil
    ) -> AutoCropFraming {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        if samplingProfile == .playback {
            let playbackRenderTime = playbackAutoTransformRenderTime(
                preparedAnalysis: preparedAnalysis,
                renderTime: renderTime
            )
            let playbackSeconds = CMTimeGetSeconds(playbackRenderTime)
            return autoCropPlaybackFraming(
                preparedAnalysis: preparedAnalysis,
                renderSeconds: playbackSeconds,
                currentTransform: currentTransform,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                transitionDuration: transitionDuration,
                leadTime: leadTime,
                holdTime: holdTime,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity,
                preparationScope: playbackPreparationScope,
                onPrepared: onPlaybackPreparationReady
            )
        }
        let framingSeconds = renderSeconds.isFinite
            ? autoCropSampleTime(renderSeconds, samplingProfile: samplingProfile)
            : renderSeconds
        let framingRenderTime = (renderSeconds.isFinite && abs(framingSeconds - renderSeconds) > 1e-9)
            ? CMTimeMakeWithSeconds(framingSeconds, preferredTimescale: 60000)
            : renderTime
        let framingTransform = (renderSeconds.isFinite && abs(framingSeconds - renderSeconds) > 1e-9)
            ? autoCropActualSampleTransform(
                preparedAnalysis: preparedAnalysis,
                currentSeconds: renderSeconds,
                sampleSeconds: framingSeconds,
                currentTransform: currentTransform,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
            : currentTransform
        let key = AutoCropFramingCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            renderTimeValue: framingRenderTime.value,
            renderTimeScale: framingRenderTime.timescale,
            renderTimeEpoch: framingRenderTime.epoch,
            outputWidth: Int32(clamping: Int(outputSize.x.rounded())),
            outputHeight: Int32(clamping: Int(outputSize.y.rounded())),
            analysisFrameCount: preparedAnalysis.frames.count,
            analysisFirstTime: preparedAnalysis.frames.first?.time.bitPattern ?? 0,
            analysisLastTime: preparedAnalysis.frames.last?.time.bitPattern ?? 0,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDuration.bitPattern,
            leadTime: leadTime.bitPattern,
            holdTime: holdTime.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            renderQualityLevel: renderQualityLevel,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            macroJitterX: strengths.macroJitterX.bitPattern,
            macroJitterY: strengths.macroJitterY.bitPattern,
            macroJitterRotation: strengths.macroJitterRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
            turnTransitionWindow: strengths.turnTransitionWindowSeconds.bitPattern,
            currentTransform: AutoCropTransformSignature(framingTransform)
        )

        autoCropFramingCacheLock.lock()
        if let cachedFraming = autoCropFramingCache[key] {
            autoCropFramingCacheLock.unlock()
            return cachedFraming
        }
        autoCropFramingCacheLock.unlock()

        let framing = autoCropFraming(
            preparedAnalysis: preparedAnalysis,
            renderTime: framingRenderTime,
            currentTransform: framingTransform,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDuration: transitionDuration,
            leadTime: leadTime,
            holdTime: holdTime,
            samplingProfile: samplingProfile,
            renderQualityLevel: renderQualityLevel,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )

        autoCropFramingCacheLock.lock()
        defer { autoCropFramingCacheLock.unlock() }
        if let cachedFraming = autoCropFramingCache[key] {
            return cachedFraming
        }
        autoCropFramingCache[key] = framing
        autoCropFramingCacheOrder.append(key)
        while autoCropFramingCacheOrder.count > autoCropFramingCacheLimit {
            let oldestKey = autoCropFramingCacheOrder.removeFirst()
            autoCropFramingCache.removeValue(forKey: oldestKey)
        }
        return framing
    }

    private static func turnSmoothingZoomNormalized(_ value: Double) -> Float {
        let boundedValue = min(
            max(Float(value.isFinite ? value : 0.0), 0.0),
            Float(stabilizerMaximumTurnSmoothingZoom)
        )
        return boundedValue / max(Float(stabilizerMaximumTurnSmoothingZoom), Float.ulpOfOne)
    }

    private static func turnViewportAuthority(_ value: Double) -> Float {
        let boundedValue = min(max(Float(value.isFinite ? value : 0.0), 0.0), 36.0)
        // New contract: 12 equals the former full (36) viewport authority and
        // 36 applies three times that zoom and X movement.
        return boundedValue / 12.0
    }

    private static func fullTurnAnalysisStrengths(
        _ strengths: StabilizerCorrectionStrengths
    ) -> StabilizerCorrectionStrengths {
        guard turnViewportAuthority(strengths.turnSmoothingZoom) > Float.ulpOfOne else {
            return strengths
        }
        // Generate one stable full-authority Turn path, then apply the UI value
        // exactly once in viewport space. This avoids estimator x viewport
        // double scaling and makes 12 match the former 36 result.
        return StabilizerCorrectionStrengths(
            cameraJitterX: strengths.cameraJitterX,
            cameraJitterY: strengths.cameraJitterY,
            cameraJitterRotation: strengths.cameraJitterRotation,
            farFieldWarp: strengths.farFieldWarp,
            turnSmoothingZoom: 36.0,
            turnViewportStrength: strengths.turnViewportStrength,
            turnTransitionWindowSeconds: strengths.turnTransitionWindowSeconds,
            turnIdleReleaseSeconds: strengths.turnIdleReleaseSeconds
        )
    }

    private static func turnViewportPlanningTransform(
        _ transform: StabilizerAutoTransform,
        turnSmoothingStrength: Double
    ) -> StabilizerAutoTransform {
        var plannedTransform = transform
        let fullTurnMacroX = transform.macroPixelOffset.x
        let plannedTurnMacroX = fullTurnMacroX * turnViewportAuthority(turnSmoothingStrength)
        let turnDeltaX = plannedTurnMacroX - fullTurnMacroX
        plannedTransform.macroPixelOffset.x += turnDeltaX
        plannedTransform.pixelOffset.x += turnDeltaX
        plannedTransform.rawPixelOffset.x += turnDeltaX
        return plannedTransform
    }

    private static func cropOffDiagnosticFraming(
        autoCropFraming: AutoCropFraming
    ) -> AutoCropFraming {
        AutoCropFraming(
            scale: 1.0,
            positionPixels: autoCropFraming.positionPixels,
            telemetry: autoCropFraming.telemetry,
            cropOffEdgeGuardScale: 1.0,
            cropOffEdgeGuardDemandX: 0.0,
            cropOffEdgeGuardActive: 0.0
        )
    }

    private static func turnSmoothingZoomCapScale(_ value: Double) -> Float {
        let zoomDelta = max(Float(0.0), stabilizerMaximumTurnSmoothingZoomScale - Float(1.0))
        return Float(1.0) + (turnSmoothingZoomNormalized(value) * zoomDelta)
    }

    private static func cropOffTurnSmoothingExposureSupport(
        currentTransform: StabilizerAutoTransform,
        masterStrength: Float,
        strengths: StabilizerCorrectionStrengths
    ) -> Float {
        let zoomSupport = turnSmoothingZoomNormalized(strengths.turnSmoothingZoom)
        guard zoomSupport > Float.ulpOfOne,
              masterStrength.isFinite,
              masterStrength > Float.ulpOfOne
        else {
            return 0.0
        }
        let turnPixels = abs(currentTransform.turnDetectedPixelOffset.x) * max(0.0, masterStrength)
        let travelSupport = thresholdRamp(
            turnPixels,
            start: stabilizerAutoCropTurnSmoothingZoomStartPixels * 0.5,
            full: stabilizerAutoCropTurnSmoothingZoomFullPixels * 0.70
        )
        guard travelSupport > Float.ulpOfOne else {
            return 0.0
        }
        let confidenceSupport = thresholdRamp(
            min(max(currentTransform.turnConfidence, 0.0), 1.0),
            start: stabilizerAutoCropTurnSmoothingZoomConfidenceStart,
            full: stabilizerAutoCropTurnSmoothingZoomConfidenceFull
        )
        return min(max(zoomSupport * travelSupport * confidenceSupport, 0.0), 1.0)
    }

    private static func autoCropFraming(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDuration: Double,
        leadTime: Double,
        holdTime: Double,
        samplingProfile: AutoCropSamplingProfile,
        renderQualityLevel: UInt32,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropFraming {
        guard masterStrength > 0.0001,
              outputSize.x > 1.0,
              outputSize.y > 1.0
        else {
            return .identity
        }

        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return .identity
        }

        let transitionDurationSeconds = autoCropTransitionDurationSeconds(transitionDuration)
        let leadTimeSeconds = autoCropLeadTimeSeconds(leadTime)
        let holdTimeSeconds = autoCropHoldTimeSeconds(holdTime)
        if samplingProfile == .playback {
            return autoCropPlaybackFraming(
                preparedAnalysis: preparedAnalysis,
                renderSeconds: renderSeconds,
                currentTransform: currentTransform,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                transitionDuration: transitionDuration,
                leadTime: leadTime,
                holdTime: holdTime,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
        }
        let context = AutoCropTransformContext(
            transform: currentTransform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let scaleDemand = cachedAutoCropScaleDemand(
            preparedAnalysis: preparedAnalysis,
            centerSeconds: renderSeconds,
            centerTransform: currentTransform,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        let zoomPlan = cachedAutoCropZoomPlan(
            preparedAnalysis: preparedAnalysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        let plannedFraming = autoCropZoomPlanSample(
            zoomPlan,
            at: renderSeconds
        )
        let activeProtectedScale = max(Float(1.0), plannedFraming.scale)
        let idleReleaseProgress = autoCropIdleScaleReleaseProgress(
            preparedAnalysis: preparedAnalysis,
            currentSeconds: renderSeconds,
            currentTransform: currentTransform,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            protectedScale: Float(1.0)
        )
        let quietCurrentTransform = autoCropTransformIsQuiet(
            currentTransform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let planIsActive = plannedFraming.influence > 0.0001
        let release = (!planIsActive && quietCurrentTransform) ? min(max(idleReleaseProgress, 0.0), 1.0) : 0.0
        let neutralProtectedScale = Float(1.0)
        let protectedScale = activeProtectedScale + ((neutralProtectedScale - activeProtectedScale) * release)
        let finalScale = autoCropKeypointScale(protectedScale: protectedScale)
        let releasedPositionPixels = release > 0.0
            ? plannedFraming.positionPixels + ((scaleDemand.neutralPositionPixels - plannedFraming.positionPixels) * release)
            : plannedFraming.positionPixels

        let finalPositionPixels = autoCropStableScaleBudgetedPositionPixels(
            stablePositionPixels: releasedPositionPixels,
            clampPositionPixels: scaleDemand.currentPositionPixels,
            context: context,
            scale: finalScale,
            samplingProfile: samplingProfile
        )
        if !autoCropPosition(
            finalPositionPixels,
            fitsWithinScale: finalScale,
            context: context,
            samplingProfile: samplingProfile
        ) {
            os_log(
                "Auto Crop coverage miss | render %.3f scale %.4f plannedScale %.4f peak %.3f",
                log: stabilizerHostAnalysisLog,
                type: .error,
                renderSeconds,
                finalScale,
                plannedFraming.scale,
                plannedFraming.peakSeconds ?? -1.0
            )
        }

        return AutoCropFraming(
            scale: finalScale,
            positionPixels: finalPositionPixels,
            telemetry: zoomPlan.telemetry
        )
    }

    private static func autoCropTransitionDurationSeconds(_ duration: Double) -> Double {
        min(max(duration, 0.0), stabilizerMaximumAutoCropTransitionDuration)
    }

    private static func autoCropLeadTimeSeconds(_ leadTime: Double) -> Double {
        min(max(leadTime, 0.0), stabilizerMaximumAutoCropLeadTime)
    }

    private static func autoCropHoldTimeSeconds(_ holdTime: Double) -> Double {
        min(max(holdTime, 0.0), stabilizerMaximumAutoCropHoldTime)
    }

    private static func linearRamp(_ progress: Float) -> Float {
        min(max(progress, 0.0), 1.0)
    }

    private static func thresholdRamp(_ value: Float, start: Float, full: Float) -> Float {
        guard value.isFinite,
              start.isFinite,
              full.isFinite,
              full > start + Float.ulpOfOne
        else {
            return 0.0
        }
        return linearRamp((value - start) / (full - start))
    }

    private static func easeInOutRamp(_ progress: Float) -> Float {
        let t = linearRamp(progress)
        return t * t * t * (t * ((t * 6.0) - 15.0) + 10.0)
    }

    private static func cachedAutoCropScaleDemand(
        preparedAnalysis: StabilizerPreparedAnalysis,
        centerSeconds: Double,
        centerTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropScaleDemand {
        let frames = preparedAnalysis.frames
        let key = AutoCropScaleDemandCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            centerSeconds: centerSeconds.bitPattern,
            outputWidth: Int32(outputSize.x.rounded()),
            outputHeight: Int32(outputSize.y.rounded()),
            analysisFrameCount: frames.count,
            analysisFirstTime: frames.first?.time.bitPattern ?? 0,
            analysisLastTime: frames.last?.time.bitPattern ?? 0,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDurationSeconds.bitPattern,
            leadTime: leadTimeSeconds.bitPattern,
            holdTime: holdTimeSeconds.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            macroJitterX: strengths.macroJitterX.bitPattern,
            macroJitterY: strengths.macroJitterY.bitPattern,
            macroJitterRotation: strengths.macroJitterRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
            turnTransitionWindow: strengths.turnTransitionWindowSeconds.bitPattern,
            centerTransform: AutoCropTransformSignature(centerTransform)
        )

        autoCropScaleDemandCacheLock.lock()
        if let cachedDemand = autoCropScaleDemandCache[key] {
            autoCropScaleDemandCacheLock.unlock()
            return cachedDemand
        }
        autoCropScaleDemandCacheLock.unlock()

        let demand = autoCropScaleDemand(
            preparedAnalysis: preparedAnalysis,
            centerSeconds: centerSeconds,
            centerTransform: centerTransform,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile
        )

        autoCropScaleDemandCacheLock.lock()
        defer { autoCropScaleDemandCacheLock.unlock() }
        if let cachedDemand = autoCropScaleDemandCache[key] {
            return cachedDemand
        }
        autoCropScaleDemandCache[key] = demand
        autoCropScaleDemandCacheOrder.append(key)
        while autoCropScaleDemandCacheOrder.count > autoCropScaleDemandCacheLimit {
            let oldestKey = autoCropScaleDemandCacheOrder.removeFirst()
            autoCropScaleDemandCache.removeValue(forKey: oldestKey)
        }
        return demand
    }

    private static func autoCropScaleDemand(
        preparedAnalysis: StabilizerPreparedAnalysis,
        centerSeconds: Double,
        centerTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile
    ) -> AutoCropScaleDemand {
        let context = AutoCropTransformContext(
            transform: centerTransform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let currentPositionPixels = blackSafeAutoCropPosition(
            preferredPositionPixels: centerTransform.macroPixelOffset * masterStrength,
            context: context,
            samplingProfile: samplingProfile
        )
        let neutralPositionPixels = blackSafeAutoCropPosition(
            preferredPositionPixels: vector_float2(0.0, 0.0),
            context: context,
            samplingProfile: samplingProfile
        )
        return AutoCropScaleDemand(
            currentPositionPixels: currentPositionPixels,
            neutralPositionPixels: neutralPositionPixels
        )
    }

    private static func cachedAutoCropZoomPlan(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropZoomPlan {
        let frames = preparedAnalysis.frames
        let key = AutoCropZoomPlanCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            outputWidth: Int32(outputSize.x.rounded()),
            outputHeight: Int32(outputSize.y.rounded()),
            analysisFrameCount: frames.count,
            analysisFirstTime: frames.first?.time.bitPattern ?? 0,
            analysisLastTime: frames.last?.time.bitPattern ?? 0,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDurationSeconds.bitPattern,
            leadTime: leadTimeSeconds.bitPattern,
            holdTime: holdTimeSeconds.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            macroJitterX: strengths.macroJitterX.bitPattern,
            macroJitterY: strengths.macroJitterY.bitPattern,
            macroJitterRotation: strengths.macroJitterRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
            turnTransitionWindow: strengths.turnTransitionWindowSeconds.bitPattern
        )

        autoCropZoomPlanCacheLock.lock()
        if let cachedPlan = autoCropZoomPlanCache[key] {
            autoCropZoomPlanCacheLock.unlock()
            return cachedPlan
        }
        autoCropZoomPlanCacheLock.unlock()

        let plan = autoCropZoomPlan(
            preparedAnalysis: preparedAnalysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )

        autoCropZoomPlanCacheLock.lock()
        defer { autoCropZoomPlanCacheLock.unlock() }
        if let cachedPlan = autoCropZoomPlanCache[key] {
            return cachedPlan
        }
        autoCropZoomPlanCache[key] = plan
        autoCropZoomPlanCacheOrder.append(key)
        while autoCropZoomPlanCacheOrder.count > autoCropZoomPlanCacheLimit {
            let oldestKey = autoCropZoomPlanCacheOrder.removeFirst()
            autoCropZoomPlanCache.removeValue(forKey: oldestKey)
        }
        return plan
    }

    private static func autoCropPlaybackScalePlanCacheKey(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropPlaybackScalePlanCacheKey {
        let frames = preparedAnalysis.frames
        return AutoCropPlaybackScalePlanCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            outputWidth: Int32(outputSize.x.rounded()),
            outputHeight: Int32(outputSize.y.rounded()),
            analysisFrameCount: frames.count,
            analysisFirstTime: frames.first?.time.bitPattern ?? 0,
            analysisLastTime: frames.last?.time.bitPattern ?? 0,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDurationSeconds.bitPattern,
            leadTime: leadTimeSeconds.bitPattern,
            holdTime: holdTimeSeconds.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            macroJitterX: strengths.macroJitterX.bitPattern,
            macroJitterY: strengths.macroJitterY.bitPattern,
            macroJitterRotation: strengths.macroJitterRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
            turnTransitionWindow: strengths.turnTransitionWindowSeconds.bitPattern
        )
    }

    private static func autoCropPlaybackScalePlanOutputSize(
        preparedAnalysis: StabilizerPreparedAnalysis,
        requestedOutputSize: vector_float2
    ) -> vector_float2 {
        guard requestedOutputSize.x.isFinite,
              requestedOutputSize.y.isFinite,
              requestedOutputSize.x > Float.ulpOfOne,
              requestedOutputSize.y > Float.ulpOfOne,
              let firstFrame = preparedAnalysis.frames.first
        else {
            return requestedOutputSize
        }

        let sampleWidth = Float(max(1, firstFrame.sampleWidth))
        let sampleHeight = Float(max(1, firstFrame.sampleHeight))
        let sourceAspect = sampleWidth / sampleHeight
        let requestedAspect = requestedOutputSize.x / requestedOutputSize.y
        let aspect = abs((requestedAspect / sourceAspect) - 1.0) <= 0.015
            ? sourceAspect
            : requestedAspect
        return vector_float2(
            max(1.0, sampleHeight * aspect),
            sampleHeight
        )
    }

    private static func cachedAutoCropPlaybackScalePlan(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropPlaybackScalePlan {
        let planOutputSize = autoCropPlaybackScalePlanOutputSize(
            preparedAnalysis: preparedAnalysis,
            requestedOutputSize: outputSize
        )
        let key = autoCropPlaybackScalePlanCacheKey(
            preparedAnalysis: preparedAnalysis,
            outputSize: planOutputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        autoCropPlaybackScalePlanCacheLock.lock()
        if let cachedPlan = autoCropPlaybackScalePlanCache[key] {
            autoCropPlaybackScalePlanCacheLock.unlock()
            return cachedPlan
        }
        autoCropPlaybackScalePlanCacheLock.unlock()

        guard let plan = autoCropPlaybackScalePlan(
            preparedAnalysis: preparedAnalysis,
            outputSize: planOutputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            shouldCancel: { false }
        ) else {
            preconditionFailure("Uncancellable Auto Crop playback preparation was cancelled")
        }

        autoCropPlaybackScalePlanCacheLock.lock()
        defer { autoCropPlaybackScalePlanCacheLock.unlock() }
        if let cachedPlan = autoCropPlaybackScalePlanCache[key] {
            return cachedPlan
        }
        autoCropPlaybackScalePlanCache[key] = plan
        autoCropPlaybackScalePlanCacheOrder.append(key)
        while autoCropPlaybackScalePlanCacheOrder.count > autoCropPlaybackScalePlanCacheLimit {
            let oldestKey = autoCropPlaybackScalePlanCacheOrder.removeFirst()
            autoCropPlaybackScalePlanCache.removeValue(forKey: oldestKey)
        }
        return plan
    }

    private static func cachedAutoCropPlaybackScalePlanIfReadyOrSchedulePreparation(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        preparationScope: UUID? = nil,
        waitForPreparation: Bool = false,
        onPrepared: (() -> Void)? = nil
    ) -> AutoCropPlaybackScalePlan? {
        let planOutputSize = autoCropPlaybackScalePlanOutputSize(
            preparedAnalysis: preparedAnalysis,
            requestedOutputSize: outputSize
        )
        let key = autoCropPlaybackScalePlanCacheKey(
            preparedAnalysis: preparedAnalysis,
            outputSize: planOutputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )

        var supersededPreviousRequest = false
        var supersededCountSnapshot: UInt64 = 0
        autoCropPlaybackScalePlanCacheLock.lock()
        if let preparationScope {
            let previousKey = latestAutoCropPlaybackScalePlanKeyByScope[preparationScope]
            if previousKey != key {
                supersededPreviousRequest = previousKey != nil
                latestAutoCropPlaybackScalePlanKeyByScope[preparationScope] = key
                for callbackKey in Array(autoCropPlaybackScalePlanPreparationCallbacks.keys) {
                    autoCropPlaybackScalePlanPreparationCallbacks[callbackKey]?.removeAll {
                        $0.scope == preparationScope
                    }
                    if autoCropPlaybackScalePlanPreparationCallbacks[callbackKey]?.isEmpty == true {
                        autoCropPlaybackScalePlanPreparationCallbacks.removeValue(forKey: callbackKey)
                    }
                }
                if supersededPreviousRequest {
                    supersededAutoCropPlaybackRequestCount &+= 1
                }
            }
        }
        supersededCountSnapshot = supersededAutoCropPlaybackRequestCount
        let cachedPlan = autoCropPlaybackScalePlanCache[key]
        if let cachedPlan {
            autoCropPlaybackScalePlanCacheLock.unlock()
            if supersededPreviousRequest {
                os_log(
                    "Auto Crop playback request superseded | total %llu",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    supersededCountSnapshot
                )
            }
            return cachedPlan
        }
        if waitForPreparation {
            autoCropPlaybackScalePlanCacheLock.unlock()
            let startedAt = CFAbsoluteTimeGetCurrent()
            let plan = cachedAutoCropPlaybackScalePlan(
                preparedAnalysis: preparedAnalysis,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                transitionDurationSeconds: transitionDurationSeconds,
                leadTimeSeconds: leadTimeSeconds,
                holdTimeSeconds: holdTimeSeconds,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
            os_log(
                "Auto Crop playback scale plan prepared inline | samples %d peak %.3f peakScale %.4f elapsed %.3fms",
                log: stabilizerHostAnalysisLog,
                type: .default,
                plan.sampleCount,
                plan.peakSeconds ?? -1.0,
                plan.peakScale,
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
            )
            return plan
        }
        guard !autoCropPlaybackScalePlanPreparations.contains(key) else {
            if let onPrepared {
                if let preparationScope {
                    autoCropPlaybackScalePlanPreparationCallbacks[key]?.removeAll {
                        $0.scope == preparationScope
                    }
                }
                autoCropPlaybackScalePlanPreparationCallbacks[key, default: []].append(
                    AutoCropPlaybackPreparationCallback(scope: preparationScope, callback: onPrepared)
                )
            }
            autoCropPlaybackScalePlanCacheLock.unlock()
            return nil
        }
        autoCropPlaybackScalePlanPreparations.insert(key)
        if let onPrepared {
            if let preparationScope {
                autoCropPlaybackScalePlanPreparationCallbacks[key]?.removeAll {
                    $0.scope == preparationScope
                }
            }
            autoCropPlaybackScalePlanPreparationCallbacks[key, default: []].append(
                AutoCropPlaybackPreparationCallback(scope: preparationScope, callback: onPrepared)
            )
        }
        autoCropPlaybackScalePlanCacheLock.unlock()

        autoCropPlaybackScalePlanPreparationQueue.async {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let shouldCancel: () -> Bool = {
                guard preparationScope != nil else {
                    return false
                }
                autoCropPlaybackScalePlanCacheLock.lock()
                let stillDesired = latestAutoCropPlaybackScalePlanKeyByScope.values.contains(key)
                autoCropPlaybackScalePlanCacheLock.unlock()
                return !stillDesired
            }
            let finishWithoutPlan: (_ reason: String) -> Void = { reason in
                autoCropPlaybackScalePlanCacheLock.lock()
                autoCropPlaybackScalePlanPreparations.remove(key)
                autoCropPlaybackScalePlanPreparationCallbacks.removeValue(forKey: key)
                let supersededCount = supersededAutoCropPlaybackRequestCount
                autoCropPlaybackScalePlanCacheLock.unlock()
                os_log(
                    "Auto Crop playback scale plan not published | reason %{public}@ elapsed %.3fms superseded %llu",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    reason,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0,
                    supersededCount
                )
            }
            guard !shouldCancel() else {
                finishWithoutPlan("superseded-before-start")
                return
            }
            let trajectoryWasReady = AutoStabilizationEstimator.playbackTrajectoryIsReady(
                preparedAnalysis: preparedAnalysis,
                panSmoothSeconds: panSmoothSeconds,
                strengths: fullTurnAnalysisStrengths(strengths)
            )
            if preparationScope != nil, !trajectoryWasReady {
                // The playback trajectory completion callback invalidates the
                // latest render. Auto Crop must never synchronously regenerate
                // an older trajectory while that canonical path is pending.
                finishWithoutPlan("canonical-trajectory-pending")
                return
            }
            guard let plan = autoCropPlaybackScalePlan(
                preparedAnalysis: preparedAnalysis,
                outputSize: planOutputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                transitionDurationSeconds: transitionDurationSeconds,
                leadTimeSeconds: leadTimeSeconds,
                holdTimeSeconds: holdTimeSeconds,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity,
                shouldCancel: shouldCancel
            ) else {
                finishWithoutPlan("superseded-during-build")
                return
            }
            guard !shouldCancel() else {
                finishWithoutPlan("superseded-after-build")
                return
            }
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
            autoCropPlaybackScalePlanCacheLock.lock()
            autoCropPlaybackScalePlanPreparations.remove(key)
            let callbacks = (autoCropPlaybackScalePlanPreparationCallbacks.removeValue(forKey: key) ?? []).filter { entry in
                guard let scope = entry.scope else {
                    return true
                }
                return latestAutoCropPlaybackScalePlanKeyByScope[scope] == key
            }
            if autoCropPlaybackScalePlanCache[key] == nil {
                autoCropPlaybackScalePlanCache[key] = plan
                autoCropPlaybackScalePlanCacheOrder.removeAll { $0 == key }
                autoCropPlaybackScalePlanCacheOrder.append(key)
                while autoCropPlaybackScalePlanCacheOrder.count > autoCropPlaybackScalePlanCacheLimit {
                    let oldestKey = autoCropPlaybackScalePlanCacheOrder.removeFirst()
                    autoCropPlaybackScalePlanCache.removeValue(forKey: oldestKey)
                    autoCropPlaybackScalePlanPreparations.remove(oldestKey)
                    autoCropPlaybackScalePlanPreparationCallbacks.removeValue(forKey: oldestKey)
                }
                os_log(
                    "Auto Crop playback final key prepared | revision %llu turn %.2f cache %{public}@ samples %d peak %.3f peakScale %.4f trajectoryWasReady %{public}@ elapsed %.3fms superseded %llu",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    analysisRevision,
                    strengths.turnSmoothingZoom,
                    cacheIdentity ?? "none",
                    plan.sampleCount,
                    plan.peakSeconds ?? -1.0,
                    plan.peakScale,
                    trajectoryWasReady ? "yes" : "no",
                    elapsedMilliseconds,
                    supersededAutoCropPlaybackRequestCount
                )
            }
            autoCropPlaybackScalePlanCacheLock.unlock()
            callbacks.forEach { entry in
                DispatchQueue.main.async(execute: entry.callback)
            }
        }
        return nil
    }

    private static func cancelAutoCropPlaybackPreparations(for scope: UUID) {
        autoCropPlaybackScalePlanCacheLock.lock()
        latestAutoCropPlaybackScalePlanKeyByScope.removeValue(forKey: scope)
        for key in Array(autoCropPlaybackScalePlanPreparationCallbacks.keys) {
            autoCropPlaybackScalePlanPreparationCallbacks[key]?.removeAll { $0.scope == scope }
            if autoCropPlaybackScalePlanPreparationCallbacks[key]?.isEmpty == true {
                autoCropPlaybackScalePlanPreparationCallbacks.removeValue(forKey: key)
            }
        }
        autoCropPlaybackScalePlanCacheLock.unlock()
    }

    private static func autoCropPlaybackScalePlan(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        shouldCancel: @escaping () -> Bool = { false }
    ) -> AutoCropPlaybackScalePlan? {
        guard !shouldCancel() else {
            return nil
        }
        guard masterStrength > 0.0001,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              let firstTime = preparedAnalysis.frames.first?.time,
              let lastTime = preparedAnalysis.frames.last?.time,
              firstTime <= lastTime
        else {
            return .identity
        }

        let playbackSampleSeconds = autoCropPlaybackScalePlanSampleSeconds(
            preparedAnalysis: preparedAnalysis,
            firstTime: firstTime,
            lastTime: lastTime
        )
        guard !shouldCancel() else {
            return nil
        }
        return autoCropPlaybackScalePlan(
            preparedAnalysis: preparedAnalysis,
            playbackSampleSeconds: playbackSampleSeconds,
            firstTime: firstTime,
            lastTime: lastTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            shouldCancel: shouldCancel
        )
    }

    private static func autoCropPlaybackScalePlan(
        preparedAnalysis: StabilizerPreparedAnalysis,
        playbackSampleSeconds: [Double],
        firstTime: Double,
        lastTime: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        shouldCancel: @escaping () -> Bool
    ) -> AutoCropPlaybackScalePlan? {
        guard !shouldCancel() else {
            return nil
        }
        guard masterStrength > 0.0001,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              firstTime.isFinite,
              lastTime.isFinite,
              firstTime <= lastTime
        else {
            return .identity
        }

        let phasesStartedAt = CFAbsoluteTimeGetCurrent()
        let planStepSeconds = autoCropPlaybackScalePlanStepSeconds(samples: playbackSampleSeconds)
        let preparedPlaybackTransforms: [StabilizerAutoTransform]?
        if samplingProfile == .playback {
            guard let readyTransforms = AutoStabilizationEstimator.playbackEstimatesIfReady(
                preparedAnalysis: preparedAnalysis,
                sampleSeconds: playbackSampleSeconds,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: fullTurnAnalysisStrengths(strengths),
                shouldCancel: shouldCancel
            ) else {
                return nil
            }
            preparedPlaybackTransforms = readyTransforms
        } else {
            preparedPlaybackTransforms = nil
        }
        let rawDemandSamples = autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            sampleSeconds: playbackSampleSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            turnZoomLookaheadSeconds: leadTimeSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            preparedPlaybackTransforms: preparedPlaybackTransforms
        )
        guard !shouldCancel() else {
            return nil
        }
        let filteredDemand = autoCropPlaybackFilteredDemandSamples(
            rawDemandSamples,
            outputSize: outputSize
        )
        let samples = filteredDemand.samples
        guard !samples.isEmpty else {
            return .identity
        }
        let demandCompletedAt = CFAbsoluteTimeGetCurrent()

        var protectedDemandSamples: [AutoCropPlaybackProtectedDemandSample] = []
        protectedDemandSamples.reserveCapacity(samples.count)
        var peakScale = Float(1.0)
        var peakSeconds: Double?
        var minimumClippedDemandSampleCount = 0
        let activeDemandScale = Float(1.0) + stabilizerAutoCropKeypointCoverageThresholdDelta
        for sample in samples {
            let safeSampleScale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
            guard safeSampleScale > activeDemandScale else {
                continue
            }
            let minimumClippedScale = autoCropPlaybackMinimumClippedScale(
                autoCropPlaybackQuantizedScale(safeSampleScale)
            )
            if minimumClippedScale > safeSampleScale + 0.00001 {
                minimumClippedDemandSampleCount += 1
            }
            let protectedScale = max(
                autoCropZoomKeypointScale(forDemandScale: safeSampleScale),
                minimumClippedScale
            )
            let neutralPosition = autoCropPlaybackFinitePosition(
                sample.neutralPositionPixels,
                fallback: sample.positionPixels
            )
            let demandPosition = autoCropPlaybackFinitePosition(
                sample.positionPixels,
                fallback: neutralPosition
            )
            protectedDemandSamples.append(
                AutoCropPlaybackProtectedDemandSample(
                    seconds: sample.seconds,
                    scale: protectedScale,
                    positionPixels: demandPosition
                )
            )
            if protectedScale > peakScale {
                peakScale = protectedScale
                peakSeconds = sample.seconds
            }
        }

        guard !shouldCancel() else {
            return nil
        }

        guard !protectedDemandSamples.isEmpty else {
            return .identity
        }

        let leadSeconds = max(0.0, leadTimeSeconds.isFinite ? leadTimeSeconds : 0.0)
        let holdSeconds = max(0.0, holdTimeSeconds.isFinite ? holdTimeSeconds : 0.0)
        let releaseSeconds = max(0.0, transitionDurationSeconds.isFinite ? transitionDurationSeconds : 0.0)
        let playbackKeypoints = protectedDemandSamples.map { demandSample in
            AutoCropZoomKeypoint(
                peakSeconds: demandSample.seconds,
                startSeconds: max(firstTime, demandSample.seconds - leadSeconds),
                holdEndSeconds: min(lastTime, demandSample.seconds + holdSeconds),
                endSeconds: min(lastTime, demandSample.seconds + holdSeconds + releaseSeconds),
                scale: demandSample.scale,
                positionPixels: demandSample.positionPixels
            )
        }
        let capLeadSeconds = min(leadSeconds, stabilizerAutoCropPlaybackCapLeadSeconds)
        let capHoldSeconds = min(max(holdSeconds, planStepSeconds), stabilizerAutoCropPlaybackCapHoldSeconds)
        let capReleaseSeconds = min(releaseSeconds, stabilizerAutoCropPlaybackCapReleaseSeconds)
        let capKeypoints = protectedDemandSamples.map { demandSample in
            AutoCropZoomKeypoint(
                peakSeconds: demandSample.seconds,
                startSeconds: max(firstTime, demandSample.seconds - capLeadSeconds),
                holdEndSeconds: min(lastTime, demandSample.seconds + capHoldSeconds),
                endSeconds: min(lastTime, demandSample.seconds + capHoldSeconds + capReleaseSeconds),
                scale: demandSample.scale,
                positionPixels: demandSample.positionPixels
            )
        }
        let playbackScaleHandoffs = autoCropZoomHandoffSegments(playbackKeypoints)
        let capScaleHandoffs = autoCropZoomHandoffSegments(capKeypoints)
        if !playbackScaleHandoffs.isEmpty {
            os_log(
                "Auto Crop playback descending handoff plan | handoffs %d capHandoffs %d release %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                playbackScaleHandoffs.count,
                capScaleHandoffs.count,
                releaseSeconds
            )
        }

        var rawPlannedSamples: [AutoCropPlaybackScaleSample] = []
        rawPlannedSamples.reserveCapacity(samples.count)
        var capSamples: [AutoCropPlaybackScaleSample] = []
        capSamples.reserveCapacity(samples.count)
        var compositionPositionSamples: [AutoCropPlaybackPositionSample] = []
        compositionPositionSamples.reserveCapacity(samples.count)
        var activeKeypointStartIndex = playbackKeypoints.startIndex
        var activeCapKeypointStartIndex = capKeypoints.startIndex

        for sample in samples {
            while activeKeypointStartIndex < playbackKeypoints.endIndex {
                let keypoint = playbackKeypoints[activeKeypointStartIndex]
                guard keypoint.endSeconds < sample.seconds - 1e-9 else {
                    break
                }
                activeKeypointStartIndex = playbackKeypoints.index(after: activeKeypointStartIndex)
            }

            var scale = Float(1.0)
            let basePositionSample = autoCropPlaybackCompositionPositionSample(sample)
            let neutralPosition = autoCropPlaybackFinitePosition(
                sample.neutralPositionPixels,
                fallback: basePositionSample.positionPixels
            )
            var compositionPosition = basePositionSample.positionPixels
            var weightedCompositionPosition = vector_float2(0.0, 0.0)
            var compositionPositionWeight = Float(0.0)
            var keypointIndex = activeKeypointStartIndex
            while keypointIndex < playbackKeypoints.endIndex {
                let keypoint = playbackKeypoints[keypointIndex]
                guard keypoint.startSeconds <= sample.seconds + 1e-9 else {
                    break
                }
                let influence = autoCropZoomKeypointInfluence(
                    keypoint,
                    at: sample.seconds
                )
                if influence > 0.0001 {
                    let candidateScale = Float(1.0) + ((keypoint.scale - Float(1.0)) * influence)
                    scale = max(scale, candidateScale)
                    let positionWeight = influence * max(Float(0.0001), keypoint.scale - Float(1.0))
                    let candidatePosition = neutralPosition + ((keypoint.positionPixels - neutralPosition) * influence)
                    weightedCompositionPosition += candidatePosition * positionWeight
                    compositionPositionWeight += positionWeight
                }
                keypointIndex = playbackKeypoints.index(after: keypointIndex)
            }
            if compositionPositionWeight > 0.0001 {
                compositionPosition = weightedCompositionPosition / compositionPositionWeight
            }
            scale = StabilizerAutoCropZoomHandoff.scale(
                baseScale: scale,
                at: sample.seconds,
                handoffs: playbackScaleHandoffs
            ).scale
            compositionPositionSamples.append(
                AutoCropPlaybackPositionSample(
                    seconds: sample.seconds,
                    positionPixels: compositionPosition
                )
            )
            let quantizedScale = autoCropPlaybackQuantizedScale(scale)
            rawPlannedSamples.append(
                AutoCropPlaybackScaleSample(
                    seconds: sample.seconds,
                    scale: quantizedScale
                )
            )

            while activeCapKeypointStartIndex < capKeypoints.endIndex {
                let keypoint = capKeypoints[activeCapKeypointStartIndex]
                guard keypoint.endSeconds < sample.seconds - 1e-9 else {
                    break
                }
                activeCapKeypointStartIndex = capKeypoints.index(after: activeCapKeypointStartIndex)
            }

            var capScale = Float(1.0)
            var capKeypointIndex = activeCapKeypointStartIndex
            while capKeypointIndex < capKeypoints.endIndex {
                let keypoint = capKeypoints[capKeypointIndex]
                guard keypoint.startSeconds <= sample.seconds + 1e-9 else {
                    break
                }
                let influence = autoCropZoomKeypointInfluence(
                    keypoint,
                    at: sample.seconds
                )
                if influence > 0.0001 {
                    capScale = max(
                        capScale,
                        Float(1.0) + ((keypoint.scale - Float(1.0)) * influence)
                    )
                }
                capKeypointIndex = capKeypoints.index(after: capKeypointIndex)
            }
            capScale = StabilizerAutoCropZoomHandoff.scale(
                baseScale: capScale,
                at: sample.seconds,
                handoffs: capScaleHandoffs
            ).scale
            capSamples.append(
                AutoCropPlaybackScaleSample(
                    seconds: sample.seconds,
                    scale: autoCropPlaybackQuantizedScale(capScale)
                )
            )
        }

        guard !shouldCancel() else {
            return nil
        }
        let keypointCompletedAt = CFAbsoluteTimeGetCurrent()

        let positionSamples = autoCropPlaybackRateLimitedPositionSamples(
            autoCropPlaybackPositionEnvelopeSamples(compositionPositionSamples),
            outputSize: outputSize
        )
        let envelopeSamples = autoCropPlaybackEnvelopeSamples(rawPlannedSamples)
        let repairedPlan = autoCropPlaybackCoverageRepairedScaleSamples(
            envelopeSamples,
            positionSamples: positionSamples,
            demandSamples: samples,
            outputSize: outputSize,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile
        )
        let continuousFloorSamples = autoCropPlaybackContinuousFloorSamples(repairedPlan.samples)
        let smoothingRadiusSeconds = autoCropPlaybackScaleSmoothingRadiusSeconds(
            peakScale: peakScale
        )
        let rateLimitedSamples = autoCropPlaybackRateLimitedScaleSamples(
            autoCropPlaybackEnvelopeSamples(repairedPlan.samples),
            floorSamples: continuousFloorSamples
        )
        let preliminaryPlannedSamples = autoCropPlaybackRateLimitedScaleSamples(
            autoCropPlaybackSmoothedScaleSamples(
                rateLimitedSamples,
                floorSamples: continuousFloorSamples,
                radiusSeconds: smoothingRadiusSeconds
            ),
            floorSamples: continuousFloorSamples
        )
        let finalFloorPlan = autoCropPlaybackFinalFramingFloorSamples(
            scaleSamples: preliminaryPlannedSamples,
            positionSamples: positionSamples,
            demandSamples: samples,
            outputSize: outputSize,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile
        )
        guard !shouldCancel() else {
            return nil
        }
        var plannedSamples: [AutoCropPlaybackScaleSample]
        var activeFloorSamples = repairedPlan.samples
        if finalFloorPlan.repairCount > 0 {
            activeFloorSamples = autoCropPlaybackMaximumScaleSamples(
                repairedPlan.samples,
                finalFloorPlan.samples
            )
            plannedSamples = autoCropPlaybackScaleSamplesByApplyingFloor(
                baseSamples: preliminaryPlannedSamples,
                floorSamples: activeFloorSamples,
                smoothingRadiusSeconds: smoothingRadiusSeconds
            )
        } else {
            plannedSamples = preliminaryPlannedSamples
        }
        var framingBuild = autoCropPlaybackFinalFramingSamples(
            scaleSamples: plannedSamples,
            positionSamples: positionSamples,
            demandSamples: samples,
            outputSize: outputSize,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile
        )
        var residualFramingRepairPasses = 0
        var residualFramingRepairCount = 0
        var residualFramingRepairMaxDelta = Float(0.0)
        var residualFramingRepairMaxDeltaSeconds = -1.0
        while framingBuild.repairCount > 0,
              residualFramingRepairPasses < 2
        {
            guard !shouldCancel() else {
                return nil
            }
            residualFramingRepairPasses += 1
            residualFramingRepairCount += framingBuild.repairCount
            if framingBuild.maxRepairDelta > residualFramingRepairMaxDelta {
                residualFramingRepairMaxDelta = framingBuild.maxRepairDelta
                residualFramingRepairMaxDeltaSeconds = framingBuild.maxRepairDeltaSeconds
            }
            activeFloorSamples = autoCropPlaybackMaximumScaleSamples(
                activeFloorSamples,
                framingBuild.repairFloorSamples
            )
            plannedSamples = autoCropPlaybackScaleSamplesByApplyingFloor(
                baseSamples: plannedSamples,
                floorSamples: activeFloorSamples,
                smoothingRadiusSeconds: smoothingRadiusSeconds
            )
            framingBuild = autoCropPlaybackFinalFramingSamples(
                scaleSamples: plannedSamples,
                positionSamples: positionSamples,
                demandSamples: samples,
                outputSize: outputSize,
                masterStrength: masterStrength,
                samplingProfile: samplingProfile
            )
        }
        guard !shouldCancel() else {
            return nil
        }
        let framingCompletedAt = CFAbsoluteTimeGetCurrent()
        if residualFramingRepairPasses > 0 {
            os_log(
                "Auto Crop playback residual framing repair folded into scale plan | passes %d repaired %d maxDelta %.5f seconds %.3f unresolved %d",
                log: stabilizerHostAnalysisLog,
                type: framingBuild.repairCount > 0 ? .error : .default,
                residualFramingRepairPasses,
                residualFramingRepairCount,
                residualFramingRepairMaxDelta,
                residualFramingRepairMaxDeltaSeconds,
                framingBuild.repairCount
            )
        }
        let framingSamples = framingBuild.samples
        let scaleBounds = plannedSamples.reduce(
            (minimum: Float.greatestFiniteMagnitude, maximum: Float(1.0))
        ) { bounds, sample in
            let scale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
            return (
                minimum: min(bounds.minimum, scale),
                maximum: max(bounds.maximum, scale)
            )
        }
        let compositionPositionStats = autoCropPlaybackCompositionPositionStats(
            demandSamples: samples,
            positionSamples: positionSamples,
            framingSamples: framingSamples
        )
        let protectedDemandScaleSamples = protectedDemandSamples.map { demandSample in
            AutoCropPlaybackScaleSample(
                seconds: demandSample.seconds,
                scale: demandSample.scale
            )
        }
        let rawDemandBounds = autoCropPlaybackDemandScaleBounds(samples)
        let protectedDemandBounds = autoCropPlaybackScaleBounds(protectedDemandScaleSamples)
        let rawPlannedBounds = autoCropPlaybackScaleBounds(rawPlannedSamples)
        let repairedBounds = autoCropPlaybackScaleBounds(repairedPlan.samples)
        let preliminaryBounds = autoCropPlaybackScaleBounds(preliminaryPlannedSamples)
        let finalFloorBounds = autoCropPlaybackScaleBounds(finalFloorPlan.samples)
        let framingBounds = autoCropPlaybackFramingScaleBounds(framingSamples)
        let turnZoomSampleCount = samples.reduce(0) { count, sample in
            count + (sample.turnZoomScale > Float(1.0001) ? 1 : 0)
        }
        let turnZoomMaxScale = samples.reduce(Float(1.0)) { partial, sample in
            max(partial, sample.turnZoomScale.isFinite ? sample.turnZoomScale : Float(1.0))
        }

        os_log(
            "Auto Crop playback scale plan | samples %d demandSamples %d isolatedDemandOutliers %d minimumClippedDemandSamples %d coverageFloorSamples %d coverageBudgetedPositions %d coverageBudgetedMax %.2f finalFloorSamples %d finalFloorMaxDelta %.5f maxTurnZoom %.2f turnZoomSamples %d turnZoomMax %.4f step %.3f minClip %.4f envelopeRadius %.3f rateLimit %.3f smoothingRadius %.3f peak %.3f peakScale %.4f minScale %.4f maxScale %.4f rawDemandMax %.4f protectedMax %.4f rawPlanMax %.4f repairedMax %.4f preliminaryMax %.4f finalFloorMax %.4f framingMax %.4f lead %.3f hold %.3f release %.3f capLead %.3f capHold %.3f capRelease %.3f positionDemandMax %.2f positionPlanMax %.2f positionFinalMax %.2f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            samples.count,
            protectedDemandSamples.count,
            filteredDemand.replacedCount,
            minimumClippedDemandSampleCount,
            repairedPlan.repairCount,
            repairedPlan.budgetedPositionCount,
            repairedPlan.maxBudgetedPositionPixels,
            finalFloorPlan.repairCount,
            finalFloorPlan.maxRepairDelta,
            strengths.turnSmoothingZoom,
            turnZoomSampleCount,
            turnZoomMaxScale,
            planStepSeconds,
            Float(1.0) + stabilizerAutoCropPlaybackMinimumClipScaleDelta,
            stabilizerAutoCropPlaybackEnvelopeRadiusSeconds,
            stabilizerAutoCropPlaybackScaleRateLimitPerSecond,
            smoothingRadiusSeconds,
            peakSeconds ?? -1.0,
            peakScale,
            scaleBounds.minimum.isFinite ? scaleBounds.minimum : Float(1.0),
            scaleBounds.maximum,
            rawDemandBounds.maximum,
            protectedDemandBounds.maximum,
            rawPlannedBounds.maximum,
            repairedBounds.maximum,
            preliminaryBounds.maximum,
            finalFloorBounds.maximum,
            framingBounds.maximum,
            leadSeconds,
            holdSeconds,
            releaseSeconds,
            capLeadSeconds,
            capHoldSeconds,
            capReleaseSeconds,
            compositionPositionStats.demandMaximum,
            compositionPositionStats.planMaximum,
            compositionPositionStats.finalMaximum
        )
        let plan = AutoCropPlaybackScalePlan(
            samples: plannedSamples,
            capSamples: capSamples,
            positionSamples: positionSamples,
            framingSamples: framingSamples,
            outputSize: outputSize,
            sampleCount: samples.count,
            peakSeconds: peakSeconds,
            peakScale: peakScale
        )
        let completedAt = CFAbsoluteTimeGetCurrent()
        os_log(
            "Auto Crop playback phases | samples %d demand %.3fms keypoints %.3fms framing %.3fms diagnostics %.3fms",
            log: stabilizerHostAnalysisLog,
            type: .default,
            samples.count,
            (demandCompletedAt - phasesStartedAt) * 1000.0,
            (keypointCompletedAt - demandCompletedAt) * 1000.0,
            (framingCompletedAt - keypointCompletedAt) * 1000.0,
            (completedAt - framingCompletedAt) * 1000.0
        )
        return plan
    }

    private static func autoCropPlaybackLookaheadScaleCap(currentFrameScale: Float) -> Float {
        let safeScale = max(Float(1.0), currentFrameScale.isFinite ? currentFrameScale : Float(1.0))
        let proportionalDelta = max(
            stabilizerAutoCropPlaybackLookaheadMinimumDelta,
            safeScale * stabilizerAutoCropPlaybackLookaheadScaleFraction
        )
        let cappedDelta = min(proportionalDelta, stabilizerAutoCropPlaybackLookaheadMaximumDelta)
        return safeScale + cappedDelta
    }

    private static func autoCropPlaybackFilteredDemandSamples(
        _ samples: [AutoCropZoomDemandSample],
        outputSize: vector_float2
    ) -> (samples: [AutoCropZoomDemandSample], replacedCount: Int) {
        guard samples.count > 2,
              outputSize.x > 1.0,
              outputSize.y > 1.0
        else {
            return (samples, 0)
        }

        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let positionSpikeThreshold = max(Float(3.0), outputReference * 0.004)
        let neighborPositionThreshold = max(Float(1.5), outputReference * 0.0015)
        let scaleSpikeThreshold: Float = 0.020
        let neighborScaleThreshold: Float = 0.004
        var filtered = samples
        var replacedCount = 0

        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let current = samples[index]
            let next = samples[index + 1]
            guard previous.seconds.isFinite,
                  current.seconds.isFinite,
                  next.seconds.isFinite
            else {
                continue
            }

            let previousNextSpan = next.seconds - previous.seconds
            guard previousNextSpan > 1e-6,
                  current.seconds > previous.seconds,
                  current.seconds < next.seconds
            else {
                continue
            }

            let fraction = Float((current.seconds - previous.seconds) / previousNextSpan)
            let clampedFraction = min(max(fraction, 0.0), 1.0)
            let interpolatedScale = previous.scale + ((next.scale - previous.scale) * clampedFraction)
            let interpolatedNeutralScale = previous.neutralScale + ((next.neutralScale - previous.neutralScale) * clampedFraction)
            let interpolatedTurnZoomScale = previous.turnZoomScale + ((next.turnZoomScale - previous.turnZoomScale) * clampedFraction)
            let interpolatedPosition = previous.positionPixels
                + ((next.positionPixels - previous.positionPixels) * clampedFraction)
            let interpolatedNeutralPosition = previous.neutralPositionPixels
                + ((next.neutralPositionPixels - previous.neutralPositionPixels) * clampedFraction)

            let scaleDeviation = abs(current.scale - interpolatedScale)
            let neutralScaleDeviation = abs(current.neutralScale - interpolatedNeutralScale)
            let neighborScaleDelta = abs(next.scale - previous.scale)
            let positionDeviation = simd_length(current.positionPixels - interpolatedPosition)
            let neutralPositionDeviation = simd_length(current.neutralPositionPixels - interpolatedNeutralPosition)
            let neighborPositionDelta = simd_length(next.positionPixels - previous.positionPixels)
            let scaleSpike = scaleDeviation >= scaleSpikeThreshold
                && neighborScaleDelta <= max(neighborScaleThreshold, scaleDeviation * 0.35)
            let neutralScaleSpike = neutralScaleDeviation >= scaleSpikeThreshold
                && abs(next.neutralScale - previous.neutralScale) <= max(neighborScaleThreshold, neutralScaleDeviation * 0.35)
            let positionSpike = positionDeviation >= positionSpikeThreshold
                && neighborPositionDelta <= max(neighborPositionThreshold, positionDeviation * 0.35)
            let neutralPositionSpike = neutralPositionDeviation >= positionSpikeThreshold
                && simd_length(next.neutralPositionPixels - previous.neutralPositionPixels) <= max(neighborPositionThreshold, neutralPositionDeviation * 0.35)

            guard scaleSpike || neutralScaleSpike || positionSpike || neutralPositionSpike else {
                continue
            }

            let replacementTransform = clampedFraction < 0.5 ? previous.transform : next.transform
            filtered[index] = AutoCropZoomDemandSample(
                seconds: current.seconds,
                scale: scaleSpike ? interpolatedScale : current.scale,
                positionPixels: positionSpike ? interpolatedPosition : current.positionPixels,
                neutralScale: neutralScaleSpike ? interpolatedNeutralScale : current.neutralScale,
                neutralPositionPixels: neutralPositionSpike ? interpolatedNeutralPosition : current.neutralPositionPixels,
                turnZoomScale: scaleSpike ? interpolatedTurnZoomScale : current.turnZoomScale,
                transform: replacementTransform
            )
            replacedCount += 1
        }

        return (filtered, replacedCount)
    }

    private static func autoCropPlaybackFinitePosition(
        _ positionPixels: vector_float2,
        fallback fallbackPositionPixels: vector_float2 = vector_float2(0.0, 0.0)
    ) -> vector_float2 {
        if positionPixels.x.isFinite,
           positionPixels.y.isFinite
        {
            return positionPixels
        }
        if fallbackPositionPixels.x.isFinite,
           fallbackPositionPixels.y.isFinite
        {
            return fallbackPositionPixels
        }
        return vector_float2(0.0, 0.0)
    }

    private static func autoCropPlaybackCompositionPositionSample(
        _ sample: AutoCropZoomDemandSample
    ) -> AutoCropPlaybackPositionSample {
        let neutralPosition = autoCropPlaybackFinitePosition(
            sample.neutralPositionPixels,
            fallback: sample.positionPixels
        )
        let demandPosition = autoCropPlaybackFinitePosition(
            sample.positionPixels,
            fallback: neutralPosition
        )
        let demandBlend = min(max(stabilizerAutoCropPlaybackPositionDemandBlend, Float(0.0)), Float(1.0))
        return AutoCropPlaybackPositionSample(
            seconds: sample.seconds,
            positionPixels: neutralPosition + ((demandPosition - neutralPosition) * demandBlend)
        )
    }

    private static func autoCropPlaybackCompositionPositionStats(
        demandSamples: [AutoCropZoomDemandSample],
        positionSamples: [AutoCropPlaybackPositionSample],
        framingSamples: [AutoCropPlaybackFramingSample]
    ) -> (demandMaximum: Float, planMaximum: Float, finalMaximum: Float) {
        var demandMaximum = Float(0.0)
        var planMaximum = Float(0.0)
        var finalMaximum = Float(0.0)
        for sample in demandSamples {
            demandMaximum = max(
                demandMaximum,
                simd_length(
                    autoCropPlaybackFinitePosition(
                        sample.positionPixels,
                        fallback: sample.neutralPositionPixels
                    )
                )
            )
        }
        for sample in positionSamples {
            planMaximum = max(
                planMaximum,
                simd_length(autoCropPlaybackFinitePosition(sample.positionPixels))
            )
        }
        for sample in framingSamples {
            finalMaximum = max(
                finalMaximum,
                simd_length(autoCropPlaybackFinitePosition(sample.positionPixels))
            )
        }
        return (
            demandMaximum: demandMaximum,
            planMaximum: planMaximum,
            finalMaximum: finalMaximum
        )
    }

    private static func autoCropPlaybackVisualScaleCap(_ scale: Float) -> Float {
        max(Float(1.0), scale.isFinite ? scale : Float(1.0))
    }

    private static func autoCropPlaybackScaleInputForProtectedScale(_ protectedScale: Float) -> Float {
        let safeScale = max(Float(1.0), protectedScale.isFinite ? protectedScale : Float(1.0))
        return autoCropPlaybackQuantizedScale(safeScale)
    }

    private static func autoCropPlaybackMinimumClippedScale(_ scale: Float) -> Float {
        StabilizerAutoCropScalePolicy.playbackMinimumClippedScale(scale)
    }

    private static func autoCropPlaybackScalePlanSampleSeconds(
        preparedAnalysis: StabilizerPreparedAnalysis,
        firstTime: Double,
        lastTime: Double
    ) -> [Double] {
        var sampleSeconds: [Double] = []
        sampleSeconds.reserveCapacity(preparedAnalysis.frames.count)
        var lastSample: Double?
        for frame in preparedAnalysis.frames {
            let seconds = frame.time
            guard seconds.isFinite,
                  seconds >= firstTime - 1e-9,
                  seconds <= lastTime + 1e-9
            else {
                continue
            }
            if let previous = lastSample,
               abs(seconds - previous) <= 1e-9
            {
                continue
            }
            sampleSeconds.append(seconds)
            lastSample = seconds
        }
        if sampleSeconds.isEmpty {
            return [firstTime, lastTime].filter { $0.isFinite }
        }
        if let firstSample = sampleSeconds.first,
           abs(firstSample - firstTime) > 1e-6,
           firstTime.isFinite
        {
            sampleSeconds.insert(firstTime, at: 0)
        }
        if let lastSample = sampleSeconds.last,
           abs(lastSample - lastTime) > 1e-6,
           lastTime.isFinite
        {
            sampleSeconds.append(lastTime)
        }
        return sampleSeconds
    }

    private static func autoCropPlaybackScalePlanStepSeconds(samples: [Double]) -> Double {
        guard samples.count > 1 else {
            return stabilizerAutoCropPlaybackScalePlanStepSeconds
        }
        var deltas: [Double] = []
        deltas.reserveCapacity(samples.count - 1)
        var previous = samples[0]
        for seconds in samples.dropFirst() {
            let delta = seconds - previous
            if delta.isFinite, delta > 1e-6 {
                deltas.append(delta)
            }
            previous = seconds
        }
        guard !deltas.isEmpty else {
            return stabilizerAutoCropPlaybackScalePlanStepSeconds
        }
        deltas.sort()
        return max(1e-6, deltas[deltas.count / 2])
    }

    private static func autoCropPlaybackEnvelopeSamples(
        _ samples: [AutoCropPlaybackScaleSample]
    ) -> [AutoCropPlaybackScaleSample] {
        guard samples.count > 1 else {
            return samples
        }

        let radiusSeconds = max(0.0, stabilizerAutoCropPlaybackEnvelopeRadiusSeconds)
        var result: [AutoCropPlaybackScaleSample] = []
        result.reserveCapacity(samples.count)
        var deque: [Int] = []
        deque.reserveCapacity(samples.count)
        var upperIndex = samples.startIndex
        for index in samples.indices {
            let centerSeconds = samples[index].seconds
            let upperSeconds = centerSeconds + radiusSeconds
            while upperIndex < samples.endIndex,
                  samples[upperIndex].seconds <= upperSeconds + 1e-9
            {
                let candidateScale = max(Float(1.0), samples[upperIndex].scale.isFinite ? samples[upperIndex].scale : Float(1.0))
                while let last = deque.last {
                    let lastScale = max(Float(1.0), samples[last].scale.isFinite ? samples[last].scale : Float(1.0))
                    guard lastScale <= candidateScale else {
                        break
                    }
                    _ = deque.popLast()
                }
                deque.append(upperIndex)
                upperIndex = samples.index(after: upperIndex)
            }

            let lowerSeconds = centerSeconds - radiusSeconds
            while let first = deque.first,
                  samples[first].seconds < lowerSeconds - 1e-9
            {
                deque.removeFirst()
            }

            let envelopeScale = deque.first.map {
                max(Float(1.0), samples[$0].scale.isFinite ? samples[$0].scale : Float(1.0))
            } ?? max(Float(1.0), samples[index].scale)
            result.append(
                AutoCropPlaybackScaleSample(
                    seconds: centerSeconds,
                    scale: autoCropPlaybackQuantizedScale(envelopeScale)
                )
            )
        }
        return result
    }

    private static func autoCropPlaybackCoverageRepairedScaleSamples(
        _ plannedSamples: [AutoCropPlaybackScaleSample],
        positionSamples: [AutoCropPlaybackPositionSample],
        demandSamples: [AutoCropZoomDemandSample],
        outputSize: vector_float2,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile
    ) -> (samples: [AutoCropPlaybackScaleSample], repairCount: Int, budgetedPositionCount: Int, maxBudgetedPositionPixels: Float) {
        guard plannedSamples.count == demandSamples.count,
              positionSamples.count == demandSamples.count,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              masterStrength.isFinite
        else {
            return (plannedSamples, 0, 0, 0.0)
        }

        var repairedSamples: [AutoCropPlaybackScaleSample] = []
        repairedSamples.reserveCapacity(plannedSamples.count)
        var repairCount = 0
        var budgetedPositionCount = 0
        var maxBudgetedPositionPixels = Float(0.0)

        for index in plannedSamples.indices {
            let plannedSample = plannedSamples[index]
            let demandSample = demandSamples[index]
            let currentScale = demandSample.scale
            let neutralScale = demandSample.neutralScale
            let currentFloorScale = autoCropPlaybackMinimumClippedScale(currentScale)
            let neutralFloorScale = autoCropPlaybackMinimumClippedScale(neutralScale)
            let plannedPositionPixels = positionSamples[index].positionPixels
            let positionReuseTolerance = max(Float(2.0), min(outputSize.x, outputSize.y) * 0.001)
            let distanceToCurrent = simd_length(plannedPositionPixels - demandSample.positionPixels)
            let distanceToNeutral = simd_length(plannedPositionPixels - demandSample.neutralPositionPixels)
            let baseCoverageFloorScale = currentFloorScale <= neutralFloorScale + stabilizerAutoCropKeypointCoverageToleranceDelta
                ? currentFloorScale
                : neutralFloorScale
            let plannedPositionFloorScale: Float
            if distanceToCurrent <= positionReuseTolerance {
                plannedPositionFloorScale = currentFloorScale
            } else {
                let context = AutoCropTransformContext(
                    transform: demandSample.transform,
                    outputSize: outputSize,
                    masterStrength: masterStrength
                )
                let plannedInputScale = max(
                    Float(1.0),
                    plannedSample.scale.isFinite ? plannedSample.scale : Float(1.0)
                )
                let budgetedProtectedScale = autoCropPlaybackMinimumClippedScale(
                    autoCropPlaybackVisualScaleCap(max(plannedInputScale, baseCoverageFloorScale))
                )
                let budgetedFinalScale = autoCropKeypointScale(protectedScale: budgetedProtectedScale)
                let budgetedPositionPixels = autoCropStableScaleBudgetedPositionPixels(
                    stablePositionPixels: plannedPositionPixels,
                    clampPositionPixels: demandSample.positionPixels,
                    context: context,
                    scale: budgetedFinalScale,
                    samplingProfile: samplingProfile
                )
                if autoCropPosition(
                    budgetedPositionPixels,
                    fitsWithinScale: budgetedFinalScale,
                    context: context,
                    samplingProfile: samplingProfile
                ) {
                    let budgetedDistance = simd_length(budgetedPositionPixels - plannedPositionPixels)
                    if budgetedDistance > positionReuseTolerance {
                        budgetedPositionCount += 1
                        maxBudgetedPositionPixels = max(maxBudgetedPositionPixels, budgetedDistance)
                    }
                    plannedPositionFloorScale = baseCoverageFloorScale
                } else if distanceToNeutral <= positionReuseTolerance {
                    plannedPositionFloorScale = neutralFloorScale
                } else {
                    let plannedPositionScale = requiredAutoCropScale(
                        context: context,
                        cropPositionPixels: plannedPositionPixels,
                        sampleSteps: samplingProfile.scaleSearchSampleSteps,
                        iterations: samplingProfile.scaleSearchIterations
                    )
                    plannedPositionFloorScale = autoCropPlaybackMinimumClippedScale(plannedPositionScale)
                }
            }
            let coverageFloorScale = max(baseCoverageFloorScale, plannedPositionFloorScale)
            let repairedScale = autoCropPlaybackQuantizedScale(max(plannedSample.scale, coverageFloorScale))
            if repairedScale > plannedSample.scale + 0.00001 {
                repairCount += 1
            }
            repairedSamples.append(
                AutoCropPlaybackScaleSample(
                    seconds: plannedSample.seconds,
                    scale: repairedScale
                )
            )
        }

        return (repairedSamples, repairCount, budgetedPositionCount, maxBudgetedPositionPixels)
    }

    private static func autoCropPlaybackMaximumScaleSamples(
        _ lhs: [AutoCropPlaybackScaleSample],
        _ rhs: [AutoCropPlaybackScaleSample]
    ) -> [AutoCropPlaybackScaleSample] {
        guard lhs.count == rhs.count else {
            return lhs
        }
        return lhs.indices.map { index in
            let left = max(Float(1.0), lhs[index].scale.isFinite ? lhs[index].scale : Float(1.0))
            let right = max(Float(1.0), rhs[index].scale.isFinite ? rhs[index].scale : Float(1.0))
            return AutoCropPlaybackScaleSample(
                seconds: lhs[index].seconds,
                scale: autoCropPlaybackQuantizedScale(max(left, right))
            )
        }
    }

    private static func autoCropPlaybackScaleSamplesByApplyingFloor(
        baseSamples: [AutoCropPlaybackScaleSample],
        floorSamples: [AutoCropPlaybackScaleSample],
        smoothingRadiusSeconds: Double
    ) -> [AutoCropPlaybackScaleSample] {
        guard baseSamples.count == floorSamples.count,
              baseSamples.count > 1
        else {
            return baseSamples
        }

        let inputSamples = autoCropPlaybackMaximumScaleSamples(
            baseSamples,
            floorSamples
        )
        let continuousFloorSamples = autoCropPlaybackContinuousFloorSamples(floorSamples)
        let rateLimitedSamples = autoCropPlaybackRateLimitedScaleSamples(
            autoCropPlaybackEnvelopeSamples(inputSamples),
            floorSamples: continuousFloorSamples
        )
        return autoCropPlaybackRateLimitedScaleSamples(
            autoCropPlaybackSmoothedScaleSamples(
                rateLimitedSamples,
                floorSamples: continuousFloorSamples,
                radiusSeconds: smoothingRadiusSeconds
            ),
            floorSamples: continuousFloorSamples
        )
    }

    private static func autoCropPlaybackScaleBounds(
        _ samples: [AutoCropPlaybackScaleSample]
    ) -> (minimum: Float, maximum: Float) {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = Float(1.0)
        for sample in samples {
            let scale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
            minimum = min(minimum, scale)
            maximum = max(maximum, scale)
        }
        return (
            minimum: minimum.isFinite ? minimum : Float(1.0),
            maximum: maximum
        )
    }

    private static func autoCropPlaybackDemandScaleBounds(
        _ samples: [AutoCropZoomDemandSample]
    ) -> (minimum: Float, maximum: Float) {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = Float(1.0)
        for sample in samples {
            let scale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
            minimum = min(minimum, scale)
            maximum = max(maximum, scale)
        }
        return (
            minimum: minimum.isFinite ? minimum : Float(1.0),
            maximum: maximum
        )
    }

    private static func autoCropPlaybackFramingScaleBounds(
        _ samples: [AutoCropPlaybackFramingSample]
    ) -> (minimum: Float, maximum: Float) {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = Float(1.0)
        for sample in samples {
            let scale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
            minimum = min(minimum, scale)
            maximum = max(maximum, scale)
        }
        return (
            minimum: minimum.isFinite ? minimum : Float(1.0),
            maximum: maximum
        )
    }

    private static func autoCropPlaybackFinalFramingFloorSamples(
        scaleSamples: [AutoCropPlaybackScaleSample],
        positionSamples: [AutoCropPlaybackPositionSample],
        demandSamples: [AutoCropZoomDemandSample],
        outputSize: vector_float2,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile
    ) -> (samples: [AutoCropPlaybackScaleSample], repairCount: Int, maxRepairDelta: Float, maxRepairDeltaSeconds: Double) {
        guard scaleSamples.count == positionSamples.count,
              scaleSamples.count == demandSamples.count,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              masterStrength.isFinite
        else {
            return (scaleSamples, 0, 0.0, -1.0)
        }

        var floorSamples: [AutoCropPlaybackScaleSample] = []
        floorSamples.reserveCapacity(scaleSamples.count)
        var repairCount = 0
        var stablePositionFloorCount = 0
        var maxRepairDelta = Float(0.0)
        var maxRepairDeltaSeconds = -1.0

        for index in scaleSamples.indices {
            let scaleSample = scaleSamples[index]
            let positionSample = positionSamples[index]
            let demandSample = demandSamples[index]
            let context = AutoCropTransformContext(
                transform: demandSample.transform,
                outputSize: outputSize,
                masterStrength: masterStrength
            )
            let originalInputScale = max(
                Float(1.0),
                scaleSample.scale.isFinite ? scaleSample.scale : Float(1.0)
            )
            var requiredInputScale = originalInputScale
            let plannedPositionPixels = positionSample.positionPixels

            if autoCropCenterIsInsideSource(
                cropPositionPixels: plannedPositionPixels,
                context: context
            ) {
                let plannedPositionProtectedScale = autoCropPlaybackMinimumClippedScale(
                    requiredAutoCropScale(
                        context: context,
                        cropPositionPixels: plannedPositionPixels,
                        sampleSteps: samplingProfile.scaleSearchSampleSteps,
                        iterations: samplingProfile.scaleSearchIterations
                    )
                )
                let originalProtectedScale = autoCropPlaybackMinimumClippedScale(
                    autoCropPlaybackVisualScaleCap(originalInputScale)
                )
                let cappedPlannedPositionProtectedScale = min(
                    plannedPositionProtectedScale,
                    originalProtectedScale + stabilizerAutoCropPlaybackStablePositionFloorMaxDelta
                )
                let plannedPositionInputScale = autoCropPlaybackScaleInputForProtectedScale(
                    cappedPlannedPositionProtectedScale
                )
                if plannedPositionInputScale > requiredInputScale + 0.00001 {
                    requiredInputScale = plannedPositionInputScale
                    stablePositionFloorCount += 1
                }
            }

            for _ in 0..<3 {
                let protectedScale = autoCropPlaybackMinimumClippedScale(
                    autoCropPlaybackVisualScaleCap(requiredInputScale)
                )
                let finalScale = autoCropKeypointScale(protectedScale: protectedScale)
                let finalPosition = autoCropStableScaleBudgetedPositionPixels(
                    stablePositionPixels: positionSample.positionPixels,
                    clampPositionPixels: demandSample.positionPixels,
                    context: context,
                    scale: finalScale,
                    samplingProfile: samplingProfile
                )
                guard !autoCropPosition(
                    finalPosition,
                    fitsWithinScale: finalScale,
                    context: context,
                    samplingProfile: samplingProfile
                ) else {
                    break
                }

                let requiredProtectedScale = autoCropPlaybackMinimumClippedScale(
                    requiredAutoCropScale(
                        context: context,
                        cropPositionPixels: finalPosition,
                        sampleSteps: samplingProfile.scaleSearchSampleSteps,
                        iterations: samplingProfile.scaleSearchIterations
                    )
                )
                let requiredVisualInputScale = autoCropPlaybackScaleInputForProtectedScale(
                    requiredProtectedScale
                )
                if requiredVisualInputScale <= requiredInputScale + 0.00001 {
                    break
                }
                requiredInputScale = requiredVisualInputScale
            }

            let floorScale = autoCropPlaybackQuantizedScale(requiredInputScale)
            let repairDelta = max(Float(0.0), floorScale - originalInputScale)
            if repairDelta > 0.00001 {
                repairCount += 1
                if repairDelta > maxRepairDelta {
                    maxRepairDelta = repairDelta
                    maxRepairDeltaSeconds = scaleSample.seconds
                }
            }
            floorSamples.append(
                AutoCropPlaybackScaleSample(
                    seconds: scaleSample.seconds,
                    scale: floorScale
                )
            )
        }

        if repairCount > 0 {
            os_log(
                "Auto Crop playback final floor prepass | samples %d repaired %d stablePositionFloors %d maxDelta %.5f seconds %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                floorSamples.count,
                repairCount,
                stablePositionFloorCount,
                maxRepairDelta,
                maxRepairDeltaSeconds
            )
        }

        return (floorSamples, repairCount, maxRepairDelta, maxRepairDeltaSeconds)
    }

    private static func autoCropPlaybackFinalFramingSamples(
        scaleSamples: [AutoCropPlaybackScaleSample],
        positionSamples: [AutoCropPlaybackPositionSample],
        demandSamples: [AutoCropZoomDemandSample],
        outputSize: vector_float2,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile
    ) -> AutoCropPlaybackFramingBuildResult {
        guard scaleSamples.count == positionSamples.count,
              scaleSamples.count == demandSamples.count,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              masterStrength.isFinite
        else {
            os_log(
                "Auto Crop playback final framing unavailable | scaleSamples %d positionSamples %d demandSamples %d",
                log: stabilizerHostAnalysisLog,
                type: .error,
                scaleSamples.count,
                positionSamples.count,
                demandSamples.count
            )
            return AutoCropPlaybackFramingBuildResult(
                samples: [],
                repairFloorSamples: [],
                repairCount: 0,
                maxRepairDelta: 0.0,
                maxRepairDeltaSeconds: -1.0
            )
        }

        var samples: [AutoCropPlaybackFramingSample] = []
        samples.reserveCapacity(scaleSamples.count)
        var repairFloorSamples: [AutoCropPlaybackScaleSample] = []
        repairFloorSamples.reserveCapacity(scaleSamples.count)
        var repairedCount = 0
        var maxRepairDelta = Float(0.0)
        var maxRepairDeltaSeconds = -1.0

        for index in scaleSamples.indices {
            let scaleSample = scaleSamples[index]
            let positionSample = positionSamples[index]
            let demandSample = demandSamples[index]
            let protectedScale = autoCropPlaybackMinimumClippedScale(
                autoCropPlaybackVisualScaleCap(scaleSample.scale)
            )
            let context = AutoCropTransformContext(
                transform: demandSample.transform,
                outputSize: outputSize,
                masterStrength: masterStrength
            )
            var finalScale = autoCropKeypointScale(protectedScale: protectedScale)
            var finalPosition = autoCropStableScaleBudgetedPositionPixels(
                stablePositionPixels: positionSample.positionPixels,
                clampPositionPixels: demandSample.positionPixels,
                context: context,
                scale: finalScale,
                samplingProfile: samplingProfile
            )
            if !autoCropPosition(
                finalPosition,
                fitsWithinScale: finalScale,
                context: context,
                samplingProfile: samplingProfile
            ) {
                let requiredScale = autoCropPlaybackMinimumClippedScale(
                    requiredAutoCropScale(
                        context: context,
                        cropPositionPixels: finalPosition,
                        sampleSteps: samplingProfile.scaleSearchSampleSteps,
                        iterations: samplingProfile.scaleSearchIterations
                    )
                )
                let repairedScale = autoCropKeypointScale(protectedScale: max(protectedScale, requiredScale))
                let repairDelta = max(Float(0.0), repairedScale - finalScale)
                finalScale = repairedScale
                if repairDelta > 0.00001 {
                    repairedCount += 1
                    if repairDelta > maxRepairDelta {
                        maxRepairDelta = repairDelta
                        maxRepairDeltaSeconds = scaleSample.seconds
                    }
                }
                finalPosition = autoCropStableScaleBudgetedPositionPixels(
                    stablePositionPixels: finalPosition,
                    clampPositionPixels: demandSample.positionPixels,
                    context: context,
                    scale: finalScale,
                    samplingProfile: samplingProfile
                )
                repairFloorSamples.append(
                    AutoCropPlaybackScaleSample(
                        seconds: scaleSample.seconds,
                        scale: autoCropPlaybackScaleInputForProtectedScale(finalScale)
                    )
                )
            } else {
                repairFloorSamples.append(
                    AutoCropPlaybackScaleSample(
                        seconds: scaleSample.seconds,
                        scale: Float(1.0)
                    )
                )
            }
            samples.append(
                AutoCropPlaybackFramingSample(
                    seconds: scaleSample.seconds,
                    scale: finalScale,
                    positionPixels: finalPosition
                )
            )
        }

        return AutoCropPlaybackFramingBuildResult(
            samples: samples,
            repairFloorSamples: repairFloorSamples,
            repairCount: repairedCount,
            maxRepairDelta: maxRepairDelta,
            maxRepairDeltaSeconds: maxRepairDeltaSeconds
        )
    }

    private static func autoCropPlaybackRateLimitedScaleSamples(
        _ samples: [AutoCropPlaybackScaleSample],
        floorSamples: [AutoCropPlaybackScaleSample]
    ) -> [AutoCropPlaybackScaleSample] {
        guard samples.count == floorSamples.count,
              samples.count > 2
        else {
            return samples
        }

        let rateLimitPerSecond = max(Float(0.0), stabilizerAutoCropPlaybackScaleRateLimitPerSecond)
        guard rateLimitPerSecond > 0.00001 else {
            return samples
        }

        func floorScale(at index: Int) -> Float {
            max(Float(1.0), floorSamples[index].scale.isFinite ? floorSamples[index].scale : Float(1.0))
        }

        func limitedScale(
            current: Float,
            adjacent: Float,
            deltaSeconds: Double,
            floor: Float
        ) -> Float {
            let safeCurrent = max(Float(1.0), current.isFinite ? current : Float(1.0))
            let safeAdjacent = max(Float(1.0), adjacent.isFinite ? adjacent : Float(1.0))
            let maxDelta = rateLimitPerSecond * Float(max(0.0, deltaSeconds))
            let limited = min(safeCurrent, safeAdjacent + maxDelta)
            return autoCropPlaybackQuantizedScale(max(floor, limited))
        }

        var forward = samples
        for index in 1..<samples.count {
            let deltaSeconds = samples[index].seconds - samples[index - 1].seconds
            forward[index] = AutoCropPlaybackScaleSample(
                seconds: samples[index].seconds,
                scale: limitedScale(
                    current: samples[index].scale,
                    adjacent: forward[index - 1].scale,
                    deltaSeconds: deltaSeconds,
                    floor: floorScale(at: index)
                )
            )
        }

        var backward = forward
        if samples.count > 1 {
            for index in stride(from: samples.count - 2, through: 0, by: -1) {
                let deltaSeconds = samples[index + 1].seconds - samples[index].seconds
                backward[index] = AutoCropPlaybackScaleSample(
                    seconds: samples[index].seconds,
                    scale: limitedScale(
                        current: forward[index].scale,
                        adjacent: backward[index + 1].scale,
                        deltaSeconds: deltaSeconds,
                        floor: floorScale(at: index)
                    )
                )
            }
        }

        return backward
    }

    private static func autoCropPlaybackScaleSmoothingRadiusSeconds(peakScale: Float) -> Double {
        let minimumRadius = max(0.0, stabilizerAutoCropPlaybackScaleSmoothingMinimumRadiusSeconds)
        let maximumRadius = max(minimumRadius, stabilizerAutoCropPlaybackScaleSmoothingMaximumRadiusSeconds)
        guard maximumRadius > minimumRadius + 1e-6 else {
            return minimumRadius
        }
        let safePeakScale = max(Float(1.0), peakScale.isFinite ? peakScale : Float(1.0))
        let peakDelta = safePeakScale - Float(1.0)
        let startDelta = max(Float(0.0), stabilizerAutoCropPlaybackScaleSmoothingAdaptiveStartDelta)
        let fullDelta = max(startDelta + Float.ulpOfOne, stabilizerAutoCropPlaybackScaleSmoothingAdaptiveFullDelta)
        guard peakDelta > startDelta else {
            return minimumRadius
        }
        let progress = min(max((peakDelta - startDelta) / (fullDelta - startDelta), Float(0.0)), Float(1.0))
        let easedProgress = Double(easeInOutRamp(progress))
        return minimumRadius + ((maximumRadius - minimumRadius) * easedProgress)
    }

    private static func autoCropPlaybackSmoothedScaleSamples(
        _ samples: [AutoCropPlaybackScaleSample],
        floorSamples: [AutoCropPlaybackScaleSample],
        radiusSeconds: Double
    ) -> [AutoCropPlaybackScaleSample] {
        guard samples.count == floorSamples.count,
              samples.count > 2
        else {
            return samples
        }

        let radiusSeconds = max(0.0, radiusSeconds.isFinite ? radiusSeconds : 0.0)
        guard radiusSeconds > 1e-6 else {
            return samples
        }

        func floorScale(at index: Int) -> Float {
            max(Float(1.0), floorSamples[index].scale.isFinite ? floorSamples[index].scale : Float(1.0))
        }

        var smoothedSamples: [AutoCropPlaybackScaleSample] = []
        smoothedSamples.reserveCapacity(samples.count)
        var lowerIndex = samples.startIndex
        var upperIndex = samples.startIndex

        for index in samples.indices {
            let centerSeconds = samples[index].seconds
            while lowerIndex < samples.endIndex,
                  samples[lowerIndex].seconds < centerSeconds - radiusSeconds - 1e-9
            {
                lowerIndex = samples.index(after: lowerIndex)
            }
            while upperIndex < samples.endIndex,
                  samples[upperIndex].seconds <= centerSeconds + radiusSeconds + 1e-9
            {
                upperIndex = samples.index(after: upperIndex)
            }

            var weightedScale = Float(0.0)
            var totalWeight = Float(0.0)
            var sampleIndex = lowerIndex
            while sampleIndex < upperIndex {
                let sample = samples[sampleIndex]
                let distance = abs(sample.seconds - centerSeconds)
                if distance <= radiusSeconds + 1e-9 {
                    let progress = Float(1.0 - min(max(distance / radiusSeconds, 0.0), 1.0))
                    let weight = easeInOutRamp(progress)
                    if weight > 0.0001 {
                        let safeScale = max(Float(1.0), sample.scale.isFinite ? sample.scale : Float(1.0))
                        weightedScale += safeScale * weight
                        totalWeight += weight
                    }
                }
                sampleIndex = samples.index(after: sampleIndex)
            }

            let averagedScale = totalWeight > 0.0001
                ? weightedScale / totalWeight
                : samples[index].scale
            let scale = autoCropPlaybackQuantizedScale(max(floorScale(at: index), averagedScale))
            smoothedSamples.append(
                AutoCropPlaybackScaleSample(
                    seconds: centerSeconds,
                    scale: scale
                )
            )
        }

        return smoothedSamples
    }

    private static func autoCropPlaybackContinuousFloorSamples(
        _ samples: [AutoCropPlaybackScaleSample]
    ) -> [AutoCropPlaybackScaleSample] {
        guard samples.count > 2 else {
            return samples
        }
        let identityFloorSamples = samples.map {
            AutoCropPlaybackScaleSample(seconds: $0.seconds, scale: Float(1.0))
        }
        return autoCropPlaybackRateLimitedScaleSamples(
            autoCropPlaybackEnvelopeSamples(samples),
            floorSamples: identityFloorSamples
        )
    }

    private static func autoCropPlaybackPositionEnvelopeSamples(
        _ samples: [AutoCropPlaybackPositionSample]
    ) -> [AutoCropPlaybackPositionSample] {
        guard samples.count > 1 else {
            return samples
        }

        let radiusSeconds = max(
            autoCropPlaybackScalePlanStepSeconds(samples: samples.map(\.seconds)),
            stabilizerAutoCropPlaybackPositionEnvelopeRadiusSeconds
        )

        var result: [AutoCropPlaybackPositionSample] = []
        result.reserveCapacity(samples.count)
        var lowerIndex = samples.startIndex
        var upperIndex = samples.startIndex
        for index in samples.indices {
            let centerSeconds = samples[index].seconds
            while lowerIndex < samples.endIndex,
                  samples[lowerIndex].seconds < centerSeconds - radiusSeconds - 1e-9
            {
                lowerIndex = samples.index(after: lowerIndex)
            }
            while upperIndex < samples.endIndex,
                  samples[upperIndex].seconds <= centerSeconds + radiusSeconds + 1e-9
            {
                upperIndex = samples.index(after: upperIndex)
            }
            var weightedPosition = vector_float2(0.0, 0.0)
            var totalWeight = Float(0.0)
            var sampleIndex = lowerIndex
            while sampleIndex < upperIndex {
                let sample = samples[sampleIndex]
                let distance = abs(sample.seconds - centerSeconds)
                if distance <= radiusSeconds + 1e-9 {
                    let progress = Float(1.0 - min(max(distance / radiusSeconds, 0.0), 1.0))
                    let weight = easeInOutRamp(progress)
                    if weight > 0.0001 {
                        weightedPosition += sample.positionPixels * weight
                        totalWeight += weight
                    }
                }
                sampleIndex = samples.index(after: sampleIndex)
            }
            let positionPixels = totalWeight > 0.0001
                ? weightedPosition / totalWeight
                : samples[index].positionPixels
            result.append(
                AutoCropPlaybackPositionSample(
                    seconds: centerSeconds,
                    positionPixels: positionPixels
                )
            )
        }
        return result
    }

    private static func autoCropPlaybackPositionStepLimit(
        deltaSeconds: Double,
        outputSize: vector_float2
    ) -> Float {
        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let rate = outputReference * max(Float(0.0), stabilizerAutoCropPlaybackPositionRateLimitFractionPerSecond)
        guard rate > 0.00001 else {
            return Float.infinity
        }
        let scaledLimit = rate * Float(max(0.0, deltaSeconds.isFinite ? deltaSeconds : 0.0))
        return max(
            stabilizerAutoCropPlaybackPositionMinimumStepPixels,
            scaledLimit
        )
    }

    private static func autoCropPlaybackLimitedPosition(
        current: vector_float2,
        adjacent: vector_float2,
        limit: Float
    ) -> vector_float2 {
        let delta = current - adjacent
        let length = simd_length(delta)
        guard length.isFinite,
              length > limit,
              limit.isFinite,
              limit >= 0.0
        else {
            return current
        }
        return adjacent + (delta / length) * limit
    }

    private static func autoCropPlaybackRateLimitedPositionSamples(
        _ samples: [AutoCropPlaybackPositionSample],
        outputSize: vector_float2
    ) -> [AutoCropPlaybackPositionSample] {
        guard samples.count > 2,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              stabilizerAutoCropPlaybackPositionRateLimitFractionPerSecond > 0.00001
        else {
            return samples
        }

        var forward = samples
        for index in 1..<samples.count {
            let deltaSeconds = samples[index].seconds - samples[index - 1].seconds
            let limit = autoCropPlaybackPositionStepLimit(
                deltaSeconds: deltaSeconds,
                outputSize: outputSize
            )
            forward[index] = AutoCropPlaybackPositionSample(
                seconds: samples[index].seconds,
                positionPixels: autoCropPlaybackLimitedPosition(
                    current: samples[index].positionPixels,
                    adjacent: forward[index - 1].positionPixels,
                    limit: limit
                )
            )
        }

        var backward = forward
        for index in stride(from: samples.count - 2, through: 0, by: -1) {
            let deltaSeconds = samples[index + 1].seconds - samples[index].seconds
            let limit = autoCropPlaybackPositionStepLimit(
                deltaSeconds: deltaSeconds,
                outputSize: outputSize
            )
            backward[index] = AutoCropPlaybackPositionSample(
                seconds: samples[index].seconds,
                positionPixels: autoCropPlaybackLimitedPosition(
                    current: forward[index].positionPixels,
                    adjacent: backward[index + 1].positionPixels,
                    limit: limit
                )
            )
        }

        return backward
    }

    private static func autoCropPlaybackScalePlanSample(
        _ plan: AutoCropPlaybackScalePlan,
        at seconds: Double
    ) -> Float {
        autoCropPlaybackScaleSample(plan.samples, at: seconds)
    }

    private static func autoCropPlaybackScalePlanCapSample(
        _ plan: AutoCropPlaybackScalePlan,
        at seconds: Double
    ) -> Float {
        let capScale = autoCropPlaybackScaleSample(plan.capSamples.isEmpty ? plan.samples : plan.capSamples, at: seconds)
        return autoCropPlaybackQuantizedScale(capScale + stabilizerAutoCropPlaybackCapSafetyDelta)
    }

    private static func autoCropPlaybackScaleSample(
        _ samples: [AutoCropPlaybackScaleSample],
        at seconds: Double
    ) -> Float {
        guard seconds.isFinite,
              let firstSample = samples.first
        else {
            return Float(1.0)
        }
        guard samples.count > 1,
              let lastSample = samples.last
        else {
            return max(Float(1.0), firstSample.scale)
        }
        if seconds <= firstSample.seconds {
            return max(Float(1.0), firstSample.scale)
        }
        if seconds >= lastSample.seconds {
            return max(Float(1.0), lastSample.scale)
        }

        var lowerIndex = 0
        var upperIndex = samples.count - 1
        while upperIndex - lowerIndex > 1 {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if samples[middleIndex].seconds <= seconds {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lowerSample = samples[lowerIndex]
        let upperSample = samples[upperIndex]
        let spanSeconds = upperSample.seconds - lowerSample.seconds
        guard spanSeconds > 1e-9 else {
            return max(Float(1.0), lowerSample.scale)
        }
        let fraction = min(max(Float((seconds - lowerSample.seconds) / spanSeconds), 0.0), 1.0)
        let easedFraction = easeInOutRamp(fraction)
        let interpolatedScale = lowerSample.scale + ((upperSample.scale - lowerSample.scale) * easedFraction)
        return max(Float(1.0), interpolatedScale)
    }

    private static func autoCropPlaybackPositionPlanSample(
        _ plan: AutoCropPlaybackScalePlan,
        at seconds: Double,
        fallback: vector_float2,
        outputSize: vector_float2
    ) -> vector_float2 {
        func scaledPosition(_ position: vector_float2) -> vector_float2 {
            guard plan.outputSize.x.isFinite,
                  plan.outputSize.y.isFinite,
                  outputSize.x.isFinite,
                  outputSize.y.isFinite,
                  plan.outputSize.x > Float.ulpOfOne,
                  plan.outputSize.y > Float.ulpOfOne,
                  outputSize.x > Float.ulpOfOne,
                  outputSize.y > Float.ulpOfOne
            else {
                return position
            }
            return vector_float2(
                position.x * (outputSize.x / plan.outputSize.x),
                position.y * (outputSize.y / plan.outputSize.y)
            )
        }

        let samples = plan.positionSamples
        guard seconds.isFinite,
              let firstSample = samples.first
        else {
            return fallback
        }
        guard samples.count > 1,
              let lastSample = samples.last
        else {
            return scaledPosition(firstSample.positionPixels)
        }
        if seconds <= firstSample.seconds {
            return scaledPosition(firstSample.positionPixels)
        }
        if seconds >= lastSample.seconds {
            return scaledPosition(lastSample.positionPixels)
        }

        var lowerIndex = 0
        var upperIndex = samples.count - 1
        while upperIndex - lowerIndex > 1 {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if samples[middleIndex].seconds <= seconds {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lowerSample = samples[lowerIndex]
        let upperSample = samples[upperIndex]
        let spanSeconds = upperSample.seconds - lowerSample.seconds
        guard spanSeconds > 1e-9 else {
            return scaledPosition(lowerSample.positionPixels)
        }
        let fraction = min(max(Float((seconds - lowerSample.seconds) / spanSeconds), 0.0), 1.0)
        let easedFraction = easeInOutRamp(fraction)
        let position = lowerSample.positionPixels + ((upperSample.positionPixels - lowerSample.positionPixels) * easedFraction)
        return scaledPosition(position)
    }

    private static func autoCropPlaybackFramingPlanSample(
        _ plan: AutoCropPlaybackScalePlan,
        at seconds: Double,
        fallback: vector_float2,
        outputSize: vector_float2
    ) -> (scale: Float, positionPixels: vector_float2) {
        func scaledPosition(_ position: vector_float2) -> vector_float2 {
            guard plan.outputSize.x.isFinite,
                  plan.outputSize.y.isFinite,
                  outputSize.x.isFinite,
                  outputSize.y.isFinite,
                  plan.outputSize.x > Float.ulpOfOne,
                  plan.outputSize.y > Float.ulpOfOne,
                  outputSize.x > Float.ulpOfOne,
                  outputSize.y > Float.ulpOfOne
            else {
                return position
            }
            return vector_float2(
                position.x * (outputSize.x / plan.outputSize.x),
                position.y * (outputSize.y / plan.outputSize.y)
            )
        }

        let samples = plan.framingSamples
        guard seconds.isFinite,
              let firstSample = samples.first
        else {
            let plannedScale = autoCropPlaybackScalePlanSample(plan, at: seconds)
            let finalScale = autoCropKeypointScale(
                protectedScale: autoCropPlaybackMinimumClippedScale(
                    autoCropPlaybackVisualScaleCap(plannedScale)
                )
            )
            return (
                scale: finalScale,
                positionPixels: autoCropPlaybackPositionPlanSample(
                    plan,
                    at: seconds,
                    fallback: fallback,
                    outputSize: outputSize
                )
            )
        }
        guard samples.count > 1,
              let lastSample = samples.last
        else {
            return (
                scale: max(Float(1.0), firstSample.scale),
                positionPixels: scaledPosition(firstSample.positionPixels)
            )
        }
        if seconds <= firstSample.seconds {
            return (
                scale: max(Float(1.0), firstSample.scale),
                positionPixels: scaledPosition(firstSample.positionPixels)
            )
        }
        if seconds >= lastSample.seconds {
            return (
                scale: max(Float(1.0), lastSample.scale),
                positionPixels: scaledPosition(lastSample.positionPixels)
            )
        }

        var lowerIndex = 0
        var upperIndex = samples.count - 1
        while upperIndex - lowerIndex > 1 {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if samples[middleIndex].seconds <= seconds {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lowerSample = samples[lowerIndex]
        let upperSample = samples[upperIndex]
        let spanSeconds = upperSample.seconds - lowerSample.seconds
        guard spanSeconds > 1e-9 else {
            return (
                scale: max(Float(1.0), lowerSample.scale),
                positionPixels: scaledPosition(lowerSample.positionPixels)
            )
        }
        let fraction = min(max(Float((seconds - lowerSample.seconds) / spanSeconds), 0.0), 1.0)
        let easedFraction = easeInOutRamp(fraction)
        let scale = lowerSample.scale + ((upperSample.scale - lowerSample.scale) * easedFraction)
        let position = lowerSample.positionPixels + ((upperSample.positionPixels - lowerSample.positionPixels) * easedFraction)
        return (
            scale: max(Float(1.0), scale),
            positionPixels: scaledPosition(position)
        )
    }

    private static func autoCropZoomPlan(
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropZoomPlan {
        guard masterStrength > 0.0001,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              let firstTime = preparedAnalysis.frames.first?.time,
              let lastTime = preparedAnalysis.frames.last?.time,
              firstTime <= lastTime
        else {
            return AutoCropZoomPlan(keypoints: [], telemetry: .empty)
        }

        let coarseSamples = autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            startSeconds: firstTime,
            endSeconds: lastTime,
            stepSeconds: samplingProfile.zoomKeypointCoarseStepSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            turnZoomLookaheadSeconds: leadTimeSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        guard !coarseSamples.isEmpty else {
            return AutoCropZoomPlan(keypoints: [], telemetry: .empty)
        }
        let coverageSamples = autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            startSeconds: firstTime,
            endSeconds: lastTime,
            stepSeconds: samplingProfile.zoomKeypointCoverageStepSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            turnZoomLookaheadSeconds: leadTimeSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        let safetySamples = coverageSamples.isEmpty ? coarseSamples : coverageSamples

        let localMaxima = autoCropZoomLocalMaxima(
            coarseSamples,
            thresholdDelta: stabilizerAutoCropKeypointScaleThresholdDelta
        )
        let rawCandidates = localMaxima.isEmpty
            ? Array(coarseSamples.sorted { $0.scale > $1.scale }.prefix(stabilizerAutoCropKeypointMaximumCount))
            : Array(localMaxima.sorted { $0.scale > $1.scale }.prefix(stabilizerAutoCropKeypointMaximumCount * 2))
        let refinedCandidates = rawCandidates.compactMap { candidate in
            autoCropRefinedZoomDemandSample(
                around: candidate.seconds,
                firstTime: firstTime,
                lastTime: lastTime,
                preparedAnalysis: preparedAnalysis,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
        }.filter { $0.scale > Float(1.0) + stabilizerAutoCropKeypointScaleThresholdDelta }

        let minimumSpacingSeconds = max(
            samplingProfile.zoomKeypointMinimumSpacingSeconds,
            max(0.0, leadTimeSeconds)
                + max(0.0, holdTimeSeconds)
                + max(0.0, transitionDurationSeconds)
        )
        var selected: [AutoCropZoomDemandSample] = []
        for candidate in refinedCandidates.sorted(by: { $0.scale > $1.scale }) {
            guard !selected.contains(where: { abs($0.seconds - candidate.seconds) < minimumSpacingSeconds }) else {
                continue
            }
            selected.append(candidate)
            if selected.count >= stabilizerAutoCropKeypointMaximumCount {
                break
            }
        }
        selected = autoCropCoverageRepairedZoomSamples(
            selected,
            coverageSamples: safetySamples,
            firstTime: firstTime,
            lastTime: lastTime,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            transitionDurationSeconds: transitionDurationSeconds
        )

        let preMergeSamples = selected
        let preMergePlan = AutoCropZoomPlan(
            keypoints: autoCropZoomKeypoints(
                from: preMergeSamples,
                firstTime: firstTime,
                lastTime: lastTime,
                leadTimeSeconds: leadTimeSeconds,
                holdTimeSeconds: holdTimeSeconds,
                transitionDurationSeconds: transitionDurationSeconds
            ),
            telemetry: .empty
        )
        let preMergeCoverage = autoCropCoverageSummary(
            plan: preMergePlan,
            samples: safetySamples
        )

        let mergeResult = autoCropMicroMergedZoomSamples(
            preMergeSamples,
            outputSize: outputSize,
            firstTime: firstTime,
            lastTime: lastTime,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            transitionDurationSeconds: transitionDurationSeconds
        )
        var finalSamples = mergeResult.samples
        var finalCoverage = autoCropCoverageSummary(
            plan: AutoCropZoomPlan(
                keypoints: autoCropZoomKeypoints(
                    from: finalSamples,
                    firstTime: firstTime,
                    lastTime: lastTime,
                    leadTimeSeconds: leadTimeSeconds,
                    holdTimeSeconds: holdTimeSeconds,
                    transitionDurationSeconds: transitionDurationSeconds
                ),
                telemetry: .empty
            ),
            samples: safetySamples
        )
        if finalCoverage.missCount > 0 {
            finalSamples = autoCropCoverageRepairedZoomSamples(
                finalSamples,
                coverageSamples: safetySamples,
                firstTime: firstTime,
                lastTime: lastTime,
                leadTimeSeconds: leadTimeSeconds,
                holdTimeSeconds: holdTimeSeconds,
                transitionDurationSeconds: transitionDurationSeconds
            )
            finalCoverage = autoCropCoverageSummary(
                plan: AutoCropZoomPlan(
                    keypoints: autoCropZoomKeypoints(
                        from: finalSamples,
                        firstTime: firstTime,
                        lastTime: lastTime,
                        leadTimeSeconds: leadTimeSeconds,
                        holdTimeSeconds: holdTimeSeconds,
                        transitionDurationSeconds: transitionDurationSeconds
                    ),
                    telemetry: .empty
                ),
                samples: safetySamples
            )
        }

        var mergeBypassed = false
        if autoCropCoverageSummary(finalCoverage, isWorseThan: preMergeCoverage) {
            os_log(
                "Auto Crop micro merge bypassed due to coverage gap | rawCount %d mergedCount %d clusters %d missCount %d baselineMissCount %d worstDeficit %.4f baselineWorstDeficit %.4f",
                log: stabilizerHostAnalysisLog,
                type: .error,
                preMergeSamples.count,
                mergeResult.mergedCount,
                mergeResult.clusterCount,
                finalCoverage.missCount,
                preMergeCoverage.missCount,
                finalCoverage.worstDeficit,
                preMergeCoverage.worstDeficit
            )
            finalSamples = preMergeSamples
            finalCoverage = preMergeCoverage
            mergeBypassed = true
        }

        let keypoints = autoCropZoomKeypoints(
            from: finalSamples,
            firstTime: firstTime,
            lastTime: lastTime,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            transitionDurationSeconds: transitionDurationSeconds
        )
        let descendingHandoffCount = autoCropZoomHandoffSegments(keypoints).count
        let telemetry = AutoCropCoverageTelemetry(
            planCount: keypoints.count,
            rawCount: preMergeSamples.count,
            mergedCount: mergeBypassed ? 0 : mergeResult.mergedCount,
            mergeClusterCount: mergeBypassed ? 0 : mergeResult.clusterCount,
            mergeBypassed: mergeBypassed,
            missCount: finalCoverage.missCount,
            worstSeconds: finalCoverage.worstSeconds,
            worstRequiredScale: finalCoverage.worstRequiredScale,
            worstPlannedScale: finalCoverage.worstPlannedScale,
            worstDeficit: finalCoverage.worstDeficit
        )

        if let strongest = keypoints.max(by: { $0.scale < $1.scale }) {
            os_log(
                "Auto Crop zoom keypoint plan | count %d descendingHandoffs %d rawCount %d mergedCount %d clusters %d missCount %d worstDeficit %.4f strongestPeak %.3f start %.3f holdEnd %.3f end %.3f scale %.4f lead %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                keypoints.count,
                descendingHandoffCount,
                telemetry.rawCount,
                telemetry.mergedCount,
                telemetry.mergeClusterCount,
                telemetry.missCount,
                telemetry.worstDeficit,
                strongest.peakSeconds,
                strongest.startSeconds,
                strongest.holdEndSeconds,
                strongest.endSeconds,
                strongest.scale,
                leadTimeSeconds
            )
            for (rank, keypoint) in keypoints
                .sorted(by: { $0.scale > $1.scale })
                .prefix(stabilizerAutoCropKeypointLogLimit)
                .enumerated() {
                os_log(
                    "Auto Crop zoom keypoint | rank %d peak %.3f start %.3f holdEnd %.3f end %.3f scale %.4f posX %.2f posY %.2f",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    rank + 1,
                    keypoint.peakSeconds,
                    keypoint.startSeconds,
                    keypoint.holdEndSeconds,
                    keypoint.endSeconds,
                    keypoint.scale,
                    keypoint.positionPixels.x,
                    keypoint.positionPixels.y
                )
            }
        } else {
            os_log(
                "Auto Crop zoom keypoint plan | count 0 rawCount %d mergedCount %d clusters %d missCount %d worstDeficit %.4f lead %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                telemetry.rawCount,
                telemetry.mergedCount,
                telemetry.mergeClusterCount,
                telemetry.missCount,
                telemetry.worstDeficit,
                leadTimeSeconds
            )
        }

        return AutoCropZoomPlan(keypoints: keypoints, telemetry: telemetry)
    }

    private static func autoCropCoverageRepairedZoomSamples(
        _ initialSamples: [AutoCropZoomDemandSample],
        coverageSamples: [AutoCropZoomDemandSample],
        firstTime: Double,
        lastTime: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        transitionDurationSeconds: Double
    ) -> [AutoCropZoomDemandSample] {
        guard !coverageSamples.isEmpty else {
            return initialSamples
        }
        let requiredSamples = coverageSamples
            .filter { $0.scale > Float(1.0) + stabilizerAutoCropKeypointCoverageThresholdDelta }
            .sorted { $0.scale > $1.scale }
        guard !requiredSamples.isEmpty else {
            return initialSamples
        }

        var selected = initialSamples
        var passCount = 0
        while selected.count < stabilizerAutoCropKeypointMaximumCount,
              passCount < stabilizerAutoCropKeypointCoveragePassLimit {
            passCount += 1
            let plan = AutoCropZoomPlan(
                keypoints: autoCropZoomKeypoints(
                    from: selected,
                    firstTime: firstTime,
                    lastTime: lastTime,
                    leadTimeSeconds: leadTimeSeconds,
                    holdTimeSeconds: holdTimeSeconds,
                    transitionDurationSeconds: transitionDurationSeconds
                ),
                telemetry: .empty
            )

            var uncoveredSample: AutoCropZoomDemandSample?
            for sample in requiredSamples {
                if selected.contains(where: { abs($0.seconds - sample.seconds) < stabilizerAutoCropKeypointDuplicateSeconds }) {
                    continue
                }
                let plannedScale = autoCropZoomPlanSample(plan, at: sample.seconds).scale
                let requiredScale = autoCropZoomKeypointScale(forDemandScale: sample.scale)
                guard plannedScale + stabilizerAutoCropKeypointCoverageToleranceDelta < requiredScale else {
                    continue
                }
                uncoveredSample = sample
                break
            }
            guard let sample = uncoveredSample else {
                break
            }
            selected.append(sample)
        }
        return selected
    }

    private static func autoCropCoverageSummary(
        plan: AutoCropZoomPlan,
        samples coverageSamples: [AutoCropZoomDemandSample]
    ) -> AutoCropCoverageSummary {
        guard !coverageSamples.isEmpty else {
            return .empty
        }
        var missCount = 0
        var worstSeconds: Double?
        var worstRequiredScale = Float(1.0)
        var worstPlannedScale = Float(1.0)
        var worstDeficit = Float(0.0)
        for sample in coverageSamples where sample.scale > Float(1.0) + stabilizerAutoCropKeypointCoverageThresholdDelta {
            let requiredScale = autoCropZoomKeypointScale(forDemandScale: sample.scale)
            let plannedScale = autoCropZoomPlanSample(plan, at: sample.seconds).scale
            let deficit = requiredScale - plannedScale
            if plannedScale + stabilizerAutoCropKeypointCoverageToleranceDelta < requiredScale {
                missCount += 1
            }
            if deficit > worstDeficit {
                worstDeficit = deficit
                worstSeconds = sample.seconds
                worstRequiredScale = requiredScale
                worstPlannedScale = plannedScale
            }
        }
        guard missCount > 0 || worstSeconds != nil else {
            return .empty
        }
        return AutoCropCoverageSummary(
            missCount: missCount,
            worstSeconds: worstSeconds,
            worstRequiredScale: worstRequiredScale,
            worstPlannedScale: worstPlannedScale,
            worstDeficit: worstDeficit
        )
    }

    private static func autoCropCoverageSummary(
        _ candidate: AutoCropCoverageSummary,
        isWorseThan baseline: AutoCropCoverageSummary
    ) -> Bool {
        if candidate.missCount != baseline.missCount {
            return candidate.missCount > baseline.missCount
        }
        return candidate.worstDeficit > baseline.worstDeficit + 0.00001
    }

    private static func autoCropMicroMergedZoomSamples(
        _ samples: [AutoCropZoomDemandSample],
        outputSize: vector_float2,
        firstTime: Double,
        lastTime: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        transitionDurationSeconds: Double
    ) -> (samples: [AutoCropZoomDemandSample], mergedCount: Int, clusterCount: Int) {
        guard samples.count > 1 else {
            return (samples, 0, 0)
        }
        let positionTolerance = max(
            stabilizerAutoCropMicroMergeMinimumPositionTolerance,
            min(outputSize.x, outputSize.y) * stabilizerAutoCropMicroMergePositionToleranceFraction
        )
        var mergedSamples: [AutoCropZoomDemandSample] = []
        var currentCluster: [AutoCropZoomDemandSample] = []
        var currentClusterEnd = -Double.infinity
        var mergedCount = 0
        var clusterCount = 0

        func keypoint(for sample: AutoCropZoomDemandSample) -> AutoCropZoomKeypoint {
            autoCropZoomKeypoints(
                from: [sample],
                firstTime: firstTime,
                lastTime: lastTime,
                leadTimeSeconds: leadTimeSeconds,
                holdTimeSeconds: holdTimeSeconds,
                transitionDurationSeconds: transitionDurationSeconds
            ).first ?? AutoCropZoomKeypoint(
                peakSeconds: sample.seconds,
                startSeconds: sample.seconds,
                holdEndSeconds: sample.seconds,
                endSeconds: sample.seconds,
                scale: autoCropZoomKeypointScale(forDemandScale: sample.scale),
                positionPixels: sample.positionPixels
            )
        }

        func appendCurrentCluster() {
            guard !currentCluster.isEmpty else {
                return
            }
            if currentCluster.count == 1 {
                mergedSamples.append(currentCluster[0])
            } else {
                let representative = autoCropMicroMergeRepresentativeSample(
                    currentCluster,
                    firstTime: firstTime,
                    lastTime: lastTime
                )
                mergedSamples.append(representative)
                mergedCount += currentCluster.count - 1
                clusterCount += 1
            }
            currentCluster.removeAll(keepingCapacity: true)
            currentClusterEnd = -Double.infinity
        }

        for sample in samples.sorted(by: { $0.seconds < $1.seconds }) {
            guard sample.scale <= stabilizerAutoCropMicroMergeScaleThreshold else {
                appendCurrentCluster()
                mergedSamples.append(sample)
                continue
            }
            let sampleKeypoint = keypoint(for: sample)
            if currentCluster.isEmpty {
                currentCluster = [sample]
                currentClusterEnd = sampleKeypoint.endSeconds
                continue
            }
            let touchesCluster = sampleKeypoint.startSeconds <= currentClusterEnd + stabilizerAutoCropMicroMergeTouchGapSeconds
            let positionMatchesCluster = autoCropMicroMergePositionMatches(
                sample.positionPixels,
                clusterSamples: currentCluster,
                tolerance: positionTolerance
            )
            guard touchesCluster, positionMatchesCluster else {
                appendCurrentCluster()
                currentCluster = [sample]
                currentClusterEnd = sampleKeypoint.endSeconds
                continue
            }
            currentCluster.append(sample)
            currentClusterEnd = max(currentClusterEnd, sampleKeypoint.endSeconds)
        }
        appendCurrentCluster()
        return (mergedSamples, mergedCount, clusterCount)
    }

    private static func autoCropMicroMergePositionMatches(
        _ position: vector_float2,
        clusterSamples: [AutoCropZoomDemandSample],
        tolerance: Float
    ) -> Bool {
        guard !clusterSamples.isEmpty else {
            return true
        }
        for sample in clusterSamples {
            let delta = position - sample.positionPixels
            guard simd_length(delta) <= tolerance else {
                return false
            }
        }
        return true
    }

    private static func autoCropMicroMergeRepresentativeSample(
        _ samples: [AutoCropZoomDemandSample],
        firstTime: Double,
        lastTime: Double
    ) -> AutoCropZoomDemandSample {
        guard var strongest = samples.first else {
            return AutoCropZoomDemandSample(
                seconds: firstTime,
                scale: 1.0,
                positionPixels: vector_float2(0.0, 0.0),
                neutralScale: 1.0,
                neutralPositionPixels: vector_float2(0.0, 0.0),
                turnZoomScale: 1.0,
                transform: .identity
            )
        }
        var firstPeak = strongest.seconds
        var lastPeak = strongest.seconds
        for sample in samples {
            firstPeak = min(firstPeak, sample.seconds)
            lastPeak = max(lastPeak, sample.seconds)
            if sample.scale > strongest.scale {
                strongest = sample
            }
        }
        let centerSeconds = min(max((firstPeak + lastPeak) * 0.5, firstTime), lastTime)
        return AutoCropZoomDemandSample(
            seconds: centerSeconds,
            scale: strongest.scale,
            positionPixels: strongest.positionPixels,
            neutralScale: strongest.neutralScale,
            neutralPositionPixels: strongest.neutralPositionPixels,
            turnZoomScale: strongest.turnZoomScale,
            transform: strongest.transform
        )
    }

    private static func autoCropZoomKeypoints(
        from samples: [AutoCropZoomDemandSample],
        firstTime: Double,
        lastTime: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        transitionDurationSeconds: Double
    ) -> [AutoCropZoomKeypoint] {
        let keypoints = samples
            .sorted { $0.seconds < $1.seconds }
            .map { sample in
                let keypointScale = autoCropZoomKeypointScale(forDemandScale: sample.scale)
                let effectiveLeadTime = leadTimeSeconds.isFinite ? max(0.0, leadTimeSeconds) : 0.0
                let effectiveHoldTime = holdTimeSeconds.isFinite ? max(0.0, holdTimeSeconds) : 0.0
                let effectiveTransitionDuration = transitionDurationSeconds.isFinite ? max(0.0, transitionDurationSeconds) : 0.0
                return AutoCropZoomKeypoint(
                    peakSeconds: sample.seconds,
                    startSeconds: max(firstTime, sample.seconds - effectiveLeadTime),
                    holdEndSeconds: min(lastTime, sample.seconds + effectiveHoldTime),
                    endSeconds: min(
                        lastTime,
                        sample.seconds + effectiveHoldTime + effectiveTransitionDuration
                    ),
                    scale: keypointScale,
                    positionPixels: sample.positionPixels
                )
            }
        return autoCropZoomKeypointsWithPostponedRelease(
            keypoints,
            lastTime: lastTime,
            leadTimeSeconds: leadTimeSeconds,
            transitionDurationSeconds: transitionDurationSeconds
        )
    }

    private static func autoCropZoomKeypointsWithPostponedRelease(
        _ keypoints: [AutoCropZoomKeypoint],
        lastTime: Double,
        leadTimeSeconds: Double,
        transitionDurationSeconds: Double
    ) -> [AutoCropZoomKeypoint] {
        guard keypoints.count > 1 else {
            return keypoints
        }
        let effectiveLeadTime = leadTimeSeconds.isFinite ? max(0.0, leadTimeSeconds) : 0.0
        let effectiveTransitionDuration = transitionDurationSeconds.isFinite ? max(0.0, transitionDurationSeconds) : 0.0
        var adjusted = keypoints.sorted { $0.peakSeconds < $1.peakSeconds }
        for index in adjusted.indices.dropLast() {
            let current = adjusted[index]
            let next = adjusted[adjusted.index(after: index)]
            guard next.scale >= current.scale - 0.00001 else {
                continue
            }
            guard next.startSeconds <= current.endSeconds + effectiveLeadTime + 1e-9 else {
                continue
            }
            let postponedHoldEnd = min(lastTime, max(current.holdEndSeconds, next.peakSeconds))
            let postponedEnd = min(
                lastTime,
                max(current.endSeconds, postponedHoldEnd + effectiveTransitionDuration)
            )
            adjusted[index] = AutoCropZoomKeypoint(
                peakSeconds: current.peakSeconds,
                startSeconds: current.startSeconds,
                holdEndSeconds: postponedHoldEnd,
                endSeconds: postponedEnd,
                scale: current.scale,
                positionPixels: current.positionPixels
            )
        }
        return adjusted
    }

    private static func autoCropZoomKeypointScale(forDemandScale demandScale: Float) -> Float {
        StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: demandScale)
    }

    private static func autoCropZoomDemandSamples(
        preparedAnalysis: StabilizerPreparedAnalysis,
        startSeconds: Double,
        endSeconds: Double,
        stepSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        turnZoomLookaheadSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        preparedPlaybackTransforms: [StabilizerAutoTransform]? = nil
    ) -> [AutoCropZoomDemandSample] {
        let step = max(stepSeconds, stabilizerAutoCropDemandMinimumStepSeconds)
        var sampleSeconds: [Double] = []
        var seconds = startSeconds
        while seconds <= endSeconds + 1e-9 {
            sampleSeconds.append(seconds)
            seconds += step
        }
        if abs((sampleSeconds.last ?? startSeconds) - endSeconds) > 1e-6 {
            sampleSeconds.append(endSeconds)
        }
        return autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            sampleSeconds: sampleSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            turnZoomLookaheadSeconds: turnZoomLookaheadSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            preparedPlaybackTransforms: preparedPlaybackTransforms
        )
    }

    private static func autoCropZoomDemandSamples(
        preparedAnalysis: StabilizerPreparedAnalysis,
        sampleSeconds: [Double],
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        turnZoomLookaheadSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        preparedPlaybackTransforms: [StabilizerAutoTransform]? = nil
    ) -> [AutoCropZoomDemandSample] {
        let turnAnalysisStrengths = fullTurnAnalysisStrengths(strengths)
        let rawTransforms: [StabilizerAutoTransform]
        if samplingProfile == .playback {
            rawTransforms = preparedPlaybackTransforms ?? AutoStabilizationEstimator.playbackEstimates(
                    preparedAnalysis: preparedAnalysis,
                    sampleSeconds: sampleSeconds,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: turnAnalysisStrengths
                )
        } else {
            rawTransforms = sampleSeconds.map { seconds in
                autoCropTimelineTransform(
                    preparedAnalysis: preparedAnalysis,
                    seconds: seconds,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: turnAnalysisStrengths,
                    samplingProfile: samplingProfile,
                    analysisRevision: analysisRevision,
                    cacheIdentity: cacheIdentity
                )
            }
        }
        guard rawTransforms.count == sampleSeconds.count else {
            return []
        }
        let viewportTransforms: [StabilizerAutoTransform]
        if samplingProfile == .playback {
            // Canonical playback applies Turn Strength before concatenation.
            viewportTransforms = rawTransforms
        } else if turnViewportAuthority(strengths.turnSmoothingZoom) > Float.ulpOfOne {
            viewportTransforms = rawTransforms.map {
                turnViewportPlanningTransform(
                    $0,
                    turnSmoothingStrength: strengths.turnSmoothingZoom
                )
            }
        } else {
            viewportTransforms = rawTransforms
        }
        var samples: [AutoCropZoomDemandSample] = []
        samples.reserveCapacity(sampleSeconds.count)
        for (seconds, transform) in zip(sampleSeconds, viewportTransforms) {
            if let sample = autoCropZoomDemandSample(
                seconds: seconds,
                transform: transform,
                outputSize: outputSize,
                masterStrength: masterStrength,
                strengths: strengths,
                samplingProfile: samplingProfile,
                turnTransformAlreadyScaled: samplingProfile == .playback
            ) {
                samples.append(sample)
            }
        }
        return autoCropDemandSamplesWithForwardTurnZoomLookahead(
            samples,
            lookaheadSeconds: turnZoomLookaheadSeconds
        )
    }

    private static func autoCropDemandSamplesWithForwardTurnZoomLookahead(
        _ samples: [AutoCropZoomDemandSample],
        lookaheadSeconds: Double
    ) -> [AutoCropZoomDemandSample] {
        guard samples.count > 1,
              lookaheadSeconds.isFinite,
              lookaheadSeconds > 1e-6
        else {
            return samples
        }
        let ordered = samples.sorted { $0.seconds < $1.seconds }
        var adjusted = ordered
        for index in ordered.indices {
            let sample = ordered[index]
            guard sample.seconds.isFinite else {
                continue
            }
            let lookaheadEnd = sample.seconds + lookaheadSeconds + 1e-9
            var strongestTurnZoom = sample.turnZoomScale.isFinite ? sample.turnZoomScale : Float(1.0)
            var futureIndex = ordered.index(after: index)
            while futureIndex < ordered.endIndex {
                let future = ordered[futureIndex]
                guard future.seconds <= lookaheadEnd else {
                    break
                }
                strongestTurnZoom = max(
                    strongestTurnZoom,
                    future.turnZoomScale.isFinite ? future.turnZoomScale : Float(1.0)
                )
                futureIndex = ordered.index(after: futureIndex)
            }
            let currentScale = sample.scale.isFinite ? sample.scale : Float(1.0)
            let heldScale = max(currentScale, strongestTurnZoom)
            let heldTurnZoom = max(
                sample.turnZoomScale.isFinite ? sample.turnZoomScale : Float(1.0),
                strongestTurnZoom
            )
            let currentTurnZoom = sample.turnZoomScale.isFinite ? sample.turnZoomScale : Float(1.0)
            guard heldScale > currentScale + Float.ulpOfOne || heldTurnZoom > currentTurnZoom + Float.ulpOfOne else {
                continue
            }
            adjusted[index] = AutoCropZoomDemandSample(
                seconds: sample.seconds,
                scale: heldScale,
                positionPixels: sample.positionPixels,
                neutralScale: sample.neutralScale,
                neutralPositionPixels: sample.neutralPositionPixels,
                turnZoomScale: heldTurnZoom,
                transform: sample.transform
            )
        }
        return adjusted
    }

    private static func autoCropZoomLocalMaxima(
        _ samples: [AutoCropZoomDemandSample],
        thresholdDelta: Float
    ) -> [AutoCropZoomDemandSample] {
        guard samples.count >= 3 else {
            return samples.filter { $0.scale > Float(1.0) + thresholdDelta }
        }
        var maxima: [AutoCropZoomDemandSample] = []
        for index in samples.indices {
            let sample = samples[index]
            guard sample.scale > Float(1.0) + thresholdDelta else {
                continue
            }
            let previousScale = index > samples.startIndex ? samples[samples.index(before: index)].scale : Float(1.0)
            let nextScale = index < samples.index(before: samples.endIndex) ? samples[samples.index(after: index)].scale : Float(1.0)
            if sample.scale >= previousScale, sample.scale >= nextScale {
                maxima.append(sample)
            }
        }
        return maxima
    }

    private static func autoCropRefinedZoomDemandSample(
        around centerSeconds: Double,
        firstTime: Double,
        lastTime: Double,
        preparedAnalysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropZoomDemandSample? {
        let startSeconds = max(firstTime, centerSeconds - stabilizerAutoCropKeypointRefineRadiusSeconds)
        let endSeconds = min(lastTime, centerSeconds + stabilizerAutoCropKeypointRefineRadiusSeconds)
        var best: AutoCropZoomDemandSample?
        var seconds = startSeconds
        while seconds <= endSeconds + 1e-9 {
            if let sample = autoCropZoomDemandSample(
                preparedAnalysis: preparedAnalysis,
                seconds: seconds,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                masterStrength: masterStrength,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            ), best == nil || sample.scale > best!.scale {
                best = sample
            }
            seconds += stabilizerAutoCropKeypointRefineStepSeconds
        }
        return best
    }

    private static func autoCropZoomDemandSample(
        preparedAnalysis: StabilizerPreparedAnalysis,
        seconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> AutoCropZoomDemandSample? {
        guard seconds.isFinite,
              outputSize.x > 1.0,
              outputSize.y > 1.0
        else {
            return nil
        }
        let transform = autoCropTimelineTransform(
            preparedAnalysis: preparedAnalysis,
            seconds: seconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        return autoCropZoomDemandSample(
            seconds: seconds,
            transform: transform,
            outputSize: outputSize,
            masterStrength: masterStrength,
            strengths: strengths,
            samplingProfile: samplingProfile,
            turnTransformAlreadyScaled: samplingProfile == .playback
        )
    }

    private static func autoCropTurnSmoothingZoomScale(
        transform: StabilizerAutoTransform,
        outputSize: vector_float2,
        masterStrength: Float,
        strengths: StabilizerCorrectionStrengths
    ) -> Float {
        let zoomCapScale = turnSmoothingZoomCapScale(strengths.turnSmoothingZoom)
        let zoomDelta = max(Float(0.0), zoomCapScale - Float(1.0))
        guard zoomDelta > Float.ulpOfOne,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              masterStrength.isFinite,
              masterStrength > Float.ulpOfOne
        else {
            return 1.0
        }
        let turnPixels = abs(transform.turnDetectedPixelOffset.x) * max(0.0, masterStrength)
        let travelSupport = thresholdRamp(
            turnPixels,
            start: stabilizerAutoCropTurnSmoothingZoomStartPixels,
            full: stabilizerAutoCropTurnSmoothingZoomFullPixels
        )
        guard travelSupport > Float.ulpOfOne else {
            return 1.0
        }
        let turnConfidenceSupport = thresholdRamp(
            min(max(transform.turnConfidence, 0.0), 1.0),
            start: stabilizerAutoCropTurnSmoothingZoomConfidenceStart,
            full: stabilizerAutoCropTurnSmoothingZoomConfidenceFull
        )
        guard turnConfidenceSupport > Float.ulpOfOne else {
            return 1.0
        }
        let support = min(travelSupport, turnConfidenceSupport)
        let delta = zoomDelta * support
        return max(1.0, 1.0 + delta)
    }

    private static func autoCropZoomDemandSample(
        seconds: Double,
        transform: StabilizerAutoTransform,
        outputSize: vector_float2,
        masterStrength: Float,
        strengths: StabilizerCorrectionStrengths,
        samplingProfile: AutoCropSamplingProfile,
        turnTransformAlreadyScaled: Bool
    ) -> AutoCropZoomDemandSample? {
        guard seconds.isFinite,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              masterStrength.isFinite
        else {
            return nil
        }
        let context = AutoCropTransformContext(
            transform: transform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        var cameraOnlyTransform = transform
        let turnMacroX = cameraOnlyTransform.macroPixelOffset.x
        cameraOnlyTransform.macroPixelOffset.x = 0.0
        cameraOnlyTransform.pixelOffset.x -= turnMacroX
        cameraOnlyTransform.rawPixelOffset.x -= turnMacroX
        let cameraOnlyContext = AutoCropTransformContext(
            transform: cameraOnlyTransform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let cameraPositionPixels = blackSafeAutoCropPosition(
            preferredPositionPixels: vector_float2(0.0, 0.0),
            context: cameraOnlyContext,
            samplingProfile: samplingProfile
        )
        let cameraCropScale = requiredAutoCropScale(
            context: cameraOnlyContext,
            cropPositionPixels: cameraPositionPixels,
            sampleSteps: samplingProfile.scaleSearchSampleSteps,
            iterations: samplingProfile.scaleSearchIterations
        )
        let fullPositionPixels = blackSafeAutoCropPosition(
            preferredPositionPixels: transform.macroPixelOffset * masterStrength,
            context: context,
            samplingProfile: samplingProfile
        )
        let fullCropScale = requiredAutoCropScale(
            context: context,
            // Measure Turn overflow against the Camera-only viewport. Measuring
            // after following the full Turn position cancels the left/right
            // overflow and makes every Turn Strength produce the same zoom.
            cropPositionPixels: cameraPositionPixels,
            sampleSteps: samplingProfile.scaleSearchSampleSteps,
            iterations: samplingProfile.scaleSearchIterations
        )
        let turnStrength = turnTransformAlreadyScaled
            ? Float(1.0)
            : turnViewportAuthority(strengths.turnSmoothingZoom)
        let turnOverflowScale = max(0.0, fullCropScale - cameraCropScale)
        let turnViewportDelta = fullPositionPixels - cameraPositionPixels
        let positionPixels = cameraPositionPixels + (turnViewportDelta * turnStrength)
        let scale = cameraCropScale + (turnOverflowScale * turnStrength)
        return AutoCropZoomDemandSample(
            seconds: seconds,
            scale: scale,
            positionPixels: positionPixels,
            neutralScale: cameraCropScale,
            neutralPositionPixels: cameraPositionPixels,
            turnZoomScale: max(1.0, 1.0 + (turnOverflowScale * turnStrength)),
            // Coverage repair must use the same Strength-scaled Turn path.
            // Supplying the full transform here made Strength 0 and 12 converge
            // to the same full-Turn coverage floor.
            transform: turnTransformAlreadyScaled
                ? transform
                : turnViewportPlanningTransform(
                    transform,
                    turnSmoothingStrength: strengths.turnSmoothingZoom
                )
        )
    }

    private static func autoCropTimelineTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        seconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> StabilizerAutoTransform {
        if samplingProfile == .playback {
            let sampleTime = CMTimeMakeWithSeconds(seconds, preferredTimescale: 60000)
            return cachedAutoTransform(
                preparedAnalysis: preparedAnalysis,
                renderTime: sampleTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity,
                playbackMode: true
            )
        }
        if !samplingProfile.usesStabilizedSampleTransforms {
            if let preparedTransform = autoCropPreparedAbsoluteTransform(
                preparedAnalysis: preparedAnalysis,
                seconds: seconds,
                outputSize: outputSize
            ) {
                return preparedTransform
            }
            os_log(
                "Auto Crop prepared sample transform unavailable; using stabilized estimator | seconds %.3f",
                log: stabilizerHostAnalysisLog,
                type: .error,
                seconds
            )
        }
        let sampleTime = CMTimeMakeWithSeconds(seconds, preferredTimescale: 60000)
        return cachedAutoTransform(
            preparedAnalysis: preparedAnalysis,
            renderTime: sampleTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            playbackMode: samplingProfile == .playback
        )
    }

    private static func autoCropPreparedAbsoluteTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        seconds: Double,
        outputSize: vector_float2
    ) -> StabilizerAutoTransform? {
        guard let sample = autoCropPreparedPathSample(
            preparedAnalysis: preparedAnalysis,
            seconds: seconds
        ) else {
            return nil
        }
        let xScale = outputSize.x / Float(max(1, sample.sampleWidth))
        let yScale = outputSize.y / Float(max(1, sample.sampleHeight))
        let macroPixelOffset = vector_float2(
            -sample.pathX * xScale,
            -sample.pathY * yScale
        )
        var transform = StabilizerAutoTransform.identity
        transform.macroPixelOffset = macroPixelOffset
        transform.pixelOffset = macroPixelOffset
        transform.rawPixelOffset = macroPixelOffset
        transform.rotationDegrees = -sample.pathRoll
        transform.rawRotationDegrees = -sample.pathRoll
        transform.yawPitchProxy = vector_float2(
            -sample.pathYaw,
            -sample.pathPitch
        )
        transform.shear = vector_float2(
            -sample.pathShearX,
            -sample.pathShearY
        )
        transform.perspective = vector_float2(
            -sample.pathPerspectiveX,
            -sample.pathPerspectiveY
        )
        return transform
    }

    private static func autoCropZoomPlanSample(
        _ plan: AutoCropZoomPlan,
        at seconds: Double
    ) -> AutoCropZoomPlanSample {
        guard seconds.isFinite else {
            return .identity
        }
        var bestSample = AutoCropZoomPlanSample.identity
        for keypoint in plan.keypoints {
            let influence = autoCropZoomKeypointInfluence(
                keypoint,
                at: seconds
            )
            guard influence > 0.0001 else {
                continue
            }
            let scale = Float(1.0) + ((max(keypoint.scale, 1.0) - Float(1.0)) * influence)
            guard scale > bestSample.scale else {
                continue
            }
            bestSample = AutoCropZoomPlanSample(
                scale: scale,
                positionPixels: keypoint.positionPixels * influence,
                influence: influence,
                peakSeconds: keypoint.peakSeconds
            )
        }
        let handoff = StabilizerAutoCropZoomHandoff.scale(
            baseScale: bestSample.scale,
            at: seconds,
            handoffs: autoCropZoomHandoffSegments(plan.keypoints)
        )
        if handoff.applied {
            bestSample = AutoCropZoomPlanSample(
                scale: handoff.scale,
                positionPixels: bestSample.positionPixels,
                influence: bestSample.influence,
                peakSeconds: bestSample.peakSeconds
            )
        }
        return bestSample
    }

    private static func autoCropZoomHandoffSegments(
        _ keypoints: [AutoCropZoomKeypoint]
    ) -> [StabilizerAutoCropZoomHandoffSegment] {
        StabilizerAutoCropZoomHandoff.segments(
            keypoints: keypoints.map { keypoint in
                StabilizerAutoCropZoomHandoffKeypoint(
                    peakSeconds: keypoint.peakSeconds,
                    startSeconds: keypoint.startSeconds,
                    holdEndSeconds: keypoint.holdEndSeconds,
                    endSeconds: keypoint.endSeconds,
                    protectedScale: keypoint.scale
                )
            }
        )
    }

    private static func autoCropZoomKeypointInfluence(
        _ keypoint: AutoCropZoomKeypoint,
        at seconds: Double
    ) -> Float {
        guard seconds >= keypoint.startSeconds,
              seconds <= keypoint.endSeconds
        else {
            return 0.0
        }
        if seconds <= keypoint.peakSeconds {
            let span = keypoint.peakSeconds - keypoint.startSeconds
            guard span > 1e-6 else {
                return 1.0
            }
            return easeInOutRamp(Float((seconds - keypoint.startSeconds) / span))
        }
        if seconds <= keypoint.holdEndSeconds {
            return 1.0
        }
        let span = max(keypoint.endSeconds - keypoint.holdEndSeconds, 1e-6)
        let progress = (seconds - keypoint.holdEndSeconds) / span
        return Float(1.0) - easeInOutRamp(Float(progress))
    }

    private static func autoCropKeypointScale(protectedScale: Float) -> Float {
        max(Float(1.0), protectedScale.isFinite ? protectedScale : Float(1.0))
    }

    private static func autoCropTransformIsQuiet(
        _ transform: StabilizerAutoTransform,
        outputSize: vector_float2,
        masterStrength: Float
    ) -> Bool {
        let pixelTolerance = max(Float(1.0), min(outputSize.x, outputSize.y) * 0.002)
        let pixelActivity = simd_length(transform.pixelOffset * masterStrength)
        let rotationActivity = abs(transform.rotationDegrees * masterStrength)
        let shearActivity = simd_length(transform.shear * masterStrength)
        let perspectiveActivity = simd_length((transform.perspective + transform.yawPitchProxy) * masterStrength)
        return pixelActivity <= pixelTolerance
            && rotationActivity <= 0.05
            && shearActivity <= 0.001
            && perspectiveActivity <= 0.001
    }

    private static func autoCropIdleScaleReleaseProgress(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        protectedScale: Float
    ) -> Float {
        guard protectedScale <= Float(1.0) + stabilizerAutoCropIdleScaleTolerance,
              currentSeconds.isFinite,
              outputSize.x > 1.0,
              outputSize.y > 1.0,
              let firstTime = preparedAnalysis.frames.first?.time
        else {
            return 0.0
        }

        let maxReleaseSeconds = max(
            stabilizerAutoCropIdleReleaseEndSeconds,
            stabilizerAutoCropIdleSampleStepSeconds
        )
        let startSeconds = max(firstTime, currentSeconds - maxReleaseSeconds)
        var quietDuration = currentSeconds - startSeconds
        var previousSeconds = currentSeconds
        var previousTransform = currentTransform
        var sampleSeconds = currentSeconds - stabilizerAutoCropIdleSampleStepSeconds

        while sampleSeconds >= startSeconds - 1e-9 {
            let sampleTransform = autoCropActualSampleTransform(
                preparedAnalysis: preparedAnalysis,
                currentSeconds: previousSeconds,
                sampleSeconds: sampleSeconds,
                currentTransform: previousTransform,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
            if !autoCropTransformDeltaIsQuiet(
                previousTransform,
                sampleTransform,
                outputSize: outputSize,
                masterStrength: masterStrength
            ) {
                quietDuration = currentSeconds - previousSeconds
                break
            }
            previousSeconds = sampleSeconds
            previousTransform = sampleTransform
            sampleSeconds -= stabilizerAutoCropIdleSampleStepSeconds
        }

        let releaseSpan = max(
            stabilizerAutoCropIdleReleaseEndSeconds - stabilizerAutoCropIdleReleaseStartSeconds,
            0.0001
        )
        let releaseProgress = (quietDuration - stabilizerAutoCropIdleReleaseStartSeconds) / releaseSpan
        return easeInOutRamp(Float(releaseProgress))
    }

    private static func autoCropTransformDeltaIsQuiet(
        _ lhs: StabilizerAutoTransform,
        _ rhs: StabilizerAutoTransform,
        outputSize: vector_float2,
        masterStrength: Float
    ) -> Bool {
        let pixelTolerance = max(Float(2.0), min(outputSize.x, outputSize.y) * 0.0018)
        let pixelDelta = simd_length((lhs.pixelOffset - rhs.pixelOffset) * masterStrength)
        let macroDelta = simd_length((lhs.macroPixelOffset - rhs.macroPixelOffset) * masterStrength)
        let rotationDelta = abs(lhs.rotationDegrees - rhs.rotationDegrees) * masterStrength
        let shearDelta = simd_length((lhs.shear - rhs.shear) * masterStrength)
        let perspectiveDelta = simd_length(
            ((lhs.perspective + lhs.yawPitchProxy) - (rhs.perspective + rhs.yawPitchProxy)) * masterStrength
        )
        return max(pixelDelta, macroDelta) <= pixelTolerance
            && rotationDelta <= 0.035
            && shearDelta <= 0.0008
            && perspectiveDelta <= 0.0008
    }

    private static func autoCropLocalPositionPixels(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        initialPositionPixels: vector_float2
    ) -> vector_float2 {
        let samples = autoCropLocalPositionSamples(
            preparedAnalysis: preparedAnalysis,
            currentSeconds: currentSeconds,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile
        )
        guard !samples.isEmpty else {
            return initialPositionPixels
        }

        var weightedPosition = initialPositionPixels * 2.0
        var totalWeight = Float(2.0)
        for sample in samples {
            let sampleTransform = autoCropActualSampleTransform(
                preparedAnalysis: preparedAnalysis,
                currentSeconds: currentSeconds,
                sampleSeconds: sample.seconds,
                currentTransform: currentTransform,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                samplingProfile: samplingProfile,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
            let sampleContext = AutoCropTransformContext(
                transform: sampleTransform,
                outputSize: outputSize,
                masterStrength: masterStrength
            )
            let samplePosition = blackSafeAutoCropPosition(
                preferredPositionPixels: sampleTransform.macroPixelOffset * masterStrength,
                context: sampleContext,
                samplingProfile: samplingProfile
            )
            let weight = min(max(sample.influence, 0.0), 1.0)
            guard weight > 0.0001 else {
                continue
            }
            weightedPosition += samplePosition * weight
            totalWeight += weight
        }

        guard totalWeight > 0.0001 else {
            return initialPositionPixels
        }
        return weightedPosition / totalWeight
    }

    private static func autoCropLocalPositionSamples(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        transitionDurationSeconds: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        samplingProfile: AutoCropSamplingProfile
    ) -> [AutoCropLocalScaleSample] {
        let frames = preparedAnalysis.frames
        guard !frames.isEmpty,
              currentSeconds.isFinite,
              let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return []
        }

        let pastRadiusSeconds = min(
            max(0.5, max(0.0, holdTimeSeconds) + (max(0.0, transitionDurationSeconds) * 0.35)),
            2.5
        )
        let futureRadiusSeconds = 0.0
        let startSeconds = max(firstTime, currentSeconds - pastRadiusSeconds)
        let endSeconds = min(lastTime, currentSeconds + futureRadiusSeconds)
        guard startSeconds <= endSeconds else {
            return []
        }

        let spanSeconds = max(0.0, endSeconds - startSeconds)
        let stepSeconds = max(
            samplingProfile.positionEnvelopeStepSeconds,
            spanSeconds / Double(max(1, samplingProfile.positionEnvelopeSampleLimit))
        )
        var samples: [AutoCropLocalScaleSample] = []
        samples.reserveCapacity(min(samplingProfile.positionEnvelopeSampleLimit + 2, 320))

        func appendSample(seconds: Double) {
            guard seconds >= firstTime,
                  seconds <= lastTime,
                  abs(seconds - currentSeconds) > 1e-6
            else {
                return
            }
            let influence = autoCropLocalPositionInfluence(
                sampleSeconds: seconds,
                currentSeconds: currentSeconds,
                pastRadiusSeconds: pastRadiusSeconds,
                futureRadiusSeconds: futureRadiusSeconds
            )
            guard influence > 0.0001 else {
                return
            }
            if samples.contains(where: { abs($0.seconds - seconds) <= 1e-6 }) {
                return
            }
            samples.append(
                AutoCropLocalScaleSample(
                    seconds: seconds,
                    influence: influence
                )
            )
        }

        appendSample(seconds: startSeconds)
        appendSample(seconds: endSeconds)

        var sampleSeconds = currentSeconds - stepSeconds
        while sampleSeconds >= startSeconds - 1e-9 {
            appendSample(seconds: sampleSeconds)
            sampleSeconds -= stepSeconds
        }

        sampleSeconds = currentSeconds + stepSeconds
        while sampleSeconds <= endSeconds + 1e-9 {
            appendSample(seconds: sampleSeconds)
            sampleSeconds += stepSeconds
        }

        return samples
    }

    private static func autoCropLocalPositionInfluence(
        sampleSeconds: Double,
        currentSeconds: Double,
        pastRadiusSeconds: Double,
        futureRadiusSeconds: Double
    ) -> Float {
        guard sampleSeconds.isFinite,
              currentSeconds.isFinite
        else {
            return 0.0
        }

        let deltaSeconds = sampleSeconds - currentSeconds
        let radiusSeconds = deltaSeconds < 0.0 ? pastRadiusSeconds : futureRadiusSeconds
        guard radiusSeconds > 1e-6 else {
            return 0.0
        }
        let progress = 1.0 - (abs(deltaSeconds) / radiusSeconds)
        return easeInOutRamp(Float(progress))
    }

    private static func autoCropPlaybackQuantizedScale(_ scale: Float) -> Float {
        let safeScale = max(Float(1.0), scale.isFinite ? scale : Float(1.0))
        let step = max(Float(0.0001), stabilizerAutoCropPlaybackScaleQuantization)
        let delta = safeScale - Float(1.0)
        guard delta > 0.0 else {
            return Float(1.0)
        }
        return Float(1.0) + (Darwin.ceilf(delta / step) * step)
    }

    private static func autoCropSamplingProfile(forQualityLevel _: UInt32, renderSourceIsProxy _: Bool) -> AutoCropSamplingProfile {
        .playback
    }

    private static func autoCropPlaybackFraming(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        transitionDuration: Double,
        leadTime: Double,
        holdTime: Double,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?,
        preparationScope: UUID? = nil,
        onPrepared: (() -> Void)? = nil
    ) -> AutoCropFraming {
        guard masterStrength > 0.0001,
              renderSeconds.isFinite,
              outputSize.x > 1.0,
              outputSize.y > 1.0
        else {
            return .identity
        }

        let transitionDurationSeconds = autoCropTransitionDurationSeconds(transitionDuration)
        let leadTimeSeconds = autoCropLeadTimeSeconds(leadTime)
        let holdTimeSeconds = autoCropHoldTimeSeconds(holdTime)
        guard let playbackScalePlan = cachedAutoCropPlaybackScalePlanIfReadyOrSchedulePreparation(
            preparedAnalysis: preparedAnalysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            transitionDurationSeconds: transitionDurationSeconds,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            preparationScope: preparationScope,
            waitForPreparation: false,
            onPrepared: onPrepared
        ) else {
            os_log(
                "Auto Crop playback unavailable | reason scale-plan-unprepared render %.3f revision %llu cache %{public}@",
                log: stabilizerHostAnalysisLog,
                type: .error,
                renderSeconds,
                analysisRevision,
                cacheIdentity ?? "none"
            )
            if let fallbackDemand = autoCropZoomDemandSample(
                seconds: renderSeconds,
                transform: currentTransform,
                outputSize: outputSize,
                masterStrength: masterStrength,
                strengths: strengths,
                samplingProfile: samplingProfile,
                turnTransformAlreadyScaled: true
            ) {
                let protectedScale = autoCropPlaybackMinimumClippedScale(
                    autoCropPlaybackVisualScaleCap(fallbackDemand.scale)
                )
                return AutoCropFraming(
                    scale: autoCropKeypointScale(protectedScale: protectedScale),
                    positionPixels: fallbackDemand.positionPixels,
                    telemetry: .empty
                )
            }
            return .identity
        }
        let plannedFraming = autoCropPlaybackFramingPlanSample(
            playbackScalePlan,
            at: renderSeconds,
            fallback: currentTransform.macroPixelOffset * masterStrength,
            outputSize: outputSize
        )
        return AutoCropFraming(
            scale: plannedFraming.scale,
            positionPixels: plannedFraming.positionPixels,
            telemetry: .empty
        )
    }

    private static func autoCropSampleTime(_ seconds: Double, samplingProfile: AutoCropSamplingProfile) -> Double {
        let step = samplingProfile.quantizationStepSeconds
        guard step > 1e-9 else {
            return seconds
        }
        return (seconds / step).rounded() * step
    }

    private static func autoCropActualSampleTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        sampleSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> StabilizerAutoTransform {
        guard abs(sampleSeconds - currentSeconds) > 1e-6 else {
            return currentTransform
        }
        let sampleTime = CMTimeMakeWithSeconds(sampleSeconds, preferredTimescale: 60000)
        return cachedAutoTransform(
            preparedAnalysis: preparedAnalysis,
            renderTime: sampleTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity,
            playbackMode: samplingProfile == .playback
        )
    }

    private static func autoCropSampleTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        sampleSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        samplingProfile: AutoCropSamplingProfile
    ) -> StabilizerAutoTransform {
        guard abs(sampleSeconds - currentSeconds) > 1e-6 else {
            return currentTransform
        }
        guard samplingProfile.usesStabilizedSampleTransforms else {
            return autoCropPreparedDeltaTransform(
                preparedAnalysis: preparedAnalysis,
                currentSeconds: currentSeconds,
                sampleSeconds: sampleSeconds,
                currentTransform: currentTransform,
                outputSize: outputSize
            )
        }
        let sampleTime = CMTimeMakeWithSeconds(sampleSeconds, preferredTimescale: 60000)
        return AutoStabilizationEstimator.autoCropWindowEstimate(
            preparedAnalysis: preparedAnalysis,
            renderTime: sampleTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
    }

    private struct AutoCropPreparedPathSample {
        let pathX: Float
        let pathY: Float
        let pathRoll: Float
        let pathYaw: Float
        let pathPitch: Float
        let pathShearX: Float
        let pathShearY: Float
        let pathPerspectiveX: Float
        let pathPerspectiveY: Float
        let sampleWidth: Int
        let sampleHeight: Int
    }

    private static func autoCropPreparedDeltaTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        currentSeconds: Double,
        sampleSeconds: Double,
        currentTransform: StabilizerAutoTransform,
        outputSize: vector_float2
    ) -> StabilizerAutoTransform {
        guard let currentSample = autoCropPreparedPathSample(preparedAnalysis: preparedAnalysis, seconds: currentSeconds),
              let targetSample = autoCropPreparedPathSample(preparedAnalysis: preparedAnalysis, seconds: sampleSeconds)
        else {
            return currentTransform
        }

        let xScale = outputSize.x / Float(max(1, currentSample.sampleWidth))
        let yScale = outputSize.y / Float(max(1, currentSample.sampleHeight))
        let macroDelta = vector_float2(
            (targetSample.pathX - currentSample.pathX) * xScale,
            (targetSample.pathY - currentSample.pathY) * yScale
        )

        var transform = currentTransform
        transform.macroPixelOffset = currentTransform.macroPixelOffset - macroDelta
        transform.pixelOffset = transform.macroPixelOffset
            + transform.microPixelOffset
            + transform.macroJitterPixelOffset
            + transform.trajectoryMicroJitterPixelOffset
            + transform.trajectoryContinuityPixelOffset
        transform.rawPixelOffset = transform.pixelOffset
        let rollDelta = targetSample.pathRoll - currentSample.pathRoll
        transform.rotationDegrees = currentTransform.rotationDegrees - rollDelta
        transform.rawRotationDegrees = currentTransform.rawRotationDegrees - rollDelta
        transform.yawPitchProxy = currentTransform.yawPitchProxy - vector_float2(
            targetSample.pathYaw - currentSample.pathYaw,
            targetSample.pathPitch - currentSample.pathPitch
        )
        transform.shear = currentTransform.shear - vector_float2(
            targetSample.pathShearX - currentSample.pathShearX,
            targetSample.pathShearY - currentSample.pathShearY
        )
        transform.perspective = currentTransform.perspective - vector_float2(
            targetSample.pathPerspectiveX - currentSample.pathPerspectiveX,
            targetSample.pathPerspectiveY - currentSample.pathPerspectiveY
        )
        return transform
    }

    private static func autoCropPreparedPathSample(
        preparedAnalysis: StabilizerPreparedAnalysis,
        seconds: Double
    ) -> AutoCropPreparedPathSample? {
        let frames = preparedAnalysis.frames
        guard !frames.isEmpty else {
            return nil
        }
        if frames.count == 1 || seconds <= frames[0].time {
            return autoCropPreparedPathSample(preparedAnalysis: preparedAnalysis, lowerIndex: 0, upperIndex: 0, fraction: 0.0)
        }
        let lastIndex = frames.count - 1
        if seconds >= frames[lastIndex].time {
            return autoCropPreparedPathSample(preparedAnalysis: preparedAnalysis, lowerIndex: lastIndex, upperIndex: lastIndex, fraction: 0.0)
        }

        var low = 0
        var high = lastIndex
        while high - low > 1 {
            let mid = (low + high) / 2
            if frames[mid].time <= seconds {
                low = mid
            } else {
                high = mid
            }
        }

        let lowerTime = frames[low].time
        let upperTime = frames[high].time
        let duration = upperTime - lowerTime
        let fraction: Float
        if duration > 1e-9 {
            fraction = min(max(Float((seconds - lowerTime) / duration), 0.0), 1.0)
        } else {
            fraction = 0.0
        }
        return autoCropPreparedPathSample(
            preparedAnalysis: preparedAnalysis,
            lowerIndex: low,
            upperIndex: high,
            fraction: fraction
        )
    }

    private static func autoCropPreparedPathSample(
        preparedAnalysis: StabilizerPreparedAnalysis,
        lowerIndex: Int,
        upperIndex: Int,
        fraction: Float
    ) -> AutoCropPreparedPathSample? {
        guard preparedAnalysis.frames.indices.contains(lowerIndex) else {
            return nil
        }
        let lowerFrame = preparedAnalysis.frames[lowerIndex]
        let sampleWidth = lowerFrame.sampleWidth
        let sampleHeight = lowerFrame.sampleHeight
        return AutoCropPreparedPathSample(
            pathX: autoCropInterpolatedPreparedValue(preparedAnalysis.farFieldPathX, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathY: autoCropInterpolatedPreparedValue(preparedAnalysis.farFieldPathY, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathRoll: autoCropInterpolatedPreparedValue(preparedAnalysis.farFieldPathRoll, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathYaw: autoCropInterpolatedPreparedValue(preparedAnalysis.pathYaw, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathPitch: autoCropInterpolatedPreparedValue(preparedAnalysis.pathPitch, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathShearX: autoCropInterpolatedPreparedValue(preparedAnalysis.pathShearX, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathShearY: autoCropInterpolatedPreparedValue(preparedAnalysis.pathShearY, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathPerspectiveX: autoCropInterpolatedPreparedValue(preparedAnalysis.pathPerspectiveX, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathPerspectiveY: autoCropInterpolatedPreparedValue(preparedAnalysis.pathPerspectiveY, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
    }

    private static func autoCropInterpolatedPreparedValue(
        _ values: [Float],
        lowerIndex: Int,
        upperIndex: Int,
        fraction: Float
    ) -> Float {
        guard values.indices.contains(lowerIndex) else {
            return 0.0
        }
        let lowerValue = values[lowerIndex]
        guard values.indices.contains(upperIndex), upperIndex != lowerIndex else {
            return lowerValue
        }
        let upperValue = values[upperIndex]
        return lowerValue + ((upperValue - lowerValue) * fraction)
    }

    private static func autoCropStableScaleBudgetedPositionPixels(
        stablePositionPixels: vector_float2,
        clampPositionPixels: vector_float2,
        context: AutoCropTransformContext,
        scale: Float,
        samplingProfile: AutoCropSamplingProfile
    ) -> vector_float2 {
        if autoCropPosition(
            stablePositionPixels,
            fitsWithinScale: scale,
            context: context,
            samplingProfile: samplingProfile
        ) {
            return stablePositionPixels
        }

        guard autoCropPosition(
            clampPositionPixels,
            fitsWithinScale: scale,
            context: context,
            samplingProfile: samplingProfile
        ) else {
            return stablePositionPixels
        }

        var invalidFraction: Float = 0.0
        var validFraction: Float = 1.0
        for _ in 0..<samplingProfile.positionBudgetIterations {
            let midpoint = (invalidFraction + validFraction) * 0.5
            let candidate = stablePositionPixels + ((clampPositionPixels - stablePositionPixels) * midpoint)
            if autoCropPosition(
                candidate,
                fitsWithinScale: scale,
                context: context,
                samplingProfile: samplingProfile
            ) {
                validFraction = midpoint
            } else {
                invalidFraction = midpoint
            }
        }
        return stablePositionPixels + ((clampPositionPixels - stablePositionPixels) * validFraction)
    }

    private static func autoCropPosition(
        _ positionPixels: vector_float2,
        fitsWithinScale maximumScale: Float,
        context: AutoCropTransformContext,
        samplingProfile: AutoCropSamplingProfile
    ) -> Bool {
        guard autoCropCenterIsInsideSource(
            cropPositionPixels: positionPixels,
            context: context
        ) else {
            return false
        }
        return autoCropScaleContainsSource(
            scale: max(maximumScale, 1.0),
            context: context,
            cropPositionPixels: positionPixels,
            sampleSteps: samplingProfile.scaleSearchSampleSteps
        )
    }

    private static func blackSafeAutoCropPosition(
        preferredPositionPixels: vector_float2,
        context: AutoCropTransformContext,
        samplingProfile: AutoCropSamplingProfile = .full
    ) -> vector_float2 {
        if autoCropCenterIsInsideSource(
            cropPositionPixels: preferredPositionPixels,
            context: context
        ) {
            return preferredPositionPixels
        }

        let currentPositionPixels = context.pixelOffset
        guard autoCropCenterIsInsideSource(
            cropPositionPixels: currentPositionPixels,
            context: context
        ) else {
            return currentPositionPixels
        }

        var invalidFraction: Float = 0.0
        var validFraction: Float = 1.0
        for _ in 0..<samplingProfile.positionClampIterations {
            let midpoint = (invalidFraction + validFraction) * 0.5
            let candidate = (preferredPositionPixels * (1.0 - midpoint)) + (currentPositionPixels * midpoint)
            if autoCropCenterIsInsideSource(
                cropPositionPixels: candidate,
                context: context
            ) {
                validFraction = midpoint
            } else {
                invalidFraction = midpoint
            }
        }
        return (preferredPositionPixels * (1.0 - validFraction)) + (currentPositionPixels * validFraction)
    }

    private static func autoCropCenterIsInsideSource(
        cropPositionPixels: vector_float2,
        context: AutoCropTransformContext
    ) -> Bool {
        let sourcePixel = context.sourcePixel(
            outputPixel: vector_float2(0.0, 0.0),
            scale: 1.0,
            cropPositionPixels: cropPositionPixels
        )
        return context.containsSourcePixel(sourcePixel)
    }

    private static func requiredAutoCropScale(
        context: AutoCropTransformContext,
        cropPositionPixels: vector_float2,
        sampleSteps: Int = 6,
        iterations: Int = 18
    ) -> Float {
        let clampedSampleSteps = max(2, sampleSteps)
        let estimatedScale = directAutoCropScaleEstimate(
            context: context,
            cropPositionPixels: cropPositionPixels,
            sampleSteps: clampedSampleSteps
        )
        guard estimatedScale.isFinite else {
            return 128.0
        }

        var scale = min(max(estimatedScale, Float(1.0)), Float(128.0))
        let refinementIterations = max(1, iterations)
        for _ in 0..<min(4, refinementIterations) {
            if autoCropScaleContainsSource(
                scale: scale,
                context: context,
                cropPositionPixels: cropPositionPixels,
                sampleSteps: clampedSampleSteps
            ) {
                return scale
            }
            scale = min(128.0, (scale * 1.015) + 0.002)
        }

        for _ in 0..<max(0, refinementIterations - min(4, refinementIterations)) {
            guard scale < 128.0,
                  !autoCropScaleContainsSource(
                      scale: scale,
                      context: context,
                      cropPositionPixels: cropPositionPixels,
                      sampleSteps: clampedSampleSteps
                  ) else {
                return scale
            }
            scale = min(128.0, scale * 1.08)
        }
        return scale
    }

    private static func directAutoCropScaleEstimate(
        context: AutoCropTransformContext,
        cropPositionPixels: vector_float2,
        sampleSteps: Int
    ) -> Float {
        let sourceCenter = context.sourcePixel(
            outputPixel: vector_float2(0.0, 0.0),
            scale: 1.0,
            cropPositionPixels: cropPositionPixels
        )
        guard context.containsSourcePixel(sourceCenter) else {
            return 128.0
        }

        let availableX = (context.halfSize.x - context.marginPixels) - abs(sourceCenter.x)
        let availableY = (context.halfSize.y - context.marginPixels) - abs(sourceCenter.y)
        guard availableX > 0.0001, availableY > 0.0001 else {
            return 128.0
        }

        var requiredScale: Float = 1.0
        for yIndex in 0...sampleSteps {
            for xIndex in 0...sampleSteps {
                let xFraction = (Float(xIndex) / Float(sampleSteps)) - 0.5
                let yFraction = (Float(yIndex) / Float(sampleSteps)) - 0.5
                let outputPixel = vector_float2(
                    xFraction * context.outputSize.x,
                    yFraction * context.outputSize.y
                )
                let sourcePixel = context.sourcePixel(
                    outputPixel: outputPixel,
                    scale: 1.0,
                    cropPositionPixels: cropPositionPixels
                )
                let delta = sourcePixel - sourceCenter
                requiredScale = max(
                    requiredScale,
                    abs(delta.x) / availableX,
                    abs(delta.y) / availableY
                )
            }
        }
        return min(max(requiredScale, Float(1.0)), Float(128.0))
    }

    private static func autoCropBoundaryScaleContainsSource(
        scale: Float,
        context: AutoCropTransformContext,
        cropPositionPixels: vector_float2,
        sampleSteps: Int
    ) -> Bool {
        for yIndex in 0...sampleSteps {
            for xIndex in 0...sampleSteps where xIndex == 0 || xIndex == sampleSteps || yIndex == 0 || yIndex == sampleSteps {
                let xFraction = (Float(xIndex) / Float(sampleSteps)) - 0.5
                let yFraction = (Float(yIndex) / Float(sampleSteps)) - 0.5
                let outputPixel = vector_float2(
                    xFraction * context.outputSize.x,
                    yFraction * context.outputSize.y
                )
                let sourcePixel = context.sourcePixel(
                    outputPixel: outputPixel,
                    scale: scale,
                    cropPositionPixels: cropPositionPixels
                )
                if !context.containsSourcePixel(sourcePixel) {
                    return false
                }
            }
        }
        return true
    }

    private static func autoCropScaleContainsSource(
        scale: Float,
        context: AutoCropTransformContext,
        cropPositionPixels: vector_float2,
        sampleSteps: Int
    ) -> Bool {
        for yIndex in 0...sampleSteps {
            for xIndex in 0...sampleSteps {
                let xFraction = (Float(xIndex) / Float(sampleSteps)) - 0.5
                let yFraction = (Float(yIndex) / Float(sampleSteps)) - 0.5
                let outputPixel = vector_float2(
                    xFraction * context.outputSize.x,
                    yFraction * context.outputSize.y
                )
                let sourcePixel = context.sourcePixel(
                    outputPixel: outputPixel,
                    scale: scale,
                    cropPositionPixels: cropPositionPixels
                )
                if !context.containsSourcePixel(sourcePixel) {
                    return false
                }
            }
        }
        return true
    }

    private func publishHostAnalysisStatus(force: Bool = false, statusOverride: String? = nil) {
        let status = Self.hostAnalysisStatusText(statusOverride ?? hostAnalysisStore.statusText)
        statusLock.lock()
        let shouldPublish = force || status != lastPublishedStatus
        statusLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if settingAPI.setStringParameterValue(status, toParameter: ParameterID.hostAnalysisStatus.rawValue) {
            statusLock.lock()
            lastPublishedStatus = status
            statusLock.unlock()
        } else {
            NSLog("TokyoWalkingStabilizer: failed to update Host Analysis Status parameter.")
        }
    }

    private func publishStabilizerInfo(
        force: Bool = false,
        inspectorSnapshotOverride: StabilizerHostAnalysisInspectorSnapshot? = nil
    ) {
        let inspectorSnapshot = inspectorSnapshotOverride ?? hostAnalysisStore.inspectorSnapshot
        let info = Self.stabilizerInfoFields(inspectorSnapshot: inspectorSnapshot)
        statusLock.lock()
        let shouldPublish = force
            || info.sample != lastPublishedSampleInfo
            || info.queue != lastPublishedQueueInfo
        statusLock.unlock()
        guard shouldPublish else {
            return
        }
        guard let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        let didSetSample = settingAPI.setStringParameterValue(info.sample, toParameter: ParameterID.sampleInfo.rawValue)
        let didSetQueue = settingAPI.setStringParameterValue(info.queue, toParameter: ParameterID.queueInfo.rawValue)
        if didSetSample && didSetQueue {
            statusLock.lock()
            lastPublishedSampleInfo = info.sample
            lastPublishedQueueInfo = info.queue
            statusLock.unlock()
        } else {
            NSLog("TokyoWalkingStabilizer: failed to update one or more Stabilizer Info parameters.")
        }
    }

    private static func stabilizerInfoFields(inspectorSnapshot: StabilizerHostAnalysisInspectorSnapshot) -> StabilizerInfoFields {
        let analysisInfo = inspectorSnapshot.analysisInfoText
        let acceptedSample = inspectorSnapshot.requestedSampleScalePercent.map(samplePercentDescription)
            ?? "unknown"
        let sampleSize: String
        if let sampleWidth = inspectorSnapshot.sampleWidth,
           let sampleHeight = inspectorSnapshot.sampleHeight {
            sampleSize = AutoStabilizationEstimator.sampleSizeDescription(width: sampleWidth, height: sampleHeight)
        } else {
            sampleSize = "-"
        }
        let frameCount = inspectorSnapshot.frameCount.map { "\($0)f" } ?? "-"
        return StabilizerInfoFields(
            sample: "Sample: \(acceptedSample) -> \(sampleSize) | Analysis: \(frameCount)",
            queue: queueDescription(from: analysisInfo)
        )
    }

    private static func samplePercentDescription(_ percent: Double) -> String {
        if percent.rounded() == percent {
            return String(format: "%.0f%%", percent)
        }
        return String(format: "%.2f%%", percent)
    }

    private static func queueDescription(from analysisInfo: String) -> String {
        if analysisInfo.hasPrefix("Queued #") {
            let pieces = analysisInfo.split(separator: ":", maxSplits: 1).map(String.init)
            let head = pieces.first ?? analysisInfo
            let queueToken = head.split(separator: " ").first { $0.hasPrefix("#") }.map(String.init) ?? "#?"
            let reason = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespaces) : ""
            let order: String
            if queueToken.contains("/") {
                let parts = queueToken.dropFirst().split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    order = "#\(parts[0]) of \(parts[1])"
                } else {
                    order = queueToken
                }
            } else {
                order = queueToken
            }
            return reason.isEmpty ? "Queue: \(order)" : "Queue: \(order) \(reason)"
        }
        if analysisInfo.hasPrefix("Requested ") {
            return "Queue: Starting"
        }
        if analysisInfo.hasPrefix("Analyzing") {
            return "Queue: Active"
        }
        return "Queue: -"
    }

    private func publishRenderRevision(_ revision: Double, currentParameterValue: Double? = nil, force: Bool = false) {
        let publishedRevision = Self.runtimeRenderRevisionToken(revision)
        guard publishedRevision > 0.0 else {
            return
        }
        let parameterNeedsUpdate = currentParameterValue.map { abs($0 - publishedRevision) >= 0.5 } ?? false
        if currentParameterValue != nil,
           !parameterNeedsUpdate {
            statusLock.lock()
            lastPublishedRenderRevision = publishedRevision
            statusLock.unlock()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        statusLock.lock()
        let recentlyAttempted = lastRenderRevisionPublishAttemptRevision == publishedRevision
            && (now - lastRenderRevisionPublishAttemptWallTime) < stabilizerRenderRevisionRetryIntervalSeconds
        let shouldPublish = force || ((parameterNeedsUpdate || lastPublishedRenderRevision != publishedRevision) && !recentlyAttempted)
        if shouldPublish {
            lastRenderRevisionPublishAttemptRevision = publishedRevision
            lastRenderRevisionPublishAttemptWallTime = now
        }
        statusLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if settingAPI.setFloatValue(publishedRevision, toParameter: ParameterID.renderRevision.rawValue, at: .zero) {
            statusLock.lock()
            lastPublishedRenderRevision = publishedRevision
            statusLock.unlock()
        } else {
            NSLog("TokyoWalkingStabilizer: failed to update Render Revision parameter.")
        }
    }

    private func shouldRetryRenderRevisionPublish(_ revision: Double) -> Bool {
        let publishedRevision = Self.runtimeRenderRevisionToken(revision)
        guard publishedRevision > 0.0 else {
            return false
        }
        let now = Date().timeIntervalSinceReferenceDate
        statusLock.lock()
        defer { statusLock.unlock() }
        if lastRenderRevisionPublishAttemptRevision == publishedRevision,
           (now - lastRenderRevisionPublishAttemptWallTime) < stabilizerRenderRevisionRetryIntervalSeconds {
            return false
        }
        lastRenderRevisionPublishAttemptRevision = publishedRevision
        lastRenderRevisionPublishAttemptWallTime = now
        return true
    }

    private static func runtimeRenderRevisionToken(_ revision: Double) -> Double {
        guard revision > 0.0,
              revision.isFinite
        else {
            return 0.0
        }
        return tokyoWalkingStabilizerRenderRevisionSeed + revision
    }

    @discardableResult
    private func publishRenderAnalysisDecisionIfChanged(_ signature: RenderAnalysisDecisionSignature) -> Bool {
        let decision = "Render Host Analysis decision | FxPlug \(signature.fxPlugVersion) | transform \(signature.transformEnabled ? "on" : "off") | completed \(signature.hasCompletedHostAnalysis ? "yes" : "no") | project cache \(signature.configuredProjectBundleCache ? "configured" : "not configured") | prepared \(signature.renderUsesPreparedAnalysis ? "yes" : "no") | stabilization \(signature.stabilizationActive ? "active" : "inactive") | debug overlay \(signature.debugOverlayActive ? "active" : "inactive") | mesh overlay \(signature.meshOverlayMode) | proxy \(signature.renderSourceIsProxy ? "yes" : "no") | source \(signature.renderSourceFrameInfo) | identity \(signature.renderCacheIdentityShort) | auto crop \(signature.autoCropEnabled ? "on" : "off") profile \(signature.autoCropProfileName) | frames \(signature.hostAnalysisFrameCount)"
        let now = Date.timeIntervalSinceReferenceDate
        statusLock.lock()
        let shouldPublish = lastRenderAnalysisDecisionSignature != signature
        if shouldPublish {
            lastRenderAnalysisDecisionSignature = signature
        }
        let shouldLog = shouldPublish
            || lastRenderAnalysisDecision != decision
            || (now - lastRenderAnalysisDecisionLogWallTime) >= 1.0
        if shouldLog {
            lastRenderAnalysisDecision = decision
            lastRenderAnalysisDecisionLogWallTime = now
        }
        statusLock.unlock()

        if shouldLog {
            os_log("%{public}@", log: stabilizerHostAnalysisLog, type: .default, decision)
            NSLog("TokyoWalkingStabilizer: \(decision)")
        }
        return shouldPublish
    }

    private func logRenderEarlyExitIfChanged(_ reason: String) {
        statusLock.lock()
        let shouldLog = lastRenderEarlyExitReason != reason
        if shouldLog {
            lastRenderEarlyExitReason = reason
        }
        statusLock.unlock()
        guard shouldLog else {
            return
        }
        os_log(
            "Render early exit | FxPlug %{public}@ | %{public}@",
            log: stabilizerHostAnalysisLog,
            type: .error,
            tokyoWalkingStabilizerVersion,
            reason
        )
    }

    private func logRenderTimingIfNeeded(
        totalMs: Double,
        setupMs: Double,
        analysisMs: Double,
        transformMs: Double,
        cropMs: Double,
        encodeMs: Double,
        gpuWaitMs: Double,
        renderUsesPreparedAnalysis: Bool,
        renderSourceIsProxy: Bool,
        autoCropEnabled: Bool,
        cacheIdentityShort: String,
        outputWidth: Int32,
        outputHeight: Int32
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        renderTimingLogLock.lock()
        let shouldLog = totalMs >= 100.0 || (now - lastRenderTimingLogWallTime) >= 0.5
        if shouldLog {
            lastRenderTimingLogWallTime = now
        }
        renderTimingLogLock.unlock()
        guard shouldLog else {
            return
        }
        os_log(
            "Render timing | FxPlug %{public}@ | total %.3fms setup %.3fms analysis %.3fms transform %.3fms crop %.3fms encode %.3fms gpuWait %.3fms | prepared %{public}@ proxy %{public}@ crop %{public}@ identity %{public}@ output %dx%d",
            log: stabilizerHostAnalysisLog,
            type: totalMs >= 33.0 ? .error : .default,
            tokyoWalkingStabilizerVersion,
            totalMs,
            setupMs,
            analysisMs,
            transformMs,
            cropMs,
            encodeMs,
            gpuWaitMs,
            renderUsesPreparedAnalysis ? "yes" : "no",
            renderSourceIsProxy ? "yes" : "no",
            autoCropEnabled ? "yes" : "no",
            cacheIdentityShort,
            outputWidth,
            outputHeight
        )
    }

    private func renderPreviewWarmupDecision(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        renderSourceIsProxy: Bool,
        autoCropEnabled: Bool,
        cacheIdentityShort: String
    ) -> RenderPreviewWarmupDecision {
        let analysisSeconds = CMTimeGetSeconds(renderTime)
        let frames = preparedAnalysis.frames
        guard analysisSeconds.isFinite,
              !frames.isEmpty
        else {
            return .inactive
        }

        let lastIndex = frames.count - 1
        let lowerIndex: Int
        let lowerTime: Double
        let upperTime: Double
        let fraction: Double
        if frames.count == 1 || analysisSeconds <= frames[0].time {
            lowerIndex = 0
            lowerTime = frames[0].time
            upperTime = frames[0].time
            fraction = 0.0
        } else if analysisSeconds >= frames[lastIndex].time {
            lowerIndex = lastIndex
            lowerTime = frames[lastIndex].time
            upperTime = frames[lastIndex].time
            fraction = 0.0
        } else {
            var low = 0
            var high = lastIndex
            while low + 1 < high {
                let middle = (low + high) / 2
                if frames[middle].time <= analysisSeconds {
                    low = middle
                } else {
                    high = middle
                }
            }
            lowerIndex = low
            lowerTime = frames[low].time
            upperTime = frames[high].time
            let duration = upperTime - lowerTime
            fraction = duration.isFinite && duration > Double.ulpOfOne
                ? min(1.0, max(0.0, (analysisSeconds - lowerTime) / duration))
                : 0.0
        }

        let fallbackFrameSeconds: Double
        if frames.count > 1 {
            fallbackFrameSeconds = frames[1].time - frames[0].time
        } else {
            fallbackFrameSeconds = 1.0 / 60.0
        }
        let expectedFrameSeconds = max(
            1.0 / 240.0,
            upperTime > lowerTime
                ? upperTime - lowerTime
                : fallbackFrameSeconds
        )
        let samplePosition = Double(lowerIndex) + fraction
        let now = CFAbsoluteTimeGetCurrent()

        let previous: RenderPreviewWarmupState?
        renderDiagnosticsLogLock.lock()
        previous = lastPreviewWarmupState
        renderDiagnosticsLogLock.unlock()

        let sameIdentity = previous?.cacheIdentityShort == cacheIdentityShort
        let deltaSeconds = sameIdentity ? analysisSeconds - (previous?.analysisSeconds ?? analysisSeconds) : 0.0
        let sampleDelta = sameIdentity ? samplePosition - (previous?.samplePosition ?? samplePosition) : 0.0
        let previousActive = previous.map { $0.active && now < $0.warmupUntil } ?? false
        let normalSequentialFrame = sameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds > expectedFrameSeconds * 0.45
            && deltaSeconds < expectedFrameSeconds * 1.85
            && sampleDelta.isFinite
            && sampleDelta > 0.45
            && sampleDelta < 1.55
        let renderTimeGap = sameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds > expectedFrameSeconds * 1.85
        let renderTimeRewind = sameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds < -expectedFrameSeconds * 0.10
        let preparedSampleGap = sameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds > expectedFrameSeconds * 0.45
            && deltaSeconds < expectedFrameSeconds * 1.85
            && sampleDelta.isFinite
            && sampleDelta > 1.55
        let reconnectNoiseWhileWarming = previousActive
            && (renderTimeGap || renderTimeRewind || preparedSampleGap)
        let triggerReason: String?
        if previous == nil {
            triggerReason = "startup"
        } else if !sameIdentity {
            triggerReason = "analysis-change"
        } else if reconnectNoiseWhileWarming && renderTimeRewind {
            triggerReason = "render-time-rewind"
        } else if reconnectNoiseWhileWarming && renderTimeGap {
            triggerReason = "render-time-gap"
        } else if reconnectNoiseWhileWarming && preparedSampleGap {
            triggerReason = "prepared-sample-gap"
        } else {
            triggerReason = nil
        }

        let stableSequentialFrameCount: Int
        if normalSequentialFrame {
            stableSequentialFrameCount = min(
                (previous?.stableSequentialFrameCount ?? 0) + 1,
                Self.previewWarmupStableSequentialFrameCount
            )
        } else if triggerReason != nil {
            stableSequentialFrameCount = 0
        } else {
            stableSequentialFrameCount = previous?.stableSequentialFrameCount ?? 0
        }

        var warmupUntil = previous?.warmupUntil ?? 0.0
        if triggerReason != nil {
            warmupUntil = max(warmupUntil, now + Self.previewWarmupHoldSeconds)
        }
        if stableSequentialFrameCount >= Self.previewWarmupStableSequentialFrameCount {
            warmupUntil = min(warmupUntil, now)
        }
        let active = now < warmupUntil
        let reason: String
        if let triggerReason {
            reason = triggerReason
        } else if active {
            reason = stableSequentialFrameCount > 0 ? "stabilizing-cadence" : "waiting-cadence"
        } else {
            reason = "ready"
        }
        let shouldForceReadyStatus = previousActive && !active
        let remainingSeconds = max(0.0, warmupUntil - now)
        let shouldLog: Bool

        renderDiagnosticsLogLock.lock()
        shouldLog = active
            && (triggerReason != nil || (now - lastPreviewWarmupLogWallTime) >= Self.previewWarmupLogIntervalSeconds)
        if shouldLog {
            lastPreviewWarmupLogWallTime = now
        }
        lastPreviewWarmupState = RenderPreviewWarmupState(
            cacheIdentityShort: cacheIdentityShort,
            analysisSeconds: analysisSeconds,
            samplePosition: samplePosition,
            warmupUntil: warmupUntil,
            stableSequentialFrameCount: stableSequentialFrameCount,
            active: active
        )
        renderDiagnosticsLogLock.unlock()

        if shouldLog {
            os_log(
                "Preview warming | FxPlug %{public}@ | reason %{public}@ | render %.3f dt %.5f expected %.5f sample %.3f dSample %.3f stable %d remaining %.3f | proxy %{public}@ crop %{public}@ identity %{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                tokyoWalkingStabilizerVersion,
                reason,
                analysisSeconds,
                deltaSeconds,
                expectedFrameSeconds,
                samplePosition,
                sampleDelta,
                stableSequentialFrameCount,
                remainingSeconds,
                renderSourceIsProxy ? "yes" : "no",
                autoCropEnabled ? "yes" : "no",
                cacheIdentityShort
            )
            publishHostAnalysisStatus(force: true, statusOverride: "Preview Warming - \(reason)")
        } else if shouldForceReadyStatus {
            publishHostAnalysisStatus(force: true)
        }
        if active {
            schedulePreviewWarmupExpiryInvalidation(
                warmupUntil: warmupUntil,
                cacheIdentityShort: cacheIdentityShort,
                reason: reason
            )
        }

        return RenderPreviewWarmupDecision(
            active: active,
            reason: reason,
            analysisSeconds: analysisSeconds,
            expectedFrameSeconds: expectedFrameSeconds,
            deltaSeconds: deltaSeconds,
            samplePosition: samplePosition,
            sampleDelta: sampleDelta,
            stableSequentialFrameCount: stableSequentialFrameCount,
            remainingSeconds: remainingSeconds
        )
    }

    private func schedulePreviewWarmupExpiryInvalidation(
        warmupUntil: TimeInterval,
        cacheIdentityShort: String,
        reason: String
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let delay = max(0.05, warmupUntil - now + 0.03)
        renderDiagnosticsLogLock.lock()
        let shouldSchedule = lastScheduledPreviewWarmupExpiryIdentity != cacheIdentityShort
            || abs(lastScheduledPreviewWarmupExpiry - warmupUntil) >= 0.05
        if shouldSchedule {
            lastScheduledPreviewWarmupExpiry = warmupUntil
            lastScheduledPreviewWarmupExpiryIdentity = cacheIdentityShort
        }
        renderDiagnosticsLogLock.unlock()
        guard shouldSchedule else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            let now = CFAbsoluteTimeGetCurrent()
            let state: RenderPreviewWarmupState?
            let shouldInvalidate: Bool
            self.renderDiagnosticsLogLock.lock()
            state = self.lastPreviewWarmupState
            if let state,
               state.cacheIdentityShort == cacheIdentityShort,
               state.active,
               now >= state.warmupUntil - 0.02 {
                shouldInvalidate = true
                self.lastPreviewWarmupState = RenderPreviewWarmupState(
                    cacheIdentityShort: state.cacheIdentityShort,
                    analysisSeconds: state.analysisSeconds,
                    samplePosition: state.samplePosition,
                    warmupUntil: now,
                    stableSequentialFrameCount: state.stableSequentialFrameCount,
                    active: false
                )
            } else {
                shouldInvalidate = false
            }
            self.renderDiagnosticsLogLock.unlock()
            guard shouldInvalidate else {
                return
            }
            let revision = self.hostAnalysisStore.notePreviewWarmupExpiredForRender(
                reason: "identity \(cacheIdentityShort) previous \(reason)"
            )
            self.publishHostAnalysisStatus(force: true)
            self.publishRenderRevision(revision, force: true)
        }
    }

    private static func lensShakeAxisDescription(_ mask: Int32) -> String {
        guard mask != 0 else {
            return "none"
        }
        var parts: [String] = []
        if (mask & 1) != 0 { parts.append("x") }
        if (mask & 2) != 0 { parts.append("y") }
        if (mask & 4) != 0 { parts.append("roll") }
        if (mask & 8) != 0 { parts.append("yaw") }
        if (mask & 16) != 0 { parts.append("pitch") }
        if (mask & 32) != 0 { parts.append("shear") }
        if (mask & 64) != 0 { parts.append("perspective") }
        return parts.joined(separator: ",")
    }

    private static func renderCSVValue<T: BinaryFloatingPoint>(_ value: T, digits: Int = 5) -> String {
        let doubleValue = Double(value)
        guard doubleValue.isFinite else {
            return "nan"
        }
        return String(format: "%.\(digits)f", doubleValue)
    }

    private static func lensShakeReasonDescription(_ code: Int32) -> String {
        switch code {
        case 1:
            return "applied"
        case 2:
            return "lowConfidence"
        case 3:
            return "belowSupport"
        case 4:
            return "noPreparedSignal"
        case 5:
            return "rollingShutterCandidate"
        case 6:
            return "rollingRowWarp"
        case 7:
            return "farFieldRigid"
        case 8:
            return "farFieldRigidSuppressed"
        case 9:
            return "dominantWindowRequired"
        case 10:
            return "rollingGlobalPixel"
        default:
            return "off"
        }
    }

    private static func lensBandCorrectionModelDescription(_ mask: Int32) -> String {
        guard mask != 0 else {
            return "none"
        }
        var parts: [String] = []
        if (mask & 1) != 0 { parts.append("rowPhase") }
        if (mask & 2) != 0 { parts.append("columnPhase") }
        if (mask & 4) != 0 { parts.append("regionCluster") }
        if (mask & 8) != 0 { parts.append("localRoll") }
        if (mask & 16) != 0 { parts.append("sourceRidge") }
        if (mask & 32) != 0 { parts.append("sourceLocal") }
        if (mask & 64) != 0 { parts.append("sourceRidgeLine") }
        if (mask & 128) != 0 { parts.append("farFieldRigid") }
        if (mask & 256) != 0 { parts.append("farFieldMesh") }
        if (mask & 512) != 0 { parts.append("shortRigidYBoost") }
        if (mask & 1024) != 0 { parts.append("dominantMeshYBlend") }
        if (mask & 2048) != 0 { parts.append("parallaxDamped") }
        if (mask & 4096) != 0 { parts.append("coherentSlabYLimited") }
        if (mask & 8192) != 0 { parts.append("coherentSlabXLimited") }
        if (mask & 16384) != 0 { parts.append("coherentMeshLimited") }
        if (mask & 32768) != 0 { parts.append("sourceRidgeSuppressed") }
        if (mask & 65536) != 0 { parts.append("rollingGlobalPixel") }
        if (mask & 131072) != 0 { parts.append("rollingMeshX") }
        if (mask & 262144) != 0 { parts.append("sourceLocalGlobal") }
        if (mask & 524288) != 0 { parts.append("sourceRidgeGlobalOnly") }
        if (mask & 1048576) != 0 { parts.append("globalY") }
        if (mask & 2097152) != 0 { parts.append("globalRoll") }
        if (mask & 4194304) != 0 { parts.append("deltaRigid") }
        return parts.joined(separator: ",")
    }

    private func logRenderMotionCadenceIfNeeded(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        autoTransform: StabilizerAutoTransform,
        autoCropFraming: AutoCropFraming,
        renderSourceIsProxy: Bool,
        autoCropEnabled: Bool,
        debugOverlayActive: Bool,
        masterStrength: Float,
        cacheIdentityShort: String,
        previewWarmupDecision: RenderPreviewWarmupDecision
    ) {
        let analysisSeconds = CMTimeGetSeconds(renderTime)
        let frames = preparedAnalysis.frames
        guard analysisSeconds.isFinite,
              !frames.isEmpty
        else {
            return
        }
        let trajectoryDiagnostic = AutoStabilizationEstimator.playbackTrajectorySampleDiagnostic(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )

        let lastIndex = frames.count - 1
        let lowerIndex: Int
        let upperIndex: Int
        let lowerTime: Double
        let upperTime: Double
        let fraction: Float
        let lowerFingerprint: String
        let upperFingerprint: String
        let pathPixelOffset: vector_float2
        if let trajectoryDiagnostic {
            lowerIndex = trajectoryDiagnostic.lowerIndex
            upperIndex = trajectoryDiagnostic.upperIndex
            lowerTime = trajectoryDiagnostic.lowerTime
            upperTime = trajectoryDiagnostic.upperTime
            fraction = trajectoryDiagnostic.fraction
            lowerFingerprint = trajectoryDiagnostic.lowerFingerprint
            upperFingerprint = trajectoryDiagnostic.upperFingerprint
            pathPixelOffset = trajectoryDiagnostic.transform.pixelOffset
        } else if frames.count == 1 || analysisSeconds <= frames[0].time {
            lowerIndex = 0
            upperIndex = 0
            lowerTime = frames[0].time
            upperTime = frames[0].time
            fraction = 0.0
            lowerFingerprint = frames[0].fingerprint
            upperFingerprint = frames[0].fingerprint
            pathPixelOffset = autoTransform.pixelOffset
        } else if analysisSeconds >= frames[lastIndex].time {
            lowerIndex = lastIndex
            upperIndex = lastIndex
            lowerTime = frames[lastIndex].time
            upperTime = frames[lastIndex].time
            fraction = 0.0
            lowerFingerprint = frames[lastIndex].fingerprint
            upperFingerprint = frames[lastIndex].fingerprint
            pathPixelOffset = autoTransform.pixelOffset
        } else {
            var low = 0
            var high = lastIndex
            while low + 1 < high {
                let middle = (low + high) / 2
                if frames[middle].time <= analysisSeconds {
                    low = middle
                } else {
                    high = middle
                }
            }
            lowerIndex = low
            upperIndex = high
            lowerTime = frames[low].time
            upperTime = frames[high].time
            let duration = upperTime - lowerTime
            fraction = duration.isFinite && duration > Double.ulpOfOne
                ? Float(min(1.0, max(0.0, (analysisSeconds - lowerTime) / duration)))
                : 0.0
            lowerFingerprint = frames[low].fingerprint
            upperFingerprint = frames[high].fingerprint
            pathPixelOffset = autoTransform.pixelOffset
        }

        let now = CFAbsoluteTimeGetCurrent()
        let previous: RenderMotionDiagnosticState?
        renderDiagnosticsLogLock.lock()
        previous = lastRenderMotionDiagnosticState
        renderDiagnosticsLogLock.unlock()

        let fallbackFrameSeconds: Double
        if preparedAnalysis.frames.count > 1 {
            fallbackFrameSeconds = preparedAnalysis.frames[1].time - preparedAnalysis.frames[0].time
        } else {
            fallbackFrameSeconds = 1.0 / 60.0
        }
        let expectedFrameSeconds = max(
            1.0 / 240.0,
            upperTime > lowerTime
                ? upperTime - lowerTime
                : fallbackFrameSeconds
        )
        let deltaSeconds = previous.map { analysisSeconds - $0.analysisSeconds } ?? 0.0
        let sameIdentity = previous?.cacheIdentityShort == cacheIdentityShort
        let normalCadence = sameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds > expectedFrameSeconds * 0.45
            && deltaSeconds < expectedFrameSeconds * 1.85
        let previousPixelOffset = previous?.pixelOffset ?? autoTransform.pixelOffset
        let previousCropPosition = previous?.cropPositionPixels ?? autoCropFraming.positionPixels
        let transformDelta = autoTransform.pixelOffset - previousPixelOffset
        let cropPositionDelta = autoCropFraming.positionPixels - previousCropPosition
        let samplePosition = Double(lowerIndex) + Double(fraction)
        let sampleDelta = previous.map { samplePosition - $0.samplePosition } ?? 0.0
        let transformStep = simd_length(transformDelta)
        let cropPositionStep = simd_length(cropPositionDelta)
        let cropScaleDeltaPercent = previous.map { abs(autoCropFraming.scale - $0.cropScale) * 100.0 } ?? 0.0
        let hasPreviousSameIdentity = sameIdentity && previous != nil
        let renderTimeGap = hasPreviousSameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds > expectedFrameSeconds * 1.85
        let renderTimeRepeat = hasPreviousSameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds >= -expectedFrameSeconds * 0.10
            && deltaSeconds <= expectedFrameSeconds * 0.45
        let renderTimeRewind = hasPreviousSameIdentity
            && deltaSeconds.isFinite
            && deltaSeconds < -expectedFrameSeconds * 0.10
        let preparedSampleGap = normalCadence
            && sampleDelta.isFinite
            && sampleDelta > 1.55
        let preparedSampleRepeat = normalCadence
            && sampleDelta.isFinite
            && sampleDelta < 0.45
        let irregularRenderCadence = renderTimeGap
            || renderTimeRepeat
            || renderTimeRewind
            || preparedSampleGap
            || preparedSampleRepeat
        let tinyStep = normalCadence
            && transformStep < 0.08
            && cropPositionStep < 0.08
            && cropScaleDeltaPercent < 0.04
        let catchUpAfterTinyStep = normalCadence
            && (previous?.tinyStep ?? false)
            && (transformStep > 1.25 || cropPositionStep > 1.25 || cropScaleDeltaPercent > 0.18)
        let largeSingleStep = normalCadence
            && (transformStep > 2.0 || cropPositionStep > 2.0 || cropScaleDeltaPercent > 0.30)
        let repeatedPreparedSample = normalCadence
            && sameIdentity
            && samplePosition <= (previous?.samplePosition ?? -1.0) + 0.05
        do {
            let trackingQuality = max(autoTransform.walkingTrackingConfidence, autoTransform.trackingConfidence)
            let appliedPixelOffset = autoTransform.pixelOffset * masterStrength
            let appliedMacroPixelOffset = autoTransform.macroPixelOffset * masterStrength
            let appliedCameraJitterPixelOffset = (
                autoTransform.microPixelOffset
                + autoTransform.macroJitterPixelOffset
                + autoTransform.trajectoryMicroJitterPixelOffset
                + autoTransform.trajectoryContinuityPixelOffset
                + autoTransform.cameraRigidPixelOffset
            ) * masterStrength
            let appliedCameraRigidPixelOffset = autoTransform.cameraRigidPixelOffset * masterStrength
            let appliedLensShakePixelOffset = autoTransform.lensShakePixelOffset * masterStrength
            let appliedTurnDetectedPixelOffset = autoTransform.turnDetectedPixelOffset * masterStrength
            let componentPixelOffset = appliedMacroPixelOffset
                + appliedCameraJitterPixelOffset
                + appliedLensShakePixelOffset
            let componentResidualPixelOffset = appliedPixelOffset - componentPixelOffset
            let appliedTransformDelta = sameIdentity ? transformDelta * masterStrength : vector_float2(0.0, 0.0)
            let appliedRotationDegrees = autoTransform.rotationDegrees * masterStrength
            let appliedCameraJitterRotationDegrees = (
                autoTransform.microJitterRotationDegrees
                + autoTransform.macroJitterRotationDegrees
                + autoTransform.cameraRigidRotationDegrees
            ) * masterStrength
            let appliedCameraRigidRotationDegrees = autoTransform.cameraRigidRotationDegrees * masterStrength
            let cameraRigidLimitX = outputSize.x * Float(min(max(strengths.cameraJitterX, 0.0), 5.0) / 100.0)
            let cameraRigidLimitY = outputSize.y * Float(min(max(strengths.cameraJitterY, 0.0), 5.0) / 100.0)
            let cameraRigidLimitRotation = Float(min(max(strengths.cameraJitterRotation, 0.0), 2.0))
            let appliedRawRotationDegrees = autoTransform.rawRotationDegrees * masterStrength
            let appliedTemporalSmoothingRotationDelta = autoTransform.temporalSmoothingRotationDelta * masterStrength
            let appliedLensShakeRotationDegrees = autoTransform.lensShakeRotationDegrees * masterStrength
            let appliedPerspective = autoTransform.perspective * masterStrength
            let appliedShear = autoTransform.shear * masterStrength
            let appliedYawPitchProxy = autoTransform.yawPitchProxy * masterStrength
            let appliedLensShakeYawPitch = autoTransform.lensShakeYawPitch * masterStrength
            let appliedLensShakeShear = autoTransform.lensShakeShear * masterStrength
            let appliedLensShakePerspective = autoTransform.lensShakePerspective * masterStrength
            let appliedLensBandTopOffset = autoTransform.lensBandTopOffset * masterStrength
            let appliedLensBandRidgeOffset = autoTransform.lensBandRidgeOffset * masterStrength
            let appliedLensBandMidOffset = autoTransform.lensBandMidOffset * masterStrength
            let appliedLensBandRawTopOffset = autoTransform.lensBandRawTopOffset * masterStrength
            let appliedLensBandRawRidgeOffset = autoTransform.lensBandRawRidgeOffset * masterStrength
            let appliedLensBandRawMidOffset = autoTransform.lensBandRawMidOffset * masterStrength
            let appliedLensBandPulseDeltaTopOffset = autoTransform.lensBandPulseDeltaTopOffset * masterStrength
            let appliedLensBandPulseDeltaRidgeOffset = autoTransform.lensBandPulseDeltaRidgeOffset * masterStrength
            let appliedLensBandPulseDeltaMidOffset = autoTransform.lensBandPulseDeltaMidOffset * masterStrength
            let appliedLensBandTopColumnOffset = autoTransform.lensBandTopColumnOffset * masterStrength
            let appliedLensBandRidgeColumnOffset = autoTransform.lensBandRidgeColumnOffset * masterStrength
            let appliedLensBandMidColumnOffset = autoTransform.lensBandMidColumnOffset * masterStrength
            let appliedLensBandTopRowPhaseOffset = autoTransform.lensBandTopRowPhaseOffset * masterStrength
            let appliedLensBandRidgeRowPhaseOffset = autoTransform.lensBandRidgeRowPhaseOffset * masterStrength
            let appliedLensBandMidRowPhaseOffset = autoTransform.lensBandMidRowPhaseOffset * masterStrength
            let appliedLensFarFieldRigidShakeOffset = autoTransform.lensFarFieldRigidShakeOffset * masterStrength
            let appliedLensFarFieldMeshOffset = autoTransform.lensFarFieldMeshOffset * masterStrength
            let appliedLensFarFieldRigidCorrectionOffset = autoTransform.lensFarFieldRigidShakeApplied > 0.5
                ? appliedLensBandRidgeOffset
                : vector_float2(0.0, 0.0)
            let appliedLensFarFieldRigidRollResidual = autoTransform.lensFarFieldRigidRollResidual * masterStrength
            let appliedLensFarFieldRigidGlobalYOffset = autoTransform.lensFarFieldRigidGlobalYOffset * masterStrength
            let appliedLensFarFieldRigidGlobalRollDegrees = autoTransform.lensFarFieldRigidGlobalRollDegrees * masterStrength
            let componentRigidDiagnostics = [
                "lensFarFieldRigidRollResidual=\(Self.renderCSVValue(appliedLensFarFieldRigidRollResidual))",
                "lensFarFieldRigidSupportX=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeSupportX))",
                "lensFarFieldRigidSupportY=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeSupportY))",
                "lensFarFieldRigidRollSupport=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidRollSupport))",
                "lensFarFieldRigidGlobalY=\(Self.renderCSVValue(appliedLensFarFieldRigidGlobalYOffset))",
                "lensFarFieldRigidGlobalRoll=\(Self.renderCSVValue(appliedLensFarFieldRigidGlobalRollDegrees))",
                "lensFarFieldRigidRollApplied=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidRollApplied, digits: 2))"
            ].joined(separator: " ")
            let appliedSourceLensShakeRidgeLineOffset = autoTransform.sourceLensShakeRidgeLineOffset * masterStrength
            let appliedSourceLensShakeLocalTopLeftOffset = autoTransform.sourceLensShakeLocalTopLeftOffset * masterStrength
            let appliedSourceLensShakeLocalTopCenterOffset = autoTransform.sourceLensShakeLocalTopCenterOffset * masterStrength
            let appliedSourceLensShakeLocalTopRightOffset = autoTransform.sourceLensShakeLocalTopRightOffset * masterStrength
            let appliedSourceLensShakeLocalRidgeLeftOffset = autoTransform.sourceLensShakeLocalRidgeLeftOffset * masterStrength
            let appliedSourceLensShakeLocalRidgeCenterOffset = autoTransform.sourceLensShakeLocalRidgeCenterOffset * masterStrength
            let appliedSourceLensShakeLocalRidgeRightOffset = autoTransform.sourceLensShakeLocalRidgeRightOffset * masterStrength
            let appliedSourceLensShakeLocalMidLeftOffset = autoTransform.sourceLensShakeLocalMidLeftOffset * masterStrength
            let appliedSourceLensShakeLocalMidCenterOffset = autoTransform.sourceLensShakeLocalMidCenterOffset * masterStrength
            let appliedSourceLensShakeLocalMidRightOffset = autoTransform.sourceLensShakeLocalMidRightOffset * masterStrength
            let componentMessage = [
                "Render frame components csv v2 |",
                "analysisTime=\(Self.renderCSVValue(analysisSeconds))",
                "sample=\(Self.renderCSVValue(samplePosition, digits: 3))",
                "idx=\(lowerIndex)-\(upperIndex)",
                "frac=\(Self.renderCSVValue(fraction))",
                "frames=\(frames.count)",
                "proxy=\(renderSourceIsProxy ? "yes" : "no")",
                "crop=\(autoCropEnabled ? "yes" : "no")",
                "identity=\(cacheIdentityShort)",
                "pixelX=\(Self.renderCSVValue(appliedPixelOffset.x))",
                "pixelY=\(Self.renderCSVValue(appliedPixelOffset.y))",
                "macroX=\(Self.renderCSVValue(appliedMacroPixelOffset.x))",
                "macroY=\(Self.renderCSVValue(appliedMacroPixelOffset.y))",
                "cameraX=\(Self.renderCSVValue(appliedCameraJitterPixelOffset.x))",
                "cameraY=\(Self.renderCSVValue(appliedCameraJitterPixelOffset.y))",
                "cameraRigidX=\(Self.renderCSVValue(appliedCameraRigidPixelOffset.x))",
                "cameraRigidY=\(Self.renderCSVValue(appliedCameraRigidPixelOffset.y))",
                "cameraRigidLimitX=\(Self.renderCSVValue(cameraRigidLimitX))",
                "cameraRigidLimitY=\(Self.renderCSVValue(cameraRigidLimitY))",
                "cameraCadenceY=\(Self.renderCSVValue(autoTransform.cameraJitterCadenceCorrectionY * masterStrength))",
                "cameraRigidRotation=\(Self.renderCSVValue(appliedCameraRigidRotationDegrees))",
                "cameraRigidLimitRotation=\(Self.renderCSVValue(cameraRigidLimitRotation))",
                "componentResidualX=\(Self.renderCSVValue(componentResidualPixelOffset.x))",
                "componentResidualY=\(Self.renderCSVValue(componentResidualPixelOffset.y))",
                "turnX=\(Self.renderCSVValue(appliedTurnDetectedPixelOffset.x))",
                "turnY=\(Self.renderCSVValue(appliedTurnDetectedPixelOffset.y))",
                "lensShakeX=\(Self.renderCSVValue(appliedLensShakePixelOffset.x))",
                "lensShakeY=\(Self.renderCSVValue(appliedLensShakePixelOffset.y))",
                "lensShakeRotation=\(Self.renderCSVValue(appliedLensShakeRotationDegrees))",
                "lensShakeYaw=\(Self.renderCSVValue(appliedLensShakeYawPitch.x, digits: 6))",
                "lensShakePitch=\(Self.renderCSVValue(appliedLensShakeYawPitch.y, digits: 6))",
                "lensShakeShearX=\(Self.renderCSVValue(appliedLensShakeShear.x, digits: 6))",
                "lensShakeShearY=\(Self.renderCSVValue(appliedLensShakeShear.y, digits: 6))",
                "lensShakePerspectiveX=\(Self.renderCSVValue(appliedLensShakePerspective.x, digits: 6))",
                "lensShakePerspectiveY=\(Self.renderCSVValue(appliedLensShakePerspective.y, digits: 6))",
                "lensShakeScore=\(Self.renderCSVValue(autoTransform.lensShakeScore))",
                "lensShakeSupport=\(Self.renderCSVValue(autoTransform.lensShakeSupport))",
                "lensShakeWindowFrames=\(Self.renderCSVValue(autoTransform.lensShakeWindowFrames, digits: 2))",
                "lensShakeWindowSeconds=\(Self.renderCSVValue(autoTransform.lensShakeWindowSeconds))",
                "lensShakeAxis=\(Self.lensShakeAxisDescription(autoTransform.lensShakeAxisMask))",
                "lensShakeReason=\(Self.lensShakeReasonDescription(autoTransform.lensShakeReasonCode))",
                "lensShakeRollingShutterCandidate=\(Self.renderCSVValue(autoTransform.lensShakeRollingShutterCandidate))",
                "lensBandCorrectionModel=\(Self.lensBandCorrectionModelDescription(autoTransform.lensBandModelMask))",
                componentRigidDiagnostics,
                "lensBandTopX=\(Self.renderCSVValue(appliedLensBandTopOffset.x))",
                "lensBandTopY=\(Self.renderCSVValue(appliedLensBandTopOffset.y))",
                "lensBandRidgeX=\(Self.renderCSVValue(appliedLensBandRidgeOffset.x))",
                "lensBandRidgeY=\(Self.renderCSVValue(appliedLensBandRidgeOffset.y))",
                "lensBandMidX=\(Self.renderCSVValue(appliedLensBandMidOffset.x))",
                "lensBandMidY=\(Self.renderCSVValue(appliedLensBandMidOffset.y))",
                "lensBandTopColumnX=\(Self.renderCSVValue(appliedLensBandTopColumnOffset.x))",
                "lensBandTopColumnY=\(Self.renderCSVValue(appliedLensBandTopColumnOffset.y))",
                "lensBandRidgeColumnX=\(Self.renderCSVValue(appliedLensBandRidgeColumnOffset.x))",
                "lensBandRidgeColumnY=\(Self.renderCSVValue(appliedLensBandRidgeColumnOffset.y))",
                "lensBandMidColumnX=\(Self.renderCSVValue(appliedLensBandMidColumnOffset.x))",
                "lensBandMidColumnY=\(Self.renderCSVValue(appliedLensBandMidColumnOffset.y))",
                "lensBandTopRowPhaseX=\(Self.renderCSVValue(appliedLensBandTopRowPhaseOffset.x))",
                "lensBandTopRowPhaseY=\(Self.renderCSVValue(appliedLensBandTopRowPhaseOffset.y))",
                "lensBandRidgeRowPhaseX=\(Self.renderCSVValue(appliedLensBandRidgeRowPhaseOffset.x))",
                "lensBandRidgeRowPhaseY=\(Self.renderCSVValue(appliedLensBandRidgeRowPhaseOffset.y))",
                "lensBandMidRowPhaseX=\(Self.renderCSVValue(appliedLensBandMidRowPhaseOffset.x))",
                "lensBandMidRowPhaseY=\(Self.renderCSVValue(appliedLensBandMidRowPhaseOffset.y))",
                "lensBandTopLocalRoll=\(Self.renderCSVValue(autoTransform.lensBandTopLocalRoll * masterStrength, digits: 7))",
                "lensBandRidgeLocalRoll=\(Self.renderCSVValue(autoTransform.lensBandRidgeLocalRoll * masterStrength, digits: 7))",
                "lensBandMidLocalRoll=\(Self.renderCSVValue(autoTransform.lensBandMidLocalRoll * masterStrength, digits: 7))",
                "lensBandWarpSupport=\(Self.renderCSVValue(autoTransform.lensBandWarpSupport))",
                "lensBandWarpApplied=\(Self.renderCSVValue(autoTransform.lensBandWarpApplied, digits: 2))",
                "lensBandRollingShutterScore=\(Self.renderCSVValue(autoTransform.lensBandRollingShutterScore))",
                "lensFarFieldMeshDominantWindowFrames=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshDominantWindowFrames, digits: 2))",
                "lensFarFieldMeshDominantWindowSeconds=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshDominantWindowSeconds))",
                "lensFarFieldMeshDominantSupport=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshDominantSupport))",
                "lensFarFieldMeshDominantCell=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshDominantCell, digits: 0))",
                "sourceLensShakeRidgeY=\(Self.renderCSVValue(autoTransform.sourceLensShakeRidgeOffset.y * masterStrength))",
                "sourceLensShakeRidgeSupport=\(Self.renderCSVValue(autoTransform.sourceLensShakeRidgeSupport))",
                "sourceLensShakeRidgeApplied=\(Self.renderCSVValue(autoTransform.sourceLensShakeRidgeApplied, digits: 2))",
                "sourceLensShakeLocalSupport=\(Self.renderCSVValue(autoTransform.sourceLensShakeLocalSupport))",
                "sourceLensShakeLocalApplied=\(Self.renderCSVValue(autoTransform.sourceLensShakeLocalApplied, digits: 2))",
                "sourceLensShakeLocalTopLeftX=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopLeftOffset.x))",
                "sourceLensShakeLocalTopLeftY=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopLeftOffset.y))",
                "sourceLensShakeLocalTopCenterX=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopCenterOffset.x))",
                "sourceLensShakeLocalTopCenterY=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopCenterOffset.y))",
                "sourceLensShakeLocalTopRightX=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopRightOffset.x))",
                "sourceLensShakeLocalTopRightY=\(Self.renderCSVValue(appliedSourceLensShakeLocalTopRightOffset.y))",
                "sourceLensShakeLocalRidgeLeftX=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeLeftOffset.x))",
                "sourceLensShakeLocalRidgeLeftY=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeLeftOffset.y))",
                "sourceLensShakeLocalRidgeCenterX=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeCenterOffset.x))",
                "sourceLensShakeLocalRidgeCenterY=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeCenterOffset.y))",
                "sourceLensShakeLocalRidgeRightX=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeRightOffset.x))",
                "sourceLensShakeLocalRidgeRightY=\(Self.renderCSVValue(appliedSourceLensShakeLocalRidgeRightOffset.y))",
                "sourceLensShakeLocalMidLeftX=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidLeftOffset.x))",
                "sourceLensShakeLocalMidLeftY=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidLeftOffset.y))",
                "sourceLensShakeLocalMidCenterX=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidCenterOffset.x))",
                "sourceLensShakeLocalMidCenterY=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidCenterOffset.y))",
                "sourceLensShakeLocalMidRightX=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidRightOffset.x))",
                "sourceLensShakeLocalMidRightY=\(Self.renderCSVValue(appliedSourceLensShakeLocalMidRightOffset.y))",
                "rotation=\(Self.renderCSVValue(appliedRotationDegrees))",
                "cameraRotation=\(Self.renderCSVValue(appliedCameraJitterRotationDegrees))",
                "rawRotation=\(Self.renderCSVValue(appliedRawRotationDegrees))",
                "smoothingRotationDelta=\(Self.renderCSVValue(appliedTemporalSmoothingRotationDelta))",
                "perspectiveX=\(Self.renderCSVValue(appliedPerspective.x))",
                "perspectiveY=\(Self.renderCSVValue(appliedPerspective.y))",
                "shearX=\(Self.renderCSVValue(appliedShear.x))",
                "shearY=\(Self.renderCSVValue(appliedShear.y))",
                "yawPitchX=\(Self.renderCSVValue(appliedYawPitchProxy.x))",
                "yawPitchY=\(Self.renderCSVValue(appliedYawPitchProxy.y))",
                "warpConfidence=\(Self.renderCSVValue(autoTransform.warpConfidence))",
                "blur=\(Self.renderCSVValue(autoTransform.blurAmount))",
                "residual=\(Self.renderCSVValue(autoTransform.residual))",
                "acceptedBlocks=\(autoTransform.acceptedBlockCount)",
                "totalBlocks=\(autoTransform.totalBlockCount)",
                "cropX=\(Self.renderCSVValue(autoCropFraming.positionPixels.x))",
                "cropY=\(Self.renderCSVValue(autoCropFraming.positionPixels.y))",
                "cropScale=\(Self.renderCSVValue(autoCropFraming.scale, digits: 6))",
                "cropOffEdgeGuardScale=\(Self.renderCSVValue(autoCropFraming.cropOffEdgeGuardScale, digits: 6))",
                "cropOffEdgeGuardDemandX=\(Self.renderCSVValue(autoCropFraming.cropOffEdgeGuardDemandX))",
                "cropOffEdgeGuardActive=\(Self.renderCSVValue(autoCropFraming.cropOffEdgeGuardActive, digits: 2))",
                "turnConfidence=\(Self.renderCSVValue(autoTransform.turnConfidence))",
                "trackingQuality=\(Self.renderCSVValue(trackingQuality))",
                "deltaX=\(Self.renderCSVValue(appliedTransformDelta.x))",
                "deltaY=\(Self.renderCSVValue(appliedTransformDelta.y))",
                "deltaSeconds=\(Self.renderCSVValue(sameIdentity ? deltaSeconds : 0.0))",
                "sampleDelta=\(Self.renderCSVValue(sameIdentity ? sampleDelta : 0.0))",
                "previewWarming=\(previewWarmupDecision.active ? "yes" : "no")",
                "previewWarmupReason=\(previewWarmupDecision.reason)"
            ].joined(separator: " ")
            os_log(
                "%{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                componentMessage
            )
            let lensBandMessage = String(
                format: "Render lens band csv v1 | analysisTime=%.5f sample=%.3f frames=%d proxy=%@ crop=%@ identity=%@ lensShakeReason=%@ lensBandCorrectionModel=%@ lensBandWarpSupport=%.5f lensBandWarpApplied=%.2f lensBandRollingShutterScore=%.5f lensBandTopX=%.5f lensBandTopY=%.5f lensBandRidgeX=%.5f lensBandRidgeY=%.5f lensBandMidX=%.5f lensBandMidY=%.5f lensBandRawTopX=%.5f lensBandRawTopY=%.5f lensBandRawRidgeX=%.5f lensBandRawRidgeY=%.5f lensBandRawMidX=%.5f lensBandRawMidY=%.5f lensBandPulseDeltaTopX=%.5f lensBandPulseDeltaTopY=%.5f lensBandPulseDeltaRidgeX=%.5f lensBandPulseDeltaRidgeY=%.5f lensBandPulseDeltaMidX=%.5f lensBandPulseDeltaMidY=%.5f lensBandPulseWindowFrames=%.2f lensBandTopColumnX=%.5f lensBandTopColumnY=%.5f lensBandRidgeColumnX=%.5f lensBandRidgeColumnY=%.5f lensBandMidColumnX=%.5f lensBandMidColumnY=%.5f lensBandTopRowPhaseX=%.5f lensBandTopRowPhaseY=%.5f lensBandRidgeRowPhaseX=%.5f lensBandRidgeRowPhaseY=%.5f lensBandMidRowPhaseX=%.5f lensBandMidRowPhaseY=%.5f lensBandTopLocalRoll=%.7f lensBandRidgeLocalRoll=%.7f lensBandMidLocalRoll=%.7f sourceLensShakeRidgeY=%.5f sourceLensShakeRidgeSupport=%.5f sourceLensShakeRidgeApplied=%.2f sourceLensShakeLocalSupport=%.5f sourceLensShakeLocalApplied=%.2f sourceLensShakeLocalTopLeftX=%.5f sourceLensShakeLocalTopLeftY=%.5f sourceLensShakeLocalTopCenterX=%.5f sourceLensShakeLocalTopCenterY=%.5f sourceLensShakeLocalTopRightX=%.5f sourceLensShakeLocalTopRightY=%.5f sourceLensShakeLocalRidgeLeftX=%.5f sourceLensShakeLocalRidgeLeftY=%.5f sourceLensShakeLocalRidgeCenterX=%.5f sourceLensShakeLocalRidgeCenterY=%.5f sourceLensShakeLocalRidgeRightX=%.5f sourceLensShakeLocalRidgeRightY=%.5f sourceLensShakeLocalMidLeftX=%.5f sourceLensShakeLocalMidLeftY=%.5f sourceLensShakeLocalMidCenterX=%.5f sourceLensShakeLocalMidCenterY=%.5f sourceLensShakeLocalMidRightX=%.5f sourceLensShakeLocalMidRightY=%.5f",
                analysisSeconds,
                samplePosition,
                frames.count,
                renderSourceIsProxy ? "yes" : "no",
                autoCropEnabled ? "yes" : "no",
                cacheIdentityShort,
                Self.lensShakeReasonDescription(autoTransform.lensShakeReasonCode),
                Self.lensBandCorrectionModelDescription(autoTransform.lensBandModelMask),
                autoTransform.lensBandWarpSupport,
                autoTransform.lensBandWarpApplied,
                autoTransform.lensBandRollingShutterScore,
                appliedLensBandTopOffset.x,
                appliedLensBandTopOffset.y,
                appliedLensBandRidgeOffset.x,
                appliedLensBandRidgeOffset.y,
                appliedLensBandMidOffset.x,
                appliedLensBandMidOffset.y,
                appliedLensBandRawTopOffset.x,
                appliedLensBandRawTopOffset.y,
                appliedLensBandRawRidgeOffset.x,
                appliedLensBandRawRidgeOffset.y,
                appliedLensBandRawMidOffset.x,
                appliedLensBandRawMidOffset.y,
                appliedLensBandPulseDeltaTopOffset.x,
                appliedLensBandPulseDeltaTopOffset.y,
                appliedLensBandPulseDeltaRidgeOffset.x,
                appliedLensBandPulseDeltaRidgeOffset.y,
                appliedLensBandPulseDeltaMidOffset.x,
                appliedLensBandPulseDeltaMidOffset.y,
                autoTransform.lensBandPulseWindowFrames,
                appliedLensBandTopColumnOffset.x,
                appliedLensBandTopColumnOffset.y,
                appliedLensBandRidgeColumnOffset.x,
                appliedLensBandRidgeColumnOffset.y,
                appliedLensBandMidColumnOffset.x,
                appliedLensBandMidColumnOffset.y,
                appliedLensBandTopRowPhaseOffset.x,
                appliedLensBandTopRowPhaseOffset.y,
                appliedLensBandRidgeRowPhaseOffset.x,
                appliedLensBandRidgeRowPhaseOffset.y,
                appliedLensBandMidRowPhaseOffset.x,
                appliedLensBandMidRowPhaseOffset.y,
                autoTransform.lensBandTopLocalRoll * masterStrength,
                autoTransform.lensBandRidgeLocalRoll * masterStrength,
                autoTransform.lensBandMidLocalRoll * masterStrength,
                autoTransform.sourceLensShakeRidgeOffset.y * masterStrength,
                autoTransform.sourceLensShakeRidgeSupport,
                autoTransform.sourceLensShakeRidgeApplied,
                autoTransform.sourceLensShakeLocalSupport,
                autoTransform.sourceLensShakeLocalApplied,
                appliedSourceLensShakeLocalTopLeftOffset.x,
                appliedSourceLensShakeLocalTopLeftOffset.y,
                appliedSourceLensShakeLocalTopCenterOffset.x,
                appliedSourceLensShakeLocalTopCenterOffset.y,
                appliedSourceLensShakeLocalTopRightOffset.x,
                appliedSourceLensShakeLocalTopRightOffset.y,
                appliedSourceLensShakeLocalRidgeLeftOffset.x,
                appliedSourceLensShakeLocalRidgeLeftOffset.y,
                appliedSourceLensShakeLocalRidgeCenterOffset.x,
                appliedSourceLensShakeLocalRidgeCenterOffset.y,
                appliedSourceLensShakeLocalRidgeRightOffset.x,
                appliedSourceLensShakeLocalRidgeRightOffset.y,
                appliedSourceLensShakeLocalMidLeftOffset.x,
                appliedSourceLensShakeLocalMidLeftOffset.y,
                appliedSourceLensShakeLocalMidCenterOffset.x,
                appliedSourceLensShakeLocalMidCenterOffset.y,
                appliedSourceLensShakeLocalMidRightOffset.x,
                appliedSourceLensShakeLocalMidRightOffset.y
            )
            os_log(
                "%{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                lensBandMessage
            )
            let lensRigidMessage = [
                "Render lens rigid csv v1 |",
                "analysisTime=\(Self.renderCSVValue(analysisSeconds))",
                "sample=\(Self.renderCSVValue(samplePosition, digits: 3))",
                "frames=\(frames.count)",
                "proxy=\(renderSourceIsProxy ? "yes" : "no")",
                "crop=\(autoCropEnabled ? "yes" : "no")",
                "identity=\(cacheIdentityShort)",
                "lensShakeReason=\(Self.lensShakeReasonDescription(autoTransform.lensShakeReasonCode))",
                "lensBandCorrectionModel=\(Self.lensBandCorrectionModelDescription(autoTransform.lensBandModelMask))",
                "lensFarFieldRigidX=\(Self.renderCSVValue(appliedLensFarFieldRigidCorrectionOffset.x))",
                "lensFarFieldRigidY=\(Self.renderCSVValue(appliedLensFarFieldRigidCorrectionOffset.y))",
                "lensFarFieldRigidResidualX=\(Self.renderCSVValue(appliedLensFarFieldRigidShakeOffset.x))",
                "lensFarFieldRigidResidualY=\(Self.renderCSVValue(appliedLensFarFieldRigidShakeOffset.y))",
                "lensFarFieldRigidRollResidual=\(Self.renderCSVValue(appliedLensFarFieldRigidRollResidual))",
                "lensFarFieldRigidSupport=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeSupport))",
                "lensFarFieldRigidRollSupport=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidRollSupport))",
                "lensFarFieldRigidApplied=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeApplied, digits: 2))",
                "lensFarFieldRigidRollApplied=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidRollApplied, digits: 2))",
                "lensFarFieldRigidGlobalY=\(Self.renderCSVValue(appliedLensFarFieldRigidGlobalYOffset))",
                "lensFarFieldRigidGlobalRoll=\(Self.renderCSVValue(appliedLensFarFieldRigidGlobalRollDegrees))",
                "lensFarFieldRigidShapeConsistency=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeShapeConsistency))",
                "lensFarFieldRigidForwardBackwardConsistency=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeForwardBackwardConsistency))",
                "lensFarFieldRigidLocalWarpSuppressed=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidShakeLocalWarpSuppressed, digits: 2))",
                "farFieldRigidXQuiverScore=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidXQuiverScore))",
                "farFieldRigidXBeforeLimiter=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidXBeforeLimiter * masterStrength))",
                "farFieldRigidXAfterLimiter=\(Self.renderCSVValue(autoTransform.lensFarFieldRigidXAfterLimiter * masterStrength))",
                "lensFarFieldMeshAvailable=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshAvailable, digits: 2))",
                "lensFarFieldMeshX=\(Self.renderCSVValue(appliedLensFarFieldMeshOffset.x))",
                "lensFarFieldMeshY=\(Self.renderCSVValue(appliedLensFarFieldMeshOffset.y))",
                "lensFarFieldMeshSupport=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshSupport))",
                "lensFarFieldMeshBlend=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshBlend))",
                "lensFarFieldMeshSupportedBins=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshSupportedBins, digits: 1))",
                "lensFarFieldMeshMaxBinDelta=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshMaxBinDelta))",
                "lensFarFieldMeshOpposingBins=\(Self.renderCSVValue(autoTransform.lensFarFieldMeshOpposingBins, digits: 1))"
            ].joined(separator: " ")
            os_log(
                "%{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                lensRigidMessage
            )
            let lensRidgeLineMessage = String(
                format: "Render lens ridge line csv v1 | analysisTime=%.5f sample=%.3f frames=%d proxy=%@ crop=%@ identity=%@ sourceLensShakeRidgeLineRawY=%.5f sourceLensShakeRidgeLineY=%.5f sourceLensShakeRidgeLineSupport=%.5f sourceLensShakeRidgeLineBandSupported=%.2f sourceLensShakeRidgeLineApplied=%.2f sourceLensShakeRidgeCombinedY=%.5f",
                analysisSeconds,
                samplePosition,
                frames.count,
                renderSourceIsProxy ? "yes" : "no",
                autoCropEnabled ? "yes" : "no",
                cacheIdentityShort,
                autoTransform.sourceLensShakeRidgeLineResidual.y * masterStrength,
                appliedSourceLensShakeRidgeLineOffset.y,
                autoTransform.sourceLensShakeRidgeLineSupport,
                autoTransform.sourceLensShakeRidgeLineBandSupported,
                autoTransform.sourceLensShakeRidgeLineApplied,
                autoTransform.sourceLensShakeRidgeOffset.y * masterStrength
            )
            os_log(
                "%{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                lensRidgeLineMessage
            )
            let lensLocalMessage = String(
                format: "Render lens local csv v1 | analysisTime=%.5f sample=%.3f frames=%d proxy=%@ crop=%@ identity=%@ sourceLensShakeLocalSupport=%.5f sourceLensShakeLocalApplied=%.2f sourceLensShakeLocalTopLeftX=%.5f sourceLensShakeLocalTopLeftY=%.5f sourceLensShakeLocalTopCenterX=%.5f sourceLensShakeLocalTopCenterY=%.5f sourceLensShakeLocalTopRightX=%.5f sourceLensShakeLocalTopRightY=%.5f sourceLensShakeLocalRidgeLeftX=%.5f sourceLensShakeLocalRidgeLeftY=%.5f sourceLensShakeLocalRidgeCenterX=%.5f sourceLensShakeLocalRidgeCenterY=%.5f sourceLensShakeLocalRidgeRightX=%.5f sourceLensShakeLocalRidgeRightY=%.5f sourceLensShakeLocalMidLeftX=%.5f sourceLensShakeLocalMidLeftY=%.5f sourceLensShakeLocalMidCenterX=%.5f sourceLensShakeLocalMidCenterY=%.5f sourceLensShakeLocalMidRightX=%.5f sourceLensShakeLocalMidRightY=%.5f",
                analysisSeconds,
                samplePosition,
                frames.count,
                renderSourceIsProxy ? "yes" : "no",
                autoCropEnabled ? "yes" : "no",
                cacheIdentityShort,
                autoTransform.sourceLensShakeLocalSupport,
                autoTransform.sourceLensShakeLocalApplied,
                appliedSourceLensShakeLocalTopLeftOffset.x,
                appliedSourceLensShakeLocalTopLeftOffset.y,
                appliedSourceLensShakeLocalTopCenterOffset.x,
                appliedSourceLensShakeLocalTopCenterOffset.y,
                appliedSourceLensShakeLocalTopRightOffset.x,
                appliedSourceLensShakeLocalTopRightOffset.y,
                appliedSourceLensShakeLocalRidgeLeftOffset.x,
                appliedSourceLensShakeLocalRidgeLeftOffset.y,
                appliedSourceLensShakeLocalRidgeCenterOffset.x,
                appliedSourceLensShakeLocalRidgeCenterOffset.y,
                appliedSourceLensShakeLocalRidgeRightOffset.x,
                appliedSourceLensShakeLocalRidgeRightOffset.y,
                appliedSourceLensShakeLocalMidLeftOffset.x,
                appliedSourceLensShakeLocalMidLeftOffset.y,
                appliedSourceLensShakeLocalMidCenterOffset.x,
                appliedSourceLensShakeLocalMidCenterOffset.y,
                appliedSourceLensShakeLocalMidRightOffset.x,
                appliedSourceLensShakeLocalMidRightOffset.y
            )
            os_log(
                "%{public}@",
                log: stabilizerHostAnalysisLog,
                type: .default,
                lensLocalMessage
            )
        }
        let motionAnomaly = irregularRenderCadence
            || catchUpAfterTinyStep
            || largeSingleStep
            || repeatedPreparedSample
        let periodicSampleDue: Bool
        let shouldLogMotionDiagnostic: Bool

        renderDiagnosticsLogLock.lock()
        periodicSampleDue = (now - lastRenderMotionDiagnosticLogWallTime) >= 0.5
        shouldLogMotionDiagnostic = periodicSampleDue
            || (motionAnomaly && (now - lastRenderMotionDiagnosticLogWallTime) >= 0.25)
        if shouldLogMotionDiagnostic {
            lastRenderMotionDiagnosticLogWallTime = now
        }
        lastRenderMotionDiagnosticState = RenderMotionDiagnosticState(
            cacheIdentityShort: cacheIdentityShort,
            analysisSeconds: analysisSeconds,
            lowerIndex: lowerIndex,
            upperIndex: upperIndex,
            samplePosition: samplePosition,
            pixelOffset: autoTransform.pixelOffset,
            cropScale: autoCropFraming.scale,
            cropPositionPixels: autoCropFraming.positionPixels,
            tinyStep: tinyStep
        )
        renderDiagnosticsLogLock.unlock()

        let reason: String
        if renderTimeRewind {
            reason = "render-time-rewind"
        } else if renderTimeGap {
            reason = "render-time-gap"
        } else if renderTimeRepeat {
            reason = "render-time-repeat"
        } else if preparedSampleGap {
            reason = "prepared-sample-gap"
        } else if preparedSampleRepeat {
            reason = "prepared-sample-repeat"
        } else if catchUpAfterTinyStep {
            reason = "catch-up-after-hold"
        } else if largeSingleStep {
            reason = "large-step"
        } else if repeatedPreparedSample {
            reason = "repeated-prepared-sample"
        } else if periodicSampleDue {
            reason = "sample"
        } else {
            return
        }
        guard shouldLogMotionDiagnostic else {
            return
        }
        let lowerFingerprintForLog = String(lowerFingerprint.prefix(8))
        let upperFingerprintForLog = String(upperFingerprint.prefix(8))
        os_log(
            "Render motion cadence | FxPlug %{public}@ | reason %{public}@ | render %.3f dt %.5f expected %.5f sample %.3f dSample %.3f idx %d-%d frac %.3f fp %{public}@/%{public}@ | X %.3f Y %.3f dX %.3f dY %.3f step %.3f pathX %.3f pathY %.3f | cropScale %.5f dScale %.4f cropX %.3f cropY %.3f cropStep %.3f | proxy %{public}@ crop %{public}@ identity %{public}@",
            log: stabilizerHostAnalysisLog,
            type: (irregularRenderCadence || catchUpAfterTinyStep || largeSingleStep || repeatedPreparedSample)
                ? .error
                : .default,
            tokyoWalkingStabilizerVersion,
            reason,
            analysisSeconds,
            deltaSeconds,
            expectedFrameSeconds,
            samplePosition,
            sampleDelta,
            lowerIndex,
            upperIndex,
            fraction,
            lowerFingerprintForLog,
            upperFingerprintForLog,
            autoTransform.pixelOffset.x,
            autoTransform.pixelOffset.y,
            transformDelta.x,
            transformDelta.y,
            transformStep,
            pathPixelOffset.x,
            pathPixelOffset.y,
            autoCropFraming.scale,
            cropScaleDeltaPercent,
            autoCropFraming.positionPixels.x,
            autoCropFraming.positionPixels.y,
            cropPositionStep,
            renderSourceIsProxy ? "yes" : "no",
            autoCropEnabled ? "yes" : "no",
            cacheIdentityShort
        )
    }

    private func publishAnalysisCallbackStatus(
        _ analysisStore: StabilizerHostAnalysisStore,
        canPublishCallbackStatus: Bool = true
    ) {
        guard canPublishCallbackStatus else {
            os_log(
                "Skipped in-progress Host Analysis status publish from a non-owner callback instance.",
                log: stabilizerHostAnalysisLog,
                type: .debug
            )
            return
        }
        if hostAnalysisStore.hasCompletedAnalysis {
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
        } else {
            publishHostAnalysisStatus(force: true, statusOverride: analysisStore.statusText)
            publishStabilizerInfo(force: true, inspectorSnapshotOverride: analysisStore.inspectorSnapshot)
            publishRenderRevision(analysisStore.renderInvalidationToken, force: true)
        }
    }

    private func publishActiveAnalysisProgressIfNeeded(
        _ analysisStore: StabilizerHostAnalysisStore,
        canPublishCallbackStatus: Bool
    ) {
        guard canPublishCallbackStatus else {
            os_log(
                "Skipped in-progress Host Analysis progress publish from a non-owner callback instance.",
                log: stabilizerHostAnalysisLog,
                type: .debug
            )
            return
        }
        let frameCount = analysisStore.frameCount
        statusLock.lock()
        let shouldPublish = frameCount == 1
            || frameCount - lastPublishedActiveAnalysisFrameCount >= 30
        if shouldPublish {
            lastPublishedActiveAnalysisFrameCount = frameCount
        }
        statusLock.unlock()
        guard shouldPublish else {
            return
        }
        publishAnalysisCallbackStatus(analysisStore, canPublishCallbackStatus: true)
    }

    private func startPersistentCacheMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: persistentCacheMonitorQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.75)
        timer.setEventHandler { [weak self] in
            self?.pollPersistentCacheForPreviewInvalidation()
        }
        persistentCacheMonitor = timer
        timer.resume()
    }

    private func pollPersistentCacheForPreviewInvalidation() {
        let expectedRange = currentCacheResolutionExpectedRange()
        guard configureProjectBundleCacheDirectory(expectedRange: expectedRange) else {
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: hostAnalysisStore.renderInvalidationToken
            )
            return
        }
        let loadedCache: Bool
        if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
           (hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)
            || hostAnalysisStore.activatePersistentCache(matchingSourceIdentity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true)) {
            loadedCache = true
        } else {
            loadedCache = hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange, allowRangeMismatch: true)
        }
        guard loadedCache || hostAnalysisStore.hasCompletedAnalysis else {
            return
        }
        if loadedCache {
            publishHostAnalysisCacheIdentityOnMain(hostAnalysisStore.activeCacheIdentity, force: false)
        }
        schedulePostAnalysisPreviewInvalidationRetries(
            revision: hostAnalysisStore.renderInvalidationToken,
            cacheIdentity: hostAnalysisStore.activeCacheIdentity
        )
        publishPreviewInvalidationOnMain(
            statusForce: loadedCache,
            infoForce: loadedCache,
            revision: hostAnalysisStore.renderInvalidationToken
        )
    }

    private func publishPreviewInvalidationOnMain(
        statusForce: Bool,
        infoForce: Bool,
        revision: Double,
        revisionForce: Bool = false,
        currentRenderRevision: Double? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.publishHostAnalysisStatus(force: statusForce)
            self.publishStabilizerInfo(force: infoForce)
            self.publishRenderRevision(
                revision,
                currentParameterValue: currentRenderRevision,
                force: revisionForce
            )
        }
    }

    private func publishPlaybackPreparationInvalidationOnMain(cacheIdentity: String?, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let revision = self.hostAnalysisStore.notePlaybackPreparationReadyForRender(reason: reason)
            self.publishHostAnalysisCacheIdentity(cacheIdentity ?? self.hostAnalysisStore.activeCacheIdentity, force: true)
            self.publishHostAnalysisStatus(force: true)
            self.publishStabilizerInfo(force: true)
            self.publishRenderRevision(revision, force: true)
            for delay in [0.25, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else {
                        return
                    }
                    self.publishRenderRevision(revision, force: true)
                }
            }
        }
    }

    private func registerActiveAnalysisSession(
        store: StabilizerHostAnalysisStore,
        range: CMTimeRange,
        frameDuration: CMTime,
        requestedSampleScalePercent: Double
    ) -> UUID {
        let session = ActiveHostAnalysisSession(
            ownerObjectID: ObjectIdentifier(self),
            store: store,
            range: range,
            frameDuration: frameDuration,
            requestedSampleScalePercent: requestedSampleScalePercent
        )
        Self.activeAnalysisStoreLock.lock()
        Self.hostAnalysisStartReserved = false
        Self.activeAnalysisSessions[session.id] = session
        Self.activeAnalysisStoreLock.unlock()
        activeAnalyzerSessionID = session.id
        return session.id
    }

    private func resolveActiveAnalysisSession(
        frameTime: CMTime,
        sourceInfo: StabilizerSourceFrameInfo?
    ) throws -> ActiveHostAnalysisRoute {
        let ownerObjectID = ObjectIdentifier(self)
        let preferredSessionID = activeAnalyzerSessionID
        Self.activeAnalysisStoreLock.lock()
        let candidates = Self.activeAnalysisSessions.values.compactMap { session -> (session: ActiveHostAnalysisSession, score: Int, sampleSize: (width: Int, height: Int)?)? in
            guard let match = session.score(
                frameTime: frameTime,
                sourceInfo: sourceInfo,
                ownerObjectID: ownerObjectID,
                preferredSessionID: preferredSessionID
            ) else {
                return nil
            }
            return (session: session, score: match.score, sampleSize: match.sampleSize)
        }.sorted { first, second in
            if first.score == second.score {
                return first.session.lastTouchedAt > second.session.lastTouchedAt
            }
            return first.score > second.score
        }
        Self.activeAnalysisStoreLock.unlock()

        guard let bestCandidate = candidates.first else {
            throw hostAnalysisRoutingError("Stabilizer Host Analysis frame had no matching active per-clip session; setupAnalysis did not isolate this callback.")
        }
        let unclaimedCandidateCount = candidates.filter { !$0.session.hasAcceptedFrame }.count
        if unclaimedCandidateCount > 1 {
            let descriptions = candidates.prefix(4).map { $0.session.debugDescription }.joined(separator: " | ")
            throw hostAnalysisRoutingError("Stabilizer Host Analysis frame matched multiple uninitialized per-clip sessions; refusing to infer a clip from callback instance alone. Active sessions: \(descriptions)")
        }
        if candidates.count > 1,
           let secondCandidate = candidates.dropFirst().first,
           secondCandidate.score == bestCandidate.score {
            let descriptions = candidates.prefix(4).map { $0.session.debugDescription }.joined(separator: " | ")
            throw hostAnalysisRoutingError("Stabilizer Host Analysis frame matched multiple active per-clip sessions; refusing to mix clips. Active sessions: \(descriptions)")
        }

        return ActiveHostAnalysisRoute(
            sessionID: bestCandidate.session.id,
            store: bestCandidate.session.store,
            sampleSize: bestCandidate.sampleSize,
            canPublishCallbackStatus: bestCandidate.session.canPublishCallbackStatus(
                ownerObjectID: ownerObjectID,
                preferredSessionID: preferredSessionID
            )
        )
    }

    private func recordActiveAnalysisFrameAccepted(
        sessionID: UUID,
        frameTime: CMTime,
        sourceInfo: StabilizerSourceFrameInfo,
        sampleSize: (width: Int, height: Int)
    ) {
        Self.activeAnalysisStoreLock.lock()
        Self.activeAnalysisSessions[sessionID]?.recordAcceptedFrame(
            frameTime: frameTime,
            sourceInfo: sourceInfo,
            sampleSize: sampleSize
        )
        Self.activeAnalysisStoreLock.unlock()
    }

    private func takeActiveAnalysisSessionForCleanup() -> ActiveHostAnalysisCleanupRoute {
        let ownerObjectID = ObjectIdentifier(self)
        let preferredSessionID = activeAnalyzerSessionID
        Self.activeAnalysisStoreLock.lock()
        defer {
            Self.activeAnalysisStoreLock.unlock()
        }

        if let preferredSessionID,
           let session = Self.activeAnalysisSessions.removeValue(forKey: preferredSessionID) {
            if Self.activeAnalysisSessions.isEmpty {
                Self.hostAnalysisStartReserved = false
            }
            activeAnalyzerSessionID = nil
            return .resolved(
                sessionID: session.id,
                store: session.store,
                expectedRange: Self.expectedRange(for: session),
                canPublishCallbackStatus: true
            )
        }

        let ownerSessions = Self.activeAnalysisSessions.values.filter { $0.ownerObjectID == ownerObjectID }
        if ownerSessions.count == 1,
           let session = ownerSessions.first {
            Self.activeAnalysisSessions.removeValue(forKey: session.id)
            if Self.activeAnalysisSessions.isEmpty {
                Self.hostAnalysisStartReserved = false
            }
            activeAnalyzerSessionID = nil
            return .resolved(
                sessionID: session.id,
                store: session.store,
                expectedRange: Self.expectedRange(for: session),
                canPublishCallbackStatus: true
            )
        }

        if Self.activeAnalysisSessions.count == 1,
           let session = Self.activeAnalysisSessions.values.first {
            let canPublishCallbackStatus = session.canPublishCallbackStatus(
                ownerObjectID: ownerObjectID,
                preferredSessionID: preferredSessionID
            )
            Self.activeAnalysisSessions.removeValue(forKey: session.id)
            if Self.activeAnalysisSessions.isEmpty {
                Self.hostAnalysisStartReserved = false
            }
            activeAnalyzerSessionID = nil
            return .resolved(
                sessionID: session.id,
                store: session.store,
                expectedRange: Self.expectedRange(for: session),
                canPublishCallbackStatus: canPublishCallbackStatus
            )
        }

        if Self.activeAnalysisSessions.isEmpty {
            Self.hostAnalysisStartReserved = false
            return .failed(reason: "Stabilizer Host Analysis cleanup had no active per-clip session.")
        }

        let descriptions = Self.activeAnalysisSessions.values
            .sorted { $0.lastTouchedAt > $1.lastTouchedAt }
            .prefix(4)
            .map(\.debugDescription)
            .joined(separator: " | ")
        return .failed(reason: "Stabilizer Host Analysis cleanup could not identify which per-clip session to finish. Active sessions: \(descriptions)")
    }

    private static func expectedRange(for session: ActiveHostAnalysisSession) -> HostAnalysisExpectedRange? {
        let expectedRange = HostAnalysisExpectedRange(
            startSeconds: CMTimeGetSeconds(session.range.start),
            durationSeconds: CMTimeGetSeconds(session.range.duration),
            frameDurationSeconds: CMTimeGetSeconds(session.frameDuration)
        )
        return expectedRange.isValid ? expectedRange : nil
    }

    private func removeActiveAnalysisSession(_ sessionID: UUID?) {
        Self.activeAnalysisStoreLock.lock()
        if let sessionID {
            Self.activeAnalysisSessions.removeValue(forKey: sessionID)
            if activeAnalyzerSessionID == sessionID {
                activeAnalyzerSessionID = nil
            }
        } else if let activeAnalyzerSessionID {
            Self.activeAnalysisSessions.removeValue(forKey: activeAnalyzerSessionID)
            self.activeAnalyzerSessionID = nil
        } else if Self.activeAnalysisSessions.count == 1,
                  let sessionID = Self.activeAnalysisSessions.keys.first {
            Self.activeAnalysisSessions.removeValue(forKey: sessionID)
        }
        if Self.activeAnalysisSessions.isEmpty {
            Self.hostAnalysisStartReserved = false
        }
        Self.activeAnalysisStoreLock.unlock()
    }

    private func abandonActiveAnalysisAfterFailure(sessionID: UUID?) {
        removeActiveAnalysisSession(sessionID)
        Self.scheduleSerialAnalysisQueueDrain(after: 0.2)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
    }

    private func hostAnalysisRoutingError(_ reason: String) -> NSError {
        NSLog("TokyoWalkingStabilizer: \(reason)")
        os_log("%{public}@", log: stabilizerHostAnalysisLog, type: .error, reason)
        Self.scheduleSerialAnalysisQueueDrain(after: 0.2)
        return NSError(
            domain: "com.justadev.TokyoWalkingStabilizer",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }

    private func updatePreferredHostAnalysisCacheIdentity(_ identity: String?) {
        let trimmedIdentity = identity?.trimmingCharacters(in: .whitespacesAndNewlines)
        cacheIdentityLock.lock()
        preferredHostAnalysisCacheIdentity = trimmedIdentity?.isEmpty == false ? trimmedIdentity : nil
        cacheIdentityLock.unlock()
    }

    private func currentPreferredHostAnalysisCacheIdentity() -> String? {
        cacheIdentityLock.lock()
        let identity = preferredHostAnalysisCacheIdentity
        cacheIdentityLock.unlock()
        return identity
    }

    private func publishHostAnalysisCacheIdentity(_ identity: String?, force: Bool = false) {
        let value = identity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedIdentity = value.isEmpty ? nil : value
        cacheIdentityLock.lock()
        let shouldPublish = force || lastPublishedHostAnalysisCacheIdentity != normalizedIdentity
        cacheIdentityLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if settingAPI.setStringParameterValue(value, toParameter: ParameterID.hostAnalysisCacheIdentity.rawValue) {
            cacheIdentityLock.lock()
            lastPublishedHostAnalysisCacheIdentity = normalizedIdentity
            preferredHostAnalysisCacheIdentity = normalizedIdentity
            cacheIdentityLock.unlock()
        } else {
            NSLog("TokyoWalkingStabilizer: failed to update Host Analysis Cache Identity parameter.")
        }
    }

    private func publishHostAnalysisCacheIdentityOnMain(_ identity: String?, force: Bool = false) {
        if Thread.isMainThread {
            publishHostAnalysisCacheIdentity(identity, force: force)
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.publishHostAnalysisCacheIdentity(identity, force: force)
        }
    }

    private func schedulePostAnalysisPreviewInvalidationRetries(revision: Double, cacheIdentity: String?) {
        guard revision > 0.0 else {
            return
        }
        statusLock.lock()
        if lastScheduledPostAnalysisPublishRevision == revision {
            statusLock.unlock()
            return
        }
        lastScheduledPostAnalysisPublishRevision = revision
        statusLock.unlock()

        // FCP can keep cleanup-time main-queue parameter updates stale; publish once in
        // the active callback/monitor context, then retry briefly on the main queue.
        publishHostAnalysisCacheIdentity(cacheIdentity, force: true)
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(revision, force: true)

        for delay in [0.0, 0.25, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else {
                    return
                }
                self.publishHostAnalysisCacheIdentity(cacheIdentity, force: true)
                self.publishHostAnalysisStatus(force: true)
                self.publishStabilizerInfo(force: true)
                self.publishRenderRevision(revision, force: true)
            }
        }
    }

    private func currentInputRange() -> HostAnalysisExpectedRange? {
        guard let timingAPI = apiManager.api(for: FxTimingAPI_v4.self) as? FxTimingAPI_v4 else {
            return nil
        }
        var start = CMTime.invalid
        var duration = CMTime.invalid
        var frameDuration = CMTime.invalid
        timingAPI.startTimeOfInput(toFilter: &start)
        timingAPI.durationTimeOfInput(toFilter: &duration)
        timingAPI.frameDuration(&frameDuration)
        let range = HostAnalysisExpectedRange(
            startSeconds: CMTimeGetSeconds(start),
            durationSeconds: CMTimeGetSeconds(duration),
            frameDurationSeconds: CMTimeGetSeconds(frameDuration)
        )
        return range.isValid ? range : nil
    }

    private func currentCacheResolutionExpectedRange() -> HostAnalysisExpectedRange? {
        currentInputRange() ?? hostAnalysisStore.activeExpectedRange
    }

    @discardableResult
    private func configureProjectBundleCacheDirectory(
        markUnavailable: Bool = true,
        expectedRange: HostAnalysisExpectedRange? = nil,
        forceRefresh: Bool = false
    ) -> Bool {
        if !forceRefresh,
           StabilizerHostAnalysisStore.hasConfiguredProjectBundleCacheDirectory {
            if markUnavailable {
                _ = hostAnalysisStore.persistCompletedAnalysisIfPossible()
            }
            return true
        }
        func clearStaleProjectCacheIfNeeded(reason: String) {
            if forceRefresh {
                StabilizerHostAnalysisStore.clearProjectBundleCacheDirectory(reason: reason)
            }
        }
        if let projectAPI = apiManager.api(for: FxProjectAPI.self) as? FxProjectAPI {
            let projectDocumentID = Self.projectDocumentID(from: projectAPI)
            var mediaURL: NSURL?
            do {
                try projectAPI.mediaFolderURL(&mediaURL)
                if let projectMediaURL = mediaURL as URL? {
                    let projectMediaURL = projectMediaURL.standardizedFileURL
                    let didStartAccess = projectMediaURL.startAccessingSecurityScopedResource()
                    var shouldRetainSecurityScopedAccess = false
                    defer {
                        if didStartAccess && !shouldRetainSecurityScopedAccess {
                            projectMediaURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    guard let bundleRoot = Self.fcpBundleRoot(containing: projectMediaURL) else {
                        let reason = "FxProjectAPI media folder is not inside a .fcpbundle: \(projectMediaURL.path)"
                        NSLog("TokyoWalkingStabilizer: \(reason)")
                        os_log("Event cache resolver rejected mediaFolderURL %{public}@ because it is not inside a .fcpbundle.", log: stabilizerHostAnalysisLog, type: .error, projectMediaURL.path)
                        clearStaleProjectCacheIfNeeded(reason: reason)
                        if markUnavailable {
                            hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                        }
                        return false
                    }
                    os_log(
                        "Event cache resolver input mediaFolderURL=%{public}@ bundleRoot=%{public}@ expectedRange=%{public}@.",
                        log: stabilizerHostAnalysisLog,
                        type: .default,
                        projectMediaURL.path,
                        bundleRoot.path,
                        Self.expectedRangeDescription(expectedRange)
                    )
                    guard let eventResolution = Self.fcpEventRoot(
                        containing: projectMediaURL,
                        in: bundleRoot,
                        expectedRange: expectedRange,
                        preferredCacheIdentity: currentPreferredHostAnalysisCacheIdentity()
                    ) else {
                        let reason = "Ambiguous Event for Host Analysis cache. FxProjectAPI media folder did not resolve to a writable Event Analysis Files root: \(projectMediaURL.path)"
                        NSLog("TokyoWalkingStabilizer: \(reason)")
                        os_log("Event cache resolver rejected mediaFolderURL %{public}@ in bundle %{public}@ because no unambiguous Event candidate was selected.", log: stabilizerHostAnalysisLog, type: .error, projectMediaURL.path, bundleRoot.path)
                        clearStaleProjectCacheIfNeeded(reason: reason)
                        if markUnavailable {
                            hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                        }
                        return false
                    }
                    let configured = configureEventHostAnalysisCache(
                        bundleRoot: bundleRoot,
                        eventResolution: eventResolution,
                        retainedSecurityScopedURL: didStartAccess ? projectMediaURL : nil,
                        legacyRoots: [
                            Self.legacyHostAnalysisCacheRoot(under: projectMediaURL),
                            Self.legacyHostAnalysisCacheRoot(under: bundleRoot),
                            Self.internalBundleHostAnalysisCacheRoot(in: bundleRoot)
                        ],
                        markUnavailable: markUnavailable
                    )
                    if configured {
                        shouldRetainSecurityScopedAccess = didStartAccess
                    } else {
                        clearStaleProjectCacheIfNeeded(reason: "Event cache root configuration failed for \(eventResolution.eventRoot.path)")
                    }
                    return configured
                }
                let reason = "FxProjectAPI did not provide a project media folder URL."
                NSLog("TokyoWalkingStabilizer: \(reason)")
                os_log("Event cache resolver rejected because FxProjectAPI did not provide mediaFolderURL.", log: stabilizerHostAnalysisLog, type: .error)
                if configureActiveFinalCutLibraryCacheDirectory(
                    markUnavailable: markUnavailable,
                    expectedRange: expectedRange,
                    preferredCacheIdentity: currentPreferredHostAnalysisCacheIdentity(),
                    triggerReason: reason,
                    projectDocumentID: projectDocumentID,
                    forceRefresh: forceRefresh
                ) {
                    return true
                }
                clearStaleProjectCacheIfNeeded(reason: reason)
                if markUnavailable {
                    hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                }
                return false
            } catch {
                let reason = "FxProjectAPI media folder unavailable: \(error.localizedDescription)"
                NSLog("TokyoWalkingStabilizer: \(reason)")
                os_log("Event cache resolver rejected because mediaFolderURL failed: %{public}@.", log: stabilizerHostAnalysisLog, type: .error, error.localizedDescription)
                if Self.isNoMediaFolderError(error),
                   configureActiveFinalCutLibraryCacheDirectory(
                        markUnavailable: markUnavailable,
                        expectedRange: expectedRange,
                        preferredCacheIdentity: currentPreferredHostAnalysisCacheIdentity(),
                        triggerReason: reason,
                        projectDocumentID: projectDocumentID,
                        forceRefresh: forceRefresh
                   ) {
                    return true
                }
                clearStaleProjectCacheIfNeeded(reason: reason)
                if markUnavailable {
                    hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                }
                return false
            }
        } else {
            let reason = "FxProjectAPI unavailable; Event Analysis Files cache cannot be resolved."
            NSLog("TokyoWalkingStabilizer: \(reason)")
            os_log("Event cache resolver rejected because FxProjectAPI is unavailable.", log: stabilizerHostAnalysisLog, type: .error)
            if configureActiveFinalCutLibraryCacheDirectory(
                markUnavailable: markUnavailable,
                expectedRange: expectedRange,
                preferredCacheIdentity: currentPreferredHostAnalysisCacheIdentity(),
                triggerReason: reason,
                projectDocumentID: nil,
                forceRefresh: forceRefresh
            ) {
                return true
            }
            clearStaleProjectCacheIfNeeded(reason: reason)
            if markUnavailable {
                hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
            }
            return false
        }
    }

    @discardableResult
    private func configureEventHostAnalysisCache(
        bundleRoot: URL,
        eventResolution: FCPEventRootResolution,
        retainedSecurityScopedURL: URL?,
        legacyRoots: [URL],
        markUnavailable: Bool
    ) -> Bool {
        let cacheRoot = Self.eventHostAnalysisCacheRoot(in: eventResolution.eventRoot)
        do {
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        } catch {
            let reason = "Event Analysis Files cache root could not be created at \(cacheRoot.path): \(error.localizedDescription)"
            NSLog("TokyoWalkingStabilizer: \(reason)")
            os_log(
                "Event cache resolver selected Event %{public}@ in bundle %{public}@ but cache root creation failed at %{public}@: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                eventResolution.eventRoot.path,
                bundleRoot.path,
                cacheRoot.path,
                error.localizedDescription
            )
            if markUnavailable {
                hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
            }
            return false
        }

        for legacyRoot in legacyRoots {
            Self.migrateLegacyHostAnalysisCacheIfNeeded(from: legacyRoot, to: cacheRoot)
        }
        StabilizerHostAnalysisStore.configureProjectBundleCacheDirectory(
            cacheRoot,
            securityScopedURL: retainedSecurityScopedURL,
            eventName: eventResolution.eventRoot.lastPathComponent
        )
        NSLog("TokyoWalkingStabilizer: using \(eventResolution.sourceDescription) Event Host Analysis cache at \(cacheRoot.path) inside \(eventResolution.eventRoot.path).")
        os_log(
            "Event cache resolver selected Event %{public}@ by %{public}@; bundleRoot=%{public}@ cacheRoot=%{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            eventResolution.eventRoot.lastPathComponent,
            eventResolution.sourceDescription,
            bundleRoot.path,
            cacheRoot.path
        )
        _ = hostAnalysisStore.persistCompletedAnalysisIfPossible()
        return true
    }

    @discardableResult
    private func configureActiveFinalCutLibraryCacheDirectory(
        markUnavailable: Bool,
        expectedRange: HostAnalysisExpectedRange?,
        preferredCacheIdentity: String?,
        triggerReason: String,
        projectDocumentID: UInt?,
        forceRefresh: Bool
    ) -> Bool {
        let lookup = Self.activeFinalCutLibraryEventRoot(
            expectedRange: expectedRange,
            preferredCacheIdentity: preferredCacheIdentity,
            projectDocumentID: projectDocumentID
        )
        guard let resolution = lookup.resolution else {
            let reason = "\(triggerReason) Active Final Cut library resolver failed: \(lookup.rejectReason)"
            os_log(
                "Active library resolver rejected trigger=%{public}@ documentID=%{public}@ reason=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                triggerReason,
                Self.projectDocumentIDDescription(projectDocumentID),
                lookup.rejectReason
            )
            if forceRefresh {
                StabilizerHostAnalysisStore.clearProjectBundleCacheDirectory(reason: reason)
            }
            if markUnavailable {
                hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
            }
            return false
        }

        os_log(
            "Active library resolver selected bundleRoot=%{public}@ Event=%{public}@ trigger=%{public}@ documentID=%{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            resolution.bundleRoot.path,
            resolution.eventResolution.eventRoot.path,
            triggerReason,
            Self.projectDocumentIDDescription(projectDocumentID)
        )
        let configured = configureEventHostAnalysisCache(
            bundleRoot: resolution.bundleRoot,
            eventResolution: resolution.eventResolution,
            retainedSecurityScopedURL: resolution.securityScopedURL,
            legacyRoots: [
                Self.legacyHostAnalysisCacheRoot(under: resolution.bundleRoot),
                Self.internalBundleHostAnalysisCacheRoot(in: resolution.bundleRoot)
            ],
            markUnavailable: markUnavailable
        )
        if !configured {
            resolution.securityScopedURL?.stopAccessingSecurityScopedResource()
            if forceRefresh {
                StabilizerHostAnalysisStore.clearProjectBundleCacheDirectory(
                    reason: "Event cache root configuration failed for \(resolution.eventResolution.eventRoot.path)"
                )
            }
        }
        return configured
    }

    private static func projectDocumentID(from projectAPI: FxProjectAPI) -> UInt? {
        var documentID = UInt(0)
        do {
            try projectAPI.documentID(&documentID)
            os_log(
                "Event cache resolver input documentID=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                projectDocumentIDDescription(documentID)
            )
            return documentID
        } catch {
            os_log(
                "Event cache resolver could not read documentID: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                error.localizedDescription
            )
            return nil
        }
    }

    private static func projectDocumentIDDescription(_ documentID: UInt?) -> String {
        guard let documentID else {
            return "unavailable"
        }
        return String(documentID)
    }

    private static func isNoMediaFolderError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == FxPlugErrorDomain as String,
           nsError.code == Int(kFxError_NoMediaFolder) {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("no media folder")
    }

    private static func eventHostAnalysisCacheRoot(in eventRoot: URL) -> URL {
        eventRoot
            .appendingPathComponent("Analysis Files", isDirectory: true)
            .appendingPathComponent("TokyoWalkingStabilizerHostAnalysis", isDirectory: true)
            .standardizedFileURL
    }

    private static func internalBundleHostAnalysisCacheRoot(in bundleRoot: URL) -> URL {
        bundleRoot
            .appendingPathComponent("__.fcpdata.apple.com", isDirectory: true)
            .appendingPathComponent("TokyoWalkingStabilizerHostAnalysis", isDirectory: true)
            .standardizedFileURL
    }

    private static func legacyHostAnalysisCacheRoot(under rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent("TokyoWalkingStabilizerHostAnalysis", isDirectory: true)
            .standardizedFileURL
    }

    private static func migrateLegacyHostAnalysisCacheIfNeeded(from legacyURL: URL, to cacheRoot: URL) {
        let legacyURL = legacyURL.standardizedFileURL
        let cacheRoot = cacheRoot.standardizedFileURL
        guard legacyURL.path != cacheRoot.path,
              FileManager.default.fileExists(atPath: legacyURL.path)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try moveDirectoryContentsPreservingExistingFiles(from: legacyURL, to: cacheRoot)
            let remainingItems = try FileManager.default.contentsOfDirectory(atPath: legacyURL.path)
            if remainingItems.isEmpty {
                try FileManager.default.removeItem(at: legacyURL)
                NSLog("TokyoWalkingStabilizer: moved legacy Host Analysis cache from \(legacyURL.path) to \(cacheRoot.path).")
            } else {
                NSLog("TokyoWalkingStabilizer: left legacy Host Analysis cache at \(legacyURL.path) because \(remainingItems.count) item(s) could not be moved without overwriting newer files.")
            }
        } catch {
            NSLog("TokyoWalkingStabilizer: failed to migrate legacy Host Analysis cache from \(legacyURL.path) to \(cacheRoot.path): \(error.localizedDescription)")
        }
    }

    private static func moveDirectoryContentsPreservingExistingFiles(from sourceURL: URL, to destinationURL: URL) throws {
        let itemURLs = try FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for itemURL in itemURLs {
            let destinationItemURL = destinationURL.appendingPathComponent(itemURL.lastPathComponent)
            let itemIsDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            var destinationIsDirectory = ObjCBool(false)
            let destinationExists = FileManager.default.fileExists(atPath: destinationItemURL.path, isDirectory: &destinationIsDirectory)

            if destinationExists {
                if itemIsDirectory && destinationIsDirectory.boolValue {
                    try moveDirectoryContentsPreservingExistingFiles(from: itemURL, to: destinationItemURL)
                    let remainingItems = try FileManager.default.contentsOfDirectory(atPath: itemURL.path)
                    if remainingItems.isEmpty {
                        try FileManager.default.removeItem(at: itemURL)
                    }
                } else {
                    NSLog("TokyoWalkingStabilizer: keeping legacy Host Analysis cache item \(itemURL.path) because \(destinationItemURL.path) already exists.")
                }
                continue
            }

            try FileManager.default.moveItem(at: itemURL, to: destinationItemURL)
        }
    }

    private static func fcpBundleRoot(containing url: URL) -> URL? {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if current.pathExtension == "fcpbundle" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private struct FCPEventRootResolution {
        let eventRoot: URL
        let sourceDescription: String
    }

    private struct FCPActiveLibraryEventResolution {
        let bundleRoot: URL
        let eventResolution: FCPEventRootResolution
        let securityScopedURL: URL?
    }

    private struct FCPActiveLibraryBundleCandidate {
        let bundleRoot: URL
        let securityScopedURL: URL?
    }

    private struct FCPActiveLibraryBundleSelection {
        let candidate: FCPActiveLibraryBundleCandidate
        let sourceDescription: String
    }

    private struct FCPActiveLibraryEventSelection {
        let candidate: FCPActiveLibraryBundleCandidate
        let eventResolution: FCPEventRootResolution
    }

    private struct FCPFinalCutLibrarySidebarSelection {
        let rawSelection: String
        let identifiers: [String]
    }

    private struct EventCacheIdentityIndex: Decodable {
        let entries: [EventCacheIdentityIndexEntry]
    }

    private struct EventCacheIdentityIndexEntry: Decodable {
        let cacheFileName: String
        let cacheIdentity: String?
    }

    private static func activeFinalCutLibraryEventRoot(
        expectedRange: HostAnalysisExpectedRange?,
        preferredCacheIdentity: String?,
        projectDocumentID: UInt?
    ) -> (resolution: FCPActiveLibraryEventResolution?, rejectReason: String) {
        let activeLibraries = activeFinalCutLibraryBundleURLs()
        os_log(
            "Active library resolver input documentID=%{public}@ expectedRange=%{public}@ candidates=%{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            projectDocumentIDDescription(projectDocumentID),
            expectedRangeDescription(expectedRange),
            activeLibraries.bundleURLs.map(\.bundleRoot.path).joined(separator: " | ")
        )
        if let activeRejectReason = activeLibraries.rejectReason {
            let recentLookup = recentFinalCutLibraryEventRootMatchingTokyoWalkingCacheIdentity(
                preferredCacheIdentity: preferredCacheIdentity
            )
            if let resolution = recentLookup.resolution {
                return (resolution, "")
            }
            return (
                nil,
                "\(activeRejectReason) \(recentLookup.rejectReason)"
            )
        }
        let bundleCandidates = activeLibraries.bundleURLs
        guard !bundleCandidates.isEmpty else {
            let recentLookup = recentFinalCutLibraryEventRootMatchingTokyoWalkingCacheIdentity(
                preferredCacheIdentity: preferredCacheIdentity
            )
            if let resolution = recentLookup.resolution {
                return (resolution, "")
            }
            return (nil, "Final Cut Pro active library list is empty. \(recentLookup.rejectReason)")
        }

        let selectedBundle: FCPActiveLibraryBundleSelection
        if bundleCandidates.count == 1, let bundleCandidate = bundleCandidates.first {
            selectedBundle = FCPActiveLibraryBundleSelection(
                candidate: bundleCandidate,
                sourceDescription: "single Final Cut Pro active library bookmark"
            )
        } else {
            let rangedSelection = activeFinalCutLibraryEventSelection(
                from: bundleCandidates,
                expectedRange: expectedRange
            )
            if let selection = rangedSelection.selection {
                for candidate in bundleCandidates where candidate.bundleRoot.path != selection.candidate.bundleRoot.path {
                    candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
                }
                return (
                    FCPActiveLibraryEventResolution(
                        bundleRoot: selection.candidate.bundleRoot,
                        eventResolution: selection.eventResolution,
                        securityScopedURL: selection.candidate.securityScopedURL
                    ),
                    ""
                )
            } else {
                let cacheIdentitySelection = activeFinalCutLibraryCacheIdentityEventSelection(
                    from: bundleCandidates,
                    preferredCacheIdentity: preferredCacheIdentity
                )
                if let selection = cacheIdentitySelection.selection {
                    for candidate in bundleCandidates where candidate.bundleRoot.path != selection.candidate.bundleRoot.path {
                        candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
                    }
                    return (
                        FCPActiveLibraryEventResolution(
                            bundleRoot: selection.candidate.bundleRoot,
                            eventResolution: selection.eventResolution,
                            securityScopedURL: selection.candidate.securityScopedURL
                        ),
                        ""
                    )
                }
                let sidebarSelection = activeFinalCutLibrarySidebarEventSelection(from: bundleCandidates)
                if let selection = sidebarSelection.selection {
                    for candidate in bundleCandidates where candidate.bundleRoot.path != selection.candidate.bundleRoot.path {
                        candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
                    }
                    return (
                        FCPActiveLibraryEventResolution(
                            bundleRoot: selection.candidate.bundleRoot,
                            eventResolution: selection.eventResolution,
                            securityScopedURL: selection.candidate.securityScopedURL
                        ),
                        ""
                    )
                }
                for candidate in bundleCandidates {
                    candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
                }
                return (
                    nil,
                    "Ambiguous active Final Cut libraries: \(bundleCandidates.map(\.bundleRoot.path).joined(separator: " | ")). \(rangedSelection.rejectReason) \(cacheIdentitySelection.rejectReason) \(sidebarSelection.rejectReason)"
                )
            }
        }
        let bundleCandidate = selectedBundle.candidate
        let bundleRoot = bundleCandidate.bundleRoot
        let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
        guard FileManager.default.fileExists(atPath: libraryMarkerURL.path) else {
            bundleCandidate.securityScopedURL?.stopAccessingSecurityScopedResource()
            return (nil, "Active Final Cut library marker is missing at \(libraryMarkerURL.path)")
        }
        guard let eventResolution = fcpEventRoot(
            containing: internalBundleHostAnalysisCacheRoot(in: bundleRoot),
            in: bundleRoot,
            expectedRange: expectedRange,
            preferredCacheIdentity: preferredCacheIdentity
        ) else {
            let sidebarSelection = activeFinalCutLibrarySidebarEventSelection(from: [bundleCandidate])
            if let selection = sidebarSelection.selection {
                return (
                    FCPActiveLibraryEventResolution(
                        bundleRoot: selection.candidate.bundleRoot,
                        eventResolution: selection.eventResolution,
                        securityScopedURL: selection.candidate.securityScopedURL
                    ),
                    ""
                )
            }
            bundleCandidate.securityScopedURL?.stopAccessingSecurityScopedResource()
            return (nil, "Ambiguous Event for active Final Cut library \(bundleRoot.path). \(sidebarSelection.rejectReason)")
        }
        return (
            FCPActiveLibraryEventResolution(
                bundleRoot: bundleRoot,
                eventResolution: FCPEventRootResolution(
                    eventRoot: eventResolution.eventRoot,
                    sourceDescription: "\(selectedBundle.sourceDescription) / \(eventResolution.sourceDescription)"
                ),
                securityScopedURL: bundleCandidate.securityScopedURL
            ),
            ""
        )
    }

    private static func activeFinalCutLibraryBundleURLs() -> (bundleURLs: [FCPActiveLibraryBundleCandidate], rejectReason: String?) {
        finalCutLibraryBundleURLs(
            preferenceKey: "FFActiveLibraries",
            sourceDescription: "active library"
        )
    }

    private static func recentFinalCutLibraryBundleURLs() -> (bundleURLs: [FCPActiveLibraryBundleCandidate], rejectReason: String?) {
        finalCutLibraryBundleURLs(
            preferenceKey: "FFRecentLibraries",
            sourceDescription: "recent library"
        )
    }

    private static func finalCutLibraryBundleURLs(
        preferenceKey: String,
        sourceDescription: String
    ) -> (bundleURLs: [FCPActiveLibraryBundleCandidate], rejectReason: String?) {
        var rejectionReasons: [String] = []
        for preferenceURL in finalCutPreferenceURLs() {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: preferenceURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                rejectionReasons.append("preferences missing at \(preferenceURL.path)")
                continue
            }
            do {
                let data = try Data(contentsOf: preferenceURL)
                var plistFormat = PropertyListSerialization.PropertyListFormat.binary
                guard let plist = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: &plistFormat
                ) as? [String: Any] else {
                    rejectionReasons.append("preferences plist is not a dictionary at \(preferenceURL.path)")
                    continue
                }
                guard let bookmarks = plist[preferenceKey] as? [Data] else {
                    rejectionReasons.append("\(preferenceKey) missing at \(preferenceURL.path)")
                    continue
                }
                var resolvedCandidates: [FCPActiveLibraryBundleCandidate] = []
                var bookmarkRejections: [String] = []
                for (index, bookmarkData) in bookmarks.enumerated() {
                    let resolvedBookmark = resolveActiveFinalCutLibraryBookmark(
                        bookmarkData,
                        index: index,
                        preferenceURL: preferenceURL
                    )
                    if let rejectReason = resolvedBookmark.rejectReason {
                        bookmarkRejections.append(rejectReason)
                    }
                    if let candidate = resolvedBookmark.candidate {
                        if let rejectReason = activeFinalCutLibraryCandidateRejectionReason(candidate, index: index) {
                            candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
                            bookmarkRejections.append(rejectReason)
                        } else {
                            resolvedCandidates.append(candidate)
                        }
                    }
                }
                let uniqueCandidates = uniqueStandardizedBundleCandidates(resolvedCandidates)
                os_log(
                    "Active library resolver read %{public}d %{public}@ bookmark(s) from %{public}@; resolved=%{public}@ rejects=%{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    bookmarks.count,
                    sourceDescription,
                    preferenceURL.path,
                    uniqueCandidates.map(\.bundleRoot.path).joined(separator: " | "),
                    bookmarkRejections.joined(separator: " | ")
                )
                if !uniqueCandidates.isEmpty {
                    return (uniqueCandidates, nil)
                }
                rejectionReasons.append("no usable \(preferenceKey) .fcpbundle bookmark in \(preferenceURL.path): \(bookmarkRejections.joined(separator: " | "))")
            } catch {
                rejectionReasons.append("preferences unreadable at \(preferenceURL.path): \(error.localizedDescription)")
            }
        }
        return ([], rejectionReasons.joined(separator: " ; "))
    }

    private static func recentFinalCutLibraryEventRootMatchingTokyoWalkingCacheIdentity(
        preferredCacheIdentity: String?
    ) -> (resolution: FCPActiveLibraryEventResolution?, rejectReason: String) {
        guard let preferredCacheIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredCacheIdentity.isEmpty
        else {
            return (nil, "Recent library lookup skipped because no saved Tokyo Walking cache identity is available.")
        }

        let recentLibraries = recentFinalCutLibraryBundleURLs()
        guard recentLibraries.rejectReason == nil else {
            return (nil, "Recent library lookup failed: \(recentLibraries.rejectReason ?? "preferences unavailable").")
        }
        let bundleCandidates = recentLibraries.bundleURLs
        guard !bundleCandidates.isEmpty else {
            return (nil, "Recent library lookup found no usable .fcpbundle bookmark.")
        }

        var matches: [FCPActiveLibraryEventSelection] = []
        var inspectedBundles: [String] = []
        for candidate in bundleCandidates {
            let bundleRoot = candidate.bundleRoot
            let eventRoots = topLevelEventRoots(in: bundleRoot)
            let analysisFilesEventRoots = eventRootsWithExistingAnalysisFiles(from: eventRoots)
            if let matchedEventRoot = eventRootMatchingTokyoWalkingCacheIdentity(
                preferredCacheIdentity,
                in: analysisFilesEventRoots
            ) {
                matches.append(FCPActiveLibraryEventSelection(
                    candidate: candidate,
                    eventResolution: FCPEventRootResolution(
                        eventRoot: matchedEventRoot,
                        sourceDescription: "recent Final Cut library saved Tokyo Walking cache identity"
                    )
                ))
                inspectedBundles.append("\(bundleRoot.path)(identityMatch:\(matchedEventRoot.lastPathComponent))")
            } else {
                inspectedBundles.append("\(bundleRoot.path)(identityMatch:none, analysisFiles:\(analysisFilesEventRoots.count))")
            }
        }

        if matches.count == 1, let match = matches.first {
            for candidate in bundleCandidates where candidate.bundleRoot.path != match.candidate.bundleRoot.path {
                candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
            }
            os_log(
                "Active library resolver selected recent bundle %{public}@ Event %{public}@ by saved Tokyo Walking cache identity.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                match.candidate.bundleRoot.path,
                match.eventResolution.eventRoot.path
            )
            return (
                FCPActiveLibraryEventResolution(
                    bundleRoot: match.candidate.bundleRoot,
                    eventResolution: match.eventResolution,
                    securityScopedURL: match.candidate.securityScopedURL
                ),
                ""
            )
        }

        for candidate in bundleCandidates {
            candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
        }
        if matches.isEmpty {
            return (
                nil,
                "Recent library lookup found no Event cache matching saved Tokyo Walking cache identity. inspected=\(inspectedBundles.joined(separator: " | "))"
            )
        }
        return (
            nil,
            "Recent library lookup found multiple Event caches matching saved Tokyo Walking cache identity: \(matches.map { "\($0.candidate.bundleRoot.path) -> \($0.eventResolution.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private static func resolveActiveFinalCutLibraryBookmark(
        _ bookmarkData: Data,
        index: Int,
        preferenceURL: URL
    ) -> (candidate: FCPActiveLibraryBundleCandidate?, rejectReason: String?) {
        let scopedResolution: (url: URL, isStale: Bool)?
        let scopedErrorDescription: String?
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
            scopedResolution = (url, isStale)
            scopedErrorDescription = nil
        } catch {
            scopedResolution = nil
            scopedErrorDescription = error.localizedDescription
            os_log(
                "Active library resolver could not resolve bookmark %{public}d from %{public}@ with security scope: %{public}@; trying regular resolution because Final Cut Pro may store regular active-library bookmarks.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                index,
                preferenceURL.path,
                error.localizedDescription
            )
        }

        let resolvedURL: URL
        let isStale: Bool
        let resolvedWithSecurityScopeOption: Bool
        if let scopedResolution {
            resolvedURL = scopedResolution.url
            isStale = scopedResolution.isStale
            resolvedWithSecurityScopeOption = true
        } else {
            do {
                var regularIsStale = false
                resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &regularIsStale
                ).standardizedFileURL
                isStale = regularIsStale
                resolvedWithSecurityScopeOption = false
            } catch {
                let scopedMessage = scopedErrorDescription.map { " security-scoped error: \($0);" } ?? ""
                return (
                    nil,
                    "bookmark \(index) could not be resolved:\(scopedMessage) regular error: \(error.localizedDescription)"
                )
            }
        }

        guard resolvedURL.pathExtension == "fcpbundle" else {
            return (nil, "bookmark \(index) resolved outside .fcpbundle: \(resolvedURL.path)")
        }
        if isStale {
            os_log(
                "Active library resolver accepted stale bookmark %{public}@ from %{public}@; filesystem validation will decide writability.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                resolvedURL.path,
                preferenceURL.path
            )
        }
        let didStartAccess = resolvedURL.startAccessingSecurityScopedResource()
        if didStartAccess {
            os_log(
                "Active library resolver started security-scoped access for %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                resolvedURL.path
            )
        } else if resolvedWithSecurityScopeOption {
            os_log(
                "Active library resolver resolved %{public}@ with security-scope option but did not receive a security-scoped lease; filesystem validation will decide writability.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                resolvedURL.path
            )
        } else {
            os_log(
                "Active library resolver resolved regular active library bookmark %{public}@ without a security-scoped lease; filesystem validation will decide writability.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                resolvedURL.path
            )
        }
        return (
            FCPActiveLibraryBundleCandidate(
                bundleRoot: resolvedURL,
                securityScopedURL: didStartAccess ? resolvedURL : nil
            ),
            nil
        )
    }

    private static func activeFinalCutLibraryCandidateRejectionReason(
        _ candidate: FCPActiveLibraryBundleCandidate,
        index: Int
    ) -> String? {
        let bundleRoot = candidate.bundleRoot.standardizedFileURL
        let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
        var markerIsDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: libraryMarkerURL.path, isDirectory: &markerIsDirectory),
              !markerIsDirectory.boolValue
        else {
            return "bookmark \(index) active library marker missing at \(libraryMarkerURL.path)"
        }

        let childURLs: [URL]
        do {
            childURLs = try FileManager.default.contentsOfDirectory(
                at: bundleRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return "bookmark \(index) active library bundle unreadable at \(bundleRoot.path): \(error.localizedDescription)"
        }

        let eventRoots = childURLs.filter { childURL in
            let childIsDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard childIsDirectory else {
                return false
            }
            let eventMarkerURL = childURL.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
            return FileManager.default.fileExists(atPath: eventMarkerURL.path)
        }
        if eventRoots.isEmpty {
            return "bookmark \(index) active library has no readable top-level Events at \(bundleRoot.path)"
        }
        return nil
    }

    private static func activeFinalCutLibraryEventSelection(
        from candidates: [FCPActiveLibraryBundleCandidate],
        expectedRange: HostAnalysisExpectedRange?
    ) -> (selection: FCPActiveLibraryEventSelection?, rejectReason: String) {
        guard let expectedRange, expectedRange.isValid else {
            return (nil, "No active Host Analysis range was available to disambiguate active libraries.")
        }

        var rangeMatches: [FCPActiveLibraryEventSelection] = []
        var inspectedBundles: [String] = []
        for candidate in candidates {
            let bundleRoot = candidate.bundleRoot
            let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
            guard FileManager.default.fileExists(atPath: libraryMarkerURL.path) else {
                inspectedBundles.append("\(bundleRoot.path)(missing CurrentVersion.flexolibrary)")
                continue
            }

            let eventRoots = topLevelEventRoots(in: bundleRoot)
            let analysisFilesEventRoots = eventRootsWithExistingAnalysisFiles(from: eventRoots)
            let matchedEventRoots = eventRootsMatchingExistingStabilizationAnalysis(
                expectedRange: expectedRange,
                in: analysisFilesEventRoots
            )
            inspectedBundles.append(
                "\(bundleRoot.path)(events:\(eventRoots.count), analysisFiles:\(analysisFilesEventRoots.count), stabilizationRangeMatches:\(matchedEventRoots.count))"
            )
            for matchedEventRoot in matchedEventRoots {
                rangeMatches.append(FCPActiveLibraryEventSelection(
                    candidate: candidate,
                    eventResolution: FCPEventRootResolution(
                        eventRoot: matchedEventRoot,
                        sourceDescription: "active Final Cut libraries FCP Stabilization range match"
                    )
                ))
            }
        }

        if rangeMatches.count == 1, let match = rangeMatches.first {
            os_log(
                "Active library resolver selected bundle %{public}@ Event %{public}@ by cross-library FCP Stabilization range match for %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                match.candidate.bundleRoot.path,
                match.eventResolution.eventRoot.path,
                expectedRangeDescription(expectedRange)
            )
            return (match, "")
        }
        if rangeMatches.isEmpty {
            return (
                nil,
                "No active library Event matched the Host Analysis range. inspected=\(inspectedBundles.joined(separator: " | "))"
            )
        }
        return (
            nil,
            "Multiple active library Events matched the Host Analysis range: \(rangeMatches.map { "\($0.candidate.bundleRoot.path) -> \($0.eventResolution.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private static func activeFinalCutLibraryCacheIdentityEventSelection(
        from candidates: [FCPActiveLibraryBundleCandidate],
        preferredCacheIdentity: String?
    ) -> (selection: FCPActiveLibraryEventSelection?, rejectReason: String) {
        guard let preferredCacheIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredCacheIdentity.isEmpty
        else {
            return (nil, "No saved Tokyo Walking cache identity was available for active-library disambiguation.")
        }

        var matches: [FCPActiveLibraryEventSelection] = []
        var inspectedBundles: [String] = []
        for candidate in candidates {
            let bundleRoot = candidate.bundleRoot
            let eventRoots = topLevelEventRoots(in: bundleRoot)
            let analysisFilesEventRoots = eventRootsWithExistingAnalysisFiles(from: eventRoots)
            if let matchedEventRoot = eventRootMatchingTokyoWalkingCacheIdentity(
                preferredCacheIdentity,
                in: analysisFilesEventRoots
            ) {
                matches.append(FCPActiveLibraryEventSelection(
                    candidate: candidate,
                    eventResolution: FCPEventRootResolution(
                        eventRoot: matchedEventRoot,
                        sourceDescription: "active Final Cut libraries saved Tokyo Walking cache identity"
                    )
                ))
                inspectedBundles.append("\(bundleRoot.path)(identityMatch:\(matchedEventRoot.lastPathComponent))")
            } else {
                inspectedBundles.append("\(bundleRoot.path)(identityMatch:none, analysisFiles:\(analysisFilesEventRoots.count))")
            }
        }

        if matches.count == 1, let match = matches.first {
            os_log(
                "Active library resolver selected bundle %{public}@ Event %{public}@ by saved Tokyo Walking cache identity.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                match.candidate.bundleRoot.path,
                match.eventResolution.eventRoot.path
            )
            return (match, "")
        }
        if matches.isEmpty {
            return (
                nil,
                "No active library Event matched saved Tokyo Walking cache identity. inspected=\(inspectedBundles.joined(separator: " | "))"
            )
        }
        return (
            nil,
            "Multiple active library Events matched saved Tokyo Walking cache identity: \(matches.map { "\($0.candidate.bundleRoot.path) -> \($0.eventResolution.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private static func activeFinalCutLibrarySidebarEventSelection(
        from candidates: [FCPActiveLibraryBundleCandidate]
    ) -> (selection: FCPActiveLibraryEventSelection?, rejectReason: String) {
        let sidebarLookup = finalCutLibrarySidebarSelection()
        guard let sidebarSelection = sidebarLookup.selection else {
            return (nil, "Final Cut Pro library sidebar selection unavailable: \(sidebarLookup.rejectReason)")
        }
        var matches: [FCPActiveLibraryEventSelection] = []
        var inspectedBundles: [String] = []
        for candidate in candidates {
            let bundleRoot = candidate.bundleRoot
            let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
            guard FileManager.default.fileExists(atPath: libraryMarkerURL.path) else {
                inspectedBundles.append("\(bundleRoot.path)(missing CurrentVersion.flexolibrary)")
                continue
            }
            let markerMatch = libraryMarkerContainsIdentifiers(sidebarSelection.identifiers, markerURL: libraryMarkerURL)
            guard markerMatch.containsAllIdentifiers else {
                inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:no: \(markerMatch.rejectReason))")
                continue
            }

            let eventLookup = eventRootForSidebarSelection(sidebarSelection, in: bundleRoot)
            guard let eventRoot = eventLookup.eventRoot else {
                inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:yes,event:no: \(eventLookup.rejectReason))")
                continue
            }
            inspectedBundles.append("\(bundleRoot.path)(sidebarIDs:yes,event:\(eventRoot.lastPathComponent))")
            matches.append(FCPActiveLibraryEventSelection(
                candidate: candidate,
                eventResolution: FCPEventRootResolution(
                    eventRoot: eventRoot,
                    sourceDescription: "Final Cut Pro library sidebar selection"
                )
            ))
        }

        if matches.count == 1, let match = matches.first {
            os_log(
                "Active library resolver selected bundle %{public}@ Event %{public}@ by Final Cut Pro library sidebar selection %{public}@ identifiers=%{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                match.candidate.bundleRoot.path,
                match.eventResolution.eventRoot.path,
                sidebarSelection.rawSelection,
                sidebarSelection.identifiers.joined(separator: ",")
            )
            return (match, "")
        }
        if matches.isEmpty {
            return (
                nil,
                "No active library matched Final Cut Pro library sidebar selection \(sidebarSelection.rawSelection). inspected=\(inspectedBundles.joined(separator: " | "))"
            )
        }
        return (
            nil,
            "Multiple active libraries matched Final Cut Pro library sidebar selection \(sidebarSelection.rawSelection): \(matches.map { "\($0.candidate.bundleRoot.path) -> \($0.eventResolution.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private static func finalCutLibrarySidebarSelection() -> (selection: FCPFinalCutLibrarySidebarSelection?, rejectReason: String) {
        var rejectionReasons: [String] = []
        for preferenceURL in finalCutPreferenceURLs() {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: preferenceURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                rejectionReasons.append("preferences missing at \(preferenceURL.path)")
                continue
            }
            do {
                let data = try Data(contentsOf: preferenceURL)
                var plistFormat = PropertyListSerialization.PropertyListFormat.binary
                guard let plist = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: &plistFormat
                ) as? [String: Any] else {
                    rejectionReasons.append("preferences plist is not a dictionary at \(preferenceURL.path)")
                    continue
                }
                guard let librarySidebar = plist["FFSidebarModuleLibrary"] as? [String: Any],
                      let rawSelections = librarySidebar["media sidebar selection"] as? [String],
                      let rawSelection = rawSelections.first(where: { !$0.isEmpty })
                else {
                    rejectionReasons.append("FFSidebarModuleLibrary media sidebar selection missing at \(preferenceURL.path)")
                    continue
                }
                let identifiers = uuidStrings(in: rawSelection)
                guard identifiers.count >= 2 else {
                    rejectionReasons.append("FFSidebarModuleLibrary media sidebar selection has fewer than two UUIDs at \(preferenceURL.path): \(rawSelection)")
                    continue
                }
                os_log(
                    "Active library resolver read Final Cut Pro library sidebar selection %{public}@ from %{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    rawSelection,
                    preferenceURL.path
                )
                return (
                    FCPFinalCutLibrarySidebarSelection(
                        rawSelection: rawSelection,
                        identifiers: identifiers
                    ),
                    ""
                )
            } catch {
                rejectionReasons.append("preferences unreadable at \(preferenceURL.path): \(error.localizedDescription)")
            }
        }
        return (nil, rejectionReasons.joined(separator: " ; "))
    }

    private static func uuidStrings(in string: String) -> [String] {
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.matches(in: string, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: string) else {
                return nil
            }
            return String(string[matchRange]).uppercased()
        }
    }

    private static func libraryMarkerContainsIdentifiers(
        _ identifiers: [String],
        markerURL: URL
    ) -> (containsAllIdentifiers: Bool, rejectReason: String) {
        do {
            let markerData = try Data(contentsOf: markerURL)
            for identifier in identifiers {
                let variants = Set([identifier, identifier.uppercased(), identifier.lowercased()])
                guard variants.contains(where: { markerData.range(of: Data($0.utf8)) != nil }) else {
                    return (false, "missing \(identifier)")
                }
            }
            return (true, "")
        } catch {
            return (false, "unreadable CurrentVersion.flexolibrary: \(error.localizedDescription)")
        }
    }

    private static func eventRootForEventIdentifier(
        _ eventIdentifier: String,
        in bundleRoot: URL
    ) -> (eventRoot: URL?, rejectReason: String) {
        let libraryMarkerURL = bundleRoot.appendingPathComponent("CurrentVersion.flexolibrary", isDirectory: false)
        let metadataLookup = eventMetadataBlobForEventIdentifier(eventIdentifier, libraryMarkerURL: libraryMarkerURL)
        guard let metadataData = metadataLookup.metadataData else {
            return (nil, metadataLookup.rejectReason)
        }
        let relativePathLookup = eventRelativePath(from: metadataData, eventIdentifier: eventIdentifier)
        guard let relativePath = relativePathLookup.relativePath else {
            return (nil, relativePathLookup.rejectReason)
        }
        let eventRoot = bundleRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
        let bundleRoot = bundleRoot.standardizedFileURL
        guard eventRoot.deletingLastPathComponent().standardizedFileURL.path == bundleRoot.path else {
            return (nil, "selected Event relativePath is not top-level in the active library: \(relativePath)")
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: eventRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return (nil, "selected Event root does not exist at \(eventRoot.path)")
        }
        let eventMarkerURL = eventRoot.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
        guard FileManager.default.fileExists(atPath: eventMarkerURL.path) else {
            return (nil, "selected Event marker is missing at \(eventMarkerURL.path)")
        }
        return (eventRoot, "")
    }

    private static func eventRootForSidebarSelection(
        _ selection: FCPFinalCutLibrarySidebarSelection,
        in bundleRoot: URL
    ) -> (eventRoot: URL?, rejectReason: String) {
        var matches: [(identifier: String, eventRoot: URL)] = []
        var rejectionReasons: [String] = []
        for identifier in selection.identifiers.reversed() {
            let lookup = eventRootForEventIdentifier(identifier, in: bundleRoot)
            if let eventRoot = lookup.eventRoot {
                matches.append((identifier, eventRoot))
            } else {
                rejectionReasons.append("\(identifier): \(lookup.rejectReason)")
            }
        }
        if matches.count == 1, let match = matches.first {
            return (match.eventRoot, "selected Event identifier \(match.identifier)")
        }
        if matches.isEmpty {
            return (
                nil,
                "no Event identifier in sidebar selection \(selection.rawSelection); \(rejectionReasons.joined(separator: " | "))"
            )
        }
        return (
            nil,
            "multiple Event identifiers in sidebar selection \(selection.rawSelection): \(matches.map { "\($0.identifier) -> \($0.eventRoot.path)" }.joined(separator: " | "))"
        )
    }

    private static func eventMetadataBlobForEventIdentifier(
        _ eventIdentifier: String,
        libraryMarkerURL: URL
    ) -> (metadataData: Data?, rejectReason: String) {
        var database: OpaquePointer?
        let openResult = libraryMarkerURL.path.withCString { path in
            sqlite3_open_v2(
                path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }
        guard openResult == SQLITE_OK, let database else {
            let message = sqliteErrorMessage(database)
            if let database {
                sqlite3_close(database)
            }
            return (nil, "could not open CurrentVersion.flexolibrary read-only at \(libraryMarkerURL.path): \(message)")
        }
        defer {
            sqlite3_close(database)
        }

        let sql = """
        SELECT md.ZDICTIONARYDATA
        FROM ZCOLLECTION c
        JOIN ZCOLLECTIONMD md ON c.ZMETADATA = md.Z_PK
        WHERE c.ZIDENTIFIER = ? COLLATE NOCASE AND c.ZTYPE = 'FFEventRecord'
        LIMIT 2
        """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            return (nil, "could not prepare Event metadata lookup: \(sqliteErrorMessage(database))")
        }
        defer {
            sqlite3_finalize(statement)
        }

        let bindResult = eventIdentifier.withCString { eventIdentifierCString in
            sqlite3_bind_text(statement, 1, eventIdentifierCString, -1, sqliteTransientDestructor)
        }
        guard bindResult == SQLITE_OK else {
            return (nil, "could not bind Event identifier \(eventIdentifier): \(sqliteErrorMessage(database))")
        }

        var blobs: [Data] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let byteCount = Int(sqlite3_column_bytes(statement, 0))
                guard byteCount > 0,
                      let bytes = sqlite3_column_blob(statement, 0)
                else {
                    return (nil, "Event metadata blob is empty for \(eventIdentifier)")
                }
                blobs.append(Data(bytes: bytes, count: byteCount))
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                return (nil, "could not step Event metadata lookup: \(sqliteErrorMessage(database))")
            }
        }

        if blobs.count == 1, let blob = blobs.first {
            return (blob, "")
        }
        if blobs.isEmpty {
            return (nil, "Event identifier \(eventIdentifier) not found in \(libraryMarkerURL.path)")
        }
        return (nil, "Event identifier \(eventIdentifier) matched multiple Event metadata rows in \(libraryMarkerURL.path)")
    }

    private static var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func sqliteErrorMessage(_ database: OpaquePointer?) -> String {
        guard let database,
              let message = sqlite3_errmsg(database)
        else {
            return "unknown SQLite error"
        }
        return String(cString: message)
    }

    private static func eventRelativePath(
        from metadataData: Data,
        eventIdentifier: String
    ) -> (relativePath: String?, rejectReason: String) {
        do {
            let allowedClasses: [AnyClass] = [
                NSDictionary.self,
                NSMutableDictionary.self,
                NSArray.self,
                NSMutableArray.self,
                NSString.self,
                NSNumber.self,
                NSData.self,
                NSMutableData.self,
                NSNull.self
            ]
            guard let dictionary = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: allowedClasses,
                from: metadataData
            ) as? NSDictionary else {
                return (nil, "Event metadata archive is not a dictionary for \(eventIdentifier)")
            }
            guard let relativePath = dictionary["relativePath"] as? String,
                  !relativePath.isEmpty
            else {
                return (nil, "Event metadata archive has no relativePath for \(eventIdentifier)")
            }
            return (relativePath, "")
        } catch {
            return (nil, "could not unarchive Event metadata for \(eventIdentifier): \(error.localizedDescription)")
        }
    }

    private static func finalCutPreferenceURLs() -> [URL] {
        let homeURL = realUserHomeDirectoryURL()
        return [
            homeURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)
                .appendingPathComponent("com.apple.FinalCut", isDirectory: true)
                .appendingPathComponent("Data", isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent("com.apple.FinalCut.plist", isDirectory: false),
            homeURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent("com.apple.FinalCut.plist", isDirectory: false)
        ]
    }

    private static func realUserHomeDirectoryURL() -> URL {
        if let passwd = getpwuid(getuid()),
           let homeDirectory = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static func uniqueStandardizedBundleCandidates(_ candidates: [FCPActiveLibraryBundleCandidate]) -> [FCPActiveLibraryBundleCandidate] {
        var seen = Set<String>()
        var unique: [FCPActiveLibraryBundleCandidate] = []
        for candidate in candidates {
            let standardizedURL = candidate.bundleRoot.standardizedFileURL
            if seen.insert(standardizedURL.path).inserted {
                unique.append(FCPActiveLibraryBundleCandidate(
                    bundleRoot: standardizedURL,
                    securityScopedURL: candidate.securityScopedURL
                ))
            } else {
                candidate.securityScopedURL?.stopAccessingSecurityScopedResource()
            }
        }
        return unique
    }

    private static func fcpEventRoot(
        containing url: URL,
        in bundleRoot: URL,
        expectedRange: HostAnalysisExpectedRange?,
        preferredCacheIdentity: String?
    ) -> FCPEventRootResolution? {
        let bundleRoot = bundleRoot.standardizedFileURL
        let eventRoots = topLevelEventRoots(in: bundleRoot)
        os_log(
            "Event cache resolver candidates in %{public}@: %{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            bundleRoot.path,
            eventRoots.map(eventCandidateDescription).joined(separator: " | ")
        )
        var current = url.standardizedFileURL
        var ancestorEventRoot: URL?
        while current.path != "/" && current.path.hasPrefix(bundleRoot.path) {
            if current.path != bundleRoot.path {
                let eventMarkerURL = current.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
                if FileManager.default.fileExists(atPath: eventMarkerURL.path) {
                    ancestorEventRoot = current
                }
            }
            if current.path == bundleRoot.path {
                break
            }
            current.deleteLastPathComponent()
        }
        if let ancestorEventRoot {
            os_log(
                "Event cache resolver selected ancestor Event %{public}@ for mediaFolderURL %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                ancestorEventRoot.path,
                url.path
            )
            return FCPEventRootResolution(
                eventRoot: ancestorEventRoot,
                sourceDescription: "FxProjectAPI media-folder ancestor"
            )
        }
        let analysisFilesEventRoots = eventRootsWithExistingAnalysisFiles(from: eventRoots)
        if analysisFilesEventRoots.count == 1,
           let analysisFilesEventRoot = analysisFilesEventRoots.first {
            os_log(
                "Event cache resolver selected the only Event with Analysis Files: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                analysisFilesEventRoot.path
            )
            return FCPEventRootResolution(
                eventRoot: analysisFilesEventRoot,
                sourceDescription: "single existing Event Analysis Files"
            )
        }
        if analysisFilesEventRoots.count > 1,
           let stabilizationMatch = eventRootMatchingExistingStabilizationAnalysis(
                expectedRange: expectedRange,
                in: analysisFilesEventRoots
           ) {
            os_log(
                "Event cache resolver selected Event %{public}@ by FCP Stabilization range match for %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                stabilizationMatch.path,
                expectedRangeDescription(expectedRange)
            )
            return FCPEventRootResolution(
                eventRoot: stabilizationMatch,
                sourceDescription: "FCP Stabilization range match"
            )
        }
        if analysisFilesEventRoots.count > 1,
           let cacheIdentityMatch = eventRootMatchingTokyoWalkingCacheIdentity(
                preferredCacheIdentity,
                in: analysisFilesEventRoots
           ) {
            os_log(
                "Event cache resolver selected Event %{public}@ by saved Tokyo Walking cache identity.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                cacheIdentityMatch.path
            )
            return FCPEventRootResolution(
                eventRoot: cacheIdentityMatch,
                sourceDescription: "saved Tokyo Walking cache identity"
            )
        }
        if eventRoots.count == 1,
           let onlyEventRoot = eventRoots.first {
            os_log(
                "Event cache resolver selected the only top-level Event: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                onlyEventRoot.path
            )
            return FCPEventRootResolution(
                eventRoot: onlyEventRoot,
                sourceDescription: "single top-level library Event"
            )
        }
        os_log(
            "Event cache resolver rejected ambiguous Event candidates. Analysis Files candidates=%{public}d total candidates=%{public}d expectedRange=%{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .error,
            analysisFilesEventRoots.count,
            eventRoots.count,
            expectedRangeDescription(expectedRange)
        )
        return nil
    }

    private static func eventRootMatchingTokyoWalkingCacheIdentity(
        _ preferredCacheIdentity: String?,
        in eventRoots: [URL]
    ) -> URL? {
        guard let preferredCacheIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredCacheIdentity.isEmpty
        else {
            return nil
        }

        var matches: [(eventRoot: URL, cacheFileName: String)] = []
        for eventRoot in eventRoots {
            let cacheRoot = eventHostAnalysisCacheRoot(in: eventRoot)
            let indexURL = cacheRoot.appendingPathComponent("host-analysis-index-v2.json", isDirectory: false)
            guard FileManager.default.fileExists(atPath: indexURL.path) else {
                continue
            }
            do {
                let data = try Data(contentsOf: indexURL)
                let index = try JSONDecoder().decode(EventCacheIdentityIndex.self, from: data)
                let storageURL = cacheRoot.appendingPathComponent("caches", isDirectory: true)
                for entry in index.entries where entry.cacheIdentity == preferredCacheIdentity {
                    let cacheURL = storageURL.appendingPathComponent(entry.cacheFileName, isDirectory: false)
                    if FileManager.default.fileExists(atPath: cacheURL.path) {
                        matches.append((eventRoot.standardizedFileURL, entry.cacheFileName))
                    } else {
                        os_log(
                            "Event cache resolver ignored stale Tokyo Walking cache identity entry in Event %{public}@ because cache file is missing: %{public}@.",
                            log: stabilizerHostAnalysisLog,
                            type: .default,
                            eventRoot.path,
                            entry.cacheFileName
                        )
                    }
                }
            } catch {
                os_log(
                    "Event cache resolver could not inspect Tokyo Walking cache index %{public}@: %{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .error,
                    indexURL.path,
                    error.localizedDescription
                )
            }
        }

        let uniqueMatches = uniqueEventCacheIdentityMatches(matches)
        if uniqueMatches.count == 1, let match = uniqueMatches.first {
            os_log(
                "Event cache resolver matched saved Tokyo Walking cache identity to Event %{public}@ file %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .default,
                match.eventRoot.path,
                match.cacheFileName
            )
            return match.eventRoot
        }
        if uniqueMatches.count > 1 {
            os_log(
                "Event cache resolver rejected saved Tokyo Walking cache identity because it matched multiple Events: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                uniqueMatches.map { "\($0.eventRoot.path)(\($0.cacheFileName))" }.joined(separator: " | ")
            )
        }
        return nil
    }

    private static func uniqueEventCacheIdentityMatches(
        _ matches: [(eventRoot: URL, cacheFileName: String)]
    ) -> [(eventRoot: URL, cacheFileName: String)] {
        var seen = Set<String>()
        var unique: [(eventRoot: URL, cacheFileName: String)] = []
        for match in matches {
            let eventRoot = match.eventRoot.standardizedFileURL
            guard seen.insert(eventRoot.path).inserted else {
                continue
            }
            unique.append((eventRoot, match.cacheFileName))
        }
        return unique
    }

    private static func eventRootsWithExistingAnalysisFiles(from eventRoots: [URL]) -> [URL] {
        eventRoots.filter { eventRoot in
            let analysisFilesURL = eventRoot.appendingPathComponent("Analysis Files", isDirectory: true)
            var isDirectory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: analysisFilesURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private static func eventRootMatchingExistingStabilizationAnalysis(
        expectedRange: HostAnalysisExpectedRange?,
        in eventRoots: [URL]
    ) -> URL? {
        let matchedRoots = eventRootsMatchingExistingStabilizationAnalysis(
            expectedRange: expectedRange,
            in: eventRoots
        )
        return matchedRoots.count == 1 ? matchedRoots[0] : nil
    }

    private static func eventRootsMatchingExistingStabilizationAnalysis(
        expectedRange: HostAnalysisExpectedRange?,
        in eventRoots: [URL]
    ) -> [URL] {
        guard let expectedRange, expectedRange.isValid else {
            return []
        }
        let startKey = StabilizerHostAnalysisStore.timeKey(expectedRange.startSeconds)
        let endKey = StabilizerHostAnalysisStore.timeKey(expectedRange.endSeconds)
        return eventRoots.filter { eventRoot in
            stabilizationAnalysisDirectoryNames(in: eventRoot).contains { name in
                stabilizationAnalysisName(name, matchesStartKey: startKey, endKey: endKey)
            }
        }
    }

    private static func stabilizationAnalysisDirectoryNames(in eventRoot: URL) -> [String] {
        let stabilizationURL = eventRoot
            .appendingPathComponent("Analysis Files", isDirectory: true)
            .appendingPathComponent("Stabilization", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: stabilizationURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? url.lastPathComponent : nil
        }
    }

    private static func stabilizationAnalysisName(_ name: String, matchesStartKey startKey: Int64, endKey: Int64) -> Bool {
        let pattern = #"(-?\d+)-(-?\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        let matches = expression.matches(in: name, range: range)
        return matches.contains { match in
            guard match.numberOfRanges >= 3,
                  let startRange = Range(match.range(at: 1), in: name),
                  let endRange = Range(match.range(at: 2), in: name),
                  let candidateStart = Int64(String(name[startRange])),
                  let candidateEnd = Int64(String(name[endRange]))
            else {
                return false
            }
            return abs(candidateStart - startKey) <= 1
                && abs(candidateEnd - endKey) <= 1
        }
    }

    private static func eventCandidateDescription(_ eventRoot: URL) -> String {
        let analysisFilesURL = eventRoot.appendingPathComponent("Analysis Files", isDirectory: true)
        let hasAnalysisFiles = FileManager.default.fileExists(atPath: analysisFilesURL.path)
        let stabilizationCount = stabilizationAnalysisDirectoryNames(in: eventRoot).count
        return "\(eventRoot.lastPathComponent)(analysisFiles:\(hasAnalysisFiles ? "yes" : "no"), stabilization:\(stabilizationCount))"
    }

    private static func expectedRangeDescription(_ expectedRange: HostAnalysisExpectedRange?) -> String {
        guard let expectedRange, expectedRange.isValid else {
            return "none"
        }
        return "start\(StabilizerHostAnalysisStore.timeKey(expectedRange.startSeconds))-end\(StabilizerHostAnalysisStore.timeKey(expectedRange.endSeconds))-duration\(StabilizerHostAnalysisStore.timeKey(expectedRange.durationSeconds))"
    }

    private static func topLevelEventRoots(in bundleRoot: URL) -> [URL] {
        let bundleRoot = bundleRoot.standardizedFileURL
        let childURLs: [URL]
        do {
            childURLs = try FileManager.default.contentsOfDirectory(
                at: bundleRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            os_log(
                "Event cache resolver could not list active library bundle %{public}@: %{public}@.",
                log: stabilizerHostAnalysisLog,
                type: .error,
                bundleRoot.path,
                error.localizedDescription
            )
            return []
        }
        return childURLs
            .filter { childURL in
                let childIsDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard childIsDirectory else {
                    return false
                }
                let eventMarkerURL = childURL.appendingPathComponent("CurrentVersion.fcpevent", isDirectory: false)
                return FileManager.default.fileExists(atPath: eventMarkerURL.path)
            }
            .map { $0.standardizedFileURL }
            .sorted { $0.path < $1.path }
    }

    private static func expectedInputRange(from state: StabilizerPluginState) -> HostAnalysisExpectedRange? {
        let range = HostAnalysisExpectedRange(
            startSeconds: state.inputRangeStartSeconds,
            durationSeconds: state.inputRangeDurationSeconds,
            frameDurationSeconds: state.inputFrameDurationSeconds
        )
        return range.isValid ? range : nil
    }

    private func currentRenderExpectedRange(from state: StabilizerPluginState) -> HostAnalysisExpectedRange? {
        Self.expectedInputRange(from: state) ?? currentInputRange() ?? hostAnalysisStore.activeExpectedRange
    }

    private static func pluginState(from data: Data?) -> StabilizerPluginState? {
        guard let data,
              data.count >= MemoryLayout<StabilizerPluginState>.size else {
            return nil
        }
        return data.withUnsafeBytes { pointer in
            pointer.bindMemory(to: StabilizerPluginState.self).baseAddress?.pointee
        }
    }

    private static func sourceRequestTime(for renderTime: CMTime, pluginState data: Data?) -> (time: CMTime, clamped: Bool) {
        guard let state = pluginState(from: data) else {
            return (renderTime, false)
        }
        return sourceRequestTime(for: renderTime, state: state)
    }

    private static func sourceRequestTime(for renderTime: CMTime, state: StabilizerPluginState) -> (time: CMTime, clamped: Bool) {
        guard let range = expectedInputRange(from: state) else {
            return (renderTime, false)
        }
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let frameDurationSeconds = range.frameDurationSeconds
        guard renderSeconds.isFinite,
              frameDurationSeconds.isFinite,
              frameDurationSeconds > 0.0
        else {
            return (renderTime, false)
        }

        let startSeconds = range.startSeconds
        let endSeconds = range.endSeconds
        let lastFrameSeconds = max(startSeconds, endSeconds - frameDurationSeconds)
        let toleranceSeconds = max(1.0 / 600.0, frameDurationSeconds * 1.5)
        let clampedSeconds: Double
        if renderSeconds < startSeconds && renderSeconds >= startSeconds - toleranceSeconds {
            clampedSeconds = startSeconds
        } else if renderSeconds > lastFrameSeconds && renderSeconds <= endSeconds + toleranceSeconds {
            clampedSeconds = lastFrameSeconds
        } else {
            clampedSeconds = renderSeconds
        }
        guard abs(clampedSeconds - renderSeconds) > 1e-9 else {
            return (renderTime, false)
        }

        let preferredTimescale = renderTime.timescale > 0 ? renderTime.timescale : 600
        return (CMTime(seconds: clampedSeconds, preferredTimescale: preferredTimescale), true)
    }

    private func requestedSampleScalePercent(at time: CMTime) -> Double {
        var sampleScale = StabilizerSampleScale.defaultScale.rawValue
        if let paramAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6 {
            paramAPI.getIntValue(&sampleScale, fromParameter: ParameterID.sampleScale.rawValue, at: time)
        }
        return StabilizerSampleScale.scale(for: sampleScale).percent
    }

    private func requestedSampleScalePercent(for expectedRange: HostAnalysisExpectedRange?) -> Double {
        guard let expectedRange,
              expectedRange.startSeconds.isFinite
        else {
            return requestedSampleScalePercent(at: .zero)
        }
        return requestedSampleScalePercent(at: CMTime(seconds: expectedRange.startSeconds, preferredTimescale: 600))
    }

    private func publishHostAnalysisRenderDiagnostics(
        frameCount: Int,
        panSmoothSeconds: Double,
        autoTransform: StabilizerAutoTransform,
        autoCropFraming: AutoCropFraming,
        appliedPixelOffset: vector_float2,
        appliedRotationRadians: Float
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        renderDiagnosticsLogLock.lock()
        let shouldPublish = now - lastRenderDiagnosticStatusWallTime >= 0.5
        if shouldPublish {
            lastRenderDiagnosticStatusWallTime = now
        }
        renderDiagnosticsLogLock.unlock()
        guard shouldPublish else {
            return
        }

        let cameraJitterPixelOffset = autoTransform.microPixelOffset
            + autoTransform.macroJitterPixelOffset
            + autoTransform.trajectoryMicroJitterPixelOffset
            + autoTransform.trajectoryContinuityPixelOffset
            + autoTransform.cameraRigidPixelOffset
        let cameraJitterRotation = autoTransform.microJitterRotationDegrees
            + autoTransform.macroJitterRotationDegrees
            + autoTransform.cameraRigidRotationDegrees
        let cameraJitterConfidence = max(
            max(autoTransform.microConfidence, autoTransform.macroJitterConfidence),
            max(autoTransform.lensFarFieldRigidShakeSupport, autoTransform.lensFarFieldRigidRollSupport)
        )
        let cameraJitterEffectiveX = max(autoTransform.effectiveMicroJitterStrength.x, autoTransform.effectiveMacroJitterStrength.x)
        let cameraJitterEffectiveY = max(autoTransform.effectiveMicroJitterStrength.y, autoTransform.effectiveMacroJitterStrength.y)
        let cameraJitterEffectiveRotation = max(autoTransform.effectiveMicroJitterStrength.z, autoTransform.effectiveMacroJitterStrength.z)
        let cropTelemetry = autoCropFraming.telemetry
        let cropMergeSuffix = cropTelemetry.mergeBypassed ? " bypass" : ""
        let status = String(
            format: "Ready (%d) | FxPlug %@ | warp q %.2f shear %.4f %.4f yp %.4f %.4f persp %.4f %.4f | lens %@ %@ %@ q %.2f x %.2f y %.2f r %.3f yp %.5f %.5f band %.2f T %.2f %.2f R %.2f %.2f M %.2f %.2f | turn %.1fs q %.2f smooth %d@%.2fs | X %.1f Y %.1f R %.2f | raw X %.1f Y %.1f R %.2f | smooth dX %.1f dY %.1f dR %.2f | track q %.2f walk q %.2f motion q %.2f blur %.2f resid %.4f | camera X %.3f Y %.3f R %.3f q %.2f eff X %.2f Y %.2f R %.2f | blocks %d/%d edge %d/%d | x turn %.1f camera %.1f | y camera %.1f | crop z %.3f miss %d worst %.4f/%.4f@%.1f merge %d/%d%@",
            frameCount,
            tokyoWalkingStabilizerVersion,
            autoTransform.warpConfidence,
            autoTransform.shear.x,
            autoTransform.shear.y,
            autoTransform.yawPitchProxy.x,
            autoTransform.yawPitchProxy.y,
            autoTransform.perspective.x,
            autoTransform.perspective.y,
            Self.lensShakeAxisDescription(autoTransform.lensShakeAxisMask),
            Self.lensShakeReasonDescription(autoTransform.lensShakeReasonCode),
            Self.lensBandCorrectionModelDescription(autoTransform.lensBandModelMask),
            autoTransform.lensShakeSupport,
            autoTransform.lensShakePixelOffset.x,
            autoTransform.lensShakePixelOffset.y,
            autoTransform.lensShakeRotationDegrees,
            autoTransform.lensShakeYawPitch.x,
            autoTransform.lensShakeYawPitch.y,
            autoTransform.lensBandWarpSupport,
            autoTransform.lensBandTopOffset.x,
            autoTransform.lensBandTopOffset.y,
            autoTransform.lensBandRidgeOffset.x,
            autoTransform.lensBandRidgeOffset.y,
            autoTransform.lensBandMidOffset.x,
            autoTransform.lensBandMidOffset.y,
            panSmoothSeconds,
            autoTransform.turnConfidence,
            autoTransform.temporalSmoothingSampleCount,
            autoTransform.temporalSmoothingWindowSeconds,
            appliedPixelOffset.x,
            appliedPixelOffset.y,
            appliedRotationRadians * 180.0 / .pi,
            autoTransform.rawPixelOffset.x,
            autoTransform.rawPixelOffset.y,
            autoTransform.rawRotationDegrees,
            autoTransform.temporalSmoothingPixelDelta.x,
            autoTransform.temporalSmoothingPixelDelta.y,
            autoTransform.temporalSmoothingRotationDelta,
            autoTransform.trackingConfidence,
            autoTransform.walkingTrackingConfidence,
            autoTransform.motionConfidence,
            autoTransform.blurAmount,
            autoTransform.residual,
            cameraJitterPixelOffset.x,
            cameraJitterPixelOffset.y,
            cameraJitterRotation,
            cameraJitterConfidence,
            cameraJitterEffectiveX,
            cameraJitterEffectiveY,
            cameraJitterEffectiveRotation,
            autoTransform.acceptedBlockCount,
            autoTransform.totalBlockCount,
            autoTransform.searchRadiusHitCount,
            autoTransform.searchRadiusTotalCount,
            autoTransform.macroPixelOffset.x,
            cameraJitterPixelOffset.x,
            cameraJitterPixelOffset.y,
            autoCropFraming.scale,
            cropTelemetry.missCount,
            cropTelemetry.worstPlannedScale,
            cropTelemetry.worstRequiredScale,
            cropTelemetry.worstSeconds ?? -1.0,
            cropTelemetry.mergedCount,
            cropTelemetry.mergeClusterCount,
            cropMergeSuffix
        )
        publishHostAnalysisStatus(statusOverride: status)
    }

    private func logDebugOverlayRenderTruthIfNeeded(
        debugOverlayActive: Bool,
        transformEnabled: Bool,
        renderUsesPreparedAnalysis: Bool,
        renderSourceIsProxy: Bool,
        renderTime: CMTime,
        analysisRenderTime: CMTime?,
        frameCount: Int,
        cacheIdentityShort: String,
        autoTransform: StabilizerAutoTransform,
        autoCropFraming: AutoCropFraming,
        metrics: StabilizerDebugOverlayMetrics,
        previewWarmupDecision: RenderPreviewWarmupDecision
    ) {
        guard debugOverlayActive,
              transformEnabled,
              renderUsesPreparedAnalysis,
              let analysisRenderTime
        else {
            return
        }
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let analysisSeconds = CMTimeGetSeconds(analysisRenderTime)
        guard renderSeconds.isFinite,
              analysisSeconds.isFinite
        else {
            return
        }

        let bucket = Int64((analysisSeconds * 2.0).rounded(.down))
        let now = Date.timeIntervalSinceReferenceDate
        renderDiagnosticsLogLock.lock()
        let shouldLog = lastRenderDiagnosticsLogBucket != bucket
            && now - lastRenderDiagnosticsLogWallTime >= 0.35
        if shouldLog {
            lastRenderDiagnosticsLogBucket = bucket
            lastRenderDiagnosticsLogWallTime = now
        }
        renderDiagnosticsLogLock.unlock()
        guard shouldLog else {
            return
        }

        os_log(
            "Debug Overlay runtime truth | FxPlug %{public}@ | render %.3f analysis %.3f | prepared yes | stabilization active | previewWarming %{public}@ reason %{public}@ | overlay active | proxy %{public}@ | identity %{public}@ | frames %{public}d | X %.2f Y %.2f R %.3f | raw X %.2f Y %.2f R %.3f | MICRO %.3f %.3f %.3f conf %.2f eff %.2f %.2f %.2f rawCorr %.3f %.3f limitedCorr %.3f %.3f pulseLimited %.3f %.3f | MACRO %.2f %.2f %.2f conf %.2f eff %.2f %.2f %.2f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            renderSeconds,
            analysisSeconds,
            previewWarmupDecision.active ? "yes" : "no",
            previewWarmupDecision.reason,
            renderSourceIsProxy ? "yes" : "no",
            cacheIdentityShort,
            frameCount,
            autoTransform.pixelOffset.x,
            autoTransform.pixelOffset.y,
            autoTransform.rotationDegrees,
            autoTransform.rawPixelOffset.x,
            autoTransform.rawPixelOffset.y,
            autoTransform.rawRotationDegrees,
            autoTransform.microImpulse.x,
            autoTransform.microImpulse.y,
            autoTransform.microImpulse.z,
            autoTransform.microConfidence,
            autoTransform.effectiveMicroJitterStrength.x,
            autoTransform.effectiveMicroJitterStrength.y,
            autoTransform.effectiveMicroJitterStrength.z,
            autoTransform.rawMicroCorrection.x,
            autoTransform.rawMicroCorrection.y,
            autoTransform.limitedMicroCorrection.x,
            autoTransform.limitedMicroCorrection.y,
            autoTransform.microPulseLimited.x,
            autoTransform.microPulseLimited.y,
            autoTransform.macroJitterPixelOffset.x,
            autoTransform.macroJitterPixelOffset.y,
            autoTransform.macroJitterRotationDegrees,
            autoTransform.macroJitterConfidence,
            autoTransform.effectiveMacroJitterStrength.x,
            autoTransform.effectiveMacroJitterStrength.y,
            autoTransform.effectiveMacroJitterStrength.z
        )
        os_log(
            "Debug Overlay bars motion | FxPlug %{public}@ | X OFFSET %.3f Y OFFSET %.3f ROLL %.3f CROP %.3f TURN %.3f MAJIT %.3f MIJIT %.3f FAR WARP %.3f SMOOTH %.3f CROP X %.2f CROP Y %.2f CROP MISS %d WORST %.4f/%.4f MERGE %d/%d %{public}@",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            metrics.xOffset,
            metrics.yOffset,
            metrics.roll,
            metrics.crop,
            metrics.turn,
            metrics.macroJitter,
            metrics.microJitter,
            metrics.farFieldWarp,
            metrics.smoothing,
            autoCropFraming.positionPixels.x,
            autoCropFraming.positionPixels.y,
            autoCropFraming.telemetry.missCount,
            autoCropFraming.telemetry.worstPlannedScale,
            autoCropFraming.telemetry.worstRequiredScale,
            autoCropFraming.telemetry.mergedCount,
            autoCropFraming.telemetry.mergeClusterCount,
            autoCropFraming.telemetry.mergeBypassed ? "bypass" : "ok"
        )
        os_log(
            "Debug Overlay bars confidence | FxPlug %{public}@ | TRK %.3f WLK %.3f SHRP %.3f RES %.3f %{public}@ HIT %.3f %{public}@ T CONF %.3f MA CONF %.3f MI CONF %.3f W CONF %.3f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            metrics.trackingQuality,
            metrics.walkingQuality,
            metrics.sharpnessQuality,
            metrics.residualQuality,
            metrics.residualQualityAvailable ? "available" : "unavailable",
            metrics.searchRadiusHeadroomQuality,
            metrics.searchRadiusHeadroomAvailable ? "available" : "unavailable",
            metrics.turnConfidence,
            metrics.macroConfidence,
            metrics.microConfidence,
            metrics.warpConfidence
        )
    }

    private static func hostAnalysisStatusText(_ status: String) -> String {
        if status.contains("FxPlug \(tokyoWalkingStabilizerVersion)") {
            return status
        }
        return "\(status) | FxPlug \(tokyoWalkingStabilizerVersion)"
    }

    private static func shortRenderCacheIdentity(_ identity: String?) -> String {
        guard let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identity.isEmpty
        else {
            return "none"
        }
        if identity.count <= 18 {
            return identity
        }
        return "\(identity.prefix(8))...\(identity.suffix(6))"
    }

    func scheduleInputs(_ inputImageRequests: AutoreleasingUnsafeMutablePointer<NSArray?>?, withPluginState pluginState: Data?, at renderTime: CMTime) throws {
        var requests: [FxImageTileRequest] = []
        let sourceRequest = Self.sourceRequestTime(for: renderTime, pluginState: pluginState)
        if sourceRequest.clamped {
            NSLog(
                "TokyoWalkingStabilizer: clamped source request time from %.6f to %.6f to keep clip-edge render inside the input range.",
                CMTimeGetSeconds(renderTime),
                CMTimeGetSeconds(sourceRequest.time)
            )
        }
        if let current = FxImageTileRequest(
            source: kFxImageTileRequestSourceEffectClip,
            time: sourceRequest.time,
            includeFilters: true,
            parameterID: 0
        ) {
            requests.append(current)
        }

        inputImageRequests?.pointee = requests as NSArray
    }

    func destinationImageRect(_ destinationImageRect: UnsafeMutablePointer<FxRect>, sourceImages: [FxImageTile], destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        destinationImageRect.pointee = destinationImage.imagePixelBounds
    }

    func sourceTileRect(_ sourceTileRect: UnsafeMutablePointer<FxRect>, sourceImageIndex: UInt, sourceImages: [FxImageTile], destinationTileRect: FxRect, destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        let index = Int(sourceImageIndex)
        if sourceImages.indices.contains(index) {
            sourceTileRect.pointee = sourceImages[index].imagePixelBounds
        } else {
            sourceTileRect.pointee = destinationTileRect
        }
    }

    private func cameraRigidFinalLimitTransform(
        _ source: StabilizerAutoTransform,
        outputSize: vector_float2,
        state: StabilizerPluginState,
        masterStrength: Float
    ) -> StabilizerAutoTransform {
        guard masterStrength > 0.0001 else {
            return source
        }
        let xLimit = outputSize.x * Float(min(max(state.cameraJitterXStrength, 0.0), 5.0) / 100.0)
        let yLimit = outputSize.y * Float(min(max(state.cameraJitterYStrength, 0.0), 5.0) / 100.0)
        let rollLimit = Float(min(max(state.cameraJitterRotationStrength, 0.0), 2.0))
        var limited = source
        let appliedRigidOffset = source.cameraRigidPixelOffset * masterStrength
        let clampedRigidOffset = vector_float2(
            min(max(appliedRigidOffset.x, -xLimit), xLimit),
            min(max(appliedRigidOffset.y, -yLimit), yLimit)
        )
        let rigidOffsetDelta = (clampedRigidOffset - appliedRigidOffset) / masterStrength
        limited.cameraRigidPixelOffset += rigidOffsetDelta
        limited.pixelOffset += rigidOffsetDelta
        let appliedRigidRoll = source.cameraRigidRotationDegrees * masterStrength
        let clampedRigidRoll = min(max(appliedRigidRoll, -rollLimit), rollLimit)
        let rigidRollDelta = (clampedRigidRoll - appliedRigidRoll) / masterStrength
        limited.cameraRigidRotationDegrees += rigidRollDelta
        limited.rotationDegrees += rigidRollDelta
        return limited
    }

    func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile], pluginState: Data?, at renderTime: CMTime) throws {
        let renderStartedAt = CFAbsoluteTimeGetCurrent()
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let renderTimeLabel = renderSeconds.isFinite ? String(format: "%.3f", renderSeconds) : "invalid"
        guard let state = Self.pluginState(from: pluginState) else {
            logRenderEarlyExitIfChanged("missing plugin state at render \(renderTimeLabel)")
            return
        }
        guard sourceImages.indices.contains(0) else {
            logRenderEarlyExitIfChanged("missing effect clip source image at render \(renderTimeLabel); source count \(sourceImages.count)")
            hostAnalysisStore.noteMediaLinkInvalidForRender(
                reason: "Final Cut Pro did not provide an effect clip source image for render."
            )
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: hostAnalysisStore.renderInvalidationToken,
                revisionForce: true,
                currentRenderRevision: state.renderRevision
            )
            return
        }
        let sourceImage = sourceImages[0]
        if let unavailableReason = StabilizerOriginalMediaPolicy.sourceUnavailableReason(for: sourceImage) {
            logRenderEarlyExitIfChanged("source unavailable at render \(renderTimeLabel): \(unavailableReason)")
            hostAnalysisStore.noteSourceUnavailableForRender(reason: unavailableReason)
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: hostAnalysisStore.renderInvalidationToken,
                revisionForce: true,
                currentRenderRevision: state.renderRevision
            )
            return
        }

        let deviceCache = MetalDeviceCache.deviceCache
        let pixelFormat = MetalDeviceCache.fxMTLPixelFormat(for: destinationImage)
        let commandQueue = deviceCache.commandQueue(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat)
        let device = deviceCache.device(with: sourceImage.deviceRegistryID)
        let inputTexture = device.flatMap { sourceImage.metalTexture(for: $0) }
        let outputTexture = device.flatMap { destinationImage.metalTexture(for: $0) }
        let pipelineState = deviceCache.pipelineState(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat)
        let commandBuffer = commandQueue?.makeCommandBuffer()
        guard
            let commandQueue,
            let inputTexture,
            let outputTexture,
            let pipelineState,
            let commandBuffer
        else {
            let reason = "Metal resources unavailable at render \(renderTimeLabel): queue=\(commandQueue != nil ? "yes" : "no") device=\(device != nil ? "yes" : "no") input=\(inputTexture != nil ? "yes" : "no") output=\(outputTexture != nil ? "yes" : "no") pipeline=\(pipelineState != nil ? "yes" : "no") commandBuffer=\(commandBuffer != nil ? "yes" : "no")"
            logRenderEarlyExitIfChanged(reason)
            NSLog("TokyoWalkingStabilizer: render skipped because \(reason).")
            return
        }

        let outputWidth = destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left
        let outputHeight = destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom
        let halfOutputWidth = Float(outputWidth) * 0.5
        let halfOutputHeight = Float(outputHeight) * 0.5
        var viewportSize = simd_uint2(UInt32(outputWidth), UInt32(outputHeight))
        let masterStrength = Float(max(0.0, state.strength))
        let transformEnabled = masterStrength > 0.0001
        var autoTransform: StabilizerAutoTransform
        var activePreparedAnalysis: StabilizerPreparedAnalysis?
        var activeAnalysisRenderTime: CMTime?
        var renderSourceIsProxy = false
        var renderSourceFrameInfo = Self.renderSourceFrameInfoDescription(
            sourceImage: sourceImage,
            preparedAnalysis: nil
        )
        renderSourceIsProxy = Self.renderSourceAppearsProxy(
            sourceImage: sourceImage,
            preparedAnalysis: nil
        )
        var renderUsesPreparedAnalysis = false
        let expectedRange = currentRenderExpectedRange(from: state)
        let preferredCacheIdentity = currentPreferredHostAnalysisCacheIdentity()
        let correctionStrengths = StabilizerCorrectionStrengths(
            cameraJitterX: state.cameraJitterXStrength,
            cameraJitterY: state.cameraJitterYStrength,
            cameraJitterRotation: state.cameraJitterRotationStrength,
            farFieldWarp: state.farFieldWarpStrength,
            turnSmoothingZoom: state.turnSmoothingZoom,
            turnViewportStrength: state.turnSmoothingZoom,
            turnTransitionWindowSeconds: state.turnTransitionWindow,
            turnIdleReleaseSeconds: Self.autoCropTransitionDurationSeconds(state.autoCropTransitionDuration)
        )
        // TURN is rendered only in viewport/crop space.  Build one canonical
        // full-authority trajectory for every non-zero TURN value so the
        // ordinary transform and Auto Crop preparation share the same cache.
        // Apply the UI strength exactly once after sampling that trajectory.
        let playbackTrajectoryStrengths = Self.fullTurnAnalysisStrengths(correctionStrengths)
        let configuredProjectBundleCache = transformEnabled
            ? configureProjectBundleCacheDirectory(markUnavailable: false, expectedRange: expectedRange)
            : false
        var storeSnapshot = hostAnalysisStore.renderSnapshot
        let hasCompletedHostAnalysis = storeSnapshot.hasCompletedAnalysis
        let hasPreparedHostAnalysis = storeSnapshot.hasPreparedAnalysis
        var renderCacheIdentity: String?
        var renderStoreRevision = storeSnapshot.revision
        let canUseHostAnalysisStoreForRender = transformEnabled
            && (hasCompletedHostAnalysis || hasPreparedHostAnalysis || configuredProjectBundleCache)
        let setupFinishedAt = CFAbsoluteTimeGetCurrent()
        let analysisLookupStartedAt = setupFinishedAt
        var analysisLookupFinishedAt = analysisLookupStartedAt
        var transformStartedAt = analysisLookupStartedAt
        var transformFinishedAt = analysisLookupStartedAt
        if transformEnabled,
           canUseHostAnalysisStoreForRender,
           let preparedAnalysis = hostAnalysisStore.preparedAnalysisForRender(
               validating: sourceImage,
               at: renderTime,
               preferredCacheIdentity: preferredCacheIdentity,
               expectedRange: expectedRange
           ) {
            analysisLookupFinishedAt = CFAbsoluteTimeGetCurrent()
            storeSnapshot = hostAnalysisStore.renderSnapshot
            renderUsesPreparedAnalysis = true
            activePreparedAnalysis = preparedAnalysis
            renderCacheIdentity = storeSnapshot.activeCacheIdentity
            renderStoreRevision = storeSnapshot.revision
            publishHostAnalysisCacheIdentityOnMain(renderCacheIdentity, force: false)
            let analysisRenderTime = hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            activeAnalysisRenderTime = analysisRenderTime
            renderSourceIsProxy = Self.renderSourceAppearsProxy(
                sourceImage: sourceImage,
                preparedAnalysis: preparedAnalysis
            )
            renderSourceFrameInfo = Self.renderSourceFrameInfoDescription(
                sourceImage: sourceImage,
                preparedAnalysis: preparedAnalysis
            )
            transformStartedAt = CFAbsoluteTimeGetCurrent()
            let playbackPreparationCacheIdentity = renderCacheIdentity
            let playbackTrajectoryPrepared: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.publishPlaybackPreparationInvalidationOnMain(
                    cacheIdentity: playbackPreparationCacheIdentity,
                    reason: "playback trajectory prepared"
                )
            }
            autoTransform = Self.cachedAutoTransform(
                preparedAnalysis: preparedAnalysis,
                renderTime: analysisRenderTime,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: 0.0,
                strengths: playbackTrajectoryStrengths,
                analysisRevision: renderStoreRevision,
                cacheIdentity: renderCacheIdentity,
                playbackMode: true,
                playbackPreparationScope: playbackPreparationScope,
                onPlaybackPreparationReady: playbackTrajectoryPrepared
            )
            transformFinishedAt = CFAbsoluteTimeGetCurrent()
        } else {
            analysisLookupFinishedAt = CFAbsoluteTimeGetCurrent()
            transformStartedAt = analysisLookupFinishedAt
            transformFinishedAt = analysisLookupFinishedAt
            autoTransform = .identity
        }
        let debugOverlayActive = state.debugOverlay
        let meshOverlayMode = StabilizerMeshOverlayMode.clampedRawValue(state.meshOverlayMode)
        let meshOverlayActive = meshOverlayMode != StabilizerMeshOverlayMode.off.rawValue
        if renderCacheIdentity == nil {
            renderCacheIdentity = storeSnapshot.activeCacheIdentity
        }
        let renderCacheIdentityShort = Self.shortRenderCacheIdentity(renderCacheIdentity)
        let renderStatusReason: String?
        if transformEnabled && renderUsesPreparedAnalysis {
            renderStatusReason = "prepared=yes debug=\(state.debugOverlay ? "on" : "off") mesh=\(meshOverlayMode) proxy=\(renderSourceIsProxy ? "yes" : "no") identity=\(renderCacheIdentityShort)"
        } else if transformEnabled {
            let preferredIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferredIdentity,
               !preferredIdentity.isEmpty,
               !StabilizerHostAnalysisStore.cacheIdentity(preferredIdentity, matches: expectedRange) {
                renderStatusReason = "cacheRangeMismatch: preferred identity \(Self.shortRenderCacheIdentity(preferredIdentity)) did not match expected render range"
            } else if hasCompletedHostAnalysis || hasPreparedHostAnalysis || configuredProjectBundleCache || !(preferredIdentity ?? "").isEmpty {
                renderStatusReason = "loadedButNotRendering: prepared=no completed=\(hasCompletedHostAnalysis ? "yes" : "no") loaded=\(hasPreparedHostAnalysis ? "yes" : "no") projectCache=\(configuredProjectBundleCache ? "configured" : "not configured") debug=\(state.debugOverlay ? "on" : "off") mesh=\(meshOverlayMode) identity=\(renderCacheIdentityShort)"
            } else {
                renderStatusReason = nil
            }
        } else {
            renderStatusReason = nil
        }
        let renderDecisionChanged = publishRenderAnalysisDecisionIfChanged(
            RenderAnalysisDecisionSignature(
                fxPlugVersion: tokyoWalkingStabilizerVersion,
                transformEnabled: transformEnabled,
                hasCompletedHostAnalysis: hasCompletedHostAnalysis,
                configuredProjectBundleCache: configuredProjectBundleCache,
                renderUsesPreparedAnalysis: renderUsesPreparedAnalysis,
                stabilizationActive: renderUsesPreparedAnalysis && transformEnabled,
                debugOverlayActive: debugOverlayActive,
                meshOverlayMode: meshOverlayMode,
                renderSourceIsProxy: renderSourceIsProxy,
                renderSourceFrameInfo: renderSourceFrameInfo,
                renderCacheIdentityShort: renderCacheIdentityShort,
                autoCropEnabled: state.autoCropEnabled,
                autoCropProfileName: state.autoCropEnabled ? Self.autoCropSamplingProfile(forQualityLevel: state.renderQualityLevel, renderSourceIsProxy: renderSourceIsProxy).displayName : "off",
                hostAnalysisFrameCount: state.hostAnalysisFrameCount
            )
        )
        if renderDecisionChanged, let renderStatusReason {
            if transformEnabled && renderUsesPreparedAnalysis {
                hostAnalysisStore.noteStabilizationActiveForRender(
                    debugOverlayActive: state.debugOverlay,
                    reason: renderStatusReason
                )
            } else if renderStatusReason.hasPrefix("cacheRangeMismatch: ") {
                hostAnalysisStore.noteCacheRangeMismatchForRender(
                    reason: String(renderStatusReason.dropFirst("cacheRangeMismatch: ".count))
                )
            } else if renderStatusReason.hasPrefix("loadedButNotRendering: ") {
                hostAnalysisStore.noteLoadedButNotRenderingForRender(
                    reason: String(renderStatusReason.dropFirst("loadedButNotRendering: ".count))
                )
            }
        }
        storeSnapshot = hostAnalysisStore.renderSnapshot
        let renderInvalidationToken = storeSnapshot.renderInvalidationToken
        let publishedRenderInvalidationToken = Self.runtimeRenderRevisionToken(renderInvalidationToken)
        renderStoreRevision = storeSnapshot.revision
        let renderStoreChangedStatus = renderStoreRevision != state.hostAnalysisRevision
        let renderRevisionNeedsRetry = abs(publishedRenderInvalidationToken - state.renderRevision) >= 0.5
            && shouldRetryRenderRevisionPublish(renderInvalidationToken)
        if renderStoreChangedStatus || renderRevisionNeedsRetry {
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: renderInvalidationToken,
                revisionForce: renderStoreChangedStatus || renderRevisionNeedsRetry,
                currentRenderRevision: state.renderRevision
            )
        }
        let debugOverlayScale: Float = (debugOverlayActive || meshOverlayActive) ? Self.debugOverlayScale(
            outputWidth: Int(outputWidth),
            outputHeight: Int(outputHeight),
            renderSourceIsProxy: renderSourceIsProxy
        ) : 1.0
        var debugOverlayMetrics = StabilizerDebugOverlayMetrics.zero
        let cropStartedAt = CFAbsoluteTimeGetCurrent()
        let autoCropFraming: AutoCropFraming
        let autoCropSamplingProfile = Self.autoCropSamplingProfile(forQualityLevel: state.renderQualityLevel, renderSourceIsProxy: renderSourceIsProxy)
        if state.autoCropEnabled,
           renderUsesPreparedAnalysis,
           let preparedAnalysis = activePreparedAnalysis {
            let autoCropRenderTime = activeAnalysisRenderTime ?? hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            let autoCropOutputSize = vector_float2(Float(outputWidth), Float(outputHeight))
            let playbackPreparationCacheIdentity = renderCacheIdentity
            // autoTransform already contains the UI-strength viewport result
            // sampled from the shared canonical TURN trajectory.
            let autoCropPlanningTransform = autoTransform
            let autoCropPlaybackPlanPrepared: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.publishPlaybackPreparationInvalidationOnMain(
                    cacheIdentity: playbackPreparationCacheIdentity,
                    reason: "auto-crop playback scale plan prepared"
                )
            }
            let rawAutoCropFraming = Self.cachedAutoCropFraming(
                preparedAnalysis: preparedAnalysis,
                renderTime: autoCropRenderTime,
                currentTransform: autoCropPlanningTransform,
                outputSize: autoCropOutputSize,
                panSmoothSeconds: 0.0,
                strengths: correctionStrengths,
                masterStrength: masterStrength,
                transitionDuration: state.autoCropTransitionDuration,
                leadTime: state.autoCropLeadTime,
                holdTime: state.autoCropHoldTime,
                samplingProfile: autoCropSamplingProfile,
                renderQualityLevel: state.renderQualityLevel,
                analysisRevision: renderStoreRevision,
                cacheIdentity: renderCacheIdentity,
                playbackPreparationScope: playbackPreparationScope,
                onPlaybackPreparationReady: autoCropPlaybackPlanPrepared
            )
            autoCropFraming = rawAutoCropFraming
        } else {
            autoCropFraming = .identity
        }
        let cropFinishedAt = CFAbsoluteTimeGetCurrent()
        let previewWarmupDecision: RenderPreviewWarmupDecision
        if transformEnabled,
           renderUsesPreparedAnalysis,
           let preparedAnalysis = activePreparedAnalysis {
            let warmupRenderTime = activeAnalysisRenderTime
                ?? hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            previewWarmupDecision = renderPreviewWarmupDecision(
                preparedAnalysis: preparedAnalysis,
                renderTime: warmupRenderTime,
                renderSourceIsProxy: renderSourceIsProxy,
                autoCropEnabled: state.autoCropEnabled,
                cacheIdentityShort: renderCacheIdentityShort
            )
        } else {
            previewWarmupDecision = .inactive
        }
        var renderedAutoTransform: StabilizerAutoTransform = previewWarmupDecision.active
            ? .identity
            : autoTransform
        let renderedAutoCropFraming: AutoCropFraming = previewWarmupDecision.active
            ? .identity
            : autoCropFraming
        // Remove Black Edges owns only crop position and scale. Keep the same
        // canonical TURN/X trajectory in both modes; disabling Auto Crop must
        // change scale to 1.0x without restoring the pre-concatenated X path.
        renderedAutoTransform = cameraRigidFinalLimitTransform(
            renderedAutoTransform,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            state: state,
            masterStrength: masterStrength
        )
        let renderedAutoCropPosition = state.autoCropEnabled
            ? renderedAutoCropFraming.positionPixels
            : vector_float2(0.0, 0.0)
        if debugOverlayActive {
            let searchRadiusHeadroomAvailable = renderedAutoTransform.searchRadiusTotalCount > 0
            let searchRadiusHeadroomQuality: Float
            if searchRadiusHeadroomAvailable {
                let hitRatio = min(
                    1.0,
                    Float(renderedAutoTransform.searchRadiusHitCount)
                        / Float(renderedAutoTransform.searchRadiusTotalCount)
                )
                searchRadiusHeadroomQuality = 1.0 - hitRatio
            } else {
                searchRadiusHeadroomQuality = 0.0
            }
            let residualQualityAvailable = renderedAutoTransform.residual.isFinite
                && activePreparedAnalysis != nil
                && !previewWarmupDecision.active
            let residualQuality = residualQualityAvailable
                ? Self.debugMatchQuality(
                    residual: renderedAutoTransform.residual,
                    preparedAnalysis: activePreparedAnalysis
                )
                : 0.0
            let microJitterPixelOffset = renderedAutoTransform.microPixelOffset
                + renderedAutoTransform.trajectoryMicroJitterPixelOffset
                + renderedAutoTransform.trajectoryContinuityPixelOffset
                + renderedAutoTransform.cameraRigidPixelOffset
            let microJitterRotation = renderedAutoTransform.microJitterRotationDegrees
                + renderedAutoTransform.cameraRigidRotationDegrees
            debugOverlayMetrics = StabilizerDebugOverlayCalculator.metrics(
                for: StabilizerDebugOverlayInputs(
                    outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                    masterStrength: masterStrength,
                    finalPixelOffset: renderedAutoTransform.pixelOffset,
                    finalRotationDegrees: renderedAutoTransform.rotationDegrees,
                    cropEnabled: state.autoCropEnabled && !previewWarmupDecision.active,
                    cropScale: renderedAutoCropFraming.scale,
                    cropPositionPixels: renderedAutoCropPosition,
                    macroJitterPixelOffset: renderedAutoTransform.macroJitterPixelOffset,
                    macroJitterRotationDegrees: renderedAutoTransform.macroJitterRotationDegrees,
                    microJitterPixelOffset: microJitterPixelOffset,
                    microJitterRotationDegrees: microJitterRotation,
                    warpShear: renderedAutoTransform.shear,
                    warpPerspective: renderedAutoTransform.perspective + renderedAutoTransform.yawPitchProxy,
                    temporalSmoothingPixelDelta: renderedAutoTransform.temporalSmoothingPixelDelta,
                    temporalSmoothingRotationDelta: renderedAutoTransform.temporalSmoothingRotationDelta,
                    trackingConfidence: renderedAutoTransform.trackingConfidence,
                    walkingTrackingConfidence: renderedAutoTransform.walkingTrackingConfidence,
                    sharpnessQuality: AutoStabilizationEstimator.blurEvidenceQuality(renderedAutoTransform.blurAmount),
                    residualQuality: residualQuality,
                    residualQualityAvailable: residualQualityAvailable,
                    searchRadiusHeadroomQuality: searchRadiusHeadroomQuality,
                    searchRadiusHeadroomAvailable: searchRadiusHeadroomAvailable,
                    turnConfidence: renderedAutoTransform.turnConfidence,
                    macroConfidence: renderedAutoTransform.macroJitterConfidence,
                    microJitterConfidence: renderedAutoTransform.microConfidence,
                    warpConfidence: renderedAutoTransform.warpConfidence
                )
            )
        }
        if transformEnabled,
           renderUsesPreparedAnalysis,
           let preparedAnalysis = activePreparedAnalysis {
            let motionRenderTime = activeAnalysisRenderTime
                ?? hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            logRenderMotionCadenceIfNeeded(
                preparedAnalysis: preparedAnalysis,
                renderTime: motionRenderTime,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: 0.0,
                strengths: correctionStrengths,
                autoTransform: renderedAutoTransform,
                autoCropFraming: autoCropFraming,
                renderSourceIsProxy: renderSourceIsProxy,
                autoCropEnabled: state.autoCropEnabled,
                debugOverlayActive: debugOverlayActive,
                masterStrength: masterStrength,
                cacheIdentityShort: renderCacheIdentityShort,
                previewWarmupDecision: previewWarmupDecision
            )
        }
        if debugOverlayActive {
            logDebugOverlayRenderTruthIfNeeded(
                debugOverlayActive: true,
                transformEnabled: transformEnabled,
                renderUsesPreparedAnalysis: renderUsesPreparedAnalysis,
                renderSourceIsProxy: renderSourceIsProxy,
                renderTime: renderTime,
                analysisRenderTime: activeAnalysisRenderTime,
                frameCount: Int(state.hostAnalysisFrameCount),
                cacheIdentityShort: renderCacheIdentityShort,
                autoTransform: renderedAutoTransform,
                autoCropFraming: renderedAutoCropFraming,
                metrics: debugOverlayMetrics,
                previewWarmupDecision: previewWarmupDecision
            )
        }

        var transform = TokyoWalkingStabilizerTransformUniforms(
            pixelOffset: renderedAutoTransform.pixelOffset * masterStrength,
            rotationRadians: renderedAutoTransform.rotationDegrees * .pi / 180.0 * masterStrength,
            rotationSinCos: vector_float2(
                Darwin.sinf(-renderedAutoTransform.rotationDegrees * .pi / 180.0 * masterStrength),
                Darwin.cosf(-renderedAutoTransform.rotationDegrees * .pi / 180.0 * masterStrength)
            ),
            strength: 1.0,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            debugDiagnostics: Self.debugOverlayUniform(debugOverlayMetrics),
            shear: renderedAutoTransform.shear * masterStrength,
            perspective: (renderedAutoTransform.perspective + renderedAutoTransform.yawPitchProxy) * masterStrength,
            edgeMode: Float(state.edgeDisplayMode),
            debugOverlay: debugOverlayActive ? 1.0 : 0.0,
            debugMode: renderSourceIsProxy ? 2.0 : 1.0,
            debugRuntimeBuild: tokyoWalkingStabilizerDebugBuildNumber,
            debugRuntimeVersion: tokyoWalkingStabilizerDebugVersion,
            debugOverlayScale: debugOverlayScale,
            debugMeshOverlayMode: Float(meshOverlayMode),
            autoCropScale: renderedAutoCropFraming.scale,
            autoCropPositionPixels: renderedAutoCropPosition,
            lensBandTopOffset: renderedAutoTransform.lensBandTopOffset * masterStrength,
            lensBandRidgeOffset: renderedAutoTransform.lensBandRidgeOffset * masterStrength,
            lensBandMidOffset: renderedAutoTransform.lensBandMidOffset * masterStrength,
            lensBandTopColumnOffset: renderedAutoTransform.lensBandTopColumnOffset * masterStrength,
            lensBandRidgeColumnOffset: renderedAutoTransform.lensBandRidgeColumnOffset * masterStrength,
            lensBandMidColumnOffset: renderedAutoTransform.lensBandMidColumnOffset * masterStrength,
            lensBandTopRowPhaseOffset: renderedAutoTransform.lensBandTopRowPhaseOffset * masterStrength,
            lensBandRidgeRowPhaseOffset: renderedAutoTransform.lensBandRidgeRowPhaseOffset * masterStrength,
            lensBandMidRowPhaseOffset: renderedAutoTransform.lensBandMidRowPhaseOffset * masterStrength,
            lensBandTopLocalRoll: renderedAutoTransform.lensBandTopLocalRoll * masterStrength,
            lensBandRidgeLocalRoll: renderedAutoTransform.lensBandRidgeLocalRoll * masterStrength,
            lensBandMidLocalRoll: renderedAutoTransform.lensBandMidLocalRoll * masterStrength,
            lensBandWarpSupport: renderedAutoTransform.lensBandWarpSupport,
            lensBandWarpApplied: renderedAutoTransform.lensBandWarpApplied,
            lensFarFieldRigidOnlyApplied: renderedAutoTransform.lensFarFieldRigidShakeLocalWarpSuppressed,
            sourceLensShakeRidgeOffset: renderedAutoTransform.sourceLensShakeRidgeOffset * masterStrength,
            sourceLensShakeRidgeSupport: renderedAutoTransform.sourceLensShakeRidgeSupport,
            sourceLensShakeRidgeApplied: renderedAutoTransform.sourceLensShakeRidgeApplied,
            sourceLensShakeLocalTopLeftOffset: renderedAutoTransform.sourceLensShakeLocalTopLeftOffset * masterStrength,
            sourceLensShakeLocalTopCenterOffset: renderedAutoTransform.sourceLensShakeLocalTopCenterOffset * masterStrength,
            sourceLensShakeLocalTopRightOffset: renderedAutoTransform.sourceLensShakeLocalTopRightOffset * masterStrength,
            sourceLensShakeLocalRidgeLeftOffset: renderedAutoTransform.sourceLensShakeLocalRidgeLeftOffset * masterStrength,
            sourceLensShakeLocalRidgeCenterOffset: renderedAutoTransform.sourceLensShakeLocalRidgeCenterOffset * masterStrength,
            sourceLensShakeLocalRidgeRightOffset: renderedAutoTransform.sourceLensShakeLocalRidgeRightOffset * masterStrength,
            sourceLensShakeLocalMidLeftOffset: renderedAutoTransform.sourceLensShakeLocalMidLeftOffset * masterStrength,
            sourceLensShakeLocalMidCenterOffset: renderedAutoTransform.sourceLensShakeLocalMidCenterOffset * masterStrength,
            sourceLensShakeLocalMidRightOffset: renderedAutoTransform.sourceLensShakeLocalMidRightOffset * masterStrength,
            sourceLensShakeLocalSupport: renderedAutoTransform.sourceLensShakeLocalSupport,
            sourceLensShakeLocalApplied: renderedAutoTransform.sourceLensShakeLocalApplied,
            debugFarFieldMesh: vector_float4(
                renderedAutoTransform.lensFarFieldMeshAvailable,
                renderedAutoTransform.lensFarFieldMeshSupport,
                renderedAutoTransform.lensFarFieldMeshBlend,
                renderedAutoTransform.lensFarFieldMeshDominantCell
            ),
            debugFarFieldMeshWindow: vector_float4(
                renderedAutoTransform.lensFarFieldMeshDominantWindowFrames,
                renderedAutoTransform.lensFarFieldMeshDominantWindowSeconds,
                renderedAutoTransform.lensFarFieldMeshDominantSupport,
                renderedAutoTransform.lensFarFieldMeshSupportedBins
            )
        )
        if debugOverlayActive && !previewWarmupDecision.active {
            publishHostAnalysisRenderDiagnostics(
                frameCount: Int(state.hostAnalysisFrameCount),
                panSmoothSeconds: 0.0,
                autoTransform: renderedAutoTransform,
                autoCropFraming: renderedAutoCropFraming,
                appliedPixelOffset: transform.pixelOffset,
                appliedRotationRadians: transform.rotationRadians
            )
        }

        let encodeStartedAt = CFAbsoluteTimeGetCurrent()
        let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
        colorAttachment.texture = outputTexture
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
        colorAttachment.clearColor = MTLClearColorMake(0, 0, 0, 0)

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0] = colorAttachment

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            deviceCache.returnCommandQueueToCache(commandQueue: commandQueue)
            return
        }

        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(outputWidth), height: Double(outputHeight), znear: -1.0, zfar: 1.0))
        encoder.setRenderPipelineState(pipelineState)
        withUnsafeTemporaryAllocation(of: StabilizerVertex2D.self, capacity: 4) { vertices in
            vertices[0] = StabilizerVertex2D(position: vector_float2(halfOutputWidth, -halfOutputHeight), textureCoordinate: vector_float2(1.0, 1.0))
            vertices[1] = StabilizerVertex2D(position: vector_float2(-halfOutputWidth, -halfOutputHeight), textureCoordinate: vector_float2(0.0, 1.0))
            vertices[2] = StabilizerVertex2D(position: vector_float2(halfOutputWidth, halfOutputHeight), textureCoordinate: vector_float2(1.0, 0.0))
            vertices[3] = StabilizerVertex2D(position: vector_float2(-halfOutputWidth, halfOutputHeight), textureCoordinate: vector_float2(0.0, 0.0))
            encoder.setVertexBytes(vertices.baseAddress!, length: MemoryLayout<StabilizerVertex2D>.stride * vertices.count, index: Int(SVI_Vertices.rawValue))
        }
        encoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(SVI_ViewportSize.rawValue))
        encoder.setFragmentTexture(inputTexture, index: Int(STI_InputImage.rawValue))
        encoder.setFragmentBytes(&transform, length: MemoryLayout.size(ofValue: transform), index: Int(SFI_Transform.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        let encodeFinishedAt = CFAbsoluteTimeGetCurrent()
        commandBuffer.commit()
        let gpuWaitStartedAt = CFAbsoluteTimeGetCurrent()
        commandBuffer.waitUntilCompleted()
        let renderFinishedAt = CFAbsoluteTimeGetCurrent()
        deviceCache.returnCommandQueueToCache(commandQueue: commandQueue)
        logRenderTimingIfNeeded(
            totalMs: (renderFinishedAt - renderStartedAt) * 1000.0,
            setupMs: (setupFinishedAt - renderStartedAt) * 1000.0,
            analysisMs: (analysisLookupFinishedAt - analysisLookupStartedAt) * 1000.0,
            transformMs: (transformFinishedAt - transformStartedAt) * 1000.0,
            cropMs: (cropFinishedAt - cropStartedAt) * 1000.0,
            encodeMs: (encodeFinishedAt - encodeStartedAt) * 1000.0,
            gpuWaitMs: (renderFinishedAt - gpuWaitStartedAt) * 1000.0,
            renderUsesPreparedAnalysis: renderUsesPreparedAnalysis,
            renderSourceIsProxy: renderSourceIsProxy,
            autoCropEnabled: state.autoCropEnabled,
            cacheIdentityShort: renderCacheIdentityShort,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>!, forInputWith inputTimeRange: CMTimeRange) throws {
        desiredRange?.pointee = inputTimeRange
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        os_log(
            "setupAnalysis requested for range %{public}.3f+%{public}.3f seconds, frameDuration %{public}.6f seconds.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        NSLog(
            "TokyoWalkingStabilizer: setup Host Analysis requested for range %.3f+%.3f seconds, frameDuration %.6f seconds.",
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        let expectedRange = HostAnalysisExpectedRange(
            startSeconds: CMTimeGetSeconds(analysisRange.start),
            durationSeconds: CMTimeGetSeconds(analysisRange.duration),
            frameDurationSeconds: CMTimeGetSeconds(frameDuration)
        )
        let configuredProjectCache = configureProjectBundleCacheDirectory(
            expectedRange: expectedRange.isValid ? expectedRange : nil,
            forceRefresh: true
        )
        let projectCacheUnavailableReason = configuredProjectCache ? nil : hostAnalysisStore.projectCacheUnavailableReasonText
        if !configuredProjectCache {
            NSLog("TokyoWalkingStabilizer: setup Host Analysis will continue in memory because the Event cache root is unavailable.")
            os_log("setupAnalysis continuing in memory because the Event cache root is unavailable; completed analysis will persist later if the Event cache root becomes available.", log: stabilizerHostAnalysisLog, type: .error)
        }
        let analysisStore = StabilizerHostAnalysisStore()
        let requestedSampleScalePercent = requestedSampleScalePercent(at: analysisRange.start)
        analysisStore.begin(
            range: analysisRange,
            frameDuration: frameDuration,
            requestedSampleScalePercent: requestedSampleScalePercent
        )
        if let projectCacheUnavailableReason {
            analysisStore.noteProjectCacheUnavailable(reason: projectCacheUnavailableReason)
        }
        lastPublishedActiveAnalysisFrameCount = 0
        let sessionID = registerActiveAnalysisSession(
            store: analysisStore,
            range: analysisRange,
            frameDuration: frameDuration,
            requestedSampleScalePercent: requestedSampleScalePercent
        )
        os_log(
            "setupAnalysis created active in-progress store %{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            sessionID.uuidString
        )
        NSLog(
            "TokyoWalkingStabilizer: setup Host Analysis session %@ range %.3f+%.3f seconds, frameDuration %.6f seconds.",
            sessionID.uuidString,
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        _ = hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange.isValid ? expectedRange : nil)
        publishAnalysisCallbackStatus(analysisStore)
    }

    func analyzeFrame(_ frame: FxImageTile!, at frameTime: CMTime) throws {
        guard let frame else {
            let route = try? resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: nil)
            abandonActiveAnalysisAfterFailure(sessionID: route?.sessionID)
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "TokyoWalkingStabilizer host analysis supplied no frame."]
            )
        }
        let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: frame)
        if let rejectionReason = StabilizerOriginalMediaPolicy.proxyRejectionReason(for: frame) {
            let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: frameInfo)
            route.store.rejectProxyAnalysis(reason: rejectionReason)
            publishAnalysisCallbackStatus(route.store, canPublishCallbackStatus: route.canPublishCallbackStatus)
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: rejectionReason]
            )
        }
        guard let frameInfo else {
            let reason = "Host Analysis could not read the original clip size for Sample Size."
            let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: nil)
            route.store.rejectProxyAnalysis(reason: reason)
            publishAnalysisCallbackStatus(route.store, canPublishCallbackStatus: route.canPublishCallbackStatus)
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: frameInfo)
        guard let sampleSize = route.sampleSize else {
            throw hostAnalysisRoutingError("Stabilizer Host Analysis session could not derive a sample size for the current clip frame.")
        }
        do {
            let analysisSample = try AutoStabilizationEstimator.analysisSample(
                from: frame,
                at: frameTime,
                sampleWidth: sampleSize.width,
                sampleHeight: sampleSize.height,
                downsampleBufferPool: route.store.reusableDownsampleBufferPool,
                retainPixels: false
            )
            try route.store.append(analysisSample, sourceInfo: frameInfo)
            recordActiveAnalysisFrameAccepted(
                sessionID: route.sessionID,
                frameTime: frameTime,
                sourceInfo: frameInfo,
                sampleSize: sampleSize
            )
            if route.store.frameCount == 1 {
                os_log(
                    "Received first Host Analysis frame for session %{public}@ at %{public}.3f seconds, sample %{public}dx%{public}d.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    route.sessionID.uuidString,
                    CMTimeGetSeconds(frameTime),
                    analysisSample.sampleWidth,
                    analysisSample.sampleHeight
                )
                NSLog(
                    "TokyoWalkingStabilizer: received first Host Analysis frame for session %@ at %.3f seconds, sample %dx%d.",
                    route.sessionID.uuidString,
                    CMTimeGetSeconds(frameTime),
                    analysisSample.sampleWidth,
                    analysisSample.sampleHeight
                )
            }
            publishActiveAnalysisProgressIfNeeded(
                route.store,
                canPublishCallbackStatus: route.canPublishCallbackStatus
            )
        } catch {
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw error
        }
    }

    func cleanupAnalysis() throws {
        let cleanupRoute = takeActiveAnalysisSessionForCleanup()
        let sessionID: UUID
        let analysisStore: StabilizerHostAnalysisStore
        let cleanupExpectedRange: HostAnalysisExpectedRange?
        let canPublishCallbackStatus: Bool
        switch cleanupRoute {
        case .resolved(let resolvedSessionID, let resolvedStore, let expectedRange, let resolvedCanPublishCallbackStatus):
            sessionID = resolvedSessionID
            analysisStore = resolvedStore
            cleanupExpectedRange = expectedRange
            canPublishCallbackStatus = resolvedCanPublishCallbackStatus
        case .failed(let reason):
            NSLog("TokyoWalkingStabilizer: \(reason)")
            os_log("cleanupAnalysis failed: %{public}@", log: stabilizerHostAnalysisLog, type: .error, reason)
            Self.scheduleSerialAnalysisQueueDrain(after: 0.2)
            throw NSError(
                domain: "com.justadev.TokyoWalkingStabilizer",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        do {
            if !configureProjectBundleCacheDirectory(markUnavailable: true, expectedRange: cleanupExpectedRange, forceRefresh: true),
               let projectCacheUnavailableReason = hostAnalysisStore.projectCacheUnavailableReasonText {
                analysisStore.noteProjectCacheUnavailable(reason: projectCacheUnavailableReason)
            }
            try analysisStore.finish()
        } catch {
            publishAnalysisCallbackStatus(analysisStore, canPublishCallbackStatus: canPublishCallbackStatus)
            abandonActiveAnalysisAfterFailure(sessionID: sessionID)
            throw error
        }
        hostAnalysisStore.installCompletedAnalysis(from: analysisStore)
        os_log(
            "cleanupAnalysis completed session %{public}@ with %{public}d analyzed frame(s).",
            log: stabilizerHostAnalysisLog,
            type: .default,
            sessionID.uuidString,
            analysisStore.frameCount
        )
        let completedCacheIdentity = hostAnalysisStore.activeCacheIdentity
        let completedRenderRevision = hostAnalysisStore.renderInvalidationToken
        DispatchQueue.main.async {
            Self.runSerialAnalysisQueueDrainPass()
        }
        if canPublishCallbackStatus {
            schedulePostAnalysisPreviewInvalidationRetries(
                revision: completedRenderRevision,
                cacheIdentity: completedCacheIdentity
            )
        } else {
            os_log(
                "Skipped completed Host Analysis status publish from a non-owner callback instance.",
                log: stabilizerHostAnalysisLog,
                type: .debug
            )
        }
    }
}
