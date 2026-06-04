import CoreMedia
import Foundation
import Metal
import simd

private enum ParameterID: UInt32 {
    case strength = 1
    case autoStabilize = 6
    case xyzStrength = 7
    case rotationStrength = 8
    case panSmoothSeconds = 9
    case debugOverlay = 10
    case analysisSource = 13
    case startHostAnalysis = 14
    case hostAnalysisStatus = 15
}

private enum AnalysisSource: Int32 {
    case hostAnalysis = 1
    case liveFrames = 2

    static func fromParameterValue(_ value: Int32) -> AnalysisSource {
        AnalysisSource(rawValue: value) ?? .hostAnalysis
    }
}

private struct StabilizerPluginState {
    var strength: Double
    var autoStabilize: Bool
    var xyzStrength: Double
    var rotationStrength: Double
    var panSmoothSeconds: Double
    var debugOverlay: Bool
    var analysisSource: Int32
    var hostAnalysisFrameCount: Int32
}

@objc(StabilizerFxPlugPlugIn)
final class StabilizerFxPlugPlugIn: NSObject, FxTileableEffect, FxAnalyzer {
    private let apiManager: PROAPIAccessing
    private let hostAnalysisStore = StabilizerHostAnalysisStore()
    private let statusLock = NSLock()
    private var lastPublishedStatus = ""

    required init?(apiManager: PROAPIAccessing) {
        self.apiManager = apiManager
        hostAnalysisStore.loadPersistentCache()
    }

    func addParameters() throws {
        let paramAPI = apiManager.api(for: FxParameterCreationAPI_v5.self) as! FxParameterCreationAPI_v5
        let flags = FxParameterFlags(kFxParameterFlag_DEFAULT)

        paramAPI.addFloatSlider(
            withName: "Strength",
            parameterID: ParameterID.strength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 2.0,
            sliderMin: 0.0,
            sliderMax: 2.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addToggleButton(
            withName: "Auto Stabilize",
            parameterID: ParameterID.autoStabilize.rawValue,
            defaultValue: true,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "XYZ Strength",
            parameterID: ParameterID.xyzStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 2.0,
            sliderMin: 0.0,
            sliderMax: 2.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Rotation Strength",
            parameterID: ParameterID.rotationStrength.rawValue,
            defaultValue: 1.0,
            parameterMin: 0.0,
            parameterMax: 2.0,
            sliderMin: 0.0,
            sliderMax: 2.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Pan Smooth Seconds Slider",
            parameterID: ParameterID.panSmoothSeconds.rawValue,
            defaultValue: 6.0,
            parameterMin: 0.1,
            parameterMax: 120.0,
            sliderMin: 0.1,
            sliderMax: 30.0,
            delta: 0.25,
            parameterFlags: flags
        )
        paramAPI.addPopupMenu(
            withName: "Analysis Source",
            parameterID: ParameterID.analysisSource.rawValue,
            defaultValue: UInt32(AnalysisSource.hostAnalysis.rawValue),
            menuEntries: ["Host Analysis", "Live Frames"],
            parameterFlags: flags
        )
        paramAPI.addPushButton(
            withName: "Start Host Analysis",
            parameterID: ParameterID.startHostAnalysis.rawValue,
            selector: #selector(startHostAnalysis),
            parameterFlags: flags
        )
        paramAPI.addStringParameter(
            withName: "Host Analysis Status",
            parameterID: ParameterID.hostAnalysisStatus.rawValue,
            defaultValue: "Needs Analysis",
            parameterFlags: FxParameterFlags(kFxParameterFlag_NOT_ANIMATABLE | kFxParameterFlag_DISABLED | kFxParameterFlag_DONT_SAVE)
        )
        paramAPI.addToggleButton(
            withName: "Debug Overlay",
            parameterID: ParameterID.debugOverlay.rawValue,
            defaultValue: false,
            parameterFlags: flags
        )
        publishHostAnalysisStatus(force: true)
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
            autoStabilize: true,
            xyzStrength: 1.0,
            rotationStrength: 1.0,
            panSmoothSeconds: 6.0,
            debugOverlay: false,
            analysisSource: AnalysisSource.hostAnalysis.rawValue,
            hostAnalysisFrameCount: 0
        )
        paramAPI.getFloatValue(&state.strength, fromParameter: ParameterID.strength.rawValue, at: renderTime)
        var autoStabilize = ObjCBool(state.autoStabilize)
        paramAPI.getBoolValue(&autoStabilize, fromParameter: ParameterID.autoStabilize.rawValue, at: renderTime)
        state.autoStabilize = autoStabilize.boolValue
        paramAPI.getFloatValue(&state.xyzStrength, fromParameter: ParameterID.xyzStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.rotationStrength, fromParameter: ParameterID.rotationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.panSmoothSeconds, fromParameter: ParameterID.panSmoothSeconds.rawValue, at: renderTime)
        var debugOverlay = ObjCBool(state.debugOverlay)
        paramAPI.getBoolValue(&debugOverlay, fromParameter: ParameterID.debugOverlay.rawValue, at: renderTime)
        state.debugOverlay = debugOverlay.boolValue
        var analysisSource = Int32(state.analysisSource)
        if paramAPI.getIntValue(&analysisSource, fromParameter: ParameterID.analysisSource.rawValue, at: renderTime) {
            state.analysisSource = AnalysisSource.fromParameterValue(analysisSource).rawValue
        }
        let cappedHostFrameCount = min(hostAnalysisStore.frameCount, Int(Int32.max))
        state.hostAnalysisFrameCount = Int32(cappedHostFrameCount)
        if state.autoStabilize && AnalysisSource.fromParameterValue(state.analysisSource) == .hostAnalysis {
            requestHostAnalysisIfNeeded()
        }
        publishHostAnalysisStatus()

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
    }

    @objc(startHostAnalysis)
    func startHostAnalysis() {
        hostAnalysisStore.reset(removePersistentCache: true)
        publishHostAnalysisStatus(force: true)
        requestHostAnalysisIfNeeded(force: true)
    }

    private func requestHostAnalysisIfNeeded(force: Bool = false) {
        guard force || !hostAnalysisStore.hasCompletedAnalysis else {
            return
        }
        guard let analysisAPI = apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            NSLog("StabilizerFxPlug: FxAnalysisAPI is unavailable; Host Analysis cannot start.")
            return
        }
        let analysisState = analysisAPI.analysisStateForEffect()
        let canStart = analysisState == kFxAnalysisState_NotAnalyzing
            || analysisState == kFxAnalysisState_AnalysisInterrupted
            || (force && analysisState == kFxAnalysisState_AnalysisCompleted)
        guard canStart else {
            publishHostAnalysisStatus(force: force)
            if force {
                NSLog("StabilizerFxPlug: Host Analysis is already requested or running.")
            }
            return
        }
        do {
            try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_GPU)
            hostAnalysisStore.markRequested()
            publishHostAnalysisStatus(force: true)
        } catch {
            NSLog("StabilizerFxPlug: Host Analysis request failed: \(error.localizedDescription)")
        }
    }

    private func publishHostAnalysisStatus(force: Bool = false) {
        let status = hostAnalysisStore.statusText
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

    func scheduleInputs(_ inputImageRequests: AutoreleasingUnsafeMutablePointer<NSArray?>?, withPluginState pluginState: Data?, at renderTime: CMTime) throws {
        guard let state = pluginState?.withUnsafeBytes({ pointer in
            pointer.bindMemory(to: StabilizerPluginState.self).baseAddress?.pointee
        }) else {
            inputImageRequests?.pointee = nil
            return
        }

        var requests: [FxImageTileRequest] = []
        if let current = FxImageTileRequest(
            source: kFxImageTileRequestSourceEffectClip,
            time: renderTime,
            includeFilters: true,
            parameterID: 0
        ) {
            requests.append(current)
        }

        if state.autoStabilize && AnalysisSource.fromParameterValue(state.analysisSource) == .liveFrames {
            let windowSeconds = max(0.1, state.panSmoothSeconds)
            let halfWindow = windowSeconds * 0.5
            let requestTimescale: CMTimeScale = 600
            let frameStep = CMTime(value: 20, timescale: requestTimescale)
            var requestedTimes = Set<Int64>()

            func appendAnalysisRequest(at time: CMTime) {
                let normalizedTime = CMTimeConvertScale(time, timescale: requestTimescale, method: .roundHalfAwayFromZero)
                guard requestedTimes.insert(normalizedTime.value).inserted else {
                    return
                }
                if let request = FxImageTileRequest(
                    source: kFxImageTileRequestSourceEffectClip,
                    time: normalizedTime,
                    includeFilters: true,
                    parameterID: 0
                ) {
                    requests.append(request)
                }
            }

            for frameOffset in -4...4 {
                appendAnalysisRequest(at: CMTimeAdd(renderTime, CMTimeMultiply(frameStep, multiplier: Int32(frameOffset))))
            }

            let sampleStepSeconds = max(0.5, windowSeconds / 240.0)
            var offset = -halfWindow
            while offset <= halfWindow + 0.0001 {
                appendAnalysisRequest(at: CMTimeAdd(renderTime, CMTime(seconds: offset, preferredTimescale: requestTimescale)))
                offset += sampleStepSeconds
            }
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
        let analysisSource = AnalysisSource.fromParameterValue(state.analysisSource)
        let autoTransform: StabilizerAutoTransform
        if state.autoStabilize {
            switch analysisSource {
            case .hostAnalysis:
                if let preparedAnalysis = hostAnalysisStore.preparedAnalysisForRender(validating: sourceImages[0], at: renderTime) {
                    autoTransform = AutoStabilizationEstimator.estimate(
                        preparedAnalysis: preparedAnalysis,
                        renderTime: renderTime,
                        outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                        panSmoothSeconds: state.panSmoothSeconds
                    )
                } else {
                    autoTransform = .identity
                }
            case .liveFrames:
                autoTransform = AutoStabilizationEstimator.estimate(
                    sourceImages: sourceImages,
                    renderTime: renderTime,
                    outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                    panSmoothSeconds: state.panSmoothSeconds
                )
            }
        } else {
            autoTransform = .identity
        }
        let masterStrength = Float(max(0.0, state.strength))
        let xyzStrength = Float(max(0.0, state.xyzStrength)) * masterStrength
        let rotationStrength = Float(max(0.0, state.rotationStrength)) * masterStrength
        let autoScale = 1.0 + ((autoTransform.scaleMultiplier - 1.0) * xyzStrength)
        let diagnostic = vector_float4(
            min(1.0, abs(autoTransform.pixelOffset.x) / max(1.0, Float(outputWidth) * 0.05)),
            min(1.0, abs(autoTransform.pixelOffset.y) / max(1.0, Float(outputHeight) * 0.05)),
            min(1.0, max(0.0, (autoTransform.scaleMultiplier - 1.0) / 0.18)),
            min(1.0, abs(autoTransform.rotationDegrees) / 5.0)
        )
        let diagnostic2 = vector_float4(
            min(1.0, simd_length(autoTransform.yawPitchProxy) / 0.10),
            min(1.0, simd_length(autoTransform.shear) / 0.10),
            min(1.0, simd_length(autoTransform.perspective) / 0.10),
            min(1.0, autoTransform.blurAmount)
        )

        var transform = StabilizerTransformUniforms(
            pixelOffset: autoTransform.pixelOffset * xyzStrength,
            rotationRadians: autoTransform.rotationDegrees * .pi / 180.0 * rotationStrength,
            scale: autoScale,
            strength: 1.0,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            diagnostic: diagnostic,
            diagnostic2: diagnostic2,
            shear: autoTransform.shear * xyzStrength,
            perspective: (autoTransform.perspective + autoTransform.yawPitchProxy) * xyzStrength,
            debugOverlay: state.debugOverlay ? 1.0 : 0.0
        )

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
        hostAnalysisStore.begin(range: analysisRange, frameDuration: frameDuration)
        publishHostAnalysisStatus(force: true)
    }

    func analyzeFrame(_ frame: FxImageTile!, at frameTime: CMTime) throws {
        guard let frame else {
            throw NSError(
                domain: "com.justadev.CommandPostEmDash.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "StabilizerFxPlug host analysis supplied no frame."]
            )
        }
        guard let analysisFrame = AutoStabilizationEstimator.analysisFrame(from: frame, at: frameTime) else {
            throw NSError(
                domain: "com.justadev.CommandPostEmDash.StabilizerFxPlug",
                code: Int(kFxError_AnalysisError),
                userInfo: [NSLocalizedDescriptionKey: "StabilizerFxPlug could not read the host analysis frame."]
            )
        }
        hostAnalysisStore.append(analysisFrame)
    }

    func cleanupAnalysis() throws {
        hostAnalysisStore.finish()
        publishHostAnalysisStatus(force: true)
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
}

private struct PersistedHostAnalysisCache: Codable {
    let schemaVersion: Int
    let createdAt: Double
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
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
    let blurAmounts: [Float]?
}

private struct PersistedHostAnalysisFrame: Codable {
    let time: Double
    let pixels: Data
    let blurAmount: Float
}

private final class StabilizerHostAnalysisStore {
    private static let cacheSchemaVersion = 2
    private static let cacheValidationMeanDifferenceThreshold: Float = 18.0
    private static let cacheDirectoryName = "StabilizerFxPlug"
    private static let cacheFileName = "host-analysis-v2.json"

    private let lock = NSLock()
    private var framesByTimeKey: [Int64: StabilizerAnalysisFrame] = [:]
    private var preparedAnalysis: StabilizerPreparedAnalysis?
    private var activeRange: CMTimeRange = .invalid
    private var activeFrameDuration: CMTime = .invalid
    private var finished = false
    private var validationState: HostAnalysisValidationState = .notRequired
    private var status: HostAnalysisStatus = .needsAnalysis

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return framesByTimeKey.count
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
        }
    }

    var hasCompletedAnalysis: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished && validationState != .rejected && preparedAnalysis != nil
    }

    func begin(range: CMTimeRange, frameDuration: CMTime) {
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        preparedAnalysis = nil
        activeRange = range
        activeFrameDuration = frameDuration
        finished = false
        validationState = .validated
        status = .analyzing
        lock.unlock()
        removePersistentCache(logFailures: true)
    }

    func markRequested() {
        lock.lock()
        if preparedAnalysis == nil && status != .analyzing {
            status = .requested
        }
        lock.unlock()
    }

    func reset(removePersistentCache shouldRemovePersistentCache: Bool = false) {
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        preparedAnalysis = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        validationState = .notRequired
        status = .needsAnalysis
        lock.unlock()
        if shouldRemovePersistentCache {
            removePersistentCache(logFailures: true)
        }
    }

    func append(_ frame: StabilizerAnalysisFrame) {
        lock.lock()
        framesByTimeKey[Self.timeKey(frame.time)] = frame
        lock.unlock()
    }

    func finish() {
        rebuildPreparedAnalysis(markFinished: true)
        persistIfCompleted()
    }

    func preparedAnalysisForRender(validating sourceImage: FxImageTile, at renderTime: CMTime) -> StabilizerPreparedAnalysis? {
        guard let analysis = preparedAnalysisSnapshot() else {
            return nil
        }

        let state = currentValidationState()
        if state == .validated || state == .notRequired {
            return analysis
        }
        if state == .rejected {
            return nil
        }

        guard let currentFrame = AutoStabilizationEstimator.analysisFrame(from: sourceImage, at: renderTime) else {
            rejectPersistentCache(reason: "could not validate the persisted cache against the current source frame")
            return nil
        }
        guard let closestFrame = analysis.frames.min(by: { abs($0.time - currentFrame.time) < abs($1.time - currentFrame.time) }) else {
            rejectPersistentCache(reason: "persisted cache had no comparable frame")
            return nil
        }

        let meanDifference = Self.meanAbsoluteDifference(currentFrame.pixels, closestFrame.pixels)
        guard meanDifference <= Self.cacheValidationMeanDifferenceThreshold else {
            rejectPersistentCache(
                reason: String(format: "current frame did not match the persisted cache (mean luma difference %.2f)", meanDifference)
            )
            return nil
        }

        lock.lock()
        if validationState == .pending {
            validationState = .validated
            status = .ready
        }
        lock.unlock()
        NSLog("StabilizerFxPlug: validated persisted Host Analysis cache with \(analysis.frames.count) frames.")
        return analysis
    }

    func loadPersistentCache() {
        let url = Self.cacheURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
            guard cache.schemaVersion == Self.cacheSchemaVersion else {
                NSLog("StabilizerFxPlug: ignoring Host Analysis cache with unsupported schema \(cache.schemaVersion).")
                return
            }
            let frames = cache.frames.compactMap { persistedFrame -> StabilizerAnalysisFrame? in
                let pixels = [UInt8](persistedFrame.pixels)
                guard !pixels.isEmpty else {
                    return nil
                }
                return StabilizerAnalysisFrame(
                    time: persistedFrame.time,
                    pixels: pixels,
                    blurAmount: persistedFrame.blurAmount
                )
            }
            guard frames.count >= 3 else {
                NSLog("StabilizerFxPlug: ignoring Host Analysis cache with too few frames.")
                return
            }
            let prepared = Self.preparedAnalysis(from: cache, frames: frames)

            lock.lock()
            framesByTimeKey = Dictionary(uniqueKeysWithValues: frames.map { (Self.timeKey($0.time), $0) })
            preparedAnalysis = prepared
            activeRange = CMTimeRange(
                start: CMTime(seconds: cache.rangeStartSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: cache.rangeDurationSeconds, preferredTimescale: 600)
            )
            activeFrameDuration = CMTime(seconds: cache.frameDurationSeconds, preferredTimescale: 600)
            finished = true
            validationState = .pending
            status = .cacheLoaded
            lock.unlock()
            NSLog("StabilizerFxPlug: loaded persisted Host Analysis cache with \(frames.count) frames.")
        } catch {
            NSLog("StabilizerFxPlug: failed to load Host Analysis cache: \(error.localizedDescription)")
        }
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
        let rangeStartSeconds = CMTimeGetSeconds(snapshot.range.start)
        let rangeDurationSeconds = CMTimeGetSeconds(snapshot.range.duration)
        let frameDurationSeconds = CMTimeGetSeconds(snapshot.frameDuration)
        guard rangeStartSeconds.isFinite, rangeDurationSeconds.isFinite, frameDurationSeconds.isFinite else {
            NSLog("StabilizerFxPlug: Host Analysis cache was not saved because the host supplied an invalid time range.")
            return
        }

        let cache = PersistedHostAnalysisCache(
            schemaVersion: Self.cacheSchemaVersion,
            createdAt: Date().timeIntervalSince1970,
            rangeStartSeconds: rangeStartSeconds,
            rangeDurationSeconds: rangeDurationSeconds,
            frameDurationSeconds: frameDurationSeconds,
            frames: snapshot.frames.map {
                PersistedHostAnalysisFrame(
                    time: $0.time,
                    pixels: Data($0.pixels),
                    blurAmount: $0.blurAmount
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
            blurAmounts: prepared.blurAmounts
        )

        do {
            try FileManager.default.createDirectory(at: Self.cacheDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: Self.cacheURL, options: .atomic)
            NSLog("StabilizerFxPlug: saved Host Analysis cache with \(snapshot.frames.count) frames to \(Self.cacheURL.path).")
        } catch {
            NSLog("StabilizerFxPlug: failed to save Host Analysis cache: \(error.localizedDescription)")
        }
    }

    private func rebuildPreparedAnalysis(markFinished: Bool) {
        let frames = framesSnapshot()
        let prepared = frames.count >= 3 ? AutoStabilizationEstimator.prepare(analysisFrames: frames) : nil
        lock.lock()
        preparedAnalysis = prepared
        if markFinished {
            finished = true
            status = prepared == nil ? .needsAnalysis : .ready
        }
        lock.unlock()
    }

    private func preparedAnalysisSnapshot() -> StabilizerPreparedAnalysis? {
        lock.lock()
        let analysis = preparedAnalysis
        lock.unlock()
        return analysis
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

    private func rejectPersistentCache(reason: String) {
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        preparedAnalysis = nil
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        validationState = .rejected
        status = .cacheRejected
        lock.unlock()
        removePersistentCache(logFailures: true)
        NSLog("StabilizerFxPlug: rejected persisted Host Analysis cache: \(reason).")
    }

    private func removePersistentCache(logFailures: Bool) {
        let url = Self.cacheURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if logFailures {
                NSLog("StabilizerFxPlug: failed to remove Host Analysis cache: \(error.localizedDescription)")
            }
        }
    }

    private static func timeKey(_ seconds: Double) -> Int64 {
        Int64((seconds * 600.0).rounded())
    }

    private static func preparedAnalysis(from cache: PersistedHostAnalysisCache, frames: [StabilizerAnalysisFrame]) -> StabilizerPreparedAnalysis {
        let arrays = [
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
            cache.blurAmounts
        ]
        if arrays.allSatisfy({ $0?.count == frames.count }),
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
                blurAmounts: blurAmounts
            )
        }
        return AutoStabilizationEstimator.prepare(analysisFrames: frames)
    }

    private static var cacheDirectoryURL: URL {
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupport.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    private static var cacheURL: URL {
        cacheDirectoryURL.appendingPathComponent(cacheFileName, isDirectory: false)
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
