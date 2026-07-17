import Foundation
import simd

@main
struct DebugOverlayDiagnosticsTests {
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func close(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func inputs(
        masterStrength: Float = 1.0,
        cropEnabled: Bool = false,
        cropScale: Float = 1.0,
        turnPixelOffset: vector_float2 = .zero,
        finalPixelOffset: vector_float2 = .zero,
        finalRotationDegrees: Float = 0.0,
        macroJitterPixelOffset: vector_float2 = .zero,
        macroJitterRotationDegrees: Float = 0.0,
        microJitterPixelOffset: vector_float2 = .zero,
        microJitterRotationDegrees: Float = 0.0,
        warpShear: vector_float2 = .zero,
        warpPerspective: vector_float2 = .zero,
        temporalSmoothingPixelDelta: vector_float2 = .zero,
        temporalSmoothingRotationDelta: Float = 0.0,
        trackingConfidence: Float = 0.0,
        walkingTrackingConfidence: Float = 0.0,
        sharpnessQuality: Float = 0.0,
        residualQuality: Float = 0.0,
        residualQualityAvailable: Bool = true,
        searchRadiusHeadroomQuality: Float = 0.0,
        searchRadiusHeadroomAvailable: Bool = true,
        turnConfidence: Float = 0.0,
        macroConfidence: Float = 0.0,
        microJitterConfidence: Float = 0.0,
        warpConfidence: Float = 0.0
    ) -> StabilizerDebugOverlayInputs {
        StabilizerDebugOverlayInputs(
            outputSize: vector_float2(1920.0, 1080.0),
            masterStrength: masterStrength,
            finalPixelOffset: finalPixelOffset,
            finalRotationDegrees: finalRotationDegrees,
            cropEnabled: cropEnabled,
            cropScale: cropScale,
            turnPixelOffset: turnPixelOffset,
            macroJitterPixelOffset: macroJitterPixelOffset,
            macroJitterRotationDegrees: macroJitterRotationDegrees,
            microJitterPixelOffset: microJitterPixelOffset,
            microJitterRotationDegrees: microJitterRotationDegrees,
            warpShear: warpShear,
            warpPerspective: warpPerspective,
            temporalSmoothingPixelDelta: temporalSmoothingPixelDelta,
            temporalSmoothingRotationDelta: temporalSmoothingRotationDelta,
            trackingConfidence: trackingConfidence,
            walkingTrackingConfidence: walkingTrackingConfidence,
            sharpnessQuality: sharpnessQuality,
            residualQuality: residualQuality,
            residualQualityAvailable: residualQualityAvailable,
            searchRadiusHeadroomQuality: searchRadiusHeadroomQuality,
            searchRadiusHeadroomAvailable: searchRadiusHeadroomAvailable,
            turnConfidence: turnConfidence,
            macroConfidence: macroConfidence,
            microJitterConfidence: microJitterConfidence,
            warpConfidence: warpConfidence
        )
    }

    private static func testZeroAndUnavailable() {
        let values = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            residualQuality: 0.9,
            residualQualityAvailable: false,
            searchRadiusHeadroomQuality: 0.9,
            searchRadiusHeadroomAvailable: false
        ))
        expect(close(values.xOffset, 0.0), "zero X activity")
        expect(close(values.crop, 0.0), "crop off must be zero")
        expect(close(values.residualQuality, 0.0), "unavailable residual must be zero")
        expect(close(values.searchRadiusHeadroomQuality, 0.0), "unavailable HIT must be zero")
        expect(!values.residualQualityAvailable, "residual availability must remain visible")
        expect(!values.searchRadiusHeadroomAvailable, "HIT availability must remain visible")
    }

    private static func testBandIsolationAndFrequencyRows() {
        let macro = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            macroJitterPixelOffset: vector_float2(7.68, 0.0),
            macroConfidence: 0.45
        ))
        expect(close(macro.macroJitter, 1.0), "MAJIT must use its own applied correction")
        expect(close(macro.microJitter, 0.0), "MAJIT must not activate MIJIT")
        expect(close(macro.macroConfidence, 0.45), "MA CONF must keep analysis confidence")

        let fine = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            microJitterPixelOffset: vector_float2(0.0, 4.32),
            microJitterConfidence: 0.62
        ))
        expect(close(fine.microJitter, 1.0), "MIJIT must use fine correction")
        expect(close(fine.macroJitter, 0.0), "MIJIT must not activate MAJIT")
        expect(close(fine.microConfidence, 0.62), "MI CONF must keep effective confidence")

        let warp = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            warpShear: vector_float2(0.016, 0.0),
            warpConfidence: 0.71
        ))
        expect(close(warp.farFieldWarp, 1.0), "WARP must use applied Metal shear")
        expect(close(warp.warpConfidence, 0.71), "W CONF must keep applied warp confidence")
    }

    private static func testFinalStrengthAndCropSemantics() {
        let disabled = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            masterStrength: 0.0,
            turnPixelOffset: vector_float2(100.0, 50.0),
            finalPixelOffset: vector_float2(20.0, 20.0),
            finalRotationDegrees: 1.0,
            macroJitterPixelOffset: vector_float2(20.0, 20.0),
            microJitterPixelOffset: vector_float2(20.0, 20.0),
            warpShear: vector_float2(0.1, 0.1),
            temporalSmoothingPixelDelta: vector_float2(20.0, 20.0),
            turnConfidence: 0.8
        ))
        expect(close(disabled.xOffset, 0.0), "master zero must disable X activity")
        expect(close(disabled.macroJitter, 0.0), "master zero must disable MAJIT activity")
        expect(close(disabled.microJitter, 0.0), "master zero must disable MIJIT activity")
        expect(close(disabled.farFieldWarp, 0.0), "master zero must disable WARP activity")
        expect(close(disabled.turn, 0.0), "master zero must disable TURN activity")
        expect(close(disabled.turnConfidence, 0.8), "confidence must remain visible when strength is zero")

        let cropOff = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            cropEnabled: false,
            cropScale: 1.25,
            turnPixelOffset: vector_float2(19.2, 0.0)
        ))
        expect(close(cropOff.crop, 0.0), "crop off must hide CROP activity")
        expect(close(cropOff.turn, 1.0), "crop off must not hide the final applied TURN correction")

        let cropOn = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            cropEnabled: true,
            cropScale: 1.25,
            turnPixelOffset: vector_float2(19.2, 0.0)
        ))
        expect(close(cropOn.crop, 1.0), "crop scale must map to CROP")
        expect(close(cropOn.turn, 1.0), "applied turn correction must map to TURN")

        let turnSeparated = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            turnPixelOffset: vector_float2(19.2, 0.0),
            finalPixelOffset: vector_float2(19.2, 0.0)
        ))
        expect(close(turnSeparated.xOffset, 0.0), "TURN must not contribute to X OFFSET")
        expect(close(turnSeparated.turn, 1.0), "TURN must remain visible in its own row")

        let nonTurnX = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            turnPixelOffset: vector_float2(9.6, 0.0),
            finalPixelOffset: vector_float2(19.2, 0.0)
        ))
        expect(close(nonTurnX.xOffset, 1.0), "X OFFSET must report only the non-TURN correction")
    }

    private static func testQualityDirectionAndClamping() {
        let values = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            trackingConfidence: 1.2,
            walkingTrackingConfidence: 0.8,
            sharpnessQuality: 0.7,
            residualQuality: 0.6,
            searchRadiusHeadroomQuality: 0.5,
            turnConfidence: -1.0,
            macroConfidence: .nan,
            microJitterConfidence: 0.4,
            warpConfidence: 2.0
        ))
        expect(close(values.trackingQuality, 1.0), "TRK must clamp high")
        expect(close(values.walkingQuality, 0.8), "WLK must preserve high-is-good value")
        expect(close(values.sharpnessQuality, 0.7), "SHRP must preserve high-is-good value")
        expect(close(values.residualQuality, 0.6), "RES must preserve high-is-good value")
        expect(close(values.searchRadiusHeadroomQuality, 0.5), "HIT must preserve high-is-good value")
        expect(close(values.turnConfidence, 0.0), "negative confidence must clamp low")
        expect(close(values.macroConfidence, 0.0), "nonfinite confidence must fail visibly as zero")
        expect(close(values.warpConfidence, 1.0), "confidence must clamp high")
    }

    static func main() {
        testZeroAndUnavailable()
        testBandIsolationAndFrequencyRows()
        testFinalStrengthAndCropSemantics()
        testQualityDirectionAndClamping()

        if failures.isEmpty {
            print("DebugOverlayDiagnosticsTests: PASS")
            return
        }
        for failure in failures {
            fputs("DebugOverlayDiagnosticsTests: FAIL: \(failure)\n", stderr)
        }
        exit(1)
    }
}
