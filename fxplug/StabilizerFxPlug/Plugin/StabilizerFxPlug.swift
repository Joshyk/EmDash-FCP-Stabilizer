import AppKit
import CoreMedia
import Foundation
import Metal
import os.log
import simd

private enum ParameterID: UInt32 {
    case strength = 1
    case xStrength = 7
    case rotationStrength = 8
    case panSmoothSeconds = 9
    case debugOverlay = 10
    case startHostAnalysis = 14
    case hostAnalysisStatus = 15
    case stabilizerInfo = 32
    case clearHostAnalysisCache = 17
    case yStrength = 18
    case sampleScale = 19
    case renderRevision = 20
    case panStabilizationStrength = 23
    case walkingBobStrength = 26
    case edgeDisplayMode = 27
    case farFieldWarpStrength = 28
    case strideWobbleXStrength = 29
    case strideWobbleYStrength = 30
    case strideWobbleRotationStrength = 31
    case hostAnalysisCacheIdentity = 33
}

private let stabilizerFxPlugVersion = "0.3.40"
private let stabilizerHostAnalysisLog = OSLog(subsystem: "com.justadev.StabilizerFxPlug", category: "HostAnalysis")
private let stabilizerFixedStrideWobbleWindowSeconds = 2.0
private let stabilizerFixedWalkingBobWindowSeconds = 2.5
private let stabilizerMinimumTurnDetectionWindowSeconds = stabilizerFixedStrideWobbleWindowSeconds
private let stabilizerProjectCacheUnavailableMessage = "Project Bundle Cache Unavailable - Event Analysis Files Unavailable"

private enum StabilizerEdgeDisplayMode: Int32 {
    case stretchEdges = 0
    case blackOutside = 1
}

private enum StabilizerSampleScale: Int32 {
    case original = 0
    case scale75 = 1
    case scale50 = 2
    case scale25 = 3
    case scale10 = 4

    static let menuEntries = ["100%", "75%", "50%", "25%", "10%"]
    static let defaultScale: StabilizerSampleScale = .scale10

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

    static func scale(for rawValue: Int32) -> StabilizerSampleScale {
        StabilizerSampleScale(rawValue: rawValue) ?? defaultScale
    }
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
    var walkingBobStrength: Double
    var farFieldWarpStrength: Double
    var panSmoothSeconds: Double
    var edgeDisplayMode: Int32
    var debugOverlay: Bool
    var sampleScale: Int32
    var hostAnalysisFrameCount: Int32
    var hostAnalysisRevision: UInt64
    var renderRevision: Double
    var inputRangeStartSeconds: Double
    var inputRangeDurationSeconds: Double
    var inputFrameDurationSeconds: Double
}

private struct HostAnalysisExpectedRange {
    let startSeconds: Double
    let durationSeconds: Double
    let frameDurationSeconds: Double

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
}

private enum ActiveHostAnalysisCleanupRoute {
    case resolved(sessionID: UUID, store: StabilizerHostAnalysisStore)
    case failed(reason: String)
}

private struct StabilizerSourceFrameInfo {
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

private enum StabilizerOriginalMediaPolicy {
    private static let proxyScaleTolerance = 0.05

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
        guard let frameInfo = frameInfo(for: frame) else {
            return "Host Analysis received a source frame without pixel transform; original media could not be confirmed."
        }
        let scaleX = frameInfo.pixelScaleX
        let scaleY = frameInfo.pixelScaleY
        guard scaleX.isFinite, scaleY.isFinite else {
            return "Host Analysis received a source frame with invalid pixel transform; original media could not be confirmed."
        }
        let scaleDelta = max(abs(scaleX - 1.0), abs(scaleY - 1.0))
        guard scaleDelta <= proxyScaleTolerance else {
            return String(
                format: "Host Analysis received scaled/proxy media (pixel transform %.2fx, %.2fx). Use original media and rerun Host Analysis.",
                scaleX,
                scaleY
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

@objc(StabilizerFxPlugPlugIn)
final class StabilizerFxPlugPlugIn: NSObject, FxTileableEffect, FxAnalyzer, FxCustomParameterViewHost_v2 {
    private static let sharedHostAnalysisStore: StabilizerHostAnalysisStore = {
        let store = StabilizerHostAnalysisStore()
        return store
    }()
    private final class SerialHostAnalysisRequest {
        let plugin: StabilizerFxPlugPlugIn
        let analysisAPI: FxAnalysisAPI

        init(plugin: StabilizerFxPlugPlugIn, analysisAPI: FxAnalysisAPI) {
            self.plugin = plugin
            self.analysisAPI = analysisAPI
        }
    }

    private static let serialAnalysisQueueLock = NSLock()
    private static var serialAnalysisQueue: [SerialHostAnalysisRequest] = []
    private static let activeAnalysisStoreLock = NSLock()
    private static var activeAnalysisSessions: [UUID: ActiveHostAnalysisSession] = [:]
    private static var hostAnalysisStartReserved = false
    private static let stabilizerInfoViewLock = NSLock()
    private static let stabilizerInfoViews = NSHashTable<StabilizerInfoScrollView>.weakObjects()
    private static var latestStabilizerInfo = "FxPlug \(stabilizerFxPlugVersion)\nNo Analysis"

    private let apiManager: PROAPIAccessing
    private let statusLock = NSLock()
    private let cacheIdentityLock = NSLock()
    private let persistentCacheMonitorQueue = DispatchQueue(label: "com.justadev.StabilizerFxPlug.PersistentCacheMonitor")
    private var lastPublishedStatus = ""
    private var lastPublishedInfo = ""
    private var lastPublishedRenderRevision: Double?
    private var lastPublishedHostAnalysisCacheIdentity: String?
    private var lastScheduledPostAnalysisPublishRevision: Double?
    private var lastRenderAnalysisDecision = ""
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
        NSLog("StabilizerFxPlug: runtime initialized version \(stabilizerFxPlugVersion).")
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
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Footstep Jitter Y Strength",
            parameterID: ParameterID.yStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Footstep Jitter Rotation Strength",
            parameterID: ParameterID.rotationStrength.rawValue,
            defaultValue: 0.2,
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
            defaultValue: 0.65,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Stride Wobble Y Strength",
            parameterID: ParameterID.strideWobbleYStrength.rawValue,
            defaultValue: 0.70,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Stride Wobble Rotation Strength",
            parameterID: ParameterID.strideWobbleRotationStrength.rawValue,
            defaultValue: 0.2,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Walking Bob Removal",
            parameterID: ParameterID.walkingBobStrength.rawValue,
            defaultValue: 0.75,
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
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 4.0,
            sliderMin: 0.0,
            sliderMax: 4.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Turn Smoothing Strength",
            parameterID: ParameterID.panStabilizationStrength.rawValue,
            defaultValue: 1.0,
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
            defaultValue: 6.0,
            parameterMin: stabilizerMinimumTurnDetectionWindowSeconds,
            parameterMax: 120.0,
            sliderMin: stabilizerMinimumTurnDetectionWindowSeconds,
            sliderMax: 30.0,
            delta: 0.25,
            parameterFlags: flags
        )
        paramAPI.addPopupMenu(
            withName: "Sample Size",
            parameterID: ParameterID.sampleScale.rawValue,
            defaultValue: UInt32(StabilizerSampleScale.defaultScale.rawValue),
            menuEntries: StabilizerSampleScale.menuEntries,
            parameterFlags: flags
        )
        paramAPI.addPopupMenu(
            withName: "Edge Display Mode",
            parameterID: ParameterID.edgeDisplayMode.rawValue,
            defaultValue: UInt32(StabilizerEdgeDisplayMode.stretchEdges.rawValue),
            menuEntries: ["Stretch Edges", "Black Outside"],
            parameterFlags: flags
        )
        paramAPI.addPushButton(
            withName: "Start Host Analysis",
            parameterID: ParameterID.startHostAnalysis.rawValue,
            selector: #selector(startHostAnalysis),
            parameterFlags: flags
        )
        paramAPI.addPushButton(
            withName: "Clear Host Analysis Cache",
            parameterID: ParameterID.clearHostAnalysisCache.rawValue,
            selector: #selector(clearHostAnalysisCache),
            parameterFlags: flags
        )
        paramAPI.addStringParameter(
            withName: "Host Analysis Status",
            parameterID: ParameterID.hostAnalysisStatus.rawValue,
            defaultValue: "Needs Analysis",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE)
        )
        paramAPI.addStringParameter(
            withName: "Stabilizer Info",
            parameterID: ParameterID.stabilizerInfo.rawValue,
            defaultValue: "No Analysis",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE | kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_USE_FULL_VIEW_WIDTH)
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

    func createView(forParameterID parameterID: UInt32) -> NSView {
        guard parameterID == ParameterID.stabilizerInfo.rawValue else {
            return NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 1))
        }
        let view = StabilizerInfoScrollView()
        Self.registerStabilizerInfoView(view)
        publishStabilizerInfo(force: true)
        return view
    }

    func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?, at renderTime: CMTime, quality qualityLevel: UInt) throws {
        let paramAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as! FxParameterRetrievalAPI_v6

        var state = StabilizerPluginState(
            strength: 1.0,
            microJitterXStrength: 1.0,
            microJitterYStrength: 1.0,
            microJitterRotationStrength: 0.2,
            strideWobbleXStrength: 0.65,
            strideWobbleYStrength: 0.70,
            strideWobbleRotationStrength: 0.2,
            panStabilizationStrength: 1.0,
            walkingBobStrength: 0.75,
            farFieldWarpStrength: 1.0,
            panSmoothSeconds: 6.0,
            edgeDisplayMode: StabilizerEdgeDisplayMode.stretchEdges.rawValue,
            debugOverlay: false,
            sampleScale: StabilizerSampleScale.defaultScale.rawValue,
            hostAnalysisFrameCount: 0,
            hostAnalysisRevision: 0,
            renderRevision: 0.0,
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
        paramAPI.getFloatValue(&state.walkingBobStrength, fromParameter: ParameterID.walkingBobStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.farFieldWarpStrength, fromParameter: ParameterID.farFieldWarpStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.panSmoothSeconds, fromParameter: ParameterID.panSmoothSeconds.rawValue, at: renderTime)
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
            if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
               !StabilizerHostAnalysisStore.cacheIdentity(preferredIdentity, matches: inputRange) {
                publishHostAnalysisCacheIdentity(nil, force: true)
            }
        }
        let expectedRange = Self.expectedInputRange(from: state)
        if configureProjectBundleCacheDirectory() {
            if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
               hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange) {
                publishHostAnalysisCacheIdentity(hostAnalysisStore.activeCacheIdentity, force: false)
            } else if hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange) {
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
        publishStabilizerInfo(state: state)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, currentParameterValue: state.renderRevision)

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
    }

    @objc(startHostAnalysis)
    func startHostAnalysis() {
        os_log("Start Host Analysis pressed in FxPlug %{public}@", log: stabilizerHostAnalysisLog, type: .default, stabilizerFxPlugVersion)
        publishHostAnalysisStatus(force: true, statusOverride: "Start Pressed")
        publishStabilizerInfo(force: true)
        let expectedRange = currentInputRange()
        if let expectedRange,
           let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
           !StabilizerHostAnalysisStore.cacheIdentity(preferredIdentity, matches: expectedRange) {
            publishHostAnalysisCacheIdentityOnMain(nil, force: true)
        }
        hostAnalysisStore.reset()
        let loadedPersistentCache: Bool
        if configureProjectBundleCacheDirectory(markUnavailable: false) {
            if let preferredIdentity = currentPreferredHostAnalysisCacheIdentity(),
               hostAnalysisStore.activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange) {
                loadedPersistentCache = true
            } else {
                loadedPersistentCache = hostAnalysisStore.loadPersistentCache(expectedRange: expectedRange)
            }
        } else {
            loadedPersistentCache = false
            os_log("Start preflight could not resolve Event cache root; requesting host analysis for analyzer setup resolution.", log: stabilizerHostAnalysisLog, type: .default)
            NSLog("StabilizerFxPlug: Start Host Analysis could not preflight the Event cache root; requesting Host Analysis so setupAnalysis can resolve the host analysis context.")
        }
        if loadedPersistentCache {
            publishHostAnalysisCacheIdentity(hostAnalysisStore.activeCacheIdentity, force: true)
        }
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
        if !loadedPersistentCache {
            requestHostAnalysisIfNeeded(force: true)
        }
    }

    @objc(clearHostAnalysisCache)
    func clearHostAnalysisCache() {
        Self.removeQueuedSerialAnalysis(self)
        guard configureProjectBundleCacheDirectory() else {
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return
        }
        hostAnalysisStore.clearPersistentCache()
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
    }

    @discardableResult
    private func requestHostAnalysisIfNeeded(
        force: Bool = false,
        allowSerialQueue: Bool = true,
        queuedStartRequest: Bool = false,
        queuedAnalysisAPI: FxAnalysisAPI? = nil
    ) -> HostAnalysisRequestResult {
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
            NSLog("StabilizerFxPlug: FxAnalysisAPI is unavailable; Host Analysis cannot start.")
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
            if allowSerialQueue && force {
                let position = Self.enqueueSerialAnalysis(self, analysisAPI: analysisAPI)
                hostAnalysisStore.markQueued(position: position, reason: reason)
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                NSLog("StabilizerFxPlug: queued Host Analysis request at position \(position) because host state is \(reason).")
                os_log("Queued Host Analysis because host state is %{public}@ at position %{public}d.", log: stabilizerHostAnalysisLog, type: .default, reason, position)
                Self.scheduleSerialAnalysisQueueDrain()
                return .queued
            } else if force {
                hostAnalysisStore.markStartFailed(reason: "Host state \(reason)")
            }
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            if force {
                NSLog("StabilizerFxPlug: Host Analysis is already requested or running.")
                os_log("Host Analysis start blocked because host state is %{public}@.", log: stabilizerHostAnalysisLog, type: .error, reason)
            }
            return .failed
        }
        guard Self.reserveHostAnalysisStartIfAvailable() else {
            let reason = "ActiveHostAnalysisSession"
            if allowSerialQueue && force {
                let position = Self.enqueueSerialAnalysis(self, analysisAPI: analysisAPI)
                hostAnalysisStore.markQueued(position: position, reason: reason)
                publishHostAnalysisStatus(force: true)
                publishStabilizerInfo(force: true)
                publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
                NSLog("StabilizerFxPlug: queued Host Analysis request at position \(position) because another clip has an active or reserved Host Analysis session.")
                os_log("Queued Host Analysis because another clip has an active or reserved session at position %{public}d.", log: stabilizerHostAnalysisLog, type: .default, position)
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
            NSLog("StabilizerFxPlug: requested GPU Host Analysis for the effect clip.")
            os_log("Requested GPU Host Analysis for the effect clip.", log: stabilizerHostAnalysisLog, type: .default)
            hostAnalysisStore.markRequested()
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
            return .started
        } catch {
            NSLog("StabilizerFxPlug: Host Analysis request failed: \(error.localizedDescription)")
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
    private static func enqueueSerialAnalysis(_ plugin: StabilizerFxPlugPlugIn, analysisAPI: FxAnalysisAPI) -> Int {
        serialAnalysisQueueLock.lock()
        serialAnalysisQueue.removeAll { queuedRequest in queuedRequest.plugin === plugin }
        serialAnalysisQueue.append(SerialHostAnalysisRequest(plugin: plugin, analysisAPI: analysisAPI))
        let position = serialAnalysisQueue.count
        serialAnalysisQueueLock.unlock()
        os_log(
            "Serial Host Analysis queue enqueued request at position %{public}d.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            position
        )
        return position
    }

    private static func removeQueuedSerialAnalysis(_ plugin: StabilizerFxPlugPlugIn) {
        serialAnalysisQueueLock.lock()
        serialAnalysisQueue.removeAll { queuedRequest in queuedRequest.plugin === plugin }
        serialAnalysisQueueLock.unlock()
    }

    private static func isQueuedSerialAnalysis(_ plugin: StabilizerFxPlugPlugIn) -> Bool {
        serialAnalysisQueueLock.lock()
        defer { serialAnalysisQueueLock.unlock() }
        return serialAnalysisQueue.contains { queuedRequest in queuedRequest.plugin === plugin }
    }

    private static func dequeueNextSerialAnalysis() -> SerialHostAnalysisRequest? {
        serialAnalysisQueueLock.lock()
        defer { serialAnalysisQueueLock.unlock() }
        guard !serialAnalysisQueue.isEmpty else {
            return nil
        }
        return serialAnalysisQueue.removeFirst()
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

        NSLog("StabilizerFxPlug: Serial Host Analysis queue drain pass saw \(queuedCount) queued request(s).")
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
        while let nextRequest = dequeueNextSerialAnalysis() {
            let result = nextRequest.plugin.requestHostAnalysisIfNeeded(
                force: true,
                allowSerialQueue: true,
                queuedStartRequest: true,
                queuedAnalysisAPI: nextRequest.analysisAPI
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

    private static func debugOverlayScale(outputWidth: Int, outputHeight: Int, renderSourceIsProxy: Bool) -> Float {
        let width = max(1, outputWidth)
        let height = max(1, outputHeight)
        let baseScale = min(Float(width) / 3840.0, Float(height) / 2160.0) * 1.35
        let minimumScale: Float = renderSourceIsProxy ? 0.25 : 0.75
        return min(max(baseScale, minimumScale), 2.25)
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
            NSLog("StabilizerFxPlug: failed to update Host Analysis Status parameter.")
        }
    }

    private func publishStabilizerInfo(
        force: Bool = false,
        state: StabilizerPluginState? = nil,
        analysisInfoOverride: String? = nil
    ) {
        let analysisInfo = analysisInfoOverride ?? hostAnalysisStore.infoText
        let info = Self.stabilizerInfoText(analysisInfo: analysisInfo, state: state)
        statusLock.lock()
        let shouldPublish = force || info != lastPublishedInfo
        statusLock.unlock()
        guard shouldPublish else {
            return
        }
        Self.updateStabilizerInfoViews(info)
        guard let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if settingAPI.setStringParameterValue(info, toParameter: ParameterID.stabilizerInfo.rawValue) {
            statusLock.lock()
            lastPublishedInfo = info
            statusLock.unlock()
        } else {
            NSLog("StabilizerFxPlug: failed to update Stabilizer Info parameter.")
        }
    }

    private static func registerStabilizerInfoView(_ view: StabilizerInfoScrollView) {
        stabilizerInfoViewLock.lock()
        stabilizerInfoViews.add(view)
        let info = latestStabilizerInfo
        stabilizerInfoViewLock.unlock()
        view.infoText = info
    }

    private static func updateStabilizerInfoViews(_ info: String) {
        stabilizerInfoViewLock.lock()
        latestStabilizerInfo = info
        let views = stabilizerInfoViews.allObjects
        stabilizerInfoViewLock.unlock()
        DispatchQueue.main.async {
            views.forEach { $0.infoText = info }
        }
    }

    private static func stabilizerInfoText(analysisInfo: String, state: StabilizerPluginState?) -> String {
        var lines = ["FxPlug \(stabilizerFxPlugVersion)"]
        if let state {
            let bobWindowSeconds = stabilizerFixedWalkingBobWindowSeconds
            let turnWindowSeconds = max(stabilizerMinimumTurnDetectionWindowSeconds, state.panSmoothSeconds)
            let turnStartSeconds = stabilizerMinimumTurnDetectionWindowSeconds
            lines.append(String(
                format: "Footstep jitter <= 1s | X %.2f Y %.2f R %.2f",
                state.microJitterXStrength,
                state.microJitterYStrength,
                state.microJitterRotationStrength
            ))
            lines.append(String(
                format: "Stride wobble <= 2s | X %.2f Y %.2f R %.2f",
                state.strideWobbleXStrength,
                state.strideWobbleYStrength,
                state.strideWobbleRotationStrength
            ))
            lines.append(String(
                format: "Walking Bob <= %.2fs | removal %.2f",
                bobWindowSeconds,
                state.walkingBobStrength
            ))
            lines.append(String(
                format: "Far-field Warp <= 1s | strength %.2f",
                state.farFieldWarpStrength
            ))
            lines.append(String(
                format: "Turn Smoothing %.2f-%.2fs | strength %.2f",
                turnStartSeconds,
                turnWindowSeconds,
                state.panStabilizationStrength
            ))
        }
        if analysisInfo != "No Analysis" {
            lines.append(analysisInfo)
        }
        return lines.joined(separator: "\n")
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
        statusLock.lock()
        let shouldPublish = force || parameterNeedsUpdate || lastPublishedRenderRevision != revision
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
            NSLog("StabilizerFxPlug: failed to update Render Revision parameter.")
        }
    }

    private func publishRenderAnalysisDecisionIfChanged(_ decision: String) {
        statusLock.lock()
        let shouldPublish = lastRenderAnalysisDecision != decision
        if shouldPublish {
            lastRenderAnalysisDecision = decision
        }
        statusLock.unlock()
        if shouldPublish {
            os_log("%{public}@", log: stabilizerHostAnalysisLog, type: .default, decision)
        }
    }

    private func publishAnalysisCallbackStatus(_ analysisStore: StabilizerHostAnalysisStore) {
        if hostAnalysisStore.hasCompletedAnalysis {
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.renderInvalidationToken, force: true)
        } else {
            publishHostAnalysisStatus(force: true, statusOverride: analysisStore.statusText)
            publishStabilizerInfo(force: true, analysisInfoOverride: analysisStore.infoText)
            publishRenderRevision(analysisStore.renderInvalidationToken, force: true)
        }
    }

    private func publishActiveAnalysisProgressIfNeeded(_ analysisStore: StabilizerHostAnalysisStore) {
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
        publishAnalysisCallbackStatus(analysisStore)
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
        guard configureProjectBundleCacheDirectory() else {
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: hostAnalysisStore.renderInvalidationToken
            )
            return
        }
        let expectedRange = currentInputRange()
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
            sampleSize: bestCandidate.sampleSize
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
            return .resolved(sessionID: session.id, store: session.store)
        }

        let ownerSessions = Self.activeAnalysisSessions.values.filter { $0.ownerObjectID == ownerObjectID }
        if ownerSessions.count == 1,
           let session = ownerSessions.first {
            Self.activeAnalysisSessions.removeValue(forKey: session.id)
            if Self.activeAnalysisSessions.isEmpty {
                Self.hostAnalysisStartReserved = false
            }
            activeAnalyzerSessionID = nil
            return .resolved(sessionID: session.id, store: session.store)
        }

        if Self.activeAnalysisSessions.count == 1,
           let session = Self.activeAnalysisSessions.values.first {
            Self.activeAnalysisSessions.removeValue(forKey: session.id)
            if Self.activeAnalysisSessions.isEmpty {
                Self.hostAnalysisStartReserved = false
            }
            activeAnalyzerSessionID = nil
            return .resolved(sessionID: session.id, store: session.store)
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
        NSLog("StabilizerFxPlug: \(reason)")
        os_log("%{public}@", log: stabilizerHostAnalysisLog, type: .error, reason)
        Self.scheduleSerialAnalysisQueueDrain(after: 0.2)
        return NSError(
            domain: "com.justadev.StabilizerFxPlug",
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
            NSLog("StabilizerFxPlug: failed to update Host Analysis Cache Identity parameter.")
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

    @discardableResult
    private func configureProjectBundleCacheDirectory(markUnavailable: Bool = true) -> Bool {
        if StabilizerHostAnalysisStore.hasConfiguredProjectBundleCacheDirectory {
            return true
        }
        if let projectAPI = apiManager.api(for: FxProjectAPI.self) as? FxProjectAPI {
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
                        NSLog("StabilizerFxPlug: \(reason)")
                        if markUnavailable {
                            hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                        }
                        return false
                    }
                    guard let eventResolution = Self.fcpEventRoot(containing: projectMediaURL, in: bundleRoot) else {
                        let reason = "FxProjectAPI media folder did not resolve to a writable Event Analysis Files root: \(projectMediaURL.path)"
                        NSLog("StabilizerFxPlug: \(reason)")
                        if markUnavailable {
                            hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                        }
                        return false
                    }
                    let cacheRoot = Self.eventHostAnalysisCacheRoot(in: eventResolution.eventRoot)
                    do {
                        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                    } catch {
                        let reason = "Event Analysis Files cache root could not be created at \(cacheRoot.path): \(error.localizedDescription)"
                        NSLog("StabilizerFxPlug: \(reason)")
                        if markUnavailable {
                            hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                        }
                        return false
                    }
                    Self.migrateLegacyHostAnalysisCacheIfNeeded(
                        from: Self.legacyHostAnalysisCacheRoot(under: projectMediaURL),
                        to: cacheRoot
                    )
                    Self.migrateLegacyHostAnalysisCacheIfNeeded(
                        from: Self.legacyHostAnalysisCacheRoot(under: bundleRoot),
                        to: cacheRoot
                    )
                    Self.migrateLegacyHostAnalysisCacheIfNeeded(
                        from: Self.internalBundleHostAnalysisCacheRoot(in: bundleRoot),
                        to: cacheRoot
                    )
                    StabilizerHostAnalysisStore.configureProjectBundleCacheDirectory(
                        cacheRoot,
                        securityScopedURL: didStartAccess ? projectMediaURL : nil
                    )
                    shouldRetainSecurityScopedAccess = didStartAccess
                    NSLog("StabilizerFxPlug: using \(eventResolution.sourceDescription) Event Host Analysis cache at \(cacheRoot.path) inside \(eventResolution.eventRoot.path).")
                    return true
                }
                let reason = "FxProjectAPI did not provide a project media folder URL."
                NSLog("StabilizerFxPlug: \(reason)")
                if markUnavailable {
                    hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                }
                return false
            } catch {
                let reason = "FxProjectAPI media folder unavailable: \(error.localizedDescription)"
                NSLog("StabilizerFxPlug: \(reason)")
                if markUnavailable {
                    hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
                }
                return false
            }
        } else {
            let reason = "FxProjectAPI unavailable; Event Analysis Files cache cannot be resolved."
            NSLog("StabilizerFxPlug: \(reason)")
            if markUnavailable {
                hostAnalysisStore.markProjectCacheUnavailable(reason: reason)
            }
            return false
        }
    }

    private static func eventHostAnalysisCacheRoot(in eventRoot: URL) -> URL {
        eventRoot
            .appendingPathComponent("Analysis Files", isDirectory: true)
            .appendingPathComponent("StabilizerFxPlugHostAnalysis", isDirectory: true)
            .standardizedFileURL
    }

    private static func internalBundleHostAnalysisCacheRoot(in bundleRoot: URL) -> URL {
        bundleRoot
            .appendingPathComponent("__.fcpdata.apple.com", isDirectory: true)
            .appendingPathComponent("StabilizerFxPlugHostAnalysis", isDirectory: true)
            .standardizedFileURL
    }

    private static func legacyHostAnalysisCacheRoot(under rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent("StabilizerFxPlugHostAnalysis", isDirectory: true)
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
                NSLog("StabilizerFxPlug: moved legacy Host Analysis cache from \(legacyURL.path) to \(cacheRoot.path).")
            } else {
                NSLog("StabilizerFxPlug: left legacy Host Analysis cache at \(legacyURL.path) because \(remainingItems.count) item(s) could not be moved without overwriting newer files.")
            }
        } catch {
            NSLog("StabilizerFxPlug: failed to migrate legacy Host Analysis cache from \(legacyURL.path) to \(cacheRoot.path): \(error.localizedDescription)")
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
                    NSLog("StabilizerFxPlug: keeping legacy Host Analysis cache item \(itemURL.path) because \(destinationItemURL.path) already exists.")
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

    private static func fcpEventRoot(containing url: URL, in bundleRoot: URL) -> FCPEventRootResolution? {
        let bundleRoot = bundleRoot.standardizedFileURL
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
            return FCPEventRootResolution(
                eventRoot: ancestorEventRoot,
                sourceDescription: "FxProjectAPI media-folder ancestor"
            )
        }
        if let analysisFilesEventRoot = singleTopLevelEventWithExistingAnalysisFiles(in: bundleRoot) {
            return FCPEventRootResolution(
                eventRoot: analysisFilesEventRoot,
                sourceDescription: "single existing Event Analysis Files"
            )
        }
        if let onlyEventRoot = singleTopLevelEvent(in: bundleRoot) {
            return FCPEventRootResolution(
                eventRoot: onlyEventRoot,
                sourceDescription: "single top-level library Event"
            )
        }
        return nil
    }

    private static func singleTopLevelEventWithExistingAnalysisFiles(in bundleRoot: URL) -> URL? {
        let eventRoots = topLevelEventRoots(in: bundleRoot).filter { eventRoot in
            let analysisFilesURL = eventRoot.appendingPathComponent("Analysis Files", isDirectory: true)
            var isDirectory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: analysisFilesURL.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        return eventRoots.count == 1 ? eventRoots[0] : nil
    }

    private static func singleTopLevelEvent(in bundleRoot: URL) -> URL? {
        let eventRoots = topLevelEventRoots(in: bundleRoot)
        return eventRoots.count == 1 ? eventRoots[0] : nil
    }

    private static func topLevelEventRoots(in bundleRoot: URL) -> [URL] {
        let bundleRoot = bundleRoot.standardizedFileURL
        guard let childURLs = try? FileManager.default.contentsOfDirectory(
            at: bundleRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
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
        currentInputRange() ?? Self.expectedInputRange(from: state)
    }

    private func requestedSampleScalePercent(at time: CMTime) -> Double {
        var sampleScale = StabilizerSampleScale.defaultScale.rawValue
        if let paramAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6 {
            paramAPI.getIntValue(&sampleScale, fromParameter: ParameterID.sampleScale.rawValue, at: time)
        }
        return StabilizerSampleScale.scale(for: sampleScale).percent
    }

    private func publishHostAnalysisRenderDiagnostics(
        frameCount: Int,
        panSmoothSeconds: Double,
        autoTransform: StabilizerAutoTransform,
        appliedPixelOffset: vector_float2,
        appliedRotationRadians: Float
    ) {
        let status = String(
            format: "Ready (%d) | FxPlug %@ | warp q %.2f shear %.4f %.4f yp %.4f %.4f persp %.4f %.4f | turn %.1fs q %.2f smooth %d@%.2fs | X %.1f Y %.1f R %.2f | raw X %.1f Y %.1f R %.2f | smooth dX %.1f dY %.1f dR %.2f | track q %.2f walk q %.2f motion q %.2f blur %.2f resid %.4f | foot raw X %.3f Y %.3f R %.3f q %.2f eff X %.2f Y %.2f R %.2f | stride q %.2f eff X %.2f Y %.2f R %.2f | bob q %.2f blocks %d/%d edge %d/%d | x turn %.1f stride %.1f | y foot %.1f stride %.1f bob %.1f",
            frameCount,
            stabilizerFxPlugVersion,
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
            autoTransform.bobConfidence,
            autoTransform.acceptedBlockCount,
            autoTransform.totalBlockCount,
            autoTransform.searchRadiusHitCount,
            autoTransform.searchRadiusTotalCount,
            autoTransform.macroPixelOffset.x,
            autoTransform.strideWobblePixelOffset.x,
            autoTransform.microPixelOffset.y,
            autoTransform.strideWobblePixelOffset.y,
            autoTransform.walkingBobPixelOffset.y
        )
        publishHostAnalysisStatus(statusOverride: status)
    }

    private static func hostAnalysisStatusText(_ status: String) -> String {
        if status.contains("FxPlug \(stabilizerFxPlugVersion)") {
            return status
        }
        return "\(status) | FxPlug \(stabilizerFxPlugVersion)"
    }

    func scheduleInputs(_ inputImageRequests: AutoreleasingUnsafeMutablePointer<NSArray?>?, withPluginState pluginState: Data?, at renderTime: CMTime) throws {
        var requests: [FxImageTileRequest] = []
        if let current = FxImageTileRequest(
            source: kFxImageTileRequestSourceEffectClip,
            time: renderTime,
            includeFilters: true,
            parameterID: 0
        ) {
            requests.append(current)
        }

        inputImageRequests?.pointee = requests as NSArray
    }

    func destinationImageRect(_ destinationImageRect: UnsafeMutablePointer<FxRect>, sourceImages: [FxImageTile], destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        destinationImageRect.pointee = sourceImages[0].imagePixelBounds
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
        guard let state = pluginState?.withUnsafeBytes({ pointer in
            pointer.bindMemory(to: StabilizerPluginState.self).baseAddress?.pointee
        }) else {
            return
        }

        let deviceCache = MetalDeviceCache.deviceCache
        let pixelFormat = MetalDeviceCache.fxMTLPixelFormat(for: destinationImage)
        guard
            let commandQueue = deviceCache.commandQueue(with: sourceImages[0].deviceRegistryID, pixelFormat: pixelFormat),
            let device = deviceCache.device(with: sourceImages[0].deviceRegistryID),
            let inputTexture = sourceImages[0].metalTexture(for: device),
            let outputTexture = destinationImage.metalTexture(for: device),
            let pipelineState = deviceCache.pipelineState(with: sourceImages[0].deviceRegistryID, pixelFormat: pixelFormat),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let outputWidth = destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left
        let outputHeight = destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom
        var vertices = [
            StabilizerVertex2D(position: vector_float2(Float(outputWidth) / 2.0, Float(-outputHeight) / 2.0), textureCoordinate: vector_float2(1.0, 1.0)),
            StabilizerVertex2D(position: vector_float2(Float(-outputWidth) / 2.0, Float(-outputHeight) / 2.0), textureCoordinate: vector_float2(0.0, 1.0)),
            StabilizerVertex2D(position: vector_float2(Float(outputWidth) / 2.0, Float(outputHeight) / 2.0), textureCoordinate: vector_float2(1.0, 0.0)),
            StabilizerVertex2D(position: vector_float2(Float(-outputWidth) / 2.0, Float(outputHeight) / 2.0), textureCoordinate: vector_float2(0.0, 0.0))
        ]
        var viewportSize = simd_uint2(UInt32(outputWidth), UInt32(outputHeight))
        let masterStrength = Float(max(0.0, state.strength))
        let transformEnabled = masterStrength > 0.0001
        let autoTransform: StabilizerAutoTransform
        var renderUsesPreparedAnalysis = false
        let expectedRange = currentRenderExpectedRange(from: state)
        let preferredCacheIdentity = currentPreferredHostAnalysisCacheIdentity()
        let hasCompletedHostAnalysis = hostAnalysisStore.hasCompletedAnalysis
        let configuredProjectBundleCache = transformEnabled && !hasCompletedHostAnalysis
            ? configureProjectBundleCacheDirectory(markUnavailable: false)
            : false
        let canUseHostAnalysisStoreForRender = transformEnabled
            && (hasCompletedHostAnalysis || configuredProjectBundleCache)
        if transformEnabled,
           canUseHostAnalysisStoreForRender,
           let preparedAnalysis = hostAnalysisStore.preparedAnalysisForRender(
               validating: sourceImages[0],
               at: renderTime,
               preferredCacheIdentity: preferredCacheIdentity,
               expectedRange: expectedRange
           ) {
            renderUsesPreparedAnalysis = true
            publishHostAnalysisCacheIdentityOnMain(hostAnalysisStore.activeCacheIdentity, force: false)
            let analysisRenderTime = hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            autoTransform = AutoStabilizationEstimator.estimate(
                preparedAnalysis: preparedAnalysis,
                renderTime: analysisRenderTime,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: state.panSmoothSeconds,
                strengths: StabilizerCorrectionStrengths(
                    microJitterX: state.microJitterXStrength,
                    microJitterY: state.microJitterYStrength,
                    microJitterRotation: state.microJitterRotationStrength,
                    strideWobbleX: state.strideWobbleXStrength,
                    strideWobbleY: state.strideWobbleYStrength,
                    strideWobbleRotation: state.strideWobbleRotationStrength,
                    panStabilizationStrength: state.panStabilizationStrength,
                    walkingBob: state.walkingBobStrength,
                    farFieldWarp: state.farFieldWarpStrength
                )
            )
        } else {
            autoTransform = .identity
        }
        publishRenderAnalysisDecisionIfChanged(
            "Render Host Analysis decision | FxPlug \(stabilizerFxPlugVersion) | transform \(transformEnabled ? "on" : "off") | completed \(hasCompletedHostAnalysis ? "yes" : "no") | project cache \(configuredProjectBundleCache ? "configured" : "not configured") | prepared \(renderUsesPreparedAnalysis ? "yes" : "no") | debug \(state.debugOverlay ? "on" : "off") | frames \(state.hostAnalysisFrameCount)"
        )
        let renderInvalidationToken = hostAnalysisStore.renderInvalidationToken
        let renderStoreRevision = hostAnalysisStore.revision
        let renderStoreChangedStatus = renderStoreRevision != state.hostAnalysisRevision
        if renderStoreChangedStatus || abs(renderInvalidationToken - state.renderRevision) >= 0.5 {
            publishPreviewInvalidationOnMain(
                statusForce: true,
                infoForce: true,
                revision: renderInvalidationToken,
                revisionForce: renderStoreChangedStatus,
                currentRenderRevision: state.renderRevision
            )
        }
        let renderSourceIsProxy = renderUsesPreparedAnalysis
            && StabilizerOriginalMediaPolicy.proxyRejectionReason(for: sourceImages[0]) != nil
        let debugOverlayScale = Self.debugOverlayScale(
            outputWidth: Int(outputWidth),
            outputHeight: Int(outputHeight),
            renderSourceIsProxy: renderSourceIsProxy
        )
        let diagnosticScaleX = max(1.0, Float(outputWidth) * 0.05)
        let diagnosticScaleY = max(1.0, Float(outputHeight) * 0.05)
        let temporalSmoothingScale = max(1.0, min(Float(outputWidth), Float(outputHeight)) * 0.03)
        let searchRadiusQuality: Float
        if autoTransform.searchRadiusTotalCount > 0 {
            let searchRadiusHitRatio = min(1.0, Float(autoTransform.searchRadiusHitCount) / Float(autoTransform.searchRadiusTotalCount))
            searchRadiusQuality = 1.0 - searchRadiusHitRatio
        } else {
            searchRadiusQuality = 0.0
        }
        let residualQuality = max(0.0, 1.0 - min(1.0, autoTransform.residual * 50.0))
        let footstepJitterActivity = min(1.0, max(
            simd_length(vector_float2(
                autoTransform.microPixelOffset.x / diagnosticScaleX,
                autoTransform.microPixelOffset.y / diagnosticScaleY
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
        let diagnostic = vector_float4(
            min(1.0, abs(autoTransform.pixelOffset.x) / diagnosticScaleX),
            min(1.0, abs(autoTransform.pixelOffset.y) / diagnosticScaleY),
            min(1.0, abs(autoTransform.rotationDegrees) / 5.0),
            searchRadiusQuality
        )
        let diagnostic2 = vector_float4(
            min(1.0, simd_length(vector_float2(autoTransform.macroPixelOffset.x / diagnosticScaleX, autoTransform.macroPixelOffset.y / diagnosticScaleY))),
            footstepJitterActivity,
            strideWobbleActivity,
            min(1.0, abs(autoTransform.walkingBobPixelOffset.y) / diagnosticScaleY)
        )
        let diagnostic3 = vector_float4(
            min(1.0, simd_length(autoTransform.temporalSmoothingPixelDelta) / temporalSmoothingScale),
            min(1.0, autoTransform.microConfidence),
            min(1.0, autoTransform.strideConfidence),
            min(1.0, autoTransform.bobConfidence)
        )
        let diagnostic4 = vector_float4(
            min(1.0, autoTransform.warpConfidence),
            min(1.0, autoTransform.trackingConfidence),
            min(1.0, 1.0 - autoTransform.blurAmount),
            residualQuality
        )
        let diagnostic5 = vector_float4(
            min(1.0, autoTransform.turnConfidence),
            farFieldWarpActivity,
            min(1.0, autoTransform.walkingTrackingConfidence),
            0.0
        )

        var transform = StabilizerTransformUniforms(
            pixelOffset: autoTransform.pixelOffset * masterStrength,
            rotationRadians: autoTransform.rotationDegrees * .pi / 180.0 * masterStrength,
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
            debugOverlay: state.debugOverlay && transformEnabled && renderUsesPreparedAnalysis ? 1.0 : 0.0,
            debugMode: renderSourceIsProxy ? 2.0 : 1.0,
            debugOverlayScale: debugOverlayScale
        )
        if state.debugOverlay && transformEnabled && renderUsesPreparedAnalysis {
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
        encoder.setVertexBytes(&vertices, length: MemoryLayout<StabilizerVertex2D>.size * vertices.count, index: Int(SVI_Vertices.rawValue))
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
            "StabilizerFxPlug: setup Host Analysis requested for range %.3f+%.3f seconds, frameDuration %.6f seconds.",
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        if !configureProjectBundleCacheDirectory() {
            NSLog("StabilizerFxPlug: setup Host Analysis will continue in memory because the Event cache root is unavailable.")
            os_log("setupAnalysis continuing in memory because the Event cache root is unavailable; completed analysis will not be persisted.", log: stabilizerHostAnalysisLog, type: .error)
        }
        let analysisStore = StabilizerHostAnalysisStore()
        let requestedSampleScalePercent = requestedSampleScalePercent(at: analysisRange.start)
        analysisStore.begin(
            range: analysisRange,
            frameDuration: frameDuration,
            requestedSampleScalePercent: requestedSampleScalePercent
        )
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
            "StabilizerFxPlug: setup Host Analysis session %@ range %.3f+%.3f seconds, frameDuration %.6f seconds.",
            sessionID.uuidString,
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        let expectedRange = HostAnalysisExpectedRange(
            startSeconds: CMTimeGetSeconds(analysisRange.start),
            durationSeconds: CMTimeGetSeconds(analysisRange.duration),
            frameDurationSeconds: CMTimeGetSeconds(frameDuration)
        )
        _ = hostAnalysisStore.reloadPersistentCacheForConsumerIfNeeded(expectedRange: expectedRange.isValid ? expectedRange : nil)
        publishAnalysisCallbackStatus(analysisStore)
    }

    func analyzeFrame(_ frame: FxImageTile!, at frameTime: CMTime) throws {
        guard let frame else {
            let route = try? resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: nil)
            abandonActiveAnalysisAfterFailure(sessionID: route?.sessionID)
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "StabilizerFxPlug host analysis supplied no frame."]
            )
        }
        let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: frame)
        if let rejectionReason = StabilizerOriginalMediaPolicy.proxyRejectionReason(for: frame) {
            let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: frameInfo)
            route.store.rejectProxyAnalysis(reason: rejectionReason)
            publishAnalysisCallbackStatus(route.store)
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: rejectionReason]
            )
        }
        guard let frameInfo else {
            let reason = "Host Analysis could not read the original clip size for Sample Size."
            let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: nil)
            route.store.rejectProxyAnalysis(reason: reason)
            publishAnalysisCallbackStatus(route.store)
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        let route = try resolveActiveAnalysisSession(frameTime: frameTime, sourceInfo: frameInfo)
        guard let sampleSize = route.sampleSize else {
            throw hostAnalysisRoutingError("Stabilizer Host Analysis session could not derive a sample size for the current clip frame.")
        }
        do {
            let analysisFrame = try AutoStabilizationEstimator.analysisFrame(
                from: frame,
                at: frameTime,
                sampleWidth: sampleSize.width,
                sampleHeight: sampleSize.height
            )
            try route.store.append(analysisFrame, sourceInfo: frameInfo)
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
                    analysisFrame.sampleWidth,
                    analysisFrame.sampleHeight
                )
                NSLog(
                    "StabilizerFxPlug: received first Host Analysis frame for session %@ at %.3f seconds, sample %dx%d.",
                    route.sessionID.uuidString,
                    CMTimeGetSeconds(frameTime),
                    analysisFrame.sampleWidth,
                    analysisFrame.sampleHeight
                )
            }
            publishActiveAnalysisProgressIfNeeded(route.store)
        } catch {
            abandonActiveAnalysisAfterFailure(sessionID: route.sessionID)
            throw error
        }
    }

    func cleanupAnalysis() throws {
        let cleanupRoute = takeActiveAnalysisSessionForCleanup()
        let sessionID: UUID
        let analysisStore: StabilizerHostAnalysisStore
        switch cleanupRoute {
        case .resolved(let resolvedSessionID, let resolvedStore):
            sessionID = resolvedSessionID
            analysisStore = resolvedStore
        case .failed(let reason):
            NSLog("StabilizerFxPlug: \(reason)")
            os_log("cleanupAnalysis failed: %{public}@", log: stabilizerHostAnalysisLog, type: .error, reason)
            Self.scheduleSerialAnalysisQueueDrain(after: 0.2)
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        do {
            try analysisStore.finish()
        } catch {
            publishAnalysisCallbackStatus(analysisStore)
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
        schedulePostAnalysisPreviewInvalidationRetries(
            revision: completedRenderRevision,
            cacheIdentity: completedCacheIdentity
        )
    }
}

private final class StabilizerInfoScrollView: NSScrollView {
    private let textView = NSTextView()

    var infoText: String {
        get {
            textView.string
        }
        set {
            if Thread.isMainThread {
                setInfoText(newValue)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.setInfoText(newValue)
                }
            }
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        drawsBackground = false
        borderType = .bezelBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = false
        translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.08)
        textView.textColor = NSColor.labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        documentView = textView

        heightAnchor.constraint(equalToConstant: 96).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setInfoText(_ text: String) {
        guard textView.string != text else {
            return
        }
        textView.string = text
    }
}

private enum HostAnalysisValidationState {
    case notRequired
    case pending
    case validated
    case rejected
}

private enum HostAnalysisStatus {
    case needsAnalysis
    case requested
    case queued
    case analyzing
    case cacheLoaded
    case ready
    case cacheRejected
    case cacheUnsupported
    case cacheIncomplete
    case cacheCleared
    case projectCacheUnavailable
    case proxyRejected
    case proxyPreview
    case proxyNeedsOriginalValidation
    case sourceUnavailable
}

private struct PersistedHostAnalysisCache: Codable {
    let schemaVersion: Int
    let createdAt: Double
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frames: [PersistedHostAnalysisFrame]
    let residuals: [Float]?
    let rollMotion: [Float]?
    let pathX: [Float]?
    let pathY: [Float]?
    let pathRoll: [Float]?
    let footstepPathX: [Float]?
    let footstepPathY: [Float]?
    let footstepPathRoll: [Float]?
    let pathYaw: [Float]?
    let pathPitch: [Float]?
    let pathShearX: [Float]?
    let pathShearY: [Float]?
    let pathPerspectiveX: [Float]?
    let pathPerspectiveY: [Float]?
    let analysisConfidence: [Float]?
    let warpConfidence: [Float]?
    let acceptedBlockCounts: [Int32]?
    let totalBlockCounts: [Int32]?
    let blurAmounts: [Float]?
    let searchRadiusHitCounts: [Int32]?
    let searchRadiusTotalCounts: [Int32]?
}

private struct PersistedHostAnalysisSchemaHeader: Codable {
    let schemaVersion: Int
}

private struct PersistedHostAnalysisFrame: Codable {
    let time: Double
    let pixels: Data?
    let blurAmount: Float
    let fingerprint: String?
}

private struct PersistedHostAnalysisIndex: Codable {
    let schemaVersion: Int
    var entries: [PersistedHostAnalysisIndexEntry]
}

private struct PersistedHostAnalysisIndexEntry: Codable {
    let cacheFileName: String
    let createdAt: Double
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frameCount: Int
    let firstFingerprint: String
    let middleFingerprint: String
    let lastFingerprint: String
    let cacheIdentity: String?
}

private struct PersistedRenderTimeOffsetIndex: Codable {
    let version: Int
    var entries: [PersistedRenderTimeOffsetEntry]
}

private struct PersistedRenderTimeOffsetEntry: Codable {
    let cacheIdentity: String
    let offsetSeconds: Double
    let savedAt: Double
    let renderSeconds: Double
    let analysisSeconds: Double
}

private struct LoadedPersistentHostAnalysisCache {
    let fileName: String
    let url: URL
    let cache: PersistedHostAnalysisCache
    let identity: String
    let frames: [StabilizerAnalysisFrame]
    let preparedAnalysis: StabilizerPreparedAnalysis
}

private final class StabilizerHostAnalysisStore {
    private typealias CompletedHostAnalysisSnapshot = (
        frames: [StabilizerAnalysisFrame],
        preparedAnalysis: StabilizerPreparedAnalysis?,
        activeRange: CMTimeRange,
        activeFrameDuration: CMTime,
        activeRequestedSampleScalePercent: Double,
        finished: Bool,
        validationState: HostAnalysisValidationState,
        status: HostAnalysisStatus,
        latestSourceFrameInfo: StabilizerSourceFrameInfo?,
        latestSampleSize: (width: Int, height: Int)?,
        analysisInfoText: String,
        activePersistentCacheIdentity: String?
    )

    private struct CompletedMemoryHostAnalysis {
        let identity: String
        let rangeKey: String
        let snapshot: CompletedHostAnalysisSnapshot
    }

    private static let cacheSchemaVersion = 14
    private static let supportedCacheSchemaVersions: Set<Int> = [14]
    private static let persistentCacheGenerationLock = NSLock()
    private static var persistentCacheGeneration: UInt64 = 0
    private static let projectCacheDirectoryLock = NSLock()
    private static var projectBundleCacheDirectoryURL: URL?
    private static var retainedSecurityScopedProjectURLs: [URL] = []
    private static let maxPersistentCacheEntriesPerSampleSize = 8
    private static let maxCompletedMemoryAnalyses = 8
    private static let maxPersistentCacheReadBytes = 629_145_600
    private static let cacheValidationMeanDifferenceThreshold: Float = 18.0
    private static let cacheFileName = "host-analysis-v2.json"
    private static let cacheIndexFileName = "host-analysis-index-v2.json"
    private static let renderTimeOffsetFileName = "host-analysis-render-offset-v2.json"
    private static let cacheStorageDirectoryName = "caches"
    private static let analysisScratchDirectoryName = "analysis-work"

    private let lock = NSLock()
    private var framesByTimeKey: [Int64: StabilizerAnalysisFrame] = [:]
    private var streamingAnalysisBuilder: StreamingStabilizationAnalysisBuilder?
    private var preparedAnalysis: StabilizerPreparedAnalysis?
    private var activeCompletedMemoryAnalysisIdentity: String?
    private var completedMemoryAnalysesByIdentity: [String: CompletedMemoryHostAnalysis] = [:]
    private var completedMemoryAnalysisIdentitiesByRangeKey: [String: [String]] = [:]
    private var completedMemoryAnalysisOrder: [String] = []
    private var rejectedCompletedMemoryAnalysisIdentities = Set<String>()
    private var persistentCachesByIdentity: [String: LoadedPersistentHostAnalysisCache] = [:]
    private var persistentCacheCandidates: [URL] = []
    private var activePersistentCacheFileName: String?
    private var activePersistentCacheIdentity: String?
    private var rejectedPersistentCacheFileNames = Set<String>()
    private var activeRange: CMTimeRange = .invalid
    private var activeFrameDuration: CMTime = .invalid
    private var activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
    private var renderToAnalysisOffsetSeconds: Double?
    private var renderToAnalysisOffsetProbeAttempted = false
    private var finished = false
    private var validationState: HostAnalysisValidationState = .notRequired
    private var status: HostAnalysisStatus = .needsAnalysis
    private var analysisRevision: UInt64 = 0
    private var renderRevisionToken: Double = 0.0
    private var observedPersistentCacheGeneration: UInt64 = 0
    private var observedPersistentCacheSignature = ""
    private var latestSourceFrameInfo: StabilizerSourceFrameInfo?
    private var latestSampleSize: (width: Int, height: Int)?
    private var analysisInfoText = "No Analysis"

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return framesByTimeKey.count
    }

    var revision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return analysisRevision
    }

    var renderInvalidationToken: Double {
        lock.lock()
        defer { lock.unlock() }
        return renderRevisionToken
    }

    var infoText: String {
        lock.lock()
        defer { lock.unlock() }
        return analysisInfoText
    }

    var activeCacheIdentity: String? {
        lock.lock()
        defer { lock.unlock() }
        return activePersistentCacheIdentity
    }

    static func configureProjectBundleCacheDirectory(_ directoryURL: URL, securityScopedURL: URL?) {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL
        projectCacheDirectoryLock.lock()
        let changed = projectBundleCacheDirectoryURL?.path != standardizedDirectoryURL.path
        projectBundleCacheDirectoryURL = standardizedDirectoryURL
        if let securityScopedURL {
            let standardizedSecurityURL = securityScopedURL.standardizedFileURL
            if !retainedSecurityScopedProjectURLs.contains(where: { $0.path == standardizedSecurityURL.path }) {
                retainedSecurityScopedProjectURLs.append(standardizedSecurityURL)
            }
        }
        projectCacheDirectoryLock.unlock()
        if changed {
            bumpPersistentCacheGeneration()
        }
    }

    static var hasConfiguredProjectBundleCacheDirectory: Bool {
        projectCacheDirectoryLock.lock()
        let configured = projectBundleCacheDirectoryURL != nil
        projectCacheDirectoryLock.unlock()
        return configured
    }

    var statusText: String {
        lock.lock()
        let currentStatus = status
        let frameCount = framesByTimeKey.count
        let hasPreparedAnalysis = preparedAnalysis != nil
        lock.unlock()

        switch currentStatus {
        case .needsAnalysis:
            return "Needs Analysis"
        case .requested:
            return "Host Analysis Requested"
        case .queued:
            return "Queued Host Analysis"
        case .analyzing:
            return "Analyzing Host Frames (\(frameCount))"
        case .cacheLoaded:
            return "Cache Loaded (\(frameCount))"
        case .ready:
            if hasPreparedAnalysis {
                return "Ready (\(frameCount) frames)"
            }
            return "Needs Analysis"
        case .cacheRejected:
            return "Cache Rejected - Run Host Analysis"
        case .cacheUnsupported:
            return "Cache Unsupported - Run Host Analysis"
        case .cacheIncomplete:
            return "Cache Incomplete - Run Host Analysis"
        case .cacheCleared:
            return "Cache Cleared"
        case .projectCacheUnavailable:
            if hasPreparedAnalysis {
                return "Ready Memory Only - \(stabilizerProjectCacheUnavailableMessage)"
            }
            return stabilizerProjectCacheUnavailableMessage
        case .proxyRejected:
            return "Proxy Media Rejected - Use Original Media"
        case .proxyPreview:
            if hasPreparedAnalysis {
                return "Proxy Preview (\(frameCount) frames)"
            }
            return "Needs Analysis"
        case .proxyNeedsOriginalValidation:
            return "Proxy Cache Unvalidated - Use Original Media"
        case .sourceUnavailable:
            return "Source Media Unavailable - Check FCP Proxy"
        }
    }

    var hasCompletedAnalysis: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished && validationState != .rejected && preparedAnalysis != nil
    }

    var hasRejectedPersistentCache: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validationState == .rejected || status == .cacheRejected
    }

    func begin(range: CMTimeRange, frameDuration: CMTime, requestedSampleScalePercent: Double) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: true)
        activeRange = range
        activeFrameDuration = frameDuration
        activeRequestedSampleScalePercent = requestedSampleScalePercent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .validated
        status = .analyzing
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "Analyzing..."
        bumpRevisionLocked()
        lock.unlock()
    }

    func sampleSize(for sourceInfo: StabilizerSourceFrameInfo) -> (width: Int, height: Int) {
        lock.lock()
        let scalePercent = activeRequestedSampleScalePercent
        lock.unlock()
        return AutoStabilizationEstimator.sampleSize(
            sourceWidth: sourceInfo.sourceWidth,
            sourceHeight: sourceInfo.sourceHeight,
            scalePercent: scalePercent
        )
    }

    func markRequested() {
        lock.lock()
        if preparedAnalysis == nil && status != .analyzing {
            status = .requested
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markQueued(position: Int, reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .queued
            analysisInfoText = "Queued Host Analysis #\(position) | waiting for \(reason)"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markStartFailed(reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .needsAnalysis
            analysisInfoText = "Host Analysis start failed: \(reason)"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func markProjectCacheUnavailable(reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .projectCacheUnavailable
            analysisInfoText = "\(stabilizerProjectCacheUnavailableMessage). \(reason)"
            bumpRevisionLocked()
        }
        lock.unlock()
        NSLog("StabilizerFxPlug: project bundle Host Analysis cache unavailable: \(reason)")
    }

    func reset(removePersistentCache shouldRemovePersistentCache: Bool = false) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "No Analysis"
        bumpRevisionLocked()
        lock.unlock()
        if shouldRemovePersistentCache {
            removePersistentCache(logFailures: true)
        }
    }

    func clearPersistentCache() {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        completedMemoryAnalysesByIdentity.removeAll(keepingCapacity: false)
        completedMemoryAnalysisIdentitiesByRangeKey.removeAll(keepingCapacity: false)
        completedMemoryAnalysisOrder.removeAll(keepingCapacity: false)
        rejectedCompletedMemoryAnalysisIdentities.removeAll(keepingCapacity: false)
        persistentCachesByIdentity.removeAll(keepingCapacity: false)
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: false)
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .cacheCleared
        latestSourceFrameInfo = nil
        latestSampleSize = nil
        analysisInfoText = "Cache Cleared"
        bumpRevisionLocked()
        lock.unlock()
        removePersistentCache(logFailures: true)
        Self.bumpPersistentCacheGeneration()
        NSLog("StabilizerFxPlug: cleared persisted Host Analysis cache set.")
    }

    func rejectProxyAnalysis(reason: String) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.defaultScale.percent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .proxyRejected
        analysisInfoText = "Rejected proxy media. Use original media and rerun Host Analysis."
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: rejected Host Analysis proxy media: \(reason)")
    }

    func append(_ frame: StabilizerAnalysisFrame, sourceInfo: StabilizerSourceFrameInfo?) throws {
        let key = Self.timeKey(frame.time)
        lock.lock()
        if framesByTimeKey[key] != nil {
            lock.unlock()
            return
        }
        if streamingAnalysisBuilder == nil {
            do {
                streamingAnalysisBuilder = try StreamingStabilizationAnalysisBuilder()
            } catch {
                lock.unlock()
                throw error
            }
        }
        let builder = streamingAnalysisBuilder
        lock.unlock()

        guard let builder else {
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "Stabilizer streaming analysis builder was unavailable."]
            )
        }
        try builder.append(frame)

        lock.lock()
        framesByTimeKey[key] = frame.withoutRetainedPixels()
        latestSampleSize = (frame.sampleWidth, frame.sampleHeight)
        if let sourceInfo {
            latestSourceFrameInfo = sourceInfo
        }
        lock.unlock()
    }

    func finish() throws {
        do {
            try rebuildPreparedAnalysis(markFinished: true)
            try validateCompletedFrameCoverage()
            markAnalysisCompleted()
            persistIfCompleted()
            releaseRetainedAnalysisPixels()
            removeLegacyAnalysisScratchDirectory()
        } catch {
            lock.lock()
            preparedAnalysis = nil
            streamingAnalysisBuilder = nil
            finished = false
            status = error.localizedDescription.contains("incomplete frame coverage") ? .cacheIncomplete : .needsAnalysis
            analysisInfoText = "Analysis failed: \(error.localizedDescription)"
            bumpRevisionLocked()
            lock.unlock()
            removeLegacyAnalysisScratchDirectory()
            NSLog("StabilizerFxPlug: Metal Host Analysis preparation failed: \(error.localizedDescription)")
            throw error
        }
    }

    func installCompletedAnalysis(from completedStore: StabilizerHostAnalysisStore) {
        let snapshot = completedStore.completedAnalysisSnapshot()
        lock.lock()
        installCompletedAnalysisLocked(snapshot)
        activeCompletedMemoryAnalysisIdentity = retainCompletedMemoryAnalysisLocked(snapshot)
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: installed completed Host Analysis session with \(snapshot.frames.count) frame(s) into shared render store.")
    }

    private func installCompletedAnalysisLocked(
        _ snapshot: CompletedHostAnalysisSnapshot,
        validationStateOverride: HostAnalysisValidationState? = nil
    ) {
        framesByTimeKey = Dictionary(uniqueKeysWithValues: snapshot.frames.map { (Self.timeKey($0.time), $0) })
        streamingAnalysisBuilder = nil
        preparedAnalysis = snapshot.preparedAnalysis
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = snapshot.activePersistentCacheIdentity
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: true)
        activeRange = snapshot.activeRange
        activeFrameDuration = snapshot.activeFrameDuration
        activeRequestedSampleScalePercent = snapshot.activeRequestedSampleScalePercent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = snapshot.finished
        validationState = validationStateOverride ?? snapshot.validationState
        status = snapshot.status
        latestSourceFrameInfo = snapshot.latestSourceFrameInfo
        latestSampleSize = snapshot.latestSampleSize
        analysisInfoText = snapshot.analysisInfoText
    }

    private func retainCompletedMemoryAnalysisLocked(_ snapshot: CompletedHostAnalysisSnapshot) -> String? {
        guard snapshot.finished,
              snapshot.preparedAnalysis != nil,
              snapshot.activePersistentCacheIdentity == nil,
              let rangeKey = Self.completedMemoryAnalysisRangeKey(range: snapshot.activeRange),
              let identity = Self.completedMemoryAnalysisIdentity(snapshot: snapshot, rangeKey: rangeKey)
        else {
            return nil
        }
        completedMemoryAnalysesByIdentity[identity] = CompletedMemoryHostAnalysis(
            identity: identity,
            rangeKey: rangeKey,
            snapshot: snapshot
        )
        var rangeIdentities = completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] ?? []
        rangeIdentities.removeAll { $0 == identity }
        rangeIdentities.append(identity)
        completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] = rangeIdentities
        completedMemoryAnalysisOrder.removeAll { $0 == identity }
        completedMemoryAnalysisOrder.append(identity)
        rejectedCompletedMemoryAnalysisIdentities.remove(identity)
        while completedMemoryAnalysisOrder.count > Self.maxCompletedMemoryAnalyses,
              let evictedIdentity = completedMemoryAnalysisOrder.first {
            completedMemoryAnalysisOrder.removeFirst()
            if let evicted = completedMemoryAnalysesByIdentity.removeValue(forKey: evictedIdentity) {
                completedMemoryAnalysisIdentitiesByRangeKey[evicted.rangeKey]?.removeAll { $0 == evictedIdentity }
                if completedMemoryAnalysisIdentitiesByRangeKey[evicted.rangeKey]?.isEmpty == true {
                    completedMemoryAnalysisIdentitiesByRangeKey.removeValue(forKey: evicted.rangeKey)
                }
            }
            rejectedCompletedMemoryAnalysisIdentities.remove(evictedIdentity)
        }
        return identity
    }

    private func activateCompletedMemoryAnalysisIfNeeded(expectedRange: HostAnalysisExpectedRange) -> Bool {
        guard let expectedKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange) else {
            return false
        }
        lock.lock()
        if activePersistentCacheIdentity == nil,
           finished,
           preparedAnalysis != nil,
           Self.completedMemoryAnalysisRangeKey(range: activeRange) == expectedKey {
            lock.unlock()
            return true
        }
        guard let memoryAnalysis = nextCompletedMemoryAnalysisLocked(rangeKey: expectedKey) else {
            lock.unlock()
            return false
        }
        installCompletedAnalysisLocked(memoryAnalysis.snapshot, validationStateOverride: .pending)
        activeCompletedMemoryAnalysisIdentity = memoryAnalysis.identity
        bumpRevisionLocked()
        lock.unlock()
        os_log(
            "Activated in-memory Host Analysis for expected range key %{public}@ identity %{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .default,
            expectedKey,
            memoryAnalysis.identity
        )
        return true
    }

    func preparedAnalysisForRender(
        validating sourceImage: FxImageTile,
        at renderTime: CMTime,
        preferredCacheIdentity: String?,
        expectedRange: HostAnalysisExpectedRange?
    ) -> StabilizerPreparedAnalysis? {
        if let unavailableReason = StabilizerOriginalMediaPolicy.sourceUnavailableReason(for: sourceImage) {
            markSourceUnavailableForRender(reason: unavailableReason)
            NSLog("StabilizerFxPlug: source frame unavailable during render: \(unavailableReason)")
            return nil
        }

        let preferredIdentity = preferredCacheIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferredIdentity,
           !preferredIdentity.isEmpty,
           Self.cacheIdentity(preferredIdentity, matches: expectedRange) {
            _ = activatePersistentCache(identity: preferredIdentity, expectedRange: expectedRange)
        }
        if let expectedRange, expectedRange.isValid {
            _ = activateCompletedMemoryAnalysisIfNeeded(expectedRange: expectedRange)
        }

        while true {
            if shouldReloadPersistentCacheForConsumer(), loadPersistentCache(expectedRange: expectedRange) {
                continue
            }
            guard let analysis = preparedAnalysisSnapshot() else {
                guard activateNextPersistentCache(afterRejecting: nil, expectedRange: expectedRange) else {
                    return nil
                }
                continue
            }

            let state = currentValidationState()
            if state == .rejected {
                return nil
            }

            let activeIdentity = activeCacheIdentity
            if let activeIdentity,
               !Self.cacheIdentity(activeIdentity, matches: expectedRange) {
                deactivateActiveCacheForRangeMismatch()
                if activateNextPersistentCache(afterRejecting: nil, expectedRange: expectedRange) {
                    continue
                }
                if loadPersistentCache(expectedRange: expectedRange) {
                    continue
                }
                return nil
            }
            if activeIdentity == nil,
               let expectedRange,
               expectedRange.isValid,
               activeCompletedMemoryAnalysisDoesNotMatch(expectedRange: expectedRange) {
                deactivateActiveCompletedMemoryAnalysisForRangeMismatch()
                if activateCompletedMemoryAnalysisIfNeeded(expectedRange: expectedRange) {
                    continue
                }
                return nil
            }

            if let rejectionReason = StabilizerOriginalMediaPolicy.proxyRejectionReason(for: sourceImage) {
                if let activeIdentity,
                   Self.cacheIdentity(activeIdentity, matches: expectedRange) {
                    markProxyPreviewForRender(reason: rejectionReason)
                    updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                    NSLog("StabilizerFxPlug: using range-matched Host Analysis cache for proxy render: \(rejectionReason)")
                    return analysis
                }
                if activeIdentity == nil,
                   hasCompletedInMemoryAnalysis {
                    markProxyPreviewForRender(reason: rejectionReason)
                    updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                    os_log("Using in-memory Host Analysis for render despite scaled or incomplete source-frame metadata: %{public}@",
                           log: stabilizerHostAnalysisLog,
                           type: .default,
                           rejectionReason)
                    return analysis
                }

                markProxyNeedsOriginalValidationForRender(reason: rejectionReason)
                return nil
            }

            if state == .validated || state == .notRequired {
                markReadyAfterOriginalMediaReturnedIfNeeded()
                updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                return analysis
            }

            if let rejectionReason = persistentCacheRejectionReason(for: analysis, validating: sourceImage, at: renderTime) {
                if activateNextCompletedMemoryAnalysis(afterRejecting: rejectionReason, expectedRange: expectedRange) {
                    continue
                }
                guard activateNextPersistentCache(afterRejecting: rejectionReason, expectedRange: expectedRange) else {
                    if activeIdentity == nil {
                        rejectActiveInMemoryAnalysis(reason: rejectionReason)
                        return nil
                    }
                    rejectPersistentCache(reason: rejectionReason)
                    return nil
                }
                continue
            }

            lock.lock()
            if validationState == .pending {
                validationState = .validated
                if status != .projectCacheUnavailable {
                    status = .ready
                }
                bumpRevisionLocked()
            }
            lock.unlock()
            NSLog("StabilizerFxPlug: validated persisted Host Analysis cache with \(analysis.frames.count) frames.")
            releaseRetainedAnalysisPixels()
            return analysis
        }
    }

    func analysisRenderTime(for renderTime: CMTime, preparedAnalysis analysis: StabilizerPreparedAnalysis) -> CMTime {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return renderTime
        }
        lock.lock()
        let offsetSeconds = renderToAnalysisOffsetSeconds
        lock.unlock()
        if let offsetSeconds, offsetSeconds.isFinite {
            let mappedSeconds = Self.clampedAnalysisSeconds(renderSeconds + offsetSeconds, frames: analysis.frames)
            let preferredTimescale = renderTime.timescale > 0 ? renderTime.timescale : CMTimeScale(600)
            return CMTime(seconds: mappedSeconds, preferredTimescale: preferredTimescale)
        }
        let mappedSeconds = mappedAnalysisSeconds(forRenderSeconds: renderSeconds, frames: analysis.frames)
        guard mappedSeconds.isFinite, abs(mappedSeconds - renderSeconds) > 1e-9 else {
            return renderTime
        }
        let preferredTimescale = renderTime.timescale > 0 ? renderTime.timescale : CMTimeScale(600)
        return CMTime(seconds: mappedSeconds, preferredTimescale: preferredTimescale)
    }

    @discardableResult
    func loadPersistentCache(expectedRange: HostAnalysisExpectedRange? = nil) -> Bool {
        defer {
            markCurrentPersistentCacheGenerationObserved()
        }
        var candidateURLs = filteredPersistentCacheCandidateURLs()
        var unusableCacheSummaries: [(status: HostAnalysisStatus, summary: String)] = []
        while !candidateURLs.isEmpty {
            let activeURL = candidateURLs.removeFirst()
            if let unsupportedSummary = Self.unsupportedPersistentCacheSummary(at: activeURL) {
                unusableCacheSummaries.append((.cacheUnsupported, unsupportedSummary))
                continue
            }
            if let incompleteSummary = Self.incompletePersistentCacheSummary(at: activeURL) {
                unusableCacheSummaries.append((.cacheIncomplete, incompleteSummary))
                continue
            }
            guard let activeCandidate = Self.loadPersistentCache(at: activeURL) else {
                continue
            }
            guard Self.cache(activeCandidate.cache, matches: expectedRange) else {
                NSLog("StabilizerFxPlug: skipped Host Analysis cache \(activeCandidate.fileName) because its range does not match the active clip.")
                continue
            }
            lock.lock()
            installPersistentCacheLocked(activeCandidate)
            persistentCacheCandidates = candidateURLs
            analysisInfoText = Self.infoText(
                completedAt: Date(timeIntervalSince1970: activeCandidate.cache.createdAt),
                frameCount: activeCandidate.frames.count,
                sampleWidth: activeCandidate.cache.sampleWidth,
                sampleHeight: activeCandidate.cache.sampleHeight,
                sourceInfo: nil,
                prefix: "Loaded Cache"
            )
            lock.unlock()
            NSLog("StabilizerFxPlug: loaded persisted Host Analysis cache \(activeCandidate.fileName) with \(activeCandidate.frames.count) frames; \(candidateURLs.count) lazy alternate cache(s) available.")
            return true
        }
        if let unusableCacheSummary = unusableCacheSummaries.first {
            lock.lock()
            if preparedAnalysis == nil && status != .analyzing {
                status = unusableCacheSummary.status
                analysisInfoText = unusableCacheSummary.summary
                bumpRevisionLocked()
            }
            lock.unlock()
        }
        return false
    }

    func reloadPersistentCacheForConsumerIfNeeded(expectedRange: HostAnalysisExpectedRange? = nil) -> Bool {
        guard shouldReloadPersistentCacheForConsumer() else {
            return false
        }
        return loadPersistentCache(expectedRange: expectedRange)
    }

    func activatePersistentCache(identity: String, expectedRange: HostAnalysisExpectedRange? = nil) -> Bool {
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentity.isEmpty,
              Self.cacheIdentity(trimmedIdentity, matches: expectedRange)
        else {
            return false
        }

        lock.lock()
        if activePersistentCacheIdentity == trimmedIdentity,
           preparedAnalysis != nil {
            lock.unlock()
            return true
        }
        if let cached = persistentCachesByIdentity[trimmedIdentity] {
            installPersistentCacheLocked(cached)
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()
            NSLog("StabilizerFxPlug: reactivated Host Analysis cache \(cached.fileName) by saved clip identity.")
            return true
        }
        lock.unlock()

        for candidateURL in Self.persistentCacheCandidateURLs() {
            guard let candidate = Self.loadPersistentCache(at: candidateURL),
                  candidate.identity == trimmedIdentity,
                  Self.cache(candidate.cache, matches: expectedRange)
            else {
                continue
            }
            lock.lock()
            installPersistentCacheLocked(candidate)
            persistentCacheCandidates.removeAll { $0.lastPathComponent == candidate.fileName }
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()
            NSLog("StabilizerFxPlug: loaded Host Analysis cache \(candidate.fileName) by saved clip identity.")
            return true
        }
        return false
    }

    private func shouldReloadPersistentCacheForConsumer() -> Bool {
        let generation = Self.currentPersistentCacheGeneration()
        let signature = Self.currentPersistentCacheSignature()
        lock.lock()
        let cacheChanged = observedPersistentCacheSignature != signature
            || observedPersistentCacheGeneration < generation
        let needsInitialLoad = preparedAnalysis == nil
            && status != .cacheUnsupported
            && status != .cacheIncomplete
        let shouldReload = needsInitialLoad
            && (cacheChanged || persistentCacheCandidates.isEmpty)
            && status != .cacheRejected
        lock.unlock()
        return shouldReload
    }

    private func markCurrentPersistentCacheGenerationObserved() {
        let generation = Self.currentPersistentCacheGeneration()
        let signature = Self.currentPersistentCacheSignature()
        lock.lock()
        observedPersistentCacheGeneration = generation
        observedPersistentCacheSignature = signature
        lock.unlock()
    }

    private func markAnalysisCompleted() {
        let completedAt = Date()
        let snapshot: (frameCount: Int, sampleSize: (width: Int, height: Int)?, sourceInfo: StabilizerSourceFrameInfo?) = {
            lock.lock()
            let value = (framesByTimeKey.count, latestSampleSize, latestSourceFrameInfo)
            lock.unlock()
            return value
        }()
        let info = Self.infoText(
            completedAt: completedAt,
            frameCount: snapshot.frameCount,
            sampleWidth: snapshot.sampleSize?.width,
            sampleHeight: snapshot.sampleSize?.height,
            sourceInfo: snapshot.sourceInfo,
            prefix: "Analyzed"
        )
        lock.lock()
        analysisInfoText = info
        bumpRevisionLocked()
        lock.unlock()
    }

    private static func infoText(
        completedAt: Date,
        frameCount: Int,
        sampleWidth: Int?,
        sampleHeight: Int?,
        sourceInfo: StabilizerSourceFrameInfo?,
        prefix: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        let dateText = formatter.string(from: completedAt)
        let sourceText = sourceInfo?.sourceSizeDescription ?? "unknown"
        let scaleText = sourceInfo?.pixelScaleDescription ?? "unknown"
        let sampleText: String
        if let sampleWidth, let sampleHeight {
            sampleText = AutoStabilizationEstimator.sampleSizeDescription(width: sampleWidth, height: sampleHeight)
        } else {
            sampleText = "unknown"
        }
        return "\(prefix) \(dateText) | frames \(frameCount) | sample \(sampleText) | source \(sourceText) | pixel scale \(scaleText)"
    }

    private func persistIfCompleted() {
        let snapshot: (frames: [StabilizerAnalysisFrame], prepared: StabilizerPreparedAnalysis?, range: CMTimeRange, frameDuration: CMTime) = {
            lock.lock()
            let frames = framesByTimeKey.values.sorted { $0.time < $1.time }
            let prepared = preparedAnalysis
            let range = activeRange
            let frameDuration = activeFrameDuration
            lock.unlock()
            return (frames, prepared, range, frameDuration)
        }()

        guard let prepared = snapshot.prepared, prepared.frames.count >= 3 else {
            return
        }
        guard let cacheDirectoryURL = Self.cacheDirectoryURL,
              let cacheStorageDirectoryURL = Self.cacheStorageDirectoryURL,
              let latestCacheURL = Self.cacheURL
        else {
            lock.lock()
            status = .projectCacheUnavailable
            analysisInfoText = "\(stabilizerProjectCacheUnavailableMessage). Host did not provide a writable Event Analysis Files cache root."
            bumpRevisionLocked()
            lock.unlock()
            NSLog("StabilizerFxPlug: failed to save Host Analysis cache because no FCP bundle cache root is configured.")
            return
        }
        let framesToPersist = prepared.frames
        if snapshot.frames.count != framesToPersist.count {
            NSLog("StabilizerFxPlug: persisting prepared Host Analysis frame set with \(framesToPersist.count) frames; retained frame map had \(snapshot.frames.count) frames.")
        }
        let firstFrameTime = framesToPersist.first?.time ?? 0.0
        let lastFrameTime = framesToPersist.last?.time ?? firstFrameTime
        let sampleWidth = framesToPersist.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
        let sampleHeight = framesToPersist.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
        let frameDurationSeconds = Self.validFrameDurationSeconds(snapshot.frameDuration, frames: framesToPersist)
        let suppliedRangeStartSeconds = CMTimeGetSeconds(snapshot.range.start)
        let suppliedRangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        let rangeStartSeconds = suppliedRangeStartSeconds.isFinite ? suppliedRangeStartSeconds : firstFrameTime
        let rangeDurationSeconds = suppliedRangeDurationSeconds.isFinite
            ? suppliedRangeDurationSeconds
            : max(frameDurationSeconds, (lastFrameTime - firstFrameTime) + frameDurationSeconds)

        let cache = PersistedHostAnalysisCache(
            schemaVersion: Self.cacheSchemaVersion,
            createdAt: Date().timeIntervalSince1970,
            rangeStartSeconds: rangeStartSeconds,
            rangeDurationSeconds: rangeDurationSeconds,
            frameDurationSeconds: frameDurationSeconds,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            frames: framesToPersist.map {
                PersistedHostAnalysisFrame(
                    time: $0.time,
                    pixels: nil,
                    blurAmount: $0.blurAmount,
                    fingerprint: $0.fingerprint
                )
            },
            residuals: prepared.residuals,
            rollMotion: prepared.rollMotion,
            pathX: prepared.pathX,
            pathY: prepared.pathY,
            pathRoll: prepared.pathRoll,
            footstepPathX: prepared.footstepPathX,
            footstepPathY: prepared.footstepPathY,
            footstepPathRoll: prepared.footstepPathRoll,
            pathYaw: prepared.pathYaw,
            pathPitch: prepared.pathPitch,
            pathShearX: prepared.pathShearX,
            pathShearY: prepared.pathShearY,
            pathPerspectiveX: prepared.pathPerspectiveX,
            pathPerspectiveY: prepared.pathPerspectiveY,
            analysisConfidence: prepared.analysisConfidence,
            warpConfidence: prepared.warpConfidence,
            acceptedBlockCounts: prepared.acceptedBlockCounts,
            totalBlockCounts: prepared.totalBlockCounts,
            blurAmounts: prepared.blurAmounts,
            searchRadiusHitCounts: prepared.searchRadiusHitCounts,
            searchRadiusTotalCounts: prepared.searchRadiusTotalCounts
        )

        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheStorageDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            let cacheFileName = Self.persistentCacheFileName(for: cache, frames: framesToPersist)
            guard let cacheIdentity = Self.persistentCacheIdentity(for: cache, frames: framesToPersist) else {
                NSLog("StabilizerFxPlug: failed to save Host Analysis cache because the prepared frame fingerprints were incomplete.")
                return
            }
            let cacheURL = cacheStorageDirectoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
            try data.write(to: cacheURL, options: .atomic)
            try data.write(to: latestCacheURL, options: .atomic)
            if let indexEntry = Self.indexEntry(for: cache, fileName: cacheFileName, frames: framesToPersist) {
                try Self.updatePersistentCacheIndex(with: indexEntry)
            }
            lock.lock()
            activePersistentCacheFileName = cacheFileName
            activePersistentCacheIdentity = cacheIdentity
            lock.unlock()
            Self.bumpPersistentCacheGeneration()
            NSLog("StabilizerFxPlug: saved sample-size Host Analysis cache \(sampleWidth)x\(sampleHeight) with \(framesToPersist.count) prepared frames to \(cacheURL.path).")
        } catch {
            NSLog("StabilizerFxPlug: failed to save Host Analysis cache: \(error.localizedDescription)")
        }
    }

    private func rebuildPreparedAnalysis(markFinished: Bool) throws {
        let snapshot: (frames: [StabilizerAnalysisFrame], builder: StreamingStabilizationAnalysisBuilder?) = {
            lock.lock()
            let value = (framesByTimeKey.values.sorted { $0.time < $1.time }, streamingAnalysisBuilder)
            lock.unlock()
            return value
        }()
        let prepared: StabilizerPreparedAnalysis?
        if snapshot.frames.count >= 3 {
            guard let builder = snapshot.builder else {
                throw NSError(
                    domain: "com.justadev.StabilizerFxPlug",
                    code: Int(kFxError_AnalysisError),
                    userInfo: [NSLocalizedDescriptionKey: "Stabilizer streaming analysis was unavailable at finish."]
                )
            }
            prepared = try builder.preparedAnalysis()
        } else {
            prepared = nil
        }
        lock.lock()
        preparedAnalysis = prepared
        if markFinished {
            activePersistentCacheFileName = nil
            activePersistentCacheIdentity = nil
            streamingAnalysisBuilder = nil
        }
        if markFinished {
            finished = true
            status = prepared == nil ? .needsAnalysis : .ready
        }
        bumpRevisionLocked()
        lock.unlock()
    }

    private func releaseRetainedAnalysisPixels() {
        lock.lock()
        framesByTimeKey = framesByTimeKey.mapValues { $0.withoutRetainedPixels() }
        if let analysis = preparedAnalysis {
            preparedAnalysis = StabilizerPreparedAnalysis(
                frames: analysis.frames.map { $0.withoutRetainedPixels() },
                residuals: analysis.residuals,
                rollMotion: analysis.rollMotion,
                pathX: analysis.pathX,
                pathY: analysis.pathY,
                pathRoll: analysis.pathRoll,
                footstepPathX: analysis.footstepPathX,
                footstepPathY: analysis.footstepPathY,
                footstepPathRoll: analysis.footstepPathRoll,
                pathYaw: analysis.pathYaw,
                pathPitch: analysis.pathPitch,
                pathShearX: analysis.pathShearX,
                pathShearY: analysis.pathShearY,
                pathPerspectiveX: analysis.pathPerspectiveX,
                pathPerspectiveY: analysis.pathPerspectiveY,
                analysisConfidence: analysis.analysisConfidence,
                warpConfidence: analysis.warpConfidence,
                acceptedBlockCounts: analysis.acceptedBlockCounts,
                totalBlockCounts: analysis.totalBlockCounts,
                blurAmounts: analysis.blurAmounts,
                searchRadiusHitCounts: analysis.searchRadiusHitCounts,
                searchRadiusTotalCounts: analysis.searchRadiusTotalCounts
            )
        }
        lock.unlock()
    }

    private func preparedAnalysisSnapshot() -> StabilizerPreparedAnalysis? {
        lock.lock()
        let analysis = preparedAnalysis
        lock.unlock()
        return analysis
    }

    private func completedAnalysisSnapshot() -> CompletedHostAnalysisSnapshot {
        lock.lock()
        let snapshot = (
            frames: framesByTimeKey.values.sorted { $0.time < $1.time },
            preparedAnalysis: preparedAnalysis,
            activeRange: activeRange,
            activeFrameDuration: activeFrameDuration,
            activeRequestedSampleScalePercent: activeRequestedSampleScalePercent,
            finished: finished,
            validationState: validationState,
            status: status,
            latestSourceFrameInfo: latestSourceFrameInfo,
            latestSampleSize: latestSampleSize,
            analysisInfoText: analysisInfoText,
            activePersistentCacheIdentity: activePersistentCacheIdentity
        )
        lock.unlock()
        return snapshot
    }

    private func framesSnapshot() -> [StabilizerAnalysisFrame] {
        lock.lock()
        let frames = framesByTimeKey.values.sorted { $0.time < $1.time }
        lock.unlock()
        return frames
    }

    private var hasCompletedInMemoryAnalysis: Bool {
        lock.lock()
        let hasCompleted = finished
            && validationState != .rejected
            && preparedAnalysis != nil
            && activePersistentCacheIdentity == nil
        lock.unlock()
        return hasCompleted
    }

    private func currentValidationState() -> HostAnalysisValidationState {
        lock.lock()
        let state = validationState
        lock.unlock()
        return state
    }

    private func markProxyMediaUnavailable(reason: String) {
        lock.lock()
        if status != .proxyRejected {
            status = .proxyRejected
            analysisInfoText = "Rejected proxy media. Use original media and rerun Host Analysis."
            bumpRevisionLocked()
        }
        lock.unlock()
        NSLog("StabilizerFxPlug: refusing proxy media frame: \(reason)")
    }

    private func markReadyAfterOriginalMediaReturnedIfNeeded() {
        lock.lock()
        if (status == .proxyRejected || status == .proxyPreview || status == .proxyNeedsOriginalValidation || status == .sourceUnavailable),
           preparedAnalysis != nil {
            status = .ready
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    private func markProxyPreviewForRender(reason: String) {
        lock.lock()
        let shouldMarkProxyPreview = preparedAnalysis != nil
            && status != .proxyPreview
        if shouldMarkProxyPreview {
            status = .proxyPreview
            analysisInfoText = "Using saved Host Analysis for proxy playback. If Final Cut Pro shows Missing Proxy, switch Viewer playback to Original/Optimized or create proxy media."
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMarkProxyPreview {
            NSLog("StabilizerFxPlug: keeping prepared Host Analysis active for proxy preview before original-media validation: \(reason)")
        }
    }

    private func markProxyNeedsOriginalValidationForRender(reason: String) {
        lock.lock()
        let shouldMark = status != .proxyNeedsOriginalValidation
        if shouldMark {
            status = .proxyNeedsOriginalValidation
            analysisInfoText = "Proxy playback cannot select a different clip's latest cache. Switch Viewer playback to Original/Optimized once so this clip can validate its saved Host Analysis cache."
            bumpRevisionLocked()
        }
        lock.unlock()
        if shouldMark {
            NSLog("StabilizerFxPlug: refused unvalidated proxy Host Analysis cache selection: \(reason)")
        }
    }

    private func markSourceUnavailableForRender(reason: String) {
        lock.lock()
        let shouldMarkSourceUnavailable = status != .sourceUnavailable
        if shouldMarkSourceUnavailable {
            status = .sourceUnavailable
            analysisInfoText = "Render source unavailable. \(reason) Switch Viewer playback to Original/Optimized or create proxy media."
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    private func rejectPersistentCache(reason: String) {
        lock.lock()
        let rejectedFileName = activePersistentCacheFileName
        if let rejectedFileName {
            rejectedPersistentCacheFileNames.insert(rejectedFileName)
        }
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .rejected
        status = .cacheRejected
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(reason).")
    }

    private func rejectActiveInMemoryAnalysis(reason: String) {
        lock.lock()
        let rejectedIdentity = activeCompletedMemoryAnalysisIdentity
        if let rejectedIdentity {
            rejectedCompletedMemoryAnalysisIdentities.insert(rejectedIdentity)
        }
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        validationState = .rejected
        status = .cacheRejected
        analysisInfoText = "In-memory Host Analysis did not match the current clip. Run Host Analysis again."
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: rejected in-memory Host Analysis \(rejectedIdentity ?? "<unknown>"): \(reason).")
    }

    private func persistentCacheRejectionReason(for analysis: StabilizerPreparedAnalysis, validating sourceImage: FxImageTile, at renderTime: CMTime) -> String? {
        let validationTime = analysisRenderTime(for: renderTime, preparedAnalysis: analysis)
        let currentFrame: StabilizerAnalysisFrame
        do {
            let sampleWidth = analysis.frames.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
            let sampleHeight = analysis.frames.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
            currentFrame = try AutoStabilizationEstimator.analysisFrame(
                from: sourceImage,
                at: validationTime,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
        } catch {
            return "could not validate the persisted cache against the current source frame: \(error.localizedDescription)"
        }
        guard let matchedFrame = matchedAnalysisFrame(for: currentFrame, in: analysis.frames) else {
            return "persisted cache had no comparable frame"
        }
        updateRenderTimeMapping(renderTime: renderTime, matchedAnalysisFrame: matchedFrame)

        if matchedFrame.pixels.isEmpty {
            if matchedFrame.fingerprint != currentFrame.fingerprint {
                NSLog(
                    "StabilizerFxPlug: accepted persisted Host Analysis cache by time proximity because retained validation pixels were not available; current fingerprint %@, cached fingerprint %@.",
                    currentFrame.fingerprint,
                    matchedFrame.fingerprint
                )
            }
            return nil
        }

        let meanDifference = Self.meanAbsoluteDifference(currentFrame.pixels, matchedFrame.pixels)
        guard meanDifference <= Self.cacheValidationMeanDifferenceThreshold else {
            return String(format: "current frame did not match the persisted cache (mean luma difference %.2f)", meanDifference)
        }
        return nil
    }

    private func updateRenderTimeMappingIfNeeded(for analysis: StabilizerPreparedAnalysis, validating sourceImage: FxImageTile, at renderTime: CMTime) {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite,
              !analysis.frames.isEmpty
        else {
            return
        }
        guard StabilizerOriginalMediaPolicy.proxyRejectionReason(for: sourceImage) == nil else {
            return
        }
        let renderTimeInsideAnalysisRange = Self.renderSeconds(renderSeconds, isInside: analysis.frames)
        lock.lock()
        let alreadyMapped = renderToAnalysisOffsetSeconds != nil
        let probeAttempted = renderToAnalysisOffsetProbeAttempted
        if !alreadyMapped, (!probeAttempted || !renderTimeInsideAnalysisRange) {
            renderToAnalysisOffsetProbeAttempted = true
        }
        lock.unlock()
        guard !alreadyMapped, !probeAttempted || !renderTimeInsideAnalysisRange else {
            return
        }

        do {
            let sampleWidth = analysis.frames.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
            let sampleHeight = analysis.frames.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
            let currentFrame = try AutoStabilizationEstimator.analysisFrame(
                from: sourceImage,
                at: renderTime,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
            if let matchedFrame = matchedAnalysisFrame(for: currentFrame, in: analysis.frames) {
                updateRenderTimeMapping(renderTime: renderTime, matchedAnalysisFrame: matchedFrame)
            }
        } catch {
            NSLog("StabilizerFxPlug: could not map trimmed render time to Host Analysis time: \(error.localizedDescription)")
        }
    }

    private func updateRenderTimeMapping(renderTime: CMTime, matchedAnalysisFrame: StabilizerAnalysisFrame) {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite, matchedAnalysisFrame.time.isFinite else {
            return
        }
        let offsetSeconds = matchedAnalysisFrame.time - renderSeconds
        lock.lock()
        renderToAnalysisOffsetSeconds = offsetSeconds
        renderToAnalysisOffsetProbeAttempted = true
        let cacheIdentity = activePersistentCacheIdentity
        lock.unlock()
        if let cacheIdentity {
            Self.saveRenderTimeOffset(
                cacheIdentity: cacheIdentity,
                offsetSeconds: offsetSeconds,
                renderSeconds: renderSeconds,
                analysisSeconds: matchedAnalysisFrame.time
            )
        }
    }

    private func matchedAnalysisFrame(for currentFrame: StabilizerAnalysisFrame, in frames: [StabilizerAnalysisFrame]) -> StabilizerAnalysisFrame? {
        if let fingerprintMatch = frames.first(where: { $0.fingerprint == currentFrame.fingerprint }) {
            return fingerprintMatch
        }
        guard let closestFrame = frames.min(by: { abs($0.time - currentFrame.time) < abs($1.time - currentFrame.time) }) else {
            return nil
        }
        if closestFrame.pixels.isEmpty {
            return nil
        }
        guard Self.meanAbsoluteDifference(currentFrame.pixels, closestFrame.pixels) <= Self.cacheValidationMeanDifferenceThreshold else {
            return nil
        }
        return closestFrame
    }

    private func deactivateActiveCacheForRangeMismatch() {
        lock.lock()
        let oldFileName = activePersistentCacheFileName
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        analysisInfoText = "No matching Host Analysis cache for the active clip range."
        bumpRevisionLocked()
        lock.unlock()
        if let oldFileName {
            NSLog("StabilizerFxPlug: deactivated Host Analysis cache \(oldFileName) because its range does not match the active clip.")
        }
    }

    private func activeCompletedMemoryAnalysisDoesNotMatch(expectedRange: HostAnalysisExpectedRange) -> Bool {
        guard let expectedKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange) else {
            return false
        }
        lock.lock()
        let hasActiveMemoryAnalysis = activePersistentCacheIdentity == nil
            && preparedAnalysis != nil
            && finished
        let activeKey = Self.completedMemoryAnalysisRangeKey(range: activeRange)
        lock.unlock()
        return hasActiveMemoryAnalysis && activeKey != expectedKey
    }

    private func deactivateActiveCompletedMemoryAnalysisForRangeMismatch() {
        lock.lock()
        let oldIdentity = activeCompletedMemoryAnalysisIdentity
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = nil
        activePersistentCacheIdentity = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        analysisInfoText = "No matching in-memory Host Analysis for the active clip range."
        bumpRevisionLocked()
        lock.unlock()
        if let oldIdentity {
            NSLog("StabilizerFxPlug: deactivated in-memory Host Analysis \(oldIdentity) because its range does not match the active clip.")
        }
    }

    private func activateNextCompletedMemoryAnalysis(afterRejecting rejectionReason: String?, expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange,
              let rangeKey = Self.completedMemoryAnalysisRangeKey(expectedRange: expectedRange)
        else {
            return false
        }

        lock.lock()
        if let rejectionReason,
           let rejectedIdentity = activeCompletedMemoryAnalysisIdentity {
            rejectedCompletedMemoryAnalysisIdentities.insert(rejectedIdentity)
            NSLog("StabilizerFxPlug: rejected in-memory Host Analysis \(rejectedIdentity): \(rejectionReason).")
        }
        guard let memoryAnalysis = nextCompletedMemoryAnalysisLocked(rangeKey: rangeKey) else {
            lock.unlock()
            return false
        }
        installCompletedAnalysisLocked(memoryAnalysis.snapshot, validationStateOverride: .pending)
        activeCompletedMemoryAnalysisIdentity = memoryAnalysis.identity
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: activated alternate in-memory Host Analysis \(memoryAnalysis.identity) for range \(rangeKey).")
        return true
    }

    private func nextCompletedMemoryAnalysisLocked(rangeKey: String) -> CompletedMemoryHostAnalysis? {
        guard let identities = completedMemoryAnalysisIdentitiesByRangeKey[rangeKey] else {
            return nil
        }
        for identity in identities.reversed() {
            guard identity != activeCompletedMemoryAnalysisIdentity,
                  !rejectedCompletedMemoryAnalysisIdentities.contains(identity),
                  let memoryAnalysis = completedMemoryAnalysesByIdentity[identity]
            else {
                continue
            }
            return memoryAnalysis
        }
        return nil
    }

    private func activateNextPersistentCache(afterRejecting rejectionReason: String?, expectedRange: HostAnalysisExpectedRange?) -> Bool {
        while true {
            lock.lock()
            let rejectedFileName = activePersistentCacheFileName
            if rejectionReason != nil,
               let rejectedFileName {
                rejectedPersistentCacheFileNames.insert(rejectedFileName)
                persistentCacheCandidates.removeAll { $0.lastPathComponent == rejectedFileName }
            }
            guard !persistentCacheCandidates.isEmpty else {
                lock.unlock()
                if let rejectionReason {
                    NSLog("StabilizerFxPlug: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(rejectionReason).")
                }
                return false
            }
            let nextURL = persistentCacheCandidates.removeFirst()
            let remainingURLCount = persistentCacheCandidates.count
            lock.unlock()

            guard let nextCandidate = Self.loadPersistentCache(at: nextURL) else {
                NSLog("StabilizerFxPlug: skipped unavailable Host Analysis cache candidate \(nextURL.lastPathComponent); \(remainingURLCount) lazy alternate cache(s) remain.")
                continue
            }
            guard Self.cache(nextCandidate.cache, matches: expectedRange) else {
                NSLog("StabilizerFxPlug: skipped Host Analysis cache candidate \(nextCandidate.fileName) because its range does not match the active clip.")
                continue
            }

            lock.lock()
            installPersistentCacheLocked(nextCandidate)
            let remainingCount = persistentCacheCandidates.count
            lock.unlock()
            markCurrentPersistentCacheGenerationObserved()

            if let rejectionReason {
                NSLog("StabilizerFxPlug: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(rejectionReason); trying \(nextCandidate.fileName).")
            } else {
                NSLog("StabilizerFxPlug: activating persisted Host Analysis cache \(nextCandidate.fileName).")
            }
            if remainingCount > 0 {
                NSLog("StabilizerFxPlug: \(remainingCount) lazy alternate Host Analysis cache(s) remain available.")
            }
            return true
        }
    }

    private func installPersistentCacheLocked(_ loadedCache: LoadedPersistentHostAnalysisCache) {
        persistentCachesByIdentity[loadedCache.identity] = loadedCache
        framesByTimeKey = Dictionary(uniqueKeysWithValues: loadedCache.frames.map { (Self.timeKey($0.time), $0) })
        preparedAnalysis = loadedCache.preparedAnalysis
        activeCompletedMemoryAnalysisIdentity = nil
        activePersistentCacheFileName = loadedCache.fileName
        activePersistentCacheIdentity = loadedCache.identity
        activeRange = CMTimeRange(
            start: CMTime(seconds: loadedCache.cache.rangeStartSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: loadedCache.cache.rangeDurationSeconds, preferredTimescale: 600)
        )
        activeFrameDuration = CMTime(seconds: loadedCache.cache.frameDurationSeconds, preferredTimescale: 600)
        if let savedOffset = Self.savedRenderTimeOffset(for: loadedCache.identity) {
            renderToAnalysisOffsetSeconds = savedOffset
            renderToAnalysisOffsetProbeAttempted = true
        } else {
            renderToAnalysisOffsetSeconds = nil
            renderToAnalysisOffsetProbeAttempted = false
        }
        finished = true
        validationState = .pending
        status = .cacheLoaded
        observedPersistentCacheGeneration = Self.currentPersistentCacheGeneration()
        bumpRevisionLocked()
    }

    private func filteredPersistentCacheCandidateURLs() -> [URL] {
        let candidateURLs = Self.persistentCacheCandidateURLs()
        lock.lock()
        let rejectedFileNames = rejectedPersistentCacheFileNames
        lock.unlock()
        guard !rejectedFileNames.isEmpty else {
            return candidateURLs
        }
        let filteredURLs = candidateURLs.filter { !rejectedFileNames.contains($0.lastPathComponent) }
        let skippedCount = candidateURLs.count - filteredURLs.count
        if skippedCount > 0 {
            NSLog("StabilizerFxPlug: skipped \(skippedCount) rejected Host Analysis cache candidate(s) before loading persistent cache.")
        }
        return filteredURLs
    }

    private static func currentPersistentCacheGeneration() -> UInt64 {
        persistentCacheGenerationLock.lock()
        let generation = persistentCacheGeneration
        persistentCacheGenerationLock.unlock()
        return generation
    }

    private static func currentPersistentCacheSignature() -> String {
        var components: [String] = []
        var seenPaths = Set<String>()

        func appendSignature(for url: URL) {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return
            }
            guard let values = try? standardizedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate
            else {
                return
            }
            let fileSize = values.fileSize ?? 0
            components.append("\(standardizedURL.path):\(modifiedAt.timeIntervalSince1970):\(fileSize)")
        }

        for directoryURL in cacheDirectoryURLs {
            appendSignature(for: cacheURL(in: directoryURL))
            appendSignature(for: cacheIndexURL(in: directoryURL))
            let storageURL = cacheStorageDirectoryURL(in: directoryURL)
            if let cacheURLs = try? FileManager.default.contentsOfDirectory(
                at: storageURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in cacheURLs where url.pathExtension == "json" {
                    appendSignature(for: url)
                }
            }
        }

        return components.sorted().joined(separator: "|")
    }

    private static func bumpPersistentCacheGeneration() {
        persistentCacheGenerationLock.lock()
        persistentCacheGeneration &+= 1
        persistentCacheGenerationLock.unlock()
    }

    private func mappedAnalysisSeconds(forRenderSeconds renderSeconds: Double, frames: [StabilizerAnalysisFrame]) -> Double {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return renderSeconds
        }

        let activeRangeSnapshot: CMTimeRange
        let activeFrameDurationSnapshot: CMTime
        lock.lock()
        activeRangeSnapshot = activeRange
        activeFrameDurationSnapshot = activeFrameDuration
        lock.unlock()

        let rangeStartSeconds = CMTimeGetSeconds(activeRangeSnapshot.start)
        let frameDurationSeconds = CMTimeGetSeconds(activeFrameDurationSnapshot)
        let padding = max(0.05, frameDurationSeconds.isFinite ? frameDurationSeconds * 2.0 : 0.05)
        var candidates = [renderSeconds, renderSeconds + firstFrameTime, renderSeconds - firstFrameTime]
        if rangeStartSeconds.isFinite {
            candidates.append(renderSeconds - rangeStartSeconds + firstFrameTime)
            candidates.append(renderSeconds + rangeStartSeconds - firstFrameTime)
        }

        var bestSeconds = renderSeconds
        var bestScore = Self.frameRangeDistance(renderSeconds, firstFrameTime: firstFrameTime, lastFrameTime: lastFrameTime, padding: padding)
        for candidate in candidates where candidate.isFinite {
            let clampedCandidate = min(max(candidate, firstFrameTime), lastFrameTime)
            let score = Self.frameRangeDistance(candidate, firstFrameTime: firstFrameTime, lastFrameTime: lastFrameTime, padding: padding)
                + abs(candidate - renderSeconds) * 1e-9
            if score < bestScore {
                bestScore = score
                bestSeconds = clampedCandidate
            }
        }
        return bestSeconds
    }

    private func bumpRevisionLocked() {
        analysisRevision &+= 1
        renderRevisionToken = Self.nextRenderInvalidationToken(after: renderRevisionToken)
    }

    private static func nextRenderInvalidationToken(after currentToken: Double) -> Double {
        let milliseconds = UInt64((Date().timeIntervalSinceReferenceDate * 1000.0).rounded())
        let nextToken = Double((milliseconds % 900_000) + 1_000)
        if abs(nextToken - currentToken) >= 0.5 {
            return nextToken
        }
        let incrementedToken = currentToken + 1.0
        return incrementedToken < 901_000.0 ? incrementedToken : 1_000.0
    }

    private func removePersistentCache(logFailures: Bool) {
        let urls = Self.cacheDirectoryURLs.flatMap { directoryURL in
            [
                Self.cacheURL(in: directoryURL),
                Self.cacheIndexURL(in: directoryURL),
                Self.renderTimeOffsetURL(in: directoryURL),
                Self.cacheStorageDirectoryURL(in: directoryURL)
            ]
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                if logFailures {
                    NSLog("StabilizerFxPlug: failed to remove Host Analysis cache \(url.path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func removeLegacyAnalysisScratchDirectory() {
        for scratchDirectory in Self.cacheDirectoryURLs.map(Self.analysisScratchDirectoryURL(in:)) where FileManager.default.fileExists(atPath: scratchDirectory.path) {
            do {
                try FileManager.default.removeItem(at: scratchDirectory)
            } catch {
                NSLog("StabilizerFxPlug: failed to remove legacy Host Analysis scratch directory \(scratchDirectory.path): \(error.localizedDescription)")
            }
        }
    }

    static func timeKey(_ seconds: Double) -> Int64 {
        Int64((seconds * 600.0).rounded())
    }

    private static func completedMemoryAnalysisRangeKey(range: CMTimeRange) -> String? {
        let startSeconds = CMTimeGetSeconds(range.start)
        let durationSeconds = CMTimeGetSeconds(range.duration)
        guard startSeconds.isFinite,
              durationSeconds.isFinite,
              durationSeconds > 0.0
        else {
            return nil
        }
        return "\(timeKey(startSeconds)):\(timeKey(durationSeconds))"
    }

    private static func completedMemoryAnalysisRangeKey(expectedRange: HostAnalysisExpectedRange) -> String? {
        guard expectedRange.isValid else {
            return nil
        }
        return "\(timeKey(expectedRange.startSeconds)):\(timeKey(expectedRange.durationSeconds))"
    }

    private static func completedMemoryAnalysisIdentity(snapshot: CompletedHostAnalysisSnapshot, rangeKey: String) -> String? {
        guard let preparedAnalysis = snapshot.preparedAnalysis,
              let firstFrame = preparedAnalysis.frames.first,
              let fingerprints = persistentCacheFingerprints(for: preparedAnalysis.frames)
        else {
            NSLog("StabilizerFxPlug: could not retain completed in-memory Host Analysis because frame fingerprints were incomplete.")
            return nil
        }
        let frameDurationSeconds = CMTimeGetSeconds(snapshot.activeFrameDuration)
        guard frameDurationSeconds.isFinite else {
            return nil
        }
        return [
            "memory",
            "\(cacheSchemaVersion)",
            rangeKey,
            "\(timeKey(frameDurationSeconds))",
            "\(firstFrame.sampleWidth)",
            "\(firstFrame.sampleHeight)",
            "\(preparedAnalysis.frames.count)",
            fingerprints.first,
            fingerprints.middle,
            fingerprints.last
        ].joined(separator: ":")
    }

    static func cacheIdentity(_ identity: String, matches expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        let parts = identity.split(separator: ":", omittingEmptySubsequences: false)
        let startIndex = parts.count >= 10 ? 1 : 0
        guard parts.count > startIndex + 1,
              let rangeStartKey = Int64(parts[startIndex]),
              let rangeDurationKey = Int64(parts[startIndex + 1])
        else {
            return false
        }
        return rangeStartKey == timeKey(expectedRange.startSeconds)
            && rangeDurationKey == timeKey(expectedRange.durationSeconds)
    }

    private static func cache(_ cache: PersistedHostAnalysisCache, matches expectedRange: HostAnalysisExpectedRange?) -> Bool {
        guard let expectedRange, expectedRange.isValid else {
            return true
        }
        return timeKey(cache.rangeStartSeconds) == timeKey(expectedRange.startSeconds)
            && timeKey(cache.rangeDurationSeconds) == timeKey(expectedRange.durationSeconds)
    }

    private static func validFrameDurationSeconds(_ frameDuration: CMTime, frames: [StabilizerAnalysisFrame]) -> Double {
        let supplied = CMTimeGetSeconds(frameDuration)
        if supplied.isFinite, supplied > 0.0 {
            return supplied
        }
        guard frames.count >= 2 else {
            return 1.0 / 30.0
        }
        let sortedTimes = frames.map(\.time).sorted()
        var deltas: [Double] = []
        for index in 1..<sortedTimes.count {
            let delta = sortedTimes[index] - sortedTimes[index - 1]
            if delta.isFinite, delta > 0.0 {
                deltas.append(delta)
            }
        }
        guard !deltas.isEmpty else {
            return 1.0 / 30.0
        }
        return deltas[deltas.count / 2]
    }

    private func validateCompletedFrameCoverage() throws {
        let snapshot: (frames: [StabilizerAnalysisFrame], range: CMTimeRange, frameDuration: CMTime) = {
            lock.lock()
            let frames = (preparedAnalysis?.frames ?? Array(framesByTimeKey.values)).sorted { $0.time < $1.time }
            let range = activeRange
            let frameDuration = activeFrameDuration
            lock.unlock()
            return (frames, range, frameDuration)
        }()
        let frameDurationSeconds = Self.validFrameDurationSeconds(snapshot.frameDuration, frames: snapshot.frames)
        let rangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        guard let reason = Self.frameCoverageMismatchReason(
            frameCount: snapshot.frames.count,
            rangeDurationSeconds: rangeDurationSeconds,
            frameDurationSeconds: frameDurationSeconds
        ) else {
            return
        }
        throw NSError(
            domain: "com.justadev.StabilizerFxPlug",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: "Host Analysis had incomplete frame coverage: \(reason)"]
        )
    }

    private static func persistentFrameCoverageMismatchReason(for cache: PersistedHostAnalysisCache, frameCount: Int) -> String? {
        frameCoverageMismatchReason(
            frameCount: frameCount,
            rangeDurationSeconds: cache.rangeDurationSeconds,
            frameDurationSeconds: cache.frameDurationSeconds
        )
    }

    private static func frameCoverageMismatchReason(
        frameCount: Int,
        rangeDurationSeconds: Double,
        frameDurationSeconds: Double
    ) -> String? {
        guard rangeDurationSeconds.isFinite,
              frameDurationSeconds.isFinite,
              rangeDurationSeconds > 0.0,
              frameDurationSeconds > 0.0
        else {
            return nil
        }
        let expectedFrameCount = max(1, Int((rangeDurationSeconds / frameDurationSeconds).rounded(.down)) + 1)
        guard expectedFrameCount > 3 else {
            return frameCount >= 3 ? nil : "only \(frameCount) frames for a short analyzed range"
        }
        let minimumFrameCount = max(3, Int((Double(expectedFrameCount) * 0.90).rounded(.down)))
        guard frameCount < minimumFrameCount else {
            return nil
        }
        return "only \(frameCount) frames for \(String(format: "%.2f", rangeDurationSeconds))s at \(String(format: "%.6f", frameDurationSeconds))s/frame; expected about \(expectedFrameCount)"
    }

    private static func plausiblePersistedFrameCountLimit(for cache: PersistedHostAnalysisCache) -> Int? {
        guard cache.rangeDurationSeconds.isFinite,
              cache.frameDurationSeconds.isFinite,
              cache.rangeDurationSeconds > 0.0,
              cache.frameDurationSeconds > 0.0
        else {
            return nil
        }
        let expectedFrameCount = Int((cache.rangeDurationSeconds / cache.frameDurationSeconds).rounded(.up)) + 2
        return max(120, expectedFrameCount * 3)
    }

    private static func frameRangeDistance(_ seconds: Double, firstFrameTime: Double, lastFrameTime: Double, padding: Double) -> Double {
        if seconds < firstFrameTime - padding {
            return firstFrameTime - padding - seconds
        }
        if seconds > lastFrameTime + padding {
            return seconds - lastFrameTime - padding
        }
        return 0.0
    }

    private static func renderSeconds(_ seconds: Double, isInside frames: [StabilizerAnalysisFrame]) -> Bool {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return true
        }
        return seconds >= firstFrameTime && seconds <= lastFrameTime
    }

    private static func clampedAnalysisSeconds(_ seconds: Double, frames: [StabilizerAnalysisFrame]) -> Double {
        guard let firstFrameTime = frames.first?.time,
              let lastFrameTime = frames.last?.time,
              firstFrameTime.isFinite,
              lastFrameTime.isFinite
        else {
            return seconds
        }
        return min(max(seconds, firstFrameTime), lastFrameTime)
    }

    private static func preparedAnalysis(from cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) throws -> StabilizerPreparedAnalysis {
        if let coverageReason = persistentFrameCoverageMismatchReason(for: cache, frameCount: frames.count) {
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache frame coverage is incomplete: \(coverageReason)"]
            )
        }
        if let mismatchReason = preparedPathArrayMismatchReason(for: cache, frameCount: frames.count) {
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache prepared paths are incomplete: \(mismatchReason)"]
            )
        }
        let floatArrays = [
            cache.residuals,
            cache.rollMotion,
            cache.pathX,
            cache.pathY,
            cache.pathRoll,
            cache.footstepPathX,
            cache.footstepPathY,
            cache.footstepPathRoll,
            cache.pathYaw,
            cache.pathPitch,
            cache.pathShearX,
            cache.pathShearY,
            cache.pathPerspectiveX,
            cache.pathPerspectiveY,
            cache.analysisConfidence,
            cache.warpConfidence,
            cache.blurAmounts
        ]
        let countArrays = [
            cache.acceptedBlockCounts,
            cache.totalBlockCounts,
            cache.searchRadiusHitCounts,
            cache.searchRadiusTotalCounts
        ]
        if floatArrays.allSatisfy({ $0?.count == frames.count }),
           countArrays.allSatisfy({ $0?.count == frames.count }),
           let residuals = cache.residuals,
           let rollMotion = cache.rollMotion,
           let pathX = cache.pathX,
           let pathY = cache.pathY,
           let pathRoll = cache.pathRoll,
           let footstepPathX = cache.footstepPathX,
           let footstepPathY = cache.footstepPathY,
           let footstepPathRoll = cache.footstepPathRoll,
           let pathYaw = cache.pathYaw,
           let pathPitch = cache.pathPitch,
           let pathShearX = cache.pathShearX,
           let pathShearY = cache.pathShearY,
           let pathPerspectiveX = cache.pathPerspectiveX,
           let pathPerspectiveY = cache.pathPerspectiveY,
           let analysisConfidence = cache.analysisConfidence,
           let warpConfidence = cache.warpConfidence,
           let acceptedBlockCounts = cache.acceptedBlockCounts,
           let totalBlockCounts = cache.totalBlockCounts,
           let blurAmounts = cache.blurAmounts,
           let searchRadiusHitCounts = cache.searchRadiusHitCounts,
           let searchRadiusTotalCounts = cache.searchRadiusTotalCounts {
            return StabilizerPreparedAnalysis(
                frames: frames.sorted { $0.time < $1.time },
                residuals: residuals,
                rollMotion: rollMotion,
                pathX: pathX,
                pathY: pathY,
                pathRoll: pathRoll,
                footstepPathX: footstepPathX,
                footstepPathY: footstepPathY,
                footstepPathRoll: footstepPathRoll,
                pathYaw: pathYaw,
                pathPitch: pathPitch,
                pathShearX: pathShearX,
                pathShearY: pathShearY,
                pathPerspectiveX: pathPerspectiveX,
                pathPerspectiveY: pathPerspectiveY,
                analysisConfidence: analysisConfidence,
                warpConfidence: warpConfidence,
                acceptedBlockCounts: acceptedBlockCounts,
                totalBlockCounts: totalBlockCounts,
                blurAmounts: blurAmounts,
                searchRadiusHitCounts: searchRadiusHitCounts,
                searchRadiusTotalCounts: searchRadiusTotalCounts
            )
        }
        throw NSError(
            domain: "com.justadev.StabilizerFxPlug",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache was missing prepared Metal motion paths"]
        )
    }

    private static func preparedPathArrayMismatchReason(for cache: PersistedHostAnalysisCache, frameCount: Int) -> String? {
        let floatArrays: [(String, [Float]?)] = [
            ("residuals", cache.residuals),
            ("rollMotion", cache.rollMotion),
            ("pathX", cache.pathX),
            ("pathY", cache.pathY),
            ("pathRoll", cache.pathRoll),
            ("footstepPathX", cache.footstepPathX),
            ("footstepPathY", cache.footstepPathY),
            ("footstepPathRoll", cache.footstepPathRoll),
            ("pathYaw", cache.pathYaw),
            ("pathPitch", cache.pathPitch),
            ("pathShearX", cache.pathShearX),
            ("pathShearY", cache.pathShearY),
            ("pathPerspectiveX", cache.pathPerspectiveX),
            ("pathPerspectiveY", cache.pathPerspectiveY),
            ("analysisConfidence", cache.analysisConfidence),
            ("warpConfidence", cache.warpConfidence),
            ("blurAmounts", cache.blurAmounts)
        ]
        let countArrays: [(String, [Int32]?)] = [
            ("acceptedBlockCounts", cache.acceptedBlockCounts),
            ("totalBlockCounts", cache.totalBlockCounts),
            ("searchRadiusHitCounts", cache.searchRadiusHitCounts),
            ("searchRadiusTotalCounts", cache.searchRadiusTotalCounts)
        ]
        for (name, values) in floatArrays {
            guard let values else {
                return "\(name) is missing"
            }
            if values.count != frameCount {
                return "\(name) has \(values.count) values but frames has \(frameCount)"
            }
        }
        for (name, values) in countArrays {
            guard let values else {
                return "\(name) is missing"
            }
            if values.count != frameCount {
                return "\(name) has \(values.count) values but frames has \(frameCount)"
            }
        }
        return nil
    }

    private static func persistentCacheCandidateURLs() -> [URL] {
        var candidateURLs: [URL] = []
        var seenPaths = Set<String>()

        func appendCandidateURL(_ url: URL) {
            guard FileManager.default.fileExists(atPath: url.path),
                  seenPaths.insert(url.path).inserted
            else {
                return
            }
            candidateURLs.append(url)
        }

        for directoryURL in cacheDirectoryURLs {
            let directoryCacheIndexURL = cacheIndexURL(in: directoryURL)
            let directoryCacheStorageURL = cacheStorageDirectoryURL(in: directoryURL)
            if FileManager.default.fileExists(atPath: directoryCacheIndexURL.path) {
                do {
                    let data = try Data(contentsOf: directoryCacheIndexURL)
                    let index = try JSONDecoder().decode(PersistedHostAnalysisIndex.self, from: data)
                    if !supportedCacheSchemaVersions.contains(index.schemaVersion) {
                        NSLog("StabilizerFxPlug: ignoring Host Analysis cache index with unsupported schema \(index.schemaVersion) at \(directoryCacheIndexURL.path).")
                    } else {
                        for entry in index.entries {
                            appendCandidateURL(directoryCacheStorageURL.appendingPathComponent(entry.cacheFileName, isDirectory: false))
                        }
                    }
                } catch {
                    NSLog("StabilizerFxPlug: failed to load Host Analysis cache index \(directoryCacheIndexURL.path): \(error.localizedDescription)")
                }
            }

            if let cacheURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryCacheStorageURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                let sortedCacheURLs = cacheURLs
                    .filter { $0.pathExtension == "json" }
                    .sorted {
                        let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return leftDate > rightDate
                    }
                for url in sortedCacheURLs {
                    appendCandidateURL(url)
                }
            }

            appendCandidateURL(cacheURL(in: directoryURL))
        }

        return candidateURLs
    }

    private static func unsupportedPersistentCacheSummary(at url: URL) -> String? {
        do {
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxPersistentCacheReadBytes {
                return nil
            }
            let data = try Data(contentsOf: url)
            let header = try JSONDecoder().decode(PersistedHostAnalysisSchemaHeader.self, from: data)
            guard !supportedCacheSchemaVersions.contains(header.schemaVersion) else {
                return nil
            }
            let expectedSchema = supportedCacheSchemaVersions.sorted().map(String.init).joined(separator: ",")
            return "Cache Unsupported (schema \(header.schemaVersion), need \(expectedSchema)) | \(url.lastPathComponent)"
        } catch {
            return nil
        }
    }

    private static func incompletePersistentCacheSummary(at url: URL) -> String? {
        do {
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxPersistentCacheReadBytes {
                return nil
            }
            let data = try Data(contentsOf: url)
            let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
            guard supportedCacheSchemaVersions.contains(cache.schemaVersion) else {
                return nil
            }
            let frameCount = cache.frames.count
            guard frameCount >= 3 else {
                return "Cache Incomplete (only \(frameCount) frames) | \(url.lastPathComponent)"
            }
            if let coverageReason = persistentFrameCoverageMismatchReason(for: cache, frameCount: frameCount) {
                return "Cache Incomplete (\(coverageReason)) | \(url.lastPathComponent)"
            }
            if let mismatchReason = preparedPathArrayMismatchReason(for: cache, frameCount: frameCount) {
                return "Cache Incomplete (\(mismatchReason)) | \(url.lastPathComponent)"
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func loadPersistentCache(at url: URL) -> LoadedPersistentHostAnalysisCache? {
        do {
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxPersistentCacheReadBytes {
                NSLog("StabilizerFxPlug: ignoring oversized Host Analysis cache at \(url.path) (\(fileSize) bytes).")
                return nil
            }
            let data = try Data(contentsOf: url)
            let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
            guard supportedCacheSchemaVersions.contains(cache.schemaVersion) else {
                NSLog("StabilizerFxPlug: ignoring Host Analysis cache with unsupported schema \(cache.schemaVersion) at \(url.path).")
                return nil
            }
            if let maximumFrameCount = plausiblePersistedFrameCountLimit(for: cache),
               cache.frames.count > maximumFrameCount {
                NSLog("StabilizerFxPlug: ignoring oversized Host Analysis cache at \(url.path): \(cache.frames.count) frames exceeded expected limit \(maximumFrameCount).")
                return nil
            }
            let frames = cache.frames.compactMap { persistedFrame -> StabilizerAnalysisFrame? in
                let pixels = persistedFrame.pixels.map { [UInt8]($0) } ?? []
                if !pixels.isEmpty, pixels.count != cache.sampleWidth * cache.sampleHeight {
                    return nil
                }
                let fingerprint = persistedFrame.fingerprint ?? (pixels.isEmpty ? nil : StabilizerAnalysisFrame.fingerprint(for: pixels))
                guard let fingerprint else {
                    return nil
                }
                return StabilizerAnalysisFrame(
                    time: persistedFrame.time,
                    pixels: pixels,
                    sampleWidth: cache.sampleWidth,
                    sampleHeight: cache.sampleHeight,
                    blurAmount: persistedFrame.blurAmount,
                    fingerprint: fingerprint
                )
            }
            guard frames.count >= 3 else {
                NSLog("StabilizerFxPlug: ignoring Host Analysis cache with too few frames at \(url.path).")
                return nil
            }
            if let coverageReason = persistentFrameCoverageMismatchReason(for: cache, frameCount: frames.count) {
                NSLog("StabilizerFxPlug: ignoring incomplete Host Analysis cache at \(url.path): \(coverageReason).")
                return nil
            }
            guard let cacheIdentity = persistentCacheIdentity(for: cache, frames: frames) else {
                NSLog("StabilizerFxPlug: ignoring Host Analysis cache with incomplete fingerprints at \(url.path).")
                return nil
            }
            let prepared = try preparedAnalysis(from: cache, frames: frames)
            let lightweightCache = PersistedHostAnalysisCache(
                schemaVersion: cache.schemaVersion,
                createdAt: cache.createdAt,
                rangeStartSeconds: cache.rangeStartSeconds,
                rangeDurationSeconds: cache.rangeDurationSeconds,
                frameDurationSeconds: cache.frameDurationSeconds,
                sampleWidth: cache.sampleWidth,
                sampleHeight: cache.sampleHeight,
                frames: [],
                residuals: cache.residuals,
                rollMotion: cache.rollMotion,
                pathX: cache.pathX,
                pathY: cache.pathY,
                pathRoll: cache.pathRoll,
                footstepPathX: cache.footstepPathX,
                footstepPathY: cache.footstepPathY,
                footstepPathRoll: cache.footstepPathRoll,
                pathYaw: cache.pathYaw,
                pathPitch: cache.pathPitch,
                pathShearX: cache.pathShearX,
                pathShearY: cache.pathShearY,
                pathPerspectiveX: cache.pathPerspectiveX,
                pathPerspectiveY: cache.pathPerspectiveY,
                analysisConfidence: cache.analysisConfidence,
                warpConfidence: cache.warpConfidence,
                acceptedBlockCounts: cache.acceptedBlockCounts,
                totalBlockCounts: cache.totalBlockCounts,
                blurAmounts: cache.blurAmounts,
                searchRadiusHitCounts: cache.searchRadiusHitCounts,
                searchRadiusTotalCounts: cache.searchRadiusTotalCounts
            )
            return LoadedPersistentHostAnalysisCache(
                fileName: url.lastPathComponent,
                url: url,
                cache: lightweightCache,
                identity: cacheIdentity,
                frames: frames,
                preparedAnalysis: prepared
            )
        } catch {
            NSLog("StabilizerFxPlug: failed to load Host Analysis cache \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func updatePersistentCacheIndex(with entry: PersistedHostAnalysisIndexEntry) throws {
        guard let cacheIndexURL else {
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: stabilizerProjectCacheUnavailableMessage]
            )
        }
        var entries: [PersistedHostAnalysisIndexEntry] = []
        if FileManager.default.fileExists(atPath: cacheIndexURL.path) {
            do {
                let data = try Data(contentsOf: cacheIndexURL)
                let index = try JSONDecoder().decode(PersistedHostAnalysisIndex.self, from: data)
                if supportedCacheSchemaVersions.contains(index.schemaVersion) {
                    entries = index.entries
                }
            } catch {
                NSLog("StabilizerFxPlug: rebuilding Host Analysis cache index after load failure: \(error.localizedDescription)")
            }
        }

        entries.removeAll { existing in
            existing.cacheFileName == entry.cacheFileName
                || (
                    existing.frameCount == entry.frameCount
                    && existing.sampleWidth == entry.sampleWidth
                    && existing.sampleHeight == entry.sampleHeight
                    && existing.rangeStartSeconds == entry.rangeStartSeconds
                    && existing.rangeDurationSeconds == entry.rangeDurationSeconds
                    && existing.firstFingerprint == entry.firstFingerprint
                    && existing.middleFingerprint == entry.middleFingerprint
                    && existing.lastFingerprint == entry.lastFingerprint
                )
        }
        entries.insert(entry, at: 0)
        entries.sort { $0.createdAt > $1.createdAt }

        var retainedEntries: [PersistedHostAnalysisIndexEntry] = []
        let entriesBySampleSize = Dictionary(grouping: entries) { entry in
            "\(entry.sampleWidth)x\(entry.sampleHeight)"
        }
        for sampleEntries in entriesBySampleSize.values {
            let sortedSampleEntries = sampleEntries.sorted { $0.createdAt > $1.createdAt }
            retainedEntries.append(contentsOf: sortedSampleEntries.prefix(maxPersistentCacheEntriesPerSampleSize))
        }
        retainedEntries.sort { $0.createdAt > $1.createdAt }
        let index = PersistedHostAnalysisIndex(schemaVersion: cacheSchemaVersion, entries: retainedEntries)
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheIndexURL, options: .atomic)
    }

    private static func indexEntry(for cache: PersistedHostAnalysisCache, fileName: String, frames: [StabilizerAnalysisFrame]) -> PersistedHostAnalysisIndexEntry? {
        guard let fingerprints = persistentCacheFingerprints(for: frames) else {
            return nil
        }
        return PersistedHostAnalysisIndexEntry(
            cacheFileName: fileName,
            createdAt: cache.createdAt,
            rangeStartSeconds: cache.rangeStartSeconds,
            rangeDurationSeconds: cache.rangeDurationSeconds,
            frameDurationSeconds: cache.frameDurationSeconds,
            sampleWidth: cache.sampleWidth,
            sampleHeight: cache.sampleHeight,
            frameCount: frames.count,
            firstFingerprint: fingerprints.first,
            middleFingerprint: fingerprints.middle,
            lastFingerprint: fingerprints.last,
            cacheIdentity: persistentCacheIdentity(for: cache, frames: frames)
        )
    }

    private static func persistentCacheFileName(for cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) -> String {
        let fingerprints = persistentCacheFingerprints(for: frames)
        let first = fingerprints?.first.prefix(12) ?? "unknown"
        let middle = fingerprints?.middle.prefix(12) ?? "unknown"
        let last = fingerprints?.last.prefix(12) ?? "unknown"
        return "host-analysis-v2-r\(timeKey(cache.rangeStartSeconds))-d\(timeKey(cache.rangeDurationSeconds))-s\(cache.sampleWidth)x\(cache.sampleHeight)-n\(frames.count)-\(first)-\(middle)-\(last).json"
    }

    private static func persistentCacheIdentity(for cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) -> String? {
        guard let fingerprints = persistentCacheFingerprints(for: frames) else {
            return nil
        }
        return [
            "\(cache.schemaVersion)",
            "\(timeKey(cache.rangeStartSeconds))",
            "\(timeKey(cache.rangeDurationSeconds))",
            "\(timeKey(cache.frameDurationSeconds))",
            "\(cache.sampleWidth)",
            "\(cache.sampleHeight)",
            "\(frames.count)",
            fingerprints.first,
            fingerprints.middle,
            fingerprints.last
        ].joined(separator: ":")
    }

    private static func savedRenderTimeOffset(for cacheIdentity: String) -> Double? {
        guard let renderTimeOffsetURL else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: renderTimeOffsetURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: renderTimeOffsetURL)
            let index = try JSONDecoder().decode(PersistedRenderTimeOffsetIndex.self, from: data)
            guard index.version == cacheSchemaVersion else {
                return nil
            }
            let entry = index.entries.first { $0.cacheIdentity == cacheIdentity }
            guard let offset = entry?.offsetSeconds, offset.isFinite else {
                return nil
            }
            return offset
        } catch {
            NSLog("StabilizerFxPlug: failed to load render-time offset map: \(error.localizedDescription)")
            return nil
        }
    }

    private static func saveRenderTimeOffset(cacheIdentity: String, offsetSeconds: Double, renderSeconds: Double, analysisSeconds: Double) {
        guard offsetSeconds.isFinite,
              renderSeconds.isFinite,
              analysisSeconds.isFinite,
              let cacheDirectoryURL,
              let renderTimeOffsetURL
        else {
            return
        }
        var entries: [PersistedRenderTimeOffsetEntry] = []
        if FileManager.default.fileExists(atPath: renderTimeOffsetURL.path) {
            do {
                let data = try Data(contentsOf: renderTimeOffsetURL)
                let index = try JSONDecoder().decode(PersistedRenderTimeOffsetIndex.self, from: data)
                if index.version == cacheSchemaVersion {
                    entries = index.entries
                }
            } catch {
                NSLog("StabilizerFxPlug: rebuilding render-time offset map after load failure: \(error.localizedDescription)")
            }
        }
        let entry = PersistedRenderTimeOffsetEntry(
            cacheIdentity: cacheIdentity,
            offsetSeconds: offsetSeconds,
            savedAt: Date().timeIntervalSince1970,
            renderSeconds: renderSeconds,
            analysisSeconds: analysisSeconds
        )
        entries.removeAll { $0.cacheIdentity == cacheIdentity }
        entries.insert(entry, at: 0)
        entries.sort { $0.savedAt > $1.savedAt }
        let index = PersistedRenderTimeOffsetIndex(version: cacheSchemaVersion, entries: Array(entries.prefix(32)))
        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: renderTimeOffsetURL, options: .atomic)
        } catch {
            NSLog("StabilizerFxPlug: failed to save render-time offset map: \(error.localizedDescription)")
        }
    }

    private static func persistentCacheFingerprints(for frames: [StabilizerAnalysisFrame]) -> (first: String, middle: String, last: String)? {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last
        else {
            return nil
        }
        let middleFrame = frames[frames.count / 2]
        return (
            first: frameFingerprint(firstFrame),
            middle: frameFingerprint(middleFrame),
            last: frameFingerprint(lastFrame)
        )
    }

    private static func frameFingerprint(_ frame: StabilizerAnalysisFrame) -> String {
        frame.fingerprint
    }

    private static var cacheDirectoryURLs: [URL] {
        projectCacheDirectoryLock.lock()
        let url = projectBundleCacheDirectoryURL
        projectCacheDirectoryLock.unlock()
        return url.map { [$0] } ?? []
    }

    private static var cacheDirectoryURL: URL? {
        cacheDirectoryURLs.first
    }

    private static var cacheURL: URL? {
        cacheDirectoryURL.map(cacheURL(in:))
    }

    private static var cacheIndexURL: URL? {
        cacheDirectoryURL.map(cacheIndexURL(in:))
    }

    private static var renderTimeOffsetURL: URL? {
        cacheDirectoryURL.map(renderTimeOffsetURL(in:))
    }

    private static var cacheStorageDirectoryURL: URL? {
        cacheDirectoryURL.map(cacheStorageDirectoryURL(in:))
    }

    private static func analysisScratchDirectoryURL() -> URL? {
        cacheDirectoryURL.map(analysisScratchDirectoryURL(in:))
    }

    private static func cacheURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private static func cacheIndexURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheIndexFileName, isDirectory: false)
    }

    private static func renderTimeOffsetURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(renderTimeOffsetFileName, isDirectory: false)
    }

    private static func cacheStorageDirectoryURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheStorageDirectoryName, isDirectory: true)
    }

    private static func analysisScratchDirectoryURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(analysisScratchDirectoryName, isDirectory: true)
    }

    private static func meanAbsoluteDifference(_ left: [UInt8], _ right: [UInt8]) -> Float {
        let count = min(left.count, right.count)
        guard count > 0, left.count == right.count else {
            return Float.greatestFiniteMagnitude
        }
        var total = 0
        for index in 0..<count {
            total += abs(Int(left[index]) - Int(right[index]))
        }
        return Float(total) / Float(count)
    }
}
