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
    let reversalThresholdX: Float
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

    private struct SignedRun {
        let direction: Float
        let indices: [Int]
    }

    static func concatenate(
        times: [Double],
        positions: [Float],
        travelPositions: [Float],
        activity: [Float],
        windowSeconds: Double,
        smoothingStrength: Float,
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
        guard smoothingStrength.isFinite, smoothingStrength >= 0.0 else {
            return rejected(positions, "TURN smoothing strength is invalid")
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

        // The Window is a rolling maximum pause between active samples. A
        // continuously active turn may therefore be longer than the Window;
        // only a pause longer than the Window starts a new cluster.
        var clusters: [[Int]] = []
        var cluster: [Int] = []
        for index in activeIndices {
            if let previousIndex = cluster.last,
               times[index] - times[previousIndex] > windowSeconds + 1e-9 {
                clusters.append(cluster)
                cluster = []
            }
            cluster.append(index)
        }
        if !cluster.isEmpty {
            clusters.append(cluster)
        }

        let normalizedStrength = max(0.0, smoothingStrength / 12.0)
        let reversalThresholdX = max(
            activityThreshold * 4.0,
            2.4 * normalizedStrength * normalizedStrength
        )

        func directionalMagnitude(_ run: SignedRun) -> Float {
            let startIndex = max(positions.startIndex, run.indices[0] - 1)
            let endIndex = min(
                positions.index(before: positions.endIndex),
                run.indices[run.indices.count - 1] + 1
            )
            guard endIndex > startIndex else {
                return 0.0
            }
            var magnitude = Float(0.0)
            for index in (startIndex + 1)...endIndex {
                let delta = (travelPositions[index] - travelPositions[index - 1]) * run.direction
                magnitude += max(0.0, delta)
            }
            return magnitude
        }

        var groups: [ActiveGroup] = []
        for cluster in clusters {
            var runs: [SignedRun] = []
            var runDirection = Float(0.0)
            var runIndices: [Int] = []
            for index in cluster {
                let direction: Float = activity[index] >= 0.0 ? 1.0 : -1.0
                if !runIndices.isEmpty, direction != runDirection {
                    runs.append(SignedRun(direction: runDirection, indices: runIndices))
                    runIndices = []
                }
                runDirection = direction
                runIndices.append(index)
            }
            if !runIndices.isEmpty {
                runs.append(SignedRun(direction: runDirection, indices: runIndices))
            }

            let runMagnitudes = runs.map(directionalMagnitude)
            guard let dominantRun = runMagnitudes.indices.max(by: {
                runMagnitudes[$0] < runMagnitudes[$1]
            }) else {
                continue
            }
            let firstSignificantRun = runs.indices.first(where: {
                runMagnitudes[$0] >= reversalThresholdX
            }) ?? dominantRun

            var currentDirection = runs[firstSignificantRun].direction
            var currentIndices = Array(runs[..<firstSignificantRun].flatMap(\.indices))
            currentIndices.append(contentsOf: runs[firstSignificantRun].indices)
            var pendingOppositeIndices: [Int] = []

            for (runOffset, run) in runs.dropFirst(firstSignificantRun + 1).enumerated() {
                let runIndex = firstSignificantRun + 1 + runOffset
                if run.direction == currentDirection {
                    currentIndices.append(contentsOf: pendingOppositeIndices)
                    pendingOppositeIndices.removeAll(keepingCapacity: true)
                    currentIndices.append(contentsOf: run.indices)
                    continue
                }
                if runMagnitudes[runIndex] < reversalThresholdX {
                    pendingOppositeIndices.append(contentsOf: run.indices)
                    continue
                }
                currentIndices.append(contentsOf: pendingOppositeIndices)
                pendingOppositeIndices.removeAll(keepingCapacity: true)
                groups.append(ActiveGroup(direction: currentDirection, indices: currentIndices))
                currentDirection = run.direction
                currentIndices = run.indices
            }
            currentIndices.append(contentsOf: pendingOppositeIndices)
            groups.append(ActiveGroup(direction: currentDirection, indices: currentIndices))
        }

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
                    reversalThresholdX: reversalThresholdX,
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
