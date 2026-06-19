import CoreMedia
import CoreVideo
import Darwin
import Foundation
import IOSurface
import Metal
import os.log
import simd

struct StabilizerAutoTransform {
    var pixelOffset: vector_float2
    var macroPixelOffset: vector_float2
    var microPixelOffset: vector_float2
    var strideWobblePixelOffset: vector_float2
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
    var turnConfidence: Float
    var acceptedBlockCount: Int32
    var totalBlockCount: Int32
    var yawPitchProxy: vector_float2
    var shear: vector_float2
    var perspective: vector_float2
    var blurAmount: Float
    var trackingConfidence: Float
    var walkingTrackingConfidence: Float
    var motionConfidence: Float
    var residual: Float
    var footstepImpulse: vector_float3
    var rawFootstepCorrection: vector_float2
    var limitedFootstepCorrection: vector_float2
    var footstepPulseLimited: vector_float2
    var searchRadiusHitCount: Int32
    var searchRadiusTotalCount: Int32

    static let identity = StabilizerAutoTransform(
        pixelOffset: vector_float2(0.0, 0.0),
        macroPixelOffset: vector_float2(0.0, 0.0),
        microPixelOffset: vector_float2(0.0, 0.0),
        strideWobblePixelOffset: vector_float2(0.0, 0.0),
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
        turnConfidence: 0.0,
        acceptedBlockCount: 0,
        totalBlockCount: 0,
        yawPitchProxy: vector_float2(0.0, 0.0),
        shear: vector_float2(0.0, 0.0),
        perspective: vector_float2(0.0, 0.0),
        blurAmount: 0.0,
        trackingConfidence: 0.0,
        walkingTrackingConfidence: 0.0,
        motionConfidence: 0.0,
        residual: 0.0,
        footstepImpulse: vector_float3(0.0, 0.0, 0.0),
        rawFootstepCorrection: vector_float2(0.0, 0.0),
        limitedFootstepCorrection: vector_float2(0.0, 0.0),
        footstepPulseLimited: vector_float2(0.0, 0.0),
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
    let farFieldWarp: Double

    static let defaultStrengths = StabilizerCorrectionStrengths(
        microJitterX: 1.0,
        microJitterY: 0.0,
        microJitterRotation: 0.0,
        strideWobbleX: 1.0,
        strideWobbleY: 0.0,
        strideWobbleRotation: 0.0,
        panStabilizationStrength: 0.2,
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
        pixels.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return fingerprintString(hash: fingerprintInitialHash, byteCount: 0)
            }
            return fingerprint(baseAddress, byteCount: buffer.count)
        }
    }

    static let fingerprintInitialHash: UInt64 = 14_695_981_039_346_656_037
    static let fingerprintChunkCount = 1024

    static func combineFingerprintByte(_ byte: UInt8, into hash: inout UInt64) {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }

    static func fingerprint(_ pixels: UnsafePointer<UInt8>, byteCount: Int) -> String {
        let chunkCount = max(1, min(fingerprintChunkCount, max(1, byteCount)))
        var combinedHash = fingerprintInitialHash
        for chunkIndex in 0..<chunkCount {
            let startIndex = (byteCount * chunkIndex) / chunkCount
            let endIndex = (byteCount * (chunkIndex + 1)) / chunkCount
            var chunkHash = fingerprintInitialHash
            if startIndex < endIndex {
                for index in startIndex..<endIndex {
                    combineFingerprintByte(pixels[index], into: &chunkHash)
                }
            }
            var value = chunkHash
            for _ in 0..<MemoryLayout<UInt64>.size {
                combineFingerprintByte(UInt8(value & 0xff), into: &combinedHash)
                value >>= 8
            }
        }
        return fingerprintString(hash: combinedHash, byteCount: byteCount)
    }

    static func fingerprintString(hash initialHash: UInt64, byteCount: Int) -> String {
        var hash = initialHash
        var count = UInt64(byteCount)
        for _ in 0..<MemoryLayout<UInt64>.size {
            combineFingerprintByte(UInt8(count & 0xff), into: &hash)
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

struct StabilizerAnalysisSample {
    let time: Double
    let pixels: [UInt8]
    let sampleWidth: Int
    let sampleHeight: Int
    let lumaBuffer: MTLBuffer
    let lumaBufferLease: StabilizerDownsampleBufferLease?
    let downsampleMilliseconds: Double
}

fileprivate struct StabilizerFrameMetrics {
    let blurAmount: Float
    let fingerprint: String
}

final class StabilizerDownsampleBufferLease {
    let buffer: MTLBuffer
    let reused: Bool
    private let releaseHandler: () -> Void
    private let lock = NSLock()
    private var released = false

    init(buffer: MTLBuffer, reused: Bool, releaseHandler: @escaping () -> Void) {
        self.buffer = buffer
        self.reused = reused
        self.releaseHandler = releaseHandler
    }

    deinit {
        release()
    }

    func release() {
        lock.lock()
        guard !released else {
            lock.unlock()
            return
        }
        released = true
        lock.unlock()
        releaseHandler()
    }
}

final class StabilizerDownsampleBufferPool {
    private struct Slot {
        var buffer: MTLBuffer
        var length: Int
        var deviceRegistryID: UInt64
        var inUse: Bool
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
    private let maxSlotCount = 2

    func leaseBuffer(device: MTLDevice, length: Int) throws -> StabilizerDownsampleBufferLease {
        let length = max(1, length)
        lock.lock()
        defer {
            lock.unlock()
        }

        if let index = slots.firstIndex(where: {
            !$0.inUse && $0.deviceRegistryID == device.registryID && $0.length >= length
        }) {
            slots[index].inUse = true
            return lease(forSlotAt: index, reused: true)
        }

        if let index = slots.firstIndex(where: { !$0.inUse }) {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer reusable downsample buffer.")
            }
            slots[index] = Slot(
                buffer: buffer,
                length: length,
                deviceRegistryID: device.registryID,
                inUse: true
            )
            return lease(forSlotAt: index, reused: false)
        }

        if slots.count < maxSlotCount {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer reusable downsample buffer.")
            }
            slots.append(Slot(
                buffer: buffer,
                length: length,
                deviceRegistryID: device.registryID,
                inUse: true
            ))
            return lease(forSlotAt: slots.count - 1, reused: false)
        }

        throw AutoStabilizationEstimator.metalError("Stabilizer downsample ping-pong buffers were both in use; Host Analysis frame callbacks overlapped.")
    }

    private func lease(forSlotAt index: Int, reused: Bool) -> StabilizerDownsampleBufferLease {
        StabilizerDownsampleBufferLease(buffer: slots[index].buffer, reused: reused) { [weak self] in
            self?.releaseSlot(at: index)
        }
    }

    private func releaseSlot(at index: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard slots.indices.contains(index) else {
            return
        }
        slots[index].inUse = false
    }
}

enum StabilizerAnalysisQualityModel {
    case fxplugHostAnalysis
    case eventAnalyzerCache
}

struct StabilizerPreparedAnalysis {
    let frames: [StabilizerAnalysisFrame]
    let qualityModel: StabilizerAnalysisQualityModel
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

struct StabilizerPairMotionTiming {
    let globalMilliseconds: Double
    let localBatchMilliseconds: Double
    let totalMilliseconds: Double
}

fileprivate struct PairMotionResult {
    let motion: PairMotion
    let timing: StabilizerPairMotionTiming
    let overlappedFrameMetrics: StabilizerFrameMetrics?
    let overlappedMetricsMilliseconds: Double
}

fileprivate struct StabilizerPendingShiftResult {
    let commandBuffer: MTLCommandBuffer
    let resultBuffer: MTLBuffer
    let startedAt: CFAbsoluteTime

    func waitForResult() throws -> (dx: Float, dy: Float, score: Float, searchRadiusHit: Bool, milliseconds: Double) {
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        let result = resultBuffer.contents().assumingMemoryBound(to: StabilizerShiftResult.self)[0]
        return (
            result.dx,
            result.dy,
            result.score,
            result.searchRadiusHit != 0,
            (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
        )
    }
}

fileprivate struct StabilizerMotionBlock {
    let x0: Int
    let y0: Int
    let width: Int
    let height: Int
    let centerX: Float
    let centerY: Float
    let farFieldWeight: Float
}

fileprivate struct StabilizerBlockShift {
    let block: StabilizerMotionBlock
    let dx: Float
    let dy: Float
    let score: Float
    let searchRadiusHit: Bool
}

fileprivate struct StabilizerMotionBlockBatch {
    let blocks: [StabilizerMotionBlock]
    let uniforms: [StabilizerShiftBatchUniforms]
    let maxBlockHeight: Int
}

fileprivate final class MetalAnalysisContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let shiftPartialPipelineState: MTLComputePipelineState
    let batchShiftPartialPipelineState: MTLComputePipelineState
    let batchShiftPartialWithGlobalCenterPipelineState: MTLComputePipelineState
    let resolveShiftPipelineState: MTLComputePipelineState
    let resolveShiftWithGlobalCenterPipelineState: MTLComputePipelineState
    private var reusableShiftScoreBuffer: MTLBuffer?
    private var reusableShiftScoreBufferLength = 0
    private var reusableShiftPartialBuffer: MTLBuffer?
    private var reusableShiftPartialBufferLength = 0
    private var reusableShiftResultBuffer: MTLBuffer?
    private var reusableShiftResultBufferLength = 0
    private var reusableShiftBatchUniformBuffer: MTLBuffer?
    private var reusableShiftBatchUniformBufferLength = 0

    init(preferredDevice: MTLDevice? = nil) throws {
        guard let device = preferredDevice ?? MTLCreateSystemDefaultDevice() else {
            throw AutoStabilizationEstimator.metalError("Metal device was not available for Stabilizer analysis.")
        }
        guard
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let shiftPartialFunction = library.makeFunction(name: "stabilizerShiftScorePartials"),
            let batchShiftPartialFunction = library.makeFunction(name: "stabilizerBatchShiftScorePartials"),
            let batchShiftPartialWithGlobalCenterFunction = library.makeFunction(name: "stabilizerBatchShiftScorePartialsWithGlobalCenter"),
            let resolveShiftFunction = library.makeFunction(name: "stabilizerResolveShiftResults"),
            let resolveShiftWithGlobalCenterFunction = library.makeFunction(name: "stabilizerResolveShiftResultsWithGlobalCenter")
        else {
            throw AutoStabilizationEstimator.metalError("Stabilizer Metal analysis resources were unavailable.")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.shiftPartialPipelineState = try device.makeComputePipelineState(function: shiftPartialFunction)
        self.batchShiftPartialPipelineState = try device.makeComputePipelineState(function: batchShiftPartialFunction)
        self.batchShiftPartialWithGlobalCenterPipelineState = try device.makeComputePipelineState(function: batchShiftPartialWithGlobalCenterFunction)
        self.resolveShiftPipelineState = try device.makeComputePipelineState(function: resolveShiftFunction)
        self.resolveShiftWithGlobalCenterPipelineState = try device.makeComputePipelineState(function: resolveShiftWithGlobalCenterFunction)
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

    func validateFrameBuffer(_ buffer: MTLBuffer, sampleWidth: Int, sampleHeight: Int) throws {
        guard buffer.device.registryID == device.registryID else {
            throw AutoStabilizationEstimator.metalError("Stabilizer analysis luma buffer was created on a different Metal device.")
        }
        guard buffer.length >= sampleWidth * sampleHeight else {
            throw AutoStabilizationEstimator.metalError("Stabilizer analysis luma buffer was smaller than the expected sample size.")
        }
    }

    func shiftScoreBuffer(length: Int) throws -> MTLBuffer {
        if let buffer = reusableShiftScoreBuffer,
           reusableShiftScoreBufferLength >= length {
            return buffer
        }
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer Metal shift score buffer.")
        }
        reusableShiftScoreBuffer = buffer
        reusableShiftScoreBufferLength = length
        return buffer
    }

    func shiftPartialBuffer(length: Int) throws -> MTLBuffer {
        if let buffer = reusableShiftPartialBuffer,
           reusableShiftPartialBufferLength >= length {
            return buffer
        }
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer Metal shift partial buffer.")
        }
        reusableShiftPartialBuffer = buffer
        reusableShiftPartialBufferLength = length
        return buffer
    }

    func shiftResultBuffer(length: Int) throws -> MTLBuffer {
        if let buffer = reusableShiftResultBuffer,
           reusableShiftResultBufferLength >= length {
            return buffer
        }
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer Metal shift result buffer.")
        }
        reusableShiftResultBuffer = buffer
        reusableShiftResultBufferLength = length
        return buffer
    }

    func shiftBatchUniformBuffer(uniforms: [StabilizerShiftBatchUniforms]) throws -> MTLBuffer {
        let length = MemoryLayout<StabilizerShiftBatchUniforms>.stride * uniforms.count
        if reusableShiftBatchUniformBuffer == nil || reusableShiftBatchUniformBufferLength < length {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw AutoStabilizationEstimator.metalError("Could not allocate Stabilizer Metal shift batch uniform buffer.")
            }
            reusableShiftBatchUniformBuffer = buffer
            reusableShiftBatchUniformBufferLength = length
        }
        guard let buffer = reusableShiftBatchUniformBuffer else {
            throw AutoStabilizationEstimator.metalError("Stabilizer Metal shift batch uniform buffer was unavailable.")
        }
        uniforms.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                memcpy(buffer.contents(), baseAddress, bytes.count)
            }
        }
        return buffer
    }
}

enum AutoStabilizationEstimator {
    static let defaultSampleWidth = 720
    static let defaultSampleHeight = 54
    static let minimumSampleWidth = 32
    static let minimumSampleHeight = 24
    static func blurEvidenceQuality(_ blurAmount: Float) -> Float {
        guard blurAmount.isFinite else {
            return 0.0
        }
        if blurAmount > 1.25 {
            // Native Event Analyzer schema 17+ stores this field as a sharpness-style
            // Metal blur-kernel response, where useful footage is commonly 2-6+.
            return clamp((blurAmount - 1.5) / 3.0, min: 0.0, max: 1.0)
        }
        return clamp(1.0 - (blurAmount * 0.45), min: 0.0, max: 1.0)
    }

    private static let minimumGlobalSearchRadius = 16
    private static let maximumGlobalSearchRadius = 36
    private static let minimumLocalSearchRadius = 5
    private static let maximumLocalSearchRadius = 10
    private static let positionGain: Float = 1.0
    private static let rotationGain: Float = 1.0
    private static let baseTurnSmoothingOffsetLimitX: Float = 0.08
    private static let extraTurnSmoothingOffsetLimitX: Float = 0.06
    private static let renderTemporalSmoothingSampleCount = 7
    private static let renderTemporalSmoothingWindowSeconds = 1.20
    private static let renderFarFieldWarpSmoothingWindowSeconds = 0.36
    private static let footstepImpulseFullScalePixels: Float = 0.35
    private static let footstepImpulseFullScaleDegrees: Float = 0.08
    private static let footstepNoiseFloorScale: Float = 0.08
    private static let footstepSurroundingNoiseMultiplier: Float = 1.10
    private static let footstepSurroundingNoiseFloorCapScale: Float = 0.45
    private static let footstepFullResponseScale: Float = 0.65
    private static let footstepConfidenceStabilityWindowSeconds = 0.18
    private static let footstepConfidenceCenterBlend: Float = 0.65
    private static let footstepPersistentSignWindowStartSeconds = 0.055
    private static let footstepPersistentSignWindowEndSeconds = 0.22
    private static let footstepXYContinuityWindowSeconds = 0.15
    private static let footstepXYContinuityMaxSamples = 9
    private static let footstepXYContinuityMinimumSpikePixels: Float = 0.75
    private static let footstepXYContinuityMadMultiplier: Float = 3.0
    private static let strideWobbleWindowSeconds = 2.0
    private static let strideWobbleFullScalePixels: Float = 0.75
    private static let strideWobbleFullScaleDegrees: Float = 0.16
    private static let strideWobbleFullResponseScale: Float = 0.65
    private static let turnSmoothingFullScalePixels: Float = 2.0
    private static let turnOwnershipFootstepXSuppression: Float = 0.90
    private static let turnOwnershipStrideXSuppression: Float = 1.0
    private static let maxFarFieldShear: Float = 0.008
    private static let maxFarFieldYawPitchProxy: Float = 0.004
    private static let maxFarFieldPerspective: Float = 0.003
    private static let maxRenderedFarFieldShear: Float = 0.004
    private static let maxRenderedFarFieldYawPitchProxy: Float = 0.0025
    private static let maxRenderedFarFieldPerspective: Float = 0.0015
    private static let farFieldWarpTrackingGateStart: Float = 0.26
    private static let farFieldWarpTrackingGateFull: Float = 0.56
    private static let farFieldWarpTrackingGateMedianBlend: Float = 0.45
    private static let farFieldWarpTrackingGateStabilityLimit: Float = 0.15
    private static let farFieldWarpEdgeQualityGateStart: Float = 0.55
    private static let farFieldWarpEdgeQualityGateFull: Float = 0.86
    private static let footstepImpulseInnerWindowSeconds = 0.10
    private static let footstepImpulseOuterWindowSeconds = 1.0
    private static let farFieldWarpInnerWindowSeconds = 0.10
    private static let farFieldWarpOuterWindowSeconds = 1.0
    private static let timeWindowSelectionEpsilon = 0.001
    private static let minimumAcceptedMotionBlocks = 3
    private static let minimumFarFieldMotionBlocks = 3
    private static let staggeredMotionBlockFarFieldThreshold: Float = 0.70
    private static let staggeredMotionBlockMinimumWidth = 18
    private static let staggeredMotionBlockMinimumHeight = 12
    private static let motionPathJerkLimitMultiplier: Float = 4.0
    private static let minimumTranslationAccelerationLimit: Float = 0.75
    private static let minimumTranslationJerkLimit: Float = 0.5
    private static let minimumRotationAccelerationLimit: Float = 0.04
    private static let minimumRotationJerkLimit: Float = 0.03
    private static let sharedRenderEstimateCacheLimit = 6
    private static let sharedRenderEstimateCacheLock = NSLock()
    private static var sharedRenderEstimateCaches: [RenderEstimateCacheStoreKey: RenderEstimateCache] = [:]
    private static var sharedRenderEstimateCacheOrder: [RenderEstimateCacheStoreKey] = []

    private enum MotionPathKind: Hashable {
        case footstepX
        case footstepY
        case footstepRoll
        case yaw
        case pitch
        case shearX
        case shearY
        case perspectiveX
        case perspectiveY
    }

    private enum LocalAverageSourceRole: Hashable {
        case footstepTurnBaseline
        case footstepStrideCleaned
    }

    private struct OuterPredictionCacheKey: Hashable {
        let kind: MotionPathKind
        let index: Int
        let innerWindowSeconds: UInt64
        let outerWindowSeconds: UInt64
    }

    private struct LocalAverageCacheKey: Hashable {
        let kind: MotionPathKind
        let sourceRole: LocalAverageSourceRole
        let sourceVariant: UInt64
        let index: Int
        let windowSeconds: UInt64
    }

    private struct RawTransformCacheKey: Hashable {
        let index: Int
        let outputWidth: UInt32
        let outputHeight: UInt32
        let panSmoothSeconds: UInt64
        let microJitterX: UInt64
        let microJitterY: UInt64
        let microJitterRotation: UInt64
        let strideWobbleX: UInt64
        let strideWobbleY: UInt64
        let strideWobbleRotation: UInt64
        let panStabilizationStrength: UInt64
        let farFieldWarp: UInt64
        let limitFootstepContinuity: Bool
    }

    private struct RenderEstimateCacheStoreKey: Hashable {
        let frameCount: Int
        let firstTime: UInt64
        let middleTime: UInt64
        let lastTime: UInt64
        let sampleWidth: Int
        let sampleHeight: Int
        let firstFingerprint: String
        let middleFingerprint: String
        let lastFingerprint: String
        let firstPathX: UInt32
        let middlePathX: UInt32
        let lastPathX: UInt32
        let firstPathY: UInt32
        let middlePathY: UInt32
        let lastPathY: UInt32
        let firstPathRoll: UInt32
        let middlePathRoll: UInt32
        let lastPathRoll: UInt32
    }

    private struct EstimatedPath {
        let values: [Float]
        let overrides: [Int: Float]
        let valueProvider: ((Int) -> Float?)?

        init(
            values: [Float],
            overrides: [Int: Float] = [:],
            valueProvider: ((Int) -> Float?)? = nil
        ) {
            self.values = values
            self.overrides = overrides
            self.valueProvider = valueProvider
        }

        subscript(index: Int) -> Float {
            guard values.indices.contains(index) else {
                return 0.0
            }
            if let providedValue = valueProvider?(index) {
                return providedValue
            }
            return overrides[index] ?? values[index]
        }
    }

    private final class RenderEstimateCache {
        private let lock = NSLock()
        private var outerPredictions: [OuterPredictionCacheKey: Float] = [:]
        private var localAverages: [LocalAverageCacheKey: Float] = [:]
        private var rawTransforms: [RawTransformCacheKey: StabilizerAutoTransform] = [:]
        private var rawTransformOrder: [RawTransformCacheKey] = []
        private let rawTransformLimit = 4096

        func rawTransform(
            analysis: StabilizerPreparedAnalysis,
            index: Int,
            outputSize: vector_float2,
            panSmoothSeconds: Double,
            strengths: StabilizerCorrectionStrengths,
            limitFootstepContinuity: Bool
        ) -> StabilizerAutoTransform {
            guard analysis.frames.indices.contains(index) else {
                return .identity
            }
            let key = RawTransformCacheKey(
                index: index,
                outputWidth: outputSize.x.bitPattern,
                outputHeight: outputSize.y.bitPattern,
                panSmoothSeconds: panSmoothSeconds.bitPattern,
                microJitterX: strengths.microJitterX.bitPattern,
                microJitterY: strengths.microJitterY.bitPattern,
                microJitterRotation: strengths.microJitterRotation.bitPattern,
                strideWobbleX: strengths.strideWobbleX.bitPattern,
                strideWobbleY: strengths.strideWobbleY.bitPattern,
                strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
                panStabilizationStrength: strengths.panStabilizationStrength.bitPattern,
                farFieldWarp: strengths.farFieldWarp.bitPattern,
                limitFootstepContinuity: limitFootstepContinuity
            )
            lock.lock()
            if let cached = rawTransforms[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let transform = AutoStabilizationEstimator.rawEstimate(
                preparedAnalysis: analysis,
                renderSeconds: analysis.frames[index].time,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                cache: self,
                limitFootstepContinuity: limitFootstepContinuity
            )

            lock.lock()
            if rawTransforms[key] == nil {
                rawTransforms[key] = transform
                rawTransformOrder.append(key)
                while rawTransformOrder.count > rawTransformLimit {
                    let oldestKey = rawTransformOrder.removeFirst()
                    rawTransforms.removeValue(forKey: oldestKey)
                }
            }
            let stored = rawTransforms[key] ?? transform
            lock.unlock()
            return stored
        }

        func outerLinearPredictionPath(
            _ kind: MotionPathKind,
            analysis: StabilizerPreparedAnalysis,
            indices: [Int],
            innerWindowSeconds: Double,
            outerWindowSeconds: Double
        ) -> EstimatedPath {
            let values = AutoStabilizationEstimator.values(for: kind, analysis: analysis)
            guard !values.isEmpty else {
                return EstimatedPath(values: values, overrides: [:])
            }
            let targetIndexSet = Set(indices)
            return EstimatedPath(values: values) { [self] index in
                guard targetIndexSet.contains(index),
                      values.indices.contains(index),
                      analysis.frames.indices.contains(index)
                else {
                    return nil
                }
                return outerLinearPrediction(
                    kind,
                    analysis: analysis,
                    index: index,
                    innerWindowSeconds: innerWindowSeconds,
                    outerWindowSeconds: outerWindowSeconds
                )
            }
        }

        func locallyTimeWeightedAveragePath(
            _ kind: MotionPathKind,
            sourceRole: LocalAverageSourceRole,
            sourceVariant: UInt64 = 0,
            source: EstimatedPath,
            analysis: StabilizerPreparedAnalysis,
            targetIndices: [Int],
            windowSeconds: Double
        ) -> EstimatedPath {
            guard !source.values.isEmpty else {
                return source
            }
            let targetIndexSet = Set(targetIndices)
            return EstimatedPath(values: source.values) { [self] index in
                guard source.values.indices.contains(index), analysis.frames.indices.contains(index) else {
                    return nil
                }
                guard targetIndexSet.contains(index) else {
                    return source[index]
                }
                return localTimeWeightedAverage(
                    kind,
                    sourceRole: sourceRole,
                    sourceVariant: sourceVariant,
                    source: source,
                    analysis: analysis,
                    index: index,
                    windowSeconds: windowSeconds
                )
            }
        }

        private func outerLinearPrediction(
            _ kind: MotionPathKind,
            analysis: StabilizerPreparedAnalysis,
            index: Int,
            innerWindowSeconds: Double,
            outerWindowSeconds: Double
        ) -> Float {
            let key = OuterPredictionCacheKey(
                kind: kind,
                index: index,
                innerWindowSeconds: innerWindowSeconds.bitPattern,
                outerWindowSeconds: outerWindowSeconds.bitPattern
            )
            lock.lock()
            if let cached = outerPredictions[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let values = AutoStabilizationEstimator.values(for: kind, analysis: analysis)
            let prediction = AutoStabilizationEstimator.outerLinearPrediction(
                values,
                frames: analysis.frames,
                centerIndex: index,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds
            ) ?? values[index]
            lock.lock()
            outerPredictions[key] = prediction
            lock.unlock()
            return prediction
        }

        private func localTimeWeightedAverage(
            _ kind: MotionPathKind,
            sourceRole: LocalAverageSourceRole,
            sourceVariant: UInt64,
            source: EstimatedPath,
            analysis: StabilizerPreparedAnalysis,
            index: Int,
            windowSeconds: Double
        ) -> Float {
            let key = LocalAverageCacheKey(
                kind: kind,
                sourceRole: sourceRole,
                sourceVariant: sourceVariant,
                index: index,
                windowSeconds: windowSeconds.bitPattern
            )
            lock.lock()
            if let cached = localAverages[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let centerTime = analysis.frames[index].time
            let localIndices = AutoStabilizationEstimator.indicesWithinTimeRadius(
                analysis.frames,
                centerTime: centerTime,
                radiusSeconds: max(0.0, windowSeconds * 0.5)
            )
            let activeIndices = localIndices.isEmpty ? [index] : localIndices
            let average = AutoStabilizationEstimator.timeWeightedAverage(
                source,
                frames: analysis.frames,
                indices: activeIndices,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            )
            lock.lock()
            localAverages[key] = average
            lock.unlock()
            return average
        }
    }

    private static func renderEstimateCache(for analysis: StabilizerPreparedAnalysis) -> RenderEstimateCache {
        guard let key = renderEstimateCacheStoreKey(for: analysis) else {
            return RenderEstimateCache()
        }

        sharedRenderEstimateCacheLock.lock()
        if let existingCache = sharedRenderEstimateCaches[key] {
            if let existingIndex = sharedRenderEstimateCacheOrder.firstIndex(of: key) {
                sharedRenderEstimateCacheOrder.remove(at: existingIndex)
            }
            sharedRenderEstimateCacheOrder.append(key)
            sharedRenderEstimateCacheLock.unlock()
            return existingCache
        }

        let cache = RenderEstimateCache()
        sharedRenderEstimateCaches[key] = cache
        sharedRenderEstimateCacheOrder.append(key)
        while sharedRenderEstimateCacheOrder.count > sharedRenderEstimateCacheLimit {
            let evictedKey = sharedRenderEstimateCacheOrder.removeFirst()
            sharedRenderEstimateCaches.removeValue(forKey: evictedKey)
        }
        sharedRenderEstimateCacheLock.unlock()
        return cache
    }

    private static func renderEstimateCacheStoreKey(for analysis: StabilizerPreparedAnalysis) -> RenderEstimateCacheStoreKey? {
        let frames = analysis.frames
        guard let firstFrame = frames.first, let lastFrame = frames.last else {
            return nil
        }
        let middleIndex = frames.count / 2
        guard frames.indices.contains(middleIndex),
              analysis.pathX.indices.contains(middleIndex),
              analysis.pathY.indices.contains(middleIndex),
              analysis.pathRoll.indices.contains(middleIndex),
              let firstPathX = analysis.pathX.first,
              let lastPathX = analysis.pathX.last,
              let firstPathY = analysis.pathY.first,
              let lastPathY = analysis.pathY.last,
              let firstPathRoll = analysis.pathRoll.first,
              let lastPathRoll = analysis.pathRoll.last
        else {
            return nil
        }
        let middleFrame = frames[middleIndex]
        return RenderEstimateCacheStoreKey(
            frameCount: frames.count,
            firstTime: firstFrame.time.bitPattern,
            middleTime: middleFrame.time.bitPattern,
            lastTime: lastFrame.time.bitPattern,
            sampleWidth: firstFrame.sampleWidth,
            sampleHeight: firstFrame.sampleHeight,
            firstFingerprint: firstFrame.fingerprint,
            middleFingerprint: middleFrame.fingerprint,
            lastFingerprint: lastFrame.fingerprint,
            firstPathX: firstPathX.bitPattern,
            middlePathX: analysis.pathX[middleIndex].bitPattern,
            lastPathX: lastPathX.bitPattern,
            firstPathY: firstPathY.bitPattern,
            middlePathY: analysis.pathY[middleIndex].bitPattern,
            lastPathY: lastPathY.bitPattern,
            firstPathRoll: firstPathRoll.bitPattern,
            middlePathRoll: analysis.pathRoll[middleIndex].bitPattern,
            lastPathRoll: lastPathRoll.bitPattern
        )
    }

    private static func values(for kind: MotionPathKind, analysis: StabilizerPreparedAnalysis) -> [Float] {
        switch kind {
        case .footstepX:
            return analysis.footstepPathX
        case .footstepY:
            return analysis.footstepPathY
        case .footstepRoll:
            return analysis.footstepPathRoll
        case .yaw:
            return analysis.pathYaw
        case .pitch:
            return analysis.pathPitch
        case .shearX:
            return analysis.pathShearX
        case .shearY:
            return analysis.pathShearY
        case .perspectiveX:
            return analysis.pathPerspectiveX
        case .perspectiveY:
            return analysis.pathPerspectiveY
        }
    }

    fileprivate static func metalError(_ message: String) -> NSError {
        NSError(
            domain: "com.justadev.TokyoWalkingStabilizer",
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

    static func proxyPlaybackEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> StabilizerAutoTransform {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        let frames = analysis.frames
        guard renderSeconds.isFinite, frames.count >= 3 else {
            return .identity
        }

        let lookup = frameLookup(at: renderSeconds, in: frames)
        let centerIndex = lookup.centerIndex
        guard frames.indices.contains(centerIndex) else {
            return .identity
        }
        let frame = frames[centerIndex]
        let xScale = outputSize.x / Float(max(1, frame.sampleWidth))
        let yScale = outputSize.y / Float(max(1, frame.sampleHeight))
        let smoothingWindow = min(max(panSmoothSeconds, renderTemporalSmoothingWindowSeconds), 3.0)
        let localIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: smoothingWindow * 0.5
        )
        let activeIndices = localIndices.isEmpty ? [centerIndex] : localIndices

        let currentX = interpolatedValue(analysis.footstepPathX, using: lookup.interpolation)
        let currentY = interpolatedValue(analysis.footstepPathY, using: lookup.interpolation)
        let currentRoll = interpolatedValue(analysis.footstepPathRoll, using: lookup.interpolation)
        let baselineX = timeWeightedAverage(
            analysis.footstepPathX,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothingWindow
        )
        let baselineY = timeWeightedAverage(
            analysis.footstepPathY,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothingWindow
        )
        let baselineRoll = timeWeightedAverage(
            analysis.footstepPathRoll,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothingWindow
        )

        let xStrength = clamp(Float(max(strengths.microJitterX, strengths.strideWobbleX, strengths.panStabilizationStrength)), min: 0.0, max: 1.0)
        let yStrength = clamp(Float(max(strengths.microJitterY, strengths.strideWobbleY)), min: 0.0, max: 1.0)
        let rotationStrength = clamp(Float(max(strengths.microJitterRotation, strengths.strideWobbleRotation)), min: 0.0, max: 1.0)
        let pixelOffset = vector_float2(
            -(currentX - baselineX) * xScale * xStrength,
            -(currentY - baselineY) * yScale * yStrength
        )
        let rotationDegrees = -(currentRoll - baselineRoll) * rotationStrength
        let trackingConfidence = interpolatedValue(analysis.analysisConfidence, using: lookup.interpolation)
        let warpConfidence = interpolatedValue(analysis.warpConfidence, using: lookup.interpolation)
        let blurAmount = interpolatedValue(analysis.blurAmounts, using: lookup.interpolation)
        let residual = interpolatedValue(analysis.residuals, using: lookup.interpolation)
        let turnTrackingConfidence = residualAdjustedTrackingConfidence(
            trackingConfidence,
            residual: residual,
            multiplier: 0.9,
            qualityModel: analysis.qualityModel
        )
        let turnConfidence = turnSmoothingConfidence(
            bandValue: currentX - baselineX,
            trackingConfidence: turnTrackingConfidence
        )
        let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(centerIndex) ? analysis.acceptedBlockCounts[centerIndex] : 0
        let totalBlockCount = analysis.totalBlockCounts.indices.contains(centerIndex) ? analysis.totalBlockCounts[centerIndex] : 0
        let searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(centerIndex) ? analysis.searchRadiusHitCounts[centerIndex] : 0
        let searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(centerIndex) ? analysis.searchRadiusTotalCounts[centerIndex] : 0

        return StabilizerAutoTransform(
            pixelOffset: pixelOffset,
            macroPixelOffset: vector_float2(0.0, 0.0),
            microPixelOffset: vector_float2(0.0, 0.0),
            strideWobblePixelOffset: pixelOffset,
            footstepJitterRotationDegrees: 0.0,
            strideWobbleRotationDegrees: rotationDegrees,
            rotationDegrees: rotationDegrees,
            rawPixelOffset: pixelOffset,
            rawRotationDegrees: rotationDegrees,
            temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
            temporalSmoothingRotationDelta: 0.0,
            temporalSmoothingSampleCount: Int32(activeIndices.count),
            temporalSmoothingWindowSeconds: Float(smoothingWindow),
            effectiveMicroJitterStrength: vector_float3(xStrength, yStrength, rotationStrength),
            effectiveStrideWobbleStrength: vector_float3(xStrength, yStrength, rotationStrength),
            warpConfidence: warpConfidence,
            microConfidence: xStrength,
            strideConfidence: xStrength,
            turnConfidence: turnConfidence,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            yawPitchProxy: vector_float2(0.0, 0.0),
            shear: vector_float2(0.0, 0.0),
            perspective: vector_float2(0.0, 0.0),
            blurAmount: blurAmount,
            trackingConfidence: trackingConfidence,
            walkingTrackingConfidence: trackingConfidence,
            motionConfidence: trackingConfidence,
            residual: residual,
            footstepImpulse: vector_float3(currentX - baselineX, currentY - baselineY, currentRoll - baselineRoll),
            rawFootstepCorrection: pixelOffset,
            limitedFootstepCorrection: pixelOffset,
            footstepPulseLimited: vector_float2(0.0, 0.0),
            searchRadiusHitCount: searchRadiusHitCount,
            searchRadiusTotalCount: searchRadiusTotalCount
        )
    }

    static func autoCropWindowEstimate(
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

        return rawEstimate(
            preparedAnalysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache(for: analysis)
        )
    }

    private static func rawEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache,
        limitFootstepContinuity: Bool = true
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return .identity
        }

        let effectiveStrideWobbleWindowSeconds = strideWobbleWindowSeconds
        let smoothWindowSeconds = max(effectiveStrideWobbleWindowSeconds, panSmoothSeconds)
        let frameLookup = frameLookup(at: renderSeconds, in: frames)
        let centerIndex = frameLookup.centerIndex
        let frameInterpolation = frameLookup.interpolation
        let windowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: smoothWindowSeconds * 0.5
        )
        let activeIndices = windowIndices.isEmpty ? Array(frames.indices) : windowIndices
        let strideWobbleWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: effectiveStrideWobbleWindowSeconds * 0.5
        )
        let strideWobbleActiveIndices = strideWobbleWindowIndices.isEmpty ? [centerIndex] : strideWobbleWindowIndices
        let farFieldWarpGateWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: farFieldWarpOuterWindowSeconds * 0.5
        )
        let farFieldWarpGateActiveIndices = farFieldWarpGateWindowIndices.isEmpty ? [centerIndex] : farFieldWarpGateWindowIndices
        let sampledIndices = uniqueSortedIndices(
            activeIndices + strideWobbleActiveIndices + [centerIndex] + frameInterpolation.indices,
            validCount: frames.count
        )
        let footstepBaselineXPath = cachedOuterLinearPredictionPath(
            .footstepX,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineYPath = cachedOuterLinearPredictionPath(
            .footstepY,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineRollPath = cachedOuterLinearPredictionPath(
            .footstepRoll,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineYawPath = cachedOuterLinearPredictionPath(
            .yaw,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselinePitchPath = cachedOuterLinearPredictionPath(
            .pitch,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineShearXPath = cachedOuterLinearPredictionPath(
            .shearX,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineShearYPath = cachedOuterLinearPredictionPath(
            .shearY,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselinePerspectiveXPath = cachedOuterLinearPredictionPath(
            .perspectiveX,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselinePerspectiveYPath = cachedOuterLinearPredictionPath(
            .perspectiveY,
            analysis: analysis,
            indices: sampledIndices,
            innerWindowSeconds: farFieldWarpInnerWindowSeconds,
            outerWindowSeconds: farFieldWarpOuterWindowSeconds,
            cache: cache
        )

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let turnResidual = percentileValue(analysis.residuals, indices: activeIndices, percentile: 0.75)
        let strideResidual = percentileValue(analysis.residuals, indices: strideWobbleActiveIndices, percentile: 0.70)
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
            totalBlockCount: totalBlockCount,
            qualityModel: analysis.qualityModel
        )
        let walkingTrackingConfidence = walkingBandTrackingConfidence(
            motionConfidence: motionConfidence,
            residual: centerResidual,
            blurAmount: centerBlurAmount,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            qualityModel: analysis.qualityModel
        )

        let strideSampledIndices = uniqueSortedIndices(
            strideWobbleActiveIndices + [centerIndex] + frameInterpolation.indices,
            validCount: frames.count
        )
        let strideSupportIndices = uniqueSortedIndices(
            strideSampledIndices + strideSampledIndices.flatMap { sampleIndex -> [Int] in
                guard frames.indices.contains(sampleIndex) else {
                    return []
                }
                return indicesWithinTimeRadius(
                    frames,
                    centerTime: frames[sampleIndex].time,
                    radiusSeconds: effectiveStrideWobbleWindowSeconds * 0.5
                )
            },
            validCount: frames.count
        )
        let turnStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineXPath,
            analysis: analysis,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let footstepXTurnGateScales = turnOwnershipGateScales(
            values: turnStrideSmoothedXPath,
            analysis: analysis,
            targetIndices: strideSupportIndices,
            windowSeconds: smoothWindowSeconds
        )
        let footstepCleanXPath = confidenceCleanedFootstepPath(
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales
        )
        let footstepCleanYPath = confidenceCleanedFootstepPath(
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepCleanRollPath = confidenceCleanedFootstepPath(
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScaleDegrees
        )
        let strideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: smoothWindowSeconds.bitPattern,
            source: footstepCleanXPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let strideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepStrideCleaned,
            source: footstepCleanYPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let strideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepStrideCleaned,
            source: footstepCleanRollPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let turnSmoothX = timeWeightedMonotonicSCurveValue(
            turnStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(turnStrideSmoothedXPath, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
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
        let turnStrideSmoothX = interpolatedValue(turnStrideSmoothedXPath, using: frameInterpolation)
        let rawFootstepXConfidence = footstepFrameConfidence(
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepYConfidence = footstepFrameConfidence(
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepRollConfidence = footstepFrameConfidence(
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScaleDegrees
        )
        let strideBandX = footstepCleanXAtRender - strideSmoothX
        let strideBandY = footstepCleanYAtRender - strideSmoothY
        let strideBandRoll = footstepCleanRollAtRender - strideSmoothRoll
        let panBandX = turnStrideSmoothX - turnSmoothX
        let strideTrackingConfidence = residualAdjustedTrackingConfidence(
            walkingTrackingConfidence,
            residual: strideResidual,
            multiplier: 0.6,
            qualityModel: analysis.qualityModel
        )
        let rawStrideXConfidence = strideWobbleConfidence(
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
        let turnTrackingConfidence = residualAdjustedTrackingConfidence(
            trackingConfidence,
            residual: turnResidual,
            multiplier: 0.9,
            qualityModel: analysis.qualityModel
        )
        let confidence = turnSmoothingConfidence(
            bandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnershipX = turnOwnershipConfidence(
            values: turnStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            turnBandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let footstepXTurnGate = clamp(1.0 - (turnOwnershipX * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        let strideXTurnGate = clamp(1.0 - (turnOwnershipX * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
        let footstepXConfidence = rawFootstepXConfidence * footstepXTurnGate
        let strideXConfidence = rawStrideXConfidence * strideXTurnGate
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let panCorrectionStrength = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: confidence)
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
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
        let rawMicroCompensationX = -(footstepPathXAtRender - microImpulseBaselineX) * xScale * microXCorrectionStrength
        let rawMicroCompensationY = -(footstepPathYAtRender - footstepBaselineY) * yScale * microYCorrectionStrength
        let limitedMicroCompensationX = limitFootstepContinuity && strengths.microJitterX > 0.0
            ? footstepContinuityLimitedCorrection(
                values: analysis.footstepPathX,
                baselineValues: footstepBaselineXPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationX,
                outputScale: xScale,
                requestedStrength: strengths.microJitterX,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepXTurnGate
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationX, limitedAmount: 0.0)
        let limitedMicroCompensationY = limitFootstepContinuity && strengths.microJitterY > 0.0
            ? footstepContinuityLimitedCorrection(
                values: analysis.footstepPathY,
                baselineValues: footstepBaselineYPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationY,
                outputScale: yScale,
                requestedStrength: strengths.microJitterY,
                fullImpulseScale: footstepImpulseFullScalePixels
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationY, limitedAmount: 0.0)
        let microCompensationX = limitedMicroCompensationX.limitedCorrection
        let microCompensationY = limitedMicroCompensationY.limitedCorrection
        let microCompensationRotation = -(footstepPathRollAtRender - microImpulseBaselineRoll) * microRotationCorrectionStrength
        let footstepImpulse = vector_float3(
            footstepPathXAtRender - microImpulseBaselineX,
            footstepPathYAtRender - footstepBaselineY,
            footstepPathRollAtRender - microImpulseBaselineRoll
        )
        let strideCompensationX = -strideBandX * xScale * strideXCorrectionStrength
        let strideCompensationY = -strideBandY * yScale * strideYCorrectionStrength
        let strideCompensationRotation = -strideBandRoll * strideRotationCorrectionStrength
        let macroPixelOffset = vector_float2(macroCompensationX, macroCompensationY)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let strideWobblePixelOffset = vector_float2(strideCompensationX, strideCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x + strideWobblePixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + strideWobblePixelOffset.y
        let compensationRotation = (macroCompensationRotation * confidence) + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrength = clamp(Float(strengths.farFieldWarp), min: 0.0, max: 4.0)
        let farFieldWarpTrackingConfidence = stableFarFieldWarpTrackingConfidence(
            analysis: analysis,
            indices: farFieldWarpGateActiveIndices,
            currentTrackingConfidence: trackingConfidence
        )
        let farFieldWarpEdgeQuality = stableFarFieldWarpEdgeQuality(
            analysis: analysis,
            indices: farFieldWarpGateActiveIndices,
            currentSearchRadiusHitCount: searchRadiusHitCount,
            currentSearchRadiusTotalCount: searchRadiusTotalCount
        )
        let farFieldWarpGate = farFieldWarpRenderGate(
            warpConfidence: warpConfidence,
            trackingConfidence: farFieldWarpTrackingConfidence,
            edgeQuality: farFieldWarpEdgeQuality
        )
        let appliedWarpConfidence = clamp(warpConfidence * farFieldWarpGate, min: 0.0, max: 1.0)
        let yawPitchProxy = vector_float2(
            clamp(
                farFieldWarpBandValue(
                    values: analysis.pathYaw,
                    baselineValues: farFieldBaselineYawPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    confidence: appliedWarpConfidence
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
                    confidence: appliedWarpConfidence
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
                    confidence: appliedWarpConfidence
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
                    confidence: appliedWarpConfidence
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
                    confidence: appliedWarpConfidence
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
                    confidence: appliedWarpConfidence
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
            turnConfidence: confidence,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            yawPitchProxy: yawPitchProxy,
            shear: shear,
            perspective: perspective,
            blurAmount: blurAmount,
            trackingConfidence: trackingConfidence,
            walkingTrackingConfidence: walkingTrackingConfidence,
            motionConfidence: motionConfidence,
            residual: centerResidual,
            footstepImpulse: footstepImpulse,
            rawFootstepCorrection: vector_float2(rawMicroCompensationX, rawMicroCompensationY),
            limitedFootstepCorrection: vector_float2(microCompensationX, microCompensationY),
            footstepPulseLimited: vector_float2(limitedMicroCompensationX.limitedAmount, limitedMicroCompensationY.limitedAmount),
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
        let renderEstimateCache = renderEstimateCache(for: analysis)
        let rawCenterTransform = rawEstimate(
            preparedAnalysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache
        )
        let sampleCount = max(3, renderTemporalSmoothingSampleCount)
        let centerSample = sampleCount / 2
        let halfWindow = renderTemporalSmoothingWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = renderTemporalSmoothingWindowSeconds / denominator
        let sigma = max(1e-6, halfWindow * 0.5)
        var weightedSamples: [(transform: StabilizerAutoTransform, weight: Float, offsetSeconds: Double)] = []
        weightedSamples.reserveCapacity(sampleCount)

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
            let transform: StabilizerAutoTransform
            if sampleIndex == centerSample {
                transform = rawCenterTransform
            } else {
                let sampleFrameIndex = frameLookup(at: sampleSeconds, in: frames).centerIndex
                transform = renderEstimateCache.rawTransform(
                    analysis: analysis,
                    index: sampleFrameIndex,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: strengths,
                    limitFootstepContinuity: false
                )
            }
            weightedSamples.append((transform: transform, weight: weight, offsetSeconds: offset))
        }

        guard !weightedSamples.isEmpty else {
            return rawCenterTransform
        }
        let broadTransformSamples = weightedSamples.map { sample in
            (transform: sample.transform, weight: sample.weight)
        }
        var smoothedTransform = weightedAverageTransform(broadTransformSamples)
        let shortWarpSamples = farFieldWarpSmoothingSamples(weightedSamples)
        let smoothedWarpTransform = shortWarpSamples.isEmpty
            ? rawCenterTransform
            : weightedAverageTransform(shortWarpSamples)
        let smoothedWarpConfidence = clamp(smoothedWarpTransform.warpConfidence, min: 0.0, max: 1.0)
        let centerWarpConfidence = clamp(rawCenterTransform.warpConfidence, min: 0.0, max: 1.0)
        let cappedWarpConfidence = min(smoothedWarpConfidence, centerWarpConfidence)
        let centerWarpScale = smoothedWarpConfidence > 1e-6 ? cappedWarpConfidence / smoothedWarpConfidence : 0.0
        smoothedTransform.warpConfidence = smoothedWarpConfidence
        smoothedTransform.yawPitchProxy = smoothedWarpTransform.yawPitchProxy * centerWarpScale
        smoothedTransform.shear = smoothedWarpTransform.shear * centerWarpScale
        smoothedTransform.perspective = smoothedWarpTransform.perspective * centerWarpScale
        smoothedTransform.trackingConfidence = clamp(smoothedTransform.trackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.walkingTrackingConfidence = clamp(smoothedTransform.walkingTrackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.motionConfidence = clamp(smoothedTransform.motionConfidence, min: 0.0, max: 1.0)
        smoothedTransform.residual = rawCenterTransform.residual
        smoothedTransform.searchRadiusHitCount = rawCenterTransform.searchRadiusHitCount
        smoothedTransform.searchRadiusTotalCount = rawCenterTransform.searchRadiusTotalCount
        smoothedTransform.pixelOffset = smoothedTransform.macroPixelOffset
            + smoothedTransform.microPixelOffset
            + smoothedTransform.strideWobblePixelOffset
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

    private static func farFieldWarpSmoothingSamples(
        _ samples: [(transform: StabilizerAutoTransform, weight: Float, offsetSeconds: Double)]
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        let halfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        let sigma = max(1e-6, halfWindow * 0.5)
        var smoothedSamples: [(transform: StabilizerAutoTransform, weight: Float)] = []
        smoothedSamples.reserveCapacity(samples.count)
        for sample in samples {
            if abs(sample.offsetSeconds) > halfWindow + 1e-9 {
                continue
            }
            let normalizedDistance = sample.offsetSeconds / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            if weight <= 0.0001 {
                continue
            }
            smoothedSamples.append((transform: sample.transform, weight: weight))
        }
        return smoothedSamples
    }

    private static func weightedAverageTransform(
        _ samples: [(transform: StabilizerAutoTransform, weight: Float)]
    ) -> StabilizerAutoTransform {
        var totalWeight: Float = 0.0
        var pixelOffset = vector_float2(0.0, 0.0)
        var macroPixelOffset = vector_float2(0.0, 0.0)
        var microPixelOffset = vector_float2(0.0, 0.0)
        var strideWobblePixelOffset = vector_float2(0.0, 0.0)
        var footstepJitterRotationDegrees: Float = 0.0
        var strideWobbleRotationDegrees: Float = 0.0
        var rotationDegrees: Float = 0.0
        var rawPixelOffset = vector_float2(0.0, 0.0)
        var rawRotationDegrees: Float = 0.0
        var temporalSmoothingPixelDelta = vector_float2(0.0, 0.0)
        var temporalSmoothingRotationDelta: Float = 0.0
        var effectiveMicroJitterStrength = vector_float3(0.0, 0.0, 0.0)
        var effectiveStrideWobbleStrength = vector_float3(0.0, 0.0, 0.0)
        var warpConfidence: Float = 0.0
        var microConfidence: Float = 0.0
        var strideConfidence: Float = 0.0
        var turnConfidence: Float = 0.0
        var acceptedBlockCount: Float = 0.0
        var totalBlockCount: Float = 0.0
        var yawPitchProxy = vector_float2(0.0, 0.0)
        var shear = vector_float2(0.0, 0.0)
        var perspective = vector_float2(0.0, 0.0)
        var blurAmount: Float = 0.0
        var trackingConfidence: Float = 0.0
        var walkingTrackingConfidence: Float = 0.0
        var motionConfidence: Float = 0.0
        var residual: Float = 0.0
        var footstepImpulse = vector_float3(0.0, 0.0, 0.0)
        var rawFootstepCorrection = vector_float2(0.0, 0.0)
        var limitedFootstepCorrection = vector_float2(0.0, 0.0)
        var footstepPulseLimited = vector_float2(0.0, 0.0)
        var searchRadiusHitCount: Float = 0.0
        var searchRadiusTotalCount: Float = 0.0

        for sample in samples {
            let transform = sample.transform
            let weight = sample.weight
            totalWeight += weight
            pixelOffset += transform.pixelOffset * weight
            macroPixelOffset += transform.macroPixelOffset * weight
            microPixelOffset += transform.microPixelOffset * weight
            strideWobblePixelOffset += transform.strideWobblePixelOffset * weight
            footstepJitterRotationDegrees += transform.footstepJitterRotationDegrees * weight
            strideWobbleRotationDegrees += transform.strideWobbleRotationDegrees * weight
            rotationDegrees += transform.rotationDegrees * weight
            rawPixelOffset += transform.rawPixelOffset * weight
            rawRotationDegrees += transform.rawRotationDegrees * weight
            temporalSmoothingPixelDelta += transform.temporalSmoothingPixelDelta * weight
            temporalSmoothingRotationDelta += transform.temporalSmoothingRotationDelta * weight
            effectiveMicroJitterStrength += transform.effectiveMicroJitterStrength * weight
            effectiveStrideWobbleStrength += transform.effectiveStrideWobbleStrength * weight
            warpConfidence += transform.warpConfidence * weight
            microConfidence += transform.microConfidence * weight
            strideConfidence += transform.strideConfidence * weight
            turnConfidence += transform.turnConfidence * weight
            acceptedBlockCount += Float(transform.acceptedBlockCount) * weight
            totalBlockCount += Float(transform.totalBlockCount) * weight
            yawPitchProxy += transform.yawPitchProxy * weight
            shear += transform.shear * weight
            perspective += transform.perspective * weight
            blurAmount += transform.blurAmount * weight
            trackingConfidence += transform.trackingConfidence * weight
            walkingTrackingConfidence += transform.walkingTrackingConfidence * weight
            motionConfidence += transform.motionConfidence * weight
            residual += transform.residual * weight
            footstepImpulse += transform.footstepImpulse * weight
            rawFootstepCorrection += transform.rawFootstepCorrection * weight
            limitedFootstepCorrection += transform.limitedFootstepCorrection * weight
            footstepPulseLimited += transform.footstepPulseLimited * weight
            searchRadiusHitCount += Float(transform.searchRadiusHitCount) * weight
            searchRadiusTotalCount += Float(transform.searchRadiusTotalCount) * weight
        }
        guard totalWeight > 0.0 else {
            return .identity
        }

        return StabilizerAutoTransform(
            pixelOffset: pixelOffset / totalWeight,
            macroPixelOffset: macroPixelOffset / totalWeight,
            microPixelOffset: microPixelOffset / totalWeight,
            strideWobblePixelOffset: strideWobblePixelOffset / totalWeight,
            footstepJitterRotationDegrees: footstepJitterRotationDegrees / totalWeight,
            strideWobbleRotationDegrees: strideWobbleRotationDegrees / totalWeight,
            rotationDegrees: rotationDegrees / totalWeight,
            rawPixelOffset: rawPixelOffset / totalWeight,
            rawRotationDegrees: rawRotationDegrees / totalWeight,
            temporalSmoothingPixelDelta: temporalSmoothingPixelDelta / totalWeight,
            temporalSmoothingRotationDelta: temporalSmoothingRotationDelta / totalWeight,
            temporalSmoothingSampleCount: Int32(samples.count),
            temporalSmoothingWindowSeconds: 0.0,
            effectiveMicroJitterStrength: effectiveMicroJitterStrength / totalWeight,
            effectiveStrideWobbleStrength: effectiveStrideWobbleStrength / totalWeight,
            warpConfidence: warpConfidence / totalWeight,
            microConfidence: microConfidence / totalWeight,
            strideConfidence: strideConfidence / totalWeight,
            turnConfidence: turnConfidence / totalWeight,
            acceptedBlockCount: Int32((acceptedBlockCount / totalWeight).rounded()),
            totalBlockCount: Int32((totalBlockCount / totalWeight).rounded()),
            yawPitchProxy: yawPitchProxy / totalWeight,
            shear: shear / totalWeight,
            perspective: perspective / totalWeight,
            blurAmount: blurAmount / totalWeight,
            trackingConfidence: trackingConfidence / totalWeight,
            walkingTrackingConfidence: walkingTrackingConfidence / totalWeight,
            motionConfidence: motionConfidence / totalWeight,
            residual: residual / totalWeight,
            footstepImpulse: footstepImpulse / totalWeight,
            rawFootstepCorrection: rawFootstepCorrection / totalWeight,
            limitedFootstepCorrection: limitedFootstepCorrection / totalWeight,
            footstepPulseLimited: footstepPulseLimited / totalWeight,
            searchRadiusHitCount: Int32(searchRadiusHitCount / totalWeight),
            searchRadiusTotalCount: Int32(searchRadiusTotalCount / totalWeight)
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
        let sample = try analysisSample(from: tile, at: frameTime, sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        return analysisFrame(from: sample, metrics: try frameMetrics(sample))
    }

    static func analysisSample(
        from tile: FxImageTile,
        at frameTime: CMTime? = nil,
        sampleWidth: Int,
        sampleHeight: Int,
        downsampleBufferPool: StabilizerDownsampleBufferPool? = nil,
        retainPixels: Bool = true
    ) throws -> StabilizerAnalysisSample {
        let startedAt = CFAbsoluteTimeGetCurrent()
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
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw metalError("Stabilizer Metal downsample resources were unavailable for Host Analysis.")
        }
        let outputBufferLength = sampleWidth * sampleHeight
        let outputLease = try downsampleBufferPool?.leaseBuffer(device: device, length: outputBufferLength)
        let outputBuffer: MTLBuffer
        if let outputLease {
            outputBuffer = outputLease.buffer
        } else {
            guard let allocatedOutputBuffer = device.makeBuffer(length: outputBufferLength, options: .storageModeShared) else {
                throw metalError("Could not allocate Stabilizer Metal downsample buffer.")
            }
            outputBuffer = allocatedOutputBuffer
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

        let pixelCount = sampleWidth * sampleHeight
        let pixels: [UInt8]
        if retainPixels {
            let pointer = outputBuffer.contents().assumingMemoryBound(to: UInt8.self)
            pixels = Array(UnsafeBufferPointer(start: pointer, count: pixelCount))
        } else {
            pixels = []
        }
        let downsampleMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
        os_log(
            "Host Analysis downsample frame %{public}.3f sample %{public}dx%{public}d took %{public}.3f ms; reused output buffer %{public}@; retained pixels %{public}@.",
            log: stabilizerHostAnalysisLog,
            type: .debug,
            time,
            sampleWidth,
            sampleHeight,
            downsampleMilliseconds,
            outputLease?.reused == true ? "yes" : "no",
            retainPixels ? "yes" : "no"
        )
        return StabilizerAnalysisSample(
            time: time,
            pixels: pixels,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            lumaBuffer: outputBuffer,
            lumaBufferLease: outputLease,
            downsampleMilliseconds: downsampleMilliseconds
        )
    }

    fileprivate static func frameMetrics(_ sample: StabilizerAnalysisSample) throws -> StabilizerFrameMetrics {
        let pixelCount = sample.sampleWidth * sample.sampleHeight
        if !sample.pixels.isEmpty {
            guard sample.pixels.count == pixelCount else {
                throw metalError("Stabilizer analysis sample retained an unexpected pixel count.")
            }
            return frameMetrics(sample.pixels, sampleWidth: sample.sampleWidth, sampleHeight: sample.sampleHeight)
        }
        guard sample.lumaBuffer.length >= pixelCount else {
            throw metalError("Stabilizer analysis luma buffer was smaller than the expected sample size.")
        }
        let pointer = sample.lumaBuffer.contents().assumingMemoryBound(to: UInt8.self)
        return frameMetrics(pointer, byteCount: pixelCount, sampleWidth: sample.sampleWidth, sampleHeight: sample.sampleHeight)
    }

    fileprivate static func analysisFrame(from sample: StabilizerAnalysisSample, metrics: StabilizerFrameMetrics) -> StabilizerAnalysisFrame {
        StabilizerAnalysisFrame(
            time: sample.time,
            pixels: sample.pixels,
            sampleWidth: sample.sampleWidth,
            sampleHeight: sample.sampleHeight,
            blurAmount: metrics.blurAmount,
            fingerprint: metrics.fingerprint
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
            qualityModel: .fxplugHostAnalysis,
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
        try pairMotionResult(
            context: context,
            previous: previous,
            current: current,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        ).motion
    }

    fileprivate static func pairMotionResult(
        context: MetalAnalysisContext,
        previous: MTLBuffer,
        current: MTLBuffer,
        sampleWidth: Int,
        sampleHeight: Int,
        motionBlockBatch cachedMotionBlockBatch: StabilizerMotionBlockBatch? = nil,
        motionBlockUniformBuffer: MTLBuffer? = nil,
        overlappedMetricsWork: (() throws -> StabilizerFrameMetrics)? = nil
    ) throws -> PairMotionResult {
        let pairStartedAt = CFAbsoluteTimeGetCurrent()
        let blockBatch = cachedMotionBlockBatch ?? motionBlockBatch(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let blocks = blockBatch.blocks
        let shiftResult = try estimateGlobalAndLocalShifts(
            context: context,
            previous: previous,
            current: current,
            blockBatch: blockBatch,
            localUniformBuffer: motionBlockUniformBuffer,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            overlappedMetricsWork: overlappedMetricsWork
        )
        let global = shiftResult.global
        let blockShifts = shiftResult.blockShifts
        let modelScoreReference = median(
            blockShifts
                .map(\.score)
                .filter(\.isFinite)
        ) ?? global.score
        os_log(
            "Host Analysis fused shift scoring pair sample %{public}dx%{public}d blocks %{public}d global(est) %{public}.3f ms local(est) %{public}.3f ms command %{public}.3f ms overlapped metrics %{public}.3f ms total %{public}.3f ms.",
            log: stabilizerHostAnalysisLog,
            type: .debug,
            sampleWidth,
            sampleHeight,
            blocks.count,
            shiftResult.globalMilliseconds,
            shiftResult.localBatchMilliseconds,
            shiftResult.commandMilliseconds,
            shiftResult.overlappedMetricsMilliseconds,
            (CFAbsoluteTimeGetCurrent() - pairStartedAt) * 1000.0
        )
        let acceptedBlocks = acceptedMotionBlocks(blockShifts, global: (global.dx, global.dy, global.score))
        let motionBlocksForModel = acceptedBlocks.count >= minimumAcceptedMotionBlocks ? acceptedBlocks : blockShifts
        let robustDx = weightedMedian(motionBlocksForModel.map {
            ($0.dx, motionBlockWeight($0, scoreReference: modelScoreReference))
        }) ?? global.dx
        let robustDy = weightedMedian(motionBlocksForModel.map {
            ($0.dy, motionBlockWeight($0, scoreReference: modelScoreReference))
        }) ?? global.dy
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

        return PairMotionResult(
            motion: PairMotion(
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
            ),
            timing: StabilizerPairMotionTiming(
                globalMilliseconds: shiftResult.globalMilliseconds,
                localBatchMilliseconds: shiftResult.localBatchMilliseconds,
                totalMilliseconds: (CFAbsoluteTimeGetCurrent() - pairStartedAt) * 1000.0
            ),
            overlappedFrameMetrics: shiftResult.overlappedFrameMetrics,
            overlappedMetricsMilliseconds: shiftResult.overlappedMetricsMilliseconds
        )
    }

    fileprivate static func frameMetrics(_ pixels: [UInt8], sampleWidth: Int, sampleHeight: Int) -> StabilizerFrameMetrics {
        pixels.withUnsafeBufferPointer { buffer in
            frameMetrics(
                buffer.baseAddress!,
                byteCount: pixels.count,
                sampleWidth: sampleWidth,
                sampleHeight: sampleHeight
            )
        }
    }

    private static func frameMetrics(
        _ pixels: UnsafePointer<UInt8>,
        byteCount: Int,
        sampleWidth: Int,
        sampleHeight: Int
    ) -> StabilizerFrameMetrics {
        var totalGradient: Float = 0.0
        var edgeSampleCount: Float = 0.0
        var strongEdgeSampleCount: Float = 0.0
        var count: Float = 0.0
        for y in 0..<sampleHeight {
            let row = y * sampleWidth
            for x in 0..<sampleWidth {
                let index = row + x
                if y > 0, y < sampleHeight - 1, x > 0, x < sampleWidth - 1 {
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
        }
        let blur: Float
        if count > 0.0 {
            let meanGradient = totalGradient / count
            let edgeCoverage = edgeSampleCount / count
            let strongEdgeCoverage = strongEdgeSampleCount / count
            let sharpnessEvidence = max(meanGradient, edgeCoverage * 0.45, strongEdgeCoverage * 0.9)
            blur = 1.0 - clamp((sharpnessEvidence - 0.006) / 0.055, min: 0.0, max: 1.0)
        } else {
            blur = 1.0
        }
        return StabilizerFrameMetrics(
            blurAmount: blur,
            fingerprint: StabilizerAnalysisFrame.fingerprint(pixels, byteCount: byteCount)
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
        let columns = max(2, min(7, usableWidth / 18))
        let rows = max(2, min(5, usableHeight / 12))
        guard columns > 0, rows > 0 else {
            return []
        }

        var rowEdges: [(y0: Int, y1: Int)] = []
        var columnEdges: [(x0: Int, x1: Int)] = []
        rowEdges.reserveCapacity(rows)
        columnEdges.reserveCapacity(columns)
        for row in 0..<rows {
            rowEdges.append((
                y0: verticalMargin + ((usableHeight * row) / rows),
                y1: verticalMargin + ((usableHeight * (row + 1)) / rows)
            ))
        }
        for column in 0..<columns {
            columnEdges.append((
                x0: horizontalMargin + ((usableWidth * column) / columns),
                x1: horizontalMargin + ((usableWidth * (column + 1)) / columns)
            ))
        }

        var blocks: [StabilizerMotionBlock] = []
        func appendBlock(x0: Int, x1: Int, y0: Int, y1: Int) {
            let width = x1 - x0
            let height = y1 - y0
            guard width >= staggeredMotionBlockMinimumWidth, height >= staggeredMotionBlockMinimumHeight else {
                return
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

        for row in 0..<rows {
            let y0 = rowEdges[row].y0
            let y1 = rowEdges[row].y1
            for column in 0..<columns {
                appendBlock(
                    x0: columnEdges[column].x0,
                    x1: columnEdges[column].x1,
                    y0: y0,
                    y1: y1
                )
            }
        }

        if columns >= 3 {
            for row in 0..<rows {
                let y0 = rowEdges[row].y0
                let y1 = rowEdges[row].y1
                let centerY = Float(y0) + (Float(y1 - y0) * 0.5)
                guard farFieldWeight(centerY: centerY, sampleHeight: sampleHeight) >= staggeredMotionBlockFarFieldThreshold else {
                    continue
                }
                for column in 0..<(columns - 1) {
                    appendBlock(
                        x0: (columnEdges[column].x0 + columnEdges[column].x1) / 2,
                        x1: (columnEdges[column + 1].x0 + columnEdges[column + 1].x1) / 2,
                        y0: y0,
                        y1: y1
                    )
                }
            }
        }
        return blocks
    }

    fileprivate static func motionBlockBatch(sampleWidth: Int, sampleHeight: Int) -> StabilizerMotionBlockBatch {
        let blocks = motionBlocks(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let localStride: UInt32 = 1
        let localSearchRadius = analysisLocalSearchRadius(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let uniforms = blocks.map { block in
            StabilizerShiftBatchUniforms(
                width: UInt32(sampleWidth),
                height: UInt32(sampleHeight),
                x0: UInt32(block.x0),
                y0: UInt32(block.y0),
                regionWidth: UInt32(block.width),
                regionHeight: UInt32(block.height),
                centerX: 0,
                centerY: 0,
                radius: UInt32(localSearchRadius),
                stride: max(1, localStride)
            )
        }
        return StabilizerMotionBlockBatch(
            blocks: blocks,
            uniforms: uniforms,
            maxBlockHeight: blocks.map(\.height).max() ?? 0
        )
    }

    private static func analysisGlobalSearchRadius(sampleWidth: Int, sampleHeight: Int) -> Int {
        let shortSide = min(sampleWidth, sampleHeight)
        let scaledRadius = Int((Float(shortSide) / 120.0).rounded(.up))
        return max(minimumGlobalSearchRadius, min(maximumGlobalSearchRadius, scaledRadius))
    }

    private static func analysisLocalSearchRadius(sampleWidth: Int, sampleHeight: Int) -> Int {
        let globalRadius = analysisGlobalSearchRadius(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let scaledRadius = Int((Float(globalRadius) / 3.25).rounded(.up))
        return max(minimumLocalSearchRadius, min(maximumLocalSearchRadius, scaledRadius))
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
        let scoreLimit = max(scoreMedian * 1.65, scoreMedian + 0.020)
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
        let distanceAccepted = clusterCandidates.filter {
            hypotf($0.dx - medianDx, $0.dy - medianDy) <= distanceLimit
        }
        guard distanceAccepted.count >= minimumAcceptedMotionBlocks else {
            return []
        }
        let centerSafeAccepted = distanceAccepted.filter { !$0.searchRadiusHit }
        if centerSafeAccepted.count >= minimumAcceptedMotionBlocks {
            return centerSafeAccepted
        }
        return distanceAccepted
    }

    private static func motionBlockWeight(_ shift: StabilizerBlockShift, scoreReference: Float) -> Float {
        let baseWeight = shift.block.farFieldWeight
        guard shift.score.isFinite else {
            return baseWeight * 0.05
        }
        let reference = max(0.001, scoreReference.isFinite ? scoreReference : shift.score)
        let scoreQuality = clamp(
            1.0 - ((shift.score - reference) / max(0.020, reference * 1.25)),
            min: 0.15,
            max: 1.0
        )
        let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
        return baseWeight * scoreQuality * searchHeadroom
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

    private static func shiftScoreChunkCount(regionHeight: Int, stride: UInt32) -> Int {
        let stride = max(1, Int(stride))
        let sampledRows = max(1, (max(1, regionHeight) + stride - 1) / stride)
        let targetRowsPerChunk = 8
        return max(1, min(128, (sampledRows + targetRowsPerChunk - 1) / targetRowsPerChunk))
    }

    private static func splitFusedShiftTiming(totalMilliseconds: Double, globalUnits: Int, localUnits: Int) -> (globalMilliseconds: Double, localMilliseconds: Double) {
        let globalUnits = max(1, globalUnits)
        let localUnits = max(1, localUnits)
        let totalUnits = Double(globalUnits + localUnits)
        return (
            globalMilliseconds: totalMilliseconds * (Double(globalUnits) / totalUnits),
            localMilliseconds: totalMilliseconds * (Double(localUnits) / totalUnits)
        )
    }

    private static func estimateGlobalAndLocalShifts(
        context: MetalAnalysisContext,
        previous: MTLBuffer,
        current: MTLBuffer,
        blockBatch: StabilizerMotionBlockBatch,
        localUniformBuffer: MTLBuffer?,
        sampleWidth: Int,
        sampleHeight: Int,
        overlappedMetricsWork: (() throws -> StabilizerFrameMetrics)?
    ) throws -> (
        global: (dx: Float, dy: Float, score: Float, searchRadiusHit: Bool),
        blockShifts: [StabilizerBlockShift],
        globalMilliseconds: Double,
        localBatchMilliseconds: Double,
        commandMilliseconds: Double,
        overlappedFrameMetrics: StabilizerFrameMetrics?,
        overlappedMetricsMilliseconds: Double
    ) {
        let blocks = blockBatch.blocks
        let globalSearchRadius = analysisGlobalSearchRadius(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let localSearchRadius = analysisLocalSearchRadius(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        guard !blocks.isEmpty else {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let pendingGlobal = try beginEstimateShift(
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
            let metricsStartedAt = CFAbsoluteTimeGetCurrent()
            let overlappedMetrics = try overlappedMetricsWork?()
            let overlappedMetricsMilliseconds = overlappedMetrics == nil ? 0.0 : (CFAbsoluteTimeGetCurrent() - metricsStartedAt) * 1000.0
            let global = try pendingGlobal.waitForResult()
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
            return (
                global: (global.dx, global.dy, global.score, global.searchRadiusHit),
                blockShifts: [],
                globalMilliseconds: elapsedMilliseconds,
                localBatchMilliseconds: 0.0,
                commandMilliseconds: elapsedMilliseconds,
                overlappedFrameMetrics: overlappedMetrics,
                overlappedMetricsMilliseconds: overlappedMetricsMilliseconds
            )
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let globalX0 = 8
        let globalY0 = 6
        let globalWidth = max(8, sampleWidth - 16)
        let globalHeight = max(8, sampleHeight - 12)
        let globalStride: UInt32 = 2
        let globalSide = (globalSearchRadius * 2) + 1
        let globalScoreCount = globalSide * globalSide
        let globalChunkCount = shiftScoreChunkCount(regionHeight: globalHeight, stride: globalStride)

        let localStride: UInt32 = 1
        let localSide = (localSearchRadius * 2) + 1
        let localScoreCount = localSide * localSide
        let localChunkCount = shiftScoreChunkCount(regionHeight: blockBatch.maxBlockHeight, stride: localStride)

        let partialBuffer = try context.shiftPartialBuffer(
            length: MemoryLayout<StabilizerShiftScorePartial>.stride * max(
                globalScoreCount * globalChunkCount,
                localScoreCount * blocks.count * localChunkCount
            )
        )
        let resultStride = MemoryLayout<StabilizerShiftResult>.stride
        let localResultOffset = resultStride
        let resultBuffer = try context.shiftResultBuffer(length: resultStride * (blocks.count + 1))
        let uniformBuffer: MTLBuffer
        if let localUniformBuffer {
            guard localUniformBuffer.device.registryID == context.device.registryID else {
                throw metalError("Stabilizer cached local shift uniform buffer was created on a different Metal device.")
            }
            let expectedUniformLength = MemoryLayout<StabilizerShiftBatchUniforms>.stride * blockBatch.uniforms.count
            guard localUniformBuffer.length >= expectedUniformLength else {
                throw metalError("Stabilizer cached local shift uniform buffer was smaller than the expected block batch.")
            }
            uniformBuffer = localUniformBuffer
        } else {
            uniformBuffer = try context.shiftBatchUniformBuffer(uniforms: blockBatch.uniforms)
        }

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw metalError("Could not allocate Stabilizer Metal fused shift command buffer.")
        }

        var globalUniforms = StabilizerShiftBatchUniforms(
            width: UInt32(sampleWidth),
            height: UInt32(sampleHeight),
            x0: UInt32(globalX0),
            y0: UInt32(globalY0),
            regionWidth: UInt32(globalWidth),
            regionHeight: UInt32(globalHeight),
            centerX: 0,
            centerY: 0,
            radius: UInt32(globalSearchRadius),
            stride: max(1, globalStride)
        )
        var globalResolveUniforms = StabilizerShiftResolveUniforms(
            radius: UInt32(globalSearchRadius),
            chunkCount: UInt32(globalChunkCount),
            blockCount: 1,
            centerX: 0,
            centerY: 0,
            refine: 1
        )
        guard let globalPartialEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal fused global shift resources.")
        }
        globalPartialEncoder.setComputePipelineState(context.shiftPartialPipelineState)
        globalPartialEncoder.setBuffer(previous, offset: 0, index: Int(SCBI_PreviousFrame.rawValue))
        globalPartialEncoder.setBuffer(current, offset: 0, index: Int(SCBI_CurrentFrame.rawValue))
        globalPartialEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        globalPartialEncoder.setBytes(&globalUniforms, length: MemoryLayout<StabilizerShiftBatchUniforms>.stride, index: Int(SCBI_ShiftUniforms.rawValue))
        globalPartialEncoder.setBytes(&globalResolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        globalPartialEncoder.dispatchThreads(
            MTLSize(width: globalScoreCount, height: 1, depth: globalChunkCount),
            threadsPerThreadgroup: MTLSize(width: min(16, globalScoreCount), height: 1, depth: 1)
        )
        globalPartialEncoder.endEncoding()

        guard let globalResolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal fused global resolve resources.")
        }
        globalResolveEncoder.setComputePipelineState(context.resolveShiftPipelineState)
        globalResolveEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        globalResolveEncoder.setBuffer(resultBuffer, offset: 0, index: Int(SCBI_ShiftResults.rawValue))
        globalResolveEncoder.setBytes(&globalResolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        globalResolveEncoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        globalResolveEncoder.endEncoding()

        var localResolveUniforms = StabilizerShiftResolveUniforms(
            radius: UInt32(localSearchRadius),
            chunkCount: UInt32(localChunkCount),
            blockCount: UInt32(blocks.count),
            centerX: 0,
            centerY: 0,
            refine: 1
        )
        guard let localPartialEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal fused local shift resources.")
        }
        localPartialEncoder.setComputePipelineState(context.batchShiftPartialWithGlobalCenterPipelineState)
        localPartialEncoder.setBuffer(previous, offset: 0, index: Int(SCBI_PreviousFrame.rawValue))
        localPartialEncoder.setBuffer(current, offset: 0, index: Int(SCBI_CurrentFrame.rawValue))
        localPartialEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        localPartialEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(SCBI_ShiftBatchUniforms.rawValue))
        localPartialEncoder.setBuffer(resultBuffer, offset: 0, index: Int(SCBI_GlobalShiftResult.rawValue))
        localPartialEncoder.setBytes(&localResolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        localPartialEncoder.dispatchThreads(
            MTLSize(width: localScoreCount, height: blocks.count, depth: localChunkCount),
            threadsPerThreadgroup: MTLSize(width: min(16, localScoreCount), height: 1, depth: 1)
        )
        localPartialEncoder.endEncoding()

        guard let localResolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal fused local resolve resources.")
        }
        localResolveEncoder.setComputePipelineState(context.resolveShiftWithGlobalCenterPipelineState)
        localResolveEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        localResolveEncoder.setBuffer(resultBuffer, offset: localResultOffset, index: Int(SCBI_ShiftResults.rawValue))
        localResolveEncoder.setBuffer(resultBuffer, offset: 0, index: Int(SCBI_GlobalShiftResult.rawValue))
        localResolveEncoder.setBytes(&localResolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        localResolveEncoder.dispatchThreads(
            MTLSize(width: blocks.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(32, blocks.count), height: 1, depth: 1)
        )
        localResolveEncoder.endEncoding()

        commandBuffer.commit()
        let metricsStartedAt = CFAbsoluteTimeGetCurrent()
        let overlappedMetrics = try overlappedMetricsWork?()
        let overlappedMetricsMilliseconds = overlappedMetrics == nil ? 0.0 : (CFAbsoluteTimeGetCurrent() - metricsStartedAt) * 1000.0
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }

        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
        let timingSplit = splitFusedShiftTiming(
            totalMilliseconds: elapsedMilliseconds,
            globalUnits: globalScoreCount * globalChunkCount,
            localUnits: localScoreCount * localChunkCount * blocks.count
        )
        let results = resultBuffer.contents().assumingMemoryBound(to: StabilizerShiftResult.self)
        let global = results[0]
        let blockShifts = blocks.enumerated().map { index, block in
            let shift = results[index + 1]
            return StabilizerBlockShift(
                block: block,
                dx: shift.dx,
                dy: shift.dy,
                score: shift.score,
                searchRadiusHit: shift.searchRadiusHit != 0
            )
        }
        return (
            global: (global.dx, global.dy, global.score, global.searchRadiusHit != 0),
            blockShifts: blockShifts,
            globalMilliseconds: timingSplit.globalMilliseconds,
            localBatchMilliseconds: timingSplit.localMilliseconds,
            commandMilliseconds: elapsedMilliseconds,
            overlappedFrameMetrics: overlappedMetrics,
            overlappedMetricsMilliseconds: overlappedMetricsMilliseconds
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
        let pending = try beginEstimateShift(
            context: context,
            previous: previous,
            current: current,
            x0: x0,
            y0: y0,
            width: width,
            height: height,
            radius: radius,
            center: center,
            refine: refine,
            stride: stride,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let result = try pending.waitForResult()
        return (result.dx, result.dy, result.score, result.searchRadiusHit)
    }

    private static func beginEstimateShift(
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
    ) throws -> StabilizerPendingShiftResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let centerX = Int(center.0.rounded())
        let centerY = Int(center.1.rounded())
        let side = (radius * 2) + 1
        let scoreCount = side * side
        let chunkCount = shiftScoreChunkCount(regionHeight: height, stride: stride)
        let partialBuffer = try context.shiftPartialBuffer(
            length: MemoryLayout<StabilizerShiftScorePartial>.stride * scoreCount * chunkCount
        )
        let resultBuffer = try context.shiftResultBuffer(
            length: MemoryLayout<StabilizerShiftResult>.stride
        )
        guard
            let commandBuffer = context.commandQueue.makeCommandBuffer(),
            let partialEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw metalError("Could not allocate Stabilizer Metal shift resources.")
        }

        var uniforms = StabilizerShiftBatchUniforms(
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
        var resolveUniforms = StabilizerShiftResolveUniforms(
            radius: UInt32(radius),
            chunkCount: UInt32(chunkCount),
            blockCount: 1,
            centerX: Int32(centerX),
            centerY: Int32(centerY),
            refine: refine ? 1 : 0
        )

        partialEncoder.setComputePipelineState(context.shiftPartialPipelineState)
        partialEncoder.setBuffer(previous, offset: 0, index: Int(SCBI_PreviousFrame.rawValue))
        partialEncoder.setBuffer(current, offset: 0, index: Int(SCBI_CurrentFrame.rawValue))
        partialEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        partialEncoder.setBytes(&uniforms, length: MemoryLayout<StabilizerShiftBatchUniforms>.stride, index: Int(SCBI_ShiftUniforms.rawValue))
        partialEncoder.setBytes(&resolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        partialEncoder.dispatchThreads(
            MTLSize(width: scoreCount, height: 1, depth: chunkCount),
            threadsPerThreadgroup: MTLSize(width: min(16, scoreCount), height: 1, depth: 1)
        )
        partialEncoder.endEncoding()
        guard let resolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal shift resolve resources.")
        }
        resolveEncoder.setComputePipelineState(context.resolveShiftPipelineState)
        resolveEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        resolveEncoder.setBuffer(resultBuffer, offset: 0, index: Int(SCBI_ShiftResults.rawValue))
        resolveEncoder.setBytes(&resolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        resolveEncoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        resolveEncoder.endEncoding()
        commandBuffer.commit()
        return StabilizerPendingShiftResult(
            commandBuffer: commandBuffer,
            resultBuffer: resultBuffer,
            startedAt: startedAt
        )
    }

    private static func estimateShifts(
        context: MetalAnalysisContext,
        previous: MTLBuffer,
        current: MTLBuffer,
        blocks: [StabilizerMotionBlock],
        radius: Int,
        center: (Float, Float),
        refine: Bool,
        stride: UInt32,
        sampleWidth: Int,
        sampleHeight: Int
    ) throws -> [StabilizerBlockShift] {
        guard !blocks.isEmpty else {
            return []
        }
        let centerX = Int(center.0.rounded())
        let centerY = Int(center.1.rounded())
        let side = (radius * 2) + 1
        let scoreCount = side * side
        let maxBlockHeight = blocks.map(\.height).max() ?? 0
        let chunkCount = shiftScoreChunkCount(regionHeight: maxBlockHeight, stride: stride)
        let partialBuffer = try context.shiftPartialBuffer(
            length: MemoryLayout<StabilizerShiftScorePartial>.stride * scoreCount * blocks.count * chunkCount
        )
        let resultBuffer = try context.shiftResultBuffer(
            length: MemoryLayout<StabilizerShiftResult>.stride * blocks.count
        )
        let uniforms = blocks.map { block in
            StabilizerShiftBatchUniforms(
                width: UInt32(sampleWidth),
                height: UInt32(sampleHeight),
                x0: UInt32(block.x0),
                y0: UInt32(block.y0),
                regionWidth: UInt32(block.width),
                regionHeight: UInt32(block.height),
                centerX: Int32(centerX),
                centerY: Int32(centerY),
                radius: UInt32(radius),
                stride: max(1, stride)
            )
        }
        let uniformBuffer = try context.shiftBatchUniformBuffer(uniforms: uniforms)
        var resolveUniforms = StabilizerShiftResolveUniforms(
            radius: UInt32(radius),
            chunkCount: UInt32(chunkCount),
            blockCount: UInt32(blocks.count),
            centerX: Int32(centerX),
            centerY: Int32(centerY),
            refine: refine ? 1 : 0
        )
        guard
            let commandBuffer = context.commandQueue.makeCommandBuffer(),
            let partialEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw metalError("Could not allocate Stabilizer Metal batch shift resources.")
        }

        partialEncoder.setComputePipelineState(context.batchShiftPartialPipelineState)
        partialEncoder.setBuffer(previous, offset: 0, index: Int(SCBI_PreviousFrame.rawValue))
        partialEncoder.setBuffer(current, offset: 0, index: Int(SCBI_CurrentFrame.rawValue))
        partialEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        partialEncoder.setBuffer(uniformBuffer, offset: 0, index: Int(SCBI_ShiftBatchUniforms.rawValue))
        partialEncoder.setBytes(&resolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        partialEncoder.dispatchThreads(
            MTLSize(width: scoreCount, height: blocks.count, depth: chunkCount),
            threadsPerThreadgroup: MTLSize(width: min(16, scoreCount), height: 1, depth: 1)
        )
        partialEncoder.endEncoding()
        guard let resolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw metalError("Could not allocate Stabilizer Metal batch shift resolve resources.")
        }
        resolveEncoder.setComputePipelineState(context.resolveShiftPipelineState)
        resolveEncoder.setBuffer(partialBuffer, offset: 0, index: Int(SCBI_ShiftScorePartials.rawValue))
        resolveEncoder.setBuffer(resultBuffer, offset: 0, index: Int(SCBI_ShiftResults.rawValue))
        resolveEncoder.setBytes(&resolveUniforms, length: MemoryLayout<StabilizerShiftResolveUniforms>.stride, index: Int(SCBI_ShiftResolveUniforms.rawValue))
        resolveEncoder.dispatchThreads(
            MTLSize(width: blocks.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(32, blocks.count), height: 1, depth: 1)
        )
        resolveEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }

        let results = resultBuffer.contents().assumingMemoryBound(to: StabilizerShiftResult.self)
        return blocks.enumerated().map { index, block in
            let shift = results[index]
            return StabilizerBlockShift(
                block: block,
                dx: shift.dx,
                dy: shift.dy,
                score: shift.score,
                searchRadiusHit: shift.searchRadiusHit != 0
            )
        }
    }

    private static func resolvedShift(
        scores: UnsafePointer<Float>,
        scoreCount: Int,
        side: Int,
        radius: Int,
        centerX: Int,
        centerY: Int,
        refine: Bool
    ) -> (dx: Float, dy: Float, score: Float, searchRadiusHit: Bool) {
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

    private struct FrameInterpolation {
        let lowerIndex: Int
        let upperIndex: Int
        let fraction: Float

        var indices: [Int] {
            lowerIndex == upperIndex ? [lowerIndex] : [lowerIndex, upperIndex]
        }
    }

    private struct FrameLookup {
        let centerIndex: Int
        let interpolation: FrameInterpolation
    }

    private static func frameLookup(at time: Double, in frames: [StabilizerAnalysisFrame]) -> FrameLookup {
        guard !frames.isEmpty else {
            return FrameLookup(centerIndex: 0, interpolation: FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0))
        }
        guard frames.count > 1 else {
            return FrameLookup(centerIndex: 0, interpolation: FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0))
        }
        if time <= frames[0].time {
            return FrameLookup(centerIndex: 0, interpolation: FrameInterpolation(lowerIndex: 0, upperIndex: 0, fraction: 0.0))
        }
        let lastIndex = frames.count - 1
        if time >= frames[lastIndex].time {
            return FrameLookup(centerIndex: lastIndex, interpolation: FrameInterpolation(lowerIndex: lastIndex, upperIndex: lastIndex, fraction: 0.0))
        }
        let lowerBoundIndex = lowerBoundFrameIndex(frames, time: time)
        let centerIndex: Int
        if lowerBoundIndex <= frames.startIndex {
            centerIndex = frames.startIndex
        } else if lowerBoundIndex >= frames.endIndex {
            centerIndex = lastIndex
        } else {
            let previousIndex = lowerBoundIndex - 1
            let previousDistance = abs(frames[previousIndex].time - time)
            let nextDistance = abs(frames[lowerBoundIndex].time - time)
            centerIndex = previousDistance <= nextDistance ? previousIndex : lowerBoundIndex
        }

        let upperIndex: Int
        if lowerBoundIndex < frames.endIndex && frames[lowerBoundIndex].time == time {
            upperIndex = upperBoundFrameIndex(frames, time: time)
        } else {
            upperIndex = lowerBoundIndex
        }
        guard upperIndex > frames.startIndex, upperIndex < frames.endIndex else {
            return FrameLookup(centerIndex: centerIndex, interpolation: FrameInterpolation(lowerIndex: lastIndex, upperIndex: lastIndex, fraction: 0.0))
        }
        let lowerIndex = upperIndex - 1
        let lowerTime = frames[lowerIndex].time
        let upperTime = frames[upperIndex].time
        let duration = upperTime - lowerTime
        guard duration > 1e-9 else {
            return FrameLookup(centerIndex: centerIndex, interpolation: FrameInterpolation(lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: 0.0))
        }
        let fraction = clamp(Float((time - lowerTime) / duration), min: 0.0, max: 1.0)
        return FrameLookup(centerIndex: centerIndex, interpolation: FrameInterpolation(lowerIndex: lowerIndex, upperIndex: upperIndex, fraction: fraction))
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

    private static func interpolatedValue(_ values: EstimatedPath, using interpolation: FrameInterpolation) -> Float {
        guard values.values.indices.contains(interpolation.lowerIndex) else {
            return 0.0
        }
        let lowerValue = values[interpolation.lowerIndex]
        guard values.values.indices.contains(interpolation.upperIndex), interpolation.upperIndex != interpolation.lowerIndex else {
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

    private static func average(_ values: EstimatedPath, indices: [Int]) -> Float {
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
        return indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: windowSeconds)
    }

    private static func indicesWithinTimeRadius(
        _ frames: [StabilizerAnalysisFrame],
        centerTime: Double,
        radiusSeconds: Double
    ) -> [Int] {
        guard !frames.isEmpty, centerTime.isFinite, radiusSeconds.isFinite else {
            return []
        }
        let boundedRadius = max(0.0, radiusSeconds)
        let startTime = centerTime - boundedRadius - timeWindowSelectionEpsilon
        let endTime = centerTime + boundedRadius + timeWindowSelectionEpsilon
        let lowerIndex = lowerBoundFrameIndex(frames, time: startTime)
        let upperIndex = upperBoundFrameIndex(frames, time: endTime)
        guard lowerIndex < upperIndex else {
            return []
        }
        return Array(lowerIndex..<upperIndex)
    }

    private static func uniqueSortedIndices(_ indices: [Int], validCount: Int) -> [Int] {
        guard validCount > 0, !indices.isEmpty else {
            return []
        }
        var seen = Set<Int>()
        var unique: [Int] = []
        unique.reserveCapacity(indices.count)
        for index in indices where index >= 0 && index < validCount {
            guard seen.insert(index).inserted else {
                continue
            }
            unique.append(index)
        }
        return unique.sorted()
    }

    private static func lowerBoundFrameIndex(_ frames: [StabilizerAnalysisFrame], time: Double) -> Int {
        var low = frames.startIndex
        var high = frames.endIndex
        while low < high {
            let mid = low + ((high - low) / 2)
            if frames[mid].time < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private static func upperBoundFrameIndex(_ frames: [StabilizerAnalysisFrame], time: Double) -> Int {
        var low = frames.startIndex
        var high = frames.endIndex
        while low < high {
            let mid = low + ((high - low) / 2)
            if frames[mid].time <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
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
        let outerIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: outerWindow)
        let indices = outerIndices.filter { index in
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
        for index in indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: outerWindow) where values.indices.contains(index) {
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
        for index in indices where values.indices.contains(index) && frames.indices.contains(index) {
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

    private static func cachedOuterLinearPredictionPath(
        _ kind: MotionPathKind,
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        innerWindowSeconds: Double,
        outerWindowSeconds: Double,
        cache: RenderEstimateCache
    ) -> EstimatedPath {
        cache.outerLinearPredictionPath(
            kind,
            analysis: analysis,
            indices: indices,
            innerWindowSeconds: innerWindowSeconds,
            outerWindowSeconds: outerWindowSeconds
        )
    }

    private static func farFieldWarpBandValue(
        values: [Float],
        baselineValues: EstimatedPath,
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

        let sortedIndices = indicesAreStrictlyAscending(indices) ? indices : indices.sorted()
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

    private static func timeWeightedAverage(_ values: EstimatedPath, frames: [StabilizerAnalysisFrame], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        guard indices.count > 1 else {
            return values[indices[0]]
        }

        let sortedIndices = indicesAreStrictlyAscending(indices) ? indices : indices.sorted()
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

    private static func indicesAreStrictlyAscending(_ indices: [Int]) -> Bool {
        guard indices.count > 1 else {
            return true
        }
        var previous = indices[0]
        for index in indices.dropFirst() {
            if index <= previous {
                return false
            }
            previous = index
        }
        return true
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
        for index in targetIndices where values.indices.contains(index) && frames.indices.contains(index) {
            let centerTime = frames[index].time
            let localIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindowSeconds)
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
        let sortedIndices = indicesAreStrictlyAscending(indices) ? indices : indices.sorted()
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

    private static func timeWeightedMonotonicSCurveValue(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        centerTime: Double,
        windowSeconds: Double
    ) -> Float? {
        guard indices.count >= 3 else {
            return nil
        }
        let sortedIndices = indicesAreStrictlyAscending(indices) ? indices : indices.sorted()
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
        var sortedValues: [Float] = []
        sortedValues.reserveCapacity(indices.count)
        for index in indices where values.indices.contains(index) {
            let value = values[index]
            if value.isFinite {
                sortedValues.append(value)
            }
        }
        sortedValues.sort()
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

    private static func walkingConfidenceCompensatedCorrectionFactor(_ strength: Double, confidence: Float, maxStrength: Float = 4.0) -> Float {
        let requestedRemoval = clamp(Float(strength), min: 0.0, max: maxStrength)
        let confidenceResponse = walkingCorrectionConfidenceResponse(confidence)
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

    private static func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {
        let boundedConfidence = clamp(confidence, min: 0.0, max: 1.0)
        return boundedConfidence * (1.0 + ((1.0 - boundedConfidence) * 0.65))
    }

    private static func farFieldWarpRenderGate(
        warpConfidence: Float,
        trackingConfidence: Float,
        edgeQuality: Float
    ) -> Float {
        guard warpConfidence > 0.0 else {
            return 0.0
        }
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

    private static func stableFarFieldWarpTrackingConfidence(
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        currentTrackingConfidence: Float
    ) -> Float {
        var localTrackingValues: [Float] = []
        localTrackingValues.reserveCapacity(indices.count)
        for index in indices {
            guard analysis.frames.indices.contains(index),
                  analysis.residuals.indices.contains(index),
                  analysis.blurAmounts.indices.contains(index),
                  analysis.analysisConfidence.indices.contains(index),
                  analysis.acceptedBlockCounts.indices.contains(index),
                  analysis.totalBlockCounts.indices.contains(index)
            else {
                continue
            }
            localTrackingValues.append(frameTrackingConfidence(
                motionConfidence: analysis.analysisConfidence[index],
                residual: analysis.residuals[index],
                blurAmount: analysis.blurAmounts[index],
                acceptedBlockCount: analysis.acceptedBlockCounts[index],
                totalBlockCount: analysis.totalBlockCounts[index],
                qualityModel: analysis.qualityModel
            ))
        }
        guard let localMedianTrackingConfidence = median(localTrackingValues) else {
            return currentTrackingConfidence
        }
        if localMedianTrackingConfidence < farFieldWarpTrackingGateStart {
            return min(currentTrackingConfidence, localMedianTrackingConfidence)
        }
        let blendedTrackingConfidence = (currentTrackingConfidence * (1.0 - farFieldWarpTrackingGateMedianBlend))
            + (localMedianTrackingConfidence * farFieldWarpTrackingGateMedianBlend)
        return clamp(
            blendedTrackingConfidence,
            min: max(0.0, currentTrackingConfidence - farFieldWarpTrackingGateStabilityLimit),
            max: min(1.0, currentTrackingConfidence + farFieldWarpTrackingGateStabilityLimit)
        )
    }

    private static func stableFarFieldWarpEdgeQuality(
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        currentSearchRadiusHitCount: Int32,
        currentSearchRadiusTotalCount: Int32
    ) -> Float {
        let currentEdgeQuality = searchRadiusEdgeQuality(
            hitCount: currentSearchRadiusHitCount,
            totalCount: currentSearchRadiusTotalCount
        )
        var localEdgeQualityValues: [Float] = []
        localEdgeQualityValues.reserveCapacity(indices.count)
        for index in indices {
            guard analysis.searchRadiusHitCounts.indices.contains(index),
                  analysis.searchRadiusTotalCounts.indices.contains(index)
            else {
                continue
            }
            localEdgeQualityValues.append(searchRadiusEdgeQuality(
                hitCount: analysis.searchRadiusHitCounts[index],
                totalCount: analysis.searchRadiusTotalCounts[index]
            ))
        }
        guard let localMedianEdgeQuality = median(localEdgeQualityValues) else {
            return currentEdgeQuality
        }
        return min(currentEdgeQuality, localMedianEdgeQuality)
    }

    private static func searchRadiusEdgeQuality(hitCount: Int32, totalCount: Int32) -> Float {
        guard totalCount > 0 else {
            return 0.0
        }
        let hitRatio = clamp(Float(hitCount) / Float(totalCount), min: 0.0, max: 1.0)
        return 1.0 - hitRatio
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
            full: max(noiseFloor + Float.ulpOfOne, fullScale * strideWobbleFullResponseScale)
        )
        return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
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

    private static func turnOwnershipConfidence(
        values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        turnBandValue: Float,
        trackingConfidence: Float
    ) -> Float {
        let sortedIndices = (indicesAreStrictlyAscending(indices) ? indices : indices.sorted())
            .filter { values.values.indices.contains($0) && frames.indices.contains($0) }
        guard sortedIndices.count >= 3 else {
            return 0.0
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
        guard totalTravel > footstepImpulseFullScalePixels else {
            return 0.0
        }

        guard let firstIndex = sortedIndices.first,
              let lastIndex = sortedIndices.last
        else {
            return 0.0
        }
        let endpointDelta = values[lastIndex] - values[firstIndex]
        let dominantTravel = max(positiveTravel, negativeTravel)
        let dominantRatio = dominantTravel / max(totalTravel, Float.ulpOfOne)
        let endpointRatio = abs(endpointDelta) / max(dominantTravel, Float.ulpOfOne)
        let monotonicQuality = confidenceRamp(dominantRatio, start: 0.58, full: 0.82)
        let endpointQuality = confidenceRamp(endpointRatio, start: 0.22, full: 0.55)
        let bandQuality = confidenceRamp(
            abs(turnBandValue),
            start: footstepImpulseFullScalePixels * 0.70,
            full: max((footstepImpulseFullScalePixels * 0.70) + Float.ulpOfOne, turnSmoothingFullScalePixels * 0.65)
        )
        let trackingQuality = confidenceRamp(trackingConfidence, start: 0.22, full: 0.62)
        return clamp(max(monotonicQuality, endpointQuality) * bandQuality * trackingQuality, min: 0.0, max: 1.0)
    }

    private static func turnOwnershipGateScales(
        values: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        targetIndices: [Int],
        windowSeconds: Double
    ) -> [Int: Float] {
        guard !targetIndices.isEmpty else {
            return [:]
        }
        let frames = analysis.frames
        let halfWindowSeconds = max(0.0, windowSeconds * 0.5)
        var scales: [Int: Float] = [:]
        scales.reserveCapacity(targetIndices.count)

        for index in targetIndices {
            guard values.values.indices.contains(index),
                  frames.indices.contains(index),
                  analysis.analysisConfidence.indices.contains(index),
                  analysis.residuals.indices.contains(index),
                  analysis.blurAmounts.indices.contains(index),
                  analysis.acceptedBlockCounts.indices.contains(index),
                  analysis.totalBlockCounts.indices.contains(index)
            else {
                continue
            }

            let centerTime = frames[index].time
            let activeIndices = indicesWithinTimeRadius(
                frames,
                centerTime: centerTime,
                radiusSeconds: halfWindowSeconds
            )
            guard !activeIndices.isEmpty else {
                continue
            }

            let turnSmooth = timeWeightedMonotonicSCurveValue(
                values,
                frames: frames,
                indices: activeIndices,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            ) ??
                timeWeightedAverage(
                    values,
                    frames: frames,
                    indices: activeIndices,
                    centerTime: centerTime,
                    windowSeconds: windowSeconds
                )
            let turnBand = values[index] - turnSmooth
            let residual = percentileValue(analysis.residuals, indices: activeIndices, percentile: 0.75)
            let trackingConfidence = frameTrackingConfidence(
                motionConfidence: analysis.analysisConfidence[index],
                residual: analysis.residuals[index],
                blurAmount: analysis.blurAmounts[index],
                acceptedBlockCount: analysis.acceptedBlockCounts[index],
                totalBlockCount: analysis.totalBlockCounts[index],
                qualityModel: analysis.qualityModel
            )
            let turnTrackingConfidence = residualAdjustedTrackingConfidence(
                trackingConfidence,
                residual: residual,
                multiplier: 0.9,
                qualityModel: analysis.qualityModel
            )
            let ownership = turnOwnershipConfidence(
                values: values,
                frames: frames,
                indices: activeIndices,
                turnBandValue: turnBand,
                trackingConfidence: turnTrackingConfidence
            )
            let gate = clamp(1.0 - (ownership * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
            if gate < 0.9999 {
                scales[index] = gate
            }
        }

        return scales
    }

    private static func residualAdjustedTrackingConfidence(
        _ trackingConfidence: Float,
        residual: Float,
        multiplier: Float,
        qualityModel: StabilizerAnalysisQualityModel
    ) -> Float {
        let residualQuality = residualEvidenceQuality(
            residual,
            multiplier: multiplier,
            qualityModel: qualityModel
        )
        return clamp(trackingConfidence * residualQuality, min: 0.0, max: 1.0)
    }

    private static func residualEvidenceQuality(
        _ residual: Float,
        multiplier: Float,
        qualityModel: StabilizerAnalysisQualityModel
    ) -> Float {
        guard residual.isFinite else {
            return 0.0
        }
        switch qualityModel {
        case .fxplugHostAnalysis:
            return clamp(1.0 - (residual * multiplier), min: 0.0, max: 1.0)
        case .eventAnalyzerCache:
            return clamp(1.0 - (residual / 48.0), min: 0.0, max: 1.0)
        }
    }

    private static func frameTrackingConfidence(
        motionConfidence: Float,
        residual: Float,
        blurAmount: Float,
        acceptedBlockCount: Int32,
        totalBlockCount: Int32,
        qualityModel: StabilizerAnalysisQualityModel
    ) -> Float {
        let residualQuality = residualEvidenceQuality(
            residual,
            multiplier: 0.7,
            qualityModel: qualityModel
        )
        let blurQuality = blurEvidenceQuality(blurAmount)
        let blockQuality: Float
        if totalBlockCount > 0 {
            blockQuality = clamp(Float(acceptedBlockCount) / Float(totalBlockCount), min: 0.0, max: 1.0)
        } else {
            blockQuality = 0.0
        }
        let combinedEvidence = motionConfidence * residualQuality * blurQuality * blockQuality
        return clamp(Darwin.sqrtf(max(0.0, combinedEvidence)), min: 0.0, max: 1.0)
    }

    private static func walkingBandTrackingConfidence(
        motionConfidence: Float,
        residual: Float,
        blurAmount: Float,
        acceptedBlockCount: Int32,
        totalBlockCount: Int32,
        qualityModel: StabilizerAnalysisQualityModel
    ) -> Float {
        let residualQuality = residualEvidenceQuality(
            residual,
            multiplier: 0.7,
            qualityModel: qualityModel
        )
        let blurQuality = blurEvidenceQuality(blurAmount)
        let blockQuality = walkingBandBlockQuality(acceptedBlockCount: acceptedBlockCount, totalBlockCount: totalBlockCount)
        let combinedEvidence = motionConfidence * residualQuality * blurQuality * blockQuality
        return clamp(Darwin.sqrtf(max(0.0, combinedEvidence)), min: 0.0, max: 1.0)
    }

    private static func walkingBandBlockQuality(acceptedBlockCount: Int32, totalBlockCount: Int32) -> Float {
        guard acceptedBlockCount > 0, totalBlockCount > 0 else {
            return 0.0
        }
        let coverage = clamp(Float(acceptedBlockCount) / Float(totalBlockCount), min: 0.0, max: 1.0)
        let countSupport = confidenceRamp(Float(acceptedBlockCount), start: 4.0, full: 10.0)
        let coverageLift = 0.35 * countSupport * (1.0 - coverage)
        return clamp(coverage + coverageLift, min: 0.0, max: 1.0)
    }

    private static func confidenceCleanedFootstepPath(
        values: [Float],
        baselineValues: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        fullImpulseScale: Float,
        confidenceScales: [Int: Float] = [:]
    ) -> EstimatedPath {
        guard !values.isEmpty else {
            return EstimatedPath(values: values)
        }
        var overrides: [Int: Float] = [:]
        overrides.reserveCapacity(indices.count)
        for index in indices {
            guard values.indices.contains(index),
                  baselineValues.values.indices.contains(index),
                  analysis.frames.indices.contains(index),
                  analysis.analysisConfidence.indices.contains(index),
                  analysis.residuals.indices.contains(index),
                  analysis.blurAmounts.indices.contains(index),
                  analysis.acceptedBlockCounts.indices.contains(index),
                  analysis.totalBlockCounts.indices.contains(index)
            else {
                continue
            }
            let trackingConfidence = walkingBandTrackingConfidence(
                motionConfidence: analysis.analysisConfidence[index],
                residual: analysis.residuals[index],
                blurAmount: analysis.blurAmounts[index],
                acceptedBlockCount: analysis.acceptedBlockCounts[index],
                totalBlockCount: analysis.totalBlockCounts[index],
                qualityModel: analysis.qualityModel
            )
            let rawValue = values[index]
            let baselineValue = baselineValues[index]
            let confidence = footstepFrameConfidenceAtIndex(
                values: values,
                baselineValues: baselineValues,
                frames: analysis.frames,
                index: index,
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale
            )
            let confidenceScale = clamp(confidenceScales[index] ?? 1.0, min: 0.0, max: 1.0)
            let effectiveConfidence = confidence * confidenceScale
            overrides[index] = rawValue - ((rawValue - baselineValue) * effectiveConfidence)
        }
        return EstimatedPath(values: values, overrides: overrides)
    }

    private struct FootstepContinuityLimitResult {
        let limitedCorrection: Float
        let limitedAmount: Float
    }

    private static func footstepContinuityLimitedCorrection(
        values: [Float],
        baselineValues: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        centerTime: Double,
        rawCorrection: Float,
        outputScale: Float,
        requestedStrength: Double,
        fullImpulseScale: Float,
        confidenceScale: Float = 1.0
    ) -> FootstepContinuityLimitResult {
        guard rawCorrection.isFinite,
              outputScale.isFinite,
              outputScale > 0.0,
              !values.isEmpty,
              !analysis.frames.isEmpty
        else {
            return FootstepContinuityLimitResult(limitedCorrection: rawCorrection, limitedAmount: 0.0)
        }

        let halfWindow = footstepXYContinuityWindowSeconds * 0.5
        var indices = indicesWithinTimeRadius(
            analysis.frames,
            centerTime: centerTime,
            radiusSeconds: halfWindow
        ).filter { values.indices.contains($0) && baselineValues.values.indices.contains($0) }
        guard indices.count >= 5 else {
            return FootstepContinuityLimitResult(limitedCorrection: rawCorrection, limitedAmount: 0.0)
        }
        if indices.count > footstepXYContinuityMaxSamples {
            indices = Array(indices
                .sorted { abs(analysis.frames[$0].time - centerTime) < abs(analysis.frames[$1].time - centerTime) }
                .prefix(footstepXYContinuityMaxSamples))
                .sorted()
        }

        let sigma = max(1e-6, halfWindow * 0.55)
        var weightedCorrections: [(value: Float, weight: Float)] = []
        weightedCorrections.reserveCapacity(indices.count)
        for index in indices {
            guard analysis.frames.indices.contains(index),
                  analysis.analysisConfidence.indices.contains(index),
                  analysis.residuals.indices.contains(index),
                  analysis.blurAmounts.indices.contains(index),
                  analysis.acceptedBlockCounts.indices.contains(index),
                  analysis.totalBlockCounts.indices.contains(index)
            else {
                continue
            }
            let offset = (analysis.frames[index].time - centerTime) / sigma
            let weight = Float(Darwin.exp(-0.5 * offset * offset))
            guard weight > 0.0001 else {
                continue
            }
            let trackingConfidence = walkingBandTrackingConfidence(
                motionConfidence: analysis.analysisConfidence[index],
                residual: analysis.residuals[index],
                blurAmount: analysis.blurAmounts[index],
                acceptedBlockCount: analysis.acceptedBlockCounts[index],
                totalBlockCount: analysis.totalBlockCounts[index],
                qualityModel: analysis.qualityModel
            )
            let confidence = footstepFrameConfidence(
                values: values,
                baselineValues: baselineValues,
                frames: analysis.frames,
                interpolation: FrameInterpolation(lowerIndex: index, upperIndex: index, fraction: 0.0),
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale
            )
            let correctionStrength = walkingConfidenceCompensatedCorrectionFactor(
                requestedStrength,
                confidence: confidence * clamp(confidenceScale, min: 0.0, max: 1.0),
                maxStrength: 10.0
            )
            let correction = -(values[index] - baselineValues[index]) * outputScale * correctionStrength
            if correction.isFinite {
                weightedCorrections.append((value: correction, weight: weight))
            }
        }

        guard weightedCorrections.count >= 5,
              let localMedian = weightedMedian(weightedCorrections)
        else {
            return FootstepContinuityLimitResult(limitedCorrection: rawCorrection, limitedAmount: 0.0)
        }
        let weightedDeviations = weightedCorrections.map {
            (value: abs($0.value - localMedian), weight: $0.weight)
        }
        let localMad = weightedMedian(weightedDeviations) ?? 0.0
        let spikeThreshold = max(
            footstepXYContinuityMinimumSpikePixels,
            localMad * footstepXYContinuityMadMultiplier
        )
        let rawDeviation = abs(rawCorrection - localMedian)
        guard rawDeviation > spikeThreshold else {
            return FootstepContinuityLimitResult(limitedCorrection: rawCorrection, limitedAmount: 0.0)
        }

        let rawSign: Float = rawCorrection >= 0.0 ? 1.0 : -1.0
        var similarNeighborWeight: Float = 0.0
        var totalNeighborWeight: Float = 0.0
        for entry in weightedCorrections {
            let value = entry.value
            guard abs(value - rawCorrection) > Float.ulpOfOne else {
                continue
            }
            totalNeighborWeight += entry.weight
            let valueSign: Float = value >= 0.0 ? 1.0 : -1.0
            if valueSign == rawSign,
               abs(value - rawCorrection) <= spikeThreshold {
                similarNeighborWeight += entry.weight
            }
        }
        if totalNeighborWeight > Float.ulpOfOne,
           similarNeighborWeight / totalNeighborWeight >= 0.35 {
            return FootstepContinuityLimitResult(limitedCorrection: rawCorrection, limitedAmount: 0.0)
        }

        let excess = rawDeviation - spikeThreshold
        let blend = clamp(excess / max(spikeThreshold * 2.0, Float.ulpOfOne), min: 0.35, max: 0.85)
        let limitedCorrection = rawCorrection + ((localMedian - rawCorrection) * blend)
        return FootstepContinuityLimitResult(
            limitedCorrection: limitedCorrection,
            limitedAmount: abs(rawCorrection - limitedCorrection)
        )
    }

    private static func footstepFrameConfidence(
        values: [Float],
        baselineValues: EstimatedPath,
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
            return stableFootstepFrameConfidence(
                values: values,
                baselineValues: baselineValues,
                frames: frames,
                centerTime: frames.indices.contains(interpolation.lowerIndex) ? frames[interpolation.lowerIndex].time : 0.0,
                instantConfidence: lowerConfidence,
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale
            )
        }
        let upperConfidence = footstepFrameConfidenceAtIndex(
            values: values,
            baselineValues: baselineValues,
            frames: frames,
            index: interpolation.upperIndex,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: fullImpulseScale
        )
        let instantConfidence = lowerConfidence + ((upperConfidence - lowerConfidence) * interpolation.fraction)
        let lowerTime = frames.indices.contains(interpolation.lowerIndex) ? frames[interpolation.lowerIndex].time : 0.0
        let upperTime = frames.indices.contains(interpolation.upperIndex) ? frames[interpolation.upperIndex].time : lowerTime
        let centerTime = lowerTime + ((upperTime - lowerTime) * Double(interpolation.fraction))
        return stableFootstepFrameConfidence(
            values: values,
            baselineValues: baselineValues,
            frames: frames,
            centerTime: centerTime,
            instantConfidence: instantConfidence,
            trackingConfidence: trackingConfidence,
            fullImpulseScale: fullImpulseScale
        )
    }

    private static func stableFootstepFrameConfidence(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        centerTime: Double,
        instantConfidence: Float,
        trackingConfidence: Float,
        fullImpulseScale: Float
    ) -> Float {
        guard centerTime.isFinite, !frames.isEmpty else {
            return instantConfidence
        }
        let halfWindow = max(0.0, footstepConfidenceStabilityWindowSeconds * 0.5)
        let indices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow)
        guard !indices.isEmpty else {
            return instantConfidence
        }
        let sigma = max(1e-6, halfWindow * 0.55)
        var weightedTotal: Float = 0.0
        var totalWeight: Float = 0.0
        for index in indices {
            guard frames.indices.contains(index) else {
                continue
            }
            let offset = (frames[index].time - centerTime) / sigma
            let weight = Float(Darwin.exp(-0.5 * offset * offset))
            guard weight > 0.0001 else {
                continue
            }
            let confidence = footstepFrameConfidenceAtIndex(
                values: values,
                baselineValues: baselineValues,
                frames: frames,
                index: index,
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale
            )
            weightedTotal += confidence * weight
            totalWeight += weight
        }
        guard totalWeight > Float.ulpOfOne else {
            return instantConfidence
        }
        let localConfidence = weightedTotal / totalWeight
        let centerBlend = clamp(footstepConfidenceCenterBlend, min: 0.0, max: 1.0)
        return clamp(
            (instantConfidence * centerBlend) + (localConfidence * (1.0 - centerBlend)),
            min: 0.0,
            max: 1.0
        )
    }

    private static func footstepFrameConfidenceAtIndex(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        index: Int,
        trackingConfidence: Float,
        fullImpulseScale: Float
    ) -> Float {
        guard values.indices.contains(index), baselineValues.values.indices.contains(index) else {
            return 0.0
        }
        let impulse = abs(values[index] - baselineValues[index])
        let surroundingIndices = surroundingIndicesExcludingCenter(
            around: index,
            frames: frames,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds
        ).filter { values.indices.contains($0) && baselineValues.values.indices.contains($0) }
        guard !surroundingIndices.isEmpty else {
            return 0.0
        }
        let surroundingNoise = median(surroundingIndices.map { abs(values[$0] - baselineValues[$0]) }) ?? 0.0
        let centerTime = frames.indices.contains(index) ? frames[index].time : 0.0
        let hasLeftSupport = surroundingIndices.contains { frames.indices.contains($0) && frames[$0].time < centerTime }
        let hasRightSupport = surroundingIndices.contains { frames.indices.contains($0) && frames[$0].time > centerTime }
        let supportQuality: Float = (hasLeftSupport && hasRightSupport) ? 1.0 : 0.65
        let surroundingNoiseFloor = min(
            surroundingNoise * footstepSurroundingNoiseMultiplier,
            fullImpulseScale * footstepSurroundingNoiseFloorCapScale
        )
        let noiseFloor = max(
            fullImpulseScale * footstepNoiseFloorScale,
            surroundingNoiseFloor
        )
        let impulseQuality = confidenceRamp(
            impulse,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, fullImpulseScale * footstepFullResponseScale)
        )
        let isolationQuality = footstepImpulseIsolationQuality(
            values: values,
            baselineValues: baselineValues,
            frames: frames,
            index: index,
            impulse: values[index] - baselineValues[index],
            fullImpulseScale: fullImpulseScale
        )
        return clamp(trackingConfidence * supportQuality * impulseQuality * isolationQuality, min: 0.0, max: 1.0)
    }

    private static func footstepImpulseIsolationQuality(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        index: Int,
        impulse: Float,
        fullImpulseScale: Float
    ) -> Float {
        guard frames.indices.contains(index), values.indices.contains(index), baselineValues.values.indices.contains(index) else {
            return 1.0
        }
        let impulseMagnitude = abs(impulse)
        guard impulseMagnitude > max(fullImpulseScale * footstepNoiseFloorScale, Float.ulpOfOne) else {
            return 1.0
        }
        let centerTime = frames[index].time
        let outerIndices = indicesWithinTimeRadius(
            frames,
            centerTime: centerTime,
            radiusSeconds: footstepPersistentSignWindowEndSeconds
        )
        let impulseSign: Float = impulse >= 0.0 ? 1.0 : -1.0
        var sameSignEnergy: Float = 0.0
        var totalEnergy: Float = 0.0
        var count: Float = 0.0
        for candidateIndex in outerIndices {
            guard candidateIndex != index,
                  frames.indices.contains(candidateIndex),
                  values.indices.contains(candidateIndex),
                  baselineValues.values.indices.contains(candidateIndex)
            else {
                continue
            }
            let distance = abs(frames[candidateIndex].time - centerTime)
            guard distance >= footstepPersistentSignWindowStartSeconds,
                  distance <= footstepPersistentSignWindowEndSeconds + timeWindowSelectionEpsilon
            else {
                continue
            }
            let candidateImpulse = values[candidateIndex] - baselineValues[candidateIndex]
            let energy = abs(candidateImpulse)
            totalEnergy += energy
            count += 1.0
            if candidateImpulse * impulseSign > 0.0 {
                sameSignEnergy += energy
            }
        }
        guard count >= 2.0, totalEnergy > Float.ulpOfOne else {
            return 1.0
        }
        let sameSignRatio = sameSignEnergy / totalEnergy
        let averageSameSignEnergy = sameSignEnergy / count
        let persistentSign = confidenceRamp(sameSignRatio, start: 0.45, full: 0.85)
        let persistentMagnitude = confidenceRamp(
            averageSameSignEnergy,
            start: impulseMagnitude * 0.18,
            full: max((impulseMagnitude * 0.55), fullImpulseScale * 0.20)
        )
        return clamp(1.0 - (0.42 * persistentSign * persistentMagnitude), min: 0.58, max: 1.0)
    }

    private static func confidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
        guard value.isFinite, start.isFinite, full.isFinite, full > start else {
            return 0.0
        }
        let normalized = clamp((value - start) / (full - start), min: 0.0, max: 1.0)
        return normalized * normalized * (3.0 - (2.0 * normalized))
    }
}

struct StabilizerStreamingAnalysisAppendResult {
    let frame: StabilizerAnalysisFrame
    let pairTiming: StabilizerPairMotionTiming?
    let metricsMilliseconds: Double
}

final class StreamingStabilizationAnalysisBuilder {
    private var context: MetalAnalysisContext?
    private var frames: [StabilizerAnalysisFrame] = []
    private var motions: [PairMotion] = []
    private var previousFrameBuffer: MTLBuffer?
    private var previousFrameBufferLease: StabilizerDownsampleBufferLease?
    private var sampleWidth: Int?
    private var sampleHeight: Int?
    private var motionBlockBatch: StabilizerMotionBlockBatch?
    private var motionBlockUniformBuffer: MTLBuffer?

    init() {}

    var frameCount: Int {
        frames.count
    }

    func append(_ sample: StabilizerAnalysisSample) throws -> StabilizerStreamingAnalysisAppendResult {
        let expectedPixelCount = sample.sampleWidth * sample.sampleHeight
        if !sample.pixels.isEmpty, sample.pixels.count != expectedPixelCount {
            throw AutoStabilizationEstimator.metalError("Stabilizer streaming analysis frame retained an unexpected pixel count.")
        }
        if let sampleWidth, let sampleHeight {
            guard sample.sampleWidth == sampleWidth, sample.sampleHeight == sampleHeight else {
                throw AutoStabilizationEstimator.metalError("Stabilizer streaming analysis frames used mixed sample sizes.")
            }
            if let previousFrameTime = frames.last?.time, sample.time <= previousFrameTime {
                throw AutoStabilizationEstimator.metalError("Stabilizer Host Analysis frames were not delivered in increasing time order.")
            }
        } else {
            sampleWidth = sample.sampleWidth
            sampleHeight = sample.sampleHeight
            motionBlockBatch = AutoStabilizationEstimator.motionBlockBatch(
                sampleWidth: sample.sampleWidth,
                sampleHeight: sample.sampleHeight
            )
        }

        if context == nil {
            context = try MetalAnalysisContext(preferredDevice: sample.lumaBuffer.device)
        }
        guard let context else {
            throw AutoStabilizationEstimator.metalError("Stabilizer Metal analysis context was unavailable.")
        }
        try context.validateFrameBuffer(sample.lumaBuffer, sampleWidth: sample.sampleWidth, sampleHeight: sample.sampleHeight)
        guard let motionBlockBatch else {
            throw AutoStabilizationEstimator.metalError("Stabilizer streaming analysis motion block batch was unavailable.")
        }
        if motionBlockUniformBuffer == nil, !motionBlockBatch.uniforms.isEmpty {
            motionBlockUniformBuffer = try context.shiftBatchUniformBuffer(uniforms: motionBlockBatch.uniforms)
        }

        let currentFrameBuffer = sample.lumaBuffer
        let timing: StabilizerPairMotionTiming?
        let metrics: StabilizerFrameMetrics
        let metricsMilliseconds: Double
        if let previousFrameBuffer {
            let result = try AutoStabilizationEstimator.pairMotionResult(
                context: context,
                previous: previousFrameBuffer,
                current: currentFrameBuffer,
                sampleWidth: sample.sampleWidth,
                sampleHeight: sample.sampleHeight,
                motionBlockBatch: motionBlockBatch,
                motionBlockUniformBuffer: motionBlockUniformBuffer,
                overlappedMetricsWork: {
                    try AutoStabilizationEstimator.frameMetrics(sample)
                }
            )
            motions.append(result.motion)
            timing = result.timing
            guard let overlappedMetrics = result.overlappedFrameMetrics else {
                throw AutoStabilizationEstimator.metalError("Stabilizer frame metrics were unavailable after overlapped Host Analysis.")
            }
            metrics = overlappedMetrics
            metricsMilliseconds = result.overlappedMetricsMilliseconds
        } else {
            let metricsStartedAt = CFAbsoluteTimeGetCurrent()
            metrics = try AutoStabilizationEstimator.frameMetrics(sample)
            metricsMilliseconds = (CFAbsoluteTimeGetCurrent() - metricsStartedAt) * 1000.0
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
            timing = nil
        }
        let frame = AutoStabilizationEstimator.analysisFrame(from: sample, metrics: metrics)
        frames.append(frame.withoutRetainedPixels())
        previousFrameBuffer = currentFrameBuffer
        previousFrameBufferLease = sample.lumaBufferLease
        return StabilizerStreamingAnalysisAppendResult(
            frame: frame,
            pairTiming: timing,
            metricsMilliseconds: metricsMilliseconds
        )
    }

    func preparedAnalysis() throws -> StabilizerPreparedAnalysis? {
        guard frames.count >= 3 else {
            return nil
        }
        return try AutoStabilizationEstimator.preparedAnalysis(sortedFrames: frames, motions: motions)
    }
}
