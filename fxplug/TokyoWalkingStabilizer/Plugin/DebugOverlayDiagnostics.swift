import Foundation
import simd

struct StabilizerDebugOverlayInputs {
    let outputSize: vector_float2
    let masterStrength: Float
    let finalPixelOffset: vector_float2
    let finalRotationDegrees: Float
    let cropEnabled: Bool
    let cropScale: Float
    let turnPixelOffset: vector_float2
    let macroJitterPixelOffset: vector_float2
    let macroJitterRotationDegrees: Float
    let microJitterPixelOffset: vector_float2
    let microJitterRotationDegrees: Float
    let warpShear: vector_float2
    let warpPerspective: vector_float2
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
    let macroConfidence: Float
    let microJitterConfidence: Float
    let warpConfidence: Float
}

struct StabilizerDebugOverlayMetrics {
    let xOffset: Float
    let yOffset: Float
    let roll: Float
    let crop: Float
    let turn: Float
    let macroJitter: Float
    let microJitter: Float
    let farFieldWarp: Float
    let smoothing: Float
    let trackingQuality: Float
    let walkingQuality: Float
    let sharpnessQuality: Float
    let residualQuality: Float
    let searchRadiusHeadroomQuality: Float
    let turnConfidence: Float
    let macroConfidence: Float
    let microConfidence: Float
    let warpConfidence: Float
    let residualQualityAvailable: Bool
    let searchRadiusHeadroomAvailable: Bool

    static let zero = StabilizerDebugOverlayMetrics(
        xOffset: 0.0,
        yOffset: 0.0,
        roll: 0.0,
        crop: 0.0,
        turn: 0.0,
        macroJitter: 0.0,
        microJitter: 0.0,
        farFieldWarp: 0.0,
        smoothing: 0.0,
        trackingQuality: 0.0,
        walkingQuality: 0.0,
        sharpnessQuality: 0.0,
        residualQuality: 0.0,
        searchRadiusHeadroomQuality: 0.0,
        turnConfidence: 0.0,
        macroConfidence: 0.0,
        microConfidence: 0.0,
        warpConfidence: 0.0,
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
        let appliedTurnOffset = input.turnPixelOffset * masterStrength
        // TURN owns its horizontal viewport travel and has its own row. Keep
        // it out of X OFFSET while retaining the final non-TURN Y correction.
        let nonTurnFinalXOffset = appliedFinalOffset.x - appliedTurnOffset.x
        let xOffset = unit(abs(nonTurnFinalXOffset) / fineScaleX)
        let yOffset = unit(abs(appliedFinalOffset.y) / fineScaleY)
        let roll = unit(abs(input.finalRotationDegrees * masterStrength) / 0.05)
        let crop = input.cropEnabled
            ? unit(max(0.0, input.cropScale - 1.0) / 0.25)
            : 0.0
        let turn = unit(max(
            abs(appliedTurnOffset.x) / turnScaleX,
            abs(appliedTurnOffset.y) / turnScaleY
        ))
        let macroJitter = correctionActivity(
            offset: input.macroJitterPixelOffset,
            rotationDegrees: input.macroJitterRotationDegrees,
            scaleX: fineScaleX,
            scaleY: fineScaleY,
            rotationScale: 0.05,
            strength: masterStrength
        )
        let microJitter = correctionActivity(
            offset: input.microJitterPixelOffset,
            rotationDegrees: input.microJitterRotationDegrees,
            scaleX: fineScaleX,
            scaleY: fineScaleY,
            rotationScale: 0.05,
            strength: masterStrength
        )
        let farFieldWarp = unit(max(
            simd_length(input.warpShear * masterStrength) / 0.016,
            simd_length(input.warpPerspective * masterStrength) / 0.006
        ))

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
            macroJitter: macroJitter,
            microJitter: microJitter,
            farFieldWarp: farFieldWarp,
            smoothing: smoothing,
            trackingQuality: unit(input.trackingConfidence),
            walkingQuality: unit(input.walkingTrackingConfidence),
            sharpnessQuality: unit(input.sharpnessQuality),
            residualQuality: input.residualQualityAvailable ? unit(input.residualQuality) : 0.0,
            searchRadiusHeadroomQuality: input.searchRadiusHeadroomAvailable ? unit(input.searchRadiusHeadroomQuality) : 0.0,
            turnConfidence: unit(input.turnConfidence),
            macroConfidence: unit(input.macroConfidence),
            microConfidence: unit(input.microJitterConfidence),
            warpConfidence: unit(input.warpConfidence),
            residualQualityAvailable: input.residualQualityAvailable,
            searchRadiusHeadroomAvailable: input.searchRadiusHeadroomAvailable
        )
    }
}
