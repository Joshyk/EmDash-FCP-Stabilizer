import Foundation

enum StabilizerAutoCropScalePolicy {
    static let coverageActivationDelta: Float = 0.0005
    static let subtleZoomMaximumDelta: Float = 0.08
    static let subtleZoomMultiplier: Float = 0.5
    static let coverageToleranceDelta: Float = 0.0005
    static let playbackMinimumClipScaleDelta: Float = 0.018
    static let playbackAdaptivePaddingDelta: Float = 0.004
    static let playbackAdaptiveMultiplier: Float = 1.5

    static func keypointScale(forDemandScale demandScale: Float) -> Float {
        let safeDemandScale = max(Float(1.0), demandScale.isFinite ? demandScale : Float(1.0))
        let demandDelta = safeDemandScale - Float(1.0)
        guard demandDelta > coverageActivationDelta else {
            return Float(1.0)
        }
        guard demandDelta <= subtleZoomMaximumDelta else {
            return safeDemandScale
        }
        let attenuatedScale = Float(1.0) + (demandDelta * subtleZoomMultiplier)
        let safetyFloor = max(Float(1.0), safeDemandScale - coverageToleranceDelta)
        return max(attenuatedScale, safetyFloor)
    }

    static func playbackMinimumClippedScale(_ scale: Float) -> Float {
        let safeScale = max(Float(1.0), scale.isFinite ? scale : Float(1.0))
        let demandDelta = max(Float(0.0), safeScale - Float(1.0))
        guard demandDelta > coverageActivationDelta else {
            return Float(1.0)
        }
        let adaptiveMinimumDelta = min(
            playbackMinimumClipScaleDelta,
            max(
                demandDelta + playbackAdaptivePaddingDelta,
                demandDelta * playbackAdaptiveMultiplier
            )
        )
        return max(Float(1.0) + adaptiveMinimumDelta, safeScale)
    }
}
