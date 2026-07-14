import Foundation

@main
struct TurnTransitionPathTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func expectStrictlyIncreasing(
        _ values: [Float],
        range: ClosedRange<Int>,
        _ message: String
    ) {
        guard range.lowerBound < range.upperBound else {
            failures.append("\(message): invalid test range")
            return
        }
        for index in (range.lowerBound + 1)...range.upperBound where values[index] <= values[index - 1] {
            failures.append("\(message): stopped or reversed at index \(index)")
            return
        }
    }

    static func main() {
        let accumulated = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.7, 1.5, 2.4, 3.1, 4.0, 5.2, 6.4, 7.0],
            positions: [0.0, 10.0, 10.0, 10.0, 30.0, 30.0, 30.0, 40.0, 40.0],
            activity: [0.0, 10.0, 0.0, 0.0, 20.0, 0.0, 0.0, 10.0, 0.0],
            windowSeconds: 6.0
        )
        expect(accumulated.rejectionReason == nil, "valid accumulated turn must not be rejected")
        expect(accumulated.events.count == 1, "10 + pause + 20 + pause + 10 must become one event")
        expect(close(accumulated.events.first?.cumulativeX ?? .nan, 40.0), "accumulated event must preserve 40px total travel")
        expect(close(accumulated.positions.first ?? .nan, 0.0), "accumulated event must preserve its start")
        expect(close(accumulated.positions.last ?? .nan, 40.0), "accumulated event must preserve its accumulated endpoint")
        expectStrictlyIncreasing(accumulated.positions, range: 0...8, "accumulated pauses must become one continuous curve")

        let variableSpeed = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.4, 1.1, 2.3, 3.0, 4.8],
            positions: [0.0, 2.0, 18.0, 21.0, 55.0, 60.0],
            activity: [0.0, 2.0, 16.0, 3.0, 34.0, 5.0],
            windowSeconds: 5.0
        )
        expect(variableSpeed.events.count == 1, "same-direction speed changes must remain one event")
        expectStrictlyIncreasing(variableSpeed.positions, range: 0...5, "speed changes must not leave an internal stop")

        let reversed = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6].map(Double.init),
            positions: [0.0, 10.0, 20.0, 20.0, 10.0, 0.0, 0.0],
            activity: [0.0, 10.0, 10.0, 0.0, -10.0, -10.0, 0.0],
            windowSeconds: 6.0
        )
        expect(reversed.events.count == 2, "direction reversal must split the transition")
        expect(reversed.events.map(\.direction) == [1.0, -1.0], "reversed events must retain their directions")

        let outsideWindow = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init),
            positions: [0.0, 5.0, 10.0, 10.0, 10.0, 10.0, 15.0, 20.0, 20.0],
            activity: [0.0, 5.0, 5.0, 0.0, 0.0, 0.0, 5.0, 5.0, 0.0],
            windowSeconds: 3.0
        )
        expect(outsideWindow.events.count == 2, "same-direction motion outside the event span must split")

        let subthresholdPositions: [Float] = [0.0, 0.1, 0.2, 0.1, 0.0]
        let subthreshold = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4].map(Double.init),
            positions: subthresholdPositions,
            activity: [0.0, 0.1, 0.2, -0.1, 0.0],
            windowSeconds: 4.0
        )
        expect(subthreshold.events.isEmpty, "sub-threshold jitter must not create a TURN event")
        expect(subthreshold.positions == subthresholdPositions, "sub-threshold jitter must remain unchanged")

        let clipEdge = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.35, 1.2, 2.8],
            positions: [0.0, 4.0, 11.0, 15.0],
            activity: [4.0, 4.0, 7.0, 4.0],
            windowSeconds: 3.0
        )
        expect(clipEdge.events.count == 1, "clip-edge event with irregular timing must be supported")
        expect(close(clipEdge.positions[0], 0.0), "clip-edge event must preserve first position")
        expect(close(clipEdge.positions[3], 15.0), "clip-edge event must preserve final position")
        expectStrictlyIncreasing(clipEdge.positions, range: 0...3, "irregular timing must still create a continuous curve")

        let rejected = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.0, 1.0],
            positions: [0.0, 1.0, 2.0],
            activity: [0.0, 1.0, 1.0],
            windowSeconds: 2.0
        )
        expect(rejected.rejectionReason != nil, "non-increasing time must fail visibly")
        expect(rejected.positions == [0.0, 1.0, 2.0], "rejected input must not be partially rewritten")

        if failures.isEmpty {
            print("TurnTransitionPathTests: PASS")
            return
        }
        for failure in failures {
            fputs("TurnTransitionPathTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
