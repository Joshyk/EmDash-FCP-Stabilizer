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
    case panSmoothSecondsText = 11
    case analysisSource = 13
    case startHostAnalysis = 14
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

    required init?(apiManager: PROAPIAccessing) {
        self.apiManager = apiManager
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
        paramAPI.addStringParameter(
            withName: "Pan Smooth Seconds",
            parameterID: ParameterID.panSmoothSecondsText.rawValue,
            defaultValue: "6",
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
        paramAPI.addToggleButton(
            withName: "Debug Overlay",
            parameterID: ParameterID.debugOverlay.rawValue,
            defaultValue: false,
            parameterFlags: flags
        )
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
        var panSmoothText = "" as NSString
        if paramAPI.getStringParameterValue(&panSmoothText, fromParameter: ParameterID.panSmoothSecondsText.rawValue),
           let value = Self.parsePositiveSeconds(panSmoothText as String) {
            state.panSmoothSeconds = value
        }
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

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
    }

    @objc(startHostAnalysis)
    func startHostAnalysis() {
        hostAnalysisStore.reset()
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
            if force {
                NSLog("StabilizerFxPlug: Host Analysis is already requested or running.")
            }
            return
        }
        do {
            try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_GPU)
        } catch {
            NSLog("StabilizerFxPlug: Host Analysis request failed: \(error.localizedDescription)")
        }
    }

    private static func parsePositiveSeconds(_ text: String?) -> Double? {
        guard let rawText = text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty else {
            return nil
        }
        let normalized = rawText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0.0 else {
            return nil
        }
        return value
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
                if hostAnalysisStore.hasCompletedAnalysis {
                    autoTransform = AutoStabilizationEstimator.estimate(
                        analysisFrames: hostAnalysisStore.framesSnapshot(),
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
    }
}

private final class StabilizerHostAnalysisStore {
    private let lock = NSLock()
    private var framesByTimeKey: [Int64: StabilizerAnalysisFrame] = [:]
    private var activeRange: CMTimeRange = .invalid
    private var activeFrameDuration: CMTime = .invalid
    private var finished = false

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return framesByTimeKey.count
    }

    var hasCompletedAnalysis: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished && framesByTimeKey.count >= 3
    }

    func begin(range: CMTimeRange, frameDuration: CMTime) {
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        activeRange = range
        activeFrameDuration = frameDuration
        finished = false
        lock.unlock()
    }

    func reset() {
        lock.lock()
        framesByTimeKey.removeAll(keepingCapacity: true)
        activeRange = .invalid
        activeFrameDuration = .invalid
        finished = false
        lock.unlock()
    }

    func append(_ frame: StabilizerAnalysisFrame) {
        lock.lock()
        framesByTimeKey[Self.timeKey(frame.time)] = frame
        lock.unlock()
    }

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func framesSnapshot() -> [StabilizerAnalysisFrame] {
        lock.lock()
        let frames = framesByTimeKey.values.sorted { $0.time < $1.time }
        lock.unlock()
        return frames
    }

    private static func timeKey(_ seconds: Double) -> Int64 {
        Int64((seconds * 600.0).rounded())
    }
}
