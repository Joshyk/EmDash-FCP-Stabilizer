import Foundation

enum StabilizerConfidencePolicy {
    private static let turnOwnedXTransitionRescueMaximumPixels: Float = 3.2

    struct TurnOwnedFarFieldXImpulseRescue {
        let gateFloor: Float
        let confidenceFloor: Float
        let continuityFloor: Float
    }

    static func unbiased(_ evidence: Float) -> Float {
        guard evidence.isFinite else {
            return 0.0
        }
        return min(1.0, max(0.0, evidence))
    }

    static func unbiasedMean(_ values: Float...) -> Float {
        guard !values.isEmpty else {
            return 0.0
        }
        let total = values.reduce(Float(0.0)) { partialResult, value in
            partialResult + unbiased(value)
        }
        return unbiased(total / Float(values.count))
    }

    static func turnOwnedFarFieldXImpulseRescue(
        rawConfidence: Float,
        bandPixels: Float,
        turnSuppression: Float,
        turnOwnership: Float,
        turnMacroPixels: Float,
        farFieldSupport: Float
    ) -> TurnOwnedFarFieldXImpulseRescue {
        guard rawConfidence.isFinite,
              bandPixels.isFinite,
              turnSuppression.isFinite,
              turnOwnership.isFinite,
              turnMacroPixels.isFinite,
              farFieldSupport.isFinite
        else {
            return TurnOwnedFarFieldXImpulseRescue(gateFloor: 0.0, confidenceFloor: 0.0, continuityFloor: 0.0)
        }

        let turnSupport = max(
            ramp(turnSuppression, start: 0.28, full: 0.66),
            ramp(turnOwnership, start: 0.28, full: 0.66)
        )
        let evidenceSupport = ramp(rawConfidence, start: 0.03, full: 0.10)
        let gateImpulseSupport = ramp(abs(bandPixels), start: 12.0, full: 75.0)
        let confidenceImpulseSupport = ramp(abs(bandPixels), start: 1.0, full: 10.0)
        let farFieldEvidence = ramp(farFieldSupport, start: 0.12, full: 0.52)
        let broadTurnRejection = 1.0 - ramp(abs(turnMacroPixels), start: 48.0, full: 160.0)
        let evidenceAuthority = unbiased(
            turnSupport * evidenceSupport * farFieldEvidence * broadTurnRejection
        )
        let gateAuthority = evidenceAuthority * gateImpulseSupport
        let confidenceAuthority = evidenceAuthority * confidenceImpulseSupport

        return TurnOwnedFarFieldXImpulseRescue(
            gateFloor: gateAuthority,
            confidenceFloor: confidenceAuthority,
            continuityFloor: farFieldSupport * confidenceAuthority
        )
    }

    static func turnOwnedXTransitionRestoration(
        requestedPixels: Float,
        microPixels: Float,
        authority: Float
    ) -> Float {
        guard requestedPixels.isFinite,
              microPixels.isFinite,
              authority.isFinite
        else {
            return 0.0
        }

        let boundedAuthority = unbiased(authority)
        let limit = min(
            turnOwnedXTransitionRescueMaximumPixels,
            abs(microPixels) * boundedAuthority
        )
        return min(limit, max(-limit, requestedPixels * boundedAuthority))
    }

    private static func ramp(_ value: Float, start: Float, full: Float) -> Float {
        guard value.isFinite, start.isFinite, full.isFinite, full > start else {
            return 0.0
        }
        let normalized = (value - start) / (full - start)
        let bounded = unbiased(normalized)
        return bounded * bounded * (3.0 - (2.0 * bounded))
    }
}
