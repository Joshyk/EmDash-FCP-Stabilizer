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

static uint debugModeLabelChar(float debugMode, float runtimeBuild, float4 runtimeVersion, uint index) {
    uint major = uint(clamp(runtimeVersion.x, 0.0, 9.0) + 0.5);
    uint minor = uint(clamp(runtimeVersion.y, 0.0, 9.0) + 0.5);
    uint patch = uint(clamp(runtimeVersion.z > 0.0 ? runtimeVersion.z : runtimeBuild, 0.0, 999.0) + 0.5);
    if (index == 0) {
        return debugMode > 1.5 ? 80 : 82; // P or R
    }
    if (index == 1) { return debugDigitChar(major); }
    if (index == 2) { return 46; } // .
    if (index == 3) { return debugDigitChar(minor); }
    if (index == 4) { return 46; } // .
    if (index == 5) { return debugDigitChar(patch / 100); }
    if (index == 6) { return debugDigitChar((patch / 10) % 10); }
    if (index == 7) { return debugDigitChar(patch); }
    return 0;
}

static uint debugLabelCharAt(uint index, uint c0, uint c1, uint c2, uint c3, uint c4, uint c5, uint c6, uint c7, uint c8, uint c9, uint c10, uint c11) {
    switch (index) {
        case 0: return c0;
        case 1: return c1;
        case 2: return c2;
        case 3: return c3;
        case 4: return c4;
        case 5: return c5;
        case 6: return c6;
        case 7: return c7;
        case 8: return c8;
        case 9: return c9;
        case 10: return c10;
        case 11: return c11;
        default: return 0;
    }
}

static uint debugLabelChar(uint row, uint index, float debugMode, float runtimeBuild, float4 runtimeVersion) {
    switch (row) {
        case 0:
            return debugLabelCharAt(index, 88, 0, 79, 70, 70, 83, 69, 84, 0, 0, 0, 0); // X OFFSET
        case 1:
            return debugLabelCharAt(index, 89, 0, 79, 70, 70, 83, 69, 84, 0, 0, 0, 0); // Y OFFSET
        case 2:
            return debugLabelCharAt(index, 82, 79, 76, 76, 0, 0, 0, 0, 0, 0, 0, 0); // ROLL
        case 3:
            return debugLabelCharAt(index, 70, 79, 79, 84, 0, 83, 84, 69, 80, 0, 0, 0); // FOOT STEP
        case 4:
            return debugLabelCharAt(index, 83, 84, 82, 73, 68, 69, 0, 0, 0, 0, 0, 0); // STRIDE
        case 5:
            return debugLabelCharAt(index, 70, 65, 82, 0, 87, 65, 82, 80, 0, 0, 0, 0); // FAR WARP
        case 6:
            return debugLabelCharAt(index, 84, 85, 82, 78, 0, 0, 0, 0, 0, 0, 0, 0); // TURN
        case 7:
            return debugLabelCharAt(index, 70, 79, 79, 84, 0, 67, 79, 78, 70, 0, 0, 0); // FOOT CONF
        case 8:
            return debugLabelCharAt(index, 83, 84, 82, 73, 68, 69, 0, 67, 79, 78, 70, 0); // STRIDE CONF
        case 9:
            return debugLabelCharAt(index, 87, 65, 82, 80, 0, 67, 79, 78, 70, 0, 0, 0); // WARP CONF
        case 10:
            return debugLabelCharAt(index, 84, 85, 82, 78, 0, 67, 79, 78, 70, 0, 0, 0); // TURN CONF
        case 11:
            return debugLabelCharAt(index, 83, 77, 79, 79, 84, 72, 0, 0, 0, 0, 0, 0); // SMOOTH
        case 12:
            return debugLabelCharAt(index, 84, 82, 65, 67, 75, 0, 67, 79, 78, 70, 0, 0); // TRACK CONF
        case 13:
            return debugLabelCharAt(index, 83, 72, 65, 82, 80, 78, 69, 83, 83, 0, 0, 0); // SHARPNESS
        case 14:
            return debugLabelCharAt(index, 77, 65, 84, 67, 72, 0, 81, 85, 65, 76, 0, 0); // MATCH QUAL
        case 15:
            return debugLabelCharAt(index, 69, 68, 71, 69, 0, 83, 65, 70, 69, 0, 0, 0); // EDGE SAFE
        case 16:
            return debugLabelCharAt(index, 87, 65, 76, 75, 0, 67, 79, 78, 70, 0, 0, 0); // WALK CONF
        case 17:
            return debugLabelCharAt(index, 67, 82, 79, 80, 0, 90, 79, 79, 77, 0, 0, 0); // CROP ZOOM
        case 18:
            return debugLabelCharAt(index, 76, 69, 78, 83, 0, 0, 0, 0, 0, 0, 0, 0); // LENS
        case 19:
            return debugModeLabelChar(debugMode, runtimeBuild, runtimeVersion, index);
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
    if (index >= 12) {
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
constant float lensBandTopRadius = 0.18;
constant float lensBandRidgeRadius = 0.20;
constant float lensBandMidRadius = 0.19;
constant float lensBandFadeStart = 0.46;
constant float lensBandFadeEnd = 0.58;
constant float lensBandInterBandDifferentialGain = 0.10;
constant float lensBandColumnDifferentialGain = 0.08;
constant float lensBandRowPhaseGain = 0.05;
constant float lensBandLocalRollGain = 0.04;

constant float sourceLensLocalTopCenter = 0.10;
constant float sourceLensLocalRidgeCenter = 0.25;
constant float sourceLensLocalMidCenter = 0.42;
constant float sourceLensLocalTopRadius = 0.18;
constant float sourceLensLocalRidgeRadius = 0.19;
constant float sourceLensLocalMidRadius = 0.18;
constant float sourceLensLocalFadeStart = 0.48;
constant float sourceLensLocalFadeEnd = 0.58;
constant float sourceLensLocalColumnDifferentialGain = 0.08;
constant float sourceLensLocalBandDifferentialGain = 0.08;

constant float sourceLensRidgeCenter = 0.25;
constant float sourceLensRidgeRadius = 0.14;
constant float sourceLensRidgeFadeStart = 0.38;
constant float sourceLensRidgeFadeEnd = 0.52;

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
    if (lensBandSupport > 0.0001) {
        float sourceY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float farFieldFade = 1.0 - smoothstep(lensBandFadeStart, lensBandFadeEnd, sourceY);
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
            float2 bandOffset = commonBandOffset
                + ((weightedBandOffset - commonBandOffset) * lensBandInterBandDifferentialGain);
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
            bandOffset += columnOffset * columnPhase * lensBandColumnDifferentialGain;
            bandOffset += rowPhaseOffset * lensBandRowPhaseGain;
            bandOffset += localRollOffset * lensBandLocalRollGain;
            stabilizedPixels -= bandOffset * lensBandSupport * farFieldFade * transform->strength;
        }
    }
    float localLensSupport = saturate(transform->sourceLensShakeLocalApplied)
        * lensBandAppliedGain(transform->sourceLensShakeLocalSupport);
    if (localLensSupport > 0.0001) {
        float sourceY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float farFieldFade = 1.0 - smoothstep(sourceLensLocalFadeStart, sourceLensLocalFadeEnd, sourceY);
        float topWeight = lensBandWeight(sourceY, sourceLensLocalTopCenter, sourceLensLocalTopRadius);
        float ridgeWeight = lensBandWeight(sourceY, sourceLensLocalRidgeCenter, sourceLensLocalRidgeRadius);
        float midWeight = lensBandWeight(sourceY, sourceLensLocalMidCenter, sourceLensLocalMidRadius);
        float totalBandWeight = topWeight + ridgeWeight + midWeight;
        if (totalBandWeight > 0.0001) {
            float sourceX = saturate((stabilizedPixels.x / transform->outputSize.x) + 0.5);
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
                + ((topColumnOffset - topCommonColumnOffset) * sourceLensLocalColumnDifferentialGain);
            float2 ridgeOffset = ridgeCommonColumnOffset
                + ((ridgeColumnOffset - ridgeCommonColumnOffset) * sourceLensLocalColumnDifferentialGain);
            float2 midOffset = midCommonColumnOffset
                + ((midColumnOffset - midCommonColumnOffset) * sourceLensLocalColumnDifferentialGain);
            float2 weightedLocalOffset = (
                (topOffset * topWeight)
                + (ridgeOffset * ridgeWeight)
                + (midOffset * midWeight)
            ) / totalBandWeight;
            float2 commonLocalOffset = (topOffset + ridgeOffset + midOffset) / 3.0;
            float2 localOffset = commonLocalOffset
                + ((weightedLocalOffset - commonLocalOffset) * sourceLensLocalBandDifferentialGain);
            stabilizedPixels -= localOffset * localLensSupport * farFieldFade * transform->strength;
        }
    }
    float sourceRidgeSupport = saturate(transform->sourceLensShakeRidgeApplied)
        * lensBandAppliedGain(transform->sourceLensShakeRidgeSupport);
    if (sourceRidgeSupport > 0.0001) {
        float sourceY = saturate((stabilizedPixels.y / transform->outputSize.y) + 0.5);
        float ridgeWeight = lensBandWeight(sourceY, sourceLensRidgeCenter, sourceLensRidgeRadius);
        float farFieldFade = 1.0 - smoothstep(sourceLensRidgeFadeStart, sourceLensRidgeFadeEnd, sourceY);
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

    if (transform->debugOverlay > 0.5) {
        float2 pixel = uv * transform->outputSize;
        float overlayScale = clamp(transform->debugOverlayScale, 0.25, 8.0);
        float panelX = pixel.x - (16.0 * overlayScale);
        float panelY = pixel.y - (16.0 * overlayScale);
        float labelWidth = 96.0 * overlayScale;
        float labelGap = 2.0 * overlayScale;
        float barWidth = 180.0 * overlayScale;
        float rowHeight = 13.0 * overlayScale;
        float panelWidth = labelWidth + labelGap + barWidth;
        float panelHeight = 20.0 * rowHeight;
        if (panelX >= 0.0 && panelX < panelWidth && panelY >= 0.0 && panelY < panelHeight) {
            uint row = uint(floor(panelY / rowHeight));
            float rowY = panelY - (float(row) * rowHeight);
            float fill = 0.0;
            float3 color = float3(0.94, 0.96, 0.98);
            if (row == 0) {
                fill = saturate(transform->diagnostic.x);
            } else if (row == 1) {
                fill = saturate(transform->diagnostic.y);
            } else if (row == 2) {
                fill = saturate(transform->diagnostic.z);
            } else if (row == 3) {
                fill = saturate(transform->diagnostic2.y);
            } else if (row == 4) {
                fill = saturate(transform->diagnostic2.z);
            } else if (row == 5) {
                fill = saturate(transform->diagnostic2.w);
            } else if (row == 6) {
                fill = saturate(transform->diagnostic2.x);
            } else if (row == 7) {
                fill = saturate(transform->diagnostic3.y);
            } else if (row == 8) {
                fill = saturate(transform->diagnostic3.z);
            } else if (row == 9) {
                fill = saturate(transform->diagnostic3.w);
            } else if (row == 10) {
                fill = saturate(transform->diagnostic4.x);
            } else if (row == 11) {
                fill = saturate(transform->diagnostic3.x);
            } else if (row == 12) {
                fill = saturate(transform->diagnostic4.y);
            } else if (row == 13) {
                fill = saturate(transform->diagnostic4.z);
            } else if (row == 14) {
                fill = saturate(transform->diagnostic4.w);
            } else if (row == 15) {
                fill = saturate(transform->diagnostic.w);
            } else if (row == 16) {
                fill = saturate(transform->diagnostic5.x);
            } else if (row == 17) {
                fill = saturate(transform->diagnostic5.y);
            } else if (row == 18) {
                fill = saturate(transform->diagnostic5.z);
            } else if (row == 19) {
                fill = 1.0;
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
