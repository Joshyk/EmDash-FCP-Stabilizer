import Foundation

@main
struct StabilizerConfidencePolicyTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    static func main() {
        expect(close(StabilizerConfidencePolicy.unbiased(0.0), 0.0), "zero must remain zero")
        expect(close(StabilizerConfidencePolicy.unbiased(0.5), 0.5), "mid confidence must remain linear")
        expect(close(StabilizerConfidencePolicy.unbiased(1.0), 1.0), "one must remain one")
        expect(close(StabilizerConfidencePolicy.unbiased(-0.25), 0.0), "negative confidence must clamp low")
        expect(close(StabilizerConfidencePolicy.unbiased(1.25), 1.0), "confidence must clamp high")
        expect(close(StabilizerConfidencePolicy.unbiased(.nan), 0.0), "NaN confidence must fail visibly as zero")
        expect(close(StabilizerConfidencePolicy.unbiased(.infinity), 0.0), "infinite confidence must fail visibly as zero")
        expect(
            close(StabilizerConfidencePolicy.unbiasedMean(0.3, 0.6, 0.9), 0.6),
            "axis confidence must use an unbiased arithmetic mean"
        )
        expect(
            close(StabilizerConfidencePolicy.unbiasedMean(0.3, .nan, 0.9), 0.4),
            "nonfinite axis confidence must contribute zero"
        )

        let rescuedImpulse = StabilizerConfidencePolicy.turnOwnedFarFieldXImpulseRescue(
            rawConfidence: 0.8,
            bandPixels: 82.0,
            turnSuppression: 1.0,
            turnOwnership: 1.0,
            turnMacroPixels: 28.0,
            farFieldSupport: 1.0
        )
        expect(close(rescuedImpulse.gateFloor, 1.0), "strong far-field X impulse must retain full Camera Jitter gate authority")
        expect(close(rescuedImpulse.confidenceFloor, 1.0), "strong far-field X impulse must retain full confidence authority")
        expect(close(rescuedImpulse.continuityFloor, 1.0), "strong far-field X impulse must retain continuity authority")

        let broadTurn = StabilizerConfidencePolicy.turnOwnedFarFieldXImpulseRescue(
            rawConfidence: 0.8,
            bandPixels: 82.0,
            turnSuppression: 1.0,
            turnOwnership: 1.0,
            turnMacroPixels: 180.0,
            farFieldSupport: 1.0
        )
        expect(close(broadTurn.gateFloor, 0.0), "broad turn travel must not be rescued as Camera Jitter")

        let weakFarField = StabilizerConfidencePolicy.turnOwnedFarFieldXImpulseRescue(
            rawConfidence: 0.8,
            bandPixels: 82.0,
            turnSuppression: 1.0,
            turnOwnership: 1.0,
            turnMacroPixels: 28.0,
            farFieldSupport: 0.1
        )
        expect(close(weakFarField.gateFloor, 0.0), "weak far-field evidence must not bypass Turn ownership")

        let fineImpulse = StabilizerConfidencePolicy.turnOwnedFarFieldXImpulseRescue(
            rawConfidence: 0.8,
            bandPixels: 10.0,
            turnSuppression: 1.0,
            turnOwnership: 1.0,
            turnMacroPixels: 28.0,
            farFieldSupport: 1.0
        )
        expect(close(fineImpulse.gateFloor, 0.0), "fine impulse must not reopen the broad Turn gate")
        expect(close(fineImpulse.confidenceFloor, 1.0), "fine impulse must retain frame-local Camera Jitter confidence")

        expect(
            close(
                StabilizerConfidencePolicy.turnOwnedFarFieldRigidXTransitionRestoration(
                    rigidPixels: -2.66871,
                    turnPixels: -4.83667,
                    support: 1.0,
                    shapeConsistency: 1.0,
                    forwardBackwardConsistency: 1.0
                ),
                -2.66871
            ),
            "supported 1:49 far-field rigid correction must survive TURN concatenation"
        )
        expect(
            close(
                StabilizerConfidencePolicy.turnOwnedFarFieldRigidXTransitionRestoration(
                    rigidPixels: 38.42,
                    turnPixels: 4.0,
                    support: 1.0,
                    shapeConsistency: 1.0,
                    forwardBackwardConsistency: 1.0
                ),
                3.2
            ),
            "far-field rigid restoration must stay below the prior transition regression"
        )
        expect(
            close(
                StabilizerConfidencePolicy.turnOwnedFarFieldRigidXTransitionRestoration(
                    rigidPixels: -2.0,
                    turnPixels: 0.0,
                    support: 1.0,
                    shapeConsistency: 1.0,
                    forwardBackwardConsistency: 1.0
                ),
                0.0
            ),
            "far-field rigid restoration must stay off without TURN activity"
        )
        expect(
            close(
                StabilizerConfidencePolicy.turnOwnedFarFieldRigidXTransitionRestoration(
                    rigidPixels: .nan,
                    turnPixels: 4.0,
                    support: 1.0,
                    shapeConsistency: 1.0,
                    forwardBackwardConsistency: 1.0
                ),
                0.0
            ),
            "nonfinite far-field rigid evidence must fail visibly as zero"
        )
        expect(
            close(
                StabilizerConfidencePolicy.turnOwnedFarFieldRigidXTransitionRestoration(
                    rigidPixels: -2.0,
                    turnPixels: 4.0,
                    support: 0.1,
                    shapeConsistency: 1.0,
                    forwardBackwardConsistency: 1.0
                ),
                0.0
            ),
            "weak far-field support must not perturb a TURN transition"
        )

        if failures.isEmpty {
            print("StabilizerConfidencePolicyTests: PASS")
            return
        }
        for failure in failures {
            fputs("StabilizerConfidencePolicyTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
