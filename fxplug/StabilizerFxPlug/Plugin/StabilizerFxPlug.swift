import CoreMedia
import Foundation
import Metal
import simd

private enum ParameterID: UInt32 {
    case strength = 1
    case offsetX = 2
    case offsetY = 3
    case rotationDegrees = 4
    case scalePercent = 5
    case autoStabilize = 6
    case xyzStrength = 7
    case rotationStrength = 8
    case panSmoothSeconds = 9
    case debugOverlay = 10
}

private struct StabilizerPluginState {
    var strength: Double
    var offsetX: Double
    var offsetY: Double
    var rotationDegrees: Double
    var scalePercent: Double
    var autoStabilize: Bool
    var xyzStrength: Double
    var rotationStrength: Double
    var panSmoothSeconds: Double
    var debugOverlay: Bool
}

@objc(StabilizerFxPlugPlugIn)
final class StabilizerFxPlugPlugIn: NSObject, FxTileableEffect {
    private let apiManager: PROAPIAccessing

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
        paramAPI.addFloatSlider(
            withName: "Offset X",
            parameterID: ParameterID.offsetX.rawValue,
            defaultValue: 0.0,
            parameterMin: -5000.0,
            parameterMax: 5000.0,
            sliderMin: -500.0,
            sliderMax: 500.0,
            delta: 0.1,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Offset Y",
            parameterID: ParameterID.offsetY.rawValue,
            defaultValue: 0.0,
            parameterMin: -5000.0,
            parameterMax: 5000.0,
            sliderMin: -500.0,
            sliderMax: 500.0,
            delta: 0.1,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Rotation Degrees",
            parameterID: ParameterID.rotationDegrees.rawValue,
            defaultValue: 0.0,
            parameterMin: -45.0,
            parameterMax: 45.0,
            sliderMin: -10.0,
            sliderMax: 10.0,
            delta: 0.01,
            parameterFlags: flags
        )
        paramAPI.addFloatSlider(
            withName: "Scale Percent",
            parameterID: ParameterID.scalePercent.rawValue,
            defaultValue: 100.0,
            parameterMin: 1.0,
            parameterMax: 200.0,
            sliderMin: 90.0,
            sliderMax: 130.0,
            delta: 0.1,
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
            withName: "Pan Smooth Seconds",
            parameterID: ParameterID.panSmoothSeconds.rawValue,
            defaultValue: 6.0,
            parameterMin: 1.0,
            parameterMax: 12.0,
            sliderMin: 1.0,
            sliderMax: 12.0,
            delta: 0.25,
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
            offsetX: 0.0,
            offsetY: 0.0,
            rotationDegrees: 0.0,
            scalePercent: 100.0,
            autoStabilize: true,
            xyzStrength: 1.0,
            rotationStrength: 1.0,
            panSmoothSeconds: 6.0,
            debugOverlay: false
        )
        paramAPI.getFloatValue(&state.strength, fromParameter: ParameterID.strength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.offsetX, fromParameter: ParameterID.offsetX.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.offsetY, fromParameter: ParameterID.offsetY.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.rotationDegrees, fromParameter: ParameterID.rotationDegrees.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.scalePercent, fromParameter: ParameterID.scalePercent.rawValue, at: renderTime)
        var autoStabilize = ObjCBool(state.autoStabilize)
        paramAPI.getBoolValue(&autoStabilize, fromParameter: ParameterID.autoStabilize.rawValue, at: renderTime)
        state.autoStabilize = autoStabilize.boolValue
        paramAPI.getFloatValue(&state.xyzStrength, fromParameter: ParameterID.xyzStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.rotationStrength, fromParameter: ParameterID.rotationStrength.rawValue, at: renderTime)
        paramAPI.getFloatValue(&state.panSmoothSeconds, fromParameter: ParameterID.panSmoothSeconds.rawValue, at: renderTime)
        var debugOverlay = ObjCBool(state.debugOverlay)
        paramAPI.getBoolValue(&debugOverlay, fromParameter: ParameterID.debugOverlay.rawValue, at: renderTime)
        state.debugOverlay = debugOverlay.boolValue

        pluginState?.pointee = NSData(bytes: &state, length: MemoryLayout<StabilizerPluginState>.size)
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

        if state.autoStabilize {
            let windowSeconds = min(12.0, max(1.0, state.panSmoothSeconds))
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

            let sampleStepSeconds = 0.5
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
        let autoTransform = state.autoStabilize
            ? AutoStabilizationEstimator.estimate(
                sourceImages: sourceImages,
                renderTime: renderTime,
                outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
                panSmoothSeconds: state.panSmoothSeconds
            )
            : .identity
        let masterStrength = Float(max(0.0, state.strength))
        let xyzStrength = Float(max(0.0, state.xyzStrength)) * masterStrength
        let rotationStrength = Float(max(0.0, state.rotationStrength)) * masterStrength
        let manualScale = Float(max(state.scalePercent, 1.0) / 100.0)
        let autoScale = 1.0 + ((autoTransform.scaleMultiplier - 1.0) * xyzStrength)
        let diagnostic = vector_float4(
            min(1.0, abs(autoTransform.pixelOffset.x) / max(1.0, Float(outputWidth) * 0.05)),
            min(1.0, abs(autoTransform.pixelOffset.y) / max(1.0, Float(outputHeight) * 0.05)),
            min(1.0, max(0.0, (autoTransform.scaleMultiplier - 1.0) / 0.18)),
            min(1.0, abs(autoTransform.rotationDegrees) / 5.0)
        )

        var transform = StabilizerTransformUniforms(
            pixelOffset: vector_float2(Float(state.offsetX), Float(state.offsetY)) + (autoTransform.pixelOffset * xyzStrength),
            rotationRadians: Float(state.rotationDegrees * .pi / 180.0) + (autoTransform.rotationDegrees * .pi / 180.0 * rotationStrength),
            scale: manualScale * autoScale,
            strength: 1.0,
            outputSize: vector_float2(Float(outputWidth), Float(outputHeight)),
            diagnostic: diagnostic,
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
}
