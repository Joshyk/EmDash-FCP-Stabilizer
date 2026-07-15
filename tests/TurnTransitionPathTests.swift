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

    private static func segmentSpeed(_ values: [Float], times: [Double], from index: Int) -> Float {
        (values[index + 1] - values[index]) / Float(times[index + 1] - times[index])
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
            smoothingStrength: 12.0,
            idleReleaseSeconds: 0.5
        )
        expect(propagatedEndpoint.events.count == 1, "same-direction travel with relaxation must remain one event")
        expect(close(propagatedEndpoint.events.first?.cumulativeX ?? .nan, 40.0), "relaxation must not erase accumulated travel")
        expect(close(propagatedEndpoint.events.first?.propagatedEndpointShiftX ?? .nan, 6.0), "removed relaxation must be measured at the endpoint")
        expectStrictlyIncreasing(propagatedEndpoint.positions, range: 0...6, "relaxation must become one continuous event curve")
        expect(close(propagatedEndpoint.positions[6], 40.0), "event endpoint must contain all same-direction travel")
        expect(close(propagatedEndpoint.positions[7], 34.0), "idle after an event must return to the original X path")
        expect(close(propagatedEndpoint.positions[8], 34.0), "released endpoint correction must not remain as a static tail")

        let composedResidual = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init),
            positions: [2.0, 12.7, 10.1, 30.6, 28.4, 38.8, 36.2, 36.2, 36.2],
            travelPositions: [0.0, 10.0, 8.0, 28.0, 26.0, 36.0, 34.0, 34.0, 34.0],
            activity: [0.0, 10.0, 0.0, 20.0, 0.0, 10.0, 0.0, 0.0, 0.0],
            windowSeconds: 5.0,
            smoothingStrength: 12.0,
            idleReleaseSeconds: 0.5
        )
        expect(close(composedResidual.events.first?.cumulativeX ?? .nan, 40.0), "final X residuals must not inflate TURN travel")
        expect(close(composedResidual.positions[0], 2.0), "final composite X must preserve the rendered start")
        expect(close(composedResidual.positions[6], 42.0), "final composite X must end at rendered start plus TURN travel")
        expectStrictlyIncreasing(composedResidual.positions, range: 0...6, "all rendered X bands must collapse into the event S curve")
        expect(close(composedResidual.positions[7], 36.2), "composite endpoint correction must release during idle")

        let releasedIdle = StabilizerTurnTransitionPath.concatenate(
            times: (0...30).map { Double($0) * 0.1 },
            positions: [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 14.0, 14.0, 14.0, 14.0, 14.0,
                        14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0,
                        14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0],
            travelPositions: [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 14.0, 14.0, 14.0, 14.0, 14.0,
                              14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0,
                              14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0, 14.0],
            activity: [0.0, 4.0, 4.0, 4.0, 4.0, 4.0] + Array(repeating: 0.0, count: 25),
            windowSeconds: 5.0,
            smoothingStrength: 12.0,
            idleReleaseSeconds: 0.5
        )
        expect(releasedIdle.events.count == 1, "idle-release fixture must contain one turn")
        expect(
            releasedIdle.events.first?.endpointReleaseEndSeconds ?? .infinity
                > releasedIdle.events.first?.endpointReleaseStartSeconds ?? -.infinity,
            "a genuine idle span must schedule an endpoint release"
        )
        expect(
            releasedIdle.positions[6] > releasedIdle.positions[7]
                && releasedIdle.positions[7] > releasedIdle.positions[8]
                && releasedIdle.positions[8] > releasedIdle.positions[9],
            "endpoint correction must recede smoothly through idle samples"
        )
        expect(close(releasedIdle.positions[11], 14.0), "idle release must converge to the original X path")
        expect(
            releasedIdle.positions[11...].allSatisfy { close($0, 14.0) },
            "idle release must not leave a stationary black-edge offset"
        )

        let signChatter = StabilizerTurnTransitionPath.concatenate(
            times: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(Double.init),
            positions: [0.0, 5.0, 10.0, 9.5, 15.0, 14.5, 20.0, 19.5, 25.0, 30.0, 30.0],
            travelPositions: [0.0, 5.0, 10.0, 9.5, 15.0, 14.5, 20.0, 19.5, 25.0, 30.0, 30.0],
            activity: [0.0, 5.0, 5.0, -0.6, 5.0, -0.6, 5.0, -0.6, 5.0, 5.0, 0.0],
            windowSeconds: 10.0,
            smoothingStrength: 12.0
        )
        expect(signChatter.events.count == 1, "substantial TURN must absorb short opposite-sign chatter")
        expect(signChatter.events.first?.direction == 1.0, "absorbed sign chatter must keep the dominant direction")
        expectStrictlyIncreasing(signChatter.positions, range: 0...10, "sign chatter must not create internal deceleration boundaries")

        let boundedWindowTimes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(Double.init)
        let boundedWindow = StabilizerTurnTransitionPath.concatenate(
            times: boundedWindowTimes,
            positions: [0.0, 4.0, 4.0, 8.0, 8.0, 12.0, 12.0, 16.0, 16.0, 20.0, 20.0, 24.0, 24.0],
            travelPositions: [0.0, 4.0, 4.0, 8.0, 8.0, 12.0, 12.0, 16.0, 16.0, 20.0, 20.0, 24.0, 24.0],
            activity: [0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(boundedWindow.events.count == 3, "activity beyond the first-sample Window must start a new event")
        expect(
            boundedWindow.events.allSatisfy {
                let first = $0.firstActiveIndex
                let last = $0.lastActiveIndex
                return boundedWindowTimes[last] - boundedWindowTimes[first] <= 3.0
            },
            "every event must keep active samples inside the first-sample Window"
        )
        expectStrictlyIncreasing(boundedWindow.positions, range: 0...12, "bounded Window events must preserve monotonic travel")

        let uninterruptedWindowSplitTimes = (0...12).map(Double.init)
        let uninterruptedWindowSplit = StabilizerTurnTransitionPath.concatenate(
            times: uninterruptedWindowSplitTimes,
            positions: (0...12).map { Float($0 * 4) },
            travelPositions: (0...12).map { Float($0 * 4) },
            activity: [0.0] + Array(repeating: Float(4.0), count: 11) + [0.0],
            windowSeconds: 3.0,
            smoothingStrength: 12.0
        )
        expect(
            uninterruptedWindowSplit.events.count == 3,
            "Window must still report uninterrupted activity as bounded events"
        )
        expect(
            Set(uninterruptedWindowSplit.events.map(\.renderChainID)).count == 1,
            "adjacent same-direction Window events must share one render chain"
        )
        expect(
            uninterruptedWindowSplit.events.allSatisfy { $0.renderChainEventCount == 3 },
            "render-chain diagnostics must expose every joined Window event"
        )
        let uninterruptedBodySpeeds = (1...10).map {
            segmentSpeed(
                uninterruptedWindowSplit.positions,
                times: uninterruptedWindowSplitTimes,
                from: $0
            )
        }
        expect(
            uninterruptedBodySpeeds.allSatisfy {
                close($0, uninterruptedBodySpeeds[0], tolerance: 0.001)
            },
            "Window boundaries must not insert a speed drop into uninterrupted same-direction activity"
        )

        let strengthInputTimes = [0, 1, 2, 3, 4, 5, 6, 7, 8].map(Double.init)
        let strengthInputPositions: [Float] = [0.0, 5.0, 10.0, 10.0, 6.0, 6.0, 11.0, 16.0, 16.0]
        let strengthInputActivity: [Float] = [0.0, 5.0, 5.0, 0.0, -4.0, -4.0, 5.0, 5.0, 0.0]
        let standardStrength = StabilizerTurnTransitionPath.concatenate(
            times: strengthInputTimes,
            positions: strengthInputPositions,
            travelPositions: strengthInputPositions,
            activity: strengthInputActivity,
            windowSeconds: 8.0,
            smoothingStrength: 12.0
        )
        let maximumStrength = StabilizerTurnTransitionPath.concatenate(
            times: strengthInputTimes,
            positions: strengthInputPositions.map { $0 * 3.0 },
            travelPositions: strengthInputPositions.map { $0 * 3.0 },
            activity: strengthInputActivity,
            windowSeconds: 8.0,
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
        let variableSpeedTimes = [0.0, 0.4, 1.1, 2.3, 3.0, 4.8]
        let variableSpeedBody = [1, 2, 3].map {
            segmentSpeed(variableSpeed.positions, times: variableSpeedTimes, from: $0)
        }
        expect(
            variableSpeedBody.allSatisfy { close($0, variableSpeedBody[0], tolerance: 0.001) },
            "concatenated turn body must replace input speed changes with one constant velocity"
        )

        let constantBodyTimes = [0.0, 0.1, 0.3, 0.6, 1.0, 1.4, 1.7, 1.9, 2.0]
        let constantBody = StabilizerTurnTransitionPath.concatenate(
            times: constantBodyTimes,
            positions: [0.0, 2.0, 8.0, 8.0, 8.0, 35.0, 35.0, 39.0, 40.0],
            travelPositions: [0.0, 2.0, 8.0, 8.0, 8.0, 35.0, 35.0, 39.0, 40.0],
            activity: [0.0, 2.0, 6.0, 0.0, 0.0, 27.0, 0.0, 4.0, 1.0],
            windowSeconds: 5.0,
            smoothingStrength: 12.0
        )
        let bodySpeeds = [2, 3, 4, 5].map {
            segmentSpeed(constantBody.positions, times: constantBodyTimes, from: $0)
        }
        expect(
            bodySpeeds.allSatisfy { close($0, bodySpeeds[0], tolerance: 0.001) },
            "irregular frame timing must keep the middle of a concatenated turn at constant velocity"
        )
        expect(
            segmentSpeed(constantBody.positions, times: constantBodyTimes, from: 0) < bodySpeeds[0],
            "only the short endpoint ramp may be slower than the constant-velocity body"
        )

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
        expect(
            reversed.events.allSatisfy {
                close(Float($0.endpointReleaseEndSeconds - $0.endpointReleaseStartSeconds), 0.0)
            },
            "an immediate reversal must hand off without an idle endpoint release"
        )

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
