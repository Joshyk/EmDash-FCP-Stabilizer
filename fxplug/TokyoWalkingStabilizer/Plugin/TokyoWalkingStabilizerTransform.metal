#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "StabilizerShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} RasterizerData;

vertex RasterizerData vertexShader(
    uint vertexID [[vertex_id]],
    constant StabilizerVertex2D *vertexArray [[buffer(SVI_Vertices)]],
    constant vector_uint2 *viewportSizePointer [[buffer(SVI_ViewportSize)]]
) {
    RasterizerData out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

static uint debugLabelRowBits(uint code, uint y) {
    switch (code) {
        case 65: // A
            if (y == 0) { return 0x2; }
            if (y == 2) { return 0x7; }
            return 0x5;
        case 66: // B
            if (y == 0 || y == 2 || y == 4) { return 0x6; }
            return 0x5;
        case 67: // C
            return (y == 0 || y == 4) ? 0x7 : 0x4;
        case 68: // D
            return (y == 0 || y == 4) ? 0x6 : 0x5;
        case 69: // E
            if (y == 0 || y == 4) { return 0x7; }
            if (y == 2) { return 0x6; }
            return 0x4;
        case 70: // F
            if (y == 0) { return 0x7; }
            if (y == 2) { return 0x6; }
            return 0x4;
        case 71: // G
            if (y == 0 || y == 4) { return 0x7; }
            if (y == 1) { return 0x4; }
            return 0x5;
        case 72: // H
            if (y == 2) { return 0x7; }
            return 0x5;
        case 73: // I
            return (y == 0 || y == 4) ? 0x7 : 0x2;
        case 74: // J
            if (y == 0) { return 0x7; }
            if (y == 4) { return 0x6; }
            return 0x1;
        case 75: // K
            return y == 2 ? 0x6 : 0x5;
        case 76: // L
            return y == 4 ? 0x7 : 0x4;
        case 77: // M
            if (y == 1 || y == 2) { return 0x7; }
            return 0x5;
        case 78: // N
            if (y == 1 || y == 2 || y == 3) { return 0x7; }
            return 0x5;
        case 79: // O
            return (y == 0 || y == 4) ? 0x7 : 0x5;
        case 80: // P
            if (y == 0 || y == 2) { return 0x6; }
            if (y == 1) { return 0x5; }
            return 0x4;
        case 81: // Q
            if (y == 0) { return 0x7; }
            if (y == 3) { return 0x7; }
            if (y == 4) { return 0x1; }
            return 0x5;
        case 82: // R
            if (y == 0 || y == 2) { return 0x6; }
            return 0x5;
        case 83: // S
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return y == 1 ? 0x4 : 0x1;
        case 84: // T
            return y == 0 ? 0x7 : 0x2;
        case 85: // U
            return y == 4 ? 0x7 : 0x5;
        case 86: // V
            return y == 4 ? 0x2 : 0x5;
        case 87: // W
            if (y == 2 || y == 3) { return 0x7; }
            return 0x5;
        case 88: // X
            return y == 2 ? 0x2 : 0x5;
        case 89: // Y
            return y < 2 ? 0x5 : 0x2;
        case 90: // Z
            if (y == 0 || y == 4) { return 0x7; }
            if (y == 1) { return 0x1; }
            if (y == 2) { return 0x2; }
            return 0x4;
        case 48: // 0
            return (y == 0 || y == 4) ? 0x7 : 0x5;
        case 49: // 1
            return y == 4 ? 0x7 : 0x2;
        case 50: // 2
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return y == 1 ? 0x1 : 0x4;
        case 51: // 3
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return 0x1;
        case 52: // 4
            if (y == 2) { return 0x7; }
            return y < 2 ? 0x5 : 0x1;
        case 53: // 5
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return y == 1 ? 0x4 : 0x1;
        case 54: // 6
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return y == 1 ? 0x4 : 0x5;
        case 55: // 7
            return y == 0 ? 0x7 : 0x1;
        case 56: // 8
            return (y == 0 || y == 2 || y == 4) ? 0x7 : 0x5;
        case 57: // 9
            if (y == 0 || y == 2 || y == 4) { return 0x7; }
            return y == 1 ? 0x5 : 0x1;
        case 46: // .
            return y == 4 ? 0x2 : 0x0;
        case 47: // /
            if (y == 0 || y == 1) { return 0x1; }
            if (y == 2) { return 0x2; }
            return 0x4;
        default:
            return 0x0;
    }
}

static bool debugLabelPixel(uint code, uint x, uint y) {
    if (code == 0 || x >= 3 || y >= 5) {
        return false;
    }
    uint bits = debugLabelRowBits(code, y);
    return ((bits >> (2 - x)) & 0x1) != 0;
}

static uint debugDigitChar(uint digit) {
    return 48 + (digit % 10);
}

static uint debugLabelCharAt(uint index, uint4 c0_3, uint4 c4_7, uint4 c8_11, uint4 c12_15, uint4 c16_19);

static uint debugModeLabelChar(float debugMode, float4 runtimeVersion, uint index) {
    uint major = uint(clamp(runtimeVersion.x, 0.0, 9.0) + 0.5);
    uint minor = uint(clamp(runtimeVersion.y, 0.0, 9.0) + 0.5);
    uint patch = uint(clamp(runtimeVersion.z, 0.0, 999.0) + 0.5);
    bool proxy = debugMode > 1.5;
    uint sourceLength = proxy ? 6 : 9;
    if (index < sourceLength) {
        if (proxy) {
            return debugLabelCharAt(index, uint4(80, 82, 79, 88), uint4(89, 0, 0, 0), uint4(0), uint4(0), uint4(0)); // PROXY
        }
        return debugLabelCharAt(index, uint4(79, 82, 73, 71), uint4(73, 78, 65, 76), uint4(0), uint4(0), uint4(0)); // ORIGINAL
    }
    uint versionIndex = index - sourceLength;
    if (versionIndex == 0) { return debugDigitChar(major); }
    if (versionIndex == 1) { return 46; } // .
    if (versionIndex == 2) { return debugDigitChar(minor); }
    if (versionIndex == 3) { return 46; } // .
    if (versionIndex == 4) {
        return patch >= 100 ? debugDigitChar(patch / 100)
            : patch >= 10 ? debugDigitChar(patch / 10)
            : debugDigitChar(patch);
    }
    if (versionIndex == 5) {
        return patch >= 100 ? debugDigitChar((patch / 10) % 10)
            : patch >= 10 ? debugDigitChar(patch)
            : 0;
    }
    if (versionIndex == 6) { return patch >= 100 ? debugDigitChar(patch) : 0; }
    return 0;
}

static uint debugLabelCharAt(uint index, uint4 c0_3, uint4 c4_7, uint4 c8_11, uint4 c12_15, uint4 c16_19) {
    uint component = index % 4;
    switch (index / 4) {
        case 0: return c0_3[component];
        case 1: return c4_7[component];
        case 2: return c8_11[component];
        case 3: return c12_15[component];
        case 4: return c16_19[component];
        default: return 0;
    }
}

static uint debugLabelChar(uint row, uint index, float debugMode, float runtimeBuild, float4 runtimeVersion) {
    switch (row) {
        case StabilizerDebugOverlayRowXOffset:
            return debugLabelCharAt(index, uint4(88, 0, 79, 70), uint4(70, 83, 69, 84), uint4(0), uint4(0), uint4(0)); // X OFFSET
        case StabilizerDebugOverlayRowYOffset:
            return debugLabelCharAt(index, uint4(89, 0, 79, 70), uint4(70, 83, 69, 84), uint4(0), uint4(0), uint4(0)); // Y OFFSET
        case StabilizerDebugOverlayRowRoll:
            return debugLabelCharAt(index, uint4(82, 79, 76, 76), uint4(0), uint4(0), uint4(0), uint4(0)); // ROLL
        case StabilizerDebugOverlayRowCrop:
            return debugLabelCharAt(index, uint4(67, 82, 79, 80), uint4(0), uint4(0), uint4(0), uint4(0)); // CROP
        case StabilizerDebugOverlayRowTurn:
            return debugLabelCharAt(index, uint4(84, 85, 82, 78), uint4(0), uint4(0), uint4(0), uint4(0)); // TURN
        case StabilizerDebugOverlayRowMacroJitter:
            return debugLabelCharAt(index, uint4(77, 65, 67, 82), uint4(79, 0, 74, 73), uint4(84, 84, 69, 82), uint4(0), uint4(0)); // MACRO JITTER
        case StabilizerDebugOverlayRowMicroJitter:
            return debugLabelCharAt(index, uint4(77, 73, 67, 82), uint4(79, 0, 74, 73), uint4(84, 84, 69, 82), uint4(0), uint4(0)); // MICRO JITTER
        case StabilizerDebugOverlayRowFarFieldWarp:
            return debugLabelCharAt(index, uint4(70, 65, 82, 0), uint4(87, 65, 82, 80), uint4(0), uint4(0), uint4(0)); // FAR WARP
        case StabilizerDebugOverlayRowLens:
            return debugLabelCharAt(index, uint4(76, 69, 78, 83), uint4(0), uint4(0), uint4(0), uint4(0)); // LENS
        case StabilizerDebugOverlayRowSmoothing:
            return debugLabelCharAt(index, uint4(83, 77, 79, 79), uint4(84, 72, 73, 78), uint4(71, 0, 0, 0), uint4(0), uint4(0)); // SMOOTHING
        case StabilizerDebugOverlayRowTrackingQuality:
            return debugLabelCharAt(index, uint4(84, 82, 65, 67), uint4(75, 73, 78, 71), uint4(0), uint4(0), uint4(0)); // TRACKING
        case StabilizerDebugOverlayRowWalkingQuality:
            return debugLabelCharAt(index, uint4(87, 65, 76, 75), uint4(73, 78, 71, 0), uint4(0), uint4(0), uint4(0)); // WALKING
        case StabilizerDebugOverlayRowSharpnessQuality:
            return debugLabelCharAt(index, uint4(83, 72, 65, 82), uint4(80, 78, 69, 83), uint4(83, 0, 0, 0), uint4(0), uint4(0)); // SHARPNESS
        case StabilizerDebugOverlayRowResidualQuality:
            return debugLabelCharAt(index, uint4(82, 69, 83, 73), uint4(68, 85, 65, 76), uint4(0), uint4(0), uint4(0)); // RESIDUAL
        case StabilizerDebugOverlayRowSearchRadiusHeadroomQuality:
            return debugLabelCharAt(index, uint4(83, 69, 65, 82), uint4(67, 72, 0, 72), uint4(69, 65, 68, 82), uint4(79, 79, 77, 0), uint4(0)); // SEARCH HEADROOM
        case StabilizerDebugOverlayRowTurnConfidence:
            return debugLabelCharAt(index, uint4(84, 85, 82, 78), uint4(0, 67, 79, 78), uint4(70, 73, 68, 69), uint4(78, 67, 69, 0), uint4(0)); // TURN CONFIDENCE
        case StabilizerDebugOverlayRowMacroConfidence:
            return debugLabelCharAt(index, uint4(77, 65, 67, 82), uint4(79, 0, 67, 79), uint4(78, 70, 73, 68), uint4(69, 78, 67, 69), uint4(0)); // MACRO CONFIDENCE
        case StabilizerDebugOverlayRowMicroConfidence:
            return debugLabelCharAt(index, uint4(77, 73, 67, 82), uint4(79, 0, 67, 79), uint4(78, 70, 73, 68), uint4(69, 78, 67, 69), uint4(0)); // MICRO CONFIDENCE
        case StabilizerDebugOverlayRowWarpConfidence:
            return debugLabelCharAt(index, uint4(87, 65, 82, 80), uint4(0, 67, 79, 78), uint4(70, 73, 68, 69), uint4(78, 67, 69, 0), uint4(0)); // WARP CONFIDENCE
        case StabilizerDebugOverlayRowLensConfidence:
            return debugLabelCharAt(index, uint4(76, 69, 78, 83), uint4(0, 67, 79, 78), uint4(70, 73, 68, 69), uint4(78, 67, 69, 0), uint4(0)); // LENS CONFIDENCE
        case StabilizerDebugOverlayRowRuntime:
            return debugModeLabelChar(debugMode, runtimeVersion, index);
        default:
            return 0;
    }
}

static bool debugLabelCoverage(float panelX, float rowY, uint row, float overlayScale, float debugMode, float runtimeBuild, float4 runtimeVersion) {
    float textScale = 2.0 * overlayScale;
    constexpr float glyphWidth = 3.0;
    constexpr float glyphHeight = 5.0;
    float glyphAdvance = 4.0 * textScale;

    float textX = panelX - 6.0;
    float textY = rowY - (1.5 * overlayScale);
    if (textX < 0.0 || textY < 0.0 || textY >= glyphHeight * textScale) {
        return false;
    }

    uint index = uint(floor(textX / glyphAdvance));
    if (index >= 20) {
        return false;
    }

    float glyphLocalX = textX - (float(index) * glyphAdvance);
    if (glyphLocalX >= glyphWidth * textScale) {
        return false;
    }

    uint glyphX = uint(floor(glyphLocalX / textScale));
    uint glyphY = uint(floor(textY / textScale));
    return debugLabelPixel(debugLabelChar(row, index, debugMode, runtimeBuild, runtimeVersion), glyphX, glyphY);
}

static float lensBandWeight(float y, float center, float radius) {
    float distance = abs(y - center);
    float normalized = saturate(1.0 - (distance / max(radius, 0.0001)));
    return normalized * normalized * (3.0 - (2.0 * normalized));
}

static float lensBandAppliedGain(float support) {
    return smoothstep(0.08, 0.55, saturate(support));
}

constant float lensBandTopCenter = 0.10;
constant float lensBandRidgeCenter = 0.25;
constant float lensBandMidCenter = 0.40;
constant float lensBandTopRadius = 0.30;
constant float lensBandRidgeRadius = 0.36;
constant float lensBandMidRadius = 0.34;
constant float lensBandFadeStart = 0.58;
constant float lensBandFadeEnd = 0.78;
constant float lensBandRigidOnlyFadeStart = 0.72;
constant float lensBandRigidOnlyFadeEnd = 0.90;
constant float lensBandInterBandDifferentialGain = 0.0;
constant float lensBandColumnDifferentialGain = 0.0;
constant float lensBandRowPhaseGain = 0.0;
constant float lensBandLocalRollGain = 0.0;
constant float lensBandMountainDifferentialFadeStart = 0.28;
constant float lensBandMountainDifferentialFadeEnd = 0.62;

constant float sourceLensLocalTopCenter = 0.10;
constant float sourceLensLocalRidgeCenter = 0.25;
constant float sourceLensLocalMidCenter = 0.42;
constant float sourceLensLocalTopRadius = 0.28;
constant float sourceLensLocalRidgeRadius = 0.34;
constant float sourceLensLocalMidRadius = 0.30;
constant float sourceLensLocalFadeStart = 0.56;
constant float sourceLensLocalFadeEnd = 0.74;
constant float sourceLensLocalColumnDifferentialGain = 0.0;
constant float sourceLensLocalBandDifferentialGain = 0.0;
constant float sourceLensLocalMountainDifferentialFadeStart = 0.28;
constant float sourceLensLocalMountainDifferentialFadeEnd = 0.60;

constant float sourceLensRidgeCenter = 0.25;
constant float sourceLensRidgeRadius = 0.40;
constant float sourceLensRidgeFadeStart = 0.56;
constant float sourceLensRidgeFadeEnd = 0.82;

static float debugRectOutlineCoverage(float2 uv, float2 outputSize, float minX, float maxX, float minY, float maxY, float thicknessPixels) {
    if (uv.x < minX || uv.x > maxX || uv.y < minY || uv.y > maxY) {
        return 0.0;
    }
    float thicknessX = max(thicknessPixels / max(outputSize.x, 1.0), 0.0001);
    float thicknessY = max(thicknessPixels / max(outputSize.y, 1.0), 0.0001);
    float edgeDistance = min(
        min(abs(uv.x - minX), abs(uv.x - maxX)) / thicknessX,
        min(abs(uv.y - minY), abs(uv.y - maxY)) / thicknessY
    );
    return 1.0 - smoothstep(0.65, 1.05, edgeDistance);
}

static float debugRectFillCoverage(float2 uv, float minX, float maxX, float minY, float maxY) {
    return (uv.x >= minX && uv.x <= maxX && uv.y >= minY && uv.y <= maxY) ? 1.0 : 0.0;
}

static float farFieldMeshMinY(uint row) {
    switch (row) {
        case 0: return 0.04;
        case 1: return 0.13;
        case 2: return 0.22;
        case 3: return 0.31;
        default: return 0.40;
    }
}

static float farFieldMeshMaxY(uint row) {
    switch (row) {
        case 0: return 0.16;
        case 1: return 0.25;
        case 2: return 0.34;
        case 3: return 0.43;
        default: return 0.52;
    }
}

static float farFieldMeshMinX(uint column) {
    switch (column) {
        case 0: return 0.00;
        case 1: return 0.10;
        case 2: return 0.22;
        case 3: return 0.34;
        case 4: return 0.46;
        case 5: return 0.58;
        case 6: return 0.70;
        case 7: return 0.82;
        default: return 0.90;
    }
}

static float farFieldMeshMaxX(uint column) {
    switch (column) {
        case 0: return 0.14;
        case 1: return 0.26;
        case 2: return 0.38;
        case 3: return 0.50;
        case 4: return 0.62;
        case 5: return 0.74;
        case 6: return 0.86;
        case 7: return 0.98;
        default: return 1.00;
    }
}

static float sourceLensLocalMinY(uint row) {
    switch (row) {
        case 0: return 0.06;
        case 1: return 0.16;
        default: return 0.28;
    }
}

static float sourceLensLocalMaxY(uint row) {
    switch (row) {
        case 0: return 0.18;
        case 1: return 0.30;
        default: return 0.46;
    }
}

static float sourceLensLocalMinX(uint column) {
    switch (column) {
        case 0: return 0.00;
        case 1: return 0.32;
        default: return 0.64;
    }
}

static float sourceLensLocalMaxX(uint column) {
    switch (column) {
        case 0: return 0.36;
        case 1: return 0.68;
        default: return 1.00;
    }
}

static float2 sourceLensLocalOffsetForBin(constant TokyoWalkingStabilizerTransformUniforms *transform, uint bin) {
    switch (bin) {
        case 0: return transform->sourceLensShakeLocalTopLeftOffset;
        case 1: return transform->sourceLensShakeLocalTopCenterOffset;
        case 2: return transform->sourceLensShakeLocalTopRightOffset;
        case 3: return transform->sourceLensShakeLocalRidgeLeftOffset;
        case 4: return transform->sourceLensShakeLocalRidgeCenterOffset;
        case 5: return transform->sourceLensShakeLocalRidgeRightOffset;
        case 6: return transform->sourceLensShakeLocalMidLeftOffset;
        case 7: return transform->sourceLensShakeLocalMidCenterOffset;
        default: return transform->sourceLensShakeLocalMidRightOffset;
    }
}

static float debugHorizontalGuideCoverage(float sourceY, float outputHeight, float guideY, float thicknessPixels) {
    float thickness = max(thicknessPixels / max(outputHeight, 1.0), 0.0001);
    return 1.0 - smoothstep(0.65, 1.05, abs(sourceY - guideY) / thickness);
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<half> colorTexture [[texture(STI_InputImage)]],
    constant TokyoWalkingStabilizerTransformUniforms *transform [[buffer(SFI_Transform)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = in.textureCoordinate;
    float autoCropScale = max(transform->autoCropScale, 1.0);
    float2 centeredPixels = (((uv - 0.5) * transform->outputSize) / autoCropScale)
        + transform->autoCropPositionPixels;

    float s = transform->rotationSinCos.x;
    float c = transform->rotationSinCos.y;
    float2 rotated = float2(
        (centeredPixels.x * c) - (centeredPixels.y * s),
        (centeredPixels.x * s) + (centeredPixels.y * c)
    );

    float2 stabilizedPixels = rotated - (transform->pixelOffset * transform->strength);
    float2 normalizedPixels = stabilizedPixels / transform->outputSize;
    float perspectiveDenominator = max(0.35, 1.0 + (transform->perspective.x * normalizedPixels.x) + (transform->perspective.y * normalizedPixels.y));
    stabilizedPixels = stabilizedPixels / perspectiveDenominator;
    stabilizedPixels -= float2(
        transform->shear.x * stabilizedPixels.y,
        transform->shear.y * stabilizedPixels.x
    );
    // The Swift path gates these offsets before marking them applied; Metal maps that
    // support to a continuous application gain so weak evidence cannot step to full warp.
    float lensBandSupport = saturate(transform->lensBandWarpApplied)
        * lensBandAppliedGain(transform->lensBandWarpSupport);
    float rigidOnlyGain = saturate(transform->lensFarFieldRigidOnlyApplied);
    float rigidOnlyLock = smoothstep(0.18, 0.42, rigidOnlyGain);
    float localWarpEscapeGain = powr(1.0 - rigidOnlyLock, 6.0);
    float ridgeWarpEscapeGain = powr(1.0 - rigidOnlyLock, 6.0);
    if (lensBandSupport > 0.0001) {
        float sourceY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float localFarFieldFade = 1.0 - smoothstep(lensBandFadeStart, lensBandFadeEnd, sourceY);
        float rigidFarFieldFade = 1.0 - smoothstep(lensBandRigidOnlyFadeStart, lensBandRigidOnlyFadeEnd, sourceY);
        float farFieldFade = mix(localFarFieldFade, rigidFarFieldFade, rigidOnlyLock);
        float topWeight = lensBandWeight(sourceY, lensBandTopCenter, lensBandTopRadius);
        float ridgeWeight = lensBandWeight(sourceY, lensBandRidgeCenter, lensBandRidgeRadius);
        float midWeight = lensBandWeight(sourceY, lensBandMidCenter, lensBandMidRadius);
        float totalWeight = topWeight + ridgeWeight + midWeight;
        if (totalWeight > 0.0001) {
            float2 weightedBandOffset = (
                (transform->lensBandTopOffset * topWeight)
                + (transform->lensBandRidgeOffset * ridgeWeight)
                + (transform->lensBandMidOffset * midWeight)
            ) / totalWeight;
            float2 commonBandOffset = (
                transform->lensBandTopOffset
                + transform->lensBandRidgeOffset
                + transform->lensBandMidOffset
            ) / 3.0;
            float mountainDifferentialMaskY = saturate(uv.y);
            float mountainDifferentialGain = 1.0 - smoothstep(
                lensBandMountainDifferentialFadeStart,
                lensBandMountainDifferentialFadeEnd,
                mountainDifferentialMaskY
            );
            float differentialGain = (1.0 - rigidOnlyLock) * mountainDifferentialGain;
            float2 bandOffset = commonBandOffset
                + ((weightedBandOffset - commonBandOffset) * lensBandInterBandDifferentialGain * differentialGain);
            float sourceX = saturate((stabilizedPixels.x / transform->outputSize.x) + 0.5);
            float columnPhase = clamp((sourceX - 0.5) * 2.0, -1.0, 1.0);
            float2 columnOffset = (
                (transform->lensBandTopColumnOffset * topWeight)
                + (transform->lensBandRidgeColumnOffset * ridgeWeight)
                + (transform->lensBandMidColumnOffset * midWeight)
            ) / totalWeight;
            float topRowPhase = clamp((lensBandTopCenter - sourceY) / lensBandTopRadius, -1.0, 1.0);
            float ridgeRowPhase = clamp((lensBandRidgeCenter - sourceY) / lensBandRidgeRadius, -1.0, 1.0);
            float midRowPhase = clamp((lensBandMidCenter - sourceY) / lensBandMidRadius, -1.0, 1.0);
            float2 rowPhaseOffset = (
                (transform->lensBandTopRowPhaseOffset * topWeight * topRowPhase)
                + (transform->lensBandRidgeRowPhaseOffset * ridgeWeight * ridgeRowPhase)
                + (transform->lensBandMidRowPhaseOffset * midWeight * midRowPhase)
            ) / totalWeight;
            float topYLocal = (sourceY - lensBandTopCenter) * transform->outputSize.y;
            float ridgeYLocal = (sourceY - lensBandRidgeCenter) * transform->outputSize.y;
            float midYLocal = (sourceY - lensBandMidCenter) * transform->outputSize.y;
            float xLocal = stabilizedPixels.x;
            float2 localRollOffset = (
                (float2(-(transform->lensBandTopLocalRoll * topYLocal), transform->lensBandTopLocalRoll * xLocal) * topWeight)
                + (float2(-(transform->lensBandRidgeLocalRoll * ridgeYLocal), transform->lensBandRidgeLocalRoll * xLocal) * ridgeWeight)
                + (float2(-(transform->lensBandMidLocalRoll * midYLocal), transform->lensBandMidLocalRoll * xLocal) * midWeight)
            ) / totalWeight;
            bandOffset += columnOffset * columnPhase * lensBandColumnDifferentialGain * differentialGain;
            bandOffset += rowPhaseOffset * lensBandRowPhaseGain * differentialGain;
            bandOffset += localRollOffset * lensBandLocalRollGain * differentialGain;
            stabilizedPixels -= bandOffset * lensBandSupport * farFieldFade * transform->strength;
        }
    }
    float localLensSupport = saturate(transform->sourceLensShakeLocalApplied)
        * lensBandAppliedGain(transform->sourceLensShakeLocalSupport)
        * localWarpEscapeGain;
    if (localLensSupport > 0.0001) {
        float sourceY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float farFieldFade = 1.0 - smoothstep(sourceLensLocalFadeStart, sourceLensLocalFadeEnd, sourceY);
        float topWeight = lensBandWeight(sourceY, sourceLensLocalTopCenter, sourceLensLocalTopRadius);
        float ridgeWeight = lensBandWeight(sourceY, sourceLensLocalRidgeCenter, sourceLensLocalRidgeRadius);
        float midWeight = lensBandWeight(sourceY, sourceLensLocalMidCenter, sourceLensLocalMidRadius);
        float totalBandWeight = topWeight + ridgeWeight + midWeight;
        if (totalBandWeight > 0.0001) {
            float sourceX = saturate((stabilizedPixels.x / transform->outputSize.x) + 0.5);
            float mountainDifferentialMaskY = saturate(uv.y);
            float mountainDifferentialGain = 1.0 - smoothstep(
                sourceLensLocalMountainDifferentialFadeStart,
                sourceLensLocalMountainDifferentialFadeEnd,
                mountainDifferentialMaskY
            );
            float leftWeight = 1.0 - smoothstep(0.22, 0.50, sourceX);
            float rightWeight = smoothstep(0.50, 0.78, sourceX);
            float centerWeight = saturate(1.0 - max(leftWeight, rightWeight));
            float totalColumnWeight = max(0.0001, leftWeight + centerWeight + rightWeight);
            float2 topColumnOffset = (
                (transform->sourceLensShakeLocalTopLeftOffset * leftWeight)
                + (transform->sourceLensShakeLocalTopCenterOffset * centerWeight)
                + (transform->sourceLensShakeLocalTopRightOffset * rightWeight)
            ) / totalColumnWeight;
            float2 ridgeColumnOffset = (
                (transform->sourceLensShakeLocalRidgeLeftOffset * leftWeight)
                + (transform->sourceLensShakeLocalRidgeCenterOffset * centerWeight)
                + (transform->sourceLensShakeLocalRidgeRightOffset * rightWeight)
            ) / totalColumnWeight;
            float2 midColumnOffset = (
                (transform->sourceLensShakeLocalMidLeftOffset * leftWeight)
                + (transform->sourceLensShakeLocalMidCenterOffset * centerWeight)
                + (transform->sourceLensShakeLocalMidRightOffset * rightWeight)
            ) / totalColumnWeight;
            float2 topCommonColumnOffset = (
                transform->sourceLensShakeLocalTopLeftOffset
                + transform->sourceLensShakeLocalTopCenterOffset
                + transform->sourceLensShakeLocalTopRightOffset
            ) / 3.0;
            float2 ridgeCommonColumnOffset = (
                transform->sourceLensShakeLocalRidgeLeftOffset
                + transform->sourceLensShakeLocalRidgeCenterOffset
                + transform->sourceLensShakeLocalRidgeRightOffset
            ) / 3.0;
            float2 midCommonColumnOffset = (
                transform->sourceLensShakeLocalMidLeftOffset
                + transform->sourceLensShakeLocalMidCenterOffset
                + transform->sourceLensShakeLocalMidRightOffset
            ) / 3.0;
            float2 topOffset = topCommonColumnOffset
                + ((topColumnOffset - topCommonColumnOffset) * sourceLensLocalColumnDifferentialGain * mountainDifferentialGain);
            float2 ridgeOffset = ridgeCommonColumnOffset
                + ((ridgeColumnOffset - ridgeCommonColumnOffset) * sourceLensLocalColumnDifferentialGain * mountainDifferentialGain);
            float2 midOffset = midCommonColumnOffset
                + ((midColumnOffset - midCommonColumnOffset) * sourceLensLocalColumnDifferentialGain * mountainDifferentialGain);
            float2 weightedLocalOffset = (
                (topOffset * topWeight)
                + (ridgeOffset * ridgeWeight)
                + (midOffset * midWeight)
            ) / totalBandWeight;
            float2 commonLocalOffset = (topOffset + ridgeOffset + midOffset) / 3.0;
            float2 localOffset = commonLocalOffset
                + ((weightedLocalOffset - commonLocalOffset) * sourceLensLocalBandDifferentialGain * mountainDifferentialGain);
            stabilizedPixels -= localOffset * localLensSupport * farFieldFade * transform->strength;
        }
    }
    float sourceRidgeSupport = saturate(transform->sourceLensShakeRidgeApplied)
        * lensBandAppliedGain(transform->sourceLensShakeRidgeSupport)
        * ridgeWarpEscapeGain;
    if (sourceRidgeSupport > 0.0001) {
        float sourceRidgeMaskY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float ridgeWeight = lensBandWeight(sourceRidgeMaskY, sourceLensRidgeCenter, sourceLensRidgeRadius);
        float farFieldFade = 1.0 - smoothstep(sourceLensRidgeFadeStart, sourceLensRidgeFadeEnd, sourceRidgeMaskY);
        stabilizedPixels -= transform->sourceLensShakeRidgeOffset
            * sourceRidgeSupport
            * ridgeWeight
            * farFieldFade
            * transform->strength;
    }
    float2 sampleUV = (stabilizedPixels / transform->outputSize) + 0.5;

    bool outsideSource = sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0;
    float4 outputColor;
    if (transform->edgeMode > 0.5 && outsideSource) {
        outputColor = float4(0.0, 0.0, 0.0, 1.0);
    } else {
        outputColor = float4(colorTexture.sample(textureSampler, sampleUV));
    }
    outputColor.a = 1.0;

    float2 pixel = uv * transform->outputSize;
    float overlayScale = clamp(transform->debugOverlayScale, 0.25, 8.0);
    float meshOverlayMode = floor(transform->debugMeshOverlayMode + 0.5);
    bool showAllMeshes = meshOverlayMode > 3.5;
    bool showFarFieldMesh = showAllMeshes || abs(meshOverlayMode - 1.0) < 0.5;
    bool showLensLocalMesh = showAllMeshes || abs(meshOverlayMode - 2.0) < 0.5;
    bool showBandGuides = showAllMeshes || abs(meshOverlayMode - 3.0) < 0.5;

    if (meshOverlayMode > 0.5 && !outsideSource) {
        if (showFarFieldMesh) {
            float farFieldOutline = 0.0;
            float farFieldDominantFill = 0.0;
            float dominantCell = floor(transform->debugFarFieldMesh.w + 0.5);
            float farFieldSupport = saturate(max(transform->debugFarFieldMesh.y, transform->debugFarFieldMeshWindow.z));
            for (uint row = 0; row < 5; ++row) {
                for (uint column = 0; column < 9; ++column) {
                    float minX = farFieldMeshMinX(column);
                    float maxX = farFieldMeshMaxX(column);
                    float minY = farFieldMeshMinY(row);
                    float maxY = farFieldMeshMaxY(row);
                    float outline = debugRectOutlineCoverage(sampleUV, transform->outputSize, minX, maxX, minY, maxY, 3.25 * overlayScale);
                    farFieldOutline = max(farFieldOutline, outline);
                    float bin = float((row * 9) + column);
                    if (dominantCell >= 0.0 && abs(bin - dominantCell) < 0.5) {
                        farFieldDominantFill = max(farFieldDominantFill, debugRectFillCoverage(sampleUV, minX, maxX, minY, maxY));
                    }
                }
            }
            float farFieldAlpha = saturate(
                (farFieldOutline * (0.38 + (0.24 * saturate(transform->debugFarFieldMesh.x))))
                + (farFieldDominantFill * farFieldSupport * 0.24)
            );
            if (farFieldAlpha > 0.0) {
                outputColor.rgb = mix(outputColor.rgb, float3(0.08, 0.88, 1.0), farFieldAlpha);
                outputColor.a = 1.0;
            }
        }

        if (showLensLocalMesh) {
            float localOutline = 0.0;
            float localActiveFill = 0.0;
            float localGain = saturate(transform->sourceLensShakeLocalApplied)
                * lensBandAppliedGain(transform->sourceLensShakeLocalSupport);
            for (uint row = 0; row < 3; ++row) {
                for (uint column = 0; column < 3; ++column) {
                    float minX = sourceLensLocalMinX(column);
                    float maxX = sourceLensLocalMaxX(column);
                    float minY = sourceLensLocalMinY(row);
                    float maxY = sourceLensLocalMaxY(row);
                    float outline = debugRectOutlineCoverage(sampleUV, transform->outputSize, minX, maxX, minY, maxY, 3.0 * overlayScale);
                    localOutline = max(localOutline, outline);
                    uint bin = (row * 3) + column;
                    float cellActivity = smoothstep(0.02, 0.90, length(sourceLensLocalOffsetForBin(transform, bin))) * localGain;
                    localActiveFill = max(
                        localActiveFill,
                        debugRectFillCoverage(sampleUV, minX, maxX, minY, maxY) * cellActivity
                    );
                }
            }
            float localAlpha = saturate(
                (localOutline * (0.34 + (0.14 * localGain)))
                + (localActiveFill * 0.26)
            );
            if (localAlpha > 0.0) {
                outputColor.rgb = mix(outputColor.rgb, float3(1.0, 0.62, 0.10), localAlpha);
                outputColor.a = 1.0;
            }
        }

        if (showBandGuides) {
            float bandGuide = max(
                debugHorizontalGuideCoverage(sampleUV.y, transform->outputSize.y, lensBandTopCenter, 3.4 * overlayScale),
                max(
                    debugHorizontalGuideCoverage(sampleUV.y, transform->outputSize.y, lensBandRidgeCenter, 3.4 * overlayScale),
                    debugHorizontalGuideCoverage(sampleUV.y, transform->outputSize.y, lensBandMidCenter, 3.4 * overlayScale)
                )
            );
            float bandGuideAlpha = bandGuide
                * (0.46 + (0.20
                    * saturate(transform->lensBandWarpApplied)
                    * lensBandAppliedGain(transform->lensBandWarpSupport)));
            if (bandGuideAlpha > 0.0) {
                outputColor.rgb = mix(outputColor.rgb, float3(1.0, 0.16, 0.72), saturate(bandGuideAlpha));
                outputColor.a = 1.0;
            }
        }
    }

    if (transform->debugOverlay > 0.5) {
        float panelX = pixel.x - (16.0 * overlayScale);
        float panelY = pixel.y - (16.0 * overlayScale);
        float labelWidth = 160.0 * overlayScale;
        float labelGap = 2.0 * overlayScale;
        float barWidth = 180.0 * overlayScale;
        float rowHeight = 13.0 * overlayScale;
        float panelWidth = labelWidth + labelGap + barWidth;
        float panelHeight = float(STABILIZER_DEBUG_OVERLAY_ROW_COUNT) * rowHeight;
        if (panelX >= 0.0 && panelX < panelWidth && panelY >= 0.0 && panelY < panelHeight) {
            uint row = uint(floor(panelY / rowHeight));
            float rowY = panelY - (float(row) * rowHeight);
            float fill = 0.0;
            float3 color = float3(0.94, 0.96, 0.98);
            switch (row) {
                case StabilizerDebugOverlayRowXOffset: fill = saturate(transform->debugDiagnostics.xOffset); break;
                case StabilizerDebugOverlayRowYOffset: fill = saturate(transform->debugDiagnostics.yOffset); break;
                case StabilizerDebugOverlayRowRoll: fill = saturate(transform->debugDiagnostics.roll); break;
                case StabilizerDebugOverlayRowCrop: fill = saturate(transform->debugDiagnostics.crop); break;
                case StabilizerDebugOverlayRowTurn: fill = saturate(transform->debugDiagnostics.turn); break;
                case StabilizerDebugOverlayRowMacroJitter: fill = saturate(transform->debugDiagnostics.macroJitter); break;
                case StabilizerDebugOverlayRowMicroJitter: fill = saturate(transform->debugDiagnostics.microJitter); break;
                case StabilizerDebugOverlayRowFarFieldWarp: fill = saturate(transform->debugDiagnostics.farFieldWarp); break;
                case StabilizerDebugOverlayRowLens: fill = saturate(transform->debugDiagnostics.lens); break;
                case StabilizerDebugOverlayRowSmoothing: fill = saturate(transform->debugDiagnostics.smoothing); break;
                case StabilizerDebugOverlayRowTrackingQuality: fill = saturate(transform->debugDiagnostics.trackingQuality); break;
                case StabilizerDebugOverlayRowWalkingQuality: fill = saturate(transform->debugDiagnostics.walkingQuality); break;
                case StabilizerDebugOverlayRowSharpnessQuality: fill = saturate(transform->debugDiagnostics.sharpnessQuality); break;
                case StabilizerDebugOverlayRowResidualQuality: fill = saturate(transform->debugDiagnostics.residualQuality); break;
                case StabilizerDebugOverlayRowSearchRadiusHeadroomQuality: fill = saturate(transform->debugDiagnostics.searchRadiusHeadroomQuality); break;
                case StabilizerDebugOverlayRowTurnConfidence: fill = saturate(transform->debugDiagnostics.turnConfidence); break;
                case StabilizerDebugOverlayRowMacroConfidence: fill = saturate(transform->debugDiagnostics.macroConfidence); break;
                case StabilizerDebugOverlayRowMicroConfidence: fill = saturate(transform->debugDiagnostics.microConfidence); break;
                case StabilizerDebugOverlayRowWarpConfidence: fill = saturate(transform->debugDiagnostics.warpConfidence); break;
                case StabilizerDebugOverlayRowLensConfidence: fill = saturate(transform->debugDiagnostics.lensConfidence); break;
                case StabilizerDebugOverlayRowRuntime: fill = 1.0; break;
                default: fill = 0.0; break;
            }
            float barX = panelX - labelWidth - labelGap;
            bool inBar = barX >= 0.0
                && barX <= barWidth
                && rowY >= (1.5 * overlayScale)
                && rowY <= (11.5 * overlayScale);
            float activeWidth = barWidth * fill;
            float3 background = float3(0.02, 0.02, 0.02);
            float3 overlay = background;
            float alpha = 0.62;
            if (inBar) {
                overlay = barX <= activeWidth ? color : background;
                alpha = 0.78;
            }
            if (debugLabelCoverage(panelX, rowY, row, overlayScale, transform->debugMode, transform->debugRuntimeBuild, transform->debugRuntimeVersion)) {
                overlay = float3(0.94, 0.96, 0.98);
                alpha = 0.92;
            }
            outputColor.rgb = mix(outputColor.rgb, overlay, alpha);
            outputColor.a = 1.0;
        }
    }

    return outputColor;
}

kernel void stabilizerDownsampleLuma(
    texture2d<float, access::sample> input [[texture(SCTI_InputImage)]],
    device uchar *output [[buffer(SCBI_DownsampleOutput)]],
    constant StabilizerDownsampleUniforms &uniforms [[buffer(SCBI_DownsampleUniforms)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    constexpr sampler nearestSampler(coord::pixel, address::clamp_to_edge, filter::nearest);
    float x = (float(gid.x) + 0.5) * float(input.get_width()) / float(uniforms.width);
    float y = (float(gid.y) + 0.5) * float(input.get_height()) / float(uniforms.height);
    float4 colorSample = input.sample(nearestSampler, float2(x, y));
    float luma = (0.2126 * colorSample.r) + (0.7152 * colorSample.g) + (0.0722 * colorSample.b);
    output[(gid.y * uniforms.width) + gid.x] = uchar(clamp(luma * 255.0, 0.0, 255.0));
}

kernel void stabilizerShiftScores(
    device const uchar *previous [[buffer(SCBI_PreviousFrame)]],
    device const uchar *current [[buffer(SCBI_CurrentFrame)]],
    device float *scores [[buffer(SCBI_ShiftScores)]],
    constant StabilizerShiftUniforms &uniforms [[buffer(SCBI_ShiftUniforms)]],
    uint gid [[thread_position_in_grid]]
) {
    uint side = (uniforms.radius * 2) + 1;
    uint count = side * side;
    if (gid >= count) {
        return;
    }

    int dx = int(gid % side) + uniforms.centerX - int(uniforms.radius);
    int dy = int(gid / side) + uniforms.centerY - int(uniforms.radius);
    int xStart = max(max(int(uniforms.x0), -dx), 0);
    int yStart = max(max(int(uniforms.y0), -dy), 0);
    int xEnd = min(min(int(uniforms.x0 + uniforms.regionWidth), int(uniforms.width) - dx), int(uniforms.width));
    int yEnd = min(min(int(uniforms.y0 + uniforms.regionHeight), int(uniforms.height) - dy), int(uniforms.height));

    if ((xEnd - xStart) < 18 || (yEnd - yStart) < 12) {
        scores[gid] = INFINITY;
        return;
    }

    float total = 0.0;
    uint samples = 0;
    for (int y = yStart; y < yEnd; y += int(uniforms.stride)) {
        int previousRow = y * int(uniforms.width);
        int currentRow = (y + dy) * int(uniforms.width);
        for (int x = xStart; x < xEnd; x += int(uniforms.stride)) {
            total += abs(float(previous[previousRow + x]) - float(current[currentRow + x + dx]));
            samples += 1;
        }
    }
    scores[gid] = samples == 0 ? INFINITY : total / float(samples) / 255.0;
}

kernel void stabilizerBatchShiftScores(
    device const uchar *previous [[buffer(SCBI_PreviousFrame)]],
    device const uchar *current [[buffer(SCBI_CurrentFrame)]],
    device float *scores [[buffer(SCBI_ShiftScores)]],
    device const StabilizerShiftBatchUniforms *uniformsList [[buffer(SCBI_ShiftBatchUniforms)]],
    uint2 gid [[thread_position_in_grid]]
) {
    StabilizerShiftBatchUniforms uniforms = uniformsList[gid.y];
    uint side = (uniforms.radius * 2) + 1;
    uint count = side * side;
    if (gid.x >= count) {
        return;
    }

    int dx = int(gid.x % side) + uniforms.centerX - int(uniforms.radius);
    int dy = int(gid.x / side) + uniforms.centerY - int(uniforms.radius);
    int xStart = max(max(int(uniforms.x0), -dx), 0);
    int yStart = max(max(int(uniforms.y0), -dy), 0);
    int xEnd = min(min(int(uniforms.x0 + uniforms.regionWidth), int(uniforms.width) - dx), int(uniforms.width));
    int yEnd = min(min(int(uniforms.y0 + uniforms.regionHeight), int(uniforms.height) - dy), int(uniforms.height));
    uint scoreIndex = (gid.y * count) + gid.x;

    if ((xEnd - xStart) < 18 || (yEnd - yStart) < 12) {
        scores[scoreIndex] = INFINITY;
        return;
    }

    float total = 0.0;
    uint samples = 0;
    for (int y = yStart; y < yEnd; y += int(uniforms.stride)) {
        int previousRow = y * int(uniforms.width);
        int currentRow = (y + dy) * int(uniforms.width);
        for (int x = xStart; x < xEnd; x += int(uniforms.stride)) {
            total += abs(float(previous[previousRow + x]) - float(current[currentRow + x + dx]));
            samples += 1;
        }
    }
    scores[scoreIndex] = samples == 0 ? INFINITY : total / float(samples) / 255.0;
}

static float stabilizerAxisOffset(float before, float center, float after) {
    if (!isfinite(before) || !isfinite(center) || !isfinite(after)) {
        return 0.0;
    }
    float denominator = before - (2.0 * center) + after;
    if (fabs(denominator) < 1.0e-9) {
        return 0.0;
    }
    return clamp(0.5 * (before - after) / denominator, -0.5, 0.5);
}

static int stabilizerRoundedShift(float value) {
    return value >= 0.0 ? int(floor(value + 0.5)) : int(ceil(value - 0.5));
}

static StabilizerShiftScorePartial stabilizerPartialShiftScore(
    device const uchar *previous,
    device const uchar *current,
    StabilizerShiftBatchUniforms uniforms,
    uint shiftIndex,
    uint chunkIndex,
    uint chunkCount
) {
    uint side = (uniforms.radius * 2) + 1;
    int dx = int(shiftIndex % side) + uniforms.centerX - int(uniforms.radius);
    int dy = int(shiftIndex / side) + uniforms.centerY - int(uniforms.radius);
    int xStart = max(max(int(uniforms.x0), -dx), 0);
    int yStart = max(max(int(uniforms.y0), -dy), 0);
    int xEnd = min(min(int(uniforms.x0 + uniforms.regionWidth), int(uniforms.width) - dx), int(uniforms.width));
    int yEnd = min(min(int(uniforms.y0 + uniforms.regionHeight), int(uniforms.height) - dy), int(uniforms.height));

    if ((xEnd - xStart) < 18 || (yEnd - yStart) < 12 || chunkCount == 0) {
        StabilizerShiftScorePartial empty;
        empty.total = 0.0;
        empty.samples = 0;
        return empty;
    }

    uint stride = max(1u, uniforms.stride);
    uint rowCount = uint(max(0, yEnd - yStart) + int(stride) - 1) / stride;
    uint rowStart = (rowCount * chunkIndex) / chunkCount;
    uint rowEnd = (rowCount * (chunkIndex + 1)) / chunkCount;

    float total = 0.0;
    uint samples = 0;
    for (uint rowSample = rowStart; rowSample < rowEnd; rowSample += 1) {
        int y = yStart + int(rowSample * stride);
        int previousRow = y * int(uniforms.width);
        int currentRow = (y + dy) * int(uniforms.width);
        for (int x = xStart; x < xEnd; x += int(stride)) {
            total += abs(float(previous[previousRow + x]) - float(current[currentRow + x + dx]));
            samples += 1;
        }
    }
    StabilizerShiftScorePartial partial;
    partial.total = total;
    partial.samples = samples;
    return partial;
}

static float stabilizerResolvedShiftScore(
    device const StabilizerShiftScorePartial *partials,
    uint blockIndex,
    uint shiftIndex,
    uint scoreCount,
    uint chunkCount
) {
    float total = 0.0;
    uint samples = 0;
    uint base = ((blockIndex * chunkCount) * scoreCount) + shiftIndex;
    for (uint chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
        StabilizerShiftScorePartial partial = partials[base + (chunkIndex * scoreCount)];
        total += partial.total;
        samples += partial.samples;
    }
    return samples == 0 ? INFINITY : total / float(samples) / 255.0;
}

static float stabilizerResolvedShiftScoreAt(
    device const StabilizerShiftScorePartial *partials,
    uint blockIndex,
    int dx,
    int dy,
    constant StabilizerShiftResolveUniforms &resolve,
    int centerX,
    int centerY
) {
    uint side = (resolve.radius * 2) + 1;
    int x = dx - centerX + int(resolve.radius);
    int y = dy - centerY + int(resolve.radius);
    if (x < 0 || x >= int(side) || y < 0 || y >= int(side)) {
        return INFINITY;
    }
    uint scoreIndex = uint(y) * side + uint(x);
    return stabilizerResolvedShiftScore(partials, blockIndex, scoreIndex, side * side, resolve.chunkCount);
}

kernel void stabilizerShiftScorePartials(
    device const uchar *previous [[buffer(SCBI_PreviousFrame)]],
    device const uchar *current [[buffer(SCBI_CurrentFrame)]],
    device StabilizerShiftScorePartial *partials [[buffer(SCBI_ShiftScorePartials)]],
    constant StabilizerShiftBatchUniforms &uniforms [[buffer(SCBI_ShiftUniforms)]],
    constant StabilizerShiftResolveUniforms &resolve [[buffer(SCBI_ShiftResolveUniforms)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint side = (uniforms.radius * 2) + 1;
    uint scoreCount = side * side;
    if (gid.x >= scoreCount || gid.z >= resolve.chunkCount) {
        return;
    }
    uint partialIndex = (gid.z * scoreCount) + gid.x;
    partials[partialIndex] = stabilizerPartialShiftScore(
        previous,
        current,
        uniforms,
        gid.x,
        gid.z,
        resolve.chunkCount
    );
}

kernel void stabilizerBatchShiftScorePartials(
    device const uchar *previous [[buffer(SCBI_PreviousFrame)]],
    device const uchar *current [[buffer(SCBI_CurrentFrame)]],
    device StabilizerShiftScorePartial *partials [[buffer(SCBI_ShiftScorePartials)]],
    device const StabilizerShiftBatchUniforms *uniformsList [[buffer(SCBI_ShiftBatchUniforms)]],
    constant StabilizerShiftResolveUniforms &resolve [[buffer(SCBI_ShiftResolveUniforms)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint blockIndex = gid.y;
    if (blockIndex >= resolve.blockCount || gid.z >= resolve.chunkCount) {
        return;
    }
    StabilizerShiftBatchUniforms uniforms = uniformsList[blockIndex];
    uint side = (uniforms.radius * 2) + 1;
    uint scoreCount = side * side;
    if (gid.x >= scoreCount) {
        return;
    }
    uint partialIndex = (((blockIndex * resolve.chunkCount) + gid.z) * scoreCount) + gid.x;
    partials[partialIndex] = stabilizerPartialShiftScore(
        previous,
        current,
        uniforms,
        gid.x,
        gid.z,
        resolve.chunkCount
    );
}

kernel void stabilizerBatchShiftScorePartialsWithGlobalCenter(
    device const uchar *previous [[buffer(SCBI_PreviousFrame)]],
    device const uchar *current [[buffer(SCBI_CurrentFrame)]],
    device StabilizerShiftScorePartial *partials [[buffer(SCBI_ShiftScorePartials)]],
    device const StabilizerShiftBatchUniforms *uniformsList [[buffer(SCBI_ShiftBatchUniforms)]],
    device const StabilizerShiftResult *globalResult [[buffer(SCBI_GlobalShiftResult)]],
    constant StabilizerShiftResolveUniforms &resolve [[buffer(SCBI_ShiftResolveUniforms)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint blockIndex = gid.y;
    if (blockIndex >= resolve.blockCount || gid.z >= resolve.chunkCount) {
        return;
    }
    StabilizerShiftBatchUniforms uniforms = uniformsList[blockIndex];
    uniforms.centerX = stabilizerRoundedShift(globalResult[0].dx);
    uniforms.centerY = stabilizerRoundedShift(globalResult[0].dy);
    uint side = (uniforms.radius * 2) + 1;
    uint scoreCount = side * side;
    if (gid.x >= scoreCount) {
        return;
    }
    uint partialIndex = (((blockIndex * resolve.chunkCount) + gid.z) * scoreCount) + gid.x;
    partials[partialIndex] = stabilizerPartialShiftScore(
        previous,
        current,
        uniforms,
        gid.x,
        gid.z,
        resolve.chunkCount
    );
}

kernel void stabilizerResolveShiftResults(
    device const StabilizerShiftScorePartial *partials [[buffer(SCBI_ShiftScorePartials)]],
    device StabilizerShiftResult *results [[buffer(SCBI_ShiftResults)]],
    constant StabilizerShiftResolveUniforms &resolve [[buffer(SCBI_ShiftResolveUniforms)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= resolve.blockCount) {
        return;
    }
    uint side = (resolve.radius * 2) + 1;
    uint scoreCount = side * side;
    uint bestIndex = 0;
    float bestScore = INFINITY;
    for (uint index = 0; index < scoreCount; index += 1) {
        float score = stabilizerResolvedShiftScore(partials, gid, index, scoreCount, resolve.chunkCount);
        if (score < bestScore) {
            bestIndex = index;
            bestScore = score;
        }
    }

    int bestDx = int(bestIndex % side) + resolve.centerX - int(resolve.radius);
    int bestDy = int(bestIndex / side) + resolve.centerY - int(resolve.radius);
    bool searchRadiusHit = abs(bestDx - resolve.centerX) >= int(resolve.radius)
        || abs(bestDy - resolve.centerY) >= int(resolve.radius);

    float refinedDx = float(bestDx);
    float refinedDy = float(bestDy);
    if (resolve.refine != 0 && !searchRadiusHit) {
        refinedDx += stabilizerAxisOffset(
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx - 1, bestDy, resolve, resolve.centerX, resolve.centerY),
            bestScore,
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx + 1, bestDy, resolve, resolve.centerX, resolve.centerY)
        );
        refinedDy += stabilizerAxisOffset(
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx, bestDy - 1, resolve, resolve.centerX, resolve.centerY),
            bestScore,
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx, bestDy + 1, resolve, resolve.centerX, resolve.centerY)
        );
    }

    StabilizerShiftResult result;
    result.dx = refinedDx;
    result.dy = refinedDy;
    result.score = bestScore;
    result.searchRadiusHit = searchRadiusHit ? 1u : 0u;
    results[gid] = result;
}

kernel void stabilizerResolveShiftResultsWithGlobalCenter(
    device const StabilizerShiftScorePartial *partials [[buffer(SCBI_ShiftScorePartials)]],
    device StabilizerShiftResult *results [[buffer(SCBI_ShiftResults)]],
    device const StabilizerShiftResult *globalResult [[buffer(SCBI_GlobalShiftResult)]],
    constant StabilizerShiftResolveUniforms &resolve [[buffer(SCBI_ShiftResolveUniforms)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= resolve.blockCount) {
        return;
    }
    int centerX = stabilizerRoundedShift(globalResult[0].dx);
    int centerY = stabilizerRoundedShift(globalResult[0].dy);
    uint side = (resolve.radius * 2) + 1;
    uint scoreCount = side * side;
    uint bestIndex = 0;
    float bestScore = INFINITY;
    for (uint index = 0; index < scoreCount; index += 1) {
        float score = stabilizerResolvedShiftScore(partials, gid, index, scoreCount, resolve.chunkCount);
        if (score < bestScore) {
            bestIndex = index;
            bestScore = score;
        }
    }

    int bestDx = int(bestIndex % side) + centerX - int(resolve.radius);
    int bestDy = int(bestIndex / side) + centerY - int(resolve.radius);
    bool searchRadiusHit = abs(bestDx - centerX) >= int(resolve.radius)
        || abs(bestDy - centerY) >= int(resolve.radius);

    float refinedDx = float(bestDx);
    float refinedDy = float(bestDy);
    if (resolve.refine != 0 && !searchRadiusHit) {
        refinedDx += stabilizerAxisOffset(
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx - 1, bestDy, resolve, centerX, centerY),
            bestScore,
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx + 1, bestDy, resolve, centerX, centerY)
        );
        refinedDy += stabilizerAxisOffset(
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx, bestDy - 1, resolve, centerX, centerY),
            bestScore,
            stabilizerResolvedShiftScoreAt(partials, gid, bestDx, bestDy + 1, resolve, centerX, centerY)
        );
    }

    StabilizerShiftResult result;
    result.dx = refinedDx;
    result.dy = refinedDy;
    result.score = bestScore;
    result.searchRadiusHit = searchRadiusHit ? 1u : 0u;
    results[gid] = result;
}
