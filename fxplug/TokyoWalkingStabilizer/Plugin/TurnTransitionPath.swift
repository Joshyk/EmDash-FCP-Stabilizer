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
    let endpointReleaseStartSeconds: Double
    let endpointReleaseEndSeconds: Double
    let endpointReleaseShiftX: Float
    let reversalThresholdX: Float
    let endpointEaseSeconds: Double
    let activeSampleCount: Int
    let renderChainID: Int
    let renderChainEventCount: Int
    let renderChainStartSeconds: Double
    let renderChainEndSeconds: Double
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

    private struct EventWork {
        let group: ActiveGroup
        let startIndex: Int
        let endIndex: Int
        let startSeconds: Double
        let endSeconds: Double
        let cumulativeX: Float
    }

    static func concatenate(
        times: [Double],
        positions: [Float],
        travelPositions: [Float],
        activity: [Float],
        windowSeconds: Double,
        smoothingStrength: Float,
        idleReleaseSeconds: Double = 6.0,
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
        guard idleReleaseSeconds.isFinite, idleReleaseSeconds >= 0.0 else {
            return rejected(positions, "TURN idle release duration is invalid")
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

        // The Window is the maximum accumulation span measured from the first
        // active sample. It must not roll forward with later active samples,
        // otherwise a long turn can grow indefinitely and become visibly slow.
        var clusters: [[Int]] = []
        var cluster: [Int] = []
        for index in activeIndices {
            if let firstIndex = cluster.first,
               times[index] - times[firstIndex] > windowSeconds + 1e-9 {
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

        var work: [EventWork] = []
        work.reserveCapacity(groups.count)
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
            work.append(
                EventWork(
                    group: group,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds,
                    cumulativeX: cumulativeMagnitude * group.direction
                )
            )
        }

        var result = positions
        var events: [StabilizerTurnTransitionEvent] = []
        events.reserveCapacity(work.count)
        var chainStart = work.startIndex
        var chainID = 0
        while chainStart < work.endIndex {
            var chainEnd = chainStart
            while chainEnd + 1 < work.endIndex {
                let current = work[chainEnd]
                let next = work[chainEnd + 1]
                let activeSamplesAreContiguous = next.group.indices[0]
                    == current.group.indices[current.group.indices.count - 1] + 1
                guard next.group.direction == current.group.direction,
                      activeSamplesAreContiguous
                else {
                    break
                }
                chainEnd += 1
            }

            chainID += 1
            let chainRange = chainStart...chainEnd
            let first = work[chainStart]
            let last = work[chainEnd]
            let chainStartIndex = first.startIndex
            let chainEndIndex = last.endIndex
            let chainStartSeconds = first.startSeconds
            let chainEndSeconds = last.endSeconds
            let chainDuration = chainEndSeconds - chainStartSeconds
            let chainCumulativeX = work[chainRange].reduce(Float(0.0)) {
                $0 + $1.cumulativeX
            }
            let startX = result[chainStartIndex]
            let previousChainEndX = result[chainEndIndex]

            // Window still caps each accumulation event. When the cap alone
            // splits uninterrupted same-direction activity, render those
            // events as one chain so an artificial stop is not inserted at
            // every Window boundary. Pauses and reversals keep separate ramps.
            let endpointEaseSeconds = min(0.30, chainDuration * 0.15)
            for index in chainStartIndex...chainEndIndex {
                let progress = constantVelocityProgress(
                    elapsedSeconds: times[index] - chainStartSeconds,
                    durationSeconds: chainDuration,
                    endpointEaseSeconds: endpointEaseSeconds
                )
                result[index] = startX + (chainCumulativeX * progress)
            }
            let propagatedChainEndpointShiftX = result[chainEndIndex] - previousChainEndX

            // Keep the endpoint correction only while it is needed to join a
            // continuous turn.  Holding it indefinitely makes Crop Off expose
            // a stationary black edge long after the camera has become idle.
            // A non-contiguous next chain proves there is a genuine idle span;
            // release the correction at the start of that span and finish
            // before the next chain.  A contiguous chain (including an
            // immediate reversal) has no idle samples and keeps its handoff.
            let nextChainStartIndex = chainEnd + 1 < work.endIndex
                ? work[chainEnd + 1].startIndex
                : result.endIndex
            let firstIdleIndex = chainEndIndex + 1
            let lastIdleIndex = min(result.index(before: result.endIndex), nextChainStartIndex - 1)
            let releaseStartSeconds = chainEndSeconds
            var releaseEndSeconds = chainEndSeconds
            let idleSampleCount = max(0, lastIdleIndex - firstIdleIndex + 1)
            let hasReleaseableIdleSpan = idleSampleCount >= 3
            if hasReleaseableIdleSpan,
               abs(propagatedChainEndpointShiftX) > Float.ulpOfOne {
                let idleEndSeconds = times[lastIdleIndex]
                let releaseDuration = min(
                    idleReleaseSeconds,
                    max(0.0, idleEndSeconds - chainEndSeconds)
                )
                if releaseDuration > 1e-9 {
                    releaseEndSeconds = chainEndSeconds + releaseDuration
                    for index in firstIdleIndex...lastIdleIndex {
                        let progress = Float((times[index] - releaseStartSeconds) / releaseDuration)
                        let retainedCorrection = propagatedChainEndpointShiftX
                            * (1.0 - quinticSmootherStep(progress))
                        result[index] += retainedCorrection
                    }
                }
            } else if abs(propagatedChainEndpointShiftX) > Float.ulpOfOne,
                      chainEndIndex + 1 < result.endIndex,
                      nextChainStartIndex >= chainEndIndex + 1,
                      nextChainStartIndex < result.endIndex {
                // One or two inactive samples are a detector dropout, not a
                // true idle. Carry the endpoint correction into the next
                // chain's anchor so it cannot restart from raw X (often zero)
                // and make the viewport jump at a direction handoff.
                let handoffStart = chainEndIndex + 1
                let handoffEnd = max(handoffStart, nextChainStartIndex)
                for index in handoffStart...handoffEnd {
                    result[index] += propagatedChainEndpointShiftX
                }
            }
            for eventIndex in chainRange {
                let eventWork = work[eventIndex]
                events.append(
                    StabilizerTurnTransitionEvent(
                        direction: eventWork.group.direction,
                        firstActiveIndex: eventWork.group.indices[0],
                        lastActiveIndex: eventWork.group.indices[eventWork.group.indices.count - 1],
                        startIndex: eventWork.startIndex,
                        endIndex: eventWork.endIndex,
                        startSeconds: eventWork.startSeconds,
                        endSeconds: eventWork.endSeconds,
                        cumulativeX: eventWork.cumulativeX,
                        propagatedEndpointShiftX: eventIndex == chainEnd
                            ? propagatedChainEndpointShiftX
                            : 0.0,
                        endpointReleaseStartSeconds: eventIndex == chainEnd
                            ? releaseStartSeconds
                            : eventWork.endSeconds,
                        endpointReleaseEndSeconds: eventIndex == chainEnd
                            ? releaseEndSeconds
                            : eventWork.endSeconds,
                        endpointReleaseShiftX: eventIndex == chainEnd
                            ? propagatedChainEndpointShiftX
                            : 0.0,
                        reversalThresholdX: reversalThresholdX,
                        endpointEaseSeconds: endpointEaseSeconds,
                        activeSampleCount: eventWork.group.indices.count,
                        renderChainID: chainID,
                        renderChainEventCount: chainRange.count,
                        renderChainStartSeconds: chainStartSeconds,
                        renderChainEndSeconds: chainEndSeconds
                    )
                )
            }
            chainStart = chainEnd + 1
        }

        return StabilizerTurnTransitionResult(
            positions: result,
            events: events,
            rejectionReason: nil
        )
    }

    private static func integratedQuinticSmootherStep(_ value: Float) -> Float {
        let t = min(max(value, 0.0), 1.0)
        let t2 = t * t
        let t4 = t2 * t2
        return t4 * ((t2 - (3.0 * t)) + 2.5)
    }

    private static func quinticSmootherStep(_ value: Float) -> Float {
        let t = min(max(value, 0.0), 1.0)
        return t * t * t * (t * ((t * 6.0) - 15.0) + 10.0)
    }

    private static func constantVelocityProgress(
        elapsedSeconds: Double,
        durationSeconds: Double,
        endpointEaseSeconds: Double
    ) -> Float {
        let elapsed = min(max(elapsedSeconds, 0.0), durationSeconds)
        let ease = min(max(endpointEaseSeconds, 0.0), durationSeconds * 0.5)
        guard ease > 1e-9 else {
            return Float(elapsed / durationSeconds)
        }

        // Velocity is quintic only in the endpoint ramps and exactly one in
        // the body. Each ramp has area ease/2, hence total area duration-ease.
        let travelTime = durationSeconds - ease
        let distance: Double
        if elapsed < ease {
            let ramp = Float(elapsed / ease)
            distance = ease * Double(integratedQuinticSmootherStep(ramp))
        } else if elapsed <= durationSeconds - ease {
            distance = (ease * 0.5) + (elapsed - ease)
        } else {
            let ramp = Float((elapsed - (durationSeconds - ease)) / ease)
            let decelerationArea = Double(ramp - integratedQuinticSmootherStep(ramp))
            distance = (durationSeconds - (ease * 1.5)) + (ease * decelerationArea)
        }
        return Float(distance / travelTime)
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
