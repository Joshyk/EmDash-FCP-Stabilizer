#!/usr/bin/env swift
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal

let sampleWidth = 96
let sampleHeight = 54
let globalSearchRadius = 16
let localSearchRadius = 5
let positionGain: Float = 1.75
let maxScale: Float = 1.35

struct Arguments {
    var mediaPath = ""
    var sourceStart = "0s"
    var duration = ""
    var clipName = "selected timeline clip"
    var durationSeconds: Double?
    var outputPath = ""
    var cacheFPS: Double = 15.0
    var maxSamples: Int = 7200
    var panSmoothSeconds: Double = 6.0
    var progressPath: String?
}

struct Motion {
    var rawMotion: Float = 0
    var globalDx: Float = 0
    var globalDy: Float = 0
    var residual: Float = 0
    var signedRoll: Float = 0
    var rollMotion: Float = 0
    var yawProxy: Float = 0
    var pitchProxy: Float = 0
    var shearX: Float = 0
    var shearY: Float = 0
    var perspectiveX: Float = 0
    var perspectiveY: Float = 0
}

struct GPUFrame {
    let time: Double
    let gray: MTLBuffer
    let blur: Float
}

struct ShiftUniforms {
    var width: UInt32
    var height: UInt32
    var x0: UInt32
    var y0: UInt32
    var regionWidth: UInt32
    var regionHeight: UInt32
    var centerX: Int32
    var centerY: Int32
    var radius: UInt32
    var stride: UInt32
}

let metalSource = """
#include <metal_stdlib>
using namespace metal;

struct ShiftUniforms {
    uint width;
    uint height;
    uint x0;
    uint y0;
    uint regionWidth;
    uint regionHeight;
    int centerX;
    int centerY;
    uint radius;
    uint stride;
};

kernel void downsampleBGRA(
    texture2d<float, access::sample> input [[texture(0)]],
    device uchar *output [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 96 || gid.y >= 54) { return; }
    constexpr sampler nearestSampler(coord::pixel, address::clamp_to_edge, filter::nearest);
    float x = (float(gid.x) + 0.5) * float(input.get_width()) / 96.0;
    float y = (float(gid.y) + 0.5) * float(input.get_height()) / 54.0;
    float4 c = input.sample(nearestSampler, float2(x, y));
    float luma = (0.2126 * c.r) + (0.7152 * c.g) + (0.0722 * c.b);
    output[(gid.y * 96) + gid.x] = uchar(clamp(luma * 255.0, 0.0, 255.0));
}

kernel void shiftScores(
    device const uchar *previous [[buffer(0)]],
    device const uchar *current [[buffer(1)]],
    device float *scores [[buffer(2)]],
    constant ShiftUniforms &u [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    uint side = (u.radius * 2) + 1;
    uint count = side * side;
    if (gid >= count) { return; }
    int dx = int(gid % side) + u.centerX - int(u.radius);
    int dy = int(gid / side) + u.centerY - int(u.radius);
    int xStart = max(max(int(u.x0), -dx), 0);
    int yStart = max(max(int(u.y0), -dy), 0);
    int xEnd = min(min(int(u.x0 + u.regionWidth), int(u.width) - dx), int(u.width));
    int yEnd = min(min(int(u.y0 + u.regionHeight), int(u.height) - dy), int(u.height));
    if ((xEnd - xStart) < 18 || (yEnd - yStart) < 12) {
        scores[gid] = INFINITY;
        return;
    }
    float total = 0.0;
    uint samples = 0;
    for (int y = yStart; y < yEnd; y += int(u.stride)) {
        int previousRow = y * int(u.width);
        int currentRow = (y + dy) * int(u.width);
        for (int x = xStart; x < xEnd; x += int(u.stride)) {
            total += abs(float(previous[previousRow + x]) - float(current[currentRow + x + dx]));
            samples += 1;
        }
    }
    scores[gid] = samples == 0 ? INFINITY : total / float(samples) / 255.0;
}
"""

final class MetalAnalyzer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let textureCache: CVMetalTextureCache
    let downsamplePipeline: MTLComputePipelineState
    let shiftPipeline: MTLComputePipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "StabilizerGPU", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device was not available"])
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "StabilizerGPU", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal command queue was not available"])
        }
        self.queue = queue
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let textureCache = cache else {
            throw NSError(domain: "StabilizerGPU", code: 3, userInfo: [NSLocalizedDescriptionKey: "CVMetalTextureCache was not available"])
        }
        self.textureCache = textureCache
        let library = try device.makeLibrary(source: metalSource, options: nil)
        self.downsamplePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "downsampleBGRA")!)
        self.shiftPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "shiftScores")!)
    }

    func downsample(pixelBuffer: CVPixelBuffer, time: Double) throws -> GPUFrame {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let texture = cvTexture, let inputTexture = CVMetalTextureGetTexture(texture) else {
            throw NSError(domain: "StabilizerGPU", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create Metal texture from decoded frame"])
        }
        guard let output = device.makeBuffer(length: sampleWidth * sampleHeight, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(domain: "StabilizerGPU", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not allocate Metal downsample resources"])
        }
        encoder.setComputePipelineState(downsamplePipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setBuffer(output, offset: 0, index: 0)
        let grid = MTLSize(width: sampleWidth, height: sampleHeight, depth: 1)
        let threads = MTLSize(width: 16, height: 8, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threads)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        return GPUFrame(time: time, gray: output, blur: blurAmount(output))
    }

    func estimateShift(previous: MTLBuffer, current: MTLBuffer, x0: Int, y0: Int, width: Int, height: Int, radius: Int, center: (Float, Float), refine: Bool) throws -> (Float, Float, Float) {
        let side = (radius * 2) + 1
        let count = side * side
        guard let scores = device.makeBuffer(length: MemoryLayout<Float>.stride * count, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw NSError(domain: "StabilizerGPU", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not allocate Metal shift resources"])
        }
        var uniforms = ShiftUniforms(
            width: UInt32(sampleWidth),
            height: UInt32(sampleHeight),
            x0: UInt32(x0),
            y0: UInt32(y0),
            regionWidth: UInt32(width),
            regionHeight: UInt32(height),
            centerX: Int32(center.0.rounded()),
            centerY: Int32(center.1.rounded()),
            radius: UInt32(radius),
            stride: 2
        )
        encoder.setComputePipelineState(shiftPipeline)
        encoder.setBuffer(previous, offset: 0, index: 0)
        encoder.setBuffer(current, offset: 0, index: 1)
        encoder.setBuffer(scores, offset: 0, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<ShiftUniforms>.stride, index: 3)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, count), height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        let pointer = scores.contents().assumingMemoryBound(to: Float.self)
        var bestIndex = 0
        var bestScore = Float.greatestFiniteMagnitude
        for index in 0..<count {
            let score = pointer[index]
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        let bestDxInt = Int(bestIndex % side) + Int(uniforms.centerX) - radius
        let bestDyInt = Int(bestIndex / side) + Int(uniforms.centerY) - radius
        guard refine else {
            return (Float(bestDxInt), Float(bestDyInt), bestScore)
        }
        func score(dx: Int, dy: Int) -> Float {
            let x = dx - Int(uniforms.centerX) + radius
            let y = dy - Int(uniforms.centerY) + radius
            guard x >= 0, x < side, y >= 0, y < side else { return .greatestFiniteMagnitude }
            return pointer[(y * side) + x]
        }
        let xOffset = axisOffset(before: score(dx: bestDxInt - 1, dy: bestDyInt), center: bestScore, after: score(dx: bestDxInt + 1, dy: bestDyInt))
        let yOffset = axisOffset(before: score(dx: bestDxInt, dy: bestDyInt - 1), center: bestScore, after: score(dx: bestDxInt, dy: bestDyInt + 1))
        return (Float(bestDxInt) + xOffset, Float(bestDyInt) + yOffset, bestScore)
    }
}

func parseArgs() throws -> Arguments {
    var args = Arguments()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let key = iterator.next() {
        guard key.hasPrefix("--"), let value = iterator.next() else { continue }
        switch key {
        case "--media-path": args.mediaPath = value
        case "--source-start": args.sourceStart = value
        case "--duration": args.duration = value
        case "--clip-name": args.clipName = value
        case "--duration-seconds": args.durationSeconds = Double(value)
        case "--fxplug-cache-output": args.outputPath = value
        case "--fxplug-cache-fps": args.cacheFPS = Double(value) ?? args.cacheFPS
        case "--fxplug-cache-max-samples": args.maxSamples = Int(value) ?? args.maxSamples
        case "--pan-smooth-seconds": args.panSmoothSeconds = Double(value) ?? args.panSmoothSeconds
        case "--progress-file": args.progressPath = value
        default: break
        }
    }
    if args.mediaPath.isEmpty { throw messageError("missing --media-path") }
    if args.outputPath.isEmpty { throw messageError("missing --fxplug-cache-output") }
    return args
}

func messageError(_ text: String) -> NSError {
    NSError(domain: "StabilizerGPU", code: 100, userInfo: [NSLocalizedDescriptionKey: text])
}

func parseSeconds(_ text: String) throws -> Double {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasSuffix("s") { value.removeLast() }
    if value.contains("/") {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
    }
    if let number = Double(value) { return number }
    throw messageError("invalid time value: \(text)")
}

func emit(_ payload: [String: Any], status: Int32 = 0) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
    exit(status)
}

func fail(_ message: String) -> Never {
    emit(["schemaVersion": 1, "error": message], status: 1)
}

func writeProgress(_ args: Arguments, _ percent: Double, _ message: String) {
    guard let path = args.progressPath else { return }
    let payload: [String: Any] = [
        "percent": max(0.0, min(1.0, percent)),
        "message": message,
    ]
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    } catch {
        // Progress is best-effort; analyzer output still reports final failure/success.
    }
}

func loadFrames(args: Arguments, analyzer: MetalAnalyzer) throws -> (AVAssetTrack, [GPUFrame]) {
    writeProgress(args, 0.04, "Preparing AVFoundation hardware decode")
    let url = URL(fileURLWithPath: args.mediaPath)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
        throw messageError("media file did not contain a video track")
    }
    let sourceStart = try parseSeconds(args.sourceStart)
    let requestedDuration = try parseSeconds(args.duration)
    let duration = min(requestedDuration, args.durationSeconds ?? requestedDuration)
    let nominalFPS = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
    var sampleFPS = min(max(1.0, args.cacheFPS), max(1.0, nominalFPS))
    if args.maxSamples > 0, Int(ceil(duration * sampleFPS)) > args.maxSamples {
        sampleFPS = Double(args.maxSamples) / duration
    }
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(
        start: CMTime(seconds: sourceStart, preferredTimescale: 600),
        duration: CMTime(seconds: duration, preferredTimescale: 600)
    )
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    )
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else {
        throw reader.error ?? messageError("AVAssetReader could not start")
    }
    writeProgress(args, 0.10, "Decoding and downsampling on Metal")
    let interval = 1.0 / sampleFPS
    var nextSampleTime = sourceStart
    var frames: [GPUFrame] = []
    while let sampleBuffer = output.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard pts.isFinite else { continue }
        if pts + 1e-6 < nextSampleTime { continue }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        let relativeTime = max(0.0, pts - sourceStart)
        frames.append(try analyzer.downsample(pixelBuffer: pixelBuffer, time: relativeTime))
        nextSampleTime += interval
        if frames.count % 8 == 0 {
            writeProgress(args, min(0.46, 0.10 + (0.36 * relativeTime / max(0.001, duration))), "Decoded \(frames.count) GPU frame samples")
        }
    }
    if let error = reader.error {
        throw error
    }
    if frames.count < 2 {
        throw messageError("GPU analyzer decoded fewer than two frame samples")
    }
    writeProgress(args, 0.48, "Decoded \(frames.count) GPU frame samples")
    return (track, frames)
}

func pairMotion(analyzer: MetalAnalyzer, previous: GPUFrame, current: GPUFrame) throws -> Motion {
    let global = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 8, y0: 6, width: sampleWidth - 16, height: sampleHeight - 12, radius: globalSearchRadius, center: (0, 0), refine: true)
    let center = (round(global.0), round(global.1))
    let left = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 4, y0: 8, width: 28, height: sampleHeight - 16, radius: localSearchRadius, center: center, refine: false)
    let right = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: sampleWidth - 32, y0: 8, width: 28, height: sampleHeight - 16, radius: localSearchRadius, center: center, refine: false)
    let top = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 12, y0: 4, width: sampleWidth - 24, height: 20, radius: localSearchRadius, center: center, refine: false)
    let bottom = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 12, y0: sampleHeight - 24, width: sampleWidth - 24, height: 20, radius: localSearchRadius, center: center, refine: false)
    let topLeft = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 6, y0: 5, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
    let topRight = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: sampleWidth - 30, y0: 5, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
    let bottomLeft = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: 6, y0: sampleHeight - 21, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
    let bottomRight = try analyzer.estimateShift(previous: previous.gray, current: current.gray, x0: sampleWidth - 30, y0: sampleHeight - 21, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)

    let rollFromVertical = (right.1 - left.1) / Float(max(1, sampleWidth - 32))
    let horizontalSlope = (bottom.0 - top.0) / Float(max(1, sampleHeight - 16))
    let rollFromHorizontal = -horizontalSlope
    let signedRoll = (rollFromVertical + rollFromHorizontal) * 0.5
    let topSpread = topRight.0 - topLeft.0
    let bottomSpread = bottomRight.0 - bottomLeft.0
    let leftVerticalSpread = bottomLeft.1 - topLeft.1
    let rightVerticalSpread = bottomRight.1 - topRight.1
    return Motion(
        rawMotion: 0,
        globalDx: global.0,
        globalDy: global.1,
        residual: global.2,
        signedRoll: signedRoll,
        rollMotion: max(abs(rollFromVertical), abs(rollFromHorizontal)),
        yawProxy: (right.0 - left.0) / Float(max(1, sampleWidth - 32)),
        pitchProxy: (bottom.1 - top.1) / Float(max(1, sampleHeight - 16)),
        shearX: horizontalSlope + signedRoll,
        shearY: rollFromVertical - signedRoll,
        perspectiveX: (topSpread - bottomSpread) / Float(max(1, sampleWidth - 12)),
        perspectiveY: (leftVerticalSpread - rightVerticalSpread) / Float(max(1, sampleHeight - 10))
    )
}

func buildSamples(args: Arguments, frames: [GPUFrame], motions: [Motion], mediaWidth: Float, mediaHeight: Float) -> [[String: Any]] {
    let times = frames.map(\.time)
    let pathX = cumulative(motions.map(\.globalDx))
    let pathY = cumulative(motions.map(\.globalDy))
    let pathRoll = cumulative(motions.map { $0.signedRoll }).map { $0 * 180 / .pi }
    let pathYaw = cumulative(motions.map(\.yawProxy))
    let pathPitch = cumulative(motions.map(\.pitchProxy))
    let pathShearX = cumulative(motions.map(\.shearX))
    let pathShearY = cumulative(motions.map(\.shearY))
    let pathPerspectiveX = cumulative(motions.map(\.perspectiveX))
    let pathPerspectiveY = cumulative(motions.map(\.perspectiveY))
    let residuals = motions.map(\.residual)
    let rollMotions = motions.map(\.rollMotion)
    let blurValues = frames.map(\.blur)
    let window = max(0.1, args.panSmoothSeconds)
    let xScale = mediaWidth / Float(sampleWidth)
    let yScale = mediaHeight / Float(sampleHeight)
    var samples: [[String: Any]] = []

    for index in frames.indices {
        let seconds = times[index]
        var active = frames.indices.filter { abs(times[$0] - seconds) <= window * 0.5 }
        if active.isEmpty { active = Array(frames.indices) }
        let smoothX = timeWeightedAverage(pathX, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothY = timeWeightedAverage(pathY, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothRoll = timeWeightedAverage(pathRoll, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothYaw = timeWeightedAverage(pathYaw, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothPitch = timeWeightedAverage(pathPitch, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothShearX = timeWeightedAverage(pathShearX, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothShearY = timeWeightedAverage(pathShearY, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothPerspectiveX = timeWeightedAverage(pathPerspectiveX, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let smoothPerspectiveY = timeWeightedAverage(pathPerspectiveY, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let residual = active.map { residuals[$0] }.max() ?? 0
        let blur = timeWeightedAverage(blurValues, times: times, indices: active, centerTime: seconds, windowSeconds: window)
        let confidence = clamp(1.0 - (residual * 1.6) - (blur * 0.35), 0.25, 1.0)
        let compensationX = -(pathX[index] - smoothX) * xScale * positionGain * confidence
        let compensationY = -(pathY[index] - smoothY) * yScale * positionGain * confidence
        let compensationRotation = -(pathRoll[index] - smoothRoll) * confidence
        let compensationYaw = clamp(-(pathYaw[index] - smoothYaw) * 1.4 * confidence, -0.18, 0.18)
        let compensationPitch = clamp(-(pathPitch[index] - smoothPitch) * 1.4 * confidence, -0.18, 0.18)
        let compensationShearX = clamp(-(pathShearX[index] - smoothShearX) * 1.3 * confidence, -0.16, 0.16)
        let compensationShearY = clamp(-(pathShearY[index] - smoothShearY) * 1.3 * confidence, -0.16, 0.16)
        let compensationPerspectiveX = clamp(-(pathPerspectiveX[index] - smoothPerspectiveX) * 1.2 * confidence, -0.16, 0.16)
        let compensationPerspectiveY = clamp(-(pathPerspectiveY[index] - smoothPerspectiveY) * 1.2 * confidence, -0.16, 0.16)
        var motionActive = frames.indices.filter { abs(times[$0] - seconds) <= (4.5 / 30.0) }
        if motionActive.isEmpty { motionActive = [index] }
        let rollMotion = motionActive.map { rollMotions[$0] }.max() ?? 0
        let translationScale = max(
            1.0 + (2.0 * abs(compensationX) / max(1.0, mediaWidth)),
            1.0 + (2.0 * abs(compensationY) / max(1.0, mediaHeight))
        )
        let rotationScale = 1.0 + min(0.12, abs(compensationRotation) * 0.006)
        let jitterScale = 1.0 + min(0.10, (residual * 0.10) + (rollMotion * 0.45))
        let warpScale = 1.0 + min(0.20, (abs(compensationYaw) + abs(compensationPitch) + abs(compensationShearX) + abs(compensationShearY) + abs(compensationPerspectiveX) + abs(compensationPerspectiveY)) * 0.55)
        let blurScale = 1.0 + min(0.06, blur * 0.06)
        let cropSafety = max(1.0, translationScale, rotationScale, warpScale)
        let scale = min(maxScale, max(cropSafety, jitterScale, blurScale))
        samples.append([
            "timeSeconds": round6(seconds),
            "pixelOffsetX": round4(compensationX),
            "pixelOffsetY": round4(compensationY),
            "rotationDegrees": round4(compensationRotation),
            "scaleMultiplier": round6(scale),
            "yawPitchProxyX": round6(compensationYaw),
            "yawPitchProxyY": round6(compensationPitch),
            "shearX": round6(compensationShearX),
            "shearY": round6(compensationShearY),
            "perspectiveX": round6(compensationPerspectiveX),
            "perspectiveY": round6(compensationPerspectiveY),
            "cropSafety": round6(cropSafety),
            "blurAmount": round6(blur),
        ])
    }
    return samples
}

func blurAmount(_ buffer: MTLBuffer) -> Float {
    let pixels = buffer.contents().assumingMemoryBound(to: UInt8.self)
    var total: Float = 0
    var count: Float = 0
    for y in 1..<(sampleHeight - 1) {
        let row = y * sampleWidth
        for x in 1..<(sampleWidth - 1) {
            let h = abs(Int(pixels[row + x + 1]) - Int(pixels[row + x - 1]))
            let v = abs(Int(pixels[row + sampleWidth + x]) - Int(pixels[row - sampleWidth + x]))
            total += Float(h + v) / 510
            count += 1
        }
    }
    if count <= 0 { return 1 }
    let sharpness = total / count
    return 1.0 - clamp((sharpness - 0.015) / 0.11, 0, 1)
}

func axisOffset(before: Float, center: Float, after: Float) -> Float {
    guard before.isFinite, center.isFinite, after.isFinite else { return 0 }
    let denominator = before - (2 * center) + after
    guard abs(denominator) >= 1e-9 else { return 0 }
    return clamp(0.5 * (before - after) / denominator, -0.5, 0.5)
}

func cumulative(_ values: [Float]) -> [Float] {
    var total: Float = 0
    return values.map { total += $0; return total }
}

func timeWeightedAverage(_ values: [Float], times: [Double], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float {
    guard !indices.isEmpty else { return 0 }
    guard indices.count > 1 else { return values[indices[0]] }
    let sorted = indices.sorted()
    let windowStart = centerTime - (windowSeconds * 0.5)
    let windowEnd = centerTime + (windowSeconds * 0.5)
    var weighted: Float = 0
    var totalWeight: Double = 0
    for (position, index) in sorted.enumerated() {
        let current = times[index]
        let left = position > 0 ? max(windowStart, (times[sorted[position - 1]] + current) * 0.5) : windowStart
        let right = position + 1 < sorted.count ? min(windowEnd, (current + times[sorted[position + 1]]) * 0.5) : windowEnd
        let weight = max(0, right - left)
        weighted += values[index] * Float(weight)
        totalWeight += weight
    }
    if totalWeight <= 1e-9 {
        return indices.reduce(Float(0)) { $0 + values[$1] } / Float(indices.count)
    }
    return weighted / Float(totalWeight)
}

func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
    max(minValue, min(maxValue, value))
}

func round4(_ value: Float) -> Double { Double((value * 10000).rounded() / 10000) }
func round6(_ value: Float) -> Double { Double((value * 1_000_000).rounded() / 1_000_000) }
func round6(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

do {
    let args = try parseArgs()
    let analyzer = try MetalAnalyzer()
    let (track, frames) = try loadFrames(args: args, analyzer: analyzer)
    writeProgress(args, 0.50, "Analyzing motion on Metal")
    var motions = [Motion()]
    let progressStep = max(1, frames.count / 80)
    for index in 1..<frames.count {
        motions.append(try pairMotion(analyzer: analyzer, previous: frames[index - 1], current: frames[index]))
        if index % progressStep == 0 {
            writeProgress(args, 0.50 + (0.34 * Double(index) / Double(max(1, frames.count - 1))), "Analyzing GPU motion \(index)/\(frames.count - 1)")
        }
    }
    writeProgress(args, 0.88, "Building cached stabilization values")
    let width = Float(track.naturalSize.width)
    let height = Float(abs(track.naturalSize.height))
    let samples = buildSamples(args: args, frames: frames, motions: motions, mediaWidth: width, mediaHeight: height)
    let duration = samples.last?["timeSeconds"] as? Double ?? 0
    let payload: [String: Any] = [
        "schemaVersion": 1,
        "model": "fxplug-metal-precomputed-stabilization-v1",
        "clipName": args.clipName,
        "mediaPath": args.mediaPath,
        "mediaWidth": Int(width),
        "mediaHeight": Int(height),
        "durationSeconds": round6(duration),
        "sourceStartSeconds": try round6(parseSeconds(args.sourceStart)),
        "sampleFps": round6(Double(frames.count) / max(0.001, duration)),
        "panSmoothSeconds": round6(args.panSmoothSeconds),
        "samples": samples,
        "warnings": [
            "FxPlug cache generated by the Metal GPU analyzer. Decode is handled by AVFoundation/VideoToolbox and downsample/block matching use Metal compute.",
            "The cache file must be rebuilt after changing clip range or smoothing window.",
        ],
    ]
    writeProgress(args, 0.96, "Writing FxPlug GPU cache")
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let outputURL = URL(fileURLWithPath: args.outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outputURL)
    writeProgress(args, 1.0, "FxPlug GPU cache complete")
    emit([
        "schemaVersion": 1,
        "model": payload["model"]!,
        "cachePath": args.outputPath,
        "clipName": args.clipName,
        "durationSeconds": payload["durationSeconds"]!,
        "sampleFps": payload["sampleFps"]!,
        "sampleCount": samples.count,
        "panSmoothSeconds": payload["panSmoothSeconds"]!,
    ])
} catch {
    let args = (try? parseArgs()) ?? Arguments()
    writeProgress(args, 1.0, "FxPlug GPU cache failed")
    fail(error.localizedDescription)
}
