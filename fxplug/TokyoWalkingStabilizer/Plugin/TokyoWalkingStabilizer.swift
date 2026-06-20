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
    case panSmoothSeconds = 9
    case debugOverlay = 10
    case startHostAnalysis = 14
    case hostAnalysisStatus = 15
    case sampleInfo = 32
    case clearHostAnalysisCache = 17
    case yStrength = 18
    case sampleScale = 19
    case renderRevision = 20
    case panStabilizationStrength = 23
    case edgeDisplayMode = 27
    // ID 28 is retired because existing FCP effect instances can persist the
    // old 0-4 slider range for that parameter ID.
    case legacyFarFieldWarpStrength = 28
    case strideWobbleXStrength = 29
    case strideWobbleYStrength = 30
    case strideWobbleRotationStrength = 31
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
}

private struct StabilizerInfoFields {
    let sample: String
    let queue: String
}

private let tokyoWalkingStabilizerVersion = "0.4.2"
let stabilizerHostAnalysisLog = OSLog(subsystem: "com.justadev.TokyoWalkingStabilizer", category: "HostAnalysis")
private let stabilizerFixedStrideWobbleWindowSeconds = 2.0
private let stabilizerMinimumTurnDetectionWindowSeconds = stabilizerFixedStrideWobbleWindowSeconds
private let stabilizerDefaultTurnDetectionWindowSeconds = 2.0
private let stabilizerMaximumFarFieldWarpStrength = 12.0
private let stabilizerDefaultAutoCropTransitionDuration = 10.0
private let stabilizerMaximumAutoCropTransitionDuration = 30.0
private let stabilizerDefaultAutoCropLeadTime = 10.0
private let stabilizerMaximumAutoCropLeadTime = 120.0
private let stabilizerDefaultAutoCropHoldTime = 2.0
private let stabilizerMaximumAutoCropHoldTime = 30.0
private let stabilizerAutoCropActiveScalePadding: Float = 0.018
private let stabilizerAutoCropKeypointScaleThresholdDelta: Float = 0.006
private let stabilizerAutoCropKeypointCoverageThresholdDelta: Float = 0.0005
private let stabilizerAutoCropKeypointRefineRadiusSeconds = 2.0
private let stabilizerAutoCropKeypointRefineStepSeconds = 0.25
private let stabilizerAutoCropKeypointMaximumCount = 64
private let stabilizerAutoCropKeypointLogLimit = 6
private let stabilizerAutoCropKeypointCoverageToleranceDelta: Float = 0.0005
private let stabilizerAutoCropKeypointDuplicateSeconds = 0.125
private let stabilizerAutoCropKeypointCoveragePassLimit = 64
private let stabilizerAutoCropSubtleZoomMaximumDelta: Float = 0.08
private let stabilizerAutoCropSubtleZoomMultiplier: Float = 0.5
private let stabilizerAutoCropDurationScaleReferenceDelta: Float = 0.10
private let stabilizerAutoCropMinimumScaledDurationSeconds = 0.25
private let stabilizerAutoCropIdleScaleTolerance: Float = 0.012
private let stabilizerAutoCropIdleReleaseStartSeconds = 1.0
private let stabilizerAutoCropIdleReleaseEndSeconds = 2.5
private let stabilizerAutoCropIdleSampleStepSeconds = 0.25
private let stabilizerRenderRevisionRetryIntervalSeconds: TimeInterval = 0.5
let stabilizerProjectCacheUnavailableMessage = "Project Bundle Cache Unavailable - Event Analysis Files Unavailable"
let stabilizerAmbiguousEventCacheUnavailableMessage = "Project Bundle Cache Unavailable - Ambiguous Event"
let stabilizerAmbiguousActiveLibrariesCacheUnavailableMessage = "Project Bundle Cache Unavailable - Ambiguous Active Libraries"

private enum StabilizerEdgeDisplayMode: Int32 {
    case stretchEdges = 0
    case blackOutside = 1
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

    static let identity = AutoCropFraming(
        scale: 1.0,
        positionPixels: vector_float2(0.0, 0.0)
    )
}

private struct AutoCropZoomDemandSample {
    let seconds: Double
    let scale: Float
    let positionPixels: vector_float2
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
            return 0.0
        case .full:
            return 0.0
        }
    }

    var positionEnvelopeSampleLimit: Int {
        switch self {
        case .playback:
            return 120
        case .full:
            return 240
        }
    }

    var positionEnvelopeStepSeconds: Double {
        switch self {
        case .playback:
            return 1.0 / 30.0
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
    let panSmoothSeconds: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let renderQualityLevel: UInt32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let strideWobbleX: UInt64
    let strideWobbleY: UInt64
    let strideWobbleRotation: UInt64
    let panStabilizationStrength: UInt64
    let farFieldWarp: UInt64
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
    let panSmoothSeconds: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let strideWobbleX: UInt64
    let strideWobbleY: UInt64
    let strideWobbleRotation: UInt64
    let panStabilizationStrength: UInt64
    let farFieldWarp: UInt64
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
    let panSmoothSeconds: UInt64
    let masterStrength: UInt32
    let transitionDuration: UInt64
    let leadTime: UInt64
    let holdTime: UInt64
    let samplingProfile: Int32
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let strideWobbleX: UInt64
    let strideWobbleY: UInt64
    let strideWobbleRotation: UInt64
    let panStabilizationStrength: UInt64
    let farFieldWarp: UInt64
}

private struct StabilizerAutoTransformCacheKey: Hashable {
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
    let analysisSampleWidth: Int32
    let analysisSampleHeight: Int32
    let analysisQualityModel: Int
    let panSmoothSeconds: UInt64
    let microJitterX: UInt64
    let microJitterY: UInt64
    let microJitterRotation: UInt64
    let strideWobbleX: UInt64
    let strideWobbleY: UInt64
    let strideWobbleRotation: UInt64
    let panStabilizationStrength: UInt64
    let farFieldWarp: UInt64
}

private struct RenderAnalysisDecisionSignature: Equatable {
    let fxPlugVersion: String
    let transformEnabled: Bool
    let hasCompletedHostAnalysis: Bool
    let configuredProjectBundleCache: Bool
    let renderUsesPreparedAnalysis: Bool
    let stabilizationActive: Bool
    let debugOverlayActive: Bool
    let renderSourceIsProxy: Bool
    let renderCacheIdentityShort: String
    let autoCropEnabled: Bool
    let autoCropProfileName: String
    let hostAnalysisFrameCount: Int32
}

private struct StabilizerPluginState {
    var strength: Double
    var microJitterXStrength: Double
    var microJitterYStrength: Double
    var microJitterRotationStrength: Double
    var strideWobbleXStrength: Double
    var strideWobbleYStrength: Double
    var strideWobbleRotationStrength: Double
    var panStabilizationStrength: Double
    var farFieldWarpStrength: Double
    var panSmoothSeconds: Double
    var autoCropTransitionDuration: Double
    var autoCropLeadTime: Double
    var autoCropHoldTime: Double
    var autoCropEnabled: Bool
    var edgeDisplayMode: Int32
    var debugOverlay: Bool
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
    private static let proxyScaleTolerance = 0.05

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

    private static let serialAnalysisQueueLock = NSLock()
    private static var serialAnalysisQueue: [SerialHostAnalysisRequest] = []
    private static let activeAnalysisStoreLock = NSLock()
    private static var activeAnalysisSessions: [UUID: ActiveHostAnalysisSession] = [:]
    private static var hostAnalysisStartReserved = false
    private static let autoCropFramingCacheLock = NSLock()
    private static var autoCropFramingCache: [AutoCropFramingCacheKey: AutoCropFraming] = [:]
    private static var autoCropFramingCacheOrder: [AutoCropFramingCacheKey] = []
    private static let autoCropFramingCacheLimit = 160
    private static let autoCropScaleDemandCacheLock = NSLock()
    private static var autoCropScaleDemandCache: [AutoCropScaleDemandCacheKey: AutoCropScaleDemand] = [:]
    private static var autoCropScaleDemandCacheOrder: [AutoCropScaleDemandCacheKey] = []
    private static let autoCropScaleDemandCacheLimit = 1024
    private static let autoCropZoomPlanCacheLock = NSLock()
    private static var autoCropZoomPlanCache: [AutoCropZoomPlanCacheKey: AutoCropZoomPlan] = [:]
    private static var autoCropZoomPlanCacheOrder: [AutoCropZoomPlanCacheKey] = []
    private static let autoCropZoomPlanCacheLimit = 16
    private static let autoTransformCacheLock = NSLock()
    private static var autoTransformCache: [StabilizerAutoTransformCacheKey: StabilizerAutoTransform] = [:]
    private static var autoTransformCacheOrder: [StabilizerAutoTransformCacheKey] = []
    private static let autoTransformCacheLimit = 512

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
    private let renderDiagnosticsLogLock = NSLock()
    private var lastRenderDiagnosticsLogBucket: Int64?
    private var lastRenderDiagnosticsLogWallTime: TimeInterval = 0.0
    private var preferredHostAnalysisCacheIdentity: String?
    private var lastPublishedActiveAnalysisFrameCount = 0
    private var activeAnalyzerSessionID: UUID?
    private var persistentCacheMonitor: DispatchSourceTimer?
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
            withName: "Footstep Jitter X Strength",
            parameterID: ParameterID.xStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 10.0,
            sliderMin: 0.0,
            sliderMax: 10.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Footstep Jitter Y Strength",
            parameterID: ParameterID.yStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 10.0,
            sliderMin: 0.0,
            sliderMax: 10.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Footstep Jitter Rotation Strength",
            parameterID: ParameterID.rotationStrength.rawValue,
            defaultValue: 0.5,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Stride Wobble X Strength",
            parameterID: ParameterID.strideWobbleXStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 10.0,
            sliderMin: 0.0,
            sliderMax: 10.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Stride Wobble Y Strength",
            parameterID: ParameterID.strideWobbleYStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 10.0,
            sliderMin: 0.0,
            sliderMax: 10.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Stride Wobble Rotation Strength",
            parameterID: ParameterID.strideWobbleRotationStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Far-field Warp Strength",
            parameterID: ParameterID.farFieldWarpStrength.rawValue,
            defaultValue: 0.5,
            parameterMin: 0.0,
            parameterMax: stabilizerMaximumFarFieldWarpStrength,
            sliderMin: 0.0,
            sliderMax: stabilizerMaximumFarFieldWarpStrength,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Turn Smoothing Strength",
            parameterID: ParameterID.panStabilizationStrength.rawValue,
            defaultValue: 0.2,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Turn Detection Window",
            parameterID: ParameterID.panSmoothSeconds.rawValue,
            defaultValue: stabilizerDefaultTurnDetectionWindowSeconds,
            parameterMin: stabilizerMinimumTurnDetectionWindowSeconds,
            parameterMax: 120.0,
            sliderMin: stabilizerMinimumTurnDetectionWindowSeconds,
            sliderMax: 30.0,
            delta: 0.25,
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
            microJitterXStrength: 1.0,
            microJitterYStrength: 1.0,
            microJitterRotationStrength: 0.5,
            strideWobbleXStrength: 1.0,
            strideWobbleYStrength: 1.0,
            strideWobbleRotationStrength: 1.0,
            panStabilizationStrength: 0.2,
            farFieldWarpStrength: 0.5,
            panSmoothSeconds: stabilizerDefaultTurnDetectionWindowSeconds,
            autoCropTransitionDuration: stabilizerDefaultAutoCropTransitionDuration,
            autoCropLeadTime: stabilizerDefaultAutoCropLeadTime,
            autoCropHoldTime: stabilizerDefaultAutoCropHoldTime,
            autoCropEnabled: true,
            edgeDisplayMode: StabilizerEdgeDisplayMode.blackOutside.rawValue,
            debugOverlay: false,
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
        paramAPI.getFloatValue(&state.microJitterXStrength, fromParameter: ParameterID.xStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.microJitterYStrength, fromParameter: ParameterID.yStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.microJitterRotationStrength, fromParameter: ParameterID.rotationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.strideWobbleXStrength, fromParameter: ParameterID.strideWobbleXStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.strideWobbleYStrength, fromParameter: ParameterID.strideWobbleYStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.strideWobbleRotationStrength, fromParameter: ParameterID.strideWobbleRotationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.panStabilizationStrength, fromParameter: ParameterID.panStabilizationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.farFieldWarpStrength, fromParameter: ParameterID.farFieldWarpStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.panSmoothSeconds, fromParameter: ParameterID.panSmoothSeconds.rawValue, at: renderTime)
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
               hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true) {
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
               hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange, allowRangeMismatch: true) {
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
        let panelRows: Float = 18.0
        let rowHeight: Float = 13.0
        return max(Float(height) * 0.5 / (panelRows * rowHeight), 0.25)
    }

    private static func renderSourceAppearsProxy(
        sourceImage: FxImageTile,
        preparedAnalysis: StabilizerPreparedAnalysis
    ) -> Bool {
        guard let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: sourceImage),
              let analysisFrame = preparedAnalysis.frames.first
        else {
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

    private static func cachedAutoTransform(
        preparedAnalysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> StabilizerAutoTransform {
        let firstFrame = preparedAnalysis.frames.first
        let qualityModelKey: Int
        switch preparedAnalysis.qualityModel {
        case .fxplugHostAnalysis:
            qualityModelKey = 0
        case .eventAnalyzerCache:
            qualityModelKey = 1
        }
        let key = StabilizerAutoTransformCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            renderTimeValue: renderTime.value,
            renderTimeScale: renderTime.timescale,
            renderTimeEpoch: renderTime.epoch,
            outputWidth: Int32(clamping: Int(outputSize.x.rounded())),
            outputHeight: Int32(clamping: Int(outputSize.y.rounded())),
            analysisFrameCount: preparedAnalysis.frames.count,
            analysisFirstTime: firstFrame?.time.bitPattern ?? 0,
            analysisLastTime: preparedAnalysis.frames.last?.time.bitPattern ?? 0,
            analysisSampleWidth: Int32(clamping: firstFrame?.sampleWidth ?? 0),
            analysisSampleHeight: Int32(clamping: firstFrame?.sampleHeight ?? 0),
            analysisQualityModel: qualityModelKey,
            panSmoothSeconds: panSmoothSeconds.bitPattern,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            strideWobbleX: strengths.strideWobbleX.bitPattern,
            strideWobbleY: strengths.strideWobbleY.bitPattern,
            strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
            panStabilizationStrength: strengths.panStabilizationStrength.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern
        )

        autoTransformCacheLock.lock()
        if let cachedTransform = autoTransformCache[key] {
            autoTransformCacheLock.unlock()
            return cachedTransform
        }
        autoTransformCacheLock.unlock()

        let transform = AutoStabilizationEstimator.estimate(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )

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
        cacheIdentity: String?
    ) -> AutoCropFraming {
        let key = AutoCropFramingCacheKey(
            cacheIdentity: cacheIdentity,
            analysisRevision: analysisRevisionCacheKey(analysisRevision, cacheIdentity: cacheIdentity),
            renderTimeValue: renderTime.value,
            renderTimeScale: renderTime.timescale,
            renderTimeEpoch: renderTime.epoch,
            outputWidth: Int32(clamping: Int(outputSize.x.rounded())),
            outputHeight: Int32(clamping: Int(outputSize.y.rounded())),
            analysisFrameCount: preparedAnalysis.frames.count,
            analysisFirstTime: preparedAnalysis.frames.first?.time.bitPattern ?? 0,
            analysisLastTime: preparedAnalysis.frames.last?.time.bitPattern ?? 0,
            panSmoothSeconds: panSmoothSeconds.bitPattern,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDuration.bitPattern,
            leadTime: leadTime.bitPattern,
            holdTime: holdTime.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            renderQualityLevel: renderQualityLevel,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            strideWobbleX: strengths.strideWobbleX.bitPattern,
            strideWobbleY: strengths.strideWobbleY.bitPattern,
            strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
            panStabilizationStrength: strengths.panStabilizationStrength.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            currentTransform: AutoCropTransformSignature(currentTransform)
        )

        autoCropFramingCacheLock.lock()
        if let cachedFraming = autoCropFramingCache[key] {
            autoCropFramingCacheLock.unlock()
            return cachedFraming
        }
        autoCropFramingCacheLock.unlock()

        let framing = autoCropFraming(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            currentTransform: currentTransform,
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

        let context = AutoCropTransformContext(
            transform: currentTransform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let transitionDurationSeconds = autoCropTransitionDurationSeconds(transitionDuration)
        let leadTimeSeconds = autoCropLeadTimeSeconds(leadTime)
        let holdTimeSeconds = autoCropHoldTimeSeconds(holdTime)
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
            positionPixels: finalPositionPixels
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
            panSmoothSeconds: panSmoothSeconds.bitPattern,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDurationSeconds.bitPattern,
            leadTime: leadTimeSeconds.bitPattern,
            holdTime: holdTimeSeconds.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            strideWobbleX: strengths.strideWobbleX.bitPattern,
            strideWobbleY: strengths.strideWobbleY.bitPattern,
            strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
            panStabilizationStrength: strengths.panStabilizationStrength.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
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
            panSmoothSeconds: panSmoothSeconds.bitPattern,
            masterStrength: masterStrength.bitPattern,
            transitionDuration: transitionDurationSeconds.bitPattern,
            leadTime: leadTimeSeconds.bitPattern,
            holdTime: holdTimeSeconds.bitPattern,
            samplingProfile: samplingProfile.rawValue,
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            strideWobbleX: strengths.strideWobbleX.bitPattern,
            strideWobbleY: strengths.strideWobbleY.bitPattern,
            strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
            panStabilizationStrength: strengths.panStabilizationStrength.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern
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
            return AutoCropZoomPlan(keypoints: [])
        }

        let coarseSamples = autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            startSeconds: firstTime,
            endSeconds: lastTime,
            stepSeconds: samplingProfile.zoomKeypointCoarseStepSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            masterStrength: masterStrength,
            samplingProfile: samplingProfile,
            analysisRevision: analysisRevision,
            cacheIdentity: cacheIdentity
        )
        guard !coarseSamples.isEmpty else {
            return AutoCropZoomPlan(keypoints: [])
        }
        let coverageSamples = autoCropZoomDemandSamples(
            preparedAnalysis: preparedAnalysis,
            startSeconds: firstTime,
            endSeconds: lastTime,
            stepSeconds: samplingProfile.zoomKeypointCoverageStepSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
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

        let keypoints = autoCropZoomKeypoints(
            from: selected,
            firstTime: firstTime,
            lastTime: lastTime,
            leadTimeSeconds: leadTimeSeconds,
            holdTimeSeconds: holdTimeSeconds,
            transitionDurationSeconds: transitionDurationSeconds
        )

        if let strongest = keypoints.max(by: { $0.scale < $1.scale }) {
            os_log(
                "Auto Crop zoom keypoint plan | count %d strongestPeak %.3f start %.3f holdEnd %.3f end %.3f scale %.4f lead %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                keypoints.count,
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
                "Auto Crop zoom keypoint plan | count 0 lead %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                leadTimeSeconds
            )
        }

        return AutoCropZoomPlan(keypoints: keypoints)
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
                )
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

    private static func autoCropZoomKeypoints(
        from samples: [AutoCropZoomDemandSample],
        firstTime: Double,
        lastTime: Double,
        leadTimeSeconds: Double,
        holdTimeSeconds: Double,
        transitionDurationSeconds: Double
    ) -> [AutoCropZoomKeypoint] {
        samples
            .sorted { $0.seconds < $1.seconds }
            .map { sample in
                let keypointScale = autoCropZoomKeypointScale(forDemandScale: sample.scale)
                let durationScale = autoCropZoomDurationScale(forKeypointScale: keypointScale)
                let effectiveLeadTime = autoCropScaledZoomDuration(
                    leadTimeSeconds,
                    durationScale: durationScale
                )
                let effectiveHoldTime = autoCropScaledZoomDuration(
                    holdTimeSeconds,
                    durationScale: durationScale
                )
                let effectiveTransitionDuration = autoCropScaledZoomDuration(
                    transitionDurationSeconds,
                    durationScale: durationScale
                )
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
    }

    private static func autoCropZoomDurationScale(forKeypointScale scale: Float) -> Double {
        let safeScale = max(Float(1.0), scale.isFinite ? scale : Float(1.0))
        let delta = max(Float(0.0), safeScale - Float(1.0))
        guard delta > 0.0 else {
            return 0.0
        }
        let normalized = delta / stabilizerAutoCropDurationScaleReferenceDelta
        return Double(min(max(normalized, Float(0.0)), Float(1.0)))
    }

    private static func autoCropScaledZoomDuration(
        _ duration: Double,
        durationScale: Double
    ) -> Double {
        let safeDuration = duration.isFinite ? max(0.0, duration) : 0.0
        let safeScale = durationScale.isFinite ? min(max(durationScale, 0.0), 1.0) : 0.0
        guard safeDuration > 0.0, safeScale > 0.0 else {
            return 0.0
        }
        let scaledDuration = safeDuration * safeScale
        return min(
            safeDuration,
            max(stabilizerAutoCropMinimumScaledDurationSeconds, scaledDuration)
        )
    }

    private static func autoCropZoomKeypointScale(forDemandScale demandScale: Float) -> Float {
        let safeDemandScale = max(Float(1.0), demandScale.isFinite ? demandScale : Float(1.0))
        let paddedScale = safeDemandScale + stabilizerAutoCropActiveScalePadding
        let paddedDelta = max(Float(0.0), paddedScale - Float(1.0))
        guard paddedDelta <= stabilizerAutoCropSubtleZoomMaximumDelta else {
            return paddedScale
        }
        let attenuatedScale = Float(1.0) + (paddedDelta * stabilizerAutoCropSubtleZoomMultiplier)
        let safetyFloor = max(Float(1.0), safeDemandScale - stabilizerAutoCropKeypointCoverageToleranceDelta)
        return max(attenuatedScale, safetyFloor)
    }

    private static func autoCropZoomDemandSamples(
        preparedAnalysis: StabilizerPreparedAnalysis,
        startSeconds: Double,
        endSeconds: Double,
        stepSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        masterStrength: Float,
        samplingProfile: AutoCropSamplingProfile,
        analysisRevision: UInt64,
        cacheIdentity: String?
    ) -> [AutoCropZoomDemandSample] {
        let step = max(stepSeconds, 0.25)
        var samples: [AutoCropZoomDemandSample] = []
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
            ) {
                samples.append(sample)
            }
            seconds += step
        }
        if abs((samples.last?.seconds ?? startSeconds) - endSeconds) > 1e-6,
           let lastSample = autoCropZoomDemandSample(
               preparedAnalysis: preparedAnalysis,
               seconds: endSeconds,
               outputSize: outputSize,
               panSmoothSeconds: panSmoothSeconds,
               strengths: strengths,
               masterStrength: masterStrength,
               samplingProfile: samplingProfile,
               analysisRevision: analysisRevision,
               cacheIdentity: cacheIdentity
           ) {
            samples.append(lastSample)
        }
        return samples
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
        let context = AutoCropTransformContext(
            transform: transform,
            outputSize: outputSize,
            masterStrength: masterStrength
        )
        let positionPixels = blackSafeAutoCropPosition(
            preferredPositionPixels: transform.macroPixelOffset * masterStrength,
            context: context,
            samplingProfile: samplingProfile
        )
        let scale = requiredAutoCropScale(
            context: context,
            cropPositionPixels: positionPixels,
            sampleSteps: samplingProfile.scaleSearchSampleSteps,
            iterations: samplingProfile.scaleSearchIterations
        )
        return AutoCropZoomDemandSample(
            seconds: seconds,
            scale: scale,
            positionPixels: positionPixels
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
        let sampleTime = CMTimeMakeWithSeconds(seconds, preferredTimescale: 60000)
        switch samplingProfile {
        case .playback:
            return AutoStabilizationEstimator.proxyPlaybackEstimate(
                preparedAnalysis: preparedAnalysis,
                renderTime: sampleTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
        case .full:
            return cachedAutoTransform(
                preparedAnalysis: preparedAnalysis,
                renderTime: sampleTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
        }
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
        return bestSample
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

    private static func autoCropSamplingProfile(forQualityLevel qualityLevel: UInt32, renderSourceIsProxy: Bool) -> AutoCropSamplingProfile {
        if renderSourceIsProxy || qualityLevel == 0 {
            return .playback
        }
        return .full
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
        switch samplingProfile {
        case .playback:
            return AutoStabilizationEstimator.proxyPlaybackEstimate(
                preparedAnalysis: preparedAnalysis,
                renderTime: sampleTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
        case .full:
            return cachedAutoTransform(
                preparedAnalysis: preparedAnalysis,
                renderTime: sampleTime,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                analysisRevision: analysisRevision,
                cacheIdentity: cacheIdentity
            )
        }
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
        transform.pixelOffset = transform.macroPixelOffset + transform.microPixelOffset + transform.strideWobblePixelOffset
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
            pathX: autoCropInterpolatedPreparedValue(preparedAnalysis.pathX, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathY: autoCropInterpolatedPreparedValue(preparedAnalysis.pathY, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
            pathRoll: autoCropInterpolatedPreparedValue(preparedAnalysis.pathRoll, lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction),
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
        guard revision > 0.0 else {
            return
        }
        let parameterNeedsUpdate = currentParameterValue.map { abs($0 - revision) >= 0.5 } ?? false
        if currentParameterValue != nil,
           !parameterNeedsUpdate {
            statusLock.lock()
            lastPublishedRenderRevision = revision
            statusLock.unlock()
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        statusLock.lock()
        let recentlyAttempted = lastRenderRevisionPublishAttemptRevision == revision
            && (now - lastRenderRevisionPublishAttemptWallTime) < stabilizerRenderRevisionRetryIntervalSeconds
        let shouldPublish = force || ((parameterNeedsUpdate || lastPublishedRenderRevision != revision) && !recentlyAttempted)
        if shouldPublish {
            lastRenderRevisionPublishAttemptRevision = revision
            lastRenderRevisionPublishAttemptWallTime = now
        }
        statusLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if settingAPI.setFloatValue(revision, toParameter: ParameterID.renderRevision.rawValue, at: .zero) {
            statusLock.lock()
            lastPublishedRenderRevision = revision
            statusLock.unlock()
        } else {
            NSLog("TokyoWalkingStabilizer: failed to update Render Revision parameter.")
        }
    }

    private func shouldRetryRenderRevisionPublish(_ revision: Double) -> Bool {
        guard revision > 0.0 else {
            return false
        }
        let now = Date().timeIntervalSinceReferenceDate
        statusLock.lock()
        defer { statusLock.unlock() }
        if lastRenderRevisionPublishAttemptRevision == revision,
           (now - lastRenderRevisionPublishAttemptWallTime) < stabilizerRenderRevisionRetryIntervalSeconds {
            return false
        }
        lastRenderRevisionPublishAttemptRevision = revision
        lastRenderRevisionPublishAttemptWallTime = now
        return true
    }

    @discardableResult
    private func publishRenderAnalysisDecisionIfChanged(_ signature: RenderAnalysisDecisionSignature) -> Bool {
        statusLock.lock()
        let shouldPublish = lastRenderAnalysisDecisionSignature != signature
        if shouldPublish {
            lastRenderAnalysisDecisionSignature = signature
        }
        statusLock.unlock()
        guard shouldPublish else {
            return false
        }

        let decision = "Render Host Analysis decision | FxPlug \(signature.fxPlugVersion) | transform \(signature.transformEnabled ? "on" : "off") | completed \(signature.hasCompletedHostAnalysis ? "yes" : "no") | project cache \(signature.configuredProjectBundleCache ? "configured" : "not configured") | prepared \(signature.renderUsesPreparedAnalysis ? "yes" : "no") | stabilization \(signature.stabilizationActive ? "active" : "inactive") | debug overlay \(signature.debugOverlayActive ? "active" : "inactive") | proxy \(signature.renderSourceIsProxy ? "yes" : "no") | identity \(signature.renderCacheIdentityShort) | auto crop \(signature.autoCropEnabled ? "on" : "off") profile \(signature.autoCropProfileName) | frames \(signature.hostAnalysisFrameCount)"
        statusLock.lock()
        let shouldPublishString = lastRenderAnalysisDecision != decision
        if shouldPublishString {
            lastRenderAnalysisDecision = decision
        }
        statusLock.unlock()
        if shouldPublishString {
            os_log("%{public}@", log: stabilizerHostAnalysisLog, type: .default, decision)
        }
        return true
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
        if let expectedRange,
           let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
           !StabilizerHostAnalysisStore.cacheIdentity(preferredIdentity, matches: expectedRange) {
            publishHostAnalysisCacheIdentity(nil, force: true)
        }
        let loadedCache: Bool
        if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
           hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange) {
            loadedCache = true
        } else {
            loadedCache = hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange)
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
            _ = hostAnalysisStore.persistCompletedAnalysisIfPossible()
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
                    guard let eventResolution = Self.fcpEventRoot(containing: projectMediaURL, in: bundleRoot, expectedRange: expectedRange) else {
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
        triggerReason: String,
        projectDocumentID: UInt?,
        forceRefresh: Bool
    ) -> Bool {
        let lookup = Self.activeFinalCutLibraryEventRoot(expectedRange: expectedRange, projectDocumentID: projectDocumentID)
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

        var eventIdentifier: String? {
            identifiers.last
        }
    }

    private static func activeFinalCutLibraryEventRoot(
        expectedRange: HostAnalysisExpectedRange?,
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
        guard activeLibraries.rejectReason == nil else {
            return (nil, activeLibraries.rejectReason ?? "Active Final Cut library preferences unavailable.")
        }
        let bundleCandidates = activeLibraries.bundleURLs
        guard !bundleCandidates.isEmpty else {
            return (nil, "Final Cut Pro active library list is empty.")
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
                    "Ambiguous active Final Cut libraries: \(bundleCandidates.map(\.bundleRoot.path).joined(separator: " | ")). \(rangedSelection.rejectReason) \(sidebarSelection.rejectReason)"
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
            expectedRange: expectedRange
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
                guard let bookmarks = plist["FFActiveLibraries"] as? [Data] else {
                    rejectionReasons.append("FFActiveLibraries missing at \(preferenceURL.path)")
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
                    "Active library resolver read %{public}d active library bookmark(s) from %{public}@; resolved=%{public}@ rejects=%{public}@.",
                    log: stabilizerHostAnalysisLog,
                    type: .default,
                    bookmarks.count,
                    preferenceURL.path,
                    uniqueCandidates.map(\.bundleRoot.path).joined(separator: " | "),
                    bookmarkRejections.joined(separator: " | ")
                )
                if !uniqueCandidates.isEmpty {
                    return (uniqueCandidates, nil)
                }
                rejectionReasons.append("no usable FFActiveLibraries .fcpbundle bookmark in \(preferenceURL.path): \(bookmarkRejections.joined(separator: " | "))")
            } catch {
                rejectionReasons.append("preferences unreadable at \(preferenceURL.path): \(error.localizedDescription)")
            }
        }
        return ([], rejectionReasons.joined(separator: " ; "))
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
        do {
            let handle = try FileHandle(forReadingFrom: libraryMarkerURL)
            try? handle.close()
        } catch {
            return "bookmark \(index) active library marker unreadable at \(libraryMarkerURL.path): \(error.localizedDescription)"
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

    private static func activeFinalCutLibrarySidebarEventSelection(
        from candidates: [FCPActiveLibraryBundleCandidate]
    ) -> (selection: FCPActiveLibraryEventSelection?, rejectReason: String) {
        let sidebarLookup = finalCutLibrarySidebarSelection()
        guard let sidebarSelection = sidebarLookup.selection else {
            return (nil, "Final Cut Pro library sidebar selection unavailable: \(sidebarLookup.rejectReason)")
        }
        guard let eventIdentifier = sidebarSelection.eventIdentifier else {
            return (nil, "Final Cut Pro library sidebar selection has no Event identifier: \(sidebarSelection.rawSelection)")
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

            let eventLookup = eventRootForEventIdentifier(eventIdentifier, in: bundleRoot)
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
                NSString.self,
                NSNumber.self,
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
        expectedRange: HostAnalysisExpectedRange?
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
        appliedPixelOffset: vector_float2,
        appliedRotationRadians: Float
    ) {
        let status = String(
            format: "Ready (%d) | FxPlug %@ | warp q %.2f shear %.4f %.4f yp %.4f %.4f persp %.4f %.4f | turn %.1fs q %.2f smooth %d@%.2fs | X %.1f Y %.1f R %.2f | raw X %.1f Y %.1f R %.2f | smooth dX %.1f dY %.1f dR %.2f | track q %.2f walk q %.2f motion q %.2f blur %.2f resid %.4f | foot raw X %.3f Y %.3f R %.3f q %.2f eff X %.2f Y %.2f R %.2f | stride q %.2f eff X %.2f Y %.2f R %.2f | blocks %d/%d edge %d/%d | x turn %.1f stride %.1f | y foot %.1f stride %.1f",
            frameCount,
            tokyoWalkingStabilizerVersion,
            autoTransform.warpConfidence,
            autoTransform.shear.x,
            autoTransform.shear.y,
            autoTransform.yawPitchProxy.x,
            autoTransform.yawPitchProxy.y,
            autoTransform.perspective.x,
            autoTransform.perspective.y,
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
            autoTransform.footstepImpulse.x,
            autoTransform.footstepImpulse.y,
            autoTransform.footstepImpulse.z,
            autoTransform.microConfidence,
            autoTransform.effectiveMicroJitterStrength.x,
            autoTransform.effectiveMicroJitterStrength.y,
            autoTransform.effectiveMicroJitterStrength.z,
            autoTransform.strideConfidence,
            autoTransform.effectiveStrideWobbleStrength.x,
            autoTransform.effectiveStrideWobbleStrength.y,
            autoTransform.effectiveStrideWobbleStrength.z,
            autoTransform.acceptedBlockCount,
            autoTransform.totalBlockCount,
            autoTransform.searchRadiusHitCount,
            autoTransform.searchRadiusTotalCount,
            autoTransform.macroPixelOffset.x,
            autoTransform.strideWobblePixelOffset.x,
            autoTransform.microPixelOffset.y,
            autoTransform.strideWobblePixelOffset.y
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
        diagnostic: vector_float4,
        diagnostic2: vector_float4,
        diagnostic3: vector_float4,
        diagnostic4: vector_float4,
        diagnostic5: vector_float4
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
            "Debug Overlay runtime truth | FxPlug %{public}@ | render %.3f analysis %.3f | prepared yes | stabilization active | overlay active | proxy %{public}@ | identity %{public}@ | frames %{public}d | X %.2f Y %.2f R %.3f | raw X %.2f Y %.2f R %.3f | FJIT %.3f %.3f %.3f q %.2f eff %.2f %.2f %.2f rawCorr %.3f %.3f limitedCorr %.3f %.3f pulseLimited %.3f %.3f | SWOB %.2f %.2f %.2f q %.2f eff %.2f %.2f %.2f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            renderSeconds,
            analysisSeconds,
            renderSourceIsProxy ? "yes" : "no",
            cacheIdentityShort,
            frameCount,
            autoTransform.pixelOffset.x,
            autoTransform.pixelOffset.y,
            autoTransform.rotationDegrees,
            autoTransform.rawPixelOffset.x,
            autoTransform.rawPixelOffset.y,
            autoTransform.rawRotationDegrees,
            autoTransform.footstepImpulse.x,
            autoTransform.footstepImpulse.y,
            autoTransform.footstepImpulse.z,
            autoTransform.microConfidence,
            autoTransform.effectiveMicroJitterStrength.x,
            autoTransform.effectiveMicroJitterStrength.y,
            autoTransform.effectiveMicroJitterStrength.z,
            autoTransform.rawFootstepCorrection.x,
            autoTransform.rawFootstepCorrection.y,
            autoTransform.limitedFootstepCorrection.x,
            autoTransform.limitedFootstepCorrection.y,
            autoTransform.footstepPulseLimited.x,
            autoTransform.footstepPulseLimited.y,
            autoTransform.strideWobblePixelOffset.x,
            autoTransform.strideWobblePixelOffset.y,
            autoTransform.strideWobbleRotationDegrees,
            autoTransform.strideConfidence,
            autoTransform.effectiveStrideWobbleStrength.x,
            autoTransform.effectiveStrideWobbleStrength.y,
            autoTransform.effectiveStrideWobbleStrength.z
        )
        os_log(
            "Debug Overlay bars motion | FxPlug %{public}@ | X OFFSET %.3f Y OFFSET %.3f ROLL %.3f FOOT STEP %.3f STRIDE %.3f FAR WARP %.3f TURN %.3f SMOOTH %.3f CROP ZOOM %.3f CROP X %.2f CROP Y %.2f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            diagnostic.x,
            diagnostic.y,
            diagnostic.z,
            diagnostic2.y,
            diagnostic2.z,
            diagnostic2.w,
            diagnostic2.x,
            diagnostic3.x,
            diagnostic5.y,
            autoCropFraming.positionPixels.x,
            autoCropFraming.positionPixels.y
        )
        os_log(
            "Debug Overlay bars quality | FxPlug %{public}@ | FOOT CONF %.3f STRIDE CONF %.3f WARP CONF %.3f TURN CONF %.3f TRACK CONF %.3f SHARPNESS %.3f MATCH QUAL %.3f EDGE HIT %.3f WALK CONF %.3f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            tokyoWalkingStabilizerVersion,
            diagnostic3.y,
            diagnostic3.z,
            diagnostic3.w,
            diagnostic4.x,
            diagnostic4.y,
            diagnostic4.z,
            diagnostic4.w,
            diagnostic.w,
            diagnostic5.x
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

    func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile], pluginState: Data?, at renderTime: CMTime) throws {
        guard let state = Self.pluginState(from: pluginState) else {
            return
        }
        guard sourceImages.indices.contains(0) else {
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
        guard
            let commandQueue = deviceCache.commandQueue(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat),
            let device = deviceCache.device(with: sourceImage.deviceRegistryID),
            let inputTexture = sourceImage.metalTexture(for: device),
            let outputTexture = destinationImage.metalTexture(for: device),
            let pipelineState = deviceCache.pipelineState(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            NSLog("TokyoWalkingStabilizer: render skipped because Metal input/output resources were unavailable.")
            return
        }

        let outputWidth = destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left
        let outputHeight = destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom
        let halfOutputWidth = Float(outputWidth) * 0.5
        let halfOutputHeight = Float(outputHeight) * 0.5
        var viewportSize = simd_uint2(UInt32(outputWidth), UInt32(outputHeight))
        let masterStrength = Float(max(0.0, state.strength))
        let transformEnabled = masterStrength > 0.0001
        let autoTransform: StabilizerAutoTransform
        var activePreparedAnalysis: StabilizerPreparedAnalysis?
        var activeAnalysisRenderTime: CMTime?
        var renderSourceIsProxy = false
        var renderUsesPreparedAnalysis = false
        let expectedRange = currentRenderExpectedRange(from: state)
        let preferredCacheIdentity = currentPreferredHostAnalysisCacheIdentity()
        let correctionStrengths = StabilizerCorrectionStrengths(
            microJitterX: state.microJitterXStrength,
            microJitterY: state.microJitterYStrength,
            microJitterRotation: state.microJitterRotationStrength,
            strideWobbleX: state.strideWobbleXStrength,
            strideWobbleY: state.strideWobbleYStrength,
            strideWobbleRotation: state.strideWobbleRotationStrength,
            panStabilizationStrength: state.panStabilizationStrength,
            farFieldWarp: state.farFieldWarpStrength
        )
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
        if transformEnabled,
           canUseHostAnalysisStoreForRender,
           let preparedAnalysis = hostAnalysisStore.preparedAnalysisForRender(
               validating: sourceImage,
               at: renderTime,
               preferredCacheIdentity: preferredCacheIdentity,
               expectedRange: expectedRange
           ) {
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
            let usesLightweightPreviewStabilization = renderSourceIsProxy || state.renderQualityLevel == 0
            if usesLightweightPreviewStabilization {
                autoTransform = AutoStabilizationEstimator.proxyPlaybackEstimate(
                    preparedAnalysis: preparedAnalysis,
                    renderTime: analysisRenderTime,
                    outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                    panSmoothSeconds: state.panSmoothSeconds,
                    strengths: correctionStrengths
                )
            } else {
                autoTransform = Self.cachedAutoTransform(
                    preparedAnalysis: preparedAnalysis,
                    renderTime: analysisRenderTime,
                    outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                    panSmoothSeconds: state.panSmoothSeconds,
                    strengths: correctionStrengths,
                    analysisRevision: renderStoreRevision,
                    cacheIdentity: renderCacheIdentity
                )
            }
        } else {
            autoTransform = .identity
        }
        let debugOverlayActive = state.debugOverlay && transformEnabled && renderUsesPreparedAnalysis
        if renderCacheIdentity == nil {
            renderCacheIdentity = storeSnapshot.activeCacheIdentity
        }
        let renderCacheIdentityShort = Self.shortRenderCacheIdentity(renderCacheIdentity)
        let renderStatusReason: String?
        if transformEnabled && renderUsesPreparedAnalysis {
            renderStatusReason = "prepared=yes debug=\(state.debugOverlay ? "on" : "off") proxy=\(renderSourceIsProxy ? "yes" : "no") identity=\(renderCacheIdentityShort)"
        } else if transformEnabled {
            let preferredIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferredIdentity,
               !preferredIdentity.isEmpty,
               !StabilizerHostAnalysisStore.cacheIdentity(preferredIdentity, matches: expectedRange) {
                renderStatusReason = "cacheRangeMismatch: preferred identity \(Self.shortRenderCacheIdentity(preferredIdentity)) did not match expected render range"
            } else if hasCompletedHostAnalysis || hasPreparedHostAnalysis || configuredProjectBundleCache || !(preferredIdentity ?? "").isEmpty {
                renderStatusReason = "loadedButNotRendering: prepared=no completed=\(hasCompletedHostAnalysis ? "yes" : "no") loaded=\(hasPreparedHostAnalysis ? "yes" : "no") projectCache=\(configuredProjectBundleCache ? "configured" : "not configured") debug=\(state.debugOverlay ? "on" : "off") identity=\(renderCacheIdentityShort)"
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
                renderSourceIsProxy: renderSourceIsProxy,
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
        renderStoreRevision = storeSnapshot.revision
        let renderStoreChangedStatus = renderStoreRevision != state.hostAnalysisRevision
        let renderRevisionNeedsRetry = abs(renderInvalidationToken - state.renderRevision) >= 0.5
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
        let debugOverlayScale: Float
        let diagnostic: vector_float4
        let diagnostic2: vector_float4
        let diagnostic3: vector_float4
        let diagnostic4: vector_float4
        var diagnostic5: vector_float4
        if debugOverlayActive {
            debugOverlayScale = Self.debugOverlayScale(
                outputWidth: Int(outputWidth),
                outputHeight: Int(outputHeight),
                renderSourceIsProxy: renderSourceIsProxy
            )
            let diagnosticScaleX = max(1.0, Float(outputWidth) * 0.05)
            let diagnosticScaleY = max(1.0, Float(outputHeight) * 0.05)
            let turnScaleX = max(1.0, Float(outputWidth) * 0.01)
            let turnScaleY = max(1.0, Float(outputHeight) * 0.01)
            let temporalSmoothingScale = max(1.0, min(Float(outputWidth), Float(outputHeight)) * 0.01)
            let searchRadiusQuality: Float
            if autoTransform.searchRadiusTotalCount > 0 {
                let searchRadiusHitRatio = min(1.0, Float(autoTransform.searchRadiusHitCount) / Float(autoTransform.searchRadiusTotalCount))
                searchRadiusQuality = 1.0 - searchRadiusHitRatio
            } else {
                searchRadiusQuality = 0.0
            }
            let fitQuality = Self.debugMatchQuality(
                residual: autoTransform.residual,
                preparedAnalysis: activePreparedAnalysis
            )
            let rotationActivity = min(1.0, max(
                abs(autoTransform.rotationDegrees),
                abs(autoTransform.rawRotationDegrees),
                abs(autoTransform.footstepJitterRotationDegrees) + abs(autoTransform.strideWobbleRotationDegrees),
                abs(autoTransform.temporalSmoothingRotationDelta)
            ) / 0.05)
            let separatedTurnActivity = simd_length(vector_float2(
                autoTransform.macroPixelOffset.x / turnScaleX,
                autoTransform.macroPixelOffset.y / turnScaleY
            ))
            let collapsedProxyTurnActivity = abs(autoTransform.pixelOffset.x) / turnScaleX
                * min(1.0, autoTransform.turnConfidence)
            let turnActivity = min(1.0, max(separatedTurnActivity, collapsedProxyTurnActivity))
            let separatedTemporalSmoothingActivity = max(
                simd_length(autoTransform.temporalSmoothingPixelDelta) / temporalSmoothingScale,
                abs(autoTransform.temporalSmoothingRotationDelta) / 0.05
            )
            let collapsedProxySmoothingActivity = autoTransform.temporalSmoothingSampleCount > 1
                ? max(
                    simd_length(autoTransform.pixelOffset) / temporalSmoothingScale,
                    abs(autoTransform.rotationDegrees) / 0.05
                )
                : 0.0
            let temporalSmoothingActivity = min(1.0, max(
                separatedTemporalSmoothingActivity,
                collapsedProxySmoothingActivity
            ))
            let footstepJitterActivity = min(1.0, max(
                simd_length(vector_float2(
                    autoTransform.limitedFootstepCorrection.x / diagnosticScaleX,
                    autoTransform.limitedFootstepCorrection.y / diagnosticScaleY
                )),
                abs(autoTransform.footstepJitterRotationDegrees) / 5.0
            ))
            let strideWobbleActivity = min(1.0, max(
                simd_length(vector_float2(
                    autoTransform.strideWobblePixelOffset.x / diagnosticScaleX,
                    autoTransform.strideWobblePixelOffset.y / diagnosticScaleY
                )),
                abs(autoTransform.strideWobbleRotationDegrees) / 5.0
            ))
            let farFieldWarpActivity = min(1.0, max(
                simd_length(autoTransform.shear) / 0.016,
                simd_length(autoTransform.yawPitchProxy) / 0.010,
                simd_length(autoTransform.perspective) / 0.006
            ))
            diagnostic = vector_float4(
                min(1.0, abs(autoTransform.pixelOffset.x) / diagnosticScaleX),
                min(1.0, abs(autoTransform.pixelOffset.y) / diagnosticScaleY),
                rotationActivity,
                searchRadiusQuality
            )
            diagnostic2 = vector_float4(
                turnActivity,
                footstepJitterActivity,
                strideWobbleActivity,
                farFieldWarpActivity
            )
            diagnostic3 = vector_float4(
                temporalSmoothingActivity,
                min(1.0, autoTransform.microConfidence),
                min(1.0, autoTransform.strideConfidence),
                min(1.0, autoTransform.warpConfidence)
            )
            diagnostic4 = vector_float4(
                min(1.0, autoTransform.turnConfidence),
                min(1.0, autoTransform.trackingConfidence),
                AutoStabilizationEstimator.blurEvidenceQuality(autoTransform.blurAmount),
                fitQuality
            )
            diagnostic5 = vector_float4(
                min(1.0, autoTransform.walkingTrackingConfidence),
                0.0,
                0.0,
                0.0
            )
        } else {
            debugOverlayScale = 1.0
            diagnostic = vector_float4(0.0, 0.0, 0.0, 0.0)
            diagnostic2 = vector_float4(0.0, 0.0, 0.0, 0.0)
            diagnostic3 = vector_float4(0.0, 0.0, 0.0, 0.0)
            diagnostic4 = vector_float4(0.0, 0.0, 0.0, 0.0)
            diagnostic5 = vector_float4(0.0, 0.0, 0.0, 0.0)
        }
        let autoCropFraming: AutoCropFraming
        let autoCropSamplingProfile = Self.autoCropSamplingProfile(forQualityLevel: state.renderQualityLevel, renderSourceIsProxy: renderSourceIsProxy)
        if state.autoCropEnabled,
           renderUsesPreparedAnalysis,
           let preparedAnalysis = activePreparedAnalysis {
            autoCropFraming = Self.cachedAutoCropFraming(
                preparedAnalysis: preparedAnalysis,
                renderTime: activeAnalysisRenderTime ?? hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis),
                currentTransform: autoTransform,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: state.panSmoothSeconds,
                strengths: correctionStrengths,
                masterStrength: masterStrength,
                transitionDuration: state.autoCropTransitionDuration,
                leadTime: state.autoCropLeadTime,
                holdTime: state.autoCropHoldTime,
                samplingProfile: autoCropSamplingProfile,
                renderQualityLevel: state.renderQualityLevel,
                analysisRevision: renderStoreRevision,
                cacheIdentity: renderCacheIdentity
            )
        } else {
            autoCropFraming = .identity
        }
        if debugOverlayActive {
            diagnostic5.y = min(1.0, max(0.0, (autoCropFraming.scale - 1.0) / 0.25))
            logDebugOverlayRenderTruthIfNeeded(
                debugOverlayActive: true,
                transformEnabled: transformEnabled,
                renderUsesPreparedAnalysis: renderUsesPreparedAnalysis,
                renderSourceIsProxy: renderSourceIsProxy,
                renderTime: renderTime,
                analysisRenderTime: activeAnalysisRenderTime,
                frameCount: Int(state.hostAnalysisFrameCount),
                cacheIdentityShort: renderCacheIdentityShort,
                autoTransform: autoTransform,
                autoCropFraming: autoCropFraming,
                diagnostic: diagnostic,
                diagnostic2: diagnostic2,
                diagnostic3: diagnostic3,
                diagnostic4: diagnostic4,
                diagnostic5: diagnostic5
            )
        }

        var transform = TokyoWalkingStabilizerTransformUniforms(
            pixelOffset: autoTransform.pixelOffset * masterStrength,
            rotationRadians: autoTransform.rotationDegrees * .pi / 180.0 * masterStrength,
            rotationSinCos: vector_float2(
                Darwin.sinf(-autoTransform.rotationDegrees * .pi / 180.0 * masterStrength),
                Darwin.cosf(-autoTransform.rotationDegrees * .pi / 180.0 * masterStrength)
            ),
            strength: 1.0,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            diagnostic: diagnostic,
            diagnostic2: diagnostic2,
            diagnostic3: diagnostic3,
            diagnostic4: diagnostic4,
            diagnostic5: diagnostic5,
            shear: autoTransform.shear * masterStrength,
            perspective: (autoTransform.perspective + autoTransform.yawPitchProxy) * masterStrength,
            edgeMode: Float(state.edgeDisplayMode),
            debugOverlay: debugOverlayActive ? 1.0 : 0.0,
            debugMode: renderSourceIsProxy ? 2.0 : 1.0,
            debugOverlayScale: debugOverlayScale,
            autoCropScale: autoCropFraming.scale,
            autoCropPositionPixels: autoCropFraming.positionPixels
        )
        if debugOverlayActive {
            publishHostAnalysisRenderDiagnostics(
                frameCount: Int(state.hostAnalysisFrameCount),
                panSmoothSeconds: state.panSmoothSeconds,
                autoTransform: autoTransform,
                appliedPixelOffset: transform.pixelOffset,
                appliedRotationRadians: transform.rotationRadians
            )
        }

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

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        deviceCache.returnCommandQueueToCache(commandQueue: commandQueue)
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
