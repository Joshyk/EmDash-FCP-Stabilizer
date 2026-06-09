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
        case 66: // B
            if (y == 0 || y == 2 || y == 4) { return 0x6; }
            return 0x5;
        case 69: // E
            if (y == 0 || y == 4) { return 0x7; }
            if (y == 2) { return 0x6; }
            return 0x4;
        case 70: // F
            if (y == 0) { return 0x7; }
            if (y == 2) { return 0x6; }
            return 0x4;
        case 72: // H
            if (y == 2) { return 0x7; }
            return 0x5;
        case 73: // I
            return (y == 0 || y == 4) ? 0x7 : 0x2;
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
        case 87: // W
            if (y == 2 || y == 3) { return 0x7; }
            return 0x5;
        case 88: // X
            return y == 2 ? 0x2 : 0x5;
        case 89: // Y
            return y < 2 ? 0x5 : 0x2;
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

static uint debugLabelChar(uint row, uint index) {
    switch (row) {
        case 0:
            return index == 0 ? 88 : 0; // X
        case 1:
            return index == 0 ? 89 : 0; // Y
        case 2:
            if (index == 0) { return 82; } // R
            if (index == 1) { return 79; } // O
            if (index == 2 || index == 3) { return 76; } // L
            return 0;
        case 3:
            if (index == 0) { return 84; } // T
            if (index == 1) { return 85; } // U
            if (index == 2) { return 82; } // R
            if (index == 3) { return 78; } // N
            return 0;
        case 4:
            if (index == 0) { return 83; } // S
            if (index == 1) { return 84; } // T
            if (index == 2) { return 69; } // E
            if (index == 3) { return 80; } // P
            return 0;
        case 5:
            if (index == 0) { return 66; } // B
            if (index == 1) { return 79; } // O
            if (index == 2) { return 66; } // B
            return 0;
        case 6:
            if (index == 0) { return 83; } // S
            if (index == 1) { return 77; } // M
            if (index == 2) { return 84; } // T
            if (index == 3) { return 72; } // H
            return 0;
        case 7:
            if (index == 0) { return 70; } // F
            if (index == 2) { return 81; } // Q
            return 0;
        case 8:
            if (index == 0) { return 83; } // S
            if (index == 2) { return 81; } // Q
            return 0;
        case 9:
            if (index == 0) { return 66; } // B
            if (index == 2) { return 81; } // Q
            return 0;
        case 10:
            if (index == 0) { return 87; } // W
            if (index == 2) { return 81; } // Q
            return 0;
        case 11:
            if (index == 0) { return 84; } // T
            if (index == 1) { return 82; } // R
            if (index == 2) { return 75; } // K
            return 0;
        case 12:
            if (index == 0) { return 66; } // B
            if (index == 1) { return 76; } // L
            if (index == 2) { return 85; } // U
            if (index == 3) { return 82; } // R
            return 0;
        case 13:
            if (index == 0) { return 82; } // R
            if (index == 1) { return 69; } // E
            if (index == 2) { return 83; } // S
            return 0;
        case 14:
            if (index == 0) { return 72; } // H
            if (index == 1) { return 73; } // I
            if (index == 2) { return 84; } // T
            return 0;
        default:
            return 0;
    }
}

static bool debugLabelCoverage(float panelX, float rowY, uint row) {
    constexpr float textScale = 2.0;
    constexpr float glyphWidth = 3.0;
    constexpr float glyphHeight = 5.0;
    constexpr float glyphAdvance = 4.0 * textScale;

    float textX = panelX - 6.0;
    float textY = rowY - 2.0;
    if (textX < 0.0 || textY < 0.0 || textY >= glyphHeight * textScale) {
        return false;
    }

    uint index = uint(floor(textX / glyphAdvance));
    if (index >= 4) {
        return false;
    }

    float glyphLocalX = textX - (float(index) * glyphAdvance);
    if (glyphLocalX >= glyphWidth * textScale) {
        return false;
    }

    uint glyphX = uint(floor(glyphLocalX / textScale));
    uint glyphY = uint(floor(textY / textScale));
    return debugLabelPixel(debugLabelChar(row, index), glyphX, glyphY);
}

fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<half> colorTexture [[texture(STI_InputImage)]],
    constant StabilizerTransformUniforms *transform [[buffer(SFI_Transform)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = in.textureCoordinate;
    float2 centeredPixels = (uv - 0.5) * transform->outputSize;

    float s = sin(-transform->rotationRadians);
    float c = cos(-transform->rotationRadians);
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
    float2 sampleUV = (stabilizedPixels / transform->outputSize) + 0.5;

    bool outsideSource = sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0;
    half4 colorSample = colorTexture.sample(textureSampler, sampleUV);
    float4 outputColor = (transform->edgeMode > 0.5 && outsideSource)
        ? float4(0.0, 0.0, 0.0, 1.0)
        : float4(colorSample);

    if (transform->debugOverlay > 0.5) {
        float2 pixel = uv * transform->outputSize;
        float panelX = pixel.x - 16.0;
        float panelY = pixel.y - 16.0;
        constexpr float labelWidth = 44.0;
        constexpr float labelGap = 6.0;
        constexpr float barWidth = 180.0;
        constexpr float rowHeight = 13.0;
        constexpr float panelWidth = labelWidth + labelGap + barWidth;
        constexpr float panelHeight = 15.0 * rowHeight;
        if (panelX >= 0.0 && panelX < panelWidth && panelY >= 0.0 && panelY < panelHeight) {
            uint row = uint(floor(panelY / rowHeight));
            float rowY = panelY - (float(row) * rowHeight);
            float fill = 0.0;
            float3 color = float3(1.0);
            if (row == 0) {
                fill = saturate(transform->diagnostic.x);
                color = float3(1.0, 0.15, 0.12);
            } else if (row == 1) {
                fill = saturate(transform->diagnostic.y);
                color = float3(0.2, 0.9, 0.25);
            } else if (row == 2) {
                fill = saturate(transform->diagnostic.z);
                color = float3(1.0, 0.85, 0.15);
            } else if (row == 3) {
                fill = saturate(transform->diagnostic2.x);
                color = float3(0.1, 0.55, 1.0);
            } else if (row == 4) {
                fill = saturate(transform->diagnostic2.y);
                color = float3(1.0, 0.25, 0.95);
            } else if (row == 5) {
                fill = saturate(transform->diagnostic2.z);
                color = float3(0.2, 0.95, 1.0);
            } else if (row == 6) {
                fill = saturate(transform->diagnostic2.w);
                color = float3(0.95, 0.95, 0.95);
            } else if (row == 7) {
                fill = saturate(transform->diagnostic3.x);
                color = float3(0.55, 0.95, 0.25);
            } else if (row == 8) {
                fill = saturate(transform->diagnostic3.y);
                color = float3(0.2, 0.65, 1.0);
            } else if (row == 9) {
                fill = saturate(transform->diagnostic3.z);
                color = float3(0.75, 0.35, 1.0);
            } else if (row == 10) {
                fill = saturate(transform->diagnostic3.w);
                color = float3(1.0, 0.45, 0.25);
            } else if (row == 11) {
                fill = saturate(transform->diagnostic4.x);
                color = float3(0.2, 1.0, 0.55);
            } else if (row == 12) {
                fill = saturate(transform->diagnostic4.y);
                color = float3(0.75, 1.0, 0.25);
            } else if (row == 13) {
                fill = saturate(transform->diagnostic4.z);
                color = float3(1.0, 0.65, 0.15);
            } else if (row == 14) {
                fill = saturate(transform->diagnostic4.w);
                color = float3(1.0, 0.1, 0.1);
            }
            float barX = panelX - labelWidth - labelGap;
            bool inBar = barX >= 0.0 && barX <= barWidth && rowY >= 2.0 && rowY <= 11.0;
            float activeWidth = barWidth * fill;
            float3 background = float3(0.02, 0.02, 0.02);
            float3 overlay = background;
            float alpha = 0.62;
            if (inBar) {
                overlay = barX <= activeWidth ? color : background;
                alpha = 0.78;
            }
            if (debugLabelCoverage(panelX, rowY, row)) {
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
