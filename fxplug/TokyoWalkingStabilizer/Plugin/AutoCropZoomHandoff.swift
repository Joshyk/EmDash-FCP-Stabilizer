import Foundation
import simd

struct StabilizerAutoCropZoomHandoffKeypoint {
    let peakSeconds: Double
    let startSeconds: Double
    let holdEndSeconds: Double
    let endSeconds: Double
    let protectedScale: Float
    let protectedPositionPixels: vector_float2
}

struct StabilizerAutoCropZoomHandoffResult {
    let scale: Float
    let positionPixels: vector_float2
    let progress: Float
    let applied: Bool
    let fromPeakSeconds: Double?
    let toPeakSeconds: Double?
}

struct StabilizerAutoCropZoomHandoffSegment {
    let startSeconds: Double
    let endSeconds: Double
    let fromScale: Float
    let toScale: Float
    let fromPositionPixels: vector_float2
    let toPositionPixels: vector_float2
    let fromPeakSeconds: Double
    let toPeakSeconds: Double
}

enum StabilizerAutoCropZoomHandoff {
    static func segments(
        keypoints: [StabilizerAutoCropZoomHandoffKeypoint]
    ) -> [StabilizerAutoCropZoomHandoffSegment] {
        guard keypoints.count > 1 else {
            return []
        }
        let ordered = keypoints.sorted { $0.peakSeconds < $1.peakSeconds }
        var peakGroups: [StabilizerAutoCropZoomHandoffKeypoint] = []
        var groupAnchorHoldEnd = -Double.infinity
        var groupPeak: StabilizerAutoCropZoomHandoffKeypoint?
        for keypoint in ordered {
            if groupPeak == nil || keypoint.peakSeconds > groupAnchorHoldEnd + 1e-9 {
                if let groupPeak {
                    peakGroups.append(groupPeak)
                }
                groupPeak = keypoint
                groupAnchorHoldEnd = keypoint.holdEndSeconds
            } else if let selected = groupPeak,
                      keypoint.protectedScale > selected.protectedScale
            {
                groupPeak = keypoint
            }
        }
        if let groupPeak {
            peakGroups.append(groupPeak)
        }
        guard peakGroups.count > 1 else {
            return []
        }
        var segments: [StabilizerAutoCropZoomHandoffSegment] = []
        segments.reserveCapacity(peakGroups.count - 1)
        for index in peakGroups.indices.dropLast() {
            let current = peakGroups[index]
            let next = peakGroups[peakGroups.index(after: index)]
            guard current.peakSeconds.isFinite,
                  current.startSeconds.isFinite,
                  current.holdEndSeconds.isFinite,
                  current.endSeconds.isFinite,
                  current.protectedScale.isFinite,
                  next.peakSeconds.isFinite,
                  next.startSeconds.isFinite,
                  next.protectedScale.isFinite,
                  current.protectedScale > next.protectedScale + 0.00001,
                  next.startSeconds <= current.endSeconds + 1e-9,
                  next.peakSeconds > current.holdEndSeconds + 1e-9
            else {
                continue
            }
            let availableSeconds = next.peakSeconds - current.holdEndSeconds
            let zoomOutSeconds = max(0.0, current.endSeconds - current.holdEndSeconds)
            let handoffDuration = min(zoomOutSeconds, availableSeconds)
            segments.append(
                StabilizerAutoCropZoomHandoffSegment(
                    startSeconds: current.holdEndSeconds,
                    endSeconds: current.holdEndSeconds + handoffDuration,
                    fromScale: current.protectedScale,
                    toScale: next.protectedScale,
                    fromPositionPixels: current.protectedPositionPixels,
                    toPositionPixels: next.protectedPositionPixels,
                    fromPeakSeconds: current.peakSeconds,
                    toPeakSeconds: next.peakSeconds
                )
            )
        }
        return segments
    }

    static func framing(
        baseScale: Float,
        basePositionPixels: vector_float2,
        at seconds: Double,
        handoffs: [StabilizerAutoCropZoomHandoffSegment],
        coverageFloorScale: Float = 1.0,
        positionRequiredScale: Float = 1.0,
        framingRepairScale: Float = 1.0
    ) -> StabilizerAutoCropZoomHandoffResult {
        let safeBaseScale = max(Float(1.0), baseScale)
        let absoluteFloor = max(
            Float(1.0),
            max(coverageFloorScale, max(positionRequiredScale, framingRepairScale))
        )
        guard seconds.isFinite, !handoffs.isEmpty else {
            return StabilizerAutoCropZoomHandoffResult(
                scale: max(safeBaseScale, absoluteFloor),
                positionPixels: basePositionPixels,
                progress: 0.0,
                applied: false,
                fromPeakSeconds: nil,
                toPeakSeconds: nil
            )
        }

        var selectedHandoff: StabilizerAutoCropZoomHandoffSegment?
        for handoff in handoffs {
            guard seconds >= handoff.startSeconds - 1e-9,
                  seconds <= handoff.toPeakSeconds + 1e-9
            else {
                continue
            }
            selectedHandoff = handoff
        }

        guard let handoff = selectedHandoff else {
            return StabilizerAutoCropZoomHandoffResult(
                scale: max(safeBaseScale, absoluteFloor),
                positionPixels: basePositionPixels,
                progress: 0.0,
                applied: false,
                fromPeakSeconds: nil,
                toPeakSeconds: nil
            )
        }

        let handoffDuration = handoff.endSeconds - handoff.startSeconds
        let progress: Float
        if handoffDuration <= 1e-9 {
            progress = 1.0
        } else {
            progress = min(
                max(Float((seconds - handoff.startSeconds) / handoffDuration), 0.0),
                1.0
            )
        }
        let handoffScale = handoff.fromScale
            + ((handoff.toScale - handoff.fromScale) * progress)
        let handoffPosition = handoff.fromPositionPixels
            + ((handoff.toPositionPixels - handoff.fromPositionPixels) * progress)
        let loweredScale = min(safeBaseScale, max(Float(1.0), handoffScale))
        let positionChanged = simd_length(handoffPosition - basePositionPixels) > 0.0001
        return StabilizerAutoCropZoomHandoffResult(
            scale: max(loweredScale, absoluteFloor),
            positionPixels: handoffPosition,
            progress: progress,
            applied: loweredScale + 0.00001 < safeBaseScale || positionChanged,
            fromPeakSeconds: handoff.fromPeakSeconds,
            toPeakSeconds: handoff.toPeakSeconds
        )
    }

}
