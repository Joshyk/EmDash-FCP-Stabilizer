import CoreMedia
import CoreVideo
import Darwin
import Foundation
import IOSurface
import simd

struct StabilizerAutoTransform {
    var pixelOffset: vector_float2
    var rotationDegrees: Float
    var scaleMultiplier: Float
    var yawPitchProxy: vector_float2
    var shear: vector_float2
    var perspective: vector_float2
    var cropSafety: Float
    var blurAmount: Float

    static let identity = StabilizerAutoTransform(
        pixelOffset: vector_float2(0.0, 0.0),
        rotationDegrees: 0.0,
        scaleMultiplier: 1.0,
        yawPitchProxy: vector_float2(0.0, 0.0),
        shear: vector_float2(0.0, 0.0),
        perspective: vector_float2(0.0, 0.0),
        cropSafety: 1.0,
        blurAmount: 0.0
    )
}

private struct GrayFrame {
    let time: Double
    let pixels: [UInt8]
    let blurAmount: Float
}

private struct PairMotion {
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
}

enum AutoStabilizationEstimator {
    private static let sampleWidth = 96
    private static let sampleHeight = 54
    private static let globalSearchRadius = 16
    private static let localSearchRadius = 5
    private static let minMatchWidth = 18
    private static let minMatchHeight = 12
    private static let positionGain: Float = 1.75
    private static let maxScale: Float = 1.35

    static func estimate(
        sourceImages: [FxImageTile],
        renderTime: CMTime,
        outputSize: vector_float2,
        panSmoothSeconds: Double
    ) -> StabilizerAutoTransform {
        let renderSeconds = CMTimeGetSeconds(renderTime)
        guard renderSeconds.isFinite else {
            return .identity
        }

        let frames = sourceImages
            .dropFirst()
            .compactMap(grayFrame(from:))
            .sorted { $0.time < $1.time }

        guard frames.count >= 3 else {
            return .identity
        }

        let smoothWindowSeconds = max(0.1, panSmoothSeconds)

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
                perspectiveY: 0.0
            )
        ]
        for index in 1..<frames.count {
            motions.append(pairMotion(previous: frames[index - 1].pixels, current: frames[index].pixels))
        }

        let pathX = cumulative(motions.map(\.dx))
        let pathY = cumulative(motions.map(\.dy))
        let pathRoll = cumulative(motions.map { radiansToDegrees($0.signedRoll) })
        let pathYaw = cumulative(motions.map(\.yawProxy))
        let pathPitch = cumulative(motions.map(\.pitchProxy))
        let pathShearX = cumulative(motions.map(\.shearX))
        let pathShearY = cumulative(motions.map(\.shearY))
        let pathPerspectiveX = cumulative(motions.map(\.perspectiveX))
        let pathPerspectiveY = cumulative(motions.map(\.perspectiveY))
        let centerIndex = closestFrameIndex(to: renderSeconds, in: frames)
        let windowIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= smoothWindowSeconds * 0.5 }
        let activeIndices = windowIndices.isEmpty ? Array(frames.indices) : Array(windowIndices)

        let smoothX = timeWeightedAverage(pathX, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothY = timeWeightedAverage(pathY, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothRoll = timeWeightedAverage(pathRoll, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothYaw = timeWeightedAverage(pathYaw, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothPitch = timeWeightedAverage(pathPitch, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothShearX = timeWeightedAverage(pathShearX, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothShearY = timeWeightedAverage(pathShearY, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothPerspectiveX = timeWeightedAverage(pathPerspectiveX, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let smoothPerspectiveY = timeWeightedAverage(pathPerspectiveY, frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)

        let xScale = outputSize.x / Float(sampleWidth)
        let yScale = outputSize.y / Float(sampleHeight)
        let residual = maxValue(motions.map(\.residual), indices: activeIndices)
        let blurAmount = timeWeightedAverage(frames.map(\.blurAmount), frames: frames, indices: activeIndices, centerTime: renderSeconds, windowSeconds: smoothWindowSeconds)
        let confidence = clamp(1.0 - (residual * 1.6) - (blurAmount * 0.35), min: 0.25, max: 1.0)
        let compensationX = -(pathX[centerIndex] - smoothX) * xScale * positionGain * confidence
        let compensationY = -(pathY[centerIndex] - smoothY) * yScale * positionGain * confidence
        let compensationRotation = -(pathRoll[centerIndex] - smoothRoll) * confidence
        let compensationYaw = clamp(-(pathYaw[centerIndex] - smoothYaw) * 1.4 * confidence, min: -0.18, max: 0.18)
        let compensationPitch = clamp(-(pathPitch[centerIndex] - smoothPitch) * 1.4 * confidence, min: -0.18, max: 0.18)
        let compensationShearX = clamp(-(pathShearX[centerIndex] - smoothShearX) * 1.3 * confidence, min: -0.16, max: 0.16)
        let compensationShearY = clamp(-(pathShearY[centerIndex] - smoothShearY) * 1.3 * confidence, min: -0.16, max: 0.16)
        let compensationPerspectiveX = clamp(-(pathPerspectiveX[centerIndex] - smoothPerspectiveX) * 1.2 * confidence, min: -0.16, max: 0.16)
        let compensationPerspectiveY = clamp(-(pathPerspectiveY[centerIndex] - smoothPerspectiveY) * 1.2 * confidence, min: -0.16, max: 0.16)

        let localMotionIndices = frames.indices.filter { abs(frames[$0].time - renderSeconds) <= (4.5 / 30.0) }
        let activeMotionIndices = localMotionIndices.isEmpty ? [centerIndex] : Array(localMotionIndices)
        let rollMotion = maxValue(motions.map(\.rollMotion), indices: activeMotionIndices)
        let translationScale = max(
            1.0 + (2.0 * abs(compensationX) / max(1.0, outputSize.x)),
            1.0 + (2.0 * abs(compensationY) / max(1.0, outputSize.y))
        )
        let rotationScale = 1.0 + min(0.12, abs(compensationRotation) * 0.006)
        let jitterScale = 1.0 + min(0.10, (residual * 0.10) + (rollMotion * 0.45))
        let warpScale = 1.0 + min(0.20, (abs(compensationYaw) + abs(compensationPitch) + abs(compensationShearX) + abs(compensationShearY) + abs(compensationPerspectiveX) + abs(compensationPerspectiveY)) * 0.55)
        let blurScale = 1.0 + min(0.06, blurAmount * 0.06)
        let cropSafety = max(1.0, translationScale, rotationScale, warpScale)
        let scale = min(maxScale, max(cropSafety, jitterScale, blurScale))

        return StabilizerAutoTransform(
            pixelOffset: vector_float2(compensationX, compensationY),
            rotationDegrees: compensationRotation,
            scaleMultiplier: scale,
            yawPitchProxy: vector_float2(compensationYaw, compensationPitch),
            shear: vector_float2(compensationShearX, compensationShearY),
            perspective: vector_float2(compensationPerspectiveX, compensationPerspectiveY),
            cropSafety: cropSafety,
            blurAmount: blurAmount
        )
    }

    private static func grayFrame(from tile: FxImageTile) -> GrayFrame? {
        guard let surface = tile.ioSurface else {
            return nil
        }
        let time = CMTimeGetSeconds(tile.mediaTime)
        guard time.isFinite else {
            return nil
        }
        guard surface.lock(options: [.readOnly], seed: nil) == KERN_SUCCESS else {
            return nil
        }
        defer {
            _ = surface.unlock(options: [.readOnly], seed: nil)
        }
        let baseAddress = surface.baseAddress

        let width = max(1, surface.width)
        let height = max(1, surface.height)
        let bytesPerRow = surface.bytesPerRow
        let pixelFormat = surface.pixelFormat
        var pixels = Array(repeating: UInt8(0), count: sampleWidth * sampleHeight)

        for sampleY in 0..<sampleHeight {
            let sourceY = min(height - 1, (sampleY * height) / sampleHeight)
            for sampleX in 0..<sampleWidth {
                let sourceX = min(width - 1, (sampleX * width) / sampleWidth)
                let luma: UInt8?
                if pixelFormat == kCVPixelFormatType_32BGRA {
                    luma = bgraLuma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else if pixelFormat == kCVPixelFormatType_32RGBA {
                    luma = rgba8Luma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else if pixelFormat == kCVPixelFormatType_32ARGB {
                    luma = argb8Luma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else if pixelFormat == kCVPixelFormatType_64RGBAHalf {
                    luma = rgbaHalfLuma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else if pixelFormat == kCVPixelFormatType_64RGBALE {
                    luma = rgba16LittleEndianLuma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else if pixelFormat == kCVPixelFormatType_128RGBAFloat {
                    luma = rgbaFloatLuma(baseAddress: baseAddress, x: sourceX, y: sourceY, bytesPerRow: bytesPerRow)
                } else {
                    luma = nil
                }
                guard let value = luma else {
                    return nil
                }
                pixels[(sampleY * sampleWidth) + sampleX] = value
            }
        }
        return GrayFrame(time: time, pixels: pixels, blurAmount: blurAmount(pixels))
    }

    private static func bgraLuma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 4)).assumingMemoryBound(to: UInt8.self)
        let blue = Float(pointer[0])
        let green = Float(pointer[1])
        let red = Float(pointer[2])
        return UInt8(clamping: Int((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)))
    }

    private static func rgba8Luma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 4)).assumingMemoryBound(to: UInt8.self)
        let red = Float(pointer[0])
        let green = Float(pointer[1])
        let blue = Float(pointer[2])
        return UInt8(clamping: Int((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)))
    }

    private static func argb8Luma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 4)).assumingMemoryBound(to: UInt8.self)
        let red = Float(pointer[1])
        let green = Float(pointer[2])
        let blue = Float(pointer[3])
        return UInt8(clamping: Int((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)))
    }

    private static func rgbaHalfLuma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 8)).assumingMemoryBound(to: UInt16.self)
        let red = halfToFloat(pointer[0])
        let green = halfToFloat(pointer[1])
        let blue = halfToFloat(pointer[2])
        return UInt8(clamping: Int(((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) * 255.0))
    }

    private static func rgba16LittleEndianLuma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 8)).assumingMemoryBound(to: UInt16.self)
        let red = Float(pointer[0]) / 65535.0
        let green = Float(pointer[1]) / 65535.0
        let blue = Float(pointer[2]) / 65535.0
        return UInt8(clamping: Int(((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) * 255.0))
    }

    private static func rgbaFloatLuma(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int, bytesPerRow: Int) -> UInt8 {
        let pointer = baseAddress.advanced(by: (y * bytesPerRow) + (x * 16)).assumingMemoryBound(to: Float.self)
        let red = clamp(pointer[0], min: 0.0, max: 1.0)
        let green = clamp(pointer[1], min: 0.0, max: 1.0)
        let blue = clamp(pointer[2], min: 0.0, max: 1.0)
        return UInt8(clamping: Int(((0.2126 * red) + (0.7152 * green) + (0.0722 * blue)) * 255.0))
    }

    private static func halfToFloat(_ bits: UInt16) -> Float {
        let sign = (UInt32(bits & 0x8000)) << 16
        let exponent = UInt32((bits & 0x7C00) >> 10)
        let mantissa = UInt32(bits & 0x03FF)

        let floatBits: UInt32
        if exponent == 0 {
            if mantissa == 0 {
                floatBits = sign
            } else {
                var normalizedMantissa = mantissa
                var normalizedExponent: Int32 = -14
                while (normalizedMantissa & 0x0400) == 0 {
                    normalizedMantissa <<= 1
                    normalizedExponent -= 1
                }
                normalizedMantissa &= 0x03FF
                let exponentBits = UInt32(normalizedExponent + 127) << 23
                floatBits = sign | exponentBits | (normalizedMantissa << 13)
            }
        } else if exponent == 0x1F {
            floatBits = sign | 0x7F800000 | (mantissa << 13)
        } else {
            let exponentBits = (exponent + 112) << 23
            floatBits = sign | exponentBits | (mantissa << 13)
        }

        return clamp(Float(bitPattern: floatBits), min: 0.0, max: 1.0)
    }

    private static func pairMotion(previous: [UInt8], current: [UInt8]) -> PairMotion {
        let global = estimateShift(
            previous: previous,
            current: current,
            x0: 8,
            y0: 6,
            width: sampleWidth - 16,
            height: sampleHeight - 12,
            radius: globalSearchRadius,
            center: (0.0, 0.0),
            refine: true
        )
        let center = (round(global.dx), round(global.dy))
        let left = estimateShift(previous: previous, current: current, x0: 4, y0: 8, width: 28, height: sampleHeight - 16, radius: localSearchRadius, center: center, refine: false)
        let right = estimateShift(previous: previous, current: current, x0: sampleWidth - 32, y0: 8, width: 28, height: sampleHeight - 16, radius: localSearchRadius, center: center, refine: false)
        let top = estimateShift(previous: previous, current: current, x0: 12, y0: 4, width: sampleWidth - 24, height: 20, radius: localSearchRadius, center: center, refine: false)
        let bottom = estimateShift(previous: previous, current: current, x0: 12, y0: sampleHeight - 24, width: sampleWidth - 24, height: 20, radius: localSearchRadius, center: center, refine: false)
        let topLeft = estimateShift(previous: previous, current: current, x0: 6, y0: 5, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
        let topRight = estimateShift(previous: previous, current: current, x0: sampleWidth - 30, y0: 5, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
        let bottomLeft = estimateShift(previous: previous, current: current, x0: 6, y0: sampleHeight - 21, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)
        let bottomRight = estimateShift(previous: previous, current: current, x0: sampleWidth - 30, y0: sampleHeight - 21, width: 24, height: 16, radius: localSearchRadius, center: center, refine: false)

        let rollFromVertical = (right.dy - left.dy) / Float(max(1, sampleWidth - 32))
        let horizontalSlope = (bottom.dx - top.dx) / Float(max(1, sampleHeight - 16))
        let rollFromHorizontal = -horizontalSlope
        let signedRoll = (rollFromVertical + rollFromHorizontal) * 0.5
        let rollMotion = max(abs(rollFromVertical), abs(rollFromHorizontal))
        let yawProxy = (right.dx - left.dx) / Float(max(1, sampleWidth - 32))
        let pitchProxy = (bottom.dy - top.dy) / Float(max(1, sampleHeight - 16))
        let shearX = horizontalSlope + signedRoll
        let shearY = rollFromVertical - signedRoll
        let topSpread = topRight.dx - topLeft.dx
        let bottomSpread = bottomRight.dx - bottomLeft.dx
        let leftVerticalSpread = bottomLeft.dy - topLeft.dy
        let rightVerticalSpread = bottomRight.dy - topRight.dy
        let perspectiveX = (topSpread - bottomSpread) / Float(max(1, sampleWidth - 12))
        let perspectiveY = (leftVerticalSpread - rightVerticalSpread) / Float(max(1, sampleHeight - 10))

        return PairMotion(
            dx: global.dx,
            dy: global.dy,
            residual: global.score,
            signedRoll: signedRoll,
            rollMotion: rollMotion,
            yawProxy: yawProxy,
            pitchProxy: pitchProxy,
            shearX: shearX,
            shearY: shearY,
            perspectiveX: perspectiveX,
            perspectiveY: perspectiveY
        )
    }

    private static func blurAmount(_ pixels: [UInt8]) -> Float {
        var totalGradient: Float = 0.0
        var count: Float = 0.0
        for y in 1..<(sampleHeight - 1) {
            let row = y * sampleWidth
            for x in 1..<(sampleWidth - 1) {
                let horizontal = abs(Int(pixels[row + x + 1]) - Int(pixels[row + x - 1]))
                let vertical = abs(Int(pixels[row + sampleWidth + x]) - Int(pixels[row - sampleWidth + x]))
                totalGradient += Float(horizontal + vertical) / 510.0
                count += 1.0
            }
        }
        guard count > 0.0 else {
            return 1.0
        }
        let sharpness = totalGradient / count
        return 1.0 - clamp((sharpness - 0.015) / 0.11, min: 0.0, max: 1.0)
    }

    private static func estimateShift(
        previous: [UInt8],
        current: [UInt8],
        x0: Int,
        y0: Int,
        width: Int,
        height: Int,
        radius: Int,
        center: (Float, Float),
        refine: Bool
    ) -> (dx: Float, dy: Float, score: Float) {
        let centerX = Int(center.0.rounded())
        let centerY = Int(center.1.rounded())
        var bestDx = centerX
        var bestDy = centerY
        var bestScore = Float.greatestFiniteMagnitude

        for dy in (centerY - radius)...(centerY + radius) {
            for dx in (centerX - radius)...(centerX + radius) {
                let score = shiftedAbsDiff(previous: previous, current: current, dx: dx, dy: dy, x0: x0, y0: y0, width: width, height: height)
                if score < bestScore {
                    bestDx = dx
                    bestDy = dy
                    bestScore = score
                }
            }
        }

        guard refine else {
            return (Float(bestDx), Float(bestDy), bestScore)
        }

        let xBefore = shiftedAbsDiff(previous: previous, current: current, dx: bestDx - 1, dy: bestDy, x0: x0, y0: y0, width: width, height: height)
        let xAfter = shiftedAbsDiff(previous: previous, current: current, dx: bestDx + 1, dy: bestDy, x0: x0, y0: y0, width: width, height: height)
        let yBefore = shiftedAbsDiff(previous: previous, current: current, dx: bestDx, dy: bestDy - 1, x0: x0, y0: y0, width: width, height: height)
        let yAfter = shiftedAbsDiff(previous: previous, current: current, dx: bestDx, dy: bestDy + 1, x0: x0, y0: y0, width: width, height: height)

        return (
            Float(bestDx) + axisOffset(before: xBefore, center: bestScore, after: xAfter),
            Float(bestDy) + axisOffset(before: yBefore, center: bestScore, after: yAfter),
            bestScore
        )
    }

    private static func shiftedAbsDiff(previous: [UInt8], current: [UInt8], dx: Int, dy: Int, x0: Int, y0: Int, width: Int, height: Int) -> Float {
        let xStart = max(x0, -dx, 0)
        let yStart = max(y0, -dy, 0)
        let xEnd = min(x0 + width, sampleWidth - dx, sampleWidth)
        let yEnd = min(y0 + height, sampleHeight - dy, sampleHeight)
        guard xEnd - xStart >= minMatchWidth, yEnd - yStart >= minMatchHeight else {
            return Float.greatestFiniteMagnitude
        }

        var total = 0
        var count = 0
        for y in stride(from: yStart, to: yEnd, by: 2) {
            let previousRow = y * sampleWidth
            let currentRow = (y + dy) * sampleWidth
            for x in stride(from: xStart, to: xEnd, by: 2) {
                total += abs(Int(previous[previousRow + x]) - Int(current[currentRow + x + dx]))
                count += 1
            }
        }
        guard count > 0 else {
            return Float.greatestFiniteMagnitude
        }
        return Float(total) / Float(count) / 255.0
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

    private static func closestFrameIndex(to time: Double, in frames: [GrayFrame]) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, frame) in frames.enumerated() {
            let distance = abs(frame.time - time)
            if distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
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

    private static func timeWeightedAverage(_ values: [Float], frames: [GrayFrame], indices: [Int], centerTime: Double, windowSeconds: Double) -> Float {
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

    private static func maxValue(_ values: [Float], indices: [Int]) -> Float {
        guard !indices.isEmpty else {
            return 0.0
        }
        return indices.reduce(Float(0.0)) { partial, index in
            max(partial, values[index])
        }
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180.0 / .pi
    }

    private static func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

private struct StabilizationCacheFile: Decodable {
    let schemaVersion: Int
    let model: String
    let mediaWidth: Float?
    let mediaHeight: Float?
    let samples: [StabilizationCacheSample]
}

private struct StabilizationCacheSample: Decodable {
    let timeSeconds: Double
    let pixelOffsetX: Float
    let pixelOffsetY: Float
    let rotationDegrees: Float
    let scaleMultiplier: Float
    let yawPitchProxyX: Float
    let yawPitchProxyY: Float
    let shearX: Float
    let shearY: Float
    let perspectiveX: Float
    let perspectiveY: Float
    let cropSafety: Float
    let blurAmount: Float
}

enum StabilizationCacheStore {
    private static let lock = NSLock()
    private static var cachedURL: URL?
    private static var cachedModifiedDate: Date?
    private static var cachedFile: StabilizationCacheFile?

    static func hasUsableCache() -> Bool {
        loadCache() != nil
    }

    static func transform(at renderTime: CMTime, outputSize: vector_float2) -> StabilizerAutoTransform? {
        guard let cache = loadCache(), cache.schemaVersion == 1, Self.supportedCacheModels.contains(cache.model) else {
            return nil
        }
        let samples = cache.samples.sorted { $0.timeSeconds < $1.timeSeconds }
        guard let first = samples.first, let last = samples.last else {
            return nil
        }
        let seconds = CMTimeGetSeconds(renderTime)
        guard seconds.isFinite else {
            return nil
        }

        let sample: StabilizationCacheSample
        if seconds <= first.timeSeconds {
            sample = first
        } else if seconds >= last.timeSeconds {
            sample = last
        } else {
            var lowerIndex = 0
            var upperIndex = samples.count - 1
            for index in 1..<samples.count where samples[index].timeSeconds >= seconds {
                lowerIndex = index - 1
                upperIndex = index
                break
            }
            sample = interpolate(samples[lowerIndex], samples[upperIndex], at: seconds)
        }

        let sourceWidth = max(1.0, cache.mediaWidth ?? outputSize.x)
        let sourceHeight = max(1.0, cache.mediaHeight ?? outputSize.y)
        let outputScale = vector_float2(outputSize.x / sourceWidth, outputSize.y / sourceHeight)
        return StabilizerAutoTransform(
            pixelOffset: vector_float2(sample.pixelOffsetX * outputScale.x, sample.pixelOffsetY * outputScale.y),
            rotationDegrees: sample.rotationDegrees,
            scaleMultiplier: sample.scaleMultiplier,
            yawPitchProxy: vector_float2(sample.yawPitchProxyX, sample.yawPitchProxyY),
            shear: vector_float2(sample.shearX, sample.shearY),
            perspective: vector_float2(sample.perspectiveX, sample.perspectiveY),
            cropSafety: sample.cropSafety,
            blurAmount: sample.blurAmount
        )
    }

    private static func loadCache() -> StabilizationCacheFile? {
        lock.lock()
        defer { lock.unlock() }

        for url in cacheURLs() {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let modifiedDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            if cachedURL == url, cachedModifiedDate == modifiedDate {
                return cachedFile
            }
            guard let data = try? Data(contentsOf: url),
                  let cache = try? JSONDecoder().decode(StabilizationCacheFile.self, from: data) else {
                cachedURL = url
                cachedModifiedDate = modifiedDate
                cachedFile = nil
                return nil
            }
            cachedURL = url
            cachedModifiedDate = modifiedDate
            cachedFile = cache
            return cache
        }

        cachedURL = nil
        cachedModifiedDate = nil
        cachedFile = nil
        return nil
    }

    private static let supportedCacheModels: Set<String> = [
        "fxplug-precomputed-stabilization-v1",
        "fxplug-metal-precomputed-stabilization-v1",
    ]

    private static func cacheURLs() -> [URL] {
        var homes: [String] = []
        if let envHome = ProcessInfo.processInfo.environment["HOME"], !envHome.isEmpty {
            homes.append(envHome)
        }
        if let passwordEntry = getpwuid(getuid()), let directory = passwordEntry.pointee.pw_dir {
            homes.append(String(cString: directory))
        }
        homes.append(NSHomeDirectory())

        var urls: [URL] = []
        var seen = Set<String>()
        for home in homes {
            let path = (home as NSString).appendingPathComponent("Library/Application Support/CommandPost/StabilizerFxPlug/current.json")
            if seen.insert(path).inserted {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    private static func interpolate(_ lower: StabilizationCacheSample, _ upper: StabilizationCacheSample, at seconds: Double) -> StabilizationCacheSample {
        let span = max(1e-9, upper.timeSeconds - lower.timeSeconds)
        let amount = Float(max(0.0, min(1.0, (seconds - lower.timeSeconds) / span)))
        func mix(_ a: Float, _ b: Float) -> Float {
            a + ((b - a) * amount)
        }
        return StabilizationCacheSample(
            timeSeconds: seconds,
            pixelOffsetX: mix(lower.pixelOffsetX, upper.pixelOffsetX),
            pixelOffsetY: mix(lower.pixelOffsetY, upper.pixelOffsetY),
            rotationDegrees: mix(lower.rotationDegrees, upper.rotationDegrees),
            scaleMultiplier: mix(lower.scaleMultiplier, upper.scaleMultiplier),
            yawPitchProxyX: mix(lower.yawPitchProxyX, upper.yawPitchProxyX),
            yawPitchProxyY: mix(lower.yawPitchProxyY, upper.yawPitchProxyY),
            shearX: mix(lower.shearX, upper.shearX),
            shearY: mix(lower.shearY, upper.shearY),
            perspectiveX: mix(lower.perspectiveX, upper.perspectiveX),
            perspectiveY: mix(lower.perspectiveY, upper.perspectiveY),
            cropSafety: mix(lower.cropSafety, upper.cropSafety),
            blurAmount: mix(lower.blurAmount, upper.blurAmount)
        )
    }
}
