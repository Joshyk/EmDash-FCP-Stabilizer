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
    var strideWobblePixelOffset: vector_float2
    var walkingBobPixelOffset: vector_float2
    var footstepJitterRotationDegrees: Float
    var strideWobbleRotationDegrees: Float
    var rotationDegrees: Float
    var rawPixelOffset: vector_float2
    var rawRotationDegrees: Float
    var temporalSmoothingPixelDelta: vector_float2
    var temporalSmoothingRotationDelta: Float
    var temporalSmoothingSampleCount: Int32
    var temporalSmoothingWindowSeconds: Float
    var effectiveMicroJitterStrength: vector_float3
    var effectiveStrideWobbleStrength: vector_float3
    var warpConfidence: Float
    var microConfidence: Float
    var strideConfidence: Float
    var bobConfidence: Float
    var turnConfidence: Float
    var acceptedBlockCount: Int32
    var totalBlockCount: Int32
    var yawPitchProxy: vector_float2
    var shear: vector_float2
    var perspective: vector_float2
    var blurAmount: Float
    var trackingConfidence: Float
    var motionConfidence: Float
    var residual: Float
    var footstepImpulse: vector_float3
    var searchRadiusHitCount: Int32
    var searchRadiusTotalCount: Int32

    static let identity = StabilizerAutoTransform(
        pixelOffset: vector_float2(0.0, 0.0),
        macroPixelOffset: vector_float2(0.0, 0.0),
        microPixelOffset: vector_float2(0.0, 0.0),
        strideWobblePixelOffset: vector_float2(0.0, 0.0),
        walkingBobPixelOffset: vector_float2(0.0, 0.0),
        footstepJitterRotationDegrees: 0.0,
        strideWobbleRotationDegrees: 0.0,
        rotationDegrees: 0.0,
        rawPixelOffset: vector_float2(0.0, 0.0),
        rawRotationDegrees: 0.0,
        temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
        temporalSmoothingRotationDelta: 0.0,
        temporalSmoothingSampleCount: 0,
        temporalSmoothingWindowSeconds: 0.0,
        effectiveMicroJitterStrength: vector_float3(0.0, 0.0, 0.0),
        effectiveStrideWobbleStrength: vector_float3(0.0, 0.0, 0.0),
        warpConfidence: 0.0,
        microConfidence: 0.0,
        strideConfidence: 0.0,
        bobConfidence: 0.0,
        turnConfidence: 0.0,
        acceptedBlockCount: 0,
        totalBlockCount: 0,
        yawPitchProxy: vector_float2(0.0, 0.0),
        shear: vector_float2(0.0, 0.0),
        perspective: vector_float2(0.0, 0.0),
        blurAmount: 0.0,
        trackingConfidence: 0.0,
        motionConfidence: 0.0,
        residual: 0.0,
        footstepImpulse: vector_float3(0.0, 0.0, 0.0),
        searchRadiusHitCount: 0,
        searchRadiusTotalCount: 0
    )
}

struct StabilizerCorrectionStrengths {
    let microJitterX: Double
    let microJitterY: Double
    let microJitterRotation: Double
    let strideWobbleX: Double
    let strideWobbleY: Double
    let strideWobbleRotation: Double
    let panStabilizationStrength: Double
    let walkingBob: Double
    let farFieldWarp: Double

    static let defaultStrengths = StabilizerCorrectionStrengths(
        microJitterX: 1.0,
        microJitterY: 1.0,
        microJitterRotation: 1.0,
        strideWobbleX: 0.65,
        strideWobbleY: 0.35,
        strideWobbleRotation: 0.75,
        panStabilizationStrength: 0.8,
        walkingBob: 0.75,
        farFieldWarp: 1.0
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
    let footstepPathX: [Float]
    let footstepPathY: [Float]
    let footstepPathRoll: [Float]
    let pathYaw: [Float]
    let pathPitch: [Float]
    let pathShearX: [Float]
    let pathShearY: [Float]
    let pathPerspectiveX: [Float]
    let pathPerspectiveY: [Float]
    let analysisConfidence: [Float]
    let warpConfidence: [Float]
    let acceptedBlockCounts: [Int32]
    let totalBlockCounts: [Int32]
    let blurAmounts: [Float]
    let searchRadiusHitCounts: [Int32]
    let searchRadiusTotalCounts: [Int32]
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
    let warpConfidence: Float
    let acceptedBlockCount: Int32
    let totalBlockCount: Int32
    let searchRadiusHitCount: Int32
    let searchRadiusTotalCount: Int32
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
    let searchRadiusHit: Bool
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
    private static let positionGain: Float = 1.0
    private static let rotationGain: Float = 1.0
    private static let baseTurnSmoothingOffsetLimitX: Float = 0.08
    private static let extraTurnSmoothingOffsetLimitX: Float = 0.06
    private static let renderTemporalSmoothingSampleCount = 21
    private static let renderTemporalSmoothingWindowSeconds = 1.20
    private static let footstepImpulseFullScalePixels: Float = 0.35
    private static let footstepImpulseFullScaleDegrees: Float = 0.08
    private static let footstepNoiseFloorScale: Float = 0.08
    private static let footstepSurroundingNoiseMultiplier: Float = 1.25
    private static let footstepFullResponseScale: Float = 0.82
    private static let strideWobbleWindowSeconds = 2.0
    private static let strideWobbleFullScalePixels: Float = 0.75
    private static let strideWobbleFullScaleDegrees: Float = 0.16
    private static let walkingBobFullScalePixels: Float = 0.65
    private static let turnSmoothingFullScalePixels: Float = 2.0
    private static let maxFarFieldShear: Float = 0.008
    private static let maxFarFieldYawPitchProxy: Float = 0.004
    private static let maxFarFieldPerspective: Float = 0.003
    private static let maxRenderedFarFieldShear: Float = 0.004
    private static let maxRenderedFarFieldYawPitchProxy: Float = 0.0025
    private static let maxRenderedFarFieldPerspective: Float = 0.0015
    private static let farFieldWarpTrackingGateStart: Float = 0.30
    private static let farFieldWarpTrackingGateFull: Float = 0.50
    private static let farFieldWarpEdgeQualityGateStart: Float = 0.55
    private static let farFieldWarpEdgeQualityGateFull: Float = 0.86
    private static let footstepImpulseInnerWindowSeconds = 0.10
    private static let footstepImpulseOuterWindowSeconds = 1.0
    private static let farFieldWarpInnerWindowSeconds = 0.10
    private static let farFieldWarpOuterWindowSeconds = 1.0
    private static let fixedWalkingBobWindowSeconds = 2.5
    private static let timeWindowSelectionEpsilon = 0.001
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
                warpConfidence: 0.0,
                acceptedBlockCount: 0,
                totalBlockCount: 0,
                searchRadiusHitCount: 0,
                searchRadiusTotalCount: 0
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
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) throws -> StabilizerAutoTransform {
        let preparedAnalysis = try prepare(analysisFrames: frames)
        return estimate(
            preparedAnalysis: preparedAnalysis,
            renderTime: renderTime,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
    }

    static func estimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> StabilizerAutoTransform {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return .identity
        }

        return temporallySmoothedEstimate(
            preparedAnalysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
    }

    private static func rawEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return .identity
        }

        let effectiveStrideWobbleWindowSeconds = strideWobbleWindowSeconds
        let effectiveWalkingBobWindowSeconds = fixedWalkingBobWindowSeconds
        let smoothWindowSeconds = max(effectiveStrideWobbleWindowSeconds, panSmoothSeconds)
        let centerIndex = closestFrameIndex(to: renderSeconds, in: frames)
        let frameInterpolation = frameInterpolation(at: renderSeconds, in: frames)
        let windowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= smoothWindowSeconds * 0.5 }
        let activeIndices = windowIndices.isEmpty ? Array(frames.indices) : Array(windowIndices)
        let strideWobbleWindowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= effectiveStrideWobbleWindowSeconds * 0.5 }
        let strideWobbleActiveIndices = strideWobbleWindowIndices.isEmpty ? [centerIndex] : Array(strideWobbleWindowIndices)
        let walkingBobWindowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= effectiveWalkingBobWindowSeconds * 0.5 }
        let walkingBobActiveIndices = walkingBobWindowIndices.isEmpty ? [centerIndex] : Array(walkingBobWindowIndices)
        let sampledIndices = activeIndices + strideWobbleActiveIndices + walkingBobActiveIndices + [centerIndex] + frameInterpolation.indices
        let footstepBaselineXPath = outerLinearPredictionPath(
            analysis.footstepPathX,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds
        )
        let footstepBaselineYPath = outerLinearPredictionPath(
            analysis.footstepPathY,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds
        )
        let footstepBaselineRollPath = outerLinearPredictionPath(
            analysis.footstepPathRoll,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds
        )
        let farFieldBaselineYawPath = outerLinearPredictionPath(
            analysis.pathYaw,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )
        let farFieldBaselinePitchPath = outerLinearPredictionPath(
            analysis.pathPitch,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )
        let farFieldBaselineShearXPath = outerLinearPredictionPath(
            analysis.pathShearX,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )
        let farFieldBaselineShearYPath = outerLinearPredictionPath(
            analysis.pathShearY,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )
        let farFieldBaselinePerspectiveXPath = outerLinearPredictionPath(
            analysis.pathPerspectiveX,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )
        let farFieldBaselinePerspectiveYPath = outerLinearPredictionPath(
            analysis.pathPerspectiveY,
            frames: frames,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds
        )

        let footstepCleanXPath = footstepBaselineXPath
        let footstepCleanYPath = footstepBaselineYPath
        let footstepCleanRollPath = footstepBaselineRollPath
        let strideSmoothedXPath = locallyTimeWeightedAveragePath(
            footstepCleanXPath,
            frames: frames,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let strideSmoothedYPath = locallyTimeWeightedAveragePath(
            footstepCleanYPath,
            frames: frames,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let strideSmoothedRollPath = locallyTimeWeightedAveragePath(
            footstepCleanRollPath,
            frames: frames,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )

        let turnSmoothX = timeWeightedMonotonicSCurveValue(
            strideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(strideSmoothedXPath, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let footstepCleanXAtRender = interpolatedValue(footstepCleanXPath, using: frameInterpolation)
        let footstepCleanYAtRender = interpolatedValue(footstepCleanYPath, using: frameInterpolation)
        let footstepCleanRollAtRender = interpolatedValue(footstepCleanRollPath, using: frameInterpolation)
        let footstepPathXAtRender = interpolatedValue(analysis.footstepPathX, using: frameInterpolation)
        let footstepPathYAtRender = interpolatedValue(analysis.footstepPathY, using: frameInterpolation)
        let footstepPathRollAtRender = interpolatedValue(analysis.footstepPathRoll, using: frameInterpolation)
        let microImpulseBaselineX = interpolatedValue(footstepBaselineXPath, using: frameInterpolation)
        let footstepBaselineY = interpolatedValue(footstepBaselineYPath, using: frameInterpolation)
        let microImpulseBaselineRoll = interpolatedValue(footstepBaselineRollPath, using: frameInterpolation)
        let strideSmoothX = interpolatedValue(strideSmoothedXPath, using: frameInterpolation)
        let strideSmoothY = interpolatedValue(strideSmoothedYPath, using: frameInterpolation)
        let strideSmoothRoll = interpolatedValue(strideSmoothedRollPath, using: frameInterpolation)
        let bobSmoothY = timeWeightedAverage(
            strideSmoothedYPath,
            frames: frames,
            indices: walkingBobActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: effectiveWalkingBobWindowSeconds
        )

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let turnResidual = percentileValue(analysis.residuals, indices: activeIndices, percentile: 0.75)
        let strideResidual = percentileValue(analysis.residuals, indices: strideWobbleActiveIndices, percentile: 0.70)
        let bobResidual = percentileValue(analysis.residuals, indices: walkingBobActiveIndices, percentile: 0.70)
        let centerResidual = interpolatedValue(analysis.residuals, using: frameInterpolation)
        let blurAmount = timeWeightedAverage(analysis.blurAmounts, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let centerBlurAmount = interpolatedValue(analysis.blurAmounts, using: frameInterpolation)
        let motionConfidence = interpolatedValue(analysis.analysisConfidence, using: frameInterpolation)
        let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(centerIndex) ? analysis.acceptedBlockCounts[centerIndex] : 0
        let totalBlockCount = analysis.totalBlockCounts.indices.contains(centerIndex) ? analysis.totalBlockCounts[centerIndex] : 0
        let searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(centerIndex) ? analysis.searchRadiusHitCounts[centerIndex] : 0
        let searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(centerIndex) ? analysis.searchRadiusTotalCounts[centerIndex] : 0
        let warpConfidence = analysis.warpConfidence.indices.contains(centerIndex) ? analysis.warpConfidence[centerIndex] : 0.0
        let trackingConfidence = frameTrackingConfidence(
            motionConfidence: motionConfidence,
            residual: centerResidual,
            blurAmount: centerBlurAmount,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount
        )
        let footstepXConfidence = footstepFrameConfidence(
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepYConfidence = footstepFrameConfidence(
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepRollConfidence = footstepFrameConfidence(
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: footstepImpulseFullScaleDegrees
        )
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideBandX = footstepCleanXAtRender - strideSmoothX
        let strideBandY = footstepCleanYAtRender - strideSmoothY
        let strideBandRoll = footstepCleanRollAtRender - strideSmoothRoll
        let panBandX = strideSmoothX - turnSmoothX
        let walkingBobBandY = strideSmoothY - bobSmoothY
        let strideTrackingConfidence = residualAdjustedTrackingConfidence(trackingConfidence, residual: strideResidual, multiplier: 0.6)
        let strideXConfidence = strideWobbleConfidence(
            bandValue: strideBandX,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScalePixels
        )
        let strideYConfidence = strideWobbleConfidence(
            bandValue: strideBandY,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScalePixels
        )
        let strideRollConfidence = strideWobbleConfidence(
            bandValue: strideBandRoll,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScaleDegrees
        )
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let turnTrackingConfidence = residualAdjustedTrackingConfidence(trackingConfidence, residual: turnResidual, multiplier: 0.9)
        let confidence = turnSmoothingConfidence(
            bandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let bobWindowSupport = symmetricWindowSupport(
            frames: frames,
            centerTime: renderSeconds,
            windowSeconds: effectiveWalkingBobWindowSeconds
        )
        let bobTrackingConfidence = residualAdjustedTrackingConfidence(trackingConfidence, residual: bobResidual, multiplier: 0.4)
        let bobConfidence = walkingBobConfidence(
            bandValue: walkingBobBandY,
            trackingConfidence: bobTrackingConfidence,
            windowSupport: bobWindowSupport
        )
        let panCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: confidence)
        let microXCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence)
        let microYCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence)
        let microRotationCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence)
        let strideYCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence)
        let strideRotationCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
        let walkingBobCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.walkingBob, confidence: bobConfidence)
        let rawMacroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrength
        let macroCompensationX = softLimit(
            rawMacroCompensationX,
            limit: turnSmoothingOffsetLimit(
                outputPixels: outputSize.x,
                baseFraction: baseTurnSmoothingOffsetLimitX,
                extraFraction: extraTurnSmoothingOffsetLimitX,
                strength: strengths.panStabilizationStrength
            )
        )
        let macroCompensationY: Float = 0.0
        let macroCompensationRotation: Float = 0.0
        let microCompensationX = -(footstepPathXAtRender - microImpulseBaselineX) * xScale * microXCorrectionStrength
        let microCompensationY = -(footstepPathYAtRender - footstepBaselineY) * yScale * microYCorrectionStrength
        let microCompensationRotation = -(footstepPathRollAtRender - microImpulseBaselineRoll) * microRotationCorrectionStrength
        let footstepImpulse = vector_float3(
            footstepPathXAtRender - microImpulseBaselineX,
            footstepPathYAtRender - footstepBaselineY,
            footstepPathRollAtRender - microImpulseBaselineRoll
        )
        let strideCompensationX = -strideBandX * xScale * strideXCorrectionStrength
        let strideCompensationY = -strideBandY * yScale * strideYCorrectionStrength
        let strideCompensationRotation = -strideBandRoll * strideRotationCorrectionStrength
        let walkingBobCompensationY = -walkingBobBandY * yScale * walkingBobCorrectionStrength
        let macroPixelOffset = vector_float2(macroCompensationX, macroCompensationY)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let strideWobblePixelOffset = vector_float2(strideCompensationX, strideCompensationY)
        let walkingBobPixelOffset = vector_float2(0.0, walkingBobCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x + strideWobblePixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + strideWobblePixelOffset.y + walkingBobPixelOffset.y
        let compensationRotation = (macroCompensationRotation * confidence) + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrength = clamp(Float(strengths.farFieldWarp), min: 0.0, max: 4.0)
        let farFieldWarpGate = farFieldWarpRenderGate(
            warpConfidence: warpConfidence,
            trackingConfidence: trackingConfidence,
            searchRadiusHitCount: searchRadiusHitCount,
            searchRadiusTotalCount: searchRadiusTotalCount
        )
        let appliedWarpConfidence = clamp(warpConfidence * farFieldWarpGate, min: 0.0, max: 1.0)
        let yawPitchProxy = vector_float2(
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathYaw,
                    baselineValues: farFieldBaselineYawPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldYawPitchProxy * farFieldWarpStrength,
                max: maxRenderedFarFieldYawPitchProxy * farFieldWarpStrength
            ),
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathPitch,
                    baselineValues: farFieldBaselinePitchPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldYawPitchProxy * farFieldWarpStrength,
                max: maxRenderedFarFieldYawPitchProxy * farFieldWarpStrength
            )
        )
        let shear = vector_float2(
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathShearX,
                    baselineValues: farFieldBaselineShearXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldShear * farFieldWarpStrength,
                max: maxRenderedFarFieldShear * farFieldWarpStrength
            ),
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathShearY,
                    baselineValues: farFieldBaselineShearYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldShear * farFieldWarpStrength,
                max: maxRenderedFarFieldShear * farFieldWarpStrength
            )
        )
        let perspective = vector_float2(
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathPerspectiveX,
                    baselineValues: farFieldBaselinePerspectiveXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldPerspective * farFieldWarpStrength,
                max: maxRenderedFarFieldPerspective * farFieldWarpStrength
            ),
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathPerspectiveY,
                    baselineValues: farFieldBaselinePerspectiveYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    confidence: farFieldWarpGate
                ),
                min: -maxRenderedFarFieldPerspective * farFieldWarpStrength,
                max: maxRenderedFarFieldPerspective * farFieldWarpStrength
            )
        )
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: strideWobblePixelOffset,
            walkingBobPixelOffset: walkingBobPixelOffset,
            footstepJitterRotationDegrees: microCompensationRotation,
            strideWobbleRotationDegrees: strideCompensationRotation,
            rotationDegrees: compensationRotation,
            rawPixelOffset: vector_float2(compensationX, compensationY),
            rawRotationDegrees: compensationRotation,
            temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
            temporalSmoothingRotationDelta: 0.0,
            temporalSmoothingSampleCount: 1,
            temporalSmoothingWindowSeconds: 0.0,
            effectiveMicroJitterStrength: vector_float3(
                microXCorrectionStrength,
                microYCorrectionStrength,
                microRotationCorrectionStrength
            ),
            effectiveStrideWobbleStrength: vector_float3(
                strideXCorrectionStrength,
                strideYCorrectionStrength,
                strideRotationCorrectionStrength
            ),
            warpConfidence: appliedWarpConfidence,
            microConfidence: jitterConfidence,
            strideConfidence: strideConfidence,
            bobConfidence: bobConfidence,
            turnConfidence: confidence,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            yawPitchProxy: yawPitchProxy,
            shear: shear,
            perspective: perspective,
            blurAmount: blurAmount,
            trackingConfidence: trackingConfidence,
            motionConfidence: motionConfidence,
            residual: centerResidual,
            footstepImpulse: footstepImpulse,
            searchRadiusHitCount: searchRadiusHitCount,
            searchRadiusTotalCount: searchRadiusTotalCount
        )
    }

    private static func temporallySmoothedEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return .identity
        }

        let firstTime = frames[0].time
        let lastTime = frames[frames.count - 1].time
        let rawCenterTransform = rawEstimate(
            preparedAnalysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
        let sampleCount = max(3, renderTemporalSmoothingSampleCount)
        let centerSample = sampleCount / 2
        let halfWindow = renderTemporalSmoothingWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = renderTemporalSmoothingWindowSeconds / denominator
        let sigma = max(1e-6, halfWindow * 0.5)
        var weightedSamples: [(transform: StabilizerAutoTransform, weight: Float)] = []

        for sampleIndex in 0..<sampleCount {
            let offset = (Double(sampleIndex - centerSample) * sampleStep)
            let sampleSeconds = renderSeconds + offset
            guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let transform = rawEstimate(
                preparedAnalysis: analysis,
                renderSeconds: sampleSeconds,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
            weightedSamples.append((transform: transform, weight: weight))
        }

        guard !weightedSamples.isEmpty else {
            return rawCenterTransform
        }
        var smoothedTransform = weightedAverageTransform(weightedSamples)
        smoothedTransform.microPixelOffset = rawCenterTransform.microPixelOffset
        smoothedTransform.footstepJitterRotationDegrees = rawCenterTransform.footstepJitterRotationDegrees
        smoothedTransform.effectiveMicroJitterStrength = rawCenterTransform.effectiveMicroJitterStrength
        smoothedTransform.microConfidence = rawCenterTransform.microConfidence
        smoothedTransform.turnConfidence = rawCenterTransform.turnConfidence
        smoothedTransform.trackingConfidence = rawCenterTransform.trackingConfidence
        smoothedTransform.motionConfidence = rawCenterTransform.motionConfidence
        smoothedTransform.residual = rawCenterTransform.residual
        smoothedTransform.footstepImpulse = rawCenterTransform.footstepImpulse
        smoothedTransform.searchRadiusHitCount = rawCenterTransform.searchRadiusHitCount
        smoothedTransform.searchRadiusTotalCount = rawCenterTransform.searchRadiusTotalCount
        smoothedTransform.pixelOffset = smoothedTransform.macroPixelOffset
            + smoothedTransform.microPixelOffset
            + smoothedTransform.strideWobblePixelOffset
            + smoothedTransform.walkingBobPixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
        smoothedTransform.rawPixelOffset = rawCenterTransform.pixelOffset
        smoothedTransform.rawRotationDegrees = rawCenterTransform.rotationDegrees
        smoothedTransform.temporalSmoothingPixelDelta = smoothedTransform.pixelOffset - rawCenterTransform.pixelOffset
        smoothedTransform.temporalSmoothingRotationDelta = smoothedTransform.rotationDegrees - rawCenterTransform.rotationDegrees
        smoothedTransform.temporalSmoothingSampleCount = Int32(weightedSamples.count)
        smoothedTransform.temporalSmoothingWindowSeconds = Float(renderTemporalSmoothingWindowSeconds)
        return smoothedTransform
    }

    private static func weightedAverageTransform(
        _ samples: [(transform: StabilizerAutoTransform, weight: Float)]
    ) -> StabilizerAutoTransform {
        let totalWeight = samples.reduce(Float(0.0)) { partial, sample in
            partial + sample.weight
        }
        guard totalWeight > 0.0 else {
            return .identity
        }

        func vectorAverage(_ keyPath: KeyPath<StabilizerAutoTransform, vector_float2>) -> vector_float2 {
            samples.reduce(vector_float2(0.0, 0.0)) { partial, sample in
                partial + (sample.transform[keyPath: keyPath] * sample.weight)
            } / totalWeight
        }

        func vector3Average(_ keyPath: KeyPath<StabilizerAutoTransform, vector_float3>) -> vector_float3 {
            samples.reduce(vector_float3(0.0, 0.0, 0.0)) { partial, sample in
                partial + (sample.transform[keyPath: keyPath] * sample.weight)
            } / totalWeight
        }

        func floatAverage(_ keyPath: KeyPath<StabilizerAutoTransform, Float>) -> Float {
            samples.reduce(Float(0.0)) { partial, sample in
                partial + (sample.transform[keyPath: keyPath] * sample.weight)
            } / totalWeight
        }

        let acceptedBlockCount = samples.reduce(Float(0.0)) { partial, sample in
            partial + (Float(sample.transform.acceptedBlockCount) * sample.weight)
        } / totalWeight
        let totalBlockCount = samples.reduce(Float(0.0)) { partial, sample in
            partial + (Float(sample.transform.totalBlockCount) * sample.weight)
        } / totalWeight

        return StabilizerAutoTransform(
            pixelOffset: vectorAverage(\.pixelOffset),
            macroPixelOffset: vectorAverage(\.macroPixelOffset),
            microPixelOffset: vectorAverage(\.microPixelOffset),
            strideWobblePixelOffset: vectorAverage(\.strideWobblePixelOffset),
            walkingBobPixelOffset: vectorAverage(\.walkingBobPixelOffset),
            footstepJitterRotationDegrees: floatAverage(\.footstepJitterRotationDegrees),
            strideWobbleRotationDegrees: floatAverage(\.strideWobbleRotationDegrees),
            rotationDegrees: floatAverage(\.rotationDegrees),
            rawPixelOffset: vectorAverage(\.rawPixelOffset),
            rawRotationDegrees: floatAverage(\.rawRotationDegrees),
            temporalSmoothingPixelDelta: vectorAverage(\.temporalSmoothingPixelDelta),
            temporalSmoothingRotationDelta: floatAverage(\.temporalSmoothingRotationDelta),
            temporalSmoothingSampleCount: Int32(samples.count),
            temporalSmoothingWindowSeconds: 0.0,
            effectiveMicroJitterStrength: vector3Average(\.effectiveMicroJitterStrength),
            effectiveStrideWobbleStrength: vector3Average(\.effectiveStrideWobbleStrength),
            warpConfidence: floatAverage(\.warpConfidence),
            microConfidence: floatAverage(\.microConfidence),
            strideConfidence: floatAverage(\.strideConfidence),
            bobConfidence: floatAverage(\.bobConfidence),
            turnConfidence: floatAverage(\.turnConfidence),
            acceptedBlockCount: Int32(acceptedBlockCount.rounded()),
            totalBlockCount: Int32(totalBlockCount.rounded()),
            yawPitchProxy: vectorAverage(\.yawPitchProxy),
            shear: vectorAverage(\.shear),
            perspective: vectorAverage(\.perspective),
            blurAmount: floatAverage(\.blurAmount),
            trackingConfidence: floatAverage(\.trackingConfidence),
            motionConfidence: floatAverage(\.motionConfidence),
            residual: floatAverage(\.residual),
            footstepImpulse: vector3Average(\.footstepImpulse),
            searchRadiusHitCount: Int32(samples.reduce(Float(0.0)) { partial, sample in
                partial + (Float(sample.transform.searchRadiusHitCount) * sample.weight)
            } / totalWeight),
            searchRadiusTotalCount: Int32(samples.reduce(Float(0.0)) { partial, sample in
                partial + (Float(sample.transform.searchRadiusTotalCount) * sample.weight)
            } / totalWeight)
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
            footstepPathX: rawPathX,
            footstepPathY: rawPathY,
            footstepPathRoll: rawPathRoll,
            pathYaw: jerkLimitedMotionPath(rawPathYaw, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathPitch: jerkLimitedMotionPath(rawPathPitch, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathShearX: jerkLimitedMotionPath(rawPathShearX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathShearY: jerkLimitedMotionPath(rawPathShearY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveX: jerkLimitedMotionPath(rawPathPerspectiveX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveY: jerkLimitedMotionPath(rawPathPerspectiveY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            analysisConfidence: motions.map(\.analysisConfidence),
            warpConfidence: motions.map(\.warpConfidence),
            acceptedBlockCounts: motions.map(\.acceptedBlockCount),
            totalBlockCounts: motions.map(\.totalBlockCount),
            blurAmounts: sortedFrames.map(\.blurAmount),
            searchRadiusHitCounts: motions.map(\.searchRadiusHitCount),
            searchRadiusTotalCounts: motions.map(\.searchRadiusTotalCount)
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
            return StabilizerBlockShift(
                block: block,
                dx: shift.dx,
                dy: shift.dy,
                score: shift.score,
                searchRadiusHit: shift.searchRadiusHit
            )
        }
        let acceptedBlocks = acceptedMotionBlocks(blockShifts, global: (global.dx, global.dy, global.score))
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
        let searchRadiusHitCount = (global.searchRadiusHit ? 1 : 0) + blockShifts.filter(\.searchRadiusHit).count
        let searchRadiusTotalCount = 1 + blockShifts.count
        let warpMotion = farFieldWarpMotion(
            shifts: motionBlocksForModel,
            robustDx: robustDx,
            robustDy: robustDy,
            signedRoll: signedRoll,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            analysisConfidence: analysisConfidence
        )

        return PairMotion(
            dx: robustDx,
            dy: robustDy,
            residual: median(motionBlocksForModel.map(\.score)) ?? global.score,
            signedRoll: signedRoll,
            rollMotion: rollMotion,
            yawProxy: warpMotion.yawProxy,
            pitchProxy: warpMotion.pitchProxy,
            shearX: warpMotion.shearX,
            shearY: warpMotion.shearY,
            perspectiveX: warpMotion.perspectiveX,
            perspectiveY: warpMotion.perspectiveY,
            analysisConfidence: analysisConfidence,
            warpConfidence: warpMotion.confidence,
            acceptedBlockCount: Int32(acceptedCount),
            totalBlockCount: Int32(blocks.count),
            searchRadiusHitCount: Int32(searchRadiusHitCount),
            searchRadiusTotalCount: Int32(searchRadiusTotalCount)
        )
    }

    fileprivate static func blurAmount(_ pixels: [UInt8], sampleWidth: Int, sampleHeight: Int) -> Float {
        var totalGradient: Float = 0.0
        var edgeSampleCount: Float = 0.0
        var strongEdgeSampleCount: Float = 0.0
        var count: Float = 0.0
        for y in 1..<(sampleHeight - 1) {
            let row = y * sampleWidth
            for x in 1..<(sampleWidth - 1) {
                let horizontal = abs(Int(pixels[row + x + 1]) - Int(pixels[row + x - 1]))
                let vertical = abs(Int(pixels[row + sampleWidth + x]) - Int(pixels[row - sampleWidth + x]))
                let gradient = Float(horizontal + vertical) / 510.0
                totalGradient += gradient
                if gradient >= 0.05 {
                    edgeSampleCount += 1.0
                }
                if gradient >= 0.10 {
                    strongEdgeSampleCount += 1.0
                }
                count += 1.0
            }
        }
        guard count > 0.0 else {
            return 1.0
        }
        let meanGradient = totalGradient / count
        let edgeCoverage = edgeSampleCount / count
        let strongEdgeCoverage = strongEdgeSampleCount / count
        let sharpnessEvidence = max(meanGradient, edgeCoverage * 0.45, strongEdgeCoverage * 0.9)
        return 1.0 - clamp((sharpnessEvidence - 0.006) / 0.055, min: 0.0, max: 1.0)
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

    private static func farFieldWarpMotion(
        shifts: [StabilizerBlockShift],
        robustDx: Float,
        robustDy: Float,
        signedRoll: Float,
        sampleWidth: Int,
        sampleHeight: Int,
        analysisConfidence: Float
    ) -> (yawProxy: Float, pitchProxy: Float, shearX: Float, shearY: Float, perspectiveX: Float, perspectiveY: Float, confidence: Float) {
        let farFieldShifts = shifts.filter { $0.block.farFieldWeight >= 0.55 }
        guard farFieldShifts.count >= minimumFarFieldMotionBlocks, analysisConfidence > 0.0 else {
            return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        }

        let halfWidth = Float(max(1, sampleWidth)) * 0.5
        let halfHeight = Float(max(1, sampleHeight)) * 0.5
        var yawCandidates: [(value: Float, weight: Float)] = []
        var pitchCandidates: [(value: Float, weight: Float)] = []
        var shearXCandidates: [(value: Float, weight: Float)] = []
        var shearYCandidates: [(value: Float, weight: Float)] = []
        var perspectiveXCandidates: [(value: Float, weight: Float)] = []
        var perspectiveYCandidates: [(value: Float, weight: Float)] = []

        for shift in farFieldShifts {
            let x = shift.block.centerX - halfWidth
            let y = shift.block.centerY - halfHeight
            let residualX = shift.dx - robustDx + (signedRoll * y)
            let residualY = shift.dy - robustDy - (signedRoll * x)
            let scoreWeight = clamp(1.0 - (shift.score * 1.8), min: 0.05, max: 1.0)
            let weight = shift.block.farFieldWeight * scoreWeight
            yawCandidates.append((
                clamp(residualX / halfWidth, min: -maxFarFieldYawPitchProxy, max: maxFarFieldYawPitchProxy),
                weight
            ))
            pitchCandidates.append((
                clamp(residualY / halfHeight, min: -maxFarFieldYawPitchProxy, max: maxFarFieldYawPitchProxy),
                weight
            ))
            if abs(y) > halfHeight * 0.15 {
                shearXCandidates.append((
                    clamp(residualX / y, min: -maxFarFieldShear, max: maxFarFieldShear),
                    weight
                ))
            }
            if abs(x) > halfWidth * 0.15 {
                shearYCandidates.append((
                    clamp(residualY / x, min: -maxFarFieldShear, max: maxFarFieldShear),
                    weight
                ))
            }
            let radialDenominator = max(1.0, (x * x) + (y * y))
            let radialResidual = (residualX * x) + (residualY * y)
            perspectiveXCandidates.append((
                clamp((radialResidual * x) / (radialDenominator * halfWidth), min: -maxFarFieldPerspective, max: maxFarFieldPerspective),
                weight
            ))
            perspectiveYCandidates.append((
                clamp((radialResidual * y) / (radialDenominator * halfHeight), min: -maxFarFieldPerspective, max: maxFarFieldPerspective),
                weight
            ))
        }

        let farFieldCoverage = Float(farFieldShifts.count) / Float(max(1, shifts.count))
        let confidence = clamp(analysisConfidence * farFieldCoverage, min: 0.0, max: 1.0)
        guard confidence >= 0.08 else {
            return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, confidence)
        }

        return (
            yawProxy: (weightedMedian(yawCandidates) ?? 0.0) * confidence,
            pitchProxy: (weightedMedian(pitchCandidates) ?? 0.0) * confidence,
            shearX: (weightedMedian(shearXCandidates) ?? 0.0) * confidence,
            shearY: (weightedMedian(shearYCandidates) ?? 0.0) * confidence,
            perspectiveX: (weightedMedian(perspectiveXCandidates) ?? 0.0) * confidence,
            perspectiveY: (weightedMedian(perspectiveYCandidates) ?? 0.0) * confidence,
            confidence: confidence
        )
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
    ) throws -> (dx: Float, dy: Float, score: Float, searchRadiusHit: Bool) {
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
        let searchRadiusHit = abs(bestDx - centerX) >= radius || abs(bestDy - centerY) >= radius

        guard refine else {
            return (Float(bestDx), Float(bestDy), bestScore, searchRadiusHit)
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
            bestScore,
            searchRadiusHit
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
            let previousAcceleration = index >= 3
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

    private struct FrameInterpolation {
        let lowerIndex: Int
        let upperIndex: Int
        let fraction: Float

        var indices: [Int] {
            lowerIndex == upperIndex ? [lowerIndex] : [lowerIndex, upperIndex]
        }
    }

    private static func frameInterpolation(at time: Double, in frames: [StabilizerAnalysisFrame]) -> FrameInterpolation {
        guard !frames.isEmpty else {
            return FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0)
        }
        guard frames.count > 1 else {
            return FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0)
        }
        if time <= frames[0].time {
            return FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0)
        }
        let lastIndex = frames.count - 1
        if time >= frames[lastIndex].time {
            return FrameInterpolation(lowerIndex: lastIndex, upperIndex: lastIndex, fraction: 0.0)
        }
        for upperIndex in 1..<frames.count {
            let upperTime = frames[upperIndex].time
            guard time <= upperTime else {
                continue
            }
            let lowerIndex = upperIndex - 1
            let lowerTime = frames[lowerIndex].time
            let duration = upperTime - lowerTime
            guard duration > 1e-9 else {
                return FrameInterpolation(lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: 0.0)
            }
            let fraction = clamp(Float((time - lowerTime) / duration), min: 0.0, max: 1.0)
            return FrameInterpolation(lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction)
        }
        return FrameInterpolation(lowerIndex: lastIndex, upperIndex: lastIndex, fraction: 0.0)
    }

    private static func interpolatedValue(_ values: [Float], using interpolation: FrameInterpolation) -> Float {
        guard values.indices.contains(interpolation.lowerIndex) else {
            return 0.0
        }
        let lowerValue = values[interpolation.lowerIndex]
        guard values.indices.contains(interpolation.upperIndex), interpolation.upperIndex != interpolation.lowerIndex else {
            return lowerValue
        }
        let upperValue = values[interpolation.upperIndex]
        return lowerValue + ((upperValue - lowerValue) * interpolation.fraction)
    }

    private static func turnSmoothingOffsetLimit(
        outputPixels: Float,
        baseFraction: Float,
        extraFraction: Float,
        strength: Double
    ) -> Float {
        let extraStrength = clamp(Float(strength - 1.0), min: 0.0, max: 3.0)
        let fraction = baseFraction + (extraFraction * extraStrength)
        return max(8.0, outputPixels * fraction)
    }

    private static func softLimit(_ value: Float, limit: Float) -> Float {
        guard value.isFinite, limit.isFinite, limit > 0.0 else {
            return value
        }
        return Float(Darwin.tanh(Double(value / limit))) * limit
    }

    private static func symmetricWindowSupport(
        frames: [StabilizerAnalysisFrame],
        centerTime: Double,
        windowSeconds: Double
    ) -> Float {
        guard windowSeconds.isFinite,
              windowSeconds > 0.0,
              let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return 0.0
        }
        let halfWindow = windowSeconds * 0.5
        let leftSupport = centerTime - firstTime
        let rightSupport = lastTime - centerTime
        return clamp(Float(min(leftSupport, rightSupport) / halfWindow), min: 0.0, max: 1.0)
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

    private static func indicesWithinTimeWindow(
        around centerIndex: Int,
        frames: [StabilizerAnalysisFrame],
        windowSeconds: Double
    ) -> [Int] {
        guard frames.indices.contains(centerIndex), windowSeconds.isFinite, windowSeconds >= 0.0 else {
            return []
        }
        let centerTime = frames[centerIndex].time
        let maxDistance = windowSeconds + timeWindowSelectionEpsilon
        return frames.indices.filter { index in
            abs(frames[index].time - centerTime) <= maxDistance
        }
    }

    private static func surroundingIndicesExcludingCenter(
        around centerIndex: Int,
        frames: [StabilizerAnalysisFrame],
        innerWindowSeconds: Double,
        outerWindowSeconds: Double
    ) -> [Int] {
        guard frames.indices.contains(centerIndex), innerWindowSeconds.isFinite, outerWindowSeconds.isFinite else {
            return []
        }
        let innerWindow = max(0.0, min(innerWindowSeconds, outerWindowSeconds))
        let outerWindow = max(innerWindow, outerWindowSeconds)
        let centerTime = frames[centerIndex].time
        let indices = frames.indices.filter { index in
            let distance = abs(frames[index].time - centerTime)
            return distance <= outerWindow + timeWindowSelectionEpsilon
                && distance > innerWindow + timeWindowSelectionEpsilon
        }
        if indices.count >= 3 {
            return Array(indices)
        }
        return indicesWithinTimeWindow(around: centerIndex, frames: frames, windowSeconds: outerWindow)
    }

    private static func outerLinearPrediction(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        centerIndex: Int,
        innerWindowSeconds: Double,
        outerWindowSeconds: Double
    ) -> Float? {
        guard values.indices.contains(centerIndex), frames.indices.contains(centerIndex) else {
            return nil
        }
        let innerWindow = max(0.0, min(innerWindowSeconds, outerWindowSeconds))
        let outerWindow = max(innerWindow, outerWindowSeconds)
        let centerTime = frames[centerIndex].time
        var points: [(x: Float, y: Float)] = []
        for index in frames.indices where values.indices.contains(index) {
            let offsetSeconds = frames[index].time - centerTime
            let distance = abs(offsetSeconds)
            if distance <= outerWindow + timeWindowSelectionEpsilon
                && distance > innerWindow + timeWindowSelectionEpsilon {
                points.append((x: Float(offsetSeconds), y: values[index]))
            }
        }
        guard points.count >= 3 else {
            let indices = surroundingIndicesExcludingCenter(
                around: centerIndex,
                frames: frames,
                innerWindowSeconds: innerWindow,
                outerWindowSeconds: outerWindow
            ).filter { values.indices.contains($0) }
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

    private static func outerLinearPredictionPath(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        innerWindowSeconds: Double,
        outerWindowSeconds: Double
    ) -> [Float] {
        guard !values.isEmpty else {
            return values
        }
        var predictedValues = values
        for index in Set(indices) where values.indices.contains(index) && frames.indices.contains(index) {
            predictedValues[index] = outerLinearPrediction(
                values,
                frames: frames,
                centerIndex: index,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds
            ) ?? values[index]
        }
        return predictedValues
    }

    private static func farFieldWarpBandValue(
        values: [Float],
        baselineValues: [Float],
        interpolation: FrameInterpolation,
        deadband: Float,
        confidence: Float
    ) -> Float {
        let currentValue = interpolatedValue(values, using: interpolation)
        let baselineValue = interpolatedValue(baselineValues, using: interpolation)
        return softDeadband(currentValue - baselineValue, threshold: deadband) * confidence
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

    private static func locallyTimeWeightedAveragePath(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        targetIndices: [Int],
        windowSeconds: Double
    ) -> [Float] {
        guard !values.isEmpty else {
            return values
        }
        var smoothedValues = values
        let halfWindowSeconds = max(0.0, windowSeconds * 0.5)
        for index in Set(targetIndices) where values.indices.contains(index) && frames.indices.contains(index) {
            let centerTime = frames[index].time
            let localIndices = frames.indices.filter { candidate in
                abs(frames[candidate].time - centerTime) <= halfWindowSeconds + timeWindowSelectionEpsilon
            }
            let activeIndices = localIndices.isEmpty ? [index] : Array(localIndices)
            smoothedValues[index] = timeWeightedAverage(
                values,
                frames: frames,
                indices: activeIndices,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            )
        }
        return smoothedValues
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

    private static func percentileValue(_ values: [Float], indices: [Int], percentile: Float) -> Float {
        let sortedValues = indices
            .filter { values.indices.contains($0) }
            .map { values[$0] }
            .filter(\.isFinite)
            .sorted()
        guard !sortedValues.isEmpty else {
            return 0.0
        }
        guard sortedValues.count > 1 else {
            return sortedValues[0]
        }
        let boundedPercentile = clamp(percentile, min: 0.0, max: 1.0)
        let scaledIndex = boundedPercentile * Float(sortedValues.count - 1)
        let lowerIndex = Int(Darwin.floorf(scaledIndex))
        let upperIndex = min(sortedValues.count - 1, lowerIndex + 1)
        let fraction = scaledIndex - Float(lowerIndex)
        return sortedValues[lowerIndex] + ((sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction)
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180.0 / .pi
    }

    private static func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func confidenceCompensatedCorrectionFactor(_ strength: Double, confidence: Float) -> Float {
        let requestedRemoval = clamp(Float(strength), min: 0.0, max: 4.0)
        let confidenceResponse = correctionConfidenceResponse(confidence)
        let directRemoval = min(requestedRemoval, 1.0) * confidenceResponse
        let confidenceBoost = max(0.0, requestedRemoval - 1.0)
            * 0.20
            * confidenceResponse
            * (1.0 - (confidenceResponse * 0.35))
        return clamp(directRemoval + confidenceBoost, min: 0.0, max: 1.0)
    }

    private static func correctionConfidenceResponse(_ confidence: Float) -> Float {
        let boundedConfidence = clamp(confidence, min: 0.0, max: 1.0)
        return boundedConfidence * (1.0 + ((1.0 - boundedConfidence) * 0.45))
    }

    private static func farFieldWarpRenderGate(
        warpConfidence: Float,
        trackingConfidence: Float,
        searchRadiusHitCount: Int32,
        searchRadiusTotalCount: Int32
    ) -> Float {
        guard warpConfidence > 0.0, searchRadiusTotalCount > 0 else {
            return 0.0
        }
        let searchRadiusHitRatio = clamp(
            Float(searchRadiusHitCount) / Float(searchRadiusTotalCount),
            min: 0.0,
            max: 1.0
        )
        let edgeQuality = 1.0 - searchRadiusHitRatio
        let trackingGate = confidenceRamp(
            trackingConfidence,
            start: farFieldWarpTrackingGateStart,
            full: farFieldWarpTrackingGateFull
        )
        let edgeGate = confidenceRamp(
            edgeQuality,
            start: farFieldWarpEdgeQualityGateStart,
            full: farFieldWarpEdgeQualityGateFull
        )
        let gate = clamp(trackingGate * edgeGate, min: 0.0, max: 1.0)
        return correctionConfidenceResponse(gate)
    }

    private static func softDeadband(_ value: Float, threshold: Float) -> Float {
        let boundedThreshold = max(0.0, threshold)
        let magnitude = abs(value)
        guard magnitude > boundedThreshold else {
            return 0.0
        }
        return (value >= 0.0 ? 1.0 : -1.0) * (magnitude - boundedThreshold)
    }

    private static func strideWobbleConfidence(
        bandValue: Float,
        trackingConfidence: Float,
        fullScale: Float
    ) -> Float {
        let magnitude = abs(bandValue)
        let noiseFloor = fullScale * 0.10
        let bandQuality = confidenceRamp(
            magnitude,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, fullScale)
        )
        return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
    }

    private static func walkingBobConfidence(
        bandValue: Float,
        trackingConfidence: Float,
        windowSupport: Float
    ) -> Float {
        let magnitude = abs(bandValue)
        let noiseFloor = walkingBobFullScalePixels * 0.08
        let bandQuality = confidenceRamp(
            magnitude,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, walkingBobFullScalePixels)
        )
        return clamp(trackingConfidence * windowSupport * bandQuality, min: 0.0, max: 1.0)
    }

    private static func turnSmoothingConfidence(
        bandValue: Float,
        trackingConfidence: Float
    ) -> Float {
        let magnitude = abs(bandValue)
        let noiseFloor = turnSmoothingFullScalePixels * 0.08
        let bandQuality = confidenceRamp(
            magnitude,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, turnSmoothingFullScalePixels)
        )
        return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
    }

    private static func residualAdjustedTrackingConfidence(
        _ trackingConfidence: Float,
        residual: Float,
        multiplier: Float
    ) -> Float {
        let residualQuality = clamp(1.0 - (residual * multiplier), min: 0.0, max: 1.0)
        return clamp(trackingConfidence * residualQuality, min: 0.0, max: 1.0)
    }

    private static func frameTrackingConfidence(
        motionConfidence: Float,
        residual: Float,
        blurAmount: Float,
        acceptedBlockCount: Int32,
        totalBlockCount: Int32
    ) -> Float {
        let residualQuality = clamp(1.0 - (residual * 0.7), min: 0.0, max: 1.0)
        let blurQuality = clamp(1.0 - (blurAmount * 0.45), min: 0.0, max: 1.0)
        let blockQuality: Float
        if totalBlockCount > 0 {
            blockQuality = clamp(Float(acceptedBlockCount) / Float(totalBlockCount), min: 0.0, max: 1.0)
        } else {
            blockQuality = 0.0
        }
        let combinedEvidence = motionConfidence * residualQuality * blurQuality * blockQuality
        return clamp(Darwin.sqrtf(max(0.0, combinedEvidence)), min: 0.0, max: 1.0)
    }

    private static func footstepFrameConfidence(
        values: [Float],
        baselineValues: [Float],
        frames: [StabilizerAnalysisFrame],
        interpolation: FrameInterpolation,
        trackingConfidence: Float,
        fullImpulseScale: Float
    ) -> Float {
        let lowerConfidence = footstepFrameConfidenceAtIndex(
            values: values,
            baselineValues: baselineValues,
            frames: frames,
            index: interpolation.lowerIndex,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: fullImpulseScale
        )
        guard interpolation.upperIndex != interpolation.lowerIndex else {
            return lowerConfidence
        }
        let upperConfidence = footstepFrameConfidenceAtIndex(
            values: values,
            baselineValues: baselineValues,
            frames: frames,
            index: interpolation.upperIndex,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: fullImpulseScale
        )
        return lowerConfidence + ((upperConfidence - lowerConfidence) * interpolation.fraction)
    }

    private static func footstepFrameConfidenceAtIndex(
        values: [Float],
        baselineValues: [Float],
        frames: [StabilizerAnalysisFrame],
        index: Int,
        trackingConfidence: Float,
        fullImpulseScale: Float
    ) -> Float {
        guard values.indices.contains(index), baselineValues.indices.contains(index) else {
            return 0.0
        }
        let impulse = abs(values[index] - baselineValues[index])
        let surroundingIndices = surroundingIndicesExcludingCenter(
            around: index,
            frames: frames,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds
        ).filter { values.indices.contains($0) && baselineValues.indices.contains($0) }
        guard !surroundingIndices.isEmpty else {
            return 0.0
        }
        let surroundingNoise = median(surroundingIndices.map { abs(values[$0] - baselineValues[$0]) }) ?? 0.0
        let centerTime = frames.indices.contains(index) ? frames[index].time : 0.0
        let hasLeftSupport = surroundingIndices.contains { frames.indices.contains($0) && frames[$0].time < centerTime }
        let hasRightSupport = surroundingIndices.contains { frames.indices.contains($0) && frames[$0].time > centerTime }
        let supportQuality: Float = (hasLeftSupport && hasRightSupport) ? 1.0 : 0.65
        let noiseFloor = max(
            fullImpulseScale * footstepNoiseFloorScale,
            surroundingNoise * footstepSurroundingNoiseMultiplier
        )
        let impulseQuality = confidenceRamp(
            impulse,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, fullImpulseScale * footstepFullResponseScale)
        )
        return clamp(trackingConfidence * supportQuality * impulseQuality, min: 0.0, max: 1.0)
    }

    private static func confidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
        guard value.isFinite, start.isFinite, full.isFinite, full > start else {
            return 0.0
        }
        let normalized = clamp((value - start) / (full - start), min: 0.0, max: 1.0)
        return normalized * normalized * (3.0 - (2.0 * normalized))
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
                warpConfidence: 0.0,
                acceptedBlockCount: 0,
                totalBlockCount: 0,
                searchRadiusHitCount: 0,
                searchRadiusTotalCount: 0
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
