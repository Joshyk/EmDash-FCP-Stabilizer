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
    var microConfidence: Float
    var bobConfidence: Float
    var acceptedBlockCount: Int32
    var totalBlockCount: Int32
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
        microConfidence: 0.0,
        bobConfidence: 0.0,
        acceptedBlockCount: 0,
        totalBlockCount: 0,
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
        microJitterX: 1.0,
        microJitterY: 1.0,
        microJitterRotation: 1.0,
        panStabilizationStrength: 0.8,
        walkingBob: 0.75
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
    let analysisConfidence: [Float]
    let acceptedBlockCounts: [Int32]
    let totalBlockCounts: [Int32]
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
    let analysisConfidence: Float
    let acceptedBlockCount: Int32
    let totalBlockCount: Int32
}

private struct StabilizerMotionBlock {
    let x0: Int
    let y0: Int
    let width: Int
    let height: Int
    let centerX: Float
    let centerY: Float
    let farFieldWeight: Float
}

private struct StabilizerBlockShift {
    let block: StabilizerMotionBlock
    let dx: Float
    let dy: Float
    let score: Float
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
    static let defaultSampleWidth = 720
    static let defaultSampleHeight = 54
    static let minimumSampleWidth = 32
    static let minimumSampleHeight = 24
    private static let globalSearchRadius = 16
    private static let localSearchRadius = 5
    private static let positionGain: Float = 0.85
    private static let rotationGain: Float = 0.65
    private static let microImpulseInnerRadius = 3
    private static let microImpulseOuterRadius = 12
    private static let minimumAcceptedMotionBlocks = 3
    private static let minimumFarFieldMotionBlocks = 3
    private static let motionPathJerkLimitMultiplier: Float = 4.0
    private static let minimumTranslationAccelerationLimit: Float = 0.75
    private static let minimumTranslationJerkLimit: Float = 0.5
    private static let minimumRotationAccelerationLimit: Float = 0.04
    private static let minimumRotationJerkLimit: Float = 0.03

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
                perspectiveY: 0.0,
                analysisConfidence: 1.0,
                acceptedBlockCount: 0,
                totalBlockCount: 0
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
        walkingBobWindowSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) throws -> StabilizerAutoTransform {
        let preparedAnalysis = try prepare(analysisFrames: frames)
        return estimate(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            walkingBobWindowSeconds: walkingBobWindowSeconds,
            strengths: strengths
        )
    }

    static func estimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
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
        let effectiveWalkingBobWindowSeconds = min(max(0.1, walkingBobWindowSeconds), smoothWindowSeconds)
        let walkingBobWindowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= effectiveWalkingBobWindowSeconds * 0.5 }
        let walkingBobActiveIndices = walkingBobWindowIndices.isEmpty ? [centerIndex] : Array(walkingBobWindowIndices)
        let footstepBaselineYPath = outerLinearPredictionPath(
            analysis.pathY,
            indices: activeIndices + walkingBobActiveIndices + [centerIndex],
            innerRadius: microImpulseInnerRadius,
            outerRadius: microImpulseOuterRadius
        )

        let turnSmoothX = timeWeightedMonotonicSCurveValue(
            analysis.pathX,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(analysis.pathX, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let turnIntentY = timeWeightedMonotonicSCurveValue(
            footstepBaselineYPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(footstepBaselineYPath, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let microImpulseBaselineX = outerLinearPrediction(
            analysis.pathX,
            centerIndex: centerIndex,
            innerRadius: microImpulseInnerRadius,
            outerRadius: microImpulseOuterRadius
        ) ?? analysis.pathX[centerIndex]
        let footstepBaselineY = footstepBaselineYPath[centerIndex]
        let microImpulseBaselineRoll = outerLinearPrediction(
            analysis.pathRoll,
            centerIndex: centerIndex,
            innerRadius: microImpulseInnerRadius,
            outerRadius: microImpulseOuterRadius
        ) ?? analysis.pathRoll[centerIndex]
        let bobSmoothY = timeWeightedAverage(
            footstepBaselineYPath,
            frames: frames,
            indices: walkingBobActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: effectiveWalkingBobWindowSeconds
        )

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let residual = maxValue(analysis.residuals, indices: activeIndices)
        let blurAmount = timeWeightedAverage(analysis.blurAmounts, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let motionConfidence = analysis.analysisConfidence.indices.contains(centerIndex) ? analysis.analysisConfidence[centerIndex] : 0.0
        let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(centerIndex) ? analysis.acceptedBlockCounts[centerIndex] : 0
        let totalBlockCount = analysis.totalBlockCounts.indices.contains(centerIndex) ? analysis.totalBlockCounts[centerIndex] : 0
        let confidence = clamp(1.0 - (residual * 1.2), min: 0.35, max: 1.0)
        let jitterConfidence = clamp((1.0 - (residual * 0.7)) * motionConfidence, min: 0.0, max: 1.0)
        let bobConfidence = clamp((1.0 - (residual * 0.4)) * motionConfidence, min: 0.0, max: 1.0)
        let panCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: confidence)
        let microXCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: jitterConfidence)
        let microYCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: jitterConfidence)
        let microRotationCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: jitterConfidence)
        let walkingBobCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.walkingBob, confidence: bobConfidence)
        let panBandX = microImpulseBaselineX - turnSmoothX
        let panBandY = bobSmoothY - turnIntentY
        let macroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrength
        let macroCompensationY = -panBandY * yScale * (positionGain * 0.5) * panCorrectionStrength
        let macroCompensationRotation: Float = 0.0
        let microCompensationX = -(analysis.pathX[centerIndex] - microImpulseBaselineX) * xScale * microXCorrectionStrength
        let microCompensationY = -(analysis.pathY[centerIndex] - footstepBaselineY) * yScale * microYCorrectionStrength
        let microCompensationRotation = -(analysis.pathRoll[centerIndex] - microImpulseBaselineRoll) * microRotationCorrectionStrength
        let walkingBobBandY = footstepBaselineY - bobSmoothY
        let walkingBobCompensationY = -walkingBobBandY * yScale * walkingBobCorrectionStrength
        let macroPixelOffset = vector_float2(macroCompensationX, macroCompensationY)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let walkingBobPixelOffset = vector_float2(0.0, walkingBobCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + walkingBobPixelOffset.y
        let compensationRotation = (macroCompensationRotation * confidence) + microCompensationRotation
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            walkingBobPixelOffset: walkingBobPixelOffset,
            rotationDegrees: compensationRotation,
            microConfidence: jitterConfidence,
            bobConfidence: bobConfidence,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            yawPitchProxy: vector_float2(0.0, 0.0),
            shear: vector_float2(0.0, 0.0),
            perspective: vector_float2(0.0, 0.0),
            blurAmount: blurAmount
        )
    }

    static func sampleSize(
        sourceWidth: Int,
        sourceHeight: Int,
        scalePercent: Double
    ) -> (width: Int, height: Int) {
        let sourceWidth = max(1, sourceWidth)
        let sourceHeight = max(1, sourceHeight)
        let normalizedPercent = clamp(Float(scalePercent), min: 10.0, max: 100.0)
        let scale = Double(normalizedPercent) / 100.0
        let width = min(sourceWidth, max(minimumSampleWidth, Int((Double(sourceWidth) * scale).rounded())))
        let height = min(sourceHeight, max(minimumSampleHeight, Int((Double(sourceHeight) * scale).rounded())))
        return (width: width, height: height)
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
        let rawPathX = cumulative(motions.map(\.dx))
        let rawPathY = cumulative(motions.map(\.dy))
        let rawPathRoll = cumulative(motions.map { radiansToDegrees($0.signedRoll) })
        let rawPathYaw = cumulative(motions.map(\.yawProxy))
        let rawPathPitch = cumulative(motions.map(\.pitchProxy))
        let rawPathShearX = cumulative(motions.map(\.shearX))
        let rawPathShearY = cumulative(motions.map(\.shearY))
        let rawPathPerspectiveX = cumulative(motions.map(\.perspectiveX))
        let rawPathPerspectiveY = cumulative(motions.map(\.perspectiveY))
        return StabilizerPreparedAnalysis(
            frames: sortedFrames.map { $0.withoutRetainedPixels() },
            residuals: motions.map(\.residual),
            rollMotion: motions.map(\.rollMotion),
            pathX: jerkLimitedMotionPath(rawPathX, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathY: jerkLimitedMotionPath(rawPathY, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathRoll: jerkLimitedMotionPath(rawPathRoll, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathYaw: jerkLimitedMotionPath(rawPathYaw, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathPitch: jerkLimitedMotionPath(rawPathPitch, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathShearX: jerkLimitedMotionPath(rawPathShearX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathShearY: jerkLimitedMotionPath(rawPathShearY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveX: jerkLimitedMotionPath(rawPathPerspectiveX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveY: jerkLimitedMotionPath(rawPathPerspectiveY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            analysisConfidence: motions.map(\.analysisConfidence),
            acceptedBlockCounts: motions.map(\.acceptedBlockCount),
            totalBlockCounts: motions.map(\.totalBlockCount),
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
            stride: 2,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let center = (round(global.dx), round(global.dy))
        let blocks = motionBlocks(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let blockShifts = try blocks.map { block -> StabilizerBlockShift in
            let shift = try estimateShift(
                context: context,
                previous: previous,
                current: current,
                x0: block.x0,
                y0: block.y0,
                width: block.width,
                height: block.height,
                radius: localSearchRadius,
                center: center,
                refine: true,
                stride: 1,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
            return StabilizerBlockShift(block: block, dx: shift.dx, dy: shift.dy, score: shift.score)
        }
        let acceptedBlocks = acceptedMotionBlocks(blockShifts, global: global)
        let motionBlocksForModel = acceptedBlocks.count >= minimumAcceptedMotionBlocks ? acceptedBlocks : blockShifts
        let robustDx = weightedMedian(motionBlocksForModel.map { ($0.dx, $0.block.farFieldWeight) }) ?? global.dx
        let robustDy = weightedMedian(motionBlocksForModel.map { ($0.dy, $0.block.farFieldWeight) }) ?? global.dy
        let rollCandidates = motionBlocksForModel.compactMap { shift -> Float? in
            let x = shift.block.centerX - (Float(sampleWidth) * 0.5)
            let y = shift.block.centerY - (Float(sampleHeight) * 0.5)
            let denominator = (x * x) + (y * y)
            guard denominator > 1.0 else {
                return nil
            }
            let u = shift.dx - robustDx
            let v = shift.dy - robustDy
            return ((x * v) - (y * u)) / denominator
        }
        let signedRoll = median(rollCandidates) ?? 0.0
        let rollMotion = rollCandidates.map { abs($0) }.max() ?? 0.0
        let acceptedCount = acceptedBlocks.count >= minimumAcceptedMotionBlocks ? acceptedBlocks.count : 0
        let farFieldAgreement = motionBlocksForModel.isEmpty ? 0.0 : average(motionBlocksForModel.map(\.block.farFieldWeight))
        let blockAgreement = blocks.isEmpty ? 0.0 : (Float(acceptedCount) / Float(blocks.count)) * clamp(farFieldAgreement, min: 0.35, max: 1.0)
        let scoreConfidence = clamp(1.0 - ((median(motionBlocksForModel.map(\.score)) ?? global.score) * 1.8), min: 0.0, max: 1.0)
        let analysisConfidence = clamp(blockAgreement * scoreConfidence, min: 0.0, max: 1.0)

        return PairMotion(
            dx: robustDx,
            dy: robustDy,
            residual: median(motionBlocksForModel.map(\.score)) ?? global.score,
            signedRoll: signedRoll,
            rollMotion: rollMotion,
            yawProxy: 0.0,
            pitchProxy: 0.0,
            shearX: 0.0,
            shearY: 0.0,
            perspectiveX: 0.0,
            perspectiveY: 0.0,
            analysisConfidence: analysisConfidence,
            acceptedBlockCount: Int32(acceptedCount),
            totalBlockCount: Int32(blocks.count)
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

    private static func motionBlocks(sampleWidth: Int, sampleHeight: Int) -> [StabilizerMotionBlock] {
        let horizontalMargin = min(8, max(2, sampleWidth / 12))
        let verticalMargin = min(6, max(2, sampleHeight / 10))
        let usableWidth = max(0, sampleWidth - (horizontalMargin * 2))
        let usableHeight = max(0, sampleHeight - (verticalMargin * 2))
        let columns = max(2, min(5, usableWidth / 18))
        let rows = max(2, min(4, usableHeight / 12))
        guard columns > 0, rows > 0 else {
            return []
        }

        var blocks: [StabilizerMotionBlock] = []
        for row in 0..<rows {
            let y0 = verticalMargin + ((usableHeight * row) / rows)
            let y1 = verticalMargin + ((usableHeight * (row + 1)) / rows)
            for column in 0..<columns {
                let x0 = horizontalMargin + ((usableWidth * column) / columns)
                let x1 = horizontalMargin + ((usableWidth * (column + 1)) / columns)
                let width = x1 - x0
                let height = y1 - y0
                guard width >= 18, height >= 12 else {
                    continue
                }
                let centerY = Float(y0) + (Float(height) * 0.5)
                blocks.append(StabilizerMotionBlock(
                    x0: x0,
                    y0: y0,
                    width: width,
                    height: height,
                    centerX: Float(x0) + (Float(width) * 0.5),
                    centerY: centerY,
                    farFieldWeight: farFieldWeight(centerY: centerY, sampleHeight: sampleHeight)
                ))
            }
        }
        return blocks
    }

    private static func farFieldWeight(centerY: Float, sampleHeight: Int) -> Float {
        let normalizedY = centerY / Float(max(1, sampleHeight))
        return clamp((0.82 - normalizedY) / 0.62, min: 0.20, max: 1.0)
    }

    private static func acceptedMotionBlocks(
        _ shifts: [StabilizerBlockShift],
        global: (dx: Float, dy: Float, score: Float)
    ) -> [StabilizerBlockShift] {
        guard shifts.count >= minimumAcceptedMotionBlocks else {
            return []
        }
        let finiteShifts = shifts.filter { $0.score.isFinite && $0.dx.isFinite && $0.dy.isFinite }
        guard finiteShifts.count >= minimumAcceptedMotionBlocks else {
            return []
        }
        let scoreMedian = median(finiteShifts.map(\.score)) ?? global.score
        let scoreLimit = max(scoreMedian * 1.8, scoreMedian + 0.025)
        let scoreFiltered = finiteShifts.filter { $0.score <= scoreLimit }
        guard scoreFiltered.count >= minimumAcceptedMotionBlocks else {
            return []
        }
        let farFieldFiltered = scoreFiltered.filter { $0.block.farFieldWeight >= 0.55 }
        let clusterCandidates = farFieldFiltered.count >= minimumFarFieldMotionBlocks ? farFieldFiltered : scoreFiltered
        let medianDx = weightedMedian(clusterCandidates.map { ($0.dx, $0.block.farFieldWeight) }) ?? global.dx
        let medianDy = weightedMedian(clusterCandidates.map { ($0.dy, $0.block.farFieldWeight) }) ?? global.dy
        let distances = clusterCandidates.map { hypotf($0.dx - medianDx, $0.dy - medianDy) }
        let medianDistance = median(distances) ?? 0.0
        let distanceLimit = max(1.25, medianDistance * 3.0)
        let accepted = clusterCandidates.filter {
            hypotf($0.dx - medianDx, $0.dy - medianDy) <= distanceLimit
        }
        guard accepted.count >= minimumAcceptedMotionBlocks else {
            return []
        }
        return accepted
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
        stride: UInt32,
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
            stride: max(1, stride)
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

    private static func jerkLimitedMotionPath(_ values: [Float], minimumAcceleration: Float, minimumJerk: Float) -> [Float] {
        guard values.count >= 4 else {
            return values
        }

        var accelerations: [Float] = []
        accelerations.reserveCapacity(values.count - 2)
        for index in 2..<values.count {
            let current = values[index]
            let previous = values[index - 1]
            let beforePrevious = values[index - 2]
            accelerations.append(current - (Float(2.0) * previous) + beforePrevious)
        }
        var jerks: [Float] = []
        jerks.reserveCapacity(max(0, accelerations.count - 1))
        for index in accelerations.indices.dropFirst() {
            jerks.append(accelerations[index] - accelerations[index - 1])
        }
        let accelerationMedian = median(accelerations.map { abs($0) }) ?? 0.0
        let jerkMedian = median(jerks.map { abs($0) }) ?? 0.0
        let accelerationLimit = max(minimumAcceleration, accelerationMedian * motionPathJerkLimitMultiplier)
        let jerkLimit = max(minimumJerk, jerkMedian * motionPathJerkLimitMultiplier)

        guard accelerationLimit.isFinite, jerkLimit.isFinite, accelerationLimit > 0.0, jerkLimit > 0.0 else {
            return values
        }

        var limited = values
        for index in 1..<(values.count - 1) {
            let previousAcceleration = index >= 2
                ? values[index - 1] - (Float(2.0) * values[index - 2]) + values[index - 3]
                : Float(0.0)
            let currentAcceleration = values[index + 1] - (Float(2.0) * values[index]) + values[index - 1]
            let nextAcceleration = index + 2 < values.count
                ? values[index + 2] - (Float(2.0) * values[index + 1]) + values[index]
                : Float(0.0)
            let localJerk = max(abs(currentAcceleration - previousAcceleration), abs(nextAcceleration - currentAcceleration))
            let accelerationExceeded = abs(currentAcceleration) > accelerationLimit
            let jerkExceeded = localJerk > jerkLimit
            guard accelerationExceeded || jerkExceeded else {
                continue
            }

            let localLinearPrediction = (values[index - 1] + values[index + 1]) * 0.5
            let maxCorrection = max(accelerationLimit, jerkLimit)
            let correction = clamp(
                localLinearPrediction - values[index],
                min: Float(0.0) - maxCorrection,
                max: maxCorrection
            )
            limited[index] = values[index] + (correction * 0.85)
        }

        let endError = limited[limited.count - 1] - values[values.count - 1]
        guard abs(endError) > Float.ulpOfOne else {
            return limited
        }
        let denominator = Float(max(1, limited.count - 1))
        for index in limited.indices {
            let progress = Float(index) / denominator
            limited[index] -= endError * progress
        }
        return limited
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

    private static func average(_ values: [Float]) -> Float {
        guard !values.isEmpty else {
            return 0.0
        }
        return values.reduce(Float(0.0), +) / Float(values.count)
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

    private static func surroundingIndicesExcludingCenter(around centerIndex: Int, innerRadius: Int, outerRadius: Int, inCount count: Int) -> [Int] {
        guard count > 0 else {
            return []
        }
        let outerStart = Swift.max(0, centerIndex - outerRadius)
        let outerEnd = Swift.min(count - 1, centerIndex + outerRadius)
        let innerStart = Swift.max(0, centerIndex - innerRadius)
        let innerEnd = Swift.min(count - 1, centerIndex + innerRadius)
        let indices = (outerStart...outerEnd).filter { index in
            index < innerStart || index > innerEnd
        }
        if indices.count >= 3 {
            return indices
        }
        return centeredIndices(around: centerIndex, radius: outerRadius, inCount: count)
    }

    private static func outerLinearPrediction(_ values: [Float], centerIndex: Int, innerRadius: Int, outerRadius: Int) -> Float? {
        guard !values.isEmpty else {
            return nil
        }
        let preEnd = Swift.max(0, centerIndex - innerRadius)
        let preStart = Swift.max(0, centerIndex - outerRadius)
        let postStart = Swift.min(values.count, centerIndex + innerRadius + 1)
        let postEnd = Swift.min(values.count, centerIndex + outerRadius + 1)
        var points: [(x: Float, y: Float)] = []
        if preStart < preEnd {
            for index in preStart..<preEnd {
                points.append((x: Float(index - centerIndex), y: values[index]))
            }
        }
        if postStart < postEnd {
            for index in postStart..<postEnd {
                points.append((x: Float(index - centerIndex), y: values[index]))
            }
        }
        guard points.count >= 3 else {
            let indices = surroundingIndicesExcludingCenter(
                around: centerIndex,
                innerRadius: Swift.max(1, innerRadius),
                outerRadius: outerRadius,
                inCount: values.count
            )
            return median(values, indices: indices)
        }

        let count = Float(points.count)
        let sumX = points.reduce(Float(0.0)) { $0 + $1.x }
        let sumY = points.reduce(Float(0.0)) { $0 + $1.y }
        let sumXX = points.reduce(Float(0.0)) { $0 + ($1.x * $1.x) }
        let sumXY = points.reduce(Float(0.0)) { $0 + ($1.x * $1.y) }
        let denominator = (count * sumXX) - (sumX * sumX)
        guard abs(denominator) > Float.ulpOfOne else {
            return sumY / count
        }
        return ((sumY * sumXX) - (sumX * sumXY)) / denominator
    }

    private static func outerLinearPredictionPath(_ values: [Float], indices: [Int], innerRadius: Int, outerRadius: Int) -> [Float] {
        guard !values.isEmpty else {
            return values
        }
        var predictedValues = values
        for index in Set(indices) where values.indices.contains(index) {
            predictedValues[index] = outerLinearPrediction(
                values,
                centerIndex: index,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            ) ?? values[index]
        }
        return predictedValues
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

    private static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else {
            return nil
        }
        let sortedValues = values.sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[middle - 1] + sortedValues[middle]) * 0.5
        }
        return sortedValues[middle]
    }

    private static func weightedMedian(_ values: [(value: Float, weight: Float)]) -> Float? {
        let finiteValues = values
            .filter { $0.value.isFinite && $0.weight.isFinite && $0.weight > 0.0 }
            .sorted { $0.value < $1.value }
        guard !finiteValues.isEmpty else {
            return nil
        }
        let totalWeight = finiteValues.reduce(Float(0.0)) { $0 + $1.weight }
        let midpoint = totalWeight * 0.5
        var runningWeight: Float = 0.0
        for entry in finiteValues {
            runningWeight += entry.weight
            if runningWeight >= midpoint {
                return entry.value
            }
        }
        return finiteValues.last?.value
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

    private static func timeWeightedMonotonicSCurveValue(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        centerTime: Double,
        windowSeconds: Double
    ) -> Float? {
        guard indices.count >= 3 else {
            return nil
        }
        let sortedIndices = indices.sorted()
        guard let firstIndex = sortedIndices.first, let lastIndex = sortedIndices.last else {
            return nil
        }

        var positiveTravel: Float = 0.0
        var negativeTravel: Float = 0.0
        for position in 1..<sortedIndices.count {
            let previousValue = values[sortedIndices[position - 1]]
            let currentValue = values[sortedIndices[position]]
            let delta = currentValue - previousValue
            if delta >= 0.0 {
                positiveTravel += delta
            } else {
                negativeTravel += -delta
            }
        }

        let totalTravel = positiveTravel + negativeTravel
        guard totalTravel > 0.5 else {
            return nil
        }

        let endpointDelta = values[lastIndex] - values[firstIndex]
        let dominantTravel = max(positiveTravel, negativeTravel)
        let dominantRatio = dominantTravel / max(totalTravel, Float.ulpOfOne)
        guard dominantRatio >= 0.62 || abs(endpointDelta) >= dominantTravel * 0.35 else {
            return nil
        }

        let direction: Float
        if abs(endpointDelta) >= dominantTravel * 0.2 {
            direction = endpointDelta >= 0.0 ? 1.0 : -1.0
        } else {
            direction = positiveTravel >= negativeTravel ? 1.0 : -1.0
        }

        let monotonicStart = values[firstIndex] * direction
        var monotonicEnd = monotonicStart
        for index in sortedIndices.dropFirst() {
            monotonicEnd = max(monotonicEnd, values[index] * direction)
        }

        let monotonicTravel = monotonicEnd - monotonicStart
        guard monotonicTravel > 0.5 else {
            return nil
        }

        let firstTime = frames[firstIndex].time
        let lastTime = frames[lastIndex].time
        let windowStart = centerTime - (windowSeconds * 0.5)
        let windowEnd = centerTime + (windowSeconds * 0.5)
        let intentStartTime = max(firstTime, windowStart)
        let intentEndTime = min(lastTime, windowEnd)
        let duration = intentEndTime - intentStartTime
        guard duration > 1e-6 else {
            return nil
        }

        let normalizedTime = clamp(Float((centerTime - intentStartTime) / duration), min: 0.0, max: 1.0)
        let progress = smootherStep(normalizedTime)
        return (monotonicStart + (monotonicTravel * progress)) * direction
    }

    private static func smootherStep(_ value: Float) -> Float {
        let t = clamp(value, min: 0.0, max: 1.0)
        return t * t * t * (t * ((t * 6.0) - 15.0) + 10.0)
    }

    private static func timeWeightedOuterLinearPredictionAverage(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        centerTime: Double,
        windowSeconds: Double,
        innerRadius: Int,
        outerRadius: Int
    ) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        guard indices.count > 1 else {
            return outerLinearPrediction(
                values,
                centerIndex: indices[0],
                innerRadius: innerRadius,
                outerRadius: outerRadius
            ) ?? values[indices[0]]
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
            let predictedValue = outerLinearPrediction(
                values,
                centerIndex: index,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            ) ?? values[index]
            weightedTotal += predictedValue * Float(weight)
            totalWeight += weight
        }

        guard totalWeight > 1e-9 else {
            let predictedValues = indices.map {
                outerLinearPrediction(values, centerIndex: $0, innerRadius: innerRadius, outerRadius: outerRadius) ?? values[$0]
            }
            return predictedValues.reduce(Float(0.0), +) / Float(predictedValues.count)
        }
        return weightedTotal / Float(totalWeight)
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

    private static func confidenceCompensatedCorrectionFactor(_ strength: Double, confidence: Float) -> Float {
        let requestedRemoval = max(0.0, Float(strength))
        return clamp(requestedRemoval * confidence, min: 0.0, max: 1.0)
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
                perspectiveY: 0.0,
                analysisConfidence: 1.0,
                acceptedBlockCount: 0,
                totalBlockCount: 0
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
