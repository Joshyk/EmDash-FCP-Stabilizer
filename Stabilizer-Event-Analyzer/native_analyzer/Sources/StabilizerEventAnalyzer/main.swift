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
private let analyzerVideoOutputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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

private struct FrameMetrics {
    let blurAmount: Float
    let fingerprint: String
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
    if progressLineActive {
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
    private var lastPublishedFrameCount = 0

    init(enabled: Bool, label: String, totalFrameCount: Int) {
        self.enabled = enabled
        self.label = label
        self.totalFrameCount = max(1, totalFrameCount)
        self.publishEveryFrameCount = max(1, totalFrameCount / 100)
    }

    func completeFrame() {
        publishAfterAddingFrameCount(1, force: false)
    }

    func finish() {
        publishAfterAddingFrameCount(0, force: true)
    }

    private func publishAfterAddingFrameCount(_ frameCount: Int, force: Bool) {
        guard enabled else {
            return
        }
        let message: String?
        lock.lock()
        completedFrameCount += frameCount
        let shouldPublish = force
            || completedFrameCount >= totalFrameCount
            || completedFrameCount - lastPublishedFrameCount >= publishEveryFrameCount
        if shouldPublish && completedFrameCount != lastPublishedFrameCount {
            lastPublishedFrameCount = completedFrameCount
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
        let fps = Double(completedFrameCount) / elapsedSeconds
        let percent = min(100.0, (Double(completedFrameCount) / Double(totalFrameCount)) * 100.0)
        return String(
            format: "progress %@: %d/%d frame(s) (%.1f%%, %.1f fps)",
            label,
            completedFrameCount,
            totalFrameCount,
            percent,
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

func fingerprint(_ pixels: UnsafePointer<UInt8>, byteCount: Int) -> String {
    var hash = fingerprintInitialHash
    for index in 0..<byteCount {
        combineFingerprintByte(pixels[index], into: &hash)
    }
    return fingerprintString(hash: hash, byteCount: byteCount)
}

func blurAmount(_ pixels: UnsafePointer<UInt8>, width: Int, height: Int) -> Float {
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

private func frameMetrics(_ pixels: UnsafePointer<UInt8>, byteCount: Int, width: Int, height: Int) -> FrameMetrics {
    FrameMetrics(
        blurAmount: blurAmount(pixels, width: width, height: height),
        fingerprint: fingerprint(pixels, byteCount: byteCount)
    )
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
        let chunkCount = max(8, min(128, (sampleColumns * sampleRows + 255) / 256))
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
    // Retain the heap for the lifetime of buffers allocated from it.
    let heap: MTLHeap
    let lumaBuffer: MTLBuffer
    let partialSumBuffer: MTLBuffer
    let partialCountBuffer: MTLBuffer
    let resultBuffer: MTLBuffer
}

private struct MetalEncodedFrame {
    let commandBuffer: MTLCommandBuffer
    let outputBuffer: MTLBuffer
    let resultBuffer: MTLBuffer?
    let motionWorkspace: MetalMotionWorkspace?
}

private final class MetalAnalysisSharedState {
    fileprivate static let sharedResult: Result<MetalAnalysisSharedState, Error> = Result {
        try MetalAnalysisSharedState()
    }

    let device: MTLDevice
    let lumaPipelineState: MTLComputePipelineState
    let blockScorePartialPipelineState: MTLComputePipelineState
    let blockScoreResolvePipelineState: MTLComputePipelineState

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw AnalyzerError("Metal analysis device unavailable; Event analysis requires GPU resources")
        }
        let library = try device.makeLibrary(source: MetalAnalysisContext.kernelSource, options: nil)
        guard let lumaFunction = library.makeFunction(name: "stabilizer_luma_sample"),
              let blockScorePartialFunction = library.makeFunction(name: "stabilizer_block_score_partials"),
              let blockScoreResolveFunction = library.makeFunction(name: "stabilizer_block_score_resolve") else {
            throw AnalyzerError("Metal analysis kernels were not found")
        }
        self.device = device
        self.lumaPipelineState = try device.makeComputePipelineState(function: lumaFunction)
        self.blockScorePartialPipelineState = try device.makeComputePipelineState(function: blockScorePartialFunction)
        self.blockScoreResolvePipelineState = try device.makeComputePipelineState(function: blockScoreResolveFunction)
    }
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
        self.blockScorePartialPipelineState = sharedState.blockScorePartialPipelineState
        self.blockScoreResolvePipelineState = sharedState.blockScoreResolvePipelineState
    }

    fileprivate func makeFrameSlots(count: Int, pixelCount: Int, width: Int, height: Int) throws -> [MetalFrameSlot] {
        let workspace = try workspaceForMotion(width: width, height: height)
        let lumaLength = pixelCount
        let partialLength = MemoryLayout<UInt32>.stride * workspace.partialElementCount
        let resultLength = MemoryLayout<MetalShiftResult>.stride * workspace.blockCount
        let options: MTLResourceOptions = .storageModeShared
        let slotHeapSize = alignedHeapBufferSize(length: lumaLength, options: options)
            + alignedHeapBufferSize(length: partialLength, options: options)
            + alignedHeapBufferSize(length: partialLength, options: options)
            + alignedHeapBufferSize(length: resultLength, options: options)
        let heapDescriptor = MTLHeapDescriptor()
        heapDescriptor.storageMode = .shared
        heapDescriptor.hazardTrackingMode = .tracked
        heapDescriptor.size = slotHeapSize * count
        guard let heap = device.makeHeap(descriptor: heapDescriptor) else {
            throw AnalyzerError("could not allocate Metal analysis heap for \(count) in-flight frame slots")
        }
        var slots: [MetalFrameSlot] = []
        slots.reserveCapacity(count)
        for _ in 0..<count {
            guard let lumaBuffer = heap.makeBuffer(length: lumaLength, options: options),
                  let partialSumBuffer = heap.makeBuffer(length: partialLength, options: options),
                  let partialCountBuffer = heap.makeBuffer(length: partialLength, options: options),
                  let resultBuffer = heap.makeBuffer(length: resultLength, options: options) else {
                throw AnalyzerError("could not allocate reusable Metal frame analysis buffers from heap")
            }
            slots.append(MetalFrameSlot(
                heap: heap,
                lumaBuffer: lumaBuffer,
                partialSumBuffer: partialSumBuffer,
                partialCountBuffer: partialCountBuffer,
                resultBuffer: resultBuffer
            ))
        }
        return slots
    }

    private func alignedHeapBufferSize(length: Int, options: MTLResourceOptions) -> Int {
        let sizeAndAlign = device.heapBufferSizeAndAlign(length: length, options: options)
        let alignment = max(1, sizeAndAlign.align)
        return ((sizeAndAlign.size + alignment - 1) / alignment) * alignment
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
            outputBuffer: outputBuffer,
            resultBuffer: previousBuffer == nil ? nil : resultBuffer,
            motionWorkspace: activeMotionWorkspace
        )
    }

    fileprivate func completeFrame(
        _ encodedFrame: MetalEncodedFrame,
        pixelCount: Int,
        sampleWidth: Int,
        sampleHeight: Int
    ) throws -> (metrics: FrameMetrics, motion: PairMotion?) {
        encodedFrame.commandBuffer.waitUntilCompleted()
        try Self.validate(commandBuffer: encodedFrame.commandBuffer, stage: encodedFrame.motionWorkspace == nil ? "luma sampling" : "luma sampling and block motion search")
        let pixels = encodedFrame.outputBuffer.contents().assumingMemoryBound(to: UInt8.self)
        let metrics = frameMetrics(pixels, byteCount: pixelCount, width: sampleWidth, height: sampleHeight)
        let motion: PairMotion?
        if let motionWorkspace = encodedFrame.motionWorkspace,
           let resultBuffer = encodedFrame.resultBuffer {
            motion = motionWorkspace.resolveMotion(resultBuffer: resultBuffer)
        } else {
            motion = nil
        }
        return (metrics, motion)
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

    fileprivate static let kernelSource = """
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

private func analyzerOfferedProcessorCount() -> Int {
    max(1, ProcessInfo.processInfo.activeProcessorCount)
}

private func analyzerPhysicalMemoryGB() -> UInt64 {
    max(1, ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
}

private func analyzerWorkerCount(explicitOnly: Bool = false) -> Int {
    let offeredProcessorCount = analyzerOfferedProcessorCount()
    if let value = ProcessInfo.processInfo.environment["STABILIZER_ANALYZER_WORKERS"],
       let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return max(1, min(offeredProcessorCount, parsed))
    }
    if explicitOnly { return 1 }
    let memoryGB = analyzerPhysicalMemoryGB()
    if memoryGB <= 18 {
        return 1
    }
    if memoryGB <= 36 {
        return max(1, min(4, max(1, offeredProcessorCount / 2)))
    }
    return max(1, min(6, max(1, offeredProcessorCount / 2)))
}

private func analyzerInFlightLimit(pixelCount: Int, readerLaneCount: Int) -> Int {
    let laneCount = max(1, readerLaneCount)
    let bytesPerFrameSlot = max(4 * 1024 * 1024, pixelCount * 6)
    let memoryGB = analyzerPhysicalMemoryGB()
    let memoryDivisor: UInt64 = memoryGB <= 18 ? 24 : 16
    let memoryBudget = max(bytesPerFrameSlot * laneCount * 2, Int(ProcessInfo.processInfo.physicalMemory / memoryDivisor))
    let memoryLimitedTotalSlotCount = max(laneCount * 2, memoryBudget / bytesPerFrameSlot)
    let memoryLimitedSlotCountPerLane = max(2, memoryLimitedTotalSlotCount / laneCount)
    if let value = ProcessInfo.processInfo.environment["STABILIZER_ANALYZER_IN_FLIGHT"],
       let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return max(2, min(memoryLimitedSlotCountPerLane, parsed))
    }
    let defaultSlotCountPerLane = memoryGB <= 18 ? 2 : 6
    let gpuBalancedTotalSlotCount = laneCount * defaultSlotCountPerLane
    let totalSlotCount = min(memoryLimitedTotalSlotCount, gpuBalancedTotalSlotCount)
    return max(2, totalSlotCount / laneCount)
}

private func shouldUseParallelReaders(plan: AssetPlan, maxFrames: Int?, workerCount: Int) -> Bool {
    if maxFrames != nil || workerCount <= 1 {
        return false
    }
    return plan.durationSeconds > max(0.10, plan.frameDurationSeconds * 4.0)
}

private func estimatedFrameCount(durationSeconds: Double, frameDurationSeconds: Double, maxFrames: Int? = nil) -> Int {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    let frameCount = max(1, Int((boundedDuration / max(1e-9, frameDurationSeconds)).rounded(.up)))
    if let maxFrames {
        return min(maxFrames, frameCount)
    }
    return frameCount
}

private func makeFrameReadChunks(durationSeconds: Double, frameDurationSeconds: Double, workerCount: Int) -> [FrameReadChunk] {
    let boundedDuration = max(frameDurationSeconds, durationSeconds)
    let chunkCount = max(1, min(workerCount, estimatedFrameCount(durationSeconds: durationSeconds, frameDurationSeconds: frameDurationSeconds)))
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
        outputSettings: analyzerVideoOutputSettings
    )
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
    progressReporter: AnalyzerFrameProgressReporter?,
    inFlightLimit: Int,
    expectedOutputFrameCount: Int,
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
        outputSettings: analyzerVideoOutputSettings
    )
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

    func pendingOutputFrameCount() -> Int {
        pendingFrames.reduce(0) { count, pending in
            count + (pending.shouldOutput ? 1 : 0)
        }
    }

    func finishOldestPendingFrame() throws {
        let pending = pendingFrames.removeFirst()
        let frameAnalysis = try metalContext.completeFrame(
            pending.encoded,
            pixelCount: pixelCount,
            sampleWidth: sample.width,
            sampleHeight: sample.height
        )
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
        motions.append(frameAnalysis.motion ?? PairMotion(dx: 0, dy: 0, residual: 0, confidence: 1))
        frames.append(frame)
        if let progressReporter {
            progressReporter.completeFrame()
        } else if progressEvery > 0 && frames.count % progressEvery == 0 {
            progressUpdate(progressEnabled, "progress \(planName): \(frames.count) frame(s)")
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
    let inFlightLimit = analyzerInFlightLimit(pixelCount: sample.width * sample.height, readerLaneCount: chunks.count)
    progress(progressEnabled, "using \(chunks.count) GPU-fed media reader lane(s) with \(inFlightLimit) in-flight GPU frame slot(s) each (\(chunks.count * inFlightLimit) total) for \(plan.name)")
    let progressReporter = AnalyzerFrameProgressReporter(
        enabled: progressEnabled,
        label: plan.name,
        totalFrameCount: estimatedFrameCount(
            durationSeconds: plan.durationSeconds,
            frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0
        )
    )
    let resultLock = NSLock()
    let group = DispatchGroup()
    var results = Array<FrameChunkResult?>(repeating: nil, count: chunks.count)
    var firstError: Error?
    for chunk in chunks {
        let expectedOutputFrameCount = estimatedFrameCount(
            durationSeconds: max(
                plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
                chunk.outputEndSeconds - chunk.outputStartSeconds
            ),
            frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0
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
                    chunk: chunk,
                    basePresentationTimeSeconds: basePTS,
                    maxFrames: nil,
                    progressEnabled: false,
                    progressEvery: 0,
                    progressReporter: progressReporter,
                    inFlightLimit: inFlightLimit,
                    expectedOutputFrameCount: expectedOutputFrameCount,
                    metalContext: context
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
        results[index] = nil
    }
    guard combinedFrames.count >= 3 else {
        throw AnalyzerError("analysis requires at least 3 frames; got \(combinedFrames.count)")
    }
    return try prepare(frames: combinedFrames, motions: combinedMotions)
}

func readFrames(
    asset plan: AssetPlan,
    sampleScalePercent: Double,
    maxFrames: Int?,
    progressEnabled: Bool,
    metalContext: MetalAnalysisContext,
    allowParallelReaders: Bool
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
    if allowParallelReaders && shouldUseParallelReaders(plan: plan, maxFrames: maxFrames, workerCount: workerCount) {
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
    let progressReporter = AnalyzerFrameProgressReporter(
        enabled: progressEnabled,
        label: plan.name,
        totalFrameCount: estimatedFrameCount(
            durationSeconds: plan.durationSeconds,
            frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
            maxFrames: maxFrames
        )
    )
    let inFlightLimit = analyzerInFlightLimit(pixelCount: sample.width * sample.height, readerLaneCount: 1)
    progress(progressEnabled, "using 1 GPU-fed media reader lane with \(inFlightLimit) in-flight GPU frame slot(s) for \(plan.name)")
    let expectedOutputFrameCount = estimatedFrameCount(
        durationSeconds: plan.durationSeconds,
        frameDurationSeconds: plan.frameDurationSeconds > 0 ? plan.frameDurationSeconds : 1.0 / 30.0,
        maxFrames: maxFrames
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
        progressReporter: progressReporter,
        inFlightLimit: inFlightLimit,
        expectedOutputFrameCount: expectedOutputFrameCount,
        metalContext: metalContext
    )
    progressReporter.finish()
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
    progress(
        arguments.progress,
        "processing \(plan.assets.count) selected asset(s) serially with Metal GPU analysis; each active asset may use all offered CPU reader lanes"
    )
    var results: [AnalysisResult] = []
    for (assetIndex, asset) in plan.assets.enumerated() {
        progress(arguments.progress, "starting asset \(assetIndex + 1)/\(plan.assets.count): \(asset.name)")
        let prepared = try readFrames(
            asset: asset,
            sampleScalePercent: plan.sampleScalePercent,
            maxFrames: plan.maxFrames,
            progressEnabled: arguments.progress,
            metalContext: metalContext,
            allowParallelReaders: true
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
