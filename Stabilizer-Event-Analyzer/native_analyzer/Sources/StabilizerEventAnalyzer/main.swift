import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal

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

private struct MetalLumaUniforms {
    let sourceWidth: UInt32
    let sourceHeight: UInt32
    let sampleWidth: UInt32
    let sampleHeight: UInt32
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
}

private final class MetalMotionWorkspace {
    let width: Int
    let height: Int
    let radius: Int
    let searchStep: Int
    let scoreGridWidth: Int
    let scoreCount: Int
    let blockCount: Int
    let uniformBuffer: MTLBuffer

    init(width: Int, height: Int, device: MTLDevice) throws {
        self.width = width
        self.height = height
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
        let scoreGridWidth = ((radius * 2) / searchStep) + 1
        let scoreGridHeight = scoreGridWidth
        let scoreCount = scoreGridWidth * scoreGridHeight
        let uniforms = centers.map {
            MetalBlockUniforms(
                centerX: UInt32($0.0),
                centerY: UInt32($0.1),
                blockWidth: UInt32(blockWidth),
                blockHeight: UInt32(blockHeight),
                width: UInt32(width),
                height: UInt32(height),
                radius: UInt32(radius),
                searchStep: UInt32(searchStep),
                sampleStep: UInt32(sampleStep),
                scoreGridWidth: UInt32(scoreGridWidth),
                scoreGridHeight: UInt32(scoreGridHeight)
            )
        }
        guard let uniformBuffer = device.makeBuffer(
            bytes: uniforms,
            length: MemoryLayout<MetalBlockUniforms>.stride * uniforms.count,
            options: .storageModeShared
        ) else {
            throw AnalyzerError("could not allocate reusable Metal motion search resources")
        }
        self.radius = radius
        self.searchStep = searchStep
        self.scoreGridWidth = scoreGridWidth
        self.scoreCount = scoreCount
        self.blockCount = uniforms.count
        self.uniformBuffer = uniformBuffer
    }

    func resolveMotion(scoreBuffer: MTLBuffer) -> PairMotion {
        let scores = UnsafeBufferPointer(
            start: scoreBuffer.contents().assumingMemoryBound(to: Float.self),
            count: scoreCount * blockCount
        )
        var dxValues: [Float] = []
        var dyValues: [Float] = []
        var residuals: [Float] = []
        dxValues.reserveCapacity(blockCount)
        dyValues.reserveCapacity(blockCount)
        residuals.reserveCapacity(blockCount)
        for blockIndex in 0..<blockCount {
            var bestScore = Float.greatestFiniteMagnitude
            var bestIndex = 0
            let blockOffset = blockIndex * scoreCount
            for scoreIndex in 0..<scoreCount {
                let score = scores[blockOffset + scoreIndex]
                if score < bestScore {
                    bestScore = score
                    bestIndex = scoreIndex
                }
            }
            let gx = bestIndex % scoreGridWidth
            let gy = bestIndex / scoreGridWidth
            dxValues.append(Float(-radius + gx * searchStep))
            dyValues.append(Float(-radius + gy * searchStep))
            residuals.append(bestScore)
        }
        let dx = dxValues.reduce(0, +) / Float(max(1, dxValues.count))
        let dy = dyValues.reduce(0, +) / Float(max(1, dyValues.count))
        let residual = residuals.reduce(0, +) / Float(max(1, residuals.count))
        let confidence = clamp(1.0 - (residual / 48.0), 0.05, 1.0)
        return PairMotion(dx: dx, dy: dy, residual: residual, confidence: confidence)
    }
}

private struct MetalFrameSlot {
    let lumaBuffer: MTLBuffer
    let scoreBuffer: MTLBuffer
}

private struct MetalEncodedFrame {
    let commandBuffer: MTLCommandBuffer
    let texture: CVMetalTexture
    let outputBuffer: MTLBuffer
    let scoreBuffer: MTLBuffer?
    let motionWorkspace: MetalMotionWorkspace?
}

final class MetalAnalysisContext {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let lumaPipelineState: MTLComputePipelineState
    private let blockScorePipelineState: MTLComputePipelineState
    private var motionWorkspace: MetalMotionWorkspace?

    var deviceName: String { device.name }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw AnalyzerError("Metal analysis device unavailable; Event analysis requires GPU resources")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw AnalyzerError("Metal analysis command queue unavailable")
        }
        var textureCache: CVMetalTextureCache?
        let textureCacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard textureCacheStatus == kCVReturnSuccess, let textureCache else {
            throw AnalyzerError("Metal analysis texture cache unavailable: CVMetalTextureCacheCreate returned \(textureCacheStatus)")
        }
        let library = try device.makeLibrary(source: Self.kernelSource, options: nil)
        guard let lumaFunction = library.makeFunction(name: "stabilizer_luma_sample"),
              let blockScoreFunction = library.makeFunction(name: "stabilizer_block_scores") else {
            throw AnalyzerError("Metal analysis kernels were not found")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = textureCache
        self.lumaPipelineState = try device.makeComputePipelineState(function: lumaFunction)
        self.blockScorePipelineState = try device.makeComputePipelineState(function: blockScoreFunction)
    }

    fileprivate func makeFrameSlot(pixelCount: Int, width: Int, height: Int) throws -> MetalFrameSlot {
        let workspace = try workspaceForMotion(width: width, height: height)
        guard let lumaBuffer = device.makeBuffer(length: pixelCount, options: .storageModeShared),
              let scoreBuffer = device.makeBuffer(
                length: MemoryLayout<Float>.stride * workspace.scoreCount * workspace.blockCount,
                options: .storageModeShared
              ) else {
            throw AnalyzerError("could not allocate reusable Metal frame analysis buffers")
        }
        return MetalFrameSlot(lumaBuffer: lumaBuffer, scoreBuffer: scoreBuffer)
    }

    fileprivate func encodeFrame(
        from pixelBuffer: CVPixelBuffer,
        sampleWidth: Int,
        sampleHeight: Int,
        outputBuffer: MTLBuffer,
        scoreBuffer: MTLBuffer,
        previousBuffer: MTLBuffer?
    ) throws -> MetalEncodedFrame {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let pixelCount = sampleWidth * sampleHeight
        guard outputBuffer.length >= pixelCount else {
            throw AnalyzerError("reusable Metal luma output buffer was too small")
        }
        var cvTexture: CVMetalTexture?
        let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
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
            sampleHeight: UInt32(sampleHeight)
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

        let activeMotionWorkspace: MetalMotionWorkspace?
        if let previousBuffer {
            let workspace = try workspaceForMotion(width: sampleWidth, height: sampleHeight)
            guard let motionEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw AnalyzerError("could not allocate Metal block motion encoder")
            }
            motionEncoder.setComputePipelineState(blockScorePipelineState)
            motionEncoder.setBuffer(previousBuffer, offset: 0, index: 0)
            motionEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
            motionEncoder.setBuffer(scoreBuffer, offset: 0, index: 2)
            motionEncoder.setBuffer(workspace.uniformBuffer, offset: 0, index: 3)
            motionEncoder.dispatchThreads(
                MTLSize(width: workspace.scoreCount, height: workspace.blockCount, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(64, workspace.scoreCount), height: 1, depth: 1)
            )
            motionEncoder.endEncoding()
            activeMotionWorkspace = workspace
        } else {
            activeMotionWorkspace = nil
        }

        commandBuffer.commit()
        return MetalEncodedFrame(
            commandBuffer: commandBuffer,
            texture: cvTexture,
            outputBuffer: outputBuffer,
            scoreBuffer: previousBuffer == nil ? nil : scoreBuffer,
            motionWorkspace: activeMotionWorkspace
        )
    }

    fileprivate func completeFrame(_ encodedFrame: MetalEncodedFrame, pixelCount: Int) throws -> (pixels: [UInt8], motion: PairMotion?) {
        encodedFrame.commandBuffer.waitUntilCompleted()
        CVMetalTextureCacheFlush(textureCache, 0)
        try Self.validate(commandBuffer: encodedFrame.commandBuffer, stage: encodedFrame.motionWorkspace == nil ? "luma sampling" : "luma sampling and block motion search")
        let pixels = [UInt8](UnsafeBufferPointer(
            start: encodedFrame.outputBuffer.contents().assumingMemoryBound(to: UInt8.self),
            count: pixelCount
        ))
        let motion: PairMotion?
        if let motionWorkspace = encodedFrame.motionWorkspace,
           let scoreBuffer = encodedFrame.scoreBuffer {
            motion = motionWorkspace.resolveMotion(scoreBuffer: scoreBuffer)
        } else {
            motion = nil
        }
        return (pixels, motion)
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

    private static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LumaUniforms {
        uint sourceWidth;
        uint sourceHeight;
        uint bytesPerRow;
        uint sampleWidth;
        uint sampleHeight;
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
    };

    kernel void stabilizer_luma_sample(
        texture2d<float, access::read> source [[texture(0)]],
        device uchar *output [[buffer(0)]],
        constant LumaUniforms &uniforms [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uniforms.sampleWidth || gid.y >= uniforms.sampleHeight) {
            return;
        }
        uint sx = min(uniforms.sourceWidth - 1, uint((float(gid.x) + 0.5f) * float(uniforms.sourceWidth) / float(uniforms.sampleWidth)));
        uint sy = min(uniforms.sourceHeight - 1, uint((float(gid.y) + 0.5f) * float(uniforms.sourceHeight) / float(uniforms.sampleHeight)));
        float4 color = source.read(uint2(sx, sy));
        output[(gid.y * uniforms.sampleWidth) + gid.x] = uchar(clamp(int(round(((0.299f * color.b) + (0.587f * color.g) + (0.114f * color.r)) * 255.0f)), 0, 255));
    }

    kernel void stabilizer_block_scores(
        device const uchar *previous [[buffer(0)]],
        device const uchar *current [[buffer(1)]],
        device float *scores [[buffer(2)]],
        device const BlockUniforms *uniformsList [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        BlockUniforms uniforms = uniformsList[gid.y];
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        if (gid.x >= scoreCount || gid.y >= 3) {
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
        float total = 0.0f;
        uint count = 0;
        for (int y = y0; y <= y1; y += int(uniforms.sampleStep)) {
            int cy = y + dy;
            if (cy < 0 || cy >= int(uniforms.height)) {
                continue;
            }
            for (int x = x0; x <= x1; x += int(uniforms.sampleStep)) {
                int cx = x + dx;
                if (cx < 0 || cx >= int(uniforms.width)) {
                    continue;
                }
                uint previousIndex = uint(y) * uniforms.width + uint(x);
                uint currentIndex = uint(cy) * uniforms.width + uint(cx);
                total += float(abs(int(previous[previousIndex]) - int(current[currentIndex])));
                count += 1;
            }
        }
        scores[(gid.y * scoreCount) + gid.x] = count > 0 ? total / float(count) : FLT_MAX;
    }
    """
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

func readFrames(
    asset plan: AssetPlan,
    sampleScalePercent: Double,
    maxFrames: Int?,
    progressEnabled: Bool,
    metalContext: MetalAnalysisContext
) throws -> PreparedAnalysis {
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
    let pixelCount = sample.width * sample.height
    let inFlightLimit = 8
    let frameSlots = try (0..<inFlightLimit).map { _ in
        try metalContext.makeFrameSlot(pixelCount: pixelCount, width: sample.width, height: sample.height)
    }
    var currentFrameSlotIndex = 0
    var previousLumaBuffer: MTLBuffer?
    var firstPTS: Double?
    var pendingFrames: [(encoded: MetalEncodedFrame, time: Double)] = []
    pendingFrames.reserveCapacity(inFlightLimit)

    func finishOldestPendingFrame() throws {
        let pending = pendingFrames.removeFirst()
        let frameAnalysis = try metalContext.completeFrame(pending.encoded, pixelCount: pixelCount)
        let pixels = frameAnalysis.pixels
        let frame = AnalysisFrame(
            time: pending.time,
            pixels: [],
            sampleWidth: sample.width,
            sampleHeight: sample.height,
            blurAmount: blurAmount(pixels, width: sample.width, height: sample.height),
            fingerprint: fingerprint(for: pixels)
        )
        motions.append(frameAnalysis.motion ?? PairMotion(dx: 0, dy: 0, residual: 0, confidence: 1))
        frames.append(frame)
        if frames.count % 30 == 0 {
            progress(progressEnabled, "analyzed \(frames.count) frame(s) for \(plan.name)")
        }
    }

    while reader.status == .reading {
        if pendingFrames.count >= inFlightLimit {
            try finishOldestPendingFrame()
        }
        let shouldContinue = try autoreleasepool {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                return false
            }
            if let maxFrames, frames.count + pendingFrames.count >= maxFrames {
                return false
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return true
            }
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard pts.isFinite else {
                return true
            }
            if firstPTS == nil {
                firstPTS = pts
            }
            let time = max(0, pts - (firstPTS ?? pts))
            let currentFrameSlot = frameSlots[currentFrameSlotIndex]
            let encodedFrame = try metalContext.encodeFrame(
                from: pixelBuffer,
                sampleWidth: sample.width,
                sampleHeight: sample.height,
                outputBuffer: currentFrameSlot.lumaBuffer,
                scoreBuffer: currentFrameSlot.scoreBuffer,
                previousBuffer: previousLumaBuffer
            )
            pendingFrames.append((encoded: encodedFrame, time: time))
            previousLumaBuffer = currentFrameSlot.lumaBuffer
            currentFrameSlotIndex = (currentFrameSlotIndex + 1) % frameSlots.count
            return true
        }
        if !shouldContinue {
            break
        }
    }
    while !pendingFrames.isEmpty {
        try finishOldestPendingFrame()
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
    let metalContext = try MetalAnalysisContext()
    progress(arguments.progress, "using Metal analyzer device: \(metalContext.deviceName)")
    var results: [AnalysisResult] = []
    for asset in plan.assets {
        progress(arguments.progress, "starting \(asset.name)")
        let prepared = try readFrames(
            asset: asset,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames,
            progressEnabled: arguments.progress,
            metalContext: metalContext
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
