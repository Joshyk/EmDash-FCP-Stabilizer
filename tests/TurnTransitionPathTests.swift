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
            travelPositions: [0.0, 10.0, 10.0, 10.0, 30.0, 30.0, 30.0, 40.0, 40.0],
            activity: [0.0, 10.0, 0.0, 0.0, 20.0, 0.0, 0.0, 10.0, 0.0],
            windowSeconds: 6.0,
            smoothingStrength: 12.0
        )
        expect(accumulated.rejectionReason == nil, "valid accumulated turn must not be rejected")
        expect(accumulated.events.count == 1, "10 + pause + 20 + pause + 10 must become one event")
        expect(close(accumulated.events.first?.cumulativeX ?? .nan, 40.0), "accumulated event must preserve 40px total travel")
        expect(close(accumulated.positions.first ?? .nan, 0.0), "accumulated event must preserve its start")
        expect(close(accumulated.positions.last ?? .nan, 40.0), "accumulated event must preserve its accumulated endpoint")
        expectStrictlyIncreasing(accumulated.positions, range: 0...8, "accumulated pauses must become one continuous curve")

        let propagatedEndpoint = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init),
            positions: [0.0, 10.0, 8.0, 28.0, 26.0, 36.0, 34.0, 34.0, 34.0],
            travelPositions: [0.0, 10.0, 8.0, 28.0, 26.0, 36.0, 34.0, 34.0, 34.0],
            activity: [0.0, 10.0, 0.0, 20.0, 0.0, 10.0, 0.0, 0.0, 0.0],
            windowSeconds: 5.0,
            smoothingStrength: 12.0
        )
        expect(propagatedEndpoint.events.count == 1, "same-direction travel with relaxation must remain one event")
        expect(close(propagatedEndpoint.events.first?.cumulativeX ?? .nan, 40.0), "relaxation must not erase accumulated travel")
        expect(close(propagatedEndpoint.events.first?.propagatedEndpointShiftX ?? .nan, 6.0), "removed relaxation must propagate past the endpoint")
        expectStrictlyIncreasing(propagatedEndpoint.positions, range: 0...6, "relaxation must become one continuous event curve")
        expect(close(propagatedEndpoint.positions[6], 40.0), "event endpoint must contain all same-direction travel")
        expect(close(propagatedEndpoint.positions[7], 40.0), "first post-event sample must not jump back")
        expect(close(propagatedEndpoint.positions[8], 40.0), "propagated endpoint must remain stable")

        let composedResidual = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init),
            positions: [2.0, 12.7, 10.1, 30.6, 28.4, 38.8, 36.2, 36.2, 36.2],
            travelPositions: [0.0, 10.0, 8.0, 28.0, 26.0, 36.0, 34.0, 34.0, 34.0],
            activity: [0.0, 10.0, 0.0, 20.0, 0.0, 10.0, 0.0, 0.0, 0.0],
            windowSeconds: 5.0,
            smoothingStrength: 12.0
        )
        expect(close(composedResidual.events.first?.cumulativeX ?? .nan, 40.0), "final X residuals must not inflate TURN travel")
        expect(close(composedResidual.positions[0], 2.0), "final composite X must preserve the rendered start")
        expect(close(composedResidual.positions[6], 42.0), "final composite X must end at rendered start plus TURN travel")
        expectStrictlyIncreasing(composedResidual.positions, range: 0...6, "all rendered X bands must collapse into the event S curve")
        expect(close(composedResidual.positions[7], 42.0), "composite endpoint correction must propagate to the tail")

        let signChatter = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(Double.init),
            positions: [0.0, 5.0, 10.0, 9.5, 15.0, 14.5, 20.0, 19.5, 25.0, 30.0, 30.0],
            travelPositions: [0.0, 5.0, 10.0, 9.5, 15.0, 14.5, 20.0, 19.5, 25.0, 30.0, 30.0],
            activity: [0.0, 5.0, 5.0, -0.6, 5.0, -0.6, 5.0, -0.6, 5.0, 5.0, 0.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(signChatter.events.count == 1, "substantial TURN must absorb short opposite-sign chatter")
        expect(signChatter.events.first?.direction == 1.0, "absorbed sign chatter must keep the dominant direction")
        expectStrictlyIncreasing(signChatter.positions, range: 0...10, "sign chatter must not create internal deceleration boundaries")

        let rollingWindow = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(Double.init),
            positions: [0.0, 4.0, 4.0, 8.0, 8.0, 12.0, 12.0, 16.0, 16.0, 20.0, 20.0, 24.0, 24.0],
            travelPositions: [0.0, 4.0, 4.0, 8.0, 8.0, 12.0, 12.0, 16.0, 16.0, 20.0, 20.0, 24.0, 24.0],
            activity: [0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(rollingWindow.events.count == 1, "continuous same-direction activity may exceed one Window span")
        expect((rollingWindow.events.first?.endSeconds ?? 0.0) - (rollingWindow.events.first?.startSeconds ?? 0.0) > 3.0, "Window must measure the pause gap rather than cap event duration")
        expectStrictlyIncreasing(rollingWindow.positions, range: 0...12, "rolling Window must produce one uninterrupted curve")

        let strengthInputTimes = [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init)
        let strengthInputPositions: [Float] = [0.0, 5.0, 10.0, 10.0, 6.0, 6.0, 11.0, 16.0, 16.0]
        let strengthInputActivity: [Float] = [0.0, 5.0, 5.0, 0.0, -4.0, -4.0, 5.0, 5.0, 0.0]
        let standardStrength = StabilizerTurnTransitionPath.concatenate(
            times: strengthInputTimes,
            positions: strengthInputPositions,
            travelPositions: strengthInputPositions,
            activity: strengthInputActivity,
            windowSeconds: 5.0,
            smoothingStrength: 12.0
        )
        let maximumStrength = StabilizerTurnTransitionPath.concatenate(
            times: strengthInputTimes,
            positions: strengthInputPositions.map { $0 * 3.0 },
            travelPositions: strengthInputPositions.map { $0 * 3.0 },
            activity: strengthInputActivity,
            windowSeconds: 5.0,
            smoothingStrength: 36.0
        )
        expect(standardStrength.events.count == 3, "standard Strength must retain a meaningful 4px reversal")
        expect(maximumStrength.events.count == 1, "maximum Strength must absorb the same small reversal into one curve")
        expect((maximumStrength.events.first?.reversalThresholdX ?? 0.0) > (standardStrength.events.first?.reversalThresholdX ?? .infinity), "higher Strength must raise reversal hysteresis")

        let smallMaximumStrengthTurn = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 1.0, 2.0, 3.0],
            positions: [0.0, 5.0, 10.0, 10.0],
            travelPositions: [0.0, 5.0, 10.0, 10.0],
            activity: [0.0, 5.0, 5.0, 0.0],
            windowSeconds: 5.0,
            smoothingStrength: 36.0
        )
        expect(smallMaximumStrengthTurn.events.count == 1, "maximum Strength must not discard a small one-direction turn")

        let variableSpeed = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.4, 1.1, 2.3, 3.0, 4.8],
            positions: [0.0, 2.0, 18.0, 21.0, 55.0, 60.0],
            travelPositions: [0.0, 2.0, 18.0, 21.0, 55.0, 60.0],
            activity: [0.0, 2.0, 16.0, 3.0, 34.0, 5.0],
            windowSeconds: 5.0,
            smoothingStrength: 12.0
        )
        expect(variableSpeed.events.count == 1, "same-direction speed changes must remain one event")
        expectStrictlyIncreasing(variableSpeed.positions, range: 0...5, "speed changes must not leave an internal stop")

        let reversed = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6].map(Double.init),
            positions: [0.0, 10.0, 20.0, 20.0, 10.0, 0.0, 0.0],
            travelPositions: [0.0, 10.0, 20.0, 20.0, 10.0, 0.0, 0.0],
            activity: [0.0, 10.0, 10.0, 0.0, -10.0, -10.0, 0.0],
            windowSeconds: 6.0,
            smoothingStrength: 12.0
        )
        expect(reversed.events.count == 2, "direction reversal must split the transition")
        expect(reversed.events.map(\.direction) == [1.0, -1.0], "reversed events must retain their directions")

        let outsideWindow = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init),
            positions: [0.0, 5.0, 10.0, 10.0, 10.0, 10.0, 15.0, 20.0, 20.0],
            travelPositions: [0.0, 5.0, 10.0, 10.0, 10.0, 10.0, 15.0, 20.0, 20.0],
            activity: [0.0, 5.0, 5.0, 0.0, 0.0, 0.0, 5.0, 5.0, 0.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(outsideWindow.events.count == 2, "same-direction motion outside the event span must split")

        let subthresholdPositions: [Float] = [0.0, 0.1, 0.2, 0.1, 0.0]
        let subthreshold = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4].map(Double.init),
            positions: subthresholdPositions,
            travelPositions: subthresholdPositions,
            activity: [0.0, 0.1, 0.2, -0.1, 0.0],
            windowSeconds: 4.0,
            smoothingStrength: 12.0
        )
        expect(subthreshold.events.isEmpty, "sub-threshold jitter must not create a TURN event")
        expect(subthreshold.positions == subthresholdPositions, "sub-threshold jitter must remain unchanged")

        let clipEdge = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.35, 1.2, 2.8],
            positions: [0.0, 4.0, 11.0, 15.0],
            travelPositions: [0.0, 4.0, 11.0, 15.0],
            activity: [4.0, 4.0, 7.0, 4.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(clipEdge.events.count == 1, "clip-edge event with irregular timing must be supported")
        expect(close(clipEdge.positions[0], 0.0), "clip-edge event must preserve first position")
        expect(close(clipEdge.positions[3], 15.0), "clip-edge event must preserve final position")
        expectStrictlyIncreasing(clipEdge.positions, range: 0...3, "irregular timing must still create a continuous curve")

        let rejected = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 0.0, 1.0],
            positions: [0.0, 1.0, 2.0],
            travelPositions: [0.0, 1.0, 2.0],
            activity: [0.0, 1.0, 1.0],
            windowSeconds: 2.0,
            smoothingStrength: 12.0
        )
        expect(rejected.rejectionReason != nil, "non-increasing time must fail visibly")
        expect(rejected.positions == [0.0, 1.0, 2.0], "rejected input must not be partially rewritten")

        let mismatchedTravel = StabilizerTurnTransitionPath.concatenate(
            times: [0.0, 1.0, 2.0],
            positions: [0.0, 1.0, 2.0],
            travelPositions: [0.0, 1.0],
            activity: [0.0, 1.0, 1.0],
            windowSeconds: 2.0,
            smoothingStrength: 12.0
        )
        expect(mismatchedTravel.rejectionReason != nil, "mismatched travel path must fail visibly")

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
