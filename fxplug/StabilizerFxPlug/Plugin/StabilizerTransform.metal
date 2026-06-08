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
        float barX = pixel.x - 16.0;
        float barY = pixel.y - 16.0;
        if (barX >= 0.0 && barX <= 180.0 && barY >= 0.0 && barY <= 143.0) {
            int row = int(floor(barY / 13.0));
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
            }
            float activeWidth = 180.0 * fill;
            float3 background = float3(0.02, 0.02, 0.02);
            float3 overlay = barX <= activeWidth ? color : background;
            outputColor.rgb = mix(outputColor.rgb, overlay, 0.78);
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
