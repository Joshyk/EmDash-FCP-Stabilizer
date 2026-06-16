import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

private let toolSchemaVersion = 1
private let cacheSchemaVersion = 15
private let cacheFileName = "host-analysis-v2.json"
private let cacheIndexFileName = "host-analysis-index-v2.json"
private let cacheStorageDirectoryName = "caches"
private let fingerprintInitialHash: UInt64 = 14_695_981_039_346_656_037

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
    let mediaPath: String
    let mediaKind: String?
    let cacheFileName: String
    let cacheIdentity: String
    let cacheSchemaVersion: Int
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
}

struct ToolOutput: Encodable {
    let schemaVersion: Int
    let status: String
    let results: [AnalysisResult]
}

struct AnalysisFrame {
    let time: Double
    let pixels: [UInt8]
    let sampleWidth: Int
    let sampleHeight: Int
    let blurAmount: Float
    let fingerprint: String
}

struct PairMotion {
    let dx: Float
    let dy: Float
    let residual: Float
    let confidence: Float
}

struct PreparedAnalysis {
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
}

struct PersistedHostAnalysisCache: Codable {
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

struct PersistedHostAnalysisFrame: Codable {
    let time: Double
    let pixels: Data?
    let blurAmount: Float
    let fingerprint: String?
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
    if enabled {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
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

func fingerprint(for pixels: [UInt8]) -> String {
    var hash = fingerprintInitialHash
    for byte in pixels {
        combineFingerprintByte(byte, into: &hash)
    }
    return fingerprintString(hash: hash, byteCount: pixels.count)
}

func blurAmount(_ pixels: [UInt8], width: Int, height: Int) -> Float {
    guard width > 2, height > 2 else { return 0 }
    var total: Int = 0
    var count: Int = 0
    let stride = max(1, min(width, height) / 160)
    var y = stride
    while y < height - stride {
        var x = stride
        while x < width - stride {
            let center = Int(pixels[y * width + x])
            let dx = abs(center - Int(pixels[y * width + x + stride]))
            let dy = abs(center - Int(pixels[(y + stride) * width + x]))
            total += dx + dy
            count += 2
            x += stride
        }
        y += stride
    }
    guard count > 0 else { return 0 }
    return Float(total) / Float(count)
}

func lumaSample(from pixelBuffer: CVPixelBuffer, sampleWidth: Int, sampleHeight: Int) throws -> [UInt8] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw AnalyzerError("pixel buffer had no base address")
    }
    let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
    let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pointer = base.assumingMemoryBound(to: UInt8.self)
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
    for y in 0..<sampleHeight {
        let sy = min(sourceHeight - 1, Int((Double(y) + 0.5) * Double(sourceHeight) / Double(sampleHeight)))
        for x in 0..<sampleWidth {
            let sx = min(sourceWidth - 1, Int((Double(x) + 0.5) * Double(sourceWidth) / Double(sampleWidth)))
            let offset = sy * bytesPerRow + sx * 4
            let b = Double(pointer[offset])
            let g = Double(pointer[offset + 1])
            let r = Double(pointer[offset + 2])
            pixels[y * sampleWidth + x] = UInt8(clamp(Int((0.299 * r + 0.587 * g + 0.114 * b).rounded()), 0, 255))
        }
    }
    return pixels
}

func blockScore(previous: [UInt8], current: [UInt8], width: Int, height: Int, centerX: Int, centerY: Int, blockWidth: Int, blockHeight: Int, dx: Int, dy: Int, step: Int) -> Float {
    var total = 0
    var count = 0
    let halfW = blockWidth / 2
    let halfH = blockHeight / 2
    let x0 = max(0, centerX - halfW)
    let x1 = min(width - 1, centerX + halfW)
    let y0 = max(0, centerY - halfH)
    let y1 = min(height - 1, centerY + halfH)
    var y = y0
    while y <= y1 {
        let cy = y + dy
        if cy >= 0 && cy < height {
            var x = x0
            while x <= x1 {
                let cx = x + dx
                if cx >= 0 && cx < width {
                    total += abs(Int(previous[y * width + x]) - Int(current[cy * width + cx]))
                    count += 1
                }
                x += step
            }
        }
        y += step
    }
    guard count > 0 else { return Float.greatestFiniteMagnitude }
    return Float(total) / Float(count)
}

func estimateMotion(previous: [UInt8], current: [UInt8], width: Int, height: Int) -> PairMotion {
    let radius = min(24, max(4, min(width, height) / 64))
    let searchStep = width > 1400 || height > 900 ? 2 : 1
    let blockWidth = max(32, width / 4)
    let blockHeight = max(24, height / 5)
    let sampleStep = max(1, min(blockWidth, blockHeight) / 56)
    let centers = [
        (width / 2, max(1, height / 4)),
        (width / 3, max(1, height / 3)),
        ((width * 2) / 3, max(1, height / 3)),
    ]
    var dxValues: [Float] = []
    var dyValues: [Float] = []
    var scores: [Float] = []
    for center in centers {
        var bestScore = Float.greatestFiniteMagnitude
        var bestDx = 0
        var bestDy = 0
        var dy = -radius
        while dy <= radius {
            var dx = -radius
            while dx <= radius {
                let score = blockScore(
                    previous: previous,
                    current: current,
                    width: width,
                    height: height,
                    centerX: center.0,
                    centerY: center.1,
                    blockWidth: blockWidth,
                    blockHeight: blockHeight,
                    dx: dx,
                    dy: dy,
                    step: sampleStep
                )
                if score < bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
                dx += searchStep
            }
            dy += searchStep
        }
        dxValues.append(Float(bestDx))
        dyValues.append(Float(bestDy))
        scores.append(bestScore)
    }
    let dx = dxValues.reduce(0, +) / Float(max(1, dxValues.count))
    let dy = dyValues.reduce(0, +) / Float(max(1, dyValues.count))
    let residual = scores.reduce(0, +) / Float(max(1, scores.count))
    let confidence = clamp(1.0 - (residual / 48.0), 0.05, 1.0)
    return PairMotion(dx: dx, dy: dy, residual: residual, confidence: confidence)
}

func prepare(frames: [AnalysisFrame], motions: [PairMotion]) throws -> PreparedAnalysis {
    guard frames.count == motions.count else {
        throw AnalyzerError("motion count did not match frame count")
    }
    var pathX: [Float] = []
    var pathY: [Float] = []
    var x: Float = 0
    var y: Float = 0
    for motion in motions {
        x += motion.dx
        y += motion.dy
        pathX.append(x)
        pathY.append(y)
    }
    let zeros = [Float](repeating: 0, count: frames.count)
    return PreparedAnalysis(
        frames: frames,
        residuals: motions.map(\.residual),
        rollMotion: zeros,
        pathX: pathX,
        pathY: pathY,
        pathRoll: zeros,
        footstepPathX: pathX,
        footstepPathY: pathY,
        footstepPathRoll: zeros,
        pathYaw: zeros,
        pathPitch: zeros,
        pathShearX: zeros,
        pathShearY: zeros,
        pathPerspectiveX: zeros,
        pathPerspectiveY: zeros,
        analysisConfidence: motions.map(\.confidence),
        warpConfidence: zeros,
        acceptedBlockCounts: [Int32](repeating: 3, count: frames.count),
        totalBlockCounts: [Int32](repeating: 3, count: frames.count),
        blurAmounts: frames.map(\.blurAmount),
        searchRadiusHitCounts: [Int32](repeating: 0, count: frames.count),
        searchRadiusTotalCounts: [Int32](repeating: 3, count: frames.count)
    )
}

func readFrames(asset plan: AssetPlan, sampleScalePercent: Double, maxFrames: Int?, progressEnabled: Bool) throws -> PreparedAnalysis {
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
    let sample = sampleSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight, scalePercent: sampleScalePercent)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw AnalyzerError("could not add AVAssetReaderTrackOutput")
    }
    reader.add(output)
    guard reader.startReading() else {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
    }
    var frames: [AnalysisFrame] = []
    var motions: [PairMotion] = []
    var previousPixels: [UInt8]?
    var firstPTS: Double?
    while reader.status == .reading {
        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            break
        }
        if let maxFrames, frames.count >= maxFrames {
            break
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            continue
        }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts.isFinite else {
            continue
        }
        if firstPTS == nil {
            firstPTS = pts
        }
        let time = max(0, pts - (firstPTS ?? pts))
        let pixels = try lumaSample(from: pixelBuffer, sampleWidth: sample.width, sampleHeight: sample.height)
        let frame = AnalysisFrame(
            time: time,
            pixels: pixels,
            sampleWidth: sample.width,
            sampleHeight: sample.height,
            blurAmount: blurAmount(pixels, width: sample.width, height: sample.height),
            fingerprint: fingerprint(for: pixels)
        )
        if let previousPixels {
            motions.append(estimateMotion(previous: previousPixels, current: pixels, width: sample.width, height: sample.height))
        } else {
            motions.append(PairMotion(dx: 0, dy: 0, residual: 0, confidence: 1))
        }
        previousPixels = pixels
        frames.append(frame)
        if frames.count % 30 == 0 {
            progress(progressEnabled, "analyzed \(frames.count) frame(s) for \(plan.name)")
        }
    }
    if reader.status == .failed {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed")
    }
    guard frames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(frames.count)")
    }
    return try prepare(frames: frames, motions: motions)
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
        frames: prepared.frames.map {
            PersistedHostAnalysisFrame(time: $0.time, pixels: nil, blurAmount: $0.blurAmount, fingerprint: $0.fingerprint)
        },
        residuals: prepared.residuals,
        rollMotion: prepared.rollMotion,
        pathX: prepared.pathX,
        pathY: prepared.pathY,
        pathRoll: prepared.pathRoll,
        footstepPathX: prepared.footstepPathX,
        footstepPathY: prepared.footstepPathY,
        footstepPathRoll: prepared.footstepPathRoll,
        pathYaw: prepared.pathYaw,
        pathPitch: prepared.pathPitch,
        pathShearX: prepared.pathShearX,
        pathShearY: prepared.pathShearY,
        pathPerspectiveX: prepared.pathPerspectiveX,
        pathPerspectiveY: prepared.pathPerspectiveY,
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

func writeCache(cacheRoot: URL, asset: AssetPlan, prepared: PreparedAnalysis, cache: PersistedHostAnalysisCache, sampleScalePercent: Double) throws -> AnalysisResult {
    let fileManager = FileManager.default
    let storageURL = cacheRoot.appendingPathComponent(cacheStorageDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    let identity = try cacheIdentity(cache: cache, frames: prepared.frames)
    let fileName = try cacheFileName(cache: cache, frames: prepared.frames)
    let encoder = JSONEncoder()
    let data = try encoder.encode(cache)
    try data.write(to: storageURL.appendingPathComponent(fileName), options: .atomic)
    try data.write(to: cacheRoot.appendingPathComponent(cacheFileName), options: .atomic)

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
        mediaPath: asset.mediaPath,
        mediaKind: asset.mediaKind,
        cacheFileName: fileName,
        cacheIdentity: identity,
        cacheSchemaVersion: cacheSchemaVersion,
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
        lastFingerprint: fp.last
    )
}

func run() throws {
    let arguments = try parseArguments()
    let planData = try Data(contentsOf: arguments.planPath)
    let plan = try JSONDecoder().decode(AnalysisPlan.self, from: planData)
    let cacheRoot = URL(fileURLWithPath: plan.cacheRoot, isDirectory: true)
    try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    var results: [AnalysisResult] = []
    for asset in plan.assets {
        progress(arguments.progress, "starting \(asset.name)")
        let prepared = try readFrames(
            asset: asset,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames,
            progressEnabled: arguments.progress
        )
        let cache = buildCache(
            asset: asset,
            eventName: plan.eventName,
            prepared: prepared,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames
        )
        let result = try writeCache(
            cacheRoot: cacheRoot,
            asset: asset,
            prepared: prepared,
            cache: cache,
            sampleScalePercent: plan.sampleScalePercent
        )
        progress(arguments.progress, "saved \(result.cacheFileName)")
        results.append(result)
    }
    let output = ToolOutput(schemaVersion: toolSchemaVersion, status: "ok", results: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(output))
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

do {
    try run()
} catch {
    let message = (error as? AnalyzerError)?.description ?? error.localizedDescription
    FileHandle.standardError.write(("StabilizerEventAnalyzer: \(message)\n").data(using: .utf8)!)
    exit(1)
}
