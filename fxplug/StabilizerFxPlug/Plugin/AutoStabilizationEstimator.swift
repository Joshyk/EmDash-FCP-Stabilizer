import CoreMedia
import CoreVideo
import Darwin
import Foundation
import IOSurface
import Metal
import simd

struct StabilizerAutoTransform {
    var pixelOffset: vector_float2
    var macroPixelOffset: vector_float2
    var microPixelOffset: vector_float2
    var walkingBobPixelOffset: vector_float2
    var rotationDegrees: Float
    var yawPitchProxy: vector_float2
    var shear: vector_float2
    var perspective: vector_float2
    var blurAmount: Float

    static let identity = StabilizerAutoTransform(
        pixelOffset: vector_float2(0.0, 0.0),
        macroPixelOffset: vector_float2(0.0, 0.0),
        microPixelOffset: vector_float2(0.0, 0.0),
        walkingBobPixelOffset: vector_float2(0.0, 0.0),
        rotationDegrees: 0.0,
        yawPitchProxy: vector_float2(0.0, 0.0),
        shear: vector_float2(0.0, 0.0),
        perspective: vector_float2(0.0, 0.0),
        blurAmount: 0.0
    )
}

struct StabilizerCorrectionStrengths {
    let microJitterX: Double
    let microJitterY: Double
    let microJitterRotation: Double
    let panStabilizationStrength: Double
    let walkingBob: Double

    static let defaultStrengths = StabilizerCorrectionStrengths(
        microJitterX: 0.5,
        microJitterY: 0.5,
        microJitterRotation: 0.35,
        panStabilizationStrength: 0.5,
        walkingBob: 0.5
    )
}

struct StabilizerAnalysisFrame {
    let time: Double
    let pixels: [UInt8]
    let sampleWidth: Int
    let sampleHeight: Int
    let blurAmount: Float
    let fingerprint: String

    init(time: Double, pixels: [UInt8], sampleWidth: Int, sampleHeight: Int, blurAmount: Float, fingerprint: String? = nil) {
        self.time = time
        self.pixels = pixels
        self.sampleWidth = sampleWidth
        self.sampleHeight = sampleHeight
        self.blurAmount = blurAmount
        self.fingerprint = fingerprint ?? Self.fingerprint(for: pixels)
    }

    var sampleSizeDescription: String {
        "\(sampleWidth)x\(sampleHeight)"
    }

    static func fingerprint(for pixels: [UInt8]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func combine(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        for byte in pixels {
            combine(byte)
        }
        var count = UInt64(pixels.count)
        for _ in 0..<MemoryLayout<UInt64>.size {
            combine(UInt8(count & 0xff))
            count >>= 8
        }
        return String(format: "%016llx", hash)
    }
}

extension StabilizerAnalysisFrame {
    func withoutRetainedPixels() -> StabilizerAnalysisFrame {
        StabilizerAnalysisFrame(
            time: time,
            pixels: [],
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            blurAmount: blurAmount,
            fingerprint: fingerprint
        )
    }

    func retainingPixels(_ pixels: [UInt8]) -> StabilizerAnalysisFrame {
        StabilizerAnalysisFrame(
            time: time,
            pixels: pixels,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            blurAmount: blurAmount,
            fingerprint: fingerprint
        )
    }
}

struct StabilizerPreparedAnalysis {
    let frames: [StabilizerAnalysisFrame]
    let residuals: [Float]
    let rollMotion: [Float]
    let pathX: [Float]
    let pathY: [Float]
    let pathRoll: [Float]
    let pathYaw: [Float]
    let pathPitch: [Float]
    let pathShearX: [Float]
    let pathShearY: [Float]
    let pathPerspectiveX: [Float]
    let pathPerspectiveY: [Float]
    let blurAmounts: [Float]
}

fileprivate struct PairMotion {
    let dx: Float
    let dy: Float
    let residual: Float
    let signedRoll: Float
    let rollMotion: Float
    let yawProxy: Float
    let pitchProxy: Float
    let shearX: Float
    let shearY: Float
    let perspectiveX: Float
    let perspectiveY: Float
}

fileprivate final class MetalAnalysisContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let shiftPipelineState: MTLComputePipelineState

    init(preferredDevice: MTLDevice? = nil) throws {
        guard let device = preferredDevice ?? MTLCreateSystemDefaultDevice() else {
            throw AutoStabilizationEstimator.metalError("Metal device was not available for Stabilizer analysis.")
        }
        guard
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let shiftFunction = library.makeFunction(name: "stabilizerShiftScores")
        else {
            throw AutoStabilizationEstimator.metalError("Stabilizer Metal analysis resources were unavailable.")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.shiftPipelineState = try device.makeComputePipelineState(function: shiftFunction)
    }

    func frameBuffer(for frame: StabilizerAnalysisFrame) throws -> MTLBuffer {
        guard frame.pixels.count == frame.sampleWidth * frame.sampleHeight else {
            throw AutoStabilizationEstimator.metalError("Stabilizer analysis frame had an unexpected sample size.")
        }
        guard let buffer = device.makeBuffer(
            bytes: frame.pixels,
            length: frame.pixels.count,
            options: .storageModeShared
        ) else {
            throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer Metal analysis frame buffer.")
        }
        return buffer
    }
}

enum AutoStabilizationEstimator {
    static let defaultSampleWidth = 96
    static let defaultSampleHeight = 54
    static let minimumSampleWidth = 32
    static let minimumSampleHeight = 24
    private static let globalSearchRadius = 16
    private static let localSearchRadius = 5
    private static let positionGain: Float = 0.85
    private static let rotationGain: Float = 0.65
    private static let microJitterPositionGain: Float = 0.75
    private static let microJitterRotationGain: Float = 0.55
    private static let walkingBobPositionGain: Float = 0.85

    fileprivate static func metalError(_ message: String) -> NSError {
        NSError(
            domain: "com.justadev.StabilizerFxPlug",
            code: Int(kFxError_AnalysisError),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func estimate(
        sourceImages: [FxImageTile],
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        microJitterWindowSeconds: Double,
        walkingBobWindowSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) throws -> StabilizerAutoTransform {
        let frames = try sourceImages
            .dropFirst()
            .map { try analysisFrame(from: $0, sampleWidth: defaultSampleWidth, sampleHeight: defaultSampleHeight) }
            .sorted { $0.time < $1.time }
        return try estimate(
            analysisFrames: frames,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            microJitterWindowSeconds: microJitterWindowSeconds,
            walkingBobWindowSeconds: walkingBobWindowSeconds,
            strengths: strengths
        )
    }

    static func prepare(analysisFrames frames: [StabilizerAnalysisFrame]) throws -> StabilizerPreparedAnalysis {
        try prepare(analysisFrames: frames) { frame in
            guard frame.pixels.count == frame.sampleWidth * frame.sampleHeight else {
                throw metalError("Stabilizer analysis frame pixels were unavailable.")
            }
            return frame.pixels
        }
    }

    static func prepare(
        analysisFrames frames: [StabilizerAnalysisFrame],
        pixelsForFrame: (StabilizerAnalysisFrame) throws -> [UInt8]
    ) throws -> StabilizerPreparedAnalysis {
        let sortedFrames = frames.sorted { $0.time < $1.time }
        guard let firstFrame = sortedFrames.first else {
            throw metalError("Stabilizer analysis had no frames to prepare.")
        }
        let sampleWidth = firstFrame.sampleWidth
        let sampleHeight = firstFrame.sampleHeight
        guard sortedFrames.allSatisfy({ $0.sampleWidth == sampleWidth && $0.sampleHeight == sampleHeight }) else {
            throw metalError("Stabilizer analysis frames used mixed sample sizes.")
        }
        let metalContext = try MetalAnalysisContext()
        var motions = [
            PairMotion(
                dx: 0.0,
                dy: 0.0,
                residual: 0.0,
                signedRoll: 0.0,
                rollMotion: 0.0,
                yawProxy: 0.0,
                pitchProxy: 0.0,
                shearX: 0.0,
                shearY: 0.0,
                perspectiveX: 0.0,
                perspectiveY: 0.0
            )
        ]
        if sortedFrames.count >= 2 {
            var previousFrame = sortedFrames[0].retainingPixels(try pixelsForFrame(sortedFrames[0]))
            var previousFrameBuffer = try metalContext.frameBuffer(for: previousFrame)
            for index in 1..<sortedFrames.count {
                let currentFrame = sortedFrames[index].retainingPixels(try pixelsForFrame(sortedFrames[index]))
                let currentFrameBuffer = try metalContext.frameBuffer(for: currentFrame)
                motions.append(try pairMotion(
                    context: metalContext,
                    previous: previousFrameBuffer,
                    current: currentFrameBuffer,
                    sampleWidth: sampleWidth,
                    sampleHeight: sampleHeight
                ))
                previousFrame = currentFrame
                previousFrameBuffer = currentFrameBuffer
            }
        }

        return try preparedAnalysis(sortedFrames: sortedFrames, motions: motions)
    }

    static func estimate(
        analysisFrames frames: [StabilizerAnalysisFrame],
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        microJitterWindowSeconds: Double,
        walkingBobWindowSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) throws -> StabilizerAutoTransform {
        let preparedAnalysis = try prepare(analysisFrames: frames)
        return estimate(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            microJitterWindowSeconds: microJitterWindowSeconds,
            walkingBobWindowSeconds: walkingBobWindowSeconds,
            strengths: strengths
        )
    }

    static func estimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        microJitterWindowSeconds: Double,
        walkingBobWindowSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> StabilizerAutoTransform {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return .identity
        }

        let frames = analysis.frames
        guard frames.count >= 3 else {
            return .identity
        }

        let smoothWindowSeconds = max(0.1, panSmoothSeconds)
        let centerIndex = closestFrameIndex(to: renderSeconds, in: frames)
        let windowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= smoothWindowSeconds * 0.5 }
        let activeIndices = windowIndices.isEmpty ? Array(frames.indices) : Array(windowIndices)

        let smoothX = timeWeightedAverage(analysis.pathX, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothY = timeWeightedAverage(analysis.pathY, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let requestedMicroWindowSeconds = min(0.12, max(0.01, smoothWindowSeconds))
        let microWindowSeconds = min(
            max(requestedMicroWindowSeconds, adjacentFrameWindowSeconds(for: centerIndex, in: frames)),
            max(0.01, smoothWindowSeconds)
        )
        let microWindowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= microWindowSeconds * 0.5 }
        let microActiveIndices = microWindowIndices.isEmpty ? [centerIndex] : Array(microWindowIndices)
        let microSmoothX = timeWeightedAverage(analysis.pathX, frames: frames, indices: microActiveIndices, centerTime: renderSeconds, windowSeconds: microWindowSeconds)
        let microSmoothY = timeWeightedAverage(analysis.pathY, frames: frames, indices: microActiveIndices, centerTime: renderSeconds, windowSeconds: microWindowSeconds)
        let microSmoothRoll = timeWeightedAverage(analysis.pathRoll, frames: frames, indices: microActiveIndices, centerTime: renderSeconds, windowSeconds: microWindowSeconds)
        let shockIndices = centeredIndices(around: centerIndex, radius: 3, inCount: frames.count)
        let microImpulseBaselineX = median(analysis.pathX, indices: shockIndices) ?? microSmoothX
        let microImpulseBaselineY = median(analysis.pathY, indices: shockIndices) ?? microSmoothY
        let microImpulseBaselineRoll = median(analysis.pathRoll, indices: shockIndices) ?? microSmoothRoll
        let effectiveWalkingBobWindowSeconds = min(max(0.1, walkingBobWindowSeconds), smoothWindowSeconds)
        let walkingBobWindowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= effectiveWalkingBobWindowSeconds * 0.5 }
        let walkingBobActiveIndices = walkingBobWindowIndices.isEmpty ? [centerIndex] : Array(walkingBobWindowIndices)
        let walkingBobSmoothY = timeWeightedAverage(analysis.pathY, frames: frames, indices: walkingBobActiveIndices, centerTime: renderSeconds, windowSeconds: effectiveWalkingBobWindowSeconds)

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let residual = maxValue(analysis.residuals, indices: activeIndices)
        let blurAmount = timeWeightedAverage(analysis.blurAmounts, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let confidence = clamp(1.0 - (residual * 1.2), min: 0.35, max: 1.0)
        let jitterConfidence = clamp(1.0 - (residual * 0.7), min: 0.70, max: 1.0)
        let panCorrectionStrength = clamp(Float(strengths.panStabilizationStrength), min: 0.0, max: 1.0)
        let panBandX = microSmoothX - smoothX
        let panBandY = walkingBobSmoothY - smoothY
        let macroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrength
        let macroCompensationY = -panBandY * yScale * positionGain * panCorrectionStrength
        let macroCompensationRotation: Float = 0.0
        let microCompensationX = -(analysis.pathX[centerIndex] - microImpulseBaselineX) * xScale * microJitterPositionGain * Float(max(0.0, strengths.microJitterX))
        let microCompensationY = -(analysis.pathY[centerIndex] - microImpulseBaselineY) * yScale * microJitterPositionGain * Float(max(0.0, strengths.microJitterY))
        let microCompensationRotation = -(analysis.pathRoll[centerIndex] - microImpulseBaselineRoll) * microJitterRotationGain * Float(max(0.0, strengths.microJitterRotation))
        let walkingBobBandY = microSmoothY - walkingBobSmoothY
        let walkingBobCompensationY = -walkingBobBandY * yScale * walkingBobPositionGain * Float(max(0.0, strengths.walkingBob))
        let macroPixelOffset = vector_float2(macroCompensationX * confidence, macroCompensationY * confidence)
        let microPixelOffset = vector_float2(microCompensationX * jitterConfidence, microCompensationY * jitterConfidence)
        let walkingBobPixelOffset = vector_float2(0.0, walkingBobCompensationY * jitterConfidence)
        let compensationX = macroPixelOffset.x + microPixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + walkingBobPixelOffset.y
        let compensationRotation = (macroCompensationRotation * confidence) + (microCompensationRotation * jitterConfidence)
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            walkingBobPixelOffset: walkingBobPixelOffset,
            rotationDegrees: compensationRotation,
            yawPitchProxy: vector_float2(0.0, 0.0),
            shear: vector_float2(0.0, 0.0),
            perspective: vector_float2(0.0, 0.0),
            blurAmount: blurAmount
        )
    }

    static func clampedSampleSize(
        requestedWidth: Int,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> (width: Int, height: Int) {
        let sourceWidth = max(1, sourceWidth)
        let sourceHeight = max(1, sourceHeight)
        let minimumWidth = min(minimumSampleWidth, sourceWidth)
        let minimumHeight = min(minimumSampleHeight, sourceHeight)
        let width = min(max(minimumWidth, requestedWidth), sourceWidth)
        if width == sourceWidth {
            return (width: sourceWidth, height: sourceHeight)
        }
        let aspectHeight = Int((Double(width) * Double(sourceHeight) / Double(sourceWidth)).rounded())
        return (
            width: width,
            height: min(max(minimumHeight, aspectHeight), sourceHeight)
        )
    }

    static func sampleSizeDescription(width: Int, height: Int) -> String {
        "\(width)x\(height)"
    }

    static func analysisFrame(from tile: FxImageTile, at frameTime: CMTime? = nil, sampleWidth: Int, sampleHeight: Int) throws -> StabilizerAnalysisFrame {
        let time = CMTimeGetSeconds(frameTime ?? tile.mediaTime)
        guard time.isFinite else {
            throw metalError("Stabilizer host analysis supplied a non-finite frame time.")
        }
        let sampleWidth = max(minimumSampleWidth, sampleWidth)
        let sampleHeight = max(minimumSampleHeight, sampleHeight)

        let deviceCache = MetalDeviceCache.deviceCache
        let pixelFormat = MetalDeviceCache.fxMTLPixelFormat(for: tile)
        guard
            let device = deviceCache.device(with: tile.deviceRegistryID),
            let inputTexture = tile.metalTexture(for: device),
            let commandQueue = deviceCache.commandQueue(with: tile.deviceRegistryID, pixelFormat: pixelFormat),
            let pipelineState = deviceCache.downsamplePipelineState(with: tile.deviceRegistryID, pixelFormat: pixelFormat),
            let outputBuffer = device.makeBuffer(length: sampleWidth * sampleHeight, options: .storageModeShared),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw metalError("Stabilizer Metal downsample resources were unavailable for Host Analysis.")
        }
        defer {
            deviceCache.returnCommandQueueToCache(commandQueue: commandQueue)
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputTexture, index: Int(SCTI_InputImage.rawValue))
        encoder.setBuffer(outputBuffer, offset: 0, index: Int(SCBI_DownsampleOutput.rawValue))
        var downsampleUniforms = StabilizerDownsampleUniforms(width: UInt32(sampleWidth), height: UInt32(sampleHeight))
        encoder.setBytes(&downsampleUniforms, length: MemoryLayout<StabilizerDownsampleUniforms>.stride, index: Int(SCBI_DownsampleUniforms.rawValue))
        encoder.dispatchThreads(
            MTLSize(width: sampleWidth, height: sampleHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }

        let pointer = outputBuffer.contents().assumingMemoryBound(to: UInt8.self)
        let pixels = Array(UnsafeBufferPointer(start: pointer, count: sampleWidth * sampleHeight))
        return StabilizerAnalysisFrame(
            time: time,
            pixels: pixels,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            blurAmount: blurAmount(pixels, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        )
    }

    fileprivate static func preparedAnalysis(sortedFrames: [StabilizerAnalysisFrame], motions: [PairMotion]) throws -> StabilizerPreparedAnalysis {
        guard sortedFrames.count == motions.count else {
            throw metalError("Stabilizer analysis motion count did not match frame count.")
        }
        return StabilizerPreparedAnalysis(
            frames: sortedFrames.map { $0.withoutRetainedPixels() },
            residuals: motions.map(\.residual),
            rollMotion: motions.map(\.rollMotion),
            pathX: cumulative(motions.map(\.dx)),
            pathY: cumulative(motions.map(\.dy)),
            pathRoll: cumulative(motions.map { radiansToDegrees($0.signedRoll) }),
            pathYaw: cumulative(motions.map(\.yawProxy)),
            pathPitch: cumulative(motions.map(\.pitchProxy)),
            pathShearX: cumulative(motions.map(\.shearX)),
            pathShearY: cumulative(motions.map(\.shearY)),
            pathPerspectiveX: cumulative(motions.map(\.perspectiveX)),
            pathPerspectiveY: cumulative(motions.map(\.perspectiveY)),
            blurAmounts: sortedFrames.map(\.blurAmount)
        )
    }

    fileprivate static func pairMotion(context: MetalAnalysisContext, previous: MTLBuffer, current: MTLBuffer, sampleWidth: Int, sampleHeight: Int) throws -> PairMotion {
        let global = try estimateShift(
            context: context,
            previous: previous,
            current: current,
            x0: 8,
            y0: 6,
            width: max(8, sampleWidth - 16),
            height: max(8, sampleHeight - 12),
            radius: globalSearchRadius,
            center: (0.0, 0.0),
            refine: true,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let center = (round(global.dx), round(global.dy))
        let left = try estimateShift(context: context, previous: previous, current: current, x0: 4, y0: 8, width: min(28, max(8, sampleWidth / 3)), height: max(8, sampleHeight - 16), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let right = try estimateShift(context: context, previous: previous, current: current, x0: max(4, sampleWidth - 32), y0: 8, width: min(28, max(8, sampleWidth / 3)), height: max(8, sampleHeight - 16), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let top = try estimateShift(context: context, previous: previous, current: current, x0: 12, y0: 4, width: max(8, sampleWidth - 24), height: min(20, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let bottom = try estimateShift(context: context, previous: previous, current: current, x0: 12, y0: max(4, sampleHeight - 24), width: max(8, sampleWidth - 24), height: min(20, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let topLeft = try estimateShift(context: context, previous: previous, current: current, x0: 6, y0: 5, width: min(24, max(8, sampleWidth / 3)), height: min(16, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let topRight = try estimateShift(context: context, previous: previous, current: current, x0: max(6, sampleWidth - 30), y0: 5, width: min(24, max(8, sampleWidth / 3)), height: min(16, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let bottomLeft = try estimateShift(context: context, previous: previous, current: current, x0: 6, y0: max(5, sampleHeight - 21), width: min(24, max(8, sampleWidth / 3)), height: min(16, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let bottomRight = try estimateShift(context: context, previous: previous, current: current, x0: max(6, sampleWidth - 30), y0: max(5, sampleHeight - 21), width: min(24, max(8, sampleWidth / 3)), height: min(16, max(8, sampleHeight / 3)), radius: localSearchRadius, center: center, refine: false, sampleWidth: sampleWidth, sampleHeight: sampleHeight)

        let rollFromVertical = (right.dy - left.dy) / Float(max(1, sampleWidth - 32))
        let horizontalSlope = (bottom.dx - top.dx) / Float(max(1, sampleHeight - 16))
        let rollFromHorizontal = -horizontalSlope
        let signedRoll = (rollFromVertical + rollFromHorizontal) * 0.5
        let rollMotion = max(abs(rollFromVertical), abs(rollFromHorizontal))
        let yawProxy = (right.dx - left.dx) / Float(max(1, sampleWidth - 32))
        let pitchProxy = (bottom.dy - top.dy) / Float(max(1, sampleHeight - 16))
        let shearX = horizontalSlope + signedRoll
        let shearY = rollFromVertical - signedRoll
        let topSpread = topRight.dx - topLeft.dx
        let bottomSpread = bottomRight.dx - bottomLeft.dx
        let leftVerticalSpread = bottomLeft.dy - topLeft.dy
        let rightVerticalSpread = bottomRight.dy - topRight.dy
        let perspectiveX = (topSpread - bottomSpread) / Float(max(1, sampleWidth - 12))
        let perspectiveY = (leftVerticalSpread - rightVerticalSpread) / Float(max(1, sampleHeight - 10))

        return PairMotion(
            dx: global.dx,
            dy: global.dy,
            residual: global.score,
            signedRoll: signedRoll,
            rollMotion: rollMotion,
            yawProxy: yawProxy,
            pitchProxy: pitchProxy,
            shearX: shearX,
            shearY: shearY,
            perspectiveX: perspectiveX,
            perspectiveY: perspectiveY
        )
    }

    fileprivate static func blurAmount(_ pixels: [UInt8], sampleWidth: Int, sampleHeight: Int) -> Float {
        var totalGradient: Float = 0.0
        var count: Float = 0.0
        for y in 1..<(sampleHeight - 1) {
            let row = y * sampleWidth
            for x in 1..<(sampleWidth - 1) {
                let horizontal = abs(Int(pixels[row + x + 1]) - Int(pixels[row + x - 1]))
                let vertical = abs(Int(pixels[row + sampleWidth + x]) - Int(pixels[row - sampleWidth + x]))
                totalGradient += Float(horizontal + vertical) / 510.0
                count += 1.0
            }
        }
        guard count > 0.0 else {
            return 1.0
        }
        let sharpness = totalGradient / count
        return 1.0 - clamp((sharpness - 0.015) / 0.11, min: 0.0, max: 1.0)
    }

    private static func estimateShift(
        context: MetalAnalysisContext,
        previous: MTLBuffer,
        current: MTLBuffer,
        x0: Int,
        y0: Int,
        width: Int,
        height: Int,
        radius: Int,
        center: (Float, Float),
        refine: Bool,
        sampleWidth: Int,
        sampleHeight: Int
    ) throws -> (dx: Float, dy: Float, score: Float) {
        let centerX = Int(center.0.rounded())
        let centerY = Int(center.1.rounded())
        let side = (radius * 2) + 1
        let scoreCount = side * side
        guard
            let scoreBuffer = context.device.makeBuffer(
                length: MemoryLayout<Float>.stride * scoreCount,
                options: .storageModeShared
            ),
            let commandBuffer = context.commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw metalError("Could not allocate Stabilizer Metal shift resources.")
        }

        var uniforms = StabilizerShiftUniforms(
            width: UInt32(sampleWidth),
            height: UInt32(sampleHeight),
            x0: UInt32(x0),
            y0: UInt32(y0),
            regionWidth: UInt32(width),
            regionHeight: UInt32(height),
            centerX: Int32(centerX),
            centerY: Int32(centerY),
            radius: UInt32(radius),
            stride: 2
        )

        encoder.setComputePipelineState(context.shiftPipelineState)
        encoder.setBuffer(previous, offset: 0, index: Int(SCBI_PreviousFrame.rawValue))
        encoder.setBuffer(current, offset: 0, index: Int(SCBI_CurrentFrame.rawValue))
        encoder.setBuffer(scoreBuffer, offset: 0, index: Int(SCBI_ShiftScores.rawValue))
        encoder.setBytes(&uniforms, length: MemoryLayout<StabilizerShiftUniforms>.stride, index: Int(SCBI_ShiftUniforms.rawValue))
        encoder.dispatchThreads(
            MTLSize(width: scoreCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, scoreCount), height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }

        let scores = scoreBuffer.contents().assumingMemoryBound(to: Float.self)
        var bestIndex = 0
        var bestScore = Float.greatestFiniteMagnitude
        for index in 0..<scoreCount {
            let score = scores[index]
            if score < bestScore {
                bestIndex = index
                bestScore = score
            }
        }
        let bestDx = Int(bestIndex % side) + centerX - radius
        let bestDy = Int(bestIndex / side) + centerY - radius

        guard refine else {
            return (Float(bestDx), Float(bestDy), bestScore)
        }

        func score(dx: Int, dy: Int) -> Float {
            let x = dx - centerX + radius
            let y = dy - centerY + radius
            guard x >= 0, x < side, y >= 0, y < side else {
                return Float.greatestFiniteMagnitude
            }
            return scores[(y * side) + x]
        }

        return (
            Float(bestDx) + axisOffset(before: score(dx: bestDx - 1, dy: bestDy), center: bestScore, after: score(dx: bestDx + 1, dy: bestDy)),
            Float(bestDy) + axisOffset(before: score(dx: bestDx, dy: bestDy - 1), center: bestScore, after: score(dx: bestDx, dy: bestDy + 1)),
            bestScore
        )
    }

    private static func axisOffset(before: Float, center: Float, after: Float) -> Float {
        guard before.isFinite, center.isFinite, after.isFinite else {
            return 0.0
        }
        let denominator = before - (2.0 * center) + after
        guard abs(denominator) >= 1e-9 else {
            return 0.0
        }
        return clamp(0.5 * (before - after) / denominator, min: -0.5, max: 0.5)
    }

    private static func cumulative(_ values: [Float]) -> [Float] {
        var total: Float = 0.0
        return values.map { value in
            total += value
            return total
        }
    }

    private static func closestFrameIndex(to time: Double, in frames: [StabilizerAnalysisFrame]) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, frame) in frames.enumerated() {
            let distance = abs(frame.time - time)
            if distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }

    private static func average(_ values: [Float], indices: [Int]) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        let total = indices.reduce(Float(0.0)) { partial, index in
            partial + values[index]
        }
        return total / Float(indices.count)
    }

    private static func centeredIndices(around centerIndex: Int, radius: Int, inCount count: Int) -> [Int] {
        guard count > 0 else {
            return []
        }
        let start = Swift.max(0, centerIndex - radius)
        let end = Swift.min(count - 1, centerIndex + radius)
        guard start <= end else {
            return []
        }
        return Array(start...end)
    }

    private static func median(_ values: [Float], indices: [Int]) -> Float? {
        guard !indices.isEmpty else {
            return nil
        }
        let sortedValues = indices.map { values[$0] }.sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[middle - 1] + sortedValues[middle]) * 0.5
        }
        return sortedValues[middle]
    }

    private static func timeWeightedAverage(_ values: [Float], frames: [StabilizerAnalysisFrame], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        guard indices.count > 1 else {
            return values[indices[0]]
        }

        let sortedIndices = indices.sorted()
        let windowStart = centerTime - (windowSeconds * 0.5)
        let windowEnd = centerTime + (windowSeconds * 0.5)
        var weightedTotal: Float = 0.0
        var totalWeight: Double = 0.0

        for (position, index) in sortedIndices.enumerated() {
            let currentTime = frames[index].time
            let leftBoundary: Double
            if position > 0 {
                leftBoundary = max(windowStart, (frames[sortedIndices[position - 1]].time + currentTime) * 0.5)
            } else {
                leftBoundary = windowStart
            }

            let rightBoundary: Double
            if position + 1 < sortedIndices.count {
                rightBoundary = min(windowEnd, (currentTime + frames[sortedIndices[position + 1]].time) * 0.5)
            } else {
                rightBoundary = windowEnd
            }

            let weight = max(0.0, rightBoundary - leftBoundary)
            weightedTotal += values[index] * Float(weight)
            totalWeight += weight
        }

        guard totalWeight > 1e-9 else {
            return average(values, indices: indices)
        }
        return weightedTotal / Float(totalWeight)
    }

    private static func adjacentFrameWindowSeconds(for centerIndex: Int, in frames: [StabilizerAnalysisFrame]) -> Double {
        guard frames.indices.contains(centerIndex), frames.count > 1 else {
            return 0.01
        }

        let centerTime = frames[centerIndex].time
        var adjacentDistance = 0.0
        if centerIndex > frames.startIndex {
            let previousDistance = abs(centerTime - frames[centerIndex - 1].time)
            if previousDistance.isFinite {
                adjacentDistance = max(adjacentDistance, previousDistance)
            }
        }
        if centerIndex + 1 < frames.endIndex {
            let nextDistance = abs(frames[centerIndex + 1].time - centerTime)
            if nextDistance.isFinite {
                adjacentDistance = max(adjacentDistance, nextDistance)
            }
        }
        guard adjacentDistance > 0.0 else {
            return 0.01
        }
        return adjacentDistance * 2.0
    }

    private static func maxValue(_ values: [Float], indices: [Int]) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        return indices.reduce(Float(0.0)) { partial, index in
            max(partial, values[index])
        }
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180.0 / .pi
    }

    private static func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

final class StreamingStabilizationAnalysisBuilder {
    private let context: MetalAnalysisContext
    private var frames: [StabilizerAnalysisFrame] = []
    private var motions: [PairMotion] = []
    private var previousFrameBuffer: MTLBuffer?
    private var sampleWidth: Int?
    private var sampleHeight: Int?

    init() throws {
        context = try MetalAnalysisContext()
    }

    var frameCount: Int {
        frames.count
    }

    func append(_ frame: StabilizerAnalysisFrame) throws {
        guard frame.pixels.count == frame.sampleWidth * frame.sampleHeight else {
            throw AutoStabilizationEstimator.metalError("Stabilizer streaming analysis frame pixels were unavailable.")
        }
        if let sampleWidth, let sampleHeight {
            guard frame.sampleWidth == sampleWidth, frame.sampleHeight == sampleHeight else {
                throw AutoStabilizationEstimator.metalError("Stabilizer streaming analysis frames used mixed sample sizes.")
            }
            if let previousFrameTime = frames.last?.time, frame.time <= previousFrameTime {
                throw AutoStabilizationEstimator.metalError("Stabilizer Host Analysis frames were not delivered in increasing time order.")
            }
        } else {
            sampleWidth = frame.sampleWidth
            sampleHeight = frame.sampleHeight
        }

        let currentFrameBuffer = try context.frameBuffer(for: frame)
        if let previousFrameBuffer {
            motions.append(try AutoStabilizationEstimator.pairMotion(
                context: context,
                previous: previousFrameBuffer,
                current: currentFrameBuffer,
                sampleWidth: frame.sampleWidth,
                sampleHeight: frame.sampleHeight
            ))
        } else {
            motions.append(PairMotion(
                dx: 0.0,
                dy: 0.0,
                residual: 0.0,
                signedRoll: 0.0,
                rollMotion: 0.0,
                yawProxy: 0.0,
                pitchProxy: 0.0,
                shearX: 0.0,
                shearY: 0.0,
                perspectiveX: 0.0,
                perspectiveY: 0.0
            ))
        }
        frames.append(frame.withoutRetainedPixels())
        previousFrameBuffer = currentFrameBuffer
    }

    func preparedAnalysis() throws -> StabilizerPreparedAnalysis? {
        guard frames.count >= 3 else {
            return nil
        }
        return try AutoStabilizationEstimator.preparedAnalysis(sortedFrames: frames, motions: motions)
    }
}
