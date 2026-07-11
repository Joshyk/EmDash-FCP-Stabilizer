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
    var trajectoryMicroJitterPixelOffset: vector_float2
    var trajectoryContinuityPixelOffset: vector_float2
    var lensShakePixelOffset: vector_float2
    var lensShakeRotationDegrees: Float
    var lensShakeYawPitch: vector_float2
    var lensShakeShear: vector_float2
    var lensShakePerspective: vector_float2
    var lensShakeScore: Float
    var lensShakeSupport: Float
    var lensShakeWindowFrames: Float
    var lensShakeWindowSeconds: Float = 0.0
    var lensShakeAxisMask: Int32
    var lensShakeReasonCode: Int32
    var lensShakeRollingShutterCandidate: Float
    var lensBandTopOffset: vector_float2
    var lensBandRidgeOffset: vector_float2
    var lensBandMidOffset: vector_float2
    var lensBandRawTopOffset: vector_float2
    var lensBandRawRidgeOffset: vector_float2
    var lensBandRawMidOffset: vector_float2
    var lensBandPulseDeltaTopOffset: vector_float2
    var lensBandPulseDeltaRidgeOffset: vector_float2
    var lensBandPulseDeltaMidOffset: vector_float2
    var lensBandPulseWindowFrames: Float
    var lensBandTopColumnOffset: vector_float2
    var lensBandRidgeColumnOffset: vector_float2
    var lensBandMidColumnOffset: vector_float2
    var lensBandTopRowPhaseOffset: vector_float2
    var lensBandRidgeRowPhaseOffset: vector_float2
    var lensBandMidRowPhaseOffset: vector_float2
    var lensBandTopLocalRoll: Float
    var lensBandRidgeLocalRoll: Float
    var lensBandMidLocalRoll: Float
    var lensBandWarpSupport: Float
    var lensBandWarpApplied: Float
    var lensBandRollingShutterScore: Float
    var lensBandModelMask: Int32
    var lensFarFieldRigidShakeOffset: vector_float2
    var lensFarFieldRigidShakeSupport: Float
    var lensFarFieldRigidShakeApplied: Float
    var lensFarFieldRigidShakeShapeConsistency: Float
    var lensFarFieldRigidShakeForwardBackwardConsistency: Float
    var lensFarFieldRigidShakeLocalWarpSuppressed: Float
    var lensFarFieldRigidXQuiverScore: Float = 0.0
    var lensFarFieldRigidXBeforeLimiter: Float = 0.0
    var lensFarFieldRigidXAfterLimiter: Float = 0.0
    var lensFarFieldRigidRollResidual: Float = 0.0
    var lensFarFieldRigidRollSupport: Float = 0.0
    var lensFarFieldRigidGlobalYOffset: Float = 0.0
    var lensFarFieldRigidGlobalRollDegrees: Float = 0.0
    var lensFarFieldRigidRollApplied: Float = 0.0
    var lensFarFieldMeshOffset: vector_float2 = vector_float2(0.0, 0.0)
    var lensFarFieldMeshSupport: Float = 0.0
    var lensFarFieldMeshBlend: Float = 0.0
    var lensFarFieldMeshAvailable: Float = 0.0
    var lensFarFieldMeshSupportedBins: Float = 0.0
    var lensFarFieldMeshMaxBinDelta: Float = 0.0
    var lensFarFieldMeshOpposingBins: Float = 0.0
    var lensFarFieldMeshDominantWindowFrames: Float = 0.0
    var lensFarFieldMeshDominantWindowSeconds: Float = 0.0
    var lensFarFieldMeshDominantSupport: Float = 0.0
    var lensFarFieldMeshDominantCell: Float = -1.0
    var sourceLensShakeRidgeOffset: vector_float2
    var sourceLensShakeRidgeSupport: Float
    var sourceLensShakeRidgeApplied: Float
    var sourceLensShakeRidgeLineResidual: vector_float2
    var sourceLensShakeRidgeLineOffset: vector_float2
    var sourceLensShakeRidgeLineSupport: Float
    var sourceLensShakeRidgeLineBandSupported: Float
    var sourceLensShakeRidgeLineApplied: Float
    var sourceLensShakeLocalTopLeftOffset: vector_float2
    var sourceLensShakeLocalTopCenterOffset: vector_float2
    var sourceLensShakeLocalTopRightOffset: vector_float2
    var sourceLensShakeLocalRidgeLeftOffset: vector_float2
    var sourceLensShakeLocalRidgeCenterOffset: vector_float2
    var sourceLensShakeLocalRidgeRightOffset: vector_float2
    var sourceLensShakeLocalMidLeftOffset: vector_float2
    var sourceLensShakeLocalMidCenterOffset: vector_float2
    var sourceLensShakeLocalMidRightOffset: vector_float2
    var sourceLensShakeLocalSupport: Float
    var sourceLensShakeLocalApplied: Float
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
        trajectoryMicroJitterPixelOffset: vector_float2(0.0, 0.0),
        trajectoryContinuityPixelOffset: vector_float2(0.0, 0.0),
        lensShakePixelOffset: vector_float2(0.0, 0.0),
        lensShakeRotationDegrees: 0.0,
        lensShakeYawPitch: vector_float2(0.0, 0.0),
        lensShakeShear: vector_float2(0.0, 0.0),
        lensShakePerspective: vector_float2(0.0, 0.0),
        lensShakeScore: 0.0,
        lensShakeSupport: 0.0,
        lensShakeWindowFrames: 0.0,
        lensShakeAxisMask: 0,
        lensShakeReasonCode: 0,
        lensShakeRollingShutterCandidate: 0.0,
        lensBandTopOffset: vector_float2(0.0, 0.0),
        lensBandRidgeOffset: vector_float2(0.0, 0.0),
        lensBandMidOffset: vector_float2(0.0, 0.0),
        lensBandRawTopOffset: vector_float2(0.0, 0.0),
        lensBandRawRidgeOffset: vector_float2(0.0, 0.0),
        lensBandRawMidOffset: vector_float2(0.0, 0.0),
        lensBandPulseDeltaTopOffset: vector_float2(0.0, 0.0),
        lensBandPulseDeltaRidgeOffset: vector_float2(0.0, 0.0),
        lensBandPulseDeltaMidOffset: vector_float2(0.0, 0.0),
        lensBandPulseWindowFrames: 0.0,
        lensBandTopColumnOffset: vector_float2(0.0, 0.0),
        lensBandRidgeColumnOffset: vector_float2(0.0, 0.0),
        lensBandMidColumnOffset: vector_float2(0.0, 0.0),
        lensBandTopRowPhaseOffset: vector_float2(0.0, 0.0),
        lensBandRidgeRowPhaseOffset: vector_float2(0.0, 0.0),
        lensBandMidRowPhaseOffset: vector_float2(0.0, 0.0),
        lensBandTopLocalRoll: 0.0,
        lensBandRidgeLocalRoll: 0.0,
        lensBandMidLocalRoll: 0.0,
        lensBandWarpSupport: 0.0,
        lensBandWarpApplied: 0.0,
        lensBandRollingShutterScore: 0.0,
        lensBandModelMask: 0,
        lensFarFieldRigidShakeOffset: vector_float2(0.0, 0.0),
        lensFarFieldRigidShakeSupport: 0.0,
        lensFarFieldRigidShakeApplied: 0.0,
        lensFarFieldRigidShakeShapeConsistency: 0.0,
        lensFarFieldRigidShakeForwardBackwardConsistency: 0.0,
        lensFarFieldRigidShakeLocalWarpSuppressed: 0.0,
        lensFarFieldRigidXQuiverScore: 0.0,
        lensFarFieldRigidXBeforeLimiter: 0.0,
        lensFarFieldRigidXAfterLimiter: 0.0,
        lensFarFieldRigidRollResidual: 0.0,
        lensFarFieldRigidRollSupport: 0.0,
        lensFarFieldRigidGlobalYOffset: 0.0,
        lensFarFieldRigidGlobalRollDegrees: 0.0,
        lensFarFieldRigidRollApplied: 0.0,
        sourceLensShakeRidgeOffset: vector_float2(0.0, 0.0),
        sourceLensShakeRidgeSupport: 0.0,
        sourceLensShakeRidgeApplied: 0.0,
        sourceLensShakeRidgeLineResidual: vector_float2(0.0, 0.0),
        sourceLensShakeRidgeLineOffset: vector_float2(0.0, 0.0),
        sourceLensShakeRidgeLineSupport: 0.0,
        sourceLensShakeRidgeLineBandSupported: 0.0,
        sourceLensShakeRidgeLineApplied: 0.0,
        sourceLensShakeLocalTopLeftOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalTopCenterOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalTopRightOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalRidgeLeftOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalRidgeCenterOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalRidgeRightOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalMidLeftOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalMidCenterOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalMidRightOffset: vector_float2(0.0, 0.0),
        sourceLensShakeLocalSupport: 0.0,
        sourceLensShakeLocalApplied: 0.0,
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
    let cameraJitterX: Double
    let cameraJitterY: Double
    let cameraJitterRotation: Double
    let farFieldWarp: Double
    let turnSmoothingZoom: Double

    // The estimator still uses its prepared short/medium residual measurements,
    // but they are one Camera Jitter stage with one set of user strengths.
    var microJitterX: Double { cameraJitterX }
    var microJitterY: Double { cameraJitterY }
    var microJitterRotation: Double { cameraJitterRotation }
    var strideWobbleX: Double { cameraJitterX }
    var strideWobbleY: Double { cameraJitterY }
    var strideWobbleRotation: Double { cameraJitterRotation }

    static let defaultStrengths = StabilizerCorrectionStrengths(
        cameraJitterX: 1.0,
        cameraJitterY: 1.0,
        cameraJitterRotation: 0.5,
        farFieldWarp: 0.5,
        turnSmoothingZoom: 5.0
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
    let farFieldPathX: [Float]
    let farFieldPathY: [Float]
    let farFieldPathRoll: [Float]
    let farFieldConfidence: [Float]
    let footstepPathX: [Float]
    let footstepPathY: [Float]
    let footstepPathRoll: [Float]
    let pathYaw: [Float]
    let pathPitch: [Float]
    let pathShearX: [Float]
    let pathShearY: [Float]
    let pathPerspectiveX: [Float]
    let pathPerspectiveY: [Float]
    let lensBandTopPathX: [Float]
    let lensBandTopPathY: [Float]
    let lensBandTopColumnPathX: [Float]
    let lensBandTopColumnPathY: [Float]
    let lensBandTopRowPhasePathX: [Float]
    let lensBandTopRowPhasePathY: [Float]
    let lensBandTopLocalRollPath: [Float]
    let lensBandRidgePathX: [Float]
    let lensBandRidgePathY: [Float]
    let lensBandRidgeColumnPathX: [Float]
    let lensBandRidgeColumnPathY: [Float]
    let lensBandRidgeRowPhasePathX: [Float]
    let lensBandRidgeRowPhasePathY: [Float]
    let lensBandRidgeLocalRollPath: [Float]
    let lensBandMidPathX: [Float]
    let lensBandMidPathY: [Float]
    let lensBandMidColumnPathX: [Float]
    let lensBandMidColumnPathY: [Float]
    let lensBandMidRowPhasePathX: [Float]
    let lensBandMidRowPhasePathY: [Float]
    let lensBandMidLocalRollPath: [Float]
    let lensBandTopConfidence: [Float]
    let lensBandRidgeConfidence: [Float]
    let lensBandMidConfidence: [Float]
    let lensBandConfidence: [Float]
    let farFieldRigidShakePathX: [Float]
    let farFieldRigidShakePathY: [Float]
    let farFieldRigidShakePathRoll: [Float]
    let farFieldRigidShakeSupport: [Float]
    let farFieldRigidShakeRollSupport: [Float]
    let farFieldRigidShakeShapeConsistency: [Float]
    let farFieldRigidShakeForwardBackwardConsistency: [Float]
    let farFieldMeshRows: Int
    let farFieldMeshColumns: Int
    let farFieldMeshPathX: [Float]
    let farFieldMeshPathY: [Float]
    let farFieldMeshSupport: [Float]
    let farFieldMeshDominantWindowFrames: [Float]
    let farFieldMeshDominantWindowSeconds: [Float]
    let farFieldMeshDominantSupport: [Float]
    let farFieldMeshDominantCell: [Int32]
    let sourceLensShakeRidgePathY: [Float]
    let sourceLensShakeRidgeSupport: [Float]
    let sourceLensShakeRidgeLinePathY: [Float]
    let sourceLensShakeRidgeLineSupport: [Float]
    let sourceLensShakeLocalBinCount: Int
    let sourceLensShakeLocalPathX: [Float]
    let sourceLensShakeLocalPathY: [Float]
    let sourceLensShakeLocalSupport: [Float]
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
    let farFieldDx: Float
    let farFieldDy: Float
    let farFieldSignedRoll: Float
    let farFieldConfidence: Float
    let yawProxy: Float
    let pitchProxy: Float
    let shearX: Float
    let shearY: Float
    let perspectiveX: Float
    let perspectiveY: Float
    let lensBandTopDx: Float
    let lensBandTopDy: Float
    let lensBandTopColumnDx: Float
    let lensBandTopColumnDy: Float
    let lensBandTopRowPhaseDx: Float
    let lensBandTopRowPhaseDy: Float
    let lensBandTopLocalRoll: Float
    let lensBandRidgeDx: Float
    let lensBandRidgeDy: Float
    let lensBandRidgeColumnDx: Float
    let lensBandRidgeColumnDy: Float
    let lensBandRidgeRowPhaseDx: Float
    let lensBandRidgeRowPhaseDy: Float
    let lensBandRidgeLocalRoll: Float
    let lensBandMidDx: Float
    let lensBandMidDy: Float
    let lensBandMidColumnDx: Float
    let lensBandMidColumnDy: Float
    let lensBandMidRowPhaseDx: Float
    let lensBandMidRowPhaseDy: Float
    let lensBandMidLocalRoll: Float
    let lensBandTopConfidence: Float
    let lensBandRidgeConfidence: Float
    let lensBandMidConfidence: Float
    let lensBandConfidence: Float
    let sourceLensShakeRidgeDy: Float
    let sourceLensShakeRidgeSupport: Float
    let sourceLensShakeRidgeLineDy: Float
    let sourceLensShakeRidgeLineSupport: Float
    let sourceLensShakeLocalDx: [Float]
    let sourceLensShakeLocalDy: [Float]
    let sourceLensShakeLocalSupport: [Float]
    let farFieldMeshDx: [Float]
    let farFieldMeshDy: [Float]
    let farFieldMeshSupport: [Float]
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
    private static let turnSmoothingFullScaleDegrees: Float = 0.16
    private static let baseTurnSmoothingRotationLimitDegrees: Float = 0.80
    private static let extraTurnSmoothingRotationLimitDegrees: Float = 0.55
    private static let renderTemporalSmoothingSampleCount = 25
    private static let renderTemporalSmoothingWindowSeconds = 2.20
    private static let renderFrameLocalSmoothingRadiusFrames = 2
    private static let renderFrameLocalSmoothingBaseWeight: Float = 1.25
    private static let renderFrameLocalSmoothingMinimumStepSeconds = 1.0 / 120.0
    private static let renderFrameLocalSmoothingMaximumStepSeconds = 1.0 / 24.0
    private static let renderTurnTransitionSmoothingSampleCount = 29
    private static let renderTurnTransitionSmoothingWindowSeconds = 2.8
    private static let renderTurnTransitionMinimumMacroPixels: Float = 0.5
    private static let renderTurnTransitionBridgeMinimumBlend: Float = 0.0
    private static let renderTurnTransitionBridgeMaximumBlend: Float = 1.0
    private static let renderTurnTransitionBridgeEdgeGateStart: Float = 0.45
    private static let renderTurnTransitionBridgeEdgeGateFull: Float = 0.78
    private static let renderTurnTransitionBridgeLowEdgeLargeTurnBlend: Float = 0.48
    private static let renderTurnTransitionBridgeLowEdgeMacroStartPixels: Float = 48.0
    private static let renderTurnTransitionBridgeLowEdgeMacroFullPixels: Float = 120.0
    private static let renderTurnTransitionZoomCenterPreservationFade: Float = 0.92
    private static let renderTurnTransitionZoomCenterAnchorFade: Float = 0.92
    private static let adaptiveXTurnTransitionTargetPixelRate: Float = 42.0
    private static let adaptiveXTurnTransitionGateStartPixels: Float = 96.0
    private static let adaptiveXTurnTransitionGateFullPixels: Float = 220.0
    private static let adaptiveXTurnTransitionStandardStrength: Float = 12.0
    private static let adaptiveXTurnTransitionMaximumZoomParameter: Float = 36.0
    private static let adaptiveXTurnTransitionZoomStartPixels: Float = 24.0
    private static let adaptiveXTurnTransitionZoomFullPixels: Float = 160.0
    private static let adaptiveXTurnTransitionZoomConfidenceStart: Float = 0.12
    private static let adaptiveXTurnTransitionZoomConfidenceFull: Float = 0.35
    private static let renderTurnGateSmoothingWindowSeconds = 0.90
    private static let renderFarFieldWarpSmoothingWindowSeconds = 0.44
    private static let renderFootstepJitterSmoothingWindowSeconds = 0.18
    private static let renderFootstepJitterSmoothingMaxBlend: Float = 0.50
    private static let renderFootstepJitterSmoothingPixelSimilarity: Float = 1.75
    private static let renderFootstepJitterSmoothingRotationSimilarity: Float = 0.22
    private static let footstepCenterImpulsePreservationScale: Float = 0.55
    private static let footstepCenterImpulsePreservationFarFieldStart: Float = 0.06
    private static let footstepCenterImpulsePreservationFarFieldFull: Float = 0.28
    private static let footstepImpulseFullScalePixels: Float = 0.35
    private static let footstepImpulseFullScaleDegrees: Float = 0.08
    private static let footstepNoiseFloorScale: Float = 0.08
    private static let footstepSurroundingNoiseMultiplier: Float = 1.10
    private static let footstepSurroundingNoiseFloorCapScale: Float = 0.45
    private static let footstepFullResponseScale: Float = 0.55
    private static let verticalWalkingMediumConfidenceLift: Float = 0.20
    private static let footstepConfidenceStabilityWindowSeconds = 0.18
    private static let footstepConfidenceCenterBlend: Float = 0.65
    private static let footstepPersistentSignWindowStartSeconds = 0.055
    private static let footstepPersistentSignWindowEndSeconds = 0.22
    private static let footstepXYContinuityWindowSeconds = 0.15
    private static let footstepXYContinuityMaxSamples = 9
    private static let footstepXYContinuityMinimumSpikePixels: Float = 0.75
    private static let footstepXYContinuityMadMultiplier: Float = 3.0
    private static let footstepLowEvidenceLargeXConfidenceStart: Float = 0.10
    private static let footstepLowEvidenceLargeXConfidenceFull: Float = 0.26
    private static let footstepLowEvidenceLargeXCorrectionStartPixels: Float = 1.2
    private static let footstepLowEvidenceLargeXCorrectionFullPixels: Float = 4.5
    private static let footstepLowEvidenceLargeXMinimumScale: Float = 0.30
    private static let farFieldFootstepConfidenceFloorMax: Float = 0.24
    private static let farFieldFootstepConfidenceFloorStartPixels: Float = 0.45
    private static let farFieldFootstepConfidenceFloorFullPixels: Float = 3.4
    private static let farFieldFootstepVerticalConfidenceFloorMax: Float = 0.44
    private static let farFieldFootstepVerticalConfidenceFloorStartPixels: Float = 0.28
    private static let farFieldFootstepVerticalConfidenceFloorFullPixels: Float = 2.2
    private static let farFieldFootstepRollConfidenceFloorMax: Float = 0.30
    private static let farFieldFootstepRollConfidenceFloorStartDegrees: Float = 0.018
    private static let farFieldFootstepRollConfidenceFloorFullDegrees: Float = 0.11
    private static let farFieldStrideVerticalConfidenceFloorScale: Float = 0.78
    private static let farFieldStrideRollConfidenceFloorScale: Float = 0.84
    private static let strideWobbleWindowSeconds = 2.0
    private static let strideWobbleFullScalePixels: Float = 0.75
    private static let strideWobbleFullScaleDegrees: Float = 0.16
    private static let strideWobbleFullResponseScale: Float = 0.55
    private static let turnSmoothingFullScalePixels: Float = 2.0
    private static let maximumTurnSmoothingCorrectionAuthority: Float = 36.0
    private static let turnOwnershipFootstepXSuppression: Float = 1.0
    private static let turnOwnershipFootstepYSuppression: Float = 0.65
    private static let turnOwnershipFootstepRollSuppression: Float = 0.55
    private static let turnOwnershipStrideXSuppression: Float = 1.0
    private static let turnOwnershipStrideYSuppression: Float = 0.55
    private static let turnOwnershipStrideRollSuppression: Float = 0.50
    private static let turnOwnedWalkingXGateFloorMax: Float = 0.82
    private static let turnOwnedStrideXGateFloorScale: Float = 1.15
    private static let turnOwnedWalkingXGateFloorStartPixels: Float = 12.0
    private static let turnOwnedWalkingXGateFloorFullPixels: Float = 75.0
    private static let turnOwnedWalkingXMacroFadeStartPixels: Float = 48.0
    private static let turnOwnedWalkingXMacroFadeFullPixels: Float = 160.0
    private static let turnOwnedFarFieldXConfidenceFloorMax: Float = 0.50
    private static let turnOwnedFarFieldXConfidenceFloorStartPixels: Float = 1.0
    private static let turnOwnedFarFieldXConfidenceFloorFullPixels: Float = 10.0
    private static let turnOwnedFarFieldXMacroGateFloorMax: Float = 1.0
    private static let turnOwnedFarFieldStrideRescueConfidenceFloorMax: Float = 0.46
    private static let turnOwnedFarFieldStrideRescueBandStartPixels: Float = 1.1
    private static let turnOwnedFarFieldStrideRescueBandFullPixels: Float = 4.2
    private static let turnOwnedFarFieldStrideRescueSupportStart: Float = 0.16
    private static let turnOwnedFarFieldStrideRescueSupportFull: Float = 0.48
    private static let turnOwnedFarFieldStrideRescueWarpStart: Float = 0.55
    private static let turnOwnedFarFieldStrideRescueWarpFull: Float = 0.88
    private static let turnOwnedFarFieldStrideRescueTrackingStart: Float = 0.24
    private static let turnOwnedFarFieldStrideRescueTrackingFull: Float = 0.56
    private static let turnOwnedFarFieldStrideRescueFarFieldStart: Float = 0.04
    private static let turnOwnedFarFieldStrideRescueFarFieldFull: Float = 0.22
    private static let farFieldWalkingResidualContinuityStartPixels: Float = 0.75
    private static let farFieldWalkingResidualContinuityFullPixels: Float = 3.5
    private static let farFieldWalkingResidualContinuityBandStartPixels: Float = 2.0
    private static let farFieldWalkingResidualContinuityBandFullPixels: Float = 12.0
    private static let farFieldWalkingResidualContinuityMaximumResidualScale: Float = 0.92
    private static let turnOwnedFootstepXFineFadeStartPixels: Float = 28.0
    private static let turnOwnedFootstepXFineFadeFullPixels: Float = 72.0
    private static let turnOwnedFootstepXRescueConfidenceFloorMax: Float = 0.34
    private static let turnOwnedFootstepXRescueBandStartPixels: Float = 18.0
    private static let turnOwnedFootstepXRescueBandFullPixels: Float = 58.0
    private static let turnOwnedFootstepXRescueSupportStart: Float = 0.02
    private static let turnOwnedFootstepXRescueSupportFull: Float = 0.12
    private static let turnOwnedFootstepXRescueTurnEvidenceStart: Float = 0.48
    private static let turnOwnedFootstepXRescueTurnEvidenceFull: Float = 0.68
    private static let turnOwnedFootstepXRescueTurnEvidenceScale: Float = 0.85
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
    private static let farFieldWarpFineShakeDeadbandScale: Float = 0.012
    private static let farFieldWarpSubunitResponseLift: Float = 2.0
    private static let farFieldWarpSubunitResponseMax: Float = 1.0
    private static let farFieldMacroBlendConfidenceStart: Float = 0.04
    private static let farFieldMacroBlendConfidenceFull: Float = 0.22
    private static let farFieldWalkingBandBlendMax: Float = 0.34
    private static let farFieldWalkingBandBlendXScale: Float = 1.0
    private static let farFieldWalkingBandBlendYScale: Float = 1.0
    private static let farFieldWalkingBandBlendRollScale: Float = 1.0
    private static let farFieldWalkingBandConfidenceStart: Float = 0.05
    private static let farFieldWalkingBandConfidenceFull: Float = 0.28
    private static let farFieldWalkingBandTrackingStart: Float = 0.18
    private static let farFieldWalkingBandTrackingFull: Float = 0.56
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
    private static let lensShakeInnerWindowMinimumSeconds = 0.13
    private static let lensShakeOuterWindowMinimumSeconds = 0.44
    private static let lensShakeOuterWindowMaximumSeconds = 1.0
    private static let lensShakeMinimumSupport: Float = 0.08
    private static let lensShakeGlobalUnsafeSupport: Float = 0.35
    private static let lensShakePixelStartPixels: Float = 0.10
    private static let lensShakePixelFullPixels: Float = 0.85
    private static let lensShakeRollingGlobalXMaximumCorrection: Float = 1.4
    private static let lensShakeRollingGlobalYMaximumCorrection: Float = 8.0
    private static let lensShakeRollingGlobalPixelSupportFull: Float = 0.46
    private static let lensShakeRollingGlobalPixelUnsafeFull: Float = 0.82
    private static let lensShakeRollingGlobalMeshXSupportStart: Float = 0.42
    private static let lensShakeRollingGlobalMeshXSupportFull: Float = 0.86
    private static let lensShakeRollingGlobalMeshXResidualStart: Float = 0.42
    private static let lensShakeRollingGlobalMeshXResidualFull: Float = 3.20
    private static let lensShakeRollingGlobalMeshXDisagreementStart: Float = 24.0
    private static let lensShakeRollingGlobalMeshXDisagreementFull: Float = 64.0
    private static let lensShakeRollStartDegrees: Float = 0.002
    private static let lensShakeRollFullDegrees: Float = 0.030
    private static let lensShakeYawPitchStart: Float = 0.000006
    private static let lensShakeYawPitchFull: Float = 0.000055
    private static let lensShakeShearStart: Float = 0.000030
    private static let lensShakeShearFull: Float = 0.000320
    private static let lensShakePerspectiveStart: Float = 0.000010
    private static let lensShakePerspectiveFull: Float = 0.000095
    private static let lensShakePixelMaximumCorrection: Float = 3.4
    private static let sourceLensRidgePixelMaximumCorrection: Float = 7.2
    private static let sourceLensRidgeLineGlobalPixelScale: Float = 0.24
    private static let sourceLensRidgeLineGlobalPixelMaximumCorrection: Float = 2.8
    private static let sourceLensRidgeLinePlaybackPixelScale: Float = 0.12
    private static let sourceLensRidgeLinePlaybackMaximumCorrection: Float = 0.85
    private static let sourceLensRidgeLinePlaybackMaximumBlend: Float = 0.42
    private static let sourceLensRidgeLineGlobalSupportStart: Float = 0.10
    private static let sourceLensRidgeLineGlobalSupportFull: Float = 0.52
    private static let sourceLensRidgeLineGlobalResidualStart: Float = 0.35
    private static let sourceLensRidgeLineGlobalResidualFull: Float = 2.8
    private static let sourceLensRidgeLineGlobalEnvelopeStart: Float = 1.4
    private static let sourceLensRidgeLineGlobalEnvelopeFull: Float = 6.0
    private static let sourceLensRidgeLineGlobalEnvelopeSeconds: Double = 0.18
    private static let lensShakeCorrectionMinimumSmoothingSeconds: Double = 0.16
    private static let lensShakeRotationMaximumCorrectionDegrees: Float = 0.11
    private static let lensBandPulseSmoothingBlend: Float = 0.46
    private static let lensBandPulseSmoothingStartPixels: Float = 0.22
    private static let lensBandPulseSmoothingFullPixels: Float = 1.35
    private static let farFieldRigidRawReinforcementMaximumBlend: Float = 0.74
    private static let farFieldLowFrequencyRawReinforcementMaximumBlend: Float = 0.94
    private static let farFieldLowFrequencyPriorityStartSeconds: Float = 0.28
    private static let farFieldLowFrequencyPriorityFullSeconds: Float = 0.86
    private static let farFieldLowFrequencyMeshSuppressionScale: Float = 1.0
    private static let farFieldLowFrequencyTurnSuppressionRelief: Float = 0.65
    private static let farFieldShortWindowRigidYBoostStartSeconds: Float = 0.15
    private static let farFieldShortWindowRigidYBoostFullSeconds: Float = 0.055
    private static let farFieldShortWindowRigidYBoostMaximum: Float = 0.0
    private static let farFieldShortWindowDominantMeshYBlendMaximum: Float = 0.0
    private static let farFieldCoherentSlabMeshYBlendMaximum: Float = 0.0
    private static let farFieldParallaxWarpDampingDeltaStart: Float = 48.0
    private static let farFieldParallaxWarpDampingDeltaFull: Float = 96.0
    private static let farFieldParallaxWarpDampingOpposingStart: Float = 0.08
    private static let farFieldParallaxWarpDampingOpposingFull: Float = 0.18
    private static let farFieldParallaxWarpDampingTwoWayStart: Float = 0.08
    private static let farFieldParallaxWarpDampingTwoWayFull: Float = 0.38
    private static let farFieldParallaxWarpDampingMaximum: Float = 0.68
    private static let farFieldCoherentSlabYShapeStart: Float = 0.18
    private static let farFieldCoherentSlabYShapeFull: Float = 0.70
    private static let farFieldCoherentSlabYTwoWayStart: Float = 0.22
    private static let farFieldCoherentSlabYTwoWayFull: Float = 0.76
    private static let farFieldCoherentSlabYMeshDeltaStart: Float = 10.0
    private static let farFieldCoherentSlabYMeshDeltaFull: Float = 24.0
    private static let farFieldCoherentSlabXShapeStart: Float = 0.12
    private static let farFieldCoherentSlabXShapeFull: Float = 0.54
    private static let farFieldCoherentSlabXTwoWayStart: Float = 0.18
    private static let farFieldCoherentSlabXTwoWayFull: Float = 0.62
    private static let farFieldCoherentSlabXMeshDeltaStart: Float = 13.0
    private static let farFieldCoherentSlabXMeshDeltaFull: Float = 22.0
    private static let farFieldCoherentSlabXQuiverStart: Float = 0.24
    private static let farFieldCoherentSlabXQuiverFull: Float = 0.62
    private static let farFieldCoherentMeshBlendDeltaStart: Float = 8.0
    private static let farFieldCoherentMeshBlendDeltaFull: Float = 20.0
    private static let farFieldCoherentMeshBlendOpposingStart: Float = 0.06
    private static let farFieldCoherentMeshBlendOpposingFull: Float = 0.22
    private static let farFieldRigidOnlyGuardSupportStart: Float = 0.08
    private static let farFieldRigidOnlyGuardSupportFull: Float = 0.30
    private static let farFieldRigidOnlyGuardShapeStart: Float = 0.24
    private static let farFieldRigidOnlyGuardShapeFull: Float = 0.56
    private static let farFieldRigidOnlyGuardTwoWayStart: Float = 0.20
    private static let farFieldRigidOnlyGuardTwoWayFull: Float = 0.52
    private static let lensBandPulseSmoothingStartRadians: Float = 0.00035
    private static let lensBandPulseSmoothingFullRadians: Float = 0.0024
    private static let farFieldRigidShakeTwoWayRadiusFrames = 5
    private static let farFieldRigidShakeShapeStartPixels: Float = 0.10
    private static let farFieldRigidShakeShapeFullPixels: Float = 1.15
    private static let farFieldRigidShakeForwardBackwardStartPixels: Float = 0.08
    private static let farFieldRigidShakeForwardBackwardFullPixels: Float = 1.00
    private static let farFieldRigidShakeResidualStartPixels: Float = 0.08
    private static let farFieldRigidShakeResidualFullPixels: Float = 0.70
    private static let farFieldRigidDeltaCoherenceTopRidgeStartPixels: Float = 1.45
    private static let farFieldRigidDeltaCoherenceTopRidgeFullPixels: Float = 5.50
    private static let farFieldRigidDeltaCoherenceMidStartPixels: Float = 3.25
    private static let farFieldRigidDeltaCoherenceMidFullPixels: Float = 9.50
    private static let farFieldRigidDeltaCoherenceMotionStartPixels: Float = 0.22
    private static let farFieldRigidDeltaCoherenceMotionFullPixels: Float = 3.60
    static let farFieldMeshRows = 5
    static let farFieldMeshColumns = 9
    static let farFieldMeshBinCount = farFieldMeshRows * farFieldMeshColumns
    private static let farFieldMeshDominantWindowSecondsCandidates: [Double] = [
        1.0 / 20.0,
        1.0 / 12.0,
        1.0 / 8.0,
        1.0 / 6.0,
        1.0 / 4.0,
        1.0 / 3.0,
        1.0 / 2.0,
        2.0 / 3.0,
        1.0
    ]
    static let sourceLensShakeLocalBandCount = 3
    static let sourceLensShakeLocalColumnCount = 5
    static let sourceLensShakeLocalBinCount = sourceLensShakeLocalBandCount * sourceLensShakeLocalColumnCount
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
    private static let sharedPlaybackTrajectoryCacheLimit = 16
    private static let sharedPlaybackTrajectoryCacheCondition = NSCondition()
    private static var sharedPlaybackTrajectoryCaches: [PlaybackTrajectoryCacheKey: PlaybackTransformTrajectory] = [:]
    private static var sharedPlaybackTrajectoryCacheOrder: [PlaybackTrajectoryCacheKey] = []
    private static var sharedPlaybackTrajectoryPreparations: Set<PlaybackTrajectoryCacheKey> = []
    private static var sharedPlaybackTrajectoryPreparationCallbacks: [PlaybackTrajectoryCacheKey: [() -> Void]] = [:]
    private static let playbackTrajectoryPreparationQueue = DispatchQueue(
        label: "com.justadev.TokyoWalkingStabilizer.PlaybackTrajectoryPreparation",
        qos: .userInitiated
    )
    private static let playbackTrajectoryPixelRate: Float = 42.0
    private static let playbackTrajectoryMaximumPixelStep: Float = 0.68
    private static let playbackTrajectoryMinimumPixelStep: Float = 0.26
    private static let playbackTrajectoryRotationRate: Float = 2.4
    private static let playbackTrajectoryMaximumRotationStep: Float = 0.040
    private static let playbackTrajectoryMinimumRotationStep: Float = 0.012
    private static let playbackTrajectoryWarpRate: Float = 0.040
    private static let playbackTrajectoryMaximumWarpStep: Float = 0.00070
    private static let playbackTrajectoryMinimumWarpStep: Float = 0.00010
    private static let playbackTrajectoryRigidYSupportStart: Float = 0.55
    private static let playbackTrajectoryRigidYSupportFull: Float = 0.85
    private static let playbackTrajectoryRigidYShapeStart: Float = 0.72
    private static let playbackTrajectoryRigidYShapeFull: Float = 0.95
    private static let playbackTrajectoryRigidYTwoWayStart: Float = 0.70
    private static let playbackTrajectoryRigidYTwoWayFull: Float = 0.90
    private static let playbackTrajectoryRigidYCorrectionMatchStartPixels: Float = 0.05
    private static let playbackTrajectoryRigidYCorrectionMatchFullPixels: Float = 0.35
    private static let playbackTrajectoryFootstepAuthorityGateStart: Float = 0.18
    private static let playbackTrajectoryFootstepAuthorityGateFull: Float = 0.62
    private static let playbackTrajectoryFootstepStepScale: Float = 0.45
    private static let playbackTrajectoryFootstepPreservationMaxBlend: Float = 0.42
    private static let playbackTrajectoryFrameCadenceDespikeMinimumPixelFraction: Float = 0.00034
    private static let playbackTrajectoryFrameCadenceDespikeMinimumPixels: Float = 0.55
    private static let playbackTrajectoryFrameCadenceDespikeMadMultiplier: Float = 2.2
    private static let playbackTrajectoryFrameCadenceDespikeMaximumBlend: Float = 0.82
    private static let playbackTrajectoryFrameCadenceDespikeWindowFrames = 7
    private static let playbackTrajectoryFrameCadenceDespikeMinimumRotationDegrees: Float = 0.010
    private static let playbackTrajectoryLandingShockInnerWindowSeconds = 0.09
    private static let playbackTrajectoryLandingShockOuterWindowSeconds = 0.42
    private static let playbackTrajectoryLandingShockLocalNoiseWindowSeconds = 0.28
    private static let playbackTrajectoryLandingShockMinimumPixelFraction: Float = 0.00034
    private static let playbackTrajectoryLandingShockMinimumPixels: Float = 0.42
    private static let playbackTrajectoryLandingShockMadMultiplier: Float = 2.4
    private static let playbackTrajectoryLandingShockMaximumBlend: Float = 0.68
    private static let playbackTrajectoryLandingShockMaximumCorrectionPixels: Float = 1.05
    private static let playbackTrajectoryLandingShockMaximumCorrectionPixelFraction: Float = 0.0012
    private static let playbackTrajectoryLandingShockMinimumRotationDegrees: Float = 0.012
    private static let playbackTrajectoryLandingShockMaximumCorrectionDegrees: Float = 0.038
    private static let playbackTrajectoryLandingShockTurnSuppressionStart: Float = 0.52
    private static let playbackTrajectoryLandingShockTurnSuppressionFull: Float = 0.88
    private static let playbackTrajectoryVelocityCollapseMinimumPixels: Float = 0.32
    private static let playbackTrajectoryVelocityCollapseMinimumPixelFraction: Float = 0.00024
    private static let playbackTrajectoryVelocityCollapseMinimumDeviationScale: Float = 0.32
    private static let playbackTrajectoryVelocityCollapseMaximumCorrectionPixels: Float = 0.90
    private static let playbackTrajectoryVelocityCollapseMaximumCorrectionPixelFraction: Float = 0.00082
    private static let playbackTrajectoryVelocityCollapseMaximumStepRatio: Float = 0.34
    private static let playbackTrajectoryVelocityCollapseMinimumFarFieldSupport: Float = 0.15
    private static let playbackTrajectoryVelocityCollapseMaximumBlend: Float = 0.78
    private static let playbackTrajectoryMicroJitterHalfWindowSeconds = 0.18
    private static let playbackTrajectoryMicroJitterMinimumPixels: Float = 0.08
    private static let playbackTrajectoryMicroJitterFullPixels: Float = 0.45
    private static let playbackTrajectoryMicroJitterMaximumBlend: Float = 0.65
    private static let playbackTrajectoryMicroJitterMaximumCorrectionPixels: Float = 0.85
    private static let playbackTrajectoryMicroJitterMaximumCorrectionPixelFraction: Float = 0.00085
    private static let playbackTrajectoryHorizontalMicroJitterTurnHardGateConfidence: Float = 0.05
    private static let playbackTrajectoryFootstepPreservationStartPixels: Float = 0.38
    private static let playbackTrajectoryFootstepPreservationFullPixels: Float = 1.65
    private static let playbackTrajectoryFootstepRotationPreservationStartDegrees: Float = 0.020
    private static let playbackTrajectoryFootstepRotationPreservationFullDegrees: Float = 0.10
    private static let playbackTrajectoryTurnOwnedXPreservationFarFieldFloorMax: Float = 0.10
    private static let playbackTrajectoryTurnOwnedXPreservationFarFieldStart: Float = 0.45
    private static let playbackTrajectoryTurnOwnedXPreservationFarFieldFull: Float = 0.85
    private static let playbackTrajectoryFarFieldMacroDespikeInnerWindowSeconds = 0.12
    private static let playbackTrajectoryFarFieldMacroDespikeOuterWindowSeconds = 0.72
    private static let playbackTrajectoryFarFieldMacroDespikeLocalWindowSeconds = 0.36
    private static let playbackTrajectoryFarFieldMacroDespikeMinimumPixels: Float = 0.42
    private static let playbackTrajectoryFarFieldMacroDespikeMinimumRotationDegrees: Float = 0.012
    private static let playbackTrajectoryFarFieldMacroDespikeMadMultiplier: Float = 1.55
    private static let playbackTrajectoryFarFieldMacroDespikeMaximumBlend: Float = 0.82
    private static let playbackTrajectoryFarFieldMacroDespikeMaximumCorrectionPixels: Float = 5.0
    private static let playbackTrajectoryFarFieldMacroDespikeMaximumCorrectionDegrees: Float = 0.055
    private static let playbackTrajectoryMicroBandYSmoothingHalfWindowSeconds = 0.08
    private static let playbackTrajectoryAlgorithmRevision: UInt64 = 96
    private enum MotionPathKind: Hashable {
        case footstepX
        case footstepY
        case footstepRoll
        case farFieldX
        case farFieldY
        case farFieldRoll
        case yaw
        case pitch
        case shearX
        case shearY
        case perspectiveX
        case perspectiveY
        case lensBandTopX
        case lensBandTopY
        case lensBandTopColumnX
        case lensBandTopColumnY
        case lensBandTopRowPhaseX
        case lensBandTopRowPhaseY
        case lensBandTopLocalRoll
        case lensBandRidgeX
        case lensBandRidgeY
        case lensBandRidgeColumnX
        case lensBandRidgeColumnY
        case lensBandRidgeRowPhaseX
        case lensBandRidgeRowPhaseY
        case lensBandRidgeLocalRoll
        case lensBandMidX
        case lensBandMidY
        case lensBandMidColumnX
        case lensBandMidColumnY
        case lensBandMidRowPhaseX
        case lensBandMidRowPhaseY
        case lensBandMidLocalRoll
        case farFieldRigidShakeX
        case farFieldRigidShakeY
        case farFieldRigidShakeRoll
        case farFieldMeshX(Int)
        case farFieldMeshY(Int)
        case sourceLensShakeRidgeY
        case sourceLensShakeRidgeLineY
        case sourceLensShakeLocalX(Int)
        case sourceLensShakeLocalY(Int)
        case sourceLensShakeLocalSupport(Int)

        var usesCachedPathSlice: Bool {
            switch self {
            case .farFieldMeshX, .farFieldMeshY, .sourceLensShakeLocalX, .sourceLensShakeLocalY, .sourceLensShakeLocalSupport:
                return true
            default:
                return false
            }
        }
    }

    private enum LocalAverageSourceRole: Hashable {
        case footstepTurnBaseline
        case footstepStrideCleaned
        case footstepBroad
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
        let farFieldWarp: UInt64
        let turnSmoothingZoom: UInt64
        let limitFootstepContinuity: Bool
        let includeFarFieldWarp: Bool
    }

    private struct FarFieldWarpComponentStrengths {
        let yawPitch: Float
        let shear: Float
        let perspective: Float

        var isActive: Bool {
            yawPitch > 0.0 || shear > 0.0 || perspective > 0.0
        }
    }

    private struct SourceSpaceLensShakeCorrection {
        var pixelOffset: vector_float2 = vector_float2(0.0, 0.0)
        var rotationDegrees: Float = 0.0
        var yawPitch: vector_float2 = vector_float2(0.0, 0.0)
        var shear: vector_float2 = vector_float2(0.0, 0.0)
        var perspective: vector_float2 = vector_float2(0.0, 0.0)
        var score: Float = 0.0
        var support: Float = 0.0
        var windowFrames: Float = 0.0
        var windowSeconds: Float = 0.0
        var axisMask: Int32 = 0
        var reasonCode: Int32 = 0
        var rollingShutterCandidate: Float = 0.0
        var bandTopOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRidgeOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandMidOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRawTopOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRawRidgeOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRawMidOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandPulseDeltaTopOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandPulseDeltaRidgeOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandPulseDeltaMidOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandPulseWindowFrames: Float = 0.0
        var bandTopColumnOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRidgeColumnOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandMidColumnOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandTopRowPhaseOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandRidgeRowPhaseOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandMidRowPhaseOffset: vector_float2 = vector_float2(0.0, 0.0)
        var bandTopLocalRoll: Float = 0.0
        var bandRidgeLocalRoll: Float = 0.0
        var bandMidLocalRoll: Float = 0.0
        var bandWarpSupport: Float = 0.0
        var bandWarpApplied: Float = 0.0
        var bandRollingShutterScore: Float = 0.0
        var bandModelMask: Int32 = 0
        var farFieldRigidOffset: vector_float2 = vector_float2(0.0, 0.0)
        var farFieldRigidSupport: Float = 0.0
        var farFieldRigidApplied: Float = 0.0
        var farFieldRigidShapeConsistency: Float = 0.0
        var farFieldRigidForwardBackwardConsistency: Float = 0.0
        var farFieldRigidLocalWarpSuppressed: Float = 0.0
        var farFieldRigidXQuiverScore: Float = 0.0
        var farFieldRigidXBeforeLimiter: Float = 0.0
        var farFieldRigidXAfterLimiter: Float = 0.0
        var farFieldRigidRollResidual: Float = 0.0
        var farFieldRigidRollSupport: Float = 0.0
        var farFieldRigidGlobalYOffset: Float = 0.0
        var farFieldRigidGlobalRollDegrees: Float = 0.0
        var farFieldRigidRollApplied: Float = 0.0
        var farFieldMeshOffset: vector_float2 = vector_float2(0.0, 0.0)
        var farFieldMeshSupport: Float = 0.0
        var farFieldMeshBlend: Float = 0.0
        var farFieldMeshAvailable: Float = 0.0
        var farFieldMeshSupportedBins: Float = 0.0
        var farFieldMeshMaxBinDelta: Float = 0.0
        var farFieldMeshOpposingBins: Float = 0.0
        var farFieldMeshDominantWindowFrames: Float = 0.0
        var farFieldMeshDominantWindowSeconds: Float = 0.0
        var farFieldMeshDominantSupport: Float = 0.0
        var farFieldMeshDominantCell: Float = -1.0
        var sourceRidgeOffset: vector_float2 = vector_float2(0.0, 0.0)
        var sourceRidgeSupport: Float = 0.0
        var sourceRidgeApplied: Float = 0.0
        var sourceRidgeLineResidual: vector_float2 = vector_float2(0.0, 0.0)
        var sourceRidgeLineOffset: vector_float2 = vector_float2(0.0, 0.0)
        var sourceRidgeLineSupport: Float = 0.0
        var sourceRidgeLineBandSupported: Float = 0.0
        var sourceRidgeLineApplied: Float = 0.0
        var localTopLeftOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localTopCenterOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localTopRightOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localRidgeLeftOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localRidgeCenterOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localRidgeRightOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localMidLeftOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localMidCenterOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localMidRightOffset: vector_float2 = vector_float2(0.0, 0.0)
        var localSupport: Float = 0.0
        var localApplied: Float = 0.0
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
        let preparedPathFingerprint: UInt64
    }

    private struct PlaybackTrajectoryCacheKey: Hashable {
        let algorithmRevision: UInt64
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
        let preparedPathFingerprint: UInt64
        let microJitterX: UInt64
        let microJitterY: UInt64
        let microJitterRotation: UInt64
        let strideWobbleX: UInt64
        let strideWobbleY: UInt64
        let strideWobbleRotation: UInt64
        let farFieldWarp: UInt64
        let turnSmoothingZoom: UInt64
    }

    private static func combinePreparedPathHash(_ value: UInt64, into hash: inout UInt64) {
        hash ^= value
        hash &*= 1_099_511_628_211
    }

    private static func preparedPathFingerprint(for analysis: StabilizerPreparedAnalysis) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        combinePreparedPathHash(UInt64(analysis.frames.count), into: &hash)
        combinePreparedPathHash(UInt64(analysis.qualityModel == .eventAnalyzerCache ? 1 : 0), into: &hash)

        func sampledIndices(count: Int) -> [Int] {
            guard count > 0 else {
                return []
            }
            guard count > 33 else {
                return Array(0..<count)
            }
            let last = count - 1
            var indices = Set<Int>()
            for sample in 0..<33 {
                let rawIndex = Int(Darwin.round((Double(sample) / 32.0) * Double(last)))
                indices.insert(max(0, min(last, rawIndex)))
            }
            return indices.sorted()
        }

        func combineFloats(_ values: [Float]) {
            combinePreparedPathHash(UInt64(values.count), into: &hash)
            for index in sampledIndices(count: values.count) where values.indices.contains(index) {
                combinePreparedPathHash(UInt64(values[index].bitPattern), into: &hash)
            }
        }

        func combineInt32s(_ values: [Int32]) {
            combinePreparedPathHash(UInt64(values.count), into: &hash)
            for index in sampledIndices(count: values.count) where values.indices.contains(index) {
                combinePreparedPathHash(UInt64(UInt32(bitPattern: values[index])), into: &hash)
            }
        }

        combineFloats(analysis.residuals)
        combineFloats(analysis.rollMotion)
        combineFloats(analysis.pathX)
        combineFloats(analysis.pathY)
        combineFloats(analysis.pathRoll)
        combineFloats(analysis.farFieldPathX)
        combineFloats(analysis.farFieldPathY)
        combineFloats(analysis.farFieldPathRoll)
        combineFloats(analysis.farFieldConfidence)
        combineFloats(analysis.footstepPathX)
        combineFloats(analysis.footstepPathY)
        combineFloats(analysis.footstepPathRoll)
        combineFloats(analysis.pathYaw)
        combineFloats(analysis.pathPitch)
        combineFloats(analysis.pathShearX)
        combineFloats(analysis.pathShearY)
        combineFloats(analysis.pathPerspectiveX)
        combineFloats(analysis.pathPerspectiveY)
        combineFloats(analysis.lensBandTopPathX)
        combineFloats(analysis.lensBandTopPathY)
        combineFloats(analysis.lensBandTopColumnPathX)
        combineFloats(analysis.lensBandTopColumnPathY)
        combineFloats(analysis.lensBandTopRowPhasePathX)
        combineFloats(analysis.lensBandTopRowPhasePathY)
        combineFloats(analysis.lensBandTopLocalRollPath)
        combineFloats(analysis.lensBandRidgePathX)
        combineFloats(analysis.lensBandRidgePathY)
        combineFloats(analysis.lensBandRidgeColumnPathX)
        combineFloats(analysis.lensBandRidgeColumnPathY)
        combineFloats(analysis.lensBandRidgeRowPhasePathX)
        combineFloats(analysis.lensBandRidgeRowPhasePathY)
        combineFloats(analysis.lensBandRidgeLocalRollPath)
        combineFloats(analysis.lensBandMidPathX)
        combineFloats(analysis.lensBandMidPathY)
        combineFloats(analysis.lensBandMidColumnPathX)
        combineFloats(analysis.lensBandMidColumnPathY)
        combineFloats(analysis.lensBandMidRowPhasePathX)
        combineFloats(analysis.lensBandMidRowPhasePathY)
        combineFloats(analysis.lensBandMidLocalRollPath)
        combineFloats(analysis.lensBandTopConfidence)
        combineFloats(analysis.lensBandRidgeConfidence)
        combineFloats(analysis.lensBandMidConfidence)
        combineFloats(analysis.lensBandConfidence)
        combineFloats(analysis.farFieldRigidShakePathX)
        combineFloats(analysis.farFieldRigidShakePathY)
        combineFloats(analysis.farFieldRigidShakePathRoll)
        combineFloats(analysis.farFieldRigidShakeSupport)
        combineFloats(analysis.farFieldRigidShakeRollSupport)
        combineFloats(analysis.farFieldRigidShakeShapeConsistency)
        combineFloats(analysis.farFieldRigidShakeForwardBackwardConsistency)
        combinePreparedPathHash(UInt64(analysis.farFieldMeshRows), into: &hash)
        combinePreparedPathHash(UInt64(analysis.farFieldMeshColumns), into: &hash)
        combineFloats(analysis.farFieldMeshPathX)
        combineFloats(analysis.farFieldMeshPathY)
        combineFloats(analysis.farFieldMeshSupport)
        combineFloats(analysis.farFieldMeshDominantWindowFrames)
        combineFloats(analysis.farFieldMeshDominantWindowSeconds)
        combineFloats(analysis.farFieldMeshDominantSupport)
        for value in analysis.farFieldMeshDominantCell {
            combinePreparedPathHash(UInt64(bitPattern: Int64(value)), into: &hash)
        }
        combineFloats(analysis.sourceLensShakeRidgePathY)
        combineFloats(analysis.sourceLensShakeRidgeSupport)
        combineFloats(analysis.sourceLensShakeRidgeLinePathY)
        combineFloats(analysis.sourceLensShakeRidgeLineSupport)
        combinePreparedPathHash(UInt64(analysis.sourceLensShakeLocalBinCount), into: &hash)
        combineFloats(analysis.sourceLensShakeLocalPathX)
        combineFloats(analysis.sourceLensShakeLocalPathY)
        combineFloats(analysis.sourceLensShakeLocalSupport)
        combineFloats(analysis.analysisConfidence)
        combineFloats(analysis.warpConfidence)
        combineInt32s(analysis.acceptedBlockCounts)
        combineInt32s(analysis.totalBlockCounts)
        combineFloats(analysis.blurAmounts)
        combineInt32s(analysis.searchRadiusHitCounts)
        combineInt32s(analysis.searchRadiusTotalCounts)
        return hash
    }

    private struct PlaybackTransformTrajectory {
        let times: [Double]
        let transforms: [StabilizerAutoTransform]
        let outputSize: vector_float2

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

        func transform(at seconds: Double, outputSize requestedOutputSize: vector_float2) -> StabilizerAutoTransform {
            AutoStabilizationEstimator.scalePixelTransform(
                transform(at: seconds),
                from: outputSize,
                to: requestedOutputSize
            )
        }
    }

    private struct PlaybackTrajectoryDespikeResult {
        let transforms: [StabilizerAutoTransform]
        let pixelFrameCount: Int
        let rotationFrameCount: Int
        let maximumPixelDeviation: Float
        let maximumRotationDeviation: Float
    }

    private struct PlaybackTrajectoryComponentDiagnostics {
        var maximumFinalStepPixels: Float = 0.0
        var maximumFinalStepFrameIndex: Int = 0
        var maximumFinalStepSeconds: Double = 0.0
        var maximumMacroStepPixels: Float = 0.0
        var maximumMicroStepPixels: Float = 0.0
        var maximumStrideStepPixels: Float = 0.0
        var maximumTurnStepPixels: Float = 0.0
        var maximumWarpStep: Float = 0.0
        var maximumRotationStepDegrees: Float = 0.0

        var maximumFinalJerkPixels: Float = 0.0
        var maximumFinalJerkFrameIndex: Int = 0
        var maximumFinalJerkSeconds: Double = 0.0
        var maximumMacroJerkPixels: Float = 0.0
        var maximumMicroJerkPixels: Float = 0.0
        var maximumStrideJerkPixels: Float = 0.0
        var maximumTurnJerkPixels: Float = 0.0
        var maximumWarpJerk: Float = 0.0
        var maximumRotationJerkDegrees: Float = 0.0
    }

    struct PlaybackTrajectorySampleDiagnostic {
        let lowerIndex: Int
        let upperIndex: Int
        let lowerTime: Double
        let upperTime: Double
        let fraction: Float
        let lowerFingerprint: String
        let upperFingerprint: String
        let transform: StabilizerAutoTransform
    }

    private struct AdaptiveXTurnTiming {
        let travelPixels: Float
        let windowSeconds: Double
        let active: Bool
    }

    private struct TurnOwnershipWindowStats {
        let range: Range<Int>
        let positiveTravel: Float
        let negativeTravel: Float
        let totalTravel: Float
        let endpointDelta: Float
        let dominantTravel: Float
        let dominantRatio: Float
        let endpointRatio: Float
        let monotonicStart: Float
        let monotonicTravel: Float
        let direction: Float
        let firstTime: Double
        let lastTime: Double
        let weightedAverage: Float
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
        private var pathValueSlices: [MotionPathKind: [Float]] = [:]
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
                farFieldWarp: strengths.farFieldWarp.bitPattern,
                turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern,
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
            let values = pathValues(kind, analysis: analysis)
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
            let values = pathValues(kind, analysis: analysis)
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

        func pathValues(_ kind: MotionPathKind, analysis: StabilizerPreparedAnalysis) -> [Float] {
            guard kind.usesCachedPathSlice else {
                return AutoStabilizationEstimator.values(for: kind, analysis: analysis)
            }
            lock.lock()
            if let cached = pathValueSlices[kind] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let values = AutoStabilizationEstimator.values(for: kind, analysis: analysis)

            lock.lock()
            if pathValueSlices[kind] == nil {
                pathValueSlices[kind] = values
            }
            let stored = pathValueSlices[kind] ?? values
            lock.unlock()
            return stored
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
            lastPathRoll: lastPathRoll.bitPattern,
            preparedPathFingerprint: preparedPathFingerprint(for: analysis)
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
        case .farFieldX:
            return analysis.farFieldPathX
        case .farFieldY:
            return analysis.farFieldPathY
        case .farFieldRoll:
            return analysis.farFieldPathRoll
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
        case .lensBandTopX:
            return analysis.lensBandTopPathX
        case .lensBandTopY:
            return analysis.lensBandTopPathY
        case .lensBandTopColumnX:
            return analysis.lensBandTopColumnPathX
        case .lensBandTopColumnY:
            return analysis.lensBandTopColumnPathY
        case .lensBandTopRowPhaseX:
            return analysis.lensBandTopRowPhasePathX
        case .lensBandTopRowPhaseY:
            return analysis.lensBandTopRowPhasePathY
        case .lensBandTopLocalRoll:
            return analysis.lensBandTopLocalRollPath
        case .lensBandRidgeX:
            return analysis.lensBandRidgePathX
        case .lensBandRidgeY:
            return analysis.lensBandRidgePathY
        case .lensBandRidgeColumnX:
            return analysis.lensBandRidgeColumnPathX
        case .lensBandRidgeColumnY:
            return analysis.lensBandRidgeColumnPathY
        case .lensBandRidgeRowPhaseX:
            return analysis.lensBandRidgeRowPhasePathX
        case .lensBandRidgeRowPhaseY:
            return analysis.lensBandRidgeRowPhasePathY
        case .lensBandRidgeLocalRoll:
            return analysis.lensBandRidgeLocalRollPath
        case .lensBandMidX:
            return analysis.lensBandMidPathX
        case .lensBandMidY:
            return analysis.lensBandMidPathY
        case .lensBandMidColumnX:
            return analysis.lensBandMidColumnPathX
        case .lensBandMidColumnY:
            return analysis.lensBandMidColumnPathY
        case .lensBandMidRowPhaseX:
            return analysis.lensBandMidRowPhasePathX
        case .lensBandMidRowPhaseY:
            return analysis.lensBandMidRowPhasePathY
        case .lensBandMidLocalRoll:
            return analysis.lensBandMidLocalRollPath
        case .farFieldRigidShakeX:
            return analysis.farFieldRigidShakePathX
        case .farFieldRigidShakeY:
            return analysis.farFieldRigidShakePathY
        case .farFieldRigidShakeRoll:
            return analysis.farFieldRigidShakePathRoll
        case .farFieldMeshX(let bin):
            return farFieldMeshPathSlice(analysis.farFieldMeshPathX, bin: bin, frameCount: analysis.frames.count)
        case .farFieldMeshY(let bin):
            return farFieldMeshPathSlice(analysis.farFieldMeshPathY, bin: bin, frameCount: analysis.frames.count)
        case .sourceLensShakeRidgeY:
            return analysis.sourceLensShakeRidgePathY
        case .sourceLensShakeRidgeLineY:
            return analysis.sourceLensShakeRidgeLinePathY
        case .sourceLensShakeLocalX(let bin):
            return localLensShakePathSlice(analysis.sourceLensShakeLocalPathX, bin: bin, frameCount: analysis.frames.count)
        case .sourceLensShakeLocalY(let bin):
            return localLensShakePathSlice(analysis.sourceLensShakeLocalPathY, bin: bin, frameCount: analysis.frames.count)
        case .sourceLensShakeLocalSupport(let bin):
            return localLensShakePathSlice(analysis.sourceLensShakeLocalSupport, bin: bin, frameCount: analysis.frames.count)
        }
    }

    private static func localLensShakePathSlice(_ values: [Float], bin: Int, frameCount: Int) -> [Float] {
        guard bin >= 0, bin < sourceLensShakeLocalBinCount, frameCount > 0 else {
            return []
        }
        let start = bin * frameCount
        let end = start + frameCount
        guard start >= 0, end <= values.count else {
            return []
        }
        return Array(values[start..<end])
    }

    private static func farFieldMeshPathSlice(_ values: [Float], bin: Int, frameCount: Int) -> [Float] {
        guard bin >= 0, bin < farFieldMeshBinCount, frameCount > 0 else {
            return []
        }
        let start = bin * frameCount
        let end = start + frameCount
        guard start >= 0, end <= values.count else {
            return []
        }
        return Array(values[start..<end])
    }

    private static func farFieldMeshBandRanges() -> [(Float, Float)] {
        [
            (0.04, 0.16),
            (0.13, 0.25),
            (0.22, 0.34),
            (0.31, 0.43),
            (0.40, 0.52)
        ]
    }

    private static func farFieldMeshColumnRanges() -> [(Float, Float)] {
        [
            (0.00, 0.14),
            (0.10, 0.26),
            (0.22, 0.38),
            (0.34, 0.50),
            (0.46, 0.62),
            (0.58, 0.74),
            (0.70, 0.86),
            (0.82, 0.98),
            (0.90, 1.00)
        ]
    }

    private struct FarFieldMeshWindowCandidate {
        let frames: Int
        let seconds: Float
    }

    private struct FarFieldMeshDominantWindows {
        let windowFrames: [Float]
        let windowSeconds: [Float]
        let support: [Float]
        let cell: [Int32]
    }

    private static func farFieldMeshWindowCandidates(frameStepSeconds: Double) -> [FarFieldMeshWindowCandidate] {
        let safeFrameStep = max(1.0 / 240.0, min(1.0, frameStepSeconds))
        let fps = max(1.0, min(240.0, 1.0 / safeFrameStep))
        var maximumFrames = max(3, Int(floor(fps)))
        if maximumFrames % 2 == 0 {
            maximumFrames -= 1
        }
        var seen = Set<Int>()
        var candidates: [FarFieldMeshWindowCandidate] = []
        for seconds in farFieldMeshDominantWindowSecondsCandidates {
            let targetFrames = seconds * fps
            var frameCount = max(3, Int(targetFrames.rounded()))
            if frameCount % 2 == 0 {
                frameCount += 1
            }
            if frameCount > maximumFrames {
                frameCount = maximumFrames
            }
            if frameCount < 3 {
                frameCount = 3
            }
            guard seen.insert(frameCount).inserted else {
                continue
            }
            candidates.append(FarFieldMeshWindowCandidate(
                frames: frameCount,
                seconds: Float(Double(frameCount) / fps)
            ))
        }
        return candidates.sorted { $0.frames < $1.frames }
    }

    private static func farFieldMeshDominantWindows(
        frames: [StabilizerAnalysisFrame],
        pathX: [Float],
        pathY: [Float],
        support: [Float],
        rows: Int,
        columns: Int
    ) -> FarFieldMeshDominantWindows {
        let frameCount = frames.count
        guard frameCount > 0 else {
            return FarFieldMeshDominantWindows(windowFrames: [], windowSeconds: [], support: [], cell: [])
        }
        let frameStepSeconds = representativeFrameStepSeconds(frames: frames)
        let candidates = farFieldMeshWindowCandidates(frameStepSeconds: frameStepSeconds)
        let defaultCandidate = candidates.first ?? FarFieldMeshWindowCandidate(frames: 3, seconds: Float(frameStepSeconds * 3.0))
        var dominantWindowFrames = Array(repeating: Float(defaultCandidate.frames), count: frameCount)
        var dominantWindowSeconds = Array(repeating: defaultCandidate.seconds, count: frameCount)
        var dominantSupport = Array(repeating: Float(0.0), count: frameCount)
        var dominantCell = Array(repeating: Int32(-1), count: frameCount)
        let binCount = rows * columns
        guard rows == farFieldMeshRows,
              columns == farFieldMeshColumns,
              pathX.count == frameCount * binCount,
              pathY.count == frameCount * binCount,
              support.count == frameCount * binCount
        else {
            return FarFieldMeshDominantWindows(
                windowFrames: dominantWindowFrames,
                windowSeconds: dominantWindowSeconds,
                support: dominantSupport,
                cell: dominantCell
            )
        }

        func meshValue(_ values: [Float], bin: Int, index: Int) -> Float {
            values[(bin * frameCount) + index]
        }

        func timingSupport(center: Int, radius: Int) -> Float {
            guard radius > 0,
                  frames.indices.contains(center - radius),
                  frames.indices.contains(center + radius)
            else {
                return 0.0
            }
            let expected = frameStepSeconds
            var maximumError = 0.0
            let lower = max(1, center - radius + 1)
            let upper = min(frameCount - 1, center + radius)
            guard lower <= upper else {
                return 0.0
            }
            for index in lower...upper {
                let delta = frames[index].time - frames[index - 1].time
                maximumError = max(maximumError, abs(delta - expected))
            }
            let normalizedError = Float(maximumError / max(expected, 1.0e-6))
            return 1.0 - confidenceRamp(normalizedError, start: 0.08, full: 0.34)
        }

        for center in 0..<frameCount {
            let blurGate = blurEvidenceQuality(frames[center].blurAmount)
            var bestScore = Float(0.0)
            for candidate in candidates {
                let radius = max(1, candidate.frames / 2)
                guard center - radius >= 0,
                      center + radius < frameCount
                else {
                    continue
                }
                let ptsGate = timingSupport(center: center, radius: radius)
                let shortWindowGate: Float
                if candidate.seconds <= Float(1.0 / 12.0) {
                    shortWindowGate = ptsGate * blurGate
                } else if candidate.seconds <= Float(1.0 / 8.0) {
                    shortWindowGate = min(ptsGate, blurGate)
                } else {
                    shortWindowGate = (ptsGate * 0.65) + (blurGate * 0.35)
                }
                guard shortWindowGate > 0.0 else {
                    continue
                }
                let leftTime = frames[center - radius].time
                let rightTime = frames[center + radius].time
                let centerTime = frames[center].time
                let denominator = max(1.0e-6, rightTime - leftTime)
                let fraction = Float(min(max((centerTime - leftTime) / denominator, 0.0), 1.0))
                for bin in 0..<binCount {
                    let leftX = meshValue(pathX, bin: bin, index: center - radius)
                    let centerX = meshValue(pathX, bin: bin, index: center)
                    let rightX = meshValue(pathX, bin: bin, index: center + radius)
                    let leftY = meshValue(pathY, bin: bin, index: center - radius)
                    let centerY = meshValue(pathY, bin: bin, index: center)
                    let rightY = meshValue(pathY, bin: bin, index: center + radius)
                    let baselineX = leftX + ((rightX - leftX) * fraction)
                    let baselineY = leftY + ((rightY - leftY) * fraction)
                    let residual = simd_length(vector_float2(centerX - baselineX, centerY - baselineY))
                    let supportGate = confidenceRamp(meshValue(support, bin: bin, index: center), start: 0.08, full: 0.38)
                    let evidence = confidenceRamp(residual, start: 0.035, full: 0.58) * supportGate * shortWindowGate
                    if evidence > bestScore {
                        bestScore = evidence
                        dominantWindowFrames[center] = Float(candidate.frames)
                        dominantWindowSeconds[center] = candidate.seconds
                        dominantSupport[center] = clamp(evidence, min: 0.0, max: 1.0)
                        dominantCell[center] = Int32(bin)
                    }
                }
            }
        }

        return FarFieldMeshDominantWindows(
            windowFrames: dominantWindowFrames,
            windowSeconds: dominantWindowSeconds,
            support: dominantSupport,
            cell: dominantCell
        )
    }

    struct FarFieldRigidShakePreparedPaths {
        let pathX: [Float]
        let pathY: [Float]
        let pathRoll: [Float]
        let support: [Float]
        let rollSupport: [Float]
        let shapeConsistency: [Float]
        let forwardBackwardConsistency: [Float]
    }

    static func farFieldRigidShakePreparedPaths(
        topX: [Float],
        topY: [Float],
        ridgeX: [Float],
        ridgeY: [Float],
        midX: [Float],
        midY: [Float],
        rollDegrees: [Float],
        topConfidence: [Float],
        ridgeConfidence: [Float],
        midConfidence: [Float]
    ) -> FarFieldRigidShakePreparedPaths {
        let frameCount = [
            topX.count, topY.count, ridgeX.count, ridgeY.count, midX.count, midY.count,
            rollDegrees.count,
            topConfidence.count, ridgeConfidence.count, midConfidence.count
        ].min() ?? 0
        guard frameCount > 0 else {
            return FarFieldRigidShakePreparedPaths(pathX: [], pathY: [], pathRoll: [], support: [], rollSupport: [], shapeConsistency: [], forwardBackwardConsistency: [])
        }

        var pathX = Array(repeating: Float(0.0), count: frameCount)
        var pathY = Array(repeating: Float(0.0), count: frameCount)
        var pathRoll = Array(repeating: Float(0.0), count: frameCount)
        var support = Array(repeating: Float(0.0), count: frameCount)
        var rollSupport = Array(repeating: Float(0.0), count: frameCount)
        var shapeConsistency = Array(repeating: Float(0.0), count: frameCount)
        var forwardBackwardConsistency = Array(repeating: Float(0.0), count: frameCount)

        for index in 0..<frameCount {
            let commonX = (topX[index] * 0.25) + (ridgeX[index] * 0.50) + (midX[index] * 0.25)
            let commonY = (topY[index] * 0.25) + (ridgeY[index] * 0.50) + (midY[index] * 0.25)
            pathX[index] = commonX
            pathY[index] = commonY
            pathRoll[index] = rollDegrees[index]

            let topDelta = hypotf(topX[index] - commonX, topY[index] - commonY)
            let ridgeDelta = hypotf(ridgeX[index] - commonX, ridgeY[index] - commonY)
            let midDelta = hypotf(midX[index] - commonX, midY[index] - commonY)
            let shapeDisagreement = max(topDelta, max(ridgeDelta, midDelta))
            let shape = 1.0 - confidenceRamp(
                shapeDisagreement,
                start: farFieldRigidShakeShapeStartPixels,
                full: farFieldRigidShakeShapeFullPixels
            )
            shapeConsistency[index] = clamp(shape, min: 0.0, max: 1.0)
        }

        let radius = farFieldRigidShakeTwoWayRadiusFrames
        guard frameCount > radius * 2 else {
            return FarFieldRigidShakePreparedPaths(
                pathX: pathX,
                pathY: pathY,
                pathRoll: pathRoll,
                support: support,
                rollSupport: rollSupport,
                shapeConsistency: shapeConsistency,
                forwardBackwardConsistency: forwardBackwardConsistency
            )
        }

        for index in radius..<(frameCount - radius) {
            let forwardX = pathX[index] - ((2.0 * pathX[index - 1]) - pathX[index - 2])
            let forwardY = pathY[index] - ((2.0 * pathY[index - 1]) - pathY[index - 2])
            let backwardX = pathX[index] - ((2.0 * pathX[index + 1]) - pathX[index + 2])
            let backwardY = pathY[index] - ((2.0 * pathY[index + 1]) - pathY[index + 2])
            let forwardRoll = pathRoll[index] - ((2.0 * pathRoll[index - 1]) - pathRoll[index - 2])
            let backwardRoll = pathRoll[index] - ((2.0 * pathRoll[index + 1]) - pathRoll[index + 2])
            let residualMagnitude = (hypotf(forwardX, forwardY) + hypotf(backwardX, backwardY)) * 0.5
            let residualMismatch = hypotf(forwardX - backwardX, forwardY - backwardY)
            let rollResidualMagnitude = (abs(forwardRoll) + abs(backwardRoll)) * 0.5
            let rollResidualMismatch = abs(forwardRoll - backwardRoll)
            let twoWay = 1.0 - confidenceRamp(
                residualMismatch,
                start: farFieldRigidShakeForwardBackwardStartPixels,
                full: farFieldRigidShakeForwardBackwardFullPixels
            )
            let rollTwoWay = 1.0 - confidenceRamp(
                rollResidualMismatch,
                start: lensShakeRollStartDegrees,
                full: lensShakeRollFullDegrees * 1.6
            )
            let confidence = min(topConfidence[index], min(ridgeConfidence[index], midConfidence[index]))
            let evidence = confidenceRamp(
                residualMagnitude,
                start: farFieldRigidShakeResidualStartPixels,
                full: farFieldRigidShakeResidualFullPixels
            )
            let rollEvidence = confidenceRamp(
                rollResidualMagnitude,
                start: lensShakeRollStartDegrees,
                full: lensShakeRollFullDegrees
            )
            forwardBackwardConsistency[index] = clamp(twoWay, min: 0.0, max: 1.0)
            support[index] = clamp(
                confidenceRamp(confidence, start: 0.08, full: 0.36)
                    * shapeConsistency[index]
                    * forwardBackwardConsistency[index]
                    * evidence,
                min: 0.0,
                max: 1.0
            )
            rollSupport[index] = clamp(
                confidenceRamp(confidence, start: 0.08, full: 0.36)
                    * shapeConsistency[index]
                    * forwardBackwardConsistency[index]
                    * clamp(rollTwoWay, min: 0.0, max: 1.0)
                    * rollEvidence,
                min: 0.0,
                max: 1.0
            )
        }

        return FarFieldRigidShakePreparedPaths(
            pathX: pathX,
            pathY: pathY,
            pathRoll: pathRoll,
            support: support,
            rollSupport: rollSupport,
            shapeConsistency: shapeConsistency,
            forwardBackwardConsistency: forwardBackwardConsistency
        )
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
                farFieldDx: 0.0,
                farFieldDy: 0.0,
                farFieldSignedRoll: 0.0,
                farFieldConfidence: 0.0,
                yawProxy: 0.0,
                pitchProxy: 0.0,
                shearX: 0.0,
                shearY: 0.0,
                perspectiveX: 0.0,
                perspectiveY: 0.0,
                lensBandTopDx: 0.0,
                lensBandTopDy: 0.0,
                lensBandTopColumnDx: 0.0,
                lensBandTopColumnDy: 0.0,
                lensBandTopRowPhaseDx: 0.0,
                lensBandTopRowPhaseDy: 0.0,
                lensBandTopLocalRoll: 0.0,
                lensBandRidgeDx: 0.0,
                lensBandRidgeDy: 0.0,
                lensBandRidgeColumnDx: 0.0,
                lensBandRidgeColumnDy: 0.0,
                lensBandRidgeRowPhaseDx: 0.0,
                lensBandRidgeRowPhaseDy: 0.0,
                lensBandRidgeLocalRoll: 0.0,
                lensBandMidDx: 0.0,
                lensBandMidDy: 0.0,
                lensBandMidColumnDx: 0.0,
                lensBandMidColumnDy: 0.0,
                lensBandMidRowPhaseDx: 0.0,
                lensBandMidRowPhaseDy: 0.0,
                lensBandMidLocalRoll: 0.0,
                lensBandTopConfidence: 0.0,
                lensBandRidgeConfidence: 0.0,
                lensBandMidConfidence: 0.0,
                lensBandConfidence: 0.0,
                sourceLensShakeRidgeDy: 0.0,
                sourceLensShakeRidgeSupport: 0.0,
                sourceLensShakeRidgeLineDy: 0.0,
                sourceLensShakeRidgeLineSupport: 0.0,
                sourceLensShakeLocalDx: Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                sourceLensShakeLocalDy: Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                sourceLensShakeLocalSupport: Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                farFieldMeshDx: Array(repeating: 0.0, count: farFieldMeshBinCount),
                farFieldMeshDy: Array(repeating: 0.0, count: farFieldMeshBinCount),
                farFieldMeshSupport: Array(repeating: 0.0, count: farFieldMeshBinCount),
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

        if let trajectory = cachedPlaybackTrajectory(
            for: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) {
            return trajectory.transform(at: renderSeconds, outputSize: outputSize)
        }

        schedulePlaybackTrajectoryPreparation(
            for: analysis,
            requestedOutputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )

        os_log(
            "Playback trajectory fallback | reason trajectory-unprepared render %.3f frames %d pan %.3f",
            log: stabilizerHostAnalysisLog,
            type: .error,
            renderSeconds,
            analysis.frames.count,
            panSmoothSeconds
        )
        return playbackPreparedPathLookupEstimate(
            preparedAnalysis: analysis,
            renderSeconds: renderSeconds,
            outputSize: outputSize
        )
    }

    static func playbackEstimateIfReadyOrSchedulePreparation(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths,
        waitForPreparation: Bool = false,
        onPrepared: (() -> Void)? = nil
    ) -> StabilizerAutoTransform? {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return .identity
        }

        if let trajectory = cachedPlaybackTrajectory(
            for: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) {
            return trajectory.transform(at: renderSeconds, outputSize: outputSize)
        }

        if waitForPreparation {
            os_log(
                "Playback trajectory waiting before render | render %.3f frames %d pan %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                renderSeconds,
                analysis.frames.count,
                panSmoothSeconds
            )
            let trajectory = playbackTrajectory(
                for: analysis,
                requestedOutputSize: outputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
            return trajectory.transform(at: renderSeconds, outputSize: outputSize)
        }

        schedulePlaybackTrajectoryPreparation(
            for: analysis,
            requestedOutputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            onPrepared: onPrepared
        )
        os_log(
            "Playback trajectory not ready | render %.3f frames %d pan %.3f",
            log: stabilizerHostAnalysisLog,
            type: .error,
            renderSeconds,
            analysis.frames.count,
            panSmoothSeconds
        )
        return nil
    }

    static func playbackTrajectoryIsReady(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> Bool {
        cachedPlaybackTrajectory(
            for: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) != nil
    }

    static func playbackTrajectorySampleDiagnostic(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> PlaybackTrajectorySampleDiagnostic? {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite,
              let trajectory = cachedPlaybackTrajectory(
                for: analysis,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
              ),
              trajectory.times.count == analysis.frames.count,
              trajectory.times.count == trajectory.transforms.count,
              !trajectory.times.isEmpty
        else {
            return nil
        }

        let lastIndex = trajectory.times.count - 1
        let lowerBound: Int
        let upperBound: Int
        let fraction: Float
        if renderSeconds <= trajectory.times[0] {
            lowerBound = 0
            upperBound = 0
            fraction = 0.0
        } else if renderSeconds >= trajectory.times[lastIndex] {
            lowerBound = lastIndex
            upperBound = lastIndex
            fraction = 0.0
        } else {
            var low = 0
            var high = lastIndex
            while low + 1 < high {
                let middle = (low + high) / 2
                if trajectory.times[middle] <= renderSeconds {
                    low = middle
                } else {
                    high = middle
                }
            }
            lowerBound = low
            upperBound = high
            let duration = trajectory.times[high] - trajectory.times[low]
            fraction = duration.isFinite && duration > Double.ulpOfOne
                ? Float(min(1.0, max(0.0, (renderSeconds - trajectory.times[low]) / duration)))
                : 0.0
        }

        guard analysis.frames.indices.contains(lowerBound),
              analysis.frames.indices.contains(upperBound)
        else {
            return nil
        }

        return PlaybackTrajectorySampleDiagnostic(
            lowerIndex: lowerBound,
            upperIndex: upperBound,
            lowerTime: trajectory.times[lowerBound],
            upperTime: trajectory.times[upperBound],
            fraction: fraction,
            lowerFingerprint: analysis.frames[lowerBound].fingerprint,
            upperFingerprint: analysis.frames[upperBound].fingerprint,
            transform: trajectory.transform(at: renderSeconds, outputSize: outputSize)
        )
    }

    static func schedulePlaybackTrajectoryPreparation(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        requestedOutputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths,
        onPrepared: (() -> Void)? = nil
    ) {
        schedulePlaybackTrajectoryPreparation(
            for: analysis,
            requestedOutputSize: requestedOutputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths,
            onPrepared: onPrepared
        )
    }

    static func playbackEstimates(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        sampleSeconds: [Double],
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths = .defaultStrengths
    ) -> [StabilizerAutoTransform] {
        guard !sampleSeconds.isEmpty else {
            return []
        }
        if let trajectory = cachedPlaybackTrajectory(
            for: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) {
            return sampleSeconds.map { trajectory.transform(at: $0, outputSize: outputSize) }
        }

        let trajectory = playbackTrajectory(
            for: analysis,
            requestedOutputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
        guard !trajectory.transforms.isEmpty else {
            return sampleSeconds.map {
                playbackPreparedPathEstimate(
                    preparedAnalysis: analysis,
                    renderSeconds: $0,
                    outputSize: outputSize,
                    panSmoothSeconds: panSmoothSeconds,
                    strengths: strengths
                )
            }
        }
        return sampleSeconds.map { trajectory.transform(at: $0, outputSize: outputSize) }
    }

    static func playbackPreparedPathLookupEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard !frames.isEmpty,
              renderSeconds.isFinite,
              outputSize.x > Float.ulpOfOne,
              outputSize.y > Float.ulpOfOne
        else {
            return .identity
        }

        let lookup = frameLookup(at: renderSeconds, in: frames)
        let interpolation = lookup.interpolation
        guard frames.indices.contains(lookup.centerIndex) else {
            return .identity
        }

        let centerFrame = frames[lookup.centerIndex]
        let xScale = outputSize.x / Float(max(1, centerFrame.sampleWidth))
        let yScale = outputSize.y / Float(max(1, centerFrame.sampleHeight))
        let macroPathX = interpolatedValue(
            analysis.farFieldPathX.isEmpty ? analysis.pathX : analysis.farFieldPathX,
            using: interpolation
        )
        let macroPathY = interpolatedValue(
            analysis.farFieldPathY.isEmpty ? analysis.pathY : analysis.farFieldPathY,
            using: interpolation
        )
        let macroPathRoll = interpolatedValue(
            analysis.farFieldPathRoll.isEmpty ? analysis.pathRoll : analysis.farFieldPathRoll,
            using: interpolation
        )
        let macroPixelOffset = vector_float2(
            -macroPathX * xScale,
            -macroPathY * yScale
        )

        var transform = StabilizerAutoTransform.identity
        transform.macroPixelOffset = macroPixelOffset
        transform.pixelOffset = macroPixelOffset
        transform.rawPixelOffset = macroPixelOffset
        transform.rotationDegrees = -macroPathRoll
        transform.rawRotationDegrees = -macroPathRoll
        transform.yawPitchProxy = vector_float2(
            -interpolatedValue(analysis.pathYaw, using: interpolation),
            -interpolatedValue(analysis.pathPitch, using: interpolation)
        )
        transform.shear = vector_float2(
            -interpolatedValue(analysis.pathShearX, using: interpolation),
            -interpolatedValue(analysis.pathShearY, using: interpolation)
        )
        transform.perspective = vector_float2(
            -interpolatedValue(analysis.pathPerspectiveX, using: interpolation),
            -interpolatedValue(analysis.pathPerspectiveY, using: interpolation)
        )
        transform.motionConfidence = interpolatedValue(analysis.analysisConfidence, using: interpolation)
        transform.warpConfidence = interpolatedValue(analysis.warpConfidence, using: interpolation)
        transform.blurAmount = interpolatedValue(analysis.blurAmounts, using: interpolation)
        transform.residual = interpolatedValue(analysis.residuals, using: interpolation)
        transform.acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(lookup.centerIndex)
            ? analysis.acceptedBlockCounts[lookup.centerIndex]
            : 0
        transform.totalBlockCount = analysis.totalBlockCounts.indices.contains(lookup.centerIndex)
            ? analysis.totalBlockCounts[lookup.centerIndex]
            : 0
        transform.searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(lookup.centerIndex)
            ? analysis.searchRadiusHitCounts[lookup.centerIndex]
            : 0
        transform.searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(lookup.centerIndex)
            ? analysis.searchRadiusTotalCounts[lookup.centerIndex]
            : 0
        transform.temporalSmoothingSampleCount = 1
        transform.temporalSmoothingWindowSeconds = 0.0
        return transform
    }

    private static func playbackPreparedPathEstimate(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        renderSeconds: Double,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> StabilizerAutoTransform {
        let frames = analysis.frames
        guard frames.count >= 3,
              renderSeconds.isFinite
        else {
            return .identity
        }

        let lookup = frameLookup(at: renderSeconds, in: frames)
        let centerIndex = lookup.centerIndex
        let interpolation = lookup.interpolation
        guard frames.indices.contains(centerIndex) else {
            return .identity
        }

        let centerFrame = frames[centerIndex]
        let xScale = outputSize.x / Float(max(1, centerFrame.sampleWidth))
        let yScale = outputSize.y / Float(max(1, centerFrame.sampleHeight))
        let centerResidual = interpolatedValue(analysis.residuals, using: interpolation)
        let centerBlurAmount = interpolatedValue(analysis.blurAmounts, using: interpolation)
        let motionConfidence = interpolatedValue(analysis.analysisConfidence, using: interpolation)
        let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(centerIndex) ? analysis.acceptedBlockCounts[centerIndex] : 0
        let totalBlockCount = analysis.totalBlockCounts.indices.contains(centerIndex) ? analysis.totalBlockCounts[centerIndex] : 0
        let searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(centerIndex) ? analysis.searchRadiusHitCounts[centerIndex] : 0
        let searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(centerIndex) ? analysis.searchRadiusTotalCounts[centerIndex] : 0
        let rawWarpConfidence = analysis.warpConfidence.indices.contains(centerIndex) ? analysis.warpConfidence[centerIndex] : 0.0
        let edgeQuality = searchRadiusEdgeQuality(
            hitCount: searchRadiusHitCount,
            totalCount: searchRadiusTotalCount
        )
        let rawTrackingConfidence = frameTrackingConfidence(
            motionConfidence: motionConfidence,
            residual: centerResidual,
            blurAmount: centerBlurAmount,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            qualityModel: analysis.qualityModel
        )
        let rawWalkingTrackingConfidence = walkingBandTrackingConfidence(
            motionConfidence: motionConfidence,
            residual: centerResidual,
            blurAmount: centerBlurAmount,
            acceptedBlockCount: acceptedBlockCount,
            totalBlockCount: totalBlockCount,
            qualityModel: analysis.qualityModel
        )
        let confidenceHalfWindow = min(0.36, max(0.18, strideWobbleWindowSeconds * 0.12))
        let smoothedTrackingConfidence = playbackPreparedSmoothedTrackingConfidence(
            preparedAnalysis: analysis,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: confidenceHalfWindow,
            sampleCount: 9,
            walkingBand: false
        )
        let smoothedWalkingTrackingConfidence = playbackPreparedSmoothedTrackingConfidence(
            preparedAnalysis: analysis,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: confidenceHalfWindow,
            sampleCount: 9,
            walkingBand: true
        )
        let macroTrackingConfidence = playbackContinuityConfidence(
            center: rawTrackingConfidence,
            smoothed: smoothedTrackingConfidence
        )
        let strideContinuityConfidence = playbackContinuityConfidence(
            center: rawWalkingTrackingConfidence,
            smoothed: smoothedWalkingTrackingConfidence
        )
        let walkingTrackingConfidence = rawWalkingTrackingConfidence
        let trackingConfidence = rawTrackingConfidence
        let turnTrackingConfidence = residualAdjustedTrackingConfidence(
            macroTrackingConfidence,
            residual: centerResidual,
            multiplier: 0.9,
            qualityModel: analysis.qualityModel
        )
        let strideTrackingConfidence = residualAdjustedTrackingConfidence(
            strideContinuityConfidence,
            residual: centerResidual,
            multiplier: 0.6,
            qualityModel: analysis.qualityModel
        )

        let shortHalfWindow = max(renderFrameLocalSmoothingMinimumStepSeconds, renderFootstepJitterSmoothingWindowSeconds * 0.5)
        let mediumHalfWindow = max(shortHalfWindow, min(strideWobbleWindowSeconds * 0.28, 0.55))
        let broadHalfWindow = max(mediumHalfWindow, max(renderTemporalSmoothingWindowSeconds, panSmoothSeconds) * 0.5)
        let continuityWindowSeconds = max(strideWobbleWindowSeconds, panSmoothSeconds)
        let continuityWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: continuityWindowSeconds * 0.5
        )
        let continuityActiveIndices = continuityWindowIndices.isEmpty ? [centerIndex] : continuityWindowIndices
        let continuitySampledIndices = uniqueSortedIndices(
            continuityActiveIndices + [centerIndex] + interpolation.indices,
            validCount: frames.count
        )
        let strideWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: strideWobbleWindowSeconds * 0.5
        )
        let strideActiveIndices = strideWindowIndices.isEmpty ? [centerIndex] : strideWindowIndices
        let strideSampledIndices = uniqueSortedIndices(
            strideActiveIndices + [centerIndex] + interpolation.indices,
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
                    radiusSeconds: strideWobbleWindowSeconds * 0.5
                )
            },
            validCount: frames.count
        )
        let cache = renderEstimateCache(for: analysis)
        let footstepBaselineXPath = cachedOuterLinearPredictionPath(
            .footstepX,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineYPath = cachedOuterLinearPredictionPath(
            .footstepY,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineRollPath = cachedOuterLinearPredictionPath(
            .footstepRoll,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineXPath = cachedOuterLinearPredictionPath(
            .farFieldX,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineYPath = cachedOuterLinearPredictionPath(
            .farFieldY,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineRollPath = cachedOuterLinearPredictionPath(
            .farFieldRoll,
            analysis: analysis,
            indices: continuitySampledIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )

        let footstepX = interpolatedValue(analysis.footstepPathX, using: interpolation)
        let footstepY = interpolatedValue(analysis.footstepPathY, using: interpolation)
        let footstepRoll = interpolatedValue(analysis.footstepPathRoll, using: interpolation)
        let footstepBaselineX = interpolatedValue(footstepBaselineXPath, using: interpolation)
        let footstepBaselineY = interpolatedValue(footstepBaselineYPath, using: interpolation)
        let footstepBaselineRoll = interpolatedValue(footstepBaselineRollPath, using: interpolation)
        let footstepImpulseX = footstepX - footstepBaselineX
        let footstepImpulseY = footstepY - footstepBaselineY
        let footstepImpulseRoll = footstepRoll - footstepBaselineRoll
        let rawFootstepXConfidenceBase = footstepFrameConfidence(
            .footstepX,
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            interpolation: interpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepYConfidenceBase = footstepFrameConfidence(
            .footstepY,
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            frames: frames,
            interpolation: interpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let rawFootstepRollConfidenceBase = footstepFrameConfidence(
            .footstepRoll,
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            interpolation: interpolation,
            trackingConfidence: walkingTrackingConfidence,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let turnStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineXPath,
            analysis: analysis,
            targetIndices: continuitySampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let turnStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineYPath,
            analysis: analysis,
            targetIndices: continuitySampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let turnStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineRollPath,
            analysis: analysis,
            targetIndices: continuitySampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let footstepXTurnGateScales = turnOwnershipGateScales(
            values: turnStrideSmoothedXPath,
            analysis: analysis,
            targetIndices: strideSupportIndices,
            windowSeconds: continuityWindowSeconds,
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
        let farFieldCleanXPath = confidenceCleanedFootstepPath(
            .farFieldX,
            values: analysis.farFieldPathX,
            baselineValues: farFieldBaselineXPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales,
            cache: cache
        )
        let farFieldCleanYPath = confidenceCleanedFootstepPath(
            .farFieldY,
            values: analysis.farFieldPathY,
            baselineValues: farFieldBaselineYPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let farFieldCleanRollPath = confidenceCleanedFootstepPath(
            .farFieldRoll,
            values: analysis.farFieldPathRoll,
            baselineValues: farFieldBaselineRollPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let strideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanXPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .farFieldX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanXPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .farFieldY,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanYPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .farFieldRoll,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanRollPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let strideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanYPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let strideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanRollPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let cleanedFootstepX = interpolatedValue(footstepCleanXPath, using: interpolation)
        let cleanedFootstepY = interpolatedValue(footstepCleanYPath, using: interpolation)
        let cleanedFootstepRoll = interpolatedValue(footstepCleanRollPath, using: interpolation)

        let mediumX = interpolatedValue(strideSmoothedXPath, using: interpolation)
        let mediumY = interpolatedValue(strideSmoothedYPath, using: interpolation)
        let mediumRoll = interpolatedValue(strideSmoothedRollPath, using: interpolation)
        let farFieldBaselineX = interpolatedValue(farFieldBaselineXPath, using: interpolation)
        let farFieldBaselineY = interpolatedValue(farFieldBaselineYPath, using: interpolation)
        let farFieldBaselineRoll = interpolatedValue(farFieldBaselineRollPath, using: interpolation)
        let farFieldCleanedX = interpolatedValue(farFieldCleanXPath, using: interpolation)
        let farFieldCleanedY = interpolatedValue(farFieldCleanYPath, using: interpolation)
        let farFieldCleanedRoll = interpolatedValue(farFieldCleanRollPath, using: interpolation)
        let farFieldMediumX = interpolatedValue(farFieldStrideSmoothedXPath, using: interpolation)
        let farFieldMediumY = interpolatedValue(farFieldStrideSmoothedYPath, using: interpolation)
        let farFieldMediumRoll = interpolatedValue(farFieldStrideSmoothedRollPath, using: interpolation)
        let broadWindowSeconds = broadHalfWindow * 2.0
        let broadWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: broadHalfWindow
        )
        let broadActiveIndices = broadWindowIndices.isEmpty ? [centerIndex] : broadWindowIndices
        let broadSampledIndices = uniqueSortedIndices(
            broadActiveIndices + [centerIndex] + interpolation.indices,
            validCount: frames.count
        )
        let broadX = adaptiveXTurnSmoothValue(
            turnStrideSmoothedXPath,
            frames: frames,
            indices: broadSampledIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: broadWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let broadY = playbackPreparedSmoothedValue(
            turnStrideSmoothedYPath,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: broadHalfWindow,
            sampleCount: 25
        )
        let broadRoll = playbackPreparedSmoothedValue(
            turnStrideSmoothedRollPath,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: broadHalfWindow,
            sampleCount: 25
        )
        let farFieldX = interpolatedValue(analysis.farFieldPathX, using: interpolation)
        let farFieldY = interpolatedValue(analysis.farFieldPathY, using: interpolation)
        let farFieldRoll = interpolatedValue(analysis.farFieldPathRoll, using: interpolation)
        let broadFarFieldX = adaptiveXTurnSmoothValue(
            EstimatedPath(values: analysis.farFieldPathX),
            frames: frames,
            indices: broadSampledIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: broadWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let broadFarFieldY = playbackPreparedSmoothedValue(
            analysis.farFieldPathY,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: broadHalfWindow,
            sampleCount: 25
        )
        let broadFarFieldRoll = playbackPreparedSmoothedValue(
            analysis.farFieldPathRoll,
            frames: frames,
            renderSeconds: renderSeconds,
            halfWindow: broadHalfWindow,
            sampleCount: 25
        )
        let farFieldMacroConfidence = clamp(
            playbackPreparedSmoothedValue(
                analysis.farFieldConfidence,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: mediumHalfWindow,
                sampleCount: 13
            ),
            min: 0.0,
            max: 1.0
        )
        let farFieldMacroBlend = confidenceRamp(
            farFieldMacroConfidence,
            start: farFieldMacroBlendConfidenceStart,
            full: farFieldMacroBlendConfidenceFull
        )
        let smoothedWarpConfidence = clamp(
            playbackPreparedSmoothedValue(
                analysis.warpConfidence,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: mediumHalfWindow,
                sampleCount: 13
            ),
            min: 0.0,
            max: 1.0
        )
        let farFieldBandBlend = farFieldWalkingBandBlend(
            farFieldConfidence: farFieldMacroConfidence,
            warpConfidence: smoothedWarpConfidence,
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            edgeQuality: edgeQuality
        )
        let farFieldBandBlendX = farFieldBandBlend * farFieldWalkingBandBlendXScale
        let farFieldBandBlendY = farFieldBandBlend * farFieldWalkingBandBlendYScale
        let farFieldBandBlendRoll = farFieldBandBlend * farFieldWalkingBandBlendRollScale
        let rawFootstepXConfidence = rawFootstepXConfidenceBase
        let rawFootstepYConfidence = rawFootstepYConfidenceBase
        let rawFootstepRollConfidence = rawFootstepRollConfidenceBase

        let microBandX = blendedFarFieldBand(
            footstepBand: footstepImpulseX,
            farFieldBand: farFieldX - farFieldBaselineX,
            blend: farFieldBandBlendX,
            hasFarField: !analysis.farFieldPathX.isEmpty
        )
        let microBandY = blendedFarFieldBand(
            footstepBand: footstepImpulseY,
            farFieldBand: farFieldY - farFieldBaselineY,
            blend: farFieldBandBlendY,
            hasFarField: !analysis.farFieldPathY.isEmpty
        )
        let microBandRoll = blendedFarFieldBand(
            footstepBand: footstepImpulseRoll,
            farFieldBand: farFieldRoll - farFieldBaselineRoll,
            blend: farFieldBandBlendRoll,
            hasFarField: !analysis.farFieldPathRoll.isEmpty
        )
        let strideBandX = blendedFarFieldBand(
            footstepBand: cleanedFootstepX - mediumX,
            farFieldBand: farFieldCleanedX - farFieldMediumX,
            blend: farFieldBandBlendX,
            hasFarField: !analysis.farFieldPathX.isEmpty
        )
        let strideBandY = blendedFarFieldBand(
            footstepBand: cleanedFootstepY - mediumY,
            farFieldBand: farFieldCleanedY - farFieldMediumY,
            blend: farFieldBandBlendY,
            hasFarField: !analysis.farFieldPathY.isEmpty
        )
        let strideBandRoll = blendedFarFieldBand(
            footstepBand: cleanedFootstepRoll - mediumRoll,
            farFieldBand: farFieldCleanedRoll - farFieldMediumRoll,
            blend: farFieldBandBlendRoll,
            hasFarField: !analysis.farFieldPathRoll.isEmpty
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
        let footstepPanBandX = mediumX - broadX
        let footstepPanBandY = mediumY - broadY
        let footstepPanBandRoll = mediumRoll - broadRoll
        let farFieldPanBandX = farFieldX - broadFarFieldX
        let farFieldPanBandY = farFieldY - broadFarFieldY
        let farFieldPanBandRoll = farFieldRoll - broadFarFieldRoll
        let panBandX = footstepPanBandX + ((farFieldPanBandX - footstepPanBandX) * farFieldMacroBlend)
        let panBandY = footstepPanBandY + ((farFieldPanBandY - footstepPanBandY) * farFieldMacroBlend)
        let panBandRoll = footstepPanBandRoll + ((farFieldPanBandRoll - footstepPanBandRoll) * farFieldMacroBlend)
        let farFieldWalkingXSupport = farFieldTurnOwnedWalkingXSupport(
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            edgeQuality: edgeQuality
        )
        let playbackTurnOwnershipX = confidenceRamp(
            abs(panBandX * xScale),
            start: turnMacroOwnershipBandStartPixels,
            full: turnMacroOwnershipBandFullPixels
        ) * turnTrackingConfidence
        let turnXMacroPixels = abs(panBandX * xScale)
        let playbackTurnOwnershipY = confidenceRamp(
            abs(panBandY * yScale),
            start: turnMacroOwnershipBandStartPixels,
            full: turnMacroOwnershipBandFullPixels
        ) * turnTrackingConfidence
        let turnYMacroPixels = abs(panBandY * yScale)
        let playbackTurnShakeSuppression = turnStabilizerShakeSuppression(
            turnOwnership: playbackTurnOwnershipX,
            turnConfidence: playbackTurnOwnershipX
        )
        let baseFootstepXTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepXSuppression),
            min: 0.0,
            max: 1.0
        )
        let footstepYTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepYSuppression),
            min: 0.0,
            max: 1.0
        )
        let footstepRollTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepRollSuppression),
            min: 0.0,
            max: 1.0
        )
        let baseStrideXTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideXSuppression),
            min: 0.0,
            max: 1.0
        )
        let strideYTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideYSuppression),
            min: 0.0,
            max: 1.0
        )
        let strideRollTurnGate = clamp(
            1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideRollSuppression),
            min: 0.0,
            max: 1.0
        )
        let turnOwnedFootstepXFineGate = turnOwnedFootstepXFineBandGate(
            bandPixels: microBandX * xScale,
            turnOwnership: playbackTurnOwnershipX
        )
        let footstepXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawFootstepXConfidence,
            bandMagnitude: abs(microBandX * xScale),
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldWalkingXSupport
        )
        let strideXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawStrideXConfidence,
            bandMagnitude: abs(strideBandX * xScale),
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldWalkingXSupport
        ) * turnOwnedStrideXGateFloorScale
        let footstepXTurnGate = max(baseFootstepXTurnGate, footstepXTurnGateFloor)
        let strideXTurnGate = max(baseStrideXTurnGate, strideXTurnGateFloor)
        let turnOwnedFootstepXConfidenceFloor = clamp(
            turnOwnedFarFieldXConfidenceFloorMax
                * farFieldWalkingXSupport
                * confidenceRamp(
                    abs(microBandX * xScale),
                    start: turnOwnedFarFieldXConfidenceFloorStartPixels,
                    full: turnOwnedFarFieldXConfidenceFloorFullPixels
                )
                * turnOwnedFootstepXFineGate,
            min: 0.0,
            max: turnOwnedFarFieldXConfidenceFloorMax
        )
        let footstepXWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: microBandX * xScale,
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldWalkingXSupport,
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            farFieldConfidence: farFieldMacroConfidence
        ) * turnOwnedFootstepXFineGate
        let footstepYWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: microBandY * yScale,
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldWalkingXSupport,
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            farFieldConfidence: farFieldMacroConfidence
        )
        let farFieldFootstepXConfidenceFloor = max(
            turnOwnedFootstepXConfidenceFloor,
            max(
                farFieldFootstepConfidenceFloor(
                    bandPixels: microBandX * xScale,
                    farFieldSupport: farFieldWalkingXSupport
                ) * turnOwnedFootstepXFineGate,
                max(
                    turnOwnedFootstepXRescueConfidenceFloor(
                        bandPixels: microBandX * xScale,
                        turnShakeSuppression: playbackTurnShakeSuppression,
                        turnOwnership: playbackTurnOwnershipX,
                        farFieldSupport: farFieldWalkingXSupport,
                        fineGate: turnOwnedFootstepXFineGate
                    ),
                    footstepXWalkingRescueConfidenceFloor
                )
            )
        )
        let footstepYFarFieldConfidenceFloor = max(
            farFieldFootstepVerticalConfidenceFloor(
                bandPixels: microBandY * yScale,
                farFieldSupport: farFieldWalkingXSupport
            ),
            footstepYWalkingRescueConfidenceFloor
        )
        let footstepRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: microBandRoll,
            farFieldSupport: farFieldWalkingXSupport
        )
        let strideXBaseFarFieldConfidenceFloor = turnOwnedFarFieldWalkingXConfidenceFloor(
            bandMagnitude: abs(strideBandX * xScale),
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldWalkingXSupport
        ) * turnOwnedStrideXGateFloorScale
        let strideXRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandX * xScale,
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldWalkingXSupport,
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideYBaseFarFieldConfidenceFloor = farFieldFootstepVerticalConfidenceFloor(
            bandPixels: strideBandY * yScale,
            farFieldSupport: farFieldWalkingXSupport
        ) * farFieldStrideVerticalConfidenceFloorScale
        let strideYRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandY * yScale,
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: playbackTurnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldWalkingXSupport,
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideXFarFieldConfidenceFloor = max(strideXBaseFarFieldConfidenceFloor, strideXRescueConfidenceFloor)
        let strideYFarFieldConfidenceFloor = max(strideYBaseFarFieldConfidenceFloor, strideYRescueConfidenceFloor)
        let strideRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: strideBandRoll,
            farFieldSupport: farFieldWalkingXSupport
        ) * farFieldStrideRollConfidenceFloorScale
        let footstepXConfidence = max(rawFootstepXConfidence * footstepXTurnGate, farFieldFootstepXConfidenceFloor)
        let footstepYConfidence = max(rawFootstepYConfidence * footstepYTurnGate, footstepYFarFieldConfidenceFloor)
        let footstepRollConfidence = max(rawFootstepRollConfidence * footstepRollTurnGate, footstepRollFarFieldConfidenceFloor)
        let strideXConfidence = max(rawStrideXConfidence * strideXTurnGate, strideXFarFieldConfidenceFloor)
        let strideYConfidence = max(rawStrideYConfidence * strideYTurnGate, strideYFarFieldConfidenceFloor)
        let strideRollConfidence = max(rawStrideRollConfidence * strideRollTurnGate, strideRollFarFieldConfidenceFloor)
        let playbackMicroConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let playbackStrideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0

        let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.turnSmoothingZoom, confidence: turnTrackingConfidence)
        let cameraJitterMacroYConfidence = turnSmoothingConfidence(
            bandValue: panBandY,
            trackingConfidence: turnTrackingConfidence
        )
        let cameraJitterMacroRollConfidence = turnSmoothingRotationConfidence(
            bandValue: panBandRoll,
            trackingConfidence: turnTrackingConfidence
        )
        let cameraJitterMacroYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterY,
            confidence: cameraJitterMacroYConfidence,
            maxStrength: 10.0
        )
        let cameraJitterMacroRollCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterRotation,
            confidence: cameraJitterMacroRollConfidence
        )
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)

        let macroPixelOffset = vector_float2(
            softLimit(
                -panBandX * xScale * positionGain * panCorrectionStrengthX,
                limit: turnSmoothingXOffsetLimit(
                    outputPixels: outputSize.x,
                    turnSmoothingStrength: strengths.turnSmoothingZoom
                )
            ),
            0.0
        )
        let cameraJitterMacroPixelOffset = vector_float2(
            0.0,
            -panBandY * yScale * positionGain * cameraJitterMacroYCorrectionStrength
        )
        let cameraJitterMacroRotation = -panBandRoll * rotationGain * cameraJitterMacroRollCorrectionStrength
        let microPixelLimitX = max(2.0, outputSize.x * 0.055)
        let microPixelLimitY = max(2.0, outputSize.y * 0.055)
        let unattenuatedRawMicroPixelOffsetX = -microBandX * xScale * microXCorrectionStrength
        let lowEvidenceMicroXScale = lowEvidenceLargeFootstepXScale(
            rawConfidence: max(rawFootstepXConfidence, farFieldFootstepXConfidenceFloor),
            correctionPixels: unattenuatedRawMicroPixelOffsetX,
            farFieldSupport: farFieldWalkingXSupport
        )
        let effectiveMicroXCorrectionStrength = microXCorrectionStrength * lowEvidenceMicroXScale
        let rawMicroPixelOffsetX = -microBandX * xScale * effectiveMicroXCorrectionStrength
        let rawMicroPixelOffsetY = -microBandY * yScale * microYCorrectionStrength
        let footstepXContinuityConfidenceScale = max(footstepXTurnGate, farFieldWalkingXSupport)
        let footstepYContinuityConfidenceScale = max(footstepYTurnGate, farFieldWalkingXSupport)
        let limitedMicroPixelOffsetX = strengths.microJitterX > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepX,
                values: analysis.footstepPathX,
                baselineValues: footstepBaselineXPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroPixelOffsetX,
                outputScale: xScale,
                requestedStrength: strengths.microJitterX,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepXContinuityConfidenceScale,
                confidenceFloor: farFieldFootstepXConfidenceFloor,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroPixelOffsetX, limitedAmount: 0.0)
        let limitedMicroPixelOffsetY = strengths.microJitterY > 0.0
            ? footstepContinuityLimitedCorrection(
                .footstepY,
                values: analysis.footstepPathY,
                baselineValues: footstepBaselineYPath,
                analysis: analysis,
                centerTime: renderSeconds,
                rawCorrection: rawMicroPixelOffsetY,
                outputScale: yScale,
                requestedStrength: strengths.microJitterY,
                fullImpulseScale: footstepImpulseFullScalePixels,
                confidenceScale: footstepYContinuityConfidenceScale,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroPixelOffsetY, limitedAmount: 0.0)
        let microPixelOffset = vector_float2(
            softLimit(limitedMicroPixelOffsetX.limitedCorrection, limit: microPixelLimitX),
            softLimit(limitedMicroPixelOffsetY.limitedCorrection, limit: microPixelLimitY)
        )
        let microRotation = softLimit(
            -microBandRoll * microRotationCorrectionStrength,
            limit: 0.55
        )
        let stridePixelOffset = vector_float2(
            softLimit(
                -strideBandX * xScale * strideXCorrectionStrength,
                limit: microPixelLimitX * 1.25
            ),
            softLimit(
                -strideBandY * yScale * strideYCorrectionStrength,
                limit: microPixelLimitY * 1.25
            )
        )
        let strideRotation = softLimit(
            -strideBandRoll * strideRotationCorrectionStrength,
            limit: 0.70
        )

        let farFieldWarpStrengths = effectiveFarFieldWarpComponentStrengths(Float(strengths.farFieldWarp))
        let farFieldWarpGateWindowIndices = indicesWithinTimeRadius(
            frames,
            centerTime: renderSeconds,
            radiusSeconds: farFieldWarpOuterWindowSeconds * 0.5
        )
        let farFieldWarpGateActiveIndices = farFieldWarpGateWindowIndices.isEmpty ? [centerIndex] : farFieldWarpGateWindowIndices
        let farFieldWarpTrackingConfidence = stableFarFieldWarpTrackingConfidence(
            analysis: analysis,
            indices: farFieldWarpGateActiveIndices,
            currentTrackingConfidence: macroTrackingConfidence
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
            currentWarpConfidence: rawWarpConfidence
        )
        let farFieldWarpGate = farFieldWarpRenderGate(
            warpConfidence: stableWarpConfidence,
            trackingConfidence: farFieldWarpTrackingConfidence,
            edgeQuality: farFieldWarpEdgeQuality
        )
        let farFieldWarpTurnGate: Float = 1.0
        let appliedWarpConfidence = farFieldWarpAppliedConfidence(
            stableWarpConfidence: stableWarpConfidence,
            warpGate: farFieldWarpGate,
            turnGate: farFieldWarpTurnGate,
            trackingConfidence: farFieldWarpTrackingConfidence,
            edgeQuality: farFieldWarpEdgeQuality
        )
        let warpHalfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
        func preparedWarpBand(_ values: [Float], deadband: Float, strength: Float, limit: Float) -> Float {
            guard strength > 0.0,
                  appliedWarpConfidence > 0.0
            else {
                return 0.0
            }
            let current = interpolatedValue(values, using: interpolation)
            let baseline = playbackPreparedSmoothedValue(
                values,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: warpHalfWindow,
                sampleCount: 7
            )
            let scaled = softDeadband(current - baseline, threshold: deadband)
                * appliedWarpConfidence
                * strength
            return clamp(scaled, min: -limit * strength, max: limit * strength)
        }
        let yawPitchProxy = vector_float2(
            preparedWarpBand(
                analysis.pathYaw,
                deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.yawPitch,
                limit: maxRenderedFarFieldYawPitchProxy
            ),
            preparedWarpBand(
                analysis.pathPitch,
                deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.yawPitch,
                limit: maxRenderedFarFieldYawPitchProxy
            )
        )
        let shear = vector_float2(
            preparedWarpBand(
                analysis.pathShearX,
                deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.shear,
                limit: maxRenderedFarFieldShear
            ),
            preparedWarpBand(
                analysis.pathShearY,
                deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.shear,
                limit: maxRenderedFarFieldShear
            )
        )
        let perspective = vector_float2(
            preparedWarpBand(
                analysis.pathPerspectiveX,
                deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.perspective,
                limit: maxRenderedFarFieldPerspective
            ),
            preparedWarpBand(
                analysis.pathPerspectiveY,
                deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                strength: farFieldWarpStrengths.perspective,
                limit: maxRenderedFarFieldPerspective
            )
        )

        let trajectoryMicroJitterPixelOffset = farFieldWalkingResidualContinuityOffset(
            footstepBandPixels: vector_float2(microBandX * xScale, microBandY * yScale),
            footstepCorrectionPixels: microPixelOffset,
            strideBandPixels: vector_float2(strideBandX * xScale, strideBandY * yScale),
            strideCorrectionPixels: stridePixelOffset,
            turnShakeSuppression: playbackTurnShakeSuppression,
            turnOwnership: vector_float2(playbackTurnOwnershipX, playbackTurnOwnershipY),
            turnMacroMagnitude: vector_float2(turnXMacroPixels, turnYMacroPixels),
            farFieldSupport: farFieldWalkingXSupport,
            warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
            trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
            farFieldConfidence: farFieldMacroConfidence
        )
        let trajectoryContinuityPixelOffset = cameraJitterMacroPixelOffset
        let lensShake = farFieldWarpStrengths.isActive
            ? sourceSpaceLensShakeCorrection(
                analysis: analysis,
                frames: frames,
                interpolation: interpolation,
                outputScale: vector_float2(xScale, yScale),
                warpConfidence: appliedWarpConfidence,
                farFieldConfidence: farFieldMacroConfidence,
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                edgeQuality: farFieldWarpEdgeQuality,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: vector_float2(playbackTurnOwnershipX, playbackTurnOwnershipY),
                cache: cache
            )
            : SourceSpaceLensShakeCorrection()
        let pixelOffset = macroPixelOffset
            + microPixelOffset
            + stridePixelOffset
            + trajectoryMicroJitterPixelOffset
            + trajectoryContinuityPixelOffset
            + lensShake.pixelOffset
        let rotation = cameraJitterMacroRotation + microRotation + strideRotation + lensShake.rotationDegrees
        return StabilizerAutoTransform(
            pixelOffset: pixelOffset,
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: stridePixelOffset,
            trajectoryMicroJitterPixelOffset: trajectoryMicroJitterPixelOffset,
            trajectoryContinuityPixelOffset: trajectoryContinuityPixelOffset,
            lensShakePixelOffset: lensShake.pixelOffset,
            lensShakeRotationDegrees: lensShake.rotationDegrees,
            lensShakeYawPitch: lensShake.yawPitch,
            lensShakeShear: lensShake.shear,
            lensShakePerspective: lensShake.perspective,
            lensShakeScore: lensShake.score,
            lensShakeSupport: lensShake.support,
            lensShakeWindowFrames: lensShake.windowFrames,
            lensShakeWindowSeconds: lensShake.windowSeconds,
            lensShakeAxisMask: lensShake.axisMask,
            lensShakeReasonCode: lensShake.reasonCode,
            lensShakeRollingShutterCandidate: lensShake.rollingShutterCandidate,
            lensBandTopOffset: lensShake.bandTopOffset,
            lensBandRidgeOffset: lensShake.bandRidgeOffset,
            lensBandMidOffset: lensShake.bandMidOffset,
            lensBandRawTopOffset: lensShake.bandRawTopOffset,
            lensBandRawRidgeOffset: lensShake.bandRawRidgeOffset,
            lensBandRawMidOffset: lensShake.bandRawMidOffset,
            lensBandPulseDeltaTopOffset: lensShake.bandPulseDeltaTopOffset,
            lensBandPulseDeltaRidgeOffset: lensShake.bandPulseDeltaRidgeOffset,
            lensBandPulseDeltaMidOffset: lensShake.bandPulseDeltaMidOffset,
            lensBandPulseWindowFrames: lensShake.bandPulseWindowFrames,
            lensBandTopColumnOffset: lensShake.bandTopColumnOffset,
            lensBandRidgeColumnOffset: lensShake.bandRidgeColumnOffset,
            lensBandMidColumnOffset: lensShake.bandMidColumnOffset,
            lensBandTopRowPhaseOffset: lensShake.bandTopRowPhaseOffset,
            lensBandRidgeRowPhaseOffset: lensShake.bandRidgeRowPhaseOffset,
            lensBandMidRowPhaseOffset: lensShake.bandMidRowPhaseOffset,
            lensBandTopLocalRoll: lensShake.bandTopLocalRoll,
            lensBandRidgeLocalRoll: lensShake.bandRidgeLocalRoll,
            lensBandMidLocalRoll: lensShake.bandMidLocalRoll,
            lensBandWarpSupport: lensShake.bandWarpSupport,
            lensBandWarpApplied: lensShake.bandWarpApplied,
            lensBandRollingShutterScore: lensShake.bandRollingShutterScore,
            lensBandModelMask: lensShake.bandModelMask,
            lensFarFieldRigidShakeOffset: lensShake.farFieldRigidOffset,
            lensFarFieldRigidShakeSupport: lensShake.farFieldRigidSupport,
            lensFarFieldRigidShakeApplied: lensShake.farFieldRigidApplied,
            lensFarFieldRigidShakeShapeConsistency: lensShake.farFieldRigidShapeConsistency,
            lensFarFieldRigidShakeForwardBackwardConsistency: lensShake.farFieldRigidForwardBackwardConsistency,
            lensFarFieldRigidShakeLocalWarpSuppressed: lensShake.farFieldRigidLocalWarpSuppressed,
            lensFarFieldRigidXQuiverScore: lensShake.farFieldRigidXQuiverScore,
            lensFarFieldRigidXBeforeLimiter: lensShake.farFieldRigidXBeforeLimiter,
            lensFarFieldRigidXAfterLimiter: lensShake.farFieldRigidXAfterLimiter,
            lensFarFieldRigidRollResidual: lensShake.farFieldRigidRollResidual,
            lensFarFieldRigidRollSupport: lensShake.farFieldRigidRollSupport,
            lensFarFieldRigidGlobalYOffset: lensShake.farFieldRigidGlobalYOffset,
            lensFarFieldRigidGlobalRollDegrees: lensShake.farFieldRigidGlobalRollDegrees,
            lensFarFieldRigidRollApplied: lensShake.farFieldRigidRollApplied,
            lensFarFieldMeshOffset: lensShake.farFieldMeshOffset,
            lensFarFieldMeshSupport: lensShake.farFieldMeshSupport,
            lensFarFieldMeshBlend: lensShake.farFieldMeshBlend,
            lensFarFieldMeshAvailable: lensShake.farFieldMeshAvailable,
            lensFarFieldMeshSupportedBins: lensShake.farFieldMeshSupportedBins,
            lensFarFieldMeshMaxBinDelta: lensShake.farFieldMeshMaxBinDelta,
            lensFarFieldMeshOpposingBins: lensShake.farFieldMeshOpposingBins,
            lensFarFieldMeshDominantWindowFrames: lensShake.farFieldMeshDominantWindowFrames,
            lensFarFieldMeshDominantWindowSeconds: lensShake.farFieldMeshDominantWindowSeconds,
            lensFarFieldMeshDominantSupport: lensShake.farFieldMeshDominantSupport,
            lensFarFieldMeshDominantCell: lensShake.farFieldMeshDominantCell,
            sourceLensShakeRidgeOffset: lensShake.sourceRidgeOffset,
            sourceLensShakeRidgeSupport: lensShake.sourceRidgeSupport,
            sourceLensShakeRidgeApplied: lensShake.sourceRidgeApplied,
            sourceLensShakeRidgeLineResidual: lensShake.sourceRidgeLineResidual,
            sourceLensShakeRidgeLineOffset: lensShake.sourceRidgeLineOffset,
            sourceLensShakeRidgeLineSupport: lensShake.sourceRidgeLineSupport,
            sourceLensShakeRidgeLineBandSupported: lensShake.sourceRidgeLineBandSupported,
            sourceLensShakeRidgeLineApplied: lensShake.sourceRidgeLineApplied,
            sourceLensShakeLocalTopLeftOffset: lensShake.localTopLeftOffset,
            sourceLensShakeLocalTopCenterOffset: lensShake.localTopCenterOffset,
            sourceLensShakeLocalTopRightOffset: lensShake.localTopRightOffset,
            sourceLensShakeLocalRidgeLeftOffset: lensShake.localRidgeLeftOffset,
            sourceLensShakeLocalRidgeCenterOffset: lensShake.localRidgeCenterOffset,
            sourceLensShakeLocalRidgeRightOffset: lensShake.localRidgeRightOffset,
            sourceLensShakeLocalMidLeftOffset: lensShake.localMidLeftOffset,
            sourceLensShakeLocalMidCenterOffset: lensShake.localMidCenterOffset,
            sourceLensShakeLocalMidRightOffset: lensShake.localMidRightOffset,
            sourceLensShakeLocalSupport: lensShake.localSupport,
            sourceLensShakeLocalApplied: lensShake.localApplied,
            footstepJitterRotationDegrees: cameraJitterMacroRotation + microRotation,
            strideWobbleRotationDegrees: strideRotation,
            rotationDegrees: rotation,
            turnDetectedPixelOffset: vector_float2(-panBandX * xScale, 0.0),
            rawPixelOffset: pixelOffset,
            rawRotationDegrees: rotation,
            temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
            temporalSmoothingRotationDelta: 0.0,
            temporalSmoothingSampleCount: 25,
            temporalSmoothingWindowSeconds: Float(broadHalfWindow * 2.0),
            effectiveMicroJitterStrength: vector_float3(
                effectiveMicroXCorrectionStrength,
                max(microYCorrectionStrength, cameraJitterMacroYCorrectionStrength),
                max(microRotationCorrectionStrength, cameraJitterMacroRollCorrectionStrength)
            ),
            effectiveStrideWobbleStrength: vector_float3(
                strideXCorrectionStrength,
                strideYCorrectionStrength,
                strideRotationCorrectionStrength
            ),
            warpConfidence: appliedWarpConfidence,
            microConfidence: max(
                playbackMicroConfidence,
                max(cameraJitterMacroYConfidence, cameraJitterMacroRollConfidence)
            ),
            strideConfidence: playbackStrideConfidence,
            turnConfidence: turnTrackingConfidence,
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
            footstepImpulse: vector_float3(microBandX, microBandY, microBandRoll),
            rawFootstepCorrection: vector_float2(
                rawMicroPixelOffsetX,
                rawMicroPixelOffsetY
            ),
            limitedFootstepCorrection: microPixelOffset,
            footstepPulseLimited: vector_float2(
                limitedMicroPixelOffsetX.limitedAmount,
                limitedMicroPixelOffsetY.limitedAmount
            ),
            searchRadiusHitCount: searchRadiusHitCount,
            searchRadiusTotalCount: searchRadiusTotalCount
        )
    }

    private static func playbackPreparedSmoothedValue(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        renderSeconds: Double,
        halfWindow: Double,
        sampleCount: Int
    ) -> Float {
        let centerLookup = frameLookup(at: renderSeconds, in: frames)
        let centerValue = interpolatedValue(values, using: centerLookup.interpolation)
        guard frames.count >= 2,
              values.count == frames.count,
              renderSeconds.isFinite,
              halfWindow.isFinite,
              halfWindow > 0.0,
              sampleCount >= 3,
              let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return centerValue
        }

        let boundedSampleCount = max(3, sampleCount | 1)
        let centerSample = boundedSampleCount / 2
        let sampleStep = (halfWindow * 2.0) / Double(max(1, boundedSampleCount - 1))
        let sigma = max(1e-6, halfWindow * 0.55)
        var weightedSum: Float = 0.0
        var weightSum: Float = 0.0
        for sampleIndex in 0..<boundedSampleCount {
            let offset = Double(sampleIndex - centerSample) * sampleStep
            let sampleSeconds = renderSeconds + offset
            guard sampleSeconds >= firstTime,
                  sampleSeconds <= lastTime
            else {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let lookup = frameLookup(at: sampleSeconds, in: frames)
            weightedSum += interpolatedValue(values, using: lookup.interpolation) * weight
            weightSum += weight
        }
        guard weightSum > Float.ulpOfOne else {
            return centerValue
        }
        return weightedSum / weightSum
    }

    private static func playbackPreparedSmoothedValue(
        _ path: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        renderSeconds: Double,
        halfWindow: Double,
        sampleCount: Int
    ) -> Float {
        let centerLookup = frameLookup(at: renderSeconds, in: frames)
        let centerValue = interpolatedValue(path, using: centerLookup.interpolation)
        guard frames.count >= 2,
              path.values.count == frames.count,
              renderSeconds.isFinite,
              halfWindow.isFinite,
              halfWindow > 0.0,
              sampleCount >= 3,
              let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return centerValue
        }

        let boundedSampleCount = max(3, sampleCount | 1)
        let centerSample = boundedSampleCount / 2
        let sampleStep = (halfWindow * 2.0) / Double(max(1, boundedSampleCount - 1))
        let sigma = max(1e-6, halfWindow * 0.55)
        var weightedSum: Float = 0.0
        var weightSum: Float = 0.0
        for sampleIndex in 0..<boundedSampleCount {
            let offset = Double(sampleIndex - centerSample) * sampleStep
            let sampleSeconds = renderSeconds + offset
            guard sampleSeconds >= firstTime,
                  sampleSeconds <= lastTime
            else {
                continue
            }
            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }
            let lookup = frameLookup(at: sampleSeconds, in: frames)
            weightedSum += interpolatedValue(path, using: lookup.interpolation) * weight
            weightSum += weight
        }
        guard weightSum > Float.ulpOfOne else {
            return centerValue
        }
        return weightedSum / weightSum
    }

    private static func playbackContinuityConfidence(center: Float, smoothed: Float) -> Float {
        let boundedCenter = clamp(center, min: 0.0, max: 1.0)
        let boundedSmoothed = clamp(smoothed, min: 0.0, max: 1.0)
        guard boundedCenter > 0.02 else {
            return 0.0
        }
        return clamp(max(boundedCenter, boundedSmoothed * 0.94), min: 0.0, max: 1.0)
    }

    private static func lowEvidenceLargeFootstepXScale(
        rawConfidence: Float,
        correctionPixels: Float,
        farFieldSupport: Float
    ) -> Float {
        guard rawConfidence.isFinite,
              correctionPixels.isFinite,
              farFieldSupport.isFinite
        else {
            return 1.0
        }
        let magnitudeGate = confidenceRamp(
            abs(correctionPixels),
            start: footstepLowEvidenceLargeXCorrectionStartPixels,
            full: footstepLowEvidenceLargeXCorrectionFullPixels
        )
        guard magnitudeGate > 0.0 else {
            return 1.0
        }
        let evidenceProtection = confidenceRamp(
            rawConfidence,
            start: footstepLowEvidenceLargeXConfidenceStart,
            full: footstepLowEvidenceLargeXConfidenceFull
        )
        let farFieldProtection = confidenceRamp(
            farFieldSupport,
            start: 0.32,
            full: 0.70
        )
        let attenuation = magnitudeGate
            * (1.0 - evidenceProtection)
            * (1.0 - farFieldProtection)
        return clamp(
            1.0 - (attenuation * (1.0 - footstepLowEvidenceLargeXMinimumScale)),
            min: footstepLowEvidenceLargeXMinimumScale,
            max: 1.0
        )
    }

    private static func playbackPreparedSmoothedTrackingConfidence(
        preparedAnalysis analysis: StabilizerPreparedAnalysis,
        frames: [StabilizerAnalysisFrame],
        renderSeconds: Double,
        halfWindow: Double,
        sampleCount: Int,
        walkingBand: Bool
    ) -> Float {
        guard frames.count >= 2,
              renderSeconds.isFinite,
              halfWindow.isFinite,
              halfWindow > 0.0,
              sampleCount >= 3,
              let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return 0.0
        }

        let boundedSampleCount = max(3, sampleCount | 1)
        let centerSample = boundedSampleCount / 2
        let sampleStep = (halfWindow * 2.0) / Double(max(1, boundedSampleCount - 1))
        let sigma = max(1e-6, halfWindow * 0.55)
        var weightedSum: Float = 0.0
        var weightSum: Float = 0.0

        for sampleIndex in 0..<boundedSampleCount {
            let offset = Double(sampleIndex - centerSample) * sampleStep
            let sampleSeconds = renderSeconds + offset
            guard sampleSeconds >= firstTime,
                  sampleSeconds <= lastTime
            else {
                continue
            }

            let normalizedDistance = offset / sigma
            let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
            guard weight > 0.0001 else {
                continue
            }

            let lookup = frameLookup(at: sampleSeconds, in: frames)
            let interpolation = lookup.interpolation
            let centerIndex = lookup.centerIndex
            let sampleMotionConfidence = interpolatedValue(analysis.analysisConfidence, using: interpolation)
            let sampleResidual = interpolatedValue(analysis.residuals, using: interpolation)
            let sampleBlurAmount = interpolatedValue(analysis.blurAmounts, using: interpolation)
            let sampleAcceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(centerIndex) ? analysis.acceptedBlockCounts[centerIndex] : 0
            let sampleTotalBlockCount = analysis.totalBlockCounts.indices.contains(centerIndex) ? analysis.totalBlockCounts[centerIndex] : 0
            let sampleConfidence = walkingBand
                ? walkingBandTrackingConfidence(
                    motionConfidence: sampleMotionConfidence,
                    residual: sampleResidual,
                    blurAmount: sampleBlurAmount,
                    acceptedBlockCount: sampleAcceptedBlockCount,
                    totalBlockCount: sampleTotalBlockCount,
                    qualityModel: analysis.qualityModel
                )
                : frameTrackingConfidence(
                    motionConfidence: sampleMotionConfidence,
                    residual: sampleResidual,
                    blurAmount: sampleBlurAmount,
                    acceptedBlockCount: sampleAcceptedBlockCount,
                    totalBlockCount: sampleTotalBlockCount,
                    qualityModel: analysis.qualityModel
                )

            weightedSum += sampleConfidence * weight
            weightSum += weight
        }

        guard weightSum > Float.ulpOfOne else {
            return 0.0
        }
        return clamp(weightedSum / weightSum, min: 0.0, max: 1.0)
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

        let broadOffsets = rawSamples.map { $0.transform.macroPixelOffset + $0.transform.strideWobblePixelOffset }
        let broadRotations = rawSamples.map { $0.transform.strideWobbleRotationDegrees }
        guard let medianX = median(broadOffsets.map { $0.x }),
              let medianY = median(broadOffsets.map { $0.y }),
              let medianRotation = median(broadRotations),
              let madX = median(broadOffsets.map { abs($0.x - medianX) }),
              let madY = median(broadOffsets.map { abs($0.y - medianY) }),
              let madRotation = median(broadRotations.map { abs($0 - medianRotation) })
        else {
            return centerTransform
        }
        let xLimit = max(0.75, madX * 3.5)
        let yLimit = max(0.75, madY * 3.5)
        let rotationLimit = max(0.040, madRotation * 3.5)
        let filteredSamples = rawSamples.filter { sample in
            let broadOffset = sample.transform.macroPixelOffset + sample.transform.strideWobblePixelOffset
            return abs(broadOffset.x - medianX) <= xLimit
                && abs(broadOffset.y - medianY) <= yLimit
                && abs(sample.transform.strideWobbleRotationDegrees - medianRotation) <= rotationLimit
        }
        let samples = filteredSamples.count >= 3 ? filteredSamples : rawSamples
        var smoothedTransform = weightedAverageTransform(samples)
        preserveLensShakeDiagnostics(from: centerTransform, into: &smoothedTransform)
        smoothedTransform.microPixelOffset = centerTransform.microPixelOffset
        smoothedTransform.footstepJitterRotationDegrees = centerTransform.footstepJitterRotationDegrees
        smoothedTransform.pixelOffset = smoothedTransform.macroPixelOffset
            + smoothedTransform.microPixelOffset
            + smoothedTransform.strideWobblePixelOffset
            + smoothedTransform.trajectoryMicroJitterPixelOffset
            + smoothedTransform.trajectoryContinuityPixelOffset
            + smoothedTransform.lensShakePixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
            + smoothedTransform.lensShakeRotationDegrees
        smoothedTransform.turnDetectedPixelOffset = centerTransform.turnDetectedPixelOffset
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
        smoothedTransform.limitedFootstepCorrection = centerTransform.limitedFootstepCorrection
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
            guard halfWindow.isFinite,
                  halfWindow >= 0.0,
                  sigma.isFinite,
                  sigma > Double.ulpOfOne,
                  let firstTime = frames.first?.time,
                  let lastTime = frames.last?.time
            else {
                return [(transform: centerTransform, weight: 1.0)]
            }
            let sampleCount = max(
                3,
                halfWindow <= (renderFarFieldWarpSmoothingWindowSeconds * 0.5 + 1e-9)
                    ? 9
                    : renderTemporalSmoothingSampleCount
            )
            let centerSample = sampleCount / 2
            let sampleStep = (halfWindow * 2.0) / Double(max(1, sampleCount - 1))
            var samples: [(transform: StabilizerAutoTransform, weight: Float)] = []
            samples.reserveCapacity(sampleCount)
            samples.append((transform: centerTransform, weight: 1.0))
            for sampleIndex in 0..<sampleCount where sampleIndex != centerSample {
                let offset = (Double(sampleIndex - centerSample) * sampleStep)
                let sampleSeconds = renderSeconds + offset
                guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
                    continue
                }
                if abs(offset) <= timeWindowSelectionEpsilon {
                    continue
                }
                let normalizedDistance = offset / sigma
                let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
                guard weight > 0.0001 else {
                    continue
                }
                samples.append((
                    transform: interpolatedRawTransform(
                        at: sampleSeconds,
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
            let timing = adaptiveXTurnTiming(
                travelPixels: abs(centerTransform.turnDetectedPixelOffset.x),
                baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
                panSmoothSeconds: panSmoothSeconds,
                turnSmoothingZoom: strengths.turnSmoothingZoom
            )
            let transitionWindowSeconds = timing.windowSeconds
            let sampleCount = adaptiveXTurnTransitionSampleCount(windowSeconds: transitionWindowSeconds)
            let centerSample = sampleCount / 2
            let halfWindow = transitionWindowSeconds * 0.5
            let denominator = Double(max(1, sampleCount - 1))
            let sampleStep = transitionWindowSeconds / denominator
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
                        centerFarFieldSupport: centerTransform.warpConfidence,
                        samples: xSamples,
                        similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                    ),
                    smoothedFootstepScalar(
                        centerValue: centerTransform.microPixelOffset.y,
                        centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                        centerFarFieldSupport: centerTransform.warpConfidence,
                        samples: ySamples,
                        similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                    )
                ),
                rotationDegrees: smoothedFootstepScalar(
                    centerValue: centerTransform.footstepJitterRotationDegrees,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                    centerFarFieldSupport: centerTransform.warpConfidence,
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
            let zoomBridgeAuthority = turnSmoothingZoomBridgeAuthority(
                turnSmoothingZoom: strengths.turnSmoothingZoom,
                turnConfidence: rawCenterTransform.turnConfidence,
                turnTravelPixels: abs(rawCenterTransform.turnDetectedPixelOffset.x)
            )
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(rawCenterTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70)
                    * 0.85
                    * (1.0 - (zoomBridgeAuthority * renderTurnTransitionZoomCenterPreservationFade))
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: rawCenterTransform,
                bridgeMacroX: bridgedMacroOffset.x,
                zoomBridgeAuthority: zoomBridgeAuthority
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: rawCenterTransform,
                bridgeTransform: smoothedTurnTransform
            ) * turnSmoothingBridgeBlend(strengths.turnSmoothingZoom)
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
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
        preserveLensShakeDiagnostics(from: rawCenterTransform, into: &smoothedTransform)

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
            + smoothedTransform.trajectoryMicroJitterPixelOffset
            + smoothedTransform.trajectoryContinuityPixelOffset
            + smoothedTransform.lensShakePixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
            + smoothedTransform.lensShakeRotationDegrees
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
        requestedOutputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory {
        let trajectoryOutputSize = playbackTrajectoryOutputSize(for: analysis)
        guard let key = playbackTrajectoryCacheKey(
            analysis: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) else {
            return PlaybackTransformTrajectory(times: [], transforms: [], outputSize: trajectoryOutputSize)
        }

        sharedPlaybackTrajectoryCacheCondition.lock()
        while true {
            if let cached = sharedPlaybackTrajectoryCaches[key] {
                sharedPlaybackTrajectoryCacheCondition.unlock()
                return cached
            }
            guard sharedPlaybackTrajectoryPreparations.contains(key) else {
                sharedPlaybackTrajectoryPreparations.insert(key)
                sharedPlaybackTrajectoryCacheCondition.unlock()
                break
            }
            sharedPlaybackTrajectoryCacheCondition.wait()
        }

        let built = buildAndLogPlaybackTrajectory(
            analysis: analysis,
            outputSize: trajectoryOutputSize,
            requestedOutputSize: requestedOutputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )

        sharedPlaybackTrajectoryCacheCondition.lock()
        defer {
            sharedPlaybackTrajectoryCacheCondition.broadcast()
            sharedPlaybackTrajectoryCacheCondition.unlock()
        }
        sharedPlaybackTrajectoryPreparations.remove(key)
        if let cached = sharedPlaybackTrajectoryCaches[key] {
            return cached
        }
        storePlaybackTrajectory(built, for: key)
        return built
    }

    private static func cachedPlaybackTrajectory(
        for analysis: StabilizerPreparedAnalysis,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory? {
        guard let key = playbackTrajectoryCacheKey(
            analysis: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) else {
            return nil
        }
        sharedPlaybackTrajectoryCacheCondition.lock()
        let cached = sharedPlaybackTrajectoryCaches[key]
        sharedPlaybackTrajectoryCacheCondition.unlock()
        return cached
    }

    private static func schedulePlaybackTrajectoryPreparation(
        for analysis: StabilizerPreparedAnalysis,
        requestedOutputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths,
        onPrepared: (() -> Void)? = nil
    ) {
        let trajectoryOutputSize = playbackTrajectoryOutputSize(for: analysis)
        guard let key = playbackTrajectoryCacheKey(
            analysis: analysis,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        ) else {
            return
        }

        sharedPlaybackTrajectoryCacheCondition.lock()
        if sharedPlaybackTrajectoryCaches[key] != nil {
            sharedPlaybackTrajectoryCacheCondition.unlock()
            if let onPrepared {
                DispatchQueue.main.async(execute: onPrepared)
            }
            return
        }
        if sharedPlaybackTrajectoryPreparations.contains(key) {
            if let onPrepared {
                sharedPlaybackTrajectoryPreparationCallbacks[key, default: []].append(onPrepared)
            }
            sharedPlaybackTrajectoryCacheCondition.unlock()
            return
        }
        sharedPlaybackTrajectoryPreparations.insert(key)
        if let onPrepared {
            sharedPlaybackTrajectoryPreparationCallbacks[key, default: []].append(onPrepared)
        }
        sharedPlaybackTrajectoryCacheCondition.unlock()

        playbackTrajectoryPreparationQueue.async {
            let built = buildAndLogPlaybackTrajectory(
                analysis: analysis,
                outputSize: trajectoryOutputSize,
                requestedOutputSize: requestedOutputSize,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )

            let callbacks: [() -> Void]
            sharedPlaybackTrajectoryCacheCondition.lock()
            sharedPlaybackTrajectoryPreparations.remove(key)
            if sharedPlaybackTrajectoryCaches[key] == nil {
                storePlaybackTrajectory(built, for: key)
            }
            callbacks = sharedPlaybackTrajectoryPreparationCallbacks.removeValue(forKey: key) ?? []
            sharedPlaybackTrajectoryCacheCondition.broadcast()
            sharedPlaybackTrajectoryCacheCondition.unlock()
            callbacks.forEach { callback in
                DispatchQueue.main.async(execute: callback)
            }
        }
    }

    private static func buildAndLogPlaybackTrajectory(
        analysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        requestedOutputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory {
        let buildStartedAt = CFAbsoluteTimeGetCurrent()
        let built = buildPlaybackTrajectory(
            analysis: analysis,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
        let buildMilliseconds = (CFAbsoluteTimeGetCurrent() - buildStartedAt) * 1000.0
        os_log(
            "Playback trajectory prepared | frames %d canonical %.0fx%.0f requested %.0fx%.0f pan %.3f elapsed %.3fms",
            log: stabilizerHostAnalysisLog,
            type: .default,
            analysis.frames.count,
            outputSize.x,
            outputSize.y,
            requestedOutputSize.x,
            requestedOutputSize.y,
            panSmoothSeconds,
            buildMilliseconds
        )
        return built
    }

    private static func storePlaybackTrajectory(
        _ trajectory: PlaybackTransformTrajectory,
        for key: PlaybackTrajectoryCacheKey
    ) {
        sharedPlaybackTrajectoryCaches[key] = trajectory
        sharedPlaybackTrajectoryCacheOrder.removeAll { $0 == key }
        sharedPlaybackTrajectoryCacheOrder.append(key)
        while sharedPlaybackTrajectoryCacheOrder.count > sharedPlaybackTrajectoryCacheLimit {
            let oldestKey = sharedPlaybackTrajectoryCacheOrder.removeFirst()
            sharedPlaybackTrajectoryCaches.removeValue(forKey: oldestKey)
        }
    }

    private static func playbackTrajectoryCacheKey(
        analysis: StabilizerPreparedAnalysis,
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
            algorithmRevision: playbackTrajectoryAlgorithmRevision,
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
            preparedPathFingerprint: preparedPathFingerprint(for: analysis),
            microJitterX: strengths.microJitterX.bitPattern,
            microJitterY: strengths.microJitterY.bitPattern,
            microJitterRotation: strengths.microJitterRotation.bitPattern,
            strideWobbleX: strengths.strideWobbleX.bitPattern,
            strideWobbleY: strengths.strideWobbleY.bitPattern,
            strideWobbleRotation: strengths.strideWobbleRotation.bitPattern,
            farFieldWarp: strengths.farFieldWarp.bitPattern,
            turnSmoothingZoom: strengths.turnSmoothingZoom.bitPattern
        )
    }

    private static func playbackTrajectoryOutputSize(for analysis: StabilizerPreparedAnalysis) -> vector_float2 {
        guard let firstFrame = analysis.frames.first else {
            return vector_float2(1.0, 1.0)
        }
        return vector_float2(
            Float(max(1, firstFrame.sampleWidth)),
            Float(max(1, firstFrame.sampleHeight))
        )
    }

    private static func scalePixelVector(
        _ value: vector_float2,
        xScale: Float,
        yScale: Float
    ) -> vector_float2 {
        vector_float2(value.x * xScale, value.y * yScale)
    }

    private static func scalePixelTransform(
        _ transform: StabilizerAutoTransform,
        from sourceSize: vector_float2,
        to requestedSize: vector_float2
    ) -> StabilizerAutoTransform {
        guard sourceSize.x.isFinite,
              sourceSize.y.isFinite,
              requestedSize.x.isFinite,
              requestedSize.y.isFinite,
              sourceSize.x > Float.ulpOfOne,
              sourceSize.y > Float.ulpOfOne,
              requestedSize.x > Float.ulpOfOne,
              requestedSize.y > Float.ulpOfOne
        else {
            return transform
        }

        let xScale = requestedSize.x / sourceSize.x
        let yScale = requestedSize.y / sourceSize.y
        guard xScale.isFinite,
              yScale.isFinite,
              abs(xScale - 1.0) > 0.000001 || abs(yScale - 1.0) > 0.000001
        else {
            return transform
        }

        var scaled = transform
        scaled.pixelOffset = scalePixelVector(transform.pixelOffset, xScale: xScale, yScale: yScale)
        scaled.macroPixelOffset = scalePixelVector(transform.macroPixelOffset, xScale: xScale, yScale: yScale)
        scaled.microPixelOffset = scalePixelVector(transform.microPixelOffset, xScale: xScale, yScale: yScale)
        scaled.strideWobblePixelOffset = scalePixelVector(transform.strideWobblePixelOffset, xScale: xScale, yScale: yScale)
        scaled.trajectoryMicroJitterPixelOffset = scalePixelVector(transform.trajectoryMicroJitterPixelOffset, xScale: xScale, yScale: yScale)
        scaled.trajectoryContinuityPixelOffset = scalePixelVector(transform.trajectoryContinuityPixelOffset, xScale: xScale, yScale: yScale)
        scaled.lensShakePixelOffset = scalePixelVector(transform.lensShakePixelOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandTopOffset = scalePixelVector(transform.lensBandTopOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRidgeOffset = scalePixelVector(transform.lensBandRidgeOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandMidOffset = scalePixelVector(transform.lensBandMidOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRawTopOffset = scalePixelVector(transform.lensBandRawTopOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRawRidgeOffset = scalePixelVector(transform.lensBandRawRidgeOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRawMidOffset = scalePixelVector(transform.lensBandRawMidOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandPulseDeltaTopOffset = scalePixelVector(transform.lensBandPulseDeltaTopOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandPulseDeltaRidgeOffset = scalePixelVector(transform.lensBandPulseDeltaRidgeOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandPulseDeltaMidOffset = scalePixelVector(transform.lensBandPulseDeltaMidOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandTopColumnOffset = scalePixelVector(transform.lensBandTopColumnOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRidgeColumnOffset = scalePixelVector(transform.lensBandRidgeColumnOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandMidColumnOffset = scalePixelVector(transform.lensBandMidColumnOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandTopRowPhaseOffset = scalePixelVector(transform.lensBandTopRowPhaseOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandRidgeRowPhaseOffset = scalePixelVector(transform.lensBandRidgeRowPhaseOffset, xScale: xScale, yScale: yScale)
        scaled.lensBandMidRowPhaseOffset = scalePixelVector(transform.lensBandMidRowPhaseOffset, xScale: xScale, yScale: yScale)
        scaled.lensFarFieldRigidShakeOffset = scalePixelVector(transform.lensFarFieldRigidShakeOffset, xScale: xScale, yScale: yScale)
        scaled.turnDetectedPixelOffset = scalePixelVector(transform.turnDetectedPixelOffset, xScale: xScale, yScale: yScale)
        scaled.rawPixelOffset = scalePixelVector(transform.rawPixelOffset, xScale: xScale, yScale: yScale)
        scaled.temporalSmoothingPixelDelta = scalePixelVector(transform.temporalSmoothingPixelDelta, xScale: xScale, yScale: yScale)
        scaled.rawFootstepCorrection = scalePixelVector(transform.rawFootstepCorrection, xScale: xScale, yScale: yScale)
        scaled.limitedFootstepCorrection = scalePixelVector(transform.limitedFootstepCorrection, xScale: xScale, yScale: yScale)
        scaled.footstepPulseLimited = scalePixelVector(transform.footstepPulseLimited, xScale: xScale, yScale: yScale)
        return scaled
    }

    private static func buildPlaybackTrajectory(
        analysis: StabilizerPreparedAnalysis,
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> PlaybackTransformTrajectory {
        let frames = analysis.frames
        guard frames.count >= 3 else {
            return PlaybackTransformTrajectory(
                times: frames.map(\.time),
                transforms: Array(repeating: .identity, count: frames.count),
                outputSize: outputSize
            )
        }
        let rawTransforms = preparedPlaybackTrajectoryRawTransforms(
            analysis: analysis,
            frames: frames,
            outputSize: outputSize,
            panSmoothSeconds: panSmoothSeconds,
            strengths: strengths
        )
        let transforms = frames.indices.map { index in
            playbackTrajectorySmoothedTransform(
                index: index,
                frames: frames,
                rawTransforms: rawTransforms,
                panSmoothSeconds: panSmoothSeconds,
                strengths: strengths
            )
        }
        let limitedTransforms = playbackTrajectoryZeroPhaseLimitedTransforms(
            frames: frames,
            rawTransforms: transforms,
            diagnosticTransforms: rawTransforms,
            preserveCurrentDiagnostics: false
        )
        let finalTransforms = playbackTrajectoryZeroPhaseLimitedTransforms(
            frames: frames,
            rawTransforms: limitedTransforms,
            diagnosticTransforms: rawTransforms,
            preserveCurrentDiagnostics: false
        )
        let landingShockLimited = playbackTrajectoryLandingShockLimitedTransforms(
            frames: frames,
            transforms: finalTransforms,
            diagnosticTransforms: rawTransforms,
            outputSize: outputSize
        )
        if landingShockLimited.pixelFrameCount > 0 || landingShockLimited.rotationFrameCount > 0 {
            os_log(
                "Playback trajectory landing-shock limit | pixelFrames %d rotationFrames %d maxPixel %.3f maxRotation %.4f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                landingShockLimited.pixelFrameCount,
                landingShockLimited.rotationFrameCount,
                landingShockLimited.maximumPixelDeviation,
                landingShockLimited.maximumRotationDeviation
            )
        }
        let despiked = playbackTrajectoryFrameCadenceDespikedTransforms(
            frames: frames,
            transforms: landingShockLimited.transforms,
            outputSize: outputSize
        )
        if despiked.pixelFrameCount > 0 || despiked.rotationFrameCount > 0 {
            os_log(
                "Playback trajectory frame-cadence despike | pixelFrames %d rotationFrames %d maxPixel %.3f maxRotation %.4f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                despiked.pixelFrameCount,
                despiked.rotationFrameCount,
                despiked.maximumPixelDeviation,
                despiked.maximumRotationDeviation
            )
        }
        let velocityCollapseGuarded = playbackTrajectoryVelocityCollapseGuardedTransforms(
            frames: frames,
            transforms: despiked.transforms,
            outputSize: outputSize
        )
        if velocityCollapseGuarded.pixelFrameCount > 0 {
            os_log(
                "Playback trajectory velocity-collapse guard | pixelFrames %d maxPixel %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                velocityCollapseGuarded.pixelFrameCount,
                velocityCollapseGuarded.maximumPixelDeviation
            )
        }
        let microJitterSuppressed = playbackTrajectoryMicroJitterSuppressedTransforms(
            frames: frames,
            transforms: velocityCollapseGuarded.transforms,
            outputSize: outputSize
        )
        if microJitterSuppressed.pixelFrameCount > 0 {
            os_log(
                "Playback trajectory micro-jitter suppression | pixelFrames %d maxPixel %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                microJitterSuppressed.pixelFrameCount,
                microJitterSuppressed.maximumPixelDeviation
            )
        }
        let postShockLimitedTransforms = playbackTrajectoryZeroPhaseLimitedTransforms(
            frames: frames,
            rawTransforms: microJitterSuppressed.transforms,
            diagnosticTransforms: rawTransforms,
            preserveCurrentDiagnostics: false
        )
        let componentDiagnostics = playbackTrajectoryComponentDiagnostics(
            frames: frames,
            transforms: postShockLimitedTransforms
        )
        os_log(
            "Playback trajectory component steps | frames %d final %.3f f%d t%.3f macro %.3f micro %.3f stride %.3f turn %.3f warp %.5f rot %.4f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            frames.count,
            componentDiagnostics.maximumFinalStepPixels,
            componentDiagnostics.maximumFinalStepFrameIndex,
            componentDiagnostics.maximumFinalStepSeconds,
            componentDiagnostics.maximumMacroStepPixels,
            componentDiagnostics.maximumMicroStepPixels,
            componentDiagnostics.maximumStrideStepPixels,
            componentDiagnostics.maximumTurnStepPixels,
            componentDiagnostics.maximumWarpStep,
            componentDiagnostics.maximumRotationStepDegrees
        )
        os_log(
            "Playback trajectory component jerk | frames %d final %.3f f%d t%.3f macro %.3f micro %.3f stride %.3f turn %.3f warp %.5f rot %.4f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            frames.count,
            componentDiagnostics.maximumFinalJerkPixels,
            componentDiagnostics.maximumFinalJerkFrameIndex,
            componentDiagnostics.maximumFinalJerkSeconds,
            componentDiagnostics.maximumMacroJerkPixels,
            componentDiagnostics.maximumMicroJerkPixels,
            componentDiagnostics.maximumStrideJerkPixels,
            componentDiagnostics.maximumTurnJerkPixels,
            componentDiagnostics.maximumWarpJerk,
            componentDiagnostics.maximumRotationJerkDegrees
        )
        return PlaybackTransformTrajectory(
            times: frames.map(\.time),
            transforms: postShockLimitedTransforms,
            outputSize: outputSize
        )
    }

    private static func playbackTrajectoryShortShockDespikedPath(
        _ values: [Float],
        frames: [StabilizerAnalysisFrame],
        minimumThreshold: Float,
        maximumCorrection: Float
    ) -> [Float] {
        guard values.count == frames.count,
              values.count >= 5,
              minimumThreshold.isFinite,
              minimumThreshold > Float.ulpOfOne,
              maximumCorrection.isFinite,
              maximumCorrection > Float.ulpOfOne
        else {
            return values
        }

        var predictions = values
        var deviations = Array(repeating: Float(0.0), count: values.count)
        for index in values.indices {
            guard let prediction = outerLinearPrediction(
                values,
                frames: frames,
                centerIndex: index,
                innerWindowSeconds: playbackTrajectoryFarFieldMacroDespikeInnerWindowSeconds,
                outerWindowSeconds: playbackTrajectoryFarFieldMacroDespikeOuterWindowSeconds
            ) else {
                continue
            }
            predictions[index] = prediction
            deviations[index] = abs(values[index] - prediction)
        }

        let localStepSeconds = localFrameStepSeconds(frames: frames, centerIndex: frames.count / 2)
        let radius = max(
            2,
            Int(Darwin.ceil(playbackTrajectoryFarFieldMacroDespikeLocalWindowSeconds / max(localStepSeconds, 1e-6)))
        )
        let maximumThreshold = minimumThreshold * 10.0
        var result = values
        for index in values.indices {
            let threshold = min(
                max(
                    minimumThreshold,
                    localMedian(
                        deviations,
                        centerIndex: index,
                        radius: radius
                    ) * playbackTrajectoryFarFieldMacroDespikeMadMultiplier
                ),
                maximumThreshold
            )
            let deviation = values[index] - predictions[index]
            let magnitude = abs(deviation)
            guard magnitude > threshold else {
                continue
            }
            let evidence = confidenceRamp(
                magnitude,
                start: threshold,
                full: max(threshold * 3.0, threshold + Float.ulpOfOne)
            )
            let blend = clamp(
                ((magnitude - threshold) / max(threshold * 2.0, Float.ulpOfOne)) * evidence,
                min: 0.0,
                max: playbackTrajectoryFarFieldMacroDespikeMaximumBlend
            )
            let correction = clamp(
                -deviation * blend,
                min: 0.0 - maximumCorrection,
                max: maximumCorrection
            )
            result[index] += correction
        }
        return result
    }

    private static func playbackTrajectoryFrameCadenceDespikedTransforms(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        outputSize: vector_float2
    ) -> PlaybackTrajectoryDespikeResult {
        guard frames.count == transforms.count,
              transforms.count >= 5
        else {
            return PlaybackTrajectoryDespikeResult(
                transforms: transforms,
                pixelFrameCount: 0,
                rotationFrameCount: 0,
                maximumPixelDeviation: 0.0,
                maximumRotationDeviation: 0.0
            )
        }

        var pixelXDeviations = Array(repeating: Float(0.0), count: transforms.count)
        var pixelYDeviations = Array(repeating: Float(0.0), count: transforms.count)
        var rotationDeviations = Array(repeating: Float(0.0), count: transforms.count)
        for index in 1..<(transforms.count - 1) {
            let fraction = interpolationFraction(
                previousTime: frames[index - 1].time,
                currentTime: frames[index].time,
                nextTime: frames[index + 1].time
            )
            let predictedPixel = transforms[index - 1].pixelOffset
                + ((transforms[index + 1].pixelOffset - transforms[index - 1].pixelOffset) * fraction)
            let predictedRotation = transforms[index - 1].rotationDegrees
                + ((transforms[index + 1].rotationDegrees - transforms[index - 1].rotationDegrees) * fraction)
            pixelXDeviations[index] = abs(transforms[index].pixelOffset.x - predictedPixel.x)
            pixelYDeviations[index] = abs(transforms[index].pixelOffset.y - predictedPixel.y)
            rotationDeviations[index] = abs(transforms[index].rotationDegrees - predictedRotation)
        }

        var result = transforms
        var pixelFrameCount = 0
        var rotationFrameCount = 0
        var maximumPixelDeviation = Float(0.0)
        var maximumRotationDeviation = Float(0.0)
        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let minimumPixelThreshold = max(
            playbackTrajectoryFrameCadenceDespikeMinimumPixels,
            outputReference * playbackTrajectoryFrameCadenceDespikeMinimumPixelFraction
        )
        let radius = max(1, playbackTrajectoryFrameCadenceDespikeWindowFrames / 2)

        for index in 1..<(transforms.count - 1) {
            let fraction = interpolationFraction(
                previousTime: frames[index - 1].time,
                currentTime: frames[index].time,
                nextTime: frames[index + 1].time
            )
            var transform = result[index]

            let predictedPixel = transforms[index - 1].pixelOffset
                + ((transforms[index + 1].pixelOffset - transforms[index - 1].pixelOffset) * fraction)
            let pixelDeviationX = transforms[index].pixelOffset.x - predictedPixel.x
            let pixelDeviationLengthX = abs(pixelDeviationX)
            let localPixelXThreshold = max(
                minimumPixelThreshold,
                localMedian(
                    pixelXDeviations,
                    centerIndex: index,
                    radius: radius
                ) * playbackTrajectoryFrameCadenceDespikeMadMultiplier
            )
            if pixelDeviationLengthX > localPixelXThreshold,
               playbackTrajectoryIsFrameCadenceSpike(
                   previous: transforms[index - 1].pixelOffset.x,
                   current: transforms[index].pixelOffset.x,
                   next: transforms[index + 1].pixelOffset.x
               ) {
                let excess = pixelDeviationLengthX - localPixelXThreshold
                let blend = clamp(
                    excess / max(localPixelXThreshold * 2.0, Float.ulpOfOne),
                    min: 0.25,
                    max: playbackTrajectoryFrameCadenceDespikeMaximumBlend
                )
                let correctionDelta = vector_float2(-pixelDeviationX * blend, 0.0)
                transform.pixelOffset += correctionDelta
                transform.microPixelOffset += correctionDelta
                transform.limitedFootstepCorrection += correctionDelta
                transform.temporalSmoothingPixelDelta += correctionDelta
                maximumPixelDeviation = max(maximumPixelDeviation, pixelDeviationLengthX)
            }

            let pixelDeviationY = transforms[index].pixelOffset.y - predictedPixel.y
            let pixelDeviationLengthY = abs(pixelDeviationY)
            let localPixelYThreshold = max(
                minimumPixelThreshold,
                localMedian(
                    pixelYDeviations,
                    centerIndex: index,
                    radius: radius
                ) * playbackTrajectoryFrameCadenceDespikeMadMultiplier
            )
            if pixelDeviationLengthY > localPixelYThreshold,
               playbackTrajectoryIsFrameCadenceSpike(
                   previous: transforms[index - 1].pixelOffset.y,
                   current: transforms[index].pixelOffset.y,
                   next: transforms[index + 1].pixelOffset.y
               ) {
                let excess = pixelDeviationLengthY - localPixelYThreshold
                let blend = clamp(
                    excess / max(localPixelYThreshold * 2.0, Float.ulpOfOne),
                    min: 0.25,
                    max: playbackTrajectoryFrameCadenceDespikeMaximumBlend
                )
                let correctionDelta = vector_float2(0.0, -pixelDeviationY * blend)
                transform.pixelOffset += correctionDelta
                transform.microPixelOffset += correctionDelta
                transform.limitedFootstepCorrection += correctionDelta
                transform.temporalSmoothingPixelDelta += correctionDelta
                maximumPixelDeviation = max(maximumPixelDeviation, pixelDeviationLengthY)
            }

            if simd_length(transform.pixelOffset - result[index].pixelOffset) > Float.ulpOfOne {
                pixelFrameCount += 1
            }

            let predictedRotation = transforms[index - 1].rotationDegrees
                + ((transforms[index + 1].rotationDegrees - transforms[index - 1].rotationDegrees) * fraction)
            let rotationDeviation = transforms[index].rotationDegrees - predictedRotation
            let rotationDeviationAbs = abs(rotationDeviation)
            let localRotationThreshold = max(
                playbackTrajectoryFrameCadenceDespikeMinimumRotationDegrees,
                localMedian(
                    rotationDeviations,
                    centerIndex: index,
                    radius: radius
                ) * playbackTrajectoryFrameCadenceDespikeMadMultiplier
            )
            if rotationDeviationAbs > localRotationThreshold,
               playbackTrajectoryIsFrameCadenceSpike(
                   previous: transforms[index - 1].rotationDegrees,
                   current: transforms[index].rotationDegrees,
                   next: transforms[index + 1].rotationDegrees
               ) {
                let excess = rotationDeviationAbs - localRotationThreshold
                let blend = clamp(
                    excess / max(localRotationThreshold * 2.0, Float.ulpOfOne),
                    min: 0.25,
                    max: playbackTrajectoryFrameCadenceDespikeMaximumBlend
                )
                let correctionDelta = -rotationDeviation * blend
                transform.rotationDegrees += correctionDelta
                transform.footstepJitterRotationDegrees += correctionDelta
                transform.temporalSmoothingRotationDelta += correctionDelta
                maximumRotationDeviation = max(maximumRotationDeviation, rotationDeviationAbs)
                rotationFrameCount += 1
            }

            result[index] = transform
        }

        return PlaybackTrajectoryDespikeResult(
            transforms: result,
            pixelFrameCount: pixelFrameCount,
            rotationFrameCount: rotationFrameCount,
            maximumPixelDeviation: maximumPixelDeviation,
            maximumRotationDeviation: maximumRotationDeviation
        )
    }

    private static func playbackTrajectoryVelocityCollapseGuardedTransforms(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        outputSize: vector_float2
    ) -> PlaybackTrajectoryDespikeResult {
        guard frames.count == transforms.count,
              transforms.count >= 5
        else {
            return PlaybackTrajectoryDespikeResult(
                transforms: transforms,
                pixelFrameCount: 0,
                rotationFrameCount: 0,
                maximumPixelDeviation: 0.0,
                maximumRotationDeviation: 0.0
            )
        }

        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let minimumStep = max(
            playbackTrajectoryVelocityCollapseMinimumPixels,
            outputReference * playbackTrajectoryVelocityCollapseMinimumPixelFraction
        )
        let maximumCorrection = max(
            playbackTrajectoryVelocityCollapseMaximumCorrectionPixels,
            outputReference * playbackTrajectoryVelocityCollapseMaximumCorrectionPixelFraction
        )
        let medianFrameStep = max(
            1e-6,
            localFrameStepSeconds(frames: frames, centerIndex: frames.count / 2)
        )
        let stepMagnitudesX = (1..<transforms.count).map { index in
            abs(transforms[index].pixelOffset.x - transforms[index - 1].pixelOffset.x)
        }
        let radius = max(1, playbackTrajectoryFrameCadenceDespikeWindowFrames / 2)

        func isNormalCadence(_ index: Int) -> Bool {
            guard frames.indices.contains(index - 1),
                  frames.indices.contains(index + 1)
            else {
                return false
            }
            let previousDelta = frames[index].time - frames[index - 1].time
            let nextDelta = frames[index + 1].time - frames[index].time
            guard previousDelta.isFinite,
                  nextDelta.isFinite,
                  previousDelta > 0.0,
                  nextDelta > 0.0
            else {
                return false
            }
            let low = medianFrameStep * 0.65
            let high = medianFrameStep * 1.55
            return previousDelta >= low
                && previousDelta <= high
                && nextDelta >= low
                && nextDelta <= high
        }

        func farFieldSupport(_ transform: StabilizerAutoTransform) -> Float {
            let edgeQuality = searchRadiusEdgeQuality(
                hitCount: transform.searchRadiusHitCount,
                totalCount: transform.searchRadiusTotalCount
            )
            return farFieldTurnOwnedWalkingXSupport(
                warpConfidence: transform.warpConfidence,
                trackingConfidence: max(transform.walkingTrackingConfidence, transform.trackingConfidence),
                edgeQuality: edgeQuality
            )
        }

        func sameDirection(_ a: Float, _ b: Float) -> Bool {
            guard a.isFinite, b.isFinite else {
                return false
            }
            return (a * b) > 0.0
        }

        func localStepThreshold(_ index: Int) -> Float {
            let stepIndex = max(0, min(stepMagnitudesX.count - 1, index - 1))
            return max(
                minimumStep,
                localMedian(
                    stepMagnitudesX,
                    centerIndex: stepIndex,
                    radius: radius
                ) * 0.72
            )
        }

        var result = transforms
        var pixelFrameCount = 0
        var candidateFrameCount = 0
        var supportRejectedFrameCount = 0
        var deviationRejectedFrameCount = 0
        var blendRejectedFrameCount = 0
        var maximumPixelDeviation = Float(0.0)
        var maximumBridgeMagnitude = Float(0.0)
        var maximumCandidateBridgeMagnitude = Float(0.0)
        var minimumCandidateSupport = Float.greatestFiniteMagnitude
        var maximumCorrectionMagnitude = Float(0.0)
        for index in 2..<(transforms.count - 2) where isNormalCadence(index) {
            let previous2 = transforms[index - 2].pixelOffset.x
            let previous = transforms[index - 1].pixelOffset.x
            let current = transforms[index].pixelOffset.x
            let next = transforms[index + 1].pixelOffset.x
            let next2 = transforms[index + 2].pixelOffset.x

            let incoming = current - previous
            let outgoing = next - current
            let previousOuter = previous - previous2
            let nextOuter = next2 - next
            let bridge = next - previous
            let bridgeMagnitude = abs(bridge)
            let threshold = localStepThreshold(index)
            maximumBridgeMagnitude = max(maximumBridgeMagnitude, bridgeMagnitude)
            guard bridgeMagnitude > max(minimumStep * 1.8, threshold),
                  abs(incoming).isFinite,
                  abs(outgoing).isFinite
            else {
                continue
            }

            let incomingMagnitude = abs(incoming)
            let outgoingMagnitude = abs(outgoing)
            let previousHold = incomingMagnitude <= max(minimumStep * 0.55, outgoingMagnitude * playbackTrajectoryVelocityCollapseMaximumStepRatio)
                && outgoingMagnitude >= threshold
                && sameDirection(previousOuter, outgoing)
            let nextHold = outgoingMagnitude <= max(minimumStep * 0.55, incomingMagnitude * playbackTrajectoryVelocityCollapseMaximumStepRatio)
                && incomingMagnitude >= threshold
                && sameDirection(incoming, nextOuter)
            guard previousHold || nextHold else {
                continue
            }
            candidateFrameCount += 1
            maximumCandidateBridgeMagnitude = max(maximumCandidateBridgeMagnitude, bridgeMagnitude)

            let support = min(
                farFieldSupport(transforms[index]),
                min(
                    farFieldSupport(transforms[index - 1]),
                    farFieldSupport(transforms[index + 1])
                )
            )
            minimumCandidateSupport = min(minimumCandidateSupport, support)
            guard support >= playbackTrajectoryVelocityCollapseMinimumFarFieldSupport else {
                supportRejectedFrameCount += 1
                continue
            }

            let fraction = interpolationFraction(
                previousTime: frames[index - 1].time,
                currentTime: frames[index].time,
                nextTime: frames[index + 1].time
            )
            let predicted = previous + (bridge * fraction)
            let deviation = current - predicted
            let deviationMagnitude = abs(deviation)
            guard deviationMagnitude > minimumStep * playbackTrajectoryVelocityCollapseMinimumDeviationScale else {
                deviationRejectedFrameCount += 1
                continue
            }

            let smallStep = min(incomingMagnitude, outgoingMagnitude)
            let largeStep = max(incomingMagnitude, outgoingMagnitude)
            let collapseSeverity = confidenceRamp(
                (largeStep - smallStep) / max(largeStep, Float.ulpOfOne),
                start: 0.50,
                full: 0.88
            )
            let turnScale = 1.0 - (0.35 * confidenceRamp(
                transforms[index].turnConfidence,
                start: 0.42,
                full: 0.86
            ))
            let blend = clamp(
                collapseSeverity * confidenceRamp(support, start: 0.18, full: 0.72) * turnScale,
                min: 0.0,
                max: playbackTrajectoryVelocityCollapseMaximumBlend
            )
            guard blend > 0.05 else {
                blendRejectedFrameCount += 1
                continue
            }

            let correction = clamp(
                -deviation * blend,
                min: -maximumCorrection,
                max: maximumCorrection
            )
            guard abs(correction) > Float.ulpOfOne else {
                continue
            }

            result[index].pixelOffset.x += correction
            result[index].macroPixelOffset.x += correction
            result[index].temporalSmoothingPixelDelta.x += correction
            maximumPixelDeviation = max(maximumPixelDeviation, deviationMagnitude)
            maximumCorrectionMagnitude = max(maximumCorrectionMagnitude, abs(correction))
            pixelFrameCount += 1
        }

        if candidateFrameCount > 0 || maximumBridgeMagnitude > minimumStep * 2.0 {
            let minimumSupportForLog = minimumCandidateSupport == Float.greatestFiniteMagnitude
                ? Float(0.0)
                : minimumCandidateSupport
            os_log(
                "Playback trajectory velocity-collapse scan | candidates %d applied %d supportReject %d deviationReject %d blendReject %d maxBridge %.3f maxCandidateBridge %.3f minCandidateSupport %.3f maxCorrection %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                candidateFrameCount,
                pixelFrameCount,
                supportRejectedFrameCount,
                deviationRejectedFrameCount,
                blendRejectedFrameCount,
                maximumBridgeMagnitude,
                maximumCandidateBridgeMagnitude,
                minimumSupportForLog,
                maximumCorrectionMagnitude
            )
        }

        return PlaybackTrajectoryDespikeResult(
            transforms: result,
            pixelFrameCount: pixelFrameCount,
            rotationFrameCount: 0,
            maximumPixelDeviation: maximumPixelDeviation,
            maximumRotationDeviation: 0.0
        )
    }

    private enum PlaybackMicroJitterAxis {
        case x
        case y
    }

    private struct PlaybackMicroJitterAxisStats {
        var candidateFrameCount = 0
        var appliedFrameCount = 0
        var supportRejectedFrameCount = 0
        var blendRejectedFrameCount = 0
        var turnRejectedFrameCount = 0
        var maximumHighFrequency = Float(0.0)
        var maximumCandidateHighFrequency = Float(0.0)
        var maximumCorrectionMagnitude = Float(0.0)
        var maximumTurnOwnership = Float(0.0)
        var minimumCandidateSupport = Float.greatestFiniteMagnitude
    }

    private static func playbackTrajectoryMicroJitterSuppressedTransforms(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        outputSize: vector_float2
    ) -> PlaybackTrajectoryDespikeResult {
        guard frames.count == transforms.count,
              transforms.count >= 5
        else {
            return PlaybackTrajectoryDespikeResult(
                transforms: transforms,
                pixelFrameCount: 0,
                rotationFrameCount: 0,
                maximumPixelDeviation: 0.0,
                maximumRotationDeviation: 0.0
            )
        }

        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let maximumCorrection = max(
            playbackTrajectoryMicroJitterMaximumCorrectionPixels,
            outputReference * playbackTrajectoryMicroJitterMaximumCorrectionPixelFraction
        )
        let halfWindowSeconds = max(
            playbackTrajectoryMicroJitterHalfWindowSeconds,
            localFrameStepSeconds(frames: frames, centerIndex: frames.count / 2) * 3.0
        )
        let sigma = max(halfWindowSeconds * 0.5, 1e-6)

        var result = transforms

        func lowFrequencyPath(_ values: [Float]) -> [Float] {
            var lowFrequency = values
            for index in transforms.indices {
                let centerTime = frames[index].time
                var weightedSum = Float(0.0)
                var totalWeight = Float(0.0)

                func accumulate(_ sampleIndex: Int) -> Bool {
                    let offset = frames[sampleIndex].time - centerTime
                    guard offset.isFinite,
                          abs(offset) <= halfWindowSeconds
                    else {
                        return false
                    }
                    let normalizedDistance = Float(offset / sigma)
                    let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
                    weightedSum += values[sampleIndex] * weight
                    totalWeight += weight
                    return true
                }

                _ = accumulate(index)
                if index > transforms.startIndex {
                    for sampleIndex in stride(from: index - 1, through: transforms.startIndex, by: -1) {
                        guard accumulate(sampleIndex) else {
                            break
                        }
                    }
                }
                if index < transforms.endIndex - 1 {
                    for sampleIndex in (index + 1)..<transforms.endIndex {
                        guard accumulate(sampleIndex) else {
                            break
                        }
                    }
                }
                if totalWeight > Float.ulpOfOne {
                    lowFrequency[index] = weightedSum / totalWeight
                }
            }
            return lowFrequency
        }

        func axisValue(_ vector: vector_float2, axis: PlaybackMicroJitterAxis) -> Float {
            switch axis {
            case .x: return vector.x
            case .y: return vector.y
            }
        }

        func applyAxisCorrection(index: Int, axis: PlaybackMicroJitterAxis, correction: Float) {
            switch axis {
            case .x:
                result[index].trajectoryMicroJitterPixelOffset.x += correction
                result[index].pixelOffset.x += correction
            case .y:
                result[index].trajectoryMicroJitterPixelOffset.y += correction
                result[index].pixelOffset.y += correction
            }
        }

        func suppressAxis(
            _ axis: PlaybackMicroJitterAxis,
            finalValues: [Float],
            lowFrequencyValues: [Float]
        ) -> PlaybackMicroJitterAxisStats {
            var stats = PlaybackMicroJitterAxisStats()
            for index in transforms.indices {
                let transform = transforms[index]
                let highFrequency = finalValues[index] - lowFrequencyValues[index]
                let highFrequencyMagnitude = abs(highFrequency)
                stats.maximumHighFrequency = max(stats.maximumHighFrequency, highFrequencyMagnitude)
                guard highFrequencyMagnitude >= playbackTrajectoryMicroJitterMinimumPixels else {
                    continue
                }
                stats.candidateFrameCount += 1
                stats.maximumCandidateHighFrequency = max(stats.maximumCandidateHighFrequency, highFrequencyMagnitude)
                if axis == .x {
                    let turnConfidence = clamp(transform.turnConfidence, min: 0.0, max: 1.0)
                    let turnOwnership = confidenceRamp(
                        abs(transform.turnDetectedPixelOffset.x),
                        start: turnMacroOwnershipBandStartPixels,
                        full: turnMacroOwnershipBandFullPixels
                    ) * turnConfidence
                    stats.maximumTurnOwnership = max(stats.maximumTurnOwnership, turnOwnership)
                    if turnConfidence >= playbackTrajectoryHorizontalMicroJitterTurnHardGateConfidence,
                       abs(transform.turnDetectedPixelOffset.x) >= turnMacroOwnershipBandStartPixels {
                        stats.turnRejectedFrameCount += 1
                        continue
                    }
                }

                let trackingSupport = confidenceRamp(
                    max(transform.walkingTrackingConfidence, transform.trackingConfidence),
                    start: 0.16,
                    full: 0.58
                )
                let microSupport = confidenceRamp(
                    abs(axisValue(transform.microPixelOffset, axis: axis)),
                    start: playbackTrajectoryMicroJitterMinimumPixels,
                    full: playbackTrajectoryMicroJitterFullPixels * 2.0
                )
                let evidenceSupport = max(
                    confidenceRamp(
                        highFrequencyMagnitude,
                        start: playbackTrajectoryMicroJitterMinimumPixels,
                        full: playbackTrajectoryMicroJitterFullPixels
                    ),
                    microSupport * 0.75
                )
                let support = trackingSupport * evidenceSupport
                stats.minimumCandidateSupport = min(stats.minimumCandidateSupport, support)
                guard support > 0.04 else {
                    stats.supportRejectedFrameCount += 1
                    continue
                }

                let blend = clamp(
                    support * playbackTrajectoryMicroJitterMaximumBlend,
                    min: 0.0,
                    max: playbackTrajectoryMicroJitterMaximumBlend
                )
                guard blend > 0.02 else {
                    stats.blendRejectedFrameCount += 1
                    continue
                }

                let correction = clamp(
                    -highFrequency * blend,
                    min: -maximumCorrection,
                    max: maximumCorrection
                )
                guard abs(correction) > Float.ulpOfOne else {
                    continue
                }

                applyAxisCorrection(index: index, axis: axis, correction: correction)
                stats.maximumCorrectionMagnitude = max(stats.maximumCorrectionMagnitude, abs(correction))
                stats.appliedFrameCount += 1
            }
            return stats
        }

        let finalX = transforms.map { $0.pixelOffset.x - $0.lensShakePixelOffset.x }
        let finalY = transforms.map { $0.pixelOffset.y - $0.lensShakePixelOffset.y }
        let xStats = suppressAxis(.x, finalValues: finalX, lowFrequencyValues: lowFrequencyPath(finalX))
        let yStats = suppressAxis(.y, finalValues: finalY, lowFrequencyValues: lowFrequencyPath(finalY))
        let candidateFrameCount = xStats.candidateFrameCount + yStats.candidateFrameCount
        let pixelFrameCount = xStats.appliedFrameCount + yStats.appliedFrameCount
        let maximumHighFrequency = max(xStats.maximumHighFrequency, yStats.maximumHighFrequency)
        let maximumCorrectionMagnitude = max(xStats.maximumCorrectionMagnitude, yStats.maximumCorrectionMagnitude)

        if candidateFrameCount > 0 || maximumHighFrequency > playbackTrajectoryMicroJitterMinimumPixels {
            let minimumXSupportForLog = xStats.minimumCandidateSupport == Float.greatestFiniteMagnitude
                ? Float(0.0)
                : xStats.minimumCandidateSupport
            let minimumYSupportForLog = yStats.minimumCandidateSupport == Float.greatestFiniteMagnitude
                ? Float(0.0)
                : yStats.minimumCandidateSupport
            os_log(
                "Playback trajectory micro-jitter scan | xCandidates %d xApplied %d xReject %d xTurnReject %d yCandidates %d yApplied %d yReject %d window %.3f maxHighFreq %.3f maxCandidateX %.3f maxCandidateY %.3f minXSupport %.3f minYSupport %.3f maxCorrectionX %.3f maxCorrectionY %.3f maxTurnOwnership %.3f",
                log: stabilizerHostAnalysisLog,
                type: .default,
                xStats.candidateFrameCount,
                xStats.appliedFrameCount,
                xStats.supportRejectedFrameCount + xStats.blendRejectedFrameCount,
                xStats.turnRejectedFrameCount,
                yStats.candidateFrameCount,
                yStats.appliedFrameCount,
                yStats.supportRejectedFrameCount + yStats.blendRejectedFrameCount,
                halfWindowSeconds,
                maximumHighFrequency,
                xStats.maximumCandidateHighFrequency,
                yStats.maximumCandidateHighFrequency,
                minimumXSupportForLog,
                minimumYSupportForLog,
                xStats.maximumCorrectionMagnitude,
                yStats.maximumCorrectionMagnitude,
                xStats.maximumTurnOwnership
            )
        }

        return PlaybackTrajectoryDespikeResult(
            transforms: result,
            pixelFrameCount: pixelFrameCount,
            rotationFrameCount: 0,
            maximumPixelDeviation: maximumCorrectionMagnitude,
            maximumRotationDeviation: 0.0
        )
    }

    private static func playbackTrajectoryComponentDiagnostics(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform]
    ) -> PlaybackTrajectoryComponentDiagnostics {
        var diagnostics = PlaybackTrajectoryComponentDiagnostics()
        guard frames.count == transforms.count,
              transforms.count >= 3
        else {
            return diagnostics
        }

        func record(
            _ value: Float,
            frameIndex: Int,
            seconds: Double,
            maximumValue: inout Float,
            maximumFrameIndex: inout Int,
            maximumSeconds: inout Double
        ) {
            guard value.isFinite, value > maximumValue else {
                return
            }
            maximumValue = value
            maximumFrameIndex = frameIndex
            maximumSeconds = seconds
        }

        func warpStep(_ lhs: StabilizerAutoTransform, _ rhs: StabilizerAutoTransform) -> Float {
            let yawPitch = lhs.yawPitchProxy - rhs.yawPitchProxy
            let shear = lhs.shear - rhs.shear
            let perspective = lhs.perspective - rhs.perspective
            return sqrt(
                dot(yawPitch, yawPitch)
                    + dot(shear, shear)
                    + dot(perspective, perspective)
            )
        }

        func warpJerk(
            previous: StabilizerAutoTransform,
            current: StabilizerAutoTransform,
            next: StabilizerAutoTransform
        ) -> Float {
            let yawPitch = next.yawPitchProxy - (current.yawPitchProxy * 2.0) + previous.yawPitchProxy
            let shear = next.shear - (current.shear * 2.0) + previous.shear
            let perspective = next.perspective - (current.perspective * 2.0) + previous.perspective
            return sqrt(
                dot(yawPitch, yawPitch)
                    + dot(shear, shear)
                    + dot(perspective, perspective)
            )
        }

        for index in 1..<transforms.count {
            let previous = transforms[index - 1]
            let current = transforms[index]
            let seconds = frames[index].time
            record(
                simd_length(current.pixelOffset - previous.pixelOffset),
                frameIndex: index,
                seconds: seconds,
                maximumValue: &diagnostics.maximumFinalStepPixels,
                maximumFrameIndex: &diagnostics.maximumFinalStepFrameIndex,
                maximumSeconds: &diagnostics.maximumFinalStepSeconds
            )
            diagnostics.maximumMacroStepPixels = max(
                diagnostics.maximumMacroStepPixels,
                simd_length(current.macroPixelOffset - previous.macroPixelOffset)
            )
            diagnostics.maximumMicroStepPixels = max(
                diagnostics.maximumMicroStepPixels,
                simd_length(current.microPixelOffset - previous.microPixelOffset)
            )
            diagnostics.maximumStrideStepPixels = max(
                diagnostics.maximumStrideStepPixels,
                simd_length(current.strideWobblePixelOffset - previous.strideWobblePixelOffset)
            )
            diagnostics.maximumTurnStepPixels = max(
                diagnostics.maximumTurnStepPixels,
                simd_length(current.turnDetectedPixelOffset - previous.turnDetectedPixelOffset)
            )
            diagnostics.maximumWarpStep = max(
                diagnostics.maximumWarpStep,
                warpStep(current, previous)
            )
            diagnostics.maximumRotationStepDegrees = max(
                diagnostics.maximumRotationStepDegrees,
                abs(current.rotationDegrees - previous.rotationDegrees)
            )
        }

        for index in 1..<(transforms.count - 1) {
            let previous = transforms[index - 1]
            let current = transforms[index]
            let next = transforms[index + 1]
            let seconds = frames[index].time
            record(
                simd_length(next.pixelOffset - (current.pixelOffset * 2.0) + previous.pixelOffset),
                frameIndex: index,
                seconds: seconds,
                maximumValue: &diagnostics.maximumFinalJerkPixels,
                maximumFrameIndex: &diagnostics.maximumFinalJerkFrameIndex,
                maximumSeconds: &diagnostics.maximumFinalJerkSeconds
            )
            diagnostics.maximumMacroJerkPixels = max(
                diagnostics.maximumMacroJerkPixels,
                simd_length(next.macroPixelOffset - (current.macroPixelOffset * 2.0) + previous.macroPixelOffset)
            )
            diagnostics.maximumMicroJerkPixels = max(
                diagnostics.maximumMicroJerkPixels,
                simd_length(next.microPixelOffset - (current.microPixelOffset * 2.0) + previous.microPixelOffset)
            )
            diagnostics.maximumStrideJerkPixels = max(
                diagnostics.maximumStrideJerkPixels,
                simd_length(next.strideWobblePixelOffset - (current.strideWobblePixelOffset * 2.0) + previous.strideWobblePixelOffset)
            )
            diagnostics.maximumTurnJerkPixels = max(
                diagnostics.maximumTurnJerkPixels,
                simd_length(next.turnDetectedPixelOffset - (current.turnDetectedPixelOffset * 2.0) + previous.turnDetectedPixelOffset)
            )
            diagnostics.maximumWarpJerk = max(
                diagnostics.maximumWarpJerk,
                warpJerk(previous: previous, current: current, next: next)
            )
            diagnostics.maximumRotationJerkDegrees = max(
                diagnostics.maximumRotationJerkDegrees,
                abs(next.rotationDegrees - (current.rotationDegrees * 2.0) + previous.rotationDegrees)
            )
        }

        return diagnostics
    }

    private static func playbackTrajectoryLandingShockLimitedTransforms(
        frames: [StabilizerAnalysisFrame],
        transforms: [StabilizerAutoTransform],
        diagnosticTransforms: [StabilizerAutoTransform],
        outputSize: vector_float2
    ) -> PlaybackTrajectoryDespikeResult {
        guard frames.count == transforms.count,
              transforms.count >= 5
        else {
            return PlaybackTrajectoryDespikeResult(
                transforms: transforms,
                pixelFrameCount: 0,
                rotationFrameCount: 0,
                maximumPixelDeviation: 0.0,
                maximumRotationDeviation: 0.0
            )
        }

        let diagnostics = diagnosticTransforms.count == transforms.count ? diagnosticTransforms : transforms
        let microX = transforms.map(\.microPixelOffset.x)
        let microY = transforms.map(\.microPixelOffset.y)
        let footstepRotation = transforms.map(\.footstepJitterRotationDegrees)
        var predictedMicroX = microX
        var predictedMicroY = microY
        var predictedRotation = footstepRotation
        var microXDeviation = Array(repeating: Float(0.0), count: transforms.count)
        var microYDeviation = Array(repeating: Float(0.0), count: transforms.count)
        var rotationDeviation = Array(repeating: Float(0.0), count: transforms.count)

        for index in transforms.indices {
            if let prediction = outerLinearPrediction(
                microX,
                frames: frames,
                centerIndex: index,
                innerWindowSeconds: playbackTrajectoryLandingShockInnerWindowSeconds,
                outerWindowSeconds: playbackTrajectoryLandingShockOuterWindowSeconds
            ) {
                predictedMicroX[index] = prediction
                microXDeviation[index] = abs(microX[index] - prediction)
            }
            if let prediction = outerLinearPrediction(
                microY,
                frames: frames,
                centerIndex: index,
                innerWindowSeconds: playbackTrajectoryLandingShockInnerWindowSeconds,
                outerWindowSeconds: playbackTrajectoryLandingShockOuterWindowSeconds
            ) {
                predictedMicroY[index] = prediction
                microYDeviation[index] = abs(microY[index] - prediction)
            }
            if let prediction = outerLinearPrediction(
                footstepRotation,
                frames: frames,
                centerIndex: index,
                innerWindowSeconds: playbackTrajectoryLandingShockInnerWindowSeconds,
                outerWindowSeconds: playbackTrajectoryLandingShockOuterWindowSeconds
            ) {
                predictedRotation[index] = prediction
                rotationDeviation[index] = abs(footstepRotation[index] - prediction)
            }
        }

        var result = transforms
        var pixelFrameCount = 0
        var rotationFrameCount = 0
        var maximumPixelDeviation = Float(0.0)
        var maximumRotationDeviation = Float(0.0)
        let outputReference = max(Float(1.0), min(outputSize.x, outputSize.y))
        let minimumPixelThreshold = max(
            playbackTrajectoryLandingShockMinimumPixels,
            outputReference * playbackTrajectoryLandingShockMinimumPixelFraction
        )
        let maximumPixelThreshold = minimumPixelThreshold * 8.0
        let maximumPixelCorrection = max(
            playbackTrajectoryLandingShockMaximumCorrectionPixels,
            outputReference * playbackTrajectoryLandingShockMaximumCorrectionPixelFraction
        )
        let localStepSeconds = localFrameStepSeconds(frames: frames, centerIndex: frames.count / 2)
        let radius = max(
            2,
            Int(Darwin.ceil(playbackTrajectoryLandingShockLocalNoiseWindowSeconds / max(localStepSeconds, 1e-6)))
        )

        for index in transforms.indices {
            var transform = result[index]
            let diagnostic = diagnostics[index]
            let turnSuppression = confidenceRamp(
                diagnostic.turnConfidence,
                start: playbackTrajectoryLandingShockTurnSuppressionStart,
                full: playbackTrajectoryLandingShockTurnSuppressionFull
            )
            let turnScale = 1.0 - (turnSuppression * 0.45)
            let trackingSupport = confidenceRamp(
                max(diagnostic.walkingTrackingConfidence, diagnostic.trackingConfidence),
                start: 0.10,
                full: 0.52
            )
            let qualityScale = max(0.50, trackingSupport)
            var changedPixel = false

            let xThreshold = min(
                max(
                    minimumPixelThreshold,
                    localMedian(
                        microXDeviation,
                        centerIndex: index,
                        radius: radius
                    ) * playbackTrajectoryLandingShockMadMultiplier
                ),
                maximumPixelThreshold
            )
            let xDeviation = microX[index] - predictedMicroX[index]
            let xCorrection = playbackTrajectoryLandingShockCorrection(
                deviation: xDeviation,
                threshold: xThreshold,
                maximumCorrection: maximumPixelCorrection,
                evidence: playbackTrajectoryLandingShockPixelEvidence(
                    deviation: abs(xDeviation),
                    threshold: xThreshold,
                    microStrength: diagnostic.effectiveMicroJitterStrength.x,
                    impulse: diagnostic.footstepImpulse.x
                ),
                qualityScale: qualityScale,
                turnScale: turnScale
            )
            if abs(xCorrection) > Float.ulpOfOne {
                transform.microPixelOffset.x += xCorrection
                transform.pixelOffset.x += xCorrection
                transform.limitedFootstepCorrection.x += xCorrection
                transform.temporalSmoothingPixelDelta.x += xCorrection
                maximumPixelDeviation = max(maximumPixelDeviation, abs(xDeviation))
                changedPixel = true
            }

            let yThreshold = min(
                max(
                    minimumPixelThreshold,
                    localMedian(
                        microYDeviation,
                        centerIndex: index,
                        radius: radius
                    ) * playbackTrajectoryLandingShockMadMultiplier
                ),
                maximumPixelThreshold
            )
            let yDeviation = microY[index] - predictedMicroY[index]
            let yCorrection = playbackTrajectoryLandingShockCorrection(
                deviation: yDeviation,
                threshold: yThreshold,
                maximumCorrection: maximumPixelCorrection,
                evidence: playbackTrajectoryLandingShockPixelEvidence(
                    deviation: abs(yDeviation),
                    threshold: yThreshold,
                    microStrength: diagnostic.effectiveMicroJitterStrength.y,
                    impulse: diagnostic.footstepImpulse.y
                ),
                qualityScale: qualityScale,
                turnScale: turnScale
            )
            if abs(yCorrection) > Float.ulpOfOne {
                transform.microPixelOffset.y += yCorrection
                transform.pixelOffset.y += yCorrection
                transform.limitedFootstepCorrection.y += yCorrection
                transform.temporalSmoothingPixelDelta.y += yCorrection
                maximumPixelDeviation = max(maximumPixelDeviation, abs(yDeviation))
                changedPixel = true
            }
            if changedPixel {
                pixelFrameCount += 1
            }

            let localRotationThreshold = min(
                max(
                    playbackTrajectoryLandingShockMinimumRotationDegrees,
                    localMedian(
                        rotationDeviation,
                        centerIndex: index,
                        radius: radius
                    ) * playbackTrajectoryLandingShockMadMultiplier
                ),
                playbackTrajectoryLandingShockMinimumRotationDegrees * 8.0
            )
            let rotationDelta = footstepRotation[index] - predictedRotation[index]
            let rotationCorrection = playbackTrajectoryLandingShockCorrection(
                deviation: rotationDelta,
                threshold: localRotationThreshold,
                maximumCorrection: playbackTrajectoryLandingShockMaximumCorrectionDegrees,
                evidence: playbackTrajectoryLandingShockRotationEvidence(
                    deviation: abs(rotationDelta),
                    threshold: localRotationThreshold,
                    microStrength: diagnostic.effectiveMicroJitterStrength.z,
                    impulse: diagnostic.footstepImpulse.z
                ),
                qualityScale: qualityScale,
                turnScale: turnScale
            )
            if abs(rotationCorrection) > Float.ulpOfOne {
                transform.footstepJitterRotationDegrees += rotationCorrection
                transform.rotationDegrees += rotationCorrection
                transform.temporalSmoothingRotationDelta += rotationCorrection
                maximumRotationDeviation = max(maximumRotationDeviation, abs(rotationDelta))
                rotationFrameCount += 1
            }

            result[index] = transform
        }

        return PlaybackTrajectoryDespikeResult(
            transforms: result,
            pixelFrameCount: pixelFrameCount,
            rotationFrameCount: rotationFrameCount,
            maximumPixelDeviation: maximumPixelDeviation,
            maximumRotationDeviation: maximumRotationDeviation
        )
    }

    private static func playbackTrajectoryLandingShockPixelEvidence(
        deviation: Float,
        threshold: Float,
        microStrength: Float,
        impulse: Float
    ) -> Float {
        let deviationSupport = confidenceRamp(
            deviation,
            start: threshold,
            full: max(threshold * 3.0, threshold + Float.ulpOfOne)
        ) * 0.75
        let strengthSupport = confidenceRamp(
            abs(microStrength),
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        let impulseSupport = confidenceRamp(
            abs(impulse),
            start: footstepImpulseFullScalePixels * 0.30,
            full: footstepImpulseFullScalePixels
        )
        return deviationSupport * max(strengthSupport, impulseSupport)
    }

    private static func playbackTrajectoryLandingShockRotationEvidence(
        deviation: Float,
        threshold: Float,
        microStrength: Float,
        impulse: Float
    ) -> Float {
        let deviationSupport = confidenceRamp(
            deviation,
            start: threshold,
            full: max(threshold * 3.0, threshold + Float.ulpOfOne)
        ) * 0.75
        let strengthSupport = confidenceRamp(
            abs(microStrength),
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        let impulseSupport = confidenceRamp(
            abs(impulse),
            start: footstepImpulseFullScaleDegrees * 0.30,
            full: footstepImpulseFullScaleDegrees
        )
        return deviationSupport * max(strengthSupport, impulseSupport)
    }

    private static func playbackTrajectoryLandingShockCorrection(
        deviation: Float,
        threshold: Float,
        maximumCorrection: Float,
        evidence: Float,
        qualityScale: Float,
        turnScale: Float
    ) -> Float {
        let deviationMagnitude = abs(deviation)
        guard deviation.isFinite,
              threshold.isFinite,
              maximumCorrection.isFinite,
              threshold > Float.ulpOfOne,
              maximumCorrection > Float.ulpOfOne,
              deviationMagnitude > threshold
        else {
            return 0.0
        }
        let excess = deviationMagnitude - threshold
        let baseBlend = clamp(
            excess / max(threshold * 2.0, Float.ulpOfOne),
            min: 0.0,
            max: playbackTrajectoryLandingShockMaximumBlend
        )
        let support = clamp(evidence * qualityScale * turnScale, min: 0.0, max: 1.0)
        guard support > 0.0001 else {
            return 0.0
        }
        let correction = -deviation * baseBlend * support
        return clamp(
            correction,
            min: 0.0 - maximumCorrection,
            max: maximumCorrection
        )
    }

    private static func interpolationFraction(
        previousTime: Double,
        currentTime: Double,
        nextTime: Double
    ) -> Float {
        let span = nextTime - previousTime
        guard span.isFinite,
              span > 1e-9,
              currentTime.isFinite
        else {
            return 0.5
        }
        return clamp(Float((currentTime - previousTime) / span), min: 0.0, max: 1.0)
    }

    private static func localMedian(
        _ values: [Float],
        centerIndex: Int,
        radius: Int
    ) -> Float {
        guard values.indices.contains(centerIndex) else {
            return 0.0
        }
        let lowerBound = max(values.startIndex, centerIndex - max(0, radius))
        let upperBound = min(values.endIndex - 1, centerIndex + max(0, radius))
        var window: [Float] = []
        window.reserveCapacity((upperBound - lowerBound) + 1)
        for index in lowerBound...upperBound {
            let value = values[index]
            if value.isFinite {
                window.append(value)
            }
        }
        guard let medianValue = median(window) else {
            return values[centerIndex].isFinite ? values[centerIndex] : 0.0
        }
        return medianValue
    }

    private static func playbackTrajectoryIsFrameCadenceSpike(
        previous: Float,
        current: Float,
        next: Float
    ) -> Bool {
        let incoming = current - previous
        let outgoing = next - current
        guard incoming.isFinite,
              outgoing.isFinite,
              abs(incoming) > Float.ulpOfOne,
              abs(outgoing) > Float.ulpOfOne
        else {
            return false
        }
        let directionReversal = (incoming * outgoing) < 0.0
        let imbalance = max(abs(incoming), abs(outgoing)) / max(min(abs(incoming), abs(outgoing)), Float.ulpOfOne)
        return directionReversal || imbalance >= 2.4
    }

    private static func preparedPlaybackTrajectoryRawTransforms(
        analysis: StabilizerPreparedAnalysis,
        frames: [StabilizerAnalysisFrame],
        outputSize: vector_float2,
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
    ) -> [StabilizerAutoTransform] {
        guard frames.count >= 3 else {
            return Array(repeating: .identity, count: frames.count)
        }

        let cache = renderEstimateCache(for: analysis)
        let allIndices = Array(frames.indices)
        let shortHalfWindow = max(renderFrameLocalSmoothingMinimumStepSeconds, renderFootstepJitterSmoothingWindowSeconds * 0.5)
        let mediumHalfWindow = max(shortHalfWindow, min(strideWobbleWindowSeconds * 0.28, 0.55))
        let broadHalfWindow = max(mediumHalfWindow, max(renderTemporalSmoothingWindowSeconds, panSmoothSeconds) * 0.5)
        let continuityWindowSeconds = max(strideWobbleWindowSeconds, panSmoothSeconds)
        let confidenceHalfWindow = min(0.36, max(0.18, strideWobbleWindowSeconds * 0.12))

        let footstepBaselineXPath = cachedOuterLinearPredictionPath(
            .footstepX,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineYPath = cachedOuterLinearPredictionPath(
            .footstepY,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let footstepBaselineRollPath = cachedOuterLinearPredictionPath(
            .footstepRoll,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineXPath = cachedOuterLinearPredictionPath(
            .farFieldX,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineYPath = cachedOuterLinearPredictionPath(
            .farFieldY,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineRollPath = cachedOuterLinearPredictionPath(
            .farFieldRoll,
            analysis: analysis,
            indices: allIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )

        let turnStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineXPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let turnStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineYPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let turnStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepTurnBaseline,
            source: footstepBaselineRollPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let footstepXTurnGateScales = turnOwnershipGateScales(
            values: turnStrideSmoothedXPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: continuityWindowSeconds,
            cache: cache
        )
        let footstepCleanXPath = confidenceCleanedFootstepPath(
            .footstepX,
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales,
            cache: cache
        )
        let footstepCleanYPath = confidenceCleanedFootstepPath(
            .footstepY,
            values: analysis.footstepPathY,
            baselineValues: footstepBaselineYPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let footstepCleanRollPath = confidenceCleanedFootstepPath(
            .footstepRoll,
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let farFieldCleanXPath = confidenceCleanedFootstepPath(
            .farFieldX,
            values: analysis.farFieldPathX,
            baselineValues: farFieldBaselineXPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales,
            cache: cache
        )
        let farFieldCleanYPath = confidenceCleanedFootstepPath(
            .farFieldY,
            values: analysis.farFieldPathY,
            baselineValues: farFieldBaselineYPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let farFieldCleanRollPath = confidenceCleanedFootstepPath(
            .farFieldRoll,
            values: analysis.farFieldPathRoll,
            baselineValues: farFieldBaselineRollPath,
            analysis: analysis,
            indices: allIndices,
            fullImpulseScale: footstepImpulseFullScaleDegrees,
            cache: cache
        )
        let strideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .footstepX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanXPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let strideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .footstepY,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanYPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let strideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .footstepRoll,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: footstepCleanRollPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .farFieldX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanXPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .farFieldY,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanYPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .farFieldRoll,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: continuityWindowSeconds.bitPattern,
            source: farFieldCleanRollPath,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: strideWobbleWindowSeconds
        )
        let broadWindowSeconds = broadHalfWindow * 2.0
        let xScale = outputSize.x / Float(max(1, frames[0].sampleWidth))
        let broadXBuild = adaptiveXTurnIntentPath(
            turnStrideSmoothedXPath,
            frames: frames,
            targetIndices: allIndices,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: broadWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let broadXPath = broadXBuild.path
        let broadYPath = turnIntentPath(
            turnStrideSmoothedYPath,
            frames: frames,
            targetIndices: allIndices,
            windowSeconds: broadWindowSeconds
        )
        let broadRollPath = turnIntentPath(
            turnStrideSmoothedRollPath,
            frames: frames,
            targetIndices: allIndices,
            windowSeconds: broadWindowSeconds
        )
        let rawFarFieldXPath = EstimatedPath(values: analysis.farFieldPathX)
        let rawFarFieldYPath = EstimatedPath(values: analysis.farFieldPathY)
        let rawFarFieldRollPath = EstimatedPath(values: analysis.farFieldPathRoll)
        let broadFarFieldXBuild = adaptiveXTurnIntentPath(
            rawFarFieldXPath,
            frames: frames,
            targetIndices: allIndices,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: broadWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let broadFarFieldXPath = broadFarFieldXBuild.path
        let broadFarFieldYPath = turnIntentPath(
            rawFarFieldYPath,
            frames: frames,
            targetIndices: allIndices,
            windowSeconds: broadWindowSeconds
        )
        let broadFarFieldRollPath = turnIntentPath(
            rawFarFieldRollPath,
            frames: frames,
            targetIndices: allIndices,
            windowSeconds: broadWindowSeconds
        )
        let adaptiveXTiming = broadXBuild.maxTiming.travelPixels >= broadFarFieldXBuild.maxTiming.travelPixels
            ? broadXBuild.maxTiming
            : broadFarFieldXBuild.maxTiming
        os_log(
            "Adaptive X turn timing | travel %.2f window %.3f active %{public}@ cropSpace %{public}@ pan %.3f",
            log: stabilizerHostAnalysisLog,
            type: .default,
            adaptiveXTiming.travelPixels,
            adaptiveXTiming.windowSeconds,
            adaptiveXTiming.active ? "yes" : "no",
            turnSmoothingZoomNormalized(strengths.turnSmoothingZoom) > Float.ulpOfOne ? "yes" : "no",
            panSmoothSeconds
        )
        let rawFarFieldPanBandXPath = frames.indices.map { index -> Float in
            guard analysis.farFieldPathX.indices.contains(index),
                  broadFarFieldXPath.values.indices.contains(index)
            else {
                return 0.0
            }
            return analysis.farFieldPathX[index] - broadFarFieldXPath[index]
        }
        let rawFarFieldPanBandYPath = frames.indices.map { index -> Float in
            guard analysis.farFieldPathY.indices.contains(index),
                  broadFarFieldYPath.values.indices.contains(index)
            else {
                return 0.0
            }
            return analysis.farFieldPathY[index] - broadFarFieldYPath[index]
        }
        let rawFarFieldPanBandRollPath = frames.indices.map { index -> Float in
            guard analysis.farFieldPathRoll.indices.contains(index),
                  broadFarFieldRollPath.values.indices.contains(index)
            else {
                return 0.0
            }
            return analysis.farFieldPathRoll[index] - broadFarFieldRollPath[index]
        }
        let farFieldPanBandXPath = playbackTrajectoryShortShockDespikedPath(
            rawFarFieldPanBandXPath,
            frames: frames,
            minimumThreshold: playbackTrajectoryFarFieldMacroDespikeMinimumPixels,
            maximumCorrection: playbackTrajectoryFarFieldMacroDespikeMaximumCorrectionPixels
        )
        let farFieldPanBandYPath = playbackTrajectoryShortShockDespikedPath(
            rawFarFieldPanBandYPath,
            frames: frames,
            minimumThreshold: playbackTrajectoryFarFieldMacroDespikeMinimumPixels,
            maximumCorrection: playbackTrajectoryFarFieldMacroDespikeMaximumCorrectionPixels
        )
        let farFieldPanBandRollPath = playbackTrajectoryShortShockDespikedPath(
            rawFarFieldPanBandRollPath,
            frames: frames,
            minimumThreshold: playbackTrajectoryFarFieldMacroDespikeMinimumRotationDegrees,
            maximumCorrection: playbackTrajectoryFarFieldMacroDespikeMaximumCorrectionDegrees
        )

        var trackingConfidences = Array(repeating: Float(0.0), count: frames.count)
        var walkingTrackingConfidences = Array(repeating: Float(0.0), count: frames.count)
        for index in frames.indices {
            let residual = analysis.residuals.indices.contains(index) ? analysis.residuals[index] : 0.0
            let blurAmount = analysis.blurAmounts.indices.contains(index) ? analysis.blurAmounts[index] : 0.0
            let motionConfidence = analysis.analysisConfidence.indices.contains(index) ? analysis.analysisConfidence[index] : 0.0
            let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(index) ? analysis.acceptedBlockCounts[index] : 0
            let totalBlockCount = analysis.totalBlockCounts.indices.contains(index) ? analysis.totalBlockCounts[index] : 0
            trackingConfidences[index] = frameTrackingConfidence(
                motionConfidence: motionConfidence,
                residual: residual,
                blurAmount: blurAmount,
                acceptedBlockCount: acceptedBlockCount,
                totalBlockCount: totalBlockCount,
                qualityModel: analysis.qualityModel
            )
            walkingTrackingConfidences[index] = walkingBandTrackingConfidence(
                motionConfidence: motionConfidence,
                residual: residual,
                blurAmount: blurAmount,
                acceptedBlockCount: acceptedBlockCount,
                totalBlockCount: totalBlockCount,
                qualityModel: analysis.qualityModel
            )
        }

        let rawPlaybackMicroBandYPath = frames.indices.map { index -> Float in
            let frame = frames[index]
            let renderSeconds = frame.time
            let searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(index) ? analysis.searchRadiusHitCounts[index] : 0
            let searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(index) ? analysis.searchRadiusTotalCounts[index] : 0
            let edgeQuality = searchRadiusEdgeQuality(
                hitCount: searchRadiusHitCount,
                totalCount: searchRadiusTotalCount
            )
            let walkingTrackingConfidence = walkingTrackingConfidences[index]
            let smoothedWalkingTrackingConfidence = playbackPreparedSmoothedValue(
                walkingTrackingConfidences,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: confidenceHalfWindow,
                sampleCount: 9
            )
            let strideContinuityConfidence = playbackContinuityConfidence(
                center: walkingTrackingConfidence,
                smoothed: smoothedWalkingTrackingConfidence
            )
            let farFieldMacroConfidence = clamp(
                playbackPreparedSmoothedValue(
                    analysis.farFieldConfidence,
                    frames: frames,
                    renderSeconds: renderSeconds,
                    halfWindow: mediumHalfWindow,
                    sampleCount: 13
                ),
                min: 0.0,
                max: 1.0
            )
            let smoothedWarpConfidence = clamp(
                playbackPreparedSmoothedValue(
                    analysis.warpConfidence,
                    frames: frames,
                    renderSeconds: renderSeconds,
                    halfWindow: mediumHalfWindow,
                    sampleCount: 13
                ),
                min: 0.0,
                max: 1.0
            )
            let farFieldBandBlend = farFieldWalkingBandBlend(
                farFieldConfidence: farFieldMacroConfidence,
                warpConfidence: smoothedWarpConfidence,
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                edgeQuality: edgeQuality
            )
            let footstepY = analysis.footstepPathY.indices.contains(index) ? analysis.footstepPathY[index] : 0.0
            let farFieldY = analysis.farFieldPathY.indices.contains(index) ? analysis.farFieldPathY[index] : 0.0
            return blendedFarFieldBand(
                footstepBand: footstepY - footstepBaselineYPath[index],
                farFieldBand: farFieldY - farFieldBaselineYPath[index],
                blend: farFieldBandBlend * farFieldWalkingBandBlendYScale,
                hasFarField: analysis.farFieldPathY.indices.contains(index)
            )
        }
        let playbackMicroBandYPath = frames.indices.map { index -> Float in
            let frame = frames[index]
            return playbackPreparedSmoothedValue(
                rawPlaybackMicroBandYPath,
                frames: frames,
                renderSeconds: frame.time,
                halfWindow: playbackTrajectoryMicroBandYSmoothingHalfWindowSeconds,
                sampleCount: 5
            )
        }
        let zeroPlaybackMicroBandYBaseline = EstimatedPath(values: Array(repeating: Float(0.0), count: frames.count))
        let footstepXConfidenceEvidence = footstepConfidenceEvidenceSeries(
            values: analysis.footstepPathX,
            baselineValues: footstepBaselineXPath,
            frames: frames,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepYConfidenceEvidence = footstepConfidenceEvidenceSeries(
            values: playbackMicroBandYPath,
            baselineValues: zeroPlaybackMicroBandYBaseline,
            frames: frames,
            fullImpulseScale: footstepImpulseFullScalePixels
        )
        let footstepRollConfidenceEvidence = footstepConfidenceEvidenceSeries(
            values: analysis.footstepPathRoll,
            baselineValues: footstepBaselineRollPath,
            frames: frames,
            fullImpulseScale: footstepImpulseFullScaleDegrees
        )

        let transforms = frames.indices.map { index in
            let frame = frames[index]
            let renderSeconds = frame.time
            let xScale = outputSize.x / Float(max(1, frame.sampleWidth))
            let yScale = outputSize.y / Float(max(1, frame.sampleHeight))
            let centerResidual = analysis.residuals.indices.contains(index) ? analysis.residuals[index] : 0.0
            let centerBlurAmount = analysis.blurAmounts.indices.contains(index) ? analysis.blurAmounts[index] : 0.0
            let motionConfidence = analysis.analysisConfidence.indices.contains(index) ? analysis.analysisConfidence[index] : 0.0
            let acceptedBlockCount = analysis.acceptedBlockCounts.indices.contains(index) ? analysis.acceptedBlockCounts[index] : 0
            let totalBlockCount = analysis.totalBlockCounts.indices.contains(index) ? analysis.totalBlockCounts[index] : 0
            let searchRadiusHitCount = analysis.searchRadiusHitCounts.indices.contains(index) ? analysis.searchRadiusHitCounts[index] : 0
            let searchRadiusTotalCount = analysis.searchRadiusTotalCounts.indices.contains(index) ? analysis.searchRadiusTotalCounts[index] : 0
            let edgeQuality = searchRadiusEdgeQuality(
                hitCount: searchRadiusHitCount,
                totalCount: searchRadiusTotalCount
            )
            let trackingConfidence = trackingConfidences[index]
            let walkingTrackingConfidence = walkingTrackingConfidences[index]
            let smoothedTrackingConfidence = playbackPreparedSmoothedValue(
                trackingConfidences,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: confidenceHalfWindow,
                sampleCount: 9
            )
            let smoothedWalkingTrackingConfidence = playbackPreparedSmoothedValue(
                walkingTrackingConfidences,
                frames: frames,
                renderSeconds: renderSeconds,
                halfWindow: confidenceHalfWindow,
                sampleCount: 9
            )
            let macroTrackingConfidence = playbackContinuityConfidence(
                center: trackingConfidence,
                smoothed: smoothedTrackingConfidence
            )
            let strideContinuityConfidence = playbackContinuityConfidence(
                center: walkingTrackingConfidence,
                smoothed: smoothedWalkingTrackingConfidence
            )
            let turnTrackingConfidence = residualAdjustedTrackingConfidence(
                macroTrackingConfidence,
                residual: centerResidual,
                multiplier: 0.9,
                qualityModel: analysis.qualityModel
            )
            let strideTrackingConfidence = residualAdjustedTrackingConfidence(
                strideContinuityConfidence,
                residual: centerResidual,
                multiplier: 0.6,
                qualityModel: analysis.qualityModel
            )

            let footstepX = analysis.footstepPathX.indices.contains(index) ? analysis.footstepPathX[index] : 0.0
            let footstepRoll = analysis.footstepPathRoll.indices.contains(index) ? analysis.footstepPathRoll[index] : 0.0
            let footstepBaselineX = footstepBaselineXPath[index]
            let footstepBaselineRoll = footstepBaselineRollPath[index]
            let cleanedFootstepX = footstepCleanXPath[index]
            let cleanedFootstepY = footstepCleanYPath[index]
            let cleanedFootstepRoll = footstepCleanRollPath[index]
            let mediumX = strideSmoothedXPath[index]
            let mediumY = strideSmoothedYPath[index]
            let mediumRoll = strideSmoothedRollPath[index]
            let broadX = broadXPath[index]
            let broadY = broadYPath[index]
            let broadRoll = broadRollPath[index]
            let farFieldX = analysis.farFieldPathX.indices.contains(index) ? analysis.farFieldPathX[index] : 0.0
            let farFieldRoll = analysis.farFieldPathRoll.indices.contains(index) ? analysis.farFieldPathRoll[index] : 0.0
            let farFieldBaselineX = farFieldBaselineXPath[index]
            let farFieldBaselineRoll = farFieldBaselineRollPath[index]
            let farFieldCleanedX = farFieldCleanXPath[index]
            let farFieldCleanedY = farFieldCleanYPath[index]
            let farFieldCleanedRoll = farFieldCleanRollPath[index]
            let farFieldMediumX = farFieldStrideSmoothedXPath[index]
            let farFieldMediumY = farFieldStrideSmoothedYPath[index]
            let farFieldMediumRoll = farFieldStrideSmoothedRollPath[index]
            let farFieldMacroConfidence = clamp(
                playbackPreparedSmoothedValue(
                    analysis.farFieldConfidence,
                    frames: frames,
                    renderSeconds: renderSeconds,
                    halfWindow: mediumHalfWindow,
                    sampleCount: 13
                ),
                min: 0.0,
                max: 1.0
            )
            let smoothedWarpConfidence = clamp(
                playbackPreparedSmoothedValue(
                    analysis.warpConfidence,
                    frames: frames,
                    renderSeconds: renderSeconds,
                    halfWindow: mediumHalfWindow,
                    sampleCount: 13
                ),
                min: 0.0,
                max: 1.0
            )
            let farFieldBandBlend = farFieldWalkingBandBlend(
                farFieldConfidence: farFieldMacroConfidence,
                warpConfidence: smoothedWarpConfidence,
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                edgeQuality: edgeQuality
            )
            let farFieldBandBlendX = farFieldBandBlend * farFieldWalkingBandBlendXScale
            let farFieldBandBlendY = farFieldBandBlend * farFieldWalkingBandBlendYScale
            let farFieldBandBlendRoll = farFieldBandBlend * farFieldWalkingBandBlendRollScale
            let footstepMicroBandX = footstepX - footstepBaselineX
            let footstepMicroBandRoll = footstepRoll - footstepBaselineRoll
            let farFieldMicroBandX = farFieldX - farFieldBaselineX
            let farFieldMicroBandRoll = farFieldRoll - farFieldBaselineRoll
            let microBandX = blendedFarFieldBand(
                footstepBand: footstepMicroBandX,
                farFieldBand: farFieldMicroBandX,
                blend: farFieldBandBlendX,
                hasFarField: analysis.farFieldPathX.indices.contains(index)
            )
            let microBandY = playbackMicroBandYPath[index]
            let microBandRoll = blendedFarFieldBand(
                footstepBand: footstepMicroBandRoll,
                farFieldBand: farFieldMicroBandRoll,
                blend: farFieldBandBlendRoll,
                hasFarField: analysis.farFieldPathRoll.indices.contains(index)
            )
            let footstepStrideBandX = cleanedFootstepX - mediumX
            let footstepStrideBandY = cleanedFootstepY - mediumY
            let footstepStrideBandRoll = cleanedFootstepRoll - mediumRoll
            let farFieldStrideBandX = farFieldCleanedX - farFieldMediumX
            let farFieldStrideBandY = farFieldCleanedY - farFieldMediumY
            let farFieldStrideBandRoll = farFieldCleanedRoll - farFieldMediumRoll
            let strideBandX = blendedFarFieldBand(
                footstepBand: footstepStrideBandX,
                farFieldBand: farFieldStrideBandX,
                blend: farFieldBandBlendX,
                hasFarField: analysis.farFieldPathX.indices.contains(index)
            )
            let strideBandY = blendedFarFieldBand(
                footstepBand: footstepStrideBandY,
                farFieldBand: farFieldStrideBandY,
                blend: farFieldBandBlendY,
                hasFarField: analysis.farFieldPathY.indices.contains(index)
            )
            let strideBandRoll = blendedFarFieldBand(
                footstepBand: footstepStrideBandRoll,
                farFieldBand: farFieldStrideBandRoll,
                blend: farFieldBandBlendRoll,
                hasFarField: analysis.farFieldPathRoll.indices.contains(index)
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
            let footstepPanBandX = mediumX - broadX
            let footstepPanBandY = mediumY - broadY
            let footstepPanBandRoll = mediumRoll - broadRoll
            let farFieldPanBandX = farFieldPanBandXPath[index]
            let farFieldPanBandY = farFieldPanBandYPath[index]
            let farFieldPanBandRoll = farFieldPanBandRollPath[index]
            let farFieldMacroBlend = confidenceRamp(
                farFieldMacroConfidence,
                start: farFieldMacroBlendConfidenceStart,
                full: farFieldMacroBlendConfidenceFull
            )
            let panBandX = footstepPanBandX + ((farFieldPanBandX - footstepPanBandX) * farFieldMacroBlend)
            let panBandY = footstepPanBandY + ((farFieldPanBandY - footstepPanBandY) * farFieldMacroBlend)
            let panBandRoll = footstepPanBandRoll + ((farFieldPanBandRoll - footstepPanBandRoll) * farFieldMacroBlend)
            let farFieldWalkingXSupport = farFieldTurnOwnedWalkingXSupport(
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                edgeQuality: edgeQuality
            )
            let playbackTurnOwnershipX = confidenceRamp(
                abs(panBandX * xScale),
                start: turnMacroOwnershipBandStartPixels,
                full: turnMacroOwnershipBandFullPixels
            ) * turnTrackingConfidence
            let turnXMacroPixels = abs(panBandX * xScale)
            let playbackTurnOwnershipY = confidenceRamp(
                abs(panBandY * yScale),
                start: turnMacroOwnershipBandStartPixels,
                full: turnMacroOwnershipBandFullPixels
            ) * turnTrackingConfidence
            let turnYMacroPixels = abs(panBandY * yScale)
            let playbackTurnShakeSuppression = turnStabilizerShakeSuppression(
                turnOwnership: playbackTurnOwnershipX,
                turnConfidence: playbackTurnOwnershipX
            )
            let baseFootstepXTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepXSuppression),
                min: 0.0,
                max: 1.0
            )
            let footstepYTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepYSuppression),
                min: 0.0,
                max: 1.0
            )
            let footstepRollTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipFootstepRollSuppression),
                min: 0.0,
                max: 1.0
            )
            let baseStrideXTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideXSuppression),
                min: 0.0,
                max: 1.0
            )
            let strideYTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideYSuppression),
                min: 0.0,
                max: 1.0
            )
            let strideRollTurnGate = clamp(
                1.0 - (playbackTurnShakeSuppression * turnOwnershipStrideRollSuppression),
                min: 0.0,
                max: 1.0
            )
            let rawFootstepXConfidenceBase = footstepConfidence(
                trackingConfidence: walkingTrackingConfidence,
                evidence: footstepXConfidenceEvidence.instant,
                index: index
            )
            let rawFootstepYConfidenceBase = footstepConfidence(
                trackingConfidence: walkingTrackingConfidence,
                evidence: footstepYConfidenceEvidence.instant,
                index: index
            )
            let rawFootstepRollConfidenceBase = footstepConfidence(
                trackingConfidence: walkingTrackingConfidence,
                evidence: footstepRollConfidenceEvidence.instant,
                index: index
            )
            let rawFootstepXConfidence = rawFootstepXConfidenceBase
            let rawFootstepYConfidence = rawFootstepYConfidenceBase
            let rawFootstepRollConfidence = rawFootstepRollConfidenceBase
            let turnOwnedFootstepXFineGate = turnOwnedFootstepXFineBandGate(
                bandPixels: microBandX * xScale,
                turnOwnership: playbackTurnOwnershipX
            )
            let footstepXTurnGateFloor = turnOwnedWalkingXGateFloor(
                rawConfidence: rawFootstepXConfidence,
                bandMagnitude: abs(microBandX * xScale),
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldWalkingXSupport
            )
            let strideXTurnGateFloor = turnOwnedWalkingXGateFloor(
                rawConfidence: rawStrideXConfidence,
                bandMagnitude: abs(strideBandX * xScale),
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldWalkingXSupport
            ) * turnOwnedStrideXGateFloorScale
            let footstepXTurnGate = max(baseFootstepXTurnGate, footstepXTurnGateFloor)
            let strideXTurnGate = max(baseStrideXTurnGate, strideXTurnGateFloor)
            let turnOwnedFootstepXConfidenceFloor = clamp(
                turnOwnedFarFieldXConfidenceFloorMax
                    * farFieldWalkingXSupport
                    * confidenceRamp(
                        abs(microBandX * xScale),
                        start: turnOwnedFarFieldXConfidenceFloorStartPixels,
                        full: turnOwnedFarFieldXConfidenceFloorFullPixels
                    )
                    * turnOwnedFootstepXFineGate,
                min: 0.0,
                max: turnOwnedFarFieldXConfidenceFloorMax
            )
            let footstepXWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
                bandPixels: microBandX * xScale,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldWalkingXSupport,
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                farFieldConfidence: farFieldMacroConfidence
            ) * turnOwnedFootstepXFineGate
            let footstepYWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
                bandPixels: microBandY * yScale,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipY,
                turnMacroMagnitude: turnYMacroPixels,
                farFieldSupport: farFieldWalkingXSupport,
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                farFieldConfidence: farFieldMacroConfidence
            )
            let farFieldFootstepXConfidenceFloor = max(
                turnOwnedFootstepXConfidenceFloor,
                max(
                    farFieldFootstepConfidenceFloor(
                        bandPixels: microBandX * xScale,
                        farFieldSupport: farFieldWalkingXSupport
                    ) * turnOwnedFootstepXFineGate,
                    max(
                        turnOwnedFootstepXRescueConfidenceFloor(
                            bandPixels: microBandX * xScale,
                            turnShakeSuppression: playbackTurnShakeSuppression,
                            turnOwnership: playbackTurnOwnershipX,
                            farFieldSupport: farFieldWalkingXSupport,
                            fineGate: turnOwnedFootstepXFineGate
                        ),
                        footstepXWalkingRescueConfidenceFloor
                    )
                )
            )
            let footstepYFarFieldConfidenceFloor = max(
                farFieldFootstepVerticalConfidenceFloor(
                    bandPixels: microBandY * yScale,
                    farFieldSupport: farFieldWalkingXSupport
                ),
                footstepYWalkingRescueConfidenceFloor
            )
            let footstepRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
                bandDegrees: microBandRoll,
                farFieldSupport: farFieldWalkingXSupport
            )
            let footstepXConfidence = max(rawFootstepXConfidence * footstepXTurnGate, farFieldFootstepXConfidenceFloor)
            let footstepYConfidence = max(rawFootstepYConfidence * footstepYTurnGate, footstepYFarFieldConfidenceFloor)
            let footstepRollConfidence = max(rawFootstepRollConfidence * footstepRollTurnGate, footstepRollFarFieldConfidenceFloor)
            let strideXBaseFarFieldConfidenceFloor = turnOwnedFarFieldWalkingXConfidenceFloor(
                bandMagnitude: abs(strideBandX * xScale),
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldWalkingXSupport
            ) * turnOwnedStrideXGateFloorScale
            let strideXRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
                bandPixels: strideBandX * xScale,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldWalkingXSupport,
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                farFieldConfidence: farFieldMacroConfidence
            )
            let strideYBaseFarFieldConfidenceFloor = farFieldFootstepVerticalConfidenceFloor(
                bandPixels: strideBandY * yScale,
                farFieldSupport: farFieldWalkingXSupport
            ) * farFieldStrideVerticalConfidenceFloorScale
            let strideYRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
                bandPixels: strideBandY * yScale,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: playbackTurnOwnershipY,
                turnMacroMagnitude: turnYMacroPixels,
                farFieldSupport: farFieldWalkingXSupport,
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                farFieldConfidence: farFieldMacroConfidence
            )
            let strideXFarFieldConfidenceFloor = max(strideXBaseFarFieldConfidenceFloor, strideXRescueConfidenceFloor)
            let strideYFarFieldConfidenceFloor = max(strideYBaseFarFieldConfidenceFloor, strideYRescueConfidenceFloor)
            let strideRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
                bandDegrees: strideBandRoll,
                farFieldSupport: farFieldWalkingXSupport
            ) * farFieldStrideRollConfidenceFloorScale
            let strideXConfidence = max(rawStrideXConfidence * strideXTurnGate, strideXFarFieldConfidenceFloor)
            let strideYConfidence = max(rawStrideYConfidence * strideYTurnGate, strideYFarFieldConfidenceFloor)
            let strideRollConfidence = max(rawStrideRollConfidence * strideRollTurnGate, strideRollFarFieldConfidenceFloor)
            let playbackMicroConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
            let playbackStrideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
            let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.turnSmoothingZoom, confidence: turnTrackingConfidence)
            let cameraJitterMacroYConfidence = turnSmoothingConfidence(
                bandValue: panBandY,
                trackingConfidence: turnTrackingConfidence
            )
            let cameraJitterMacroRollConfidence = turnSmoothingRotationConfidence(
                bandValue: panBandRoll,
                trackingConfidence: turnTrackingConfidence
            )
            let cameraJitterMacroYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(
                strengths.cameraJitterY,
                confidence: cameraJitterMacroYConfidence,
                maxStrength: 10.0
            )
            let cameraJitterMacroRollCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(
                strengths.cameraJitterRotation,
                confidence: cameraJitterMacroRollConfidence
            )
            let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
            let microYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
            let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
            let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
            let strideYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
            let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)

            let macroPixelOffset = vector_float2(
                softLimit(
                    -panBandX * xScale * positionGain * panCorrectionStrengthX,
                    limit: turnSmoothingXOffsetLimit(
                        outputPixels: outputSize.x,
                        turnSmoothingStrength: strengths.turnSmoothingZoom
                    )
                ),
                0.0
            )
            // TURN owns only X. The remaining broad Y/roll trajectory belongs
            // to Camera Jitter and follows its own axis strengths.
            let cameraJitterMacroPixelOffset = vector_float2(
                0.0,
                -panBandY * yScale * positionGain * cameraJitterMacroYCorrectionStrength
            )
            let cameraJitterMacroRotation = -panBandRoll * rotationGain * cameraJitterMacroRollCorrectionStrength
            let microPixelLimitX = max(2.0, outputSize.x * 0.055)
            let microPixelLimitY = max(2.0, outputSize.y * 0.055)
            let unattenuatedRawMicroPixelOffsetX = -microBandX * xScale * microXCorrectionStrength
            let lowEvidenceMicroXScale = lowEvidenceLargeFootstepXScale(
                rawConfidence: max(rawFootstepXConfidence, farFieldFootstepXConfidenceFloor),
                correctionPixels: unattenuatedRawMicroPixelOffsetX,
                farFieldSupport: farFieldWalkingXSupport
            )
            let effectiveMicroXCorrectionStrength = microXCorrectionStrength * lowEvidenceMicroXScale
            let rawMicroPixelOffsetX = -microBandX * xScale * effectiveMicroXCorrectionStrength
            let rawMicroPixelOffsetY = -microBandY * yScale * microYCorrectionStrength
            let footstepXContinuityConfidenceScale = max(footstepXTurnGate, farFieldWalkingXSupport)
            let footstepYContinuityConfidenceScale = max(footstepYTurnGate, farFieldWalkingXSupport)
            let limitedMicroPixelOffsetX = strengths.microJitterX > 0.0
                ? footstepContinuityLimitedCorrection(
                    .footstepX,
                    values: analysis.footstepPathX,
                    baselineValues: footstepBaselineXPath,
                    analysis: analysis,
                    centerTime: renderSeconds,
                    rawCorrection: rawMicroPixelOffsetX,
                    outputScale: xScale,
                    requestedStrength: strengths.microJitterX,
                    fullImpulseScale: footstepImpulseFullScalePixels,
                    confidenceScale: footstepXContinuityConfidenceScale,
                    confidenceFloor: farFieldFootstepXConfidenceFloor,
                    trackingConfidences: walkingTrackingConfidences,
                    stableConfidenceEvidence: footstepXConfidenceEvidence.stable,
                    cache: cache
                )
                : FootstepContinuityLimitResult(limitedCorrection: rawMicroPixelOffsetX, limitedAmount: 0.0)
            let limitedMicroPixelOffsetY = strengths.microJitterY > 0.0
                ? footstepContinuityLimitedCorrection(
                    .footstepY,
                    values: playbackMicroBandYPath,
                    baselineValues: zeroPlaybackMicroBandYBaseline,
                    analysis: analysis,
                    centerTime: renderSeconds,
                    rawCorrection: rawMicroPixelOffsetY,
                    outputScale: yScale,
                    requestedStrength: strengths.microJitterY,
                    fullImpulseScale: footstepImpulseFullScalePixels,
                    confidenceScale: footstepYContinuityConfidenceScale,
                    trackingConfidences: walkingTrackingConfidences,
                    stableConfidenceEvidence: footstepYConfidenceEvidence.stable,
                    cache: cache
                )
                : FootstepContinuityLimitResult(limitedCorrection: rawMicroPixelOffsetY, limitedAmount: 0.0)
            let microPixelOffset = vector_float2(
                softLimit(limitedMicroPixelOffsetX.limitedCorrection, limit: microPixelLimitX),
                softLimit(limitedMicroPixelOffsetY.limitedCorrection, limit: microPixelLimitY)
            )
            let microRotation = softLimit(
                -microBandRoll * microRotationCorrectionStrength,
                limit: 0.55
            )
            let stridePixelOffset = vector_float2(
                softLimit(
                    -strideBandX * xScale * strideXCorrectionStrength,
                    limit: microPixelLimitX * 1.25
                ),
                softLimit(
                    -strideBandY * yScale * strideYCorrectionStrength,
                    limit: microPixelLimitY * 1.25
                )
            )
            let strideRotation = softLimit(
                -strideBandRoll * strideRotationCorrectionStrength,
                limit: 0.70
            )
            let farFieldWarpStrengths = effectiveFarFieldWarpComponentStrengths(Float(strengths.farFieldWarp))
            let rawWarpConfidence = analysis.warpConfidence.indices.contains(index) ? analysis.warpConfidence[index] : 0.0
            let farFieldWarpGateWindowIndices = indicesWithinTimeRadius(
                frames,
                centerTime: renderSeconds,
                radiusSeconds: farFieldWarpOuterWindowSeconds * 0.5
            )
            let farFieldWarpGateActiveIndices = farFieldWarpGateWindowIndices.isEmpty ? [index] : farFieldWarpGateWindowIndices
            let farFieldWarpTrackingConfidence = stableFarFieldWarpTrackingConfidence(
                analysis: analysis,
                indices: farFieldWarpGateActiveIndices,
                currentTrackingConfidence: macroTrackingConfidence
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
                currentWarpConfidence: rawWarpConfidence
            )
            let farFieldWarpGate = farFieldWarpRenderGate(
                warpConfidence: stableWarpConfidence,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )
            let farFieldWarpTurnGate: Float = 1.0
            let appliedWarpConfidence = farFieldWarpAppliedConfidence(
                stableWarpConfidence: stableWarpConfidence,
                warpGate: farFieldWarpGate,
                turnGate: farFieldWarpTurnGate,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )
            let warpHalfWindow = renderFarFieldWarpSmoothingWindowSeconds * 0.5
            func preparedWarpBand(_ values: [Float], deadband: Float, strength: Float, limit: Float) -> Float {
                guard strength > 0.0,
                      appliedWarpConfidence > 0.0,
                      values.indices.contains(index)
                else {
                    return 0.0
                }
                let baseline = playbackPreparedSmoothedValue(
                    values,
                    frames: frames,
                    renderSeconds: renderSeconds,
                    halfWindow: warpHalfWindow,
                    sampleCount: 7
                )
                let scaled = softDeadband(values[index] - baseline, threshold: deadband)
                    * appliedWarpConfidence
                    * strength
                return clamp(scaled, min: -limit * strength, max: limit * strength)
            }
            let yawPitchProxy = vector_float2(
                preparedWarpBand(
                    analysis.pathYaw,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                ),
                preparedWarpBand(
                    analysis.pathPitch,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                )
            )
            let shear = vector_float2(
                preparedWarpBand(
                    analysis.pathShearX,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                ),
                preparedWarpBand(
                    analysis.pathShearY,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                )
            )
            let perspective = vector_float2(
                preparedWarpBand(
                    analysis.pathPerspectiveX,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                ),
                preparedWarpBand(
                    analysis.pathPerspectiveY,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                )
            )

            let trajectoryMicroJitterPixelOffset = farFieldWalkingResidualContinuityOffset(
                footstepBandPixels: vector_float2(microBandX * xScale, microBandY * yScale),
                footstepCorrectionPixels: microPixelOffset,
                strideBandPixels: vector_float2(strideBandX * xScale, strideBandY * yScale),
                strideCorrectionPixels: stridePixelOffset,
                turnShakeSuppression: playbackTurnShakeSuppression,
                turnOwnership: vector_float2(playbackTurnOwnershipX, playbackTurnOwnershipY),
                turnMacroMagnitude: vector_float2(turnXMacroPixels, turnYMacroPixels),
                farFieldSupport: farFieldWalkingXSupport,
                warpConfidence: max(smoothedWarpConfidence, farFieldMacroConfidence),
                trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                farFieldConfidence: farFieldMacroConfidence
            )
            let trajectoryContinuityPixelOffset = cameraJitterMacroPixelOffset
            let cameraJitterPixelOffset = microPixelOffset
                + stridePixelOffset
                + trajectoryMicroJitterPixelOffset
                + trajectoryContinuityPixelOffset
            let cameraJitterRotation = cameraJitterMacroRotation + microRotation + strideRotation
            let lensShake = farFieldWarpStrengths.isActive
                ? sourceSpaceLensShakeCorrection(
                    analysis: analysis,
                    frames: frames,
                    interpolation: FrameInterpolation(lowerIndex: index, upperIndex: index, fraction: 0.0),
                    outputScale: vector_float2(xScale, yScale),
                    warpConfidence: appliedWarpConfidence,
                    farFieldConfidence: farFieldMacroConfidence,
                    trackingConfidence: max(strideContinuityConfidence, smoothedWalkingTrackingConfidence),
                    edgeQuality: farFieldWarpEdgeQuality,
                    turnShakeSuppression: playbackTurnShakeSuppression,
                    turnOwnership: vector_float2(playbackTurnOwnershipX, playbackTurnOwnershipY),
                    cache: cache
                )
                : SourceSpaceLensShakeCorrection()
            let pixelOffset = macroPixelOffset
                + cameraJitterPixelOffset
                + lensShake.pixelOffset
            let rotation = cameraJitterRotation + lensShake.rotationDegrees
            return StabilizerAutoTransform(
                pixelOffset: pixelOffset,
                macroPixelOffset: macroPixelOffset,
                microPixelOffset: cameraJitterPixelOffset,
                strideWobblePixelOffset: vector_float2(0.0, 0.0),
                trajectoryMicroJitterPixelOffset: vector_float2(0.0, 0.0),
                trajectoryContinuityPixelOffset: vector_float2(0.0, 0.0),
                lensShakePixelOffset: lensShake.pixelOffset,
                lensShakeRotationDegrees: lensShake.rotationDegrees,
                lensShakeYawPitch: lensShake.yawPitch,
                lensShakeShear: lensShake.shear,
                lensShakePerspective: lensShake.perspective,
                lensShakeScore: lensShake.score,
                lensShakeSupport: lensShake.support,
                lensShakeWindowFrames: lensShake.windowFrames,
                lensShakeWindowSeconds: lensShake.windowSeconds,
                lensShakeAxisMask: lensShake.axisMask,
                lensShakeReasonCode: lensShake.reasonCode,
                lensShakeRollingShutterCandidate: lensShake.rollingShutterCandidate,
                lensBandTopOffset: lensShake.bandTopOffset,
                lensBandRidgeOffset: lensShake.bandRidgeOffset,
                lensBandMidOffset: lensShake.bandMidOffset,
                lensBandRawTopOffset: lensShake.bandRawTopOffset,
                lensBandRawRidgeOffset: lensShake.bandRawRidgeOffset,
                lensBandRawMidOffset: lensShake.bandRawMidOffset,
                lensBandPulseDeltaTopOffset: lensShake.bandPulseDeltaTopOffset,
                lensBandPulseDeltaRidgeOffset: lensShake.bandPulseDeltaRidgeOffset,
                lensBandPulseDeltaMidOffset: lensShake.bandPulseDeltaMidOffset,
                lensBandPulseWindowFrames: lensShake.bandPulseWindowFrames,
                lensBandTopColumnOffset: lensShake.bandTopColumnOffset,
                lensBandRidgeColumnOffset: lensShake.bandRidgeColumnOffset,
                lensBandMidColumnOffset: lensShake.bandMidColumnOffset,
                lensBandTopRowPhaseOffset: lensShake.bandTopRowPhaseOffset,
                lensBandRidgeRowPhaseOffset: lensShake.bandRidgeRowPhaseOffset,
                lensBandMidRowPhaseOffset: lensShake.bandMidRowPhaseOffset,
                lensBandTopLocalRoll: lensShake.bandTopLocalRoll,
                lensBandRidgeLocalRoll: lensShake.bandRidgeLocalRoll,
                lensBandMidLocalRoll: lensShake.bandMidLocalRoll,
                lensBandWarpSupport: lensShake.bandWarpSupport,
                lensBandWarpApplied: lensShake.bandWarpApplied,
                lensBandRollingShutterScore: lensShake.bandRollingShutterScore,
                lensBandModelMask: lensShake.bandModelMask,
                lensFarFieldRigidShakeOffset: lensShake.farFieldRigidOffset,
                lensFarFieldRigidShakeSupport: lensShake.farFieldRigidSupport,
                lensFarFieldRigidShakeApplied: lensShake.farFieldRigidApplied,
                lensFarFieldRigidShakeShapeConsistency: lensShake.farFieldRigidShapeConsistency,
                lensFarFieldRigidShakeForwardBackwardConsistency: lensShake.farFieldRigidForwardBackwardConsistency,
                lensFarFieldRigidShakeLocalWarpSuppressed: lensShake.farFieldRigidLocalWarpSuppressed,
                lensFarFieldRigidXQuiverScore: lensShake.farFieldRigidXQuiverScore,
                lensFarFieldRigidXBeforeLimiter: lensShake.farFieldRigidXBeforeLimiter,
                lensFarFieldRigidXAfterLimiter: lensShake.farFieldRigidXAfterLimiter,
                lensFarFieldRigidRollResidual: lensShake.farFieldRigidRollResidual,
                lensFarFieldRigidRollSupport: lensShake.farFieldRigidRollSupport,
                lensFarFieldRigidGlobalYOffset: lensShake.farFieldRigidGlobalYOffset,
                lensFarFieldRigidGlobalRollDegrees: lensShake.farFieldRigidGlobalRollDegrees,
                lensFarFieldRigidRollApplied: lensShake.farFieldRigidRollApplied,
                lensFarFieldMeshOffset: lensShake.farFieldMeshOffset,
                lensFarFieldMeshSupport: lensShake.farFieldMeshSupport,
                lensFarFieldMeshBlend: lensShake.farFieldMeshBlend,
                lensFarFieldMeshAvailable: lensShake.farFieldMeshAvailable,
                lensFarFieldMeshSupportedBins: lensShake.farFieldMeshSupportedBins,
                lensFarFieldMeshMaxBinDelta: lensShake.farFieldMeshMaxBinDelta,
                lensFarFieldMeshOpposingBins: lensShake.farFieldMeshOpposingBins,
                lensFarFieldMeshDominantWindowFrames: lensShake.farFieldMeshDominantWindowFrames,
                lensFarFieldMeshDominantWindowSeconds: lensShake.farFieldMeshDominantWindowSeconds,
                lensFarFieldMeshDominantSupport: lensShake.farFieldMeshDominantSupport,
                lensFarFieldMeshDominantCell: lensShake.farFieldMeshDominantCell,
            sourceLensShakeRidgeOffset: lensShake.sourceRidgeOffset,
            sourceLensShakeRidgeSupport: lensShake.sourceRidgeSupport,
            sourceLensShakeRidgeApplied: lensShake.sourceRidgeApplied,
            sourceLensShakeRidgeLineResidual: lensShake.sourceRidgeLineResidual,
            sourceLensShakeRidgeLineOffset: lensShake.sourceRidgeLineOffset,
            sourceLensShakeRidgeLineSupport: lensShake.sourceRidgeLineSupport,
            sourceLensShakeRidgeLineBandSupported: lensShake.sourceRidgeLineBandSupported,
            sourceLensShakeRidgeLineApplied: lensShake.sourceRidgeLineApplied,
            sourceLensShakeLocalTopLeftOffset: lensShake.localTopLeftOffset,
            sourceLensShakeLocalTopCenterOffset: lensShake.localTopCenterOffset,
            sourceLensShakeLocalTopRightOffset: lensShake.localTopRightOffset,
            sourceLensShakeLocalRidgeLeftOffset: lensShake.localRidgeLeftOffset,
            sourceLensShakeLocalRidgeCenterOffset: lensShake.localRidgeCenterOffset,
            sourceLensShakeLocalRidgeRightOffset: lensShake.localRidgeRightOffset,
            sourceLensShakeLocalMidLeftOffset: lensShake.localMidLeftOffset,
            sourceLensShakeLocalMidCenterOffset: lensShake.localMidCenterOffset,
            sourceLensShakeLocalMidRightOffset: lensShake.localMidRightOffset,
            sourceLensShakeLocalSupport: lensShake.localSupport,
            sourceLensShakeLocalApplied: lensShake.localApplied,
                footstepJitterRotationDegrees: cameraJitterRotation,
                strideWobbleRotationDegrees: 0.0,
                rotationDegrees: rotation,
                turnDetectedPixelOffset: vector_float2(-panBandX * xScale, 0.0),
                rawPixelOffset: pixelOffset,
                rawRotationDegrees: rotation,
                temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
                temporalSmoothingRotationDelta: 0.0,
                temporalSmoothingSampleCount: 25,
                temporalSmoothingWindowSeconds: Float(broadHalfWindow * 2.0),
                effectiveMicroJitterStrength: vector_float3(
                    max(effectiveMicroXCorrectionStrength, strideXCorrectionStrength),
                    max(max(microYCorrectionStrength, strideYCorrectionStrength), cameraJitterMacroYCorrectionStrength),
                    max(max(microRotationCorrectionStrength, strideRotationCorrectionStrength), cameraJitterMacroRollCorrectionStrength)
                ),
                effectiveStrideWobbleStrength: vector_float3(0.0, 0.0, 0.0),
                warpConfidence: appliedWarpConfidence,
                microConfidence: max(
                    max(playbackMicroConfidence, playbackStrideConfidence),
                    max(cameraJitterMacroYConfidence, cameraJitterMacroRollConfidence)
                ),
                strideConfidence: 0.0,
                turnConfidence: turnTrackingConfidence,
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
                footstepImpulse: vector_float3(microBandX, microBandY, microBandRoll),
                rawFootstepCorrection: vector_float2(
                    rawMicroPixelOffsetX,
                    rawMicroPixelOffsetY
                ),
                limitedFootstepCorrection: cameraJitterPixelOffset,
                footstepPulseLimited: vector_float2(
                    limitedMicroPixelOffsetX.limitedAmount,
                    limitedMicroPixelOffsetY.limitedAmount
                ),
                searchRadiusHitCount: searchRadiusHitCount,
                searchRadiusTotalCount: searchRadiusTotalCount
            )
        }
        return transforms
    }

    private static func playbackTrajectoryZeroPhaseLimitedTransforms(
        frames: [StabilizerAnalysisFrame],
        rawTransforms: [StabilizerAutoTransform],
        diagnosticTransforms: [StabilizerAutoTransform]? = nil,
        preserveCurrentDiagnostics: Bool
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
                deltaSeconds: deltaSeconds,
                preserveCurrentDiagnostics: preserveCurrentDiagnostics
            )
        }

        var backward = rawTransforms
        if rawTransforms.count > 1 {
            for index in stride(from: rawTransforms.count - 2, through: 0, by: -1) {
                let deltaSeconds = max(0.0, frames[index + 1].time - frames[index].time)
                backward[index] = playbackTrajectoryLimitedTransform(
                    rawTransforms[index],
                    previous: backward[index + 1],
                    deltaSeconds: deltaSeconds,
                    preserveCurrentDiagnostics: preserveCurrentDiagnostics
                )
            }
        }

        let diagnostics = (diagnosticTransforms?.count == rawTransforms.count) ? diagnosticTransforms! : rawTransforms
        return rawTransforms.indices.map { index in
            let blended = weightedAverageTransform([
                (transform: forward[index], weight: 0.5),
                (transform: backward[index], weight: 0.5)
            ])
            let sourceLensReinforced = playbackTrajectorySourceLensReinforcedTransform(
                blended,
                rawTransform: diagnostics[index]
            )
            if preserveCurrentDiagnostics {
                return playbackTrajectoryTransformWithCurrentDiagnostics(
                    sourceLensReinforced,
                    rawTransform: diagnostics[index]
                )
            }
            return playbackTrajectoryTransformWithDiagnosticMetadata(
                sourceLensReinforced,
                rawTransform: diagnostics[index],
                sampleCount: 2,
                windowSeconds: renderFrameLocalSmoothingMinimumStepSeconds
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

    private static func playbackTrajectoryComposedPixelOffset(_ transform: StabilizerAutoTransform) -> vector_float2 {
        transform.macroPixelOffset
            + transform.microPixelOffset
            + transform.strideWobblePixelOffset
            + transform.trajectoryMicroJitterPixelOffset
            + transform.trajectoryContinuityPixelOffset
            + transform.lensShakePixelOffset
    }

    private static func playbackTrajectoryComposedNonLensPixelOffset(_ transform: StabilizerAutoTransform) -> vector_float2 {
        transform.macroPixelOffset
            + transform.microPixelOffset
            + transform.strideWobblePixelOffset
            + transform.trajectoryMicroJitterPixelOffset
            + transform.trajectoryContinuityPixelOffset
    }

    private static func playbackTrajectorySourceLensReinforcedTransform(
        _ limitedTransform: StabilizerAutoTransform,
        rawTransform: StabilizerAutoTransform
    ) -> StabilizerAutoTransform {
        var transform = limitedTransform
        let support = clamp(rawTransform.sourceLensShakeRidgeLineSupport, min: 0.0, max: 1.0)
        let residualY = rawTransform.sourceLensShakeRidgeLineResidual.y
        guard rawTransform.sourceLensShakeRidgeLineApplied > 0.5,
              support >= lensShakeMinimumSupport,
              residualY.isFinite
        else {
            return transform
        }

        let magnitude = abs(residualY)
        let sourceLensAuthority = confidenceRamp(
            support,
            start: 0.28,
            full: 0.72
        ) * confidenceRamp(
            magnitude,
            start: sourceLensRidgeLineGlobalEnvelopeStart,
            full: sourceLensRidgeLineGlobalEnvelopeFull
        ) * confidenceRamp(
            rawTransform.lensShakeRollingShutterCandidate,
            start: lensShakeGlobalUnsafeSupport,
            full: lensShakeRollingGlobalPixelUnsafeFull
        )
        guard sourceLensAuthority >= lensShakeMinimumSupport else {
            return transform
        }

        let targetY = clamp(
            -residualY * sourceLensRidgeLinePlaybackPixelScale,
            min: -sourceLensRidgeLinePlaybackMaximumCorrection,
            max: sourceLensRidgeLinePlaybackMaximumCorrection
        )
        let blend = clamp(
            sourceLensAuthority * sourceLensRidgeLinePlaybackMaximumBlend,
            min: 0.0,
            max: sourceLensRidgeLinePlaybackMaximumBlend
        )
        transform.lensShakePixelOffset.y += (targetY - transform.lensShakePixelOffset.y) * blend
        transform.sourceLensShakeRidgeLineOffset.y += (targetY - transform.sourceLensShakeRidgeLineOffset.y) * blend
        transform.pixelOffset = playbackTrajectoryComposedPixelOffset(transform)
        return transform
    }

    private static func preserveLensShakeDiagnostics(from source: StabilizerAutoTransform, into target: inout StabilizerAutoTransform) {
        target.lensShakeScore = source.lensShakeScore
        target.lensShakeSupport = source.lensShakeSupport
        target.lensShakeWindowFrames = source.lensShakeWindowFrames
        target.lensShakeWindowSeconds = source.lensShakeWindowSeconds
        target.lensShakeAxisMask = source.lensShakeAxisMask
        target.lensShakeReasonCode = source.lensShakeReasonCode
        target.lensShakeRollingShutterCandidate = source.lensShakeRollingShutterCandidate
        target.lensBandRawTopOffset = source.lensBandRawTopOffset
        target.lensBandRawRidgeOffset = source.lensBandRawRidgeOffset
        target.lensBandRawMidOffset = source.lensBandRawMidOffset
        target.lensBandPulseDeltaTopOffset = source.lensBandPulseDeltaTopOffset
        target.lensBandPulseDeltaRidgeOffset = source.lensBandPulseDeltaRidgeOffset
        target.lensBandPulseDeltaMidOffset = source.lensBandPulseDeltaMidOffset
        target.lensBandPulseWindowFrames = source.lensBandPulseWindowFrames
        target.lensBandWarpSupport = source.lensBandWarpSupport
        target.lensBandWarpApplied = source.lensBandWarpApplied
        target.lensBandRollingShutterScore = source.lensBandRollingShutterScore
        target.lensBandModelMask = source.lensBandModelMask
        target.lensFarFieldRigidShakeSupport = source.lensFarFieldRigidShakeSupport
        target.lensFarFieldRigidShakeApplied = source.lensFarFieldRigidShakeApplied
        target.lensFarFieldRigidShakeShapeConsistency = source.lensFarFieldRigidShakeShapeConsistency
        target.lensFarFieldRigidShakeForwardBackwardConsistency = source.lensFarFieldRigidShakeForwardBackwardConsistency
        target.lensFarFieldRigidShakeLocalWarpSuppressed = source.lensFarFieldRigidShakeLocalWarpSuppressed
        target.lensFarFieldRigidXQuiverScore = source.lensFarFieldRigidXQuiverScore
        target.lensFarFieldRigidXBeforeLimiter = source.lensFarFieldRigidXBeforeLimiter
        target.lensFarFieldRigidXAfterLimiter = source.lensFarFieldRigidXAfterLimiter
        target.lensFarFieldRigidRollResidual = source.lensFarFieldRigidRollResidual
        target.lensFarFieldRigidRollSupport = source.lensFarFieldRigidRollSupport
        target.lensFarFieldRigidGlobalYOffset = source.lensFarFieldRigidGlobalYOffset
        target.lensFarFieldRigidGlobalRollDegrees = source.lensFarFieldRigidGlobalRollDegrees
        target.lensFarFieldRigidRollApplied = source.lensFarFieldRigidRollApplied
        target.lensFarFieldMeshDominantWindowFrames = source.lensFarFieldMeshDominantWindowFrames
        target.lensFarFieldMeshDominantWindowSeconds = source.lensFarFieldMeshDominantWindowSeconds
        target.lensFarFieldMeshDominantSupport = source.lensFarFieldMeshDominantSupport
        target.lensFarFieldMeshDominantCell = source.lensFarFieldMeshDominantCell
        target.sourceLensShakeRidgeSupport = source.sourceLensShakeRidgeSupport
        target.sourceLensShakeRidgeApplied = source.sourceLensShakeRidgeApplied
        target.sourceLensShakeRidgeLineResidual = source.sourceLensShakeRidgeLineResidual
        target.sourceLensShakeRidgeLineSupport = source.sourceLensShakeRidgeLineSupport
        target.sourceLensShakeRidgeLineBandSupported = source.sourceLensShakeRidgeLineBandSupported
        target.sourceLensShakeRidgeLineApplied = source.sourceLensShakeRidgeLineApplied
    }

    private static func playbackTrajectoryLimitedTransform(
        _ current: StabilizerAutoTransform,
        previous: StabilizerAutoTransform,
        deltaSeconds: Double,
        preserveCurrentDiagnostics: Bool = true
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
        let microXAuthority = confidenceRamp(
            current.effectiveMicroJitterStrength.x,
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        let microYAuthority = confidenceRamp(
            current.effectiveMicroJitterStrength.y,
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        let microTranslationAuthority = max(microXAuthority, microYAuthority * 0.35)
        let microRotationAuthority = confidenceRamp(
            current.effectiveMicroJitterStrength.z,
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        let microPixelLimitScale = 0.55 + (playbackTrajectoryFootstepStepScale * microTranslationAuthority)
        let finalPixelLimitScale = 1.0 + (playbackTrajectoryFootstepStepScale * microTranslationAuthority)
        let microRotationLimitScale = 0.60 + (playbackTrajectoryFootstepStepScale * microRotationAuthority)
        let finalRotationLimitScale = 1.0 + (playbackTrajectoryFootstepStepScale * microRotationAuthority)
        var limited = current
        limited.trajectoryContinuityPixelOffset = vector_float2(0.0, 0.0)
        let lensPixelLimit = pixelLimit * 0.72
        let lensRotationLimit = rotationLimit * 0.72
        let lensLocalRollLimit = (lensRotationLimit * .pi) / 180.0

        let rigidYCorrectionMismatch = abs(
            current.lensShakePixelOffset.y - current.lensFarFieldRigidGlobalYOffset
        )
        let rigidYCorrectionMatch = 1.0 - confidenceRamp(
            rigidYCorrectionMismatch,
            start: playbackTrajectoryRigidYCorrectionMatchStartPixels,
            full: playbackTrajectoryRigidYCorrectionMatchFullPixels
        )
        let rigidYAuthority = current.lensFarFieldRigidShakeApplied > 0.5
            ? confidenceRamp(
                current.lensFarFieldRigidShakeSupport,
                start: playbackTrajectoryRigidYSupportStart,
                full: playbackTrajectoryRigidYSupportFull
            ) * confidenceRamp(
                current.lensFarFieldRigidShakeShapeConsistency,
                start: playbackTrajectoryRigidYShapeStart,
                full: playbackTrajectoryRigidYShapeFull
            ) * confidenceRamp(
                current.lensFarFieldRigidShakeForwardBackwardConsistency,
                start: playbackTrajectoryRigidYTwoWayStart,
                full: playbackTrajectoryRigidYTwoWayFull
            ) * rigidYCorrectionMatch
            : 0.0
        let rigidYTargetStep = abs(
            current.lensFarFieldRigidGlobalYOffset - previous.lensShakePixelOffset.y
        )
        let lensYLimit = max(lensPixelLimit, rigidYTargetStep * rigidYAuthority)

        limited.lensShakePixelOffset.y = playbackTrajectoryLimitedScalar(
            current.lensShakePixelOffset.y,
            previous: previous.lensShakePixelOffset.y,
            limit: lensYLimit
        )
        limited.lensShakeRotationDegrees = playbackTrajectoryLimitedScalar(
            current.lensShakeRotationDegrees,
            previous: previous.lensShakeRotationDegrees,
            limit: lensRotationLimit
        )
        limited.lensShakeYawPitch = playbackTrajectoryLimitedVector(
            current.lensShakeYawPitch,
            previous: previous.lensShakeYawPitch,
            limit: warpLimit
        )
        limited.lensShakeShear = playbackTrajectoryLimitedVector(
            current.lensShakeShear,
            previous: previous.lensShakeShear,
            limit: warpLimit
        )
        limited.lensShakePerspective = playbackTrajectoryLimitedVector(
            current.lensShakePerspective,
            previous: previous.lensShakePerspective,
            limit: warpLimit
        )
        limited.lensBandTopOffset = playbackTrajectoryLimitedVector(
            current.lensBandTopOffset,
            previous: previous.lensBandTopOffset,
            limit: lensPixelLimit
        )
        limited.lensBandRidgeOffset = playbackTrajectoryLimitedVector(
            current.lensBandRidgeOffset,
            previous: previous.lensBandRidgeOffset,
            limit: lensPixelLimit
        )
        limited.lensBandMidOffset = playbackTrajectoryLimitedVector(
            current.lensBandMidOffset,
            previous: previous.lensBandMidOffset,
            limit: lensPixelLimit
        )
        limited.lensBandTopColumnOffset = playbackTrajectoryLimitedVector(
            current.lensBandTopColumnOffset,
            previous: previous.lensBandTopColumnOffset,
            limit: lensPixelLimit
        )
        limited.lensBandRidgeColumnOffset = playbackTrajectoryLimitedVector(
            current.lensBandRidgeColumnOffset,
            previous: previous.lensBandRidgeColumnOffset,
            limit: lensPixelLimit
        )
        limited.lensBandMidColumnOffset = playbackTrajectoryLimitedVector(
            current.lensBandMidColumnOffset,
            previous: previous.lensBandMidColumnOffset,
            limit: lensPixelLimit
        )
        limited.lensBandTopRowPhaseOffset = playbackTrajectoryLimitedVector(
            current.lensBandTopRowPhaseOffset,
            previous: previous.lensBandTopRowPhaseOffset,
            limit: lensPixelLimit
        )
        limited.lensBandRidgeRowPhaseOffset = playbackTrajectoryLimitedVector(
            current.lensBandRidgeRowPhaseOffset,
            previous: previous.lensBandRidgeRowPhaseOffset,
            limit: lensPixelLimit
        )
        limited.lensBandMidRowPhaseOffset = playbackTrajectoryLimitedVector(
            current.lensBandMidRowPhaseOffset,
            previous: previous.lensBandMidRowPhaseOffset,
            limit: lensPixelLimit
        )
        limited.lensBandTopLocalRoll = playbackTrajectoryLimitedScalar(
            current.lensBandTopLocalRoll,
            previous: previous.lensBandTopLocalRoll,
            limit: lensLocalRollLimit
        )
        limited.lensBandRidgeLocalRoll = playbackTrajectoryLimitedScalar(
            current.lensBandRidgeLocalRoll,
            previous: previous.lensBandRidgeLocalRoll,
            limit: lensLocalRollLimit
        )
        limited.lensBandMidLocalRoll = playbackTrajectoryLimitedScalar(
            current.lensBandMidLocalRoll,
            previous: previous.lensBandMidLocalRoll,
            limit: lensLocalRollLimit
        )
        limited.sourceLensShakeRidgeOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeRidgeOffset,
            previous: previous.sourceLensShakeRidgeOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeRidgeLineOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeRidgeLineOffset,
            previous: previous.sourceLensShakeRidgeLineOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalTopLeftOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalTopLeftOffset,
            previous: previous.sourceLensShakeLocalTopLeftOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalTopCenterOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalTopCenterOffset,
            previous: previous.sourceLensShakeLocalTopCenterOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalTopRightOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalTopRightOffset,
            previous: previous.sourceLensShakeLocalTopRightOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalRidgeLeftOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalRidgeLeftOffset,
            previous: previous.sourceLensShakeLocalRidgeLeftOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalRidgeCenterOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalRidgeCenterOffset,
            previous: previous.sourceLensShakeLocalRidgeCenterOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalRidgeRightOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalRidgeRightOffset,
            previous: previous.sourceLensShakeLocalRidgeRightOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalMidLeftOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalMidLeftOffset,
            previous: previous.sourceLensShakeLocalMidLeftOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalMidCenterOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalMidCenterOffset,
            previous: previous.sourceLensShakeLocalMidCenterOffset,
            limit: lensPixelLimit
        )
        limited.sourceLensShakeLocalMidRightOffset = playbackTrajectoryLimitedVector(
            current.sourceLensShakeLocalMidRightOffset,
            previous: previous.sourceLensShakeLocalMidRightOffset,
            limit: lensPixelLimit
        )

        limited.macroPixelOffset = playbackTrajectoryLimitedVector(
            current.macroPixelOffset,
            previous: previous.macroPixelOffset,
            limit: pixelLimit * 0.85
        )
        limited.microPixelOffset = playbackTrajectoryLimitedVector(
            current.microPixelOffset,
            previous: previous.microPixelOffset,
            limit: pixelLimit * microPixelLimitScale
        )
        limited.strideWobblePixelOffset = playbackTrajectoryLimitedVector(
            current.strideWobblePixelOffset,
            previous: previous.strideWobblePixelOffset,
            limit: pixelLimit * 0.65
        )
        let componentPixelOffset = playbackTrajectoryComposedNonLensPixelOffset(limited)
        let previousNonLensPixelOffset = previous.pixelOffset - previous.lensShakePixelOffset
        let finalPixelOffset = playbackTrajectoryLimitedVector(
            componentPixelOffset,
            previous: previousNonLensPixelOffset,
            limit: pixelLimit * finalPixelLimitScale
        )
        limited.trajectoryContinuityPixelOffset = finalPixelOffset - componentPixelOffset
        limited.pixelOffset = playbackTrajectoryComposedPixelOffset(limited)

        limited.footstepJitterRotationDegrees = playbackTrajectoryLimitedScalar(
            current.footstepJitterRotationDegrees,
            previous: previous.footstepJitterRotationDegrees,
            limit: rotationLimit * microRotationLimitScale
        )
        limited.strideWobbleRotationDegrees = playbackTrajectoryLimitedScalar(
            current.strideWobbleRotationDegrees,
            previous: previous.strideWobbleRotationDegrees,
            limit: rotationLimit * 0.80
        )
        let componentRotation = limited.footstepJitterRotationDegrees
            + limited.strideWobbleRotationDegrees
        let previousNonLensRotation = previous.rotationDegrees - previous.lensShakeRotationDegrees
        let finalRotation = playbackTrajectoryLimitedScalar(
            componentRotation,
            previous: previousNonLensRotation,
            limit: rotationLimit * finalRotationLimitScale
        )
        limited.strideWobbleRotationDegrees += finalRotation - componentRotation
        limited.rotationDegrees = finalRotation + limited.lensShakeRotationDegrees

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
        if preserveCurrentDiagnostics {
            return playbackTrajectoryTransformWithCurrentDiagnostics(limited, rawTransform: current)
        }
        return playbackTrajectoryTransformWithDiagnosticMetadata(
            limited,
            rawTransform: current,
            sampleCount: 2,
            windowSeconds: renderFrameLocalSmoothingMinimumStepSeconds
        )
    }

    private static func playbackTrajectoryTransformWithCurrentDiagnostics(
        _ limitedTransform: StabilizerAutoTransform,
        rawTransform: StabilizerAutoTransform
    ) -> StabilizerAutoTransform {
        var transform = limitedTransform
        let preserveMicroX = playbackTrajectoryFootstepPreservationBlend(
            magnitude: rawTransform.microPixelOffset.x,
            confidence: rawTransform.effectiveMicroJitterStrength.x,
            start: playbackTrajectoryFootstepPreservationStartPixels,
            full: playbackTrajectoryFootstepPreservationFullPixels
        ) * playbackTrajectoryTurnOwnedXPreservationScale(rawTransform)
        let preserveMicroY = playbackTrajectoryFootstepPreservationBlend(
            magnitude: rawTransform.microPixelOffset.y,
            confidence: rawTransform.effectiveMicroJitterStrength.y,
            start: playbackTrajectoryFootstepPreservationStartPixels,
            full: playbackTrajectoryFootstepPreservationFullPixels
        )
        let preserveRotation = playbackTrajectoryFootstepPreservationBlend(
            magnitude: rawTransform.footstepJitterRotationDegrees,
            confidence: rawTransform.effectiveMicroJitterStrength.z,
            start: playbackTrajectoryFootstepRotationPreservationStartDegrees,
            full: playbackTrajectoryFootstepRotationPreservationFullDegrees
        )
        transform.microPixelOffset.x += (rawTransform.microPixelOffset.x - transform.microPixelOffset.x) * preserveMicroX
        transform.microPixelOffset.y += (rawTransform.microPixelOffset.y - transform.microPixelOffset.y) * preserveMicroY
        transform.footstepJitterRotationDegrees += (rawTransform.footstepJitterRotationDegrees - transform.footstepJitterRotationDegrees) * preserveRotation
        transform.pixelOffset = transform.macroPixelOffset
            + transform.microPixelOffset
            + transform.strideWobblePixelOffset
            + transform.trajectoryMicroJitterPixelOffset
            + transform.trajectoryContinuityPixelOffset
            + transform.lensShakePixelOffset
        transform.rotationDegrees = transform.footstepJitterRotationDegrees
            + transform.strideWobbleRotationDegrees
            + transform.lensShakeRotationDegrees
        return playbackTrajectoryTransformWithDiagnosticMetadata(
            transform,
            rawTransform: rawTransform,
            sampleCount: 2,
            windowSeconds: renderFrameLocalSmoothingMinimumStepSeconds
        )
    }

    private static func playbackTrajectoryTransformWithDiagnosticMetadata(
        _ limitedTransform: StabilizerAutoTransform,
        rawTransform: StabilizerAutoTransform,
        sampleCount: Int32,
        windowSeconds: Double
    ) -> StabilizerAutoTransform {
        var transform = limitedTransform
        transform.turnDetectedPixelOffset = rawTransform.turnDetectedPixelOffset
        transform.rawPixelOffset = rawTransform.pixelOffset
        transform.rawRotationDegrees = rawTransform.rotationDegrees
        transform.temporalSmoothingPixelDelta = transform.pixelOffset - rawTransform.pixelOffset
        transform.temporalSmoothingRotationDelta = transform.rotationDegrees - rawTransform.rotationDegrees
        transform.temporalSmoothingSampleCount = sampleCount
        transform.temporalSmoothingWindowSeconds = Float(windowSeconds)
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

    private static func playbackTrajectoryFootstepPreservationBlend(
        magnitude: Float,
        confidence: Float,
        start: Float,
        full: Float
    ) -> Float {
        guard magnitude.isFinite,
              confidence.isFinite
        else {
            return 0.0
        }
        let magnitudeSupport = confidenceRamp(
            abs(magnitude),
            start: start,
            full: full
        )
        let confidenceSupport = confidenceRamp(
            confidence,
            start: playbackTrajectoryFootstepAuthorityGateStart,
            full: playbackTrajectoryFootstepAuthorityGateFull
        )
        return clamp(
            playbackTrajectoryFootstepPreservationMaxBlend * magnitudeSupport * confidenceSupport,
            min: 0.0,
            max: playbackTrajectoryFootstepPreservationMaxBlend
        )
    }

    private static func playbackTrajectoryTurnOwnedXPreservationScale(
        _ rawTransform: StabilizerAutoTransform
    ) -> Float {
        let turnOwnershipX = confidenceRamp(
            abs(rawTransform.turnDetectedPixelOffset.x),
            start: turnMacroOwnershipBandStartPixels,
            full: turnMacroOwnershipBandFullPixels
        ) * clamp(rawTransform.turnConfidence, min: 0.0, max: 1.0)
        let fineBandGate = turnOwnedFootstepXFineBandGate(
            bandPixels: rawTransform.microPixelOffset.x,
            turnOwnership: turnOwnershipX
        )
        let edgeQuality = searchRadiusEdgeQuality(
            hitCount: rawTransform.searchRadiusHitCount,
            totalCount: rawTransform.searchRadiusTotalCount
        )
        let farFieldSupport = farFieldTurnOwnedWalkingXSupport(
            warpConfidence: rawTransform.warpConfidence,
            trackingConfidence: max(rawTransform.walkingTrackingConfidence, rawTransform.trackingConfidence),
            edgeQuality: edgeQuality
        )
        let farFieldFloor = playbackTrajectoryTurnOwnedXPreservationFarFieldFloorMax
            * confidenceRamp(
                farFieldSupport,
                start: playbackTrajectoryTurnOwnedXPreservationFarFieldStart,
                full: playbackTrajectoryTurnOwnedXPreservationFarFieldFull
            )
            * confidenceRamp(
                abs(rawTransform.microPixelOffset.x),
                start: playbackTrajectoryFootstepPreservationStartPixels,
                full: playbackTrajectoryFootstepPreservationFullPixels
            )
        return clamp(max(fineBandGate, farFieldFloor), min: 0.0, max: 1.0)
    }


    private static func playbackTrajectorySmoothedTransform(
        index: Int,
        frames: [StabilizerAnalysisFrame],
        rawTransforms: [StabilizerAutoTransform],
        panSmoothSeconds: Double,
        strengths: StabilizerCorrectionStrengths
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
        preserveLensShakeDiagnostics(from: centerTransform, into: &smoothedTransform)

        let turnSamples = playbackTrajectoryTurnTransitionSamples(
            centerTransform: centerTransform,
            centerTime: centerTime,
            frames: frames,
            transforms: rawTransforms,
            panSmoothSeconds: panSmoothSeconds,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        if !turnSamples.isEmpty {
            let smoothedTurnTransform = weightedAverageTransform(turnSamples)
            var bridgedMacroOffset = smoothedTurnTransform.macroPixelOffset
            let centerMacroX = centerTransform.macroPixelOffset.x
            let bridgedMacroX = bridgedMacroOffset.x
            let zoomBridgeAuthority = turnSmoothingZoomBridgeAuthority(
                turnSmoothingZoom: strengths.turnSmoothingZoom,
                turnConfidence: centerTransform.turnConfidence,
                turnTravelPixels: abs(centerTransform.turnDetectedPixelOffset.x)
            )
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(centerTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70)
                    * 0.85
                    * (1.0 - (zoomBridgeAuthority * renderTurnTransitionZoomCenterPreservationFade))
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: centerTransform,
                bridgeMacroX: bridgedMacroOffset.x,
                zoomBridgeAuthority: zoomBridgeAuthority
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: centerTransform,
                bridgeTransform: smoothedTurnTransform
            ) * turnSmoothingBridgeBlend(strengths.turnSmoothingZoom)
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
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
            + smoothedTransform.trajectoryMicroJitterPixelOffset
            + smoothedTransform.trajectoryContinuityPixelOffset
            + smoothedTransform.lensShakePixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
            + smoothedTransform.lensShakeRotationDegrees
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
        transforms: [StabilizerAutoTransform],
        panSmoothSeconds: Double,
        turnSmoothingZoom: Double
    ) -> [(transform: StabilizerAutoTransform, weight: Float)] {
        guard let firstTime = frames.first?.time,
              let lastTime = frames.last?.time
        else {
            return [(centerTransform, 1.0)]
        }
        let timing = adaptiveXTurnTiming(
            travelPixels: abs(centerTransform.turnDetectedPixelOffset.x),
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            turnSmoothingZoom: turnSmoothingZoom
        )
        let transitionWindowSeconds = timing.windowSeconds
        let sampleCount = adaptiveXTurnTransitionSampleCount(windowSeconds: transitionWindowSeconds)
        let centerSample = sampleCount / 2
        let halfWindow = transitionWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = transitionWindowSeconds / denominator
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
                    centerFarFieldSupport: centerTransform.warpConfidence,
                    samples: xSamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                ),
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.y,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                    centerFarFieldSupport: centerTransform.warpConfidence,
                    samples: ySamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                )
            ),
            rotationDegrees: smoothedFootstepScalar(
                centerValue: centerTransform.footstepJitterRotationDegrees,
                centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                centerFarFieldSupport: centerTransform.warpConfidence,
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
        let farFieldTurnOwnedXSupport = farFieldTurnOwnedWalkingXSupport(
            warpConfidence: warpConfidence,
            trackingConfidence: walkingTrackingConfidence,
            edgeQuality: searchRadiusEdgeQuality(
                hitCount: searchRadiusHitCount,
                totalCount: searchRadiusTotalCount
            )
        )
        let pathX = EstimatedPath(values: analysis.pathX)
        let pathY = EstimatedPath(values: analysis.pathY)
        let pathRoll = EstimatedPath(values: analysis.pathRoll)
        let farFieldPathX = EstimatedPath(values: analysis.farFieldPathX)
        let farFieldPathY = EstimatedPath(values: analysis.farFieldPathY)
        let farFieldPathRoll = EstimatedPath(values: analysis.farFieldPathRoll)
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
        let turnSmoothX = adaptiveXTurnSmoothValue(
            pathX,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: smoothWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
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
        let farFieldTurnSmoothX = adaptiveXTurnSmoothValue(
            farFieldPathX,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: smoothWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let farFieldTurnSmoothY = timeWeightedLinearPrediction(
            farFieldPathY,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                farFieldPathY,
                frames: frames,
                indices: turnActiveIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let farFieldTurnSmoothRoll = timeWeightedLinearPrediction(
            farFieldPathRoll,
            frames: frames,
            indices: turnActiveIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                farFieldPathRoll,
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
        let farFieldXAtRender = interpolatedValue(analysis.farFieldPathX, using: frameInterpolation)
        let farFieldYAtRender = interpolatedValue(analysis.farFieldPathY, using: frameInterpolation)
        let farFieldRollAtRender = interpolatedValue(analysis.farFieldPathRoll, using: frameInterpolation)
        let farFieldMacroConfidence = clamp(
            interpolatedValue(analysis.farFieldConfidence, using: frameInterpolation),
            min: 0.0,
            max: 1.0
        )
        let farFieldMacroBlend = confidenceRamp(
            farFieldMacroConfidence,
            start: farFieldMacroBlendConfidenceStart,
            full: farFieldMacroBlendConfidenceFull
        )
        let strideBandX = cleanedFootstepXAtRender - strideSmoothX
        let strideBandY = cleanedFootstepYAtRender - strideSmoothY
        let strideBandRoll = cleanedFootstepRollAtRender - strideSmoothRoll
        let globalPanBandX = pathXAtRender - turnSmoothX
        let globalPanBandY = pathYAtRender - turnSmoothY
        let globalPanBandRoll = pathRollAtRender - turnSmoothRoll
        let farFieldPanBandX = farFieldXAtRender - farFieldTurnSmoothX
        let farFieldPanBandY = farFieldYAtRender - farFieldTurnSmoothY
        let farFieldPanBandRoll = farFieldRollAtRender - farFieldTurnSmoothRoll
        let panBandX = globalPanBandX + ((farFieldPanBandX - globalPanBandX) * farFieldMacroBlend)
        let panBandY = globalPanBandY + ((farFieldPanBandY - globalPanBandY) * farFieldMacroBlend)
        let panBandRoll = globalPanBandRoll + ((farFieldPanBandRoll - globalPanBandRoll) * farFieldMacroBlend)
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
        let turnOwnership = turnOwnershipX
        let confidenceX = turnBandConfidenceX * turnOwnershipX
        let confidence = confidenceX
        let combinedTurnCorrectionConfidence = turnCorrectionConfidence(
            confidence: confidence,
            turnOwnership: turnOwnership
        )
        let turnCorrectionConfidenceX = turnCorrectionConfidence(
            confidence: confidenceX,
            turnOwnership: turnOwnershipX
        )
        let turnShakeSuppression = turnStabilizerShakeSuppression(
            turnOwnership: turnOwnership,
            turnConfidence: confidence
        )
        let turnXMacroPixels = abs(panBandX * xScale)
        let turnYMacroPixels = abs(panBandY * yScale)
        let footstepXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        let footstepYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepYSuppression), min: 0.0, max: 1.0)
        let footstepRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepRollSuppression), min: 0.0, max: 1.0)
        let strideXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
        let strideYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideYSuppression), min: 0.0, max: 1.0)
        let strideRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideRollSuppression), min: 0.0, max: 1.0)
        let turnOwnedFootstepXFineGate = turnOwnedFootstepXFineBandGate(
            bandPixels: footstepImpulseX * xScale,
            turnOwnership: turnOwnershipX
        )
        let footstepXWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: footstepImpulseX * xScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        ) * turnOwnedFootstepXFineGate
        let footstepYWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: footstepImpulseY * yScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let footstepXFarFieldConfidenceFloor = max(
            turnOwnedFarFieldWalkingXConfidenceFloor(
                bandMagnitude: abs(footstepImpulseX * xScale),
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: turnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldTurnOwnedXSupport
            ),
            max(
                turnOwnedFootstepXRescueConfidenceFloor(
                    bandPixels: footstepImpulseX * xScale,
                    turnShakeSuppression: turnShakeSuppression,
                    turnOwnership: turnOwnershipX,
                    farFieldSupport: farFieldTurnOwnedXSupport,
                    fineGate: turnOwnedFootstepXFineGate
                ),
                footstepXWalkingRescueConfidenceFloor
            )
        )
        let footstepRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: footstepPathRollAtRender - microImpulseBaselineRoll,
            farFieldSupport: farFieldTurnOwnedXSupport
        )
        let footstepYFarFieldConfidenceFloor = max(
            farFieldFootstepVerticalConfidenceFloor(
                bandPixels: footstepImpulseY * yScale,
                farFieldSupport: farFieldTurnOwnedXSupport
            ),
            footstepYWalkingRescueConfidenceFloor
        )
        let strideXBaseFarFieldConfidenceFloor = turnOwnedFarFieldWalkingXConfidenceFloor(
            bandMagnitude: abs(strideBandX * xScale),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * turnOwnedStrideXGateFloorScale
        let strideXRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandX * xScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideYBaseFarFieldConfidenceFloor = farFieldFootstepVerticalConfidenceFloor(
            bandPixels: strideBandY * yScale,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * farFieldStrideVerticalConfidenceFloorScale
        let strideYRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandY * yScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideXFarFieldConfidenceFloor = max(strideXBaseFarFieldConfidenceFloor, strideXRescueConfidenceFloor)
        let strideYFarFieldConfidenceFloor = max(strideYBaseFarFieldConfidenceFloor, strideYRescueConfidenceFloor)
        let strideRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: strideBandRoll,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * farFieldStrideRollConfidenceFloorScale
        let footstepXConfidence = max(rawFootstepXConfidence * footstepXTurnGate, footstepXFarFieldConfidenceFloor)
        let footstepYConfidence = max(rawFootstepYConfidence * footstepYTurnGate, footstepYFarFieldConfidenceFloor)
        let footstepRollConfidence = max(rawFootstepRollConfidence * footstepRollTurnGate, footstepRollFarFieldConfidenceFloor)
        let strideXConfidence = max(rawStrideXConfidence * strideXTurnGate, strideXFarFieldConfidenceFloor)
        let strideYConfidence = max(rawStrideYConfidence * strideYTurnGate, strideYFarFieldConfidenceFloor)
        let strideRollConfidence = max(rawStrideRollConfidence * strideRollTurnGate, strideRollFarFieldConfidenceFloor)
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.turnSmoothingZoom, confidence: turnCorrectionConfidenceX)
        let cameraJitterMacroYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterY,
            confidence: turnBandConfidenceY,
            maxStrength: 10.0
        )
        let cameraJitterMacroRollCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterRotation,
            confidence: turnBandConfidenceRoll
        )
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
        let rawMacroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrengthX
        let cameraJitterMacroCompensationY = -panBandY * yScale * positionGain * cameraJitterMacroYCorrectionStrength
        let cameraJitterMacroCompensationRotation = -panBandRoll * rotationGain * cameraJitterMacroRollCorrectionStrength
        let macroCompensationX = softLimit(
            rawMacroCompensationX,
            limit: turnSmoothingXOffsetLimit(
                outputPixels: outputSize.x,
                turnSmoothingStrength: strengths.turnSmoothingZoom
            )
        )
        let unscaledRawMicroCompensationX = -footstepImpulseX * xScale * microXCorrectionStrength
        let lowEvidenceMicroXScale = lowEvidenceLargeFootstepXScale(
            rawConfidence: max(rawFootstepXConfidence, footstepXFarFieldConfidenceFloor),
            correctionPixels: unscaledRawMicroCompensationX,
            farFieldSupport: farFieldTurnOwnedXSupport
        )
        let effectiveMicroXCorrectionStrength = microXCorrectionStrength * lowEvidenceMicroXScale
        let rawMicroCompensationX = unscaledRawMicroCompensationX * lowEvidenceMicroXScale
        let rawMicroCompensationY = -footstepImpulseY * yScale * microYCorrectionStrength
        let footstepXContinuityConfidenceScale = max(footstepXTurnGate, farFieldTurnOwnedXSupport)
        let footstepYContinuityConfidenceScale = max(footstepYTurnGate, farFieldTurnOwnedXSupport)
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
                confidenceScale: footstepXContinuityConfidenceScale,
                confidenceFloor: footstepXFarFieldConfidenceFloor,
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
                confidenceScale: footstepYContinuityConfidenceScale,
                cache: cache
            )
            : FootstepContinuityLimitResult(limitedCorrection: rawMicroCompensationY, limitedAmount: 0.0)
        let microCompensationX = limitedMicroCompensationX.limitedCorrection
        let microCompensationY = limitedMicroCompensationY.limitedCorrection
        let microCompensationRotation = -footstepImpulseRoll * microRotationCorrectionStrength
        let strideCompensationX = -strideBandX * xScale * strideXCorrectionStrength
        let strideCompensationY = -strideBandY * yScale * strideYCorrectionStrength
        let strideCompensationRotation = -strideBandRoll * strideRotationCorrectionStrength
        let macroPixelOffset = vector_float2(macroCompensationX, 0.0)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let strideWobblePixelOffset = vector_float2(strideCompensationX, strideCompensationY)
        let trajectoryMicroJitterPixelOffset = farFieldWalkingResidualContinuityOffset(
            footstepBandPixels: vector_float2(footstepImpulseX * xScale, footstepImpulseY * yScale),
            footstepCorrectionPixels: microPixelOffset,
            strideBandPixels: vector_float2(strideBandX * xScale, strideBandY * yScale),
            strideCorrectionPixels: strideWobblePixelOffset,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: vector_float2(turnOwnershipX, turnOwnershipY),
            turnMacroMagnitude: vector_float2(turnXMacroPixels, turnYMacroPixels),
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let trajectoryContinuityPixelOffset = vector_float2(0.0, cameraJitterMacroCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x + strideWobblePixelOffset.x + trajectoryMicroJitterPixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + strideWobblePixelOffset.y + trajectoryMicroJitterPixelOffset.y + trajectoryContinuityPixelOffset.y
        let compensationRotation = cameraJitterMacroCompensationRotation + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrengths = effectiveFarFieldWarpComponentStrengths(Float(strengths.farFieldWarp))
        let shouldEstimateFarFieldWarp = farFieldWarpStrengths.isActive
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
            let farFieldWarpTurnGate: Float = 1.0
            appliedWarpConfidence = farFieldWarpAppliedConfidence(
                stableWarpConfidence: stableWarpConfidence,
                warpGate: farFieldWarpGate,
                turnGate: farFieldWarpTurnGate,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )

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

            func farFieldBand(_ values: [Float], deadband: Float, strength: Float, limit: Float) -> Float {
                let current = interpolatedValue(values, using: frameInterpolation)
                let lowerBaseline = farFieldBaseline(values, index: frameInterpolation.lowerIndex)
                let upperBaseline = frameInterpolation.upperIndex == frameInterpolation.lowerIndex
                    ? lowerBaseline
                    : farFieldBaseline(values, index: frameInterpolation.upperIndex)
                let baseline = lowerBaseline + ((upperBaseline - lowerBaseline) * frameInterpolation.fraction)
                let scaled = softDeadband(current - baseline, threshold: deadband)
                    * appliedWarpConfidence
                    * strength
                return clamp(scaled, min: -limit * strength, max: limit * strength)
            }

            yawPitchProxy = vector_float2(
                farFieldBand(
                    analysis.pathYaw,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                ),
                farFieldBand(
                    analysis.pathPitch,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                )
            )
            shear = vector_float2(
                farFieldBand(
                    analysis.pathShearX,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                ),
                farFieldBand(
                    analysis.pathShearY,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                )
            )
            perspective = vector_float2(
                farFieldBand(
                    analysis.pathPerspectiveX,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                ),
                farFieldBand(
                    analysis.pathPerspectiveY,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                )
            )
        } else {
            appliedWarpConfidence = 0.0
            yawPitchProxy = vector_float2(0.0, 0.0)
            shear = vector_float2(0.0, 0.0)
            perspective = vector_float2(0.0, 0.0)
        }
        let lensShake = shouldEstimateFarFieldWarp
            ? sourceSpaceLensShakeCorrection(
                analysis: analysis,
                frames: frames,
                interpolation: frameInterpolation,
                outputScale: vector_float2(xScale, yScale),
                warpConfidence: appliedWarpConfidence,
                farFieldConfidence: farFieldMacroConfidence,
                trackingConfidence: trackingConfidence,
                edgeQuality: searchRadiusEdgeQuality(
                    hitCount: searchRadiusHitCount,
                    totalCount: searchRadiusTotalCount
                ),
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: vector_float2(turnOwnershipX, turnOwnershipY),
                cache: cache
            )
            : SourceSpaceLensShakeCorrection(reasonCode: 0)

        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY) + lensShake.pixelOffset,
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: strideWobblePixelOffset,
            trajectoryMicroJitterPixelOffset: trajectoryMicroJitterPixelOffset,
            trajectoryContinuityPixelOffset: trajectoryContinuityPixelOffset,
            lensShakePixelOffset: lensShake.pixelOffset,
            lensShakeRotationDegrees: lensShake.rotationDegrees,
            lensShakeYawPitch: lensShake.yawPitch,
            lensShakeShear: lensShake.shear,
            lensShakePerspective: lensShake.perspective,
            lensShakeScore: lensShake.score,
            lensShakeSupport: lensShake.support,
            lensShakeWindowFrames: lensShake.windowFrames,
            lensShakeWindowSeconds: lensShake.windowSeconds,
            lensShakeAxisMask: lensShake.axisMask,
            lensShakeReasonCode: lensShake.reasonCode,
            lensShakeRollingShutterCandidate: lensShake.rollingShutterCandidate,
            lensBandTopOffset: lensShake.bandTopOffset,
            lensBandRidgeOffset: lensShake.bandRidgeOffset,
            lensBandMidOffset: lensShake.bandMidOffset,
            lensBandRawTopOffset: lensShake.bandRawTopOffset,
            lensBandRawRidgeOffset: lensShake.bandRawRidgeOffset,
            lensBandRawMidOffset: lensShake.bandRawMidOffset,
            lensBandPulseDeltaTopOffset: lensShake.bandPulseDeltaTopOffset,
            lensBandPulseDeltaRidgeOffset: lensShake.bandPulseDeltaRidgeOffset,
            lensBandPulseDeltaMidOffset: lensShake.bandPulseDeltaMidOffset,
            lensBandPulseWindowFrames: lensShake.bandPulseWindowFrames,
            lensBandTopColumnOffset: lensShake.bandTopColumnOffset,
            lensBandRidgeColumnOffset: lensShake.bandRidgeColumnOffset,
            lensBandMidColumnOffset: lensShake.bandMidColumnOffset,
            lensBandTopRowPhaseOffset: lensShake.bandTopRowPhaseOffset,
            lensBandRidgeRowPhaseOffset: lensShake.bandRidgeRowPhaseOffset,
            lensBandMidRowPhaseOffset: lensShake.bandMidRowPhaseOffset,
            lensBandTopLocalRoll: lensShake.bandTopLocalRoll,
            lensBandRidgeLocalRoll: lensShake.bandRidgeLocalRoll,
            lensBandMidLocalRoll: lensShake.bandMidLocalRoll,
            lensBandWarpSupport: lensShake.bandWarpSupport,
            lensBandWarpApplied: lensShake.bandWarpApplied,
            lensBandRollingShutterScore: lensShake.bandRollingShutterScore,
            lensBandModelMask: lensShake.bandModelMask,
            lensFarFieldRigidShakeOffset: lensShake.farFieldRigidOffset,
            lensFarFieldRigidShakeSupport: lensShake.farFieldRigidSupport,
            lensFarFieldRigidShakeApplied: lensShake.farFieldRigidApplied,
            lensFarFieldRigidShakeShapeConsistency: lensShake.farFieldRigidShapeConsistency,
            lensFarFieldRigidShakeForwardBackwardConsistency: lensShake.farFieldRigidForwardBackwardConsistency,
            lensFarFieldRigidShakeLocalWarpSuppressed: lensShake.farFieldRigidLocalWarpSuppressed,
            lensFarFieldRigidXQuiverScore: lensShake.farFieldRigidXQuiverScore,
            lensFarFieldRigidXBeforeLimiter: lensShake.farFieldRigidXBeforeLimiter,
            lensFarFieldRigidXAfterLimiter: lensShake.farFieldRigidXAfterLimiter,
            lensFarFieldRigidRollResidual: lensShake.farFieldRigidRollResidual,
            lensFarFieldRigidRollSupport: lensShake.farFieldRigidRollSupport,
            lensFarFieldRigidGlobalYOffset: lensShake.farFieldRigidGlobalYOffset,
            lensFarFieldRigidGlobalRollDegrees: lensShake.farFieldRigidGlobalRollDegrees,
            lensFarFieldRigidRollApplied: lensShake.farFieldRigidRollApplied,
            lensFarFieldMeshOffset: lensShake.farFieldMeshOffset,
            lensFarFieldMeshSupport: lensShake.farFieldMeshSupport,
            lensFarFieldMeshBlend: lensShake.farFieldMeshBlend,
            lensFarFieldMeshAvailable: lensShake.farFieldMeshAvailable,
            lensFarFieldMeshSupportedBins: lensShake.farFieldMeshSupportedBins,
            lensFarFieldMeshMaxBinDelta: lensShake.farFieldMeshMaxBinDelta,
            lensFarFieldMeshOpposingBins: lensShake.farFieldMeshOpposingBins,
            lensFarFieldMeshDominantWindowFrames: lensShake.farFieldMeshDominantWindowFrames,
            lensFarFieldMeshDominantWindowSeconds: lensShake.farFieldMeshDominantWindowSeconds,
            lensFarFieldMeshDominantSupport: lensShake.farFieldMeshDominantSupport,
            lensFarFieldMeshDominantCell: lensShake.farFieldMeshDominantCell,
            sourceLensShakeRidgeOffset: lensShake.sourceRidgeOffset,
            sourceLensShakeRidgeSupport: lensShake.sourceRidgeSupport,
            sourceLensShakeRidgeApplied: lensShake.sourceRidgeApplied,
            sourceLensShakeRidgeLineResidual: lensShake.sourceRidgeLineResidual,
            sourceLensShakeRidgeLineOffset: lensShake.sourceRidgeLineOffset,
            sourceLensShakeRidgeLineSupport: lensShake.sourceRidgeLineSupport,
            sourceLensShakeRidgeLineBandSupported: lensShake.sourceRidgeLineBandSupported,
            sourceLensShakeRidgeLineApplied: lensShake.sourceRidgeLineApplied,
            sourceLensShakeLocalTopLeftOffset: lensShake.localTopLeftOffset,
            sourceLensShakeLocalTopCenterOffset: lensShake.localTopCenterOffset,
            sourceLensShakeLocalTopRightOffset: lensShake.localTopRightOffset,
            sourceLensShakeLocalRidgeLeftOffset: lensShake.localRidgeLeftOffset,
            sourceLensShakeLocalRidgeCenterOffset: lensShake.localRidgeCenterOffset,
            sourceLensShakeLocalRidgeRightOffset: lensShake.localRidgeRightOffset,
            sourceLensShakeLocalMidLeftOffset: lensShake.localMidLeftOffset,
            sourceLensShakeLocalMidCenterOffset: lensShake.localMidCenterOffset,
            sourceLensShakeLocalMidRightOffset: lensShake.localMidRightOffset,
            sourceLensShakeLocalSupport: lensShake.localSupport,
            sourceLensShakeLocalApplied: lensShake.localApplied,
            footstepJitterRotationDegrees: cameraJitterMacroCompensationRotation + microCompensationRotation,
            strideWobbleRotationDegrees: strideCompensationRotation,
            rotationDegrees: compensationRotation + lensShake.rotationDegrees,
            turnDetectedPixelOffset: vector_float2(-panBandX * xScale, 0.0),
            rawPixelOffset: vector_float2(compensationX, compensationY) + lensShake.pixelOffset,
            rawRotationDegrees: compensationRotation + lensShake.rotationDegrees,
            temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
            temporalSmoothingRotationDelta: 0.0,
            temporalSmoothingSampleCount: 1,
            temporalSmoothingWindowSeconds: 0.0,
            effectiveMicroJitterStrength: vector_float3(
                effectiveMicroXCorrectionStrength,
                max(microYCorrectionStrength, cameraJitterMacroYCorrectionStrength),
                max(microRotationCorrectionStrength, cameraJitterMacroRollCorrectionStrength)
            ),
            effectiveStrideWobbleStrength: vector_float3(
                strideXCorrectionStrength,
                strideYCorrectionStrength,
                strideRotationCorrectionStrength
            ),
            warpConfidence: appliedWarpConfidence,
            microConfidence: max(jitterConfidence, max(turnBandConfidenceY, turnBandConfidenceRoll)),
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
        let farFieldTurnOwnedXSupport = farFieldTurnOwnedWalkingXSupport(
            warpConfidence: warpConfidence,
            trackingConfidence: walkingTrackingConfidence,
            edgeQuality: searchRadiusEdgeQuality(
                hitCount: searchRadiusHitCount,
                totalCount: searchRadiusTotalCount
            )
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
        let farFieldBaselineXPath = cachedOuterLinearPredictionPath(
            .farFieldX,
            analysis: analysis,
            indices: strideSupportIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineYPath = cachedOuterLinearPredictionPath(
            .farFieldY,
            analysis: analysis,
            indices: strideSupportIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldBaselineRollPath = cachedOuterLinearPredictionPath(
            .farFieldRoll,
            analysis: analysis,
            indices: strideSupportIndices,
            innerWindowSeconds: footstepImpulseInnerWindowSeconds,
            outerWindowSeconds: footstepImpulseOuterWindowSeconds,
            cache: cache
        )
        let farFieldCleanXPath = confidenceCleanedFootstepPath(
            .farFieldX,
            values: analysis.farFieldPathX,
            baselineValues: farFieldBaselineXPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            confidenceScales: footstepXTurnGateScales,
            cache: cache
        )
        let farFieldCleanYPath = confidenceCleanedFootstepPath(
            .farFieldY,
            values: analysis.farFieldPathY,
            baselineValues: farFieldBaselineYPath,
            analysis: analysis,
            indices: strideSupportIndices,
            fullImpulseScale: footstepImpulseFullScalePixels,
            cache: cache
        )
        let farFieldCleanRollPath = confidenceCleanedFootstepPath(
            .farFieldRoll,
            values: analysis.farFieldPathRoll,
            baselineValues: farFieldBaselineRollPath,
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
        let farFieldStrideSmoothedXPath = cache.locallyTimeWeightedAveragePath(
            .farFieldX,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: smoothWindowSeconds.bitPattern,
            source: farFieldCleanXPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedYPath = cache.locallyTimeWeightedAveragePath(
            .farFieldY,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: smoothWindowSeconds.bitPattern,
            source: farFieldCleanYPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let farFieldStrideSmoothedRollPath = cache.locallyTimeWeightedAveragePath(
            .farFieldRoll,
            sourceRole: .footstepStrideCleaned,
            sourceVariant: smoothWindowSeconds.bitPattern,
            source: farFieldCleanRollPath,
            analysis: analysis,
            targetIndices: strideSampledIndices,
            windowSeconds: effectiveStrideWobbleWindowSeconds
        )
        let turnSmoothX = adaptiveXTurnSmoothValue(
            turnStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: smoothWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
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
        let broadFarFieldX = adaptiveXTurnSmoothValue(
            farFieldStrideSmoothedXPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            fallbackWindowSeconds: smoothWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: xScale,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let broadFarFieldY = timeWeightedLinearPrediction(
            farFieldStrideSmoothedYPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                farFieldStrideSmoothedYPath,
                frames: frames,
                indices: activeIndices,
                centerTime: renderSeconds,
                windowSeconds: smoothWindowSeconds
            )
        let broadFarFieldRoll = timeWeightedLinearPrediction(
            farFieldStrideSmoothedRollPath,
            frames: frames,
            indices: activeIndices,
            centerTime: renderSeconds,
            windowSeconds: smoothWindowSeconds
        ) ??
            timeWeightedAverage(
                farFieldStrideSmoothedRollPath,
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
        let farFieldPathXAtRender = interpolatedValue(analysis.farFieldPathX, using: frameInterpolation)
        let farFieldPathYAtRender = interpolatedValue(analysis.farFieldPathY, using: frameInterpolation)
        let farFieldPathRollAtRender = interpolatedValue(analysis.farFieldPathRoll, using: frameInterpolation)
        let farFieldMacroConfidence = clamp(
            interpolatedValue(analysis.farFieldConfidence, using: frameInterpolation),
            min: 0.0,
            max: 1.0
        )
        let farFieldMacroBlend = confidenceRamp(
            farFieldMacroConfidence,
            start: farFieldMacroBlendConfidenceStart,
            full: farFieldMacroBlendConfidenceFull
        )
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
        let globalPanBandX = turnStrideSmoothX - turnSmoothX
        let globalPanBandY = turnStrideSmoothY - turnSmoothY
        let globalPanBandRoll = turnStrideSmoothRoll - turnSmoothRoll
        let farFieldPanBandX = farFieldPathXAtRender - broadFarFieldX
        let farFieldPanBandY = farFieldPathYAtRender - broadFarFieldY
        let farFieldPanBandRoll = farFieldPathRollAtRender - broadFarFieldRoll
        let panBandX = globalPanBandX + ((farFieldPanBandX - globalPanBandX) * farFieldMacroBlend)
        let panBandY = globalPanBandY + ((farFieldPanBandY - globalPanBandY) * farFieldMacroBlend)
        let panBandRoll = globalPanBandRoll + ((farFieldPanBandRoll - globalPanBandRoll) * farFieldMacroBlend)
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
        let turnOwnership = turnOwnershipX
        let confidenceX = turnBandConfidenceX * turnOwnershipX
        let confidence = confidenceX
        let combinedTurnCorrectionConfidence = turnCorrectionConfidence(
            confidence: confidence,
            turnOwnership: turnOwnership
        )
        let turnCorrectionConfidenceX = turnCorrectionConfidence(
            confidence: confidenceX,
            turnOwnership: turnOwnershipX
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
        let turnXMacroPixels = abs(panBandX * xScale)
        let turnYMacroPixels = abs(panBandY * yScale)
        let baseFootstepXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        let baseStrideXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
        let footstepXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawFootstepXConfidence,
            bandMagnitude: abs(footstepImpulseX * xScale),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport
        )
        let strideXTurnGateFloor = turnOwnedWalkingXGateFloor(
            rawConfidence: rawStrideXConfidence,
            bandMagnitude: abs(strideBandX * xScale),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * turnOwnedStrideXGateFloorScale
        let footstepXTurnGate = max(baseFootstepXTurnGate, footstepXTurnGateFloor)
        let footstepYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepYSuppression), min: 0.0, max: 1.0)
        let footstepRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepRollSuppression), min: 0.0, max: 1.0)
        let strideXTurnGate = max(baseStrideXTurnGate, strideXTurnGateFloor)
        let strideYTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideYSuppression), min: 0.0, max: 1.0)
        let strideRollTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideRollSuppression), min: 0.0, max: 1.0)
        let turnOwnedFootstepXFineGate = turnOwnedFootstepXFineBandGate(
            bandPixels: footstepImpulseX * xScale,
            turnOwnership: turnOwnershipX
        )
        let footstepXWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: footstepImpulseX * xScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        ) * turnOwnedFootstepXFineGate
        let footstepYWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: (footstepPathYAtRender - footstepBaselineY) * yScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let footstepXFarFieldConfidenceFloor = max(
            turnOwnedFarFieldWalkingXConfidenceFloor(
                bandMagnitude: abs(footstepImpulseX * xScale),
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: turnOwnershipX,
                turnMacroMagnitude: turnXMacroPixels,
                farFieldSupport: farFieldTurnOwnedXSupport
            ),
            max(
                turnOwnedFootstepXRescueConfidenceFloor(
                    bandPixels: footstepImpulseX * xScale,
                    turnShakeSuppression: turnShakeSuppression,
                    turnOwnership: turnOwnershipX,
                    farFieldSupport: farFieldTurnOwnedXSupport,
                    fineGate: turnOwnedFootstepXFineGate
                ),
                footstepXWalkingRescueConfidenceFloor
            )
        )
        let footstepRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: footstepPathRollAtRender - microImpulseBaselineRoll,
            farFieldSupport: farFieldTurnOwnedXSupport
        )
        let footstepYFarFieldConfidenceFloor = max(
            farFieldFootstepVerticalConfidenceFloor(
                bandPixels: (footstepPathYAtRender - footstepBaselineY) * yScale,
                farFieldSupport: farFieldTurnOwnedXSupport
            ),
            footstepYWalkingRescueConfidenceFloor
        )
        let strideXBaseFarFieldConfidenceFloor = turnOwnedFarFieldWalkingXConfidenceFloor(
            bandMagnitude: abs(strideBandX * xScale),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * turnOwnedStrideXGateFloorScale
        let strideXRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandX * xScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideYBaseFarFieldConfidenceFloor = farFieldFootstepVerticalConfidenceFloor(
            bandPixels: strideBandY * yScale,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * farFieldStrideVerticalConfidenceFloorScale
        let strideYRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
            bandPixels: strideBandY * yScale,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipY,
            turnMacroMagnitude: turnYMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let strideXFarFieldConfidenceFloor = max(strideXBaseFarFieldConfidenceFloor, strideXRescueConfidenceFloor)
        let strideYFarFieldConfidenceFloor = max(strideYBaseFarFieldConfidenceFloor, strideYRescueConfidenceFloor)
        let strideRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
            bandDegrees: strideBandRoll,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * farFieldStrideRollConfidenceFloorScale
        let footstepXConfidence = max(rawFootstepXConfidence * footstepXTurnGate, footstepXFarFieldConfidenceFloor)
        let footstepYConfidence = max(rawFootstepYConfidence * footstepYTurnGate, footstepYFarFieldConfidenceFloor)
        let footstepRollConfidence = max(rawFootstepRollConfidence * footstepRollTurnGate, footstepRollFarFieldConfidenceFloor)
        let strideXConfidence = max(rawStrideXConfidence * strideXTurnGate, strideXFarFieldConfidenceFloor)
        let strideYConfidence = max(rawStrideYConfidence * strideYTurnGate, strideYFarFieldConfidenceFloor)
        let strideRollConfidence = max(rawStrideRollConfidence * strideRollTurnGate, strideRollFarFieldConfidenceFloor)
        let jitterConfidence = (footstepXConfidence + footstepYConfidence + footstepRollConfidence) / 3.0
        let strideConfidence = (strideXConfidence + strideYConfidence + strideRollConfidence) / 3.0
        let panCorrectionStrengthX = confidenceCompensatedCorrectionFactor(strengths.turnSmoothingZoom, confidence: turnCorrectionConfidenceX)
        let cameraJitterMacroYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterY,
            confidence: turnBandConfidenceY,
            maxStrength: 10.0
        )
        let cameraJitterMacroRollCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(
            strengths.cameraJitterRotation,
            confidence: turnBandConfidenceRoll
        )
        let microXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterX, confidence: footstepXConfidence, maxStrength: 10.0)
        let microYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.microJitterY, confidence: footstepYConfidence, maxStrength: 10.0)
        let microRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.microJitterRotation, confidence: footstepRollConfidence)
        let strideXCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleX, confidence: strideXConfidence, maxStrength: 10.0)
        let strideYCorrectionStrength = verticalWalkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleY, confidence: strideYConfidence, maxStrength: 10.0)
        let strideRotationCorrectionStrength = walkingConfidenceCompensatedCorrectionFactor(strengths.strideWobbleRotation, confidence: strideRollConfidence)
        let rawMacroCompensationX = -panBandX * xScale * positionGain * panCorrectionStrengthX
        let cameraJitterMacroCompensationY = -panBandY * yScale * positionGain * cameraJitterMacroYCorrectionStrength
        let cameraJitterMacroCompensationRotation = -panBandRoll * rotationGain * cameraJitterMacroRollCorrectionStrength
        let detectedTurnPixelOffset = vector_float2(-panBandX * xScale, 0.0)
        let macroCompensationX = softLimit(
            rawMacroCompensationX,
            limit: turnSmoothingXOffsetLimit(
                outputPixels: outputSize.x,
                turnSmoothingStrength: strengths.turnSmoothingZoom
            )
        )
        let unscaledRawMicroCompensationX = -footstepImpulseX * xScale * microXCorrectionStrength
        let lowEvidenceMicroXScale = lowEvidenceLargeFootstepXScale(
            rawConfidence: max(rawFootstepXConfidence, footstepXFarFieldConfidenceFloor),
            correctionPixels: unscaledRawMicroCompensationX,
            farFieldSupport: farFieldTurnOwnedXSupport
        )
        let effectiveMicroXCorrectionStrength = microXCorrectionStrength * lowEvidenceMicroXScale
        let rawMicroCompensationX = unscaledRawMicroCompensationX * lowEvidenceMicroXScale
        let rawMicroCompensationY = -(footstepPathYAtRender - footstepBaselineY) * yScale * microYCorrectionStrength
        let footstepXContinuityConfidenceScale = max(footstepXTurnGate, farFieldTurnOwnedXSupport)
        let footstepYContinuityConfidenceScale = max(footstepYTurnGate, farFieldTurnOwnedXSupport)
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
                confidenceScale: footstepXContinuityConfidenceScale,
                confidenceFloor: footstepXFarFieldConfidenceFloor,
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
                confidenceScale: footstepYContinuityConfidenceScale,
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
        let macroPixelOffset = vector_float2(macroCompensationX, 0.0)
        let microPixelOffset = vector_float2(microCompensationX, microCompensationY)
        let strideWobblePixelOffset = vector_float2(strideCompensationX, strideCompensationY)
        let trajectoryMicroJitterPixelOffset = farFieldWalkingResidualContinuityOffset(
            footstepBandPixels: vector_float2(
                footstepImpulseX * xScale,
                (footstepPathYAtRender - footstepBaselineY) * yScale
            ),
            footstepCorrectionPixels: microPixelOffset,
            strideBandPixels: vector_float2(strideBandX * xScale, strideBandY * yScale),
            strideCorrectionPixels: strideWobblePixelOffset,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: vector_float2(turnOwnershipX, turnOwnershipY),
            turnMacroMagnitude: vector_float2(turnXMacroPixels, turnYMacroPixels),
            farFieldSupport: farFieldTurnOwnedXSupport,
            warpConfidence: max(warpConfidence, farFieldMacroConfidence),
            trackingConfidence: strideTrackingConfidence,
            farFieldConfidence: farFieldMacroConfidence
        )
        let trajectoryContinuityPixelOffset = vector_float2(0.0, cameraJitterMacroCompensationY)
        let compensationX = macroPixelOffset.x + microPixelOffset.x + strideWobblePixelOffset.x + trajectoryMicroJitterPixelOffset.x
        let compensationY = macroPixelOffset.y + microPixelOffset.y + strideWobblePixelOffset.y + trajectoryMicroJitterPixelOffset.y + trajectoryContinuityPixelOffset.y
        let compensationRotation = cameraJitterMacroCompensationRotation + microCompensationRotation + strideCompensationRotation
        let farFieldWarpStrengths = effectiveFarFieldWarpComponentStrengths(Float(strengths.farFieldWarp))
        let shouldEstimateFarFieldWarp = includeFarFieldWarp && farFieldWarpStrengths.isActive
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
            let farFieldWarpTurnGate: Float = 1.0
            appliedWarpConfidence = farFieldWarpAppliedConfidence(
                stableWarpConfidence: stableWarpConfidence,
                warpGate: farFieldWarpGate,
                turnGate: farFieldWarpTurnGate,
                trackingConfidence: farFieldWarpTrackingConfidence,
                edgeQuality: farFieldWarpEdgeQuality
            )
            yawPitchProxy = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathYaw,
                    baselineValues: farFieldBaselineYawPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPitch,
                    baselineValues: farFieldBaselinePitchPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldYawPitchProxy * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.yawPitch,
                    limit: maxRenderedFarFieldYawPitchProxy
                )
            )
            shear = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathShearX,
                    baselineValues: farFieldBaselineShearXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathShearY,
                    baselineValues: farFieldBaselineShearYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldShear * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.shear,
                    limit: maxRenderedFarFieldShear
                )
            )
            perspective = vector_float2(
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPerspectiveX,
                    baselineValues: farFieldBaselinePerspectiveXPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                ),
                strengthScaledFarFieldWarpBandValue(
                    values: analysis.pathPerspectiveY,
                    baselineValues: farFieldBaselinePerspectiveYPath,
                    interpolation: frameInterpolation,
                    deadband: maxRenderedFarFieldPerspective * farFieldWarpFineShakeDeadbandScale,
                    confidence: appliedWarpConfidence,
                    strength: farFieldWarpStrengths.perspective,
                    limit: maxRenderedFarFieldPerspective
                )
            )
        } else {
            appliedWarpConfidence = 0.0
            yawPitchProxy = vector_float2(0.0, 0.0)
            shear = vector_float2(0.0, 0.0)
            perspective = vector_float2(0.0, 0.0)
        }
        let lensShake = shouldEstimateFarFieldWarp
            ? sourceSpaceLensShakeCorrection(
                analysis: analysis,
                frames: frames,
                interpolation: frameInterpolation,
                outputScale: vector_float2(xScale, yScale),
                warpConfidence: appliedWarpConfidence,
                farFieldConfidence: farFieldMacroConfidence,
                trackingConfidence: trackingConfidence,
                edgeQuality: searchRadiusEdgeQuality(
                    hitCount: searchRadiusHitCount,
                    totalCount: searchRadiusTotalCount
                ),
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: vector_float2(turnOwnershipX, turnOwnershipY),
                cache: cache
            )
            : SourceSpaceLensShakeCorrection()
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY) + lensShake.pixelOffset,
            macroPixelOffset: macroPixelOffset,
            microPixelOffset: microPixelOffset,
            strideWobblePixelOffset: strideWobblePixelOffset,
            trajectoryMicroJitterPixelOffset: trajectoryMicroJitterPixelOffset,
            trajectoryContinuityPixelOffset: trajectoryContinuityPixelOffset,
            lensShakePixelOffset: lensShake.pixelOffset,
            lensShakeRotationDegrees: lensShake.rotationDegrees,
            lensShakeYawPitch: lensShake.yawPitch,
            lensShakeShear: lensShake.shear,
            lensShakePerspective: lensShake.perspective,
            lensShakeScore: lensShake.score,
            lensShakeSupport: lensShake.support,
            lensShakeWindowFrames: lensShake.windowFrames,
            lensShakeWindowSeconds: lensShake.windowSeconds,
            lensShakeAxisMask: lensShake.axisMask,
            lensShakeReasonCode: lensShake.reasonCode,
            lensShakeRollingShutterCandidate: lensShake.rollingShutterCandidate,
            lensBandTopOffset: lensShake.bandTopOffset,
            lensBandRidgeOffset: lensShake.bandRidgeOffset,
            lensBandMidOffset: lensShake.bandMidOffset,
            lensBandRawTopOffset: lensShake.bandRawTopOffset,
            lensBandRawRidgeOffset: lensShake.bandRawRidgeOffset,
            lensBandRawMidOffset: lensShake.bandRawMidOffset,
            lensBandPulseDeltaTopOffset: lensShake.bandPulseDeltaTopOffset,
            lensBandPulseDeltaRidgeOffset: lensShake.bandPulseDeltaRidgeOffset,
            lensBandPulseDeltaMidOffset: lensShake.bandPulseDeltaMidOffset,
            lensBandPulseWindowFrames: lensShake.bandPulseWindowFrames,
            lensBandTopColumnOffset: lensShake.bandTopColumnOffset,
            lensBandRidgeColumnOffset: lensShake.bandRidgeColumnOffset,
            lensBandMidColumnOffset: lensShake.bandMidColumnOffset,
            lensBandTopRowPhaseOffset: lensShake.bandTopRowPhaseOffset,
            lensBandRidgeRowPhaseOffset: lensShake.bandRidgeRowPhaseOffset,
            lensBandMidRowPhaseOffset: lensShake.bandMidRowPhaseOffset,
            lensBandTopLocalRoll: lensShake.bandTopLocalRoll,
            lensBandRidgeLocalRoll: lensShake.bandRidgeLocalRoll,
            lensBandMidLocalRoll: lensShake.bandMidLocalRoll,
            lensBandWarpSupport: lensShake.bandWarpSupport,
            lensBandWarpApplied: lensShake.bandWarpApplied,
            lensBandRollingShutterScore: lensShake.bandRollingShutterScore,
            lensBandModelMask: lensShake.bandModelMask,
            lensFarFieldRigidShakeOffset: lensShake.farFieldRigidOffset,
            lensFarFieldRigidShakeSupport: lensShake.farFieldRigidSupport,
            lensFarFieldRigidShakeApplied: lensShake.farFieldRigidApplied,
            lensFarFieldRigidShakeShapeConsistency: lensShake.farFieldRigidShapeConsistency,
            lensFarFieldRigidShakeForwardBackwardConsistency: lensShake.farFieldRigidForwardBackwardConsistency,
            lensFarFieldRigidShakeLocalWarpSuppressed: lensShake.farFieldRigidLocalWarpSuppressed,
            lensFarFieldRigidXQuiverScore: lensShake.farFieldRigidXQuiverScore,
            lensFarFieldRigidXBeforeLimiter: lensShake.farFieldRigidXBeforeLimiter,
            lensFarFieldRigidXAfterLimiter: lensShake.farFieldRigidXAfterLimiter,
            lensFarFieldRigidRollResidual: lensShake.farFieldRigidRollResidual,
            lensFarFieldRigidRollSupport: lensShake.farFieldRigidRollSupport,
            lensFarFieldRigidGlobalYOffset: lensShake.farFieldRigidGlobalYOffset,
            lensFarFieldRigidGlobalRollDegrees: lensShake.farFieldRigidGlobalRollDegrees,
            lensFarFieldRigidRollApplied: lensShake.farFieldRigidRollApplied,
            lensFarFieldMeshOffset: lensShake.farFieldMeshOffset,
            lensFarFieldMeshSupport: lensShake.farFieldMeshSupport,
            lensFarFieldMeshBlend: lensShake.farFieldMeshBlend,
            lensFarFieldMeshAvailable: lensShake.farFieldMeshAvailable,
            lensFarFieldMeshSupportedBins: lensShake.farFieldMeshSupportedBins,
            lensFarFieldMeshMaxBinDelta: lensShake.farFieldMeshMaxBinDelta,
            lensFarFieldMeshOpposingBins: lensShake.farFieldMeshOpposingBins,
            lensFarFieldMeshDominantWindowFrames: lensShake.farFieldMeshDominantWindowFrames,
            lensFarFieldMeshDominantWindowSeconds: lensShake.farFieldMeshDominantWindowSeconds,
            lensFarFieldMeshDominantSupport: lensShake.farFieldMeshDominantSupport,
            lensFarFieldMeshDominantCell: lensShake.farFieldMeshDominantCell,
            sourceLensShakeRidgeOffset: lensShake.sourceRidgeOffset,
            sourceLensShakeRidgeSupport: lensShake.sourceRidgeSupport,
            sourceLensShakeRidgeApplied: lensShake.sourceRidgeApplied,
            sourceLensShakeRidgeLineResidual: lensShake.sourceRidgeLineResidual,
            sourceLensShakeRidgeLineOffset: lensShake.sourceRidgeLineOffset,
            sourceLensShakeRidgeLineSupport: lensShake.sourceRidgeLineSupport,
            sourceLensShakeRidgeLineBandSupported: lensShake.sourceRidgeLineBandSupported,
            sourceLensShakeRidgeLineApplied: lensShake.sourceRidgeLineApplied,
            sourceLensShakeLocalTopLeftOffset: lensShake.localTopLeftOffset,
            sourceLensShakeLocalTopCenterOffset: lensShake.localTopCenterOffset,
            sourceLensShakeLocalTopRightOffset: lensShake.localTopRightOffset,
            sourceLensShakeLocalRidgeLeftOffset: lensShake.localRidgeLeftOffset,
            sourceLensShakeLocalRidgeCenterOffset: lensShake.localRidgeCenterOffset,
            sourceLensShakeLocalRidgeRightOffset: lensShake.localRidgeRightOffset,
            sourceLensShakeLocalMidLeftOffset: lensShake.localMidLeftOffset,
            sourceLensShakeLocalMidCenterOffset: lensShake.localMidCenterOffset,
            sourceLensShakeLocalMidRightOffset: lensShake.localMidRightOffset,
            sourceLensShakeLocalSupport: lensShake.localSupport,
            sourceLensShakeLocalApplied: lensShake.localApplied,
            footstepJitterRotationDegrees: cameraJitterMacroCompensationRotation + microCompensationRotation,
            strideWobbleRotationDegrees: strideCompensationRotation,
            rotationDegrees: compensationRotation + lensShake.rotationDegrees,
            turnDetectedPixelOffset: detectedTurnPixelOffset,
            rawPixelOffset: vector_float2(compensationX, compensationY) + lensShake.pixelOffset,
            rawRotationDegrees: compensationRotation + lensShake.rotationDegrees,
            temporalSmoothingPixelDelta: vector_float2(0.0, 0.0),
            temporalSmoothingRotationDelta: 0.0,
            temporalSmoothingSampleCount: 1,
            temporalSmoothingWindowSeconds: 0.0,
            effectiveMicroJitterStrength: vector_float3(
                effectiveMicroXCorrectionStrength,
                max(microYCorrectionStrength, cameraJitterMacroYCorrectionStrength),
                max(microRotationCorrectionStrength, cameraJitterMacroRollCorrectionStrength)
            ),
            effectiveStrideWobbleStrength: vector_float3(
                strideXCorrectionStrength,
                strideYCorrectionStrength,
                strideRotationCorrectionStrength
            ),
            warpConfidence: appliedWarpConfidence,
            microConfidence: max(jitterConfidence, max(turnBandConfidenceY, turnBandConfidenceRoll)),
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
        preserveLensShakeDiagnostics(from: rawCenterTransform, into: &smoothedTransform)
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
            let zoomBridgeAuthority = turnSmoothingZoomBridgeAuthority(
                turnSmoothingZoom: strengths.turnSmoothingZoom,
                turnConfidence: rawCenterTransform.turnConfidence,
                turnTravelPixels: abs(rawCenterTransform.turnDetectedPixelOffset.x)
            )
            if abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
               abs(centerMacroX) > abs(bridgedMacroX),
               (centerMacroX * bridgedMacroX) > 0.0
            {
                let centerResponse = turnCorrectionConfidenceResponse(rawCenterTransform.turnConfidence)
                let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70)
                    * 0.85
                    * (1.0 - (zoomBridgeAuthority * renderTurnTransitionZoomCenterPreservationFade))
                bridgedMacroOffset.x = bridgedMacroX + ((centerMacroX - bridgedMacroX) * centerPreservation)
            }
            bridgedMacroOffset.x = turnTransitionCenterAnchoredBridgeMacroX(
                centerTransform: rawCenterTransform,
                bridgeMacroX: bridgedMacroOffset.x,
                zoomBridgeAuthority: zoomBridgeAuthority
            )
            let bridgeBlend = turnTransitionBridgeBlend(
                centerTransform: rawCenterTransform,
                bridgeTransform: smoothedTurnTransform
            ) * turnSmoothingBridgeBlend(strengths.turnSmoothingZoom)
            smoothedTransform.macroPixelOffset += (bridgedMacroOffset - smoothedTransform.macroPixelOffset) * bridgeBlend
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
        // Footstep Jitter stays on its short confidence window; broad smoothing is only for TURN/SWOB.
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
            + smoothedTransform.trajectoryMicroJitterPixelOffset
            + smoothedTransform.trajectoryContinuityPixelOffset
            + smoothedTransform.lensShakePixelOffset
        smoothedTransform.rotationDegrees = smoothedTransform.footstepJitterRotationDegrees
            + smoothedTransform.strideWobbleRotationDegrees
            + smoothedTransform.lensShakeRotationDegrees
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
            directionSupport = 0.75
        }
        return clamp(max(centerSupport, smoothedSupport * max(0.72, directionSupport)), min: 0.0, max: 1.0)
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
        let timing = adaptiveXTurnTiming(
            travelPixels: abs(centerTransform.turnDetectedPixelOffset.x),
            baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            turnSmoothingZoom: strengths.turnSmoothingZoom
        )
        let transitionWindowSeconds = timing.windowSeconds
        let sampleCount = adaptiveXTurnTransitionSampleCount(windowSeconds: transitionWindowSeconds)
        let centerSample = sampleCount / 2
        let halfWindow = transitionWindowSeconds * 0.5
        let denominator = Double(max(1, sampleCount - 1))
        let sampleStep = transitionWindowSeconds / denominator
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

    private static func turnSmoothingZoomNormalized(_ value: Double) -> Float {
        let boundedValue = clamp(
            Float(value.isFinite ? value : 0.0),
            min: 0.0,
            max: adaptiveXTurnTransitionMaximumZoomParameter
        )
        return boundedValue / max(adaptiveXTurnTransitionMaximumZoomParameter, Float.ulpOfOne)
    }

    private static func turnSmoothingZoomDemandSupport(
        turnTravelPixels: Float,
        turnConfidence: Float
    ) -> Float {
        let travelSupport = confidenceRamp(
            abs(turnTravelPixels),
            start: adaptiveXTurnTransitionZoomStartPixels,
            full: adaptiveXTurnTransitionZoomFullPixels
        )
        let confidenceSupport = confidenceRamp(
            clamp(turnConfidence, min: 0.0, max: 1.0),
            start: adaptiveXTurnTransitionZoomConfidenceStart,
            full: adaptiveXTurnTransitionZoomConfidenceFull
        )
        return min(travelSupport, confidenceSupport)
    }

    private static func turnSmoothingZoomBridgeAuthority(
        turnSmoothingZoom: Double,
        turnConfidence: Float,
        turnTravelPixels: Float
    ) -> Float {
        turnSmoothingZoomNormalized(turnSmoothingZoom)
            * turnSmoothingZoomDemandSupport(
                turnTravelPixels: turnTravelPixels,
                turnConfidence: turnConfidence
            )
    }

    private static func turnSmoothingBridgeBlend(_ value: Double) -> Float {
        clamp(
            turnSmoothingZoomNormalized(value)
                * (adaptiveXTurnTransitionMaximumZoomParameter / adaptiveXTurnTransitionStandardStrength),
            min: 0.0,
            max: 1.0
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
        bridgeMacroX: Float,
        zoomBridgeAuthority: Float
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
            * (1.0 - (clamp(zoomBridgeAuthority, min: 0.0, max: 1.0) * renderTurnTransitionZoomCenterAnchorFade))
        return bridgeMacroX + ((centerMacroX - bridgeMacroX) * anchor)
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
                    centerFarFieldSupport: centerTransform.warpConfidence,
                    samples: xSamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                ),
                smoothedFootstepScalar(
                    centerValue: centerTransform.microPixelOffset.y,
                    centerConfidence: centerTransform.effectiveMicroJitterStrength.y,
                    centerFarFieldSupport: centerTransform.warpConfidence,
                    samples: ySamples,
                    similarityScale: renderFootstepJitterSmoothingPixelSimilarity
                )
            ),
            rotationDegrees: smoothedFootstepScalar(
                centerValue: centerTransform.footstepJitterRotationDegrees,
                centerConfidence: centerTransform.effectiveMicroJitterStrength.z,
                centerFarFieldSupport: centerTransform.warpConfidence,
                samples: rollSamples,
                similarityScale: renderFootstepJitterSmoothingRotationSimilarity
            )
        )
    }

    private static func smoothedFootstepScalar(
        centerValue: Float,
        centerConfidence: Float,
        centerFarFieldSupport: Float,
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
                  sample.confidence > 0.0
            else {
                continue
            }
            guard sample.value * centerValue > 0.0 else {
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
        let neighborSupport = totalWeight > Float.ulpOfOne
            ? clamp(neighborWeight / totalWeight, min: 0.0, max: 1.0)
            : 0.0
        guard neighborWeight > 0.05, totalWeight > Float.ulpOfOne else {
            return centerValue
        }

        let localAverage = weightedTotal / totalWeight
        let support = neighborSupport
        var blend = renderFootstepJitterSmoothingMaxBlend
            * support
            * max(0.35, boundedCenterConfidence)
        let localAverageMagnitude = abs(localAverage)
        if localAverageMagnitude < centerMagnitude {
            let farFieldSmoothingAuthority = confidenceRamp(
                clamp(centerFarFieldSupport, min: 0.0, max: 1.0),
                start: footstepCenterImpulsePreservationFarFieldStart,
                full: footstepCenterImpulsePreservationFarFieldFull
            )
            let centerDominance = confidenceRamp(
                centerMagnitude - localAverageMagnitude,
                start: similarityScale * 0.10,
                full: similarityScale * 0.55
            )
            let centerAuthority = confidenceRamp(
                boundedCenterConfidence,
                start: playbackTrajectoryFootstepAuthorityGateStart,
                full: playbackTrajectoryFootstepAuthorityGateFull
            )
            let nearFieldImpulseAuthority = 1.0 - farFieldSmoothingAuthority
            blend *= 1.0 - (footstepCenterImpulsePreservationScale * centerDominance * centerAuthority * nearFieldImpulseAuthority)
        }
        let smoothed = centerValue + ((localAverage - centerValue) * blend)
        return smoothed
    }

    private static func weightedAverageTransform(
        _ samples: [(transform: StabilizerAutoTransform, weight: Float)]
    ) -> StabilizerAutoTransform {
        var totalWeight: Float = 0.0
        var macroPixelOffset = vector_float2(0.0, 0.0)
        var microPixelOffset = vector_float2(0.0, 0.0)
        var strideWobblePixelOffset = vector_float2(0.0, 0.0)
        var trajectoryMicroJitterPixelOffset = vector_float2(0.0, 0.0)
        var trajectoryContinuityPixelOffset = vector_float2(0.0, 0.0)
        var lensShakePixelOffset = vector_float2(0.0, 0.0)
        var lensShakeRotationDegrees: Float = 0.0
        var lensShakeYawPitch = vector_float2(0.0, 0.0)
        var lensShakeShear = vector_float2(0.0, 0.0)
        var lensShakePerspective = vector_float2(0.0, 0.0)
        var lensShakeScore: Float = 0.0
        var lensShakeSupport: Float = 0.0
        var lensShakeWindowFrames: Float = 0.0
        var lensShakeWindowSeconds: Float = 0.0
        var lensShakeAxisMask: Int32 = 0
        var lensShakeReasonCode: Int32 = 0
        var lensShakeRollingShutterCandidate: Float = 0.0
        var lensBandTopOffset = vector_float2(0.0, 0.0)
        var lensBandRidgeOffset = vector_float2(0.0, 0.0)
        var lensBandMidOffset = vector_float2(0.0, 0.0)
        var lensBandRawTopOffset = vector_float2(0.0, 0.0)
        var lensBandRawRidgeOffset = vector_float2(0.0, 0.0)
        var lensBandRawMidOffset = vector_float2(0.0, 0.0)
        var lensBandPulseDeltaTopOffset = vector_float2(0.0, 0.0)
        var lensBandPulseDeltaRidgeOffset = vector_float2(0.0, 0.0)
        var lensBandPulseDeltaMidOffset = vector_float2(0.0, 0.0)
        var lensBandPulseWindowFrames: Float = 0.0
        var lensBandTopColumnOffset = vector_float2(0.0, 0.0)
        var lensBandRidgeColumnOffset = vector_float2(0.0, 0.0)
        var lensBandMidColumnOffset = vector_float2(0.0, 0.0)
        var lensBandTopRowPhaseOffset = vector_float2(0.0, 0.0)
        var lensBandRidgeRowPhaseOffset = vector_float2(0.0, 0.0)
        var lensBandMidRowPhaseOffset = vector_float2(0.0, 0.0)
        var lensBandTopLocalRoll: Float = 0.0
        var lensBandRidgeLocalRoll: Float = 0.0
        var lensBandMidLocalRoll: Float = 0.0
        var lensBandWarpSupport: Float = 0.0
        var lensBandWarpApplied: Float = 0.0
        var lensBandRollingShutterScore: Float = 0.0
        var lensBandModelMask: Int32 = 0
        var lensFarFieldRigidShakeOffset = vector_float2(0.0, 0.0)
        var lensFarFieldRigidShakeSupport: Float = 0.0
        var lensFarFieldRigidShakeApplied: Float = 0.0
        var lensFarFieldRigidShakeShapeConsistency: Float = 0.0
        var lensFarFieldRigidShakeForwardBackwardConsistency: Float = 0.0
        var lensFarFieldRigidShakeLocalWarpSuppressed: Float = 0.0
        var lensFarFieldRigidXQuiverScore: Float = 0.0
        var lensFarFieldRigidXBeforeLimiter: Float = 0.0
        var lensFarFieldRigidXAfterLimiter: Float = 0.0
        var lensFarFieldRigidRollResidual: Float = 0.0
        var lensFarFieldRigidRollSupport: Float = 0.0
        var lensFarFieldRigidGlobalYOffset: Float = 0.0
        var lensFarFieldRigidGlobalRollDegrees: Float = 0.0
        var lensFarFieldRigidRollApplied: Float = 0.0
        var lensFarFieldMeshOffset = vector_float2(0.0, 0.0)
        var lensFarFieldMeshSupport: Float = 0.0
        var lensFarFieldMeshBlend: Float = 0.0
        var lensFarFieldMeshAvailable: Float = 0.0
        var lensFarFieldMeshSupportedBins: Float = 0.0
        var lensFarFieldMeshMaxBinDelta: Float = 0.0
        var lensFarFieldMeshOpposingBins: Float = 0.0
        var lensFarFieldMeshDominantWindowFrames: Float = 0.0
        var lensFarFieldMeshDominantWindowSeconds: Float = 0.0
        var lensFarFieldMeshDominantSupport: Float = 0.0
        var lensFarFieldMeshDominantCell: Float = 0.0
        var sourceLensShakeRidgeOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeRidgeSupport: Float = 0.0
        var sourceLensShakeRidgeApplied: Float = 0.0
        var sourceLensShakeRidgeLineResidual = vector_float2(0.0, 0.0)
        var sourceLensShakeRidgeLineOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeRidgeLineSupport: Float = 0.0
        var sourceLensShakeRidgeLineBandSupported: Float = 0.0
        var sourceLensShakeRidgeLineApplied: Float = 0.0
        var sourceLensShakeLocalTopLeftOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalTopCenterOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalTopRightOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalRidgeLeftOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalRidgeCenterOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalRidgeRightOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalMidLeftOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalMidCenterOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalMidRightOffset = vector_float2(0.0, 0.0)
        var sourceLensShakeLocalSupport: Float = 0.0
        var sourceLensShakeLocalApplied: Float = 0.0
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
            macroPixelOffset += transform.macroPixelOffset * weight
            microPixelOffset += transform.microPixelOffset * weight
            strideWobblePixelOffset += transform.strideWobblePixelOffset * weight
            trajectoryMicroJitterPixelOffset += transform.trajectoryMicroJitterPixelOffset * weight
            trajectoryContinuityPixelOffset += transform.trajectoryContinuityPixelOffset * weight
            lensShakePixelOffset += transform.lensShakePixelOffset * weight
            lensShakeRotationDegrees += transform.lensShakeRotationDegrees * weight
            lensShakeYawPitch += transform.lensShakeYawPitch * weight
            lensShakeShear += transform.lensShakeShear * weight
            lensShakePerspective += transform.lensShakePerspective * weight
            lensShakeScore += transform.lensShakeScore * weight
            lensShakeSupport += transform.lensShakeSupport * weight
            lensShakeWindowFrames += transform.lensShakeWindowFrames * weight
            lensShakeWindowSeconds += transform.lensShakeWindowSeconds * weight
            lensShakeAxisMask |= transform.lensShakeAxisMask
            if transform.lensShakeReasonCode == 1 || transform.lensShakeReasonCode == 6 || lensShakeReasonCode == 0 {
                lensShakeReasonCode = transform.lensShakeReasonCode
            }
            lensShakeRollingShutterCandidate += transform.lensShakeRollingShutterCandidate * weight
            lensBandTopOffset += transform.lensBandTopOffset * weight
            lensBandRidgeOffset += transform.lensBandRidgeOffset * weight
            lensBandMidOffset += transform.lensBandMidOffset * weight
            lensBandRawTopOffset += transform.lensBandRawTopOffset * weight
            lensBandRawRidgeOffset += transform.lensBandRawRidgeOffset * weight
            lensBandRawMidOffset += transform.lensBandRawMidOffset * weight
            lensBandPulseDeltaTopOffset += transform.lensBandPulseDeltaTopOffset * weight
            lensBandPulseDeltaRidgeOffset += transform.lensBandPulseDeltaRidgeOffset * weight
            lensBandPulseDeltaMidOffset += transform.lensBandPulseDeltaMidOffset * weight
            lensBandPulseWindowFrames += transform.lensBandPulseWindowFrames * weight
            lensBandTopColumnOffset += transform.lensBandTopColumnOffset * weight
            lensBandRidgeColumnOffset += transform.lensBandRidgeColumnOffset * weight
            lensBandMidColumnOffset += transform.lensBandMidColumnOffset * weight
            lensBandTopRowPhaseOffset += transform.lensBandTopRowPhaseOffset * weight
            lensBandRidgeRowPhaseOffset += transform.lensBandRidgeRowPhaseOffset * weight
            lensBandMidRowPhaseOffset += transform.lensBandMidRowPhaseOffset * weight
            lensBandTopLocalRoll += transform.lensBandTopLocalRoll * weight
            lensBandRidgeLocalRoll += transform.lensBandRidgeLocalRoll * weight
            lensBandMidLocalRoll += transform.lensBandMidLocalRoll * weight
            lensBandWarpSupport += transform.lensBandWarpSupport * weight
            lensBandWarpApplied += transform.lensBandWarpApplied * weight
            lensBandRollingShutterScore += transform.lensBandRollingShutterScore * weight
            lensBandModelMask |= transform.lensBandModelMask
            lensFarFieldRigidShakeOffset += transform.lensFarFieldRigidShakeOffset * weight
            lensFarFieldRigidShakeSupport += transform.lensFarFieldRigidShakeSupport * weight
            lensFarFieldRigidShakeApplied += transform.lensFarFieldRigidShakeApplied * weight
            lensFarFieldRigidShakeShapeConsistency += transform.lensFarFieldRigidShakeShapeConsistency * weight
            lensFarFieldRigidShakeForwardBackwardConsistency += transform.lensFarFieldRigidShakeForwardBackwardConsistency * weight
            lensFarFieldRigidShakeLocalWarpSuppressed += transform.lensFarFieldRigidShakeLocalWarpSuppressed * weight
            lensFarFieldRigidXQuiverScore += transform.lensFarFieldRigidXQuiverScore * weight
            lensFarFieldRigidXBeforeLimiter += transform.lensFarFieldRigidXBeforeLimiter * weight
            lensFarFieldRigidXAfterLimiter += transform.lensFarFieldRigidXAfterLimiter * weight
            lensFarFieldRigidRollResidual += transform.lensFarFieldRigidRollResidual * weight
            lensFarFieldRigidRollSupport += transform.lensFarFieldRigidRollSupport * weight
            lensFarFieldRigidGlobalYOffset += transform.lensFarFieldRigidGlobalYOffset * weight
            lensFarFieldRigidGlobalRollDegrees += transform.lensFarFieldRigidGlobalRollDegrees * weight
            lensFarFieldRigidRollApplied += transform.lensFarFieldRigidRollApplied * weight
            lensFarFieldMeshOffset += transform.lensFarFieldMeshOffset * weight
            lensFarFieldMeshSupport += transform.lensFarFieldMeshSupport * weight
            lensFarFieldMeshBlend += transform.lensFarFieldMeshBlend * weight
            lensFarFieldMeshAvailable += transform.lensFarFieldMeshAvailable * weight
            lensFarFieldMeshSupportedBins += transform.lensFarFieldMeshSupportedBins * weight
            lensFarFieldMeshMaxBinDelta += transform.lensFarFieldMeshMaxBinDelta * weight
            lensFarFieldMeshOpposingBins += transform.lensFarFieldMeshOpposingBins * weight
            lensFarFieldMeshDominantWindowFrames += transform.lensFarFieldMeshDominantWindowFrames * weight
            lensFarFieldMeshDominantWindowSeconds += transform.lensFarFieldMeshDominantWindowSeconds * weight
            lensFarFieldMeshDominantSupport += transform.lensFarFieldMeshDominantSupport * weight
            lensFarFieldMeshDominantCell += transform.lensFarFieldMeshDominantCell * weight
            sourceLensShakeRidgeOffset += transform.sourceLensShakeRidgeOffset * weight
            sourceLensShakeRidgeSupport += transform.sourceLensShakeRidgeSupport * weight
            sourceLensShakeRidgeApplied += transform.sourceLensShakeRidgeApplied * weight
            sourceLensShakeRidgeLineResidual += transform.sourceLensShakeRidgeLineResidual * weight
            sourceLensShakeRidgeLineOffset += transform.sourceLensShakeRidgeLineOffset * weight
            sourceLensShakeRidgeLineSupport += transform.sourceLensShakeRidgeLineSupport * weight
            sourceLensShakeRidgeLineBandSupported += transform.sourceLensShakeRidgeLineBandSupported * weight
            sourceLensShakeRidgeLineApplied += transform.sourceLensShakeRidgeLineApplied * weight
            sourceLensShakeLocalTopLeftOffset += transform.sourceLensShakeLocalTopLeftOffset * weight
            sourceLensShakeLocalTopCenterOffset += transform.sourceLensShakeLocalTopCenterOffset * weight
            sourceLensShakeLocalTopRightOffset += transform.sourceLensShakeLocalTopRightOffset * weight
            sourceLensShakeLocalRidgeLeftOffset += transform.sourceLensShakeLocalRidgeLeftOffset * weight
            sourceLensShakeLocalRidgeCenterOffset += transform.sourceLensShakeLocalRidgeCenterOffset * weight
            sourceLensShakeLocalRidgeRightOffset += transform.sourceLensShakeLocalRidgeRightOffset * weight
            sourceLensShakeLocalMidLeftOffset += transform.sourceLensShakeLocalMidLeftOffset * weight
            sourceLensShakeLocalMidCenterOffset += transform.sourceLensShakeLocalMidCenterOffset * weight
            sourceLensShakeLocalMidRightOffset += transform.sourceLensShakeLocalMidRightOffset * weight
            sourceLensShakeLocalSupport += transform.sourceLensShakeLocalSupport * weight
            sourceLensShakeLocalApplied += transform.sourceLensShakeLocalApplied * weight
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
        let averagedMacroPixelOffset = macroPixelOffset / totalWeight
        let averagedMicroPixelOffset = microPixelOffset / totalWeight
        let averagedStrideWobblePixelOffset = strideWobblePixelOffset / totalWeight
        let averagedTrajectoryMicroJitterPixelOffset = trajectoryMicroJitterPixelOffset / totalWeight
        let averagedTrajectoryContinuityPixelOffset = trajectoryContinuityPixelOffset / totalWeight
        let averagedLensShakePixelOffset = lensShakePixelOffset / totalWeight

        return StabilizerAutoTransform(
            pixelOffset: averagedMacroPixelOffset
                + averagedMicroPixelOffset
                + averagedStrideWobblePixelOffset
                + averagedTrajectoryMicroJitterPixelOffset
                + averagedTrajectoryContinuityPixelOffset
                + averagedLensShakePixelOffset,
            macroPixelOffset: averagedMacroPixelOffset,
            microPixelOffset: averagedMicroPixelOffset,
            strideWobblePixelOffset: averagedStrideWobblePixelOffset,
            trajectoryMicroJitterPixelOffset: averagedTrajectoryMicroJitterPixelOffset,
            trajectoryContinuityPixelOffset: averagedTrajectoryContinuityPixelOffset,
            lensShakePixelOffset: averagedLensShakePixelOffset,
            lensShakeRotationDegrees: lensShakeRotationDegrees / totalWeight,
            lensShakeYawPitch: lensShakeYawPitch / totalWeight,
            lensShakeShear: lensShakeShear / totalWeight,
            lensShakePerspective: lensShakePerspective / totalWeight,
            lensShakeScore: lensShakeScore / totalWeight,
            lensShakeSupport: lensShakeSupport / totalWeight,
            lensShakeWindowFrames: lensShakeWindowFrames / totalWeight,
            lensShakeWindowSeconds: lensShakeWindowSeconds / totalWeight,
            lensShakeAxisMask: lensShakeAxisMask,
            lensShakeReasonCode: lensShakeReasonCode,
            lensShakeRollingShutterCandidate: lensShakeRollingShutterCandidate / totalWeight,
            lensBandTopOffset: lensBandTopOffset / totalWeight,
            lensBandRidgeOffset: lensBandRidgeOffset / totalWeight,
            lensBandMidOffset: lensBandMidOffset / totalWeight,
            lensBandRawTopOffset: lensBandRawTopOffset / totalWeight,
            lensBandRawRidgeOffset: lensBandRawRidgeOffset / totalWeight,
            lensBandRawMidOffset: lensBandRawMidOffset / totalWeight,
            lensBandPulseDeltaTopOffset: lensBandPulseDeltaTopOffset / totalWeight,
            lensBandPulseDeltaRidgeOffset: lensBandPulseDeltaRidgeOffset / totalWeight,
            lensBandPulseDeltaMidOffset: lensBandPulseDeltaMidOffset / totalWeight,
            lensBandPulseWindowFrames: lensBandPulseWindowFrames / totalWeight,
            lensBandTopColumnOffset: lensBandTopColumnOffset / totalWeight,
            lensBandRidgeColumnOffset: lensBandRidgeColumnOffset / totalWeight,
            lensBandMidColumnOffset: lensBandMidColumnOffset / totalWeight,
            lensBandTopRowPhaseOffset: lensBandTopRowPhaseOffset / totalWeight,
            lensBandRidgeRowPhaseOffset: lensBandRidgeRowPhaseOffset / totalWeight,
            lensBandMidRowPhaseOffset: lensBandMidRowPhaseOffset / totalWeight,
            lensBandTopLocalRoll: lensBandTopLocalRoll / totalWeight,
            lensBandRidgeLocalRoll: lensBandRidgeLocalRoll / totalWeight,
            lensBandMidLocalRoll: lensBandMidLocalRoll / totalWeight,
            lensBandWarpSupport: lensBandWarpSupport / totalWeight,
            lensBandWarpApplied: lensBandWarpApplied / totalWeight,
            lensBandRollingShutterScore: lensBandRollingShutterScore / totalWeight,
            lensBandModelMask: lensBandModelMask,
            lensFarFieldRigidShakeOffset: lensFarFieldRigidShakeOffset / totalWeight,
            lensFarFieldRigidShakeSupport: lensFarFieldRigidShakeSupport / totalWeight,
            lensFarFieldRigidShakeApplied: lensFarFieldRigidShakeApplied / totalWeight,
            lensFarFieldRigidShakeShapeConsistency: lensFarFieldRigidShakeShapeConsistency / totalWeight,
            lensFarFieldRigidShakeForwardBackwardConsistency: lensFarFieldRigidShakeForwardBackwardConsistency / totalWeight,
            lensFarFieldRigidShakeLocalWarpSuppressed: lensFarFieldRigidShakeLocalWarpSuppressed / totalWeight,
            lensFarFieldRigidXQuiverScore: lensFarFieldRigidXQuiverScore / totalWeight,
            lensFarFieldRigidXBeforeLimiter: lensFarFieldRigidXBeforeLimiter / totalWeight,
            lensFarFieldRigidXAfterLimiter: lensFarFieldRigidXAfterLimiter / totalWeight,
            lensFarFieldRigidRollResidual: lensFarFieldRigidRollResidual / totalWeight,
            lensFarFieldRigidRollSupport: lensFarFieldRigidRollSupport / totalWeight,
            lensFarFieldRigidGlobalYOffset: lensFarFieldRigidGlobalYOffset / totalWeight,
            lensFarFieldRigidGlobalRollDegrees: lensFarFieldRigidGlobalRollDegrees / totalWeight,
            lensFarFieldRigidRollApplied: lensFarFieldRigidRollApplied / totalWeight,
            lensFarFieldMeshOffset: lensFarFieldMeshOffset / totalWeight,
            lensFarFieldMeshSupport: lensFarFieldMeshSupport / totalWeight,
            lensFarFieldMeshBlend: lensFarFieldMeshBlend / totalWeight,
            lensFarFieldMeshAvailable: lensFarFieldMeshAvailable / totalWeight,
            lensFarFieldMeshSupportedBins: lensFarFieldMeshSupportedBins / totalWeight,
            lensFarFieldMeshMaxBinDelta: lensFarFieldMeshMaxBinDelta / totalWeight,
            lensFarFieldMeshOpposingBins: lensFarFieldMeshOpposingBins / totalWeight,
            lensFarFieldMeshDominantWindowFrames: lensFarFieldMeshDominantWindowFrames / totalWeight,
            lensFarFieldMeshDominantWindowSeconds: lensFarFieldMeshDominantWindowSeconds / totalWeight,
            lensFarFieldMeshDominantSupport: lensFarFieldMeshDominantSupport / totalWeight,
            lensFarFieldMeshDominantCell: lensFarFieldMeshDominantCell / totalWeight,
            sourceLensShakeRidgeOffset: sourceLensShakeRidgeOffset / totalWeight,
            sourceLensShakeRidgeSupport: sourceLensShakeRidgeSupport / totalWeight,
            sourceLensShakeRidgeApplied: sourceLensShakeRidgeApplied / totalWeight,
            sourceLensShakeRidgeLineResidual: sourceLensShakeRidgeLineResidual / totalWeight,
            sourceLensShakeRidgeLineOffset: sourceLensShakeRidgeLineOffset / totalWeight,
            sourceLensShakeRidgeLineSupport: sourceLensShakeRidgeLineSupport / totalWeight,
            sourceLensShakeRidgeLineBandSupported: sourceLensShakeRidgeLineBandSupported / totalWeight,
            sourceLensShakeRidgeLineApplied: sourceLensShakeRidgeLineApplied / totalWeight,
            sourceLensShakeLocalTopLeftOffset: sourceLensShakeLocalTopLeftOffset / totalWeight,
            sourceLensShakeLocalTopCenterOffset: sourceLensShakeLocalTopCenterOffset / totalWeight,
            sourceLensShakeLocalTopRightOffset: sourceLensShakeLocalTopRightOffset / totalWeight,
            sourceLensShakeLocalRidgeLeftOffset: sourceLensShakeLocalRidgeLeftOffset / totalWeight,
            sourceLensShakeLocalRidgeCenterOffset: sourceLensShakeLocalRidgeCenterOffset / totalWeight,
            sourceLensShakeLocalRidgeRightOffset: sourceLensShakeLocalRidgeRightOffset / totalWeight,
            sourceLensShakeLocalMidLeftOffset: sourceLensShakeLocalMidLeftOffset / totalWeight,
            sourceLensShakeLocalMidCenterOffset: sourceLensShakeLocalMidCenterOffset / totalWeight,
            sourceLensShakeLocalMidRightOffset: sourceLensShakeLocalMidRightOffset / totalWeight,
            sourceLensShakeLocalSupport: sourceLensShakeLocalSupport / totalWeight,
            sourceLensShakeLocalApplied: sourceLensShakeLocalApplied / totalWeight,
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
        let rawFarFieldPathX = cumulative(motions.map(\.farFieldDx))
        let rawFarFieldPathY = cumulative(motions.map(\.farFieldDy))
        let rawFarFieldPathRoll = cumulative(motions.map { radiansToDegrees($0.farFieldSignedRoll) })
        let rawPathYaw = cumulative(motions.map(\.yawProxy))
        let rawPathPitch = cumulative(motions.map(\.pitchProxy))
        let rawPathShearX = cumulative(motions.map(\.shearX))
        let rawPathShearY = cumulative(motions.map(\.shearY))
        let rawPathPerspectiveX = cumulative(motions.map(\.perspectiveX))
        let rawPathPerspectiveY = cumulative(motions.map(\.perspectiveY))
        let rawLensBandTopPathX = cumulative(motions.map(\.lensBandTopDx))
        let rawLensBandTopPathY = cumulative(motions.map(\.lensBandTopDy))
        let rawLensBandTopColumnPathX = cumulative(motions.map(\.lensBandTopColumnDx))
        let rawLensBandTopColumnPathY = cumulative(motions.map(\.lensBandTopColumnDy))
        let rawLensBandTopRowPhasePathX = cumulative(motions.map(\.lensBandTopRowPhaseDx))
        let rawLensBandTopRowPhasePathY = cumulative(motions.map(\.lensBandTopRowPhaseDy))
        let rawLensBandTopLocalRollPath = cumulative(motions.map(\.lensBandTopLocalRoll))
        let rawLensBandRidgePathX = cumulative(motions.map(\.lensBandRidgeDx))
        let rawLensBandRidgePathY = cumulative(motions.map(\.lensBandRidgeDy))
        let rawLensBandRidgeColumnPathX = cumulative(motions.map(\.lensBandRidgeColumnDx))
        let rawLensBandRidgeColumnPathY = cumulative(motions.map(\.lensBandRidgeColumnDy))
        let rawLensBandRidgeRowPhasePathX = cumulative(motions.map(\.lensBandRidgeRowPhaseDx))
        let rawLensBandRidgeRowPhasePathY = cumulative(motions.map(\.lensBandRidgeRowPhaseDy))
        let rawLensBandRidgeLocalRollPath = cumulative(motions.map(\.lensBandRidgeLocalRoll))
        let rawLensBandMidPathX = cumulative(motions.map(\.lensBandMidDx))
        let rawLensBandMidPathY = cumulative(motions.map(\.lensBandMidDy))
        let rawLensBandMidColumnPathX = cumulative(motions.map(\.lensBandMidColumnDx))
        let rawLensBandMidColumnPathY = cumulative(motions.map(\.lensBandMidColumnDy))
        let rawLensBandMidRowPhasePathX = cumulative(motions.map(\.lensBandMidRowPhaseDx))
        let rawLensBandMidRowPhasePathY = cumulative(motions.map(\.lensBandMidRowPhaseDy))
        let rawLensBandMidLocalRollPath = cumulative(motions.map(\.lensBandMidLocalRoll))
        let rawSourceLensShakeRidgePathY = cumulative(motions.map(\.sourceLensShakeRidgeDy))
        let rawSourceLensShakeRidgeLinePathY = cumulative(motions.map(\.sourceLensShakeRidgeLineDy))
        var rawSourceLensShakeLocalPathX: [Float] = []
        var rawSourceLensShakeLocalPathY: [Float] = []
        rawSourceLensShakeLocalPathX.reserveCapacity(sourceLensShakeLocalBinCount * motions.count)
        rawSourceLensShakeLocalPathY.reserveCapacity(sourceLensShakeLocalBinCount * motions.count)
        for bin in 0..<sourceLensShakeLocalBinCount {
            rawSourceLensShakeLocalPathX.append(contentsOf: cumulative(motions.map { motion in
                motion.sourceLensShakeLocalDx.indices.contains(bin) ? motion.sourceLensShakeLocalDx[bin] : 0.0
            }))
            rawSourceLensShakeLocalPathY.append(contentsOf: cumulative(motions.map { motion in
                motion.sourceLensShakeLocalDy.indices.contains(bin) ? motion.sourceLensShakeLocalDy[bin] : 0.0
            }))
        }
        var rawSourceLensShakeLocalSupport: [Float] = []
        rawSourceLensShakeLocalSupport.reserveCapacity(sourceLensShakeLocalBinCount * motions.count)
        for bin in 0..<sourceLensShakeLocalBinCount {
            rawSourceLensShakeLocalSupport.append(contentsOf: motions.map { motion in
                motion.sourceLensShakeLocalSupport.indices.contains(bin) ? motion.sourceLensShakeLocalSupport[bin] : 0.0
            })
        }
        var rawFarFieldMeshPathX: [Float] = []
        var rawFarFieldMeshPathY: [Float] = []
        var rawFarFieldMeshSupport: [Float] = []
        rawFarFieldMeshPathX.reserveCapacity(farFieldMeshBinCount * motions.count)
        rawFarFieldMeshPathY.reserveCapacity(farFieldMeshBinCount * motions.count)
        rawFarFieldMeshSupport.reserveCapacity(farFieldMeshBinCount * motions.count)
        for bin in 0..<farFieldMeshBinCount {
            rawFarFieldMeshPathX.append(contentsOf: cumulative(motions.map { motion in
                motion.farFieldMeshDx.indices.contains(bin) ? motion.farFieldMeshDx[bin] : 0.0
            }))
            rawFarFieldMeshPathY.append(contentsOf: cumulative(motions.map { motion in
                motion.farFieldMeshDy.indices.contains(bin) ? motion.farFieldMeshDy[bin] : 0.0
            }))
            rawFarFieldMeshSupport.append(contentsOf: motions.map { motion in
                motion.farFieldMeshSupport.indices.contains(bin) ? motion.farFieldMeshSupport[bin] : 0.0
            })
        }
        let farFieldMeshDominantWindows = farFieldMeshDominantWindows(
            frames: sortedFrames,
            pathX: rawFarFieldMeshPathX,
            pathY: rawFarFieldMeshPathY,
            support: rawFarFieldMeshSupport,
            rows: farFieldMeshRows,
            columns: farFieldMeshColumns
        )
        let farFieldRigidShake = farFieldRigidShakePreparedPaths(
            topX: rawLensBandTopPathX,
            topY: rawLensBandTopPathY,
            ridgeX: rawLensBandRidgePathX,
            ridgeY: rawLensBandRidgePathY,
            midX: rawLensBandMidPathX,
            midY: rawLensBandMidPathY,
            rollDegrees: rawFarFieldPathRoll,
            topConfidence: motions.map(\.lensBandTopConfidence),
            ridgeConfidence: motions.map(\.lensBandRidgeConfidence),
            midConfidence: motions.map(\.lensBandMidConfidence)
        )
        guard farFieldRigidShake.pathX.count == sortedFrames.count,
              farFieldRigidShake.pathY.count == sortedFrames.count,
              farFieldRigidShake.pathRoll.count == sortedFrames.count,
              farFieldRigidShake.support.count == sortedFrames.count,
              farFieldRigidShake.rollSupport.count == sortedFrames.count,
              farFieldRigidShake.shapeConsistency.count == sortedFrames.count,
              farFieldRigidShake.forwardBackwardConsistency.count == sortedFrames.count else {
            throw metalError("far-field rigid shake preparation produced incomplete current-schema paths")
        }
        return StabilizerPreparedAnalysis(
            frames: sortedFrames.map { $0.withoutRetainedPixels() },
            qualityModel: .fxplugHostAnalysis,
            residuals: motions.map(\.residual),
            rollMotion: motions.map(\.rollMotion),
            pathX: jerkLimitedMotionPath(rawPathX, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathY: jerkLimitedMotionPath(rawPathY, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathRoll: jerkLimitedMotionPath(rawPathRoll, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            farFieldPathX: jerkLimitedMotionPath(rawFarFieldPathX, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            farFieldPathY: jerkLimitedMotionPath(rawFarFieldPathY, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            farFieldPathRoll: jerkLimitedMotionPath(rawFarFieldPathRoll, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            farFieldConfidence: motions.map(\.farFieldConfidence),
            footstepPathX: rawPathX,
            footstepPathY: rawPathY,
            footstepPathRoll: rawPathRoll,
            pathYaw: jerkLimitedMotionPath(rawPathYaw, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathPitch: jerkLimitedMotionPath(rawPathPitch, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
            pathShearX: jerkLimitedMotionPath(rawPathShearX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathShearY: jerkLimitedMotionPath(rawPathShearY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveX: jerkLimitedMotionPath(rawPathPerspectiveX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            pathPerspectiveY: jerkLimitedMotionPath(rawPathPerspectiveY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
            lensBandTopPathX: rawLensBandTopPathX,
            lensBandTopPathY: rawLensBandTopPathY,
            lensBandTopColumnPathX: rawLensBandTopColumnPathX,
            lensBandTopColumnPathY: rawLensBandTopColumnPathY,
            lensBandTopRowPhasePathX: rawLensBandTopRowPhasePathX,
            lensBandTopRowPhasePathY: rawLensBandTopRowPhasePathY,
            lensBandTopLocalRollPath: rawLensBandTopLocalRollPath,
            lensBandRidgePathX: rawLensBandRidgePathX,
            lensBandRidgePathY: rawLensBandRidgePathY,
            lensBandRidgeColumnPathX: rawLensBandRidgeColumnPathX,
            lensBandRidgeColumnPathY: rawLensBandRidgeColumnPathY,
            lensBandRidgeRowPhasePathX: rawLensBandRidgeRowPhasePathX,
            lensBandRidgeRowPhasePathY: rawLensBandRidgeRowPhasePathY,
            lensBandRidgeLocalRollPath: rawLensBandRidgeLocalRollPath,
            lensBandMidPathX: rawLensBandMidPathX,
            lensBandMidPathY: rawLensBandMidPathY,
            lensBandMidColumnPathX: rawLensBandMidColumnPathX,
            lensBandMidColumnPathY: rawLensBandMidColumnPathY,
            lensBandMidRowPhasePathX: rawLensBandMidRowPhasePathX,
            lensBandMidRowPhasePathY: rawLensBandMidRowPhasePathY,
            lensBandMidLocalRollPath: rawLensBandMidLocalRollPath,
            lensBandTopConfidence: motions.map(\.lensBandTopConfidence),
            lensBandRidgeConfidence: motions.map(\.lensBandRidgeConfidence),
            lensBandMidConfidence: motions.map(\.lensBandMidConfidence),
            lensBandConfidence: motions.map(\.lensBandConfidence),
            farFieldRigidShakePathX: farFieldRigidShake.pathX,
            farFieldRigidShakePathY: farFieldRigidShake.pathY,
            farFieldRigidShakePathRoll: farFieldRigidShake.pathRoll,
            farFieldRigidShakeSupport: farFieldRigidShake.support,
            farFieldRigidShakeRollSupport: farFieldRigidShake.rollSupport,
            farFieldRigidShakeShapeConsistency: farFieldRigidShake.shapeConsistency,
            farFieldRigidShakeForwardBackwardConsistency: farFieldRigidShake.forwardBackwardConsistency,
            farFieldMeshRows: farFieldMeshRows,
            farFieldMeshColumns: farFieldMeshColumns,
            farFieldMeshPathX: rawFarFieldMeshPathX,
            farFieldMeshPathY: rawFarFieldMeshPathY,
            farFieldMeshSupport: rawFarFieldMeshSupport,
            farFieldMeshDominantWindowFrames: farFieldMeshDominantWindows.windowFrames,
            farFieldMeshDominantWindowSeconds: farFieldMeshDominantWindows.windowSeconds,
            farFieldMeshDominantSupport: farFieldMeshDominantWindows.support,
            farFieldMeshDominantCell: farFieldMeshDominantWindows.cell,
            sourceLensShakeRidgePathY: rawSourceLensShakeRidgePathY,
            sourceLensShakeRidgeSupport: motions.map(\.sourceLensShakeRidgeSupport),
            sourceLensShakeRidgeLinePathY: rawSourceLensShakeRidgeLinePathY,
            sourceLensShakeRidgeLineSupport: motions.map(\.sourceLensShakeRidgeLineSupport),
            sourceLensShakeLocalBinCount: sourceLensShakeLocalBinCount,
            sourceLensShakeLocalPathX: rawSourceLensShakeLocalPathX,
            sourceLensShakeLocalPathY: rawSourceLensShakeLocalPathY,
            sourceLensShakeLocalSupport: rawSourceLensShakeLocalSupport,
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
        let farFieldDx = farFieldPlane?.dx ?? modelDx
        let farFieldDy = farFieldPlane?.dy ?? modelDy
        let farFieldSignedRoll = farFieldPlane?.signedRoll ?? signedRoll
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
        let lensBandMotion = farFieldLensBandMotion(
            shifts: motionBlocksForModel,
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
                farFieldDx: farFieldDx,
                farFieldDy: farFieldDy,
                farFieldSignedRoll: farFieldSignedRoll,
                farFieldConfidence: farFieldAuthority,
                yawProxy: modelYawProxy,
                pitchProxy: modelPitchProxy,
                shearX: modelShearX,
                shearY: modelShearY,
                perspectiveX: warpMotion.perspectiveX,
                perspectiveY: warpMotion.perspectiveY,
                lensBandTopDx: lensBandMotion.topDx,
                lensBandTopDy: lensBandMotion.topDy,
                lensBandTopColumnDx: lensBandMotion.topColumnDx,
                lensBandTopColumnDy: lensBandMotion.topColumnDy,
                lensBandTopRowPhaseDx: lensBandMotion.topRowPhaseDx,
                lensBandTopRowPhaseDy: lensBandMotion.topRowPhaseDy,
                lensBandTopLocalRoll: lensBandMotion.topLocalRoll,
                lensBandRidgeDx: lensBandMotion.ridgeDx,
                lensBandRidgeDy: lensBandMotion.ridgeDy,
                lensBandRidgeColumnDx: lensBandMotion.ridgeColumnDx,
                lensBandRidgeColumnDy: lensBandMotion.ridgeColumnDy,
                lensBandRidgeRowPhaseDx: lensBandMotion.ridgeRowPhaseDx,
                lensBandRidgeRowPhaseDy: lensBandMotion.ridgeRowPhaseDy,
                lensBandRidgeLocalRoll: lensBandMotion.ridgeLocalRoll,
                lensBandMidDx: lensBandMotion.midDx,
                lensBandMidDy: lensBandMotion.midDy,
                lensBandMidColumnDx: lensBandMotion.midColumnDx,
                lensBandMidColumnDy: lensBandMotion.midColumnDy,
                lensBandMidRowPhaseDx: lensBandMotion.midRowPhaseDx,
                lensBandMidRowPhaseDy: lensBandMotion.midRowPhaseDy,
                lensBandMidLocalRoll: lensBandMotion.midLocalRoll,
                lensBandTopConfidence: lensBandMotion.topConfidence,
                lensBandRidgeConfidence: lensBandMotion.ridgeConfidence,
                lensBandMidConfidence: lensBandMotion.midConfidence,
                lensBandConfidence: lensBandMotion.confidence,
                sourceLensShakeRidgeDy: lensBandMotion.sourceLensShakeRidgeDy,
                sourceLensShakeRidgeSupport: lensBandMotion.sourceLensShakeRidgeSupport,
                sourceLensShakeRidgeLineDy: 0.0,
                sourceLensShakeRidgeLineSupport: 0.0,
                sourceLensShakeLocalDx: lensBandMotion.sourceLensShakeLocalDx,
                sourceLensShakeLocalDy: lensBandMotion.sourceLensShakeLocalDy,
                sourceLensShakeLocalSupport: lensBandMotion.sourceLensShakeLocalSupport,
                farFieldMeshDx: lensBandMotion.farFieldMeshDx,
                farFieldMeshDy: lensBandMotion.farFieldMeshDy,
                farFieldMeshSupport: lensBandMotion.farFieldMeshSupport,
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
        let sourceLensBandColumns = max(4, min(12, usableWidth / 220))
        let sourceLensBands: [(minY: Float, maxY: Float)] = [
            (0.06, 0.18),
            (0.16, 0.30),
            (0.28, 0.46)
        ]
        let meshObservationBands = farFieldMeshBandRanges().map { (minY: $0.0, maxY: $0.1) }
        for band in sourceLensBands + meshObservationBands {
            let y0 = verticalMargin + Int((Float(usableHeight) * band.minY).rounded(.down))
            let y1 = verticalMargin + Int((Float(usableHeight) * band.maxY).rounded(.up))
            let clampedY0 = max(verticalMargin, min(sampleHeight - verticalMargin, y0))
            let clampedY1 = max(clampedY0 + staggeredMotionBlockMinimumHeight, min(sampleHeight - verticalMargin, y1))
            guard clampedY1 <= sampleHeight - verticalMargin else {
                continue
            }
            let centerY = Float(clampedY0 + clampedY1) * 0.5
            guard farFieldWeight(centerY: centerY, sampleHeight: sampleHeight) >= detailMotionBlockFarFieldThreshold else {
                continue
            }
            for column in 0..<sourceLensBandColumns {
                let x0 = horizontalMargin + ((usableWidth * column) / sourceLensBandColumns)
                let x1 = horizontalMargin + ((usableWidth * (column + 1)) / sourceLensBandColumns)
                appendBlock(x0: x0, x1: x1, y0: clampedY0, y1: clampedY1)
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
        return clamp((0.72 - normalizedY) / 0.48, min: 0.04, max: 1.0)
    }

    private static func farFieldPriorityWeight(_ farFieldWeight: Float) -> Float {
        let safeWeight = clamp(farFieldWeight, min: 0.0, max: 1.0)
        return max(0.02, powf(safeWeight, 2.2))
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
        let farFieldFiltered = scoreFiltered.filter { $0.block.farFieldWeight >= farFieldPlaneBroadThreshold }
        let midFieldFiltered = scoreFiltered.filter { $0.block.farFieldWeight >= farFieldPlaneNearThreshold }
        let clusterCandidates: [StabilizerBlockShift]
        if farFieldFiltered.count >= minimumFarFieldMotionBlocks {
            clusterCandidates = farFieldFiltered
        } else if midFieldFiltered.count >= minimumAcceptedMotionBlocks {
            clusterCandidates = midFieldFiltered
        } else {
            clusterCandidates = scoreFiltered
        }
        let medianDx = weightedMedian(clusterCandidates.map { ($0.dx, farFieldPriorityWeight($0.block.farFieldWeight)) }) ?? global.dx
        let medianDy = weightedMedian(clusterCandidates.map { ($0.dy, farFieldPriorityWeight($0.block.farFieldWeight)) }) ?? global.dy
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
        let baseWeight = farFieldPriorityWeight(shift.block.farFieldWeight)
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
        let farFieldShifts = shifts.filter { $0.block.farFieldWeight >= farFieldPlaneBroadThreshold }
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
            let weight = farFieldPriorityWeight(shift.block.farFieldWeight) * scoreWeight
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

    private static func farFieldLensBandMotion(
        shifts: [StabilizerBlockShift],
        sampleWidth: Int,
        sampleHeight: Int,
        analysisConfidence: Float
    ) -> (
        topDx: Float,
        topDy: Float,
        topColumnDx: Float,
        topColumnDy: Float,
        topRowPhaseDx: Float,
        topRowPhaseDy: Float,
        topLocalRoll: Float,
        ridgeDx: Float,
        ridgeDy: Float,
        ridgeColumnDx: Float,
        ridgeColumnDy: Float,
        ridgeRowPhaseDx: Float,
        ridgeRowPhaseDy: Float,
        ridgeLocalRoll: Float,
        midDx: Float,
        midDy: Float,
        midColumnDx: Float,
        midColumnDy: Float,
        midRowPhaseDx: Float,
        midRowPhaseDy: Float,
        midLocalRoll: Float,
        topConfidence: Float,
        ridgeConfidence: Float,
        midConfidence: Float,
        confidence: Float,
        sourceLensShakeRidgeDy: Float,
        sourceLensShakeRidgeSupport: Float,
        sourceLensShakeLocalDx: [Float],
        sourceLensShakeLocalDy: [Float],
        sourceLensShakeLocalSupport: [Float],
        farFieldMeshDx: [Float],
        farFieldMeshDy: [Float],
        farFieldMeshSupport: [Float]
    ) {
        guard shifts.count >= minimumFarFieldMotionBlocks, analysisConfidence > 0.0 else {
            return (
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                Array(repeating: 0.0, count: sourceLensShakeLocalBinCount),
                Array(repeating: 0.0, count: farFieldMeshBinCount),
                Array(repeating: 0.0, count: farFieldMeshBinCount),
                Array(repeating: 0.0, count: farFieldMeshBinCount)
            )
        }
        func band(_ minY: Float, _ maxY: Float, minX: Float = 0.0, maxX: Float = 1.0) -> (dx: Float, dy: Float, support: Float) {
            let candidates = shifts.filter { shift in
                let normalizedY = shift.block.centerY / Float(max(1, sampleHeight))
                let normalizedX = shift.block.centerX / Float(max(1, sampleWidth))
                return normalizedY >= minY
                    && normalizedY <= maxY
                    && normalizedX >= minX
                    && normalizedX <= maxX
                    && shift.block.farFieldWeight >= farFieldPlaneBroadThreshold
                    && shift.score.isFinite
                    && shift.dx.isFinite
                    && shift.dy.isFinite
            }
            guard candidates.count >= minimumFarFieldMotionBlocks else {
                return (0.0, 0.0, 0.0)
            }
            let scoreReference = median(candidates.map(\.score)) ?? 0.0
            let weighted = candidates.map { shift -> (dx: (value: Float, weight: Float), dy: (value: Float, weight: Float)) in
                let scoreQuality = clamp(
                    1.0 - ((shift.score - scoreReference) / max(0.020, scoreReference * 1.25)),
                    min: 0.10,
                    max: 1.0
                )
                let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
                let weight = farFieldPriorityWeight(shift.block.farFieldWeight) * scoreQuality * searchHeadroom
                return ((shift.dx, weight), (shift.dy, weight))
            }
            let dx = weightedMedian(weighted.map(\.dx)) ?? 0.0
            let dy = weightedMedian(weighted.map(\.dy)) ?? 0.0
            let coherencePixels = farFieldConsensusCoherencePixels(sampleWidth: sampleWidth, sampleHeight: sampleHeight)
            let medianDistance = median(candidates.map { hypotf($0.dx - dx, $0.dy - dy) }) ?? coherencePixels
            let coherence = clamp(1.0 - (medianDistance / coherencePixels), min: 0.0, max: 1.0)
            let coverage = confidenceRamp(
                Float(candidates.count),
                start: Float(minimumFarFieldMotionBlocks),
                full: Float(minimumFarFieldMotionBlocks * 3)
            )
            return (dx, dy, clamp(analysisConfidence * coherence * coverage, min: 0.0, max: 1.0))
        }
        func localRoll(_ minY: Float, _ maxY: Float, bandMotion: (dx: Float, dy: Float, support: Float)) -> Float {
            let centerY = (minY + maxY) * 0.5 * Float(max(1, sampleHeight))
            let centerX = Float(max(1, sampleWidth)) * 0.5
            let candidates = shifts.compactMap { shift -> (value: Float, weight: Float)? in
                let normalizedY = shift.block.centerY / Float(max(1, sampleHeight))
                guard normalizedY >= minY,
                      normalizedY <= maxY,
                      shift.block.farFieldWeight >= farFieldPlaneBroadThreshold,
                      shift.score.isFinite,
                      shift.dx.isFinite,
                      shift.dy.isFinite
                else {
                    return nil
                }
                let x = shift.block.centerX - centerX
                let y = shift.block.centerY - centerY
                let denominator = (x * x) + (y * y)
                guard denominator > 1.0 else {
                    return nil
                }
                let residualX = shift.dx - bandMotion.dx
                let residualY = shift.dy - bandMotion.dy
                let roll = ((x * residualY) - (y * residualX)) / denominator
                let scoreQuality = clamp(1.0 - (shift.score * 1.8), min: 0.05, max: 1.0)
                let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
                return (roll, farFieldPriorityWeight(shift.block.farFieldWeight) * scoreQuality * searchHeadroom)
            }
            guard candidates.count >= minimumFarFieldMotionBlocks else {
                return 0.0
            }
            return (weightedMedian(candidates) ?? 0.0) * bandMotion.support
        }
        func ridgeLineImpulseDy(_ bandMotion: (dx: Float, dy: Float, support: Float)) -> (dy: Float, support: Float) {
            guard bandMotion.support > 0.0 else {
                return (0.0, 0.0)
            }
            let candidates = shifts.compactMap { shift -> (value: Float, weight: Float)? in
                let normalizedY = shift.block.centerY / Float(max(1, sampleHeight))
                guard normalizedY >= 0.16,
                      normalizedY <= 0.30,
                      shift.block.farFieldWeight >= farFieldPlaneBroadThreshold,
                      shift.score.isFinite,
                      shift.dy.isFinite
                else {
                    return nil
                }
                let residual = shift.dy - bandMotion.dy
                let scoreQuality = clamp(1.0 - (shift.score * 1.8), min: 0.05, max: 1.0)
                let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
                let weight = farFieldPriorityWeight(shift.block.farFieldWeight) * scoreQuality * searchHeadroom
                return (residual, weight)
            }
            guard candidates.count >= minimumFarFieldMotionBlocks else {
                return (0.0, 0.0)
            }
            let positive = candidates.filter { $0.value > 0.0 }
            let negative = candidates.filter { $0.value < 0.0 }
            let positiveEvidence = positive.reduce(Float(0.0)) { $0 + ($1.value * $1.weight) }
            let negativeEvidence = negative.reduce(Float(0.0)) { $0 + (-$1.value * $1.weight) }
            let selected = positiveEvidence >= negativeEvidence ? positive : negative
            guard selected.count >= minimumFarFieldMotionBlocks,
                  let impulse = weightedMedian(selected),
                  abs(impulse) > 0.0
            else {
                return (0.0, 0.0)
            }
            let selectedWeight = selected.reduce(Float(0.0)) { $0 + $1.weight }
            let support = bandMotion.support
                * confidenceRamp(abs(impulse), start: 0.35, full: 1.45)
                * confidenceRamp(selectedWeight, start: 0.80, full: 3.0)
            return (impulse * support, support)
        }
        let top = band(0.04, 0.22)
        let ridge = band(0.14, 0.34)
        let mid = band(0.28, 0.50)
        let topLeft = band(0.04, 0.22, minX: 0.00, maxX: 0.46)
        let topRight = band(0.04, 0.22, minX: 0.54, maxX: 1.00)
        let ridgeLeft = band(0.14, 0.34, minX: 0.00, maxX: 0.46)
        let ridgeRight = band(0.14, 0.34, minX: 0.54, maxX: 1.00)
        let midLeft = band(0.28, 0.50, minX: 0.00, maxX: 0.46)
        let midRight = band(0.28, 0.50, minX: 0.54, maxX: 1.00)
        let topUpper = band(0.04, 0.13)
        let topLower = band(0.13, 0.22)
        let ridgeUpper = band(0.14, 0.24)
        let ridgeLower = band(0.24, 0.34)
        let midUpper = band(0.28, 0.39)
        let midLower = band(0.39, 0.50)
        func columnDelta(_ left: (dx: Float, dy: Float, support: Float), _ right: (dx: Float, dy: Float, support: Float)) -> (dx: Float, dy: Float) {
            guard left.support > 0.0, right.support > 0.0 else {
                return (0.0, 0.0)
            }
            return (right.dx - left.dx, right.dy - left.dy)
        }
        func rowDelta(_ upper: (dx: Float, dy: Float, support: Float), _ lower: (dx: Float, dy: Float, support: Float)) -> (dx: Float, dy: Float) {
            guard upper.support > 0.0, lower.support > 0.0 else {
                return (0.0, 0.0)
            }
            return (upper.dx - lower.dx, upper.dy - lower.dy)
        }
        let topColumn = columnDelta(topLeft, topRight)
        let ridgeColumn = columnDelta(ridgeLeft, ridgeRight)
        let midColumn = columnDelta(midLeft, midRight)
        let topRow = rowDelta(topUpper, topLower)
        let ridgeRow = rowDelta(ridgeUpper, ridgeLower)
        let midRow = rowDelta(midUpper, midLower)
        let ridgeImpulse = ridgeLineImpulseDy(ridge)
        let localBandRanges: [(Float, Float)] = [
            (0.06, 0.18),
            (0.16, 0.30),
            (0.28, 0.46)
        ]
        let localColumnRanges: [(Float, Float)] = [
            (0.00, 0.24),
            (0.18, 0.42),
            (0.38, 0.62),
            (0.58, 0.82),
            (0.76, 1.00)
        ]
        var localDx = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
        var localDy = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
        var localSupport = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
        for bandIndex in 0..<sourceLensShakeLocalBandCount {
            for columnIndex in 0..<sourceLensShakeLocalColumnCount {
                let bin = (bandIndex * sourceLensShakeLocalColumnCount) + columnIndex
                let bandRange = localBandRanges[bandIndex]
                let columnRange = localColumnRanges[columnIndex]
                let local = band(bandRange.0, bandRange.1, minX: columnRange.0, maxX: columnRange.1)
                localDx[bin] = local.dx
                localDy[bin] = local.dy
                localSupport[bin] = local.support
            }
        }
        let meshBandRanges = farFieldMeshBandRanges()
        let meshColumnRanges = farFieldMeshColumnRanges()
        var meshDx = Array(repeating: Float(0.0), count: farFieldMeshBinCount)
        var meshDy = Array(repeating: Float(0.0), count: farFieldMeshBinCount)
        var meshSupport = Array(repeating: Float(0.0), count: farFieldMeshBinCount)
        for bandIndex in 0..<farFieldMeshRows {
            for columnIndex in 0..<farFieldMeshColumns {
                let bin = (bandIndex * farFieldMeshColumns) + columnIndex
                guard meshBandRanges.indices.contains(bandIndex),
                      meshColumnRanges.indices.contains(columnIndex)
                else {
                    continue
                }
                let bandRange = meshBandRanges[bandIndex]
                let columnRange = meshColumnRanges[columnIndex]
                let mesh = band(bandRange.0, bandRange.1, minX: columnRange.0, maxX: columnRange.1)
                meshDx[bin] = mesh.dx
                meshDy[bin] = mesh.dy
                meshSupport[bin] = mesh.support
            }
        }
        return (
            topDx: top.dx,
            topDy: top.dy,
            topColumnDx: topColumn.dx,
            topColumnDy: topColumn.dy,
            topRowPhaseDx: topRow.dx,
            topRowPhaseDy: topRow.dy,
            topLocalRoll: localRoll(0.04, 0.22, bandMotion: top),
            ridgeDx: ridge.dx,
            ridgeDy: ridge.dy,
            ridgeColumnDx: ridgeColumn.dx,
            ridgeColumnDy: ridgeColumn.dy,
            ridgeRowPhaseDx: ridgeRow.dx,
            ridgeRowPhaseDy: ridgeRow.dy,
            ridgeLocalRoll: localRoll(0.14, 0.34, bandMotion: ridge),
            midDx: mid.dx,
            midDy: mid.dy,
            midColumnDx: midColumn.dx,
            midColumnDy: midColumn.dy,
            midRowPhaseDx: midRow.dx,
            midRowPhaseDy: midRow.dy,
            midLocalRoll: localRoll(0.28, 0.50, bandMotion: mid),
            topConfidence: top.support,
            ridgeConfidence: max(ridge.support, ridgeImpulse.support),
            midConfidence: mid.support,
            confidence: max(top.support, max(max(ridge.support, ridgeImpulse.support), mid.support)),
            sourceLensShakeRidgeDy: ridgeImpulse.dy,
            sourceLensShakeRidgeSupport: ridgeImpulse.support,
            sourceLensShakeLocalDx: localDx,
            sourceLensShakeLocalDy: localDy,
            sourceLensShakeLocalSupport: localSupport,
            farFieldMeshDx: meshDx,
            farFieldMeshDy: meshDy,
            farFieldMeshSupport: meshSupport
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
        let baseWeight = farFieldPriorityWeight(shift.block.farFieldWeight)
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

    private static func representativeFrameStepSeconds(frames: [StabilizerAnalysisFrame]) -> Double {
        guard frames.count >= 2 else {
            return 1.0 / 60.0
        }
        var deltas: [Double] = []
        deltas.reserveCapacity(frames.count - 1)
        for index in 1..<frames.count {
            let delta = frames[index].time - frames[index - 1].time
            if delta.isFinite, delta > 0.0 {
                deltas.append(delta)
            }
        }
        guard !deltas.isEmpty else {
            return 1.0 / 60.0
        }
        deltas.sort()
        return max(1.0 / 240.0, deltas[deltas.count / 2])
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

    private static func turnSmoothingOffsetLimit() -> Float {
        return Float.infinity
    }

    private static func turnSmoothingXOffsetLimit(
        outputPixels: Float,
        turnSmoothingStrength: Double
    ) -> Float {
        guard outputPixels.isFinite, outputPixels > 0.0 else {
            return 0.0
        }
        return outputPixels * 0.5 * turnSmoothingZoomNormalized(turnSmoothingStrength)
    }

    private static func turnSmoothingRotationLimit() -> Float {
        return Float.infinity
    }

    private static func softLimit(_ value: Float, limit: Float) -> Float {
        guard value.isFinite else {
            return value
        }
        guard limit.isFinite else {
            return value
        }
        guard limit > 0.0 else {
            return 0.0
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

    private static func sourceSpaceLensShakeCorrection(
        analysis: StabilizerPreparedAnalysis,
        frames: [StabilizerAnalysisFrame],
        interpolation: FrameInterpolation,
        outputScale: vector_float2,
        warpConfidence: Float,
        farFieldConfidence: Float,
        trackingConfidence: Float,
        edgeQuality: Float,
        turnShakeSuppression: Float,
        turnOwnership: vector_float2,
        cache: RenderEstimateCache
    ) -> SourceSpaceLensShakeCorrection {
        guard frames.count >= 5,
              interpolation.lowerIndex >= 0,
              interpolation.lowerIndex < frames.count
        else {
            var result = SourceSpaceLensShakeCorrection()
            result.reasonCode = 4
            return result
        }

        let centerIndex = interpolation.fraction < 0.5 ? interpolation.lowerIndex : interpolation.upperIndex
        let frameStepSeconds = representativeFrameStepSeconds(frames: frames)
        let hasDominantWindowPaths = analysis.farFieldMeshDominantWindowFrames.count == frames.count
            && analysis.farFieldMeshDominantWindowSeconds.count == frames.count
            && analysis.farFieldMeshDominantSupport.count == frames.count
            && analysis.farFieldMeshDominantCell.count == frames.count
        guard hasDominantWindowPaths else {
            var result = SourceSpaceLensShakeCorrection()
            result.reasonCode = 9
            return result
        }
        let dominantWindowFrames = hasDominantWindowPaths
            ? max(3.0, interpolatedValue(analysis.farFieldMeshDominantWindowFrames, using: interpolation))
            : 3.0
        let dominantWindowSeconds = hasDominantWindowPaths
            ? max(Float(frameStepSeconds * 3.0), interpolatedValue(analysis.farFieldMeshDominantWindowSeconds, using: interpolation))
            : Float(frameStepSeconds * 3.0)
        let dominantWindowSupport = hasDominantWindowPaths
            ? max(0.0, interpolatedValue(analysis.farFieldMeshDominantSupport, using: interpolation))
            : 0.0
        let dominantCellIndex = hasDominantWindowPaths
            ? (interpolation.fraction < 0.5
                ? (analysis.farFieldMeshDominantCell.indices.contains(interpolation.lowerIndex) ? analysis.farFieldMeshDominantCell[interpolation.lowerIndex] : -1)
                : (analysis.farFieldMeshDominantCell.indices.contains(interpolation.upperIndex) ? analysis.farFieldMeshDominantCell[interpolation.upperIndex] : -1))
            : -1
        let targetWindowSeconds = min(1.0, Double(dominantWindowSeconds))
        let innerWindowSeconds = max(lensShakeInnerWindowMinimumSeconds, targetWindowSeconds * 0.56)
        let outerWindowSeconds = min(
            lensShakeOuterWindowMaximumSeconds,
            max(lensShakeOuterWindowMinimumSeconds, targetWindowSeconds * 3.0)
        )
        let activeIndices = indicesWithinTimeRadius(
            frames,
            centerTime: frames[max(0, min(frames.count - 1, centerIndex))].time,
            radiusSeconds: outerWindowSeconds * 0.5
        )
        let sampledIndices = uniqueSortedIndices(
            activeIndices + interpolation.indices,
            validCount: frames.count
        )
        let qualitySupport = confidenceRamp(
            clamp(warpConfidence, min: 0.0, max: 1.0),
            start: 0.16,
            full: 0.55
        ) * confidenceRamp(
            clamp(trackingConfidence, min: 0.0, max: 1.0),
            start: 0.14,
            full: 0.42
        ) * confidenceRamp(
            clamp(edgeQuality, min: 0.0, max: 1.0),
            start: 0.46,
            full: 0.82
        )
        let turnScale: Float = 1.0

        func residual(kind: MotionPathKind, values: [Float]) -> Float {
            guard !values.isEmpty else {
                return 0.0
            }
            let baseline = cachedOuterLinearPredictionPath(
                kind,
                analysis: analysis,
                indices: sampledIndices,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds,
                cache: cache
            )
            return interpolatedValue(values, using: interpolation)
                - interpolatedValue(baseline, using: interpolation)
        }

        func residualValue(values: [Float], baseline: EstimatedPath, index: Int) -> Float {
            guard values.indices.contains(index), baseline.values.indices.contains(index) else {
                return 0.0
            }
            return values[index] - baseline[index]
        }

        func pulseSmoothedResidual(
            kind: MotionPathKind,
            values: [Float],
            currentResidual: Float,
            scale: Float,
            start: Float,
            full: Float
        ) -> Float {
            guard !values.isEmpty else {
                return currentResidual
            }
            let baseline = cachedOuterLinearPredictionPath(
                kind,
                analysis: analysis,
                indices: sampledIndices,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds,
                cache: cache
            )
            let correctionSmoothingWindowSeconds = min(
                1.0,
                max(targetWindowSeconds, lensShakeCorrectionMinimumSmoothingSeconds)
            )
            let correctionSmoothingWindowFrames = max(
                3.0,
                Float(correctionSmoothingWindowSeconds / max(frameStepSeconds, 1.0 / 240.0)).rounded()
            )
            let radiusFrames = max(1, Int(correctionSmoothingWindowFrames) / 2)
            let centerTime = frames[max(0, min(frames.count - 1, centerIndex))].time
            let radiusSeconds = max(frameStepSeconds, Double(radiusFrames) * frameStepSeconds)
            var weightedResidual = Float(0.0)
            var totalWeight = Float(0.0)
            for index in (centerIndex - radiusFrames)...(centerIndex + radiusFrames) {
                guard frames.indices.contains(index), values.indices.contains(index) else {
                    continue
                }
                let distance = abs(frames[index].time - centerTime)
                let normalizedDistance = clamp(Float(distance / radiusSeconds), min: 0.0, max: 1.0)
                let weight = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)
                weightedResidual += residualValue(values: values, baseline: baseline, index: index) * scale * weight
                totalWeight += weight
            }
            guard totalWeight > Float.ulpOfOne else {
                return currentResidual
            }
            let smoothedResidual = weightedResidual / totalWeight
            let pulseMagnitude = abs(currentResidual - smoothedResidual)
            let blend = confidenceRamp(pulseMagnitude, start: start, full: full) * lensBandPulseSmoothingBlend
            return currentResidual + ((smoothedResidual - currentResidual) * blend)
        }

        func pulseSmoothedPixelResidual(kind: MotionPathKind, values: [Float], scale: Float) -> Float {
            let currentResidual = residual(kind: kind, values: values) * scale
            return pulseSmoothedResidual(
                kind: kind,
                values: values,
                currentResidual: currentResidual,
                scale: scale,
                start: lensBandPulseSmoothingStartPixels,
                full: lensBandPulseSmoothingFullPixels
            )
        }

        func localPeakPixelResidual(
            kind: MotionPathKind,
            values: [Float],
            scale: Float,
            radiusSeconds: Double
        ) -> Float {
            guard !values.isEmpty else {
                return 0.0
            }
            let baseline = cachedOuterLinearPredictionPath(
                kind,
                analysis: analysis,
                indices: sampledIndices,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds,
                cache: cache
            )
            let centerTime = frames[max(0, min(frames.count - 1, centerIndex))].time
            let localIndices = indicesWithinTimeRadius(
                frames,
                centerTime: centerTime,
                radiusSeconds: max(frameStepSeconds, radiusSeconds)
            )
            var peak = Float(0.0)
            for index in localIndices where values.indices.contains(index) {
                peak = max(
                    peak,
                    abs(residualValue(values: values, baseline: baseline, index: index) * scale)
                )
            }
            return peak
        }

        func meshValue(_ values: [Float], bin: Int, index: Int, binCount: Int) -> Float? {
            guard bin >= 0,
                  bin < binCount,
                  frames.indices.contains(index)
            else {
                return nil
            }
            let offset = (bin * frames.count) + index
            guard values.indices.contains(offset) else {
                return nil
            }
            return values[offset]
        }

        func interpolatedMeshValue(_ values: [Float], bin: Int, binCount: Int) -> Float {
            guard let lowerValue = meshValue(values, bin: bin, index: interpolation.lowerIndex, binCount: binCount) else {
                return 0.0
            }
            guard interpolation.upperIndex != interpolation.lowerIndex,
                  let upperValue = meshValue(values, bin: bin, index: interpolation.upperIndex, binCount: binCount)
            else {
                return lowerValue
            }
            return lowerValue + ((upperValue - lowerValue) * interpolation.fraction)
        }

        func pulseSmoothedMeshPixelResidual(kind: MotionPathKind, values: [Float], scale: Float) -> Float {
            guard !values.isEmpty else {
                return 0.0
            }
            let baseline = cachedOuterLinearPredictionPath(
                kind,
                analysis: analysis,
                indices: sampledIndices,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds,
                cache: cache
            )
            let currentResidual = (
                interpolatedValue(values, using: interpolation)
                - interpolatedValue(baseline, using: interpolation)
            ) * scale
            let correctionSmoothingWindowSeconds = min(
                1.0,
                max(targetWindowSeconds, lensShakeCorrectionMinimumSmoothingSeconds)
            )
            let correctionSmoothingWindowFrames = max(
                3.0,
                Float(correctionSmoothingWindowSeconds / max(frameStepSeconds, 1.0 / 240.0)).rounded()
            )
            let radiusFrames = max(1, Int(correctionSmoothingWindowFrames) / 2)
            let centerTime = frames[max(0, min(frames.count - 1, centerIndex))].time
            let radiusSeconds = max(frameStepSeconds, Double(radiusFrames) * frameStepSeconds)
            var weightedResidual = Float(0.0)
            var totalWeight = Float(0.0)
            for index in (centerIndex - radiusFrames)...(centerIndex + radiusFrames) {
                guard frames.indices.contains(index),
                      values.indices.contains(index),
                      baseline.values.indices.contains(index)
                else {
                    continue
                }
                let distance = abs(frames[index].time - centerTime)
                let normalizedDistance = clamp(Float(distance / radiusSeconds), min: 0.0, max: 1.0)
                let weight = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)
                weightedResidual += (values[index] - baseline[index]) * scale * weight
                totalWeight += weight
            }
            guard totalWeight > Float.ulpOfOne else {
                return currentResidual
            }
            let smoothedResidual = weightedResidual / totalWeight
            let pulseMagnitude = abs(currentResidual - smoothedResidual)
            let blend = confidenceRamp(pulseMagnitude, start: lensBandPulseSmoothingStartPixels, full: lensBandPulseSmoothingFullPixels) * lensBandPulseSmoothingBlend
            return currentResidual + ((smoothedResidual - currentResidual) * blend)
        }

        func pulseSmoothedRollResidual(kind: MotionPathKind, values: [Float]) -> Float {
            let currentResidual = residual(kind: kind, values: values)
            return pulseSmoothedResidual(
                kind: kind,
                values: values,
                currentResidual: currentResidual,
                scale: 1.0,
                start: lensBandPulseSmoothingStartRadians,
                full: lensBandPulseSmoothingFullRadians
            )
        }

        func pulseSmoothedDegreeRollResidual(kind: MotionPathKind, values: [Float]) -> Float {
            let currentResidual = residual(kind: kind, values: values)
            return pulseSmoothedResidual(
                kind: kind,
                values: values,
                currentResidual: currentResidual,
                scale: 1.0,
                start: lensShakeRollStartDegrees,
                full: lensShakeRollFullDegrees
            )
        }

        func shortWindowQuiverScore(
            kind: MotionPathKind,
            values: [Float],
            rawResidualPixels: Float,
            limitedResidualPixels: Float,
            scale: Float
        ) -> Float {
            guard values.count == frames.count else {
                return 0.0
            }
            let baseline = cachedOuterLinearPredictionPath(
                kind,
                analysis: analysis,
                indices: sampledIndices,
                innerWindowSeconds: innerWindowSeconds,
                outerWindowSeconds: outerWindowSeconds,
                cache: cache
            )
            let windowFrameCount = max(3, Int(max(3.0, dominantWindowFrames).rounded()))
            let radiusFrames = max(1, min(windowFrameCount / 2, Int((1.0 / max(frameStepSeconds, 1.0 / 240.0)).rounded()) / 2))
            let centerTime = frames[max(0, min(frames.count - 1, centerIndex))].time
            let radiusSeconds = min(0.5, max(frameStepSeconds, Double(radiusFrames) * frameStepSeconds))
            var samples: [Float] = []
            samples.reserveCapacity((radiusFrames * 2) + 1)
            for index in (centerIndex - radiusFrames)...(centerIndex + radiusFrames) {
                guard frames.indices.contains(index),
                      values.indices.contains(index),
                      baseline.values.indices.contains(index)
                else {
                    continue
                }
                if abs(frames[index].time - centerTime) > radiusSeconds + (frameStepSeconds * 0.5) {
                    continue
                }
                samples.append((values[index] - baseline[index]) * scale)
            }
            guard samples.count >= 3 else {
                return 0.0
            }
            var minResidual = Float.greatestFiniteMagnitude
            var maxResidual = -Float.greatestFiniteMagnitude
            var maxStep = Float(0.0)
            var maxJerk = Float(0.0)
            var flipCount = 0
            var deltaCount = 0
            var previousSample: Float?
            var previousDelta: Float?
            for sample in samples {
                minResidual = min(minResidual, sample)
                maxResidual = max(maxResidual, sample)
                if let previousSample {
                    let delta = sample - previousSample
                    maxStep = max(maxStep, abs(delta))
                    if let previousDelta {
                        maxJerk = max(maxJerk, abs(delta - previousDelta))
                        if delta * previousDelta < -0.05 {
                            flipCount += 1
                        }
                    }
                    previousDelta = delta
                    deltaCount += 1
                }
                previousSample = sample
            }
            let residualSpan = max(0.0, maxResidual - minResidual)
            let rawDivergence = abs(rawResidualPixels - limitedResidualPixels)
            let flipRatio = deltaCount > 1 ? Float(flipCount) / Float(deltaCount - 1) : 0.0
            let shortPulseEvidence = max(
                confidenceRamp(maxStep, start: 0.35, full: 1.85),
                max(
                    confidenceRamp(maxJerk, start: 0.26, full: 1.25),
                    max(
                        confidenceRamp(residualSpan, start: 0.70, full: 3.10),
                        confidenceRamp(flipRatio, start: 0.18, full: 0.55)
                    )
                )
            )
            let rawDivergenceEvidence = confidenceRamp(rawDivergence, start: 0.22, full: 1.60)
            let sampleSupport = confidenceRamp(Float(samples.count), start: 3.0, full: 9.0)
            let directQuiverEvidence = max(
                confidenceRamp(maxStep, start: 0.18, full: 0.85),
                max(
                    confidenceRamp(maxJerk, start: 0.14, full: 0.62),
                    confidenceRamp(flipRatio, start: 0.10, full: 0.34)
                )
            )
            return clamp(max(shortPulseEvidence * rawDivergenceEvidence, directQuiverEvidence * 0.72) * sampleSupport, min: 0.0, max: 1.0)
        }

        var result = SourceSpaceLensShakeCorrection()
        result.windowFrames = dominantWindowFrames
        result.windowSeconds = Float(targetWindowSeconds)
        result.farFieldMeshDominantWindowFrames = dominantWindowFrames
        result.farFieldMeshDominantWindowSeconds = Float(targetWindowSeconds)
        result.farFieldMeshDominantSupport = clamp(dominantWindowSupport, min: 0.0, max: 1.0)
        result.farFieldMeshDominantCell = Float(dominantCellIndex)
        let lowFrequencyWindowSupport = confidenceRamp(
            Float(targetWindowSeconds),
            start: farFieldLowFrequencyPriorityStartSeconds,
            full: farFieldLowFrequencyPriorityFullSeconds
        )
        let lowFrequencySupport = lowFrequencyWindowSupport
            * confidenceRamp(dominantWindowSupport, start: 0.18, full: 0.72)
            * qualitySupport
        let lowFrequencyTurnScale = 1.0 - ((1.0 - turnScale) * (1.0 - farFieldLowFrequencyTurnSuppressionRelief))

        var maximumEvidence = Float(0.0)
        var maximumAppliedSupport = Float(0.0)

        func supportFor(_ magnitude: Float, start: Float, full: Float) -> Float {
            let evidence = confidenceRamp(magnitude, start: start, full: full)
            maximumEvidence = max(maximumEvidence, evidence)
            return clamp(evidence * qualitySupport * turnScale, min: 0.0, max: 1.0)
        }

        func recordSupport(_ support: Float, axisBit: Int32) -> Bool {
            guard support >= lensShakeMinimumSupport else {
                return false
            }
            maximumAppliedSupport = max(maximumAppliedSupport, support)
            return true
        }

        let residualX = residual(kind: .farFieldX, values: analysis.farFieldPathX) * outputScale.x
        let residualY = residual(kind: .farFieldY, values: analysis.farFieldPathY) * outputScale.y
        let smoothedResidualX = pulseSmoothedPixelResidual(kind: .farFieldX, values: analysis.farFieldPathX, scale: outputScale.x)
        let smoothedResidualY = pulseSmoothedPixelResidual(kind: .farFieldY, values: analysis.farFieldPathY, scale: outputScale.y)
        let residualRoll = residual(kind: .farFieldRoll, values: analysis.farFieldPathRoll)
        let smoothedResidualRoll = pulseSmoothedRollResidual(kind: .farFieldRoll, values: analysis.farFieldPathRoll)
        let yaw = residual(kind: .yaw, values: analysis.pathYaw)
        let pitch = residual(kind: .pitch, values: analysis.pathPitch)
        let shearX = residual(kind: .shearX, values: analysis.pathShearX)
        let shearY = residual(kind: .shearY, values: analysis.pathShearY)
        let perspectiveX = residual(kind: .perspectiveX, values: analysis.pathPerspectiveX)
        let perspectiveY = residual(kind: .perspectiveY, values: analysis.pathPerspectiveY)

        let supportX = supportFor(abs(residualX), start: lensShakePixelStartPixels, full: lensShakePixelFullPixels)
        let supportY = supportFor(abs(residualY), start: lensShakePixelStartPixels, full: lensShakePixelFullPixels)
        let supportRoll = supportFor(abs(residualRoll), start: lensShakeRollStartDegrees, full: lensShakeRollFullDegrees)
        let supportYaw = supportFor(abs(yaw), start: lensShakeYawPitchStart, full: lensShakeYawPitchFull)
        let supportPitch = supportFor(abs(pitch), start: lensShakeYawPitchStart, full: lensShakeYawPitchFull)
        let supportShearX = supportFor(abs(shearX), start: lensShakeShearStart, full: lensShakeShearFull)
        let supportShearY = supportFor(abs(shearY), start: lensShakeShearStart, full: lensShakeShearFull)
        let supportPerspectiveX = supportFor(abs(perspectiveX), start: lensShakePerspectiveStart, full: lensShakePerspectiveFull)
        let supportPerspectiveY = supportFor(abs(perspectiveY), start: lensShakePerspectiveStart, full: lensShakePerspectiveFull)

        let yawPitchSupport = max(supportYaw, supportPitch)
        let affineSupport = max(max(supportX, supportY), supportRoll)
        let projectiveSupport = max(yawPitchSupport, max(max(supportShearX, supportShearY), max(supportPerspectiveX, supportPerspectiveY)))
        let dominantProjectiveCandidate = confidenceRamp(projectiveSupport - affineSupport, start: 0.18, full: 0.55)
        let mixedProjectiveCandidate = min(
            confidenceRamp(projectiveSupport, start: 0.35, full: 0.70),
            confidenceRamp(affineSupport, start: 0.20, full: 0.55)
        ) * 0.75
        result.rollingShutterCandidate = max(dominantProjectiveCandidate, mixedProjectiveCandidate)
        result.bandRollingShutterScore = result.rollingShutterCandidate
        result.score = max(affineSupport, projectiveSupport)
        if supportX >= lensShakeMinimumSupport { result.axisMask |= 1 }
        if supportY >= lensShakeMinimumSupport { result.axisMask |= 2 }
        if supportRoll >= lensShakeMinimumSupport { result.axisMask |= 4 }
        if supportYaw >= lensShakeMinimumSupport { result.axisMask |= 8 }
        if supportPitch >= lensShakeMinimumSupport { result.axisMask |= 16 }
        if supportShearX >= lensShakeMinimumSupport || supportShearY >= lensShakeMinimumSupport { result.axisMask |= 32 }
        if supportPerspectiveX >= lensShakeMinimumSupport || supportPerspectiveY >= lensShakeMinimumSupport { result.axisMask |= 64 }
        if supportRoll >= lensShakeMinimumSupport {
            maximumAppliedSupport = max(maximumAppliedSupport, supportRoll)
            result.rotationDegrees = clamp(
                -smoothedResidualRoll * supportRoll,
                min: -lensShakeRotationMaximumCorrectionDegrees,
                max: lensShakeRotationMaximumCorrectionDegrees
            )
        }

        let hasLensBandPaths = analysis.lensBandTopPathX.count == frames.count
            && analysis.lensBandTopPathY.count == frames.count
            && analysis.lensBandTopColumnPathX.count == frames.count
            && analysis.lensBandTopColumnPathY.count == frames.count
            && analysis.lensBandTopRowPhasePathX.count == frames.count
            && analysis.lensBandTopRowPhasePathY.count == frames.count
            && analysis.lensBandTopLocalRollPath.count == frames.count
            && analysis.lensBandRidgePathX.count == frames.count
            && analysis.lensBandRidgePathY.count == frames.count
            && analysis.lensBandRidgeColumnPathX.count == frames.count
            && analysis.lensBandRidgeColumnPathY.count == frames.count
            && analysis.lensBandRidgeRowPhasePathX.count == frames.count
            && analysis.lensBandRidgeRowPhasePathY.count == frames.count
            && analysis.lensBandRidgeLocalRollPath.count == frames.count
            && analysis.lensBandMidPathX.count == frames.count
            && analysis.lensBandMidPathY.count == frames.count
            && analysis.lensBandMidColumnPathX.count == frames.count
            && analysis.lensBandMidColumnPathY.count == frames.count
            && analysis.lensBandMidRowPhasePathX.count == frames.count
            && analysis.lensBandMidRowPhasePathY.count == frames.count
            && analysis.lensBandMidLocalRollPath.count == frames.count
            && analysis.lensBandTopConfidence.count == frames.count
            && analysis.lensBandRidgeConfidence.count == frames.count
            && analysis.lensBandMidConfidence.count == frames.count
            && analysis.lensBandConfidence.count == frames.count
            && analysis.sourceLensShakeRidgePathY.count == frames.count
            && analysis.sourceLensShakeRidgeSupport.count == frames.count
            && analysis.sourceLensShakeRidgeLinePathY.count == frames.count
            && analysis.sourceLensShakeRidgeLineSupport.count == frames.count
            && analysis.sourceLensShakeLocalBinCount == sourceLensShakeLocalBinCount
            && analysis.sourceLensShakeLocalPathX.count == frames.count * sourceLensShakeLocalBinCount
            && analysis.sourceLensShakeLocalPathY.count == frames.count * sourceLensShakeLocalBinCount
            && analysis.sourceLensShakeLocalSupport.count == frames.count * sourceLensShakeLocalBinCount
        let hasFarFieldRigidShakePaths = analysis.farFieldRigidShakePathX.count == frames.count
            && analysis.farFieldRigidShakePathY.count == frames.count
            && analysis.farFieldRigidShakePathRoll.count == frames.count
            && analysis.farFieldRigidShakeSupport.count == frames.count
            && analysis.farFieldRigidShakeRollSupport.count == frames.count
            && analysis.farFieldRigidShakeShapeConsistency.count == frames.count
            && analysis.farFieldRigidShakeForwardBackwardConsistency.count == frames.count
        let farFieldMeshBinCount = analysis.farFieldMeshRows * analysis.farFieldMeshColumns
        let hasFarFieldMeshPaths = analysis.farFieldMeshRows == farFieldMeshRows
            && analysis.farFieldMeshColumns == farFieldMeshColumns
            && analysis.farFieldMeshPathX.count == frames.count * farFieldMeshBinCount
            && analysis.farFieldMeshPathY.count == frames.count * farFieldMeshBinCount
            && analysis.farFieldMeshSupport.count == frames.count * farFieldMeshBinCount

        func farFieldRigidDeltaCoherenceSupport() -> Float {
            guard hasLensBandPaths,
                  frames.indices.contains(centerIndex),
                  frames.count >= 3
            else {
                return 0.0
            }
            let fpsWindowLimit = max(3, Int((1.0 / max(frameStepSeconds, 1.0 / 240.0)).rounded()))
            let windowFrameCount = max(
                3,
                min(Int(max(3.0, dominantWindowFrames).rounded()), fpsWindowLimit)
            )
            let radiusFrames = max(1, windowFrameCount / 2)
            let centerTime = frames[centerIndex].time
            let radiusSeconds = min(1.0, max(frameStepSeconds, Double(radiusFrames) * frameStepSeconds))
            var weightedSupport = Float(0.0)
            var totalWeight = Float(0.0)
            for index in (centerIndex - radiusFrames)...(centerIndex + radiusFrames) {
                guard index > 0,
                      frames.indices.contains(index),
                      analysis.lensBandTopPathX.indices.contains(index),
                      analysis.lensBandTopPathX.indices.contains(index - 1),
                      analysis.lensBandTopPathY.indices.contains(index),
                      analysis.lensBandTopPathY.indices.contains(index - 1),
                      analysis.lensBandRidgePathX.indices.contains(index),
                      analysis.lensBandRidgePathX.indices.contains(index - 1),
                      analysis.lensBandRidgePathY.indices.contains(index),
                      analysis.lensBandRidgePathY.indices.contains(index - 1),
                      analysis.lensBandMidPathX.indices.contains(index),
                      analysis.lensBandMidPathX.indices.contains(index - 1),
                      analysis.lensBandMidPathY.indices.contains(index),
                      analysis.lensBandMidPathY.indices.contains(index - 1),
                      analysis.lensBandTopConfidence.indices.contains(index),
                      analysis.lensBandRidgeConfidence.indices.contains(index),
                      analysis.lensBandMidConfidence.indices.contains(index)
                else {
                    continue
                }
                let distance = abs(frames[index].time - centerTime)
                guard distance <= radiusSeconds + (frameStepSeconds * 0.5) else {
                    continue
                }
                let topDelta = vector_float2(
                    (analysis.lensBandTopPathX[index] - analysis.lensBandTopPathX[index - 1]) * outputScale.x,
                    (analysis.lensBandTopPathY[index] - analysis.lensBandTopPathY[index - 1]) * outputScale.y
                )
                let ridgeDelta = vector_float2(
                    (analysis.lensBandRidgePathX[index] - analysis.lensBandRidgePathX[index - 1]) * outputScale.x,
                    (analysis.lensBandRidgePathY[index] - analysis.lensBandRidgePathY[index - 1]) * outputScale.y
                )
                let midDelta = vector_float2(
                    (analysis.lensBandMidPathX[index] - analysis.lensBandMidPathX[index - 1]) * outputScale.x,
                    (analysis.lensBandMidPathY[index] - analysis.lensBandMidPathY[index - 1]) * outputScale.y
                )
                let farDelta = (topDelta * 0.35) + (ridgeDelta * 0.65)
                let topRidgeDisagreement = simd_length(topDelta - ridgeDelta)
                let midDisagreement = simd_length(midDelta - farDelta)
                let topRidgeCoherence = 1.0 - confidenceRamp(
                    topRidgeDisagreement,
                    start: farFieldRigidDeltaCoherenceTopRidgeStartPixels,
                    full: farFieldRigidDeltaCoherenceTopRidgeFullPixels
                )
                let midParallaxVeto = confidenceRamp(
                    midDisagreement,
                    start: farFieldRigidDeltaCoherenceMidStartPixels,
                    full: farFieldRigidDeltaCoherenceMidFullPixels
                )
                let rollDelta = analysis.farFieldRigidShakePathRoll.indices.contains(index)
                    && analysis.farFieldRigidShakePathRoll.indices.contains(index - 1)
                    ? abs(analysis.farFieldRigidShakePathRoll[index] - analysis.farFieldRigidShakePathRoll[index - 1])
                    : 0.0
                let motionEvidence = max(
                    confidenceRamp(
                        simd_length(farDelta),
                        start: farFieldRigidDeltaCoherenceMotionStartPixels,
                        full: farFieldRigidDeltaCoherenceMotionFullPixels
                    ),
                    confidenceRamp(
                        rollDelta,
                        start: lensShakeRollStartDegrees * 0.5,
                        full: lensShakeRollFullDegrees
                    )
                )
                let farConfidence = min(analysis.lensBandTopConfidence[index], analysis.lensBandRidgeConfidence[index])
                let confidenceGate = confidenceRamp(farConfidence, start: 0.08, full: 0.34)
                let midConfidenceGate = 0.65 + (0.35 * confidenceRamp(analysis.lensBandMidConfidence[index], start: 0.06, full: 0.30))
                let support = clamp(
                    topRidgeCoherence
                        * (1.0 - (midParallaxVeto * 0.45))
                        * motionEvidence
                        * confidenceGate
                        * midConfidenceGate
                        * confidenceRamp(dominantWindowSupport, start: 0.16, full: 0.66),
                    min: 0.0,
                    max: 1.0
                )
                let normalizedDistance = clamp(Float(distance / radiusSeconds), min: 0.0, max: 1.0)
                let weight = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)
                weightedSupport += support * weight
                totalWeight += weight
            }
            guard totalWeight > Float.ulpOfOne else {
                return 0.0
            }
            return clamp(weightedSupport / totalWeight, min: 0.0, max: 1.0)
        }

        if hasFarFieldRigidShakePaths {
            let rawRigidResidual = vector_float2(
                residual(kind: .farFieldRigidShakeX, values: analysis.farFieldRigidShakePathX) * outputScale.x,
                residual(kind: .farFieldRigidShakeY, values: analysis.farFieldRigidShakePathY) * outputScale.y
            )
            var rigidResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .farFieldRigidShakeX, values: analysis.farFieldRigidShakePathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .farFieldRigidShakeY, values: analysis.farFieldRigidShakePathY, scale: outputScale.y)
            )
            let rigidRollResidual = pulseSmoothedDegreeRollResidual(kind: .farFieldRigidShakeRoll, values: analysis.farFieldRigidShakePathRoll)
            let rawRigidMagnitude = simd_length(rawRigidResidual)
            let preparedRigidSupport = interpolatedValue(analysis.farFieldRigidShakeSupport, using: interpolation)
            let preparedRigidRollSupport = interpolatedValue(analysis.farFieldRigidShakeRollSupport, using: interpolation)
            let shapeConsistency = interpolatedValue(analysis.farFieldRigidShakeShapeConsistency, using: interpolation)
            let forwardBackwardConsistency = interpolatedValue(analysis.farFieldRigidShakeForwardBackwardConsistency, using: interpolation)
            let deltaCoherenceSupport = farFieldRigidDeltaCoherenceSupport()
            let deltaCoherenceAuthority = confidenceRamp(deltaCoherenceSupport, start: 0.08, full: 0.34)
            let effectivePreparedRigidSupport = max(preparedRigidSupport, deltaCoherenceAuthority)
            let effectivePreparedRigidRollSupport = max(preparedRigidRollSupport, deltaCoherenceAuthority)
            let effectiveShapeConsistency = max(shapeConsistency, deltaCoherenceAuthority)
            let effectiveForwardBackwardConsistency = max(forwardBackwardConsistency, deltaCoherenceAuthority * 0.92)
            if deltaCoherenceSupport >= lensShakeMinimumSupport {
                result.bandModelMask |= 4194304
            }
            let lowFrequencyRigidPriority = lowFrequencySupport
                * confidenceRamp(rawRigidMagnitude, start: 0.08, full: 0.66)
                * confidenceRamp(max(effectivePreparedRigidSupport, dominantWindowSupport), start: 0.10, full: 0.56)
                * confidenceRamp(effectiveShapeConsistency, start: 0.28, full: 0.70)
                * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.24, full: 0.68)
                * lowFrequencyTurnScale
                * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.62, full: 0.88) * 0.55))
            let lowFrequencyDominance = clamp(
                lowFrequencyRigidPriority
                    * confidenceRamp(Float(targetWindowSeconds), start: 0.42, full: farFieldLowFrequencyPriorityFullSeconds)
                    * confidenceRamp(rawRigidMagnitude, start: 0.12, full: 0.90),
                min: 0.0,
                max: 1.0
            )
            var meshRigidResidual = vector_float2(0.0, 0.0)
            var meshRigidWeight = Float(0.0)
            var meshRigidSupport = Float(0.0)
            var meshRigidMaxSupport = Float(0.0)
            var meshRigidSupportSum = Float(0.0)
            var meshRigidSupportedBinCount = 0
            var meshRigidMaxBinDelta = Float(0.0)
            var meshRigidOpposingBins = Float(0.0)
            var dominantMeshResidual = vector_float2(0.0, 0.0)
            var dominantMeshSupport = Float(0.0)
            var meshRigidSupportedResiduals: [(residual: vector_float2, support: Float)] = []
            if hasFarFieldMeshPaths {
                result.farFieldMeshAvailable = 1.0
                for bin in 0..<farFieldMeshBinCount {
                    let pathX = cache.pathValues(.farFieldMeshX(bin), analysis: analysis)
                    let pathY = cache.pathValues(.farFieldMeshY(bin), analysis: analysis)
                    let residualVector = vector_float2(
                        pulseSmoothedMeshPixelResidual(kind: .farFieldMeshX(bin), values: pathX, scale: outputScale.x),
                        pulseSmoothedMeshPixelResidual(kind: .farFieldMeshY(bin), values: pathY, scale: outputScale.y)
                    )
                    let preparedSupport = interpolatedMeshValue(analysis.farFieldMeshSupport, bin: bin, binCount: farFieldMeshBinCount)
                    let support = confidenceRamp(simd_length(residualVector), start: 0.08, full: 0.70)
                        * confidenceRamp(preparedSupport, start: 0.08, full: 0.38)
                        * qualitySupport
                        * turnScale
                    if bin == dominantCellIndex {
                        dominantMeshResidual = residualVector
                        dominantMeshSupport = support
                    }
                    let weight = max(0.0, support)
                    meshRigidResidual += residualVector * weight
                    meshRigidWeight += weight
                    if support > 0.01 {
                        meshRigidMaxSupport = max(meshRigidMaxSupport, support)
                        meshRigidSupportSum += support
                        meshRigidSupportedBinCount += 1
                        meshRigidSupportedResiduals.append((residual: residualVector, support: support))
                    }
                }
                if meshRigidSupportedBinCount > 0 {
                    let averageSupport = meshRigidSupportSum / Float(meshRigidSupportedBinCount)
                    let coverageSupport = confidenceRamp(Float(meshRigidSupportedBinCount), start: 4.0, full: 12.0)
                    meshRigidSupport = min(meshRigidMaxSupport, averageSupport * coverageSupport)
                }
                if meshRigidWeight > Float.ulpOfOne {
                    meshRigidResidual /= meshRigidWeight
                    for supported in meshRigidSupportedResiduals {
                        meshRigidMaxBinDelta = max(meshRigidMaxBinDelta, simd_length(supported.residual - meshRigidResidual))
                        if simd_dot(supported.residual, meshRigidResidual) < -0.01 {
                            meshRigidOpposingBins += 1.0
                        }
                    }
                    let lowFrequencyMeshSuppression = clamp(
                        lowFrequencyDominance * farFieldLowFrequencyMeshSuppressionScale,
                        min: 0.0,
                        max: 1.0
                    )
                    let meshOpposingFraction = meshRigidSupportedBinCount > 0
                        ? meshRigidOpposingBins / Float(meshRigidSupportedBinCount)
                        : 1.0
                    let meshCoherenceVeto = max(
                        confidenceRamp(
                            meshRigidMaxBinDelta,
                            start: farFieldCoherentMeshBlendDeltaStart,
                            full: farFieldCoherentMeshBlendDeltaFull
                        ),
                        confidenceRamp(
                            meshOpposingFraction,
                            start: farFieldCoherentMeshBlendOpposingStart,
                            full: farFieldCoherentMeshBlendOpposingFull
                        )
                    )
                    let meshBlendAuthority = clamp(
                        max(
                            1.0 - meshCoherenceVeto,
                            lowFrequencyDominance * (1.0 - (meshCoherenceVeto * 0.70))
                        ),
                        min: 0.0,
                        max: 1.0
                    )
                    let meshBlendCeiling = Float(0.45) * (1.0 - lowFrequencyMeshSuppression)
                    let rawMeshBlend = min(meshBlendCeiling, meshRigidSupport * 0.45 * (1.0 - lowFrequencyMeshSuppression))
                    let meshBlend = rawMeshBlend * meshBlendAuthority
                    let meshYBlend = min(meshBlend, meshRigidSupport * farFieldCoherentSlabMeshYBlendMaximum * (1.0 - lowFrequencyMeshSuppression))
                    result.farFieldMeshOffset = meshRigidResidual
                    result.farFieldMeshSupport = clamp(meshRigidSupport, min: 0.0, max: 1.0)
                    result.farFieldMeshBlend = meshBlend
                    result.farFieldMeshSupportedBins = Float(meshRigidSupportedBinCount)
                    result.farFieldMeshMaxBinDelta = meshRigidMaxBinDelta
                    result.farFieldMeshOpposingBins = meshRigidOpposingBins
                    rigidResidual.x += (meshRigidResidual.x - rigidResidual.x) * meshBlend
                    rigidResidual.y += (meshRigidResidual.y - rigidResidual.y) * meshYBlend
                    if meshBlend > 0.0 {
                        result.bandModelMask |= 256
                    }
                    if rawMeshBlend > 0.001 && meshBlendAuthority < 0.995 {
                        result.bandModelMask |= 16384
                    }
                }
            }
            let smoothedRigidMagnitude = simd_length(rigidResidual)
            let xQuiverScore = shortWindowQuiverScore(
                kind: .farFieldRigidShakeX,
                values: analysis.farFieldRigidShakePathX,
                rawResidualPixels: rawRigidResidual.x,
                limitedResidualPixels: rigidResidual.x,
                scale: outputScale.x
            )
            let yQuiverScore = shortWindowQuiverScore(
                kind: .farFieldRigidShakeY,
                values: analysis.farFieldRigidShakePathY,
                rawResidualPixels: rawRigidResidual.y,
                limitedResidualPixels: rigidResidual.y,
                scale: outputScale.y
            )
            if rawRigidMagnitude > smoothedRigidMagnitude,
               simd_dot(rawRigidResidual, rigidResidual) > 0.0 {
                let xBeforeLimiter = rigidResidual.x
                let rawReinforcement = confidenceRamp(
                    rawRigidMagnitude - smoothedRigidMagnitude,
                    start: 0.18,
                    full: 1.15
                ) * confidenceRamp(
                    max(dominantWindowSupport, meshRigidSupport),
                    start: 0.45,
                    full: 0.85
                ) * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.62, full: 0.88) * 0.55))
                let lowFrequencyRawReinforcement = max(
                    lowFrequencyRigidPriority * confidenceRamp(rawRigidMagnitude - smoothedRigidMagnitude, start: 0.04, full: 0.42),
                    lowFrequencyDominance * confidenceRamp(rawRigidMagnitude, start: 0.12, full: 0.90)
                )
                let rawBlendCeiling = farFieldRigidRawReinforcementMaximumBlend
                    + ((farFieldLowFrequencyRawReinforcementMaximumBlend - farFieldRigidRawReinforcementMaximumBlend) * lowFrequencyDominance)
                let rawBlend = min(
                    rawBlendCeiling,
                    max(rawReinforcement, lowFrequencyRawReinforcement) * rawBlendCeiling
                )
                let xQuiverVeto = confidenceRamp(xQuiverScore, start: 0.28, full: 0.68)
                let xQuiverSuppression = max(
                    xQuiverScore * (0.92 * (1.0 - (lowFrequencyDominance * 0.25))),
                    xQuiverVeto * 0.96
                )
                let yQuiverVeto = confidenceRamp(yQuiverScore, start: 0.24, full: 0.66)
                let yQuiverSuppression = max(
                    yQuiverScore * (0.88 * (1.0 - (lowFrequencyDominance * 0.18))),
                    yQuiverVeto * 0.94
                )
                let xBlend = rawBlend * (1.0 - xQuiverSuppression)
                let yBlend = rawBlend * (1.0 - yQuiverSuppression)
                rigidResidual.x += (rawRigidResidual.x - rigidResidual.x) * xBlend
                rigidResidual.y += (rawRigidResidual.y - rigidResidual.y) * yBlend
                result.farFieldRigidXQuiverScore = max(result.farFieldRigidXQuiverScore, xQuiverScore)
                result.farFieldRigidXBeforeLimiter = xBeforeLimiter + ((rawRigidResidual.x - xBeforeLimiter) * rawBlend)
                result.farFieldRigidXAfterLimiter = rigidResidual.x
            } else {
                result.farFieldRigidXBeforeLimiter = rigidResidual.x
                result.farFieldRigidXAfterLimiter = rigidResidual.x
            }
            let dominantCellAsInt = Int(dominantCellIndex)
            let dominantCellInUpperFarField = dominantCellAsInt >= 0
                && dominantCellAsInt < farFieldMeshBinCount
                && (dominantCellAsInt / farFieldMeshColumns) <= 1
            let shortWindowDominantMeshYPriority = (
                1.0 - confidenceRamp(
                    Float(targetWindowSeconds),
                    start: farFieldShortWindowRigidYBoostFullSeconds,
                    full: farFieldShortWindowRigidYBoostStartSeconds
                )
            )
                * (dominantCellInUpperFarField ? 1.0 : 0.0)
                * confidenceRamp(dominantWindowSupport, start: 0.52, full: 0.88)
                * confidenceRamp(dominantMeshSupport, start: 0.22, full: 0.62)
                * (dominantMeshResidual.y * rigidResidual.y > 0.0 ? 1.0 : 0.0)
                * confidenceRamp(abs(dominantMeshResidual.y), start: 0.10, full: 0.95)
                * qualitySupport
                * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.62, full: 0.88) * 0.50))
            let dominantMeshYBlend = min(
                farFieldShortWindowDominantMeshYBlendMaximum,
                farFieldShortWindowDominantMeshYBlendMaximum * clamp(shortWindowDominantMeshYPriority, min: 0.0, max: 1.0)
            )
            if dominantMeshYBlend > 0.0 {
                rigidResidual.y += (dominantMeshResidual.y - rigidResidual.y) * dominantMeshYBlend
                result.bandModelMask |= 1024
            }
            let shortWindowRigidYPriority = (
                1.0 - confidenceRamp(
                    Float(targetWindowSeconds),
                    start: farFieldShortWindowRigidYBoostFullSeconds,
                    full: farFieldShortWindowRigidYBoostStartSeconds
                )
            )
                * confidenceRamp(max(dominantWindowSupport, meshRigidSupport), start: 0.52, full: 0.88)
                * (1.0 - (confidenceRamp(meshRigidMaxBinDelta, start: 12.0, full: 32.0) * 0.65))
                * (1.0 - confidenceRamp(meshRigidSupportedBinCount > 0 ? meshRigidOpposingBins / Float(meshRigidSupportedBinCount) : 1.0, start: 0.08, full: 0.32))
                * (1.0 - (confidenceRamp(yQuiverScore, start: 0.18, full: 0.60) * 0.90))
                * confidenceRamp(abs(rigidResidual.y), start: 0.10, full: 0.95)
                * qualitySupport
                * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.62, full: 0.88) * 0.50))
            let shortWindowRigidYBoost = farFieldShortWindowRigidYBoostMaximum
                * clamp(shortWindowRigidYPriority, min: 0.0, max: 1.0)
            if shortWindowRigidYBoost > 0.0001 {
                rigidResidual.y *= 1.0 + shortWindowRigidYBoost
                result.bandModelMask |= 512
            }
            let meshOpposingFraction = meshRigidSupportedBinCount > 0
                ? meshRigidOpposingBins / Float(meshRigidSupportedBinCount)
                : 0.0
            let parallaxDampingEvidence = confidenceRamp(
                meshRigidMaxBinDelta,
                start: farFieldParallaxWarpDampingDeltaStart,
                full: farFieldParallaxWarpDampingDeltaFull
            )
                * confidenceRamp(Float(meshRigidSupportedBinCount), start: 8.0, full: 16.0)
                * max(
                    confidenceRamp(
                        meshOpposingFraction,
                        start: farFieldParallaxWarpDampingOpposingStart,
                        full: farFieldParallaxWarpDampingOpposingFull
	                    ),
	                    (1.0 - confidenceRamp(
	                        effectiveForwardBackwardConsistency,
	                        start: farFieldParallaxWarpDampingTwoWayStart,
	                        full: farFieldParallaxWarpDampingTwoWayFull
	                    )) * 0.85
                )
                * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.62, full: 0.88) * 0.35))
            let parallaxWarpDamping = farFieldParallaxWarpDampingMaximum
                * clamp(parallaxDampingEvidence, min: 0.0, max: 1.0)
            let parallaxWarpScale = 1.0 - parallaxWarpDamping
            if parallaxWarpDamping > 0.0 {
                rigidResidual *= parallaxWarpScale
                if parallaxWarpDamping >= 0.05 {
                    result.bandModelMask |= 2048
                }
            }
	            let coherentXShapeAuthority = confidenceRamp(
	                effectiveShapeConsistency,
	                start: farFieldCoherentSlabXShapeStart,
	                full: farFieldCoherentSlabXShapeFull
	            )
	            let coherentXTwoWayAuthority = confidenceRamp(
	                effectiveForwardBackwardConsistency,
	                start: farFieldCoherentSlabXTwoWayStart,
	                full: farFieldCoherentSlabXTwoWayFull
	            )
            let coherentXMeshVeto = confidenceRamp(
                meshRigidMaxBinDelta,
                start: farFieldCoherentSlabXMeshDeltaStart,
                full: farFieldCoherentSlabXMeshDeltaFull
            )
            let coherentXQuiverVeto = confidenceRamp(
                xQuiverScore,
                start: farFieldCoherentSlabXQuiverStart,
                full: farFieldCoherentSlabXQuiverFull
            )
	            let lowFrequencyXAuthority = lowFrequencyRigidPriority
	                * confidenceRamp(Float(targetWindowSeconds), start: 0.42, full: farFieldLowFrequencyPriorityFullSeconds)
	                * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.08, full: 0.42)
	                * (1.0 - (coherentXMeshVeto * 0.72))
	                * (1.0 - (coherentXQuiverVeto * 0.78))
            let coherentSlabXAuthority = clamp(
                max(
                    coherentXShapeAuthority * coherentXTwoWayAuthority * (1.0 - (max(coherentXMeshVeto, coherentXQuiverVeto) * 0.92)),
                    lowFrequencyXAuthority
                ),
                min: 0.0,
                max: 1.0
            )
            if coherentSlabXAuthority < 0.995 {
                rigidResidual.x *= coherentSlabXAuthority
                if abs(rigidResidual.x) >= 0.01 {
                    result.bandModelMask |= 8192
                }
            }
	            let coherentYShapeAuthority = confidenceRamp(
	                effectiveShapeConsistency,
	                start: farFieldCoherentSlabYShapeStart,
	                full: farFieldCoherentSlabYShapeFull
	            )
	            let coherentYTwoWayAuthority = confidenceRamp(
	                effectiveForwardBackwardConsistency,
	                start: farFieldCoherentSlabYTwoWayStart,
	                full: farFieldCoherentSlabYTwoWayFull
	            )
            let coherentYMeshVeto = confidenceRamp(
                meshRigidMaxBinDelta,
                start: farFieldCoherentSlabYMeshDeltaStart,
                full: farFieldCoherentSlabYMeshDeltaFull
            )
	            let lowFrequencyYAuthority = lowFrequencyRigidPriority
	                * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.08, full: 0.42)
	                * (1.0 - (coherentYMeshVeto * 0.55))
            let coherentSlabYAuthority = clamp(
                max(coherentYShapeAuthority * coherentYTwoWayAuthority, lowFrequencyYAuthority),
                min: 0.0,
                max: 1.0
            )
            if coherentSlabYAuthority < 0.995 {
                rigidResidual.y *= coherentSlabYAuthority
                if abs(rigidResidual.y) >= 0.01 {
                    result.bandModelMask |= 4096
                }
            }
            let lowFrequencyRigidSupport = lowFrequencyRigidPriority
                * confidenceRamp(simd_length(rigidResidual), start: 0.05, full: 0.48)
	            let rigidSupport = max(
	                confidenceRamp(simd_length(rigidResidual), start: 0.08, full: 0.70)
	                * confidenceRamp(effectivePreparedRigidSupport, start: 0.08, full: 0.36)
	                * confidenceRamp(effectiveShapeConsistency, start: 0.44, full: 0.82)
	                * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.36, full: 0.78)
	                * qualitySupport
	                * turnScale,
                max(
                    meshRigidSupport * confidenceRamp(simd_length(rigidResidual), start: 0.08, full: 0.70),
                    lowFrequencyRigidSupport
                )
	            )
	            let rigidRollSupport = confidenceRamp(abs(rigidRollResidual), start: lensShakeRollStartDegrees, full: lensShakeRollFullDegrees)
	                * confidenceRamp(effectivePreparedRigidRollSupport, start: 0.08, full: 0.36)
	                * confidenceRamp(effectiveShapeConsistency, start: 0.44, full: 0.82)
	                * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.36, full: 0.78)
	                * qualitySupport
	                * turnScale
            result.farFieldRigidOffset = rigidResidual
            result.farFieldRigidSupport = clamp(rigidSupport, min: 0.0, max: 1.0)
            result.farFieldRigidRollResidual = rigidRollResidual
            result.farFieldRigidRollSupport = clamp(rigidRollSupport, min: 0.0, max: 1.0)
	            result.farFieldRigidShapeConsistency = clamp(effectiveShapeConsistency, min: 0.0, max: 1.0)
	            result.farFieldRigidForwardBackwardConsistency = clamp(effectiveForwardBackwardConsistency, min: 0.0, max: 1.0)
	            let rigidOnlyEvidence = clamp(
	                confidenceRamp(result.farFieldRigidSupport, start: farFieldRigidOnlyGuardSupportStart, full: farFieldRigidOnlyGuardSupportFull)
	                    * confidenceRamp(effectiveShapeConsistency, start: farFieldRigidOnlyGuardShapeStart, full: farFieldRigidOnlyGuardShapeFull)
	                    * confidenceRamp(effectiveForwardBackwardConsistency, start: farFieldRigidOnlyGuardTwoWayStart, full: farFieldRigidOnlyGuardTwoWayFull)
	                    * (1.0 - (confidenceRamp(result.rollingShutterCandidate, start: 0.45, full: 0.75) * 0.65)),
                min: 0.0,
                max: 1.0
            )
            let rigidOnlyGuard = rigidOnlyEvidence >= 0.34
                ? max(rigidOnlyEvidence, confidenceRamp(rigidOnlyEvidence, start: 0.34, full: 0.58))
                : rigidOnlyEvidence
            result.farFieldRigidLocalWarpSuppressed = rigidOnlyGuard
            result.bandRawTopOffset = rawRigidResidual
            result.bandRawRidgeOffset = rawRigidResidual
            result.bandRawMidOffset = rawRigidResidual
            result.bandPulseDeltaTopOffset = rigidResidual - rawRigidResidual
            result.bandPulseDeltaRidgeOffset = rigidResidual - rawRigidResidual
            result.bandPulseDeltaMidOffset = rigidResidual - rawRigidResidual
            result.bandPulseWindowFrames = dominantWindowFrames
            result.bandWarpSupport = max(result.bandWarpSupport, result.farFieldRigidSupport)
            let rigidBranchSupport = max(result.farFieldRigidSupport, result.farFieldRigidRollSupport)
            if rigidBranchSupport >= lensShakeMinimumSupport {
                let rigidOffset = vector_float2(
                    clamp(-rigidResidual.x, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection),
                    clamp(-rigidResidual.y, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
                )
                let globalYSupport = confidenceRamp(
                    result.farFieldRigidSupport,
                    start: lensShakeMinimumSupport,
                    full: 0.62
                )
                let globalYOffset = clamp(
                    rigidOffset.y * globalYSupport,
                    min: -lensShakeRollingGlobalYMaximumCorrection,
                    max: lensShakeRollingGlobalYMaximumCorrection
                )
                let rigidRollCorrection = clamp(
                    -rigidRollResidual * rigidRollSupport,
                    min: -lensShakeRotationMaximumCorrectionDegrees,
                    max: lensShakeRotationMaximumCorrectionDegrees
                )
                result.pixelOffset.y = globalYOffset
                result.farFieldRigidGlobalYOffset = globalYOffset
                result.farFieldRigidGlobalRollDegrees = rigidRollCorrection
                result.bandTopOffset = vector_float2(rigidOffset.x, 0.0)
                result.bandRidgeOffset = vector_float2(rigidOffset.x, 0.0)
                result.bandMidOffset = vector_float2(rigidOffset.x, 0.0)
                result.bandModelMask |= 128
                result.bandModelMask |= 1048576
                result.farFieldRigidApplied = result.farFieldRigidSupport >= lensShakeMinimumSupport ? 1.0 : 0.0
                if rigidRollSupport >= lensShakeMinimumSupport, abs(rigidRollCorrection) >= 0.00001 {
                    result.rotationDegrees = rigidRollCorrection
                    result.farFieldRigidRollApplied = 1.0
                    result.axisMask |= 4
                    maximumAppliedSupport = max(maximumAppliedSupport, rigidRollSupport)
                }
                if abs(rigidOffset.x) >= 0.02 {
                    result.bandWarpApplied = 1.0
                }
                let appliedRigidSupport = max(result.farFieldRigidSupport, result.farFieldRigidRollSupport)
                if result.farFieldRigidApplied > 0.5 || result.farFieldRigidRollApplied > 0.5 || rigidBranchSupport >= lensShakeMinimumSupport {
                    result.support = max(maximumAppliedSupport, appliedRigidSupport)
                    result.reasonCode = 7
                    return result
                }
            }
        }
        var sourceLocalGlobalResidual = vector_float2(0.0, 0.0)
        var sourceLocalGlobalSupport = Float(0.0)
        if hasLensBandPaths && hasFarFieldRigidShakePaths {
            let rigidOnlyRidgeWarpScale = Float(0.0)
            let sourceRidgeResidualY = pulseSmoothedPixelResidual(kind: .sourceLensShakeRidgeY, values: analysis.sourceLensShakeRidgePathY, scale: outputScale.y)
            let sourceRidgeLineResidualY = pulseSmoothedPixelResidual(kind: .sourceLensShakeRidgeLineY, values: analysis.sourceLensShakeRidgeLinePathY, scale: outputScale.y)
            let sourceRidgeLineRawResidualY = residual(kind: .sourceLensShakeRidgeLineY, values: analysis.sourceLensShakeRidgeLinePathY) * outputScale.y

            let sourceRidgePreparedSupport = interpolatedValue(analysis.sourceLensShakeRidgeSupport, using: interpolation)
            let sourceRidgeCandidateSupport = confidenceRamp(abs(sourceRidgeResidualY), start: 0.18, full: 1.25)
                * confidenceRamp(sourceRidgePreparedSupport, start: 0.08, full: 0.45)
                * qualitySupport
                * turnScale
            let sourceRidgeSupport = sourceRidgeCandidateSupport
                * rigidOnlyRidgeWarpScale
            let sourceRidgeLinePreparedSupport = interpolatedValue(analysis.sourceLensShakeRidgeLineSupport, using: interpolation)
            let sourceRidgeLineRawBlend = confidenceRamp(
                    abs(sourceRidgeLineRawResidualY - sourceRidgeLineResidualY),
                    start: 0.55,
                    full: 4.0
                )
                * confidenceRamp(sourceRidgeLinePreparedSupport, start: 0.10, full: 0.42)
                * qualitySupport
                * turnScale
            let sourceRidgeLineCorrectionResidualY = sourceRidgeLineResidualY
                + ((sourceRidgeLineRawResidualY - sourceRidgeLineResidualY) * sourceRidgeLineRawBlend)
            result.sourceRidgeLineResidual = vector_float2(0.0, sourceRidgeLineCorrectionResidualY)
            let sourceRidgeLineCandidateSupport = confidenceRamp(abs(sourceRidgeLineCorrectionResidualY), start: 0.14, full: 1.10)
                * confidenceRamp(sourceRidgeLinePreparedSupport, start: 0.08, full: 0.45)
                * qualitySupport
                * turnScale
            let sourceRidgeLineEnvelopeY = max(
                abs(sourceRidgeLineCorrectionResidualY),
                localPeakPixelResidual(
                    kind: .sourceLensShakeRidgeLineY,
                    values: analysis.sourceLensShakeRidgeLinePathY,
                    scale: outputScale.y,
                    radiusSeconds: min(
                        sourceLensRidgeLineGlobalEnvelopeSeconds,
                        max(frameStepSeconds * 3.0, Double(dominantWindowSeconds) * 0.55)
                    )
                )
            )
            let sourceRidgeLineDirectGlobalSupport = confidenceRamp(
                    sourceRidgeLineEnvelopeY,
                    start: sourceLensRidgeLineGlobalEnvelopeStart,
                    full: sourceLensRidgeLineGlobalEnvelopeFull
                )
                * qualitySupport
                * turnScale
                * confidenceRamp(result.rollingShutterCandidate, start: 0.45, full: 0.75)
            let sourceRidgeLineGlobalSupport = max(
                sourceRidgeLineCandidateSupport,
                sourceRidgeLineDirectGlobalSupport * 0.72
            )
                * confidenceRamp(
                    sourceRidgeLineEnvelopeY,
                    start: sourceLensRidgeLineGlobalResidualStart,
                    full: sourceLensRidgeLineGlobalResidualFull
                )
            if sourceRidgeLineGlobalSupport >= lensShakeMinimumSupport {
                result.sourceRidgeLineOffset = vector_float2(
                    0.0,
                    clamp(
                        -sourceRidgeLineCorrectionResidualY
                            * sourceLensRidgeLineGlobalPixelScale
                            * sourceRidgeLineGlobalSupport,
                        min: -sourceLensRidgeLineGlobalPixelMaximumCorrection,
                        max: sourceLensRidgeLineGlobalPixelMaximumCorrection
                    )
                )
                result.sourceRidgeLineSupport = clamp(sourceRidgeLineGlobalSupport, min: 0.0, max: 1.0)
                result.sourceRidgeLineApplied = 1.0
                result.bandModelMask |= 64
            }
            let sourceRidgeLineSupport = sourceRidgeLineCandidateSupport
                * rigidOnlyRidgeWarpScale
            if sourceRidgeCandidateSupport >= lensShakeMinimumSupport
                || sourceRidgeLineCandidateSupport >= lensShakeMinimumSupport {
                result.bandModelMask |= 32768
            }

            var localResiduals = Array(repeating: vector_float2(0.0, 0.0), count: sourceLensShakeLocalBinCount)
            var localSupports = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
            var supportedLocalResiduals: [vector_float2] = []
            var weightedLocalResidual = vector_float2(0.0, 0.0)
            var localResidualWeight = Float(0.0)
            var localMaxSupport = Float(0.0)
            var localSupportSum = Float(0.0)
            var localSupportedBinCount = 0
            for bin in 0..<sourceLensShakeLocalBinCount {
                let pathX = cache.pathValues(.sourceLensShakeLocalX(bin), analysis: analysis)
                let pathY = cache.pathValues(.sourceLensShakeLocalY(bin), analysis: analysis)
                let supportPath = cache.pathValues(.sourceLensShakeLocalSupport(bin), analysis: analysis)
                let residualVector = vector_float2(
                    pulseSmoothedPixelResidual(kind: .sourceLensShakeLocalX(bin), values: pathX, scale: outputScale.x),
                    pulseSmoothedPixelResidual(kind: .sourceLensShakeLocalY(bin), values: pathY, scale: outputScale.y)
                )
                let preparedSupport = interpolatedValue(supportPath, using: interpolation)
                let row = bin / sourceLensShakeLocalColumnCount
                let farFieldRowWeight: Float
                switch row {
                case 0:
                    farFieldRowWeight = 1.0
                case 1:
                    farFieldRowWeight = 0.82
                default:
                    farFieldRowWeight = 0.34
                }
                let support = confidenceRamp(simd_length(residualVector), start: 0.08, full: 0.82)
                    * confidenceRamp(preparedSupport, start: 0.08, full: 0.38)
                    * qualitySupport
                    * turnScale
                    * farFieldRowWeight
                localResiduals[bin] = residualVector
                localSupports[bin] = support
                if support > 0.01 {
                    weightedLocalResidual += residualVector * support
                    localResidualWeight += support
                    localMaxSupport = max(localMaxSupport, support)
                    localSupportSum += support
                    localSupportedBinCount += 1
                    supportedLocalResiduals.append(residualVector)
                }
            }
            if localResidualWeight > Float.ulpOfOne {
                let averageLocalResidual = weightedLocalResidual / localResidualWeight
                let averageLocalSupport = localSupportSum / Float(max(1, localSupportedBinCount))
                let coverageSupport = confidenceRamp(Float(localSupportedBinCount), start: 3.0, full: 10.0)
                let maxLocalDelta = supportedLocalResiduals.reduce(Float(0.0)) { partial, residual in
                    max(partial, simd_length(residual - averageLocalResidual))
                }
                let coherentSupport = (1.0 - (confidenceRamp(maxLocalDelta, start: 3.8, full: 14.0) * 0.72))
                    * coverageSupport
                sourceLocalGlobalResidual = averageLocalResidual
                sourceLocalGlobalSupport = clamp(min(localMaxSupport, averageLocalSupport * coverageSupport) * coherentSupport, min: 0.0, max: 1.0)
                if sourceLocalGlobalSupport >= lensShakeMinimumSupport {
                    result.bandRollingShutterScore = max(result.bandRollingShutterScore, sourceLocalGlobalSupport)
                    result.bandModelMask |= 262144
                }
            }

            if sourceRidgeSupport >= lensShakeMinimumSupport {
                result.sourceRidgeOffset = vector_float2(
                    0.0,
                    clamp(
                        -sourceRidgeResidualY,
                        min: -sourceLensRidgePixelMaximumCorrection,
                        max: sourceLensRidgePixelMaximumCorrection
                    )
                )
                result.sourceRidgeSupport = clamp(sourceRidgeSupport, min: 0.0, max: 1.0)
                result.sourceRidgeApplied = 1.0
                result.bandModelMask |= 16
            }
            if sourceRidgeLineSupport >= lensShakeMinimumSupport {
                let lineOffset = vector_float2(
                    0.0,
                    clamp(
                        -sourceRidgeLineCorrectionResidualY,
                        min: -sourceLensRidgePixelMaximumCorrection,
                        max: sourceLensRidgePixelMaximumCorrection
                    )
                )
                result.sourceRidgeLineOffset = lineOffset
                result.sourceRidgeLineSupport = clamp(sourceRidgeLineSupport, min: 0.0, max: 1.0)
                result.sourceRidgeLineApplied = 1.0
                let lineBlend = min(0.50, result.sourceRidgeLineSupport)
                let baseRidgeY = result.sourceRidgeApplied > 0.5 ? result.sourceRidgeOffset.y : lineOffset.y
                result.sourceRidgeOffset = vector_float2(
                    0.0,
                    clamp(
                        baseRidgeY + ((lineOffset.y - baseRidgeY) * lineBlend),
                        min: -sourceLensRidgePixelMaximumCorrection,
                        max: sourceLensRidgePixelMaximumCorrection
                    )
                )
                result.sourceRidgeSupport = max(result.sourceRidgeSupport, result.sourceRidgeLineSupport)
                result.sourceRidgeApplied = 1.0
                result.bandModelMask |= 64
            }
        }
        if hasLensBandPaths && !hasFarFieldRigidShakePaths {
            let rawTopResidual = vector_float2(
                residual(kind: .lensBandTopX, values: analysis.lensBandTopPathX) * outputScale.x,
                residual(kind: .lensBandTopY, values: analysis.lensBandTopPathY) * outputScale.y
            )
            let topResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandTopX, values: analysis.lensBandTopPathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandTopY, values: analysis.lensBandTopPathY, scale: outputScale.y)
            )
            let rawRidgeResidual = vector_float2(
                residual(kind: .lensBandRidgeX, values: analysis.lensBandRidgePathX) * outputScale.x,
                residual(kind: .lensBandRidgeY, values: analysis.lensBandRidgePathY) * outputScale.y
            )
            let ridgeResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandRidgeX, values: analysis.lensBandRidgePathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandRidgeY, values: analysis.lensBandRidgePathY, scale: outputScale.y)
            )
            let rawMidResidual = vector_float2(
                residual(kind: .lensBandMidX, values: analysis.lensBandMidPathX) * outputScale.x,
                residual(kind: .lensBandMidY, values: analysis.lensBandMidPathY) * outputScale.y
            )
            let midResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandMidX, values: analysis.lensBandMidPathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandMidY, values: analysis.lensBandMidPathY, scale: outputScale.y)
            )
            result.bandPulseWindowFrames = dominantWindowFrames
            result.bandRawTopOffset = rawTopResidual
            result.bandRawRidgeOffset = rawRidgeResidual
            result.bandRawMidOffset = rawMidResidual
            result.bandPulseDeltaTopOffset = topResidual - rawTopResidual
            result.bandPulseDeltaRidgeOffset = ridgeResidual - rawRidgeResidual
            result.bandPulseDeltaMidOffset = midResidual - rawMidResidual
            let topColumnResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandTopColumnX, values: analysis.lensBandTopColumnPathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandTopColumnY, values: analysis.lensBandTopColumnPathY, scale: outputScale.y)
            )
            let topRowResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandTopRowPhaseX, values: analysis.lensBandTopRowPhasePathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandTopRowPhaseY, values: analysis.lensBandTopRowPhasePathY, scale: outputScale.y)
            )
            let topLocalRoll = pulseSmoothedRollResidual(kind: .lensBandTopLocalRoll, values: analysis.lensBandTopLocalRollPath)
            let ridgeColumnResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandRidgeColumnX, values: analysis.lensBandRidgeColumnPathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandRidgeColumnY, values: analysis.lensBandRidgeColumnPathY, scale: outputScale.y)
            )
            let ridgeRowResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandRidgeRowPhaseX, values: analysis.lensBandRidgeRowPhasePathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandRidgeRowPhaseY, values: analysis.lensBandRidgeRowPhasePathY, scale: outputScale.y)
            )
            let ridgeLocalRoll = pulseSmoothedRollResidual(kind: .lensBandRidgeLocalRoll, values: analysis.lensBandRidgeLocalRollPath)
            let midColumnResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandMidColumnX, values: analysis.lensBandMidColumnPathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandMidColumnY, values: analysis.lensBandMidColumnPathY, scale: outputScale.y)
            )
            let midRowResidual = vector_float2(
                pulseSmoothedPixelResidual(kind: .lensBandMidRowPhaseX, values: analysis.lensBandMidRowPhasePathX, scale: outputScale.x),
                pulseSmoothedPixelResidual(kind: .lensBandMidRowPhaseY, values: analysis.lensBandMidRowPhasePathY, scale: outputScale.y)
            )
            let midLocalRoll = pulseSmoothedRollResidual(kind: .lensBandMidLocalRoll, values: analysis.lensBandMidLocalRollPath)
            let sourceRidgeResidualY = pulseSmoothedPixelResidual(kind: .sourceLensShakeRidgeY, values: analysis.sourceLensShakeRidgePathY, scale: outputScale.y)
            let sourceRidgeLineResidualY = pulseSmoothedPixelResidual(kind: .sourceLensShakeRidgeLineY, values: analysis.sourceLensShakeRidgeLinePathY, scale: outputScale.y)
            let sourceRidgeLineRawResidualY = residual(kind: .sourceLensShakeRidgeLineY, values: analysis.sourceLensShakeRidgeLinePathY) * outputScale.y
            let bandMagnitude = max(
                simd_length(topResidual),
                max(simd_length(ridgeResidual), simd_length(midResidual))
            )
            let bandDisagreement = max(
                simd_length(topResidual - ridgeResidual),
                max(
                    simd_length(topResidual - midResidual),
                    simd_length(ridgeResidual - midResidual)
                )
            )
            let columnMagnitude = max(
                simd_length(topColumnResidual),
                max(simd_length(ridgeColumnResidual), simd_length(midColumnResidual))
            )
            let rowMagnitude = max(
                simd_length(topRowResidual),
                max(simd_length(ridgeRowResidual), simd_length(midRowResidual))
            )
            let columnDisagreement = max(
                simd_length(topColumnResidual - ridgeColumnResidual),
                max(
                    simd_length(topColumnResidual - midColumnResidual),
                    simd_length(ridgeColumnResidual - midColumnResidual)
                )
            )
            let localWarpRigidLock = confidenceRamp(result.farFieldRigidLocalWarpSuppressed, start: 0.18, full: 0.42)
            let rigidOnlyLocalWarpScale = powf(1.0 - localWarpRigidLock, 6.0)
            let rigidOnlyGlobalRollScale = 1.0 - (localWarpRigidLock * 0.35)
            let rigidOnlyRidgeWarpScaleForLocal = powf(1.0 - localWarpRigidLock, 3.0)
            func bandSupport(residual: vector_float2, confidenceValues: [Float]) -> Float {
                let confidence = interpolatedValue(confidenceValues, using: interpolation)
                return confidenceRamp(simd_length(residual), start: 0.08, full: 0.65)
                    * confidenceRamp(confidence, start: 0.08, full: 0.36)
                    * qualitySupport
                    * turnScale
                    * rigidOnlyLocalWarpScale
            }
            let topSupport = bandSupport(residual: topResidual, confidenceValues: analysis.lensBandTopConfidence)
            let ridgeSupport = bandSupport(residual: ridgeResidual, confidenceValues: analysis.lensBandRidgeConfidence)
            let midSupport = bandSupport(residual: midResidual, confidenceValues: analysis.lensBandMidConfidence)
            let topColumnSupport = bandSupport(residual: topColumnResidual, confidenceValues: analysis.lensBandTopConfidence)
            let ridgeColumnSupport = bandSupport(residual: ridgeColumnResidual, confidenceValues: analysis.lensBandRidgeConfidence)
            let midColumnSupport = bandSupport(residual: midColumnResidual, confidenceValues: analysis.lensBandMidConfidence)
            let topRowSupport = bandSupport(residual: topRowResidual, confidenceValues: analysis.lensBandTopConfidence)
            let ridgeRowSupport = bandSupport(residual: ridgeRowResidual, confidenceValues: analysis.lensBandRidgeConfidence)
            let midRowSupport = bandSupport(residual: midRowResidual, confidenceValues: analysis.lensBandMidConfidence)
            func localRollBandSupport(_ value: Float, confidenceValues: [Float]) -> Float {
                let confidence = interpolatedValue(confidenceValues, using: interpolation)
                let evidence = confidenceRamp(abs(value), start: lensShakeRollStartDegrees * 0.25, full: lensShakeRollFullDegrees * 0.75)
                maximumEvidence = max(maximumEvidence, evidence)
                return evidence
                    * confidenceRamp(confidence, start: 0.08, full: 0.36)
                    * qualitySupport
                    * turnScale
                    * rigidOnlyGlobalRollScale
            }
            let topLocalRollSupport = localRollBandSupport(topLocalRoll, confidenceValues: analysis.lensBandTopConfidence)
            let ridgeLocalRollSupport = localRollBandSupport(ridgeLocalRoll, confidenceValues: analysis.lensBandRidgeConfidence)
            let midLocalRollSupport = localRollBandSupport(midLocalRoll, confidenceValues: analysis.lensBandMidConfidence)
            let localRollSupport = max(topLocalRollSupport, max(ridgeLocalRollSupport, midLocalRollSupport))
            let sourceRidgePreparedSupport = interpolatedValue(analysis.sourceLensShakeRidgeSupport, using: interpolation)
            let sourceRidgeSupport = confidenceRamp(abs(sourceRidgeResidualY), start: 0.18, full: 1.25)
                * confidenceRamp(sourceRidgePreparedSupport, start: 0.08, full: 0.45)
                * qualitySupport
                * turnScale
                * rigidOnlyRidgeWarpScaleForLocal
            let sourceRidgeLinePreparedSupport = interpolatedValue(analysis.sourceLensShakeRidgeLineSupport, using: interpolation)
            let sourceRidgeLineRawBlend = confidenceRamp(
                    abs(sourceRidgeLineRawResidualY - sourceRidgeLineResidualY),
                    start: 0.55,
                    full: 4.0
                )
                * confidenceRamp(sourceRidgeLinePreparedSupport, start: 0.10, full: 0.42)
                * qualitySupport
                * turnScale
                * rigidOnlyRidgeWarpScaleForLocal
            let sourceRidgeLineCorrectionResidualY = sourceRidgeLineResidualY
                + ((sourceRidgeLineRawResidualY - sourceRidgeLineResidualY) * sourceRidgeLineRawBlend)
            result.sourceRidgeLineResidual = vector_float2(0.0, sourceRidgeLineCorrectionResidualY)
            let sourceRidgeLineDirectSupport = confidenceRamp(abs(sourceRidgeLineCorrectionResidualY), start: 0.14, full: 1.10)
                * confidenceRamp(sourceRidgeLinePreparedSupport, start: 0.08, full: 0.45)
                * qualitySupport
                * turnScale
                * rigidOnlyRidgeWarpScaleForLocal
            var localResiduals = Array(repeating: vector_float2(0.0, 0.0), count: sourceLensShakeLocalBinCount)
            var localSupports = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
            var localPreparedSupports = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
            for bin in 0..<sourceLensShakeLocalBinCount {
                let pathX = cache.pathValues(.sourceLensShakeLocalX(bin), analysis: analysis)
                let pathY = cache.pathValues(.sourceLensShakeLocalY(bin), analysis: analysis)
                let supportPath = cache.pathValues(.sourceLensShakeLocalSupport(bin), analysis: analysis)
                let residualVector = vector_float2(
                    pulseSmoothedPixelResidual(kind: .sourceLensShakeLocalX(bin), values: pathX, scale: outputScale.x),
                    pulseSmoothedPixelResidual(kind: .sourceLensShakeLocalY(bin), values: pathY, scale: outputScale.y)
                )
                let preparedSupport = interpolatedValue(supportPath, using: interpolation)
                let support = confidenceRamp(simd_length(residualVector), start: 0.10, full: 0.95)
                    * confidenceRamp(preparedSupport, start: 0.08, full: 0.38)
                    * qualitySupport
                    * turnScale
                    * rigidOnlyLocalWarpScale
                localResiduals[bin] = residualVector
                localSupports[bin] = support
                localPreparedSupports[bin] = preparedSupport
            }
            let localBinSupport = localSupports.max() ?? 0.0
            let localBinMagnitude = localResiduals.map { simd_length($0) }.max() ?? 0.0
            _ = localPreparedSupports
            let sourceRidgeLineBandEvidenceSupport = max(ridgeSupport, max(ridgeColumnSupport, ridgeRowSupport))
            let sourceRidgeLineBandSupport = confidenceRamp(abs(sourceRidgeLineCorrectionResidualY), start: 0.14, full: 1.10)
                * confidenceRamp(sourceRidgeLineBandEvidenceSupport, start: 0.08, full: 0.36)
                * qualitySupport
                * turnScale
                * rigidOnlyRidgeWarpScaleForLocal
            let sourceRidgeLineSupport = max(sourceRidgeLineDirectSupport, sourceRidgeLineBandSupport)
            let sourceRidgeLineBandSupported: Float = sourceRidgeLineBandSupport > sourceRidgeLineDirectSupport
                && sourceRidgeLineBandSupport >= lensShakeMinimumSupport ? 1.0 : 0.0
            let bandSupport = max(
                max(max(topSupport, max(ridgeSupport, midSupport)), max(topRowSupport, max(ridgeRowSupport, midRowSupport))),
                max(max(topColumnSupport, max(ridgeColumnSupport, midColumnSupport)), max(localRollSupport, max(max(sourceRidgeSupport, sourceRidgeLineSupport), localBinSupport)))
            )
            let bandDisagreementSupport = confidenceRamp(bandDisagreement, start: 0.20, full: 1.50)
                * confidenceRamp(max(topSupport, max(ridgeSupport, midSupport)), start: 0.04, full: 0.20)
            let columnSupport = max(topColumnSupport, max(ridgeColumnSupport, midColumnSupport))
            let columnPhaseSupport = max(
                confidenceRamp(columnMagnitude, start: 0.12, full: 1.10),
                confidenceRamp(columnDisagreement, start: 0.16, full: 1.35)
            ) * confidenceRamp(columnSupport, start: 0.04, full: 0.20)
            let rowPhaseSupport = confidenceRamp(rowMagnitude, start: 0.12, full: 1.10)
                * confidenceRamp(max(topRowSupport, max(ridgeRowSupport, midRowSupport)), start: 0.04, full: 0.20)
            let localWarpSupport = max(
                bandSupport,
                max(max(bandDisagreementSupport, columnPhaseSupport), max(max(rowPhaseSupport, localRollSupport), max(max(sourceRidgeSupport, sourceRidgeLineSupport), localBinSupport)))
            )
            result.bandRollingShutterScore = max(
                result.rollingShutterCandidate,
                localWarpSupport
            )
            _ = bandMagnitude
            func supportedOffset(_ residual: vector_float2, support: Float) -> vector_float2 {
                guard support >= lensShakeMinimumSupport else {
                    return vector_float2(0.0, 0.0)
                }
                let supportRatio = localWarpSupport > 0.0 ? clamp(support / localWarpSupport, min: 0.0, max: 1.0) : 0.0
                return vector_float2(
                    clamp(-residual.x, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection),
                    clamp(-residual.y, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
                ) * supportRatio
            }
            func supportedColumnOffset(_ residual: vector_float2, support: Float) -> vector_float2 {
                guard support >= lensShakeMinimumSupport else {
                    return vector_float2(0.0, 0.0)
                }
                let supportRatio = localWarpSupport > 0.0 ? clamp(support / localWarpSupport, min: 0.0, max: 1.0) : 0.0
                return vector_float2(
                    clamp(-0.5 * residual.x, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection),
                    clamp(-0.5 * residual.y, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
                ) * supportRatio
            }
            func supportedRowPhaseOffset(_ current: vector_float2, _ neighbor: vector_float2, support: Float) -> vector_float2 {
                guard support >= lensShakeMinimumSupport else {
                    return vector_float2(0.0, 0.0)
                }
                let supportRatio = localWarpSupport > 0.0 ? clamp(support / localWarpSupport, min: 0.0, max: 1.0) : 0.0
                let residualDelta = current - neighbor
                return vector_float2(
                    clamp(-0.5 * residualDelta.x, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection),
                    clamp(-0.5 * residualDelta.y, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
                ) * supportRatio
            }
            func supportedLocalRoll(_ value: Float, support: Float) -> Float {
                guard support >= lensShakeMinimumSupport else {
                    return 0.0
                }
                let supportRatio = localWarpSupport > 0.0 ? clamp(support / localWarpSupport, min: 0.0, max: 1.0) : 0.0
                return clamp(
                    -value,
                    min: -lensShakeRotationMaximumCorrectionDegrees * .pi / 180.0,
                    max: lensShakeRotationMaximumCorrectionDegrees * .pi / 180.0
                ) * supportRatio
            }
            func supportedLocalBinOffset(_ residual: vector_float2, support: Float) -> vector_float2 {
                guard support >= lensShakeMinimumSupport else {
                    return vector_float2(0.0, 0.0)
                }
                let supportRatio = localWarpSupport > 0.0 ? clamp(support / localWarpSupport, min: 0.0, max: 1.0) : 0.0
                return vector_float2(
                    clamp(-residual.x, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection),
                    clamp(-residual.y, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
                ) * supportRatio
            }
            if localWarpSupport >= lensShakeMinimumSupport {
                result.bandTopOffset = supportedOffset(topResidual, support: topSupport)
                result.bandRidgeOffset = supportedOffset(ridgeResidual, support: ridgeSupport)
                result.bandMidOffset = supportedOffset(midResidual, support: midSupport)
                result.bandTopColumnOffset = supportedColumnOffset(topColumnResidual, support: topColumnSupport)
                result.bandRidgeColumnOffset = supportedColumnOffset(ridgeColumnResidual, support: ridgeColumnSupport)
                result.bandMidColumnOffset = supportedColumnOffset(midColumnResidual, support: midColumnSupport)
                result.bandTopRowPhaseOffset = supportedRowPhaseOffset(topRowResidual, vector_float2(0.0, 0.0), support: topRowSupport)
                result.bandRidgeRowPhaseOffset = supportedRowPhaseOffset(ridgeRowResidual, vector_float2(0.0, 0.0), support: ridgeRowSupport)
                result.bandMidRowPhaseOffset = supportedRowPhaseOffset(midRowResidual, vector_float2(0.0, 0.0), support: midRowSupport)
                result.bandTopLocalRoll = supportedLocalRoll(topLocalRoll, support: topLocalRollSupport)
                result.bandRidgeLocalRoll = supportedLocalRoll(ridgeLocalRoll, support: ridgeLocalRollSupport)
                result.bandMidLocalRoll = supportedLocalRoll(midLocalRoll, support: midLocalRollSupport)
                let commonBandYOffset = (result.bandTopOffset.y + result.bandRidgeOffset.y + result.bandMidOffset.y) / 3.0
                let globalBandYSupport = confidenceRamp(
                    localWarpSupport,
                    start: lensShakeMinimumSupport,
                    full: 0.62
                )
                let globalBandYOffset = clamp(
                    commonBandYOffset * globalBandYSupport,
                    min: -lensShakeRollingGlobalYMaximumCorrection,
                    max: lensShakeRollingGlobalYMaximumCorrection
                )
                if abs(globalBandYOffset) >= 0.001 {
                    result.pixelOffset.y += globalBandYOffset
                    result.bandTopOffset.y -= globalBandYOffset
                    result.bandRidgeOffset.y -= globalBandYOffset
                    result.bandMidOffset.y -= globalBandYOffset
                    result.bandModelMask |= 1048576
                }
                let commonLocalRoll = (result.bandTopLocalRoll + result.bandRidgeLocalRoll + result.bandMidLocalRoll) / 3.0
                let globalLocalRollSupport = confidenceRamp(
                    localRollSupport,
                    start: lensShakeMinimumSupport,
                    full: 0.62
                )
                let globalLocalRollDegrees = clamp(
                    commonLocalRoll * 180.0 / .pi * globalLocalRollSupport,
                    min: -lensShakeRotationMaximumCorrectionDegrees,
                    max: lensShakeRotationMaximumCorrectionDegrees
                )
                if abs(globalLocalRollDegrees) >= 0.00001 {
                    result.rotationDegrees += globalLocalRollDegrees
                    let globalLocalRollRadians = globalLocalRollDegrees * .pi / 180.0
                    result.bandTopLocalRoll -= globalLocalRollRadians
                    result.bandRidgeLocalRoll -= globalLocalRollRadians
                    result.bandMidLocalRoll -= globalLocalRollRadians
                    result.bandModelMask |= 2097152
                }
                if sourceRidgeSupport >= lensShakeMinimumSupport {
                    result.sourceRidgeOffset = vector_float2(
                        0.0,
                        clamp(
                            -sourceRidgeResidualY,
                            min: -sourceLensRidgePixelMaximumCorrection,
                            max: sourceLensRidgePixelMaximumCorrection
                        )
                    )
                    result.sourceRidgeSupport = clamp(sourceRidgeSupport, min: 0.0, max: 1.0)
                    result.sourceRidgeApplied = 1.0
                }
                if sourceRidgeLineSupport >= lensShakeMinimumSupport {
                    let lineOffset = vector_float2(
                        0.0,
                        clamp(
                            -sourceRidgeLineCorrectionResidualY,
                            min: -sourceLensRidgePixelMaximumCorrection,
                            max: sourceLensRidgePixelMaximumCorrection
                        )
                    )
                    result.sourceRidgeLineOffset = lineOffset
                    result.sourceRidgeLineSupport = clamp(sourceRidgeLineSupport, min: 0.0, max: 1.0)
                    result.sourceRidgeLineBandSupported = sourceRidgeLineBandSupported
                    result.sourceRidgeLineApplied = 1.0
                    let lineBlend = min(0.50, result.sourceRidgeLineSupport)
                    let baseRidgeY = result.sourceRidgeApplied > 0.5 ? result.sourceRidgeOffset.y : lineOffset.y
                    result.sourceRidgeOffset = vector_float2(
                        0.0,
                        clamp(
                            baseRidgeY + ((lineOffset.y - baseRidgeY) * lineBlend),
                            min: -sourceLensRidgePixelMaximumCorrection,
                            max: sourceLensRidgePixelMaximumCorrection
                        )
                    )
                    result.sourceRidgeSupport = max(result.sourceRidgeSupport, result.sourceRidgeLineSupport)
                    result.sourceRidgeApplied = 1.0
                }
                if localBinSupport >= lensShakeMinimumSupport {
                    let localOffsets = (0..<sourceLensShakeLocalBinCount).map { bin in
                        supportedLocalBinOffset(localResiduals[bin], support: localSupports[bin])
                    }
                    func localOffset(row: Int, column: Int) -> vector_float2 {
                        let bin = (row * sourceLensShakeLocalColumnCount) + column
                        guard localOffsets.indices.contains(bin) else {
                            return vector_float2(0.0, 0.0)
                        }
                        return localOffsets[bin]
                    }
                    let leftColumn = 0
                    let centerColumn = sourceLensShakeLocalColumnCount / 2
                    let rightColumn = max(0, sourceLensShakeLocalColumnCount - 1)
                    result.localTopLeftOffset = localOffset(row: 0, column: leftColumn)
                    result.localTopCenterOffset = localOffset(row: 0, column: centerColumn)
                    result.localTopRightOffset = localOffset(row: 0, column: rightColumn)
                    result.localRidgeLeftOffset = localOffset(row: 1, column: leftColumn)
                    result.localRidgeCenterOffset = localOffset(row: 1, column: centerColumn)
                    result.localRidgeRightOffset = localOffset(row: 1, column: rightColumn)
                    result.localMidLeftOffset = localOffset(row: 2, column: leftColumn)
                    result.localMidCenterOffset = localOffset(row: 2, column: centerColumn)
                    result.localMidRightOffset = localOffset(row: 2, column: rightColumn)
                    result.localSupport = clamp(localBinSupport, min: 0.0, max: 1.0)
                    result.localApplied = 1.0
                }
                result.bandWarpSupport = clamp(localWarpSupport, min: 0.0, max: 1.0)
                if rowPhaseSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 1
                }
                if bandDisagreementSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 1
                    result.bandModelMask |= 4
                }
                if columnPhaseSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 2
                }
                if localRollSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 8
                }
                if sourceRidgeSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 16
                }
                if sourceRidgeLineSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 64
                }
                if localBinSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 32
                }
                let localWarpMagnitude = max(
                    max(
                        simd_length(result.bandTopOffset),
                        max(simd_length(result.bandRidgeOffset), simd_length(result.bandMidOffset))
                    ),
                    max(
                        max(
                            simd_length(result.bandTopColumnOffset),
                            max(simd_length(result.bandRidgeColumnOffset), simd_length(result.bandMidColumnOffset))
                        ),
                        max(
                            max(
                                simd_length(result.bandTopRowPhaseOffset),
                                max(simd_length(result.bandRidgeRowPhaseOffset), simd_length(result.bandMidRowPhaseOffset))
                            ),
                            max(
                                max(abs(result.bandTopLocalRoll), max(abs(result.bandRidgeLocalRoll), abs(result.bandMidLocalRoll))),
                                max(simd_length(result.sourceRidgeOffset), localBinMagnitude)
                            )
                        )
                    )
                )
                if localWarpMagnitude >= 0.02 {
                    result.bandWarpApplied = 1.0
                }
            }
        }

        if result.farFieldRigidApplied > 0.5 {
            result.support = result.farFieldRigidSupport
            result.reasonCode = 7
            return result
        }

        if result.farFieldRigidLocalWarpSuppressed > 0.5,
           result.farFieldRigidSupport >= lensShakeMinimumSupport {
            result.support = result.farFieldRigidSupport
            result.reasonCode = 8
            return result
        }

        if result.bandWarpApplied > 0.5 {
            result.support = result.bandWarpSupport
            result.reasonCode = 6
            return result
        }

        if result.bandWarpSupport >= lensShakeMinimumSupport {
            result.support = result.bandWarpSupport
            result.reasonCode = 5
            return result
        }

        let unsafeRollingScore = max(result.rollingShutterCandidate, result.bandRollingShutterScore)
        if unsafeRollingScore >= lensShakeGlobalUnsafeSupport {
            let rollingGlobalPixelBridge = confidenceRamp(
                unsafeRollingScore,
                start: lensShakeGlobalUnsafeSupport,
                full: lensShakeRollingGlobalPixelUnsafeFull
            )
                * confidenceRamp(dominantWindowSupport, start: 0.10, full: 0.54)
            let meshGlobalXResidual = result.farFieldMeshOffset.x
            let meshGlobalXSupport = rollingGlobalPixelBridge
                * confidenceRamp(
                    result.farFieldMeshSupport,
                    start: lensShakeRollingGlobalMeshXSupportStart,
                    full: lensShakeRollingGlobalMeshXSupportFull
                )
                * confidenceRamp(
                    abs(meshGlobalXResidual),
                    start: lensShakeRollingGlobalMeshXResidualStart,
                    full: lensShakeRollingGlobalMeshXResidualFull
                )
                * (1.0 - (confidenceRamp(
                    result.farFieldMeshMaxBinDelta,
                    start: lensShakeRollingGlobalMeshXDisagreementStart,
                    full: lensShakeRollingGlobalMeshXDisagreementFull
                ) * 0.35))
            let localGlobalXSupport = rollingGlobalPixelBridge
                * confidenceRamp(sourceLocalGlobalSupport, start: 0.16, full: 0.58)
                * confidenceRamp(abs(sourceLocalGlobalResidual.x), start: 0.10, full: 1.35)
            let localGlobalYSupport = rollingGlobalPixelBridge
                * confidenceRamp(sourceLocalGlobalSupport, start: 0.16, full: 0.58)
                * confidenceRamp(abs(sourceLocalGlobalResidual.y), start: 0.10, full: 1.65)
            let rollingGlobalXSupport = supportX
                * rollingGlobalPixelBridge
                * confidenceRamp(
                    supportX,
                    start: lensShakeMinimumSupport,
                    full: lensShakeRollingGlobalPixelSupportFull
                )
                * confidenceRamp(abs(residualX), start: lensShakePixelStartPixels, full: 2.2)
            let usesRollingGlobalMeshX = abs(meshGlobalXResidual) * meshGlobalXSupport > abs(smoothedResidualX) * rollingGlobalXSupport
            let rollingGlobalXResidual = usesRollingGlobalMeshX
                ? meshGlobalXResidual
                : smoothedResidualX
            let usesRollingGlobalLocalX = abs(sourceLocalGlobalResidual.x) * localGlobalXSupport > abs(rollingGlobalXResidual) * max(rollingGlobalXSupport, meshGlobalXSupport)
            let rollingGlobalXEffectiveResidual = usesRollingGlobalLocalX
                ? sourceLocalGlobalResidual.x
                : rollingGlobalXResidual
            let rollingGlobalXEffectiveSupport = max(rollingGlobalXSupport, max(meshGlobalXSupport, localGlobalXSupport))
            let rollingGlobalYSupport = supportY
                * rollingGlobalPixelBridge
                * confidenceRamp(
                    supportY,
                    start: lensShakeMinimumSupport,
                    full: lensShakeRollingGlobalPixelSupportFull
                )
                * confidenceRamp(abs(residualY), start: lensShakePixelStartPixels, full: 2.4)
            let ridgeLineGlobalYSupport = result.sourceRidgeLineSupport
                * rollingGlobalPixelBridge
                * confidenceRamp(
                    result.sourceRidgeLineSupport,
                    start: sourceLensRidgeLineGlobalSupportStart,
                    full: sourceLensRidgeLineGlobalSupportFull
                )
            let rollingGlobalYOffset = clamp(
                -smoothedResidualY * rollingGlobalYSupport,
                min: -lensShakeRollingGlobalYMaximumCorrection,
                max: lensShakeRollingGlobalYMaximumCorrection
            )
            let localGlobalYOffset = clamp(
                -sourceLocalGlobalResidual.y * localGlobalYSupport,
                min: -lensShakeRollingGlobalYMaximumCorrection,
                max: lensShakeRollingGlobalYMaximumCorrection
            )
            let ridgeLineResidualGlobalYOffset = clamp(
                -result.sourceRidgeLineResidual.y * sourceLensRidgeLineGlobalPixelScale,
                min: -sourceLensRidgeLineGlobalPixelMaximumCorrection,
                max: sourceLensRidgeLineGlobalPixelMaximumCorrection
            )
            let ridgeLineGlobalYOffset = abs(ridgeLineResidualGlobalYOffset) > abs(result.sourceRidgeLineOffset.y)
                ? ridgeLineResidualGlobalYOffset
                : result.sourceRidgeLineOffset.y
            let ridgeLineGlobalYDisagreement = confidenceRamp(
                abs(ridgeLineGlobalYOffset - rollingGlobalYOffset),
                start: 0.85,
                full: 2.20
            )
            let ridgeLineGlobalYAuthority = clamp(
                ridgeLineGlobalYSupport
                    + (result.sourceRidgeLineSupport * ridgeLineGlobalYDisagreement * 0.42)
                    * (1.0 - (confidenceRamp(
                        abs(ridgeLineGlobalYOffset - rollingGlobalYOffset),
                        start: 3.5,
                        full: 8.0
                    ) * 0.35)),
                min: 0.0,
                max: 1.0
            )
            let localGlobalYAuthority = confidenceRamp(
                localGlobalYSupport,
                start: sourceLensRidgeLineGlobalSupportStart,
                full: sourceLensRidgeLineGlobalSupportFull
            ) * (1.0 - (confidenceRamp(
                abs(localGlobalYOffset - rollingGlobalYOffset),
                start: 4.5,
                full: 10.0
            ) * 0.45))
            let rollingGlobalSupport = clamp(
                max(rollingGlobalXEffectiveSupport, max(rollingGlobalYSupport, max(ridgeLineGlobalYSupport, localGlobalYSupport))),
                min: 0.0,
                max: 1.0
            )
            if rollingGlobalSupport >= lensShakeMinimumSupport {
                result.pixelOffset.x = clamp(
                    -rollingGlobalXEffectiveResidual * rollingGlobalXEffectiveSupport,
                    min: -lensShakeRollingGlobalXMaximumCorrection,
                    max: lensShakeRollingGlobalXMaximumCorrection
                )
                let localMixedYOffset = rollingGlobalYOffset
                    + ((localGlobalYOffset - rollingGlobalYOffset) * localGlobalYAuthority)
                result.pixelOffset.y = localMixedYOffset
                    + ((ridgeLineGlobalYOffset - localMixedYOffset) * ridgeLineGlobalYAuthority)
                result.sourceRidgeOffset = vector_float2(0.0, 0.0)
                result.sourceRidgeSupport = 0.0
                result.sourceRidgeApplied = 0.0
                result.support = rollingGlobalSupport
                result.reasonCode = 10
                result.bandModelMask |= 65536
                result.bandModelMask |= 524288
                if usesRollingGlobalMeshX {
                    result.bandModelMask |= 131072
                }
                if usesRollingGlobalLocalX || localGlobalYSupport >= lensShakeMinimumSupport {
                    result.bandModelMask |= 262144
                }
                return result
            }
        }

        result.yawPitch = vector_float2(
            clamp(yaw * supportYaw, min: -maxRenderedFarFieldYawPitchProxy, max: maxRenderedFarFieldYawPitchProxy),
            clamp(pitch * supportPitch, min: -maxRenderedFarFieldYawPitchProxy, max: maxRenderedFarFieldYawPitchProxy)
        )
        result.shear = vector_float2(
            clamp(shearX * supportShearX, min: -maxRenderedFarFieldShear, max: maxRenderedFarFieldShear),
            clamp(shearY * supportShearY, min: -maxRenderedFarFieldShear, max: maxRenderedFarFieldShear)
        )
        result.perspective = vector_float2(
            clamp(perspectiveX * supportPerspectiveX, min: -maxRenderedFarFieldPerspective, max: maxRenderedFarFieldPerspective),
            clamp(perspectiveY * supportPerspectiveY, min: -maxRenderedFarFieldPerspective, max: maxRenderedFarFieldPerspective)
        )

        if recordSupport(supportX, axisBit: 1) {
            result.pixelOffset.x = clamp(-smoothedResidualX * supportX, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
        }
        if recordSupport(supportY, axisBit: 2) {
            result.pixelOffset.y = clamp(-smoothedResidualY * supportY, min: -lensShakePixelMaximumCorrection, max: lensShakePixelMaximumCorrection)
        }

        if supportRoll >= lensShakeMinimumSupport {
            result.rotationDegrees = clamp(
                -smoothedResidualRoll * supportRoll,
                min: -lensShakeRotationMaximumCorrectionDegrees,
                max: lensShakeRotationMaximumCorrectionDegrees
            )
        }
        result.support = maximumAppliedSupport
        if maximumAppliedSupport > 0.0 {
            result.reasonCode = 1
        } else if qualitySupport < 0.12, maximumEvidence > 0.0 {
            result.reasonCode = 2
        } else if maximumEvidence > 0.0 {
            result.reasonCode = 3
        } else {
            result.reasonCode = 4
        }
        return result
    }

    private static func effectiveFarFieldWarpComponentStrengths(_ requestedStrength: Float) -> FarFieldWarpComponentStrengths {
        let bounded = clamp(
            requestedStrength,
            min: 0.0,
            max: maximumFarFieldWarpStrength
        )
        guard bounded > 0.0 else {
            return FarFieldWarpComponentStrengths(yawPitch: 0.0, shear: 0.0, perspective: 0.0)
        }
        guard bounded < 1.0 else {
            return FarFieldWarpComponentStrengths(yawPitch: bounded, shear: bounded, perspective: bounded)
        }
        let lifted = bounded + (bounded * (1.0 - bounded) * farFieldWarpSubunitResponseLift)
        let yawPitchStrength = clamp(lifted, min: bounded, max: farFieldWarpSubunitResponseMax)
        return FarFieldWarpComponentStrengths(
            yawPitch: yawPitchStrength,
            shear: bounded,
            perspective: bounded
        )
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

    private static func monotonicDominantTravel(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int]
    ) -> Float {
        let sortedIndices = (indicesAreStrictlyAscending(indices) ? indices : indices.sorted())
            .filter { values.values.indices.contains($0) && frames.indices.contains($0) }
        guard sortedIndices.count >= 2 else {
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
        return max(positiveTravel, negativeTravel)
    }

    private static func adaptiveXTurnTiming(
        travelPixels: Float,
        baseWindowSeconds: Double,
        panSmoothSeconds: Double,
        turnSmoothingZoom: Double
    ) -> AdaptiveXTurnTiming {
        let baseWindow = baseWindowSeconds.isFinite && baseWindowSeconds > 0.0
            ? baseWindowSeconds
            : renderTurnTransitionSmoothingWindowSeconds
        guard travelPixels.isFinite, travelPixels > 0.0 else {
            return AdaptiveXTurnTiming(travelPixels: 0.0, windowSeconds: baseWindow, active: false)
        }
        guard turnSmoothingZoomNormalized(turnSmoothingZoom) > Float.ulpOfOne else {
            return AdaptiveXTurnTiming(travelPixels: travelPixels, windowSeconds: baseWindow, active: false)
        }

        let requestedWindow = panSmoothSeconds.isFinite && panSmoothSeconds > 0.0
            ? panSmoothSeconds
            : baseWindow
        let strengthWindow = baseWindow * Double(max(
            0.25,
            turnSmoothingZoomNormalized(turnSmoothingZoom) * (adaptiveXTurnTransitionMaximumZoomParameter / adaptiveXTurnTransitionStandardStrength)
        ))
        let maximumWindow = max(strengthWindow, requestedWindow)
        let targetPixelRate = adaptiveXTurnTransitionTargetPixelRate
        let gateStartPixels = adaptiveXTurnTransitionGateStartPixels
        let gateFullPixels = adaptiveXTurnTransitionGateFullPixels
        let travelWindow = min(
            maximumWindow,
            max(strengthWindow, Double(travelPixels / max(targetPixelRate, Float.ulpOfOne)))
        )
        let travelGate = confidenceRamp(
            travelPixels,
            start: min(gateStartPixels, gateFullPixels - Float.ulpOfOne),
            full: max(gateFullPixels, gateStartPixels + Float.ulpOfOne)
        )
        let effectiveWindow = strengthWindow + ((travelWindow - strengthWindow) * Double(travelGate))
        return AdaptiveXTurnTiming(
            travelPixels: travelPixels,
            windowSeconds: effectiveWindow,
            active: true
        )
    }

    private static func adaptiveXTurnTransitionSampleCount(windowSeconds: Double) -> Int {
        let baseCount = max(3, renderTurnTransitionSmoothingSampleCount)
        let baseWindow = max(renderTurnTransitionSmoothingWindowSeconds, 1e-6)
        guard windowSeconds.isFinite, windowSeconds > baseWindow else {
            return baseCount
        }
        var expandedCount = Int(ceil(Double(baseCount) * (windowSeconds / baseWindow)))
        expandedCount = max(baseCount, expandedCount)
        if expandedCount % 2 == 0 {
            expandedCount += 1
        }
        return expandedCount
    }

    private static func adaptiveXTurnTiming(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        baseWindowSeconds: Double,
        panSmoothSeconds: Double,
        outputScale: Float,
        turnSmoothingZoom: Double
    ) -> AdaptiveXTurnTiming {
        let travelPixels = monotonicDominantTravel(values, frames: frames, indices: indices)
            * max(0.0, outputScale.isFinite ? abs(outputScale) : 0.0)
        return adaptiveXTurnTiming(
            travelPixels: travelPixels,
            baseWindowSeconds: baseWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            turnSmoothingZoom: turnSmoothingZoom
        )
    }

    private static func adaptiveXTurnTiming(
        _ paths: [EstimatedPath],
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        baseWindowSeconds: Double,
        panSmoothSeconds: Double,
        outputScale: Float,
        turnSmoothingZoom: Double
    ) -> AdaptiveXTurnTiming {
        let safeOutputScale = max(0.0, outputScale.isFinite ? abs(outputScale) : 0.0)
        let travelPixels = paths.reduce(Float(0.0)) { partial, path in
            max(partial, monotonicDominantTravel(path, frames: frames, indices: indices) * safeOutputScale)
        }
        return adaptiveXTurnTiming(
            travelPixels: travelPixels,
            baseWindowSeconds: baseWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            turnSmoothingZoom: turnSmoothingZoom
        )
    }

    private static func adaptiveXTurnSmoothValue(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        indices: [Int],
        centerTime: Double,
        baseWindowSeconds: Double,
        fallbackWindowSeconds: Double? = nil,
        panSmoothSeconds: Double,
        outputScale: Float,
        turnSmoothingZoom: Double
    ) -> Float {
        let timing = adaptiveXTurnTiming(
            values,
            frames: frames,
            indices: indices,
            baseWindowSeconds: baseWindowSeconds,
            panSmoothSeconds: panSmoothSeconds,
            outputScale: outputScale,
            turnSmoothingZoom: turnSmoothingZoom
        )
        let fallbackWindow = fallbackWindowSeconds ?? baseWindowSeconds
        let activeWindow = timing.active ? max(fallbackWindow, timing.windowSeconds) : fallbackWindow
        if timing.active,
           let sCurveValue = timeWeightedMonotonicSCurveValue(
            values,
            frames: frames,
            indices: indices,
            centerTime: centerTime,
            windowSeconds: activeWindow
           )
        {
            return sCurveValue
        }
        return timeWeightedLinearPrediction(
            values,
            frames: frames,
            indices: indices,
            centerTime: centerTime,
            windowSeconds: fallbackWindow
        ) ??
            timeWeightedMonotonicSCurveValue(
                values,
                frames: frames,
                indices: indices,
                centerTime: centerTime,
                windowSeconds: fallbackWindow
            ) ??
            timeWeightedAverage(
                values,
                frames: frames,
                indices: indices,
                centerTime: centerTime,
                windowSeconds: fallbackWindow
            )
    }

    private static func turnIntentPath(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        targetIndices: [Int],
        windowSeconds: Double
    ) -> EstimatedPath {
        guard !values.values.isEmpty else {
            return values
        }
        var intentValues = values.values
        let halfWindowSeconds = max(0.0, windowSeconds * 0.5)
        for index in targetIndices where values.values.indices.contains(index) && frames.indices.contains(index) {
            let centerTime = frames[index].time
            let localIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindowSeconds)
            let activeIndices = localIndices.isEmpty ? [index] : localIndices
            intentValues[index] = timeWeightedMonotonicSCurveValue(
                values,
                frames: frames,
                indices: activeIndices,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            ) ?? timeWeightedAverage(
                values,
                frames: frames,
                indices: activeIndices,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            )
        }
        return EstimatedPath(values: intentValues)
    }

    private static func adaptiveXTurnIntentPath(
        _ values: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        targetIndices: [Int],
        baseWindowSeconds: Double,
        fallbackWindowSeconds: Double? = nil,
        panSmoothSeconds: Double,
        outputScale: Float,
        turnSmoothingZoom: Double
    ) -> (path: EstimatedPath, maxTiming: AdaptiveXTurnTiming) {
        guard !values.values.isEmpty else {
            return (
                values,
                AdaptiveXTurnTiming(travelPixels: 0.0, windowSeconds: baseWindowSeconds, active: false)
            )
        }

        var intentValues = values.values
        var maxTiming = AdaptiveXTurnTiming(travelPixels: 0.0, windowSeconds: baseWindowSeconds, active: false)
        let fallbackWindow = fallbackWindowSeconds ?? baseWindowSeconds
        let baseHalfWindowSeconds = max(0.0, baseWindowSeconds * 0.5)
        for index in targetIndices where values.values.indices.contains(index) && frames.indices.contains(index) {
            let centerTime = frames[index].time
            let centeredIndices = indicesWithinTimeRadius(
                frames,
                centerTime: centerTime,
                radiusSeconds: baseHalfWindowSeconds
            )
            let lookaheadIndices = indicesWithinForwardTimeWindow(
                frames,
                startTime: centerTime,
                durationSeconds: panSmoothSeconds
            )
            let activeIndices = uniqueSortedIndices(
                centeredIndices + lookaheadIndices,
                validCount: frames.count
            )
            let timingSourceIndices = activeIndices.isEmpty ? [index] : activeIndices
            let timing = adaptiveXTurnTiming(
                values,
                frames: frames,
                indices: timingSourceIndices,
                baseWindowSeconds: baseWindowSeconds,
                panSmoothSeconds: panSmoothSeconds,
                outputScale: outputScale,
                turnSmoothingZoom: turnSmoothingZoom
            )
            if timing.travelPixels > maxTiming.travelPixels || timing.windowSeconds > maxTiming.windowSeconds {
                maxTiming = timing
            }
            let activeWindow = timing.active ? max(fallbackWindow, timing.windowSeconds) : fallbackWindow
            let activeHalfWindow = max(0.0, activeWindow * 0.5)
            let timingCenteredIndices = abs(activeWindow - baseWindowSeconds) > 0.001
                ? indicesWithinTimeRadius(
                    frames,
                    centerTime: centerTime,
                    radiusSeconds: activeHalfWindow
                )
                : centeredIndices
            let timingLookaheadIndices = indicesWithinForwardTimeWindow(
                frames,
                startTime: centerTime,
                durationSeconds: activeWindow
            )
            let timingIndices = uniqueSortedIndices(
                timingCenteredIndices + timingLookaheadIndices,
                validCount: frames.count
            )
            let effectiveIndices = timingIndices.isEmpty ? timingSourceIndices : timingIndices
            intentValues[index] = timeWeightedMonotonicSCurveValue(
                values,
                frames: frames,
                indices: effectiveIndices,
                centerTime: centerTime,
                windowSeconds: activeWindow
            ) ?? timeWeightedAverage(
                values,
                frames: frames,
                indices: effectiveIndices,
                centerTime: centerTime,
                windowSeconds: activeWindow
            )
        }
        return (EstimatedPath(values: intentValues), maxTiming)
    }

    private static func indicesWithinForwardTimeWindow(
        _ frames: [StabilizerAnalysisFrame],
        startTime: Double,
        durationSeconds: Double
    ) -> [Int] {
        guard !frames.isEmpty, startTime.isFinite, durationSeconds.isFinite else {
            return []
        }
        let boundedDuration = max(0.0, durationSeconds)
        let lowerIndex = lowerBoundFrameIndex(frames, time: startTime - timeWindowSelectionEpsilon)
        let upperIndex = upperBoundFrameIndex(
            frames,
            time: startTime + boundedDuration + timeWindowSelectionEpsilon
        )
        guard lowerIndex < upperIndex else {
            return []
        }
        return Array(lowerIndex..<upperIndex)
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

    private static func farFieldWalkingBandBlend(
        farFieldConfidence: Float,
        warpConfidence: Float,
        trackingConfidence: Float,
        edgeQuality: Float
    ) -> Float {
        // Far-field translation/mesh evidence belongs exclusively to Far-field Warp.
        // Camera Jitter consumes the prepared global walking trajectory only.
        _ = farFieldConfidence
        _ = warpConfidence
        _ = trackingConfidence
        _ = edgeQuality
        return 0.0
    }

    private static func blendedFarFieldBand(
        footstepBand: Float,
        farFieldBand: Float,
        blend: Float,
        hasFarField: Bool
    ) -> Float {
        guard hasFarField,
              footstepBand.isFinite,
              farFieldBand.isFinite,
              blend.isFinite,
              blend > 0.0
        else {
            return footstepBand
        }
        let boundedBlend = clamp(blend, min: 0.0, max: 1.0)
        let footstepMagnitude = abs(footstepBand)
        let farFieldMagnitude = abs(farFieldBand)
        let overshootAllowance = max(0.35, footstepMagnitude * 0.12)
        guard farFieldMagnitude <= footstepMagnitude + overshootAllowance else {
            return footstepBand
        }
        let directionBlendScale: Float = (footstepBand * farFieldBand) < 0.0
            ? confidenceRamp(min(footstepMagnitude, farFieldMagnitude), start: 0.0, full: 0.35)
            : 1.0
        let effectiveBlend = boundedBlend * directionBlendScale
        return footstepBand + ((farFieldBand - footstepBand) * effectiveBlend)
    }

    private static func confidenceCompensatedCorrectionFactor(_ strength: Double, confidence: Float) -> Float {
        let requestedRemoval = turnSmoothingZoomNormalized(strength) * maximumTurnSmoothingCorrectionAuthority
        let confidenceResponse = turnCorrectionConfidenceResponse(confidence)
        let directRemoval = min(requestedRemoval, 1.0) * confidenceResponse
        let confidenceBoost = max(0.0, requestedRemoval - 1.0)
            * 0.55
            * confidenceResponse
            * (1.0 - (confidenceResponse * 0.25))
        return max(0.0, directRemoval + confidenceBoost)
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

    private static func verticalWalkingConfidenceCompensatedCorrectionFactor(_ strength: Double, confidence: Float, maxStrength: Float = 4.0) -> Float {
        let base = walkingConfidenceCompensatedCorrectionFactor(strength, confidence: confidence, maxStrength: maxStrength)
        let boundedConfidence = clamp(confidence, min: 0.0, max: 1.0)
        let mediumLift = boundedConfidence * (1.0 - boundedConfidence) * verticalWalkingMediumConfidenceLift
        return clamp(base + mediumLift, min: 0.0, max: 1.0)
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

    private static func farFieldWarpAppliedConfidence(
        stableWarpConfidence: Float,
        warpGate: Float,
        turnGate: Float,
        trackingConfidence: Float,
        edgeQuality: Float
    ) -> Float {
        let safeWarpConfidence = clamp(stableWarpConfidence, min: 0.0, max: 1.0)
        let safeWarpGate = clamp(warpGate, min: 0.0, max: 1.0)
        let safeTurnGate = clamp(turnGate, min: 0.0, max: 1.0)
        let base = safeWarpConfidence * safeWarpGate * safeTurnGate
        guard base > 0.0 else {
            return 0.0
        }
        let trackingSupport = confidenceRamp(
            trackingConfidence,
            start: farFieldWarpTrackingGateStart,
            full: farFieldWarpTrackingGateFull
        )
        let edgeSupport = confidenceRamp(
            edgeQuality,
            start: farFieldWarpEdgeQualityGateStart,
            full: farFieldWarpEdgeQualityGateFull
        )
        let evidenceSupport = max(safeWarpGate, trackingSupport * edgeSupport)
        let lifted = base + (base * (1.0 - base) * 0.85 * evidenceSupport)
        return clamp(lifted, min: base, max: 1.0)
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
        let stableFloor = localMedianTrackingConfidence * 0.72
        return clamp(
            max(blendedTrackingConfidence, stableFloor),
            min: 0.0,
            max: max(currentTrackingConfidence, localMedianTrackingConfidence)
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
        guard localMedianEdgeQuality >= farFieldWarpEdgeQualityGateStart else {
            return min(currentEdgeQuality, localMedianEdgeQuality)
        }
        let stableFloor = localMedianEdgeQuality * 0.72
        return clamp(
            max(currentEdgeQuality, stableFloor),
            min: 0.0,
            max: max(currentEdgeQuality, localMedianEdgeQuality)
        )
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
        let stabilizedMedian = localMedianWarpConfidence * (0.68 + (0.24 * medianSupport))
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
        turnOwnership: Float,
        turnMacroMagnitude: Float,
        farFieldSupport: Float
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
        let macroGate = turnOwnedFarFieldXMacroGate(
            turnMacroMagnitude,
            farFieldSupport: farFieldSupport
        )
        return clamp(
            turnOwnedWalkingXGateFloorMax * turnSupport * walkingSupport * impulseSupport * macroGate,
            min: 0.0,
            max: turnOwnedWalkingXGateFloorMax
        )
    }

    private static func turnOwnedWalkingXMacroGate(_ turnMacroMagnitude: Float) -> Float {
        guard turnMacroMagnitude.isFinite else {
            return 1.0
        }
        let macroOwnership = confidenceRamp(
            abs(turnMacroMagnitude),
            start: turnOwnedWalkingXMacroFadeStartPixels,
            full: turnOwnedWalkingXMacroFadeFullPixels
        )
        return clamp(1.0 - macroOwnership, min: 0.0, max: 1.0)
    }

    private static func turnOwnedFarFieldXMacroGate(
        _ turnMacroMagnitude: Float,
        farFieldSupport: Float
    ) -> Float {
        guard turnMacroMagnitude.isFinite else {
            return 1.0
        }
        let macroOwnership = confidenceRamp(
            abs(turnMacroMagnitude),
            start: turnOwnedWalkingXMacroFadeStartPixels,
            full: turnOwnedWalkingXMacroFadeFullPixels
        )
        let baseGate = 1.0 - macroOwnership
        let farFieldFloor = turnOwnedFarFieldXMacroGateFloorMax
            * confidenceRamp(farFieldSupport, start: 0.12, full: 0.52)
            * macroOwnership
        return clamp(max(baseGate, farFieldFloor), min: 0.0, max: 1.0)
    }

    private static func farFieldTurnOwnedWalkingXSupport(
        warpConfidence: Float,
        trackingConfidence: Float,
        edgeQuality: Float
    ) -> Float {
        let warpSupport = confidenceRamp(
            clamp(warpConfidence, min: 0.0, max: 1.0),
            start: 0.45,
            full: 0.88
        )
        let trackingSupport = confidenceRamp(
            clamp(trackingConfidence, min: 0.0, max: 1.0),
            start: 0.32,
            full: 0.62
        )
        let edgeSupport = confidenceRamp(
            clamp(edgeQuality, min: 0.0, max: 1.0),
            start: farFieldWarpEdgeQualityGateStart,
            full: farFieldWarpEdgeQualityGateFull
        )
        return clamp(warpSupport * trackingSupport * edgeSupport, min: 0.0, max: 1.0)
    }

    private static func turnOwnedFarFieldWalkingXConfidenceFloor(
        bandMagnitude: Float,
        turnShakeSuppression: Float,
        turnOwnership: Float,
        turnMacroMagnitude: Float,
        farFieldSupport: Float
    ) -> Float {
        guard bandMagnitude.isFinite else {
            return 0.0
        }
        let turnSupport = max(
            confidenceRamp(turnShakeSuppression, start: 0.18, full: 0.56),
            confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
        )
        let bandSupport = confidenceRamp(
            bandMagnitude,
            start: turnOwnedFarFieldXConfidenceFloorStartPixels,
            full: turnOwnedFarFieldXConfidenceFloorFullPixels
        )
        let evidenceSupport = confidenceRamp(
            farFieldSupport,
            start: 0.12,
            full: 0.52
        )
        let macroGate = turnOwnedFarFieldXMacroGate(
            turnMacroMagnitude,
            farFieldSupport: farFieldSupport
        )
        return clamp(
            turnOwnedFarFieldXConfidenceFloorMax * turnSupport * bandSupport * evidenceSupport * macroGate,
            min: 0.0,
            max: turnOwnedFarFieldXConfidenceFloorMax
        )
    }

    private static func turnOwnedFarFieldWalkingRescueConfidenceFloor(
        bandPixels: Float,
        turnShakeSuppression: Float,
        turnOwnership: Float,
        turnMacroMagnitude: Float,
        farFieldSupport: Float,
        warpConfidence: Float,
        trackingConfidence: Float,
        farFieldConfidence: Float
    ) -> Float {
        guard bandPixels.isFinite else {
            return 0.0
        }
        let turnSupport = max(
            confidenceRamp(turnShakeSuppression, start: 0.28, full: 0.66),
            confidenceRamp(turnOwnership, start: 0.28, full: 0.66)
        )
        let macroSupport = confidenceRamp(
            turnMacroMagnitude,
            start: turnMacroOwnershipBandStartPixels,
            full: turnMacroOwnershipBandFullPixels
        )
        let bandSupport = confidenceRamp(
            abs(bandPixels),
            start: turnOwnedFarFieldStrideRescueBandStartPixels,
            full: turnOwnedFarFieldStrideRescueBandFullPixels
        )
        let directFarFieldSupport = confidenceRamp(
            farFieldSupport,
            start: turnOwnedFarFieldStrideRescueSupportStart,
            full: turnOwnedFarFieldStrideRescueSupportFull
        )
        let warpSupport = confidenceRamp(
            clamp(warpConfidence, min: 0.0, max: 1.0),
            start: turnOwnedFarFieldStrideRescueWarpStart,
            full: turnOwnedFarFieldStrideRescueWarpFull
        )
        let trackingSupport = confidenceRamp(
            clamp(trackingConfidence, min: 0.0, max: 1.0),
            start: turnOwnedFarFieldStrideRescueTrackingStart,
            full: turnOwnedFarFieldStrideRescueTrackingFull
        )
        let farFieldPathSupport = confidenceRamp(
            clamp(farFieldConfidence, min: 0.0, max: 1.0),
            start: turnOwnedFarFieldStrideRescueFarFieldStart,
            full: turnOwnedFarFieldStrideRescueFarFieldFull
        )
        let evidenceSupport = warpSupport * trackingSupport * max(farFieldPathSupport, directFarFieldSupport)
        return clamp(
            turnOwnedFarFieldStrideRescueConfidenceFloorMax
                * turnSupport
                * macroSupport
                * bandSupport
                * evidenceSupport,
            min: 0.0,
            max: turnOwnedFarFieldStrideRescueConfidenceFloorMax
        )
    }

    private static func farFieldWalkingResidualContinuityOffset(
        footstepBandPixels: vector_float2,
        footstepCorrectionPixels: vector_float2,
        strideBandPixels: vector_float2,
        strideCorrectionPixels: vector_float2,
        turnShakeSuppression: Float,
        turnOwnership: vector_float2,
        turnMacroMagnitude: vector_float2,
        farFieldSupport: Float,
        warpConfidence: Float,
        trackingConfidence: Float,
        farFieldConfidence: Float
    ) -> vector_float2 {
        vector_float2(
            farFieldWalkingResidualContinuityCorrection(
                footstepBandPixels: footstepBandPixels.x,
                footstepCorrectionPixels: footstepCorrectionPixels.x,
                strideBandPixels: strideBandPixels.x,
                strideCorrectionPixels: strideCorrectionPixels.x,
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: turnOwnership.x,
                turnMacroMagnitude: turnMacroMagnitude.x,
                farFieldSupport: farFieldSupport,
                warpConfidence: warpConfidence,
                trackingConfidence: trackingConfidence,
                farFieldConfidence: farFieldConfidence
            ),
            farFieldWalkingResidualContinuityCorrection(
                footstepBandPixels: footstepBandPixels.y,
                footstepCorrectionPixels: footstepCorrectionPixels.y,
                strideBandPixels: strideBandPixels.y,
                strideCorrectionPixels: strideCorrectionPixels.y,
                turnShakeSuppression: turnShakeSuppression,
                turnOwnership: turnOwnership.y,
                turnMacroMagnitude: turnMacroMagnitude.y,
                farFieldSupport: farFieldSupport,
                warpConfidence: warpConfidence,
                trackingConfidence: trackingConfidence,
                farFieldConfidence: farFieldConfidence
            )
        )
    }

    private static func farFieldWalkingResidualContinuityCorrection(
        footstepBandPixels: Float,
        footstepCorrectionPixels: Float,
        strideBandPixels: Float,
        strideCorrectionPixels: Float,
        turnShakeSuppression: Float,
        turnOwnership: Float,
        turnMacroMagnitude: Float,
        farFieldSupport: Float,
        warpConfidence: Float,
        trackingConfidence: Float,
        farFieldConfidence: Float
    ) -> Float {
        guard footstepBandPixels.isFinite,
              footstepCorrectionPixels.isFinite,
              strideBandPixels.isFinite,
              strideCorrectionPixels.isFinite
        else {
            return 0.0
        }
        let residualPixels = footstepBandPixels
            + footstepCorrectionPixels
            + strideBandPixels
            + strideCorrectionPixels
        guard residualPixels.isFinite else {
            return 0.0
        }
        let residualMagnitude = abs(residualPixels)
        let bandMagnitude = max(abs(footstepBandPixels), abs(strideBandPixels))
        let residualSupport = confidenceRamp(
            residualMagnitude,
            start: farFieldWalkingResidualContinuityStartPixels,
            full: farFieldWalkingResidualContinuityFullPixels
        )
        let bandSupport = confidenceRamp(
            bandMagnitude,
            start: farFieldWalkingResidualContinuityBandStartPixels,
            full: farFieldWalkingResidualContinuityBandFullPixels
        )
        guard residualSupport > 0.0,
              bandSupport > 0.0
        else {
            return 0.0
        }

        let directFarFieldSupport = confidenceRamp(
            clamp(farFieldSupport, min: 0.0, max: 1.0),
            start: 0.08,
            full: 0.28
        )
        let pathFarFieldSupport = confidenceRamp(
            clamp(farFieldConfidence, min: 0.0, max: 1.0),
            start: 0.04,
            full: 0.18
        )
        let warpSupport = confidenceRamp(
            clamp(warpConfidence, min: 0.0, max: 1.0),
            start: 0.18,
            full: 0.55
        )
        let trackingSupport = confidenceRamp(
            clamp(trackingConfidence, min: 0.0, max: 1.0),
            start: 0.14,
            full: 0.38
        )
        let turnSupport = max(
            max(
                confidenceRamp(turnShakeSuppression, start: 0.18, full: 0.56),
                confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
            ),
            confidenceRamp(
                turnMacroMagnitude,
                start: turnMacroOwnershipBandStartPixels,
                full: turnMacroOwnershipBandFullPixels
            ) * 0.85
        )
        let evidenceSupport = max(directFarFieldSupport, pathFarFieldSupport)
            * max(warpSupport, trackingSupport)
            * max(0.35, turnSupport)
        let authority = clamp(
            residualSupport * bandSupport * evidenceSupport,
            min: 0.0,
            max: 1.0
        )
        guard authority > 0.0 else {
            return 0.0
        }

        let rawCorrection = -residualPixels * authority
        let limit = residualMagnitude * farFieldWalkingResidualContinuityMaximumResidualScale
        return clamp(rawCorrection, min: -limit, max: limit)
    }

    private static func turnOwnedFootstepXFineBandGate(
        bandPixels: Float,
        turnOwnership: Float
    ) -> Float {
        guard bandPixels.isFinite else {
            return 0.0
        }
        let turnSupport = confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
        let largeBandFade = confidenceRamp(
            abs(bandPixels),
            start: turnOwnedFootstepXFineFadeStartPixels,
            full: turnOwnedFootstepXFineFadeFullPixels
        )
        return clamp(1.0 - (turnSupport * largeBandFade), min: 0.0, max: 1.0)
    }

    private static func turnOwnedFootstepXRescueConfidenceFloor(
        bandPixels: Float,
        turnShakeSuppression: Float,
        turnOwnership: Float,
        farFieldSupport: Float,
        fineGate: Float
    ) -> Float {
        guard bandPixels.isFinite,
              turnShakeSuppression.isFinite,
              turnOwnership.isFinite,
              farFieldSupport.isFinite,
              fineGate.isFinite
        else {
            return 0.0
        }
        let suppressedFineGate = 1.0 - clamp(fineGate, min: 0.0, max: 1.0)
        guard suppressedFineGate > 0.0 else {
            return 0.0
        }
        let turnSupport = max(
            confidenceRamp(turnShakeSuppression, start: 0.18, full: 0.56),
            confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
        )
        let bandSupport = confidenceRamp(
            abs(bandPixels),
            start: turnOwnedFootstepXRescueBandStartPixels,
            full: turnOwnedFootstepXRescueBandFullPixels
        )
        let farFieldEvidenceSupport = confidenceRamp(
            farFieldSupport,
            start: turnOwnedFootstepXRescueSupportStart,
            full: turnOwnedFootstepXRescueSupportFull
        )
        let turnEvidenceSupport = confidenceRamp(
            turnOwnership,
            start: turnOwnedFootstepXRescueTurnEvidenceStart,
            full: turnOwnedFootstepXRescueTurnEvidenceFull
        ) * turnOwnedFootstepXRescueTurnEvidenceScale
        let evidenceSupport = max(farFieldEvidenceSupport, turnEvidenceSupport)
        return clamp(
            turnOwnedFootstepXRescueConfidenceFloorMax
                * suppressedFineGate
                * turnSupport
                * bandSupport
                * evidenceSupport,
            min: 0.0,
            max: turnOwnedFootstepXRescueConfidenceFloorMax
        )
    }

    private static func farFieldFootstepConfidenceFloor(
        bandPixels: Float,
        farFieldSupport: Float
    ) -> Float {
        guard bandPixels.isFinite,
              farFieldSupport.isFinite
        else {
            return 0.0
        }
        let impulseSupport = confidenceRamp(
            abs(bandPixels),
            start: farFieldFootstepConfidenceFloorStartPixels,
            full: farFieldFootstepConfidenceFloorFullPixels
        )
        let evidenceSupport = confidenceRamp(
            farFieldSupport,
            start: 0.20,
            full: 0.70
        )
        return clamp(
            farFieldFootstepConfidenceFloorMax * impulseSupport * evidenceSupport,
            min: 0.0,
            max: farFieldFootstepConfidenceFloorMax
        )
    }

    private static func farFieldFootstepVerticalConfidenceFloor(
        bandPixels: Float,
        farFieldSupport: Float
    ) -> Float {
        guard bandPixels.isFinite,
              farFieldSupport.isFinite
        else {
            return 0.0
        }
        let impulseSupport = confidenceRamp(
            abs(bandPixels),
            start: farFieldFootstepVerticalConfidenceFloorStartPixels,
            full: farFieldFootstepVerticalConfidenceFloorFullPixels
        )
        let evidenceSupport = confidenceRamp(
            farFieldSupport,
            start: 0.20,
            full: 0.70
        )
        return clamp(
            farFieldFootstepVerticalConfidenceFloorMax * impulseSupport * evidenceSupport,
            min: 0.0,
            max: farFieldFootstepVerticalConfidenceFloorMax
        )
    }

    private static func farFieldFootstepRollConfidenceFloor(
        bandDegrees: Float,
        farFieldSupport: Float
    ) -> Float {
        guard bandDegrees.isFinite,
              farFieldSupport.isFinite
        else {
            return 0.0
        }
        let impulseSupport = confidenceRamp(
            abs(bandDegrees),
            start: farFieldFootstepRollConfidenceFloorStartDegrees,
            full: farFieldFootstepRollConfidenceFloorFullDegrees
        )
        let evidenceSupport = confidenceRamp(
            farFieldSupport,
            start: 0.20,
            full: 0.70
        )
        return clamp(
            farFieldFootstepRollConfidenceFloorMax * impulseSupport * evidenceSupport,
            min: 0.0,
            max: farFieldFootstepRollConfidenceFloorMax
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
        let materializedValues = materializedPathValues(values)
        var scales: [Int: Float] = [:]
        scales.reserveCapacity(targetIndices.count)

        for index in targetIndices {
            guard materializedValues.indices.contains(index),
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
            let activeRange = indexRangeWithinTimeRadius(
                frames,
                centerTime: centerTime,
                radiusSeconds: halfWindowSeconds
            )
            guard let stats = turnOwnershipWindowStats(
                values: materializedValues,
                frames: frames,
                range: activeRange,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            ),
                  stats.totalTravel > footstepImpulseFullScalePixels
            else {
                continue
            }

            let turnSmooth = turnOwnershipMonotonicSCurveValue(
                stats: stats,
                centerTime: centerTime,
                windowSeconds: windowSeconds
            ) ?? stats.weightedAverage
            let turnBand = materializedValues[index] - turnSmooth
            let residual = cache.residualPercentile(
                analysis: analysis,
                indices: Array(stats.range),
                percentile: 0.75
            )
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
                stats: stats,
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

    private static func materializedPathValues(_ values: EstimatedPath) -> [Float] {
        guard values.valueProvider != nil || !values.overrides.isEmpty else {
            return values.values
        }
        return values.values.indices.map { values[$0] }
    }

    private static func indexRangeWithinTimeRadius(
        _ frames: [StabilizerAnalysisFrame],
        centerTime: Double,
        radiusSeconds: Double
    ) -> Range<Int> {
        guard !frames.isEmpty, centerTime.isFinite, radiusSeconds.isFinite else {
            return frames.startIndex..<frames.startIndex
        }
        let boundedRadius = max(0.0, radiusSeconds)
        let startTime = centerTime - boundedRadius - timeWindowSelectionEpsilon
        let endTime = centerTime + boundedRadius + timeWindowSelectionEpsilon
        let lowerIndex = lowerBoundFrameIndex(frames, time: startTime)
        let upperIndex = upperBoundFrameIndex(frames, time: endTime)
        guard lowerIndex < upperIndex else {
            return frames.startIndex..<frames.startIndex
        }
        return lowerIndex..<upperIndex
    }

    private static func turnOwnershipWindowStats(
        values: [Float],
        frames: [StabilizerAnalysisFrame],
        range: Range<Int>,
        centerTime: Double,
        windowSeconds: Double
    ) -> TurnOwnershipWindowStats? {
        guard range.count >= 3,
              values.indices.contains(range.lowerBound),
              values.indices.contains(range.upperBound - 1),
              frames.indices.contains(range.lowerBound),
              frames.indices.contains(range.upperBound - 1)
        else {
            return nil
        }

        var positiveTravel: Float = 0.0
        var negativeTravel: Float = 0.0
        for index in (range.lowerBound + 1)..<range.upperBound {
            let delta = values[index] - values[index - 1]
            if delta >= 0.0 {
                positiveTravel += delta
            } else {
                negativeTravel += -delta
            }
        }

        let totalTravel = positiveTravel + negativeTravel
        let firstValue = values[range.lowerBound]
        let lastValue = values[range.upperBound - 1]
        let endpointDelta = lastValue - firstValue
        let dominantTravel = max(positiveTravel, negativeTravel)
        let dominantRatio = dominantTravel / max(totalTravel, Float.ulpOfOne)
        let endpointRatio = abs(endpointDelta) / max(dominantTravel, Float.ulpOfOne)
        let direction: Float
        if abs(endpointDelta) >= dominantTravel * 0.2 {
            direction = endpointDelta >= 0.0 ? 1.0 : -1.0
        } else {
            direction = positiveTravel >= negativeTravel ? 1.0 : -1.0
        }
        let monotonicStart = firstValue * direction
        var monotonicEnd = monotonicStart
        for index in (range.lowerBound + 1)..<range.upperBound {
            monotonicEnd = max(monotonicEnd, values[index] * direction)
        }

        let windowStart = centerTime - (windowSeconds * 0.5)
        let windowEnd = centerTime + (windowSeconds * 0.5)
        var weightedTotal: Float = 0.0
        var totalWeight = Double(0.0)
        for index in range {
            let currentTime = frames[index].time
            let leftBoundary: Double
            if index > range.lowerBound {
                leftBoundary = max(windowStart, (frames[index - 1].time + currentTime) * 0.5)
            } else {
                leftBoundary = windowStart
            }

            let rightBoundary: Double
            if index + 1 < range.upperBound {
                rightBoundary = min(windowEnd, (currentTime + frames[index + 1].time) * 0.5)
            } else {
                rightBoundary = windowEnd
            }

            let weight = max(0.0, rightBoundary - leftBoundary)
            weightedTotal += values[index] * Float(weight)
            totalWeight += weight
        }

        let weightedAverage: Float
        if totalWeight > 1e-9 {
            weightedAverage = weightedTotal / Float(totalWeight)
        } else {
            var total = Float(0.0)
            for index in range {
                total += values[index]
            }
            weightedAverage = total / Float(range.count)
        }

        return TurnOwnershipWindowStats(
            range: range,
            positiveTravel: positiveTravel,
            negativeTravel: negativeTravel,
            totalTravel: totalTravel,
            endpointDelta: endpointDelta,
            dominantTravel: dominantTravel,
            dominantRatio: dominantRatio,
            endpointRatio: endpointRatio,
            monotonicStart: monotonicStart,
            monotonicTravel: monotonicEnd - monotonicStart,
            direction: direction,
            firstTime: frames[range.lowerBound].time,
            lastTime: frames[range.upperBound - 1].time,
            weightedAverage: weightedAverage
        )
    }

    private static func turnOwnershipMonotonicSCurveValue(
        stats: TurnOwnershipWindowStats,
        centerTime: Double,
        windowSeconds: Double
    ) -> Float? {
        guard stats.totalTravel > 0.5,
              stats.dominantRatio >= 0.62 || abs(stats.endpointDelta) >= stats.dominantTravel * 0.35,
              stats.monotonicTravel > 0.5
        else {
            return nil
        }

        let windowStart = centerTime - (windowSeconds * 0.5)
        let windowEnd = centerTime + (windowSeconds * 0.5)
        let intentStartTime = max(stats.firstTime, windowStart)
        let intentEndTime = min(stats.lastTime, windowEnd)
        let duration = intentEndTime - intentStartTime
        guard duration > 1e-6 else {
            return nil
        }

        let normalizedTime = clamp(Float((centerTime - intentStartTime) / duration), min: 0.0, max: 1.0)
        let progress = smootherStep(normalizedTime)
        return (stats.monotonicStart + (stats.monotonicTravel * progress)) * stats.direction
    }

    private static func turnOwnershipConfidence(
        stats: TurnOwnershipWindowStats,
        turnBandValue: Float,
        trackingConfidence: Float
    ) -> Float {
        guard stats.totalTravel > footstepImpulseFullScalePixels else {
            return 0.0
        }

        let monotonicQuality = confidenceRamp(stats.dominantRatio, start: 0.58, full: 0.82)
        let endpointQuality = confidenceRamp(stats.endpointRatio, start: 0.22, full: 0.55)
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
            stats.dominantTravel,
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

    private struct FootstepConfidenceEvidenceSeries {
        let instant: [Float]
        let stable: [Float]
    }

    private static func footstepConfidenceEvidenceSeries(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        fullImpulseScale: Float
    ) -> FootstepConfidenceEvidenceSeries {
        guard !values.isEmpty, !frames.isEmpty else {
            return FootstepConfidenceEvidenceSeries(instant: [], stable: [])
        }
        let instant = frames.indices.map { index -> Float in
            footstepFrameConfidenceEvidenceAtIndex(
                values: values,
                baselineValues: baselineValues,
                frames: frames,
                index: index,
                fullImpulseScale: fullImpulseScale
            )
        }
        return FootstepConfidenceEvidenceSeries(
            instant: instant,
            stable: stableFootstepConfidenceEvidencePath(
                instantEvidence: instant,
                frames: frames
            )
        )
    }

    private static func stableFootstepConfidenceEvidencePath(
        instantEvidence: [Float],
        frames: [StabilizerAnalysisFrame]
    ) -> [Float] {
        guard !instantEvidence.isEmpty, !frames.isEmpty else {
            return instantEvidence
        }
        let halfWindow = max(0.0, footstepConfidenceStabilityWindowSeconds * 0.5)
        let sigma = max(1e-6, halfWindow * 0.55)
        let centerBlend = clamp(footstepConfidenceCenterBlend, min: 0.0, max: 1.0)
        return frames.indices.map { centerIndex -> Float in
            guard instantEvidence.indices.contains(centerIndex) else {
                return 0.0
            }
            let centerTime = frames[centerIndex].time
            let indices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow)
            guard !indices.isEmpty else {
                return instantEvidence[centerIndex]
            }
            var weightedTotal: Float = 0.0
            var totalWeight: Float = 0.0
            for index in indices where instantEvidence.indices.contains(index) {
                let offset = (frames[index].time - centerTime) / sigma
                let weight = Float(Darwin.exp(-0.5 * offset * offset))
                guard weight > 0.0001 else {
                    continue
                }
                weightedTotal += instantEvidence[index] * weight
                totalWeight += weight
            }
            guard totalWeight > Float.ulpOfOne else {
                return instantEvidence[centerIndex]
            }
            let localEvidence = weightedTotal / totalWeight
            return clamp(
                (instantEvidence[centerIndex] * centerBlend) + (localEvidence * (1.0 - centerBlend)),
                min: 0.0,
                max: 1.0
            )
        }
    }

    private static func footstepConfidence(
        trackingConfidence: Float,
        evidence: [Float],
        index: Int
    ) -> Float {
        guard evidence.indices.contains(index) else {
            return 0.0
        }
        return clamp(trackingConfidence * evidence[index], min: 0.0, max: 1.0)
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
        confidenceFloor: Float = 0.0,
        trackingConfidences: [Float]? = nil,
        stableConfidenceEvidence: [Float]? = nil,
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
            let trackingConfidence = trackingConfidences?.indices.contains(index) == true
                ? trackingConfidences![index]
                : walkingBandTrackingConfidence(
                    motionConfidence: analysis.analysisConfidence[index],
                    residual: analysis.residuals[index],
                    blurAmount: analysis.blurAmounts[index],
                    acceptedBlockCount: analysis.acceptedBlockCounts[index],
                    totalBlockCount: analysis.totalBlockCounts[index],
                    qualityModel: analysis.qualityModel
                )
            let confidence: Float
            if let stableConfidenceEvidence,
               stableConfidenceEvidence.indices.contains(index) {
                confidence = footstepConfidence(
                    trackingConfidence: trackingConfidence,
                    evidence: stableConfidenceEvidence,
                    index: index
                )
            } else {
                confidence = footstepFrameConfidence(
                    kind,
                    values: values,
                    baselineValues: baselineValues,
                    frames: analysis.frames,
                    interpolation: FrameInterpolation(lowerIndex: index, upperIndex: index, fraction: 0.0),
                    trackingConfidence: trackingConfidence,
                    fullImpulseScale: fullImpulseScale,
                    cache: cache
                )
            }
            let correctionStrength = walkingConfidenceCompensatedCorrectionFactor(
                requestedStrength,
                confidence: max(
                    confidence * clamp(confidenceScale, min: 0.0, max: 1.0),
                    clamp(confidenceFloor, min: 0.0, max: 1.0)
                ),
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
        var limitedCorrection = rawCorrection + ((localMedian - rawCorrection) * blend)
        if limitedCorrection.isFinite,
           rawCorrection.isFinite,
           abs(limitedCorrection) > abs(rawCorrection) {
            limitedCorrection = rawCorrection
        }
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
        clamp(
            trackingConfidence * footstepFrameConfidenceEvidenceAtIndex(
                values: values,
                baselineValues: baselineValues,
                frames: frames,
                index: index,
                fullImpulseScale: fullImpulseScale
            ),
            min: 0.0,
            max: 1.0
        )
    }

    private static func footstepFrameConfidenceEvidenceAtIndex(
        values: [Float],
        baselineValues: EstimatedPath,
        frames: [StabilizerAnalysisFrame],
        index: Int,
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
        return clamp(supportQuality * impulseQuality * isolationQuality, min: 0.0, max: 1.0)
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
                farFieldDx: 0.0,
                farFieldDy: 0.0,
                farFieldSignedRoll: 0.0,
                farFieldConfidence: 0.0,
                yawProxy: 0.0,
                pitchProxy: 0.0,
                shearX: 0.0,
                shearY: 0.0,
                perspectiveX: 0.0,
                perspectiveY: 0.0,
                lensBandTopDx: 0.0,
                lensBandTopDy: 0.0,
                lensBandTopColumnDx: 0.0,
                lensBandTopColumnDy: 0.0,
                lensBandTopRowPhaseDx: 0.0,
                lensBandTopRowPhaseDy: 0.0,
                lensBandTopLocalRoll: 0.0,
                lensBandRidgeDx: 0.0,
                lensBandRidgeDy: 0.0,
                lensBandRidgeColumnDx: 0.0,
                lensBandRidgeColumnDy: 0.0,
                lensBandRidgeRowPhaseDx: 0.0,
                lensBandRidgeRowPhaseDy: 0.0,
                lensBandRidgeLocalRoll: 0.0,
                lensBandMidDx: 0.0,
                lensBandMidDy: 0.0,
                lensBandMidColumnDx: 0.0,
                lensBandMidColumnDy: 0.0,
                lensBandMidRowPhaseDx: 0.0,
                lensBandMidRowPhaseDy: 0.0,
                lensBandMidLocalRoll: 0.0,
                lensBandTopConfidence: 0.0,
                lensBandRidgeConfidence: 0.0,
                lensBandMidConfidence: 0.0,
                lensBandConfidence: 0.0,
                sourceLensShakeRidgeDy: 0.0,
                sourceLensShakeRidgeSupport: 0.0,
                sourceLensShakeRidgeLineDy: 0.0,
                sourceLensShakeRidgeLineSupport: 0.0,
                sourceLensShakeLocalDx: Array(repeating: 0.0, count: AutoStabilizationEstimator.sourceLensShakeLocalBinCount),
                sourceLensShakeLocalDy: Array(repeating: 0.0, count: AutoStabilizationEstimator.sourceLensShakeLocalBinCount),
                sourceLensShakeLocalSupport: Array(repeating: 0.0, count: AutoStabilizationEstimator.sourceLensShakeLocalBinCount),
                farFieldMeshDx: Array(repeating: 0.0, count: AutoStabilizationEstimator.farFieldMeshBinCount),
                farFieldMeshDy: Array(repeating: 0.0, count: AutoStabilizationEstimator.farFieldMeshBinCount),
                farFieldMeshSupport: Array(repeating: 0.0, count: AutoStabilizationEstimator.farFieldMeshBinCount),
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
