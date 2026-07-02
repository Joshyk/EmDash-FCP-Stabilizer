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
    var turnDetectedPixelOffset: vector_float2
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
        turnDetectedPixelOffset: vector_float2(0.0, 0.0),
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
        microJitterY: 1.0,
        microJitterRotation: 0.5,
        strideWobbleX: 1.0,
        strideWobbleY: 1.0,
        strideWobbleRotation: 0.5,
        panStabilizationStrength: 2.0,
        farFieldWarp: 0.5
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

fileprivate struct StabilizerFarFieldPlaneMotion {
    let dx: Float
    let dy: Float
    let signedRoll: Float
    let yawProxy: Float
    let pitchProxy: Float
    let shearX: Float
    let shearY: Float
    let authority: Float
    let parallaxPixels: Float
}

fileprivate struct StabilizerAffineAxisFit {
    let offset: Float
    let xSlope: Float
    let ySlope: Float
    let residual: Float
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
    private static let baseTurnSmoothingOffsetLimitY: Float = 0.055
    private static let extraTurnSmoothingOffsetLimitY: Float = 0.040
    private static let turnSmoothingFullScaleDegrees: Float = 0.16
    private static let baseTurnSmoothingRotationLimitDegrees: Float = 0.80
    private static let extraTurnSmoothingRotationLimitDegrees: Float = 0.55
    private static let renderTemporalSmoothingSampleCount = 25
    private static let renderTemporalSmoothingWindowSeconds = 2.20
    private static let renderFrameLocalSmoothingRadiusFrames = 0
    private static let renderFrameLocalSmoothingBaseWeight: Float = 1.25
    private static let renderFrameLocalSmoothingMinimumStepSeconds = 1.0 / 120.0
    private static let renderFrameLocalSmoothingMaximumStepSeconds = 1.0 / 24.0
    private static let renderTurnTransitionSmoothingSampleCount = 29
    private static let renderTurnTransitionSmoothingWindowSeconds = 2.8
    private static let renderTurnTransitionMinimumMacroPixels: Float = 0.5
    private static let renderTurnTransitionBridgeMinimumBlend: Float = 0.0
    private static let renderTurnTransitionBridgeMaximumBlend: Float = 0.86
    private static let renderTurnTransitionBridgeEdgeGateStart: Float = 0.45
    private static let renderTurnTransitionBridgeEdgeGateFull: Float = 0.78
    private static let renderTurnTransitionBridgeLowEdgeLargeTurnBlend: Float = 0.48
    private static let renderTurnTransitionBridgeLowEdgeMacroStartPixels: Float = 48.0
    private static let renderTurnTransitionBridgeLowEdgeMacroFullPixels: Float = 120.0
    private static let renderTurnTransitionDetectedCapStartPixels: Float = 180.0
    private static let renderTurnTransitionDetectedCapAllowancePixels: Float = 48.0
    private static let renderTurnGateSmoothingWindowSeconds = 0.90
    private static let renderFarFieldWarpSmoothingWindowSeconds = 0.20
    private static let renderFootstepJitterSmoothingWindowSeconds = 0.18
    private static let renderFootstepJitterSmoothingMaxBlend: Float = 0.42
    private static let renderFootstepJitterSmoothingPixelSimilarity: Float = 1.75
    private static let renderFootstepJitterSmoothingRotationSimilarity: Float = 0.22
    private static let footstepImpulseFullScalePixels: Float = 0.35
    private static let footstepImpulseFullScaleDegrees: Float = 0.08
    private static let footstepNoiseFloorScale: Float = 0.08
    private static let footstepSurroundingNoiseMultiplier: Float = 1.10
    private static let footstepSurroundingNoiseFloorCapScale: Float = 0.45
    private static let footstepFullResponseScale: Float = 0.55
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
    private static let strideWobbleFullResponseScale: Float = 0.55
    private static let turnSmoothingFullScalePixels: Float = 2.0
    private static let maximumTurnSmoothingStrength: Float = 12.0
    private static let turnOwnershipFootstepXSuppression: Float = 1.0
    private static let turnOwnershipFootstepYSuppression: Float = 0.45
    private static let turnOwnershipFootstepRollSuppression: Float = 0.55
    private static let turnOwnershipStrideXSuppression: Float = 1.0
    private static let turnOwnershipStrideYSuppression: Float = 0.38
    private static let turnOwnershipStrideRollSuppression: Float = 0.50
    private static let turnOwnershipFarFieldWarpSuppression: Float = 0.30
    private static let turnOwnedWalkingXGateFloorMax: Float = 0.82
    private static let turnOwnedStrideXGateFloorScale: Float = 0.92
    private static let turnOwnedWalkingXGateFloorStartPixels: Float = 12.0
    private static let turnOwnedWalkingXGateFloorFullPixels: Float = 75.0
    private static let turnMacroOwnershipBandStartPixels: Float = 16.0
    private static let turnMacroOwnershipBandFullPixels: Float = 96.0
    private static let turnMacroOwnershipTravelStartPixels: Float = 24.0
    private static let turnMacroOwnershipTravelFullPixels: Float = 180.0
    private static let turnMacroOwnershipTrackingStart: Float = 0.02
    private static let turnMacroOwnershipTrackingFull: Float = 0.12
    private static let turnMacroOwnershipScale: Float = 0.70
    private static let maxFarFieldShear: Float = 0.008
    private static let maxFarFieldYawPitchProxy: Float = 0.004
    private static let maxFarFieldPerspective: Float = 0.003
    private static let maxRenderedFarFieldShear: Float = 0.0048
    private static let maxRenderedFarFieldYawPitchProxy: Float = 0.0032
    private static let maxRenderedFarFieldPerspective: Float = 0.0020
    private static let maximumFarFieldWarpStrength: Float = 12.0
    private static let farFieldWarpTrackingGateStart: Float = 0.24
    private static let farFieldWarpTrackingGateFull: Float = 0.52
    private static let farFieldWarpTrackingGateMedianBlend: Float = 0.45
    private static let farFieldWarpTrackingGateStabilityLimit: Float = 0.15
    private static let farFieldWarpEdgeQualityGateStart: Float = 0.55
    private static let farFieldWarpEdgeQualityGateFull: Float = 0.86
    private static let farFieldWarpConsensusGateStart: Float = 0.04
    private static let farFieldWarpConsensusGateFull: Float = 0.28
    private static let farFieldConsensusConfidenceFloor: Float = 0.04
    private static let farFieldConsensusMinimumWeight: Float = 3.0
    private static let farFieldConsensusFullWeight: Float = 18.0
    private static let farFieldConsensusCoherenceFrameFraction: Float = 0.010
    private static let farFieldPlaneStrictThreshold: Float = 0.70
    private static let farFieldPlaneBroadThreshold: Float = 0.55
    private static let farFieldPlaneNearThreshold: Float = 0.45
    private static let farFieldPlaneMinimumBlocks = 3
    private static let farFieldPlaneParallaxStartPixels: Float = 0.65
    private static let farFieldPlaneParallaxFullPixels: Float = 5.0
    private static let farFieldPlaneAuthorityBase: Float = 0.25
    private static let farFieldPlaneAuthorityParallaxScale: Float = 0.60
    private static let farFieldPlaneMaximumAuthority: Float = 0.85
    private static let footstepImpulseInnerWindowSeconds = 0.10
    private static let footstepImpulseOuterWindowSeconds = 1.0
    private static let farFieldWarpInnerWindowSeconds = 0.10
    private static let farFieldWarpOuterWindowSeconds = 1.0
    private static let timeWindowSelectionEpsilon = 0.001
    private static let minimumAcceptedMotionBlocks = 3
    private static let minimumFarFieldMotionBlocks = 3
    private static let staggeredMotionBlockFarFieldThreshold: Float = 0.70
    private static let detailMotionBlockFarFieldThreshold: Float = 0.70
    private static let verticalDetailMotionBlockFarFieldThreshold: Float = 0.85
    private static let attitudeDetailMotionBlockFarFieldThreshold: Float = 0.45
    private static let attitudeDetailMotionBlockColumnRadius = 1
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
    private static let sharedPlaybackTrajectoryCacheLimit = 3
    private static let sharedPlaybackTrajectoryCacheLock = NSLock()
    private static var sharedPlaybackTrajectoryCaches: [PlaybackTrajectoryCacheKey: PlaybackTransformTrajectory] = [:]
    private static var sharedPlaybackTrajectoryCacheOrder: [PlaybackTrajectoryCacheKey] = []
    private static let playbackTrajectoryPixelRate: Float = 52.0
    private static let playbackTrajectoryMaximumPixelStep: Float = 0.86
    private static let playbackTrajectoryMinimumPixelStep: Float = 0.32
    private static let playbackTrajectoryRotationRate: Float = 2.4
    private static let playbackTrajectoryMaximumRotationStep: Float = 0.040
    private static let playbackTrajectoryMinimumRotationStep: Float = 0.012
    private static let playbackTrajectoryWarpRate: Float = 0.040
    private static let playbackTrajectoryMaximumWarpStep: Float = 0.00070
    private static let playbackTrajectoryMinimumWarpStep: Float = 0.00010
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
        let includeFarFieldWarp: Bool
    }

    private struct ResidualPercentileCacheKey: Hashable {
        let lowerIndex: Int
        let upperIndex: Int
        let count: Int
        let percentile: UInt32
    }

    private struct FootstepConfidenceCacheKey: Hashable {
        let kind: MotionPathKind
        let index: Int
        let trackingConfidence: UInt32
        let fullImpulseScale: UInt32
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

    private struct PlaybackTrajectoryCacheKey: Hashable {
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
    }

    private struct PlaybackTransformTrajectory {
        let times: [Double]
        let transforms: [StabilizerAutoTransform]

        func transform(at seconds: Double) -> StabilizerAutoTransform {
            guard !times.isEmpty,
                  times.count == transforms.count,
                  seconds.isFinite
            else {
                return .identity
            }
            if seconds <= times[0] {
                return transforms[0]
            }
            let lastIndex = times.count - 1
            if seconds >= times[lastIndex] {
                return transforms[lastIndex]
            }
            var lowerBound = 0
            var upperBound = lastIndex
            while lowerBound + 1 < upperBound {
                let middle = (lowerBound + upperBound) / 2
                if times[middle] <= seconds {
                    lowerBound = middle
                } else {
                    upperBound = middle
                }
            }
            let lowerTime = times[lowerBound]
            let upperTime = times[upperBound]
            let duration = upperTime - lowerTime
            guard duration.isFinite, duration > Double.ulpOfOne else {
                return transforms[lowerBound]
            }
            let fraction = Float(min(1.0, max(0.0, (seconds - lowerTime) / duration)))
            return weightedAverageTransform([
                (transform: transforms[lowerBound], weight: 1.0 - fraction),
                (transform: transforms[upperBound], weight: fraction)
            ])
        }
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
            if valueProvider == nil && overrides.isEmpty {
                return values[index]
            }
            if let override = overrides[index] {
                return override
            }
            if let providedValue = valueProvider?(index) {
                return providedValue
            }
            return values[index]
        }
    }

    private final class RenderEstimateCache {
        private let lock = NSLock()
        private var outerPredictions: [OuterPredictionCacheKey: Float] = [:]
        private var localAverages: [LocalAverageCacheKey: Float] = [:]
        private var rawTransforms: [RawTransformCacheKey: StabilizerAutoTransform] = [:]
        private var rawTransformOrder: [RawTransformCacheKey] = []
        private var residualPercentiles: [ResidualPercentileCacheKey: Float] = [:]
        private var footstepConfidences: [FootstepConfidenceCacheKey: Float] = [:]
        private let rawTransformLimit = 32768

        func rawTransform(
            analysis: StabilizerPreparedAnalysis,
            index: Int,
            outputSize: vector_float2,
            panSmoothSeconds: Double,
            strengths: StabilizerCorrectionStrengths,
            limitFootstepContinuity: Bool,
            includeFarFieldWarp: Bool
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
                limitFootstepContinuity: limitFootstepContinuity,
                includeFarFieldWarp: includeFarFieldWarp
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
                limitFootstepContinuity: limitFootstepContinuity,
                includeFarFieldWarp: includeFarFieldWarp
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

        func residualPercentile(
            analysis: StabilizerPreparedAnalysis,
            indices: [Int],
            percentile: Float
        ) -> Float {
            guard let key = residualPercentileCacheKey(indices: indices, percentile: percentile) else {
                return AutoStabilizationEstimator.percentileValue(
                    analysis.residuals,
                    indices: indices,
                    percentile: percentile
                )
            }

            lock.lock()
            if let cached = residualPercentiles[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let value = AutoStabilizationEstimator.percentileValue(
                analysis.residuals,
                indices: indices,
                percentile: percentile
            )

            lock.lock()
            residualPercentiles[key] = value
            lock.unlock()
            return value
        }

        private func residualPercentileCacheKey(
            indices: [Int],
            percentile: Float
        ) -> ResidualPercentileCacheKey? {
            guard let firstIndex = indices.first,
                  let lastIndex = indices.last,
                  firstIndex >= 0,
                  indices.count == (lastIndex - firstIndex + 1)
            else {
                return nil
            }
            return ResidualPercentileCacheKey(
                lowerIndex: firstIndex,
                upperIndex: lastIndex + 1,
                count: indices.count,
                percentile: percentile.bitPattern
            )
        }

        func footstepFrameConfidence(
            kind: MotionPathKind,
            values: [Float],
            baselineValues: EstimatedPath,
            frames: [StabilizerAnalysisFrame],
            index: Int,
            trackingConfidence: Float,
            fullImpulseScale: Float
        ) -> Float {
            let key = FootstepConfidenceCacheKey(
                kind: kind,
                index: index,
                trackingConfidence: trackingConfidence.bitPattern,
                fullImpulseScale: fullImpulseScale.bitPattern
            )
            lock.lock()
            if let cached = footstepConfidences[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let confidence = AutoStabilizationEstimator.footstepFrameConfidenceAtIndex(
                values: values,
                baselineValues: baselineValues,
                frames: frames,
                index: index,
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale
            )

            lock.lock()
            footstepConfidences[key] = confidence
            lock.unlock()
            return confidence
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
                return EstimatedPath(values: values)
            }
            let targetIndexSet = Set(indices)
            return EstimatedPath(
                values: values,
                valueProvider: { [weak self] index in
                    guard targetIndexSet.contains(index),
                          values.indices.contains(index),
                          analysis.frames.indices.contains(index),
                          let self
                    else {
                        return nil
                    }
                    return self.outerLinearPrediction(
                        kind,
                        analysis: analysis,
                        index: index,
                        innerWindowSeconds: innerWindowSeconds,
                        outerWindowSeconds: outerWindowSeconds
                    )
                }
            )
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
            var overrides = source.overrides
            for index in targetIndexSet where source.values.indices.contains(index) && analysis.frames.indices.contains(index) {
                overrides[index] = localTimeWeightedAverage(
                    kind,
                    sourceRole: sourceRole,
                    sourceVariant: sourceVariant,
                    source: source,
                    analysis: analysis,
                    index: index,
                    windowSeconds: windowSeconds
                )
            }
            return EstimatedPath(values: source.values, overrides: overrides, valueProvider: source.valueProvider)
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

    static func playbackEstimate(
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

        return playbackTrajectory(
            for: analysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ).transform(at: renderSeconds)
    }

    private static func playbackLocalContinuityEstimate(
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
        let interpolation = frameLookup(at: renderSeconds, in: frames).interpolation
        let centerIndex = interpolation.fraction > 0.5 ? interpolation.upperIndex : interpolation.lowerIndex
        let lowerIndex = max(0, centerIndex - 3)
        let upperIndex = min(frames.count - 1, centerIndex + 3)
        let cache = renderEstimateCache(for: analysis)
        let centerTransform = cache.rawTransform(
            analysis: analysis,
            index: centerIndex,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            limitFootstepContinuity: true,
            includeFarFieldWarp: true
        )
        var rawSamples: [(transform: StabilizerAutoTransform, weight: Float)] = []
        rawSamples.reserveCapacity(upperIndex - lowerIndex + 1)

        for index in lowerIndex...upperIndex {
            let transform = cache.rawTransform(
                analysis: analysis,
                index: index,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                limitFootstepContinuity: true,
                includeFarFieldWarp: true
            )
            let offset = frames[index].time - renderSeconds
            let sigma = max(1.0 / 600.0, 2.2 / 60.0)
            let weight = Float(Darwin.exp(-0.5 * (offset / sigma) * (offset / sigma)))
            guard weight > 0.0001 else {
                continue
            }
            rawSamples.append((transform: transform, weight: index == centerIndex ? weight * 1.15 : weight))
        }

        guard !rawSamples.isEmpty else {
            return centerTransform
        }
        guard rawSamples.count >= 3 else {
            return centerTransform
        }

        guard let medianX = median(rawSamples.map { $0.transform.pixelOffset.x }),
              let medianY = median(rawSamples.map { $0.transform.pixelOffset.y }),
              let medianRotation = median(rawSamples.map { $0.transform.rotationDegrees }),
              let madX = median(rawSamples.map { abs($0.transform.pixelOffset.x - medianX) }),
              let madY = median(rawSamples.map { abs($0.transform.pixelOffset.y - medianY) }),
              let madRotation = median(rawSamples.map { abs($0.transform.rotationDegrees - medianRotation) })
        else {
            return centerTransform
        }
        let xLimit = max(0.75, madX * 3.5)
        let yLimit = max(0.75, madY * 3.5)
        let rotationLimit = max(0.040, madRotation * 3.5)
        let filteredSamples = rawSamples.filter { sample in
            abs(sample.transform.pixelOffset.x - medianX) <= xLimit
                && abs(sample.transform.pixelOffset.y - medianY) <= yLimit
                && abs(sample.transform.rotationDegrees - medianRotation) <= rotationLimit
        }
        let samples = filteredSamples.count >= 3 ? filteredSamples : rawSamples
        var smoothedTransform = weightedAverageTransform(samples)
        smoothedTransform.rawPixelOffset = centerTransform.pixelOffset
        smoothedTransform.rawRotationDegrees = centerTransform.rotationDegrees
        smoothedTransform.temporalSmoothingPixelDelta = smoothedTransform.pixelOffset - centerTransform.pixelOffset
        smoothedTransform.temporalSmoothingRotationDelta = smoothedTransform.rotationDegrees - centerTransform.rotationDegrees
        smoothedTransform.temporalSmoothingSampleCount = Int32(samples.count)
        smoothedTransform.temporalSmoothingWindowSeconds = Float(max(0.0, frames[upperIndex].time - frames[lowerIndex].time))
        smoothedTransform.effectiveMicroJitterStrength = centerTransform.effectiveMicroJitterStrength
        smoothedTransform.effectiveStrideWobbleStrength = centerTransform.effectiveStrideWobbleStrength
        smoothedTransform.warpConfidence = centerTransform.warpConfidence
        smoothedTransform.microConfidence = centerTransform.microConfidence
        smoothedTransform.strideConfidence = centerTransform.strideConfidence
        smoothedTransform.turnConfidence = centerTransform.turnConfidence
        smoothedTransform.acceptedBlockCount = centerTransform.acceptedBlockCount
        smoothedTransform.totalBlockCount = centerTransform.totalBlockCount
        smoothedTransform.blurAmount = centerTransform.blurAmount
        smoothedTransform.trackingConfidence = centerTransform.trackingConfidence
        smoothedTransform.walkingTrackingConfidence = centerTransform.walkingTrackingConfidence
        smoothedTransform.motionConfidence = centerTransform.motionConfidence
        smoothedTransform.residual = centerTransform.residual
        smoothedTransform.footstepImpulse = centerTransform.footstepImpulse
        smoothedTransform.rawFootstepCorrection = centerTransform.rawFootstepCorrection
        smoothedTransform.limitedFootstepCorrection = smoothedTransform.microPixelOffset
        smoothedTransform.footstepPulseLimited = centerTransform.footstepPulseLimited
        smoothedTransform.searchRadiusHitCount = centerTransform.searchRadiusHitCount
        smoothedTransform.searchRadiusTotalCount = centerTransform.searchRadiusTotalCount
        return smoothedTransform
    }

    private static func playbackFrameCadenceEstimate(
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
        let renderEstimateCache = renderEstimateCache(for: analysis)

        struct LocalRawTransformKey: Hashable {
            let index: Int
            let limitFootstepContinuity: Bool
            let includeFarFieldWarp: Bool
        }

        var localRawTransforms: [LocalRawTransformKey: StabilizerAutoTransform] = [:]

        func rawTransform(
            at index: Int,
            limitFootstepContinuity: Bool,
            includeFarFieldWarp: Bool
        ) -> StabilizerAutoTransform {
            guard frames.indices.contains(index) else {
                return .identity
            }
            let key = LocalRawTransformKey(
                index: index,
                limitFootstepContinuity: limitFootstepContinuity,
                includeFarFieldWarp: includeFarFieldWarp
            )
            if let cached = localRawTransforms[key] {
                return cached
            }
            let transform = renderEstimateCache.rawTransform(
                analysis: analysis,
                index: index,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                limitFootstepContinuity: limitFootstepContinuity,
                includeFarFieldWarp: includeFarFieldWarp
            )
            localRawTransforms[key] = transform
            return transform
        }

        func interpolatedRawTransform(
            at seconds: Double,
            limitFootstepContinuity: Bool,
            includeFarFieldWarp: Bool
        ) -> StabilizerAutoTransform {
            let interpolation = frameLookup(at: seconds, in: frames).interpolation
            let lowerTransform = rawTransform(
                at: interpolation.lowerIndex,
                limitFootstepContinuity: limitFootstepContinuity,
                includeFarFieldWarp: includeFarFieldWarp
            )
            guard interpolation.upperIndex != interpolation.lowerIndex,
                  interpolation.fraction > 0.0001
            else {
                return lowerTransform
            }
            let upperWeight = clamp(interpolation.fraction, min: 0.0, max: 1.0)
            let lowerWeight = 1.0 - upperWeight
            return weightedAverageTransform([
                (transform: lowerTransform, weight: lowerWeight),
                (transform: rawTransform(
                    at: interpolation.upperIndex,
                    limitFootstepContinuity: limitFootstepContinuity,
                    includeFarFieldWarp: includeFarFieldWarp
                ), weight: upperWeight)
            ])
        }

        func weightedSamples(
            centerTransform: StabilizerAutoTransform,
            halfWindow: Double,
            sigma: Double,
            limitFootstepContinuity: Bool,
            includeFarFieldWarp: Bool
        ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
            let candidateIndices = indicesWithinTimeRadius(
                frames,
                centerTime: renderSeconds,
                radiusSeconds: halfWindow
            )
            var samples: [(transform: StabilizerAutoTransform, weight: Float)] = []
            samples.reserveCapacity(candidateIndices.count + 1)
            samples.append((transform: centerTransform, weight: 1.0))
            for index in candidateIndices {
                let offset = frames[index].time - renderSeconds
                if abs(offset) <= timeWindowSelectionEpsilon {
                    continue
                }
                let normalizedDistance = offset / sigma
                let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
                guard weight > 0.0001 else {
                    continue
                }
                samples.append((
                    transform: rawTransform(
                        at: index,
                        limitFootstepContinuity: limitFootstepContinuity,
                        includeFarFieldWarp: includeFarFieldWarp
                    ),
                    weight: weight
                ))
            }
            return samples
        }

        func turnTransitionSamples(centerTransform: StabilizerAutoTransform) -> [(transform: StabilizerAutoTransform, weight: Float)] {
            guard let firstTime = frames.first?.time,
                  let lastTime = frames.last?.time
            else {
                return [(centerTransform, 1.0)]
            }
            let sampleCount = max(3, renderTurnTransitionSmoothingSampleCount)
            let centerSample = sampleCount / 2
            let halfWindow = renderTurnTransitionSmoothingWindowSeconds * 0.5
            let denominator = Double(max(1, sampleCount - 1))
            let sampleStep = renderTurnTransitionSmoothingWindowSeconds / denominator
            let sigma = max(1e-6, halfWindow * 0.55)
            var rawSamples: [(transform: StabilizerAutoTransform, timeWeight: Float, isCenter: Bool)] = [(centerTransform, 1.0, true)]
            rawSamples.reserveCapacity(sampleCount)
            for sampleIndex in 0..<sampleCount where sampleIndex != centerSample {
                let offset = Double(sampleIndex - centerSample) * sampleStep
                let sampleSeconds = renderSeconds + offset
                guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                    continue
                }
                let normalizedDistance = offset / sigma
                let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
                guard weight > 0.0001 else {
                    continue
                }
                rawSamples.append((transform: interpolatedRawTransform(
                    at: sampleSeconds,
                    limitFootstepContinuity: false,
                    includeFarFieldWarp: false
                ), timeWeight: weight, isCenter: false))
            }

            var supportMagnitude: Float = 0.0
            var signedSupport: Float = 0.0
            var signedSupportWeight: Float = 0.0
            for sample in rawSamples {
                let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
                let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
                let evidenceWeight = sample.timeWeight * turnResponse * qualitySupport
                guard evidenceWeight > 0.0001 else {
                    continue
                }
                let macroX = sample.transform.macroPixelOffset.x
                supportMagnitude = max(supportMagnitude, abs(macroX))
                signedSupport += macroX * evidenceWeight
                signedSupportWeight += evidenceWeight
            }
            guard supportMagnitude >= renderTurnTransitionMinimumMacroPixels,
                  signedSupportWeight > 0.0001
            else {
                return [(centerTransform, 1.0)]
            }
            let dominantSign: Float = signedSupport >= 0.0 ? 1.0 : -1.0
            let samples = rawSamples.compactMap { sample -> (transform: StabilizerAutoTransform, weight: Float)? in
                let macroX = sample.transform.macroPixelOffset.x
                let macroMagnitude = abs(macroX)
                let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
                let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
                let evidenceWeight = turnResponse * qualitySupport
                let magnitudeSupport = confidenceRamp(
                    macroMagnitude,
                    start: supportMagnitude * 0.10,
                    full: max(supportMagnitude * 0.45, renderTurnTransitionMinimumMacroPixels)
                )
                let directionSupport: Float
                if macroMagnitude < renderTurnTransitionMinimumMacroPixels {
                    directionSupport = sample.isCenter ? 0.25 : 0.10
                } else {
                    directionSupport = (macroX * dominantSign) >= 0.0 ? 1.0 : 0.15
                }
                let centerScale: Float = sample.isCenter
                    ? 0.25 + (turnCorrectionConfidenceResponse(sample.transform.turnConfidence) * 0.75)
                    : 1.0
                let weight = sample.timeWeight
                    * evidenceWeight
                    * max(0.15, magnitudeSupport)
                    * directionSupport
                    * centerScale
                guard weight > 0.0001 else {
                    return nil
                }
                return (transform: sample.transform, weight: weight)
            }
            return samples.isEmpty ? [(transform: centerTransform, weight: Float(1.0))] : samples
        }

        func smoothedFootstepJitter(centerTransform: StabilizerAutoTransform) -> (microPixelOffset: vector_float2, rotationDegrees: Float) {
            let halfWindow = renderFootstepJitterSmoothingWindowSeconds * 0.5
            let sigma = max(1e-6, halfWindow * 0.55)
            let candidateIndices = indicesWithinTimeRadius(
                frames,
                centerTime: renderSeconds,
                radiusSeconds: halfWindow
            )
            var xSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
            var ySamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
            var rollSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
            xSamples.reserveCapacity(candidateIndices.count)
            ySamples.reserveCapacity(candidateIndices.count)
            rollSamples.reserveCapacity(candidateIndices.count)
            for index in candidateIndices {
                let offset = frames[index].time - renderSeconds
                if abs(offset) <= timeWindowSelectionEpsilon {
                    continue
                }
                let normalizedDistance = offset / sigma
                let timeWeight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
                guard timeWeight > 0.0001 else {
                    continue
                }
                let transform = rawTransform(
                    at: index,
                    limitFootstepContinuity: true,
                    includeFarFieldWarp: false
                )
                xSamples.append((transform.microPixelOffset.x, transform.effectiveMicroJitterStrength.x, timeWeight))
                ySamples.append((transform.microPixelOffset.y, transform.effectiveMicroJitterStrength.y, timeWeight))
                rollSamples.append((transform.footstepJitterRotationDegrees, transform.effectiveMicroJitterStrength.z, timeWeight))
            }
            return (
                microPixelOffset: vector_float2(
                    smoothedFootstepScalar(
                        centerValue: centerTransform.microPixelOffset.x,
                        centerConfidence: centerTransform.effectiveMicroJitterStrength.x,
                        samples: xSamples,
                        similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                    ),
                    smoothedFootstepScalar(
                        centerValue: centerTransform.microPixelOffset.y,
                        centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                        samples: ySamples,
                        similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                    )
                ),
                rotationDegrees: smoothedFootstepScalar(
                    centerValue: centerTransform.footstepJitterRotationDegrees,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                    samples: rollSamples,
                    similarityScale: renderFootstepJitterSmoothingRotationSimilarity
                )
            )
        }

        let rawCenterTransform = interpolatedRawTransform(
            at: renderSeconds,
            limitFootstepContinuity: true,
            includeFarFieldWarp: true
        )
        let broadHalfWindow = renderTemporalSmoothingWindowSeconds * 0.5
        let broadSamples = weightedSamples(
            centerTransform: rawCenterTransform,
            halfWindow: broadHalfWindow,
            sigma: max(1e-6, broadHalfWindow * 0.5),
            limitFootstepContinuity: false,
            includeFarFieldWarp: false
        )
        var smoothedTransform = broadSamples.isEmpty
            ? rawCenterTransform
            : weightedAverageTransform(broadSamples)
        let turnSamples = turnTransitionSamples(centerTransform: rawCenterTransform)
        if !turnSamples.isEmpty {
            let smoothedTurnTransform = weightedAverageTransform(turnSamples)
            var bridgedMacroOffset = smoothedTurnTransform.macroPixelOffset
            let centerMacroX = rawCenterTransform.macroPixelOffset.x
            let bridgedMacroX = bridgedMacroOffset.x
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(rawCenterTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70) * 0.85
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: rawCenterTransform,
                bridgeMacroX: bridgedMacroOffset.x
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: rawCenterTransform,
                bridgeTransform: smoothedTurnTransform
            )
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
            smoothedTransform.macroPixelOffset.x = turnTransitionDetectedCappedMacroX(
                centerTransform: rawCenterTransform,
                proposedMacroX: smoothedTransform.macroPixelOffset.x
            )
            smoothedTransform.turnConfidence = smoothedTurnTransform.turnConfidence
        }

        let warpHalfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        let warpSamples = weightedSamples(
            centerTransform: rawCenterTransform,
            halfWindow: warpHalfWindow,
            sigma: max(1e-6, warpHalfWindow * 0.55),
            limitFootstepContinuity: false,
            includeFarFieldWarp: true
        )
        let smoothedWarpTransform = warpSamples.isEmpty
            ? rawCenterTransform
            : weightedAverageTransform(warpSamples)
        let smoothedWarpConfidence = clamp(smoothedWarpTransform.warpConfidence, min: 0.0, max: 1.0)
        let temporalWarpScale = farFieldWarpTemporalScale(
            centerTransform: rawCenterTransform,
            smoothedTransform: smoothedWarpTransform,
            smoothedConfidence: smoothedWarpConfidence
        )
        smoothedTransform.warpConfidence = smoothedWarpConfidence * temporalWarpScale
        smoothedTransform.yawPitchProxy = smoothedWarpTransform.yawPitchProxy * temporalWarpScale
        smoothedTransform.shear = smoothedWarpTransform.shear * temporalWarpScale
        smoothedTransform.perspective = smoothedWarpTransform.perspective * temporalWarpScale

        let footstep = smoothedFootstepJitter(centerTransform: rawCenterTransform)
        smoothedTransform.microPixelOffset = footstep.microPixelOffset
        smoothedTransform.footstepJitterRotationDegrees = footstep.rotationDegrees
        smoothedTransform.effectiveMicroJitterStrength = rawCenterTransform.effectiveMicroJitterStrength
        smoothedTransform.microConfidence = rawCenterTransform.microConfidence
        smoothedTransform.footstepImpulse = rawCenterTransform.footstepImpulse
        smoothedTransform.rawFootstepCorrection = rawCenterTransform.rawFootstepCorrection
        smoothedTransform.limitedFootstepCorrection = footstep.microPixelOffset
        smoothedTransform.footstepPulseLimited = rawCenterTransform.footstepPulseLimited
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
        smoothedTransform.temporalSmoothingSampleCount = Int32(broadSamples.count)
        smoothedTransform.temporalSmoothingWindowSeconds = Float(renderTemporalSmoothingWindowSeconds)
        return smoothedTransform
    }

    private static func playbackTrajectory(
        for analysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory {
        guard let key = playbackTrajectoryCacheKey(
            analysis: analysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) else {
            return PlaybackTransformTrajectory(times: [], transforms: [])
        }

        sharedPlaybackTrajectoryCacheLock.lock()
        if let cached = sharedPlaybackTrajectoryCaches[key] {
            sharedPlaybackTrajectoryCacheLock.unlock()
            return cached
        }
        sharedPlaybackTrajectoryCacheLock.unlock()

        let built = buildPlaybackTrajectory(
            analysis: analysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )

        sharedPlaybackTrajectoryCacheLock.lock()
        defer { sharedPlaybackTrajectoryCacheLock.unlock() }
        if let cached = sharedPlaybackTrajectoryCaches[key] {
            return cached
        }
        sharedPlaybackTrajectoryCaches[key] = built
        sharedPlaybackTrajectoryCacheOrder.append(key)
        while sharedPlaybackTrajectoryCacheOrder.count > sharedPlaybackTrajectoryCacheLimit {
            let oldestKey = sharedPlaybackTrajectoryCacheOrder.removeFirst()
            sharedPlaybackTrajectoryCaches.removeValue(forKey: oldestKey)
        }
        return built
    }

    private static func playbackTrajectoryCacheKey(
        analysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTrajectoryCacheKey? {
        let frames = analysis.frames
        guard let firstFrame = frames.first,
              let lastFrame = frames.last
        else {
            return nil
        }
        let middleIndex = frames.count / 2
        let middleFrame = frames[middleIndex]
        let firstPathX = analysis.pathX.first ?? 0.0
        let middlePathX = analysis.pathX.indices.contains(middleIndex) ? analysis.pathX[middleIndex] : firstPathX
        let lastPathX = analysis.pathX.last ?? firstPathX
        let firstPathY = analysis.pathY.first ?? 0.0
        let middlePathY = analysis.pathY.indices.contains(middleIndex) ? analysis.pathY[middleIndex] : firstPathY
        let lastPathY = analysis.pathY.last ?? firstPathY
        let firstPathRoll = analysis.pathRoll.first ?? 0.0
        let middlePathRoll = analysis.pathRoll.indices.contains(middleIndex) ? analysis.pathRoll[middleIndex] : firstPathRoll
        let lastPathRoll = analysis.pathRoll.last ?? firstPathRoll
        return PlaybackTrajectoryCacheKey(
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
            middlePathX: middlePathX.bitPattern,
            lastPathX: lastPathX.bitPattern,
            firstPathY: firstPathY.bitPattern,
            middlePathY: middlePathY.bitPattern,
            lastPathY: lastPathY.bitPattern,
            firstPathRoll: firstPathRoll.bitPattern,
            middlePathRoll: middlePathRoll.bitPattern,
            lastPathRoll: lastPathRoll.bitPattern,
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
            farFieldWarp: strengths.farFieldWarp.bitPattern
        )
    }

    private static func buildPlaybackTrajectory(
        analysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return PlaybackTransformTrajectory(times: frames.map(\.time), transforms: Array(repeating: .identity, count: frames.count))
        }
        let cache = renderEstimateCache(for: analysis)
        let rawTransforms = frames.indices.map { index in
            cache.rawTransform(
                analysis: analysis,
                index: index,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                limitFootstepContinuity: true,
                includeFarFieldWarp: true
            )
        }
        let limitedTransforms = playbackTrajectoryZeroPhaseLimitedTransforms(
            frames: frames,
            rawTransforms: rawTransforms
        )
        return PlaybackTransformTrajectory(times: frames.map(\.time), transforms: limitedTransforms)
    }

    private static func playbackTrajectoryZeroPhaseLimitedTransforms(
        frames: [StabilizerAnalysisFrame],
        rawTransforms: [StabilizerAutoTransform],
        diagnosticTransforms: [StabilizerAutoTransform]? = nil
    ) -> [StabilizerAutoTransform] {
        guard frames.count == rawTransforms.count,
              !frames.isEmpty
        else {
            return rawTransforms
        }
        guard rawTransforms.count >= 3 else {
            return rawTransforms
        }

        var forward = rawTransforms
        for index in 1..<rawTransforms.count {
            let deltaSeconds = max(0.0, frames[index].time - frames[index - 1].time)
            forward[index] = playbackTrajectoryLimitedTransform(
                rawTransforms[index],
                previous: forward[index - 1],
                deltaSeconds: deltaSeconds
            )
        }

        var backward = rawTransforms
        if rawTransforms.count > 1 {
            for index in stride(from: rawTransforms.count - 2, through: 0, by: -1) {
                let deltaSeconds = max(0.0, frames[index + 1].time - frames[index].time)
                backward[index] = playbackTrajectoryLimitedTransform(
                    rawTransforms[index],
                    previous: backward[index + 1],
                    deltaSeconds: deltaSeconds
                )
            }
        }

        let diagnostics = (diagnosticTransforms?.count == rawTransforms.count) ? diagnosticTransforms! : rawTransforms
        return rawTransforms.indices.map { index in
            let blended = weightedAverageTransform([
                (transform: forward[index], weight: 0.5),
                (transform: backward[index], weight: 0.5)
            ])
            return playbackTrajectoryTransformWithCurrentDiagnostics(
                blended,
                rawTransform: diagnostics[index]
            )
        }
    }

    private static func playbackTrajectoryStepLimit(
        deltaSeconds: Double,
        rate: Float,
        minimum: Float,
        maximum: Float
    ) -> Float {
        guard deltaSeconds.isFinite, deltaSeconds > 0.0 else {
            return minimum
        }
        return max(minimum, min(maximum, Float(deltaSeconds) * rate))
    }

    private static func playbackTrajectoryLimitedScalar(_ current: Float, previous: Float, limit: Float) -> Float {
        guard current.isFinite, previous.isFinite, limit.isFinite, limit >= 0.0 else {
            return current
        }
        let delta = current - previous
        return previous + max(-limit, min(limit, delta))
    }

    private static func playbackTrajectoryLimitedVector(
        _ current: vector_float2,
        previous: vector_float2,
        limit: Float
    ) -> vector_float2 {
        vector_float2(
            playbackTrajectoryLimitedScalar(current.x, previous: previous.x, limit: limit),
            playbackTrajectoryLimitedScalar(current.y, previous: previous.y, limit: limit)
        )
    }

    private static func playbackTrajectoryLimitedTransform(
        _ current: StabilizerAutoTransform,
        previous: StabilizerAutoTransform,
        deltaSeconds: Double
    ) -> StabilizerAutoTransform {
        let pixelLimit = playbackTrajectoryStepLimit(
            deltaSeconds: deltaSeconds,
            rate: playbackTrajectoryPixelRate,
            minimum: playbackTrajectoryMinimumPixelStep,
            maximum: playbackTrajectoryMaximumPixelStep
        )
        let rotationLimit = playbackTrajectoryStepLimit(
            deltaSeconds: deltaSeconds,
            rate: playbackTrajectoryRotationRate,
            minimum: playbackTrajectoryMinimumRotationStep,
            maximum: playbackTrajectoryMaximumRotationStep
        )
        let warpLimit = playbackTrajectoryStepLimit(
            deltaSeconds: deltaSeconds,
            rate: playbackTrajectoryWarpRate,
            minimum: playbackTrajectoryMinimumWarpStep,
            maximum: playbackTrajectoryMaximumWarpStep
        )
        var limited = current

        limited.macroPixelOffset = playbackTrajectoryLimitedVector(
            current.macroPixelOffset,
            previous: previous.macroPixelOffset,
            limit: pixelLimit * 0.85
        )
        limited.microPixelOffset = playbackTrajectoryLimitedVector(
            current.microPixelOffset,
            previous: previous.microPixelOffset,
            limit: pixelLimit * 0.55
        )
        limited.strideWobblePixelOffset = playbackTrajectoryLimitedVector(
            current.strideWobblePixelOffset,
            previous: previous.strideWobblePixelOffset,
            limit: pixelLimit * 0.65
        )
        let componentPixelOffset = limited.macroPixelOffset
            + limited.microPixelOffset
            + limited.strideWobblePixelOffset
        let finalPixelOffset = playbackTrajectoryLimitedVector(
            componentPixelOffset,
            previous: previous.pixelOffset,
            limit: pixelLimit
        )
        limited.macroPixelOffset += finalPixelOffset - componentPixelOffset
        limited.pixelOffset = finalPixelOffset

        limited.footstepJitterRotationDegrees = playbackTrajectoryLimitedScalar(
            current.footstepJitterRotationDegrees,
            previous: previous.footstepJitterRotationDegrees,
            limit: rotationLimit * 0.60
        )
        limited.strideWobbleRotationDegrees = playbackTrajectoryLimitedScalar(
            current.strideWobbleRotationDegrees,
            previous: previous.strideWobbleRotationDegrees,
            limit: rotationLimit * 0.80
        )
        let componentRotation = limited.footstepJitterRotationDegrees + limited.strideWobbleRotationDegrees
        let finalRotation = playbackTrajectoryLimitedScalar(
            componentRotation,
            previous: previous.rotationDegrees,
            limit: rotationLimit
        )
        limited.strideWobbleRotationDegrees += finalRotation - componentRotation
        limited.rotationDegrees = finalRotation

        limited.yawPitchProxy = playbackTrajectoryLimitedVector(
            current.yawPitchProxy,
            previous: previous.yawPitchProxy,
            limit: warpLimit
        )
        limited.shear = playbackTrajectoryLimitedVector(
            current.shear,
            previous: previous.shear,
            limit: warpLimit
        )
        limited.perspective = playbackTrajectoryLimitedVector(
            current.perspective,
            previous: previous.perspective,
            limit: warpLimit
        )
        return playbackTrajectoryTransformWithCurrentDiagnostics(limited, rawTransform: current)
    }

    private static func playbackTrajectoryTransformWithCurrentDiagnostics(
        _ limitedTransform: StabilizerAutoTransform,
        rawTransform: StabilizerAutoTransform
    ) -> StabilizerAutoTransform {
        var transform = limitedTransform
        transform.turnDetectedPixelOffset = rawTransform.turnDetectedPixelOffset
        transform.rawPixelOffset = rawTransform.pixelOffset
        transform.rawRotationDegrees = rawTransform.rotationDegrees
        transform.temporalSmoothingPixelDelta = transform.pixelOffset - rawTransform.pixelOffset
        transform.temporalSmoothingRotationDelta = transform.rotationDegrees - rawTransform.rotationDegrees
        transform.temporalSmoothingSampleCount = 2
        transform.temporalSmoothingWindowSeconds = Float(renderFrameLocalSmoothingMinimumStepSeconds)
        transform.effectiveMicroJitterStrength = rawTransform.effectiveMicroJitterStrength
        transform.effectiveStrideWobbleStrength = rawTransform.effectiveStrideWobbleStrength
        transform.warpConfidence = rawTransform.warpConfidence
        transform.microConfidence = rawTransform.microConfidence
        transform.strideConfidence = rawTransform.strideConfidence
        transform.turnConfidence = rawTransform.turnConfidence
        transform.acceptedBlockCount = rawTransform.acceptedBlockCount
        transform.totalBlockCount = rawTransform.totalBlockCount
        transform.blurAmount = rawTransform.blurAmount
        transform.trackingConfidence = rawTransform.trackingConfidence
        transform.walkingTrackingConfidence = rawTransform.walkingTrackingConfidence
        transform.motionConfidence = rawTransform.motionConfidence
        transform.residual = rawTransform.residual
        transform.footstepImpulse = rawTransform.footstepImpulse
        transform.rawFootstepCorrection = rawTransform.rawFootstepCorrection
        transform.limitedFootstepCorrection = transform.microPixelOffset
        transform.footstepPulseLimited = rawTransform.footstepPulseLimited
        transform.searchRadiusHitCount = rawTransform.searchRadiusHitCount
        transform.searchRadiusTotalCount = rawTransform.searchRadiusTotalCount
        return transform
    }

    private static func playbackTrajectorySmoothedTransform(
        index: Int,
        frames: [StabilizerAnalysisFrame],
        rawTransforms: [StabilizerAutoTransform]
    ) -> StabilizerAutoTransform {
        guard frames.indices.contains(index),
              rawTransforms.indices.contains(index)
        else {
            return .identity
        }
        let centerTime = frames[index].time
        let centerTransform = rawTransforms[index]
        let broadHalfWindow = renderTemporalSmoothingWindowSeconds * 0.5
        let broadSigma = max(1e-6, broadHalfWindow * 0.5)
        let broadSamples = playbackTrajectoryWeightedSamples(
            frames: frames,
            transforms: rawTransforms,
            centerTime: centerTime,
            halfWindow: broadHalfWindow,
            sigma: broadSigma
        )
        var smoothedTransform = broadSamples.isEmpty
            ? centerTransform
            : weightedAverageTransform(broadSamples)

        let turnSamples = playbackTrajectoryTurnTransitionSamples(
            centerTransform: centerTransform,
            centerTime: centerTime,
            frames: frames,
            transforms: rawTransforms
        )
        if !turnSamples.isEmpty {
            let smoothedTurnTransform = weightedAverageTransform(turnSamples)
            var bridgedMacroOffset = smoothedTurnTransform.macroPixelOffset
            let centerMacroX = centerTransform.macroPixelOffset.x
            let bridgedMacroX = bridgedMacroOffset.x
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(centerTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70) * 0.85
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: centerTransform,
                bridgeMacroX: bridgedMacroOffset.x
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: centerTransform,
                bridgeTransform: smoothedTurnTransform
            )
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
            smoothedTransform.macroPixelOffset.x = turnTransitionDetectedCappedMacroX(
                centerTransform: centerTransform,
                proposedMacroX: smoothedTransform.macroPixelOffset.x
            )
            smoothedTransform.turnConfidence = smoothedTurnTransform.turnConfidence
        }

        let warpHalfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        let warpSamples = playbackTrajectoryWeightedSamples(
            frames: frames,
            transforms: rawTransforms,
            centerTime: centerTime,
            halfWindow: warpHalfWindow,
            sigma: max(1e-6, warpHalfWindow * 0.55)
        )
        let smoothedWarpTransform = warpSamples.isEmpty
            ? centerTransform
            : weightedAverageTransform(warpSamples)
        let smoothedWarpConfidence = clamp(smoothedWarpTransform.warpConfidence, min: 0.0, max: 1.0)
        let temporalWarpScale = farFieldWarpTemporalScale(
            centerTransform: centerTransform,
            smoothedTransform: smoothedWarpTransform,
            smoothedConfidence: smoothedWarpConfidence
        )
        smoothedTransform.warpConfidence = smoothedWarpConfidence * temporalWarpScale
        smoothedTransform.yawPitchProxy = smoothedWarpTransform.yawPitchProxy * temporalWarpScale
        smoothedTransform.shear = smoothedWarpTransform.shear * temporalWarpScale
        smoothedTransform.perspective = smoothedWarpTransform.perspective * temporalWarpScale

        let footstep = playbackTrajectorySmoothedFootstepJitter(
            centerTransform: centerTransform,
            centerTime: centerTime,
            frames: frames,
            transforms: rawTransforms
        )
        smoothedTransform.microPixelOffset = footstep.microPixelOffset
        smoothedTransform.footstepJitterRotationDegrees = footstep.rotationDegrees
        smoothedTransform.effectiveMicroJitterStrength = centerTransform.effectiveMicroJitterStrength
        smoothedTransform.microConfidence = centerTransform.microConfidence
        smoothedTransform.footstepImpulse = centerTransform.footstepImpulse
        smoothedTransform.rawFootstepCorrection = centerTransform.rawFootstepCorrection
        smoothedTransform.limitedFootstepCorrection = footstep.microPixelOffset
        smoothedTransform.footstepPulseLimited = centerTransform.footstepPulseLimited
        smoothedTransform.trackingConfidence = clamp(smoothedTransform.trackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.walkingTrackingConfidence = clamp(smoothedTransform.walkingTrackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.motionConfidence = clamp(smoothedTransform.motionConfidence, min: 0.0, max: 1.0)
        smoothedTransform.residual = centerTransform.residual
        smoothedTransform.searchRadiusHitCount = centerTransform.searchRadiusHitCount
        smoothedTransform.searchRadiusTotalCount = centerTransform.searchRadiusTotalCount
        smoothedTransform.pixelOffset = smoothedTransform.macroPixelOffset
            + smoothedTransform.microPixelOffset
            + smoothedTransform.strideWobblePixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
        smoothedTransform.rawPixelOffset = centerTransform.pixelOffset
        smoothedTransform.rawRotationDegrees = centerTransform.rotationDegrees
        smoothedTransform.temporalSmoothingPixelDelta = smoothedTransform.pixelOffset - centerTransform.pixelOffset
        smoothedTransform.temporalSmoothingRotationDelta = smoothedTransform.rotationDegrees - centerTransform.rotationDegrees
        smoothedTransform.temporalSmoothingSampleCount = Int32(broadSamples.count)
        smoothedTransform.temporalSmoothingWindowSeconds = Float(renderTemporalSmoothingWindowSeconds)
        return smoothedTransform
    }

    private static func playbackTrajectoryWeightedSamples(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        centerTime: Double,
        halfWindow: Double,
        sigma: Double
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        guard halfWindow.isFinite,
              halfWindow >= 0.0,
              sigma.isFinite,
              sigma > Double.ulpOfOne
        else {
            return []
        }
        let candidateIndices = indicesWithinTimeRadius(
            frames,
            centerTime: centerTime,
            radiusSeconds: halfWindow
        )
        var samples: [(transform: StabilizerAutoTransform, weight: Float)] = []
        samples.reserveCapacity(candidateIndices.count)
        for index in candidateIndices where transforms.indices.contains(index) {
            let time = frames[index].time
            let offset = time - centerTime
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            samples.append((transform: transforms[index], weight: weight))
        }
        return samples
    }

    private static func playbackTrajectoryTurnTransitionSamples(
        centerTransform: StabilizerAutoTransform,
        centerTime: Double,
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform]
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        guard let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return [(centerTransform, 1.0)]
        }
        let sampleCount = max(3, renderTurnTransitionSmoothingSampleCount)
        let centerSample = sampleCount / 2
        let halfWindow = renderTurnTransitionSmoothingWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = renderTurnTransitionSmoothingWindowSeconds / denominator
        let sigma = max(1e-6, halfWindow * 0.55)
        var rawSamples: [(transform: StabilizerAutoTransform, timeWeight: Float, isCenter: Bool)] = [(centerTransform, 1.0, true)]
        rawSamples.reserveCapacity(sampleCount)
        for sampleIndex in 0..<sampleCount where sampleIndex != centerSample {
            let offset = Double(sampleIndex - centerSample) * sampleStep
            let sampleSeconds = centerTime + offset
            guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let transform = playbackTrajectoryInterpolatedRawTransform(
                frames: frames,
                transforms: transforms,
                seconds: sampleSeconds
            )
            rawSamples.append((transform: transform, timeWeight: weight, isCenter: false))
        }

        var supportMagnitude: Float = 0.0
        var signedSupport: Float = 0.0
        var signedSupportWeight: Float = 0.0
        for sample in rawSamples {
            let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
            let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
            let evidenceWeight = sample.timeWeight * turnResponse * qualitySupport
            guard evidenceWeight > 0.0001 else {
                continue
            }
            let macroX = sample.transform.macroPixelOffset.x
            supportMagnitude = max(supportMagnitude, abs(macroX))
            signedSupport += macroX * evidenceWeight
            signedSupportWeight += evidenceWeight
        }
        guard supportMagnitude >= renderTurnTransitionMinimumMacroPixels,
              signedSupportWeight > 0.0001
        else {
            return [(centerTransform, 1.0)]
        }
        let dominantSign: Float = signedSupport >= 0.0 ? 1.0 : -1.0
        let samples = rawSamples.compactMap { sample -> (transform: StabilizerAutoTransform, weight: Float)? in
            let macroX = sample.transform.macroPixelOffset.x
            let macroMagnitude = abs(macroX)
            let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
            let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
            let evidenceWeight = turnResponse * qualitySupport
            let magnitudeSupport = confidenceRamp(
                macroMagnitude,
                start: supportMagnitude * 0.10,
                full: max(supportMagnitude * 0.45, renderTurnTransitionMinimumMacroPixels)
            )
            let directionSupport: Float
            if macroMagnitude < renderTurnTransitionMinimumMacroPixels {
                directionSupport = sample.isCenter ? 0.25 : 0.10
            } else {
                directionSupport = (macroX * dominantSign) >= 0.0 ? 1.0 : 0.15
            }
            let centerScale: Float = sample.isCenter
                ? 0.25 + (turnCorrectionConfidenceResponse(sample.transform.turnConfidence) * 0.75)
                : 1.0
            let weight = sample.timeWeight
                * evidenceWeight
                * max(0.15, magnitudeSupport)
                * directionSupport
                * centerScale
            guard weight > 0.0001 else {
                return nil
            }
            return (transform: sample.transform, weight: weight)
        }
        return samples.isEmpty ? [(transform: centerTransform, weight: Float(1.0))] : samples
    }

    private static func playbackTrajectoryInterpolatedRawTransform(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        seconds: Double
    ) -> StabilizerAutoTransform {
        guard !frames.isEmpty,
              frames.count == transforms.count,
              seconds.isFinite
        else {
            return .identity
        }
        if seconds <= frames[0].time {
            return transforms[0]
        }
        let lastIndex = frames.count - 1
        if seconds >= frames[lastIndex].time {
            return transforms[lastIndex]
        }
        let interpolation = frameLookup(at: seconds, in: frames).interpolation
        guard transforms.indices.contains(interpolation.lowerIndex) else {
            return .identity
        }
        let lowerTransform = transforms[interpolation.lowerIndex]
        guard interpolation.upperIndex != interpolation.lowerIndex,
              interpolation.fraction > 0.0001,
              transforms.indices.contains(interpolation.upperIndex)
        else {
            return lowerTransform
        }
        let upperWeight = clamp(interpolation.fraction, min: 0.0, max: 1.0)
        let lowerWeight = 1.0 - upperWeight
        return weightedAverageTransform([
            (transform: lowerTransform, weight: lowerWeight),
            (transform: transforms[interpolation.upperIndex], weight: upperWeight)
        ])
    }

    private static func playbackTrajectorySmoothedFootstepJitter(
        centerTransform: StabilizerAutoTransform,
        centerTime: Double,
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform]
    ) -> (microPixelOffset: vector_float2, rotationDegrees: Float) {
        let halfWindow = renderFootstepJitterSmoothingWindowSeconds * 0.5
        let sigma = max(1e-6, halfWindow * 0.55)
        let candidateIndices = indicesWithinTimeRadius(
            frames,
            centerTime: centerTime,
            radiusSeconds: halfWindow
        )
        var xSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        var ySamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        var rollSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        xSamples.reserveCapacity(candidateIndices.count)
        ySamples.reserveCapacity(candidateIndices.count)
        rollSamples.reserveCapacity(candidateIndices.count)

        for index in candidateIndices where transforms.indices.contains(index) {
            let time = frames[index].time
            let offset = time - centerTime
            if abs(offset) <= timeWindowSelectionEpsilon {
                continue
            }
            let normalizedDistance = offset / sigma
            let timeWeight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard timeWeight > 0.0001 else {
                continue
            }
            let transform = transforms[index]
            xSamples.append((transform.microPixelOffset.x, transform.effectiveMicroJitterStrength.x, timeWeight))
            ySamples.append((transform.microPixelOffset.y, transform.effectiveMicroJitterStrength.y, timeWeight))
            rollSamples.append((transform.footstepJitterRotationDegrees, transform.effectiveMicroJitterStrength.z, timeWeight))
        }

        return (
            microPixelOffset: vector_float2(
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.x,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.x,
                    samples: xSamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                ),
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.y,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                    samples: ySamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                )
            ),
            rotationDegrees: smoothedFootstepScalar(
                centerValue: centerTransform.footstepJitterRotationDegrees,
                centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                samples: rollSamples,
                similarityScale: renderFootstepJitterSmoothingRotationSimilarity
            )
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

    private static func playbackRawEstimate(
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

        let frameLookup = frameLookup(at: renderSeconds, in: frames)
        let centerIndex = frameLookup.centerIndex
        let frameInterpolation = frameLookup.interpolation
        guard frames.indices.contains(centerIndex) else {
            return .identity
        }

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let effectiveStrideWobbleWindowSeconds = strideWobbleWindowSeconds
        let smoothWindowSeconds = max(effectiveStrideWobbleWindowSeconds, panSmoothSeconds)
        let activeIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: smoothWindowSeconds * 0.5
        )
        let turnActiveIndices = activeIndices.isEmpty ? [centerIndex] : activeIndices
        let strideIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: effectiveStrideWobbleWindowSeconds * 0.5
        )
        let strideActiveIndices = strideIndices.isEmpty ? [centerIndex] : strideIndices
        let cache = renderEstimateCache(for: analysis)

        func outerPredictionPath(_ kind: MotionPathKind) -> EstimatedPath {
            let values = AutoStabilizationEstimator.values(for: kind, analysis: analysis)
            return EstimatedPath(values: values, valueProvider: { index in
                guard values.indices.contains(index),
                      frames.indices.contains(index)
                else {
                    return nil
                }
                return outerLinearPrediction(
                    values,
                    frames: frames,
                    centerIndex: index,
                    innerWindowSeconds: footstepImpulseInnerWindowSeconds,
                    outerWindowSeconds: footstepImpulseOuterWindowSeconds
                ) ?? values[index]
            })
        }

        let footstepBaselineXPath = outerPredictionPath(.footstepX)
        let footstepBaselineYPath = outerPredictionPath(.footstepY)
        let footstepBaselineRollPath = outerPredictionPath(.footstepRoll)
        let centerResidual = interpolatedValue(analysis.residuals, using: frameInterpolation)
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
        let pathX = EstimatedPath(values: analysis.pathX)
        let pathY = EstimatedPath(values: analysis.pathY)
        let pathRoll = EstimatedPath(values: analysis.pathRoll)
        let footstepPathX = EstimatedPath(values: analysis.footstepPathX)
        let footstepPathY = EstimatedPath(values: analysis.footstepPathY)
        let footstepPathRoll = EstimatedPath(values: analysis.footstepPathRoll)
        let footstepPathXAtRender = interpolatedValue(analysis.footstepPathX, using: frameInterpolation)
        let footstepPathYAtRender = interpolatedValue(analysis.footstepPathY, using: frameInterpolation)
        let footstepPathRollAtRender = interpolatedValue(analysis.footstepPathRoll, using: frameInterpolation)
        let microImpulseBaselineX = interpolatedValue(footstepBaselineXPath, using: frameInterpolation)
        let microImpulseBaselineY = interpolatedValue(footstepBaselineYPath, using: frameInterpolation)
        let microImpulseBaselineRoll = interpolatedValue(footstepBaselineRollPath, using: frameInterpolation)
        let footstepImpulseX = footstepPathXAtRender - microImpulseBaselineX
        let footstepImpulseY = footstepPathYAtRender - microImpulseBaselineY
        let footstepImpulseRoll = footstepPathRollAtRender - microImpulseBaselineRoll
        let rawFootstepXConfidence = footstepFrameConfidence(
            .footstepX,
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepYConfidence = footstepFrameConfidence(
            .footstepY,
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepRollConfidence = footstepFrameConfidence(
            .footstepRoll,
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let cleanedFootstepXAtRender = footstepPathXAtRender - (footstepImpulseX * rawFootstepXConfidence)
        let cleanedFootstepYAtRender = footstepPathYAtRender - (footstepImpulseY * rawFootstepYConfidence)
        let cleanedFootstepRollAtRender = footstepPathRollAtRender - (footstepImpulseRoll * rawFootstepRollConfidence)
        let strideSmoothX = timeWeightedLinearPrediction(
            footstepPathX,
            frames: frames,
            indices: strideActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        ) ??
            timeWeightedAverage(
                footstepPathX,
                frames: frames,
                indices: strideActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: effectiveStrideWobbleWindowSeconds
            )
        let strideSmoothY = timeWeightedLinearPrediction(
            footstepPathY,
            frames: frames,
            indices: strideActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        ) ??
            timeWeightedAverage(
                footstepPathY,
                frames: frames,
                indices: strideActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: effectiveStrideWobbleWindowSeconds
            )
        let strideSmoothRoll = timeWeightedLinearPrediction(
            footstepPathRoll,
            frames: frames,
            indices: strideActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        ) ??
            timeWeightedAverage(
                footstepPathRoll,
                frames: frames,
                indices: strideActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: effectiveStrideWobbleWindowSeconds
            )
        let turnSmoothX = timeWeightedLinearPrediction(
            pathX,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                pathX,
                frames: frames,
                indices: turnActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let turnSmoothY = timeWeightedLinearPrediction(
            pathY,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                pathY,
                frames: frames,
                indices: turnActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let turnSmoothRoll = timeWeightedLinearPrediction(
            pathRoll,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                pathRoll,
                frames: frames,
                indices: turnActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let pathXAtRender = interpolatedValue(analysis.pathX, using: frameInterpolation)
        let pathYAtRender = interpolatedValue(analysis.pathY, using: frameInterpolation)
        let pathRollAtRender = interpolatedValue(analysis.pathRoll, using: frameInterpolation)
        let strideBandX = cleanedFootstepXAtRender - strideSmoothX
        let strideBandY = cleanedFootstepYAtRender - strideSmoothY
        let strideBandRoll = cleanedFootstepRollAtRender - strideSmoothRoll
        let panBandX = pathXAtRender - turnSmoothX
        let panBandY = pathYAtRender - turnSmoothY
        let panBandRoll = pathRollAtRender - turnSmoothRoll
        let strideTrackingConfidence = residualAdjustedTrackingConfidence(
            walkingTrackingConfidence,
            residual: centerResidual,
            multiplier: 0.6,
            qualityModel: analysis.qualityModel
        )
        let rawStrideXConfidence = strideWobbleConfidence(
            bandValue: strideBandX,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScalePixels
        )
        let rawStrideYConfidence = strideWobbleConfidence(
            bandValue: strideBandY,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScalePixels
        )
        let rawStrideRollConfidence = strideWobbleConfidence(
            bandValue: strideBandRoll,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScaleDegrees
        )
        let turnTrackingConfidence = residualAdjustedTrackingConfidence(
            trackingConfidence,
            residual: centerResidual,
            multiplier: 0.9,
            qualityModel: analysis.qualityModel
        )
        let turnBandConfidenceX = turnSmoothingConfidence(
            bandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let turnBandConfidenceY = turnSmoothingConfidence(
            bandValue: panBandY,
            trackingConfidence: turnTrackingConfidence
        )
        let turnBandConfidenceRoll = turnSmoothingRotationConfidence(
            bandValue: panBandRoll,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnershipX = turnOwnershipConfidence(
            values: pathX,
            frames: frames,
            indices: turnActiveIndices,
            turnBandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnershipY = turnOwnershipConfidence(
            values: pathY,
            frames: frames,
            indices: turnActiveIndices,
            turnBandValue: panBandY,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnership = max(turnOwnershipX, turnOwnershipY)
        let coupledTurnOwnershipY = max(turnOwnershipY, turnOwnershipX * 0.70)
        let coupledTurnOwnershipRoll = max(turnOwnership, turnOwnershipX * 0.70)
        let confidenceX = turnBandConfidenceX * turnOwnershipX
        let confidenceY = turnBandConfidenceY * coupledTurnOwnershipY
        let confidenceRoll = turnBandConfidenceRoll * coupledTurnOwnershipRoll
        let confidence = max(confidenceX, confidenceY, confidenceRoll)
        let combinedTurnCorrectionConfidence = turnCorrectionConfidence(
            confidence: confidence,
            turnOwnership: turnOwnership
        )
        let turnCorrectionConfidenceX = turnCorrectionConfidence(
            confidence: confidenceX,
            turnOwnership: turnOwnershipX
        )
        let turnCorrectionConfidenceY = turnCorrectionConfidence(
            confidence: confidenceY,
            turnOwnership: coupledTurnOwnershipY
        )
        let turnCorrectionConfidenceRoll = turnCorrectionConfidence(
            confidence: confidenceRoll,
            turnOwnership: coupledTurnOwnershipRoll
        )
        let turnShakeSuppression = turnStabilizerShakeSuppression(
            turnOwnership: turnOwnership,
            turnConfidence: confidence
        )
        let footstepXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        let footstepYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepYSuppression), min: 0.0, max: 1.0)
        let footstepRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepRollSuppression), min: 0.0, max: 1.0)
        let strideXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
        let strideYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideYSuppression), min: 0.0, max: 1.0)
        let strideRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideRollSuppression), min: 0.0, max: 1.0)
        let footstepXConfidence = rawFootstepXConfidence * footstepXTurnGate
        let footstepYConfidence = rawFootstepYConfidence * footstepYTurnGate
        let footstepRollConfidence = rawFootstepRollConfidence * footstepRollTurnGate
        let strideXConfidence = rawStrideXConfidence * strideXTurnGate
        let strideYConfidence = rawStrideYConfidence * strideYTurnGate
        let strideRollConfidence = rawStrideRollConfidence * strideRollTurnGate
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceX)
        let panCorrectionStrengthY = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceY)
        let panCorrectionStrengthRoll = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceRoll)
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
        let rawMacroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrengthX
        let rawMacroCompensationY = -panBandY * yScale * positionGain * panCorrectionStrengthY
        let rawMacroCompensationRotation = -panBandRoll * rotationGain * panCorrectionStrengthRoll
        let macroCompensationX = softLimit(
            rawMacroCompensationX,
            limit: turnSmoothingOffsetLimit(
                outputPixels: outputSize.x,
                baseFraction: baseTurnSmoothingOffsetLimitX,
                extraFraction: extraTurnSmoothingOffsetLimitX,
                strength: strengths.panStabilizationStrength
            )
        )
        let macroCompensationY = softLimit(
            rawMacroCompensationY,
            limit: turnSmoothingOffsetLimit(
                outputPixels: outputSize.y,
                baseFraction: baseTurnSmoothingOffsetLimitY,
                extraFraction: extraTurnSmoothingOffsetLimitY,
                strength: strengths.panStabilizationStrength
            )
        )
        let macroCompensationRotation = softLimit(
            rawMacroCompensationRotation,
            limit: turnSmoothingRotationLimit(strength: strengths.panStabilizationStrength)
        )
        let rawMicroCompensationX = -footstepImpulseX * xScale * microXCorrectionStrength
        let rawMicroCompensationY = -footstepImpulseY * yScale * microYCorrectionStrength
        let limitedMicroCompensationX = strengths.microJitterX > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepX,
                values: analysis.footstepPathX,
                baselineValues: footstepBaselineXPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationX,
                outputScale: xScale,
                requestedStrength: strengths.microJitterX,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepXTurnGate,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationX, limitedAmount: 0.0)
        let limitedMicroCompensationY = strengths.microJitterY > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepY,
                values: analysis.footstepPathY,
                baselineValues: footstepBaselineYPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationY,
                outputScale: yScale,
                requestedStrength: strengths.microJitterY,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepYTurnGate,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationY, limitedAmount: 0.0)
        let microCompensationX = limitedMicroCompensationX.limitedCorrection
        let microCompensationY = limitedMicroCompensationY.limitedCorrection
        let microCompensationRotation = -footstepImpulseRoll * microRotationCorrectionStrength
        let strideCompensationX = -strideBandX * xScale * strideXCorrectionStrength
        let strideCompensationY = -strideBandY * yScale * strideYCorrectionStrength
        let strideCompensationRotation = -strideBandRoll * strideRotationCorrectionStrength
        let macroPixelOffset = vector_float2(macroCompensationX, macroCompensationY)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let strideWobblePixelOffset = vector_float2(strideCompensationX, strideCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x + strideWobblePixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + strideWobblePixelOffset.y
        let compensationRotation = macroCompensationRotation + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrength = clamp(Float(strengths.farFieldWarp), min: 0.0, max: maximumFarFieldWarpStrength)
        let shouldEstimateFarFieldWarp = farFieldWarpStrength > 0.0
        let appliedWarpConfidence: Float
        let yawPitchProxy: vector_float2
        let shear: vector_float2
        let perspective: vector_float2
        if shouldEstimateFarFieldWarp {
            let farFieldWarpGateIndices = indicesWithinTimeRadius(
                frames,
                centerTime: renderSeconds,
                radiusSeconds: farFieldWarpOuterWindowSeconds * 0.5
            )
            let farFieldWarpActiveIndices = farFieldWarpGateIndices.isEmpty ? [centerIndex] : farFieldWarpGateIndices
            let farFieldWarpTrackingConfidence = stableFarFieldWarpTrackingConfidence(
                analysis: analysis,
                indices: farFieldWarpActiveIndices,
                currentTrackingConfidence: trackingConfidence
            )
            let farFieldWarpEdgeQuality = stableFarFieldWarpEdgeQuality(
                analysis: analysis,
                indices: farFieldWarpActiveIndices,
                currentSearchRadiusHitCount: searchRadiusHitCount,
                currentSearchRadiusTotalCount: searchRadiusTotalCount
            )
            let stableWarpConfidence = stableFarFieldWarpConfidence(
                analysis: analysis,
                indices: farFieldWarpActiveIndices,
                currentWarpConfidence: warpConfidence
            )
            let farFieldWarpGate = farFieldWarpRenderGate(
                warpConfidence: stableWarpConfidence,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )
            let farFieldWarpTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFarFieldWarpSuppression), min: 0.0, max: 1.0)
            appliedWarpConfidence = clamp(stableWarpConfidence * farFieldWarpGate * farFieldWarpTurnGate, min: 0.0, max: 1.0)

            func farFieldBaseline(_ values: [Float], index: Int) -> Float {
                guard values.indices.contains(index),
                      frames.indices.contains(index)
                else {
                    return 0.0
                }
                return outerLinearPrediction(
                    values,
                    frames: frames,
                    centerIndex: index,
                    innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                    outerWindowSeconds: farFieldWarpOuterWindowSeconds
                ) ?? values[index]
            }

            func farFieldBand(_ values: [Float], deadband: Float, limit: Float) -> Float {
                let current = interpolatedValue(values, using: frameInterpolation)
                let lowerBaseline = farFieldBaseline(values, index: frameInterpolation.lowerIndex)
                let upperBaseline = frameInterpolation.upperIndex == frameInterpolation.lowerIndex
                    ? lowerBaseline
                    : farFieldBaseline(values, index: frameInterpolation.upperIndex)
                let baseline = lowerBaseline + ((upperBaseline - lowerBaseline) * frameInterpolation.fraction)
                let scaled = softDeadband(current - baseline, threshold: deadband)
                    * appliedWarpConfidence
                    * farFieldWarpStrength
                return clamp(scaled, min: -limit * farFieldWarpStrength, max: limit * farFieldWarpStrength)
            }

            yawPitchProxy = vector_float2(
                farFieldBand(
                    analysis.pathYaw,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    limit: maxRenderedFarFieldYawPitchProxy
                ),
                farFieldBand(
                    analysis.pathPitch,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    limit: maxRenderedFarFieldYawPitchProxy
                )
            )
            shear = vector_float2(
                farFieldBand(
                    analysis.pathShearX,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    limit: maxRenderedFarFieldShear
                ),
                farFieldBand(
                    analysis.pathShearY,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    limit: maxRenderedFarFieldShear
                )
            )
            perspective = vector_float2(
                farFieldBand(
                    analysis.pathPerspectiveX,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    limit: maxRenderedFarFieldPerspective
                ),
                farFieldBand(
                    analysis.pathPerspectiveY,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    limit: maxRenderedFarFieldPerspective
                )
            )
        } else {
            appliedWarpConfidence = 0.0
            yawPitchProxy = vector_float2(0.0, 0.0)
            shear = vector_float2(0.0, 0.0)
            perspective = vector_float2(0.0, 0.0)
        }

        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: strideWobblePixelOffset,
            footstepJitterRotationDegrees: macroCompensationRotation + microCompensationRotation,
            strideWobbleRotationDegrees: strideCompensationRotation,
            rotationDegrees: compensationRotation,
            turnDetectedPixelOffset: vector_float2(-panBandX * xScale, -panBandY * yScale),
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
            turnConfidence: combinedTurnCorrectionConfidence,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            yawPitchProxy: yawPitchProxy,
            shear: shear,
            perspective: perspective,
            blurAmount: centerBlurAmount,
            trackingConfidence: trackingConfidence,
            walkingTrackingConfidence: walkingTrackingConfidence,
            motionConfidence: motionConfidence,
            residual: centerResidual,
            footstepImpulse: vector_float3(footstepImpulseX, footstepImpulseY, footstepImpulseRoll),
            rawFootstepCorrection: vector_float2(rawMicroCompensationX, rawMicroCompensationY),
            limitedFootstepCorrection: vector_float2(microCompensationX, microCompensationY),
            footstepPulseLimited: vector_float2(limitedMicroCompensationX.limitedAmount, limitedMicroCompensationY.limitedAmount),
            searchRadiusHitCount: searchRadiusHitCount,
            searchRadiusTotalCount: searchRadiusTotalCount
        )
    }

    private static func rawEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache,
        limitFootstepContinuity: Bool = true,
        includeFarFieldWarp: Bool = true
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

        let sampleWidth = frames[centerIndex].sampleWidth
        let sampleHeight = frames[centerIndex].sampleHeight
        let xScale = outputSize.x / Float(max(1, sampleWidth))
        let yScale = outputSize.y / Float(max(1, sampleHeight))
        let turnResidual = cache.residualPercentile(analysis: analysis, indices: activeIndices, percentile: 0.75)
        let strideResidual = cache.residualPercentile(analysis: analysis, indices: strideWobbleActiveIndices, percentile: 0.70)
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
        let turnStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineYPath,
            analysis: analysis,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let turnStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineRollPath,
            analysis: analysis,
            targetIndices: sampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let footstepXTurnGateScales = turnOwnershipGateScales(
            values: turnStrideSmoothedXPath,
            analysis: analysis,
            targetIndices: strideSupportIndices,
            windowSeconds: smoothWindowSeconds,
            cache: cache
        )
        let footstepCleanXPath = confidenceCleanedFootstepPath(
            .footstepX,
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales,
            cache: cache
        )
        let footstepCleanYPath = confidenceCleanedFootstepPath(
            .footstepY,
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let footstepCleanRollPath = confidenceCleanedFootstepPath(
            .footstepRoll,
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
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
        let turnSmoothX = timeWeightedLinearPrediction(
            turnStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedMonotonicSCurveValue(
                turnStrideSmoothedXPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            ) ??
            timeWeightedAverage(
                turnStrideSmoothedXPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let turnSmoothY = timeWeightedLinearPrediction(
            turnStrideSmoothedYPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedMonotonicSCurveValue(
                turnStrideSmoothedYPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            ) ??
            timeWeightedAverage(
                turnStrideSmoothedYPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let turnSmoothRoll = timeWeightedLinearPrediction(
            turnStrideSmoothedRollPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedMonotonicSCurveValue(
                turnStrideSmoothedRollPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            ) ??
            timeWeightedAverage(
                turnStrideSmoothedRollPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
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
        let turnStrideSmoothY = interpolatedValue(turnStrideSmoothedYPath, using: frameInterpolation)
        let turnStrideSmoothRoll = interpolatedValue(turnStrideSmoothedRollPath, using: frameInterpolation)
        let rawFootstepXConfidence = footstepFrameConfidence(
            .footstepX,
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepYConfidence = footstepFrameConfidence(
            .footstepY,
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepRollConfidence = footstepFrameConfidence(
            .footstepRoll,
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            interpolation: frameInterpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let strideBandX = footstepCleanXAtRender - strideSmoothX
        let strideBandY = footstepCleanYAtRender - strideSmoothY
        let strideBandRoll = footstepCleanRollAtRender - strideSmoothRoll
        let panBandX = turnStrideSmoothX - turnSmoothX
        let panBandY = turnStrideSmoothY - turnSmoothY
        let panBandRoll = turnStrideSmoothRoll - turnSmoothRoll
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
        let rawStrideYConfidence = strideWobbleConfidence(
            bandValue: strideBandY,
            trackingConfidence: strideTrackingConfidence,
            fullScale: strideWobbleFullScalePixels
        )
        let rawStrideRollConfidence = strideWobbleConfidence(
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
        let turnBandConfidenceX = turnSmoothingConfidence(
            bandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let turnBandConfidenceY = turnSmoothingConfidence(
            bandValue: panBandY,
            trackingConfidence: turnTrackingConfidence
        )
        let turnBandConfidenceRoll = turnSmoothingRotationConfidence(
            bandValue: panBandRoll,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnershipX = turnOwnershipConfidence(
            values: turnStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            turnBandValue: panBandX,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnershipY = turnOwnershipConfidence(
            values: turnStrideSmoothedYPath,
            frames: frames,
            indices: activeIndices,
            turnBandValue: panBandY,
            trackingConfidence: turnTrackingConfidence
        )
        let turnOwnership = max(turnOwnershipX, turnOwnershipY)
        let coupledTurnOwnershipY = max(turnOwnershipY, turnOwnershipX * 0.70)
        let coupledTurnOwnershipRoll = max(turnOwnership, turnOwnershipX * 0.70)
        let confidenceX = turnBandConfidenceX * turnOwnershipX
        let confidenceY = turnBandConfidenceY * coupledTurnOwnershipY
        let confidenceRoll = turnBandConfidenceRoll * coupledTurnOwnershipRoll
        let confidence = max(confidenceX, confidenceY, confidenceRoll)
        let combinedTurnCorrectionConfidence = turnCorrectionConfidence(
            confidence: confidence,
            turnOwnership: turnOwnership
        )
        let turnCorrectionConfidenceX = turnCorrectionConfidence(
            confidence: confidenceX,
            turnOwnership: turnOwnershipX
        )
        let turnCorrectionConfidenceY = turnCorrectionConfidence(
            confidence: confidenceY,
            turnOwnership: coupledTurnOwnershipY
        )
        let turnCorrectionConfidenceRoll = turnCorrectionConfidence(
            confidence: confidenceRoll,
            turnOwnership: coupledTurnOwnershipRoll
        )
        let rawTurnShakeSuppression = turnStabilizerShakeSuppression(
            turnOwnership: turnOwnership,
            turnConfidence: confidence
        )
        let turnShakeSuppression = smoothedTurnShakeSuppression(
            rawSuppression: rawTurnShakeSuppression,
            gateScales: footstepXTurnGateScales,
            frames: frames,
            centerTime: renderSeconds
        )
        let footstepImpulseX = footstepPathXAtRender - microImpulseBaselineX
        let baseFootstepXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        let baseStrideXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
        let footstepXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawFootstepXConfidence,
            bandMagnitude: abs(footstepImpulseX),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX
        )
        let strideXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawStrideXConfidence,
            bandMagnitude: abs(strideBandX),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX
        ) * turnOwnedStrideXGateFloorScale
        let footstepXTurnGate = max(baseFootstepXTurnGate, footstepXTurnGateFloor)
        let footstepYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepYSuppression), min: 0.0, max: 1.0)
        let footstepRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepRollSuppression), min: 0.0, max: 1.0)
        let strideXTurnGate = max(baseStrideXTurnGate, strideXTurnGateFloor)
        let strideYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideYSuppression), min: 0.0, max: 1.0)
        let strideRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideRollSuppression), min: 0.0, max: 1.0)
        let footstepXConfidence = rawFootstepXConfidence * footstepXTurnGate
        let footstepYConfidence = rawFootstepYConfidence * footstepYTurnGate
        let footstepRollConfidence = rawFootstepRollConfidence * footstepRollTurnGate
        let strideXConfidence = rawStrideXConfidence * strideXTurnGate
        let strideYConfidence = rawStrideYConfidence * strideYTurnGate
        let strideRollConfidence = rawStrideRollConfidence * strideRollTurnGate
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceX)
        let panCorrectionStrengthY = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceY)
        let panCorrectionStrengthRoll = confidenceCompensatedCorrectionFactor(strengths.panStabilizationStrength, confidence: turnCorrectionConfidenceRoll)
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
        let rawMacroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrengthX
        let rawMacroCompensationY = -panBandY * yScale * positionGain * panCorrectionStrengthY
        let rawMacroCompensationRotation = -panBandRoll * rotationGain * panCorrectionStrengthRoll
        let detectedTurnPixelOffset = vector_float2(-panBandX * xScale, -panBandY * yScale)
        let macroCompensationX = softLimit(
            rawMacroCompensationX,
            limit: turnSmoothingOffsetLimit(
                outputPixels: outputSize.x,
                baseFraction: baseTurnSmoothingOffsetLimitX,
                extraFraction: extraTurnSmoothingOffsetLimitX,
                strength: strengths.panStabilizationStrength
            )
        )
        let macroCompensationY = softLimit(
            rawMacroCompensationY,
            limit: turnSmoothingOffsetLimit(
                outputPixels: outputSize.y,
                baseFraction: baseTurnSmoothingOffsetLimitY,
                extraFraction: extraTurnSmoothingOffsetLimitY,
                strength: strengths.panStabilizationStrength
            )
        )
        let macroCompensationRotation = softLimit(
            rawMacroCompensationRotation,
            limit: turnSmoothingRotationLimit(strength: strengths.panStabilizationStrength)
        )
        let rawMicroCompensationX = -footstepImpulseX * xScale * microXCorrectionStrength
        let rawMicroCompensationY = -(footstepPathYAtRender - footstepBaselineY) * yScale * microYCorrectionStrength
        let limitedMicroCompensationX = limitFootstepContinuity && strengths.microJitterX > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepX,
                values: analysis.footstepPathX,
                baselineValues: footstepBaselineXPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationX,
                outputScale: xScale,
                requestedStrength: strengths.microJitterX,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepXTurnGate,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationX, limitedAmount: 0.0)
        let limitedMicroCompensationY = limitFootstepContinuity && strengths.microJitterY > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepY,
                values: analysis.footstepPathY,
                baselineValues: footstepBaselineYPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroCompensationY,
                outputScale: yScale,
                requestedStrength: strengths.microJitterY,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepYTurnGate,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationY, limitedAmount: 0.0)
        let microCompensationX = limitedMicroCompensationX.limitedCorrection
        let microCompensationY = limitedMicroCompensationY.limitedCorrection
        let microCompensationRotation = -(footstepPathRollAtRender - microImpulseBaselineRoll) * microRotationCorrectionStrength
        let footstepImpulse = vector_float3(
            footstepImpulseX,
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
        let compensationRotation = macroCompensationRotation + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrength = clamp(Float(strengths.farFieldWarp), min: 0.0, max: maximumFarFieldWarpStrength)
        let shouldEstimateFarFieldWarp = includeFarFieldWarp && farFieldWarpStrength > 0.0
        let appliedWarpConfidence: Float
        let yawPitchProxy: vector_float2
        let shear: vector_float2
        let perspective: vector_float2
        if shouldEstimateFarFieldWarp {
            let farFieldWarpGateWindowIndices = indicesWithinTimeRadius(
                frames,
                centerTime: renderSeconds,
                radiusSeconds: farFieldWarpOuterWindowSeconds * 0.5
            )
            let farFieldWarpGateActiveIndices = farFieldWarpGateWindowIndices.isEmpty ? [centerIndex] : farFieldWarpGateWindowIndices
            let farFieldWarpSampledIndices = uniqueSortedIndices(
                farFieldWarpGateActiveIndices + [centerIndex] + frameInterpolation.indices,
                validCount: frames.count
            )
            let farFieldBaselineYawPath = cachedOuterLinearPredictionPath(
                .yaw,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
            let farFieldBaselinePitchPath = cachedOuterLinearPredictionPath(
                .pitch,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
            let farFieldBaselineShearXPath = cachedOuterLinearPredictionPath(
                .shearX,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
            let farFieldBaselineShearYPath = cachedOuterLinearPredictionPath(
                .shearY,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
            let farFieldBaselinePerspectiveXPath = cachedOuterLinearPredictionPath(
                .perspectiveX,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
            let farFieldBaselinePerspectiveYPath = cachedOuterLinearPredictionPath(
                .perspectiveY,
                analysis: analysis,
                indices: farFieldWarpSampledIndices,
                innerWindowSeconds: farFieldWarpInnerWindowSeconds,
                outerWindowSeconds: farFieldWarpOuterWindowSeconds,
                cache: cache
            )
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
            let stableWarpConfidence = stableFarFieldWarpConfidence(
                analysis: analysis,
                indices: farFieldWarpGateActiveIndices,
                currentWarpConfidence: warpConfidence
            )
            let farFieldWarpGate = farFieldWarpRenderGate(
                warpConfidence: stableWarpConfidence,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )
            let farFieldWarpTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFarFieldWarpSuppression), min: 0.0, max: 1.0)
            appliedWarpConfidence = clamp(stableWarpConfidence * farFieldWarpGate * farFieldWarpTurnGate, min: 0.0, max: 1.0)
            yawPitchProxy = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathYaw,
                    baselineValues: farFieldBaselineYawPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldYawPitchProxy
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPitch,
                    baselineValues: farFieldBaselinePitchPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldYawPitchProxy
                )
            )
            shear = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathShearX,
                    baselineValues: farFieldBaselineShearXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldShear
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathShearY,
                    baselineValues: farFieldBaselineShearYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldShear
                )
            )
            perspective = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPerspectiveX,
                    baselineValues: farFieldBaselinePerspectiveXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldPerspective
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPerspectiveY,
                    baselineValues: farFieldBaselinePerspectiveYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * 0.08,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrength,
                    limit: maxRenderedFarFieldPerspective
                )
            )
        } else {
            appliedWarpConfidence = 0.0
            yawPitchProxy = vector_float2(0.0, 0.0)
            shear = vector_float2(0.0, 0.0)
            perspective = vector_float2(0.0, 0.0)
        }
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: strideWobblePixelOffset,
            footstepJitterRotationDegrees: macroCompensationRotation + microCompensationRotation,
            strideWobbleRotationDegrees: strideCompensationRotation,
            rotationDegrees: compensationRotation,
            turnDetectedPixelOffset: detectedTurnPixelOffset,
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
            turnConfidence: combinedTurnCorrectionConfidence,
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
        let rawCenterTransform = interpolatedRawTransform(
            analysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache,
            limitFootstepContinuity: true,
            includeFarFieldWarp: true
        )
        let sampleCount = max(3, renderTemporalSmoothingSampleCount)
        let centerSample = sampleCount / 2
        let halfWindow = renderTemporalSmoothingWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = renderTemporalSmoothingWindowSeconds / denominator
        let sigma = max(1e-6, halfWindow * 0.5)
        let farFieldWarpHalfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        var weightedSamples: [(transform: StabilizerAutoTransform, weight: Float, offsetSeconds: Double)] = []
        weightedSamples.reserveCapacity(sampleCount + (renderFrameLocalSmoothingRadiusFrames * 2))
        let centerFrameIndex = frameLookup(at: renderSeconds, in: frames).centerIndex

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
                let includeFarFieldWarp = abs(offset) <= farFieldWarpHalfWindow + 1e-9
                transform = interpolatedRawTransform(
                    analysis: analysis,
                    renderSeconds: sampleSeconds,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: strengths,
                    cache: renderEstimateCache,
                    limitFootstepContinuity: false,
                    includeFarFieldWarp: includeFarFieldWarp
                )
            }
            weightedSamples.append((transform: transform, weight: weight, offsetSeconds: offset))
        }
        let frameStepSeconds = localFrameStepSeconds(frames: frames, centerIndex: centerFrameIndex)
        let duplicateOffsetTolerance = max(0.0005, frameStepSeconds * 0.25)
        if frameStepSeconds > 0.0 {
            for offsetFrame in (-renderFrameLocalSmoothingRadiusFrames)...renderFrameLocalSmoothingRadiusFrames where offsetFrame != 0 {
                let offset = Double(offsetFrame) * frameStepSeconds
                let sampleSeconds = renderSeconds + offset
                guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                    continue
                }
                if weightedSamples.contains(where: { abs($0.offsetSeconds - offset) <= duplicateOffsetTolerance }) {
                    continue
                }
                let sampleFrameIndex = frameLookup(at: sampleSeconds, in: frames).centerIndex
                guard sampleFrameIndex != centerFrameIndex else {
                    continue
                }
                let includeFarFieldWarp = abs(offset) <= farFieldWarpHalfWindow + 1e-9
                let transform = interpolatedRawTransform(
                    analysis: analysis,
                    renderSeconds: sampleSeconds,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: strengths,
                    cache: renderEstimateCache,
                    limitFootstepContinuity: false,
                    includeFarFieldWarp: includeFarFieldWarp
                )
                let distanceWeight = Float(max(1, abs(offsetFrame)))
                let weight = renderFrameLocalSmoothingBaseWeight / distanceWeight
                weightedSamples.append((transform: transform, weight: weight, offsetSeconds: offset))
            }
        }

        guard !weightedSamples.isEmpty else {
            return rawCenterTransform
        }
        let broadTransformSamples = weightedSamples.map { sample in
            (transform: sample.transform, weight: sample.weight)
        }
        var smoothedTransform = weightedAverageTransform(broadTransformSamples)
        let turnTransitionSamples = turnTransitionSmoothingSamples(
            centerTransform: rawCenterTransform,
            analysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache
        )
        if !turnTransitionSamples.isEmpty {
            let smoothedTurnTransform = weightedAverageTransform(turnTransitionSamples)
            var bridgedMacroOffset = smoothedTurnTransform.macroPixelOffset
            let centerMacroX = rawCenterTransform.macroPixelOffset.x
            let bridgedMacroX = bridgedMacroOffset.x
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(rawCenterTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70) * 0.85
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: rawCenterTransform,
                bridgeMacroX: bridgedMacroOffset.x
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: rawCenterTransform,
                bridgeTransform: smoothedTurnTransform
            )
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
            smoothedTransform.macroPixelOffset.x = turnTransitionDetectedCappedMacroX(
                centerTransform: rawCenterTransform,
                proposedMacroX: smoothedTransform.macroPixelOffset.x
            )
            smoothedTransform.turnConfidence = smoothedTurnTransform.turnConfidence
        }
        let shortWarpSamples = farFieldWarpSmoothingSamples(
            centerTransform: rawCenterTransform,
            analysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache
        )
        let smoothedWarpTransform = shortWarpSamples.isEmpty
            ? rawCenterTransform
            : weightedAverageTransform(shortWarpSamples)
        let smoothedWarpConfidence = clamp(smoothedWarpTransform.warpConfidence, min: 0.0, max: 1.0)
        let temporalWarpScale = farFieldWarpTemporalScale(
            centerTransform: rawCenterTransform,
            smoothedTransform: smoothedWarpTransform,
            smoothedConfidence: smoothedWarpConfidence
        )
        smoothedTransform.warpConfidence = smoothedWarpConfidence * temporalWarpScale
        smoothedTransform.yawPitchProxy = smoothedWarpTransform.yawPitchProxy * temporalWarpScale
        smoothedTransform.shear = smoothedWarpTransform.shear * temporalWarpScale
        smoothedTransform.perspective = smoothedWarpTransform.perspective * temporalWarpScale
        smoothedTransform.trackingConfidence = clamp(smoothedTransform.trackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.walkingTrackingConfidence = clamp(smoothedTransform.walkingTrackingConfidence, min: 0.0, max: 1.0)
        smoothedTransform.motionConfidence = clamp(smoothedTransform.motionConfidence, min: 0.0, max: 1.0)
        smoothedTransform.residual = rawCenterTransform.residual
        smoothedTransform.searchRadiusHitCount = rawCenterTransform.searchRadiusHitCount
        smoothedTransform.searchRadiusTotalCount = rawCenterTransform.searchRadiusTotalCount
        let smoothedFootstepJitter = smoothedFootstepJitter(
            centerTransform: rawCenterTransform,
            analysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            cache: renderEstimateCache
        )
        // Footstep Jitter is frame-local; broad temporal smoothing is only for TURN/SWOB.
        smoothedTransform.microPixelOffset = smoothedFootstepJitter.microPixelOffset
        smoothedTransform.footstepJitterRotationDegrees = smoothedFootstepJitter.rotationDegrees
        smoothedTransform.effectiveMicroJitterStrength = rawCenterTransform.effectiveMicroJitterStrength
        smoothedTransform.microConfidence = rawCenterTransform.microConfidence
        smoothedTransform.footstepImpulse = rawCenterTransform.footstepImpulse
        smoothedTransform.rawFootstepCorrection = rawCenterTransform.rawFootstepCorrection
        smoothedTransform.limitedFootstepCorrection = smoothedFootstepJitter.microPixelOffset
        smoothedTransform.footstepPulseLimited = rawCenterTransform.footstepPulseLimited
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

    private static func interpolatedRawTransform(
        analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache,
        limitFootstepContinuity: Bool,
        includeFarFieldWarp: Bool
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return .identity
        }
        let interpolation = frameLookup(at: renderSeconds, in: frames).interpolation
        guard frames.indices.contains(interpolation.lowerIndex) else {
            return .identity
        }
        let lowerTransform = cache.rawTransform(
            analysis: analysis,
            index: interpolation.lowerIndex,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            limitFootstepContinuity: limitFootstepContinuity,
            includeFarFieldWarp: includeFarFieldWarp
        )
        guard interpolation.upperIndex != interpolation.lowerIndex,
              interpolation.fraction > 0.0001,
              frames.indices.contains(interpolation.upperIndex)
        else {
            return lowerTransform
        }
        let upperTransform = cache.rawTransform(
            analysis: analysis,
            index: interpolation.upperIndex,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            limitFootstepContinuity: limitFootstepContinuity,
            includeFarFieldWarp: includeFarFieldWarp
        )
        let upperWeight = clamp(interpolation.fraction, min: 0.0, max: 1.0)
        let lowerWeight = 1.0 - upperWeight
        return weightedAverageTransform([
            (transform: lowerTransform, weight: lowerWeight),
            (transform: upperTransform, weight: upperWeight)
        ])
    }

    private static func farFieldWarpTemporalScale(
        centerTransform: StabilizerAutoTransform,
        smoothedTransform: StabilizerAutoTransform,
        smoothedConfidence: Float
    ) -> Float {
        let boundedSmoothedConfidence = clamp(smoothedConfidence, min: 0.0, max: 1.0)
        guard boundedSmoothedConfidence > Float.ulpOfOne else {
            return 0.0
        }
        let centerConfidence = clamp(centerTransform.warpConfidence, min: 0.0, max: 1.0)
        let centerSupport = confidenceRamp(centerConfidence, start: 0.02, full: 0.20)
        let smoothedSupport = confidenceRamp(boundedSmoothedConfidence, start: 0.06, full: 0.28)
        let centerVector = vector_float4(
            centerTransform.yawPitchProxy.x + centerTransform.perspective.x,
            centerTransform.yawPitchProxy.y + centerTransform.perspective.y,
            centerTransform.shear.x,
            centerTransform.shear.y
        )
        let smoothedVector = vector_float4(
            smoothedTransform.yawPitchProxy.x + smoothedTransform.perspective.x,
            smoothedTransform.yawPitchProxy.y + smoothedTransform.perspective.y,
            smoothedTransform.shear.x,
            smoothedTransform.shear.y
        )
        let centerMagnitude = simd_length(centerVector)
        let smoothedMagnitude = simd_length(smoothedVector)
        let directionSupport: Float
        if centerMagnitude > 1e-7, smoothedMagnitude > 1e-7 {
            let cosine = simd_dot(centerVector, smoothedVector) / max(centerMagnitude * smoothedMagnitude, 1e-7)
            directionSupport = clamp((cosine + 1.0) * 0.5, min: 0.0, max: 1.0)
        } else {
            directionSupport = 0.65
        }
        return clamp(max(centerSupport, smoothedSupport * max(0.55, directionSupport)), min: 0.0, max: 1.0)
    }

    private static func turnTransitionSmoothingSamples(
        centerTransform: StabilizerAutoTransform,
        analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        let frames = analysis.frames
        guard let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return [(centerTransform, 1.0)]
        }
        let sampleCount = max(3, renderTurnTransitionSmoothingSampleCount)
        let centerSample = sampleCount / 2
        let halfWindow = renderTurnTransitionSmoothingWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = renderTurnTransitionSmoothingWindowSeconds / denominator
        let sigma = max(1e-6, halfWindow * 0.55)
        var rawSamples: [(transform: StabilizerAutoTransform, timeWeight: Float, isCenter: Bool)] = [(centerTransform, 1.0, true)]
        rawSamples.reserveCapacity(sampleCount)
        for sampleIndex in 0..<sampleCount {
            guard sampleIndex != centerSample else {
                continue
            }
            let offset = Double(sampleIndex - centerSample) * sampleStep
            let sampleSeconds = renderSeconds + offset
            guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let transform = interpolatedRawTransform(
                analysis: analysis,
                renderSeconds: sampleSeconds,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                cache: cache,
                limitFootstepContinuity: false,
                includeFarFieldWarp: false
            )
            rawSamples.append((transform: transform, timeWeight: weight, isCenter: false))
        }

        var supportMagnitude = Float(0.0)
        var signedSupport = Float(0.0)
        var signedSupportWeight = Float(0.0)
        for sample in rawSamples {
            let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
            let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
            let evidenceWeight = sample.timeWeight * turnResponse * qualitySupport
            guard evidenceWeight > 0.0001 else {
                continue
            }
            let macroX = sample.transform.macroPixelOffset.x
            supportMagnitude = max(supportMagnitude, abs(macroX))
            signedSupport += macroX * evidenceWeight
            signedSupportWeight += evidenceWeight
        }
        guard supportMagnitude >= renderTurnTransitionMinimumMacroPixels else {
            return [(centerTransform, 1.0)]
        }
        guard signedSupportWeight > 0.0001 else {
            return [(centerTransform, 1.0)]
        }
        let dominantSign: Float = signedSupport >= 0.0 ? 1.0 : -1.0
        let samples = rawSamples.compactMap { sample -> (transform: StabilizerAutoTransform, weight: Float)? in
            let macroX = sample.transform.macroPixelOffset.x
            let macroMagnitude = abs(macroX)
            let turnResponse = turnCorrectionConfidenceResponse(sample.transform.turnConfidence)
            let qualitySupport = turnTransitionBridgeQualitySupport(sample.transform)
            let evidenceWeight = turnResponse * qualitySupport
            let magnitudeSupport = confidenceRamp(
                macroMagnitude,
                start: supportMagnitude * 0.10,
                full: max(supportMagnitude * 0.45, renderTurnTransitionMinimumMacroPixels)
            )
            let directionSupport: Float
            if macroMagnitude < renderTurnTransitionMinimumMacroPixels {
                directionSupport = sample.isCenter ? 0.25 : 0.10
            } else {
                directionSupport = (macroX * dominantSign) >= 0.0 ? 1.0 : 0.15
            }
            let centerScale: Float = sample.isCenter
                ? 0.25 + (turnCorrectionConfidenceResponse(sample.transform.turnConfidence) * 0.75)
                : 1.0
            let weight = sample.timeWeight
                * evidenceWeight
                * max(0.15, magnitudeSupport)
                * directionSupport
                * centerScale
            guard weight > 0.0001 else {
                return nil
            }
            return (transform: sample.transform, weight: weight)
        }
        guard !samples.isEmpty else {
            return [(centerTransform, 1.0)]
        }
        return samples
    }

    private static func turnTransitionBridgeBlend(
        centerTransform: StabilizerAutoTransform,
        bridgeTransform: StabilizerAutoTransform
    ) -> Float {
        let centerEdgeQuality = searchRadiusEdgeQuality(
            hitCount: centerTransform.searchRadiusHitCount,
            totalCount: centerTransform.searchRadiusTotalCount
        )
        let centerEdgeSupport = turnTransitionBridgeEdgeSupport(edgeQuality: centerEdgeQuality)
        let centerTrackingQualitySupport = turnTransitionBridgeQualitySupport(centerTransform)
        let centerTurnResponse = turnCorrectionConfidenceResponse(centerTransform.turnConfidence)
        let bridgeTurnResponse = turnCorrectionConfidenceResponse(bridgeTransform.turnConfidence)
        let centerTurnSupport = centerTurnResponse * centerEdgeSupport
        let bridgeTurnSupport = bridgeTurnResponse * centerTrackingQualitySupport
        let evidenceSupport = max(centerTurnSupport, bridgeTurnSupport)
        let gatedBlend = clamp(
            renderTurnTransitionBridgeMinimumBlend
                + ((renderTurnTransitionBridgeMaximumBlend - renderTurnTransitionBridgeMinimumBlend) * evidenceSupport),
            min: renderTurnTransitionBridgeMinimumBlend,
            max: renderTurnTransitionBridgeMaximumBlend
        )
        let lowEdgeLargeTurnBlend = renderTurnTransitionBridgeLowEdgeLargeTurnBlend
            * bridgeTurnResponse
            * confidenceRamp(
                abs(bridgeTransform.macroPixelOffset.x),
                start: renderTurnTransitionBridgeLowEdgeMacroStartPixels,
                full: renderTurnTransitionBridgeLowEdgeMacroFullPixels
            )
        return clamp(
            max(gatedBlend, lowEdgeLargeTurnBlend),
            min: renderTurnTransitionBridgeMinimumBlend,
            max: renderTurnTransitionBridgeMaximumBlend
        )
    }

    private static func turnTransitionBridgeQualitySupport(_ transform: StabilizerAutoTransform) -> Float {
        let trackingSupport = confidenceRamp(
            clamp(transform.trackingConfidence, min: 0.0, max: 1.0),
            start: 0.12,
            full: 0.52
        )
        let walkingSupport = confidenceRamp(
            clamp(transform.walkingTrackingConfidence, min: 0.0, max: 1.0),
            start: 0.12,
            full: 0.52
        ) * 0.85
        let edgeQuality = searchRadiusEdgeQuality(
            hitCount: transform.searchRadiusHitCount,
            totalCount: transform.searchRadiusTotalCount
        )
        let edgeSupport = turnTransitionBridgeEdgeSupport(edgeQuality: edgeQuality)
        return min(max(trackingSupport, walkingSupport), edgeSupport)
    }

    private static func turnTransitionBridgeEdgeSupport(edgeQuality: Float) -> Float {
        confidenceRamp(
            clamp(edgeQuality, min: 0.0, max: 1.0),
            start: renderTurnTransitionBridgeEdgeGateStart,
            full: renderTurnTransitionBridgeEdgeGateFull
        )
    }

    private static func turnTransitionCenterAnchoredBridgeMacroX(
        centerTransform: StabilizerAutoTransform,
        bridgeMacroX: Float
    ) -> Float {
        let centerMacroX = centerTransform.macroPixelOffset.x
        guard abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
              abs(bridgeMacroX) > abs(centerMacroX),
              (centerMacroX * bridgeMacroX) > 0.0
        else {
            return bridgeMacroX
        }
        let centerReliability = turnCorrectionConfidenceResponse(centerTransform.turnConfidence)
            * turnTransitionBridgeQualitySupport(centerTransform)
        let anchor = confidenceRamp(centerReliability, start: 0.18, full: 0.45)
        return bridgeMacroX + ((centerMacroX - bridgeMacroX) * anchor)
    }

    private static func turnTransitionDetectedCappedMacroX(
        centerTransform: StabilizerAutoTransform,
        proposedMacroX: Float
    ) -> Float {
        let detectedMacroX = centerTransform.turnDetectedPixelOffset.x
        let detectedMagnitude = abs(detectedMacroX)
        let allowedMagnitude = detectedMagnitude + renderTurnTransitionDetectedCapAllowancePixels
        guard detectedMagnitude >= renderTurnTransitionDetectedCapStartPixels,
              abs(proposedMacroX) > allowedMagnitude,
              (detectedMacroX * proposedMacroX) > 0.0
        else {
            return proposedMacroX
        }
        let detectedSign: Float = detectedMacroX >= 0.0 ? 1.0 : -1.0
        return detectedSign * allowedMagnitude
    }

    private static func farFieldWarpSmoothingSamples(
        centerTransform: StabilizerAutoTransform,
        analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        let frames = analysis.frames
        let halfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        let sigma = max(1e-6, halfWindow * 0.55)
        let candidateIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: halfWindow
        )
        var smoothedSamples: [(transform: StabilizerAutoTransform, weight: Float)] = [(centerTransform, 1.0)]
        smoothedSamples.reserveCapacity(candidateIndices.count + 1)
        for index in candidateIndices where frames.indices.contains(index) {
            let offset = frames[index].time - renderSeconds
            if abs(offset) <= timeWindowSelectionEpsilon {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            if weight <= 0.0001 {
                continue
            }
            let transform = interpolatedRawTransform(
                analysis: analysis,
                renderSeconds: frames[index].time,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                cache: cache,
                limitFootstepContinuity: false,
                includeFarFieldWarp: true
            )
            smoothedSamples.append((transform: transform, weight: weight))
        }
        return smoothedSamples
    }

    private static func smoothedFootstepJitter(
        centerTransform: StabilizerAutoTransform,
        analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        cache: RenderEstimateCache
    ) -> (microPixelOffset: vector_float2, rotationDegrees: Float) {
        let frames = analysis.frames
        let halfWindow = renderFootstepJitterSmoothingWindowSeconds * 0.5
        let sigma = max(1e-6, halfWindow * 0.55)
        let candidateIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: halfWindow
        )
        var xSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        var ySamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        var rollSamples: [(value: Float, confidence: Float, timeWeight: Float)] = []
        xSamples.reserveCapacity(candidateIndices.count)
        ySamples.reserveCapacity(candidateIndices.count)
        rollSamples.reserveCapacity(candidateIndices.count)

        for index in candidateIndices where frames.indices.contains(index) {
            let offset = frames[index].time - renderSeconds
            if abs(offset) <= timeWindowSelectionEpsilon {
                continue
            }
            let normalizedDistance = offset / sigma
            let timeWeight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            if timeWeight <= 0.0001 {
                continue
            }
            let transform = interpolatedRawTransform(
                analysis: analysis,
                renderSeconds: frames[index].time,
                outputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths,
                cache: cache,
                limitFootstepContinuity: true,
                includeFarFieldWarp: false
            )
            xSamples.append((transform.microPixelOffset.x, transform.effectiveMicroJitterStrength.x, timeWeight))
            ySamples.append((transform.microPixelOffset.y, transform.effectiveMicroJitterStrength.y, timeWeight))
            rollSamples.append((transform.footstepJitterRotationDegrees, transform.effectiveMicroJitterStrength.z, timeWeight))
        }

        return (
            microPixelOffset: vector_float2(
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.x,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.x,
                    samples: xSamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                ),
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.y,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                    samples: ySamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                )
            ),
            rotationDegrees: smoothedFootstepScalar(
                centerValue: centerTransform.footstepJitterRotationDegrees,
                centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                samples: rollSamples,
                similarityScale: renderFootstepJitterSmoothingRotationSimilarity
            )
        )
    }

    private static func smoothedFootstepScalar(
        centerValue: Float,
        centerConfidence: Float,
        samples: [(value: Float, confidence: Float, timeWeight: Float)],
        similarityScale: Float
    ) -> Float {
        guard centerValue.isFinite,
              abs(centerValue) > Float.ulpOfOne,
              similarityScale.isFinite,
              similarityScale > Float.ulpOfOne
        else {
            return centerValue
        }
        let boundedCenterConfidence = clamp(centerConfidence, min: 0.0, max: 1.0)
        guard boundedCenterConfidence > 0.02 else {
            return centerValue
        }

        let centerWeight: Float = 0.55
        let centerMagnitude = abs(centerValue)
        var weightedTotal = centerValue * centerWeight
        var totalWeight = centerWeight
        var neighborWeight: Float = 0.0
        for sample in samples {
            guard sample.value.isFinite,
                  sample.timeWeight.isFinite,
                  sample.confidence.isFinite,
                  sample.timeWeight > 0.0,
                  sample.confidence > 0.0,
                  sample.value * centerValue > 0.0
            else {
                continue
            }
            let sampleMagnitude = abs(sample.value)
            let magnitudeSupport = confidenceRamp(
                sampleMagnitude,
                start: centerMagnitude * 0.15,
                full: max(centerMagnitude * 0.65, Float.ulpOfOne)
            )
            let difference = abs(sample.value - centerValue)
            let similarity = 1.0 - confidenceRamp(
                difference,
                start: similarityScale * 0.35,
                full: max(similarityScale, centerMagnitude * 0.9)
            )
            let weight = sample.timeWeight
                * clamp(sample.confidence, min: 0.0, max: 1.0)
                * magnitudeSupport
                * similarity
            guard weight > 0.0001 else {
                continue
            }
            weightedTotal += sample.value * weight
            totalWeight += weight
            neighborWeight += weight
        }
        guard neighborWeight > 0.05, totalWeight > Float.ulpOfOne else {
            return centerValue
        }

        let localAverage = weightedTotal / totalWeight
        let support = clamp(neighborWeight / totalWeight, min: 0.0, max: 1.0)
        let blend = renderFootstepJitterSmoothingMaxBlend
            * support
            * max(0.35, boundedCenterConfidence)
        return centerValue + ((localAverage - centerValue) * blend)
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
        var turnDetectedPixelOffset = vector_float2(0.0, 0.0)
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
            turnDetectedPixelOffset += transform.turnDetectedPixelOffset * weight
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
            turnDetectedPixelOffset: turnDetectedPixelOffset / totalWeight,
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
        let farFieldPlane = farFieldPlaneMotion(
            shifts: motionBlocksForModel,
            seedDx: robustDx,
            seedDy: robustDy,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let farFieldAuthority = farFieldPlane?.authority ?? 0.0
        let modelDx = farFieldPlane.map {
            robustDx + (($0.dx - robustDx) * farFieldAuthority)
        } ?? robustDx
        let modelDy = farFieldPlane.map {
            robustDy + (($0.dy - robustDy) * farFieldAuthority)
        } ?? robustDy
        let rollCandidates = motionBlocksForModel.compactMap { shift -> Float? in
            let x = shift.block.centerX - (Float(sampleWidth) * 0.5)
            let y = shift.block.centerY - (Float(sampleHeight) * 0.5)
            let denominator = (x * x) + (y * y)
            guard denominator > 1.0 else {
                return nil
            }
            let u = shift.dx - modelDx
            let v = shift.dy - modelDy
            return ((x * v) - (y * u)) / denominator
        }
        let broadSignedRoll = median(rollCandidates) ?? 0.0
        let signedRoll = farFieldPlane.map {
            broadSignedRoll + (($0.signedRoll - broadSignedRoll) * farFieldAuthority)
        } ?? broadSignedRoll
        let rollMotion = rollCandidates.map { abs($0) }.max() ?? 0.0
        let acceptedCount = acceptedBlocks.count >= minimumAcceptedMotionBlocks ? acceptedBlocks.count : 0
        let farFieldAgreement = motionBlocksForModel.isEmpty ? 0.0 : average(motionBlocksForModel.map(\.block.farFieldWeight))
        let blockAgreement = blocks.isEmpty ? 0.0 : (Float(acceptedCount) / Float(blocks.count)) * clamp(farFieldAgreement, min: 0.35, max: 1.0)
        let scoreConfidence = clamp(1.0 - ((median(motionBlocksForModel.map(\.score)) ?? global.score) * 1.8), min: 0.0, max: 1.0)
        let analysisConfidence = clamp(max(blockAgreement * scoreConfidence, farFieldAuthority * scoreConfidence), min: 0.0, max: 1.0)
        let searchRadiusHitCount = (global.searchRadiusHit ? 1 : 0) + blockShifts.filter(\.searchRadiusHit).count
        let searchRadiusTotalCount = 1 + blockShifts.count
        let warpMotion = farFieldWarpMotion(
            shifts: motionBlocksForModel,
            robustDx: modelDx,
            robustDy: modelDy,
            signedRoll: signedRoll,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            analysisConfidence: analysisConfidence
        )
        let modelYawProxy = farFieldPlane.map {
            warpMotion.yawProxy + (($0.yawProxy - warpMotion.yawProxy) * farFieldAuthority)
        } ?? warpMotion.yawProxy
        let modelPitchProxy = farFieldPlane.map {
            warpMotion.pitchProxy + (($0.pitchProxy - warpMotion.pitchProxy) * farFieldAuthority)
        } ?? warpMotion.pitchProxy
        let modelShearX = farFieldPlane.map {
            warpMotion.shearX + (($0.shearX - warpMotion.shearX) * farFieldAuthority)
        } ?? warpMotion.shearX
        let modelShearY = farFieldPlane.map {
            warpMotion.shearY + (($0.shearY - warpMotion.shearY) * farFieldAuthority)
        } ?? warpMotion.shearY

        return PairMotionResult(
            motion: PairMotion(
                dx: modelDx,
                dy: modelDy,
                residual: median(motionBlocksForModel.map(\.score)) ?? global.score,
                signedRoll: signedRoll,
                rollMotion: rollMotion,
                yawProxy: modelYawProxy,
                pitchProxy: modelPitchProxy,
                shearX: modelShearX,
                shearY: modelShearY,
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
        let columns = max(2, min(9, usableWidth / 18))
        let rows = max(2, min(7, usableHeight / 12))
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
        for row in 0..<rows {
            let y0 = rowEdges[row].y0
            let y1 = rowEdges[row].y1
            let centerY = Float(y0) + (Float(y1 - y0) * 0.5)
            guard farFieldWeight(centerY: centerY, sampleHeight: sampleHeight) >= detailMotionBlockFarFieldThreshold else {
                continue
            }
            for column in 0..<columns {
                let x0 = columnEdges[column].x0
                let x1 = columnEdges[column].x1
                let midX = (x0 + x1) / 2
                appendBlock(x0: x0, x1: midX, y0: y0, y1: y1)
                appendBlock(x0: midX, x1: x1, y0: y0, y1: y1)
            }
        }
        for row in 0..<rows {
            let y0 = rowEdges[row].y0
            let y1 = rowEdges[row].y1
            let centerY = Float(y0) + (Float(y1 - y0) * 0.5)
            guard farFieldWeight(centerY: centerY, sampleHeight: sampleHeight) >= verticalDetailMotionBlockFarFieldThreshold else {
                continue
            }
            let midY = (y0 + y1) / 2
            for column in 0..<columns {
                let x0 = columnEdges[column].x0
                let x1 = columnEdges[column].x1
                appendBlock(x0: x0, x1: x1, y0: y0, y1: midY)
                appendBlock(x0: x0, x1: x1, y0: midY, y1: y1)
            }
        }
        let centerColumn = columns / 2
        for row in 0..<rows {
            let y0 = rowEdges[row].y0
            let y1 = rowEdges[row].y1
            let centerY = Float(y0) + (Float(y1 - y0) * 0.5)
            guard farFieldWeight(centerY: centerY, sampleHeight: sampleHeight) >= attitudeDetailMotionBlockFarFieldThreshold else {
                continue
            }
            let midY = (y0 + y1) / 2
            for column in 0..<columns where abs(column - centerColumn) <= attitudeDetailMotionBlockColumnRadius {
                let x0 = columnEdges[column].x0
                let x1 = columnEdges[column].x1
                let midX = (x0 + x1) / 2
                appendBlock(x0: x0, x1: midX, y0: y0, y1: midY)
                appendBlock(x0: midX, x1: x1, y0: y0, y1: midY)
                appendBlock(x0: x0, x1: midX, y0: midY, y1: y1)
                appendBlock(x0: midX, x1: x1, y0: midY, y1: y1)
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

    private static func weightedAffineAxisFit(
        _ samples: [(x: Float, y: Float, value: Float, weight: Float)]
    ) -> StabilizerAffineAxisFit? {
        let finiteSamples = samples.filter {
            $0.x.isFinite && $0.y.isFinite && $0.value.isFinite && $0.weight.isFinite && $0.weight > 0.0
        }
        guard finiteSamples.count >= 3 else {
            return nil
        }

        var weightedSamples = finiteSamples
        var fit = solveWeightedAffineAxis(weightedSamples)
        for _ in 0..<2 {
            guard let currentFit = fit else {
                return nil
            }
            let residuals = finiteSamples.map {
                abs($0.value - affineAxisValue(currentFit, x: $0.x, y: $0.y))
            }
            let residualScale = max(Float(0.75), (median(residuals) ?? 0.0) * 2.5)
            weightedSamples = finiteSamples.map { sample in
                let residual = abs(sample.value - affineAxisValue(currentFit, x: sample.x, y: sample.y))
                let robustWeight = residual <= residualScale || residual <= Float.ulpOfOne
                    ? Float(1.0)
                    : residualScale / residual
                return (
                    x: sample.x,
                    y: sample.y,
                    value: sample.value,
                    weight: sample.weight * clamp(robustWeight, min: 0.05, max: 1.0)
                )
            }
            fit = solveWeightedAffineAxis(weightedSamples)
        }

        guard let finalFit = fit else {
            return nil
        }
        let residuals = finiteSamples.map {
            abs($0.value - affineAxisValue(finalFit, x: $0.x, y: $0.y))
        }
        return StabilizerAffineAxisFit(
            offset: finalFit.offset,
            xSlope: finalFit.xSlope,
            ySlope: finalFit.ySlope,
            residual: median(residuals) ?? 0.0
        )
    }

    private static func solveWeightedAffineAxis(
        _ samples: [(x: Float, y: Float, value: Float, weight: Float)]
    ) -> StabilizerAffineAxisFit? {
        var m00 = Double(0.0)
        var m01 = Double(0.0)
        var m02 = Double(0.0)
        var m11 = Double(0.0)
        var m12 = Double(0.0)
        var m22 = Double(0.0)
        var b0 = Double(0.0)
        var b1 = Double(0.0)
        var b2 = Double(0.0)
        var totalWeight = Double(0.0)

        for sample in samples {
            let w = Double(sample.weight)
            let x = Double(sample.x)
            let y = Double(sample.y)
            let value = Double(sample.value)
            totalWeight += w
            m00 += w
            m01 += w * x
            m02 += w * y
            m11 += w * x * x
            m12 += w * x * y
            m22 += w * y * y
            b0 += w * value
            b1 += w * x * value
            b2 += w * y * value
        }
        guard totalWeight > 0.0 else {
            return nil
        }
        guard let solution = solve3x3(
            [
                [m00, m01, m02],
                [m01, m11, m12],
                [m02, m12, m22]
            ],
            [b0, b1, b2]
        ) else {
            return nil
        }
        return StabilizerAffineAxisFit(
            offset: Float(solution[0]),
            xSlope: Float(solution[1]),
            ySlope: Float(solution[2]),
            residual: 0.0
        )
    }

    private static func solve3x3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 3 }), rhs.count == 3 else {
            return nil
        }
        var rows = [
            [matrix[0][0], matrix[0][1], matrix[0][2], rhs[0]],
            [matrix[1][0], matrix[1][1], matrix[1][2], rhs[1]],
            [matrix[2][0], matrix[2][1], matrix[2][2], rhs[2]]
        ]
        for column in 0..<3 {
            var pivotRow = column
            var pivotValue = abs(rows[column][column])
            for row in (column + 1)..<3 {
                let value = abs(rows[row][column])
                if value > pivotValue {
                    pivotValue = value
                    pivotRow = row
                }
            }
            guard pivotValue > 1e-9 else {
                return nil
            }
            if pivotRow != column {
                rows.swapAt(pivotRow, column)
            }
            let pivot = rows[column][column]
            for entry in column...3 {
                rows[column][entry] /= pivot
            }
            for row in 0..<3 where row != column {
                let factor = rows[row][column]
                guard abs(factor) > 1e-12 else {
                    continue
                }
                for entry in column...3 {
                    rows[row][entry] -= factor * rows[column][entry]
                }
            }
        }
        return [rows[0][3], rows[1][3], rows[2][3]]
    }

    private static func affineAxisValue(_ fit: StabilizerAffineAxisFit, x: Float, y: Float) -> Float {
        fit.offset + (fit.xSlope * x) + (fit.ySlope * y)
    }

    private static func farFieldPlaneMotion(
        shifts: [StabilizerBlockShift],
        seedDx: Float,
        seedDy: Float,
        sampleWidth: Int,
        sampleHeight: Int
    ) -> StabilizerFarFieldPlaneMotion? {
        let finiteShifts = shifts.filter { shift in
            shift.dx.isFinite && shift.dy.isFinite && shift.score.isFinite
        }
        guard finiteShifts.count >= farFieldPlaneMinimumBlocks else {
            return nil
        }
        let strictFarField = finiteShifts.filter { $0.block.farFieldWeight >= farFieldPlaneStrictThreshold }
        let broadFarField = finiteShifts.filter { $0.block.farFieldWeight >= farFieldPlaneBroadThreshold }
        let farFieldShifts = strictFarField.count >= farFieldPlaneMinimumBlocks ? strictFarField : broadFarField
        guard farFieldShifts.count >= farFieldPlaneMinimumBlocks else {
            return nil
        }
        let scoreReference = median(farFieldShifts.map(\.score).filter(\.isFinite)) ?? 0.0
        let weightedDx = weightedMedian(farFieldShifts.map {
            ($0.dx, motionBlockWeight($0, scoreReference: scoreReference))
        }) ?? seedDx
        let weightedDy = weightedMedian(farFieldShifts.map {
            ($0.dy, motionBlockWeight($0, scoreReference: scoreReference))
        }) ?? seedDy
        let halfWidth = Float(max(1, sampleWidth)) * 0.5
        let halfHeight = Float(max(1, sampleHeight)) * 0.5
        let affineSamples = farFieldShifts.map { shift -> (x: Float, y: Float, dx: Float, dy: Float, weight: Float) in
            let x = (shift.block.centerX - halfWidth) / halfWidth
            let y = (shift.block.centerY - halfHeight) / halfHeight
            return (
                x: x,
                y: y,
                dx: shift.dx,
                dy: shift.dy,
                weight: motionBlockWeight(shift, scoreReference: scoreReference)
            )
        }
        let affineX = weightedAffineAxisFit(affineSamples.map {
            (x: $0.x, y: $0.y, value: $0.dx, weight: $0.weight)
        })
        let affineY = weightedAffineAxisFit(affineSamples.map {
            (x: $0.x, y: $0.y, value: $0.dy, weight: $0.weight)
        })
        let affineDx = affineX?.offset ?? weightedDx
        let affineDy = affineY?.offset ?? weightedDy
        let rollCandidates = farFieldShifts.compactMap { shift -> (value: Float, weight: Float)? in
            let x = shift.block.centerX - halfWidth
            let y = shift.block.centerY - halfHeight
            let denominator = (x * x) + (y * y)
            guard denominator > 1.0 else {
                return nil
            }
            let u = shift.dx - affineDx
            let v = shift.dy - affineDy
            let roll = ((x * v) - (y * u)) / denominator
            return (roll, motionBlockWeight(shift, scoreReference: scoreReference))
        }
        let medianRoll = weightedMedian(rollCandidates) ?? 0.0
        let affineRoll: Float
        if let affineX, let affineY {
            let xRoll = -affineX.ySlope / halfHeight
            let yRoll = affineY.xSlope / halfWidth
            affineRoll = (xRoll + yRoll) * 0.5
        } else {
            affineRoll = medianRoll
        }
        let affineSupport = (affineX != nil && affineY != nil) ? Float(1.0) : Float(0.0)
        let weightedRoll = medianRoll + ((affineRoll - medianRoll) * affineSupport)
        let nearFieldShifts = finiteShifts.filter { $0.block.farFieldWeight <= farFieldPlaneNearThreshold }
        let nearDx = nearFieldShifts.count >= farFieldPlaneMinimumBlocks
            ? weightedMedian(nearFieldShifts.map { ($0.dx, max(Float(0.05), 1.0 - $0.block.farFieldWeight)) })
            : nil
        let nearDy = nearFieldShifts.count >= farFieldPlaneMinimumBlocks
            ? weightedMedian(nearFieldShifts.map { ($0.dy, max(Float(0.05), 1.0 - $0.block.farFieldWeight)) })
            : nil
        let nearParallax = (nearDx != nil && nearDy != nil)
            ? hypotf((nearDx ?? weightedDx) - weightedDx, (nearDy ?? weightedDy) - weightedDy)
            : Float(0.0)
        let seedParallax = hypotf(weightedDx - seedDx, weightedDy - seedDy)
        let parallaxPixels = max(nearParallax, seedParallax)
        let parallaxSupport = confidenceRamp(
            parallaxPixels,
            start: farFieldPlaneParallaxStartPixels,
            full: farFieldPlaneParallaxFullPixels
        )
        let consensusConfidence = farFieldConsensusConfidence(
            farFieldShifts: farFieldShifts,
            allShiftCount: finiteShifts.count,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let authority = clamp(
            consensusConfidence * (farFieldPlaneAuthorityBase + (farFieldPlaneAuthorityParallaxScale * parallaxSupport)),
            min: 0.0,
            max: farFieldPlaneMaximumAuthority
        )
        guard authority >= farFieldConsensusConfidenceFloor else {
            return nil
        }
        let yawProxy = affineX.map {
            clamp(($0.xSlope / halfWidth) * consensusConfidence, min: -maxFarFieldYawPitchProxy, max: maxFarFieldYawPitchProxy)
        } ?? 0.0
        let pitchProxy = affineY.map {
            clamp(($0.ySlope / halfHeight) * consensusConfidence, min: -maxFarFieldYawPitchProxy, max: maxFarFieldYawPitchProxy)
        } ?? 0.0
        let shearX = affineX.map {
            clamp((($0.ySlope + (weightedRoll * halfHeight)) / halfHeight) * consensusConfidence, min: -maxFarFieldShear, max: maxFarFieldShear)
        } ?? 0.0
        let shearY = affineY.map {
            clamp((($0.xSlope - (weightedRoll * halfWidth)) / halfWidth) * consensusConfidence, min: -maxFarFieldShear, max: maxFarFieldShear)
        } ?? 0.0
        return StabilizerFarFieldPlaneMotion(
            dx: affineDx,
            dy: affineDy,
            signedRoll: weightedRoll,
            yawProxy: yawProxy,
            pitchProxy: pitchProxy,
            shearX: shearX,
            shearY: shearY,
            authority: authority,
            parallaxPixels: parallaxPixels
        )
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
        let consensusConfidence = farFieldConsensusConfidence(
            farFieldShifts: farFieldShifts,
            allShiftCount: shifts.count,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight
        )
        let confidence = max(
            clamp(analysisConfidence * farFieldCoverage, min: 0.0, max: 1.0),
            consensusConfidence
        )
        guard confidence >= farFieldConsensusConfidenceFloor else {
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

    private static func farFieldConsensusConfidence(
        farFieldShifts: [StabilizerBlockShift],
        allShiftCount: Int,
        sampleWidth: Int,
        sampleHeight: Int
    ) -> Float {
        guard farFieldShifts.count >= minimumFarFieldMotionBlocks else {
            return 0.0
        }

        let weightedDx = weightedMedian(farFieldShifts.map {
            ($0.dx, farFieldConsensusWeight($0))
        }) ?? 0.0
        let weightedDy = weightedMedian(farFieldShifts.map {
            ($0.dy, farFieldConsensusWeight($0))
        }) ?? 0.0
        let coherencePixels = farFieldConsensusCoherencePixels(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
        let medianDistance = median(farFieldShifts.map {
            hypotf($0.dx - weightedDx, $0.dy - weightedDy)
        }) ?? coherencePixels
        let coherence = clamp(
            1.0 - (medianDistance / coherencePixels),
            min: 0.0,
            max: 1.0
        )
        let totalWeight = farFieldShifts.reduce(Float(0.0)) {
            $0 + farFieldConsensusWeight($1)
        }
        let weightSupport = confidenceRamp(
            totalWeight,
            start: farFieldConsensusMinimumWeight,
            full: farFieldConsensusFullWeight
        )
        let coverage = Float(farFieldShifts.count) / Float(max(1, allShiftCount))
        let coverageSupport = confidenceRamp(coverage, start: 0.08, full: 0.32)
        let searchHeadroom = Float(farFieldShifts.filter { !$0.searchRadiusHit }.count) / Float(farFieldShifts.count)
        let saturationSupport = clamp(0.35 + (searchHeadroom * 0.65), min: 0.0, max: 1.0)
        return clamp(weightSupport * coherence * max(coverageSupport, 0.25) * saturationSupport, min: 0.0, max: 1.0)
    }

    private static func farFieldConsensusWeight(_ shift: StabilizerBlockShift) -> Float {
        let baseWeight = shift.block.farFieldWeight
        guard shift.score.isFinite else {
            return baseWeight * 0.05
        }
        let scoreQuality = clamp(
            1.0 - (shift.score * 1.8),
            min: 0.05,
            max: 1.0
        )
        let searchHeadroom: Float = shift.searchRadiusHit ? 0.65 : 1.0
        return baseWeight * scoreQuality * searchHeadroom
    }

    private static func farFieldConsensusCoherencePixels(sampleWidth: Int, sampleHeight: Int) -> Float {
        max(6.0, Float(max(1, min(sampleWidth, sampleHeight))) * farFieldConsensusCoherenceFrameFraction)
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

    private static func localFrameStepSeconds(frames: [StabilizerAnalysisFrame], centerIndex: Int) -> Double {
        guard frames.count > 1 else {
            return 1.0 / 60.0
        }

        var candidates: [Double] = []
        func appendDelta(_ lowerIndex: Int, _ upperIndex: Int) {
            guard frames.indices.contains(lowerIndex),
                  frames.indices.contains(upperIndex)
            else {
                return
            }
            let delta = frames[upperIndex].time - frames[lowerIndex].time
            if delta.isFinite, delta > 0.0 {
                candidates.append(delta)
            }
        }

        appendDelta(centerIndex - 2, centerIndex - 1)
        appendDelta(centerIndex - 1, centerIndex)
        appendDelta(centerIndex, centerIndex + 1)
        appendDelta(centerIndex + 1, centerIndex + 2)
        guard !candidates.isEmpty else {
            return 1.0 / 60.0
        }
        candidates.sort()
        let median = candidates[candidates.count / 2]
        return min(
            max(median, renderFrameLocalSmoothingMinimumStepSeconds),
            renderFrameLocalSmoothingMaximumStepSeconds
        )
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

    private static func turnSmoothingRotationLimit(strength: Double) -> Float {
        let extraStrength = clamp(Float(strength - 1.0), min: 0.0, max: 3.0)
        return baseTurnSmoothingRotationLimitDegrees + (extraTurnSmoothingRotationLimitDegrees * extraStrength)
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

    private static func strengthScaledFarFieldWarpBandValue(
        values: [Float],
        baselineValues: EstimatedPath,
        interpolation: FrameInterpolation,
        deadband: Float,
        confidence: Float,
        strength: Float,
        limit: Float
    ) -> Float {
        let scaledValue = farFieldWarpBandValue(
            values: values,
            baselineValues: baselineValues,
            interpolation: interpolation,
            deadband: deadband,
            confidence: confidence
        ) * strength
        return clamp(scaledValue, min: -limit * strength, max: limit * strength)
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

    private static func timeWeightedLinearPrediction(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        centerTime: Double,
        windowSeconds: Double
    ) -> Float? {
        guard indices.count >= 3,
              centerTime.isFinite,
              windowSeconds.isFinite,
              windowSeconds > 0.0
        else {
            return nil
        }

        let sortedIndices = indicesAreStrictlyAscending(indices) ? indices : indices.sorted()
        let windowStart = centerTime - (windowSeconds * 0.5)
        let windowEnd = centerTime + (windowSeconds * 0.5)
        var s00 = Double(0.0)
        var s01 = Double(0.0)
        var s11 = Double(0.0)
        var b0 = Double(0.0)
        var b1 = Double(0.0)
        var acceptedCount = 0

        for (position, index) in sortedIndices.enumerated() where frames.indices.contains(index) {
            let currentTime = frames[index].time
            guard currentTime.isFinite else {
                continue
            }

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
            guard weight > 1e-9 else {
                continue
            }

            let t = currentTime - centerTime
            let value = Double(values[index])
            guard value.isFinite, t.isFinite else {
                continue
            }

            s00 += weight
            s01 += weight * t
            s11 += weight * t * t
            b0 += weight * value
            b1 += weight * t * value
            acceptedCount += 1
        }

        guard acceptedCount >= 3, s00 > 1e-9 else {
            return nil
        }

        let determinant = (s00 * s11) - (s01 * s01)
        guard abs(determinant) > 1e-9 else {
            return Float(b0 / s00)
        }

        let intercept = ((b0 * s11) - (b1 * s01)) / determinant
        guard intercept.isFinite else {
            return nil
        }
        return Float(intercept)
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
        let requestedRemoval = clamp(Float(strength), min: 0.0, max: maximumTurnSmoothingStrength)
        let confidenceResponse = turnCorrectionConfidenceResponse(confidence)
        let directRemoval = min(requestedRemoval, 1.0) * confidenceResponse
        let confidenceBoost = max(0.0, requestedRemoval - 1.0)
            * 0.55
            * confidenceResponse
            * (1.0 - (confidenceResponse * 0.25))
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
        return boundedConfidence * boundedConfidence * (3.0 - (2.0 * boundedConfidence))
    }

    private static func turnCorrectionConfidenceResponse(_ confidence: Float) -> Float {
        let boundedConfidence = clamp(confidence, min: 0.0, max: 1.0)
        let eased = boundedConfidence * (1.0 + ((1.0 - boundedConfidence) * 1.0))
        return clamp(eased, min: 0.0, max: 1.0)
    }

    private static func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {
        let boundedConfidence = clamp(confidence, min: 0.0, max: 1.0)
        return boundedConfidence * (1.0 + ((1.0 - boundedConfidence) * 0.90))
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
        let strictGate = correctionConfidenceResponse(
            clamp(trackingGate * edgeGate, min: 0.0, max: 1.0)
        )
        let consensusGate = correctionConfidenceResponse(
            confidenceRamp(
                warpConfidence,
                start: farFieldWarpConsensusGateStart,
                full: farFieldWarpConsensusGateFull
            )
        ) * confidenceRamp(edgeQuality, start: 0.08, full: 0.42)
        return max(strictGate, consensusGate)
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

    private static func stableFarFieldWarpConfidence(
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        currentWarpConfidence: Float
    ) -> Float {
        var localWarpValues: [Float] = []
        localWarpValues.reserveCapacity(indices.count)
        for index in indices {
            guard analysis.warpConfidence.indices.contains(index) else {
                continue
            }
            let confidence = analysis.warpConfidence[index]
            guard confidence.isFinite else {
                continue
            }
            localWarpValues.append(clamp(confidence, min: 0.0, max: 1.0))
        }
        guard let localMedianWarpConfidence = median(localWarpValues) else {
            return currentWarpConfidence
        }
        let medianSupport = confidenceRamp(
            localMedianWarpConfidence,
            start: farFieldConsensusConfidenceFloor,
            full: farFieldWarpConsensusGateFull
        )
        let stabilizedMedian = localMedianWarpConfidence * (0.55 + (0.30 * medianSupport))
        return clamp(
            max(currentWarpConfidence, stabilizedMedian),
            min: 0.0,
            max: 1.0
        )
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

    private static func turnSmoothingRotationConfidence(
        bandValue: Float,
        trackingConfidence: Float
    ) -> Float {
        let magnitude = abs(bandValue)
        let noiseFloor = turnSmoothingFullScaleDegrees * 0.08
        let bandQuality = confidenceRamp(
            magnitude,
            start: noiseFloor,
            full: max(noiseFloor + Float.ulpOfOne, turnSmoothingFullScaleDegrees)
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
        let strictOwnership = max(monotonicQuality, endpointQuality) * bandQuality * trackingQuality
        let directionalCoherence = max(monotonicQuality, endpointQuality)
        let macroBandQuality = confidenceRamp(
            abs(turnBandValue),
            start: turnMacroOwnershipBandStartPixels,
            full: turnMacroOwnershipBandFullPixels
        )
        let macroTravelQuality = confidenceRamp(
            dominantTravel,
            start: turnMacroOwnershipTravelStartPixels,
            full: turnMacroOwnershipTravelFullPixels
        )
        let macroTrackingQuality = confidenceRamp(
            trackingConfidence,
            start: turnMacroOwnershipTrackingStart,
            full: turnMacroOwnershipTrackingFull
        )
        let macroOwnership = directionalCoherence
            * macroBandQuality
            * macroTravelQuality
            * macroTrackingQuality
            * turnMacroOwnershipScale
        return clamp(max(strictOwnership, macroOwnership), min: 0.0, max: 1.0)
    }

    private static func turnStabilizerShakeSuppression(
        turnOwnership: Float,
        turnConfidence: Float
    ) -> Float {
        let ownershipQuality = confidenceRamp(turnOwnership, start: 0.12, full: 0.48)
        return clamp(max(turnConfidence, ownershipQuality), min: 0.0, max: 1.0)
    }

    private static func turnOwnedWalkingXGateFloor(
        rawConfidence: Float,
        bandMagnitude: Float,
        turnShakeSuppression: Float,
        turnOwnership: Float
    ) -> Float {
        guard bandMagnitude.isFinite else {
            return 0.0
        }
        let turnSupport = max(
            confidenceRamp(turnShakeSuppression, start: 0.18, full: 0.56),
            confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
        )
        let walkingSupport = confidenceRamp(rawConfidence, start: 0.03, full: 0.10)
        let impulseSupport = confidenceRamp(
            bandMagnitude,
            start: turnOwnedWalkingXGateFloorStartPixels,
            full: turnOwnedWalkingXGateFloorFullPixels
        )
        return clamp(
            turnOwnedWalkingXGateFloorMax * turnSupport * walkingSupport * impulseSupport,
            min: 0.0,
            max: turnOwnedWalkingXGateFloorMax
        )
    }

    private static func turnCorrectionConfidence(
        confidence: Float,
        turnOwnership: Float
    ) -> Float {
        let ownershipFloor = confidenceRamp(turnOwnership, start: 0.12, full: 0.48) * 0.42
        return clamp(max(confidence, ownershipFloor), min: 0.0, max: 1.0)
    }

    private static func smoothedTurnShakeSuppression(
        rawSuppression: Float,
        gateScales: [Int: Float],
        frames: [StabilizerAnalysisFrame],
        centerTime: Double
    ) -> Float {
        let boundedRaw = clamp(rawSuppression, min: 0.0, max: 1.0)
        guard !gateScales.isEmpty,
              renderTurnGateSmoothingWindowSeconds > 0.0
        else {
            return boundedRaw
        }
        let halfWindow = renderTurnGateSmoothingWindowSeconds * 0.5
        let sigma = max(1e-6, halfWindow * 0.55)
        let centerWeight: Float = 0.75
        var weightedSuppression = boundedRaw * centerWeight
        var totalWeight = centerWeight
        for index in indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow) {
            guard frames.indices.contains(index),
                  let gateScale = gateScales[index]
            else {
                continue
            }
            let offset = frames[index].time - centerTime
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let localSuppression = clamp(1.0 - gateScale, min: 0.0, max: 1.0)
            weightedSuppression += localSuppression * weight
            totalWeight += weight
        }
        guard totalWeight > Float.ulpOfOne else {
            return boundedRaw
        }
        let smoothedSuppression = weightedSuppression / totalWeight
        return clamp(max(boundedRaw, smoothedSuppression), min: 0.0, max: 1.0)
    }

    private static func turnOwnershipGateScales(
        values: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        targetIndices: [Int],
        windowSeconds: Double,
        cache: RenderEstimateCache
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
            let residual = cache.residualPercentile(analysis: analysis, indices: activeIndices, percentile: 0.75)
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
        _ kind: MotionPathKind,
        values: [Float],
        baselineValues: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        indices: [Int],
        fullImpulseScale: Float,
        confidenceScales: [Int: Float] = [:],
        cache: RenderEstimateCache
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
            let confidence = cache.footstepFrameConfidence(
                kind: kind,
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
        _ kind: MotionPathKind,
        values: [Float],
        baselineValues: EstimatedPath,
        analysis: StabilizerPreparedAnalysis,
        centerTime: Double,
        rawCorrection: Float,
        outputScale: Float,
        requestedStrength: Double,
        fullImpulseScale: Float,
        confidenceScale: Float = 1.0,
        cache: RenderEstimateCache
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
                kind,
                values: values,
                baselineValues: baselineValues,
                frames: analysis.frames,
                interpolation: FrameInterpolation(lowerIndex: index, upperIndex: index, fraction: 0.0),
                trackingConfidence: trackingConfidence,
                fullImpulseScale: fullImpulseScale,
                cache: cache
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
        _ kind: MotionPathKind,
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        interpolation: FrameInterpolation,
        trackingConfidence: Float,
        fullImpulseScale: Float,
        cache: RenderEstimateCache
    ) -> Float {
        let lowerConfidence = cache.footstepFrameConfidence(
            kind: kind,
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
                fullImpulseScale: fullImpulseScale,
                kind: kind,
                cache: cache
            )
        }
        let upperConfidence = cache.footstepFrameConfidence(
            kind: kind,
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
            fullImpulseScale: fullImpulseScale,
            kind: kind,
            cache: cache
        )
    }

    private static func stableFootstepFrameConfidence(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        centerTime: Double,
        instantConfidence: Float,
        trackingConfidence: Float,
        fullImpulseScale: Float,
        kind: MotionPathKind,
        cache: RenderEstimateCache
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
            let confidence = cache.footstepFrameConfidence(
                kind: kind,
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
