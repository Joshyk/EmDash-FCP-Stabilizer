import Foundation

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
}
