import AppKit
import CoreMedia
import Foundation
import Metal
import simd

private enum ParameterID: UInt32 {
    case strength = 1
    case xStrength = 7
    case rotationStrength = 8
    case panSmoothSeconds = 9
    case debugOverlay = 10
    case startHostAnalysis = 14
    case hostAnalysisStatus = 15
    case stabilizerInfo = 16
    case clearHostAnalysisCache = 17
    case yStrength = 18
    case sampleScale = 19
    case renderRevision = 20
    case walkingBobWindowSeconds = 22
    case panStabilizationStrength = 23
    case walkingBobStrength = 26
    case edgeDisplayMode = 27
    case farFieldWarpStrength = 28
    case strideWobbleXStrength = 29
    case strideWobbleYStrength = 30
    case strideWobbleRotationStrength = 31
}

private let stabilizerFxPlugVersion = "0.2.112"

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
        StabilizerSampleScale(rawValue: rawValue) ?? .original
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
    var walkingBobWindowSeconds: Double
    var edgeDisplayMode: Int32
    var debugOverlay: Bool
    var sampleScale: Int32
    var hostAnalysisFrameCount: Int32
    var hostAnalysisRevision: UInt64
    var renderRevision: Double
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

private enum StabilizerOriginalMediaPolicy {
    private static let proxyScaleTolerance = 0.05

    static func proxyRejectionReason(for frame: FxImageTile) -> String? {
        guard let frameInfo = frameInfo(for: frame) else {
            return "Host Analysis received a source frame without pixel transform; original media could not be confirmed."
        }
        let scaleX = frameInfo.pixelScaleX
        let scaleY = frameInfo.pixelScaleY
        guard scaleX.isFinite, scaleY.isFinite else {
            return "Host Analysis received a source frame with invalid pixel transform; original media could not be confirmed."
        }
        guard max(scaleX, scaleY) <= 1.0 + proxyScaleTolerance else {
            return String(
                format: "Host Analysis received proxy-scaled media (pixel transform %.2fx, %.2fx). Use original media and rerun Host Analysis.",
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
        store.loadPersistentCache()
        return store
    }()
    private static let stabilizerInfoViewLock = NSLock()
    private static let stabilizerInfoViews = NSHashTable<StabilizerInfoScrollView>.weakObjects()
    private static var latestStabilizerInfo = "No Analysis"

    private let apiManager: PROAPIAccessing
    private let statusLock = NSLock()
    private var lastPublishedStatus = ""
    private var lastPublishedInfo = ""
    private var lastPublishedRenderRevision: UInt64?
    private var hostAnalysisStore: StabilizerHostAnalysisStore {
        Self.sharedHostAnalysisStore
    }

    required init?(apiManager: PROAPIAccessing) {
        self.apiManager = apiManager
        super.init()
        _ = Self.sharedHostAnalysisStore
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
            defaultValue: 1.0,
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
            defaultValue: 0.35,
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
            defaultValue: 0.75,
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
            parameterMin: 0.1,
            parameterMax: 120.0,
            sliderMin: 0.1,
            sliderMax: 30.0,
            delta: 0.25,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Walking Bob Window",
            parameterID: ParameterID.walkingBobWindowSeconds.rawValue,
            defaultValue: 1.5,
            parameterMin: 0.1,
            parameterMax: 30.0,
            sliderMin: 0.1,
            sliderMax: 6.0,
            delta: 0.05,
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
        paramAPI.addPopupMenu(
            withName: "Sample Size",
            parameterID: ParameterID.sampleScale.rawValue,
            defaultValue: UInt32(StabilizerSampleScale.original.rawValue),
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
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DONT_SAVE | kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_USE_FULL_VIEW_WIDTH)
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
        return view
    }

    func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?, at renderTime: CMTime, quality qualityLevel: UInt) throws {
        let paramAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as! FxParameterRetrievalAPI_v6

        var state = StabilizerPluginState(
            strength: 1.0,
            microJitterXStrength: 1.0,
            microJitterYStrength: 1.0,
            microJitterRotationStrength: 1.0,
            strideWobbleXStrength: 0.65,
            strideWobbleYStrength: 0.35,
            strideWobbleRotationStrength: 0.75,
            panStabilizationStrength: 1.0,
            walkingBobStrength: 0.75,
            farFieldWarpStrength: 1.0,
            panSmoothSeconds: 6.0,
            walkingBobWindowSeconds: 1.5,
            edgeDisplayMode: StabilizerEdgeDisplayMode.stretchEdges.rawValue,
            debugOverlay: false,
            sampleScale: StabilizerSampleScale.original.rawValue,
            hostAnalysisFrameCount: 0,
            hostAnalysisRevision: 0,
            renderRevision: 0.0
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
        paramAPI.getFloatValue(&state.walkingBobWindowSeconds, fromParameter: ParameterID.walkingBobWindowSeconds.rawValue, at: renderTime)
        paramAPI.getIntValue(&state.edgeDisplayMode, fromParameter: ParameterID.edgeDisplayMode.rawValue, at: renderTime)
        var debugOverlay = ObjCBool(state.debugOverlay)
        paramAPI.getBoolValue(&debugOverlay, fromParameter: ParameterID.debugOverlay.rawValue, at: renderTime)
        state.debugOverlay = debugOverlay.boolValue
        paramAPI.getIntValue(&state.sampleScale, fromParameter: ParameterID.sampleScale.rawValue, at: renderTime)
        let cappedHostFrameCount = min(hostAnalysisStore.frameCount, Int(Int32.max))
        state.hostAnalysisFrameCount = Int32(cappedHostFrameCount)
        state.hostAnalysisRevision = hostAnalysisStore.revision
        paramAPI.getFloatValue(&state.renderRevision, fromParameter: ParameterID.renderRevision.rawValue, at: renderTime)
        publishHostAnalysisStatus()
        publishStabilizerInfo(state: state)
        publishRenderRevision(state.hostAnalysisRevision)

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
    }

    @objc(startHostAnalysis)
    func startHostAnalysis() {
        publishHostAnalysisStatus(force: true, statusOverride: "Start Pressed")
        publishStabilizerInfo(force: true)
        let shouldSkipPersistentCacheReload = hostAnalysisStore.hasRejectedPersistentCache
        hostAnalysisStore.reset()
        let loadedPersistentCache = shouldSkipPersistentCacheReload ? false : hostAnalysisStore.loadPersistentCache()
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.revision, force: true)
        if !loadedPersistentCache {
            requestHostAnalysisIfNeeded(force: true)
        }
    }

    @objc(clearHostAnalysisCache)
    func clearHostAnalysisCache() {
        hostAnalysisStore.clearPersistentCache()
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.revision, force: true)
    }

    private func requestHostAnalysisIfNeeded(force: Bool = false) {
        if hostAnalysisStore.hasCompletedAnalysis {
            return
        }
        guard force || !hostAnalysisStore.hasCompletedAnalysis else {
            return
        }
        guard let analysisAPI = apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            NSLog("StabilizerFxPlug: FxAnalysisAPI is unavailable; Host Analysis cannot start.")
            hostAnalysisStore.markStartFailed(reason: "FxAnalysisAPI unavailable")
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.revision, force: true)
            return
        }
        let analysisState = analysisAPI.analysisStateForEffect()
        let canStart = analysisState == kFxAnalysisState_NotAnalyzing
            || analysisState == kFxAnalysisState_AnalysisInterrupted
            || (force && analysisState == kFxAnalysisState_AnalysisCompleted)
        guard canStart else {
            let reason = Self.analysisStateDescription(analysisState)
            if force {
                hostAnalysisStore.markStartFailed(reason: "Host state \(reason)")
            }
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.revision, force: true)
            if force {
                NSLog("StabilizerFxPlug: Host Analysis is already requested or running.")
            }
            return
        }
        do {
            try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_GPU)
            NSLog("StabilizerFxPlug: requested GPU Host Analysis for the effect clip.")
            hostAnalysisStore.markRequested()
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.revision, force: true)
        } catch {
            NSLog("StabilizerFxPlug: Host Analysis request failed: \(error.localizedDescription)")
            hostAnalysisStore.markStartFailed(reason: error.localizedDescription)
            publishHostAnalysisStatus(force: true)
            publishStabilizerInfo(force: true)
            publishRenderRevision(hostAnalysisStore.revision, force: true)
        }
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

    private func publishHostAnalysisStatus(force: Bool = false, statusOverride: String? = nil) {
        let status = statusOverride ?? hostAnalysisStore.statusText
        statusLock.lock()
        let shouldPublish = force || status != lastPublishedStatus
        if shouldPublish {
            lastPublishedStatus = status
        }
        statusLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if !settingAPI.setStringParameterValue(status, toParameter: ParameterID.hostAnalysisStatus.rawValue) {
            NSLog("StabilizerFxPlug: failed to update Host Analysis Status parameter.")
        }
    }

    private func publishStabilizerInfo(force: Bool = false, state: StabilizerPluginState? = nil) {
        let info = Self.stabilizerInfoText(analysisInfo: hostAnalysisStore.infoText, state: state)
        statusLock.lock()
        let shouldPublish = force || info != lastPublishedInfo
        if shouldPublish {
            lastPublishedInfo = info
        }
        statusLock.unlock()
        guard shouldPublish else {
            return
        }
        Self.updateStabilizerInfoViews(info)
        guard let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if !settingAPI.setStringParameterValue(info, toParameter: ParameterID.stabilizerInfo.rawValue) {
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
            lines.append(String(
                format: "Footstep jitter | X %.2f Y %.2f R %.2f",
                state.microJitterXStrength,
                state.microJitterYStrength,
                state.microJitterRotationStrength
            ))
            lines.append(String(
                format: "Stride wobble | X %.2f Y %.2f R %.2f",
                state.strideWobbleXStrength,
                state.strideWobbleYStrength,
                state.strideWobbleRotationStrength
            ))
            lines.append(String(
                format: "Walking Bob <= %.2fs | removal %.2f",
                state.walkingBobWindowSeconds,
                state.walkingBobStrength
            ))
            lines.append(String(
                format: "Turn Smoothing %.2f-%.2fs | strength %.2f",
                state.walkingBobWindowSeconds,
                state.panSmoothSeconds,
                state.panStabilizationStrength
            ))
            lines.append(String(
                format: "Far-field Warp | strength %.2f",
                state.farFieldWarpStrength
            ))
        }
        if analysisInfo != "No Analysis" {
            lines.append(analysisInfo)
        }
        return lines.joined(separator: "\n")
    }

    private func publishRenderRevision(_ revision: UInt64, force: Bool = false) {
        statusLock.lock()
        let shouldPublish = force || lastPublishedRenderRevision != revision
        if shouldPublish {
            lastPublishedRenderRevision = revision
        }
        statusLock.unlock()
        guard shouldPublish,
              let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
        else {
            return
        }
        if !settingAPI.setFloatValue(Double(revision), toParameter: ParameterID.renderRevision.rawValue, at: .zero) {
            NSLog("StabilizerFxPlug: failed to update Render Revision parameter.")
        }
    }

    private func abandonActiveAnalysisAfterFailure() {
        publishRenderRevision(hostAnalysisStore.revision, force: true)
    }

    private func requestedSampleScalePercent(at time: CMTime) -> Double {
        var sampleScale = StabilizerSampleScale.original.rawValue
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
            format: "Ready (%d) | turn %.1fs smooth %d@%.2fs | X %.1f Y %.1f R %.2f | raw X %.1f Y %.1f R %.2f | smooth dX %.1f dY %.1f dR %.2f | foot q %.2f eff X %.2f Y %.2f R %.2f | stride q %.2f eff X %.2f Y %.2f R %.2f | bob q %.2f warp q %.2f shear %.4f %.4f yp %.4f %.4f persp %.4f %.4f blocks %d/%d | x turn %.1f stride %.1f | y foot %.1f stride %.1f bob %.1f",
            frameCount,
            panSmoothSeconds,
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
            autoTransform.microConfidence,
            autoTransform.effectiveMicroJitterStrength.x,
            autoTransform.effectiveMicroJitterStrength.y,
            autoTransform.effectiveMicroJitterStrength.z,
            autoTransform.strideConfidence,
            autoTransform.effectiveStrideWobbleStrength.x,
            autoTransform.effectiveStrideWobbleStrength.y,
            autoTransform.effectiveStrideWobbleStrength.z,
            autoTransform.bobConfidence,
            autoTransform.warpConfidence,
            autoTransform.shear.x,
            autoTransform.shear.y,
            autoTransform.yawPitchProxy.x,
            autoTransform.yawPitchProxy.y,
            autoTransform.perspective.x,
            autoTransform.perspective.y,
            autoTransform.acceptedBlockCount,
            autoTransform.totalBlockCount,
            autoTransform.macroPixelOffset.x,
            autoTransform.strideWobblePixelOffset.x,
            autoTransform.microPixelOffset.y,
            autoTransform.strideWobblePixelOffset.y,
            autoTransform.walkingBobPixelOffset.y
        )
        publishHostAnalysisStatus(statusOverride: status)
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
        if transformEnabled,
           let preparedAnalysis = hostAnalysisStore.preparedAnalysisForRender(validating: sourceImages[0], at: renderTime) {
            let analysisRenderTime = hostAnalysisStore.analysisRenderTime(for: renderTime, preparedAnalysis: preparedAnalysis)
            autoTransform = AutoStabilizationEstimator.estimate(
                preparedAnalysis: preparedAnalysis,
                renderTime: analysisRenderTime,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: state.panSmoothSeconds,
                walkingBobWindowSeconds: state.walkingBobWindowSeconds,
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
        let diagnosticScaleX = max(1.0, Float(outputWidth) * 0.05)
        let diagnosticScaleY = max(1.0, Float(outputHeight) * 0.05)
        let temporalSmoothingScale = max(1.0, min(Float(outputWidth), Float(outputHeight)) * 0.03)
        let diagnostic = vector_float4(
            min(1.0, abs(autoTransform.pixelOffset.x) / diagnosticScaleX),
            min(1.0, abs(autoTransform.pixelOffset.y) / diagnosticScaleY),
            min(1.0, abs(autoTransform.rotationDegrees) / 5.0),
            0.0
        )
        let diagnostic2 = vector_float4(
            min(1.0, simd_length(vector_float2(autoTransform.macroPixelOffset.x / diagnosticScaleX, autoTransform.macroPixelOffset.y / diagnosticScaleY))),
            min(1.0, max(
                simd_length(vector_float2(
                    (autoTransform.microPixelOffset.x + autoTransform.strideWobblePixelOffset.x) / diagnosticScaleX,
                    (autoTransform.microPixelOffset.y + autoTransform.strideWobblePixelOffset.y) / diagnosticScaleY
                )),
                abs(autoTransform.rotationDegrees) / 5.0
            )),
            min(1.0, abs(autoTransform.walkingBobPixelOffset.y) / diagnosticScaleY),
            min(1.0, simd_length(autoTransform.temporalSmoothingPixelDelta) / temporalSmoothingScale)
        )
        let diagnostic3 = vector_float4(
            min(1.0, autoTransform.microConfidence),
            min(1.0, autoTransform.strideConfidence),
            min(1.0, autoTransform.bobConfidence),
            min(1.0, autoTransform.warpConfidence)
        )

        var transform = StabilizerTransformUniforms(
            pixelOffset: autoTransform.pixelOffset * masterStrength,
            rotationRadians: autoTransform.rotationDegrees * .pi / 180.0 * masterStrength,
            strength: 1.0,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            diagnostic: diagnostic,
            diagnostic2: diagnostic2,
            diagnostic3: diagnostic3,
            shear: autoTransform.shear * masterStrength,
            perspective: (autoTransform.perspective + autoTransform.yawPitchProxy) * masterStrength,
            edgeMode: Float(state.edgeDisplayMode),
            debugOverlay: state.debugOverlay && transformEnabled ? 1.0 : 0.0
        )
        if state.debugOverlay && transformEnabled {
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
        let analysisStore = hostAnalysisStore
        analysisStore.begin(
            range: analysisRange,
            frameDuration: frameDuration,
            requestedSampleScalePercent: requestedSampleScalePercent(at: analysisRange.start)
        )
        NSLog(
            "StabilizerFxPlug: setup Host Analysis range %.3f+%.3f seconds, frameDuration %.6f seconds.",
            CMTimeGetSeconds(analysisRange.start),
            CMTimeGetSeconds(analysisRange.duration),
            CMTimeGetSeconds(frameDuration)
        )
        publishHostAnalysisStatus(force: true, statusOverride: analysisStore.statusText)
    }

    func analyzeFrame(_ frame: FxImageTile!, at frameTime: CMTime) throws {
        let analysisStore = hostAnalysisStore
        guard let frame else {
            abandonActiveAnalysisAfterFailure()
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "StabilizerFxPlug host analysis supplied no frame."]
            )
        }
        if let rejectionReason = StabilizerOriginalMediaPolicy.proxyRejectionReason(for: frame) {
            analysisStore.rejectProxyAnalysis(reason: rejectionReason)
            publishHostAnalysisStatus(force: true, statusOverride: analysisStore.statusText)
            publishStabilizerInfo(force: true)
            abandonActiveAnalysisAfterFailure()
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: rejectionReason]
            )
        }
        guard let frameInfo = StabilizerOriginalMediaPolicy.frameInfo(for: frame) else {
            let reason = "Host Analysis could not read the original clip size for Sample Size."
            analysisStore.rejectProxyAnalysis(reason: reason)
            publishHostAnalysisStatus(force: true, statusOverride: analysisStore.statusText)
            publishStabilizerInfo(force: true)
            abandonActiveAnalysisAfterFailure()
            throw NSError(
                domain: "com.justadev.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: reason]
            )
        }
        let sampleSize = analysisStore.sampleSize(for: frameInfo)
        do {
            let analysisFrame = try AutoStabilizationEstimator.analysisFrame(
                from: frame,
                at: frameTime,
                sampleWidth: sampleSize.width,
                sampleHeight: sampleSize.height
            )
            try analysisStore.append(analysisFrame, sourceInfo: frameInfo)
            if analysisStore.frameCount == 1 {
                NSLog(
                    "StabilizerFxPlug: received first Host Analysis frame at %.3f seconds, sample %dx%d.",
                    CMTimeGetSeconds(frameTime),
                    analysisFrame.sampleWidth,
                    analysisFrame.sampleHeight
                )
            }
        } catch {
            abandonActiveAnalysisAfterFailure()
            throw error
        }
    }

    func cleanupAnalysis() throws {
        let analysisStore = hostAnalysisStore
        try analysisStore.finish()
        publishHostAnalysisStatus(force: true)
        publishStabilizerInfo(force: true)
        publishRenderRevision(hostAnalysisStore.revision, force: true)
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
    case analyzing
    case cacheLoaded
    case ready
    case cacheRejected
    case cacheCleared
    case proxyRejected
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
}

private struct LoadedPersistentHostAnalysisCache {
    let fileName: String
    let url: URL
    let cache: PersistedHostAnalysisCache
    let frames: [StabilizerAnalysisFrame]
    let preparedAnalysis: StabilizerPreparedAnalysis
}

private final class StabilizerHostAnalysisStore {
    private static let cacheSchemaVersion = 12
    private static let supportedCacheSchemaVersions: Set<Int> = [12]
    private static let persistentCacheGenerationLock = NSLock()
    private static var persistentCacheGeneration: UInt64 = 0
    private static let maxPersistentCacheEntries = 8
    private static let maxPersistentCacheReadBytes = 629_145_600
    private static let cacheValidationMeanDifferenceThreshold: Float = 18.0
    private static let cacheValidationTimeToleranceSeconds = 0.1
    private static let cacheDirectoryName = "StabilizerFxPlug"
    private static let cacheFileName = "host-analysis-v2.json"
    private static let cacheIndexFileName = "host-analysis-index-v2.json"
    private static let cacheStorageDirectoryName = "caches"
    private static let analysisScratchDirectoryName = "analysis-work"
    private static let legacyCacheBundleIdentifiers = [
        "com.justadev.CommandPostEmDash.StabilizerFxPlug.Plugin",
        "com.justadev.CommandPostEmDash.StabilizerFxPlug"
    ]

    private let lock = NSLock()
    private var framesByTimeKey: [Int64: StabilizerAnalysisFrame] = [:]
    private var streamingAnalysisBuilder: StreamingStabilizationAnalysisBuilder?
    private var preparedAnalysis: StabilizerPreparedAnalysis?
    private var persistentCacheCandidates: [URL] = []
    private var activePersistentCacheFileName: String?
    private var rejectedPersistentCacheFileNames = Set<String>()
    private var activeRange: CMTimeRange = .invalid
    private var activeFrameDuration: CMTime = .invalid
    private var activeRequestedSampleScalePercent = StabilizerSampleScale.original.percent
    private var renderToAnalysisOffsetSeconds: Double?
    private var renderToAnalysisOffsetProbeAttempted = false
    private var finished = false
    private var validationState: HostAnalysisValidationState = .notRequired
    private var status: HostAnalysisStatus = .needsAnalysis
    private var analysisRevision: UInt64 = 0
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

    var infoText: String {
        lock.lock()
        defer { lock.unlock() }
        return analysisInfoText
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
        case .cacheCleared:
            return "Cache Cleared"
        case .proxyRejected:
            return "Proxy Media Rejected - Use Original Media"
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
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
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

    func markStartFailed(reason: String) {
        lock.lock()
        if preparedAnalysis == nil {
            status = .needsAnalysis
            analysisInfoText = "Host Analysis start failed: \(reason)"
            bumpRevisionLocked()
        }
        lock.unlock()
    }

    func reset(removePersistentCache shouldRemovePersistentCache: Bool = false) {
        removeLegacyAnalysisScratchDirectory()
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        streamingAnalysisBuilder = nil
        preparedAnalysis = nil
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.original.percent
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
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: false)
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.original.percent
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
        activeRange = .invalid
        activeFrameDuration = .invalid
        activeRequestedSampleScalePercent = StabilizerSampleScale.original.percent
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
            markAnalysisCompleted()
            persistIfCompleted()
            releaseRetainedAnalysisPixels()
            removeLegacyAnalysisScratchDirectory()
        } catch {
            lock.lock()
            preparedAnalysis = nil
            streamingAnalysisBuilder = nil
            finished = false
            status = .needsAnalysis
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
        framesByTimeKey = Dictionary(uniqueKeysWithValues: snapshot.frames.map { (Self.timeKey($0.time), $0) })
        streamingAnalysisBuilder = nil
        preparedAnalysis = snapshot.preparedAnalysis
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        rejectedPersistentCacheFileNames.removeAll(keepingCapacity: true)
        activeRange = snapshot.activeRange
        activeFrameDuration = snapshot.activeFrameDuration
        activeRequestedSampleScalePercent = snapshot.activeRequestedSampleScalePercent
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
        finished = snapshot.finished
        validationState = snapshot.validationState
        status = snapshot.status
        latestSourceFrameInfo = snapshot.latestSourceFrameInfo
        latestSampleSize = snapshot.latestSampleSize
        analysisInfoText = snapshot.analysisInfoText
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: installed completed Host Analysis session with \(snapshot.frames.count) frame(s) into shared render store.")
    }

    func preparedAnalysisForRender(validating sourceImage: FxImageTile, at renderTime: CMTime) -> StabilizerPreparedAnalysis? {
        while true {
            guard let analysis = preparedAnalysisSnapshot() else {
                if shouldReloadPersistentCacheForRender(), loadPersistentCache() {
                    continue
                }
                guard activateNextPersistentCache(afterRejecting: nil) else {
                    return nil
                }
                continue
            }

            let state = currentValidationState()
            if state == .validated || state == .notRequired {
                markReadyAfterOriginalMediaReturnedIfNeeded()
                updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                return analysis
            }
            if state == .rejected {
                return nil
            }

            if let rejectionReason = StabilizerOriginalMediaPolicy.proxyRejectionReason(for: sourceImage) {
                markReadyAfterOriginalMediaReturnedIfNeeded()
                updateRenderTimeMappingIfNeeded(for: analysis, validating: sourceImage, at: renderTime)
                NSLog("StabilizerFxPlug: using loaded Host Analysis cache for render before original-media validation because current playback frame is proxy media: \(rejectionReason)")
                return analysis
            }

            if let rejectionReason = persistentCacheRejectionReason(for: analysis, validating: sourceImage, at: renderTime) {
                guard activateNextPersistentCache(afterRejecting: rejectionReason) else {
                    rejectPersistentCache(reason: rejectionReason)
                    return nil
                }
                continue
            }

            lock.lock()
            if validationState == .pending {
                validationState = .validated
                status = .ready
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
    func loadPersistentCache() -> Bool {
        defer {
            markCurrentPersistentCacheGenerationObserved()
        }
        var candidateURLs = filteredPersistentCacheCandidateURLs()
        while !candidateURLs.isEmpty {
            let activeURL = candidateURLs.removeFirst()
            guard let activeCandidate = Self.loadPersistentCache(at: activeURL) else {
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
        return false
    }

    private func shouldReloadPersistentCacheForRender() -> Bool {
        let generation = Self.currentPersistentCacheGeneration()
        let signature = Self.currentPersistentCacheSignature()
        lock.lock()
        let shouldReload = (preparedAnalysis == nil
            || observedPersistentCacheSignature != signature
            || observedPersistentCacheGeneration < generation)
            && persistentCacheCandidates.isEmpty
            && status != .analyzing
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

        guard snapshot.frames.count >= 3, let prepared = snapshot.prepared else {
            return
        }
        let firstFrameTime = snapshot.frames.first?.time ?? 0.0
        let lastFrameTime = snapshot.frames.last?.time ?? firstFrameTime
        let sampleWidth = snapshot.frames.first?.sampleWidth ?? AutoStabilizationEstimator.defaultSampleWidth
        let sampleHeight = snapshot.frames.first?.sampleHeight ?? AutoStabilizationEstimator.defaultSampleHeight
        let frameDurationSeconds = Self.validFrameDurationSeconds(snapshot.frameDuration, frames: snapshot.frames)
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
            frames: snapshot.frames.map {
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
            blurAmounts: prepared.blurAmounts
        )

        do {
            try FileManager.default.createDirectory(at: Self.cacheDirectoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.cacheStorageDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            let cacheFileName = Self.persistentCacheFileName(for: cache, frames: snapshot.frames)
            let cacheURL = Self.cacheStorageDirectoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
            try data.write(to: cacheURL, options: .atomic)
            try data.write(to: Self.cacheURL, options: .atomic)
            if let indexEntry = Self.indexEntry(for: cache, fileName: cacheFileName, frames: snapshot.frames) {
                try Self.updatePersistentCacheIndex(with: indexEntry)
            }
            Self.bumpPersistentCacheGeneration()
            NSLog("StabilizerFxPlug: saved Host Analysis cache with \(snapshot.frames.count) frames to \(cacheURL.path).")
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
                blurAmounts: analysis.blurAmounts
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

    private func completedAnalysisSnapshot() -> (
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
        analysisInfoText: String
    ) {
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
            analysisInfoText: analysisInfoText
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
        if status == .proxyRejected, preparedAnalysis != nil {
            status = .ready
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
        persistentCacheCandidates.removeAll(keepingCapacity: false)
        activePersistentCacheFileName = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        validationState = .rejected
        status = .cacheRejected
        bumpRevisionLocked()
        lock.unlock()
        NSLog("StabilizerFxPlug: rejected persisted Host Analysis cache \(rejectedFileName ?? "<unknown>"): \(reason).")
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
        lock.unlock()
    }

    private func matchedAnalysisFrame(for currentFrame: StabilizerAnalysisFrame, in frames: [StabilizerAnalysisFrame]) -> StabilizerAnalysisFrame? {
        if let fingerprintMatch = frames.first(where: { $0.fingerprint == currentFrame.fingerprint }) {
            return fingerprintMatch
        }
        guard let closestFrame = frames.min(by: { abs($0.time - currentFrame.time) < abs($1.time - currentFrame.time) }) else {
            return nil
        }
        if closestFrame.pixels.isEmpty {
            let timeDifference = abs(closestFrame.time - currentFrame.time)
            guard timeDifference <= Self.cacheValidationTimeToleranceSeconds else {
                return nil
            }
            return closestFrame
        }
        guard Self.meanAbsoluteDifference(currentFrame.pixels, closestFrame.pixels) <= Self.cacheValidationMeanDifferenceThreshold else {
            return nil
        }
        return closestFrame
    }

    private func activateNextPersistentCache(afterRejecting rejectionReason: String?) -> Bool {
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
        framesByTimeKey = Dictionary(uniqueKeysWithValues: loadedCache.frames.map { (Self.timeKey($0.time), $0) })
        preparedAnalysis = loadedCache.preparedAnalysis
        activePersistentCacheFileName = loadedCache.fileName
        activeRange = CMTimeRange(
            start: CMTime(seconds: loadedCache.cache.rangeStartSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: loadedCache.cache.rangeDurationSeconds, preferredTimescale: 600)
        )
        activeFrameDuration = CMTime(seconds: loadedCache.cache.frameDurationSeconds, preferredTimescale: 600)
        renderToAnalysisOffsetSeconds = nil
        renderToAnalysisOffsetProbeAttempted = false
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
    }

    private func removePersistentCache(logFailures: Bool) {
        let urls = Self.cacheDirectoryURLs.flatMap { directoryURL in
            [
                Self.cacheURL(in: directoryURL),
                Self.cacheIndexURL(in: directoryURL),
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

    private static func timeKey(_ seconds: Double) -> Int64 {
        Int64((seconds * 600.0).rounded())
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
        let floatArrays = [
            cache.residuals,
            cache.rollMotion,
            cache.pathX,
            cache.pathY,
            cache.pathRoll,
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
            cache.totalBlockCounts
        ]
        if floatArrays.allSatisfy({ $0?.count == frames.count }),
           countArrays.allSatisfy({ $0?.count == frames.count }),
           let residuals = cache.residuals,
           let rollMotion = cache.rollMotion,
           let pathX = cache.pathX,
           let pathY = cache.pathY,
           let pathRoll = cache.pathRoll,
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
           let blurAmounts = cache.blurAmounts {
            return StabilizerPreparedAnalysis(
                frames: frames.sorted { $0.time < $1.time },
                residuals: residuals,
                rollMotion: rollMotion,
                pathX: pathX,
                pathY: pathY,
                pathRoll: pathRoll,
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
                blurAmounts: blurAmounts
            )
        }
        throw NSError(
            domain: "com.justadev.StabilizerFxPlug",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: "persisted Host Analysis cache was missing prepared Metal motion paths"]
        )
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
            guard persistentCacheIdentity(for: cache, frames: frames) != nil else {
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
                blurAmounts: cache.blurAmounts
            )
            return LoadedPersistentHostAnalysisCache(
                fileName: url.lastPathComponent,
                url: url,
                cache: lightweightCache,
                frames: frames,
                preparedAnalysis: prepared
            )
        } catch {
            NSLog("StabilizerFxPlug: failed to load Host Analysis cache \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func updatePersistentCacheIndex(with entry: PersistedHostAnalysisIndexEntry) throws {
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

        let retainedEntries = Array(entries.prefix(maxPersistentCacheEntries))
        let prunedEntries = entries.dropFirst(maxPersistentCacheEntries)
        let index = PersistedHostAnalysisIndex(schemaVersion: cacheSchemaVersion, entries: retainedEntries)
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheIndexURL, options: .atomic)

        for prunedEntry in prunedEntries {
            let url = cacheStorageDirectoryURL.appendingPathComponent(prunedEntry.cacheFileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
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
            lastFingerprint: fingerprints.last
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

    private static var cacheDirectoryURL: URL {
        if let sharedUserCacheDirectoryURL {
            return sharedUserCacheDirectoryURL
        }
        return cacheDirectoryURLs[0]
    }

    private static var cacheDirectoryURLs: [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()
        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            if seenPaths.insert(standardized.path).inserted {
                urls.append(standardized)
            }
        }

        if let sharedUserCacheDirectoryURL {
            append(sharedUserCacheDirectoryURL)
        }
        if let homeDirectory = ProcessInfo.processInfo.environment["HOME"], !homeDirectory.isEmpty {
            let homeURL = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            append(homeURL.appendingPathComponent("Library/Containers/com.justadev.StabilizerFxPlug.Plugin/Data/Library/Application Support/\(cacheDirectoryName)", isDirectory: true))
            for bundleIdentifier in legacyCacheBundleIdentifiers {
                append(homeURL.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(cacheDirectoryName)", isDirectory: true))
            }
        }
        let userName = NSUserName()
        if !userName.isEmpty {
            let userHomeURL = URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true)
            append(userHomeURL.appendingPathComponent("Library/Containers/com.justadev.StabilizerFxPlug.Plugin/Data/Library/Application Support/\(cacheDirectoryName)", isDirectory: true))
            for bundleIdentifier in legacyCacheBundleIdentifiers {
                append(userHomeURL.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(cacheDirectoryName)", isDirectory: true))
            }
        }
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            append(applicationSupport.appendingPathComponent(cacheDirectoryName, isDirectory: true))
        }
        if urls.isEmpty {
            append(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(cacheDirectoryName, isDirectory: true))
        }
        return urls
    }

    private static var sharedUserCacheDirectoryURL: URL? {
        let userName = NSUserName()
        if !userName.isEmpty {
            return URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(cacheDirectoryName)", isDirectory: true)
                .standardizedFileURL
        }
        if let homeDirectory = ProcessInfo.processInfo.environment["HOME"], !homeDirectory.isEmpty {
            return URL(fileURLWithPath: homeDirectory, isDirectory: true)
                .appendingPathComponent("Library/Application Support/\(cacheDirectoryName)", isDirectory: true)
                .standardizedFileURL
        }
        return nil
    }

    private static var cacheURL: URL {
        cacheURL(in: cacheDirectoryURL)
    }

    private static var cacheIndexURL: URL {
        cacheIndexURL(in: cacheDirectoryURL)
    }

    private static var cacheStorageDirectoryURL: URL {
        cacheStorageDirectoryURL(in: cacheDirectoryURL)
    }

    private static func analysisScratchDirectoryURL() -> URL {
        analysisScratchDirectoryURL(in: cacheDirectoryURL)
    }

    private static func cacheURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private static func cacheIndexURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheIndexFileName, isDirectory: false)
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
