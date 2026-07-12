import Darwin
import Foundation

private struct FeedbackError: Error, CustomStringConvertible {
    let description: String
}

private struct Options {
    var cachePath: String?
    var compareCachePath: String?
    var compareTolerance: Float = 0.0005
    var cacheRoot: String?
    var relativeTime: Double?
    var note: String?
    var windowSeconds = 0.25
    var outputSize: (width: Float, height: Float)?
    var json = false
    var limit = 5
    var listCaches = false
    var turnWindowSeconds = renderTurnTransitionSmoothingWindowSeconds
    var turnStrength = 12.0
    var strengths = Strengths.defaults
}

private struct Strengths {
    var cameraX: Double
    var cameraY: Double
    var cameraR: Double
    var microX: Double
    var microY: Double
    var microR: Double
    var strideX: Double
    var strideY: Double
    var strideR: Double
    var warp: Double

    static let defaults = Strengths(
        cameraX: 2.0,
        cameraY: 2.0,
        cameraR: 0.5,
        microX: 4.0,
        microY: 4.0,
        microR: 1.0,
        strideX: 4.0,
        strideY: 4.0,
        strideR: 1.0,
        warp: 1.0
    )
}

private let maximumTurnSmoothingCorrectionAuthority: Float = 36.0

private struct PersistedHostAnalysisCache: Decodable {
    let schemaVersion: Int
    let requestedSampleScalePercent: Double?
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let sourceMediaKind: String?
    let sourceWidth: Int?
    let sourceHeight: Int?
    let sourceFileName: String?
    let frames: [PersistedHostAnalysisFrame]
    let residuals: [Float]?
    let rollMotion: [Float]?
    let pathX: [Float]?
    let pathY: [Float]?
    let pathRoll: [Float]?
    let farFieldPathX: [Float]?
    let farFieldPathY: [Float]?
    let farFieldPathRoll: [Float]?
    let farFieldConfidence: [Float]?
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
    let farFieldRigidShakePathRoll: [Float]?
    let cameraRigidTargetX: [Float]?
    let cameraRigidTargetY: [Float]?
    let cameraRigidTargetRollDegrees: [Float]?
    let farFieldRigidShakeSupport: [Float]?
    let farFieldRigidShakeSupportX: [Float]?
    let farFieldRigidShakeSupportY: [Float]?
    let farFieldRigidShakeRollSupport: [Float]?
    let farFieldRigidShakeShapeConsistency: [Float]?
    let farFieldRigidShakeShapeConsistencyX: [Float]?
    let farFieldRigidShakeShapeConsistencyY: [Float]?
    let farFieldRigidShakeForwardBackwardConsistency: [Float]?
    let farFieldRigidShakeForwardBackwardConsistencyX: [Float]?
    let farFieldRigidShakeForwardBackwardConsistencyY: [Float]?
    let farFieldRigidShakeRollForwardBackwardConsistency: [Float]?
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
    let footstepPathX: [Float]?
    let footstepPathY: [Float]?
    let footstepPathRoll: [Float]?
    let pathYaw: [Float]?
    let pathPitch: [Float]?
    let pathShearX: [Float]?
    let pathShearY: [Float]?
    let pathPerspectiveX: [Float]?
    let pathPerspectiveY: [Float]?
    let analysisConfidence: [Float]?
    let warpConfidence: [Float]?
    let acceptedBlockCounts: [Int32]?
    let totalBlockCounts: [Int32]?
    let blurAmounts: [Float]?
    let searchRadiusHitCounts: [Int32]?
    let searchRadiusTotalCounts: [Int32]?
}

private struct PersistedHostAnalysisFrame: Decodable {
    let time: Double
    let pixels: Data?
    let blurAmount: Float
    let fingerprint: String?
}

private struct CacheInventoryEntry {
    let path: String
    let status: String
    let reason: String
    let schemaVersion: Int?
    let frameCount: Int?
    let rangeStartSeconds: Double?
    let rangeDurationSeconds: Double?
    let requestedSampleScalePercent: Double?
    let sampleWidth: Int?
    let sampleHeight: Int?
    let modifiedAt: Date?
}

private struct AnalysisFrame {
    let time: Double
    let blurAmount: Float
    let fingerprint: String
}

private enum AnalysisQualityModel {
    case fxplugHostAnalysis
    case eventAnalyzerCache
}

private struct Analysis {
    let cachePath: String
    let schemaVersion: Int
    let qualityModel: AnalysisQualityModel
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
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
    let cameraRigidTargetX: [Float]
    let cameraRigidTargetY: [Float]
    let cameraRigidTargetRollDegrees: [Float]
    let farFieldRigidShakeSupport: [Float]
    let farFieldRigidShakeSupportX: [Float]
    let farFieldRigidShakeSupportY: [Float]
    let farFieldRigidShakeRollSupport: [Float]
    let farFieldRigidShakeShapeConsistency: [Float]
    let farFieldRigidShakeShapeConsistencyX: [Float]
    let farFieldRigidShakeShapeConsistencyY: [Float]
    let farFieldRigidShakeForwardBackwardConsistency: [Float]
    let farFieldRigidShakeForwardBackwardConsistencyX: [Float]
    let farFieldRigidShakeForwardBackwardConsistencyY: [Float]
    let farFieldRigidShakeRollForwardBackwardConsistency: [Float]
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

    init(cache: PersistedHostAnalysisCache, cachePath: String) throws {
        guard supportedCacheSchemaVersions.contains(cache.schemaVersion) else {
            throw FeedbackError(description: "unsupported Host Analysis cache schema \(cache.schemaVersion); supported schemas: \(supportedCacheSchemaDescription)")
        }
        guard cache.sourceMediaKind == "original-media" || cache.sourceMediaKind == "asset-src",
              let sourceWidth = cache.sourceWidth,
              let sourceHeight = cache.sourceHeight,
              sourceWidth > 0,
              sourceHeight > 0,
              let sourceFileName = cache.sourceFileName,
              !sourceFileName.isEmpty else {
            throw FeedbackError(description: "schema 51 cache is missing validated original-media provenance")
        }
        let frames = try cache.frames.map { persisted -> AnalysisFrame in
            guard let fingerprint = persisted.fingerprint, !fingerprint.isEmpty else {
                throw FeedbackError(description: "cache frame at \(formatSeconds(persisted.time)) is missing a fingerprint")
            }
            return AnalysisFrame(time: persisted.time, blurAmount: persisted.blurAmount, fingerprint: fingerprint)
        }
        guard frames.count >= 3 else {
            throw FeedbackError(description: "Host Analysis cache has \(frames.count) frames; feedback diagnostics need at least 3")
        }
        for index in 1..<frames.count where frames[index].time <= frames[index - 1].time {
            throw FeedbackError(description: "Host Analysis cache frame times are not strictly increasing near frame \(index)")
        }

        func requireFloatArray(_ value: [Float]?, _ name: String) throws -> [Float] {
            guard let value else {
                throw FeedbackError(description: "Host Analysis cache is missing \(name); rerun Host Analysis with the current FxPlug")
            }
            guard value.count == frames.count else {
                throw FeedbackError(description: "Host Analysis cache is not feedback-ready: \(name) has \(value.count) values but frames has \(frames.count); rerun Host Analysis with the current FxPlug")
            }
            return value
        }

        func requireFloatArray(_ value: [Float]?, _ name: String, count expectedCount: Int) throws -> [Float] {
            guard let value else {
                throw FeedbackError(description: "Host Analysis cache is missing \(name); rerun Host Analysis with the current FxPlug")
            }
            guard value.count == expectedCount else {
                throw FeedbackError(description: "Host Analysis cache is not feedback-ready: \(name) has \(value.count) values but expected \(expectedCount); rerun Host Analysis with the current FxPlug")
            }
            return value
        }

        func requireIntArray(_ value: [Int32]?, _ name: String) throws -> [Int32] {
            guard let value else {
                throw FeedbackError(description: "Host Analysis cache is missing \(name); rerun Host Analysis with the current FxPlug")
            }
            guard value.count == frames.count else {
                throw FeedbackError(description: "Host Analysis cache is not feedback-ready: \(name) has \(value.count) values but frames has \(frames.count); rerun Host Analysis with the current FxPlug")
            }
            return value
        }

        func requireIntArray(_ value: [Int32]?, _ name: String, count expectedCount: Int) throws -> [Int32] {
            guard let value else {
                throw FeedbackError(description: "Host Analysis cache is missing \(name); rerun Host Analysis with the current FxPlug")
            }
            guard value.count == expectedCount else {
                throw FeedbackError(description: "Host Analysis cache is not feedback-ready: \(name) has \(value.count) values but expected \(expectedCount); rerun Host Analysis with the current FxPlug")
            }
            return value
        }

        self.cachePath = cachePath
        schemaVersion = cache.schemaVersion
        qualityModel = analysisQualityModel(for: cache)
        rangeStartSeconds = cache.rangeStartSeconds
        rangeDurationSeconds = cache.rangeDurationSeconds
        frameDurationSeconds = cache.frameDurationSeconds
        sampleWidth = cache.sampleWidth
        sampleHeight = cache.sampleHeight
        self.frames = frames
        residuals = try requireFloatArray(cache.residuals, "residuals")
        rollMotion = try requireFloatArray(cache.rollMotion, "rollMotion")
        pathX = try requireFloatArray(cache.pathX, "pathX")
        pathY = try requireFloatArray(cache.pathY, "pathY")
        pathRoll = try requireFloatArray(cache.pathRoll, "pathRoll")
        farFieldPathX = try requireFloatArray(cache.farFieldPathX, "farFieldPathX")
        farFieldPathY = try requireFloatArray(cache.farFieldPathY, "farFieldPathY")
        farFieldPathRoll = try requireFloatArray(cache.farFieldPathRoll, "farFieldPathRoll")
        farFieldConfidence = try requireFloatArray(cache.farFieldConfidence, "farFieldConfidence")
        lensBandTopPathX = try requireFloatArray(cache.lensBandTopPathX, "lensBandTopPathX")
        lensBandTopPathY = try requireFloatArray(cache.lensBandTopPathY, "lensBandTopPathY")
        lensBandTopColumnPathX = try requireFloatArray(cache.lensBandTopColumnPathX, "lensBandTopColumnPathX")
        lensBandTopColumnPathY = try requireFloatArray(cache.lensBandTopColumnPathY, "lensBandTopColumnPathY")
        lensBandTopRowPhasePathX = try requireFloatArray(cache.lensBandTopRowPhasePathX, "lensBandTopRowPhasePathX")
        lensBandTopRowPhasePathY = try requireFloatArray(cache.lensBandTopRowPhasePathY, "lensBandTopRowPhasePathY")
        lensBandTopLocalRollPath = try requireFloatArray(cache.lensBandTopLocalRollPath, "lensBandTopLocalRollPath")
        lensBandRidgePathX = try requireFloatArray(cache.lensBandRidgePathX, "lensBandRidgePathX")
        lensBandRidgePathY = try requireFloatArray(cache.lensBandRidgePathY, "lensBandRidgePathY")
        lensBandRidgeColumnPathX = try requireFloatArray(cache.lensBandRidgeColumnPathX, "lensBandRidgeColumnPathX")
        lensBandRidgeColumnPathY = try requireFloatArray(cache.lensBandRidgeColumnPathY, "lensBandRidgeColumnPathY")
        lensBandRidgeRowPhasePathX = try requireFloatArray(cache.lensBandRidgeRowPhasePathX, "lensBandRidgeRowPhasePathX")
        lensBandRidgeRowPhasePathY = try requireFloatArray(cache.lensBandRidgeRowPhasePathY, "lensBandRidgeRowPhasePathY")
        lensBandRidgeLocalRollPath = try requireFloatArray(cache.lensBandRidgeLocalRollPath, "lensBandRidgeLocalRollPath")
        lensBandMidPathX = try requireFloatArray(cache.lensBandMidPathX, "lensBandMidPathX")
        lensBandMidPathY = try requireFloatArray(cache.lensBandMidPathY, "lensBandMidPathY")
        lensBandMidColumnPathX = try requireFloatArray(cache.lensBandMidColumnPathX, "lensBandMidColumnPathX")
        lensBandMidColumnPathY = try requireFloatArray(cache.lensBandMidColumnPathY, "lensBandMidColumnPathY")
        lensBandMidRowPhasePathX = try requireFloatArray(cache.lensBandMidRowPhasePathX, "lensBandMidRowPhasePathX")
        lensBandMidRowPhasePathY = try requireFloatArray(cache.lensBandMidRowPhasePathY, "lensBandMidRowPhasePathY")
        lensBandMidLocalRollPath = try requireFloatArray(cache.lensBandMidLocalRollPath, "lensBandMidLocalRollPath")
        lensBandConfidence = try requireFloatArray(cache.lensBandConfidence, "lensBandConfidence")
        lensBandTopConfidence = try requireFloatArray(cache.lensBandTopConfidence, "lensBandTopConfidence")
        lensBandRidgeConfidence = try requireFloatArray(cache.lensBandRidgeConfidence, "lensBandRidgeConfidence")
        lensBandMidConfidence = try requireFloatArray(cache.lensBandMidConfidence, "lensBandMidConfidence")
        farFieldRigidShakePathX = try requireFloatArray(cache.farFieldRigidShakePathX, "farFieldRigidShakePathX", count: frames.count)
        farFieldRigidShakePathY = try requireFloatArray(cache.farFieldRigidShakePathY, "farFieldRigidShakePathY", count: frames.count)
        farFieldRigidShakePathRoll = try requireFloatArray(cache.farFieldRigidShakePathRoll, "farFieldRigidShakePathRoll", count: frames.count)
        cameraRigidTargetX = try requireFloatArray(cache.cameraRigidTargetX, "cameraRigidTargetX", count: frames.count)
        cameraRigidTargetY = try requireFloatArray(cache.cameraRigidTargetY, "cameraRigidTargetY", count: frames.count)
        cameraRigidTargetRollDegrees = try requireFloatArray(cache.cameraRigidTargetRollDegrees, "cameraRigidTargetRollDegrees", count: frames.count)
        farFieldRigidShakeSupport = try requireFloatArray(cache.farFieldRigidShakeSupport, "farFieldRigidShakeSupport", count: frames.count)
        farFieldRigidShakeSupportX = try requireFloatArray(cache.farFieldRigidShakeSupportX, "farFieldRigidShakeSupportX", count: frames.count)
        farFieldRigidShakeSupportY = try requireFloatArray(cache.farFieldRigidShakeSupportY, "farFieldRigidShakeSupportY", count: frames.count)
        farFieldRigidShakeRollSupport = try requireFloatArray(cache.farFieldRigidShakeRollSupport, "farFieldRigidShakeRollSupport", count: frames.count)
        farFieldRigidShakeShapeConsistency = try requireFloatArray(cache.farFieldRigidShakeShapeConsistency, "farFieldRigidShakeShapeConsistency", count: frames.count)
        farFieldRigidShakeShapeConsistencyX = try requireFloatArray(cache.farFieldRigidShakeShapeConsistencyX, "farFieldRigidShakeShapeConsistencyX", count: frames.count)
        farFieldRigidShakeShapeConsistencyY = try requireFloatArray(cache.farFieldRigidShakeShapeConsistencyY, "farFieldRigidShakeShapeConsistencyY", count: frames.count)
        farFieldRigidShakeForwardBackwardConsistency = try requireFloatArray(cache.farFieldRigidShakeForwardBackwardConsistency, "farFieldRigidShakeForwardBackwardConsistency", count: frames.count)
        farFieldRigidShakeForwardBackwardConsistencyX = try requireFloatArray(cache.farFieldRigidShakeForwardBackwardConsistencyX, "farFieldRigidShakeForwardBackwardConsistencyX", count: frames.count)
        farFieldRigidShakeForwardBackwardConsistencyY = try requireFloatArray(cache.farFieldRigidShakeForwardBackwardConsistencyY, "farFieldRigidShakeForwardBackwardConsistencyY", count: frames.count)
        farFieldRigidShakeRollForwardBackwardConsistency = try requireFloatArray(cache.farFieldRigidShakeRollForwardBackwardConsistency, "farFieldRigidShakeRollForwardBackwardConsistency", count: frames.count)
        guard let rows = cache.farFieldMeshRows,
              let columns = cache.farFieldMeshColumns
        else {
            throw FeedbackError(description: "Host Analysis cache is missing farFieldMeshRows/Columns; rerun Event Analyzer with schema \(supportedCacheSchemaDescription)")
        }
        guard rows == expectedFarFieldMeshRows,
              columns == expectedFarFieldMeshColumns
        else {
            throw FeedbackError(description: "Host Analysis cache has farFieldMesh grid \(rows)x\(columns); expected \(expectedFarFieldMeshRows)x\(expectedFarFieldMeshColumns)")
        }
        farFieldMeshRows = rows
        farFieldMeshColumns = columns
        let meshCount = frames.count * expectedFarFieldMeshBinCount
        farFieldMeshPathX = try requireFloatArray(cache.farFieldMeshPathX, "farFieldMeshPathX", count: meshCount)
        farFieldMeshPathY = try requireFloatArray(cache.farFieldMeshPathY, "farFieldMeshPathY", count: meshCount)
        farFieldMeshSupport = try requireFloatArray(cache.farFieldMeshSupport, "farFieldMeshSupport", count: meshCount)
        farFieldMeshDominantWindowFrames = try requireFloatArray(cache.farFieldMeshDominantWindowFrames, "farFieldMeshDominantWindowFrames", count: frames.count)
        farFieldMeshDominantWindowSeconds = try requireFloatArray(cache.farFieldMeshDominantWindowSeconds, "farFieldMeshDominantWindowSeconds", count: frames.count)
        farFieldMeshDominantSupport = try requireFloatArray(cache.farFieldMeshDominantSupport, "farFieldMeshDominantSupport", count: frames.count)
        farFieldMeshDominantCell = try requireIntArray(cache.farFieldMeshDominantCell, "farFieldMeshDominantCell", count: frames.count)
        sourceLensShakeRidgePathY = try requireFloatArray(cache.sourceLensShakeRidgePathY, "sourceLensShakeRidgePathY")
        sourceLensShakeRidgeSupport = try requireFloatArray(cache.sourceLensShakeRidgeSupport, "sourceLensShakeRidgeSupport")
        sourceLensShakeRidgeLinePathY = try requireFloatArray(cache.sourceLensShakeRidgeLinePathY, "sourceLensShakeRidgeLinePathY")
        sourceLensShakeRidgeLineSupport = try requireFloatArray(cache.sourceLensShakeRidgeLineSupport, "sourceLensShakeRidgeLineSupport")
        guard cache.sourceLensShakeLocalBinCount == expectedSourceLensShakeLocalBinCount else {
            throw FeedbackError(description: "Host Analysis cache has sourceLensShakeLocalBinCount \(cache.sourceLensShakeLocalBinCount.map(String.init) ?? "missing"); expected \(expectedSourceLensShakeLocalBinCount); rerun Host Analysis with the current FxPlug")
        }
        self.sourceLensShakeLocalBinCount = expectedSourceLensShakeLocalBinCount
        let sourceLensShakeLocalPathCount = frames.count * expectedSourceLensShakeLocalBinCount
        sourceLensShakeLocalPathX = try requireFloatArray(cache.sourceLensShakeLocalPathX, "sourceLensShakeLocalPathX", count: sourceLensShakeLocalPathCount)
        sourceLensShakeLocalPathY = try requireFloatArray(cache.sourceLensShakeLocalPathY, "sourceLensShakeLocalPathY", count: sourceLensShakeLocalPathCount)
        sourceLensShakeLocalSupport = try requireFloatArray(cache.sourceLensShakeLocalSupport, "sourceLensShakeLocalSupport", count: sourceLensShakeLocalPathCount)
        footstepPathX = try requireFloatArray(cache.footstepPathX, "footstepPathX")
        footstepPathY = try requireFloatArray(cache.footstepPathY, "footstepPathY")
        footstepPathRoll = try requireFloatArray(cache.footstepPathRoll, "footstepPathRoll")
        pathYaw = try requireFloatArray(cache.pathYaw, "pathYaw")
        pathPitch = try requireFloatArray(cache.pathPitch, "pathPitch")
        pathShearX = try requireFloatArray(cache.pathShearX, "pathShearX")
        pathShearY = try requireFloatArray(cache.pathShearY, "pathShearY")
        pathPerspectiveX = try requireFloatArray(cache.pathPerspectiveX, "pathPerspectiveX")
        pathPerspectiveY = try requireFloatArray(cache.pathPerspectiveY, "pathPerspectiveY")
        analysisConfidence = try requireFloatArray(cache.analysisConfidence, "analysisConfidence")
        warpConfidence = try requireFloatArray(cache.warpConfidence, "warpConfidence")
        acceptedBlockCounts = try requireIntArray(cache.acceptedBlockCounts, "acceptedBlockCounts")
        totalBlockCounts = try requireIntArray(cache.totalBlockCounts, "totalBlockCounts")
        blurAmounts = try requireFloatArray(cache.blurAmounts, "blurAmounts")
        searchRadiusHitCounts = try requireIntArray(cache.searchRadiusHitCounts, "searchRadiusHitCounts")
        searchRadiusTotalCounts = try requireIntArray(cache.searchRadiusTotalCounts, "searchRadiusTotalCounts")
    }
}

private struct FloatArrayComparison {
    let name: String
    let baselineCount: Int
    let comparedCount: Int
    let maxDelta: Float
    let maxIndex: Int?
    let baselineValue: Float?
    let comparedValue: Float?
    let passed: Bool
}

private struct IntArrayComparison {
    let name: String
    let baselineCount: Int
    let comparedCount: Int
    let mismatchCount: Int
    let firstMismatchIndex: Int?
    let baselineValue: Int32?
    let comparedValue: Int32?
    let passed: Bool
}

private struct CacheComparison {
    let baseline: Analysis
    let compared: Analysis
    let tolerance: Float
    let metadataIssues: [String]
    let floatComparisons: [FloatArrayComparison]
    let intComparisons: [IntArrayComparison]

    var passed: Bool {
        metadataIssues.isEmpty
            && floatComparisons.allSatisfy(\.passed)
            && intComparisons.allSatisfy(\.passed)
    }
}

private struct BandAssessment {
    let name: String
    let detected: Float
    let applied: Float
    let remaining: Float
    let confidence: Float
    let note: String
}

private struct TurnCorrectionSample {
    let bandX: Float
    let bandY: Float
    let bandRoll: Float
    let detected: Float
    let applied: Float
    let macroPixelOffsetX: Float
    let confidence: Float
    let rawConfidence: Float
    let ownership: Float
    let ownershipY: Float
    let trackingConfidence: Float
    let macroTrackingConfidence: Float
    let walkingTrackingConfidence: Float
    let edgeQuality: Float
}

private struct RenderTurnBridgeAssessment {
    let applied: Float
    let remaining: Float
    let confidence: Float
    let sampleCount: Int
    let rawApplied: Float
    let delta: Float
    let note: String
}

private struct AdaptiveXTurnTiming {
    let travelPixels: Float
    let windowSeconds: Double
    let active: Bool
}

private struct FrameAssessment {
    let index: Int
    let absoluteTime: Double
    let clipTime: Double
    let trackingConfidence: Float
    let walkingTrackingConfidence: Float
    let motionConfidence: Float
    let residual: Float
    let blur: Float
    let residualQuality: Float
    let blurQuality: Float
    let blockCoverage: Float
    let acceptedBlocks: Int32
    let totalBlocks: Int32
    let edgeHits: Int32
    let edgeTotal: Int32
    let edgeQuality: Float
    let warpTrackingConfidence: Float
    let warpTrackingGate: Float
    let warpEdgeGate: Float
    let warpGate: Float
    let footstepRawImpulseX: Float
    let footstepRawImpulseY: Float
    let footstepBaselineX: Float
    let footstepBaselineY: Float
    let footstepConfidenceX: Float
    let footstepConfidenceY: Float
    let footstepRawCorrectionX: Float
    let footstepRawCorrectionY: Float
    let footstepLimitedCorrectionX: Float
    let footstepLimitedCorrectionY: Float
    let footstepPulseLimitedX: Float
    let footstepPulseLimitedY: Float
    let renderTurnBridge: RenderTurnBridgeAssessment
    let bands: [BandAssessment]

    var topBand: BandAssessment {
        bands.max { $0.remaining < $1.remaining } ?? BandAssessment(name: "NONE", detected: 0.0, applied: 0.0, remaining: 0.0, confidence: 0.0, note: "no band data")
    }

    var score: Float {
        bands.reduce(Float(0.0)) { $0 + $1.remaining }
    }
}

private struct AssessmentContext {
    let analysis: Analysis
    let footstepBaselineXPath: [Float]
    let footstepBaselineYPath: [Float]
    let footstepBaselineRPath: [Float]
    let footstepCleanXPath: [Float]
    let footstepCleanYPath: [Float]
    let footstepCleanRPath: [Float]
    let strideSmoothedXPath: [Float]
    let strideSmoothedYPath: [Float]
    let strideSmoothedRPath: [Float]
    let turnStrideSmoothedXPath: [Float]
    let turnStrideSmoothedYPath: [Float]
    let footstepXTurnGateScales: [Int: Float]
    let warpMagnitudes: [Float]

    init(analysis: Analysis, turnWindowSeconds: Double) {
        self.analysis = analysis
        let allIndices = Array(analysis.frames.indices)
        let baselineX = outerLinearPredictionPath(
            analysis.footstepPathX,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: footstepInnerWindowSeconds,
            outerWindowSeconds: footstepOuterWindowSeconds
        )
        let baselineY = outerLinearPredictionPath(
            analysis.footstepPathY,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: footstepInnerWindowSeconds,
            outerWindowSeconds: footstepOuterWindowSeconds
        )
        let baselineR = outerLinearPredictionPath(
            analysis.footstepPathRoll,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: footstepInnerWindowSeconds,
            outerWindowSeconds: footstepOuterWindowSeconds
        )
        let turnStrideSmoothedX = locallyTimeWeightedAveragePath(
            baselineX,
            frames: analysis.frames,
            targetIndices: allIndices,
            windowSeconds: strideWindowSeconds
        )
        let turnStrideSmoothedY = locallyTimeWeightedAveragePath(
            baselineY,
            frames: analysis.frames,
            targetIndices: allIndices,
            windowSeconds: strideWindowSeconds
        )
        let footstepXTurnGateScales = turnOwnershipGateScales(
            values: turnStrideSmoothedX,
            analysis: analysis,
            targetIndices: allIndices,
            windowSeconds: turnWindowSeconds
        )
        let cleanX = confidenceCleanedFootstepPath(
            values: analysis.footstepPathX,
            baselineValues: baselineX,
            analysis: analysis,
            targetIndices: allIndices,
            fullImpulseScale: footstepFullScalePixels,
            confidenceScales: footstepXTurnGateScales
        )
        let cleanY = confidenceCleanedFootstepPath(
            values: analysis.footstepPathY,
            baselineValues: baselineY,
            analysis: analysis,
            targetIndices: allIndices,
            fullImpulseScale: footstepFullScalePixels
        )
        let cleanR = confidenceCleanedFootstepPath(
            values: analysis.footstepPathRoll,
            baselineValues: baselineR,
            analysis: analysis,
            targetIndices: allIndices,
            fullImpulseScale: footstepFullScaleDegrees
        )
        footstepBaselineXPath = baselineX
        footstepBaselineYPath = baselineY
        footstepBaselineRPath = baselineR
        footstepCleanXPath = cleanX
        footstepCleanYPath = cleanY
        footstepCleanRPath = cleanR
        strideSmoothedXPath = locallyTimeWeightedAveragePath(
            cleanX,
            frames: analysis.frames,
            targetIndices: allIndices,
            windowSeconds: strideWindowSeconds
        )
        strideSmoothedYPath = locallyTimeWeightedAveragePath(
            cleanY,
            frames: analysis.frames,
            targetIndices: allIndices,
            windowSeconds: strideWindowSeconds
        )
        strideSmoothedRPath = locallyTimeWeightedAveragePath(
            cleanR,
            frames: analysis.frames,
            targetIndices: allIndices,
            windowSeconds: strideWindowSeconds
        )
        turnStrideSmoothedXPath = turnStrideSmoothedX
        turnStrideSmoothedYPath = turnStrideSmoothedY
        self.footstepXTurnGateScales = footstepXTurnGateScales

        let baselineYaw = outerLinearPredictionPath(
            analysis.pathYaw,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        let baselinePitch = outerLinearPredictionPath(
            analysis.pathPitch,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        let baselineShearX = outerLinearPredictionPath(
            analysis.pathShearX,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        let baselineShearY = outerLinearPredictionPath(
            analysis.pathShearY,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        let baselinePerspectiveX = outerLinearPredictionPath(
            analysis.pathPerspectiveX,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        let baselinePerspectiveY = outerLinearPredictionPath(
            analysis.pathPerspectiveY,
            frames: analysis.frames,
            targetIndices: allIndices,
            innerWindowSeconds: farFieldInnerWindowSeconds,
            outerWindowSeconds: farFieldOuterWindowSeconds
        )
        warpMagnitudes = allIndices.map { index in
            let yaw = analysis.pathYaw[index] - baselineYaw[index]
            let pitch = analysis.pathPitch[index] - baselinePitch[index]
            let shearX = analysis.pathShearX[index] - baselineShearX[index]
            let shearY = analysis.pathShearY[index] - baselineShearY[index]
            let perspectiveX = analysis.pathPerspectiveX[index] - baselinePerspectiveX[index]
            let perspectiveY = analysis.pathPerspectiveY[index] - baselinePerspectiveY[index]
            return (hypotf(yaw, pitch) * 1000.0)
                + (hypotf(shearX, shearY) * 900.0)
                + (hypotf(perspectiveX, perspectiveY) * 900.0)
        }
    }
}

private let strideWindowSeconds = 2.0
private let footstepInnerWindowSeconds = 0.10
private let footstepOuterWindowSeconds = 1.0
private let farFieldInnerWindowSeconds = 0.10
private let farFieldOuterWindowSeconds = 1.0
private let timeWindowSelectionEpsilon = 0.001
private let footstepFullScalePixels: Float = 0.35
private let footstepFullScaleDegrees: Float = 0.08
private let footstepNoiseFloorScale: Float = 0.08
private let footstepSurroundingNoiseMultiplier: Float = 1.10
private let footstepSurroundingNoiseFloorCapScale: Float = 0.45
private let footstepFullResponseScale: Float = 0.55
private let verticalWalkingMediumConfidenceLift: Float = 0.20
private let footstepXYContinuityWindowSeconds = 0.15
private let footstepXYContinuityMaxSamples = 9
private let footstepXYContinuityMinimumSpikePixels: Float = 0.75
private let footstepXYContinuityMadMultiplier: Float = 3.0
private let footstepLowEvidenceLargeXConfidenceStart: Float = 0.10
private let footstepLowEvidenceLargeXConfidenceFull: Float = 0.26
private let footstepLowEvidenceLargeXCorrectionStartPixels: Float = 1.2
private let footstepLowEvidenceLargeXCorrectionFullPixels: Float = 4.5
private let footstepLowEvidenceLargeXMinimumScale: Float = 0.30
private let farFieldFootstepConfidenceFloorMax: Float = 0.24
private let farFieldFootstepConfidenceFloorStartPixels: Float = 0.45
private let farFieldFootstepConfidenceFloorFullPixels: Float = 3.4
private let farFieldFootstepVerticalConfidenceFloorMax: Float = 0.44
private let farFieldFootstepVerticalConfidenceFloorStartPixels: Float = 0.28
private let farFieldFootstepVerticalConfidenceFloorFullPixels: Float = 2.2
private let farFieldFootstepRollConfidenceFloorMax: Float = 0.30
private let farFieldFootstepRollConfidenceFloorStartDegrees: Float = 0.018
private let farFieldFootstepRollConfidenceFloorFullDegrees: Float = 0.11
private let farFieldStrideVerticalConfidenceFloorScale: Float = 0.78
private let farFieldStrideRollConfidenceFloorScale: Float = 0.84
private let strideFullScalePixels: Float = 0.75
private let strideFullScaleDegrees: Float = 0.16
private let strideFullResponseScale: Float = 0.55
private let turnFullScalePixels: Float = 2.0
private let turnFullScaleDegrees: Float = 0.16
private let turnOwnershipFootstepXSuppression: Float = 1.0
private let turnOwnershipFootstepYSuppression: Float = 0.65
private let turnOwnershipFootstepRollSuppression: Float = 0.55
private let turnOwnershipStrideXSuppression: Float = 1.0
private let turnOwnershipStrideYSuppression: Float = 0.55
private let turnOwnershipStrideRollSuppression: Float = 0.50
private let turnOwnedWalkingXGateFloorMax: Float = 0.82
private let turnOwnedStrideXGateFloorScale: Float = 1.15
private let turnOwnedWalkingXGateFloorStartPixels: Float = 12.0
private let turnOwnedWalkingXGateFloorFullPixels: Float = 75.0
private let turnOwnedWalkingXMacroFadeStartPixels: Float = 48.0
private let turnOwnedWalkingXMacroFadeFullPixels: Float = 160.0
private let turnOwnedFarFieldXConfidenceFloorMax: Float = 0.50
private let turnOwnedFarFieldXConfidenceFloorStartPixels: Float = 1.0
private let turnOwnedFarFieldXConfidenceFloorFullPixels: Float = 10.0
private let turnOwnedFarFieldXMacroGateFloorMax: Float = 1.0
private let turnOwnedFarFieldStrideRescueConfidenceFloorMax: Float = 0.46
private let turnOwnedFarFieldStrideRescueBandStartPixels: Float = 1.1
private let turnOwnedFarFieldStrideRescueBandFullPixels: Float = 4.2
private let turnOwnedFarFieldStrideRescueSupportStart: Float = 0.16
private let turnOwnedFarFieldStrideRescueSupportFull: Float = 0.48
private let turnOwnedFarFieldStrideRescueWarpStart: Float = 0.55
private let turnOwnedFarFieldStrideRescueWarpFull: Float = 0.88
private let turnOwnedFarFieldStrideRescueTrackingStart: Float = 0.24
private let turnOwnedFarFieldStrideRescueTrackingFull: Float = 0.56
private let turnOwnedFarFieldStrideRescueFarFieldStart: Float = 0.04
private let turnOwnedFarFieldStrideRescueFarFieldFull: Float = 0.22
private let farFieldWalkingResidualContinuityStartPixels: Float = 0.75
private let farFieldWalkingResidualContinuityFullPixels: Float = 3.5
private let farFieldWalkingResidualContinuityBandStartPixels: Float = 2.0
private let farFieldWalkingResidualContinuityBandFullPixels: Float = 12.0
private let farFieldWalkingResidualContinuityMaximumResidualScale: Float = 0.92
private let turnMacroOwnershipBandStartPixels: Float = 16.0
private let turnMacroOwnershipBandFullPixels: Float = 96.0
private let turnMacroOwnershipTravelStartPixels: Float = 24.0
private let turnMacroOwnershipTravelFullPixels: Float = 180.0
private let turnMacroOwnershipTrackingStart: Float = 0.02
private let turnMacroOwnershipTrackingFull: Float = 0.12
private let turnMacroOwnershipScale: Float = 0.70
private let renderTurnTransitionSmoothingSampleCount = 29
private let renderTurnTransitionSmoothingWindowSeconds = 2.8
private let renderTurnTransitionMinimumMacroPixels: Float = 0.5
private let renderTurnTransitionBridgeMinimumBlend: Float = 0.0
private let renderTurnTransitionBridgeMaximumBlend: Float = 1.0
private let renderTurnTransitionBridgeEdgeGateStart: Float = 0.45
private let renderTurnTransitionBridgeEdgeGateFull: Float = 0.78
private let renderTurnTransitionBridgeLowEdgeLargeTurnBlend: Float = 0.48
private let renderTurnTransitionBridgeLowEdgeMacroStartPixels: Float = 48.0
private let renderTurnTransitionBridgeLowEdgeMacroFullPixels: Float = 120.0
private let renderTurnTransitionZoomCenterPreservationFade: Float = 0.92
private let renderTurnTransitionZoomCenterAnchorFade: Float = 0.92
private let adaptiveXTurnTransitionTargetPixelRate: Float = 42.0
private let adaptiveXTurnTransitionGateStartPixels: Float = 96.0
private let adaptiveXTurnTransitionGateFullPixels: Float = 220.0
private let adaptiveXTurnTransitionStandardStrength: Float = 12.0
private let adaptiveXTurnTransitionMaximumZoomParameter: Float = 36.0
private let adaptiveXTurnTransitionZoomStartPixels: Float = 24.0
private let adaptiveXTurnTransitionZoomFullPixels: Float = 160.0
private let adaptiveXTurnTransitionZoomConfidenceStart: Float = 0.12
private let adaptiveXTurnTransitionZoomConfidenceFull: Float = 0.35
private let adaptiveXTurnTransitionHighStrengthBlendFloor: Float = 0.78
private let adaptiveXTurnTransitionHighStrengthBlendStartPixels: Float = 24.0
private let adaptiveXTurnTransitionHighStrengthBlendFullPixels: Float = 96.0
private let adaptiveXTurnTransitionPreRollMaximumBlend: Float = 0.35
private let adaptiveXTurnTransitionPreRollStartPixels: Float = 24.0
private let adaptiveXTurnTransitionPreRollFullPixels: Float = 96.0
private let renderTurnGateSmoothingWindowSeconds = 0.90
private let farFieldWarpTrackingGateStart: Float = 0.24
private let farFieldWarpTrackingGateFull: Float = 0.52
private let farFieldWarpTrackingGateMedianBlend: Float = 0.45
private let farFieldWarpEdgeQualityGateStart: Float = 0.55
private let farFieldWarpEdgeQualityGateFull: Float = 0.86
private let farFieldWarpConsensusGateStart: Float = 0.04
private let farFieldWarpConsensusGateFull: Float = 0.28
private let farFieldConsensusConfidenceFloor: Float = 0.04
private let lensShakeInnerWindowMinimumSeconds = 0.13
private let lensShakeOuterWindowMinimumSeconds = 0.44
private let lensShakeOuterWindowMaximumSeconds = 1.0
private let lensShakeMinimumSupport: Float = 0.08
private let lensShakePixelStartPixels: Float = 0.10
private let lensShakePixelFullPixels: Float = 0.85
private let lensShakeRollStartDegrees: Float = 0.002
private let lensShakeRollFullDegrees: Float = 0.030
private let lensShakeYawPitchStart: Float = 0.000006
private let lensShakeYawPitchFull: Float = 0.000055
private let lensShakeShearStart: Float = 0.000030
private let lensShakeShearFull: Float = 0.000320
private let lensShakePerspectiveStart: Float = 0.000010
private let lensShakePerspectiveFull: Float = 0.000095
private let farFieldRigidRawReinforcementMaximumBlend: Float = 0.74
private let farFieldLowFrequencyRawReinforcementMaximumBlend: Float = 0.94
private let lensBandPulseSmoothingBlend: Float = 0.46
private let lensBandPulseSmoothingStartPixels: Float = 0.22
private let lensBandPulseSmoothingFullPixels: Float = 1.35
private let farFieldRigidDeltaCoherenceTopRidgeStartPixels: Float = 1.45
private let farFieldRigidDeltaCoherenceTopRidgeFullPixels: Float = 5.50
private let farFieldRigidDeltaCoherenceMidStartPixels: Float = 3.25
private let farFieldRigidDeltaCoherenceMidFullPixels: Float = 9.50
private let farFieldRigidDeltaCoherenceMotionStartPixels: Float = 0.22
private let farFieldRigidDeltaCoherenceMotionFullPixels: Float = 3.60
private let farFieldLowFrequencyPriorityStartSeconds: Float = 0.28
private let farFieldLowFrequencyPriorityFullSeconds: Float = 0.86
private let farFieldLowFrequencyMeshSuppressionScale: Float = 1.0
private let farFieldLowFrequencyTurnSuppressionRelief: Float = 0.65
private let farFieldShortWindowRigidYBoostStartSeconds: Float = 0.15
private let farFieldShortWindowRigidYBoostFullSeconds: Float = 0.055
private let farFieldShortWindowRigidYBoostMaximum: Float = 0.0
private let farFieldShortWindowDominantMeshYBlendMaximum: Float = 0.0
private let farFieldCoherentSlabMeshYBlendMaximum: Float = 0.0
private let farFieldParallaxWarpDampingDeltaStart: Float = 48.0
private let farFieldParallaxWarpDampingDeltaFull: Float = 96.0
private let farFieldParallaxWarpDampingOpposingStart: Float = 0.08
private let farFieldParallaxWarpDampingOpposingFull: Float = 0.18
private let farFieldParallaxWarpDampingTwoWayStart: Float = 0.08
private let farFieldParallaxWarpDampingTwoWayFull: Float = 0.38
private let farFieldParallaxWarpDampingMaximum: Float = 0.68
private let farFieldCoherentSlabYShapeStart: Float = 0.18
private let farFieldCoherentSlabYShapeFull: Float = 0.70
private let farFieldCoherentSlabYTwoWayStart: Float = 0.22
private let farFieldCoherentSlabYTwoWayFull: Float = 0.76
private let farFieldCoherentSlabYMeshDeltaStart: Float = 10.0
private let farFieldCoherentSlabYMeshDeltaFull: Float = 24.0
private let farFieldCoherentSlabXShapeStart: Float = 0.12
private let farFieldCoherentSlabXShapeFull: Float = 0.54
private let farFieldCoherentSlabXTwoWayStart: Float = 0.18
private let farFieldCoherentSlabXTwoWayFull: Float = 0.62
private let farFieldCoherentSlabXMeshDeltaStart: Float = 13.0
private let farFieldCoherentSlabXMeshDeltaFull: Float = 22.0
private let farFieldCoherentSlabXQuiverStart: Float = 0.24
private let farFieldCoherentSlabXQuiverFull: Float = 0.62
private let farFieldCoherentMeshBlendDeltaStart: Float = 8.0
private let farFieldCoherentMeshBlendDeltaFull: Float = 20.0
private let farFieldCoherentMeshBlendOpposingStart: Float = 0.06
private let farFieldCoherentMeshBlendOpposingFull: Float = 0.22
private let farFieldRigidOnlyGuardSupportStart: Float = 0.08
private let farFieldRigidOnlyGuardSupportFull: Float = 0.30
private let farFieldRigidOnlyGuardShapeStart: Float = 0.24
private let farFieldRigidOnlyGuardShapeFull: Float = 0.56
private let farFieldRigidOnlyGuardTwoWayStart: Float = 0.20
private let farFieldRigidOnlyGuardTwoWayFull: Float = 0.52
private let expectedSourceLensShakeLocalBinCount = 15
private let expectedFarFieldMeshRows = 5
private let expectedFarFieldMeshColumns = 9
private let expectedFarFieldMeshBinCount = expectedFarFieldMeshRows * expectedFarFieldMeshColumns
private let maximumFarFieldWarpStrength: Float = 12.0
private let farFieldWarpSubunitResponseLift: Float = 2.0
private let farFieldWarpSubunitResponseMax: Float = 1.0
private let supportedCacheSchemaVersions: Set<Int> = [51]
private let supportedCacheSchemaDescription = supportedCacheSchemaVersions.sorted().map(String.init).joined(separator: ", ")
private func analysisQualityModel(for cache: PersistedHostAnalysisCache) -> AnalysisQualityModel {
    _ = cache
    return .eventAnalyzerCache
}

private func loadAnalysis(path: String) throws -> Analysis {
    let expandedPath = expandPath(path)
    let url = URL(fileURLWithPath: expandedPath)
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
    return try Analysis(cache: cache, cachePath: expandedPath)
}

private func compareCaches(baseline: Analysis, compared: Analysis, tolerance: Float) -> CacheComparison {
    var metadataIssues: [String] = []
    let timeTolerance = 1e-9

    func appendIssue(_ issue: String) {
        metadataIssues.append(issue)
    }

    func compareMetadata<T: Equatable>(_ name: String, _ baselineValue: T, _ comparedValue: T) {
        if baselineValue != comparedValue {
            appendIssue("\(name) differs: baseline \(baselineValue), compared \(comparedValue)")
        }
    }

    func compareTimeMetadata(_ name: String, _ baselineValue: Double, _ comparedValue: Double) {
        if abs(baselineValue - comparedValue) > timeTolerance {
            appendIssue(String(format: "%@ differs: baseline %.12f, compared %.12f", name, baselineValue, comparedValue))
        }
    }

    compareMetadata("schemaVersion", baseline.schemaVersion, compared.schemaVersion)
    compareMetadata("sampleWidth", baseline.sampleWidth, compared.sampleWidth)
    compareMetadata("sampleHeight", baseline.sampleHeight, compared.sampleHeight)
    compareMetadata("frameCount", baseline.frames.count, compared.frames.count)
    compareTimeMetadata("rangeStartSeconds", baseline.rangeStartSeconds, compared.rangeStartSeconds)
    compareTimeMetadata("rangeDurationSeconds", baseline.rangeDurationSeconds, compared.rangeDurationSeconds)
    compareTimeMetadata("frameDurationSeconds", baseline.frameDurationSeconds, compared.frameDurationSeconds)

    let sharedFrameCount = min(baseline.frames.count, compared.frames.count)
    var frameTimeMismatchCount = 0
    var firstFrameTimeMismatch: (index: Int, baseline: Double, compared: Double)?
    var fingerprintMismatchCount = 0
    var firstFingerprintMismatch: (index: Int, baseline: String, compared: String)?
    for index in 0..<sharedFrameCount {
        let baselineFrame = baseline.frames[index]
        let comparedFrame = compared.frames[index]
        if abs(baselineFrame.time - comparedFrame.time) > timeTolerance {
            frameTimeMismatchCount += 1
            if firstFrameTimeMismatch == nil {
                firstFrameTimeMismatch = (index, baselineFrame.time, comparedFrame.time)
            }
        }
        if baselineFrame.fingerprint != comparedFrame.fingerprint {
            fingerprintMismatchCount += 1
            if firstFingerprintMismatch == nil {
                firstFingerprintMismatch = (index, baselineFrame.fingerprint, comparedFrame.fingerprint)
            }
        }
    }
    if let mismatch = firstFrameTimeMismatch {
        appendIssue(String(format: "frame times differ at %d and %d total frame(s): baseline %.12f, compared %.12f",
                           mismatch.index,
                           frameTimeMismatchCount,
                           mismatch.baseline,
                           mismatch.compared))
    }
    if let mismatch = firstFingerprintMismatch {
        appendIssue("frame fingerprints differ at \(mismatch.index) and \(fingerprintMismatchCount) total frame(s): baseline \(mismatch.baseline), compared \(mismatch.compared)")
    }

    let floatComparisons = floatComparisonInputs(baseline: baseline, compared: compared)
        .map { name, baselineValues, comparedValues in
            compareFloatArray(name: name, baselineValues: baselineValues, comparedValues: comparedValues, tolerance: tolerance)
        }
    let intComparisons = intComparisonInputs(baseline: baseline, compared: compared)
        .map { name, baselineValues, comparedValues in
            compareIntArray(name: name, baselineValues: baselineValues, comparedValues: comparedValues)
        }

    return CacheComparison(
        baseline: baseline,
        compared: compared,
        tolerance: tolerance,
        metadataIssues: metadataIssues,
        floatComparisons: floatComparisons,
        intComparisons: intComparisons
    )
}

private func floatComparisonInputs(baseline: Analysis, compared: Analysis) -> [(String, [Float], [Float])] {
    [
        ("frame.blurAmount", baseline.frames.map(\.blurAmount), compared.frames.map(\.blurAmount)),
        ("residuals", baseline.residuals, compared.residuals),
        ("rollMotion", baseline.rollMotion, compared.rollMotion),
        ("pathX", baseline.pathX, compared.pathX),
        ("pathY", baseline.pathY, compared.pathY),
        ("pathRoll", baseline.pathRoll, compared.pathRoll),
        ("farFieldPathX", baseline.farFieldPathX, compared.farFieldPathX),
        ("farFieldPathY", baseline.farFieldPathY, compared.farFieldPathY),
        ("farFieldPathRoll", baseline.farFieldPathRoll, compared.farFieldPathRoll),
        ("farFieldConfidence", baseline.farFieldConfidence, compared.farFieldConfidence),
        ("lensBandTopPathX", baseline.lensBandTopPathX, compared.lensBandTopPathX),
        ("lensBandTopPathY", baseline.lensBandTopPathY, compared.lensBandTopPathY),
        ("lensBandTopColumnPathX", baseline.lensBandTopColumnPathX, compared.lensBandTopColumnPathX),
        ("lensBandTopColumnPathY", baseline.lensBandTopColumnPathY, compared.lensBandTopColumnPathY),
        ("lensBandTopRowPhasePathX", baseline.lensBandTopRowPhasePathX, compared.lensBandTopRowPhasePathX),
        ("lensBandTopRowPhasePathY", baseline.lensBandTopRowPhasePathY, compared.lensBandTopRowPhasePathY),
        ("lensBandTopLocalRollPath", baseline.lensBandTopLocalRollPath, compared.lensBandTopLocalRollPath),
        ("lensBandRidgePathX", baseline.lensBandRidgePathX, compared.lensBandRidgePathX),
        ("lensBandRidgePathY", baseline.lensBandRidgePathY, compared.lensBandRidgePathY),
        ("lensBandRidgeColumnPathX", baseline.lensBandRidgeColumnPathX, compared.lensBandRidgeColumnPathX),
        ("lensBandRidgeColumnPathY", baseline.lensBandRidgeColumnPathY, compared.lensBandRidgeColumnPathY),
        ("lensBandRidgeRowPhasePathX", baseline.lensBandRidgeRowPhasePathX, compared.lensBandRidgeRowPhasePathX),
        ("lensBandRidgeRowPhasePathY", baseline.lensBandRidgeRowPhasePathY, compared.lensBandRidgeRowPhasePathY),
        ("lensBandRidgeLocalRollPath", baseline.lensBandRidgeLocalRollPath, compared.lensBandRidgeLocalRollPath),
        ("lensBandMidPathX", baseline.lensBandMidPathX, compared.lensBandMidPathX),
        ("lensBandMidPathY", baseline.lensBandMidPathY, compared.lensBandMidPathY),
        ("lensBandMidColumnPathX", baseline.lensBandMidColumnPathX, compared.lensBandMidColumnPathX),
        ("lensBandMidColumnPathY", baseline.lensBandMidColumnPathY, compared.lensBandMidColumnPathY),
        ("lensBandMidRowPhasePathX", baseline.lensBandMidRowPhasePathX, compared.lensBandMidRowPhasePathX),
        ("lensBandMidRowPhasePathY", baseline.lensBandMidRowPhasePathY, compared.lensBandMidRowPhasePathY),
        ("lensBandMidLocalRollPath", baseline.lensBandMidLocalRollPath, compared.lensBandMidLocalRollPath),
        ("lensBandTopConfidence", baseline.lensBandTopConfidence, compared.lensBandTopConfidence),
        ("lensBandRidgeConfidence", baseline.lensBandRidgeConfidence, compared.lensBandRidgeConfidence),
        ("lensBandMidConfidence", baseline.lensBandMidConfidence, compared.lensBandMidConfidence),
        ("lensBandConfidence", baseline.lensBandConfidence, compared.lensBandConfidence),
        ("farFieldRigidShakePathX", baseline.farFieldRigidShakePathX, compared.farFieldRigidShakePathX),
        ("farFieldRigidShakePathY", baseline.farFieldRigidShakePathY, compared.farFieldRigidShakePathY),
        ("farFieldRigidShakePathRoll", baseline.farFieldRigidShakePathRoll, compared.farFieldRigidShakePathRoll),
        ("cameraRigidTargetX", baseline.cameraRigidTargetX, compared.cameraRigidTargetX),
        ("cameraRigidTargetY", baseline.cameraRigidTargetY, compared.cameraRigidTargetY),
        ("cameraRigidTargetRollDegrees", baseline.cameraRigidTargetRollDegrees, compared.cameraRigidTargetRollDegrees),
        ("farFieldRigidShakeSupport", baseline.farFieldRigidShakeSupport, compared.farFieldRigidShakeSupport),
        ("farFieldRigidShakeSupportX", baseline.farFieldRigidShakeSupportX, compared.farFieldRigidShakeSupportX),
        ("farFieldRigidShakeSupportY", baseline.farFieldRigidShakeSupportY, compared.farFieldRigidShakeSupportY),
        ("farFieldRigidShakeRollSupport", baseline.farFieldRigidShakeRollSupport, compared.farFieldRigidShakeRollSupport),
        ("farFieldRigidShakeShapeConsistency", baseline.farFieldRigidShakeShapeConsistency, compared.farFieldRigidShakeShapeConsistency),
        ("farFieldRigidShakeShapeConsistencyX", baseline.farFieldRigidShakeShapeConsistencyX, compared.farFieldRigidShakeShapeConsistencyX),
        ("farFieldRigidShakeShapeConsistencyY", baseline.farFieldRigidShakeShapeConsistencyY, compared.farFieldRigidShakeShapeConsistencyY),
        ("farFieldRigidShakeForwardBackwardConsistency", baseline.farFieldRigidShakeForwardBackwardConsistency, compared.farFieldRigidShakeForwardBackwardConsistency),
        ("farFieldRigidShakeForwardBackwardConsistencyX", baseline.farFieldRigidShakeForwardBackwardConsistencyX, compared.farFieldRigidShakeForwardBackwardConsistencyX),
        ("farFieldRigidShakeForwardBackwardConsistencyY", baseline.farFieldRigidShakeForwardBackwardConsistencyY, compared.farFieldRigidShakeForwardBackwardConsistencyY),
        ("farFieldRigidShakeRollForwardBackwardConsistency", baseline.farFieldRigidShakeRollForwardBackwardConsistency, compared.farFieldRigidShakeRollForwardBackwardConsistency),
        ("sourceLensShakeRidgePathY", baseline.sourceLensShakeRidgePathY, compared.sourceLensShakeRidgePathY),
        ("sourceLensShakeRidgeSupport", baseline.sourceLensShakeRidgeSupport, compared.sourceLensShakeRidgeSupport),
        ("sourceLensShakeRidgeLinePathY", baseline.sourceLensShakeRidgeLinePathY, compared.sourceLensShakeRidgeLinePathY),
        ("sourceLensShakeRidgeLineSupport", baseline.sourceLensShakeRidgeLineSupport, compared.sourceLensShakeRidgeLineSupport),
        ("sourceLensShakeLocalPathX", baseline.sourceLensShakeLocalPathX, compared.sourceLensShakeLocalPathX),
        ("sourceLensShakeLocalPathY", baseline.sourceLensShakeLocalPathY, compared.sourceLensShakeLocalPathY),
        ("sourceLensShakeLocalSupport", baseline.sourceLensShakeLocalSupport, compared.sourceLensShakeLocalSupport),
        ("footstepPathX", baseline.footstepPathX, compared.footstepPathX),
        ("footstepPathY", baseline.footstepPathY, compared.footstepPathY),
        ("footstepPathRoll", baseline.footstepPathRoll, compared.footstepPathRoll),
        ("pathYaw", baseline.pathYaw, compared.pathYaw),
        ("pathPitch", baseline.pathPitch, compared.pathPitch),
        ("pathShearX", baseline.pathShearX, compared.pathShearX),
        ("pathShearY", baseline.pathShearY, compared.pathShearY),
        ("pathPerspectiveX", baseline.pathPerspectiveX, compared.pathPerspectiveX),
        ("pathPerspectiveY", baseline.pathPerspectiveY, compared.pathPerspectiveY),
        ("analysisConfidence", baseline.analysisConfidence, compared.analysisConfidence),
        ("warpConfidence", baseline.warpConfidence, compared.warpConfidence),
        ("blurAmounts", baseline.blurAmounts, compared.blurAmounts)
    ]
}

private func intComparisonInputs(baseline: Analysis, compared: Analysis) -> [(String, [Int32], [Int32])] {
    [
        ("acceptedBlockCounts", baseline.acceptedBlockCounts, compared.acceptedBlockCounts),
        ("totalBlockCounts", baseline.totalBlockCounts, compared.totalBlockCounts),
        ("searchRadiusHitCounts", baseline.searchRadiusHitCounts, compared.searchRadiusHitCounts),
        ("searchRadiusTotalCounts", baseline.searchRadiusTotalCounts, compared.searchRadiusTotalCounts)
    ]
}

private func compareFloatArray(
    name: String,
    baselineValues: [Float],
    comparedValues: [Float],
    tolerance: Float
) -> FloatArrayComparison {
    let sharedCount = min(baselineValues.count, comparedValues.count)
    var maxDelta: Float = 0.0
    var maxIndex: Int?
    var baselineValue: Float?
    var comparedValue: Float?
    var hasNonFiniteMismatch = false
    for index in 0..<sharedCount {
        let left = baselineValues[index]
        let right = comparedValues[index]
        let delta: Float
        if left.isFinite && right.isFinite {
            delta = abs(left - right)
        } else if left == right {
            delta = 0.0
        } else {
            hasNonFiniteMismatch = true
            delta = Float.greatestFiniteMagnitude
        }
        if maxIndex == nil || delta > maxDelta {
            maxDelta = delta
            maxIndex = index
            baselineValue = left
            comparedValue = right
        }
    }
    let passed = baselineValues.count == comparedValues.count
        && !hasNonFiniteMismatch
        && maxDelta <= tolerance
    return FloatArrayComparison(
        name: name,
        baselineCount: baselineValues.count,
        comparedCount: comparedValues.count,
        maxDelta: maxDelta,
        maxIndex: maxIndex,
        baselineValue: baselineValue,
        comparedValue: comparedValue,
        passed: passed
    )
}

private func compareIntArray(
    name: String,
    baselineValues: [Int32],
    comparedValues: [Int32]
) -> IntArrayComparison {
    let sharedCount = min(baselineValues.count, comparedValues.count)
    var mismatchCount = abs(baselineValues.count - comparedValues.count)
    var firstMismatchIndex: Int?
    var baselineValue: Int32?
    var comparedValue: Int32?
    for index in 0..<sharedCount where baselineValues[index] != comparedValues[index] {
        mismatchCount += 1
        if firstMismatchIndex == nil {
            firstMismatchIndex = index
            baselineValue = baselineValues[index]
            comparedValue = comparedValues[index]
        }
    }
    if firstMismatchIndex == nil, baselineValues.count != comparedValues.count {
        firstMismatchIndex = sharedCount
    }
    return IntArrayComparison(
        name: name,
        baselineCount: baselineValues.count,
        comparedCount: comparedValues.count,
        mismatchCount: mismatchCount,
        firstMismatchIndex: firstMismatchIndex,
        baselineValue: baselineValue,
        comparedValue: comparedValue,
        passed: mismatchCount == 0
    )
}

private func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

private func cacheInventory(rootPath: String) -> [CacheInventoryEntry] {
    let rootURL = URL(fileURLWithPath: expandPath(rootPath), isDirectory: true)
    let cacheStorageURL = rootURL.appendingPathComponent("caches", isDirectory: true)
    var urls: [URL] = []
    var seen = Set<String>()

    func appendURL(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path), seen.insert(path).inserted else {
            return
        }
        urls.append(URL(fileURLWithPath: path))
    }

    appendURL(rootURL.appendingPathComponent("host-analysis-v2.json", isDirectory: false))
    if let cacheURLs = try? FileManager.default.contentsOfDirectory(
        at: cacheStorageURL,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) {
        for url in cacheURLs where url.pathExtension == "json" {
            appendURL(url)
        }
    }

    return urls
        .map(cacheInventoryEntry(at:))
        .sorted { left, right in
            (left.modifiedAt ?? .distantPast) > (right.modifiedAt ?? .distantPast)
        }
}

private func cacheInventoryEntry(at url: URL) -> CacheInventoryEntry {
    let path = url.path
    let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    do {
        let data = try Data(contentsOf: url)
        let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
        let status: String
        let reason: String
        if !supportedCacheSchemaVersions.contains(cache.schemaVersion) {
            status = "unsupported"
            reason = "schema \(cache.schemaVersion), need \(supportedCacheSchemaDescription)"
        } else if cache.frames.count < 3 {
            status = "incomplete"
            reason = "only \(cache.frames.count) frames"
        } else if let issue = preparedCacheIssue(cache) {
            status = "incomplete"
            reason = issue
        } else {
            status = "ready"
            reason = "feedback-ready"
        }
        return CacheInventoryEntry(
            path: path,
            status: status,
            reason: reason,
            schemaVersion: cache.schemaVersion,
            frameCount: cache.frames.count,
            rangeStartSeconds: cache.rangeStartSeconds,
            rangeDurationSeconds: cache.rangeDurationSeconds,
            requestedSampleScalePercent: cache.requestedSampleScalePercent,
            sampleWidth: cache.sampleWidth,
            sampleHeight: cache.sampleHeight,
            modifiedAt: modifiedAt
        )
    } catch {
        return CacheInventoryEntry(
            path: path,
            status: "unreadable",
            reason: error.localizedDescription,
            schemaVersion: nil,
            frameCount: nil,
            rangeStartSeconds: nil,
            rangeDurationSeconds: nil,
            requestedSampleScalePercent: nil,
            sampleWidth: nil,
            sampleHeight: nil,
            modifiedAt: modifiedAt
        )
    }
}

private func preparedCacheIssue(_ cache: PersistedHostAnalysisCache) -> String? {
    let frames = cache.frames
    for index in 1..<frames.count where frames[index].time <= frames[index - 1].time {
        return "frame times are not strictly increasing near frame \(index)"
    }
    for (index, frame) in frames.enumerated() {
        if frame.fingerprint?.isEmpty ?? true {
            return "frame \(index) is missing fingerprint"
        }
    }

    let frameCount = frames.count
    var floatArrays: [(String, [Float]?)] = [
        ("residuals", cache.residuals),
        ("rollMotion", cache.rollMotion),
        ("pathX", cache.pathX),
        ("pathY", cache.pathY),
        ("pathRoll", cache.pathRoll),
        ("farFieldPathX", cache.farFieldPathX),
        ("farFieldPathY", cache.farFieldPathY),
        ("farFieldPathRoll", cache.farFieldPathRoll),
        ("farFieldConfidence", cache.farFieldConfidence),
        ("lensBandTopPathX", cache.lensBandTopPathX),
        ("lensBandTopPathY", cache.lensBandTopPathY),
        ("lensBandTopColumnPathX", cache.lensBandTopColumnPathX),
        ("lensBandTopColumnPathY", cache.lensBandTopColumnPathY),
        ("lensBandTopRowPhasePathX", cache.lensBandTopRowPhasePathX),
        ("lensBandTopRowPhasePathY", cache.lensBandTopRowPhasePathY),
        ("lensBandTopLocalRollPath", cache.lensBandTopLocalRollPath),
        ("lensBandRidgePathX", cache.lensBandRidgePathX),
        ("lensBandRidgePathY", cache.lensBandRidgePathY),
        ("lensBandRidgeColumnPathX", cache.lensBandRidgeColumnPathX),
        ("lensBandRidgeColumnPathY", cache.lensBandRidgeColumnPathY),
        ("lensBandRidgeRowPhasePathX", cache.lensBandRidgeRowPhasePathX),
        ("lensBandRidgeRowPhasePathY", cache.lensBandRidgeRowPhasePathY),
        ("lensBandRidgeLocalRollPath", cache.lensBandRidgeLocalRollPath),
        ("lensBandMidPathX", cache.lensBandMidPathX),
        ("lensBandMidPathY", cache.lensBandMidPathY),
        ("lensBandMidColumnPathX", cache.lensBandMidColumnPathX),
        ("lensBandMidColumnPathY", cache.lensBandMidColumnPathY),
        ("lensBandMidRowPhasePathX", cache.lensBandMidRowPhasePathX),
        ("lensBandMidRowPhasePathY", cache.lensBandMidRowPhasePathY),
        ("lensBandMidLocalRollPath", cache.lensBandMidLocalRollPath),
        ("lensBandTopConfidence", cache.lensBandTopConfidence),
        ("lensBandRidgeConfidence", cache.lensBandRidgeConfidence),
        ("lensBandMidConfidence", cache.lensBandMidConfidence),
        ("lensBandConfidence", cache.lensBandConfidence),
        ("sourceLensShakeRidgePathY", cache.sourceLensShakeRidgePathY),
        ("sourceLensShakeRidgeSupport", cache.sourceLensShakeRidgeSupport),
        ("sourceLensShakeRidgeLinePathY", cache.sourceLensShakeRidgeLinePathY),
        ("sourceLensShakeRidgeLineSupport", cache.sourceLensShakeRidgeLineSupport),
        ("footstepPathX", cache.footstepPathX),
        ("footstepPathY", cache.footstepPathY),
        ("footstepPathRoll", cache.footstepPathRoll),
        ("pathYaw", cache.pathYaw),
        ("pathPitch", cache.pathPitch),
        ("pathShearX", cache.pathShearX),
        ("pathShearY", cache.pathShearY),
        ("pathPerspectiveX", cache.pathPerspectiveX),
        ("pathPerspectiveY", cache.pathPerspectiveY),
        ("analysisConfidence", cache.analysisConfidence),
        ("warpConfidence", cache.warpConfidence),
        ("blurAmounts", cache.blurAmounts)
    ]
    floatArrays.append(contentsOf: [
        ("farFieldRigidShakePathX", cache.farFieldRigidShakePathX),
        ("farFieldRigidShakePathY", cache.farFieldRigidShakePathY),
        ("farFieldRigidShakePathRoll", cache.farFieldRigidShakePathRoll),
        ("cameraRigidTargetX", cache.cameraRigidTargetX),
        ("cameraRigidTargetY", cache.cameraRigidTargetY),
        ("cameraRigidTargetRollDegrees", cache.cameraRigidTargetRollDegrees),
        ("farFieldRigidShakeSupport", cache.farFieldRigidShakeSupport),
        ("farFieldRigidShakeSupportX", cache.farFieldRigidShakeSupportX),
        ("farFieldRigidShakeSupportY", cache.farFieldRigidShakeSupportY),
        ("farFieldRigidShakeRollSupport", cache.farFieldRigidShakeRollSupport),
        ("farFieldRigidShakeShapeConsistency", cache.farFieldRigidShakeShapeConsistency),
        ("farFieldRigidShakeShapeConsistencyX", cache.farFieldRigidShakeShapeConsistencyX),
        ("farFieldRigidShakeShapeConsistencyY", cache.farFieldRigidShakeShapeConsistencyY),
        ("farFieldRigidShakeForwardBackwardConsistency", cache.farFieldRigidShakeForwardBackwardConsistency),
        ("farFieldRigidShakeForwardBackwardConsistencyX", cache.farFieldRigidShakeForwardBackwardConsistencyX),
        ("farFieldRigidShakeForwardBackwardConsistencyY", cache.farFieldRigidShakeForwardBackwardConsistencyY),
        ("farFieldRigidShakeRollForwardBackwardConsistency", cache.farFieldRigidShakeRollForwardBackwardConsistency)
    ])
    guard let rows = cache.farFieldMeshRows,
          let columns = cache.farFieldMeshColumns
    else {
        return "farFieldMeshRows/Columns are missing"
    }
    if rows != expectedFarFieldMeshRows || columns != expectedFarFieldMeshColumns {
        return "farFieldMesh grid is \(rows)x\(columns); expected \(expectedFarFieldMeshRows)x\(expectedFarFieldMeshColumns)"
    }
    let intArrays: [(String, [Int32]?)] = [
        ("acceptedBlockCounts", cache.acceptedBlockCounts),
        ("totalBlockCounts", cache.totalBlockCounts),
        ("searchRadiusHitCounts", cache.searchRadiusHitCounts),
        ("searchRadiusTotalCounts", cache.searchRadiusTotalCounts)
    ]

    for (name, values) in floatArrays {
        guard let values else {
            return "\(name) is missing"
        }
        if values.count != frameCount {
            return "\(name) has \(values.count) values but frames has \(frameCount)"
        }
    }
    if cache.sourceLensShakeLocalBinCount != expectedSourceLensShakeLocalBinCount {
        return "sourceLensShakeLocalBinCount is \(cache.sourceLensShakeLocalBinCount.map(String.init) ?? "missing"); expected \(expectedSourceLensShakeLocalBinCount)"
    }
    let localPathCount = frameCount * expectedSourceLensShakeLocalBinCount
    let localFloatArrays: [(String, [Float]?)] = [
        ("sourceLensShakeLocalPathX", cache.sourceLensShakeLocalPathX),
        ("sourceLensShakeLocalPathY", cache.sourceLensShakeLocalPathY),
        ("sourceLensShakeLocalSupport", cache.sourceLensShakeLocalSupport)
    ]
    for (name, values) in localFloatArrays {
        guard let values else {
            return "\(name) is missing"
        }
        if values.count != localPathCount {
            return "\(name) has \(values.count) values but expected \(localPathCount)"
        }
    }
    let meshPathCount = frameCount * expectedFarFieldMeshBinCount
    let meshFloatArrays: [(String, [Float]?)] = [
        ("farFieldMeshPathX", cache.farFieldMeshPathX),
        ("farFieldMeshPathY", cache.farFieldMeshPathY),
        ("farFieldMeshSupport", cache.farFieldMeshSupport)
    ]
    for (name, values) in meshFloatArrays {
        guard let values else {
            return "\(name) is missing"
        }
        if values.count != meshPathCount {
            return "\(name) has \(values.count) values but expected \(meshPathCount)"
        }
    }
    let meshFrameFloatArrays: [(String, [Float]?)] = [
        ("farFieldMeshDominantWindowFrames", cache.farFieldMeshDominantWindowFrames),
        ("farFieldMeshDominantWindowSeconds", cache.farFieldMeshDominantWindowSeconds),
        ("farFieldMeshDominantSupport", cache.farFieldMeshDominantSupport)
    ]
    for (name, values) in meshFrameFloatArrays {
        guard let values else {
            return "\(name) is missing"
        }
        if values.count != frameCount {
            return "\(name) has \(values.count) values but frames has \(frameCount)"
        }
    }
    guard let dominantCell = cache.farFieldMeshDominantCell else {
        return "farFieldMeshDominantCell is missing"
    }
    if dominantCell.count != frameCount {
        return "farFieldMeshDominantCell has \(dominantCell.count) values but frames has \(frameCount)"
    }
    for (name, values) in intArrays {
        guard let values else {
            return "\(name) is missing"
        }
        if values.count != frameCount {
            return "\(name) has \(values.count) values but frames has \(frameCount)"
        }
    }
    return nil
}

private func monotonicDominantTravel(_ values: [Float], indices: [Int]) -> Float {
    let sortedIndices = indices.sorted().filter { values.indices.contains($0) }
    guard sortedIndices.count >= 2 else {
        return 0.0
    }

    var positiveTravel: Float = 0.0
    var negativeTravel: Float = 0.0
    for position in 1..<sortedIndices.count {
        let currentValue = values[sortedIndices[position]]
        let delta = currentValue - values[sortedIndices[position - 1]]
        if delta >= 0.0 {
            positiveTravel += delta
        } else {
            negativeTravel += -delta
        }
    }
    return max(positiveTravel, negativeTravel)
}

private func adaptiveXTurnTiming(
    travelPixels: Float,
    baseWindowSeconds: Double,
    turnWindowSeconds: Double,
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

    let requestedWindow = turnWindowSeconds.isFinite && turnWindowSeconds > 0.0
        ? turnWindowSeconds
        : baseWindow
    // Turn Transition Window owns duration; strength owns X amplitude only.
    let strengthWindow = requestedWindow
    let maximumWindow = requestedWindow
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

private func adaptiveXTurnTransitionSampleCount(windowSeconds: Double) -> Int {
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

private func adaptiveXTurnSmoothValue(
    _ values: [Float],
    frames: [AnalysisFrame],
    indices: [Int],
    centerTime: Double,
    baseWindowSeconds: Double,
    fallbackWindowSeconds: Double,
    turnWindowSeconds: Double,
    outputScale: Float,
    turnSmoothingZoom: Double
) -> Float {
    let travelPixels = monotonicDominantTravel(values, indices: indices)
        * max(0.0, outputScale.isFinite ? abs(outputScale) : 0.0)
    let timing = adaptiveXTurnTiming(
        travelPixels: travelPixels,
        baseWindowSeconds: baseWindowSeconds,
        turnWindowSeconds: turnWindowSeconds,
        turnSmoothingZoom: turnSmoothingZoom
    )
    let activeWindow = timing.active ? max(fallbackWindowSeconds, timing.windowSeconds) : fallbackWindowSeconds
    let timingIndices = abs(activeWindow - fallbackWindowSeconds) > 0.001
        ? activeIndices(frames, centerTime: centerTime, windowSeconds: activeWindow)
        : indices
    let effectiveIndices = timingIndices.isEmpty ? indices : timingIndices
    return timeWeightedMonotonicSCurveValue(
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

private func turnCorrectionSample(for context: AssessmentContext, index: Int, options: Options) -> TurnCorrectionSample {
    let analysis = context.analysis
    guard analysis.frames.indices.contains(index),
          context.turnStrideSmoothedXPath.indices.contains(index),
          context.turnStrideSmoothedYPath.indices.contains(index),
          context.strideSmoothedRPath.indices.contains(index)
    else {
        return TurnCorrectionSample(
            bandX: 0.0,
            bandY: 0.0,
            bandRoll: 0.0,
            detected: 0.0,
            applied: 0.0,
            macroPixelOffsetX: 0.0,
            confidence: 0.0,
            rawConfidence: 0.0,
            ownership: 0.0,
            ownershipY: 0.0,
            trackingConfidence: 0.0,
            macroTrackingConfidence: 0.0,
            walkingTrackingConfidence: 0.0,
            edgeQuality: 0.0
        )
    }
    let frame = analysis.frames[index]
    let outputWidth = options.outputSize?.width ?? Float(analysis.sampleWidth)
    let xScale = outputWidth / Float(max(1, analysis.sampleWidth))
    let turnWindowSeconds = max(strideWindowSeconds, options.turnWindowSeconds)
    let turnIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: turnWindowSeconds)
    let centerResidual = analysis.residuals[index]
    let quality = frameTrackingQuality(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index],
        qualityModel: analysis.qualityModel
    )
    let tracking = frameTrackingConfidence(quality)
    let walkingTracking = walkingBandTrackingConfidence(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index],
        qualityModel: analysis.qualityModel
    )
    let edgeQuality = searchRadiusEdgeQuality(
        hitCount: analysis.searchRadiusHitCounts[index],
        totalCount: analysis.searchRadiusTotalCounts[index]
    )
    let turnResidual = percentileValue(analysis.residuals, indices: turnIndices, percentile: 0.75)
    let turnTracking = residualAdjustedTrackingConfidence(
        tracking,
        residual: turnResidual,
        multiplier: 0.9,
        qualityModel: analysis.qualityModel
    )
    let turnSmoothX = adaptiveXTurnSmoothValue(
        context.turnStrideSmoothedXPath,
        frames: analysis.frames,
        indices: turnIndices,
        centerTime: frame.time,
        baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
        fallbackWindowSeconds: turnWindowSeconds,
        turnWindowSeconds: turnWindowSeconds,
        outputScale: xScale,
        turnSmoothingZoom: options.turnStrength
    )
    let turnSmoothY = timeWeightedMonotonicSCurveValue(
        context.turnStrideSmoothedYPath,
        frames: analysis.frames,
        indices: turnIndices,
        centerTime: frame.time,
        windowSeconds: turnWindowSeconds
    ) ?? timeWeightedAverage(
        context.turnStrideSmoothedYPath,
        frames: analysis.frames,
        indices: turnIndices,
        centerTime: frame.time,
        windowSeconds: turnWindowSeconds
    )
    let turnBandX = context.turnStrideSmoothedXPath[index] - turnSmoothX
    let turnBandY = context.turnStrideSmoothedYPath[index] - turnSmoothY
    let turnSmoothRoll = timeWeightedAverage(
        context.strideSmoothedRPath,
        frames: analysis.frames,
        indices: turnIndices,
        centerTime: frame.time,
        windowSeconds: turnWindowSeconds
    )
    let turnBandRoll = context.strideSmoothedRPath[index] - turnSmoothRoll
    let turnOwnershipX = turnOwnershipConfidence(
        values: context.turnStrideSmoothedXPath,
        frames: analysis.frames,
        indices: turnIndices,
        turnBandValue: turnBandX,
        trackingConfidence: turnTracking
    )
    let turnOwnershipY = turnOwnershipConfidence(
        values: context.turnStrideSmoothedYPath,
        frames: analysis.frames,
        indices: turnIndices,
        turnBandValue: turnBandY,
        trackingConfidence: turnTracking
    )
    let rawTurnQ = turnConfidence(bandValue: turnBandX, trackingConfidence: turnTracking) * turnOwnershipX
    let turnQ = turnCorrectionConfidence(confidence: rawTurnQ, turnOwnership: turnOwnershipX)
    let correction = correctionFactor(turnSmoothingZoom: options.turnStrength, confidence: turnQ)
    let detected = abs(turnBandX * xScale)
    let macroPixelOffsetX = -(turnBandX * xScale) * correction
    return TurnCorrectionSample(
        bandX: turnBandX,
        bandY: turnBandY,
        bandRoll: turnBandRoll,
        detected: detected,
        applied: detected * correction,
        macroPixelOffsetX: macroPixelOffsetX,
        confidence: turnQ,
        rawConfidence: rawTurnQ,
        ownership: turnOwnershipX,
        ownershipY: turnOwnershipY,
        trackingConfidence: tracking,
        macroTrackingConfidence: turnTracking,
        walkingTrackingConfidence: walkingTracking,
        edgeQuality: edgeQuality
    )
}

private func nearestFrameIndex(at time: Double, in frames: [AnalysisFrame]) -> Int {
    guard !frames.isEmpty else {
        return 0
    }
    guard frames.count > 1 else {
        return 0
    }
    if time <= frames[0].time {
        return 0
    }
    let lastIndex = frames.count - 1
    if time >= frames[lastIndex].time {
        return lastIndex
    }
    let lowerBoundIndex = lowerBoundFrameIndex(frames, time: time)
    if lowerBoundIndex <= frames.startIndex {
        return frames.startIndex
    }
    if lowerBoundIndex >= frames.endIndex {
        return lastIndex
    }
    let previousIndex = lowerBoundIndex - 1
    let previousDistance = abs(frames[previousIndex].time - time)
    let nextDistance = abs(frames[lowerBoundIndex].time - time)
    return previousDistance <= nextDistance ? previousIndex : lowerBoundIndex
}

private func renderTurnBridgeAssessment(
    for context: AssessmentContext,
    index: Int,
    options: Options,
    centerSample: TurnCorrectionSample
) -> RenderTurnBridgeAssessment {
    let analysis = context.analysis
    let frames = analysis.frames
    guard frames.indices.contains(index),
          let firstTime = frames.first?.time,
          let lastTime = frames.last?.time
    else {
        return RenderTurnBridgeAssessment(
            applied: centerSample.applied,
            remaining: max(0.0, centerSample.detected - centerSample.applied),
            confidence: centerSample.confidence,
            sampleCount: 1,
            rawApplied: centerSample.applied,
            delta: 0.0,
            note: "render bridge unavailable"
        )
    }

    let timing = adaptiveXTurnTiming(
        travelPixels: centerSample.detected,
        baseWindowSeconds: renderTurnTransitionSmoothingWindowSeconds,
        turnWindowSeconds: options.turnWindowSeconds,
        turnSmoothingZoom: options.turnStrength
    )
    let transitionWindowSeconds = timing.windowSeconds
    let sampleCount = adaptiveXTurnTransitionSampleCount(windowSeconds: transitionWindowSeconds)
    let centerSampleIndex = sampleCount / 2
    let halfWindow = transitionWindowSeconds * 0.5
    let denominator = Double(max(1, sampleCount - 1))
    let sampleStep = transitionWindowSeconds / denominator
    let sigma = max(1e-6, halfWindow * 0.55)
    let renderSeconds = frames[index].time
    var rawSamples: [(sample: TurnCorrectionSample, timeWeight: Float, isCenter: Bool)] = [
        (centerSample, 1.0, true)
    ]
    rawSamples.reserveCapacity(sampleCount)
    for sampleIndex in 0..<sampleCount {
        guard sampleIndex != centerSampleIndex else {
            continue
        }
        let offset = Double(sampleIndex - centerSampleIndex) * sampleStep
        let sampleSeconds = renderSeconds + offset
        guard sampleSeconds >= firstTime, sampleSeconds <= lastTime else {
            continue
        }
        let normalizedDistance = offset / sigma
        let weight = Float(Darwin.exp(-0.5 * normalizedDistance * normalizedDistance))
        guard weight > 0.0001 else {
            continue
        }
        let sampleFrameIndex = nearestFrameIndex(at: sampleSeconds, in: frames)
        rawSamples.append((
            turnCorrectionSample(for: context, index: sampleFrameIndex, options: options),
            weight,
            false
        ))
    }

    var supportMagnitude = Float(0.0)
    var signedSupport = Float(0.0)
    var signedSupportWeight = Float(0.0)
    for sample in rawSamples {
        let turnResponse = turnCorrectionConfidenceResponse(sample.sample.confidence)
        let qualitySupport = turnTransitionBridgeQualitySupport(
            trackingConfidence: sample.sample.trackingConfidence,
            walkingTrackingConfidence: sample.sample.walkingTrackingConfidence,
            edgeQuality: sample.sample.edgeQuality
        )
        let evidenceWeight = sample.timeWeight * turnResponse * qualitySupport
        guard evidenceWeight > 0.0001 else {
            continue
        }
        let macroX = sample.sample.macroPixelOffsetX
        supportMagnitude = max(supportMagnitude, abs(macroX))
        signedSupport += macroX * evidenceWeight
        signedSupportWeight += evidenceWeight
    }
    guard supportMagnitude >= renderTurnTransitionMinimumMacroPixels else {
        return RenderTurnBridgeAssessment(
            applied: centerSample.applied,
            remaining: max(0.0, centerSample.detected - centerSample.applied),
            confidence: centerSample.confidence,
            sampleCount: rawSamples.count,
            rawApplied: centerSample.applied,
            delta: 0.0,
            note: "render bridge below support threshold"
        )
    }
    guard signedSupportWeight > 0.0001 else {
        return RenderTurnBridgeAssessment(
            applied: centerSample.applied,
            remaining: max(0.0, centerSample.detected - centerSample.applied),
            confidence: centerSample.confidence,
            sampleCount: rawSamples.count,
            rawApplied: centerSample.applied,
            delta: 0.0,
            note: "render bridge had no coherent evidence"
        )
    }
    let dominantSign: Float = signedSupport >= 0.0 ? 1.0 : -1.0
    var weightedMacro: Float = 0.0
    var weightedConfidence: Float = 0.0
    var totalWeight: Float = 0.0
    var acceptedSamples = 0
    for sample in rawSamples {
        let macroX = sample.sample.macroPixelOffsetX
        let macroMagnitude = abs(macroX)
        let turnResponse = turnCorrectionConfidenceResponse(sample.sample.confidence)
        let qualitySupport = turnTransitionBridgeQualitySupport(
            trackingConfidence: sample.sample.trackingConfidence,
            walkingTrackingConfidence: sample.sample.walkingTrackingConfidence,
            edgeQuality: sample.sample.edgeQuality
        )
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
            ? 0.25 + (turnCorrectionConfidenceResponse(sample.sample.confidence) * 0.75)
            : 1.0
        let weight = sample.timeWeight
            * evidenceWeight
            * max(0.15, magnitudeSupport)
            * directionSupport
            * centerScale
        guard weight > 0.0001 else {
            continue
        }
        weightedMacro += macroX * weight
        weightedConfidence += sample.sample.confidence * weight
        totalWeight += weight
        acceptedSamples += 1
    }
    guard totalWeight > 0.0 else {
        return RenderTurnBridgeAssessment(
            applied: centerSample.applied,
            remaining: max(0.0, centerSample.detected - centerSample.applied),
            confidence: centerSample.confidence,
            sampleCount: 1,
            rawApplied: centerSample.applied,
            delta: 0.0,
            note: "render bridge had no weighted samples"
        )
    }

    let averagedMacro = weightedMacro / totalWeight
    let centerMacro = centerSample.macroPixelOffsetX
    let zoomBridgeAuthority = turnSmoothingZoomBridgeAuthority(
        turnSmoothingZoom: options.turnStrength,
        turnConfidence: centerSample.confidence,
        turnTravelPixels: centerSample.detected
    )
    let bridgedMacro: Float
    if abs(centerMacro) >= renderTurnTransitionMinimumMacroPixels,
       abs(centerMacro) > abs(averagedMacro),
       (centerMacro * averagedMacro) > 0.0
    {
        let centerResponse = turnCorrectionConfidenceResponse(centerSample.confidence)
        let centerPreservation = confidenceRamp(centerResponse, start: 0.35, full: 0.70)
            * 0.85
            * (1.0 - (zoomBridgeAuthority * renderTurnTransitionZoomCenterPreservationFade))
        bridgedMacro = averagedMacro + ((centerMacro - averagedMacro) * centerPreservation)
    } else {
        bridgedMacro = averagedMacro
    }
    let anchoredMacro = turnTransitionCenterAnchoredBridgeMacroX(
        centerMacroX: centerMacro,
        bridgeMacroX: bridgedMacro,
        centerTurnConfidence: centerSample.confidence,
        centerTrackingConfidence: centerSample.trackingConfidence,
        centerWalkingTrackingConfidence: centerSample.walkingTrackingConfidence,
        centerEdgeQuality: centerSample.edgeQuality,
        zoomBridgeAuthority: zoomBridgeAuthority
    )
    let bridgedConfidence = clamp(weightedConfidence / totalWeight, min: 0.0, max: 1.0)
    let bridgeBlend = turnTransitionBridgeBlend(
        centerTurnConfidence: centerSample.confidence,
        centerTrackingConfidence: centerSample.trackingConfidence,
        centerWalkingTrackingConfidence: centerSample.walkingTrackingConfidence,
        centerEdgeQuality: centerSample.edgeQuality,
        bridgeTurnConfidence: bridgedConfidence,
        bridgeMacroX: averagedMacro,
        turnSmoothingStrength: options.turnStrength,
        centerTurnDetected: centerSample.detected,
        bridgeTurnDetected: supportMagnitude
    ) * turnSmoothingBridgeBlend(options.turnStrength)
    let blendedMacro = centerMacro + ((anchoredMacro - centerMacro) * bridgeBlend)
    let bridgedApplied = abs(blendedMacro)
    return RenderTurnBridgeAssessment(
        applied: bridgedApplied,
        remaining: max(0.0, centerSample.detected - bridgedApplied),
        confidence: bridgedConfidence,
        sampleCount: acceptedSamples,
        rawApplied: centerSample.applied,
        delta: bridgedApplied - centerSample.applied,
        note: String(format: "29-sample %.2fs bridge support %.3f adaptive %.2fs/%.1fpx zoomAuthority %.2f blend %.2f centerKeep %.3f centerAnchor %.3f uncapped", renderTurnTransitionSmoothingWindowSeconds, supportMagnitude, transitionWindowSeconds, timing.travelPixels, zoomBridgeAuthority, bridgeBlend, abs(bridgedMacro - averagedMacro), abs(anchoredMacro - bridgedMacro))
    )
}

private func turnTransitionBridgeBlend(
    centerTurnConfidence: Float,
    centerTrackingConfidence: Float,
    centerWalkingTrackingConfidence: Float,
    centerEdgeQuality: Float,
    bridgeTurnConfidence: Float,
    bridgeMacroX: Float,
    turnSmoothingStrength: Double,
    centerTurnDetected: Float,
    bridgeTurnDetected: Float
) -> Float {
    let centerEdgeSupport = turnTransitionBridgeEdgeSupport(edgeQuality: centerEdgeQuality)
    let centerTrackingQualitySupport = turnTransitionBridgeQualitySupport(
        trackingConfidence: centerTrackingConfidence,
        walkingTrackingConfidence: centerWalkingTrackingConfidence,
        edgeQuality: centerEdgeQuality
    )
    let centerTurnResponse = turnCorrectionConfidenceResponse(centerTurnConfidence)
    let bridgeTurnResponse = turnCorrectionConfidenceResponse(bridgeTurnConfidence)
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
            abs(bridgeMacroX),
            start: renderTurnTransitionBridgeLowEdgeMacroStartPixels,
            full: renderTurnTransitionBridgeLowEdgeMacroFullPixels
        )
    let highStrengthBlendFloor = turnSmoothingZoomNormalized(turnSmoothingStrength)
        * adaptiveXTurnTransitionHighStrengthBlendFloor
        * confidenceRamp(
            abs(bridgeMacroX),
            start: adaptiveXTurnTransitionHighStrengthBlendStartPixels,
            full: adaptiveXTurnTransitionHighStrengthBlendFullPixels
        )
    let preRollBlend = turnSmoothingZoomNormalized(turnSmoothingStrength)
        * adaptiveXTurnTransitionPreRollMaximumBlend
        * confidenceRamp(
            max(0.0, abs(bridgeTurnDetected) - abs(centerTurnDetected)),
            start: adaptiveXTurnTransitionPreRollStartPixels,
            full: adaptiveXTurnTransitionPreRollFullPixels
        )
        * (1.0 - confidenceRamp(
            abs(centerTurnDetected),
            start: adaptiveXTurnTransitionPreRollStartPixels * 0.5,
            full: adaptiveXTurnTransitionPreRollFullPixels * 0.75
        ))
    return clamp(
        max(gatedBlend, max(lowEdgeLargeTurnBlend, max(highStrengthBlendFloor, preRollBlend))),
        min: renderTurnTransitionBridgeMinimumBlend,
        max: renderTurnTransitionBridgeMaximumBlend
    )
}

private func turnTransitionBridgeQualitySupport(
    trackingConfidence: Float,
    walkingTrackingConfidence: Float,
    edgeQuality: Float
) -> Float {
    let trackingSupport = confidenceRamp(
        clamp(trackingConfidence, min: 0.0, max: 1.0),
        start: 0.12,
        full: 0.52
    )
    let walkingSupport = confidenceRamp(
        clamp(walkingTrackingConfidence, min: 0.0, max: 1.0),
        start: 0.12,
        full: 0.52
    ) * 0.85
    let edgeSupport = turnTransitionBridgeEdgeSupport(edgeQuality: edgeQuality)
    return min(max(trackingSupport, walkingSupport), edgeSupport)
}

private func turnTransitionBridgeEdgeSupport(edgeQuality: Float) -> Float {
    confidenceRamp(
        clamp(edgeQuality, min: 0.0, max: 1.0),
        start: renderTurnTransitionBridgeEdgeGateStart,
        full: renderTurnTransitionBridgeEdgeGateFull
    )
}

private func turnSmoothingZoomBridgeAuthority(
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

private func turnSmoothingZoomNormalized(_ value: Double) -> Float {
    let boundedValue = clamp(
        Float(value.isFinite ? value : 0.0),
        min: 0.0,
        max: adaptiveXTurnTransitionMaximumZoomParameter
    )
    return boundedValue / max(adaptiveXTurnTransitionMaximumZoomParameter, Float.ulpOfOne)
}

private func turnSmoothingBridgeBlend(_ value: Double) -> Float {
    clamp(
        turnSmoothingZoomNormalized(value)
            * (adaptiveXTurnTransitionMaximumZoomParameter / adaptiveXTurnTransitionStandardStrength),
        min: 0.0,
        max: 1.0
    )
}

private func turnSmoothingZoomDemandSupport(
    turnTravelPixels: Float,
    turnConfidence: Float
) -> Float {
    let travelSupport = confidenceRamp(
        abs(turnTravelPixels),
        start: adaptiveXTurnTransitionZoomStartPixels * 0.5,
        full: adaptiveXTurnTransitionZoomFullPixels * 0.60
    )
    let confidenceSupport = confidenceRamp(
        clamp(turnConfidence, min: 0.0, max: 1.0),
        start: adaptiveXTurnTransitionZoomConfidenceStart * 0.5,
        full: adaptiveXTurnTransitionZoomConfidenceFull * 0.80
    )
    return min(travelSupport, confidenceSupport)
}

private func turnTransitionCenterAnchoredBridgeMacroX(
    centerMacroX: Float,
    bridgeMacroX: Float,
    centerTurnConfidence: Float,
    centerTrackingConfidence: Float,
    centerWalkingTrackingConfidence: Float,
    centerEdgeQuality: Float,
    zoomBridgeAuthority: Float
) -> Float {
    guard abs(centerMacroX) >= renderTurnTransitionMinimumMacroPixels,
          abs(bridgeMacroX) > abs(centerMacroX),
          (centerMacroX * bridgeMacroX) > 0.0
    else {
        return bridgeMacroX
    }
    let centerReliability = turnCorrectionConfidenceResponse(centerTurnConfidence)
        * turnTransitionBridgeQualitySupport(
            trackingConfidence: centerTrackingConfidence,
            walkingTrackingConfidence: centerWalkingTrackingConfidence,
            edgeQuality: centerEdgeQuality
        )
    let anchor = confidenceRamp(centerReliability, start: 0.18, full: 0.45)
        * (1.0 - (clamp(zoomBridgeAuthority, min: 0.0, max: 1.0) * renderTurnTransitionZoomCenterAnchorFade))
    return bridgeMacroX + ((centerMacroX - bridgeMacroX) * anchor)
}

private func assessment(for context: AssessmentContext, index: Int, options: Options, includeRenderTurnBridge: Bool = false) -> FrameAssessment {
    let analysis = context.analysis
    let frame = analysis.frames[index]
    let outputWidth = options.outputSize?.width ?? Float(analysis.sampleWidth)
    let outputHeight = options.outputSize?.height ?? Float(analysis.sampleHeight)
    let xScale = outputWidth / Float(max(1, analysis.sampleWidth))
    let yScale = outputHeight / Float(max(1, analysis.sampleHeight))

    let strideIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: strideWindowSeconds)
    let warpGateIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: farFieldOuterWindowSeconds)
    let centerResidual = analysis.residuals[index]
    let quality = frameTrackingQuality(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index],
        qualityModel: analysis.qualityModel
    )
    let tracking = frameTrackingConfidence(quality)
    let walkingTracking = walkingBandTrackingConfidence(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index],
        qualityModel: analysis.qualityModel
    )

    let footstepBaseX = context.footstepBaselineXPath[index]
    let footstepBaseY = context.footstepBaselineYPath[index]
    let footstepBaseR = context.footstepBaselineRPath[index]
    let footstepCleanX = context.footstepCleanXPath[index]
    let footstepCleanY = context.footstepCleanYPath[index]
    let footstepCleanR = context.footstepCleanRPath[index]
    let strideSmoothX = context.strideSmoothedXPath[index]
    let strideSmoothY = context.strideSmoothedYPath[index]
    let strideSmoothR = context.strideSmoothedRPath[index]

    let strideResidual = percentileValue(analysis.residuals, indices: strideIndices, percentile: 0.70)
    let strideTracking = residualAdjustedTrackingConfidence(
        walkingTracking,
        residual: strideResidual,
        multiplier: 0.6,
        qualityModel: analysis.qualityModel
    )
    let turnSample = turnCorrectionSample(for: context, index: index, options: options)
    let turnBandX = turnSample.bandX
    let turnBandY = turnSample.bandY
    let turnBandRoll = turnSample.bandRoll
    let turnOwnershipX = turnSample.ownership
    let turnOwnershipY = turnSample.ownershipY
    let rawTurnQ = turnSample.rawConfidence
    let turnQ = turnSample.confidence
    let rawTurnShakeSuppression = turnStabilizerShakeSuppression(
        turnOwnership: turnOwnershipX,
        turnConfidence: rawTurnQ
    )
    let turnShakeSuppression = smoothedTurnShakeSuppression(
        rawSuppression: rawTurnShakeSuppression,
        gateScales: context.footstepXTurnGateScales,
        frames: analysis.frames,
        centerTime: frame.time
    )

    let footX = analysis.footstepPathX[index] - footstepBaseX
    let footY = analysis.footstepPathY[index] - footstepBaseY
    let footR = analysis.footstepPathRoll[index] - footstepBaseR
    let strideX = footstepCleanX - strideSmoothX
    let strideY = footstepCleanY - strideSmoothY
    let strideR = footstepCleanR - strideSmoothR
    let rawFootQX = footstepConfidence(values: analysis.footstepPathX, baselineValues: context.footstepBaselineXPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScalePixels)
    let rawFootQY = footstepConfidence(values: analysis.footstepPathY, baselineValues: context.footstepBaselineYPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScalePixels)
    let rawFootQR = footstepConfidence(values: analysis.footstepPathRoll, baselineValues: context.footstepBaselineRPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScaleDegrees)
    let rawStrideQX = strideConfidence(bandValue: strideX, trackingConfidence: strideTracking, fullScale: strideFullScalePixels)
    let rawStrideQY = strideConfidence(bandValue: strideY, trackingConfidence: strideTracking, fullScale: strideFullScalePixels)
    let rawStrideQR = strideConfidence(bandValue: strideR, trackingConfidence: strideTracking, fullScale: strideFullScaleDegrees)
    let farFieldTurnOwnedXSupport = farFieldTurnOwnedWalkingXSupport(
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: walkingTracking,
        edgeQuality: searchRadiusEdgeQuality(
            hitCount: analysis.searchRadiusHitCounts[index],
            totalCount: analysis.searchRadiusTotalCounts[index]
        )
    )
    let baseFootstepXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
    let baseStrideXTurnGate = clamp(1.0 - (turnShakeSuppression * turnOwnershipStrideXSuppression), min: 0.0, max: 1.0)
    let turnXMacroPixels = abs(turnBandX * xScale)
    let turnYMacroPixels = abs(turnBandY * yScale)
    let footstepXTurnGateFloor = turnOwnedWalkingXGateFloor(
        rawConfidence: rawFootQX,
        bandMagnitude: abs(footX * xScale),
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipX,
        turnMacroMagnitude: turnXMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport
    )
    let strideXTurnGateFloor = turnOwnedWalkingXGateFloor(
        rawConfidence: rawStrideQX,
        bandMagnitude: abs(strideX * xScale),
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
        bandPixels: footX * xScale,
        turnOwnership: turnOwnershipX
    )
    let footstepXWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
        bandPixels: footX * xScale,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipX,
        turnMacroMagnitude: turnXMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport,
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: strideTracking,
        farFieldConfidence: analysis.farFieldConfidence[index]
    ) * turnOwnedFootstepXFineGate
    let footstepYWalkingRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
        bandPixels: footY * yScale,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipY,
        turnMacroMagnitude: turnYMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport,
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: strideTracking,
        farFieldConfidence: analysis.farFieldConfidence[index]
    )
    let footstepXFarFieldConfidenceFloor = max(
        turnOwnedFarFieldWalkingXConfidenceFloor(
            bandMagnitude: abs(footX * xScale),
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnXMacroPixels,
            farFieldSupport: farFieldTurnOwnedXSupport
        ) * turnOwnedFootstepXFineGate,
        max(
            farFieldFootstepConfidenceFloor(
                bandPixels: footX * xScale,
                farFieldSupport: farFieldTurnOwnedXSupport
            ) * turnOwnedFootstepXFineGate,
            max(
                turnOwnedFootstepXRescueConfidenceFloor(
                    bandPixels: footX * xScale,
                    turnShakeSuppression: turnShakeSuppression,
                    turnOwnership: turnOwnershipX,
                    farFieldSupport: farFieldTurnOwnedXSupport,
                    fineGate: turnOwnedFootstepXFineGate
                ),
                footstepXWalkingRescueConfidenceFloor
            )
        )
    )
    let strideXBaseFarFieldConfidenceFloor = turnOwnedFarFieldWalkingXConfidenceFloor(
        bandMagnitude: abs(strideX * xScale),
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipX,
        turnMacroMagnitude: turnXMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport
    ) * turnOwnedStrideXGateFloorScale
    let strideXRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
        bandPixels: strideX * xScale,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipX,
        turnMacroMagnitude: turnXMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport,
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: strideTracking,
        farFieldConfidence: analysis.farFieldConfidence[index]
    )
    let footstepYFarFieldConfidenceFloor = max(
        farFieldFootstepVerticalConfidenceFloor(
            bandPixels: footY * yScale,
            farFieldSupport: farFieldTurnOwnedXSupport
        ),
        footstepYWalkingRescueConfidenceFloor
    )
    let footstepRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
        bandDegrees: footR,
        farFieldSupport: farFieldTurnOwnedXSupport
    )
    let strideYBaseFarFieldConfidenceFloor = farFieldFootstepVerticalConfidenceFloor(
        bandPixels: strideY * yScale,
        farFieldSupport: farFieldTurnOwnedXSupport
    ) * farFieldStrideVerticalConfidenceFloorScale
    let strideYRescueConfidenceFloor = turnOwnedFarFieldWalkingRescueConfidenceFloor(
        bandPixels: strideY * yScale,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnership: turnOwnershipY,
        turnMacroMagnitude: turnYMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport,
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: strideTracking,
        farFieldConfidence: analysis.farFieldConfidence[index]
    )
    let strideXFarFieldConfidenceFloor = max(strideXBaseFarFieldConfidenceFloor, strideXRescueConfidenceFloor)
    let strideYFarFieldConfidenceFloor = max(strideYBaseFarFieldConfidenceFloor, strideYRescueConfidenceFloor)
    let strideRollFarFieldConfidenceFloor = farFieldFootstepRollConfidenceFloor(
        bandDegrees: strideR,
        farFieldSupport: farFieldTurnOwnedXSupport
    ) * farFieldStrideRollConfidenceFloorScale

    let footQX = max(rawFootQX * footstepXTurnGate, footstepXFarFieldConfidenceFloor)
    let footQY = max(rawFootQY * footstepYTurnGate, footstepYFarFieldConfidenceFloor)
    let footQR = max(rawFootQR * footstepRollTurnGate, footstepRollFarFieldConfidenceFloor)
    let unscaledRawFootCorrectionX = -(footX * xScale) * walkingCorrectionFactor(options.strengths.microX, confidence: footQX, maxStrength: 10.0)
    let rawFootCorrectionX = unscaledRawFootCorrectionX * lowEvidenceLargeFootstepXScale(
        rawConfidence: max(rawFootQX, footstepXFarFieldConfidenceFloor),
        correctionPixels: unscaledRawFootCorrectionX,
        farFieldSupport: farFieldTurnOwnedXSupport
    )
    let rawFootCorrectionY = -(footY * yScale) * verticalWalkingCorrectionFactor(options.strengths.microY, confidence: footQY, maxStrength: 10.0)
    let footstepXContinuityConfidenceScale = max(footstepXTurnGate, farFieldTurnOwnedXSupport)
    let limitedFootCorrectionX = footstepContinuityLimitedCorrection(
        values: analysis.footstepPathX,
        baselineValues: context.footstepBaselineXPath,
        analysis: analysis,
        centerIndex: index,
        rawCorrection: rawFootCorrectionX,
        outputScale: xScale,
        requestedStrength: options.strengths.microX,
        fullImpulseScale: footstepFullScalePixels,
        confidenceScale: footstepXContinuityConfidenceScale,
        confidenceFloor: footstepXFarFieldConfidenceFloor
    )
    let limitedFootCorrectionY = footstepContinuityLimitedCorrection(
        values: analysis.footstepPathY,
        baselineValues: context.footstepBaselineYPath,
        analysis: analysis,
        centerIndex: index,
        rawCorrection: rawFootCorrectionY,
        outputScale: yScale,
        requestedStrength: options.strengths.microY,
        fullImpulseScale: footstepFullScalePixels,
        confidenceScale: footstepYTurnGate
    )
    let strideQX = max(rawStrideQX * strideXTurnGate, strideXFarFieldConfidenceFloor)
    let strideQY = max(rawStrideQY * strideYTurnGate, strideYFarFieldConfidenceFloor)
    let strideQR = max(rawStrideQR * strideRollTurnGate, strideRollFarFieldConfidenceFloor)
    let strideCorrectionX = -(strideX * xScale) * walkingCorrectionFactor(options.strengths.strideX, confidence: strideQX, maxStrength: 10.0)
    let strideCorrectionY = -(strideY * yScale) * verticalWalkingCorrectionFactor(options.strengths.strideY, confidence: strideQY, maxStrength: 10.0)
    let cameraMacroYConfidence = turnConfidence(
        bandValue: turnBandY,
        trackingConfidence: turnSample.macroTrackingConfidence
    )
    let cameraMacroRollConfidence = cameraJitterMacroRotationConfidence(
        bandValue: turnBandRoll,
        trackingConfidence: turnSample.macroTrackingConfidence
    )
    let cameraMacroCorrectionY = -(turnBandY * yScale) * verticalWalkingCorrectionFactor(
        options.strengths.microY,
        confidence: cameraMacroYConfidence,
        maxStrength: 10.0
    )
    let cameraMacroCorrectionRoll = -turnBandRoll * walkingCorrectionFactor(
        options.strengths.microR,
        confidence: cameraMacroRollConfidence
    )
    let trajectoryMicroJitterOffset = farFieldWalkingResidualContinuityOffset(
        footstepBandX: footX * xScale,
        footstepBandY: footY * yScale,
        footstepCorrectionX: limitedFootCorrectionX,
        footstepCorrectionY: limitedFootCorrectionY,
        strideBandX: strideX * xScale,
        strideBandY: strideY * yScale,
        strideCorrectionX: strideCorrectionX,
        strideCorrectionY: strideCorrectionY,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnershipX: turnOwnershipX,
        turnOwnershipY: turnOwnershipY,
        turnMacroX: turnXMacroPixels,
        turnMacroY: turnYMacroPixels,
        farFieldSupport: farFieldTurnOwnedXSupport,
        warpConfidence: max(analysis.warpConfidence[index], analysis.farFieldConfidence[index]),
        trackingConfidence: strideTracking,
        farFieldConfidence: analysis.farFieldConfidence[index]
    )
    let footAppliedX = abs(limitedFootCorrectionX)
    let footAppliedY = abs(limitedFootCorrectionY)
    let footAppliedR = abs(footR) * walkingCorrectionFactor(options.strengths.microR, confidence: footQR)
    let footDetected = hypotf(footX * xScale, footY * yScale) + (abs(footR) * 12.0)
    let footApplied = hypotf(footAppliedX, footAppliedY) + (footAppliedR * 12.0)
    let strideAppliedX = abs(strideCorrectionX)
    let strideAppliedY = abs(strideCorrectionY)
    let strideAppliedR = abs(strideR) * walkingCorrectionFactor(options.strengths.strideR, confidence: strideQR)
    let strideDetected = hypotf(strideX * xScale, strideY * yScale) + (abs(strideR) * 12.0)
    let strideApplied = hypotf(strideAppliedX, strideAppliedY) + (strideAppliedR * 12.0)
    let walkingResidualBeforeX = (footX * xScale)
        + limitedFootCorrectionX
        + (strideX * xScale)
        + strideCorrectionX
    let walkingResidualBeforeY = (footY * yScale)
        + limitedFootCorrectionY
        + (strideY * yScale)
        + strideCorrectionY
    let walkingResidualBefore = hypotf(walkingResidualBeforeX, walkingResidualBeforeY)
    let walkingResidualAfter = hypotf(
        walkingResidualBeforeX + trajectoryMicroJitterOffset.x,
        walkingResidualBeforeY + trajectoryMicroJitterOffset.y
    )
    let trajectoryMicroJitterApplied = max(0.0, walkingResidualBefore - walkingResidualAfter)

    let turnDetected = turnSample.detected
    let turnApplied = turnSample.applied
    let renderTurnBridge = includeRenderTurnBridge
        ? renderTurnBridgeAssessment(for: context, index: index, options: options, centerSample: turnSample)
        : RenderTurnBridgeAssessment(
            applied: turnApplied,
            remaining: max(0.0, turnDetected - turnApplied),
            confidence: turnQ,
            sampleCount: 1,
            rawApplied: turnApplied,
            delta: 0.0,
            note: "render bridge evaluated after candidate selection"
        )

    let rawWarpConfidence = analysis.warpConfidence[index]
    let warpTracking = stableFarFieldWarpTrackingConfidence(
        analysis: analysis,
        indices: warpGateIndices,
        currentTrackingConfidence: tracking
    )
    let warpEdgeQuality = stableFarFieldWarpEdgeQuality(
        analysis: analysis,
        indices: warpGateIndices,
        currentSearchRadiusHitCount: analysis.searchRadiusHitCounts[index],
        currentSearchRadiusTotalCount: analysis.searchRadiusTotalCounts[index]
    )
    let stableWarpConfidence = stableFarFieldWarpConfidence(
        analysis: analysis,
        indices: warpGateIndices,
        currentWarpConfidence: rawWarpConfidence
    )
    let warpGateComponents = farFieldWarpGateComponents(
        warpConfidence: stableWarpConfidence,
        trackingConfidence: warpTracking,
        edgeQuality: warpEdgeQuality
    )
    let warpGate = warpGateComponents.gate
    let warpTurnGate: Float = 1.0
    let appliedWarpConfidence = farFieldWarpAppliedConfidence(
        stableWarpConfidence: stableWarpConfidence,
        warpGate: warpGate,
        turnGate: warpTurnGate,
        trackingConfidence: warpTracking,
        edgeQuality: warpEdgeQuality
    )
    let warpDetected = context.warpMagnitudes[index] * effectiveFarFieldWarpStrength(Float(options.strengths.warp))
    let warpApplied = warpDetected * appliedWarpConfidence
    let lensBand = sourceSpaceLensShakeBand(
        analysis: analysis,
        index: index,
        xScale: xScale,
        yScale: yScale,
        appliedWarpConfidence: appliedWarpConfidence,
        farFieldConfidence: analysis.farFieldConfidence[index],
        trackingConfidence: tracking,
        edgeQuality: warpEdgeQuality,
        turnShakeSuppression: turnShakeSuppression,
        turnOwnershipX: turnOwnershipX,
        turnOwnershipY: turnOwnershipY,
        cameraStrengthX: options.strengths.microX,
        cameraStrengthY: options.strengths.microY,
        cameraStrengthR: options.strengths.microR,
        cameraLimitXPercent: options.strengths.cameraX,
        cameraLimitYPercent: options.strengths.cameraY,
        cameraLimitRotationDegrees: options.strengths.cameraR
    )

    let cameraMacroDetected = abs(turnBandY * yScale) + (abs(turnBandRoll) * 12.0)
    let cameraMacroApplied = abs(cameraMacroCorrectionY) + (abs(cameraMacroCorrectionRoll) * 12.0)
    let cameraMacroRemaining = abs((turnBandY * yScale) + cameraMacroCorrectionY)
        + (abs(turnBandRoll + cameraMacroCorrectionRoll) * 12.0)
    let cameraDetected = footDetected + strideDetected + walkingResidualBefore + cameraMacroDetected + lensBand.detected
    let cameraApplied = footApplied + strideApplied + trajectoryMicroJitterApplied + cameraMacroApplied + lensBand.applied
    let cameraConfidence = max(
        max(
            (footQX + footQY + footQR) / 3.0,
            (strideQX + strideQY + strideQR) / 3.0
        ),
        max(max(cameraMacroYConfidence, cameraMacroRollConfidence), lensBand.confidence)
    )
    let farFieldDetected = warpDetected
    let farFieldApplied = warpApplied
    let bands = [
        BandAssessment(
            name: "CAM",
            detected: cameraDetected,
            applied: cameraApplied,
            remaining: walkingResidualAfter + cameraMacroRemaining,
            confidence: cameraConfidence,
            note: String(format: "foot X %.3f Y %.3f R %.3f | stride X %.3f Y %.3f R %.3f | macro Y %.3f R %.3f corr %.3f %.3f | rigid %@ | traj %.3f %.3f | post %.3f", footX, footY, footR, strideX, strideY, strideR, turnBandY, turnBandRoll, cameraMacroCorrectionY, cameraMacroCorrectionRoll, lensBand.note, trajectoryMicroJitterOffset.x, trajectoryMicroJitterOffset.y, walkingResidualAfter + cameraMacroRemaining)
        ),
        BandAssessment(
            name: "WARP",
            detected: farFieldDetected,
            applied: farFieldApplied,
            remaining: max(0.0, farFieldDetected - farFieldApplied),
            confidence: appliedWarpConfidence,
            note: String(format: "warp q %.2f stable %.2f gate %.2f trk %.2f edge %.2f", rawWarpConfidence, stableWarpConfidence, warpGate, warpTracking, warpGateComponents.edgeGate)
        ),
        BandAssessment(
            name: "TURN",
            detected: turnDetected,
            applied: turnApplied,
            remaining: max(0.0, turnDetected - turnApplied),
            confidence: turnQ,
            note: String(format: "X band %.3f ownership %.2f", turnBandX, turnOwnershipX)
        )
    ]

    return FrameAssessment(
        index: index,
        absoluteTime: frame.time,
        clipTime: frame.time - analysis.rangeStartSeconds,
        trackingConfidence: tracking,
        walkingTrackingConfidence: walkingTracking,
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blur: analysis.blurAmounts[index],
        residualQuality: quality.residualQuality,
        blurQuality: quality.blurQuality,
        blockCoverage: quality.blockCoverage,
        acceptedBlocks: analysis.acceptedBlockCounts[index],
        totalBlocks: analysis.totalBlockCounts[index],
        edgeHits: analysis.searchRadiusHitCounts[index],
        edgeTotal: analysis.searchRadiusTotalCounts[index],
        edgeQuality: warpGateComponents.edgeQuality,
        warpTrackingConfidence: warpTracking,
        warpTrackingGate: warpGateComponents.trackingGate,
        warpEdgeGate: warpGateComponents.edgeGate,
        warpGate: warpGate,
        footstepRawImpulseX: footX,
        footstepRawImpulseY: footY,
        footstepBaselineX: footstepBaseX,
        footstepBaselineY: footstepBaseY,
        footstepConfidenceX: footQX,
        footstepConfidenceY: footQY,
        footstepRawCorrectionX: rawFootCorrectionX,
        footstepRawCorrectionY: rawFootCorrectionY,
        footstepLimitedCorrectionX: limitedFootCorrectionX,
        footstepLimitedCorrectionY: limitedFootCorrectionY,
        footstepPulseLimitedX: abs(rawFootCorrectionX - limitedFootCorrectionX),
        footstepPulseLimitedY: abs(rawFootCorrectionY - limitedFootCorrectionY),
        renderTurnBridge: renderTurnBridge,
        bands: bands
    )
}

private func activeIndices(_ frames: [AnalysisFrame], centerTime: Double, windowSeconds: Double) -> [Int] {
    let halfWindow = windowSeconds * 0.5
    let indices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow)
    return indices.isEmpty ? Array(frames.indices) : Array(indices)
}

private func indicesWithinTimeRadius(_ frames: [AnalysisFrame], centerTime: Double, radiusSeconds: Double) -> [Int] {
    guard !frames.isEmpty else {
        return []
    }
    let boundedRadius = max(0.0, radiusSeconds)
    let startTime = centerTime - boundedRadius - timeWindowSelectionEpsilon
    let endTime = centerTime + boundedRadius + timeWindowSelectionEpsilon
    let lower = lowerBoundFrameIndex(frames, time: startTime)
    let upper = upperBoundFrameIndex(frames, time: endTime)
    guard lower < upper else {
        return []
    }
    return Array(lower..<upper)
}

private func lowerBoundFrameIndex(_ frames: [AnalysisFrame], time: Double) -> Int {
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

private func upperBoundFrameIndex(_ frames: [AnalysisFrame], time: Double) -> Int {
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

private func timeWeightedAverage(_ values: [Float], frames: [AnalysisFrame], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float {
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
        let leftBoundary = position > 0 ? max(windowStart, (frames[sortedIndices[position - 1]].time + currentTime) * 0.5) : windowStart
        let rightBoundary = position + 1 < sortedIndices.count ? min(windowEnd, (currentTime + frames[sortedIndices[position + 1]].time) * 0.5) : windowEnd
        let weight = max(0.0, rightBoundary - leftBoundary)
        weightedTotal += values[index] * Float(weight)
        totalWeight += weight
    }
    guard totalWeight > 1e-9 else {
        return indices.reduce(Float(0.0)) { $0 + values[$1] } / Float(indices.count)
    }
    return weightedTotal / Float(totalWeight)
}

private func outerLinearPredictionPath(_ values: [Float], frames: [AnalysisFrame], targetIndices: [Int], innerWindowSeconds: Double, outerWindowSeconds: Double) -> [Float] {
    guard !values.isEmpty else {
        return values
    }
    var predicted = values
    for index in Set(targetIndices) where values.indices.contains(index) && frames.indices.contains(index) {
        predicted[index] = outerLinearPrediction(
            values,
            frames: frames,
            centerIndex: index,
            innerWindowSeconds: innerWindowSeconds,
            outerWindowSeconds: outerWindowSeconds
        ) ?? values[index]
    }
    return predicted
}

private func locallyTimeWeightedAveragePath(_ values: [Float], frames: [AnalysisFrame], targetIndices: [Int], windowSeconds: Double) -> [Float] {
    guard !values.isEmpty else {
        return values
    }
    var smoothed = values
    let halfWindow = max(0.0, windowSeconds * 0.5)
    for index in Set(targetIndices) where values.indices.contains(index) && frames.indices.contains(index) {
        let centerTime = frames[index].time
        let localIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow)
        let indices = localIndices.isEmpty ? [index] : Array(localIndices)
        smoothed[index] = timeWeightedAverage(
            values,
            frames: frames,
            indices: indices,
            centerTime: centerTime,
            windowSeconds: windowSeconds
        )
    }
    return smoothed
}

private func timeWeightedMonotonicSCurveValue(_ values: [Float], frames: [AnalysisFrame], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float? {
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
        let delta = values[sortedIndices[position]] - values[sortedIndices[position - 1]]
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

private func outerLinearPrediction(_ values: [Float], frames: [AnalysisFrame], centerIndex: Int, innerWindowSeconds: Double, outerWindowSeconds: Double) -> Float? {
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
        if distance <= outerWindow + timeWindowSelectionEpsilon && distance > innerWindow + timeWindowSelectionEpsilon {
            points.append((x: Float(offsetSeconds), y: values[index]))
        }
    }
    guard points.count >= 3 else {
        let indices = surroundingIndices(around: centerIndex, frames: frames, innerWindowSeconds: innerWindow, outerWindowSeconds: outerWindow).filter { values.indices.contains($0) }
        return median(indices.map { values[$0] })
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

private func surroundingIndices(around centerIndex: Int, frames: [AnalysisFrame], innerWindowSeconds: Double, outerWindowSeconds: Double) -> [Int] {
    guard frames.indices.contains(centerIndex) else {
        return []
    }
    let innerWindow = max(0.0, min(innerWindowSeconds, outerWindowSeconds))
    let outerWindow = max(innerWindow, outerWindowSeconds)
    let centerTime = frames[centerIndex].time
    let outerIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: outerWindow)
    let indices = outerIndices.filter { index in
        let distance = abs(frames[index].time - centerTime)
        return distance <= outerWindow + timeWindowSelectionEpsilon && distance > innerWindow + timeWindowSelectionEpsilon
    }
    if indices.count >= 3 {
        return Array(indices)
    }
    return outerIndices
}

private func confidenceCleanedFootstepPath(
    values: [Float],
    baselineValues: [Float],
    analysis: Analysis,
    targetIndices: [Int],
    fullImpulseScale: Float,
    confidenceScales: [Int: Float] = [:]
) -> [Float] {
    guard !values.isEmpty else {
        return values
    }
    var cleaned = values
    for index in targetIndices {
        guard values.indices.contains(index),
              baselineValues.indices.contains(index),
              analysis.frames.indices.contains(index),
              analysis.analysisConfidence.indices.contains(index),
              analysis.residuals.indices.contains(index),
              analysis.blurAmounts.indices.contains(index),
              analysis.acceptedBlockCounts.indices.contains(index),
              analysis.totalBlockCounts.indices.contains(index)
        else {
            continue
        }
        let tracking = walkingBandTrackingConfidence(
            motionConfidence: analysis.analysisConfidence[index],
            residual: analysis.residuals[index],
            blurAmount: analysis.blurAmounts[index],
            acceptedBlockCount: analysis.acceptedBlockCounts[index],
            totalBlockCount: analysis.totalBlockCounts[index],
            qualityModel: analysis.qualityModel
        )
        let confidence = footstepConfidence(
            values: values,
            baselineValues: baselineValues,
            frames: analysis.frames,
            index: index,
            trackingConfidence: tracking,
            fullImpulseScale: fullImpulseScale
        )
        let confidenceScale = clamp(confidenceScales[index] ?? 1.0, min: 0.0, max: 1.0)
        let effectiveConfidence = confidence * confidenceScale
        cleaned[index] = values[index] - ((values[index] - baselineValues[index]) * effectiveConfidence)
    }
    return cleaned
}

private func footstepContinuityLimitedCorrection(
    values: [Float],
    baselineValues: [Float],
    analysis: Analysis,
    centerIndex: Int,
    rawCorrection: Float,
    outputScale: Float,
    requestedStrength: Double,
    fullImpulseScale: Float,
    confidenceScale: Float = 1.0,
    confidenceFloor: Float = 0.0
) -> Float {
    guard rawCorrection.isFinite,
          outputScale.isFinite,
          outputScale > 0.0,
          values.indices.contains(centerIndex),
          baselineValues.indices.contains(centerIndex),
          analysis.frames.indices.contains(centerIndex)
    else {
        return rawCorrection
    }

    let centerTime = analysis.frames[centerIndex].time
    let halfWindow = footstepXYContinuityWindowSeconds * 0.5
    var indices = indicesWithinTimeRadius(
        analysis.frames,
        centerTime: centerTime,
        radiusSeconds: halfWindow
    ).filter { values.indices.contains($0) && baselineValues.indices.contains($0) }
    guard indices.count >= 5 else {
        return rawCorrection
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
        let tracking = walkingBandTrackingConfidence(
            motionConfidence: analysis.analysisConfidence[index],
            residual: analysis.residuals[index],
            blurAmount: analysis.blurAmounts[index],
            acceptedBlockCount: analysis.acceptedBlockCounts[index],
            totalBlockCount: analysis.totalBlockCounts[index],
            qualityModel: analysis.qualityModel
        )
        let confidence = footstepConfidence(
            values: values,
            baselineValues: baselineValues,
            frames: analysis.frames,
            index: index,
            trackingConfidence: tracking,
            fullImpulseScale: fullImpulseScale
        )
        let correctionStrength = walkingCorrectionFactor(
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
        return rawCorrection
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
        return rawCorrection
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
        return rawCorrection
    }

    let excess = rawDeviation - spikeThreshold
    let blend = clamp(excess / max(spikeThreshold * 2.0, Float.ulpOfOne), min: 0.35, max: 0.85)
    var limitedCorrection = rawCorrection + ((localMedian - rawCorrection) * blend)
    if limitedCorrection.isFinite,
       rawCorrection.isFinite,
       abs(limitedCorrection) > abs(rawCorrection) {
        limitedCorrection = rawCorrection
    }
    return limitedCorrection
}

private func lowEvidenceLargeFootstepXScale(
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
        start: 0.35,
        full: 0.75
    )
    let attenuation = magnitudeGate * (1.0 - evidenceProtection) * (1.0 - farFieldProtection)
    return clamp(
        1.0 - (attenuation * (1.0 - footstepLowEvidenceLargeXMinimumScale)),
        min: footstepLowEvidenceLargeXMinimumScale,
        max: 1.0
    )
}

private func footstepConfidence(values: [Float], baselineValues: [Float], frames: [AnalysisFrame], index: Int, trackingConfidence: Float, fullImpulseScale: Float) -> Float {
    guard values.indices.contains(index), baselineValues.indices.contains(index) else {
        return 0.0
    }
    let baselineValue = baselineValues[index]
    let impulse = abs(values[index] - baselineValue)
    let surrounding = surroundingIndices(
        around: index,
        frames: frames,
        innerWindowSeconds: footstepInnerWindowSeconds,
        outerWindowSeconds: footstepOuterWindowSeconds
    ).filter { values.indices.contains($0) }
    guard !surrounding.isEmpty else {
        return 0.0
    }
    let surroundingNoise = median(surrounding.filter { baselineValues.indices.contains($0) }.map { abs(values[$0] - baselineValues[$0]) }) ?? 0.0
    let centerTime = frames[index].time
    let hasLeft = surrounding.contains { frames[$0].time < centerTime }
    let hasRight = surrounding.contains { frames[$0].time > centerTime }
    let supportQuality: Float = (hasLeft && hasRight) ? 1.0 : 0.65
    let surroundingNoiseFloor = min(
        surroundingNoise * footstepSurroundingNoiseMultiplier,
        fullImpulseScale * footstepSurroundingNoiseFloorCapScale
    )
    let noiseFloor = max(fullImpulseScale * footstepNoiseFloorScale, surroundingNoiseFloor)
    let impulseQuality = confidenceRamp(impulse, start: noiseFloor, full: max(noiseFloor + Float.ulpOfOne, fullImpulseScale * footstepFullResponseScale))
    return clamp(trackingConfidence * supportQuality * impulseQuality, min: 0.0, max: 1.0)
}

private func strideConfidence(bandValue: Float, trackingConfidence: Float, fullScale: Float) -> Float {
    let magnitude = abs(bandValue)
    let noiseFloor = fullScale * 0.10
    let bandQuality = confidenceRamp(magnitude, start: noiseFloor, full: max(noiseFloor + Float.ulpOfOne, fullScale * strideFullResponseScale))
    return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
}

private func turnConfidence(bandValue: Float, trackingConfidence: Float) -> Float {
    let magnitude = abs(bandValue)
    let noiseFloor = turnFullScalePixels * 0.08
    let bandQuality = confidenceRamp(magnitude, start: noiseFloor, full: max(noiseFloor + Float.ulpOfOne, turnFullScalePixels))
    return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
}

private func cameraJitterMacroRotationConfidence(bandValue: Float, trackingConfidence: Float) -> Float {
    let magnitude = abs(bandValue)
    let noiseFloor = turnFullScaleDegrees * 0.08
    let bandQuality = confidenceRamp(
        magnitude,
        start: noiseFloor,
        full: max(noiseFloor + Float.ulpOfOne, turnFullScaleDegrees)
    )
    return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
}

private func turnOwnershipConfidence(
    values: [Float],
    frames: [AnalysisFrame],
    indices: [Int],
    turnBandValue: Float,
    trackingConfidence: Float
) -> Float {
    let sortedIndices = indices.sorted().filter { values.indices.contains($0) && frames.indices.contains($0) }
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
    guard totalTravel > footstepFullScalePixels else {
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
        start: footstepFullScalePixels * 0.70,
        full: max((footstepFullScalePixels * 0.70) + Float.ulpOfOne, turnFullScalePixels * 0.65)
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

private func turnStabilizerShakeSuppression(turnOwnership: Float, turnConfidence: Float) -> Float {
    let ownershipQuality = confidenceRamp(turnOwnership, start: 0.12, full: 0.48)
    return clamp(max(turnConfidence, ownershipQuality), min: 0.0, max: 1.0)
}

private func turnOwnedWalkingXGateFloor(
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

private func turnOwnedWalkingXMacroGate(_ turnMacroMagnitude: Float) -> Float {
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

private func turnOwnedFarFieldXMacroGate(
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

private func farFieldTurnOwnedWalkingXSupport(
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

private func turnOwnedFarFieldWalkingXConfidenceFloor(
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

private func turnOwnedFarFieldWalkingRescueConfidenceFloor(
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

private func farFieldWalkingResidualContinuityOffset(
    footstepBandX: Float,
    footstepBandY: Float,
    footstepCorrectionX: Float,
    footstepCorrectionY: Float,
    strideBandX: Float,
    strideBandY: Float,
    strideCorrectionX: Float,
    strideCorrectionY: Float,
    turnShakeSuppression: Float,
    turnOwnershipX: Float,
    turnOwnershipY: Float,
    turnMacroX: Float,
    turnMacroY: Float,
    farFieldSupport: Float,
    warpConfidence: Float,
    trackingConfidence: Float,
    farFieldConfidence: Float
) -> (x: Float, y: Float) {
    (
        x: farFieldWalkingResidualContinuityCorrection(
            footstepBandPixels: footstepBandX,
            footstepCorrectionPixels: footstepCorrectionX,
            strideBandPixels: strideBandX,
            strideCorrectionPixels: strideCorrectionX,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipX,
            turnMacroMagnitude: turnMacroX,
            farFieldSupport: farFieldSupport,
            warpConfidence: warpConfidence,
            trackingConfidence: trackingConfidence,
            farFieldConfidence: farFieldConfidence
        ),
        y: farFieldWalkingResidualContinuityCorrection(
            footstepBandPixels: footstepBandY,
            footstepCorrectionPixels: footstepCorrectionY,
            strideBandPixels: strideBandY,
            strideCorrectionPixels: strideCorrectionY,
            turnShakeSuppression: turnShakeSuppression,
            turnOwnership: turnOwnershipY,
            turnMacroMagnitude: turnMacroY,
            farFieldSupport: farFieldSupport,
            warpConfidence: warpConfidence,
            trackingConfidence: trackingConfidence,
            farFieldConfidence: farFieldConfidence
        )
    )
}

private func farFieldWalkingResidualContinuityCorrection(
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
    let directFarFieldSupport = confidenceRamp(clamp(farFieldSupport, min: 0.0, max: 1.0), start: 0.08, full: 0.28)
    let pathFarFieldSupport = confidenceRamp(clamp(farFieldConfidence, min: 0.0, max: 1.0), start: 0.04, full: 0.18)
    let warpSupport = confidenceRamp(clamp(warpConfidence, min: 0.0, max: 1.0), start: 0.18, full: 0.55)
    let trackingSupport = confidenceRamp(clamp(trackingConfidence, min: 0.0, max: 1.0), start: 0.14, full: 0.38)
    let turnSupport = max(
        max(
            confidenceRamp(turnShakeSuppression, start: 0.18, full: 0.56),
            confidenceRamp(turnOwnership, start: 0.18, full: 0.56)
        ),
        confidenceRamp(turnMacroMagnitude, start: turnMacroOwnershipBandStartPixels, full: turnMacroOwnershipBandFullPixels) * 0.85
    )
    let evidenceSupport = max(directFarFieldSupport, pathFarFieldSupport)
        * max(warpSupport, trackingSupport)
        * max(0.35, turnSupport)
    let authority = clamp(residualSupport * bandSupport * evidenceSupport, min: 0.0, max: 1.0)
    guard authority > 0.0 else {
        return 0.0
    }
    let rawCorrection = -residualPixels * authority
    let limit = residualMagnitude * farFieldWalkingResidualContinuityMaximumResidualScale
    return clamp(rawCorrection, min: -limit, max: limit)
}

private func turnOwnedFootstepXFineBandGate(
    bandPixels: Float,
    turnOwnership: Float
) -> Float {
    guard bandPixels.isFinite, turnOwnership.isFinite else {
        return 0.0
    }
    return 1.0
}

private func turnOwnedFootstepXRescueConfidenceFloor(
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
    return 0.0
}

private func farFieldFootstepConfidenceFloor(
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

private func farFieldFootstepVerticalConfidenceFloor(
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

private func farFieldFootstepRollConfidenceFloor(
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

private func turnCorrectionConfidence(confidence: Float, turnOwnership: Float) -> Float {
    let ownershipFloor = confidenceRamp(turnOwnership, start: 0.12, full: 0.48) * 0.42
    return clamp(max(confidence, ownershipFloor), min: 0.0, max: 1.0)
}

private func smoothedTurnShakeSuppression(
    rawSuppression: Float,
    gateScales: [Int: Float],
    frames: [AnalysisFrame],
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

private func turnOwnershipGateScales(
    values: [Float],
    analysis: Analysis,
    targetIndices: [Int],
    windowSeconds: Double
) -> [Int: Float] {
    guard !targetIndices.isEmpty else {
        return [:]
    }
    let frames = analysis.frames
    let halfWindow = max(0.0, windowSeconds * 0.5)
    var scales: [Int: Float] = [:]
    scales.reserveCapacity(targetIndices.count)

    for index in targetIndices {
        guard values.indices.contains(index),
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
        let activeIndices = indicesWithinTimeRadius(frames, centerTime: centerTime, radiusSeconds: halfWindow)
        guard !activeIndices.isEmpty else {
            continue
        }

        let turnSmooth = timeWeightedMonotonicSCurveValue(
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
        let turnBand = values[index] - turnSmooth
        let residual = percentileValue(analysis.residuals, indices: activeIndices, percentile: 0.75)
        let trackingQuality = frameTrackingQuality(
            motionConfidence: analysis.analysisConfidence[index],
            residual: analysis.residuals[index],
            blurAmount: analysis.blurAmounts[index],
            acceptedBlockCount: analysis.acceptedBlockCounts[index],
            totalBlockCount: analysis.totalBlockCounts[index],
            qualityModel: analysis.qualityModel
        )
        let turnTracking = residualAdjustedTrackingConfidence(
            frameTrackingConfidence(trackingQuality),
            residual: residual,
            multiplier: 0.9,
            qualityModel: analysis.qualityModel
        )
        let ownership = turnOwnershipConfidence(
            values: values,
            frames: frames,
            indices: activeIndices,
            turnBandValue: turnBand,
            trackingConfidence: turnTracking
        )
        let gate = clamp(1.0 - (ownership * turnOwnershipFootstepXSuppression), min: 0.0, max: 1.0)
        if gate < 0.9999 {
            scales[index] = gate
        }
    }

    return scales
}

private func farFieldWarpGateComponents(
    warpConfidence: Float,
    trackingConfidence: Float,
    edgeQuality: Float
) -> (edgeQuality: Float, trackingGate: Float, edgeGate: Float, gate: Float) {
    guard warpConfidence > 0.0 else {
        return (edgeQuality, 0.0, 0.0, 0.0)
    }
    let trackingGate = confidenceRamp(trackingConfidence, start: farFieldWarpTrackingGateStart, full: farFieldWarpTrackingGateFull)
    let edgeGate = confidenceRamp(edgeQuality, start: farFieldWarpEdgeQualityGateStart, full: farFieldWarpEdgeQualityGateFull)
    let strictGate = correctionConfidenceResponse(clamp(trackingGate * edgeGate, min: 0.0, max: 1.0))
    let consensusGate = correctionConfidenceResponse(
        confidenceRamp(warpConfidence, start: farFieldWarpConsensusGateStart, full: farFieldWarpConsensusGateFull)
    ) * confidenceRamp(edgeQuality, start: 0.08, full: 0.42)
    let gate = max(strictGate, consensusGate)
    return (edgeQuality, trackingGate, edgeGate, gate)
}

private func farFieldWarpAppliedConfidence(
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

private func sourceSpaceLensShakeBand(
    analysis: Analysis,
    index: Int,
    xScale: Float,
    yScale: Float,
    appliedWarpConfidence: Float,
    farFieldConfidence: Float,
    trackingConfidence: Float,
    edgeQuality: Float,
    turnShakeSuppression: Float,
    turnOwnershipX: Float,
    turnOwnershipY: Float,
    cameraStrengthX: Double,
    cameraStrengthY: Double,
    cameraStrengthR: Double,
    cameraLimitXPercent: Double,
    cameraLimitYPercent: Double,
    cameraLimitRotationDegrees: Double
) -> BandAssessment {
    guard analysis.frames.indices.contains(index) else {
        return BandAssessment(name: "LENS", detected: 0.0, applied: 0.0, remaining: 0.0, confidence: 0.0, note: "no frame")
    }
    let previousTime = index > 0 ? analysis.frames[index - 1].time : analysis.frames[index].time
    let nextTime = index + 1 < analysis.frames.count ? analysis.frames[index + 1].time : analysis.frames[index].time
    let frameStep = max(1.0 / 240.0, max(nextTime - previousTime, 1.0 / 60.0) * 0.5)
    let preparedWindowSeconds = analysis.farFieldMeshDominantWindowSeconds.indices.contains(index)
        ? Double(analysis.farFieldMeshDominantWindowSeconds[index])
        : 0.0
    guard preparedWindowSeconds > 0.0 else {
        return BandAssessment(name: "LENS", detected: 0.0, applied: 0.0, remaining: 0.0, confidence: 0.0, note: "dominantWindowRequired")
    }
    let targetWindowSeconds = min(1.0, max(frameStep * 3.0, preparedWindowSeconds))
    let dominantCell = analysis.farFieldMeshDominantCell.indices.contains(index)
        ? Int(analysis.farFieldMeshDominantCell[index])
        : -1
    let innerWindowSeconds = max(lensShakeInnerWindowMinimumSeconds, targetWindowSeconds * 0.56)
    let outerWindowSeconds = min(lensShakeOuterWindowMaximumSeconds, max(lensShakeOuterWindowMinimumSeconds, targetWindowSeconds * 3.0))

    func residual(_ values: [Float]) -> Float {
        guard values.indices.contains(index) else { return 0.0 }
        return values[index] - (outerLinearPrediction(
            values,
            frames: analysis.frames,
            centerIndex: index,
            innerWindowSeconds: innerWindowSeconds,
            outerWindowSeconds: outerWindowSeconds
        ) ?? values[index])
    }
    func residualAt(_ values: [Float], index sampleIndex: Int) -> Float {
        guard values.indices.contains(sampleIndex), analysis.frames.indices.contains(sampleIndex) else { return 0.0 }
        return values[sampleIndex] - (outerLinearPrediction(
            values,
            frames: analysis.frames,
            centerIndex: sampleIndex,
            innerWindowSeconds: innerWindowSeconds,
            outerWindowSeconds: outerWindowSeconds
        ) ?? values[sampleIndex])
    }
    func pulseSmoothedPixelResidual(_ values: [Float], scale: Float) -> Float {
        let current = residual(values) * scale
        let windowFrames = analysis.farFieldMeshDominantWindowFrames.indices.contains(index)
            ? max(3, Int(round(analysis.farFieldMeshDominantWindowFrames[index])))
            : max(3, Int(round(targetWindowSeconds / frameStep)))
        let radiusFrames = max(1, windowFrames / 2)
        let centerTime = analysis.frames[index].time
        let radiusSeconds = max(frameStep, Double(radiusFrames) * frameStep)
        var weightedResidual = Float(0.0)
        var totalWeight = Float(0.0)
        for sampleIndex in (index - radiusFrames)...(index + radiusFrames) {
            guard analysis.frames.indices.contains(sampleIndex), values.indices.contains(sampleIndex) else { continue }
            let distance = abs(analysis.frames[sampleIndex].time - centerTime)
            let normalizedDistance = clamp(Float(distance / radiusSeconds), min: 0.0, max: 1.0)
            let weight = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)
            weightedResidual += residualAt(values, index: sampleIndex) * scale * weight
            totalWeight += weight
        }
        guard totalWeight > Float.ulpOfOne else { return current }
        let smoothed = weightedResidual / totalWeight
        let pulseMagnitude = abs(current - smoothed)
        let blend = confidenceRamp(
            pulseMagnitude,
            start: lensBandPulseSmoothingStartPixels,
            full: lensBandPulseSmoothingFullPixels
        ) * lensBandPulseSmoothingBlend
        return current + ((smoothed - current) * blend)
    }
    func pulseSmoothedDegreeRollResidual(_ values: [Float]) -> Float {
        let current = residual(values)
        let windowFrames = analysis.farFieldMeshDominantWindowFrames.indices.contains(index)
            ? max(3, Int(round(analysis.farFieldMeshDominantWindowFrames[index])))
            : max(3, Int(round(targetWindowSeconds / frameStep)))
        let radiusFrames = max(1, windowFrames / 2)
        let centerTime = analysis.frames[index].time
        let radiusSeconds = max(frameStep, Double(radiusFrames) * frameStep)
        var weightedResidual = Float(0.0)
        var totalWeight = Float(0.0)
        for sampleIndex in (index - radiusFrames)...(index + radiusFrames) {
            guard analysis.frames.indices.contains(sampleIndex), values.indices.contains(sampleIndex) else { continue }
            let distance = abs(analysis.frames[sampleIndex].time - centerTime)
            let normalizedDistance = clamp(Float(distance / radiusSeconds), min: 0.0, max: 1.0)
            let weight = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)
            weightedResidual += residualAt(values, index: sampleIndex) * weight
            totalWeight += weight
        }
        guard totalWeight > Float.ulpOfOne else { return current }
        let smoothed = weightedResidual / totalWeight
        let pulseMagnitude = abs(current - smoothed)
        let blend = confidenceRamp(
            pulseMagnitude,
            start: lensShakeRollStartDegrees,
            full: lensShakeRollFullDegrees
        ) * lensBandPulseSmoothingBlend
        return current + ((smoothed - current) * blend)
    }
    func shortWindowQuiverScore(_ values: [Float], rawResidualPixels: Float, limitedResidualPixels: Float, scale: Float) -> Float {
        guard values.count == analysis.frames.count else { return 0.0 }
        let windowFrames = analysis.farFieldMeshDominantWindowFrames.indices.contains(index)
            ? max(3, Int(round(analysis.farFieldMeshDominantWindowFrames[index])))
            : max(3, Int(round(targetWindowSeconds / frameStep)))
        let radiusFrames = max(1, min(windowFrames / 2, Int(round(1.0 / frameStep)) / 2))
        let centerTime = analysis.frames[index].time
        let radiusSeconds = min(0.5, max(frameStep, Double(radiusFrames) * frameStep))
        var samples: [Float] = []
        for sampleIndex in (index - radiusFrames)...(index + radiusFrames) {
            guard analysis.frames.indices.contains(sampleIndex), values.indices.contains(sampleIndex) else { continue }
            if abs(analysis.frames[sampleIndex].time - centerTime) > radiusSeconds + (frameStep * 0.5) {
                continue
            }
            samples.append(residualAt(values, index: sampleIndex) * scale)
        }
        guard samples.count >= 3 else { return 0.0 }
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
        let directQuiverEvidence = max(
            confidenceRamp(maxStep, start: 0.18, full: 0.85),
            max(
                confidenceRamp(maxJerk, start: 0.14, full: 0.62),
                confidenceRamp(flipRatio, start: 0.10, full: 0.34)
            )
        )
        return clamp(
            max(shortPulseEvidence * confidenceRamp(rawDivergence, start: 0.22, full: 1.60), directQuiverEvidence * 0.72)
                * confidenceRamp(Float(samples.count), start: 3.0, full: 9.0),
            min: 0.0,
            max: 1.0
        )
    }
    func farFieldRigidDeltaCoherenceSupport() -> Float {
        guard analysis.frames.count >= 3,
              analysis.lensBandTopPathX.count == analysis.frames.count,
              analysis.lensBandTopPathY.count == analysis.frames.count,
              analysis.lensBandRidgePathX.count == analysis.frames.count,
              analysis.lensBandRidgePathY.count == analysis.frames.count,
              analysis.lensBandMidPathX.count == analysis.frames.count,
              analysis.lensBandMidPathY.count == analysis.frames.count,
              analysis.lensBandTopConfidence.count == analysis.frames.count,
              analysis.lensBandRidgeConfidence.count == analysis.frames.count,
              analysis.lensBandMidConfidence.count == analysis.frames.count
        else {
            return 0.0
        }
        let fpsWindowLimit = max(3, Int(round(1.0 / max(frameStep, 1.0 / 240.0))))
        let preparedWindowFrames = analysis.farFieldMeshDominantWindowFrames.indices.contains(index)
            ? max(3, Int(round(analysis.farFieldMeshDominantWindowFrames[index])))
            : max(3, Int(round(targetWindowSeconds / frameStep)))
        let localDominantSupport = analysis.farFieldMeshDominantSupport.indices.contains(index)
            ? analysis.farFieldMeshDominantSupport[index]
            : 0.0
        let windowFrames = max(3, min(preparedWindowFrames, fpsWindowLimit))
        let radiusFrames = max(1, windowFrames / 2)
        let centerTime = analysis.frames[index].time
        let radiusSeconds = min(1.0, max(frameStep, Double(radiusFrames) * frameStep))
        var weightedSupport = Float(0.0)
        var totalWeight = Float(0.0)
        for sampleIndex in (index - radiusFrames)...(index + radiusFrames) {
            guard sampleIndex > 0,
                  analysis.frames.indices.contains(sampleIndex)
            else {
                continue
            }
            let distance = abs(analysis.frames[sampleIndex].time - centerTime)
            guard distance <= radiusSeconds + (frameStep * 0.5) else {
                continue
            }
            let topDeltaX = (analysis.lensBandTopPathX[sampleIndex] - analysis.lensBandTopPathX[sampleIndex - 1]) * xScale
            let topDeltaY = (analysis.lensBandTopPathY[sampleIndex] - analysis.lensBandTopPathY[sampleIndex - 1]) * yScale
            let ridgeDeltaX = (analysis.lensBandRidgePathX[sampleIndex] - analysis.lensBandRidgePathX[sampleIndex - 1]) * xScale
            let ridgeDeltaY = (analysis.lensBandRidgePathY[sampleIndex] - analysis.lensBandRidgePathY[sampleIndex - 1]) * yScale
            let midDeltaX = (analysis.lensBandMidPathX[sampleIndex] - analysis.lensBandMidPathX[sampleIndex - 1]) * xScale
            let midDeltaY = (analysis.lensBandMidPathY[sampleIndex] - analysis.lensBandMidPathY[sampleIndex - 1]) * yScale
            let farDeltaX = (topDeltaX * 0.35) + (ridgeDeltaX * 0.65)
            let farDeltaY = (topDeltaY * 0.35) + (ridgeDeltaY * 0.65)
            let topRidgeDisagreement = hypotf(topDeltaX - ridgeDeltaX, topDeltaY - ridgeDeltaY)
            let midDisagreement = hypotf(midDeltaX - farDeltaX, midDeltaY - farDeltaY)
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
            let rollDelta = analysis.farFieldRigidShakePathRoll.indices.contains(sampleIndex)
                && analysis.farFieldRigidShakePathRoll.indices.contains(sampleIndex - 1)
                ? abs(analysis.farFieldRigidShakePathRoll[sampleIndex] - analysis.farFieldRigidShakePathRoll[sampleIndex - 1])
                : 0.0
            let motionEvidence = max(
                confidenceRamp(
                    hypotf(farDeltaX, farDeltaY),
                    start: farFieldRigidDeltaCoherenceMotionStartPixels,
                    full: farFieldRigidDeltaCoherenceMotionFullPixels
                ),
                confidenceRamp(
                    rollDelta,
                    start: lensShakeRollStartDegrees * 0.5,
                    full: lensShakeRollFullDegrees
                )
            )
            let farConfidence = min(analysis.lensBandTopConfidence[sampleIndex], analysis.lensBandRidgeConfidence[sampleIndex])
            let confidenceGate = confidenceRamp(farConfidence, start: 0.08, full: 0.34)
            let midConfidenceGate = 0.65 + (0.35 * confidenceRamp(analysis.lensBandMidConfidence[sampleIndex], start: 0.06, full: 0.30))
            let support = clamp(
                topRidgeCoherence
                    * (1.0 - (midParallaxVeto * 0.45))
                    * motionEvidence
                    * confidenceGate
                    * midConfidenceGate
                    * confidenceRamp(localDominantSupport, start: 0.16, full: 0.66),
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
    let qualitySupport = confidenceRamp(appliedWarpConfidence, start: 0.16, full: 0.55)
        * confidenceRamp(trackingConfidence, start: 0.14, full: 0.42)
        * confidenceRamp(edgeQuality, start: 0.46, full: 0.82)
    let turnScale: Float = 1.0
    let dominantSupport = analysis.farFieldMeshDominantSupport.indices.contains(index)
        ? analysis.farFieldMeshDominantSupport[index]
        : 0.0
    let lowFrequencyWindowSupport = confidenceRamp(
        Float(targetWindowSeconds),
        start: farFieldLowFrequencyPriorityStartSeconds,
        full: farFieldLowFrequencyPriorityFullSeconds
    )
    let lowFrequencySupport = lowFrequencyWindowSupport
        * confidenceRamp(dominantSupport, start: 0.18, full: 0.72)
        * qualitySupport
    let lowFrequencyTurnScale = 1.0 - ((1.0 - turnScale) * (1.0 - farFieldLowFrequencyTurnSuppressionRelief))
    func support(_ magnitude: Float, start: Float, full: Float) -> Float {
        clamp(confidenceRamp(magnitude, start: start, full: full) * qualitySupport * turnScale, min: 0.0, max: 1.0)
    }

    let residualX = residual(analysis.farFieldPathX) * xScale
    let residualY = residual(analysis.farFieldPathY) * yScale
    let residualRoll = residual(analysis.farFieldPathRoll)
    let yaw = residual(analysis.pathYaw)
    let pitch = residual(analysis.pathPitch)
    let shearX = residual(analysis.pathShearX)
    let shearY = residual(analysis.pathShearY)
    let perspectiveX = residual(analysis.pathPerspectiveX)
    let perspectiveY = residual(analysis.pathPerspectiveY)
    let pixelSupport = max(
        support(abs(residualX), start: lensShakePixelStartPixels, full: lensShakePixelFullPixels),
        support(abs(residualY), start: lensShakePixelStartPixels, full: lensShakePixelFullPixels)
    )
    let rollSupport = support(abs(residualRoll), start: lensShakeRollStartDegrees, full: lensShakeRollFullDegrees)
    let yawPitchSupport = max(
        support(abs(yaw), start: lensShakeYawPitchStart, full: lensShakeYawPitchFull),
        support(abs(pitch), start: lensShakeYawPitchStart, full: lensShakeYawPitchFull)
    )
    let shearSupport = max(
        support(abs(shearX), start: lensShakeShearStart, full: lensShakeShearFull),
        support(abs(shearY), start: lensShakeShearStart, full: lensShakeShearFull)
    )
    let perspectiveSupport = max(
        support(abs(perspectiveX), start: lensShakePerspectiveStart, full: lensShakePerspectiveFull),
        support(abs(perspectiveY), start: lensShakePerspectiveStart, full: lensShakePerspectiveFull)
    )
    let affineSupport = max(pixelSupport, rollSupport)
    let projectiveSupport = max(yawPitchSupport, max(shearSupport, perspectiveSupport))
    let dominantProjectiveCandidate = confidenceRamp(projectiveSupport - affineSupport, start: 0.18, full: 0.55)
    let mixedProjectiveCandidate = min(
        confidenceRamp(projectiveSupport, start: 0.35, full: 0.70),
        confidenceRamp(affineSupport, start: 0.20, full: 0.55)
    ) * 0.75
    let rollingShutterCandidate = max(dominantProjectiveCandidate, mixedProjectiveCandidate)
    let rollingShutterSuppression = 1.0 - (confidenceRamp(rollingShutterCandidate, start: 0.62, full: 0.88) * 0.55)
    let lensSupport = max(pixelSupport, rollSupport)

    let hasFarFieldRigidShakePaths = analysis.farFieldRigidShakePathX.count == analysis.frames.count
        && analysis.farFieldRigidShakePathY.count == analysis.frames.count
        && analysis.farFieldRigidShakePathRoll.count == analysis.frames.count
        && analysis.cameraRigidTargetX.count == analysis.frames.count
        && analysis.cameraRigidTargetY.count == analysis.frames.count
        && analysis.cameraRigidTargetRollDegrees.count == analysis.frames.count
        && analysis.farFieldRigidShakeSupport.count == analysis.frames.count
        && analysis.farFieldRigidShakeSupportX.count == analysis.frames.count
        && analysis.farFieldRigidShakeSupportY.count == analysis.frames.count
        && analysis.farFieldRigidShakeRollSupport.count == analysis.frames.count
        && analysis.farFieldRigidShakeShapeConsistency.count == analysis.frames.count
        && analysis.farFieldRigidShakeShapeConsistencyX.count == analysis.frames.count
        && analysis.farFieldRigidShakeShapeConsistencyY.count == analysis.frames.count
        && analysis.farFieldRigidShakeForwardBackwardConsistency.count == analysis.frames.count
        && analysis.farFieldRigidShakeForwardBackwardConsistencyX.count == analysis.frames.count
        && analysis.farFieldRigidShakeForwardBackwardConsistencyY.count == analysis.frames.count
        && analysis.farFieldRigidShakeRollForwardBackwardConsistency.count == analysis.frames.count
    if hasFarFieldRigidShakePaths {
        let rawRigidResidualX = analysis.cameraRigidTargetX[index] * xScale
        let rawRigidResidualY = analysis.cameraRigidTargetY[index] * yScale
        let rawRigidRollResidual = analysis.cameraRigidTargetRollDegrees[index]
        var rigidResidualX = rawRigidResidualX
        var rigidResidualY = rawRigidResidualY
        var rigidRollResidual = rawRigidRollResidual
        let rawRigidMagnitude = hypotf(rawRigidResidualX, rawRigidResidualY)
        let preparedRigidSupport = analysis.farFieldRigidShakeSupport[index]
        let preparedRigidSupportX = analysis.farFieldRigidShakeSupportX[index]
        let preparedRigidSupportY = analysis.farFieldRigidShakeSupportY[index]
        let preparedRigidRollSupport = analysis.farFieldRigidShakeRollSupport[index]
        let shapeConsistency = analysis.farFieldRigidShakeShapeConsistency[index]
        let shapeConsistencyX = analysis.farFieldRigidShakeShapeConsistencyX[index]
        let shapeConsistencyY = analysis.farFieldRigidShakeShapeConsistencyY[index]
        let forwardBackwardConsistency = analysis.farFieldRigidShakeForwardBackwardConsistency[index]
        let forwardBackwardConsistencyX = analysis.farFieldRigidShakeForwardBackwardConsistencyX[index]
        let forwardBackwardConsistencyY = analysis.farFieldRigidShakeForwardBackwardConsistencyY[index]
        let rollForwardBackwardConsistency = analysis.farFieldRigidShakeRollForwardBackwardConsistency[index]
        let deltaCoherenceSupport = Float(0.0)
        let deltaCoherenceAuthority = Float(0.0)
        let effectivePreparedRigidSupport = preparedRigidSupport
        let effectivePreparedRigidSupportX = preparedRigidSupportX
        let effectivePreparedRigidSupportY = preparedRigidSupportY
        let effectivePreparedRigidRollSupport = preparedRigidRollSupport
        let effectiveShapeConsistency = shapeConsistency
        let effectiveShapeConsistencyX = shapeConsistencyX
        let effectiveShapeConsistencyY = shapeConsistencyY
        let effectiveForwardBackwardConsistency = forwardBackwardConsistency
        let effectiveForwardBackwardConsistencyX = forwardBackwardConsistencyX
        let effectiveForwardBackwardConsistencyY = forwardBackwardConsistencyY
        let lowFrequencyRigidPriority = lowFrequencySupport
            * confidenceRamp(rawRigidMagnitude, start: 0.08, full: 0.66)
            * confidenceRamp(max(effectivePreparedRigidSupport, dominantSupport), start: 0.10, full: 0.56)
            * confidenceRamp(effectiveShapeConsistency, start: 0.28, full: 0.70)
            * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.24, full: 0.68)
            * lowFrequencyTurnScale
            * rollingShutterSuppression
        let lowFrequencyDominance = clamp(
            lowFrequencyRigidPriority
                * confidenceRamp(Float(targetWindowSeconds), start: 0.42, full: farFieldLowFrequencyPriorityFullSeconds)
                * confidenceRamp(rawRigidMagnitude, start: 0.12, full: 0.90),
            min: 0.0,
            max: 1.0
        )
        var meshBlend = Float(0.0)
        var meshSupport = Float(0.0)
        var meshMaxBinDelta = Float(0.0)
        var meshOpposingBins = Float(0.0)
        var meshSupportedBinCount = 0
        var dominantMeshResidualY = Float(0.0)
        var dominantMeshSupport = Float(0.0)
        let hasFarFieldMeshPaths = analysis.farFieldMeshRows == expectedFarFieldMeshRows
            && analysis.farFieldMeshColumns == expectedFarFieldMeshColumns
            && analysis.farFieldMeshPathX.count == analysis.frames.count * expectedFarFieldMeshBinCount
            && analysis.farFieldMeshPathY.count == analysis.frames.count * expectedFarFieldMeshBinCount
            && analysis.farFieldMeshSupport.count == analysis.frames.count * expectedFarFieldMeshBinCount
        if hasFarFieldMeshPaths {
            var meshResidualX = Float(0.0)
            var meshResidualY = Float(0.0)
            var meshWeight = Float(0.0)
            var meshMaxSupport = Float(0.0)
            var meshSupportSum = Float(0.0)
            var meshSupportedResiduals: [(x: Float, y: Float, support: Float)] = []
            for bin in 0..<expectedFarFieldMeshBinCount {
                let start = bin * analysis.frames.count
                let end = start + analysis.frames.count
                guard analysis.farFieldMeshPathX.indices.contains(start),
                      analysis.farFieldMeshPathX.indices.contains(end - 1),
                      analysis.farFieldMeshPathY.indices.contains(start),
                      analysis.farFieldMeshPathY.indices.contains(end - 1),
                      analysis.farFieldMeshSupport.indices.contains(start + index)
                else {
                    continue
                }
                let pathX = Array(analysis.farFieldMeshPathX[start..<end])
                let pathY = Array(analysis.farFieldMeshPathY[start..<end])
                let residualX = pulseSmoothedPixelResidual(pathX, scale: xScale)
                let residualY = pulseSmoothedPixelResidual(pathY, scale: yScale)
                let preparedSupport = analysis.farFieldMeshSupport[start + index]
                let support = confidenceRamp(hypotf(residualX, residualY), start: 0.08, full: 0.70)
                    * confidenceRamp(preparedSupport, start: 0.08, full: 0.38)
                    * qualitySupport
                    * turnScale
                if bin == dominantCell {
                    dominantMeshResidualY = residualY
                    dominantMeshSupport = support
                }
                let weight = max(0.0, support)
                meshResidualX += residualX * weight
                meshResidualY += residualY * weight
                meshWeight += weight
                if support > 0.01 {
                    meshMaxSupport = max(meshMaxSupport, support)
                    meshSupportSum += support
                    meshSupportedBinCount += 1
                    meshSupportedResiduals.append((x: residualX, y: residualY, support: support))
                }
            }
            if meshWeight > Float.ulpOfOne {
                meshResidualX /= meshWeight
                meshResidualY /= meshWeight
                for residual in meshSupportedResiduals {
                    let deltaX = residual.x - meshResidualX
                    let deltaY = residual.y - meshResidualY
                    meshMaxBinDelta = max(meshMaxBinDelta, hypotf(deltaX, deltaY))
                    if (residual.x * meshResidualX) + (residual.y * meshResidualY) < -0.01 {
                        meshOpposingBins += 1.0
                    }
                }
                if meshSupportedBinCount > 0 {
                    let averageSupport = meshSupportSum / Float(meshSupportedBinCount)
                    let coverageSupport = confidenceRamp(Float(meshSupportedBinCount), start: 4.0, full: 12.0)
                    meshSupport = min(meshMaxSupport, averageSupport * coverageSupport)
                }
                let lowFrequencyMeshSuppression = clamp(
                    lowFrequencyDominance * farFieldLowFrequencyMeshSuppressionScale,
                    min: 0.0,
                    max: 1.0
                )
                let meshOpposingFraction = meshSupportedBinCount > 0
                    ? meshOpposingBins / Float(meshSupportedBinCount)
                    : 1.0
                let meshCoherenceVeto = max(
                    confidenceRamp(
                        meshMaxBinDelta,
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
                let rawMeshBlend = min(meshBlendCeiling, meshSupport * 0.45 * (1.0 - lowFrequencyMeshSuppression))
                meshBlend = rawMeshBlend * meshBlendAuthority
                let meshYBlend = min(meshBlend, meshSupport * farFieldCoherentSlabMeshYBlendMaximum * (1.0 - lowFrequencyMeshSuppression))
                rigidResidualX += (meshResidualX - rigidResidualX) * meshBlend
                rigidResidualY += (meshResidualY - rigidResidualY) * meshYBlend
            }
        }
        let smoothedRigidMagnitude = hypotf(rigidResidualX, rigidResidualY)
        var rawReinforcementBlend = Float(0.0)
        let xQuiverScore = shortWindowQuiverScore(
            analysis.farFieldRigidShakePathX,
            rawResidualPixels: rawRigidResidualX,
            limitedResidualPixels: rigidResidualX,
            scale: xScale
        )
        let yQuiverScore = shortWindowQuiverScore(
            analysis.farFieldRigidShakePathY,
            rawResidualPixels: rawRigidResidualY,
            limitedResidualPixels: rigidResidualY,
            scale: yScale
        )
        let xBeforeLimiter = rigidResidualX
        var xBeforeQuiverLimiter = rigidResidualX
        var yBeforeQuiverLimiter = rigidResidualY
        if rawRigidMagnitude > smoothedRigidMagnitude,
           (rawRigidResidualX * rigidResidualX) + (rawRigidResidualY * rigidResidualY) > 0.0 {
            let rawReinforcement = confidenceRamp(
                rawRigidMagnitude - smoothedRigidMagnitude,
                start: 0.18,
                full: 1.15
            ) * confidenceRamp(
                max(dominantSupport, meshSupport),
                start: 0.45,
                full: 0.85
            ) * rollingShutterSuppression
            let lowFrequencyRawReinforcement = max(
                lowFrequencyRigidPriority * confidenceRamp(rawRigidMagnitude - smoothedRigidMagnitude, start: 0.04, full: 0.42),
                lowFrequencyDominance * confidenceRamp(rawRigidMagnitude, start: 0.12, full: 0.90)
            )
            let rawBlendCeiling = farFieldRigidRawReinforcementMaximumBlend
                + ((farFieldLowFrequencyRawReinforcementMaximumBlend - farFieldRigidRawReinforcementMaximumBlend) * lowFrequencyDominance)
            rawReinforcementBlend = min(
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
            let xBlend = rawReinforcementBlend * (1.0 - xQuiverSuppression)
            let yBlend = rawReinforcementBlend * (1.0 - yQuiverSuppression)
            xBeforeQuiverLimiter = xBeforeLimiter + ((rawRigidResidualX - xBeforeLimiter) * rawReinforcementBlend)
            yBeforeQuiverLimiter = rigidResidualY + ((rawRigidResidualY - rigidResidualY) * rawReinforcementBlend)
            rigidResidualX += (rawRigidResidualX - rigidResidualX) * xBlend
            rigidResidualY += (rawRigidResidualY - rigidResidualY) * yBlend
        }
        let dominantCellInUpperFarField = dominantCell >= 0
            && dominantCell < expectedFarFieldMeshBinCount
            && (dominantCell / expectedFarFieldMeshColumns) <= 1
        let shortWindowDominantMeshYPriority = (
            1.0 - confidenceRamp(
                Float(targetWindowSeconds),
                start: farFieldShortWindowRigidYBoostFullSeconds,
                full: farFieldShortWindowRigidYBoostStartSeconds
            )
        )
            * (dominantCellInUpperFarField ? 1.0 : 0.0)
            * confidenceRamp(dominantSupport, start: 0.52, full: 0.88)
            * confidenceRamp(dominantMeshSupport, start: 0.22, full: 0.62)
            * (dominantMeshResidualY * rigidResidualY > 0.0 ? 1.0 : 0.0)
            * confidenceRamp(abs(dominantMeshResidualY), start: 0.10, full: 0.95)
            * qualitySupport
            * (1.0 - (confidenceRamp(rollingShutterCandidate, start: 0.62, full: 0.88) * 0.50))
        let dominantMeshYBlend = min(
            farFieldShortWindowDominantMeshYBlendMaximum,
            farFieldShortWindowDominantMeshYBlendMaximum * clamp(shortWindowDominantMeshYPriority, min: 0.0, max: 1.0)
        )
        if dominantMeshYBlend > 0.0 {
            rigidResidualY += (dominantMeshResidualY - rigidResidualY) * dominantMeshYBlend
        }
        let shortWindowRigidYPriority = (
            1.0 - confidenceRamp(
                Float(targetWindowSeconds),
                start: farFieldShortWindowRigidYBoostFullSeconds,
                full: farFieldShortWindowRigidYBoostStartSeconds
            )
        )
            * confidenceRamp(max(dominantSupport, meshSupport), start: 0.52, full: 0.88)
            * (1.0 - (confidenceRamp(meshMaxBinDelta, start: 12.0, full: 32.0) * 0.65))
            * (1.0 - confidenceRamp(meshSupportedBinCount > 0 ? meshOpposingBins / Float(meshSupportedBinCount) : 1.0, start: 0.08, full: 0.32))
            * (1.0 - (confidenceRamp(yQuiverScore, start: 0.18, full: 0.60) * 0.90))
            * confidenceRamp(abs(rigidResidualY), start: 0.10, full: 0.95)
            * qualitySupport
            * (1.0 - (confidenceRamp(rollingShutterCandidate, start: 0.62, full: 0.88) * 0.50))
        let shortWindowRigidYBoost = farFieldShortWindowRigidYBoostMaximum
            * clamp(shortWindowRigidYPriority, min: 0.0, max: 1.0)
        if shortWindowRigidYBoost > 0.0 {
            rigidResidualY *= 1.0 + shortWindowRigidYBoost
        }
        let meshOpposingFraction = meshSupportedBinCount > 0
            ? meshOpposingBins / Float(meshSupportedBinCount)
            : 0.0
        let parallaxDampingEvidence = confidenceRamp(
            meshMaxBinDelta,
            start: farFieldParallaxWarpDampingDeltaStart,
            full: farFieldParallaxWarpDampingDeltaFull
        )
            * confidenceRamp(Float(meshSupportedBinCount), start: 8.0, full: 16.0)
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
            * (1.0 - (confidenceRamp(rollingShutterCandidate, start: 0.62, full: 0.88) * 0.35))
        let parallaxWarpDamping = farFieldParallaxWarpDampingMaximum
            * clamp(parallaxDampingEvidence, min: 0.0, max: 1.0)
        if parallaxWarpDamping > 0.0 {
            rigidResidualX *= 1.0 - parallaxWarpDamping
            rigidResidualY *= 1.0 - parallaxWarpDamping
        }
        let coherentXMeshVeto = confidenceRamp(
            meshMaxBinDelta,
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
        let frameLocalPreparedAuthorityX = confidenceRamp(
            effectivePreparedRigidSupportX,
            start: 0.12,
            full: 0.62
        )
        let coherentSlabXAuthority = clamp(
            max(frameLocalPreparedAuthorityX, lowFrequencyXAuthority),
            min: 0.0,
            max: 1.0
        )
        if coherentSlabXAuthority < 0.995 {
            rigidResidualX *= coherentSlabXAuthority
        }
        let coherentYMeshVeto = confidenceRamp(
            meshMaxBinDelta,
            start: farFieldCoherentSlabYMeshDeltaStart,
            full: farFieldCoherentSlabYMeshDeltaFull
        )
        let lowFrequencyYAuthority = lowFrequencyRigidPriority
            * confidenceRamp(effectiveForwardBackwardConsistency, start: 0.08, full: 0.42)
            * (1.0 - (coherentYMeshVeto * 0.55))
        let frameLocalPreparedAuthorityY = confidenceRamp(
            effectivePreparedRigidSupportY,
            start: 0.12,
            full: 0.62
        )
        let coherentSlabYAuthority = clamp(
            max(frameLocalPreparedAuthorityY, lowFrequencyYAuthority),
            min: 0.0,
            max: 1.0
        )
        if coherentSlabYAuthority < 0.995 {
            rigidResidualY *= coherentSlabYAuthority
        }
        let frameLocalRollAuthority = confidenceRamp(effectivePreparedRigidRollSupport, start: 0.42, full: 0.78)
            * confidenceRamp(rollForwardBackwardConsistency, start: 0.48, full: 0.84)
        rigidRollResidual += (rawRigidRollResidual - rigidRollResidual) * frameLocalRollAuthority
        let rigidMagnitude = hypotf(rigidResidualX, rigidResidualY)
        let lowFrequencyRigidSupport = lowFrequencyRigidPriority
            * confidenceRamp(rigidMagnitude, start: 0.05, full: 0.48)
        let rigidSupportX = max(
            confidenceRamp(abs(rigidResidualX), start: 0.08, full: 0.70)
                * confidenceRamp(effectivePreparedRigidSupportX, start: 0.08, full: 0.56)
                * qualitySupport,
            meshSupport * confidenceRamp(abs(rigidResidualX), start: 0.08, full: 0.70)
        )
        let rigidSupportY = max(
            confidenceRamp(abs(rigidResidualY), start: 0.08, full: 0.70)
                * confidenceRamp(effectivePreparedRigidSupportY, start: 0.08, full: 0.56)
                * qualitySupport,
            max(
                meshSupport * confidenceRamp(abs(rigidResidualY), start: 0.08, full: 0.70),
                lowFrequencyRigidSupport
            )
        )
        let rigidSupport = max(rigidSupportX, rigidSupportY)
        let rigidRollSupport = confidenceRamp(abs(rigidRollResidual), start: lensShakeRollStartDegrees, full: lensShakeRollFullDegrees)
            * confidenceRamp(effectivePreparedRigidRollSupport, start: 0.08, full: 0.36)
            * confidenceRamp(rollForwardBackwardConsistency, start: 0.20, full: 0.72)
            * qualitySupport
        let boundedSupport = clamp(max(max(rigidSupport, rigidRollSupport), max(meshSupport * confidenceRamp(rigidMagnitude, start: 0.08, full: 0.70), lowFrequencyRigidSupport)), min: 0.0, max: 1.0)
        let rigidOnlyEvidence = clamp(
            confidenceRamp(boundedSupport, start: farFieldRigidOnlyGuardSupportStart, full: farFieldRigidOnlyGuardSupportFull)
                * confidenceRamp(effectiveShapeConsistency, start: farFieldRigidOnlyGuardShapeStart, full: farFieldRigidOnlyGuardShapeFull)
                * confidenceRamp(effectiveForwardBackwardConsistency, start: farFieldRigidOnlyGuardTwoWayStart, full: farFieldRigidOnlyGuardTwoWayFull)
                * (1.0 - (confidenceRamp(rollingShutterCandidate, start: 0.45, full: 0.75) * 0.65)),
            min: 0.0,
            max: 1.0
        )
        let rigidOnlyGuard = rigidOnlyEvidence >= 0.34
            ? max(rigidOnlyEvidence, confidenceRamp(rigidOnlyEvidence, start: 0.34, full: 0.58))
            : rigidOnlyEvidence
        let xConfidence = rigidSupportX
        let yConfidence = rigidSupportY
        let xStrength = walkingCorrectionFactor(cameraStrengthX, confidence: xConfidence)
        let yStrength = verticalWalkingCorrectionFactor(cameraStrengthY, confidence: yConfidence)
        let rotationStrength = walkingCorrectionFactor(cameraStrengthR, confidence: rigidRollSupport)
        let detected = abs(rigidResidualX) + abs(rigidResidualY) + (abs(rigidRollResidual) * 12.0)
        let rigidXLimit = analysis.sampleWidth > 0 ? Float(analysis.sampleWidth) * xScale * Float(min(max(cameraLimitXPercent, 0.0), 5.0) / 100.0) : 0.0
        let rigidYLimit = analysis.sampleHeight > 0 ? Float(analysis.sampleHeight) * yScale * Float(min(max(cameraLimitYPercent, 0.0), 5.0) / 100.0) : 0.0
        let rigidRollLimit = Float(min(max(cameraLimitRotationDegrees, 0.0), 2.0))
        let appliedRigidX = min(abs(rigidResidualX * xStrength), rigidXLimit)
        let appliedRigidY = min(abs(rigidResidualY * yStrength), rigidYLimit)
        let appliedRigidRoll = min(abs(rigidRollResidual * rotationStrength), rigidRollLimit)
        let applied = appliedRigidX + appliedRigidY + (appliedRigidRoll * 12.0)
        let reason = boundedSupport >= lensShakeMinimumSupport ? "farFieldRigid" : "farFieldRigidSuppressed"
        return BandAssessment(
            name: "LENS",
            detected: detected,
            applied: applied,
            remaining: max(0.0, detected - applied),
            confidence: boundedSupport,
            note: String(format: "source-space %.3fs farFieldRigid residual %.3f %.3f roll %.5f cap %.3f %.3f %.3f applied %.3f %.3f %.3f raw %.3f %.3f rawRoll %.5f support %.2f supportX %.2f supportY %.2f rollSupport %.2f prepared %.2f rollPrepared %.2f shapeX %.2f shapeY %.2f twoWayX %.2f twoWayY %.2f rollTwoWay %.2f deltaRigid %.2f deltaAuthority %.2f dominantSupport %.2f lowFreqPriority %.2f lowFreqDominance %.2f dominantMeshYBlend %.2f shortYBoost %.2f parallaxDamp %.2f coherentX %.2f coherentY %.2f rolling %.2f meshSupport %.2f meshBlend %.2f meshMaxDelta %.2f meshOpposing %.0f rawReinforceBlend %.2f xQuiver %.2f yQuiver %.2f xBeforeLimiter %.3f xAfterLimiter %.3f yBeforeLimiter %.3f yAfterLimiter %.3f localWarpSuppressed %.2f reason %@", targetWindowSeconds, rigidResidualX, rigidResidualY, rigidRollResidual, rigidXLimit, rigidYLimit, rigidRollLimit, appliedRigidX, appliedRigidY, appliedRigidRoll, rawRigidResidualX, rawRigidResidualY, rawRigidRollResidual, boundedSupport, rigidSupportX, rigidSupportY, rigidRollSupport, preparedRigidSupport, preparedRigidRollSupport, effectiveShapeConsistencyX, effectiveShapeConsistencyY, effectiveForwardBackwardConsistencyX, effectiveForwardBackwardConsistencyY, rollForwardBackwardConsistency, deltaCoherenceSupport, deltaCoherenceAuthority, dominantSupport, lowFrequencyRigidPriority, lowFrequencyDominance, dominantMeshYBlend, shortWindowRigidYBoost, parallaxWarpDamping, coherentSlabXAuthority, coherentSlabYAuthority, rollingShutterCandidate, meshSupport, meshBlend, meshMaxBinDelta, meshOpposingBins, rawReinforcementBlend, xQuiverScore, yQuiverScore, xBeforeQuiverLimiter, rigidResidualX, yBeforeQuiverLimiter, rigidResidualY, rigidOnlyGuard, reason)
        )
    }

    let topResidual = (
        x: residual(analysis.lensBandTopPathX) * xScale,
        y: residual(analysis.lensBandTopPathY) * yScale
    )
    let ridgeResidual = (
        x: residual(analysis.lensBandRidgePathX) * xScale,
        y: residual(analysis.lensBandRidgePathY) * yScale
    )
    let midResidual = (
        x: residual(analysis.lensBandMidPathX) * xScale,
        y: residual(analysis.lensBandMidPathY) * yScale
    )
    let topColumnResidual = (
        x: residual(analysis.lensBandTopColumnPathX) * xScale,
        y: residual(analysis.lensBandTopColumnPathY) * yScale
    )
    let topRowResidual = (
        x: residual(analysis.lensBandTopRowPhasePathX) * xScale,
        y: residual(analysis.lensBandTopRowPhasePathY) * yScale
    )
    let topLocalRoll = residual(analysis.lensBandTopLocalRollPath)
    let ridgeColumnResidual = (
        x: residual(analysis.lensBandRidgeColumnPathX) * xScale,
        y: residual(analysis.lensBandRidgeColumnPathY) * yScale
    )
    let ridgeRowResidual = (
        x: residual(analysis.lensBandRidgeRowPhasePathX) * xScale,
        y: residual(analysis.lensBandRidgeRowPhasePathY) * yScale
    )
    let ridgeLocalRoll = residual(analysis.lensBandRidgeLocalRollPath)
    let sourceRidgeResidualY = residual(analysis.sourceLensShakeRidgePathY) * yScale
    let sourceRidgeLineResidualY = residual(analysis.sourceLensShakeRidgeLinePathY) * yScale
    let midColumnResidual = (
        x: residual(analysis.lensBandMidColumnPathX) * xScale,
        y: residual(analysis.lensBandMidColumnPathY) * yScale
    )
    let midRowResidual = (
        x: residual(analysis.lensBandMidRowPhasePathX) * xScale,
        y: residual(analysis.lensBandMidRowPhasePathY) * yScale
    )
    let midLocalRoll = residual(analysis.lensBandMidLocalRollPath)
    let bandMagnitude = max(
        hypotf(topResidual.x, topResidual.y),
        max(hypotf(ridgeResidual.x, ridgeResidual.y), hypotf(midResidual.x, midResidual.y))
    )
    let columnMagnitude = max(
        hypotf(topColumnResidual.x, topColumnResidual.y),
        max(hypotf(ridgeColumnResidual.x, ridgeColumnResidual.y), hypotf(midColumnResidual.x, midColumnResidual.y))
    )
    let rowMagnitude = max(
        hypotf(topRowResidual.x, topRowResidual.y),
        max(hypotf(ridgeRowResidual.x, ridgeRowResidual.y), hypotf(midRowResidual.x, midRowResidual.y))
    )
    let localRollMagnitude = max(abs(topLocalRoll), max(abs(ridgeLocalRoll), abs(midLocalRoll)))
    let bandDisagreement = max(
        hypotf(topResidual.x - ridgeResidual.x, topResidual.y - ridgeResidual.y),
        max(
            hypotf(topResidual.x - midResidual.x, topResidual.y - midResidual.y),
            hypotf(ridgeResidual.x - midResidual.x, ridgeResidual.y - midResidual.y)
        )
    )
    let columnDisagreement = max(
        hypotf(topColumnResidual.x - ridgeColumnResidual.x, topColumnResidual.y - ridgeColumnResidual.y),
        max(
            hypotf(topColumnResidual.x - midColumnResidual.x, topColumnResidual.y - midColumnResidual.y),
            hypotf(ridgeColumnResidual.x - midColumnResidual.x, ridgeColumnResidual.y - midColumnResidual.y)
        )
    )
    func bandConfidence(_ values: [Float]) -> Float {
        values.indices.contains(index) ? values[index] : 0.0
    }
    let topConfidence = bandConfidence(analysis.lensBandTopConfidence)
    let ridgeConfidence = bandConfidence(analysis.lensBandRidgeConfidence)
    let midConfidence = bandConfidence(analysis.lensBandMidConfidence)
    let sourceRidgePreparedSupport = bandConfidence(analysis.sourceLensShakeRidgeSupport)
    let sourceRidgeLinePreparedSupport = bandConfidence(analysis.sourceLensShakeRidgeLineSupport)
    func bandSupport(residual: (x: Float, y: Float), confidence: Float) -> Float {
        confidenceRamp(hypotf(residual.x, residual.y), start: 0.08, full: 0.65)
            * confidenceRamp(confidence, start: 0.08, full: 0.36)
            * qualitySupport
            * turnScale
    }
    let topSupport = bandSupport(residual: topResidual, confidence: topConfidence)
    let ridgeSupport = bandSupport(residual: ridgeResidual, confidence: ridgeConfidence)
    let midSupport = bandSupport(residual: midResidual, confidence: midConfidence)
    let topColumnSupport = bandSupport(residual: topColumnResidual, confidence: topConfidence)
    let ridgeColumnSupport = bandSupport(residual: ridgeColumnResidual, confidence: ridgeConfidence)
    let midColumnSupport = bandSupport(residual: midColumnResidual, confidence: midConfidence)
    let topRowSupport = bandSupport(residual: topRowResidual, confidence: topConfidence)
    let ridgeRowSupport = bandSupport(residual: ridgeRowResidual, confidence: ridgeConfidence)
    let midRowSupport = bandSupport(residual: midRowResidual, confidence: midConfidence)
    let maxBandConfidence = max(topConfidence, max(ridgeConfidence, midConfidence))
    let sourceRidgeSupport = confidenceRamp(abs(sourceRidgeResidualY), start: 0.18, full: 1.25)
        * confidenceRamp(sourceRidgePreparedSupport, start: 0.08, full: 0.45)
        * qualitySupport
        * turnScale
    let sourceRidgeLineDirectSupport = confidenceRamp(abs(sourceRidgeLineResidualY), start: 0.14, full: 1.10)
        * confidenceRamp(sourceRidgeLinePreparedSupport, start: 0.08, full: 0.45)
        * qualitySupport
        * turnScale
    func localLensShakePathSlice(_ values: [Float], bin: Int) -> [Float] {
        guard bin >= 0, bin < analysis.sourceLensShakeLocalBinCount else {
            return []
        }
        let start = bin * analysis.frames.count
        let end = start + analysis.frames.count
        guard start >= 0, end <= values.count else {
            return []
        }
        return Array(values[start..<end])
    }
    var sourceLocalMagnitude: Float = 0.0
    var sourceLocalSupport: Float = 0.0
    for bin in 0..<analysis.sourceLensShakeLocalBinCount {
        let localX = localLensShakePathSlice(analysis.sourceLensShakeLocalPathX, bin: bin)
        let localY = localLensShakePathSlice(analysis.sourceLensShakeLocalPathY, bin: bin)
        let localSupportPath = localLensShakePathSlice(analysis.sourceLensShakeLocalSupport, bin: bin)
        let localResidual = (
            x: residual(localX) * xScale,
            y: residual(localY) * yScale
        )
        let localMagnitude = hypotf(localResidual.x, localResidual.y)
        let localPreparedSupport = bandConfidence(localSupportPath)
        let localSupport = confidenceRamp(localMagnitude, start: 0.10, full: 0.95)
            * confidenceRamp(localPreparedSupport, start: 0.08, full: 0.38)
            * qualitySupport
            * turnScale
        sourceLocalMagnitude = max(sourceLocalMagnitude, localMagnitude)
        sourceLocalSupport = max(sourceLocalSupport, localSupport)
    }
    let sourceRidgeLineBandEvidenceSupport = max(ridgeSupport, max(ridgeColumnSupport, ridgeRowSupport))
    let sourceRidgeLineBandSupport = confidenceRamp(abs(sourceRidgeLineResidualY), start: 0.14, full: 1.10)
        * confidenceRamp(sourceRidgeLineBandEvidenceSupport, start: 0.08, full: 0.36)
        * qualitySupport
        * turnScale
    let sourceRidgeLineSupport = max(sourceRidgeLineDirectSupport, sourceRidgeLineBandSupport)
    let bandSupport = max(
        max(max(topSupport, max(ridgeSupport, midSupport)), max(topRowSupport, max(ridgeRowSupport, midRowSupport))),
        max(max(topColumnSupport, max(ridgeColumnSupport, midColumnSupport)), max(max(max(sourceRidgeSupport, sourceRidgeLineSupport), sourceLocalSupport), support(localRollMagnitude, start: lensShakeRollStartDegrees * 0.25, full: lensShakeRollFullDegrees * 0.75)))
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
    let localRollSupport = support(localRollMagnitude, start: lensShakeRollStartDegrees * 0.25, full: lensShakeRollFullDegrees * 0.75)
    var correctionModels: [String] = []
    if bandSupport >= lensShakeMinimumSupport && rowPhaseSupport >= lensShakeMinimumSupport {
        correctionModels.append("rowPhase")
    }
    if bandSupport >= lensShakeMinimumSupport && bandDisagreementSupport >= lensShakeMinimumSupport {
        correctionModels.append("regionCluster")
    }
    if bandSupport >= lensShakeMinimumSupport && columnPhaseSupport >= lensShakeMinimumSupport {
        correctionModels.append("columnPhase")
    }
    if bandSupport >= lensShakeMinimumSupport && localRollSupport >= lensShakeMinimumSupport {
        correctionModels.append("localRoll")
    }
    if bandSupport >= lensShakeMinimumSupport && sourceRidgeSupport >= lensShakeMinimumSupport {
        correctionModels.append("sourceRidge")
    }
    if bandSupport >= lensShakeMinimumSupport && sourceRidgeLineSupport >= lensShakeMinimumSupport {
        correctionModels.append("sourceRidgeLine")
    }
    if bandSupport >= lensShakeMinimumSupport && sourceLocalSupport >= lensShakeMinimumSupport {
        correctionModels.append("sourceLocal")
    }
    let correctionModel = correctionModels.isEmpty ? "none" : correctionModels.joined(separator: ",")
    let detected = hypotf(residualX, residualY)
        + (abs(residualRoll) * 12.0)
    let diagnosticDetected = detected
        + (hypotf(yaw, pitch) * 1000.0)
        + (hypotf(shearX, shearY) * 900.0)
        + (hypotf(perspectiveX, perspectiveY) * 900.0)
        + bandMagnitude
        + columnMagnitude
        + sourceLocalMagnitude
        + abs(sourceRidgeResidualY)
        + abs(sourceRidgeLineResidualY)
    let appliesBand = bandSupport >= lensShakeMinimumSupport
    let appliesGlobal = !appliesBand && lensSupport >= lensShakeMinimumSupport && rollingShutterCandidate < 0.45
    let bandAppliedMagnitude = max(max(max(bandMagnitude, columnMagnitude), sourceLocalMagnitude), max(abs(sourceRidgeResidualY), abs(sourceRidgeLineResidualY)))
    let applied = appliesGlobal ? detected * lensSupport : (appliesBand ? bandAppliedMagnitude * bandSupport : 0.0)
    let reason: String
    if appliesGlobal {
        reason = "applied"
    } else if appliesBand {
        reason = "rollingRowWarp"
    } else if rollingShutterCandidate >= 0.45 {
        reason = "rollingShutterCandidate"
    } else if qualitySupport < 0.12 && detected > 0.0 {
        reason = "lowConfidence"
    } else if diagnosticDetected > 0.0 {
        reason = "belowSupport"
    } else {
        reason = "noPreparedSignal"
    }
    return BandAssessment(
        name: "LENS",
        detected: diagnosticDetected,
        applied: applied,
        remaining: max(0.0, diagnosticDetected - applied),
        confidence: max(affineSupport, projectiveSupport),
        note: String(format: "source-space %.3fs residual x %.3f y %.3f r %.4f yaw %.6f pitch %.6f shear %.6f %.6f persp %.6f %.6f bandT %.3f %.3f bandR %.3f %.3f bandM %.3f %.3f colT %.3f %.3f colR %.3f %.3f colM %.3f %.3f rowT %.3f %.3f rowR %.3f %.3f rowM %.3f %.3f localRoll %.6f %.6f %.6f sourceRidgeY %.3f sourceRidgeSupport %.2f sourceRidgeLineY %.3f sourceRidgeLineSupport %.2f sourceRidgeLineBandSupport %.2f sourceLocalMag %.3f sourceLocalSupport %.2f bandConf %.2f q %.2f rolling %.2f band %.2f model %@ reason %@", targetWindowSeconds, residualX, residualY, residualRoll, yaw, pitch, shearX, shearY, perspectiveX, perspectiveY, topResidual.x, topResidual.y, ridgeResidual.x, ridgeResidual.y, midResidual.x, midResidual.y, topColumnResidual.x, topColumnResidual.y, ridgeColumnResidual.x, ridgeColumnResidual.y, midColumnResidual.x, midColumnResidual.y, topRowResidual.x, topRowResidual.y, ridgeRowResidual.x, ridgeRowResidual.y, midRowResidual.x, midRowResidual.y, topLocalRoll, ridgeLocalRoll, midLocalRoll, sourceRidgeResidualY, sourceRidgeSupport, sourceRidgeLineResidualY, sourceRidgeLineSupport, sourceRidgeLineBandSupport, sourceLocalMagnitude, sourceLocalSupport, maxBandConfidence, max(affineSupport, projectiveSupport), rollingShutterCandidate, bandSupport, correctionModel, reason)
    )
}

private func stableFarFieldWarpTrackingConfidence(
    analysis: Analysis,
    indices: [Int],
    currentTrackingConfidence: Float
) -> Float {
    let localTrackingValues = indices.compactMap { index -> Float? in
        guard analysis.frames.indices.contains(index),
              analysis.residuals.indices.contains(index),
              analysis.blurAmounts.indices.contains(index),
              analysis.analysisConfidence.indices.contains(index),
              analysis.acceptedBlockCounts.indices.contains(index),
              analysis.totalBlockCounts.indices.contains(index)
        else {
            return nil
        }
        let quality = frameTrackingQuality(
            motionConfidence: analysis.analysisConfidence[index],
            residual: analysis.residuals[index],
            blurAmount: analysis.blurAmounts[index],
            acceptedBlockCount: analysis.acceptedBlockCounts[index],
            totalBlockCount: analysis.totalBlockCounts[index],
            qualityModel: analysis.qualityModel
        )
        return frameTrackingConfidence(quality)
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

private func stableFarFieldWarpEdgeQuality(
    analysis: Analysis,
    indices: [Int],
    currentSearchRadiusHitCount: Int32,
    currentSearchRadiusTotalCount: Int32
) -> Float {
    let currentEdgeQuality = searchRadiusEdgeQuality(
        hitCount: currentSearchRadiusHitCount,
        totalCount: currentSearchRadiusTotalCount
    )
    let localEdgeQualityValues = indices.compactMap { index -> Float? in
        guard analysis.searchRadiusHitCounts.indices.contains(index),
              analysis.searchRadiusTotalCounts.indices.contains(index)
        else {
            return nil
        }
        return searchRadiusEdgeQuality(
            hitCount: analysis.searchRadiusHitCounts[index],
            totalCount: analysis.searchRadiusTotalCounts[index]
        )
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

private func stableFarFieldWarpConfidence(
    analysis: Analysis,
    indices: [Int],
    currentWarpConfidence: Float
) -> Float {
    let localWarpValues = indices.compactMap { index -> Float? in
        guard analysis.warpConfidence.indices.contains(index) else {
            return nil
        }
        let confidence = analysis.warpConfidence[index]
        guard confidence.isFinite else {
            return nil
        }
        return clamp(confidence, min: 0.0, max: 1.0)
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

private func searchRadiusEdgeQuality(hitCount: Int32, totalCount: Int32) -> Float {
    guard totalCount > 0 else {
        return 0.0
    }
    let hitRatio = clamp(Float(hitCount) / Float(totalCount), min: 0.0, max: 1.0)
    return 1.0 - hitRatio
}

private func blurEvidenceQuality(_ blurAmount: Float) -> Float {
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

private func frameTrackingQuality(
    motionConfidence: Float,
    residual: Float,
    blurAmount: Float,
    acceptedBlockCount: Int32,
    totalBlockCount: Int32,
    qualityModel: AnalysisQualityModel
) -> (residualQuality: Float, blurQuality: Float, blockCoverage: Float, combinedEvidence: Float) {
    let residualQuality = residualEvidenceQuality(
        residual,
        multiplier: 0.7,
        qualityModel: qualityModel
    )
    let blurQuality = blurEvidenceQuality(blurAmount)
    let blockCoverage = totalBlockCount > 0 ? clamp(Float(acceptedBlockCount) / Float(totalBlockCount), min: 0.0, max: 1.0) : 0.0
    let evidence = motionConfidence * residualQuality * blurQuality * blockCoverage
    return (residualQuality, blurQuality, blockCoverage, evidence)
}

private func frameTrackingConfidence(_ quality: (residualQuality: Float, blurQuality: Float, blockCoverage: Float, combinedEvidence: Float)) -> Float {
    clamp(sqrtf(max(0.0, quality.combinedEvidence)), min: 0.0, max: 1.0)
}

private func walkingBandTrackingConfidence(
    motionConfidence: Float,
    residual: Float,
    blurAmount: Float,
    acceptedBlockCount: Int32,
    totalBlockCount: Int32,
    qualityModel: AnalysisQualityModel
) -> Float {
    let residualQuality = residualEvidenceQuality(
        residual,
        multiplier: 0.7,
        qualityModel: qualityModel
    )
    let blurQuality = blurEvidenceQuality(blurAmount)
    let blockQuality = walkingBandBlockQuality(acceptedBlockCount: acceptedBlockCount, totalBlockCount: totalBlockCount)
    let evidence = motionConfidence * residualQuality * blurQuality * blockQuality
    return clamp(sqrtf(max(0.0, evidence)), min: 0.0, max: 1.0)
}

private func walkingBandBlockQuality(acceptedBlockCount: Int32, totalBlockCount: Int32) -> Float {
    guard acceptedBlockCount > 0, totalBlockCount > 0 else {
        return 0.0
    }
    let coverage = clamp(Float(acceptedBlockCount) / Float(totalBlockCount), min: 0.0, max: 1.0)
    let countSupport = confidenceRamp(Float(acceptedBlockCount), start: 4.0, full: 10.0)
    let coverageLift = 0.35 * countSupport * (1.0 - coverage)
    return clamp(coverage + coverageLift, min: 0.0, max: 1.0)
}

private func residualAdjustedTrackingConfidence(
    _ trackingConfidence: Float,
    residual: Float,
    multiplier: Float,
    qualityModel: AnalysisQualityModel
) -> Float {
    let residualQuality = residualEvidenceQuality(
        residual,
        multiplier: multiplier,
        qualityModel: qualityModel
    )
    return clamp(trackingConfidence * residualQuality, min: 0.0, max: 1.0)
}

private func residualEvidenceQuality(
    _ residual: Float,
    multiplier: Float,
    qualityModel: AnalysisQualityModel
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

private func symmetricWindowSupport(frames: [AnalysisFrame], centerTime: Double, windowSeconds: Double) -> Float {
    guard let first = frames.first?.time, let last = frames.last?.time else {
        return 0.0
    }
    let halfWindow = windowSeconds * 0.5
    guard halfWindow > 0.0 else {
        return 1.0
    }
    return clamp(Float(min(centerTime - first, last - centerTime) / halfWindow), min: 0.0, max: 1.0)
}

private func percentileValue(_ values: [Float], indices: [Int], percentile: Float) -> Float {
    let sortedValues = indices.filter { values.indices.contains($0) }.map { values[$0] }.filter(\.isFinite).sorted()
    guard !sortedValues.isEmpty else {
        return 0.0
    }
    guard sortedValues.count > 1 else {
        return sortedValues[0]
    }
    let bounded = clamp(percentile, min: 0.0, max: 1.0)
    let scaledIndex = bounded * Float(sortedValues.count - 1)
    let lowerIndex = Int(floorf(scaledIndex))
    let upperIndex = min(sortedValues.count - 1, lowerIndex + 1)
    let fraction = scaledIndex - Float(lowerIndex)
    return sortedValues[lowerIndex] + ((sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction)
}

private func correctionFactor(turnSmoothingZoom: Double, confidence: Float) -> Float {
    let requested = turnSmoothingZoomNormalized(turnSmoothingZoom) * maximumTurnSmoothingCorrectionAuthority
    let response = turnCorrectionConfidenceResponse(confidence)
    let direct = min(requested, 1.0) * response
    let boost = max(0.0, requested - 1.0) * 0.55 * response * (1.0 - (response * 0.25))
    return max(0.0, direct + boost)
}

private func walkingCorrectionFactor(_ strength: Double, confidence: Float, maxStrength: Float = 4.0) -> Float {
    let requested = clamp(Float(strength), min: 0.0, max: maxStrength)
    let response = walkingCorrectionConfidenceResponse(confidence)
    let direct = min(requested, 1.0) * response
    let boost = max(0.0, requested - 1.0) * 0.20 * response * (1.0 - (response * 0.35))
    return clamp(direct + boost, min: 0.0, max: 1.0)
}

private func verticalWalkingCorrectionFactor(_ strength: Double, confidence: Float, maxStrength: Float = 4.0) -> Float {
    let base = walkingCorrectionFactor(strength, confidence: confidence, maxStrength: maxStrength)
    let bounded = clamp(confidence, min: 0.0, max: 1.0)
    let mediumLift = bounded * (1.0 - bounded) * verticalWalkingMediumConfidenceLift
    return clamp(base + mediumLift, min: 0.0, max: 1.0)
}

private func correctionConfidenceResponse(_ confidence: Float) -> Float {
    let bounded = clamp(confidence, min: 0.0, max: 1.0)
    return bounded * bounded * (3.0 - (2.0 * bounded))
}

private func turnCorrectionConfidenceResponse(_ confidence: Float) -> Float {
    let bounded = clamp(confidence, min: 0.0, max: 1.0)
    let eased = bounded * (1.0 + ((1.0 - bounded) * 1.0))
    return clamp(eased, min: 0.0, max: 1.0)
}

private func walkingCorrectionConfidenceResponse(_ confidence: Float) -> Float {
    let bounded = clamp(confidence, min: 0.0, max: 1.0)
    return bounded * (1.0 + ((1.0 - bounded) * 0.90))
}

private func confidenceRamp(_ value: Float, start: Float, full: Float) -> Float {
    guard full > start else {
        return value >= full ? 1.0 : 0.0
    }
    let normalized = clamp((value - start) / (full - start), min: 0.0, max: 1.0)
    return normalized * normalized * (3.0 - (2.0 * normalized))
}

private func smootherStep(_ value: Float) -> Float {
    let t = clamp(value, min: 0.0, max: 1.0)
    return t * t * t * (t * ((t * 6.0) - 15.0) + 10.0)
}

private func median(_ values: [Float]) -> Float? {
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

private func weightedMedian(_ values: [(value: Float, weight: Float)]) -> Float? {
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

private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(maxValue, value))
}

private func effectiveFarFieldWarpStrength(_ requestedStrength: Float) -> Float {
    let bounded = clamp(requestedStrength, min: 0.0, max: maximumFarFieldWarpStrength)
    guard bounded > 0.0 else {
        return 0.0
    }
    guard bounded < 1.0 else {
        return bounded
    }
    let lifted = bounded + (bounded * (1.0 - bounded) * farFieldWarpSubunitResponseLift)
    return clamp(lifted, min: bounded, max: farFieldWarpSubunitResponseMax)
}

private func nearestIndex(in analysis: Analysis, absoluteTime: Double) -> Int {
    analysis.frames.indices.min { left, right in
        abs(analysis.frames[left].time - absoluteTime) < abs(analysis.frames[right].time - absoluteTime)
    } ?? 0
}

private func chooseAssessments(analysis: Analysis, options: Options) throws -> [FrameAssessment] {
    let context = AssessmentContext(analysis: analysis, turnWindowSeconds: options.turnWindowSeconds)
    if let relativeTime = options.relativeTime {
        let absoluteTime = analysis.rangeStartSeconds + relativeTime
        let firstTime = analysis.frames[0].time
        let lastTime = analysis.frames[analysis.frames.count - 1].time
        let tolerance = max(0.05, abs(analysis.frameDurationSeconds) * 2.0)
        guard absoluteTime >= firstTime - tolerance && absoluteTime <= lastTime + tolerance else {
            throw FeedbackError(description: "requested clip-relative time \(formatSeconds(relativeTime)) is outside the cached analysis range \(formatSeconds(firstTime - analysis.rangeStartSeconds))...\(formatSeconds(lastTime - analysis.rangeStartSeconds)); run Host Analysis on a range that covers that moment")
        }
        let halfWindow = max(0.0, options.windowSeconds * 0.5)
        let indices = analysis.frames.indices.filter { abs(analysis.frames[$0].time - absoluteTime) <= halfWindow + timeWindowSelectionEpsilon }
        let candidates = (indices.isEmpty ? [nearestIndex(in: analysis, absoluteTime: absoluteTime)] : Array(indices))
            .map { assessment(for: context, index: $0, options: options) }
        let selectedIndex = candidates.max { $0.score < $1.score }?.index ?? nearestIndex(in: analysis, absoluteTime: absoluteTime)
        return [assessment(for: context, index: selectedIndex, options: options, includeRenderTurnBridge: true)]
    }
    let selectedIndices = analysis.frames.indices
        .map { assessment(for: context, index: $0, options: options) }
        .sorted { $0.score > $1.score }
        .prefix(max(1, options.limit))
        .map(\.index)
    return selectedIndices.map { assessment(for: context, index: $0, options: options, includeRenderTurnBridge: true) }
}

private func renderHuman(_ assessments: [FrameAssessment], analysis: Analysis, options: Options) {
    print("Stabilizer feedback")
    print("Cache: \(analysis.cachePath)")
    print("Schema: \(analysis.schemaVersion), frames: \(analysis.frames.count), sample: \(analysis.sampleWidth)x\(analysis.sampleHeight)")
    print("Turn window: \(formatSeconds(options.turnWindowSeconds))")
    print(String(format: "Turn smoothing strength: %.2f", options.turnStrength))
    if let time = options.relativeTime {
        print("Requested clip time: \(formatSeconds(time)), window: \(formatSeconds(options.windowSeconds))")
        if let selected = assessments.first {
            let delta = selected.clipTime - time
            print("Selected clip time: \(formatSeconds(selected.clipTime)) (\(formatSignedSeconds(delta)) from request; highest-score frame in window)")
        }
    } else {
        print("Top \(assessments.count) residual candidates across cache")
    }
    if let note = options.note, !note.isEmpty {
        print("Note: \(note)")
    }
    print("")
    for assessment in assessments {
        let top = assessment.topBand
        let severity = top.remaining >= 1.0 ? "notable" : (top.remaining >= 0.35 ? "mild" : "low")
        print(String(format: "At %.3fs clip-relative: %@ remaining %@ shake, likely %@", assessment.clipTime, severity, top.name, top.name))
        print(String(format: "  tracking %.2f walking %.2f motion %.2f residual %.4f blur %.2f blocks %d/%d edge %d/%d",
                     assessment.trackingConfidence,
                     assessment.walkingTrackingConfidence,
                     assessment.motionConfidence,
                     assessment.residual,
                     assessment.blur,
                     assessment.acceptedBlocks,
                     assessment.totalBlocks,
                     assessment.edgeHits,
                     assessment.edgeTotal))
        print(String(format: "  quality residualQ %.2f blurQ %.2f blockQ %.2f edgeQ %.2f warpGate %.2f (trk %.2f stable %.2f edge %.2f)",
                     assessment.residualQuality,
                     assessment.blurQuality,
                     assessment.blockCoverage,
                     assessment.edgeQuality,
                     assessment.warpGate,
                     assessment.warpTrackingGate,
                     assessment.warpTrackingConfidence,
                     assessment.warpEdgeGate))
        for band in assessment.bands {
            print(String(format: "  %-4@ detected %.3f applied %.3f remaining %.3f q %.2f | %@",
                         band.name as NSString,
                         band.detected,
                         band.applied,
                         band.remaining,
                         band.confidence,
                         band.note))
        }
        let bridge = assessment.renderTurnBridge
        print(String(format: "  REND TURN bridge applied %.3f remaining %.3f q %.2f samples %d delta %.3f | %@",
                     bridge.applied,
                     bridge.remaining,
                     bridge.confidence,
                     bridge.sampleCount,
                     bridge.delta,
                     bridge.note))
        print("")
    }
}

private func renderJSON(_ assessments: [FrameAssessment], analysis: Analysis, options: Options) throws {
    let root: [String: Any] = [
        "cache": analysis.cachePath,
        "schemaVersion": analysis.schemaVersion,
        "frameCount": analysis.frames.count,
        "sampleWidth": analysis.sampleWidth,
        "sampleHeight": analysis.sampleHeight,
        "selectionMode": options.relativeTime == nil ? "top-cache-candidates" : "highest-score-frame-in-time-window",
        "requestedClipTime": jsonValue(options.relativeTime),
        "selectedClipTime": jsonValue(assessments.first?.clipTime),
        "selectedClipTimeDelta": jsonValue(options.relativeTime.map { requested in
            (assessments.first?.clipTime ?? requested) - requested
        }),
        "windowSeconds": options.windowSeconds,
        "turnWindowSeconds": options.turnWindowSeconds,
        "turnStrength": options.turnStrength,
        "note": jsonValue(options.note),
        "assessments": assessments.map { assessment in
            [
                "frameIndex": assessment.index,
                "clipTime": assessment.clipTime,
                "absoluteTime": assessment.absoluteTime,
                "trackingConfidence": assessment.trackingConfidence,
                "walkingTrackingConfidence": assessment.walkingTrackingConfidence,
                "motionConfidence": assessment.motionConfidence,
                "residual": assessment.residual,
                "blur": assessment.blur,
                "residualQuality": assessment.residualQuality,
                "blurQuality": assessment.blurQuality,
                "blockCoverage": assessment.blockCoverage,
                "acceptedBlocks": assessment.acceptedBlocks,
                "totalBlocks": assessment.totalBlocks,
                "edgeHits": assessment.edgeHits,
                "edgeTotal": assessment.edgeTotal,
                "edgeQuality": assessment.edgeQuality,
                "warpTrackingConfidence": assessment.warpTrackingConfidence,
                "warpTrackingGate": assessment.warpTrackingGate,
                "warpEdgeGate": assessment.warpEdgeGate,
                "warpGate": assessment.warpGate,
                "footstepRawImpulseX": assessment.footstepRawImpulseX,
                "footstepRawImpulseY": assessment.footstepRawImpulseY,
                "footstepBaselineX": assessment.footstepBaselineX,
                "footstepBaselineY": assessment.footstepBaselineY,
                "footstepConfidenceX": assessment.footstepConfidenceX,
                "footstepConfidenceY": assessment.footstepConfidenceY,
                "footstepRawCorrectionX": assessment.footstepRawCorrectionX,
                "footstepRawCorrectionY": assessment.footstepRawCorrectionY,
                "footstepLimitedCorrectionX": assessment.footstepLimitedCorrectionX,
                "footstepLimitedCorrectionY": assessment.footstepLimitedCorrectionY,
                "footstepPulseLimitedX": assessment.footstepPulseLimitedX,
                "footstepPulseLimitedY": assessment.footstepPulseLimitedY,
                "renderTurnBridge": [
                    "applied": assessment.renderTurnBridge.applied,
                    "remaining": assessment.renderTurnBridge.remaining,
                    "confidence": assessment.renderTurnBridge.confidence,
                    "sampleCount": assessment.renderTurnBridge.sampleCount,
                    "rawApplied": assessment.renderTurnBridge.rawApplied,
                    "delta": assessment.renderTurnBridge.delta,
                    "note": assessment.renderTurnBridge.note
                ] as [String: Any],
                "topBand": assessment.topBand.name,
                "bands": assessment.bands.map { band in
                    [
                        "name": band.name,
                        "detected": band.detected,
                        "applied": band.applied,
                        "remaining": band.remaining,
                        "confidence": band.confidence,
                        "note": band.note
                    ] as [String: Any]
                }
            ] as [String: Any]
        }
    ]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    print("")
}

private func renderCacheComparisonHuman(_ comparison: CacheComparison) {
    print("Stabilizer Host Analysis cache comparison")
    print("Baseline: \(comparison.baseline.cachePath)")
    print("Compared: \(comparison.compared.cachePath)")
    print(String(format: "Tolerance: %.9f", comparison.tolerance))
    print("Baseline schema \(comparison.baseline.schemaVersion), frames \(comparison.baseline.frames.count), sample \(comparison.baseline.sampleWidth)x\(comparison.baseline.sampleHeight)")
    print("Compared schema \(comparison.compared.schemaVersion), frames \(comparison.compared.frames.count), sample \(comparison.compared.sampleWidth)x\(comparison.compared.sampleHeight)")
    print("Result: \(comparison.passed ? "MATCH" : "MISMATCH")")
    if !comparison.metadataIssues.isEmpty {
        print("")
        print("Metadata issues:")
        for issue in comparison.metadataIssues {
            print("  \(issue)")
        }
    }
    print("")
    print("Float arrays:")
    for item in comparison.floatComparisons {
        let status = item.passed ? "MATCH" : "MISMATCH"
        let index = item.maxIndex.map(String.init) ?? "-"
        let baselineValue = item.baselineValue.map { String(format: "%.9f", $0) } ?? "-"
        let comparedValue = item.comparedValue.map { String(format: "%.9f", $0) } ?? "-"
        print(String(format: "  %-22@ %@ count %d/%d maxDelta %.9f at %@ baseline %@ compared %@",
                     item.name as NSString,
                     status,
                     item.baselineCount,
                     item.comparedCount,
                     item.maxDelta,
                     index as NSString,
                     baselineValue as NSString,
                     comparedValue as NSString))
    }
    print("")
    print("Integer arrays:")
    for item in comparison.intComparisons {
        let status = item.passed ? "MATCH" : "MISMATCH"
        let index = item.firstMismatchIndex.map(String.init) ?? "-"
        let baselineValue = item.baselineValue.map(String.init) ?? "-"
        let comparedValue = item.comparedValue.map(String.init) ?? "-"
        print(String(format: "  %-22@ %@ count %d/%d mismatches %d first %@ baseline %@ compared %@",
                     item.name as NSString,
                     status,
                     item.baselineCount,
                     item.comparedCount,
                     item.mismatchCount,
                     index as NSString,
                     baselineValue as NSString,
                     comparedValue as NSString))
    }
}

private func renderCacheComparisonJSON(_ comparison: CacheComparison) throws {
    let root: [String: Any] = [
        "baselineCache": comparison.baseline.cachePath,
        "comparedCache": comparison.compared.cachePath,
        "passed": comparison.passed,
        "tolerance": comparison.tolerance,
        "baseline": [
            "schemaVersion": comparison.baseline.schemaVersion,
            "frameCount": comparison.baseline.frames.count,
            "sampleWidth": comparison.baseline.sampleWidth,
            "sampleHeight": comparison.baseline.sampleHeight,
            "rangeStartSeconds": comparison.baseline.rangeStartSeconds,
            "rangeDurationSeconds": comparison.baseline.rangeDurationSeconds,
            "frameDurationSeconds": comparison.baseline.frameDurationSeconds
        ] as [String: Any],
        "compared": [
            "schemaVersion": comparison.compared.schemaVersion,
            "frameCount": comparison.compared.frames.count,
            "sampleWidth": comparison.compared.sampleWidth,
            "sampleHeight": comparison.compared.sampleHeight,
            "rangeStartSeconds": comparison.compared.rangeStartSeconds,
            "rangeDurationSeconds": comparison.compared.rangeDurationSeconds,
            "frameDurationSeconds": comparison.compared.frameDurationSeconds
        ] as [String: Any],
        "metadataIssues": comparison.metadataIssues,
        "floatArrays": comparison.floatComparisons.map { item in
            [
                "name": item.name,
                "passed": item.passed,
                "baselineCount": item.baselineCount,
                "comparedCount": item.comparedCount,
                "maxDelta": item.maxDelta,
                "maxIndex": jsonValue(item.maxIndex),
                "baselineValue": jsonValue(item.baselineValue),
                "comparedValue": jsonValue(item.comparedValue)
            ] as [String: Any]
        },
        "integerArrays": comparison.intComparisons.map { item in
            [
                "name": item.name,
                "passed": item.passed,
                "baselineCount": item.baselineCount,
                "comparedCount": item.comparedCount,
                "mismatchCount": item.mismatchCount,
                "firstMismatchIndex": jsonValue(item.firstMismatchIndex),
                "baselineValue": jsonValue(item.baselineValue),
                "comparedValue": jsonValue(item.comparedValue)
            ] as [String: Any]
        }
    ]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    print("")
}

private func renderCacheInventoryHuman(_ entries: [CacheInventoryEntry], rootPath: String) {
    print("Stabilizer Host Analysis persisted analyses")
    print("Root: \(expandPath(rootPath))")
    if entries.isEmpty {
        print("No persisted analysis files found.")
        return
    }
    for entry in entries {
        let schema = entry.schemaVersion.map(String.init) ?? "-"
        let frames = entry.frameCount.map(String.init) ?? "-"
        let sample: String
        if let width = entry.sampleWidth, let height = entry.sampleHeight {
            sample = "\(width)x\(height)"
        } else {
            sample = "-"
        }
        let range: String
        if let start = entry.rangeStartSeconds, let duration = entry.rangeDurationSeconds {
            range = "\(formatSeconds(start))+\(formatSeconds(duration))"
        } else {
            range = "-"
        }
        let modified = entry.modifiedAt.map { iso8601Formatter.string(from: $0) } ?? "-"
        print("\(entry.status.uppercased()) schema \(schema) frames \(frames) pixels \(sample) range \(range) modified \(modified)")
        print("  \(entry.reason)")
        print("  \(entry.path)")
    }
}

private func renderCacheInventoryJSON(_ entries: [CacheInventoryEntry], rootPath: String) throws {
    let root: [String: Any] = [
        "root": expandPath(rootPath),
        "persistedAnalyses": entries.map { entry in
            [
                "path": entry.path,
                "status": entry.status,
                "reason": entry.reason,
                "schemaVersion": jsonValue(entry.schemaVersion),
                "frameCount": jsonValue(entry.frameCount),
                "rangeStartSeconds": jsonValue(entry.rangeStartSeconds),
                "rangeDurationSeconds": jsonValue(entry.rangeDurationSeconds),
                "requestedSampleScalePercent": jsonValue(entry.requestedSampleScalePercent),
                "sampleWidth": jsonValue(entry.sampleWidth),
                "sampleHeight": jsonValue(entry.sampleHeight),
                "modifiedAt": jsonValue(entry.modifiedAt.map { iso8601Formatter.string(from: $0) })
            ] as [String: Any]
        }
    ]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    print("")
}

private func jsonValue<T>(_ value: T?) -> Any {
    value ?? NSNull()
}

private func parseOptions() throws -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func nextValue(for flag: String) throws -> String {
        guard !args.isEmpty else {
            throw FeedbackError(description: "\(flag) requires a value")
        }
        return args.removeFirst()
    }
    func nextDouble(for flag: String) throws -> Double {
        let value = try nextValue(for: flag)
        guard let number = Double(value), number.isFinite else {
            throw FeedbackError(description: "\(flag) requires a finite number, got \(value)")
        }
        return number
    }
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--cache":
            options.cachePath = try nextValue(for: arg)
        case "--compare-cache":
            options.compareCachePath = try nextValue(for: arg)
        case "--compare-tolerance":
            let tolerance = try nextDouble(for: arg)
            guard tolerance >= 0.0 else {
                throw FeedbackError(description: "--compare-tolerance must be >= 0, got \(tolerance)")
            }
            options.compareTolerance = Float(tolerance)
        case "--cache-root":
            options.cacheRoot = try nextValue(for: arg)
        case "--list-caches":
            options.listCaches = true
        case "--time":
            options.relativeTime = try nextDouble(for: arg)
        case "--note":
            options.note = try nextValue(for: arg)
        case "--window":
            options.windowSeconds = max(0.0, try nextDouble(for: arg))
        case "--turn-window":
            options.turnWindowSeconds = min(max(0.5, try nextDouble(for: arg)), 8.0)
        case "--turn-strength":
            options.turnStrength = min(max(0.0, try nextDouble(for: arg)), 36.0)
        case "--max-turn-zoom":
            FileHandle.standardError.write(Data("warning: --max-turn-zoom is deprecated; use --turn-strength.\n".utf8))
            options.turnStrength = min(max(0.0, try nextDouble(for: arg)), 36.0)
        case "--turn-zoom":
            FileHandle.standardError.write(Data("warning: --turn-zoom is deprecated; use --turn-strength.\n".utf8))
            options.turnStrength = min(max(0.0, try nextDouble(for: arg)), 36.0)
        case "--output-size":
            let value = try nextValue(for: arg)
            let parts = value.lowercased().split(separator: "x")
            guard parts.count == 2, let width = Float(parts[0]), let height = Float(parts[1]), width > 0.0, height > 0.0 else {
                throw FeedbackError(description: "--output-size expects WIDTHxHEIGHT, got \(value)")
            }
            options.outputSize = (width, height)
        case "--json":
            options.json = true
        case "--limit":
            options.limit = max(1, Int(try nextDouble(for: arg)))
        case "--camera-x":
            let value = min(max(0.0, try nextDouble(for: arg)), 5.0)
            options.strengths.cameraX = value
            options.strengths.microX = value * 2.0
            options.strengths.strideX = value * 2.0
        case "--camera-y":
            let value = min(max(0.0, try nextDouble(for: arg)), 5.0)
            options.strengths.cameraY = value
            options.strengths.microY = value * 2.0
            options.strengths.strideY = value * 2.0
        case "--camera-r":
            let value = min(max(0.0, try nextDouble(for: arg)), 2.0)
            options.strengths.cameraR = value
            options.strengths.microR = value * 2.0
            options.strengths.strideR = value * 2.0
        case "--micro-x", "--micro-y", "--micro-r", "--stride-x", "--stride-y", "--stride-r":
            _ = try nextDouble(for: arg)
            throw FeedbackError(description: "\(arg) is retired; use --camera-x, --camera-y, or --camera-r.")
        case "--turn":
            _ = try nextDouble(for: arg)
            throw FeedbackError(description: "--turn is retired; use --turn-strength for turn smoothing correction and zoom authority.")
        case "--warp":
            options.strengths.warp = try nextDouble(for: arg)
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw FeedbackError(description: "unknown argument \(arg)")
        }
    }
    return options
}

private func printUsage() {
    print("""
    usage:
      stabilizer_feedback.sh --cache /path/to/host-analysis-v2.json --time 5.0 --note "notable unremoved shake"
      stabilizer_feedback.sh --cache /path/to/host-analysis-v2.json --time 5.0 --json
      stabilizer_feedback.sh --cache /path/to/host-analysis-v2.json --limit 5
      stabilizer_feedback.sh --list-caches --cache-root /path/to/TokyoWalkingStabilizerHostAnalysis
      stabilizer_feedback.sh --cache /path/to/baseline.json --compare-cache /path/to/new.json

    time is clip-relative: 0.0 is the Host Analysis range start.
    caches are stored inside the active Final Cut Pro library bundle under TokyoWalkingStabilizerHostAnalysis.
    --turn-strength should match Turn Smoothing Strength when it is not 12.0; range is 0...36.
    --camera-x and --camera-y are Camera Rigid maximum corrections in output percent (0...5).
    --camera-r is Camera Rigid maximum correction in degrees (0...2).
    --turn-zoom and --max-turn-zoom are deprecated aliases for --turn-strength and print a warning when used.
    --turn-window should match Turn Transition Window (s); range is 0.5...8.0.
    --list-caches reports saved cache readiness without repairing cache files.
    --compare-cache validates saved cache equivalence; float arrays may differ only within --compare-tolerance.
    """)
}

private func formatSeconds(_ value: Double) -> String {
    String(format: "%.3fs", value)
}

private func formatPercent(_ value: Double) -> String {
    if value.rounded() == value {
        return String(format: "%.0f%%", value)
    }
    return String(format: "%.2f%%", value)
}

private func formatSignedSeconds(_ value: Double) -> String {
    String(format: "%+.3fs", value)
}

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

do {
    let options = try parseOptions()
    if options.listCaches {
        guard let cacheRoot = options.cacheRoot else {
            throw FeedbackError(description: "--list-caches requires --cache-root pointing to the library bundle's TokyoWalkingStabilizerHostAnalysis directory")
        }
        let entries = cacheInventory(rootPath: cacheRoot)
        if options.json {
            try renderCacheInventoryJSON(entries, rootPath: cacheRoot)
        } else {
            renderCacheInventoryHuman(entries, rootPath: cacheRoot)
        }
    } else if let compareCachePath = options.compareCachePath {
        guard let cachePath = options.cachePath else {
            throw FeedbackError(description: "--compare-cache requires --cache pointing to the baseline host-analysis cache file")
        }
        let baseline = try loadAnalysis(path: cachePath)
        let compared = try loadAnalysis(path: compareCachePath)
        let comparison = compareCaches(baseline: baseline, compared: compared, tolerance: options.compareTolerance)
        if options.json {
            try renderCacheComparisonJSON(comparison)
        } else {
            renderCacheComparisonHuman(comparison)
        }
        if !comparison.passed {
            throw FeedbackError(description: "Host Analysis cache comparison failed")
        }
    } else {
        guard let cachePath = options.cachePath else {
            throw FeedbackError(description: "feedback requires --cache pointing to a bundle-local host-analysis cache file")
        }
        let analysis = try loadAnalysis(path: cachePath)
        let assessments = try chooseAssessments(analysis: analysis, options: options)
        if options.json {
            try renderJSON(assessments, analysis: analysis, options: options)
        } else {
            renderHuman(assessments, analysis: analysis, options: options)
        }
    }
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
