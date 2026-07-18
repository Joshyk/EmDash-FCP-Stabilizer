import Foundation

@main
struct AutoCropScalePolicyTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.00001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    static func main() {
        expect(close(StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: 1.0), 1.0), "identity demand must not create base crop")
        expect(close(StabilizerAutoCropScalePolicy.playbackMinimumClippedScale(1.0), 1.0), "identity playback scale must remain 1.0")
        expect(close(StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: .nan), 1.0), "invalid demand must not create guessed crop")

        let tinyInactiveDemand = Float(1.0) + (StabilizerAutoCropScalePolicy.coverageActivationDelta * 0.5)
        expect(close(StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: tinyInactiveDemand), 1.0), "sub-threshold numerical noise must not create crop")

        let onePixelBoundaryGuardAt1080p = Float(1080.0 / 1078.0)
        expect(
            close(
                StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: onePixelBoundaryGuardAt1080p),
                onePixelBoundaryGuardAt1080p
            ),
            "one-pixel boundary guard must not receive extra keypoint padding"
        )
        expect(
            close(
                StabilizerAutoCropScalePolicy.playbackMinimumClippedScale(onePixelBoundaryGuardAt1080p),
                onePixelBoundaryGuardAt1080p
            ),
            "one-pixel boundary guard must not receive adaptive playback padding"
        )

        let requiredScale: Float = 1.012
        let protectedScale = StabilizerAutoCropScalePolicy.keypointScale(forDemandScale: requiredScale)
        expect(protectedScale >= requiredScale - StabilizerAutoCropScalePolicy.coverageToleranceDelta, "active crop must preserve the measured coverage floor")
        let playbackScale = StabilizerAutoCropScalePolicy.playbackMinimumClippedScale(protectedScale)
        expect(playbackScale >= protectedScale, "playback safety must never reduce active required crop")
        expect(playbackScale <= Float(1.0) + StabilizerAutoCropScalePolicy.playbackMinimumClipScaleDelta + 0.00001, "adaptive safety must respect its maximum floor")

        let reserved = StabilizerAutoCropScalePolicy.reservedDemandScales(
            times: [0, 1, 2, 3, 4, 5].map(Double.init),
            demandScales: [1.0, 1.02, 1.0, 1.08, 1.0, 1.0],
            leadSeconds: 1.0,
            holdSeconds: 1.0,
            releaseSeconds: 1.0
        )
        expect(reserved != nil, "finite ordered demand must produce a reservation")
        expect(close(reserved?[0] ?? .nan, 1.02), "lead must reserve the next accepted X demand")
        expect(close(reserved?[2] ?? .nan, 1.08), "lead must reserve the stronger upcoming demand")
        expect(close(reserved?[4] ?? .nan, 1.08), "hold and release must retain the interval maximum")
        expect(close(reserved?[5] ?? .nan, 1.08), "release endpoint must keep the reserved coverage floor")
        expect(
            StabilizerAutoCropScalePolicy.reservedDemandScales(
                times: [0.0, 2.0, 1.0],
                demandScales: [1.0, 1.1, 1.0],
                leadSeconds: 1.0,
                holdSeconds: 1.0,
                releaseSeconds: 1.0
            ) == nil,
            "unordered demand must fail explicitly"
        )

        if failures.isEmpty {
            print("AutoCropScalePolicyTests: PASS")
            return
        }
        for failure in failures {
            fputs("AutoCropScalePolicyTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
