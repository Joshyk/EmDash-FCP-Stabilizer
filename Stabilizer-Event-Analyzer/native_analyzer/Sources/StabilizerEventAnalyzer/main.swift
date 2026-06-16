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
    let chunkCount: UInt32
}

private struct MetalShiftResult {
    let dx: Float
    let dy: Float
    let score: Float
    let bestIndex: UInt32
}

private final class MetalMotionWorkspace {
    let width: Int
    let height: Int
    let radius: Int
    let searchStep: Int
    let scoreGridWidth: Int
    let scoreCount: Int
    let blockCount: Int
    let chunkCount: Int
    let uniformBuffer: MTLBuffer

    init(width: Int, height: Int, device: MTLDevice) throws {
        self.width = width
        self.height = height
        let radius = min(24, max(4, min(width, height) / 64))
        let searchStep = width > 1400 || height > 900 ? 2 : 1
        let blockWidth = max(32, width / 4)
        let blockHeight = max(24, height / 5)
        let sampleStep = max(1, min(blockWidth, blockHeight) / 56)
        let sampleColumns = max(1, (blockWidth / sampleStep) + 1)
        let sampleRows = max(1, (blockHeight / sampleStep) + 1)
        let chunkCount = max(4, min(32, (sampleColumns * sampleRows + 511) / 512))
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
                scoreGridHeight: UInt32(scoreGridHeight),
                chunkCount: UInt32(chunkCount)
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
        self.chunkCount = chunkCount
        self.uniformBuffer = uniformBuffer
    }

    var partialElementCount: Int {
        scoreCount * blockCount * chunkCount
    }

    func resolveMotion(resultBuffer: MTLBuffer) -> PairMotion {
        let results = UnsafeBufferPointer(
            start: resultBuffer.contents().assumingMemoryBound(to: MetalShiftResult.self),
            count: blockCount
        )
        var dxValues: [Float] = []
        var dyValues: [Float] = []
        var residuals: [Float] = []
        dxValues.reserveCapacity(blockCount)
        dyValues.reserveCapacity(blockCount)
        residuals.reserveCapacity(blockCount)
        for result in results {
            dxValues.append(result.dx)
            dyValues.append(result.dy)
            residuals.append(result.score)
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
    let partialSumBuffer: MTLBuffer
    let partialCountBuffer: MTLBuffer
    let resultBuffer: MTLBuffer
}

private struct MetalEncodedFrame {
    let commandBuffer: MTLCommandBuffer
    let texture: CVMetalTexture
    let outputBuffer: MTLBuffer
    let resultBuffer: MTLBuffer?
    let motionWorkspace: MetalMotionWorkspace?
}

final class MetalAnalysisContext {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache
    private let lumaPipelineState: MTLComputePipelineState
    private let blockScorePartialPipelineState: MTLComputePipelineState
    private let blockScoreResolvePipelineState: MTLComputePipelineState
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
              let blockScorePartialFunction = library.makeFunction(name: "stabilizer_block_score_partials"),
              let blockScoreResolveFunction = library.makeFunction(name: "stabilizer_block_score_resolve") else {
            throw AnalyzerError("Metal analysis kernels were not found")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = textureCache
        self.lumaPipelineState = try device.makeComputePipelineState(function: lumaFunction)
        self.blockScorePartialPipelineState = try device.makeComputePipelineState(function: blockScorePartialFunction)
        self.blockScoreResolvePipelineState = try device.makeComputePipelineState(function: blockScoreResolveFunction)
    }

    fileprivate func makeFrameSlot(pixelCount: Int, width: Int, height: Int) throws -> MetalFrameSlot {
        let workspace = try workspaceForMotion(width: width, height: height)
        guard let lumaBuffer = device.makeBuffer(length: pixelCount, options: .storageModeShared),
              let partialSumBuffer = device.makeBuffer(
                length: MemoryLayout<UInt32>.stride * workspace.partialElementCount,
                options: .storageModeShared
              ),
              let partialCountBuffer = device.makeBuffer(
                length: MemoryLayout<UInt32>.stride * workspace.partialElementCount,
                options: .storageModeShared
              ),
              let resultBuffer = device.makeBuffer(
                length: MemoryLayout<MetalShiftResult>.stride * workspace.blockCount,
                options: .storageModeShared
              ) else {
            throw AnalyzerError("could not allocate reusable Metal frame analysis buffers")
        }
        return MetalFrameSlot(
            lumaBuffer: lumaBuffer,
            partialSumBuffer: partialSumBuffer,
            partialCountBuffer: partialCountBuffer,
            resultBuffer: resultBuffer
        )
    }

    fileprivate func encodeFrame(
        from pixelBuffer: CVPixelBuffer,
        sampleWidth: Int,
        sampleHeight: Int,
        outputBuffer: MTLBuffer,
        partialSumBuffer: MTLBuffer,
        partialCountBuffer: MTLBuffer,
        resultBuffer: MTLBuffer,
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
            motionEncoder.setComputePipelineState(blockScorePartialPipelineState)
            motionEncoder.setBuffer(previousBuffer, offset: 0, index: 0)
            motionEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
            motionEncoder.setBuffer(partialSumBuffer, offset: 0, index: 2)
            motionEncoder.setBuffer(partialCountBuffer, offset: 0, index: 3)
            motionEncoder.setBuffer(workspace.uniformBuffer, offset: 0, index: 4)
            motionEncoder.dispatchThreads(
                MTLSize(width: workspace.scoreCount, height: workspace.blockCount, depth: workspace.chunkCount),
                threadsPerThreadgroup: MTLSize(width: min(64, workspace.scoreCount), height: 1, depth: 1)
            )
            motionEncoder.endEncoding()

            guard let resolveEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw AnalyzerError("could not allocate Metal block motion resolve encoder")
            }
            var chunkCount = UInt32(workspace.chunkCount)
            resolveEncoder.setComputePipelineState(blockScoreResolvePipelineState)
            resolveEncoder.setBuffer(partialSumBuffer, offset: 0, index: 0)
            resolveEncoder.setBuffer(partialCountBuffer, offset: 0, index: 1)
            resolveEncoder.setBuffer(resultBuffer, offset: 0, index: 2)
            resolveEncoder.setBuffer(workspace.uniformBuffer, offset: 0, index: 3)
            resolveEncoder.setBytes(&chunkCount, length: MemoryLayout<UInt32>.stride, index: 4)
            resolveEncoder.dispatchThreads(
                MTLSize(width: workspace.blockCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(32, workspace.blockCount), height: 1, depth: 1)
            )
            resolveEncoder.endEncoding()
            activeMotionWorkspace = workspace
        } else {
            activeMotionWorkspace = nil
        }

        commandBuffer.commit()
        return MetalEncodedFrame(
            commandBuffer: commandBuffer,
            texture: cvTexture,
            outputBuffer: outputBuffer,
            resultBuffer: previousBuffer == nil ? nil : resultBuffer,
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
           let resultBuffer = encodedFrame.resultBuffer {
            motion = motionWorkspace.resolveMotion(resultBuffer: resultBuffer)
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
        uint chunkCount;
    };

    struct ShiftResult {
        float dx;
        float dy;
        float score;
        uint bestIndex;
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

    kernel void stabilizer_block_score_partials(
        device const uchar *previous [[buffer(0)]],
        device const uchar *current [[buffer(1)]],
        device uint *partialSums [[buffer(2)]],
        device uint *partialCounts [[buffer(3)]],
        device const BlockUniforms *uniformsList [[buffer(4)]],
        uint3 gid [[thread_position_in_grid]]
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
        if (gid >= 3) {
            return;
        }
        BlockUniforms uniforms = uniformsList[gid];
        uint scoreCount = uniforms.scoreGridWidth * uniforms.scoreGridHeight;
        float bestScore = FLT_MAX;
        uint bestIndex = 0;
        for (uint scoreIndex = 0; scoreIndex < scoreCount; scoreIndex += 1) {
            uint total = 0;
            uint count = 0;
            uint base = ((gid * scoreCount) + scoreIndex) * chunkCount;
            for (uint chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
                total += partialSums[base + chunkIndex];
                count += partialCounts[base + chunkIndex];
            }
            float score = count > 0 ? float(total) / float(count) : FLT_MAX;
            if (score < bestScore) {
                bestScore = score;
                bestIndex = scoreIndex;
            }
        }
        uint gx = bestIndex % uniforms.scoreGridWidth;
        uint gy = bestIndex / uniforms.scoreGridWidth;
        results[gid].dx = float(-int(uniforms.radius) + int(gx * uniforms.searchStep));
        results[gid].dy = float(-int(uniforms.radius) + int(gy * uniforms.searchStep));
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
}

private func analyzerWorkerCount(explicitOnly: Bool = false) -> Int {
    if let value = ProcessInfo.processInfo.environment["STABILIZER_ANALYZER_WORKERS"],
       let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return max(1, min(12, parsed))
    }
    if explicitOnly { return 1 }
    let processorCount = ProcessInfo.processInfo.activeProcessorCount
    return max(1, min(6, processorCount > 2 ? processorCount - 2 : processorCount))
}

private func shouldUseParallelReaders(plan: AssetPlan, maxFrames: Int?, workerCount: Int) -> Bool {
    if maxFrames != nil || workerCount <= 1 {
        return false
    }
    if ProcessInfo.processInfo.environment["STABILIZER_ANALYZER_WORKERS"] != nil {
        return plan.durationSeconds > max(0.5, plan.frameDurationSeconds * 4.0)
    }
    return plan.durationSeconds >= 12.0
}

private func makeFrameReadChunks(durationSeconds: Double, frameDurationSeconds: Double, workerCount: Int) -> [FrameReadChunk] {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    let chunkCount = max(1, workerCount)
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
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw AnalyzerError("could not add AVAssetReaderTrackOutput")
    }
    reader.add(output)
    guard reader.startReading() else {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
    }
    guard let sampleBuffer = output.copyNextSampleBuffer() else {
        throw AnalyzerError("asset had no readable video frames: \(url.path)")
    }
    let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    guard pts.isFinite else {
        throw AnalyzerError("asset first video frame had non-finite presentation time: \(url.path)")
    }
    return pts
}

private func readFrameChunk(
    url: URL,
    planName: String,
    sample: AnalysisSampleSize,
    chunk: FrameReadChunk,
    basePresentationTimeSeconds: Double?,
    maxFrames: Int?,
    progressEnabled: Bool,
    progressEvery: Int,
    metalContext: MetalAnalysisContext
) throws -> FrameChunkResult {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw AnalyzerError("asset had no video track: \(url.path)")
    }
    let reader = try AVAssetReader(asset: asset)
    if let readStartSeconds = chunk.readStartSeconds,
       let readEndSeconds = chunk.readEndSeconds {
        let baseSeconds = basePresentationTimeSeconds ?? 0.0
        let start = CMTime(seconds: baseSeconds + readStartSeconds, preferredTimescale: 600_000)
        let duration = CMTime(seconds: max(0.0, readEndSeconds - readStartSeconds), preferredTimescale: 600_000)
        reader.timeRange = CMTimeRange(start: start, duration: duration)
    }
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
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
    var firstPTS = basePresentationTimeSeconds
    var sawOutputFrame = false
    let frameTimeEpsilon = 1.0 / 600_000.0
    var pendingFrames: [(encoded: MetalEncodedFrame, time: Double, shouldOutput: Bool)] = []
    pendingFrames.reserveCapacity(inFlightLimit)

    func pendingOutputFrameCount() -> Int {
        pendingFrames.reduce(0) { count, pending in
            count + (pending.shouldOutput ? 1 : 0)
        }
    }

    func finishOldestPendingFrame() throws {
        let pending = pendingFrames.removeFirst()
        let frameAnalysis = try metalContext.completeFrame(pending.encoded, pixelCount: pixelCount)
        guard pending.shouldOutput else {
            return
        }
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
        if progressEvery > 0 && frames.count % progressEvery == 0 {
            progress(progressEnabled, "analyzed \(frames.count) frame(s) for \(planName)")
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
            if let maxFrames, frames.count + pendingOutputFrameCount() >= maxFrames {
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
            if !chunk.isLast && time >= chunk.outputEndSeconds - frameTimeEpsilon {
                return false
            }
            let shouldOutput = time + frameTimeEpsilon >= chunk.outputStartSeconds
                && (chunk.isLast || time < chunk.outputEndSeconds - frameTimeEpsilon)
            if shouldOutput && chunk.requiresPreviousFrame && !sawOutputFrame && previousLumaBuffer == nil {
                throw AnalyzerError("parallel reader chunk \(chunk.index + 1) for \(planName) did not receive the required overlap frame")
            }
            let currentFrameSlot = frameSlots[currentFrameSlotIndex]
            let encodedFrame = try metalContext.encodeFrame(
                from: pixelBuffer,
                sampleWidth: sample.width,
                sampleHeight: sample.height,
                outputBuffer: currentFrameSlot.lumaBuffer,
                partialSumBuffer: currentFrameSlot.partialSumBuffer,
                partialCountBuffer: currentFrameSlot.partialCountBuffer,
                resultBuffer: currentFrameSlot.resultBuffer,
                previousBuffer: shouldOutput ? previousLumaBuffer : nil
            )
            pendingFrames.append((encoded: encodedFrame, time: time, shouldOutput: shouldOutput))
            previousLumaBuffer = currentFrameSlot.lumaBuffer
            currentFrameSlotIndex = (currentFrameSlotIndex + 1) % frameSlots.count
            if shouldOutput {
                sawOutputFrame = true
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
    if reader.status == .failed {
        throw AnalyzerError(reader.error?.localizedDescription ?? "AVAssetReader failed")
    }
    return FrameChunkResult(index: chunk.index, frames: frames, motions: motions)
}

private func readFramesInParallel(
    url: URL,
    plan: AssetPlan,
    sample: AnalysisSampleSize,
    workerCount: Int,
    progressEnabled: Bool
) throws -> PreparedAnalysis {
    let chunks = makeFrameReadChunks(
        durationSeconds: plan.durationSeconds,
        frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
        workerCount: workerCount
    )
    let basePTS = try firstPresentationTimeSeconds(url: url)
    progress(progressEnabled, "using \(chunks.count) parallel media reader(s) for \(plan.name)")
    let resultLock = NSLock()
    let group = DispatchGroup()
    var results = Array<FrameChunkResult?>(repeating: nil, count: chunks.count)
    var firstError: Error?
    for chunk in chunks {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                let context = try MetalAnalysisContext()
                let result = try readFrameChunk(
                    url: url,
                    planName: plan.name,
                    sample: sample,
                    chunk: chunk,
                    basePresentationTimeSeconds: basePTS,
                    maxFrames: nil,
                    progressEnabled: false,
                    progressEvery: 0,
                    metalContext: context
                )
                resultLock.lock()
                results[chunk.index] = result
                resultLock.unlock()
                progress(progressEnabled, "analyzed chunk \(chunk.index + 1)/\(chunk.totalCount) for \(plan.name) (\(result.frames.count) frame(s))")
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
    var combinedFrames: [AnalysisFrame] = []
    var combinedMotions: [PairMotion] = []
    for index in 0..<results.count {
        guard let result = results[index] else {
            throw AnalyzerError("parallel reader chunk \(index + 1) did not produce a result")
        }
        combinedFrames.append(contentsOf: result.frames)
        combinedMotions.append(contentsOf: result.motions)
    }
    let ordered = zip(combinedFrames, combinedMotions).sorted { lhs, rhs in
        lhs.0.time < rhs.0.time
    }
    let frames = ordered.map(\.0)
    let motions = ordered.map(\.1)
    guard frames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(frames.count)")
    }
    return try prepare(frames: frames, motions: motions)
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
    let size = sampleSize(sourceWidth: sourceWidth, sourceHeight: sourceHeight, scalePercent: sampleScalePercent)
    let sample = AnalysisSampleSize(width: size.width, height: size.height)
    let workerCount = analyzerWorkerCount()
    if shouldUseParallelReaders(plan: plan, maxFrames: maxFrames, workerCount: workerCount) {
        return try readFramesInParallel(
            url: url,
            plan: plan,
            sample: sample,
            workerCount: workerCount,
            progressEnabled: progressEnabled
        )
    }
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
    let result = try readFrameChunk(
        url: url,
        planName: plan.name,
        sample: sample,
        chunk: serialChunk,
        basePresentationTimeSeconds: nil,
        maxFrames: maxFrames,
        progressEnabled: progressEnabled,
        progressEvery: 30,
        metalContext: metalContext
    )
    guard result.frames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(result.frames.count)")
    }
    return try prepare(frames: result.frames, motions: result.motions)
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
