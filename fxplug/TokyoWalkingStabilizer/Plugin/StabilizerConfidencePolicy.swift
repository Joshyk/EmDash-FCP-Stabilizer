import Foundation

struct StabilizerXTrackingOutlierDecision {
    let reject: Bool
    let reason: String
    let deviation: Float
    let threshold: Float
}

enum StabilizerAxisLimitPolicy {
    static func xUnrestrictedYStepLimited(
        _ current: SIMD2<Float>,
        previous: SIMD2<Float>,
        limit: Float
    ) -> SIMD2<Float> {
        guard current.y.isFinite,
              previous.y.isFinite,
              limit.isFinite,
              limit >= 0.0
        else {
            return current
        }
        let deltaY = current.y - previous.y
        return SIMD2<Float>(
            current.x,
            previous.y + max(-limit, min(limit, deltaY))
        )
    }

    static func xUnrestrictedYAmplitudeLimited(
        _ value: SIMD2<Float>,
        yLimit: Float
    ) -> SIMD2<Float> {
        guard value.y.isFinite,
              yLimit.isFinite,
              yLimit >= 0.0
        else {
            return value
        }
        return SIMD2<Float>(
            value.x,
            max(-yLimit, min(yLimit, value.y))
        )
    }
}

enum StabilizerConfidencePolicy {
    static func unbiased(_ evidence: Float) -> Float {
        guard evidence.isFinite else {
            return 0.0
        }
        return min(1.0, max(0.0, evidence))
    }

    static func unbiasedMean(_ values: Float...) -> Float {
        guard !values.isEmpty else {
            return 0.0
        }
        let total = values.reduce(Float(0.0)) { partialResult, value in
            partialResult + unbiased(value)
        }
        return unbiased(total / Float(values.count))
    }

    static func unrestrictedXCorrectionFactor(_ strength: Double) -> Float {
        guard strength.isFinite else {
            return 0.0
        }
        return max(0.0, Float(strength))
    }

    static func trackedXOutlierDecision(
        value: Float,
        neighborhood: [Float],
        trackingConfidence: Float,
        walkingTrackingConfidence: Float,
        acceptedBlockCount: Int32,
        edgeQuality: Float
    ) -> StabilizerXTrackingOutlierDecision {
        guard value.isFinite,
              neighborhood.count >= 3,
              neighborhood.allSatisfy(\.isFinite)
        else {
            return StabilizerXTrackingOutlierDecision(
                reject: true,
                reason: "nonfinite-or-incomplete",
                deviation: .infinity,
                threshold: 0.0
            )
        }

        let median = sortedMedian(neighborhood)
        let deviations = neighborhood.map { abs($0 - median) }
        let medianAbsoluteDeviation = sortedMedian(deviations)
        let threshold = max(1.0, medianAbsoluteDeviation * 6.0)
        let deviation = abs(value - median)
        guard deviation > threshold else {
            return StabilizerXTrackingOutlierDecision(
                reject: false,
                reason: "temporal-consistent",
                deviation: deviation,
                threshold: threshold
            )
        }

        let trackingWeak = !trackingConfidence.isFinite
            || !walkingTrackingConfidence.isFinite
            || trackingConfidence < 0.56
            || walkingTrackingConfidence < 0.56
        let blocksWeak = acceptedBlockCount < 3
        let edgeWeak = !edgeQuality.isFinite || edgeQuality < 0.86
        var reasons: [String] = []
        if trackingWeak { reasons.append("tracking") }
        if blocksWeak { reasons.append("blocks") }
        if edgeWeak { reasons.append("search-headroom") }
        return StabilizerXTrackingOutlierDecision(
            reject: !reasons.isEmpty,
            reason: reasons.isEmpty ? "strong-evidence" : reasons.joined(separator: ","),
            deviation: deviation,
            threshold: threshold
        )
    }

    private static func sortedMedian(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }
}
