import Foundation
import simd

struct StabilizerDebugOverlayLensComponent {
    let offset: vector_float2
    let effectiveSupport: Float
}

struct StabilizerDebugOverlayInputs {
    let outputSize: vector_float2
    let masterStrength: Float
    let finalPixelOffset: vector_float2
    let finalRotationDegrees: Float
    let cropEnabled: Bool
    let cropScale: Float
    let cropPositionPixels: vector_float2
    let stridePixelOffset: vector_float2
    let strideRotationDegrees: Float
    let fineJitterPixelOffset: vector_float2
    let fineJitterRotationDegrees: Float
    let warpShear: vector_float2
    let warpPerspective: vector_float2
    let lensComponents: [StabilizerDebugOverlayLensComponent]
    let temporalSmoothingPixelDelta: vector_float2
    let temporalSmoothingRotationDelta: Float
    let trackingConfidence: Float
    let walkingTrackingConfidence: Float
    let sharpnessQuality: Float
    let residualQuality: Float
    let residualQualityAvailable: Bool
    let searchRadiusHeadroomQuality: Float
    let searchRadiusHeadroomAvailable: Bool
    let turnConfidence: Float
    let strideConfidence: Float
    let fineJitterConfidence: Float
    let warpConfidence: Float
}

struct StabilizerDebugOverlayMetrics {
    let xOffset: Float
    let yOffset: Float
    let roll: Float
    let crop: Float
    let turn: Float
    let strideWobble: Float
    let footstepJitter: Float
    let farFieldWarp: Float
    let lens: Float
    let smoothing: Float
    let trackingQuality: Float
    let walkingQuality: Float
    let sharpnessQuality: Float
    let residualQuality: Float
    let searchRadiusHeadroomQuality: Float
    let turnConfidence: Float
    let strideConfidence: Float
    let footstepConfidence: Float
    let warpConfidence: Float
    let lensConfidence: Float
    let residualQualityAvailable: Bool
    let searchRadiusHeadroomAvailable: Bool

    static let zero = StabilizerDebugOverlayMetrics(
        xOffset: 0.0,
        yOffset: 0.0,
        roll: 0.0,
        crop: 0.0,
        turn: 0.0,
        strideWobble: 0.0,
        footstepJitter: 0.0,
        farFieldWarp: 0.0,
        lens: 0.0,
        smoothing: 0.0,
        trackingQuality: 0.0,
        walkingQuality: 0.0,
        sharpnessQuality: 0.0,
        residualQuality: 0.0,
        searchRadiusHeadroomQuality: 0.0,
        turnConfidence: 0.0,
        strideConfidence: 0.0,
        footstepConfidence: 0.0,
        warpConfidence: 0.0,
        lensConfidence: 0.0,
        residualQualityAvailable: false,
        searchRadiusHeadroomAvailable: false
    )
}

enum StabilizerDebugOverlayCalculator {
    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0.0
        }
        return min(1.0, max(0.0, value))
    }

    private static func strength(_ value: Float) -> Float {
        guard value.isFinite else {
            return 0.0
        }
        return max(0.0, value)
    }

    private static func correctionActivity(
        offset: vector_float2,
        rotationDegrees: Float,
        scaleX: Float,
        scaleY: Float,
        rotationScale: Float,
        strength: Float
    ) -> Float {
        let appliedOffset = offset * strength
        let appliedRotation = rotationDegrees * strength
        return unit(max(
            abs(appliedOffset.x) / max(scaleX, Float.ulpOfOne),
            abs(appliedOffset.y) / max(scaleY, Float.ulpOfOne),
            abs(appliedRotation) / max(rotationScale, Float.ulpOfOne)
        ))
    }

    static func lensAppliedGain(_ support: Float) -> Float {
        let normalized = unit(support)
        let t = unit((normalized - 0.08) / (0.55 - 0.08))
        return t * t * (3.0 - (2.0 * t))
    }

    static func rigidLocalWarpEscapeGain(_ rigidOnlyApplied: Float) -> Float {
        let normalized = unit(rigidOnlyApplied)
        let t = unit((normalized - 0.18) / (0.42 - 0.18))
        let lock = t * t * (3.0 - (2.0 * t))
        return powf(max(0.0, 1.0 - lock), 6.0)
    }

    static func metrics(for input: StabilizerDebugOverlayInputs) -> StabilizerDebugOverlayMetrics {
        let width = max(1.0, input.outputSize.x.isFinite ? input.outputSize.x : 1.0)
        let height = max(1.0, input.outputSize.y.isFinite ? input.outputSize.y : 1.0)
        let masterStrength = strength(input.masterStrength)
        let fineScaleX = max(4.0, width * 0.004)
        let fineScaleY = max(4.0, height * 0.004)
        let turnScaleX = max(1.0, width * 0.01)
        let turnScaleY = max(1.0, height * 0.01)
        let smoothingScale = max(1.0, min(width, height) * 0.01)

        let appliedFinalOffset = input.finalPixelOffset * masterStrength
        let xOffset = unit(abs(appliedFinalOffset.x) / fineScaleX)
        let yOffset = unit(abs(appliedFinalOffset.y) / fineScaleY)
        let roll = unit(abs(input.finalRotationDegrees * masterStrength) / 0.05)
        let crop = input.cropEnabled
            ? unit(max(0.0, input.cropScale - 1.0) / 0.25)
            : 0.0
        let turn = input.cropEnabled
            ? unit(max(
                abs(input.cropPositionPixels.x) / turnScaleX,
                abs(input.cropPositionPixels.y) / turnScaleY
            ))
            : 0.0
        let strideWobble = correctionActivity(
            offset: input.stridePixelOffset,
            rotationDegrees: input.strideRotationDegrees,
            scaleX: fineScaleX,
            scaleY: fineScaleY,
            rotationScale: 0.05,
            strength: masterStrength
        )
        let footstepJitter = correctionActivity(
            offset: input.fineJitterPixelOffset,
            rotationDegrees: input.fineJitterRotationDegrees,
            scaleX: fineScaleX,
            scaleY: fineScaleY,
            rotationScale: 0.05,
            strength: masterStrength
        )
        let farFieldWarp = unit(max(
            simd_length(input.warpShear * masterStrength) / 0.016,
            simd_length(input.warpPerspective * masterStrength) / 0.006
        ))

        var lensActivity: Float = 0.0
        var lensConfidence: Float = 0.0
        for component in input.lensComponents {
            let support = unit(component.effectiveSupport)
            lensConfidence = max(lensConfidence, support)
            let appliedOffset = component.offset * masterStrength * support
            lensActivity = max(
                lensActivity,
                abs(appliedOffset.x) / fineScaleX,
                abs(appliedOffset.y) / fineScaleY
            )
        }

        let smoothing = correctionActivity(
            offset: input.temporalSmoothingPixelDelta,
            rotationDegrees: input.temporalSmoothingRotationDelta,
            scaleX: smoothingScale,
            scaleY: smoothingScale,
            rotationScale: 0.05,
            strength: masterStrength
        )

        return StabilizerDebugOverlayMetrics(
            xOffset: xOffset,
            yOffset: yOffset,
            roll: roll,
            crop: crop,
            turn: turn,
            strideWobble: strideWobble,
            footstepJitter: footstepJitter,
            farFieldWarp: farFieldWarp,
            lens: unit(lensActivity),
            smoothing: smoothing,
            trackingQuality: unit(input.trackingConfidence),
            walkingQuality: unit(input.walkingTrackingConfidence),
            sharpnessQuality: unit(input.sharpnessQuality),
            residualQuality: input.residualQualityAvailable ? unit(input.residualQuality) : 0.0,
            searchRadiusHeadroomQuality: input.searchRadiusHeadroomAvailable ? unit(input.searchRadiusHeadroomQuality) : 0.0,
            turnConfidence: unit(input.turnConfidence),
            strideConfidence: unit(input.strideConfidence),
            footstepConfidence: unit(input.fineJitterConfidence),
            warpConfidence: unit(input.warpConfidence),
            lensConfidence: unit(lensConfidence),
            residualQualityAvailable: input.residualQualityAvailable,
            searchRadiusHeadroomAvailable: input.searchRadiusHeadroomAvailable
        )
    }
}
