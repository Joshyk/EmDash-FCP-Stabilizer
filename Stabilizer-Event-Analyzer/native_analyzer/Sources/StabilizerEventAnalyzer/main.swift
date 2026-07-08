import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import Metal
import VideoToolbox

private let toolSchemaVersion = 1
private let cacheSchemaVersion = 45
private let farFieldMeshRows = 5
private let farFieldMeshColumns = 9
private let farFieldMeshBinCount = farFieldMeshRows * farFieldMeshColumns
private let farFieldMeshDominantWindowSecondsCandidates: [Double] = [
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
private let sourceLensShakeLocalBandCount = 3
private let sourceLensShakeLocalColumnCount = 5
private let sourceLensShakeLocalBinCount = sourceLensShakeLocalBandCount * sourceLensShakeLocalColumnCount
private let cacheFileName = "host-analysis-v2.json"
private let cacheIndexFileName = "host-analysis-index-v2.json"
private let cacheStorageDirectoryName = "caches"
private let fingerprintInitialHash: UInt64 = 14_695_981_039_346_656_037
private let metalBlurChunkCount = 256
private let fingerprintChunkCount = 1024
private let motionPathJerkLimitMultiplier: Float = 4.0
private let minimumTranslationAccelerationLimit: Float = 0.75
private let minimumTranslationJerkLimit: Float = 0.5
private let minimumRotationAccelerationLimit: Float = 0.04
private let minimumRotationJerkLimit: Float = 0.03
private let farFieldRigidShakeTwoWayRadiusFrames = 5
private let farFieldRigidShakeShapeStartPixels: Float = 0.10
private let farFieldRigidShakeShapeFullPixels: Float = 1.15
private let farFieldRigidShakeForwardBackwardStartPixels: Float = 0.08
private let farFieldRigidShakeForwardBackwardFullPixels: Float = 1.00
private let farFieldRigidShakeResidualStartPixels: Float = 0.08
private let farFieldRigidShakeResidualFullPixels: Float = 0.70

private func farFieldMeshBandRanges() -> [(Float, Float)] {
    [
        (0.04, 0.16),
        (0.13, 0.25),
        (0.22, 0.34),
        (0.31, 0.43),
        (0.40, 0.52)
    ]
}

private func farFieldMeshColumnRanges() -> [(Float, Float)] {
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

private func representativeFrameStepSeconds(frames: [AnalysisFrame]) -> Double {
    guard frames.count >= 2 else {
        return 1.0 / 30.0
    }
    var deltas: [Double] = []
    deltas.reserveCapacity(frames.count - 1)
    for index in 1..<frames.count {
        let delta = frames[index].time - frames[index - 1].time
        if delta.isFinite && delta > 0.0 {
            deltas.append(delta)
        }
    }
    guard !deltas.isEmpty else {
        return 1.0 / 30.0
    }
    deltas.sort()
    return max(1.0 / 240.0, deltas[deltas.count / 2])
}

private func farFieldMeshWindowCandidates(frameStepSeconds: Double) -> [FarFieldMeshWindowCandidate] {
    let safeFrameStep = max(1.0 / 240.0, min(1.0, frameStepSeconds))
    let fps = max(1.0, min(240.0, 1.0 / safeFrameStep))
    var maximumFrames = max(3, Int(floor(fps)))
    if maximumFrames % 2 == 0 {
        maximumFrames -= 1
    }
    var seen = Set<Int>()
    var candidates: [FarFieldMeshWindowCandidate] = []
    for seconds in farFieldMeshDominantWindowSecondsCandidates {
        var frameCount = max(3, Int((seconds * fps).rounded()))
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

private func farFieldMeshConfidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
    guard full > start else {
        return value >= full ? 1.0 : 0.0
    }
    return min(max((value - start) / (full - start), 0.0), 1.0)
}

private func blurEvidenceQuality(_ blurAmount: Float) -> Float {
    guard blurAmount.isFinite else {
        return 0.0
    }
    if blurAmount > 1.25 {
        return min(max((blurAmount - 1.5) / 3.0, 0.0), 1.0)
    }
    return min(max(1.0 - (blurAmount * 0.45), 0.0), 1.0)
}

private func farFieldMeshDominantWindows(
    frames: [AnalysisFrame],
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
        return 1.0 - farFieldMeshConfidenceRamp(normalizedError, start: 0.08, full: 0.34)
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
                let residualX = centerX - baselineX
                let residualY = centerY - baselineY
                let residual = sqrtf((residualX * residualX) + (residualY * residualY))
                let supportGate = farFieldMeshConfidenceRamp(meshValue(support, bin: bin, index: center), start: 0.08, full: 0.38)
                let evidence = farFieldMeshConfidenceRamp(residual, start: 0.035, full: 0.58) * supportGate * shortWindowGate
                if evidence > bestScore {
                    bestScore = evidence
                    dominantWindowFrames[center] = Float(candidate.frames)
                    dominantWindowSeconds[center] = candidate.seconds
                    dominantSupport[center] = min(max(evidence, 0.0), 1.0)
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
private let localSearchRadius = 5
private let maximumMotionSearchRadius = 36
private let minimumAcceptedMotionBlocks = 3
private let minimumFarFieldMotionBlocks = 3
private let staggeredMotionBlockFarFieldThreshold: Float = 0.62
private let detailMotionBlockFarFieldThreshold: Float = 0.62
private let denseSampleMotionBlockFarFieldThreshold: Float = 0.62
private let verticalDetailMotionBlockFarFieldThreshold: Float = 0.80
private let attitudeDetailMotionBlockFarFieldThreshold: Float = 0.55
private let attitudeDetailMotionBlockColumnRadius = 1
private let staggeredMotionBlockMinimumWidth = 18
private let staggeredMotionBlockMinimumHeight = 12
private let maxFarFieldShear: Float = 0.008
private let maxFarFieldYawPitchProxy: Float = 0.004
private let maxFarFieldPerspective: Float = 0.003
private let farFieldConsensusConfidenceFloor: Float = 0.04
private let farFieldConsensusMinimumWeight: Float = 2.5
private let farFieldConsensusFullWeight: Float = 14.0
private let farFieldConsensusCoherenceFrameFraction: Float = 0.010
private let farFieldPlaneStrictThreshold: Float = 0.70
private let farFieldPlaneBroadThreshold: Float = 0.55
private let farFieldPlaneNearThreshold: Float = 0.45
private let farFieldPlaneMinimumBlocks = 3
private let farFieldPlaneParallaxStartPixels: Float = 0.65
private let farFieldPlaneParallaxFullPixels: Float = 5.0
private let farFieldPlaneAuthorityBase: Float = 0.25
private let farFieldPlaneAuthorityParallaxScale: Float = 0.60
private let farFieldPlaneMaximumAuthority: Float = 0.85
private let coarseMotionSearchStep = 6
private let fineMotionSearchRadius = 3
private let fineMotionSearchStep = 1
private let progressMinimumPublishIntervalSeconds = 0.5
private let progressOutputIsTerminal = isatty(STDERR_FILENO) == 1
private let analyzerVideoOutputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: [
        NSNumber(value: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
        NSNumber(value: kCVPixelFormatType_420YpCbCr10BiPlanarFullRange),
        NSNumber(value: kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange),
        NSNumber(value: kCVPixelFormatType_422YpCbCr10BiPlanarFullRange),
        NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
        NSNumber(value: kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange),
        NSNumber(value: kCVPixelFormatType_422YpCbCr8BiPlanarFullRange),
    ],
    kCVPixelBufferMetalCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
]

struct AnalysisPlan: Decodable {
    let cacheRoot: String
    let eventName: String?
    let sampleScalePercent: Double
    let maxFrames: Int?
    let assets: [AssetPlan]
}

struct AssetPlan: Decodable {
    let assetId: String
    let name: String
    let eventName: String?
    let cacheRoot: String
    let mediaPath: String
    let mediaKind: String?
    let durationSeconds: Double
    let frameDurationSeconds: Double
    let sourceStartSeconds: Double
    let width: Int?
    let height: Int?
}

struct AnalysisResult: Encodable {
    let assetId: String
    let name: String
    let eventName: String?
    let footageFileName: String
    let mediaPath: String
    let mediaKind: String?
    let cacheRoot: String
    let sourceMediaFingerprint: String
    let cacheFileName: String
    let cacheIdentity: String
    let cacheSchemaVersion: Int
    let durationSeconds: Double
    let sampleScalePercent: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frameCount: Int
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let rangeEndSeconds: Double
    let frameDurationSeconds: Double
    let firstFingerprint: String
    let middleFingerprint: String
    let lastFingerprint: String
    let preparedMotionPath: Bool
    var analysisTimings: AnalysisTimingSummary? = nil
}

struct AnalysisTimingSummary: Encodable {
    let frameCount: Int
    let totalWallSeconds: Double
    let readFramesWallSeconds: Double
    let readerLaneWallSeconds: Double
    let decoderCopyNextFrameSeconds: Double
    let metalEncodeSeconds: Double
    let metalCompleteSeconds: Double
    let preparedPathSeconds: Double
    let cacheBuildSeconds: Double
    let cacheWriteSeconds: Double
    let readerLaneCount: Int
    let framesPerWallSecond: Double
}

struct ToolOutput: Encodable {
    let schemaVersion: Int
    let status: String
    let results: [AnalysisResult]
}

struct AnalysisFrame: Encodable {
    let time: Double
    let pixels: [UInt8]
    let sampleWidth: Int
    let sampleHeight: Int
    let blurAmount: Float
    let fingerprint: String

    private enum CodingKeys: String, CodingKey {
        case time
        case pixels
        case blurAmount
        case fingerprint
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encodeNil(forKey: .pixels)
        try container.encode(blurAmount, forKey: .blurAmount)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}

struct PairMotion {
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

    static let zero = PairMotion(
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
}

private struct FrameMetrics {
    let blurAmount: Float
    let fingerprint: String
}

private struct RidgeLineProfile {
    let values: [Float]
    let support: Float
}

private struct RidgeLineMotion {
    let dy: Float
    let support: Float

    static let zero = RidgeLineMotion(dy: 0.0, support: 0.0)
}

private func pairMotion(_ motion: PairMotion, applying ridgeLineMotion: RidgeLineMotion) -> PairMotion {
    PairMotion(
        dx: motion.dx,
        dy: motion.dy,
        residual: motion.residual,
        signedRoll: motion.signedRoll,
        rollMotion: motion.rollMotion,
        farFieldDx: motion.farFieldDx,
        farFieldDy: motion.farFieldDy,
        farFieldSignedRoll: motion.farFieldSignedRoll,
        farFieldConfidence: motion.farFieldConfidence,
        yawProxy: motion.yawProxy,
        pitchProxy: motion.pitchProxy,
        shearX: motion.shearX,
        shearY: motion.shearY,
        perspectiveX: motion.perspectiveX,
        perspectiveY: motion.perspectiveY,
        lensBandTopDx: motion.lensBandTopDx,
        lensBandTopDy: motion.lensBandTopDy,
        lensBandTopColumnDx: motion.lensBandTopColumnDx,
        lensBandTopColumnDy: motion.lensBandTopColumnDy,
        lensBandTopRowPhaseDx: motion.lensBandTopRowPhaseDx,
        lensBandTopRowPhaseDy: motion.lensBandTopRowPhaseDy,
        lensBandTopLocalRoll: motion.lensBandTopLocalRoll,
        lensBandRidgeDx: motion.lensBandRidgeDx,
        lensBandRidgeDy: motion.lensBandRidgeDy,
        lensBandRidgeColumnDx: motion.lensBandRidgeColumnDx,
        lensBandRidgeColumnDy: motion.lensBandRidgeColumnDy,
        lensBandRidgeRowPhaseDx: motion.lensBandRidgeRowPhaseDx,
        lensBandRidgeRowPhaseDy: motion.lensBandRidgeRowPhaseDy,
        lensBandRidgeLocalRoll: motion.lensBandRidgeLocalRoll,
        lensBandMidDx: motion.lensBandMidDx,
        lensBandMidDy: motion.lensBandMidDy,
        lensBandMidColumnDx: motion.lensBandMidColumnDx,
        lensBandMidColumnDy: motion.lensBandMidColumnDy,
        lensBandMidRowPhaseDx: motion.lensBandMidRowPhaseDx,
        lensBandMidRowPhaseDy: motion.lensBandMidRowPhaseDy,
        lensBandMidLocalRoll: motion.lensBandMidLocalRoll,
        lensBandTopConfidence: motion.lensBandTopConfidence,
        lensBandRidgeConfidence: max(motion.lensBandRidgeConfidence, ridgeLineMotion.support),
        lensBandMidConfidence: motion.lensBandMidConfidence,
        lensBandConfidence: max(motion.lensBandConfidence, ridgeLineMotion.support),
        sourceLensShakeRidgeDy: motion.sourceLensShakeRidgeDy,
        sourceLensShakeRidgeSupport: motion.sourceLensShakeRidgeSupport,
        sourceLensShakeRidgeLineDy: ridgeLineMotion.dy,
        sourceLensShakeRidgeLineSupport: ridgeLineMotion.support,
        sourceLensShakeLocalDx: motion.sourceLensShakeLocalDx,
        sourceLensShakeLocalDy: motion.sourceLensShakeLocalDy,
        sourceLensShakeLocalSupport: motion.sourceLensShakeLocalSupport,
        farFieldMeshDx: motion.farFieldMeshDx,
        farFieldMeshDy: motion.farFieldMeshDy,
        farFieldMeshSupport: motion.farFieldMeshSupport,
        analysisConfidence: motion.analysisConfidence,
        warpConfidence: motion.warpConfidence,
        acceptedBlockCount: motion.acceptedBlockCount,
        totalBlockCount: motion.totalBlockCount,
        searchRadiusHitCount: motion.searchRadiusHitCount,
        searchRadiusTotalCount: motion.searchRadiusTotalCount
    )
}

private struct LumaBufferFormat {
    let valueRange: UInt16

    var normalizedResidualScale: Float {
        255.0 / Float(max(1, valueRange))
    }
}

private struct DecodedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationSeconds: Double
}

private enum DecoderMode {
    case hardwareRequired

    var description: String {
        "hardware-required VideoToolbox"
    }

    var requiresHardware: Bool {
        true
    }
}

private struct DecoderLanePlan {
    let laneCount: Int
    let mode: DecoderMode

    var description: String {
        mode.description
    }
}

private struct DecoderSessionProbeResult {
    let sessionCount: Int
    let firstFailureDescription: String?
}

private let videoToolboxDecodeOutputCallback: VTDecompressionOutputCallback = { refCon, _, status, _, imageBuffer, presentationTimeStamp, _ in
    guard let refCon else { return }
    let reader = Unmanaged<VideoToolboxDecodedFrameReader>.fromOpaque(refCon).takeUnretainedValue()
    reader.handleDecodeOutput(status: status, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp)
}

private let videoToolboxDecodeProbeOutputCallback: VTDecompressionOutputCallback = { _, _, _, _, _, _, _ in }

private func fourCharacterCodeString(_ code: FourCharCode) -> String {
    String(
        format: "%c%c%c%c",
        Int((code >> 24) & 0xff),
        Int((code >> 16) & 0xff),
        Int((code >> 8) & 0xff),
        Int(code & 0xff)
    )
}

private func videoFormatSummary(formatDescription: CMVideoFormatDescription) -> String {
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    let codec = fourCharacterCodeString(CMFormatDescriptionGetMediaSubType(formatDescription))
    return "\(codec) \(dimensions.width)x\(dimensions.height)"
}

private func decoderImageBufferAttributes(formatDescription: CMVideoFormatDescription) -> [String: Any] {
    let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any]
    let bitsPerComponent = extensions?["BitsPerComponent"] as? Int ?? 8
    let isFullRange = (extensions?["FullRangeVideo"] as? Int ?? 0) != 0
    let pixelFormat: OSType
    if bitsPerComponent >= 10 {
        pixelFormat = isFullRange
            ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    } else {
        pixelFormat = isFullRange
            ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }
    return [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: pixelFormat),
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
}

private func makeVideoToolboxDecompressionSession(
    formatDescription: CMVideoFormatDescription,
    callback: inout VTDecompressionOutputCallbackRecord,
    mode: DecoderMode
) throws -> VTDecompressionSession {
    var decoderSpecification: [String: Any] = [
        kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: mode.requiresHardware
    ]
    if mode.requiresHardware {
        decoderSpecification[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String] = true
    }
    var createdSession: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
        allocator: kCFAllocatorDefault,
        formatDescription: formatDescription,
        decoderSpecification: decoderSpecification as CFDictionary,
        imageBufferAttributes: decoderImageBufferAttributes(formatDescription: formatDescription) as CFDictionary,
        outputCallback: &callback,
        decompressionSessionOut: &createdSession
    )
    guard status == noErr, let createdSession else {
        throw AnalyzerError("\(mode.description) decoder unavailable for \(videoFormatSummary(formatDescription: formatDescription)): VTDecompressionSessionCreate returned \(status)")
    }
    return createdSession
}

private func videoFormatDescription(url: URL) throws -> CMVideoFormatDescription {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw AnalyzerError("asset had no video track: \(url.path)")
    }
    guard let firstFormatDescription = track.formatDescriptions.first else {
        throw AnalyzerError("asset had no video format description: \(url.path)")
    }
    return firstFormatDescription as! CMVideoFormatDescription
}

private func compressedVideoFormatDescription(url: URL) throws -> CMVideoFormatDescription {
    let assetFormatDescription = try videoFormatDescription(url: url)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw AnalyzerError("asset had no video track: \(url.path)")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw AnalyzerError("could not add compressed AVAssetReaderTrackOutput")
    }
    reader.add(output)
    guard reader.startReading() else {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
    }
    defer {
        if reader.status == .reading {
            reader.cancelReading()
        }
    }
    while reader.status == .reading {
        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            break
        }
        if CMSampleBufferGetNumSamples(sampleBuffer) == 0 {
            continue
        }
        return CMSampleBufferGetFormatDescription(sampleBuffer) ?? assetFormatDescription
    }
    return assetFormatDescription
}

private func decoderSessionLimit(url: URL, requestedLimit: Int, mode: DecoderMode) throws -> DecoderSessionProbeResult {
    let requestedLimit = max(1, requestedLimit)
    let formatDescription = try compressedVideoFormatDescription(url: url)
    var sessions: [VTDecompressionSession] = []
    var firstFailureDescription: String?
    defer {
        for session in sessions {
            VTDecompressionSessionInvalidate(session)
        }
    }
    for _ in 0..<requestedLimit {
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: videoToolboxDecodeProbeOutputCallback,
            decompressionOutputRefCon: nil
        )
        do {
            sessions.append(try makeVideoToolboxDecompressionSession(
                formatDescription: formatDescription,
                callback: &callback,
                mode: mode
            ))
        } catch {
            if firstFailureDescription == nil {
                firstFailureDescription = String(describing: error)
            }
            break
        }
    }
    return DecoderSessionProbeResult(
        sessionCount: sessions.count,
        firstFailureDescription: firstFailureDescription
    )
}

private func decoderLanePlan(url: URL, requestedLimit: Int) throws -> DecoderLanePlan {
    let requestedLimit = max(1, requestedLimit)
    let hardwareProbe = try decoderSessionLimit(
        url: url,
        requestedLimit: requestedLimit,
        mode: .hardwareRequired
    )
    if hardwareProbe.sessionCount > 0 {
        return DecoderLanePlan(laneCount: hardwareProbe.sessionCount, mode: .hardwareRequired)
    }
    let hardwareFailure = hardwareProbe.firstFailureDescription ?? "hardware-required VideoToolbox decoder unavailable"
    throw AnalyzerError("hardware-required VideoToolbox decoder unavailable for \(url.path): \(hardwareFailure)")
}

private final class VideoToolboxDecodedFrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let sourceFormatDescription: CMVideoFormatDescription
    private let maxPendingDecodeCount: Int
    private let decoderMode: DecoderMode
    private var session: VTDecompressionSession?
    private var decodedFrames: [DecodedVideoFrame] = []
    private var decodedFrameReadIndex = 0
    private var decodeError: Error?
    private var pendingDecodeCount = 0
    private var reachedEnd = false
    private let lock = NSLock()
    private let decodeSemaphore = DispatchSemaphore(value: 0)

    init(url: URL, timeRange: CMTimeRange?, maxPendingDecodeCount: Int, decoderMode: DecoderMode) throws {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw AnalyzerError("asset had no video track: \(url.path)")
        }
        let formatDescription = try videoFormatDescription(url: url)
        let reader = try AVAssetReader(asset: asset)
        if let timeRange {
            reader.timeRange = timeRange
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AnalyzerError("could not add compressed AVAssetReaderTrackOutput")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
        }
        self.reader = reader
        self.output = output
        self.sourceFormatDescription = formatDescription
        self.maxPendingDecodeCount = max(2, min(32, maxPendingDecodeCount))
        self.decoderMode = decoderMode
    }

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        if reader.status == .reading {
            reader.cancelReading()
        }
    }

    func handleDecodeOutput(status: OSStatus, imageBuffer: CVImageBuffer?, presentationTimeStamp: CMTime) {
        lock.lock()
        pendingDecodeCount = max(0, pendingDecodeCount - 1)
        defer { lock.unlock() }
        defer { decodeSemaphore.signal() }
        guard status == noErr else {
            decodeError = AnalyzerError("\(decoderMode.description) decode output failed with status \(status)")
            return
        }
        guard let imageBuffer else {
            decodeError = AnalyzerError("\(decoderMode.description) decode returned no image buffer")
            return
        }
        let seconds = CMTimeGetSeconds(presentationTimeStamp)
        guard seconds.isFinite else {
            decodeError = AnalyzerError("\(decoderMode.description) decode returned a non-finite presentation time")
            return
        }
        decodedFrames.append(DecodedVideoFrame(pixelBuffer: imageBuffer, presentationSeconds: seconds))
    }

    func copyNextFrame() throws -> DecodedVideoFrame? {
        while true {
            if let frame = popDecodedFrame() {
                return frame
            }
            try throwPendingDecodeError()
            if reachedEnd {
                if pendingDecodeCountSnapshot() > 0 {
                    decodeSemaphore.wait()
                    continue
                }
                if reader.status == .failed {
                    throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed")
                }
                return nil
            }
            if pendingDecodeCountSnapshot() >= maxPendingDecodeCount {
                decodeSemaphore.wait()
                continue
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                reachedEnd = true
                if let session {
                    VTDecompressionSessionFinishDelayedFrames(session)
                    VTDecompressionSessionWaitForAsynchronousFrames(session)
                }
                continue
            }
            try decode(sampleBuffer)
        }
    }

    func cancelReading() {
        if reader.status == .reading {
            reader.cancelReading()
        }
    }

    private func popDecodedFrame() -> DecodedVideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard decodedFrameReadIndex < decodedFrames.count else {
            if decodedFrameReadIndex > 0 {
                decodedFrames.removeAll(keepingCapacity: true)
                decodedFrameReadIndex = 0
            }
            return nil
        }
        let frame = decodedFrames[decodedFrameReadIndex]
        decodedFrameReadIndex += 1
        if decodedFrameReadIndex >= 64 && decodedFrameReadIndex * 2 >= decodedFrames.count {
            decodedFrames.removeFirst(decodedFrameReadIndex)
            decodedFrameReadIndex = 0
        }
        return frame
    }

    private func throwPendingDecodeError() throws {
        lock.lock()
        let error = decodeError
        decodeError = nil
        lock.unlock()
        if let error {
            throw error
        }
    }

    private func pendingDecodeCountSnapshot() -> Int {
        lock.lock()
        let count = pendingDecodeCount
        lock.unlock()
        return count
    }

    private func beginPendingDecode() {
        lock.lock()
        pendingDecodeCount += 1
        lock.unlock()
    }

    private func endPendingDecodeWithoutCallback() {
        lock.lock()
        pendingDecodeCount = max(0, pendingDecodeCount - 1)
        lock.unlock()
        decodeSemaphore.signal()
    }

    private func decode(_ sampleBuffer: CMSampleBuffer) throws {
        if CMSampleBufferGetNumSamples(sampleBuffer) == 0 {
            return
        }
        let session = try decompressionSession(for: sampleBuffer)
        var infoFlags = VTDecodeInfoFlags()
        beginPendingDecode()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: VTDecodeFrameFlags(rawValue: 1),
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
        guard decodeStatus == noErr else {
            endPendingDecodeWithoutCallback()
            let hasImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) != nil
            let hasDataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) != nil
            throw AnalyzerError("\(decoderMode.description) decode failed with status \(decodeStatus) (hasImageBuffer=\(hasImageBuffer), hasDataBuffer=\(hasDataBuffer), samples=\(CMSampleBufferGetNumSamples(sampleBuffer)))")
        }
        try throwPendingDecodeError()
    }

    private func decompressionSession(for sampleBuffer: CMSampleBuffer) throws -> VTDecompressionSession {
        if let session {
            return session
        }
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) ?? sourceFormatDescription
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: videoToolboxDecodeOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let createdSession = try makeVideoToolboxDecompressionSession(
            formatDescription: formatDescription,
            callback: &callback,
            mode: decoderMode
        )
        session = createdSession
        return createdSession
    }
}

struct PreparedAnalysis {
    let frames: [AnalysisFrame]
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
    let farFieldRigidShakeSupport: [Float]
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

struct PersistedHostAnalysisCache: Encodable {
    let schemaVersion: Int
    let createdAt: Double
    let clipLabel: String?
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let rangeEndSeconds: Double?
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let eventName: String?
    let frames: [AnalysisFrame]
    let residuals: [Float]?
    let rollMotion: [Float]?
    let pathX: [Float]?
    let pathY: [Float]?
    let pathRoll: [Float]?
    let farFieldPathX: [Float]?
    let farFieldPathY: [Float]?
    let farFieldPathRoll: [Float]?
    let farFieldConfidence: [Float]?
    let footstepPathX: [Float]?
    let footstepPathY: [Float]?
    let footstepPathRoll: [Float]?
    let pathYaw: [Float]?
    let pathPitch: [Float]?
    let pathShearX: [Float]?
    let pathShearY: [Float]?
    let pathPerspectiveX: [Float]?
    let pathPerspectiveY: [Float]?
    let lensBandTopPathX: [Float]?
    let lensBandTopPathY: [Float]?
    let lensBandTopColumnPathX: [Float]?
    let lensBandTopColumnPathY: [Float]?
    let lensBandTopRowPhasePathX: [Float]?
    let lensBandTopRowPhasePathY: [Float]?
    let lensBandTopLocalRollPath: [Float]?
    let lensBandRidgePathX: [Float]?
    let lensBandRidgePathY: [Float]?
    let lensBandRidgeColumnPathX: [Float]?
    let lensBandRidgeColumnPathY: [Float]?
    let lensBandRidgeRowPhasePathX: [Float]?
    let lensBandRidgeRowPhasePathY: [Float]?
    let lensBandRidgeLocalRollPath: [Float]?
    let lensBandMidPathX: [Float]?
    let lensBandMidPathY: [Float]?
    let lensBandMidColumnPathX: [Float]?
    let lensBandMidColumnPathY: [Float]?
    let lensBandMidRowPhasePathX: [Float]?
    let lensBandMidRowPhasePathY: [Float]?
    let lensBandMidLocalRollPath: [Float]?
    let lensBandTopConfidence: [Float]?
    let lensBandRidgeConfidence: [Float]?
    let lensBandMidConfidence: [Float]?
    let lensBandConfidence: [Float]?
    let farFieldRigidShakePathX: [Float]?
    let farFieldRigidShakePathY: [Float]?
    let farFieldRigidShakeSupport: [Float]?
    let farFieldRigidShakeShapeConsistency: [Float]?
    let farFieldRigidShakeForwardBackwardConsistency: [Float]?
    let farFieldMeshRows: Int?
    let farFieldMeshColumns: Int?
    let farFieldMeshPathX: [Float]?
    let farFieldMeshPathY: [Float]?
    let farFieldMeshSupport: [Float]?
    let farFieldMeshDominantWindowFrames: [Float]?
    let farFieldMeshDominantWindowSeconds: [Float]?
    let farFieldMeshDominantSupport: [Float]?
    let farFieldMeshDominantCell: [Int32]?
    let sourceLensShakeRidgePathY: [Float]?
    let sourceLensShakeRidgeSupport: [Float]?
    let sourceLensShakeRidgeLinePathY: [Float]?
    let sourceLensShakeRidgeLineSupport: [Float]?
    let sourceLensShakeLocalBinCount: Int?
    let sourceLensShakeLocalPathX: [Float]?
    let sourceLensShakeLocalPathY: [Float]?
    let sourceLensShakeLocalSupport: [Float]?
    let analysisConfidence: [Float]?
    let warpConfidence: [Float]?
    let acceptedBlockCounts: [Int32]?
    let totalBlockCounts: [Int32]?
    let blurAmounts: [Float]?
    let searchRadiusHitCounts: [Int32]?
    let searchRadiusTotalCounts: [Int32]?
}

struct PersistedHostAnalysisIndex: Codable {
    let schemaVersion: Int
    var entries: [PersistedHostAnalysisIndexEntry]
}

struct PersistedHostAnalysisIndexEntry: Codable {
    let cacheFileName: String
    let createdAt: Double
    let clipLabel: String?
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let rangeEndSeconds: Double?
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frameCount: Int
    let firstFingerprint: String
    let middleFingerprint: String
    let lastFingerprint: String
    let fingerprints: [String]?
    let cacheIdentity: String?
}

struct AnalyzerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Arguments {
    let planPath: URL
    let progress: Bool
}

private let progressOutputLock = NSLock()
private var progressLineActive = false
private var progressLineWidth = 0

func parseArguments() throws -> Arguments {
    let args = Array(CommandLine.arguments.dropFirst())
    var planPath: URL?
    var progress = false
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--plan":
            index += 1
            guard index < args.count else { throw AnalyzerError("--plan requires a path") }
            planPath = URL(fileURLWithPath: args[index])
        case "--progress":
            progress = true
        default:
            throw AnalyzerError("unknown argument: \(arg)")
        }
        index += 1
    }
    guard let planPath else {
        throw AnalyzerError("usage: StabilizerEventAnalyzer --plan PLAN.json [--progress]")
    }
    return Arguments(planPath: planPath, progress: progress)
}

func progress(_ enabled: Bool, _ message: String) {
    guard enabled else {
        return
    }
    progressOutputLock.lock()
    defer {
        progressOutputLock.unlock()
    }
    clearProgressLineLocked()
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func progressUpdate(_ enabled: Bool, _ message: String) {
    guard enabled else {
        return
    }
    progressOutputLock.lock()
    defer {
        progressOutputLock.unlock()
    }
    guard progressOutputIsTerminal else {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        progressLineActive = false
        progressLineWidth = 0
        return
    }
    let paddingCount = max(0, progressLineWidth - message.count)
    let paddedMessage = message + String(repeating: " ", count: paddingCount)
    FileHandle.standardError.write(("\r" + paddedMessage).data(using: .utf8)!)
    progressLineActive = true
    progressLineWidth = max(progressLineWidth, message.count)
}

func finishProgressLine(_ enabled: Bool) {
    guard enabled else {
        return
    }
    progressOutputLock.lock()
    defer {
        progressOutputLock.unlock()
    }
    if progressLineActive {
        FileHandle.standardError.write("\n".data(using: .utf8)!)
        progressLineActive = false
        progressLineWidth = 0
    }
}

private func clearProgressLineLocked() {
    if progressOutputIsTerminal && progressLineActive {
        let clearText = "\r" + String(repeating: " ", count: progressLineWidth) + "\r"
        FileHandle.standardError.write(clearText.data(using: .utf8)!)
        progressLineActive = false
        progressLineWidth = 0
    }
}

private final class AnalyzerFrameProgressReporter {
    private let enabled: Bool
    private let label: String
    private let totalFrameCount: Int
    private let publishEveryFrameCount: Int
    private let startedAt = Date()
    private let lock = NSLock()
    private var completedFrameCount = 0
    private var submittedFrameCount = 0
    private var lastPublishedCompletedFrameCount = 0
    private var lastPublishedSubmittedFrameCount = 0
    private var lastPublishedAt = Date.distantPast

    init(enabled: Bool, label: String, totalFrameCount: Int) {
        self.enabled = enabled
        self.label = label
        self.totalFrameCount = max(1, totalFrameCount)
        self.publishEveryFrameCount = max(1, min(4, totalFrameCount / 100))
    }

    func start() {
        publishAfterAddingFrameCount(0, submittedFrameCount: 0, force: true)
    }

    func submitFrame() {
        publishAfterAddingFrameCount(0, submittedFrameCount: 1, force: false)
    }

    func completeFrame() {
        publishAfterAddingFrameCount(1, submittedFrameCount: 0, force: false)
    }

    func finish() {
        publishAfterAddingFrameCount(0, submittedFrameCount: 0, force: true)
    }

    private func publishAfterAddingFrameCount(_ completedFrameCountDelta: Int, submittedFrameCount submittedFrameCountDelta: Int, force: Bool) {
        guard enabled else {
            return
        }
        let message: String?
        lock.lock()
        completedFrameCount = min(totalFrameCount, completedFrameCount + completedFrameCountDelta)
        submittedFrameCount = min(totalFrameCount, max(submittedFrameCount + submittedFrameCountDelta, completedFrameCount))
        let now = Date()
        let frameDeltaReached = completedFrameCount - lastPublishedCompletedFrameCount >= publishEveryFrameCount
            || submittedFrameCount - lastPublishedSubmittedFrameCount >= publishEveryFrameCount
        let shouldPublish = force
            || completedFrameCount >= totalFrameCount
            || submittedFrameCount >= totalFrameCount
            || (frameDeltaReached && now.timeIntervalSince(lastPublishedAt) >= progressMinimumPublishIntervalSeconds)
        if shouldPublish {
            lastPublishedCompletedFrameCount = completedFrameCount
            lastPublishedSubmittedFrameCount = submittedFrameCount
            lastPublishedAt = now
            message = progressMessageLocked()
        } else {
            message = nil
        }
        lock.unlock()
        if let message {
            progressUpdate(true, message)
        }
    }

    private func progressMessageLocked() -> String {
        let elapsedSeconds = max(0.001, Date().timeIntervalSince(startedAt))
        if submittedFrameCount > completedFrameCount {
            let submittedPercent = min(100.0, (Double(submittedFrameCount) / Double(totalFrameCount)) * 100.0)
            let submitFPS = Double(submittedFrameCount) / elapsedSeconds
            return String(
                format: "progress %@: %d/%d frame(s) complete, %d submitted (%.1f%% submitted, %.1f submit fps)",
                label,
                completedFrameCount,
                totalFrameCount,
                submittedFrameCount,
                submittedPercent,
                submitFPS
            )
        }
        let fps = Double(completedFrameCount) / elapsedSeconds
        let completedPercent = min(100.0, (Double(completedFrameCount) / Double(totalFrameCount)) * 100.0)
        return String(
            format: "progress %@: %d/%d frame(s) (%.1f%%, %.1f fps)",
            label,
            completedFrameCount,
            totalFrameCount,
            completedPercent,
            fps
        )
    }
}

func clamp<T: Comparable>(_ value: T, _ minValue: T, _ maxValue: T) -> T {
    min(max(value, minValue), maxValue)
}

func sampleSize(sourceWidth: Int, sourceHeight: Int, scalePercent: Double) -> (width: Int, height: Int) {
    let normalized = clamp(scalePercent, 10.0, 100.0)
    let scale = normalized / 100.0
    return (
        width: min(max(1, sourceWidth), max(32, Int((Double(max(1, sourceWidth)) * scale).rounded()))),
        height: min(max(1, sourceHeight), max(24, Int((Double(max(1, sourceHeight)) * scale).rounded())))
    )
}

@inline(__always)
func combineFingerprintByte(_ byte: UInt8, into hash: inout UInt64) {
    hash ^= UInt64(byte)
    hash = hash &* 1_099_511_628_211
}

func fingerprintString(hash initialHash: UInt64, byteCount: Int) -> String {
    var hash = initialHash
    var count = UInt64(byteCount)
    for _ in 0..<MemoryLayout<UInt64>.size {
        combineFingerprintByte(UInt8(count & 0xff), into: &hash)
        count >>= 8
    }
    return String(format: "%016llx", hash)
}

func chunkedFingerprintString(partialHashes: UnsafeBufferPointer<UInt64>, byteCount: Int) -> String {
    var hash = fingerprintInitialHash
    for partialHash in partialHashes {
        var value = partialHash
        for _ in 0..<MemoryLayout<UInt64>.size {
            combineFingerprintByte(UInt8(value & 0xff), into: &hash)
            value >>= 8
        }
    }
    return fingerprintString(hash: hash, byteCount: byteCount)
}

private func frameMetrics(fingerprint: String, blurAmount: Float) -> FrameMetrics {
    return FrameMetrics(
        blurAmount: blurAmount,
        fingerprint: fingerprint
    )
}

private struct MetalLumaUniforms {
    let sourceWidth: UInt32
    let sourceHeight: UInt32
    let sampleWidth: UInt32
    let sampleHeight: UInt32
    let lumaMode: UInt32
}

private struct MetalBlockUniforms {
    let centerX: UInt32
    let centerY: UInt32
    let blockWidth: UInt32
    let blockHeight: UInt32
    let width: UInt32
    let height: UInt32
    let radius: UInt32
    let searchStep: UInt32
    let sampleStep: UInt32
    let scoreGridWidth: UInt32
    let scoreGridHeight: UInt32
    let chunkCount: UInt32
}

private struct MetalBlurUniforms {
    let width: UInt32
    let height: UInt32
    let stride: UInt32
    let chunkCount: UInt32
}

private struct MetalShiftResult {
    let dx: Float
    let dy: Float
    let score: Float
    let bestIndex: UInt32
}

private struct MotionBlock {
    let centerX: Float
    let centerY: Float
    let farFieldWeight: Float
}

private struct BlockShift {
    let block: MotionBlock
    let dx: Float
    let dy: Float
    let score: Float
    let searchRadiusHit: Bool
}

private struct FarFieldPlaneMotion {
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

private struct AffineAxisFit {
    let offset: Float
    let xSlope: Float
    let ySlope: Float
    let residual: Float
}

private struct MetalBlurResult {
    let total: UInt32
    let count: UInt32
}

private struct MetalFingerprintResult {
    let value: UInt64
}

private struct MetalFingerprintUniforms {
    let pixelCount: UInt32
    let valueRange: UInt32
    let chunkCount: UInt32
}

private final class MetalMotionWorkspace {
    let width: Int
    let height: Int
    let radius: Int
    let coarseSearchStep: Int
    let coarseScoreGridWidth: Int
    let coarseScoreCount: Int
    let fineRadius: Int
    let fineSearchStep: Int
    let fineScoreGridWidth: Int
    let fineScoreCount: Int
    let maxScoreCount: Int
    let blockCount: Int
    let chunkCount: Int
    let blocks: [MotionBlock]
    let coarseUniformBuffer: MTLBuffer
    let fineUniformBuffer: MTLBuffer

    init(width: Int, height: Int, device: MTLDevice) throws {
        self.width = width
        self.height = height
        let radius = min(maximumMotionSearchRadius, max(localSearchRadius, min(width, height) / 32))
        let coarseSearchStep = width > 1400 || height > 900 ? coarseMotionSearchStep : 1
        let fineRadius = coarseSearchStep <= 1 ? 0 : max(fineMotionSearchRadius, coarseSearchStep / 2)
        let fineSearchStep = fineMotionSearchStep
        let blockSpecs = Self.motionBlocks(width: width, height: height)
        guard !blockSpecs.isEmpty else {
            throw AnalyzerError("could not create Event Analyzer motion blocks")
        }
        let maxSampleCount = blockSpecs.map { spec in
            let sampleStep = Self.motionBlockSampleStep(
                width: spec.width,
                height: spec.height,
                farFieldWeight: spec.farFieldWeight
            )
            let sampleColumns = max(1, (spec.width / sampleStep) + 1)
            let sampleRows = max(1, (spec.height / sampleStep) + 1)
            return sampleColumns * sampleRows
        }.max() ?? 1
        let chunkCount = max(8, min(128, (maxSampleCount + 255) / 256))
        let coarseScoreGridWidth = ((radius * 2) / coarseSearchStep) + 1
        let coarseScoreGridHeight = coarseScoreGridWidth
        let coarseScoreCount = coarseScoreGridWidth * coarseScoreGridHeight
        let fineScoreGridWidth = fineRadius > 0 ? ((fineRadius * 2) / fineSearchStep) + 1 : 0
        let fineScoreGridHeight = fineScoreGridWidth
        let fineScoreCount = fineScoreGridWidth * fineScoreGridHeight
        let maxScoreCount = max(coarseScoreCount, fineScoreCount)
        let coarseUniforms = blockSpecs.map { spec in
            let sampleStep = Self.coarseMotionBlockSampleStep(
                width: spec.width,
                height: spec.height,
                farFieldWeight: spec.farFieldWeight
            )
            return MetalBlockUniforms(
                centerX: UInt32(Int(spec.centerX.rounded())),
                centerY: UInt32(Int(spec.centerY.rounded())),
                blockWidth: UInt32(spec.width),
                blockHeight: UInt32(spec.height),
                width: UInt32(width),
                height: UInt32(height),
                radius: UInt32(radius),
                searchStep: UInt32(coarseSearchStep),
                sampleStep: UInt32(sampleStep),
                scoreGridWidth: UInt32(coarseScoreGridWidth),
                scoreGridHeight: UInt32(coarseScoreGridHeight),
                chunkCount: UInt32(chunkCount)
            )
        }
        let fineUniforms = blockSpecs.map { spec in
            let sampleStep = Self.motionBlockSampleStep(
                width: spec.width,
                height: spec.height,
                farFieldWeight: spec.farFieldWeight
            )
            return MetalBlockUniforms(
                centerX: UInt32(Int(spec.centerX.rounded())),
                centerY: UInt32(Int(spec.centerY.rounded())),
                blockWidth: UInt32(spec.width),
                blockHeight: UInt32(spec.height),
                width: UInt32(width),
                height: UInt32(height),
                radius: UInt32(max(0, fineRadius)),
                searchStep: UInt32(fineSearchStep),
                sampleStep: UInt32(sampleStep),
                scoreGridWidth: UInt32(max(1, fineScoreGridWidth)),
                scoreGridHeight: UInt32(max(1, fineScoreGridHeight)),
                chunkCount: UInt32(chunkCount)
            )
        }
        let blocks = blockSpecs.map {
            MotionBlock(centerX: $0.centerX, centerY: $0.centerY, farFieldWeight: $0.farFieldWeight)
        }
        guard let coarseUniformBuffer = device.makeBuffer(
            bytes: coarseUniforms,
            length: MemoryLayout<MetalBlockUniforms>.stride * coarseUniforms.count,
            options: .storageModeShared
        ),
              let fineUniformBuffer = device.makeBuffer(
            bytes: fineUniforms,
            length: MemoryLayout<MetalBlockUniforms>.stride * fineUniforms.count,
            options: .storageModeShared
        ) else {
            throw AnalyzerError("could not allocate reusable Metal motion search resources")
        }
        self.radius = radius
        self.coarseSearchStep = coarseSearchStep
        self.coarseScoreGridWidth = coarseScoreGridWidth
        self.coarseScoreCount = coarseScoreCount
        self.fineRadius = fineRadius
        self.fineSearchStep = fineSearchStep
        self.fineScoreGridWidth = fineScoreGridWidth
        self.fineScoreCount = fineScoreCount
        self.maxScoreCount = maxScoreCount
        self.blockCount = coarseUniforms.count
        self.chunkCount = chunkCount
        self.blocks = blocks
        self.coarseUniformBuffer = coarseUniformBuffer
        self.fineUniformBuffer = fineUniformBuffer
    }

    private static func motionBlockSampleStep(width: Int, height: Int, farFieldWeight: Float) -> Int {
        let blockShortSide = max(1, min(width, height))
        let farFieldBaseSampleStep = max(1, blockShortSide / 72)
        if farFieldWeight >= denseSampleMotionBlockFarFieldThreshold {
            let highResolutionDetailFloor = blockShortSide >= 128 ? 2 : 1
            return max(highResolutionDetailFloor, (farFieldBaseSampleStep * 3) / 4)
        }
        if farFieldWeight <= farFieldPlaneNearThreshold {
            return max(farFieldBaseSampleStep, blockShortSide / 42)
        }
        return max(farFieldBaseSampleStep, blockShortSide / 56)
    }

    private static func coarseMotionBlockSampleStep(width: Int, height: Int, farFieldWeight: Float) -> Int {
        let fineStep = motionBlockSampleStep(width: width, height: height, farFieldWeight: farFieldWeight)
        let multiplier = farFieldWeight >= denseSampleMotionBlockFarFieldThreshold ? 3 : 4
        return max(fineStep, fineStep * multiplier)
    }

    private static func motionBlocks(width: Int, height: Int) -> [(centerX: Float, centerY: Float, width: Int, height: Int, farFieldWeight: Float)] {
        let horizontalMargin = min(8, max(2, width / 12))
        let verticalMargin = min(6, max(2, height / 10))
        let usableWidth = max(0, width - (horizontalMargin * 2))
        let usableHeight = max(0, height - (verticalMargin * 2))
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

        var blocks: [(centerX: Float, centerY: Float, width: Int, height: Int, farFieldWeight: Float)] = []
        func appendBlock(x0: Int, x1: Int, y0: Int, y1: Int) {
            let blockWidth = x1 - x0
            let blockHeight = y1 - y0
            guard blockWidth >= staggeredMotionBlockMinimumWidth,
                  blockHeight >= staggeredMotionBlockMinimumHeight else {
                return
            }
            let centerY = Float(y0) + (Float(blockHeight) * 0.5)
            blocks.append((
                centerX: Float(x0) + (Float(blockWidth) * 0.5),
                centerY: centerY,
                width: blockWidth,
                height: blockHeight,
                farFieldWeight: farFieldWeight(centerY: centerY, height: height)
            ))
        }

        for row in 0..<rows {
            for column in 0..<columns {
                appendBlock(
                    x0: columnEdges[column].x0,
                    x1: columnEdges[column].x1,
                    y0: rowEdges[row].y0,
                    y1: rowEdges[row].y1
                )
            }
        }

        if columns >= 3 {
            for row in 0..<rows {
                let y0 = rowEdges[row].y0
                let y1 = rowEdges[row].y1
                let centerY = Float(y0) + (Float(y1 - y0) * 0.5)
                guard farFieldWeight(centerY: centerY, height: height) >= staggeredMotionBlockFarFieldThreshold else {
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
            guard farFieldWeight(centerY: centerY, height: height) >= detailMotionBlockFarFieldThreshold else {
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
            guard farFieldWeight(centerY: centerY, height: height) >= verticalDetailMotionBlockFarFieldThreshold else {
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
            guard farFieldWeight(centerY: centerY, height: height) >= attitudeDetailMotionBlockFarFieldThreshold else {
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
            let clampedY0 = max(verticalMargin, min(height - verticalMargin, y0))
            let clampedY1 = max(clampedY0 + staggeredMotionBlockMinimumHeight, min(height - verticalMargin, y1))
            guard clampedY1 <= height - verticalMargin else {
                continue
            }
            let centerY = Float(clampedY0 + clampedY1) * 0.5
            guard farFieldWeight(centerY: centerY, height: height) >= detailMotionBlockFarFieldThreshold else {
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

    private static func farFieldWeight(centerY: Float, height: Int) -> Float {
        let normalizedY = centerY / Float(max(1, height))
        return clamp((0.72 - normalizedY) / 0.48, 0.04, 1.0)
    }

    private static func farFieldPriorityWeight(_ farFieldWeight: Float) -> Float {
        let safeWeight = clamp(farFieldWeight, 0.0, 1.0)
        return max(0.02, powf(safeWeight, 2.2))
    }

    private static func acceptedMotionBlocks(
        _ shifts: [BlockShift],
        global: (dx: Float, dy: Float, score: Float)
    ) -> [BlockShift] {
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
        let clusterCandidates: [BlockShift]
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

    private static func motionBlockWeight(_ shift: BlockShift, scoreReference: Float) -> Float {
        let baseWeight = farFieldPriorityWeight(shift.block.farFieldWeight)
        guard shift.score.isFinite else {
            return baseWeight * 0.05
        }
        let reference = max(0.001, scoreReference.isFinite ? scoreReference : shift.score)
        let scoreQuality = clamp(
            1.0 - ((shift.score - reference) / max(0.020, reference * 1.25)),
            0.15,
            1.0
        )
        let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
        return baseWeight * scoreQuality * searchHeadroom
    }

    private static func weightedAffineAxisFit(
        _ samples: [(x: Float, y: Float, value: Float, weight: Float)]
    ) -> AffineAxisFit? {
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
                    weight: sample.weight * clamp(robustWeight, 0.05, 1.0)
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
        return AffineAxisFit(
            offset: finalFit.offset,
            xSlope: finalFit.xSlope,
            ySlope: finalFit.ySlope,
            residual: median(residuals) ?? 0.0
        )
    }

    private static func solveWeightedAffineAxis(
        _ samples: [(x: Float, y: Float, value: Float, weight: Float)]
    ) -> AffineAxisFit? {
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
        return AffineAxisFit(
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

    private static func affineAxisValue(_ fit: AffineAxisFit, x: Float, y: Float) -> Float {
        fit.offset + (fit.xSlope * x) + (fit.ySlope * y)
    }

    private static func farFieldPlaneMotion(
        shifts: [BlockShift],
        seedDx: Float,
        seedDy: Float,
        width: Int,
        height: Int
    ) -> FarFieldPlaneMotion? {
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
        let halfWidth = Float(max(1, width)) * 0.5
        let halfHeight = Float(max(1, height)) * 0.5
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
            width: width,
            height: height
        )
        let authority = clamp(
            consensusConfidence * (farFieldPlaneAuthorityBase + (farFieldPlaneAuthorityParallaxScale * parallaxSupport)),
            0.0,
            farFieldPlaneMaximumAuthority
        )
        guard authority >= farFieldConsensusConfidenceFloor else {
            return nil
        }
        let yawProxy = affineX.map {
            clamp(($0.xSlope / halfWidth) * consensusConfidence, -maxFarFieldYawPitchProxy, maxFarFieldYawPitchProxy)
        } ?? 0.0
        let pitchProxy = affineY.map {
            clamp(($0.ySlope / halfHeight) * consensusConfidence, -maxFarFieldYawPitchProxy, maxFarFieldYawPitchProxy)
        } ?? 0.0
        let shearX = affineX.map {
            clamp((($0.ySlope + (weightedRoll * halfHeight)) / halfHeight) * consensusConfidence, -maxFarFieldShear, maxFarFieldShear)
        } ?? 0.0
        let shearY = affineY.map {
            clamp((($0.xSlope - (weightedRoll * halfWidth)) / halfWidth) * consensusConfidence, -maxFarFieldShear, maxFarFieldShear)
        } ?? 0.0
        return FarFieldPlaneMotion(
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
        shifts: [BlockShift],
        robustDx: Float,
        robustDy: Float,
        signedRoll: Float,
        width: Int,
        height: Int,
        analysisConfidence: Float
    ) -> (yawProxy: Float, pitchProxy: Float, shearX: Float, shearY: Float, perspectiveX: Float, perspectiveY: Float, confidence: Float) {
        let farFieldShifts = shifts.filter { $0.block.farFieldWeight >= farFieldPlaneBroadThreshold }
        guard farFieldShifts.count >= minimumFarFieldMotionBlocks, analysisConfidence > 0.0 else {
            return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        }

        let halfWidth = Float(max(1, width)) * 0.5
        let halfHeight = Float(max(1, height)) * 0.5
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
            let scoreWeight = clamp(1.0 - (shift.score / 48.0), 0.05, 1.0)
            let weight = farFieldPriorityWeight(shift.block.farFieldWeight) * scoreWeight
            yawCandidates.append((clamp(residualX / halfWidth, -maxFarFieldYawPitchProxy, maxFarFieldYawPitchProxy), weight))
            pitchCandidates.append((clamp(residualY / halfHeight, -maxFarFieldYawPitchProxy, maxFarFieldYawPitchProxy), weight))
            if abs(y) > halfHeight * 0.15 {
                shearXCandidates.append((clamp(residualX / y, -maxFarFieldShear, maxFarFieldShear), weight))
            }
            if abs(x) > halfWidth * 0.15 {
                shearYCandidates.append((clamp(residualY / x, -maxFarFieldShear, maxFarFieldShear), weight))
            }
            let radialDenominator = max(1.0, (x * x) + (y * y))
            let radialResidual = (residualX * x) + (residualY * y)
            perspectiveXCandidates.append((clamp((radialResidual * x) / (radialDenominator * halfWidth), -maxFarFieldPerspective, maxFarFieldPerspective), weight))
            perspectiveYCandidates.append((clamp((radialResidual * y) / (radialDenominator * halfHeight), -maxFarFieldPerspective, maxFarFieldPerspective), weight))
        }

        let farFieldCoverage = Float(farFieldShifts.count) / Float(max(1, shifts.count))
        let consensusConfidence = farFieldConsensusConfidence(
            farFieldShifts: farFieldShifts,
            allShiftCount: shifts.count,
            width: width,
            height: height
        )
        let confidence = max(
            clamp(analysisConfidence * farFieldCoverage, 0.0, 1.0),
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
        shifts: [BlockShift],
        width: Int,
        height: Int,
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
                let normalizedY = shift.block.centerY / Float(max(1, height))
                let normalizedX = shift.block.centerX / Float(max(1, width))
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
                let scoreQuality = clamp(1.0 - ((shift.score - scoreReference) / max(0.020, scoreReference * 1.25)), 0.10, 1.0)
                let searchHeadroom: Float = shift.searchRadiusHit ? 0.55 : 1.0
                let weight = farFieldPriorityWeight(shift.block.farFieldWeight) * scoreQuality * searchHeadroom
                return ((shift.dx, weight), (shift.dy, weight))
            }
            let dx = weightedMedian(weighted.map(\.dx)) ?? 0.0
            let dy = weightedMedian(weighted.map(\.dy)) ?? 0.0
            let coherencePixels = farFieldConsensusCoherencePixels(width: width, height: height)
            let medianDistance = median(candidates.map { hypotf($0.dx - dx, $0.dy - dy) }) ?? coherencePixels
            let coherence = clamp(1.0 - (medianDistance / coherencePixels), 0.0, 1.0)
            let coverage = confidenceRamp(Float(candidates.count), start: Float(minimumFarFieldMotionBlocks), full: Float(minimumFarFieldMotionBlocks * 3))
            return (dx, dy, clamp(analysisConfidence * coherence * coverage, 0.0, 1.0))
        }
        func localRoll(_ minY: Float, _ maxY: Float, bandMotion: (dx: Float, dy: Float, support: Float)) -> Float {
            let centerY = (minY + maxY) * 0.5 * Float(max(1, height))
            let centerX = Float(max(1, width)) * 0.5
            let candidates = shifts.compactMap { shift -> (value: Float, weight: Float)? in
                let normalizedY = shift.block.centerY / Float(max(1, height))
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
                let scoreQuality = clamp(1.0 - (shift.score * 1.8), 0.05, 1.0)
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
                let normalizedY = shift.block.centerY / Float(max(1, height))
                guard normalizedY >= 0.16,
                      normalizedY <= 0.30,
                      shift.block.farFieldWeight >= farFieldPlaneBroadThreshold,
                      shift.score.isFinite,
                      shift.dy.isFinite
                else {
                    return nil
                }
                let residual = shift.dy - bandMotion.dy
                let scoreQuality = clamp(1.0 - (shift.score * 1.8), 0.05, 1.0)
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
        farFieldShifts: [BlockShift],
        allShiftCount: Int,
        width: Int,
        height: Int
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
        let medianDistance = median(farFieldShifts.map {
            hypotf($0.dx - weightedDx, $0.dy - weightedDy)
        }) ?? farFieldConsensusCoherencePixels(width: width, height: height)
        let coherencePixels = farFieldConsensusCoherencePixels(width: width, height: height)
        let coherence = clamp(
            1.0 - (medianDistance / coherencePixels),
            0.0,
            1.0
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
        let searchHeadroom = farFieldShifts.isEmpty ? Float(0.0) : (
            Float(farFieldShifts.filter { !$0.searchRadiusHit }.count) / Float(farFieldShifts.count)
        )
        let saturationSupport = clamp(0.35 + (searchHeadroom * 0.65), 0.0, 1.0)
        return clamp(weightSupport * coherence * max(coverageSupport, 0.25) * saturationSupport, 0.0, 1.0)
    }

    private static func farFieldConsensusCoherencePixels(width: Int, height: Int) -> Float {
        max(6.0, Float(max(1, min(width, height))) * farFieldConsensusCoherenceFrameFraction)
    }

    private static func farFieldConsensusWeight(_ shift: BlockShift) -> Float {
        let baseWeight = farFieldPriorityWeight(shift.block.farFieldWeight)
        guard shift.score.isFinite else {
            return baseWeight * 0.05
        }
        let scoreQuality = clamp(1.0 - (shift.score / 48.0), 0.05, 1.0)
        let searchHeadroom: Float = shift.searchRadiusHit ? 0.65 : 1.0
        return baseWeight * scoreQuality * searchHeadroom
    }

    private static func confidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
        guard full > start else {
            return value >= full ? 1.0 : 0.0
        }
        return clamp((value - start) / (full - start), 0.0, 1.0)
    }

    private static func average(_ values: [Float]) -> Float {
        guard !values.isEmpty else {
            return 0.0
        }
        return values.reduce(Float(0.0), +) / Float(values.count)
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

    var partialElementCount: Int {
        maxScoreCount * blockCount * chunkCount
    }

    func resolveMotion(resultBuffer: MTLBuffer, lumaFormat: LumaBufferFormat) -> PairMotion {
        let results = UnsafeBufferPointer(
            start: resultBuffer.contents().assumingMemoryBound(to: MetalShiftResult.self),
            count: blockCount
        )
        let blockShifts = zip(blocks, results).map { block, result in
            BlockShift(
                block: block,
                dx: result.dx,
                dy: result.dy,
                score: result.score * lumaFormat.normalizedResidualScale,
                searchRadiusHit: abs(result.dx) >= Float(radius) || abs(result.dy) >= Float(radius)
            )
        }
        let finiteScores = blockShifts.map(\.score).filter(\.isFinite)
        let globalDx = Self.weightedMedian(blockShifts.map { ($0.dx, Self.farFieldPriorityWeight($0.block.farFieldWeight)) }) ?? 0.0
        let globalDy = Self.weightedMedian(blockShifts.map { ($0.dy, Self.farFieldPriorityWeight($0.block.farFieldWeight)) }) ?? 0.0
        let globalScore = median(finiteScores) ?? 0.0
        let acceptedBlocks = Self.acceptedMotionBlocks(blockShifts, global: (globalDx, globalDy, globalScore))
        let motionBlocksForModel = acceptedBlocks.count >= minimumAcceptedMotionBlocks ? acceptedBlocks : blockShifts
        let modelScoreReference = median(motionBlocksForModel.map(\.score).filter(\.isFinite)) ?? globalScore
        let robustDx = Self.weightedMedian(motionBlocksForModel.map {
            ($0.dx, Self.motionBlockWeight($0, scoreReference: modelScoreReference))
        }) ?? globalDx
        let robustDy = Self.weightedMedian(motionBlocksForModel.map {
            ($0.dy, Self.motionBlockWeight($0, scoreReference: modelScoreReference))
        }) ?? globalDy
        let halfWidth = Float(max(1, width)) * 0.5
        let halfHeight = Float(max(1, height)) * 0.5
        let farFieldPlane = Self.farFieldPlaneMotion(
            shifts: motionBlocksForModel,
            seedDx: robustDx,
            seedDy: robustDy,
            width: width,
            height: height
        )
        let farFieldAuthority = farFieldPlane?.authority ?? 0.0
        let modelDx = farFieldPlane.map {
            robustDx + (($0.dx - robustDx) * farFieldAuthority)
        } ?? robustDx
        let modelDy = farFieldPlane.map {
            robustDy + (($0.dy - robustDy) * farFieldAuthority)
        } ?? robustDy
        let rollCandidates = motionBlocksForModel.compactMap { shift -> Float? in
            let x = shift.block.centerX - halfWidth
            let y = shift.block.centerY - halfHeight
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
        let farFieldAgreement = motionBlocksForModel.isEmpty ? 0.0 : Self.average(motionBlocksForModel.map(\.block.farFieldWeight))
        let blockAgreement = blockShifts.isEmpty
            ? 0.0
            : (Float(acceptedCount) / Float(blockShifts.count)) * clamp(farFieldAgreement, 0.35, 1.0)
        let scoreConfidence = clamp(1.0 - (modelScoreReference / 48.0), 0.0, 1.0)
        let analysisConfidence = clamp(max(blockAgreement * scoreConfidence, farFieldAuthority * scoreConfidence), 0.0, 1.0)
        let warpMotion = Self.farFieldWarpMotion(
            shifts: motionBlocksForModel,
            robustDx: modelDx,
            robustDy: modelDy,
            signedRoll: signedRoll,
            width: width,
            height: height,
            analysisConfidence: analysisConfidence
        )
        let lensBandMotion = Self.farFieldLensBandMotion(
            shifts: motionBlocksForModel,
            width: width,
            height: height,
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
        return PairMotion(
            dx: modelDx,
            dy: modelDy,
            residual: modelScoreReference,
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
            totalBlockCount: Int32(blockShifts.count),
            searchRadiusHitCount: Int32(blockShifts.filter(\.searchRadiusHit).count),
            searchRadiusTotalCount: Int32(blockShifts.count)
        )
    }
}

private struct MetalFrameSlot {
    let lumaBuffer: MTLBuffer
    let blurResultBuffer: MTLBuffer
    let fingerprintResultBuffer: MTLBuffer
    let partialSumBuffer: MTLBuffer
    let partialCountBuffer: MTLBuffer
    let coarseResultBuffer: MTLBuffer
    let resultBuffer: MTLBuffer
}

private struct MetalLumaSource {
    let pixelFormat: MTLPixelFormat
    let mode: UInt32
    let format: LumaBufferFormat
    let description: String
}

private struct MetalEncodedFrame {
    let commandBuffer: MTLCommandBuffer
    let outputBuffer: MTLBuffer
    let sampleWidth: Int
    let sampleHeight: Int
    let blurResultBuffer: MTLBuffer
    let blurChunkCount: Int
    let fingerprintResultBuffer: MTLBuffer
    let fingerprintByteCount: Int
    let resultBuffer: MTLBuffer?
    let motionWorkspace: MetalMotionWorkspace?
    let lumaFormat: LumaBufferFormat
}

private final class MetalAnalysisSharedState {
    fileprivate static let sharedResult: Result<MetalAnalysisSharedState, Error> = Result {
        try MetalAnalysisSharedState()
    }

    let device: MTLDevice
    let lumaPipelineState: MTLComputePipelineState
    let blurPartialPipelineState: MTLComputePipelineState
    let fingerprintPipelineState: MTLComputePipelineState
    let blockScorePartialPipelineState: MTLComputePipelineState
    let blockScoreFinePartialPipelineState: MTLComputePipelineState
    let blockScoreResolvePipelineState: MTLComputePipelineState
    let blockScoreFineResolvePipelineState: MTLComputePipelineState

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw AnalyzerError("Metal analysis device unavailable; Event analysis requires GPU resources")
        }
        let library = try Self.loadPrecompiledLibrary(device: device)
        guard let lumaFunction = library.makeFunction(name: "stabilizer_luma_sample"),
              let blurPartialFunction = library.makeFunction(name: "stabilizer_blur_partials"),
              let fingerprintFunction = library.makeFunction(name: "stabilizer_fingerprint"),
              let blockScorePartialFunction = library.makeFunction(name: "stabilizer_block_score_partials"),
              let blockScoreFinePartialFunction = library.makeFunction(name: "stabilizer_block_score_fine_partials"),
              let blockScoreResolveFunction = library.makeFunction(name: "stabilizer_block_score_resolve"),
              let blockScoreFineResolveFunction = library.makeFunction(name: "stabilizer_block_score_fine_resolve") else {
            throw AnalyzerError("Metal analysis kernels were not found")
        }
        self.device = device
        self.lumaPipelineState = try device.makeComputePipelineState(function: lumaFunction)
        self.blurPartialPipelineState = try device.makeComputePipelineState(function: blurPartialFunction)
        self.fingerprintPipelineState = try device.makeComputePipelineState(function: fingerprintFunction)
        self.blockScorePartialPipelineState = try device.makeComputePipelineState(function: blockScorePartialFunction)
        self.blockScoreFinePartialPipelineState = try device.makeComputePipelineState(function: blockScoreFinePartialFunction)
        self.blockScoreResolvePipelineState = try device.makeComputePipelineState(function: blockScoreResolveFunction)
        self.blockScoreFineResolvePipelineState = try device.makeComputePipelineState(function: blockScoreFineResolveFunction)
    }

    private static func loadPrecompiledLibrary(device: MTLDevice) throws -> MTLLibrary {
        let environment = ProcessInfo.processInfo.environment
        guard let metallibPath = environment["STABILIZER_ANALYZER_METALLIB"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !metallibPath.isEmpty else {
            throw AnalyzerError("STABILIZER_ANALYZER_METALLIB is required; run Event analysis through analyze_event_assets.py so Metal kernels are precompiled before analyzer startup")
        }
        guard FileManager.default.fileExists(atPath: metallibPath) else {
            throw AnalyzerError("precompiled Metal analyzer library was not found at \(metallibPath)")
        }
        do {
            return try device.makeLibrary(URL: URL(fileURLWithPath: metallibPath))
        } catch {
            throw AnalyzerError("could not load precompiled Metal analyzer library at \(metallibPath): \(error.localizedDescription)")
        }
    }
}

final class MetalAnalysisContext {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let lumaPipelineState: MTLComputePipelineState
    private let blurPartialPipelineState: MTLComputePipelineState
    private let fingerprintPipelineState: MTLComputePipelineState
    private let blockScorePartialPipelineState: MTLComputePipelineState
    private let blockScoreFinePartialPipelineState: MTLComputePipelineState
    private let blockScoreResolvePipelineState: MTLComputePipelineState
    private let blockScoreFineResolvePipelineState: MTLComputePipelineState
    private var motionWorkspace: MetalMotionWorkspace?

    var deviceName: String { device.name }

    init() throws {
        let sharedState = try MetalAnalysisSharedState.sharedResult.get()
        let device = sharedState.device
        guard let commandQueue = device.makeCommandQueue() else {
            throw AnalyzerError("Metal analysis command queue unavailable")
        }
        var textureCache: CVMetalTextureCache?
        let textureCacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard textureCacheStatus == kCVReturnSuccess, let textureCache else {
            throw AnalyzerError("Metal analysis texture cache unavailable: CVMetalTextureCacheCreate returned \(textureCacheStatus)")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = textureCache
        self.lumaPipelineState = sharedState.lumaPipelineState
        self.blurPartialPipelineState = sharedState.blurPartialPipelineState
        self.fingerprintPipelineState = sharedState.fingerprintPipelineState
        self.blockScorePartialPipelineState = sharedState.blockScorePartialPipelineState
        self.blockScoreFinePartialPipelineState = sharedState.blockScoreFinePartialPipelineState
        self.blockScoreResolvePipelineState = sharedState.blockScoreResolvePipelineState
        self.blockScoreFineResolvePipelineState = sharedState.blockScoreFineResolvePipelineState
    }

    fileprivate func makeFrameSlots(count: Int, pixelCount: Int, width: Int, height: Int) throws -> [MetalFrameSlot] {
        let workspace = try workspaceForMotion(width: width, height: height)
        let lumaLength = pixelCount * MemoryLayout<UInt16>.stride
        let blurResultLength = MemoryLayout<MetalBlurResult>.stride * metalBlurChunkCount
        let fingerprintResultLength = MemoryLayout<MetalFingerprintResult>.stride * fingerprintChunkCount
        let partialLength = MemoryLayout<UInt32>.stride * workspace.partialElementCount
        let resultLength = MemoryLayout<MetalShiftResult>.stride * workspace.blockCount
        let sharedOptions: MTLResourceOptions = .storageModeShared
        let gpuOnlyOptions: MTLResourceOptions = .storageModePrivate
        var slots: [MetalFrameSlot] = []
        slots.reserveCapacity(count)
        for _ in 0..<count {
            guard let lumaBuffer = device.makeBuffer(length: lumaLength, options: sharedOptions),
                  let blurResultBuffer = device.makeBuffer(length: blurResultLength, options: sharedOptions),
                  let fingerprintResultBuffer = device.makeBuffer(length: fingerprintResultLength, options: sharedOptions),
                  let partialSumBuffer = device.makeBuffer(length: partialLength, options: gpuOnlyOptions),
                  let partialCountBuffer = device.makeBuffer(length: partialLength, options: gpuOnlyOptions),
                  let coarseResultBuffer = device.makeBuffer(length: resultLength, options: sharedOptions),
                  let resultBuffer = device.makeBuffer(length: resultLength, options: sharedOptions) else {
                throw AnalyzerError("could not allocate reusable Metal frame analysis buffers")
            }
            slots.append(MetalFrameSlot(
                lumaBuffer: lumaBuffer,
                blurResultBuffer: blurResultBuffer,
                fingerprintResultBuffer: fingerprintResultBuffer,
                partialSumBuffer: partialSumBuffer,
                partialCountBuffer: partialCountBuffer,
                coarseResultBuffer: coarseResultBuffer,
                resultBuffer: resultBuffer
            ))
        }
        return slots
    }

    fileprivate func encodeFrame(
        from pixelBuffer: CVPixelBuffer,
        sampleWidth: Int,
        sampleHeight: Int,
        outputBuffer: MTLBuffer,
        blurResultBuffer: MTLBuffer,
        fingerprintResultBuffer: MTLBuffer,
        partialSumBuffer: MTLBuffer,
        partialCountBuffer: MTLBuffer,
        coarseResultBuffer: MTLBuffer,
        resultBuffer: MTLBuffer,
        previousBuffer: MTLBuffer?
    ) throws -> MetalEncodedFrame {
        let pixelCount = sampleWidth * sampleHeight
        guard outputBuffer.length >= pixelCount * MemoryLayout<UInt16>.stride else {
            throw AnalyzerError("reusable Metal luma output buffer was too small")
        }
        let lumaSource = try Self.lumaSource(for: pixelBuffer)
        let sourceWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let sourceHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        var cvTexture: CVMetalTexture?
        let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            lumaSource.pixelFormat,
            sourceWidth,
            sourceHeight,
            0,
            &cvTexture
        )
        guard textureStatus == kCVReturnSuccess,
              let cvTexture,
              let sourceTexture = CVMetalTextureGetTexture(cvTexture),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AnalyzerError("could not allocate Metal luma sampling resources")
        }
        var uniforms = MetalLumaUniforms(
            sourceWidth: UInt32(sourceWidth),
            sourceHeight: UInt32(sourceHeight),
            sampleWidth: UInt32(sampleWidth),
            sampleHeight: UInt32(sampleHeight),
            lumaMode: lumaSource.mode
        )
        encoder.setComputePipelineState(lumaPipelineState)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<MetalLumaUniforms>.stride, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: sampleWidth, height: sampleHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        encoder.endEncoding()

        guard let blurEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AnalyzerError("could not allocate Metal blur metric encoder")
        }
        var blurUniforms = MetalBlurUniforms(
            width: UInt32(sampleWidth),
            height: UInt32(sampleHeight),
            stride: UInt32(max(1, min(sampleWidth, sampleHeight) / 160)),
            chunkCount: UInt32(metalBlurChunkCount)
        )
        blurEncoder.setComputePipelineState(blurPartialPipelineState)
        blurEncoder.setBuffer(outputBuffer, offset: 0, index: 0)
        blurEncoder.setBuffer(blurResultBuffer, offset: 0, index: 1)
        blurEncoder.setBytes(&blurUniforms, length: MemoryLayout<MetalBlurUniforms>.stride, index: 2)
        blurEncoder.dispatchThreads(
            MTLSize(width: metalBlurChunkCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(64, metalBlurChunkCount), height: 1, depth: 1)
        )
        blurEncoder.endEncoding()

        guard let fingerprintEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AnalyzerError("could not allocate Metal fingerprint encoder")
        }
        var fingerprintUniforms = MetalFingerprintUniforms(
            pixelCount: UInt32(pixelCount),
            valueRange: UInt32(max(1, lumaSource.format.valueRange)),
            chunkCount: UInt32(fingerprintChunkCount)
        )
        fingerprintEncoder.setComputePipelineState(fingerprintPipelineState)
        fingerprintEncoder.setBuffer(outputBuffer, offset: 0, index: 0)
        fingerprintEncoder.setBuffer(fingerprintResultBuffer, offset: 0, index: 1)
        fingerprintEncoder.setBytes(&fingerprintUniforms, length: MemoryLayout<MetalFingerprintUniforms>.stride, index: 2)
        fingerprintEncoder.dispatchThreads(
            MTLSize(width: fingerprintChunkCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(64, fingerprintChunkCount), height: 1, depth: 1)
        )
        fingerprintEncoder.endEncoding()

        let activeMotionWorkspace: MetalMotionWorkspace?
        if let previousBuffer {
            let workspace = try workspaceForMotion(width: sampleWidth, height: sampleHeight)
            guard let motionEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw AnalyzerError("could not allocate Metal block motion encoder")
            }
            motionEncoder.setComputePipelineState(blockScorePartialPipelineState)
            motionEncoder.setBuffer(previousBuffer, offset: 0, index: 0)
            motionEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
            motionEncoder.setBuffer(partialSumBuffer, offset: 0, index: 2)
            motionEncoder.setBuffer(partialCountBuffer, offset: 0, index: 3)
            motionEncoder.setBuffer(workspace.coarseUniformBuffer, offset: 0, index: 4)
            motionEncoder.dispatchThreads(
                MTLSize(width: workspace.coarseScoreCount, height: workspace.blockCount, depth: workspace.chunkCount),
                threadsPerThreadgroup: MTLSize(width: min(64, workspace.coarseScoreCount), height: 1, depth: 1)
            )
            motionEncoder.endEncoding()

            guard let resolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw AnalyzerError("could not allocate Metal block motion resolve encoder")
            }
            var chunkCount = UInt32(workspace.chunkCount)
            resolveEncoder.setComputePipelineState(blockScoreResolvePipelineState)
            resolveEncoder.setBuffer(partialSumBuffer, offset: 0, index: 0)
            resolveEncoder.setBuffer(partialCountBuffer, offset: 0, index: 1)
            resolveEncoder.setBuffer(coarseResultBuffer, offset: 0, index: 2)
            resolveEncoder.setBuffer(workspace.coarseUniformBuffer, offset: 0, index: 3)
            resolveEncoder.setBytes(&chunkCount, length: MemoryLayout<UInt32>.stride, index: 4)
            resolveEncoder.dispatchThreads(
                MTLSize(width: workspace.blockCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(32, workspace.blockCount), height: 1, depth: 1)
            )
            resolveEncoder.endEncoding()

            if workspace.fineScoreCount > 0 {
                guard let fineEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    throw AnalyzerError("could not allocate Metal fine block motion encoder")
                }
                fineEncoder.setComputePipelineState(blockScoreFinePartialPipelineState)
                fineEncoder.setBuffer(previousBuffer, offset: 0, index: 0)
                fineEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
                fineEncoder.setBuffer(partialSumBuffer, offset: 0, index: 2)
                fineEncoder.setBuffer(partialCountBuffer, offset: 0, index: 3)
                fineEncoder.setBuffer(workspace.fineUniformBuffer, offset: 0, index: 4)
                fineEncoder.setBuffer(coarseResultBuffer, offset: 0, index: 5)
                fineEncoder.dispatchThreads(
                    MTLSize(width: workspace.fineScoreCount, height: workspace.blockCount, depth: workspace.chunkCount),
                    threadsPerThreadgroup: MTLSize(width: min(64, workspace.fineScoreCount), height: 1, depth: 1)
                )
                fineEncoder.endEncoding()

                guard let fineResolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    throw AnalyzerError("could not allocate Metal fine block motion resolve encoder")
                }
                fineResolveEncoder.setComputePipelineState(blockScoreFineResolvePipelineState)
                fineResolveEncoder.setBuffer(partialSumBuffer, offset: 0, index: 0)
                fineResolveEncoder.setBuffer(partialCountBuffer, offset: 0, index: 1)
                fineResolveEncoder.setBuffer(resultBuffer, offset: 0, index: 2)
                fineResolveEncoder.setBuffer(workspace.fineUniformBuffer, offset: 0, index: 3)
                fineResolveEncoder.setBytes(&chunkCount, length: MemoryLayout<UInt32>.stride, index: 4)
                fineResolveEncoder.setBuffer(coarseResultBuffer, offset: 0, index: 5)
                fineResolveEncoder.dispatchThreads(
                    MTLSize(width: workspace.blockCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: min(32, workspace.blockCount), height: 1, depth: 1)
                )
                fineResolveEncoder.endEncoding()
            } else {
                guard let copyEncoder = commandBuffer.makeBlitCommandEncoder() else {
                    throw AnalyzerError("could not allocate Metal motion result copy encoder")
                }
                copyEncoder.copy(
                    from: coarseResultBuffer,
                    sourceOffset: 0,
                    to: resultBuffer,
                    destinationOffset: 0,
                    size: MemoryLayout<MetalShiftResult>.stride * workspace.blockCount
                )
                copyEncoder.endEncoding()
            }
            activeMotionWorkspace = workspace
        } else {
            activeMotionWorkspace = nil
        }

        commandBuffer.commit()
        return MetalEncodedFrame(
            commandBuffer: commandBuffer,
            outputBuffer: outputBuffer,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            blurResultBuffer: blurResultBuffer,
            blurChunkCount: metalBlurChunkCount,
            fingerprintResultBuffer: fingerprintResultBuffer,
            fingerprintByteCount: pixelCount,
            resultBuffer: previousBuffer == nil ? nil : resultBuffer,
            motionWorkspace: activeMotionWorkspace,
            lumaFormat: lumaSource.format
        )
    }

    fileprivate func completeFrame(
        _ encodedFrame: MetalEncodedFrame
    ) throws -> (metrics: FrameMetrics, motion: PairMotion?, ridgeLineProfile: RidgeLineProfile) {
        encodedFrame.commandBuffer.waitUntilCompleted()
        let stage = encodedFrame.motionWorkspace == nil ? "luma sampling, blur, and fingerprint" : "luma sampling, blur, fingerprint, and block motion search"
        try Self.validate(commandBuffer: encodedFrame.commandBuffer, stage: stage)
        let blurAmount = Self.blurAmount(
            resultBuffer: encodedFrame.blurResultBuffer,
            chunkCount: encodedFrame.blurChunkCount,
            lumaFormat: encodedFrame.lumaFormat
        )
        let fingerprintHashes = UnsafeBufferPointer(
            start: encodedFrame.fingerprintResultBuffer.contents().assumingMemoryBound(to: UInt64.self),
            count: fingerprintChunkCount
        )
        let fingerprint = chunkedFingerprintString(partialHashes: fingerprintHashes, byteCount: encodedFrame.fingerprintByteCount)
        let metrics = frameMetrics(
            fingerprint: fingerprint,
            blurAmount: blurAmount
        )
        let ridgeLineProfile = Self.ridgeLineProfile(
            outputBuffer: encodedFrame.outputBuffer,
            width: encodedFrame.sampleWidth,
            height: encodedFrame.sampleHeight,
            lumaFormat: encodedFrame.lumaFormat
        )
        let motion: PairMotion?
        if let motionWorkspace = encodedFrame.motionWorkspace,
           let resultBuffer = encodedFrame.resultBuffer {
            motion = motionWorkspace.resolveMotion(resultBuffer: resultBuffer, lumaFormat: encodedFrame.lumaFormat)
        } else {
            motion = nil
        }
        return (metrics, motion, ridgeLineProfile)
    }

    private static func ridgeLineProfile(
        outputBuffer: MTLBuffer,
        width: Int,
        height: Int,
        lumaFormat: LumaBufferFormat
    ) -> RidgeLineProfile {
        let rowStart = max(2, Int((Float(height) * 0.12).rounded(.down)))
        let rowEnd = min(height - 3, Int((Float(height) * 0.36).rounded(.up)))
        let colStart = max(2, Int((Float(width) * 0.08).rounded(.down)))
        let colEnd = min(width - 3, Int((Float(width) * 0.92).rounded(.up)))
        guard rowEnd > rowStart + 6, colEnd > colStart + 8 else {
            return RidgeLineProfile(values: [], support: 0.0)
        }
        let pixels = UnsafeBufferPointer(
            start: outputBuffer.contents().assumingMemoryBound(to: UInt16.self),
            count: max(0, width * height)
        )
        let xStride = max(1, width / 420)
        let valueScale = Float(max(1, lumaFormat.valueRange))
        var values: [Float] = []
        values.reserveCapacity(rowEnd - rowStart + 1)
        var strengthTotal: Float = 0.0
        for y in rowStart...rowEnd {
            var rowStrength: Float = 0.0
            var sampleCount = 0
            var x = colStart
            while x <= colEnd {
                let above = Float(pixels[(y - 1) * width + x])
                let below = Float(pixels[(y + 1) * width + x])
                rowStrength += abs(below - above) / valueScale
                sampleCount += 1
                x += xStride
            }
            let normalized = sampleCount > 0 ? rowStrength / Float(sampleCount) : 0.0
            values.append(normalized)
            strengthTotal += normalized
        }
        guard !values.isEmpty else {
            return RidgeLineProfile(values: [], support: 0.0)
        }
        let meanStrength = strengthTotal / Float(values.count)
        let centered = values.map { max(0.0, $0 - (meanStrength * 0.55)) }
        let peak = centered.max() ?? 0.0
        let centeredMean = centered.reduce(Float(0.0), +) / Float(max(1, centered.count))
        let contrast = peak - centeredMean
        let support = profileConfidenceRamp(contrast, start: 0.0025, full: 0.018)
            * profileConfidenceRamp(peak, start: 0.006, full: 0.040)
        return RidgeLineProfile(values: centered, support: clamp(support, 0.0, 1.0))
    }

    fileprivate static func ridgeLineMotion(previous: RidgeLineProfile?, current: RidgeLineProfile) -> RidgeLineMotion {
        guard let previous,
              previous.support > 0.0,
              current.support > 0.0,
              previous.values.count == current.values.count,
              previous.values.count >= 12
        else {
            return .zero
        }
        let radius = min(36, max(3, previous.values.count / 4))
        var bestShift = 0
        var bestScore = Float.greatestFiniteMagnitude
        var scores: [(shift: Int, score: Float)] = []
        scores.reserveCapacity((radius * 2) + 1)
        for shift in -radius...radius {
            var total: Float = 0.0
            var weightTotal: Float = 0.0
            for index in 0..<previous.values.count {
                let currentIndex = index + shift
                guard currentIndex >= 0, currentIndex < current.values.count else {
                    continue
                }
                let weight = max(previous.values[index], current.values[currentIndex])
                guard weight > 0.0 else {
                    continue
                }
                total += abs(previous.values[index] - current.values[currentIndex]) * (0.25 + weight)
                weightTotal += 0.25 + weight
            }
            guard weightTotal > 0.0 else {
                continue
            }
            let score = total / weightTotal
            scores.append((shift, score))
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        guard scores.count >= 5, bestScore.isFinite else {
            return .zero
        }
        let scoreMedian = median(scores.map(\.score)) ?? bestScore
        let separation = max(0.0, scoreMedian - bestScore)
        let support = min(previous.support, current.support)
            * profileConfidenceRamp(separation, start: 0.0005, full: 0.006)
            * profileConfidenceRamp(abs(Float(bestShift)), start: 0.10, full: 1.50)
        guard support > 0.0 else {
            return .zero
        }
        return RidgeLineMotion(dy: Float(bestShift), support: clamp(support, 0.0, 1.0))
    }

    private static func profileConfidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
        guard full > start else {
            return value >= full ? 1.0 : 0.0
        }
        return clamp((value - start) / (full - start), 0.0, 1.0)
    }

    private static func blurAmount(resultBuffer: MTLBuffer, chunkCount: Int, lumaFormat: LumaBufferFormat) -> Float {
        let results = UnsafeBufferPointer(
            start: resultBuffer.contents().assumingMemoryBound(to: MetalBlurResult.self),
            count: chunkCount
        )
        var total: UInt64 = 0
        var count: UInt64 = 0
        for result in results {
            total += UInt64(result.total)
            count += UInt64(result.count)
        }
        guard count > 0 else {
            return 0.0
        }
        return (Float(total) / Float(count)) * (255.0 / Float(max(1, lumaFormat.valueRange)))
    }

    fileprivate func flushTextureCache() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    private func workspaceForMotion(width: Int, height: Int) throws -> MetalMotionWorkspace {
        if let motionWorkspace,
           motionWorkspace.width == width,
           motionWorkspace.height == height {
            return motionWorkspace
        }
        let workspace = try MetalMotionWorkspace(width: width, height: height, device: device)
        motionWorkspace = workspace
        return workspace
    }

    private static func validate(commandBuffer: MTLCommandBuffer, stage: String) throws {
        if commandBuffer.status == .error {
            throw AnalyzerError("Metal \(stage) failed: \(commandBuffer.error?.localizedDescription ?? "unknown error")")
        }
    }

    private static func lumaSource(for pixelBuffer: CVPixelBuffer) throws -> MetalLumaSource {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1 else {
            throw AnalyzerError("VideoToolbox did not provide a planar YUV frame for Metal luma sampling")
        }
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange:
            return MetalLumaSource(pixelFormat: .r8Unorm, mode: 0, format: LumaBufferFormat(valueRange: 255), description: "8-bit video-range Y")
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr8BiPlanarFullRange:
            return MetalLumaSource(pixelFormat: .r8Unorm, mode: 0, format: LumaBufferFormat(valueRange: 255), description: "8-bit full-range Y")
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange:
            return MetalLumaSource(pixelFormat: .r16Unorm, mode: 1, format: LumaBufferFormat(valueRange: 1023), description: "10-bit video-range Y")
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
            return MetalLumaSource(pixelFormat: .r16Unorm, mode: 1, format: LumaBufferFormat(valueRange: 1023), description: "10-bit full-range Y")
        default:
            let code = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let text = fourCharacterCodeString(code)
            throw AnalyzerError("unsupported VideoToolbox pixel format \(text); Event analysis requires native YUV frames for Metal luma sampling")
        }
    }

    fileprivate static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LumaUniforms {
        uint sourceWidth;
        uint sourceHeight;
        uint sampleWidth;
        uint sampleHeight;
        uint lumaMode;
    };

    struct BlurUniforms {
        uint width;
        uint height;
        uint stride;
        uint chunkCount;
    };

    struct BlurResult {
        uint total;
        uint count;
    };

    struct FingerprintUniforms {
        uint pixelCount;
        uint valueRange;
        uint chunkCount;
    };

    struct BlockUniforms {
        uint centerX;
        uint centerY;
        uint blockWidth;
        uint blockHeight;
        uint width;
        uint height;
        uint radius;
        uint searchStep;
        uint sampleStep;
        uint scoreGridWidth;
        uint scoreGridHeight;
        uint chunkCount;
    };

    struct ShiftResult {
        float dx;
        float dy;
        float score;
        uint bestIndex;
    };

    static float stabilizer_axis_offset(float before, float center, float after) {
        if (!isfinite(before) || !isfinite(center) || !isfinite(after)) {
            return 0.0f;
        }
        float denominator = before - (2.0f * center) + after;
        if (fabs(denominator) < 1.0e-9f) {
            return 0.0f;
        }
        return clamp(0.5f * (before - after) / denominator, -0.5f, 0.5f);
    }

    static float stabilizer_resolved_block_score(
        device const uint *partialSums,
        device const uint *partialCounts,
        uint blockIndex,
        uint scoreIndex,
        uint scoreCount,
        uint chunkCount
    ) {
        uint total = 0;
        uint count = 0;
        uint base = ((blockIndex * scoreCount) + scoreIndex) * chunkCount;
        for (uint chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
            total += partialSums[base + chunkIndex];
            count += partialCounts[base + chunkIndex];
        }
        return count > 0u ? float(total) / float(count) : FLT_MAX;
    }

    kernel void stabilizer_luma_sample(
        texture2d<float, access::read> source [[texture(0)]],
        device ushort *output [[buffer(0)]],
        constant LumaUniforms &uniforms [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uniforms.sampleWidth || gid.y >= uniforms.sampleHeight) {
            return;
        }
        uint sx = min(uniforms.sourceWidth - 1, uint((float(gid.x) + 0.5f) * float(uniforms.sourceWidth) / float(uniforms.sampleWidth)));
        uint sy = min(uniforms.sourceHeight - 1, uint((float(gid.y) + 0.5f) * float(uniforms.sourceHeight) / float(uniforms.sampleHeight)));
        float normalizedY = source.read(uint2(sx, sy)).r;
        float scale;
        if (uniforms.lumaMode == 0) {
            scale = 255.0f;
        } else {
            scale = 1023.0f;
        }
        output[(gid.y * uniforms.sampleWidth) + gid.x] = ushort(clamp(int(round(normalizedY * scale)), 0, int(scale)));
    }

    kernel void stabilizer_blur_partials(
        device const ushort *pixels [[buffer(0)]],
        device BlurResult *results [[buffer(1)]],
        constant BlurUniforms &uniforms [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= uniforms.chunkCount) {
            return;
        }
        uint stride = max(1u, uniforms.stride);
        uint total = 0;
        uint count = 0;
        if (uniforms.width > stride * 2u && uniforms.height > stride * 2u) {
            uint xCount = ((uniforms.width - stride - 1u - stride) / stride) + 1u;
            uint yCount = ((uniforms.height - stride - 1u - stride) / stride) + 1u;
            uint sampleCount = xCount * yCount;
            for (uint sampleIndex = gid; sampleIndex < sampleCount; sampleIndex += uniforms.chunkCount) {
                uint x = stride + (sampleIndex % xCount) * stride;
                uint y = stride + (sampleIndex / xCount) * stride;
                uint centerIndex = (y * uniforms.width) + x;
                int center = int(pixels[centerIndex]);
                uint dx = uint(abs(center - int(pixels[centerIndex + stride])));
                uint dy = uint(abs(center - int(pixels[((y + stride) * uniforms.width) + x])));
                total += dx + dy;
                count += 2u;
            }
        }
        results[gid].total = total;
        results[gid].count = count;
    }

    kernel void stabilizer_fingerprint(
        device const ushort *pixels [[buffer(0)]],
        device ulong *partials [[buffer(1)]],
        constant FingerprintUniforms &uniforms [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= uniforms.chunkCount) {
            return;
        }
        uint startIndex = (uniforms.pixelCount * gid) / uniforms.chunkCount;
        uint endIndex = (uniforms.pixelCount * (gid + 1u)) / uniforms.chunkCount;
        ulong hash = 14695981039346656037UL;
        uint range = max(1u, uniforms.valueRange);
        for (uint index = startIndex; index < endIndex; index += 1) {
            uint value = uint(pixels[index]);
            uint byteValue = range <= 255u ? min(255u, value) : min(255u, (value * 255u + (range / 2u)) / range);
            hash ^= ulong(byteValue);
            hash *= 1099511628211UL;
        }
        partials[gid] = hash;
    }

    kernel void stabilizer_block_score_partials(
        device const ushort *previous [[buffer(0)]],
        device const ushort *current [[buffer(1)]],
        device uint *partialSums [[buffer(2)]],
        device uint *partialCounts [[buffer(3)]],
        device const BlockUniforms *uniformsList [[buffer(4)]],
        uint3 gid [[thread_position_in_grid]]
    ) {
        BlockUniforms uniforms = uniformsList[gid.y];
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        if (gid.x >= scoreCount) {
            return;
        }
        uint gx = gid.x % uniforms.scoreGridWidth;
        uint gy = gid.x / uniforms.scoreGridWidth;
        int dx = -int(uniforms.radius) + int(gx * uniforms.searchStep);
        int dy = -int(uniforms.radius) + int(gy * uniforms.searchStep);
        int halfW = int(uniforms.blockWidth / 2);
        int halfH = int(uniforms.blockHeight / 2);
        int x0 = max(0, int(uniforms.centerX) - halfW);
        int y0 = max(0, int(uniforms.centerY) - halfH);
        int x1 = min(int(uniforms.width) - 1, int(uniforms.centerX) + halfW);
        int y1 = min(int(uniforms.height) - 1, int(uniforms.centerY) + halfH);
        uint xSamples = uint(max(0, x1 - x0) / int(uniforms.sampleStep)) + 1;
        uint ySamples = uint(max(0, y1 - y0) / int(uniforms.sampleStep)) + 1;
        uint sampleCount = xSamples * ySamples;
        uint chunkCount = uniforms.chunkCount;
        uint startIndex = (sampleCount * gid.z) / chunkCount;
        uint endIndex = (sampleCount * (gid.z + 1)) / chunkCount;
        uint total = 0;
        uint count = 0;
        for (uint sampleIndex = startIndex; sampleIndex < endIndex; sampleIndex += 1) {
            int x = x0 + int(sampleIndex % xSamples) * int(uniforms.sampleStep);
            int y = y0 + int(sampleIndex / xSamples) * int(uniforms.sampleStep);
            int cy = y + dy;
            if (cy < 0 || cy >= int(uniforms.height)) {
                continue;
            }
            int cx = x + dx;
            if (cx < 0 || cx >= int(uniforms.width)) {
                continue;
            }
            uint previousIndex = uint(y) * uniforms.width + uint(x);
            uint currentIndex = uint(cy) * uniforms.width + uint(cx);
            total += uint(abs(int(previous[previousIndex]) - int(current[currentIndex])));
            count += 1;
        }
        uint partialIndex = ((gid.y * scoreCount) + gid.x) * chunkCount + gid.z;
        partialSums[partialIndex] = total;
        partialCounts[partialIndex] = count;
    }

    kernel void stabilizer_block_score_fine_partials(
        device const ushort *previous [[buffer(0)]],
        device const ushort *current [[buffer(1)]],
        device uint *partialSums [[buffer(2)]],
        device uint *partialCounts [[buffer(3)]],
        device const BlockUniforms *uniformsList [[buffer(4)]],
        device const ShiftResult *coarseResults [[buffer(5)]],
        uint3 gid [[thread_position_in_grid]]
    ) {
        BlockUniforms uniforms = uniformsList[gid.y];
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        if (gid.x >= scoreCount) {
            return;
        }
        ShiftResult coarse = coarseResults[gid.y];
        int baseDx = isfinite(coarse.dx) ? int(round(coarse.dx)) : 0;
        int baseDy = isfinite(coarse.dy) ? int(round(coarse.dy)) : 0;
        uint gx = gid.x % uniforms.scoreGridWidth;
        uint gy = gid.x / uniforms.scoreGridWidth;
        int dx = baseDx - int(uniforms.radius) + int(gx * uniforms.searchStep);
        int dy = baseDy - int(uniforms.radius) + int(gy * uniforms.searchStep);
        int halfW = int(uniforms.blockWidth / 2);
        int halfH = int(uniforms.blockHeight / 2);
        int x0 = max(0, int(uniforms.centerX) - halfW);
        int y0 = max(0, int(uniforms.centerY) - halfH);
        int x1 = min(int(uniforms.width) - 1, int(uniforms.centerX) + halfW);
        int y1 = min(int(uniforms.height) - 1, int(uniforms.centerY) + halfH);
        uint xSamples = uint(max(0, x1 - x0) / int(uniforms.sampleStep)) + 1;
        uint ySamples = uint(max(0, y1 - y0) / int(uniforms.sampleStep)) + 1;
        uint sampleCount = xSamples * ySamples;
        uint chunkCount = uniforms.chunkCount;
        uint startIndex = (sampleCount * gid.z) / chunkCount;
        uint endIndex = (sampleCount * (gid.z + 1)) / chunkCount;
        uint total = 0;
        uint count = 0;
        for (uint sampleIndex = startIndex; sampleIndex < endIndex; sampleIndex += 1) {
            int x = x0 + int(sampleIndex % xSamples) * int(uniforms.sampleStep);
            int y = y0 + int(sampleIndex / xSamples) * int(uniforms.sampleStep);
            int cy = y + dy;
            if (cy < 0 || cy >= int(uniforms.height)) {
                continue;
            }
            int cx = x + dx;
            if (cx < 0 || cx >= int(uniforms.width)) {
                continue;
            }
            uint previousIndex = uint(y) * uniforms.width + uint(x);
            uint currentIndex = uint(cy) * uniforms.width + uint(cx);
            total += uint(abs(int(previous[previousIndex]) - int(current[currentIndex])));
            count += 1;
        }
        uint partialIndex = ((gid.y * scoreCount) + gid.x) * chunkCount + gid.z;
        partialSums[partialIndex] = total;
        partialCounts[partialIndex] = count;
    }

    kernel void stabilizer_block_score_resolve(
        device const uint *partialSums [[buffer(0)]],
        device const uint *partialCounts [[buffer(1)]],
        device ShiftResult *results [[buffer(2)]],
        device const BlockUniforms *uniformsList [[buffer(3)]],
        constant uint &chunkCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        BlockUniforms uniforms = uniformsList[gid];
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        float bestScore = FLT_MAX;
        uint bestIndex = 0;
        for (uint scoreIndex = 0; scoreIndex < scoreCount; scoreIndex += 1) {
            float score = stabilizer_resolved_block_score(
                partialSums,
                partialCounts,
                gid,
                scoreIndex,
                scoreCount,
                chunkCount
            );
            if (score < bestScore) {
                bestScore = score;
                bestIndex = scoreIndex;
            }
        }
        uint gx = bestIndex % uniforms.scoreGridWidth;
        uint gy = bestIndex / uniforms.scoreGridWidth;
        float refinedGridX = float(gx);
        float refinedGridY = float(gy);
        bool searchRadiusHit = gx == 0u
            || gy == 0u
            || gx + 1u >= uniforms.scoreGridWidth
            || gy + 1u >= uniforms.scoreGridHeight;
        if (!searchRadiusHit) {
            uint leftIndex = gy * uniforms.scoreGridWidth + (gx - 1u);
            uint rightIndex = gy * uniforms.scoreGridWidth + (gx + 1u);
            uint upIndex = (gy - 1u) * uniforms.scoreGridWidth + gx;
            uint downIndex = (gy + 1u) * uniforms.scoreGridWidth + gx;

            refinedGridX += stabilizer_axis_offset(
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, leftIndex, scoreCount, chunkCount),
                bestScore,
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, rightIndex, scoreCount, chunkCount)
            );
            refinedGridY += stabilizer_axis_offset(
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, upIndex, scoreCount, chunkCount),
                bestScore,
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, downIndex, scoreCount, chunkCount)
            );
        }
        results[gid].dx = float(-int(uniforms.radius)) + (refinedGridX * float(uniforms.searchStep));
        results[gid].dy = float(-int(uniforms.radius)) + (refinedGridY * float(uniforms.searchStep));
        results[gid].score = bestScore;
        results[gid].bestIndex = bestIndex;
    }

    kernel void stabilizer_block_score_fine_resolve(
        device const uint *partialSums [[buffer(0)]],
        device const uint *partialCounts [[buffer(1)]],
        device ShiftResult *results [[buffer(2)]],
        device const BlockUniforms *uniformsList [[buffer(3)]],
        constant uint &chunkCount [[buffer(4)]],
        device const ShiftResult *coarseResults [[buffer(5)]],
        uint gid [[thread_position_in_grid]]
    ) {
        BlockUniforms uniforms = uniformsList[gid];
        ShiftResult coarse = coarseResults[gid];
        int baseDx = isfinite(coarse.dx) ? int(round(coarse.dx)) : 0;
        int baseDy = isfinite(coarse.dy) ? int(round(coarse.dy)) : 0;
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        float bestScore = FLT_MAX;
        uint bestIndex = 0;
        for (uint scoreIndex = 0; scoreIndex < scoreCount; scoreIndex += 1) {
            float score = stabilizer_resolved_block_score(
                partialSums,
                partialCounts,
                gid,
                scoreIndex,
                scoreCount,
                chunkCount
            );
            if (score < bestScore) {
                bestScore = score;
                bestIndex = scoreIndex;
            }
        }
        uint gx = bestIndex % uniforms.scoreGridWidth;
        uint gy = bestIndex / uniforms.scoreGridWidth;
        float refinedGridX = float(gx);
        float refinedGridY = float(gy);
        bool searchRadiusHit = gx == 0u
            || gy == 0u
            || gx + 1u >= uniforms.scoreGridWidth
            || gy + 1u >= uniforms.scoreGridHeight;
        if (!searchRadiusHit) {
            uint leftIndex = gy * uniforms.scoreGridWidth + (gx - 1u);
            uint rightIndex = gy * uniforms.scoreGridWidth + (gx + 1u);
            uint upIndex = (gy - 1u) * uniforms.scoreGridWidth + gx;
            uint downIndex = (gy + 1u) * uniforms.scoreGridWidth + gx;

            refinedGridX += stabilizer_axis_offset(
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, leftIndex, scoreCount, chunkCount),
                bestScore,
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, rightIndex, scoreCount, chunkCount)
            );
            refinedGridY += stabilizer_axis_offset(
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, upIndex, scoreCount, chunkCount),
                bestScore,
                stabilizer_resolved_block_score(partialSums, partialCounts, gid, downIndex, scoreCount, chunkCount)
            );
        }
        results[gid].dx = float(baseDx - int(uniforms.radius)) + (refinedGridX * float(uniforms.searchStep));
        results[gid].dy = float(baseDy - int(uniforms.radius)) + (refinedGridY * float(uniforms.searchStep));
        results[gid].score = bestScore;
        results[gid].bestIndex = bestIndex;
    }
    """
}

func prepare(frames: [AnalysisFrame], motions: [PairMotion]) throws -> PreparedAnalysis {
    guard frames.count == motions.count else {
        throw AnalyzerError("motion count did not match frame count")
    }
    var pathX: [Float] = []
    var pathY: [Float] = []
    var rawRoll: [Float] = []
    var farFieldPathX: [Float] = []
    var farFieldPathY: [Float] = []
    var farFieldRawRoll: [Float] = []
    var yaw: [Float] = []
    var pitch: [Float] = []
    var shearX: [Float] = []
    var shearY: [Float] = []
    var perspectiveX: [Float] = []
    var perspectiveY: [Float] = []
    var lensBandTopPathX: [Float] = []
    var lensBandTopPathY: [Float] = []
    var lensBandTopColumnPathX: [Float] = []
    var lensBandTopColumnPathY: [Float] = []
    var lensBandTopRowPhasePathX: [Float] = []
    var lensBandTopRowPhasePathY: [Float] = []
    var lensBandTopLocalRollPath: [Float] = []
    var lensBandRidgePathX: [Float] = []
    var lensBandRidgePathY: [Float] = []
    var lensBandRidgeColumnPathX: [Float] = []
    var lensBandRidgeColumnPathY: [Float] = []
    var lensBandRidgeRowPhasePathX: [Float] = []
    var lensBandRidgeRowPhasePathY: [Float] = []
    var lensBandRidgeLocalRollPath: [Float] = []
    var lensBandMidPathX: [Float] = []
    var lensBandMidPathY: [Float] = []
    var lensBandMidColumnPathX: [Float] = []
    var lensBandMidColumnPathY: [Float] = []
    var lensBandMidRowPhasePathX: [Float] = []
    var lensBandMidRowPhasePathY: [Float] = []
    var lensBandMidLocalRollPath: [Float] = []
    var sourceLensShakeRidgePathY: [Float] = []
    var sourceLensShakeRidgeLinePathY: [Float] = []
    var sourceLensShakeLocalPathX = Array(repeating: Array<Float>(), count: sourceLensShakeLocalBinCount)
    var sourceLensShakeLocalPathY = Array(repeating: Array<Float>(), count: sourceLensShakeLocalBinCount)
    var sourceLensShakeLocalSupport = Array(repeating: Array<Float>(), count: sourceLensShakeLocalBinCount)
    var farFieldMeshPathX = Array(repeating: Array<Float>(), count: farFieldMeshBinCount)
    var farFieldMeshPathY = Array(repeating: Array<Float>(), count: farFieldMeshBinCount)
    var farFieldMeshSupport = Array(repeating: Array<Float>(), count: farFieldMeshBinCount)
    var x: Float = 0
    var y: Float = 0
    var roll: Float = 0
    var farFieldX: Float = 0
    var farFieldY: Float = 0
    var farFieldRoll: Float = 0
    var yawValue: Float = 0
    var pitchValue: Float = 0
    var shearXValue: Float = 0
    var shearYValue: Float = 0
    var perspectiveXValue: Float = 0
    var perspectiveYValue: Float = 0
    var lensBandTopX: Float = 0
    var lensBandTopY: Float = 0
    var lensBandTopColumnX: Float = 0
    var lensBandTopColumnY: Float = 0
    var lensBandTopRowPhaseX: Float = 0
    var lensBandTopRowPhaseY: Float = 0
    var lensBandTopLocalRoll: Float = 0
    var lensBandRidgeX: Float = 0
    var lensBandRidgeY: Float = 0
    var lensBandRidgeColumnX: Float = 0
    var lensBandRidgeColumnY: Float = 0
    var lensBandRidgeRowPhaseX: Float = 0
    var lensBandRidgeRowPhaseY: Float = 0
    var lensBandRidgeLocalRoll: Float = 0
    var lensBandMidX: Float = 0
    var lensBandMidY: Float = 0
    var lensBandMidColumnX: Float = 0
    var lensBandMidColumnY: Float = 0
    var lensBandMidRowPhaseX: Float = 0
    var lensBandMidRowPhaseY: Float = 0
    var lensBandMidLocalRoll: Float = 0
    var sourceLensShakeRidgeY: Float = 0
    var sourceLensShakeRidgeLineY: Float = 0
    var sourceLensShakeLocalX = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
    var sourceLensShakeLocalY = Array(repeating: Float(0.0), count: sourceLensShakeLocalBinCount)
    var farFieldMeshX = Array(repeating: Float(0.0), count: farFieldMeshBinCount)
    var farFieldMeshY = Array(repeating: Float(0.0), count: farFieldMeshBinCount)
    for motion in motions {
        x += motion.dx
        y += motion.dy
        roll += motion.signedRoll
        farFieldX += motion.farFieldDx
        farFieldY += motion.farFieldDy
        farFieldRoll += motion.farFieldSignedRoll
        yawValue += motion.yawProxy
        pitchValue += motion.pitchProxy
        shearXValue += motion.shearX
        shearYValue += motion.shearY
        perspectiveXValue += motion.perspectiveX
        perspectiveYValue += motion.perspectiveY
        lensBandTopX += motion.lensBandTopDx
        lensBandTopY += motion.lensBandTopDy
        lensBandTopColumnX += motion.lensBandTopColumnDx
        lensBandTopColumnY += motion.lensBandTopColumnDy
        lensBandTopRowPhaseX += motion.lensBandTopRowPhaseDx
        lensBandTopRowPhaseY += motion.lensBandTopRowPhaseDy
        lensBandTopLocalRoll += motion.lensBandTopLocalRoll
        lensBandRidgeX += motion.lensBandRidgeDx
        lensBandRidgeY += motion.lensBandRidgeDy
        lensBandRidgeColumnX += motion.lensBandRidgeColumnDx
        lensBandRidgeColumnY += motion.lensBandRidgeColumnDy
        lensBandRidgeRowPhaseX += motion.lensBandRidgeRowPhaseDx
        lensBandRidgeRowPhaseY += motion.lensBandRidgeRowPhaseDy
        lensBandRidgeLocalRoll += motion.lensBandRidgeLocalRoll
        lensBandMidX += motion.lensBandMidDx
        lensBandMidY += motion.lensBandMidDy
        lensBandMidColumnX += motion.lensBandMidColumnDx
        lensBandMidColumnY += motion.lensBandMidColumnDy
        lensBandMidRowPhaseX += motion.lensBandMidRowPhaseDx
        lensBandMidRowPhaseY += motion.lensBandMidRowPhaseDy
        lensBandMidLocalRoll += motion.lensBandMidLocalRoll
        sourceLensShakeRidgeY += motion.sourceLensShakeRidgeDy
        sourceLensShakeRidgeLineY += motion.sourceLensShakeRidgeLineDy
        for bin in 0..<sourceLensShakeLocalBinCount {
            sourceLensShakeLocalX[bin] += motion.sourceLensShakeLocalDx.indices.contains(bin) ? motion.sourceLensShakeLocalDx[bin] : 0.0
            sourceLensShakeLocalY[bin] += motion.sourceLensShakeLocalDy.indices.contains(bin) ? motion.sourceLensShakeLocalDy[bin] : 0.0
            sourceLensShakeLocalPathX[bin].append(sourceLensShakeLocalX[bin])
            sourceLensShakeLocalPathY[bin].append(sourceLensShakeLocalY[bin])
            sourceLensShakeLocalSupport[bin].append(motion.sourceLensShakeLocalSupport.indices.contains(bin) ? motion.sourceLensShakeLocalSupport[bin] : 0.0)
        }
        for bin in 0..<farFieldMeshBinCount {
            farFieldMeshX[bin] += motion.farFieldMeshDx.indices.contains(bin) ? motion.farFieldMeshDx[bin] : 0.0
            farFieldMeshY[bin] += motion.farFieldMeshDy.indices.contains(bin) ? motion.farFieldMeshDy[bin] : 0.0
            farFieldMeshPathX[bin].append(farFieldMeshX[bin])
            farFieldMeshPathY[bin].append(farFieldMeshY[bin])
            farFieldMeshSupport[bin].append(motion.farFieldMeshSupport.indices.contains(bin) ? motion.farFieldMeshSupport[bin] : 0.0)
        }
        pathX.append(x)
        pathY.append(y)
        rawRoll.append(roll)
        farFieldPathX.append(farFieldX)
        farFieldPathY.append(farFieldY)
        farFieldRawRoll.append(farFieldRoll)
        yaw.append(yawValue)
        pitch.append(pitchValue)
        shearX.append(shearXValue)
        shearY.append(shearYValue)
        perspectiveX.append(perspectiveXValue)
        perspectiveY.append(perspectiveYValue)
        lensBandTopPathX.append(lensBandTopX)
        lensBandTopPathY.append(lensBandTopY)
        lensBandTopColumnPathX.append(lensBandTopColumnX)
        lensBandTopColumnPathY.append(lensBandTopColumnY)
        lensBandTopRowPhasePathX.append(lensBandTopRowPhaseX)
        lensBandTopRowPhasePathY.append(lensBandTopRowPhaseY)
        lensBandTopLocalRollPath.append(lensBandTopLocalRoll)
        lensBandRidgePathX.append(lensBandRidgeX)
        lensBandRidgePathY.append(lensBandRidgeY)
        lensBandRidgeColumnPathX.append(lensBandRidgeColumnX)
        lensBandRidgeColumnPathY.append(lensBandRidgeColumnY)
        lensBandRidgeRowPhasePathX.append(lensBandRidgeRowPhaseX)
        lensBandRidgeRowPhasePathY.append(lensBandRidgeRowPhaseY)
        lensBandRidgeLocalRollPath.append(lensBandRidgeLocalRoll)
        lensBandMidPathX.append(lensBandMidX)
        lensBandMidPathY.append(lensBandMidY)
        lensBandMidColumnPathX.append(lensBandMidColumnX)
        lensBandMidColumnPathY.append(lensBandMidColumnY)
        lensBandMidRowPhasePathX.append(lensBandMidRowPhaseX)
        lensBandMidRowPhasePathY.append(lensBandMidRowPhaseY)
        lensBandMidLocalRollPath.append(lensBandMidLocalRoll)
        sourceLensShakeRidgePathY.append(sourceLensShakeRidgeY)
        sourceLensShakeRidgeLinePathY.append(sourceLensShakeRidgeLineY)
    }
    let flatFarFieldMeshPathX = farFieldMeshPathX.flatMap { $0 }
    let flatFarFieldMeshPathY = farFieldMeshPathY.flatMap { $0 }
    let flatFarFieldMeshSupport = farFieldMeshSupport.flatMap { $0 }
    let farFieldMeshDominantWindows = farFieldMeshDominantWindows(
        frames: frames,
        pathX: flatFarFieldMeshPathX,
        pathY: flatFarFieldMeshPathY,
        support: flatFarFieldMeshSupport,
        rows: farFieldMeshRows,
        columns: farFieldMeshColumns
    )
    let farFieldRigidShake = farFieldRigidShakePreparedPaths(
        topX: lensBandTopPathX,
        topY: lensBandTopPathY,
        ridgeX: lensBandRidgePathX,
        ridgeY: lensBandRidgePathY,
        midX: lensBandMidPathX,
        midY: lensBandMidPathY,
        topConfidence: motions.map(\.lensBandTopConfidence),
        ridgeConfidence: motions.map(\.lensBandRidgeConfidence),
        midConfidence: motions.map(\.lensBandMidConfidence)
    )
    guard farFieldRigidShake.pathX.count == frames.count,
          farFieldRigidShake.pathY.count == frames.count,
          farFieldRigidShake.support.count == frames.count,
          farFieldRigidShake.shapeConsistency.count == frames.count,
          farFieldRigidShake.forwardBackwardConsistency.count == frames.count else {
        throw AnalyzerError("far-field rigid shake preparation produced incomplete current-schema paths")
    }
    return PreparedAnalysis(
        frames: frames,
        residuals: motions.map(\.residual),
        rollMotion: motions.map(\.rollMotion),
        pathX: jerkLimitedMotionPath(pathX, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        pathY: jerkLimitedMotionPath(pathY, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        pathRoll: jerkLimitedMotionPath(rawRoll, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        farFieldPathX: jerkLimitedMotionPath(farFieldPathX, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        farFieldPathY: jerkLimitedMotionPath(farFieldPathY, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        farFieldPathRoll: jerkLimitedMotionPath(farFieldRawRoll, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        farFieldConfidence: motions.map(\.farFieldConfidence),
        footstepPathX: pathX,
        footstepPathY: pathY,
        footstepPathRoll: rawRoll,
        pathYaw: jerkLimitedMotionPath(yaw, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        pathPitch: jerkLimitedMotionPath(pitch, minimumAcceleration: minimumTranslationAccelerationLimit, minimumJerk: minimumTranslationJerkLimit),
        pathShearX: jerkLimitedMotionPath(shearX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        pathShearY: jerkLimitedMotionPath(shearY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        pathPerspectiveX: jerkLimitedMotionPath(perspectiveX, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        pathPerspectiveY: jerkLimitedMotionPath(perspectiveY, minimumAcceleration: minimumRotationAccelerationLimit, minimumJerk: minimumRotationJerkLimit),
        lensBandTopPathX: lensBandTopPathX,
        lensBandTopPathY: lensBandTopPathY,
        lensBandTopColumnPathX: lensBandTopColumnPathX,
        lensBandTopColumnPathY: lensBandTopColumnPathY,
        lensBandTopRowPhasePathX: lensBandTopRowPhasePathX,
        lensBandTopRowPhasePathY: lensBandTopRowPhasePathY,
        lensBandTopLocalRollPath: lensBandTopLocalRollPath,
        lensBandRidgePathX: lensBandRidgePathX,
        lensBandRidgePathY: lensBandRidgePathY,
        lensBandRidgeColumnPathX: lensBandRidgeColumnPathX,
        lensBandRidgeColumnPathY: lensBandRidgeColumnPathY,
        lensBandRidgeRowPhasePathX: lensBandRidgeRowPhasePathX,
        lensBandRidgeRowPhasePathY: lensBandRidgeRowPhasePathY,
        lensBandRidgeLocalRollPath: lensBandRidgeLocalRollPath,
        lensBandMidPathX: lensBandMidPathX,
        lensBandMidPathY: lensBandMidPathY,
        lensBandMidColumnPathX: lensBandMidColumnPathX,
        lensBandMidColumnPathY: lensBandMidColumnPathY,
        lensBandMidRowPhasePathX: lensBandMidRowPhasePathX,
        lensBandMidRowPhasePathY: lensBandMidRowPhasePathY,
        lensBandMidLocalRollPath: lensBandMidLocalRollPath,
        lensBandTopConfidence: motions.map(\.lensBandTopConfidence),
        lensBandRidgeConfidence: motions.map(\.lensBandRidgeConfidence),
        lensBandMidConfidence: motions.map(\.lensBandMidConfidence),
        lensBandConfidence: motions.map(\.lensBandConfidence),
        farFieldRigidShakePathX: farFieldRigidShake.pathX,
        farFieldRigidShakePathY: farFieldRigidShake.pathY,
        farFieldRigidShakeSupport: farFieldRigidShake.support,
        farFieldRigidShakeShapeConsistency: farFieldRigidShake.shapeConsistency,
        farFieldRigidShakeForwardBackwardConsistency: farFieldRigidShake.forwardBackwardConsistency,
        farFieldMeshRows: farFieldMeshRows,
        farFieldMeshColumns: farFieldMeshColumns,
        farFieldMeshPathX: flatFarFieldMeshPathX,
        farFieldMeshPathY: flatFarFieldMeshPathY,
        farFieldMeshSupport: flatFarFieldMeshSupport,
        farFieldMeshDominantWindowFrames: farFieldMeshDominantWindows.windowFrames,
        farFieldMeshDominantWindowSeconds: farFieldMeshDominantWindows.windowSeconds,
        farFieldMeshDominantSupport: farFieldMeshDominantWindows.support,
        farFieldMeshDominantCell: farFieldMeshDominantWindows.cell,
        sourceLensShakeRidgePathY: sourceLensShakeRidgePathY,
        sourceLensShakeRidgeSupport: motions.map(\.sourceLensShakeRidgeSupport),
        sourceLensShakeRidgeLinePathY: sourceLensShakeRidgeLinePathY,
        sourceLensShakeRidgeLineSupport: motions.map(\.sourceLensShakeRidgeLineSupport),
        sourceLensShakeLocalBinCount: sourceLensShakeLocalBinCount,
        sourceLensShakeLocalPathX: sourceLensShakeLocalPathX.flatMap { $0 },
        sourceLensShakeLocalPathY: sourceLensShakeLocalPathY.flatMap { $0 },
        sourceLensShakeLocalSupport: sourceLensShakeLocalSupport.flatMap { $0 },
        analysisConfidence: motions.map(\.analysisConfidence),
        warpConfidence: motions.map(\.warpConfidence),
        acceptedBlockCounts: motions.map(\.acceptedBlockCount),
        totalBlockCounts: motions.map(\.totalBlockCount),
        blurAmounts: frames.map(\.blurAmount),
        searchRadiusHitCounts: motions.map(\.searchRadiusHitCount),
        searchRadiusTotalCounts: motions.map(\.searchRadiusTotalCount)
    )
}

func jerkLimitedMotionPath(_ values: [Float], minimumAcceleration: Float, minimumJerk: Float) -> [Float] {
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
            Float(0.0) - maxCorrection,
            maxCorrection
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

func median(_ values: [Float]) -> Float? {
    guard !values.isEmpty else {
        return nil
    }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[middle - 1] + sorted[middle]) * 0.5
    }
    return sorted[middle]
}

private struct AnalysisSampleSize {
    let width: Int
    let height: Int
}

private struct FrameReadChunk {
    let index: Int
    let totalCount: Int
    let readStartSeconds: Double?
    let readEndSeconds: Double?
    let outputStartSeconds: Double
    let outputEndSeconds: Double
    let requiresPreviousFrame: Bool
    let isLast: Bool
}

private struct FrameChunkResult {
    let index: Int
    let frames: [AnalysisFrame]
    let motions: [PairMotion]
    let timings: FrameReadTimingAccumulator
}

private struct ReadFramesResult {
    let prepared: PreparedAnalysis
    let timings: FrameReadTimingAccumulator
}

private struct FarFieldRigidShakePreparedPaths {
    let pathX: [Float]
    let pathY: [Float]
    let support: [Float]
    let shapeConsistency: [Float]
    let forwardBackwardConsistency: [Float]
}

private func preparedConfidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
    guard full > start else {
        return value >= full ? 1.0 : 0.0
    }
    return clamp((value - start) / (full - start), 0.0, 1.0)
}

private func farFieldRigidShakePreparedPaths(
    topX: [Float],
    topY: [Float],
    ridgeX: [Float],
    ridgeY: [Float],
    midX: [Float],
    midY: [Float],
    topConfidence: [Float],
    ridgeConfidence: [Float],
    midConfidence: [Float]
) -> FarFieldRigidShakePreparedPaths {
    let frameCount = [
        topX.count, topY.count, ridgeX.count, ridgeY.count, midX.count, midY.count,
        topConfidence.count, ridgeConfidence.count, midConfidence.count
    ].min() ?? 0
    guard frameCount > 0 else {
        return FarFieldRigidShakePreparedPaths(pathX: [], pathY: [], support: [], shapeConsistency: [], forwardBackwardConsistency: [])
    }

    var pathX = Array(repeating: Float(0.0), count: frameCount)
    var pathY = Array(repeating: Float(0.0), count: frameCount)
    var support = Array(repeating: Float(0.0), count: frameCount)
    var shapeConsistency = Array(repeating: Float(0.0), count: frameCount)
    var forwardBackwardConsistency = Array(repeating: Float(0.0), count: frameCount)

    for index in 0..<frameCount {
        let commonX = (topX[index] * 0.25) + (ridgeX[index] * 0.50) + (midX[index] * 0.25)
        let commonY = (topY[index] * 0.25) + (ridgeY[index] * 0.50) + (midY[index] * 0.25)
        pathX[index] = commonX
        pathY[index] = commonY

        let topDelta = hypotf(topX[index] - commonX, topY[index] - commonY)
        let ridgeDelta = hypotf(ridgeX[index] - commonX, ridgeY[index] - commonY)
        let midDelta = hypotf(midX[index] - commonX, midY[index] - commonY)
        let shapeDisagreement = max(topDelta, max(ridgeDelta, midDelta))
        shapeConsistency[index] = clamp(
            1.0 - preparedConfidenceRamp(
                shapeDisagreement,
                start: farFieldRigidShakeShapeStartPixels,
                full: farFieldRigidShakeShapeFullPixels
            ),
            0.0,
            1.0
        )
    }

    let radius = farFieldRigidShakeTwoWayRadiusFrames
    guard frameCount > radius * 2 else {
        return FarFieldRigidShakePreparedPaths(pathX: pathX, pathY: pathY, support: support, shapeConsistency: shapeConsistency, forwardBackwardConsistency: forwardBackwardConsistency)
    }

    for index in radius..<(frameCount - radius) {
        let forwardX = pathX[index] - ((2.0 * pathX[index - 1]) - pathX[index - 2])
        let forwardY = pathY[index] - ((2.0 * pathY[index - 1]) - pathY[index - 2])
        let backwardX = pathX[index] - ((2.0 * pathX[index + 1]) - pathX[index + 2])
        let backwardY = pathY[index] - ((2.0 * pathY[index + 1]) - pathY[index + 2])
        let residualMagnitude = (hypotf(forwardX, forwardY) + hypotf(backwardX, backwardY)) * 0.5
        let residualMismatch = hypotf(forwardX - backwardX, forwardY - backwardY)
        let twoWay = 1.0 - preparedConfidenceRamp(
            residualMismatch,
            start: farFieldRigidShakeForwardBackwardStartPixels,
            full: farFieldRigidShakeForwardBackwardFullPixels
        )
        let confidence = min(topConfidence[index], min(ridgeConfidence[index], midConfidence[index]))
        forwardBackwardConsistency[index] = clamp(twoWay, 0.0, 1.0)
        support[index] = clamp(
            preparedConfidenceRamp(confidence, start: 0.08, full: 0.36)
                * shapeConsistency[index]
                * forwardBackwardConsistency[index]
                * preparedConfidenceRamp(
                    residualMagnitude,
                    start: farFieldRigidShakeResidualStartPixels,
                    full: farFieldRigidShakeResidualFullPixels
                ),
            0.0,
            1.0
        )
    }

    return FarFieldRigidShakePreparedPaths(
        pathX: pathX,
        pathY: pathY,
        support: support,
        shapeConsistency: shapeConsistency,
        forwardBackwardConsistency: forwardBackwardConsistency
    )
}

private struct FrameReadTimingAccumulator {
    var readFramesWallSeconds: Double = 0.0
    var readerLaneWallSeconds: Double = 0.0
    var decoderCopyNextFrameSeconds: Double = 0.0
    var metalEncodeSeconds: Double = 0.0
    var metalCompleteSeconds: Double = 0.0
    var preparedPathSeconds: Double = 0.0
    var readerLaneCount: Int = 0

    mutating func add(_ other: FrameReadTimingAccumulator) {
        readFramesWallSeconds += other.readFramesWallSeconds
        readerLaneWallSeconds += other.readerLaneWallSeconds
        decoderCopyNextFrameSeconds += other.decoderCopyNextFrameSeconds
        metalEncodeSeconds += other.metalEncodeSeconds
        metalCompleteSeconds += other.metalCompleteSeconds
        preparedPathSeconds += other.preparedPathSeconds
        readerLaneCount += other.readerLaneCount
    }
}

private func timingNowSeconds() -> Double {
    ProcessInfo.processInfo.systemUptime
}

private func analyzerOfferedProcessorCount() -> Int {
    max(1, ProcessInfo.processInfo.activeProcessorCount)
}

private func analyzerPhysicalMemoryGB() -> UInt64 {
    max(1, ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
}

private func validateAnalyzerResourceEnvironment() throws {
    let unsupportedKeys = [
        "STABILIZER_ANALYZER_WORKERS",
        "STABILIZER_ANALYZER_IN_FLIGHT",
    ]
    for key in unsupportedKeys {
        guard let value = ProcessInfo.processInfo.environment[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continue
        }
        throw AnalyzerError("\(key) is not supported; Event Analyzer automatically uses detected maximum reader and GPU resources")
    }
}

private func analyzerReaderLaneProbeLimit() -> Int {
    analyzerOfferedProcessorCount()
}

private func analyzerInFlightLimit(pixelCount: Int, readerLaneCount: Int) -> Int {
    let laneCount = max(1, readerLaneCount)
    let bytesPerFrameSlot = max(4 * 1024 * 1024, pixelCount * 6)
    let memoryGB = analyzerPhysicalMemoryGB()
    let targetSlotCountPerLane = memoryGB <= 10 ? 2 : memoryGB <= 18 ? 3 : 4
    let memoryDivisor: UInt64 = memoryGB <= 10 ? 24 : memoryGB <= 18 ? 12 : 10
    let minimumPipelineBudget = bytesPerFrameSlot * laneCount * targetSlotCountPerLane
    let memoryBudget = max(minimumPipelineBudget, Int(ProcessInfo.processInfo.physicalMemory / memoryDivisor))
    let memoryLimitedTotalSlotCount = max(laneCount * targetSlotCountPerLane, memoryBudget / bytesPerFrameSlot)
    let memoryLimitedSlotCountPerLane = max(targetSlotCountPerLane, memoryLimitedTotalSlotCount / laneCount)
    return memoryLimitedSlotCountPerLane
}

private func analyzerTextureCacheFlushInterval(sourcePixelCount: Int) -> Int {
    let bytesPerSourceFrame = max(1, sourcePixelCount * 4)
    let memoryGB = analyzerPhysicalMemoryGB()
    let textureCacheBudget = Int((memoryGB < 16 ? 128 : memoryGB <= 18 ? 256 : memoryGB <= 36 ? 384 : 768) * 1024 * 1024)
    return max(1, min(60, textureCacheBudget / bytesPerSourceFrame))
}

private func textureCacheFlushDescription(interval: Int) -> String {
    interval <= 1 ? "every completed frame" : "every \(interval) completed frames"
}

private func analysisDurationSeconds(durationSeconds: Double, frameDurationSeconds: Double, maxFrames: Int?) -> Double {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    guard let maxFrames else {
        return boundedDuration
    }
    let limitedFrameCount = max(1, maxFrames)
    return min(boundedDuration, max(frameDurationSeconds, Double(limitedFrameCount) * frameDurationSeconds))
}

private func shouldUseParallelReaders(plan: AssetPlan, maxFrames: Int?, readerLaneCount: Int) -> Bool {
    if readerLaneCount <= 1 {
        return false
    }
    let frameDuration = plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0
    let analysisDuration = analysisDurationSeconds(
        durationSeconds: plan.durationSeconds,
        frameDurationSeconds: frameDuration,
        maxFrames: maxFrames
    )
    let analysisFrameCount = estimatedFrameCount(
        durationSeconds: analysisDuration,
        frameDurationSeconds: frameDuration
    )
    return analysisFrameCount >= max(12, readerLaneCount * 3)
}

private func estimatedFrameCount(durationSeconds: Double, frameDurationSeconds: Double, maxFrames: Int? = nil) -> Int {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    let frameCount = max(1, Int((boundedDuration / max(1e-9, frameDurationSeconds)).rounded(.up)))
    if let maxFrames {
        return min(maxFrames, frameCount)
    }
    return frameCount
}

private func makeFrameReadChunks(durationSeconds: Double, frameDurationSeconds: Double, readerLaneCount: Int) -> [FrameReadChunk] {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    let chunkCount = max(1, min(readerLaneCount, estimatedFrameCount(durationSeconds: durationSeconds, frameDurationSeconds: frameDurationSeconds)))
    let chunkDuration = boundedDuration / Double(chunkCount)
    let overlapSeconds = max(frameDurationSeconds * 4.0, 0.12)
    return (0..<chunkCount).map { index in
        let outputStart = Double(index) * chunkDuration
        let outputEnd = index == chunkCount - 1 ? boundedDuration : Double(index + 1) * chunkDuration
        let readStart = index == 0 ? outputStart : max(0.0, outputStart - overlapSeconds)
        return FrameReadChunk(
            index: index,
            totalCount: chunkCount,
            readStartSeconds: readStart,
            readEndSeconds: outputEnd,
            outputStartSeconds: outputStart,
            outputEndSeconds: outputEnd,
            requiresPreviousFrame: index > 0,
            isLast: index == chunkCount - 1
        )
    }
}

private func firstPresentationTimeSeconds(url: URL) throws -> Double {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw AnalyzerError("asset had no video track: \(url.path)")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw AnalyzerError("could not add AVAssetReaderTrackOutput")
    }
    reader.add(output)
    guard reader.startReading() else {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
    }
    defer {
        if reader.status == .reading {
            reader.cancelReading()
        }
    }
    var firstSampleBuffer: CMSampleBuffer?
    while reader.status == .reading {
        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            break
        }
        if CMSampleBufferGetNumSamples(sampleBuffer) > 0 {
            firstSampleBuffer = sampleBuffer
            break
        }
    }
    guard let firstSampleBuffer else {
        throw AnalyzerError("asset had no readable compressed video frames: \(url.path)")
    }
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(firstSampleBuffer))
    guard pts.isFinite else {
        throw AnalyzerError("asset first video frame had non-finite presentation time: \(url.path)")
    }
    return pts
}

private func readFrameChunk(
    url: URL,
    planName: String,
    sample: AnalysisSampleSize,
    sourcePixelCount: Int,
    chunk: FrameReadChunk,
    basePresentationTimeSeconds: Double?,
    maxFrames: Int?,
    progressEnabled: Bool,
    progressEvery: Int,
    progressReporter: AnalyzerFrameProgressReporter?,
    inFlightLimit: Int,
    expectedOutputFrameCount: Int,
    metalContext: MetalAnalysisContext,
    decoderMode: DecoderMode
) throws -> FrameChunkResult {
    let chunkWallStart = timingNowSeconds()
    var timings = FrameReadTimingAccumulator(readerLaneCount: 1)
    let timeRange: CMTimeRange?
    if let readStartSeconds = chunk.readStartSeconds,
       let readEndSeconds = chunk.readEndSeconds {
        let baseSeconds = basePresentationTimeSeconds ?? 0.0
        let start = CMTime(seconds: baseSeconds + readStartSeconds, preferredTimescale: 600_000)
        let duration = CMTime(seconds: max(0.0, readEndSeconds - readStartSeconds), preferredTimescale: 600_000)
        timeRange = CMTimeRange(start: start, duration: duration)
    } else {
        timeRange = nil
    }
    let frameReader = try VideoToolboxDecodedFrameReader(
        url: url,
        timeRange: timeRange,
        maxPendingDecodeCount: inFlightLimit * 2,
        decoderMode: decoderMode
    )
    defer {
        frameReader.cancelReading()
        metalContext.flushTextureCache()
    }
    var frames: [AnalysisFrame] = []
    var motions: [PairMotion] = []
    frames.reserveCapacity(max(3, expectedOutputFrameCount))
    motions.reserveCapacity(max(3, expectedOutputFrameCount))
    let pixelCount = sample.width * sample.height
    let frameSlots = try metalContext.makeFrameSlots(count: inFlightLimit, pixelCount: pixelCount, width: sample.width, height: sample.height)
    var currentFrameSlotIndex = 0
    var previousLumaBuffer: MTLBuffer?
    var firstPTS = basePresentationTimeSeconds
    var sawOutputFrame = false
    let frameTimeEpsilon = 1.0 / 600_000.0
    var pendingFrames: [(encoded: MetalEncodedFrame, time: Double, shouldOutput: Bool)] = []
    pendingFrames.reserveCapacity(inFlightLimit)
    let textureCacheFlushInterval = analyzerTextureCacheFlushInterval(sourcePixelCount: sourcePixelCount)
    var completedEncodedFrameCount = 0
    var previousRidgeLineProfile: RidgeLineProfile?

    func pendingOutputFrameCount() -> Int {
        pendingFrames.reduce(0) { count, pending in
            count + (pending.shouldOutput ? 1 : 0)
        }
    }

    func finishOldestPendingFrame() throws {
        let pending = pendingFrames.removeFirst()
        let metalCompleteStart = timingNowSeconds()
        let frameAnalysis = try metalContext.completeFrame(pending.encoded)
        timings.metalCompleteSeconds += timingNowSeconds() - metalCompleteStart
        completedEncodedFrameCount += 1
        if completedEncodedFrameCount % textureCacheFlushInterval == 0 {
            metalContext.flushTextureCache()
        }
        let ridgeLineMotion = MetalAnalysisContext.ridgeLineMotion(
            previous: previousRidgeLineProfile,
            current: frameAnalysis.ridgeLineProfile
        )
        previousRidgeLineProfile = frameAnalysis.ridgeLineProfile
        guard pending.shouldOutput else {
            return
        }
        let frame = AnalysisFrame(
            time: pending.time,
            pixels: [],
            sampleWidth: sample.width,
            sampleHeight: sample.height,
            blurAmount: frameAnalysis.metrics.blurAmount,
            fingerprint: frameAnalysis.metrics.fingerprint
        )
        if let motion = frameAnalysis.motion {
            motions.append(pairMotion(motion, applying: ridgeLineMotion))
        } else {
            motions.append(.zero)
        }
        frames.append(frame)
        if let progressReporter {
            progressReporter.completeFrame()
        } else if progressEvery > 0 && frames.count % progressEvery == 0 {
            progressUpdate(progressEnabled, "progress \(planName): \(frames.count) frame(s)")
        }
    }

    while true {
        if pendingFrames.count >= inFlightLimit {
            try finishOldestPendingFrame()
        }
        let shouldContinue = try autoreleasepool {
            let decodeStart = timingNowSeconds()
            let nextFrame = try frameReader.copyNextFrame()
            timings.decoderCopyNextFrameSeconds += timingNowSeconds() - decodeStart
            guard let decodedFrame = nextFrame else {
                return false
            }
            if let maxFrames, frames.count + pendingOutputFrameCount() >= maxFrames {
                return false
            }
            let pixelBuffer = decodedFrame.pixelBuffer
            let pts = decodedFrame.presentationSeconds
            if firstPTS == nil {
                firstPTS = pts
            }
            let time = max(0, pts - (firstPTS ?? pts))
            if !chunk.isLast && time >= chunk.outputEndSeconds - frameTimeEpsilon {
                return false
            }
            let shouldOutput = time + frameTimeEpsilon >= chunk.outputStartSeconds
                && (chunk.isLast || time < chunk.outputEndSeconds - frameTimeEpsilon)
            if shouldOutput && chunk.requiresPreviousFrame && !sawOutputFrame && previousLumaBuffer == nil {
                throw AnalyzerError("parallel reader chunk \(chunk.index + 1) for \(planName) did not receive the required overlap frame")
            }
            let currentFrameSlot = frameSlots[currentFrameSlotIndex]
            let metalEncodeStart = timingNowSeconds()
            let encodedFrame = try metalContext.encodeFrame(
                from: pixelBuffer,
                sampleWidth: sample.width,
                sampleHeight: sample.height,
                outputBuffer: currentFrameSlot.lumaBuffer,
                blurResultBuffer: currentFrameSlot.blurResultBuffer,
                fingerprintResultBuffer: currentFrameSlot.fingerprintResultBuffer,
                partialSumBuffer: currentFrameSlot.partialSumBuffer,
                partialCountBuffer: currentFrameSlot.partialCountBuffer,
                coarseResultBuffer: currentFrameSlot.coarseResultBuffer,
                resultBuffer: currentFrameSlot.resultBuffer,
                previousBuffer: shouldOutput ? previousLumaBuffer : nil
            )
            timings.metalEncodeSeconds += timingNowSeconds() - metalEncodeStart
            pendingFrames.append((encoded: encodedFrame, time: time, shouldOutput: shouldOutput))
            previousLumaBuffer = currentFrameSlot.lumaBuffer
            currentFrameSlotIndex = (currentFrameSlotIndex + 1) % frameSlots.count
            if shouldOutput {
                sawOutputFrame = true
                progressReporter?.submitFrame()
            }
            return true
        }
        if !shouldContinue {
            break
        }
        if let maxFrames, frames.count + pendingOutputFrameCount() >= maxFrames {
            break
        }
    }
    while !pendingFrames.isEmpty {
        try finishOldestPendingFrame()
    }
    let chunkWallSeconds = timingNowSeconds() - chunkWallStart
    timings.readFramesWallSeconds = chunkWallSeconds
    timings.readerLaneWallSeconds = chunkWallSeconds
    return FrameChunkResult(index: chunk.index, frames: frames, motions: motions, timings: timings)
}

private func readFramesInParallel(
    url: URL,
    plan: AssetPlan,
    sample: AnalysisSampleSize,
    sourcePixelCount: Int,
    decoderPlan: DecoderLanePlan,
    maxFrames: Int?,
    progressEnabled: Bool
) throws -> ReadFramesResult {
    let readWallStart = timingNowSeconds()
    let frameDuration = plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0
    let analysisDuration = analysisDurationSeconds(
        durationSeconds: plan.durationSeconds,
        frameDurationSeconds: frameDuration,
        maxFrames: maxFrames
    )
    let chunks = makeFrameReadChunks(
        durationSeconds: analysisDuration,
        frameDurationSeconds: frameDuration,
        readerLaneCount: decoderPlan.laneCount
    )
    var aggregateTimings = FrameReadTimingAccumulator()
    let basePTSStart = timingNowSeconds()
    let basePTS = try firstPresentationTimeSeconds(url: url)
    aggregateTimings.decoderCopyNextFrameSeconds += timingNowSeconds() - basePTSStart
    let inFlightLimit = analyzerInFlightLimit(pixelCount: sample.width * sample.height, readerLaneCount: chunks.count)
    let textureCacheFlushInterval = analyzerTextureCacheFlushInterval(sourcePixelCount: sourcePixelCount)
    progress(progressEnabled, "using \(chunks.count) \(decoderPlan.description) Metal reader lane(s) with \(inFlightLimit) in-flight GPU frame slot(s) each (\(chunks.count * inFlightLimit) total), flushing Metal texture cache \(textureCacheFlushDescription(interval: textureCacheFlushInterval)) for \(plan.name)")
    let progressReporter = AnalyzerFrameProgressReporter(
        enabled: progressEnabled,
        label: plan.name,
        totalFrameCount: estimatedFrameCount(
            durationSeconds: analysisDuration,
            frameDurationSeconds: frameDuration
        )
    )
    progressReporter.start()
    let resultLock = NSLock()
    let group = DispatchGroup()
    var results = Array<FrameChunkResult?>(repeating: nil, count: chunks.count)
    var firstError: Error?
    for chunk in chunks {
        let expectedOutputFrameCount = estimatedFrameCount(
            durationSeconds: max(
                frameDuration,
                chunk.outputEndSeconds - chunk.outputStartSeconds
            ),
            frameDurationSeconds: frameDuration
        )
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                let context = try MetalAnalysisContext()
                let result = try readFrameChunk(
                    url: url,
                    planName: plan.name,
                    sample: sample,
                    sourcePixelCount: sourcePixelCount,
                    chunk: chunk,
                    basePresentationTimeSeconds: basePTS,
                    maxFrames: nil,
                    progressEnabled: false,
                    progressEvery: 0,
                    progressReporter: progressReporter,
                    inFlightLimit: inFlightLimit,
                    expectedOutputFrameCount: expectedOutputFrameCount,
                    metalContext: context,
                    decoderMode: decoderPlan.mode
                )
                resultLock.lock()
                results[chunk.index] = result
                resultLock.unlock()
            } catch {
                resultLock.lock()
                if firstError == nil {
                    firstError = error
                }
                resultLock.unlock()
            }
        }
    }
    group.wait()
    if let firstError {
        throw firstError
    }
    progressReporter.finish()
    var combinedFrames: [AnalysisFrame] = []
    var combinedMotions: [PairMotion] = []
    let combinedCapacity = results.reduce(0) { total, result in
        total + (result?.frames.count ?? 0)
    }
    combinedFrames.reserveCapacity(combinedCapacity)
    combinedMotions.reserveCapacity(combinedCapacity)
    for index in 0..<results.count {
        guard let result = results[index] else {
            throw AnalyzerError("parallel reader chunk \(index + 1) did not produce a result")
        }
        combinedFrames.append(contentsOf: result.frames)
        combinedMotions.append(contentsOf: result.motions)
        aggregateTimings.readerLaneWallSeconds += result.timings.readFramesWallSeconds
        aggregateTimings.decoderCopyNextFrameSeconds += result.timings.decoderCopyNextFrameSeconds
        aggregateTimings.metalEncodeSeconds += result.timings.metalEncodeSeconds
        aggregateTimings.metalCompleteSeconds += result.timings.metalCompleteSeconds
        results[index] = nil
    }
    guard combinedFrames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(combinedFrames.count)")
    }
    aggregateTimings.readFramesWallSeconds = timingNowSeconds() - readWallStart
    aggregateTimings.readerLaneCount = chunks.count
    let prepareStart = timingNowSeconds()
    let prepared = try prepare(frames: combinedFrames, motions: combinedMotions)
    aggregateTimings.preparedPathSeconds = timingNowSeconds() - prepareStart
    return ReadFramesResult(prepared: prepared, timings: aggregateTimings)
}

private func readFrames(
    asset plan: AssetPlan,
    sampleScalePercent: Double,
    maxFrames: Int?,
    progressEnabled: Bool,
    metalContext: MetalAnalysisContext,
    allowParallelReaders: Bool
) throws -> ReadFramesResult {
    guard plan.mediaKind == "original-media" || plan.mediaKind == "asset-src" else {
        throw AnalyzerError("analysis requires original media; got \(plan.mediaKind ?? "unknown") for \(plan.name)")
    }
    let url = URL(fileURLWithPath: plan.mediaPath)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw AnalyzerError("asset had no video track: \(plan.mediaPath)")
    }
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let sourceWidth = max(1, Int(abs(transformed.width).rounded()))
    let sourceHeight = max(1, Int(abs(transformed.height).rounded()))
    let size = sampleSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight, scalePercent: sampleScalePercent)
    let sample = AnalysisSampleSize(width: size.width, height: size.height)
    let sourcePixelCount = sourceWidth * sourceHeight
    let readerLaneProbeLimit = analyzerReaderLaneProbeLimit()
    if allowParallelReaders && shouldUseParallelReaders(plan: plan, maxFrames: maxFrames, readerLaneCount: readerLaneProbeLimit) {
        let decoderPlan = try decoderLanePlan(url: url, requestedLimit: readerLaneProbeLimit)
        if decoderPlan.laneCount < readerLaneProbeLimit {
            progress(progressEnabled, "\(decoderPlan.description) accepted \(decoderPlan.laneCount)/\(readerLaneProbeLimit) active processor reader lane(s) for \(plan.name); using the decoder-detected maximum")
        }
        return try readFramesInParallel(
            url: url,
            plan: plan,
            sample: sample,
            sourcePixelCount: sourcePixelCount,
            decoderPlan: decoderPlan,
            maxFrames: maxFrames,
            progressEnabled: progressEnabled
        )
    }
    let serialDecoderPlan = try decoderLanePlan(url: url, requestedLimit: 1)
    let serialChunk = FrameReadChunk(
        index: 0,
        totalCount: 1,
        readStartSeconds: nil,
        readEndSeconds: nil,
        outputStartSeconds: 0.0,
        outputEndSeconds: Double.greatestFiniteMagnitude,
        requiresPreviousFrame: false,
        isLast: true
    )
    let progressReporter = AnalyzerFrameProgressReporter(
        enabled: progressEnabled,
        label: plan.name,
        totalFrameCount: estimatedFrameCount(
            durationSeconds: plan.durationSeconds,
            frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
            maxFrames: maxFrames
        )
    )
    progressReporter.start()
    let inFlightLimit = analyzerInFlightLimit(pixelCount: sample.width * sample.height, readerLaneCount: 1)
    let textureCacheFlushInterval = analyzerTextureCacheFlushInterval(sourcePixelCount: sourcePixelCount)
    progress(progressEnabled, "using 1 \(serialDecoderPlan.description) Metal reader lane with \(inFlightLimit) in-flight GPU frame slot(s), flushing Metal texture cache \(textureCacheFlushDescription(interval: textureCacheFlushInterval)) for \(plan.name)")
    let expectedOutputFrameCount = estimatedFrameCount(
        durationSeconds: plan.durationSeconds,
        frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
        maxFrames: maxFrames
    )
    let result = try readFrameChunk(
        url: url,
        planName: plan.name,
        sample: sample,
        sourcePixelCount: sourcePixelCount,
        chunk: serialChunk,
        basePresentationTimeSeconds: nil,
        maxFrames: maxFrames,
        progressEnabled: progressEnabled,
        progressEvery: 30,
        progressReporter: progressReporter,
        inFlightLimit: inFlightLimit,
        expectedOutputFrameCount: expectedOutputFrameCount,
        metalContext: metalContext,
        decoderMode: serialDecoderPlan.mode
    )
    progressReporter.finish()
    guard result.frames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(result.frames.count)")
    }
    var timings = result.timings
    let prepareStart = timingNowSeconds()
    let prepared = try prepare(frames: result.frames, motions: result.motions)
    timings.preparedPathSeconds = timingNowSeconds() - prepareStart
    return ReadFramesResult(prepared: prepared, timings: timings)
}

func timeKey(_ seconds: Double) -> Int64 {
    Int64((seconds * 600.0).rounded())
}

func safeFileComponent(_ value: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let mapped = value.map { allowed.contains($0) ? String($0) : "-" }.joined()
    let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    return String((trimmed.isEmpty ? "clip" : trimmed).prefix(80))
}

func fingerprints(_ frames: [AnalysisFrame]) throws -> (first: String, middle: String, last: String) {
    guard let first = frames.first?.fingerprint, let last = frames.last?.fingerprint else {
        throw AnalyzerError("missing frame fingerprints")
    }
    return (first, frames[frames.count / 2].fingerprint, last)
}

func rangeEndSeconds(cache: PersistedHostAnalysisCache) -> Double {
    if let rangeEndSeconds = cache.rangeEndSeconds, rangeEndSeconds.isFinite {
        return rangeEndSeconds
    }
    return cache.rangeStartSeconds + cache.rangeDurationSeconds
}

func cacheIdentity(cache: PersistedHostAnalysisCache, frames: [AnalysisFrame]) throws -> String {
    let fp = try fingerprints(frames)
    return [
        "\(cache.schemaVersion)",
        "\(timeKey(cache.rangeStartSeconds))",
        "\(timeKey(cache.rangeDurationSeconds))",
        "\(timeKey(cache.frameDurationSeconds))",
        "\(cache.sampleWidth)",
        "\(cache.sampleHeight)",
        "\(frames.count)",
        fp.first,
        fp.middle,
        fp.last,
        "end\(timeKey(rangeEndSeconds(cache: cache)))",
        safeFileComponent(cache.clipLabel ?? "clip"),
    ].joined(separator: ":")
}

func cacheFileName(cache: PersistedHostAnalysisCache, frames: [AnalysisFrame]) throws -> String {
    let fp = try fingerprints(frames)
    let end = rangeEndSeconds(cache: cache)
    return "host-analysis-v2-\(safeFileComponent(cache.clipLabel ?? "clip"))-start\(timeKey(cache.rangeStartSeconds))-end\(timeKey(end))-sample\(cache.sampleWidth)x\(cache.sampleHeight)-n\(frames.count)-\(fp.first.prefix(12))-\(fp.middle.prefix(12))-\(fp.last.prefix(12)).json"
}

func buildCache(asset: AssetPlan, eventName: String?, prepared: PreparedAnalysis, sampleScalePercent: Double, maxFrames: Int?) -> PersistedHostAnalysisCache {
    let firstTime = prepared.frames.first?.time ?? 0
    let lastTime = prepared.frames.last?.time ?? firstTime
    let frameDuration = asset.frameDurationSeconds > 0 ? asset.frameDurationSeconds : max(1.0 / 30.0, lastTime - firstTime)
    let fullDuration = asset.durationSeconds
    let analyzedDuration = maxFrames == nil ? fullDuration : max(frameDuration, (lastTime - firstTime) + frameDuration)
    let sampleWidth = prepared.frames.first?.sampleWidth ?? max(32, asset.width ?? 32)
    let sampleHeight = prepared.frames.first?.sampleHeight ?? max(24, asset.height ?? 24)
    return PersistedHostAnalysisCache(
        schemaVersion: cacheSchemaVersion,
        createdAt: Date().timeIntervalSince1970,
        clipLabel: asset.name,
        rangeStartSeconds: 0,
        rangeDurationSeconds: analyzedDuration,
        rangeEndSeconds: analyzedDuration,
        frameDurationSeconds: frameDuration,
        sampleWidth: sampleWidth,
        sampleHeight: sampleHeight,
        eventName: eventName,
        frames: prepared.frames,
        residuals: prepared.residuals,
        rollMotion: prepared.rollMotion,
        pathX: prepared.pathX,
        pathY: prepared.pathY,
        pathRoll: prepared.pathRoll,
        farFieldPathX: prepared.farFieldPathX,
        farFieldPathY: prepared.farFieldPathY,
        farFieldPathRoll: prepared.farFieldPathRoll,
        farFieldConfidence: prepared.farFieldConfidence,
        footstepPathX: prepared.footstepPathX,
        footstepPathY: prepared.footstepPathY,
        footstepPathRoll: prepared.footstepPathRoll,
        pathYaw: prepared.pathYaw,
        pathPitch: prepared.pathPitch,
        pathShearX: prepared.pathShearX,
        pathShearY: prepared.pathShearY,
        pathPerspectiveX: prepared.pathPerspectiveX,
        pathPerspectiveY: prepared.pathPerspectiveY,
        lensBandTopPathX: prepared.lensBandTopPathX,
        lensBandTopPathY: prepared.lensBandTopPathY,
        lensBandTopColumnPathX: prepared.lensBandTopColumnPathX,
        lensBandTopColumnPathY: prepared.lensBandTopColumnPathY,
        lensBandTopRowPhasePathX: prepared.lensBandTopRowPhasePathX,
        lensBandTopRowPhasePathY: prepared.lensBandTopRowPhasePathY,
        lensBandTopLocalRollPath: prepared.lensBandTopLocalRollPath,
        lensBandRidgePathX: prepared.lensBandRidgePathX,
        lensBandRidgePathY: prepared.lensBandRidgePathY,
        lensBandRidgeColumnPathX: prepared.lensBandRidgeColumnPathX,
        lensBandRidgeColumnPathY: prepared.lensBandRidgeColumnPathY,
        lensBandRidgeRowPhasePathX: prepared.lensBandRidgeRowPhasePathX,
        lensBandRidgeRowPhasePathY: prepared.lensBandRidgeRowPhasePathY,
        lensBandRidgeLocalRollPath: prepared.lensBandRidgeLocalRollPath,
        lensBandMidPathX: prepared.lensBandMidPathX,
        lensBandMidPathY: prepared.lensBandMidPathY,
        lensBandMidColumnPathX: prepared.lensBandMidColumnPathX,
        lensBandMidColumnPathY: prepared.lensBandMidColumnPathY,
        lensBandMidRowPhasePathX: prepared.lensBandMidRowPhasePathX,
        lensBandMidRowPhasePathY: prepared.lensBandMidRowPhasePathY,
        lensBandMidLocalRollPath: prepared.lensBandMidLocalRollPath,
        lensBandTopConfidence: prepared.lensBandTopConfidence,
        lensBandRidgeConfidence: prepared.lensBandRidgeConfidence,
        lensBandMidConfidence: prepared.lensBandMidConfidence,
        lensBandConfidence: prepared.lensBandConfidence,
        farFieldRigidShakePathX: prepared.farFieldRigidShakePathX,
        farFieldRigidShakePathY: prepared.farFieldRigidShakePathY,
        farFieldRigidShakeSupport: prepared.farFieldRigidShakeSupport,
        farFieldRigidShakeShapeConsistency: prepared.farFieldRigidShakeShapeConsistency,
        farFieldRigidShakeForwardBackwardConsistency: prepared.farFieldRigidShakeForwardBackwardConsistency,
        farFieldMeshRows: prepared.farFieldMeshRows,
        farFieldMeshColumns: prepared.farFieldMeshColumns,
        farFieldMeshPathX: prepared.farFieldMeshPathX,
        farFieldMeshPathY: prepared.farFieldMeshPathY,
        farFieldMeshSupport: prepared.farFieldMeshSupport,
        farFieldMeshDominantWindowFrames: prepared.farFieldMeshDominantWindowFrames,
        farFieldMeshDominantWindowSeconds: prepared.farFieldMeshDominantWindowSeconds,
        farFieldMeshDominantSupport: prepared.farFieldMeshDominantSupport,
        farFieldMeshDominantCell: prepared.farFieldMeshDominantCell,
        sourceLensShakeRidgePathY: prepared.sourceLensShakeRidgePathY,
        sourceLensShakeRidgeSupport: prepared.sourceLensShakeRidgeSupport,
        sourceLensShakeRidgeLinePathY: prepared.sourceLensShakeRidgeLinePathY,
        sourceLensShakeRidgeLineSupport: prepared.sourceLensShakeRidgeLineSupport,
        sourceLensShakeLocalBinCount: prepared.sourceLensShakeLocalBinCount,
        sourceLensShakeLocalPathX: prepared.sourceLensShakeLocalPathX,
        sourceLensShakeLocalPathY: prepared.sourceLensShakeLocalPathY,
        sourceLensShakeLocalSupport: prepared.sourceLensShakeLocalSupport,
        analysisConfidence: prepared.analysisConfidence,
        warpConfidence: prepared.warpConfidence,
        acceptedBlockCounts: prepared.acceptedBlockCounts,
        totalBlockCounts: prepared.totalBlockCounts,
        blurAmounts: prepared.blurAmounts,
        searchRadiusHitCounts: prepared.searchRadiusHitCounts,
        searchRadiusTotalCounts: prepared.searchRadiusTotalCounts
    )
}

func indexEntry(cache: PersistedHostAnalysisCache, fileName: String, identity: String, frames: [AnalysisFrame]) throws -> PersistedHostAnalysisIndexEntry {
    let fp = try fingerprints(frames)
    return PersistedHostAnalysisIndexEntry(
        cacheFileName: fileName,
        createdAt: cache.createdAt,
        clipLabel: cache.clipLabel,
        rangeStartSeconds: cache.rangeStartSeconds,
        rangeDurationSeconds: cache.rangeDurationSeconds,
        rangeEndSeconds: rangeEndSeconds(cache: cache),
        frameDurationSeconds: cache.frameDurationSeconds,
        sampleWidth: cache.sampleWidth,
        sampleHeight: cache.sampleHeight,
        frameCount: frames.count,
        firstFingerprint: fp.first,
        middleFingerprint: fp.middle,
        lastFingerprint: fp.last,
        fingerprints: [fp.first, fp.middle, fp.last],
        cacheIdentity: identity
    )
}

private final class UTF8FileWriter {
    private let handle: FileHandle

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ value: String) {
        handle.write(Data(value.utf8))
    }

    func close() throws {
        try handle.close()
    }
}

private func jsonNumber(_ value: Double, field: String) throws -> String {
    guard value.isFinite else {
        throw AnalyzerError("cache field \(field) contained a non-finite number")
    }
    return String(value)
}

private func jsonNumber(_ value: Float, field: String) throws -> String {
    guard value.isFinite else {
        throw AnalyzerError("cache field \(field) contained a non-finite number")
    }
    return String(value)
}

private func writeJSONString(_ value: String, to writer: UTF8FileWriter) {
    writer.write("\"")
    var buffer = ""
    buffer.reserveCapacity(min(4096, value.count + 16))
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x08:
            buffer += "\\b"
        case 0x09:
            buffer += "\\t"
        case 0x0A:
            buffer += "\\n"
        case 0x0C:
            buffer += "\\f"
        case 0x0D:
            buffer += "\\r"
        case 0x22:
            buffer += "\\\""
        case 0x5C:
            buffer += "\\\\"
        case 0x00..<0x20:
            buffer += String(format: "\\u%04X", scalar.value)
        default:
            buffer.unicodeScalars.append(scalar)
        }
        if buffer.utf8.count >= 16 * 1024 {
            writer.write(buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
    if !buffer.isEmpty {
        writer.write(buffer)
    }
    writer.write("\"")
}

private func writeFloatArray(_ values: [Float], field: String, to writer: UTF8FileWriter) throws {
    writer.write("[")
    var buffer = ""
    buffer.reserveCapacity(64 * 1024)
    for index in values.indices {
        if index > values.startIndex {
            buffer += ","
        }
        buffer += try jsonNumber(values[index], field: "\(field)[\(index)]")
        if buffer.utf8.count >= 64 * 1024 {
            writer.write(buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
    if !buffer.isEmpty {
        writer.write(buffer)
    }
    writer.write("]")
}

private func writeInt32Array(_ values: [Int32], to writer: UTF8FileWriter) {
    writer.write("[")
    var buffer = ""
    buffer.reserveCapacity(64 * 1024)
    for index in values.indices {
        if index > values.startIndex {
            buffer += ","
        }
        buffer += String(values[index])
        if buffer.utf8.count >= 64 * 1024 {
            writer.write(buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
    if !buffer.isEmpty {
        writer.write(buffer)
    }
    writer.write("]")
}

private func writeFrames(_ frames: [AnalysisFrame], to writer: UTF8FileWriter) throws {
    writer.write("[")
    for index in frames.indices {
        if index > frames.startIndex {
            writer.write(",")
        }
        let frame = frames[index]
        writer.write("{\"time\":")
        writer.write(try jsonNumber(frame.time, field: "frames[\(index)].time"))
        writer.write(",\"pixels\":null,\"blurAmount\":")
        writer.write(try jsonNumber(frame.blurAmount, field: "frames[\(index)].blurAmount"))
        writer.write(",\"fingerprint\":")
        writeJSONString(frame.fingerprint, to: writer)
        writer.write("}")
    }
    writer.write("]")
}

private func replaceFileAtomically(at destinationURL: URL, withTemporaryFileAt temporaryURL: URL) throws {
    let fileManager = FileManager.default
    do {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    } catch {
        try? fileManager.removeItem(at: temporaryURL)
        throw error
    }
}

private func writeCacheJSON(_ cache: PersistedHostAnalysisCache, to destinationURL: URL) throws {
    let fileManager = FileManager.default
    let temporaryURL = destinationURL
        .deletingLastPathComponent()
        .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
    try? fileManager.removeItem(at: temporaryURL)
    let writer = try UTF8FileWriter(url: temporaryURL)
    do {
        var wroteField = false

        func beginField(_ name: String) {
            if wroteField {
                writer.write(",")
            }
            writeJSONString(name, to: writer)
            writer.write(":")
            wroteField = true
        }

        func writeDoubleField(_ name: String, _ value: Double) throws {
            beginField(name)
            writer.write(try jsonNumber(value, field: name))
        }

        func writeIntField(_ name: String, _ value: Int) {
            beginField(name)
            writer.write(String(value))
        }

        func writeOptionalDoubleField(_ name: String, _ value: Double?) throws {
            guard let value else { return }
            try writeDoubleField(name, value)
        }

        func writeOptionalStringField(_ name: String, _ value: String?) {
            guard let value else { return }
            beginField(name)
            writeJSONString(value, to: writer)
        }

        func writeOptionalFloatArrayField(_ name: String, _ values: [Float]?) throws {
            guard let values else { return }
            beginField(name)
            try writeFloatArray(values, field: name, to: writer)
        }

        func writeOptionalInt32ArrayField(_ name: String, _ values: [Int32]?) {
            guard let values else { return }
            beginField(name)
            writeInt32Array(values, to: writer)
        }

        writer.write("{")
        beginField("schemaVersion")
        writer.write(String(cache.schemaVersion))
        try writeDoubleField("createdAt", cache.createdAt)
        writeOptionalStringField("clipLabel", cache.clipLabel)
        try writeDoubleField("rangeStartSeconds", cache.rangeStartSeconds)
        try writeDoubleField("rangeDurationSeconds", cache.rangeDurationSeconds)
        try writeOptionalDoubleField("rangeEndSeconds", cache.rangeEndSeconds)
        try writeDoubleField("frameDurationSeconds", cache.frameDurationSeconds)
        beginField("sampleWidth")
        writer.write(String(cache.sampleWidth))
        beginField("sampleHeight")
        writer.write(String(cache.sampleHeight))
        writeOptionalStringField("eventName", cache.eventName)
        beginField("frames")
        try writeFrames(cache.frames, to: writer)
        try writeOptionalFloatArrayField("residuals", cache.residuals)
        try writeOptionalFloatArrayField("rollMotion", cache.rollMotion)
        try writeOptionalFloatArrayField("pathX", cache.pathX)
        try writeOptionalFloatArrayField("pathY", cache.pathY)
        try writeOptionalFloatArrayField("pathRoll", cache.pathRoll)
        try writeOptionalFloatArrayField("farFieldPathX", cache.farFieldPathX)
        try writeOptionalFloatArrayField("farFieldPathY", cache.farFieldPathY)
        try writeOptionalFloatArrayField("farFieldPathRoll", cache.farFieldPathRoll)
        try writeOptionalFloatArrayField("farFieldConfidence", cache.farFieldConfidence)
        try writeOptionalFloatArrayField("footstepPathX", cache.footstepPathX)
        try writeOptionalFloatArrayField("footstepPathY", cache.footstepPathY)
        try writeOptionalFloatArrayField("footstepPathRoll", cache.footstepPathRoll)
        try writeOptionalFloatArrayField("pathYaw", cache.pathYaw)
        try writeOptionalFloatArrayField("pathPitch", cache.pathPitch)
        try writeOptionalFloatArrayField("pathShearX", cache.pathShearX)
        try writeOptionalFloatArrayField("pathShearY", cache.pathShearY)
        try writeOptionalFloatArrayField("pathPerspectiveX", cache.pathPerspectiveX)
        try writeOptionalFloatArrayField("pathPerspectiveY", cache.pathPerspectiveY)
        try writeOptionalFloatArrayField("lensBandTopPathX", cache.lensBandTopPathX)
        try writeOptionalFloatArrayField("lensBandTopPathY", cache.lensBandTopPathY)
        try writeOptionalFloatArrayField("lensBandTopColumnPathX", cache.lensBandTopColumnPathX)
        try writeOptionalFloatArrayField("lensBandTopColumnPathY", cache.lensBandTopColumnPathY)
        try writeOptionalFloatArrayField("lensBandTopRowPhasePathX", cache.lensBandTopRowPhasePathX)
        try writeOptionalFloatArrayField("lensBandTopRowPhasePathY", cache.lensBandTopRowPhasePathY)
        try writeOptionalFloatArrayField("lensBandTopLocalRollPath", cache.lensBandTopLocalRollPath)
        try writeOptionalFloatArrayField("lensBandRidgePathX", cache.lensBandRidgePathX)
        try writeOptionalFloatArrayField("lensBandRidgePathY", cache.lensBandRidgePathY)
        try writeOptionalFloatArrayField("lensBandRidgeColumnPathX", cache.lensBandRidgeColumnPathX)
        try writeOptionalFloatArrayField("lensBandRidgeColumnPathY", cache.lensBandRidgeColumnPathY)
        try writeOptionalFloatArrayField("lensBandRidgeRowPhasePathX", cache.lensBandRidgeRowPhasePathX)
        try writeOptionalFloatArrayField("lensBandRidgeRowPhasePathY", cache.lensBandRidgeRowPhasePathY)
        try writeOptionalFloatArrayField("lensBandRidgeLocalRollPath", cache.lensBandRidgeLocalRollPath)
        try writeOptionalFloatArrayField("lensBandMidPathX", cache.lensBandMidPathX)
        try writeOptionalFloatArrayField("lensBandMidPathY", cache.lensBandMidPathY)
        try writeOptionalFloatArrayField("lensBandMidColumnPathX", cache.lensBandMidColumnPathX)
        try writeOptionalFloatArrayField("lensBandMidColumnPathY", cache.lensBandMidColumnPathY)
        try writeOptionalFloatArrayField("lensBandMidRowPhasePathX", cache.lensBandMidRowPhasePathX)
        try writeOptionalFloatArrayField("lensBandMidRowPhasePathY", cache.lensBandMidRowPhasePathY)
        try writeOptionalFloatArrayField("lensBandMidLocalRollPath", cache.lensBandMidLocalRollPath)
        try writeOptionalFloatArrayField("lensBandTopConfidence", cache.lensBandTopConfidence)
        try writeOptionalFloatArrayField("lensBandRidgeConfidence", cache.lensBandRidgeConfidence)
        try writeOptionalFloatArrayField("lensBandMidConfidence", cache.lensBandMidConfidence)
        try writeOptionalFloatArrayField("lensBandConfidence", cache.lensBandConfidence)
        try writeOptionalFloatArrayField("farFieldRigidShakePathX", cache.farFieldRigidShakePathX)
        try writeOptionalFloatArrayField("farFieldRigidShakePathY", cache.farFieldRigidShakePathY)
        try writeOptionalFloatArrayField("farFieldRigidShakeSupport", cache.farFieldRigidShakeSupport)
        try writeOptionalFloatArrayField("farFieldRigidShakeShapeConsistency", cache.farFieldRigidShakeShapeConsistency)
        try writeOptionalFloatArrayField("farFieldRigidShakeForwardBackwardConsistency", cache.farFieldRigidShakeForwardBackwardConsistency)
        if let farFieldMeshRows = cache.farFieldMeshRows {
            writeIntField("farFieldMeshRows", farFieldMeshRows)
        }
        if let farFieldMeshColumns = cache.farFieldMeshColumns {
            writeIntField("farFieldMeshColumns", farFieldMeshColumns)
        }
        try writeOptionalFloatArrayField("farFieldMeshPathX", cache.farFieldMeshPathX)
        try writeOptionalFloatArrayField("farFieldMeshPathY", cache.farFieldMeshPathY)
        try writeOptionalFloatArrayField("farFieldMeshSupport", cache.farFieldMeshSupport)
        try writeOptionalFloatArrayField("farFieldMeshDominantWindowFrames", cache.farFieldMeshDominantWindowFrames)
        try writeOptionalFloatArrayField("farFieldMeshDominantWindowSeconds", cache.farFieldMeshDominantWindowSeconds)
        try writeOptionalFloatArrayField("farFieldMeshDominantSupport", cache.farFieldMeshDominantSupport)
        writeOptionalInt32ArrayField("farFieldMeshDominantCell", cache.farFieldMeshDominantCell)
        try writeOptionalFloatArrayField("sourceLensShakeRidgePathY", cache.sourceLensShakeRidgePathY)
        try writeOptionalFloatArrayField("sourceLensShakeRidgeSupport", cache.sourceLensShakeRidgeSupport)
        try writeOptionalFloatArrayField("sourceLensShakeRidgeLinePathY", cache.sourceLensShakeRidgeLinePathY)
        try writeOptionalFloatArrayField("sourceLensShakeRidgeLineSupport", cache.sourceLensShakeRidgeLineSupport)
        if let sourceLensShakeLocalBinCount = cache.sourceLensShakeLocalBinCount {
            writeIntField("sourceLensShakeLocalBinCount", sourceLensShakeLocalBinCount)
        }
        try writeOptionalFloatArrayField("sourceLensShakeLocalPathX", cache.sourceLensShakeLocalPathX)
        try writeOptionalFloatArrayField("sourceLensShakeLocalPathY", cache.sourceLensShakeLocalPathY)
        try writeOptionalFloatArrayField("sourceLensShakeLocalSupport", cache.sourceLensShakeLocalSupport)
        try writeOptionalFloatArrayField("analysisConfidence", cache.analysisConfidence)
        try writeOptionalFloatArrayField("warpConfidence", cache.warpConfidence)
        writeOptionalInt32ArrayField("acceptedBlockCounts", cache.acceptedBlockCounts)
        writeOptionalInt32ArrayField("totalBlockCounts", cache.totalBlockCounts)
        try writeOptionalFloatArrayField("blurAmounts", cache.blurAmounts)
        writeOptionalInt32ArrayField("searchRadiusHitCounts", cache.searchRadiusHitCounts)
        writeOptionalInt32ArrayField("searchRadiusTotalCounts", cache.searchRadiusTotalCounts)
        writer.write("}")
        try writer.close()
        try replaceFileAtomically(at: destinationURL, withTemporaryFileAt: temporaryURL)
    } catch {
        try? writer.close()
        try? fileManager.removeItem(at: temporaryURL)
        throw error
    }
}

func copyFileAtomically(from sourceURL: URL, to destinationURL: URL) throws {
    let fileManager = FileManager.default
    let temporaryURL = destinationURL
        .deletingLastPathComponent()
        .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
    try? fileManager.removeItem(at: temporaryURL)
    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
    try replaceFileAtomically(at: destinationURL, withTemporaryFileAt: temporaryURL)
}

func writeCache(cacheRoot: URL, asset: AssetPlan, prepared: PreparedAnalysis, cache: PersistedHostAnalysisCache, sampleScalePercent: Double) throws -> AnalysisResult {
    let fileManager = FileManager.default
    let storageURL = cacheRoot.appendingPathComponent(cacheStorageDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    let identity = try cacheIdentity(cache: cache, frames: prepared.frames)
    let fileName = try cacheFileName(cache: cache, frames: prepared.frames)
    let encoder = JSONEncoder()
    let storedCacheURL = storageURL.appendingPathComponent(fileName)
    try writeCacheJSON(cache, to: storedCacheURL)
    try copyFileAtomically(from: storedCacheURL, to: cacheRoot.appendingPathComponent(cacheFileName))

    let indexURL = cacheRoot.appendingPathComponent(cacheIndexFileName)
    var entries: [PersistedHostAnalysisIndexEntry] = []
    if let indexData = try? Data(contentsOf: indexURL),
       let existing = try? JSONDecoder().decode(PersistedHostAnalysisIndex.self, from: indexData),
       existing.schemaVersion == cacheSchemaVersion {
        entries = existing.entries
    }
    entries.removeAll { $0.cacheIdentity == identity || $0.cacheFileName == fileName }
    entries.insert(try indexEntry(cache: cache, fileName: fileName, identity: identity, frames: prepared.frames), at: 0)
    let index = PersistedHostAnalysisIndex(schemaVersion: cacheSchemaVersion, entries: Array(entries.prefix(64)))
    try encoder.encode(index).write(to: indexURL, options: .atomic)

    let fp = try fingerprints(prepared.frames)
    return AnalysisResult(
        assetId: asset.assetId,
        name: asset.name,
        eventName: asset.eventName,
        footageFileName: URL(fileURLWithPath: asset.mediaPath).lastPathComponent,
        mediaPath: asset.mediaPath,
        mediaKind: asset.mediaKind,
        cacheRoot: cacheRoot.path,
        sourceMediaFingerprint: "\(fp.first):\(fp.middle):\(fp.last)",
        cacheFileName: fileName,
        cacheIdentity: identity,
        cacheSchemaVersion: cacheSchemaVersion,
        durationSeconds: asset.durationSeconds,
        sampleScalePercent: sampleScalePercent,
        sampleWidth: cache.sampleWidth,
        sampleHeight: cache.sampleHeight,
        frameCount: prepared.frames.count,
        rangeStartSeconds: cache.rangeStartSeconds,
        rangeDurationSeconds: cache.rangeDurationSeconds,
        rangeEndSeconds: rangeEndSeconds(cache: cache),
        frameDurationSeconds: cache.frameDurationSeconds,
        firstFingerprint: fp.first,
        middleFingerprint: fp.middle,
        lastFingerprint: fp.last,
        preparedMotionPath: !prepared.pathX.isEmpty && !prepared.pathY.isEmpty && !prepared.pathRoll.isEmpty
    )
}

func run() throws {
    let arguments = try parseArguments()
    try validateAnalyzerResourceEnvironment()
    let planData = try Data(contentsOf: arguments.planPath)
    let plan = try JSONDecoder().decode(AnalysisPlan.self, from: planData)
    let metalContext = try MetalAnalysisContext()
    progress(arguments.progress, "using Metal analyzer device: \(metalContext.deviceName)")
    progress(
        arguments.progress,
        "processing \(plan.assets.count) selected asset(s) with hardware-required VideoToolbox decode and Metal GPU analysis"
    )
    var results: [AnalysisResult] = []
    for (assetIndex, asset) in plan.assets.enumerated() {
        progress(arguments.progress, "starting asset \(assetIndex + 1)/\(plan.assets.count): \(asset.name)")
        let totalStart = timingNowSeconds()
        let readResult = try readFrames(
            asset: asset,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames,
            progressEnabled: arguments.progress,
            metalContext: metalContext,
            allowParallelReaders: true
        )
        let prepared = readResult.prepared
        let buildCacheStart = timingNowSeconds()
        let cache = buildCache(
            asset: asset,
            eventName: asset.eventName ?? plan.eventName,
            prepared: prepared,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames
        )
        let buildCacheSeconds = timingNowSeconds() - buildCacheStart
        let writeCacheStart = timingNowSeconds()
        let cacheRoot = URL(fileURLWithPath: asset.cacheRoot, isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        var result = try writeCache(
            cacheRoot: cacheRoot,
            asset: asset,
            prepared: prepared,
            cache: cache,
            sampleScalePercent: plan.sampleScalePercent
        )
        let writeCacheSeconds = timingNowSeconds() - writeCacheStart
        let totalWallSeconds = timingNowSeconds() - totalStart
        result.analysisTimings = AnalysisTimingSummary(
            frameCount: prepared.frames.count,
            totalWallSeconds: totalWallSeconds,
            readFramesWallSeconds: readResult.timings.readFramesWallSeconds,
            readerLaneWallSeconds: readResult.timings.readerLaneWallSeconds,
            decoderCopyNextFrameSeconds: readResult.timings.decoderCopyNextFrameSeconds,
            metalEncodeSeconds: readResult.timings.metalEncodeSeconds,
            metalCompleteSeconds: readResult.timings.metalCompleteSeconds,
            preparedPathSeconds: readResult.timings.preparedPathSeconds,
            cacheBuildSeconds: buildCacheSeconds,
            cacheWriteSeconds: writeCacheSeconds,
            readerLaneCount: readResult.timings.readerLaneCount,
            framesPerWallSecond: Double(max(0, prepared.frames.count)) / max(1e-9, totalWallSeconds)
        )
        progress(arguments.progress, "saved \(result.cacheFileName)")
        results.append(result)
    }
    finishProgressLine(arguments.progress)
    let output = ToolOutput(schemaVersion: toolSchemaVersion, status: "ok", results: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(output))
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

do {
    try run()
} catch {
    finishProgressLine(true)
    let message = (error as? AnalyzerError)?.description ?? error.localizedDescription
    FileHandle.standardError.write(("StabilizerEventAnalyzer: \(message)\n").data(using: .utf8)!)
    exit(1)
}
