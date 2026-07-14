import Foundation

struct StabilizerTurnTransitionEvent {
    let direction: Float
    let firstActiveIndex: Int
    let lastActiveIndex: Int
    let startIndex: Int
    let endIndex: Int
    let startSeconds: Double
    let endSeconds: Double
    let cumulativeX: Float
    let propagatedEndpointShiftX: Float
    let activeSampleCount: Int
}

struct StabilizerTurnTransitionResult {
    let positions: [Float]
    let events: [StabilizerTurnTransitionEvent]
    let rejectionReason: String?
}

enum StabilizerTurnTransitionPath {
    private struct ActiveGroup {
        let direction: Float
        let indices: [Int]
    }

    static func concatenate(
        times: [Double],
        positions: [Float],
        travelPositions: [Float],
        activity: [Float],
        windowSeconds: Double,
        activityThreshold: Float = 0.5
    ) -> StabilizerTurnTransitionResult {
        guard times.count == positions.count,
              positions.count == travelPositions.count,
              positions.count == activity.count
        else {
            return rejected(positions, "TURN transition arrays have different lengths")
        }
        guard positions.count >= 3 else {
            return StabilizerTurnTransitionResult(
                positions: positions,
                events: [],
                rejectionReason: nil
            )
        }
        guard windowSeconds.isFinite, windowSeconds > 0.0 else {
            return rejected(positions, "TURN transition window is not a positive finite value")
        }
        guard activityThreshold.isFinite, activityThreshold >= 0.0 else {
            return rejected(positions, "TURN activity threshold is invalid")
        }
        for index in times.indices {
            guard times[index].isFinite,
                  positions[index].isFinite,
                  travelPositions[index].isFinite,
                  activity[index].isFinite
            else {
                return rejected(positions, "TURN transition input contains a non-finite sample")
            }
            if index > times.startIndex, times[index] <= times[index - 1] {
                return rejected(positions, "TURN transition times are not strictly increasing")
            }
        }

        let activeIndices = activity.indices.filter {
            abs(activity[$0]) >= activityThreshold
        }
        guard !activeIndices.isEmpty else {
            return StabilizerTurnTransitionResult(
                positions: positions,
                events: [],
                rejectionReason: nil
            )
        }

        var groups: [ActiveGroup] = []
        var currentDirection = Float(0.0)
        var currentIndices: [Int] = []
        var groupStartSeconds = Double(0.0)

        func appendCurrentGroup() {
            guard !currentIndices.isEmpty else {
                return
            }
            groups.append(
                ActiveGroup(
                    direction: currentDirection,
                    indices: currentIndices
                )
            )
            currentIndices.removeAll(keepingCapacity: true)
        }

        for index in activeIndices {
            let direction: Float = activity[index] >= 0.0 ? 1.0 : -1.0
            if currentIndices.isEmpty {
                currentDirection = direction
                currentIndices = [index]
                groupStartSeconds = times[index]
                continue
            }
            let withinWindow = times[index] - groupStartSeconds <= windowSeconds + 1e-9
            if direction == currentDirection, withinWindow {
                currentIndices.append(index)
            } else {
                appendCurrentGroup()
                currentDirection = direction
                currentIndices = [index]
                groupStartSeconds = times[index]
            }
        }
        appendCurrentGroup()

        var boundaries = groups.map { group in
            (
                start: max(positions.startIndex, group.indices[0] - 1),
                end: min(positions.index(before: positions.endIndex), group.indices[group.indices.count - 1] + 1)
            )
        }
        if boundaries.count > 1 {
            for index in boundaries.indices.dropLast() {
                let nextIndex = boundaries.index(after: index)
                guard boundaries[index].end >= boundaries[nextIndex].start else {
                    continue
                }
                let boundary = (groups[index].indices[groups[index].indices.count - 1]
                    + groups[nextIndex].indices[0]) / 2
                boundaries[index].end = boundary
                boundaries[nextIndex].start = boundary
            }
        }

        var result = positions
        var events: [StabilizerTurnTransitionEvent] = []
        events.reserveCapacity(groups.count)

        for (groupIndex, group) in groups.enumerated() {
            let startIndex = boundaries[groupIndex].start
            let endIndex = boundaries[groupIndex].end
            guard endIndex > startIndex else {
                continue
            }

            var cumulativeMagnitude = Float(0.0)
            for index in (startIndex + 1)...endIndex {
                let directionalDelta = (travelPositions[index] - travelPositions[index - 1]) * group.direction
                cumulativeMagnitude += max(0.0, directionalDelta)
            }
            guard cumulativeMagnitude >= activityThreshold else {
                continue
            }

            let startSeconds = times[startIndex]
            let endSeconds = times[endIndex]
            let duration = endSeconds - startSeconds
            guard duration > 1e-9 else {
                continue
            }
            let startX = result[startIndex]
            let cumulativeX = cumulativeMagnitude * group.direction
            let previousEndX = result[endIndex]
            for index in startIndex...endIndex {
                let normalizedTime = Float((times[index] - startSeconds) / duration)
                let progress = quinticSmootherStep(normalizedTime)
                result[index] = startX + (cumulativeX * progress)
            }
            let propagatedEndpointShiftX = result[endIndex] - previousEndX
            if endIndex + 1 < result.endIndex {
                for index in (endIndex + 1)..<result.endIndex {
                    result[index] += propagatedEndpointShiftX
                }
            }
            events.append(
                StabilizerTurnTransitionEvent(
                    direction: group.direction,
                    firstActiveIndex: group.indices[0],
                    lastActiveIndex: group.indices[group.indices.count - 1],
                    startIndex: startIndex,
                    endIndex: endIndex,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds,
                    cumulativeX: cumulativeX,
                    propagatedEndpointShiftX: propagatedEndpointShiftX,
                    activeSampleCount: group.indices.count
                )
            )
        }

        return StabilizerTurnTransitionResult(
            positions: result,
            events: events,
            rejectionReason: nil
        )
    }

    private static func quinticSmootherStep(_ value: Float) -> Float {
        let t = min(max(value, 0.0), 1.0)
        return t * t * t * (t * ((t * 6.0) - 15.0) + 10.0)
    }

    private static func rejected(
        _ positions: [Float],
        _ reason: String
    ) -> StabilizerTurnTransitionResult {
        StabilizerTurnTransitionResult(
            positions: positions,
            events: [],
            rejectionReason: reason
        )
    }
}
