import Foundation

@main
struct StabilizerConfidencePolicyTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    static func main() {
        expect(close(StabilizerConfidencePolicy.unbiased(0.0), 0.0), "zero must remain zero")
        expect(close(StabilizerConfidencePolicy.unbiased(0.5), 0.5), "mid confidence must remain linear")
        expect(close(StabilizerConfidencePolicy.unbiased(1.0), 1.0), "one must remain one")
        expect(close(StabilizerConfidencePolicy.unbiased(-0.25), 0.0), "negative confidence must clamp low")
        expect(close(StabilizerConfidencePolicy.unbiased(1.25), 1.0), "confidence must clamp high")
        expect(close(StabilizerConfidencePolicy.unbiased(.nan), 0.0), "NaN confidence must fail visibly as zero")
        expect(close(StabilizerConfidencePolicy.unbiased(.infinity), 0.0), "infinite confidence must fail visibly as zero")
        expect(
            close(StabilizerConfidencePolicy.unbiasedMean(0.3, 0.6, 0.9), 0.6),
            "axis confidence must use an unbiased arithmetic mean"
        )
        expect(
            close(StabilizerConfidencePolicy.unbiasedMean(0.3, .nan, 0.9), 0.4),
            "nonfinite axis confidence must contribute zero"
        )

        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(0.0), 0.0), "zero X strength must disable correction")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(0.35), 0.35), "subunit X strength must remain direct")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(1.0), 1.0), "unit X strength must remove the full detected path")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(12.0), 12.0), "X strength must not be capped")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(-1.0), 0.0), "negative X strength must disable correction")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(.nan), 0.0), "NaN X strength must fail visibly as zero")
        expect(close(StabilizerConfidencePolicy.unrestrictedXCorrectionFactor(.infinity), 0.0), "infinite X strength must fail visibly as zero")

        let strongLargeImpulse = StabilizerConfidencePolicy.trackedXOutlierDecision(
            value: 241.0,
            neighborhood: [0.0, 0.1, 241.0, -0.1, 0.0],
            trackingConfidence: 0.9,
            walkingTrackingConfidence: 0.8,
            acceptedBlockCount: 12,
            edgeQuality: 1.0
        )
        expect(!strongLargeImpulse.reject, "strong evidence must retain an unrestricted large X impulse")

        let weakLargeImpulse = StabilizerConfidencePolicy.trackedXOutlierDecision(
            value: 241.0,
            neighborhood: [0.0, 0.1, 241.0, -0.1, 0.0],
            trackingConfidence: 0.45,
            walkingTrackingConfidence: 0.50,
            acceptedBlockCount: 2,
            edgeQuality: 0.5
        )
        expect(weakLargeImpulse.reject, "weak tracking evidence must reject an isolated finite X outlier")
        expect(weakLargeImpulse.reason.contains("tracking"), "rejection must expose the tracking reason")

        let weakValidImpulse = StabilizerConfidencePolicy.trackedXOutlierDecision(
            value: 0.35,
            neighborhood: [0.0, 0.1, 0.35, -0.1, 0.0],
            trackingConfidence: 0.2,
            walkingTrackingConfidence: 0.2,
            acceptedBlockCount: 0,
            edgeQuality: 0.0
        )
        expect(!weakValidImpulse.reject, "weak evidence alone must not suppress a temporally consistent X correction")

        if failures.isEmpty {
            print("StabilizerConfidencePolicyTests: PASS")
            return
        }
        for failure in failures {
            fputs("StabilizerConfidencePolicyTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
