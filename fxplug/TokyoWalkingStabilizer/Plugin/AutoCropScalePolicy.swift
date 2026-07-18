import Foundation

enum StabilizerAutoCropScalePolicy {
    static let coverageActivationDelta: Float = 0.0005
    static let unbufferedDemandMaximumDelta: Float = 0.006
    static let subtleZoomMaximumDelta: Float = 0.08
    static let subtleZoomMultiplier: Float = 0.5
    static let coverageToleranceDelta: Float = 0.0005
    static let playbackMinimumClipScaleDelta: Float = 0.018
    static let playbackAdaptivePaddingDelta: Float = 0.004
    static let playbackAdaptiveMultiplier: Float = 1.5

    static func keypointScale(forDemandScale demandScale: Float) -> Float {
        let safeDemandScale = max(Float(1.0), demandScale.isFinite ? demandScale : Float(1.0))
        let demandDelta = safeDemandScale - Float(1.0)
        guard demandDelta > coverageActivationDelta else {
            return Float(1.0)
        }
        guard demandDelta > unbufferedDemandMaximumDelta else {
            return safeDemandScale
        }
        guard demandDelta <= subtleZoomMaximumDelta else {
            return safeDemandScale
        }
        let attenuatedScale = Float(1.0) + (demandDelta * subtleZoomMultiplier)
        let safetyFloor = max(Float(1.0), safeDemandScale - coverageToleranceDelta)
        return max(attenuatedScale, safetyFloor)
    }

    static func playbackMinimumClippedScale(_ scale: Float) -> Float {
        let safeScale = max(Float(1.0), scale.isFinite ? scale : Float(1.0))
        let demandDelta = max(Float(0.0), safeScale - Float(1.0))
        guard demandDelta > coverageActivationDelta else {
            return Float(1.0)
        }
        guard demandDelta > unbufferedDemandMaximumDelta else {
            return safeScale
        }
        let adaptiveMinimumDelta = min(
            playbackMinimumClipScaleDelta,
            max(
                demandDelta + playbackAdaptivePaddingDelta,
                demandDelta * playbackAdaptiveMultiplier
            )
        )
        return max(Float(1.0) + adaptiveMinimumDelta, safeScale)
    }

    static func reservedDemandScales(
        times: [Double],
        demandScales: [Float],
        leadSeconds: Double,
        holdSeconds: Double,
        releaseSeconds: Double
    ) -> [Float]? {
        guard times.count == demandScales.count,
              times.allSatisfy(\.isFinite),
              demandScales.allSatisfy(\.isFinite),
              leadSeconds.isFinite,
              holdSeconds.isFinite,
              releaseSeconds.isFinite,
              leadSeconds >= 0.0,
              holdSeconds >= 0.0,
              releaseSeconds >= 0.0
        else {
            return nil
        }
        guard !times.isEmpty else {
            return []
        }
        for index in 1..<times.count where times[index] < times[index - 1] {
            return nil
        }

        let safeDemands = demandScales.map { max(Float(1.0), $0) }
        let trailingSeconds = holdSeconds + releaseSeconds
        var deque: [Int] = []
        var dequeStart = 0
        var right = 0
        var result = Array(repeating: Float(1.0), count: times.count)
        for index in times.indices {
            let currentTime = times[index]
            let upperTime = currentTime + leadSeconds + 1e-9
            while right < times.count, times[right] <= upperTime {
                while deque.count > dequeStart,
                      safeDemands[deque.last!] <= safeDemands[right]
                {
                    deque.removeLast()
                }
                deque.append(right)
                right += 1
            }
            let lowerTime = currentTime - trailingSeconds - 1e-9
            while deque.count > dequeStart, times[deque[dequeStart]] < lowerTime {
                dequeStart += 1
            }
            if dequeStart > 256, dequeStart * 2 > deque.count {
                deque.removeFirst(dequeStart)
                dequeStart = 0
            }
            if deque.count > dequeStart {
                result[index] = safeDemands[deque[dequeStart]]
            }
        }
        return result
    }
}
