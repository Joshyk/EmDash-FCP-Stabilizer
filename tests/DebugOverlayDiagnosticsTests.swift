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
        cropPositionPixels: vector_float2 = .zero,
        finalPixelOffset: vector_float2 = .zero,
        finalRotationDegrees: Float = 0.0,
        stridePixelOffset: vector_float2 = .zero,
        strideRotationDegrees: Float = 0.0,
        fineJitterPixelOffset: vector_float2 = .zero,
        fineJitterRotationDegrees: Float = 0.0,
        warpShear: vector_float2 = .zero,
        warpPerspective: vector_float2 = .zero,
        lensComponents: [StabilizerDebugOverlayLensComponent] = [],
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
        strideConfidence: Float = 0.0,
        fineJitterConfidence: Float = 0.0,
        warpConfidence: Float = 0.0
    ) -> StabilizerDebugOverlayInputs {
        StabilizerDebugOverlayInputs(
            outputSize: vector_float2(1920.0, 1080.0),
            masterStrength: masterStrength,
            finalPixelOffset: finalPixelOffset,
            finalRotationDegrees: finalRotationDegrees,
            cropEnabled: cropEnabled,
            cropScale: cropScale,
            cropPositionPixels: cropPositionPixels,
            stridePixelOffset: stridePixelOffset,
            strideRotationDegrees: strideRotationDegrees,
            fineJitterPixelOffset: fineJitterPixelOffset,
            fineJitterRotationDegrees: fineJitterRotationDegrees,
            warpShear: warpShear,
            warpPerspective: warpPerspective,
            lensComponents: lensComponents,
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
            strideConfidence: strideConfidence,
            fineJitterConfidence: fineJitterConfidence,
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
        let stride = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            stridePixelOffset: vector_float2(7.68, 0.0),
            strideConfidence: 0.45
        ))
        expect(close(stride.strideWobble, 1.0), "SWOB must use its own applied correction")
        expect(close(stride.footstepJitter, 0.0), "SWOB must not activate FJIT")
        expect(close(stride.strideConfidence, 0.45), "S CONF must keep analysis confidence")

        let fine = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            fineJitterPixelOffset: vector_float2(0.0, 4.32),
            fineJitterConfidence: 0.62
        ))
        expect(close(fine.footstepJitter, 1.0), "FJIT must use fine correction")
        expect(close(fine.strideWobble, 0.0), "FJIT must not activate SWOB")
        expect(close(fine.footstepConfidence, 0.62), "F CONF must keep effective confidence")

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
            finalPixelOffset: vector_float2(20.0, 20.0),
            finalRotationDegrees: 1.0,
            stridePixelOffset: vector_float2(20.0, 20.0),
            fineJitterPixelOffset: vector_float2(20.0, 20.0),
            warpShear: vector_float2(0.1, 0.1),
            lensComponents: [StabilizerDebugOverlayLensComponent(offset: vector_float2(20.0, 20.0), effectiveSupport: 1.0)],
            temporalSmoothingPixelDelta: vector_float2(20.0, 20.0),
            turnConfidence: 0.8
        ))
        expect(close(disabled.xOffset, 0.0), "master zero must disable X activity")
        expect(close(disabled.strideWobble, 0.0), "master zero must disable SWOB activity")
        expect(close(disabled.footstepJitter, 0.0), "master zero must disable FJIT activity")
        expect(close(disabled.farFieldWarp, 0.0), "master zero must disable WARP activity")
        expect(close(disabled.lens, 0.0), "master zero must disable LENS activity")
        expect(close(disabled.turnConfidence, 0.8), "confidence must remain visible when strength is zero")

        let cropOff = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            cropEnabled: false,
            cropScale: 1.25,
            cropPositionPixels: vector_float2(100.0, 50.0)
        ))
        expect(close(cropOff.crop, 0.0), "crop off must hide CROP activity")
        expect(close(cropOff.turn, 0.0), "crop off must hide TURN viewport activity")

        let cropOn = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            cropEnabled: true,
            cropScale: 1.25,
            cropPositionPixels: vector_float2(19.2, 0.0)
        ))
        expect(close(cropOn.crop, 1.0), "crop scale must map to CROP")
        expect(close(cropOn.turn, 1.0), "applied crop position must map to TURN")
    }

    private static func testLensUsesOnlyAppliedComponents() {
        let support = StabilizerDebugOverlayCalculator.lensAppliedGain(0.55)
        let values = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            lensComponents: [
                StabilizerDebugOverlayLensComponent(
                    offset: vector_float2(7.68, 0.0),
                    effectiveSupport: support
                )
            ]
        ))
        expect(close(values.lens, 1.0), "LENS must use the actual supported Metal offset")
        expect(close(values.lensConfidence, 1.0), "L CONF must use effective applied support")
        expect(close(StabilizerDebugOverlayCalculator.lensAppliedGain(0.08), 0.0), "lens gain lower edge")
        expect(close(StabilizerDebugOverlayCalculator.rigidLocalWarpEscapeGain(0.42), 0.0), "rigid mode must suppress local warp")
    }

    private static func testQualityDirectionAndClamping() {
        let values = StabilizerDebugOverlayCalculator.metrics(for: inputs(
            trackingConfidence: 1.2,
            walkingTrackingConfidence: 0.8,
            sharpnessQuality: 0.7,
            residualQuality: 0.6,
            searchRadiusHeadroomQuality: 0.5,
            turnConfidence: -1.0,
            strideConfidence: .nan,
            fineJitterConfidence: 0.4,
            warpConfidence: 2.0
        ))
        expect(close(values.trackingQuality, 1.0), "TRK must clamp high")
        expect(close(values.walkingQuality, 0.8), "WLK must preserve high-is-good value")
        expect(close(values.sharpnessQuality, 0.7), "SHRP must preserve high-is-good value")
        expect(close(values.residualQuality, 0.6), "RES must preserve high-is-good value")
        expect(close(values.searchRadiusHeadroomQuality, 0.5), "HIT must preserve high-is-good value")
        expect(close(values.turnConfidence, 0.0), "negative confidence must clamp low")
        expect(close(values.strideConfidence, 0.0), "nonfinite confidence must fail visibly as zero")
        expect(close(values.warpConfidence, 1.0), "confidence must clamp high")
    }

    static func main() {
        testZeroAndUnavailable()
        testBandIsolationAndFrequencyRows()
        testFinalStrengthAndCropSemantics()
        testLensUsesOnlyAppliedComponents()
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
