import Foundation

@main
struct AutoCropZoomHandoffTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func keypoint(
        peak: Double,
        start: Double,
        holdEnd: Double,
        end: Double,
        scale: Float
    ) -> StabilizerAutoCropZoomHandoffKeypoint {
        StabilizerAutoCropZoomHandoffKeypoint(
            peakSeconds: peak,
            startSeconds: start,
            holdEndSeconds: holdEnd,
            endSeconds: end,
            protectedScale: scale
        )
    }

    static func main() {
        let descending = StabilizerAutoCropZoomHandoff.segments(
            keypoints: [
                keypoint(peak: 0.0, start: 0.0, holdEnd: 2.0, end: 8.0, scale: 1.20),
                keypoint(peak: 5.0, start: 1.0, holdEnd: 7.0, end: 13.0, scale: 1.08),
            ]
        )
        expect(descending.count == 1, "overlapping high-to-low peaks must create one handoff")
        expect(close(StabilizerAutoCropZoomHandoff.scale(baseScale: 1.20, at: 2.0, handoffs: descending).scale, 1.20), "handoff must start at the high protected scale")
        let midpoint = StabilizerAutoCropZoomHandoff.scale(baseScale: 1.20, at: 3.5, handoffs: descending)
        expect(midpoint.applied, "descending handoff must lower the existing max-composed plan")
        expect(close(midpoint.scale, 1.14), "handoff midpoint must ease between the protected peaks")
        expect(close(StabilizerAutoCropZoomHandoff.scale(baseScale: 1.20, at: 5.0, handoffs: descending).scale, 1.08), "handoff must reach the next protected scale instead of returning to 1x")

        let densePlayback = StabilizerAutoCropZoomHandoff.segments(
            keypoints: [
                keypoint(peak: 0.0, start: 0.0, holdEnd: 2.0, end: 8.0, scale: 1.12),
                keypoint(peak: 0.5, start: 0.0, holdEnd: 2.5, end: 8.5, scale: 1.20),
                keypoint(peak: 1.0, start: 0.0, holdEnd: 3.0, end: 9.0, scale: 1.15),
                keypoint(peak: 5.0, start: 1.0, holdEnd: 7.0, end: 13.0, scale: 1.08),
            ]
        )
        expect(densePlayback.count == 1, "dense samples inside one Hold must collapse to their strongest peak")
        expect(close(densePlayback.first?.fromScale ?? .nan, 1.20), "dense handoff must start from the true high peak")

        let floored = StabilizerAutoCropZoomHandoff.scale(
            baseScale: 1.20,
            at: 5.0,
            handoffs: descending,
            coverageFloorScale: 1.09,
            positionRequiredScale: 1.11,
            framingRepairScale: 1.10
        )
        expect(close(floored.scale, 1.11), "coverage, position, and framing floors must remain absolute")

        let shortGap = StabilizerAutoCropZoomHandoff.segments(
            keypoints: [
                keypoint(peak: 0.0, start: 0.0, holdEnd: 2.0, end: 8.0, scale: 1.20),
                keypoint(peak: 3.0, start: 1.0, holdEnd: 5.0, end: 11.0, scale: 1.05),
            ]
        )
        expect(close(shortGap.first.map { Float($0.endSeconds - $0.startSeconds) } ?? .nan, 1.0), "handoff duration must be capped by time remaining to the next peak")

        let rising = StabilizerAutoCropZoomHandoff.segments(
            keypoints: [
                keypoint(peak: 0.0, start: 0.0, holdEnd: 2.0, end: 8.0, scale: 1.08),
                keypoint(peak: 5.0, start: 1.0, holdEnd: 7.0, end: 13.0, scale: 1.20),
            ]
        )
        expect(rising.isEmpty, "equal or larger next peaks must keep existing lookahead behavior")
        expect(close(StabilizerAutoCropZoomHandoff.scale(baseScale: 1.16, at: 3.0, handoffs: rising).scale, 1.16), "no handoff must preserve the current plan")

        let separate = StabilizerAutoCropZoomHandoff.segments(
            keypoints: [
                keypoint(peak: 0.0, start: 0.0, holdEnd: 2.0, end: 4.0, scale: 1.20),
                keypoint(peak: 8.0, start: 6.0, holdEnd: 10.0, end: 12.0, scale: 1.05),
            ]
        )
        expect(separate.isEmpty, "non-overlapping keypoint intervals must keep ordinary release")

        if failures.isEmpty {
            print("AutoCropZoomHandoffTests: PASS")
            return
        }
        for failure in failures {
            fputs("AutoCropZoomHandoffTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
