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
