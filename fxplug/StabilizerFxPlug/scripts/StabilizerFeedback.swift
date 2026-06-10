import Darwin
import Foundation

private struct FeedbackError: Error, CustomStringConvertible {
    let description: String
}

private struct Options {
    var cachePath = "~/Library/Application Support/StabilizerFxPlug/host-analysis-v2.json"
    var cacheRoot = "~/Library/Application Support/StabilizerFxPlug"
    var relativeTime: Double?
    var note: String?
    var windowSeconds = 0.25
    var outputSize: (width: Float, height: Float)?
    var json = false
    var limit = 5
    var listCaches = false
    var strengths = Strengths.defaults
}

private struct Strengths {
    var microX: Double
    var microY: Double
    var microR: Double
    var strideX: Double
    var strideY: Double
    var strideR: Double
    var turn: Double
    var bob: Double
    var warp: Double

    static let defaults = Strengths(
        microX: 1.0,
        microY: 1.0,
        microR: 1.0,
        strideX: 0.65,
        strideY: 0.70,
        strideR: 0.75,
        turn: 1.0,
        bob: 0.75,
        warp: 1.0
    )
}

private struct PersistedHostAnalysisCache: Decodable {
    let schemaVersion: Int
    let rangeStartSeconds: Double
    let rangeDurationSeconds: Double
    let frameDurationSeconds: Double
    let sampleWidth: Int
    let sampleHeight: Int
    let frames: [PersistedHostAnalysisFrame]
    let residuals: [Float]?
    let rollMotion: [Float]?
    let pathX: [Float]?
    let pathY: [Float]?
    let pathRoll: [Float]?
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
    let sampleWidth: Int?
    let sampleHeight: Int?
    let modifiedAt: Date?
}

private struct AnalysisFrame {
    let time: Double
    let blurAmount: Float
    let fingerprint: String
}

private struct Analysis {
    let cachePath: String
    let schemaVersion: Int
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
        guard cache.schemaVersion == supportedCacheSchemaVersion else {
            throw FeedbackError(description: "unsupported Host Analysis cache schema \(cache.schemaVersion); run Host Analysis with the current FxPlug before using feedback diagnostics")
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

        func requireIntArray(_ value: [Int32]?, _ name: String) throws -> [Int32] {
            guard let value else {
                throw FeedbackError(description: "Host Analysis cache is missing \(name); rerun Host Analysis with the current FxPlug")
            }
            guard value.count == frames.count else {
                throw FeedbackError(description: "Host Analysis cache is not feedback-ready: \(name) has \(value.count) values but frames has \(frames.count); rerun Host Analysis with the current FxPlug")
            }
            return value
        }

        self.cachePath = cachePath
        schemaVersion = cache.schemaVersion
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

private struct BandAssessment {
    let name: String
    let detected: Float
    let applied: Float
    let remaining: Float
    let confidence: Float
    let note: String
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
    let bands: [BandAssessment]

    var topBand: BandAssessment {
        bands.max { $0.remaining < $1.remaining } ?? BandAssessment(name: "NONE", detected: 0.0, applied: 0.0, remaining: 0.0, confidence: 0.0, note: "no band data")
    }

    var score: Float {
        bands.reduce(Float(0.0)) { $0 + $1.remaining }
    }
}

private let strideWindowSeconds = 2.0
private let walkingBobWindowSeconds = 2.5
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
private let footstepFullResponseScale: Float = 0.65
private let strideFullScalePixels: Float = 0.75
private let strideFullScaleDegrees: Float = 0.16
private let strideFullResponseScale: Float = 0.65
private let walkingBobFullScalePixels: Float = 0.65
private let turnFullScalePixels: Float = 2.0
private let farFieldWarpTrackingGateStart: Float = 0.26
private let farFieldWarpTrackingGateFull: Float = 0.56
private let farFieldWarpTrackingGateMedianBlend: Float = 0.45
private let farFieldWarpTrackingGateStabilityLimit: Float = 0.15
private let farFieldWarpEdgeQualityGateStart: Float = 0.55
private let farFieldWarpEdgeQualityGateFull: Float = 0.86
private let supportedCacheSchemaVersion = 14

private func loadAnalysis(path: String) throws -> Analysis {
    let expandedPath = expandPath(path)
    let url = URL(fileURLWithPath: expandedPath)
    let data = try Data(contentsOf: url)
    let cache = try JSONDecoder().decode(PersistedHostAnalysisCache.self, from: data)
    return try Analysis(cache: cache, cachePath: expandedPath)
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
        if cache.schemaVersion != supportedCacheSchemaVersion {
            status = "unsupported"
            reason = "schema \(cache.schemaVersion), need \(supportedCacheSchemaVersion)"
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
    let floatArrays: [(String, [Float]?)] = [
        ("residuals", cache.residuals),
        ("rollMotion", cache.rollMotion),
        ("pathX", cache.pathX),
        ("pathY", cache.pathY),
        ("pathRoll", cache.pathRoll),
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

private func assessment(for analysis: Analysis, index: Int, options: Options) -> FrameAssessment {
    let frame = analysis.frames[index]
    let outputWidth = options.outputSize?.width ?? Float(analysis.sampleWidth)
    let outputHeight = options.outputSize?.height ?? Float(analysis.sampleHeight)
    let xScale = outputWidth / Float(max(1, analysis.sampleWidth))
    let yScale = outputHeight / Float(max(1, analysis.sampleHeight))

    let strideIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: strideWindowSeconds)
    let bobIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: walkingBobWindowSeconds)
    let turnWindowSeconds = max(strideWindowSeconds, 6.0)
    let turnIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: turnWindowSeconds)
    let warpGateIndices = activeIndices(analysis.frames, centerTime: frame.time, windowSeconds: farFieldOuterWindowSeconds)
    let sampledIndices = Array(Set(strideIndices + bobIndices + turnIndices + [index]))
    let centerResidual = analysis.residuals[index]
    let quality = frameTrackingQuality(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index]
    )
    let tracking = frameTrackingConfidence(quality)
    let walkingTracking = walkingBandTrackingConfidence(
        motionConfidence: analysis.analysisConfidence[index],
        residual: centerResidual,
        blurAmount: analysis.blurAmounts[index],
        acceptedBlockCount: analysis.acceptedBlockCounts[index],
        totalBlockCount: analysis.totalBlockCounts[index]
    )

    let footstepCleanXPath = outerLinearPredictionPath(
        analysis.footstepPathX,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        innerWindowSeconds: footstepInnerWindowSeconds,
        outerWindowSeconds: footstepOuterWindowSeconds
    )
    let footstepCleanYPath = outerLinearPredictionPath(
        analysis.footstepPathY,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        innerWindowSeconds: footstepInnerWindowSeconds,
        outerWindowSeconds: footstepOuterWindowSeconds
    )
    let footstepCleanRPath = outerLinearPredictionPath(
        analysis.footstepPathRoll,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        innerWindowSeconds: footstepInnerWindowSeconds,
        outerWindowSeconds: footstepOuterWindowSeconds
    )
    let strideSmoothedXPath = locallyTimeWeightedAveragePath(
        footstepCleanXPath,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        windowSeconds: strideWindowSeconds
    )
    let strideSmoothedYPath = locallyTimeWeightedAveragePath(
        footstepCleanYPath,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        windowSeconds: strideWindowSeconds
    )
    let strideSmoothedRPath = locallyTimeWeightedAveragePath(
        footstepCleanRPath,
        frames: analysis.frames,
        targetIndices: sampledIndices,
        windowSeconds: strideWindowSeconds
    )

    let footstepBaseX = footstepCleanXPath[index]
    let footstepBaseY = footstepCleanYPath[index]
    let footstepBaseR = footstepCleanRPath[index]
    let strideSmoothX = strideSmoothedXPath[index]
    let strideSmoothY = strideSmoothedYPath[index]
    let strideSmoothR = strideSmoothedRPath[index]
    let bobSmoothY = timeWeightedAverage(strideSmoothedYPath, frames: analysis.frames, indices: bobIndices, centerTime: frame.time, windowSeconds: walkingBobWindowSeconds)
    let turnSmoothX = timeWeightedMonotonicSCurveValue(strideSmoothedXPath, frames: analysis.frames, indices: turnIndices, centerTime: frame.time, windowSeconds: turnWindowSeconds)
        ?? timeWeightedAverage(strideSmoothedXPath, frames: analysis.frames, indices: turnIndices, centerTime: frame.time, windowSeconds: turnWindowSeconds)

    let strideResidual = percentileValue(analysis.residuals, indices: strideIndices, percentile: 0.70)
    let bobResidual = percentileValue(analysis.residuals, indices: bobIndices, percentile: 0.70)
    let turnResidual = percentileValue(analysis.residuals, indices: turnIndices, percentile: 0.75)
    let strideTracking = residualAdjustedTrackingConfidence(walkingTracking, residual: strideResidual, multiplier: 0.6)
    let bobTracking = residualAdjustedTrackingConfidence(walkingTracking, residual: bobResidual, multiplier: 0.4)
    let turnTracking = residualAdjustedTrackingConfidence(tracking, residual: turnResidual, multiplier: 0.9)

    let footX = analysis.footstepPathX[index] - footstepBaseX
    let footY = analysis.footstepPathY[index] - footstepBaseY
    let footR = analysis.footstepPathRoll[index] - footstepBaseR
    let footQX = footstepConfidence(values: analysis.footstepPathX, baselineValues: footstepCleanXPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScalePixels)
    let footQY = footstepConfidence(values: analysis.footstepPathY, baselineValues: footstepCleanYPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScalePixels)
    let footQR = footstepConfidence(values: analysis.footstepPathRoll, baselineValues: footstepCleanRPath, frames: analysis.frames, index: index, trackingConfidence: walkingTracking, fullImpulseScale: footstepFullScaleDegrees)
    let footAppliedX = abs(footX * xScale) * correctionFactor(options.strengths.microX, confidence: footQX)
    let footAppliedY = abs(footY * yScale) * correctionFactor(options.strengths.microY, confidence: footQY)
    let footAppliedR = abs(footR) * correctionFactor(options.strengths.microR, confidence: footQR)
    let footDetected = hypotf(footX * xScale, footY * yScale) + (abs(footR) * 12.0)
    let footApplied = hypotf(footAppliedX, footAppliedY) + (footAppliedR * 12.0)

    let strideX = footstepBaseX - strideSmoothX
    let strideY = footstepBaseY - strideSmoothY
    let strideR = footstepBaseR - strideSmoothR
    let strideQX = strideConfidence(bandValue: strideX, trackingConfidence: strideTracking, fullScale: strideFullScalePixels)
    let strideQY = strideConfidence(bandValue: strideY, trackingConfidence: strideTracking, fullScale: strideFullScalePixels)
    let strideQR = strideConfidence(bandValue: strideR, trackingConfidence: strideTracking, fullScale: strideFullScaleDegrees)
    let strideAppliedX = abs(strideX * xScale) * correctionFactor(options.strengths.strideX, confidence: strideQX)
    let strideAppliedY = abs(strideY * yScale) * correctionFactor(options.strengths.strideY, confidence: strideQY)
    let strideAppliedR = abs(strideR) * correctionFactor(options.strengths.strideR, confidence: strideQR)
    let strideDetected = hypotf(strideX * xScale, strideY * yScale) + (abs(strideR) * 12.0)
    let strideApplied = hypotf(strideAppliedX, strideAppliedY) + (strideAppliedR * 12.0)

    let bobBandY = strideSmoothY - bobSmoothY
    let bobSupport = symmetricWindowSupport(frames: analysis.frames, centerTime: frame.time, windowSeconds: walkingBobWindowSeconds)
    let bobQ = walkingBobConfidence(bandValue: bobBandY, trackingConfidence: bobTracking, windowSupport: bobSupport)
    let bobDetected = abs(bobBandY * yScale)
    let bobApplied = bobDetected * correctionFactor(options.strengths.bob, confidence: bobQ)

    let turnBandX = strideSmoothX - turnSmoothX
    let turnQ = turnConfidence(bandValue: turnBandX, trackingConfidence: turnTracking)
    let turnDetected = abs(turnBandX * xScale)
    let turnApplied = turnDetected * correctionFactor(options.strengths.turn, confidence: turnQ)

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
    let warpGateComponents = farFieldWarpGateComponents(
        warpConfidence: rawWarpConfidence,
        trackingConfidence: warpTracking,
        edgeQuality: warpEdgeQuality
    )
    let warpGate = warpGateComponents.gate
    let appliedWarpConfidence = clamp(rawWarpConfidence * warpGate, min: 0.0, max: 1.0)
    let warpDetected = warpMagnitude(analysis: analysis, index: index) * min(4.0, max(0.0, Float(options.strengths.warp)))
    let warpApplied = warpDetected * warpGate

    let bands = [
        BandAssessment(
            name: "FJIT",
            detected: footDetected,
            applied: footApplied,
            remaining: max(0.0, footDetected - footApplied),
            confidence: (footQX + footQY + footQR) / 3.0,
            note: String(format: "foot raw X %.3f Y %.3f R %.3f qX %.2f qY %.2f qR %.2f", footX, footY, footR, footQX, footQY, footQR)
        ),
        BandAssessment(
            name: "SWOB",
            detected: strideDetected,
            applied: strideApplied,
            remaining: max(0.0, strideDetected - strideApplied),
            confidence: (strideQX + strideQY + strideQR) / 3.0,
            note: String(format: "stride band X %.3f Y %.3f R %.3f qX %.2f qY %.2f qR %.2f", strideX, strideY, strideR, strideQX, strideQY, strideQR)
        ),
        BandAssessment(
            name: "BOB",
            detected: bobDetected,
            applied: bobApplied,
            remaining: max(0.0, bobDetected - bobApplied),
            confidence: bobQ,
            note: String(format: "Y band %.3f trk %.2f support %.2f", bobBandY, bobTracking, bobSupport)
        ),
        BandAssessment(
            name: "TURN",
            detected: turnDetected,
            applied: turnApplied,
            remaining: max(0.0, turnDetected - turnApplied),
            confidence: turnQ,
            note: String(format: "X band %.3f", turnBandX)
        ),
        BandAssessment(
            name: "WARP",
            detected: warpDetected,
            applied: warpApplied,
            remaining: max(0.0, warpDetected - warpApplied),
            confidence: appliedWarpConfidence,
            note: String(format: "dimensionless warp band raw q %.2f gate %.2f trkGate %.2f edgeGate %.2f stableTrk %.2f", rawWarpConfidence, warpGate, warpGateComponents.trackingGate, warpGateComponents.edgeGate, warpTracking)
        )
    ].sorted { $0.remaining > $1.remaining }

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
        bands: bands
    )
}

private func warpMagnitude(analysis: Analysis, index: Int) -> Float {
    let yaw = analysis.pathYaw[index] - (outerLinearPrediction(analysis.pathYaw, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathYaw[index])
    let pitch = analysis.pathPitch[index] - (outerLinearPrediction(analysis.pathPitch, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathPitch[index])
    let shearX = analysis.pathShearX[index] - (outerLinearPrediction(analysis.pathShearX, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathShearX[index])
    let shearY = analysis.pathShearY[index] - (outerLinearPrediction(analysis.pathShearY, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathShearY[index])
    let perspX = analysis.pathPerspectiveX[index] - (outerLinearPrediction(analysis.pathPerspectiveX, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathPerspectiveX[index])
    let perspY = analysis.pathPerspectiveY[index] - (outerLinearPrediction(analysis.pathPerspectiveY, frames: analysis.frames, centerIndex: index, innerWindowSeconds: farFieldInnerWindowSeconds, outerWindowSeconds: farFieldOuterWindowSeconds) ?? analysis.pathPerspectiveY[index])
    return (hypotf(yaw, pitch) * 1000.0) + (hypotf(shearX, shearY) * 900.0) + (hypotf(perspX, perspY) * 900.0)
}

private func activeIndices(_ frames: [AnalysisFrame], centerTime: Double, windowSeconds: Double) -> [Int] {
    let halfWindow = windowSeconds * 0.5
    let indices = frames.indices.filter { abs(frames[$0].time - centerTime) <= halfWindow + timeWindowSelectionEpsilon }
    return indices.isEmpty ? Array(frames.indices) : Array(indices)
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
        let localIndices = frames.indices.filter { candidate in
            abs(frames[candidate].time - centerTime) <= halfWindow + timeWindowSelectionEpsilon
        }
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
    for index in frames.indices where values.indices.contains(index) {
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
    let indices = frames.indices.filter { index in
        let distance = abs(frames[index].time - centerTime)
        return distance <= outerWindow + timeWindowSelectionEpsilon && distance > innerWindow + timeWindowSelectionEpsilon
    }
    if indices.count >= 3 {
        return Array(indices)
    }
    return frames.indices.filter { abs(frames[$0].time - centerTime) <= outerWindow + timeWindowSelectionEpsilon }
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

private func walkingBobConfidence(bandValue: Float, trackingConfidence: Float, windowSupport: Float) -> Float {
    let magnitude = abs(bandValue)
    let noiseFloor = walkingBobFullScalePixels * 0.08
    let bandQuality = confidenceRamp(magnitude, start: noiseFloor, full: max(noiseFloor + Float.ulpOfOne, walkingBobFullScalePixels))
    return clamp(trackingConfidence * windowSupport * bandQuality, min: 0.0, max: 1.0)
}

private func turnConfidence(bandValue: Float, trackingConfidence: Float) -> Float {
    let magnitude = abs(bandValue)
    let noiseFloor = turnFullScalePixels * 0.08
    let bandQuality = confidenceRamp(magnitude, start: noiseFloor, full: max(noiseFloor + Float.ulpOfOne, turnFullScalePixels))
    return clamp(trackingConfidence * bandQuality, min: 0.0, max: 1.0)
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
    let gate = correctionConfidenceResponse(clamp(trackingGate * edgeGate, min: 0.0, max: 1.0))
    return (edgeQuality, trackingGate, edgeGate, gate)
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
            totalBlockCount: analysis.totalBlockCounts[index]
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
    return clamp(
        blendedTrackingConfidence,
        min: max(0.0, currentTrackingConfidence - farFieldWarpTrackingGateStabilityLimit),
        max: min(1.0, currentTrackingConfidence + farFieldWarpTrackingGateStabilityLimit)
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
    return min(currentEdgeQuality, localMedianEdgeQuality)
}

private func searchRadiusEdgeQuality(hitCount: Int32, totalCount: Int32) -> Float {
    guard totalCount > 0 else {
        return 0.0
    }
    let hitRatio = clamp(Float(hitCount) / Float(totalCount), min: 0.0, max: 1.0)
    return 1.0 - hitRatio
}

private func frameTrackingQuality(
    motionConfidence: Float,
    residual: Float,
    blurAmount: Float,
    acceptedBlockCount: Int32,
    totalBlockCount: Int32
) -> (residualQuality: Float, blurQuality: Float, blockCoverage: Float, combinedEvidence: Float) {
    let residualQuality = clamp(1.0 - (residual * 0.7), min: 0.0, max: 1.0)
    let blurQuality = clamp(1.0 - (blurAmount * 0.45), min: 0.0, max: 1.0)
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
    totalBlockCount: Int32
) -> Float {
    let residualQuality = clamp(1.0 - (residual * 0.7), min: 0.0, max: 1.0)
    let blurQuality = clamp(1.0 - (blurAmount * 0.45), min: 0.0, max: 1.0)
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

private func residualAdjustedTrackingConfidence(_ trackingConfidence: Float, residual: Float, multiplier: Float) -> Float {
    let residualQuality = clamp(1.0 - (residual * multiplier), min: 0.0, max: 1.0)
    return clamp(trackingConfidence * residualQuality, min: 0.0, max: 1.0)
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

private func correctionFactor(_ strength: Double, confidence: Float) -> Float {
    let requested = clamp(Float(strength), min: 0.0, max: 4.0)
    let response = correctionConfidenceResponse(confidence)
    let direct = min(requested, 1.0) * response
    let boost = max(0.0, requested - 1.0) * 0.20 * response * (1.0 - (response * 0.35))
    return clamp(direct + boost, min: 0.0, max: 1.0)
}

private func correctionConfidenceResponse(_ confidence: Float) -> Float {
    let bounded = clamp(confidence, min: 0.0, max: 1.0)
    return bounded * (1.0 + ((1.0 - bounded) * 0.45))
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

private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(maxValue, value))
}

private func nearestIndex(in analysis: Analysis, absoluteTime: Double) -> Int {
    analysis.frames.indices.min { left, right in
        abs(analysis.frames[left].time - absoluteTime) < abs(analysis.frames[right].time - absoluteTime)
    } ?? 0
}

private func chooseAssessments(analysis: Analysis, options: Options) throws -> [FrameAssessment] {
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
            .map { assessment(for: analysis, index: $0, options: options) }
        return [candidates.max { $0.score < $1.score } ?? assessment(for: analysis, index: nearestIndex(in: analysis, absoluteTime: absoluteTime), options: options)]
    }
    return analysis.frames.indices
        .map { assessment(for: analysis, index: $0, options: options) }
        .sorted { $0.score > $1.score }
        .prefix(max(1, options.limit))
        .map { $0 }
}

private func renderHuman(_ assessments: [FrameAssessment], analysis: Analysis, options: Options) {
    print("Stabilizer feedback")
    print("Cache: \(analysis.cachePath)")
    print("Schema: \(analysis.schemaVersion), frames: \(analysis.frames.count), sample: \(analysis.sampleWidth)x\(analysis.sampleHeight)")
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

private func renderCacheInventoryHuman(_ entries: [CacheInventoryEntry], rootPath: String) {
    print("Stabilizer Host Analysis caches")
    print("Root: \(expandPath(rootPath))")
    if entries.isEmpty {
        print("No cache files found.")
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
        print("\(entry.status.uppercased()) schema \(schema) frames \(frames) sample \(sample) range \(range) modified \(modified)")
        print("  \(entry.reason)")
        print("  \(entry.path)")
    }
}

private func renderCacheInventoryJSON(_ entries: [CacheInventoryEntry], rootPath: String) throws {
    let root: [String: Any] = [
        "root": expandPath(rootPath),
        "caches": entries.map { entry in
            [
                "path": entry.path,
                "status": entry.status,
                "reason": entry.reason,
                "schemaVersion": jsonValue(entry.schemaVersion),
                "frameCount": jsonValue(entry.frameCount),
                "rangeStartSeconds": jsonValue(entry.rangeStartSeconds),
                "rangeDurationSeconds": jsonValue(entry.rangeDurationSeconds),
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
        case "--micro-x":
            options.strengths.microX = try nextDouble(for: arg)
        case "--micro-y":
            options.strengths.microY = try nextDouble(for: arg)
        case "--micro-r":
            options.strengths.microR = try nextDouble(for: arg)
        case "--stride-x":
            options.strengths.strideX = try nextDouble(for: arg)
        case "--stride-y":
            options.strengths.strideY = try nextDouble(for: arg)
        case "--stride-r":
            options.strengths.strideR = try nextDouble(for: arg)
        case "--turn":
            options.strengths.turn = try nextDouble(for: arg)
        case "--bob":
            options.strengths.bob = try nextDouble(for: arg)
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
      stabilizer_feedback.sh --time 5.0 --note "notable unremoved shake"
      stabilizer_feedback.sh --time 5.0 --json
      stabilizer_feedback.sh --cache /path/to/host-analysis-v2.json --limit 5
      stabilizer_feedback.sh --list-caches

    time is clip-relative: 0.0 is the Host Analysis range start.
    --list-caches reports saved cache readiness without repairing cache files.
    """)
}

private func formatSeconds(_ value: Double) -> String {
    String(format: "%.3fs", value)
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
        let entries = cacheInventory(rootPath: options.cacheRoot)
        if options.json {
            try renderCacheInventoryJSON(entries, rootPath: options.cacheRoot)
        } else {
            renderCacheInventoryHuman(entries, rootPath: options.cacheRoot)
        }
    } else {
        let analysis = try loadAnalysis(path: options.cachePath)
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
