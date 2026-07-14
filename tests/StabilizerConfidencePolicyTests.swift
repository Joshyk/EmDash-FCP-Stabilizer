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
