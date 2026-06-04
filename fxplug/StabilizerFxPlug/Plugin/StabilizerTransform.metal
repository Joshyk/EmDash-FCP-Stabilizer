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

    float scale = max(transform->scale, 0.01);
    float2 stabilizedPixels = (rotated / scale) - (transform->pixelOffset * transform->strength);
    float2 normalizedPixels = stabilizedPixels / transform->outputSize;
    float perspectiveDenominator = max(0.35, 1.0 + (transform->perspective.x * normalizedPixels.x) + (transform->perspective.y * normalizedPixels.y));
    stabilizedPixels = stabilizedPixels / perspectiveDenominator;
    stabilizedPixels -= float2(
        transform->shear.x * stabilizedPixels.y,
        transform->shear.y * stabilizedPixels.x
    );
    float2 sampleUV = (stabilizedPixels / transform->outputSize) + 0.5;

    half4 colorSample = colorTexture.sample(textureSampler, sampleUV);
    float4 outputColor = float4(colorSample);

    if (transform->debugOverlay > 0.5) {
        float2 pixel = uv * transform->outputSize;
        float barX = pixel.x - 16.0;
        float barY = pixel.y - 16.0;
        if (barX >= 0.0 && barX <= 180.0 && barY >= 0.0 && barY <= 104.0) {
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
                color = float3(0.2, 0.45, 1.0);
            } else if (row == 3) {
                fill = saturate(transform->diagnostic.w);
                color = float3(1.0, 0.85, 0.15);
            } else if (row == 4) {
                fill = saturate(transform->diagnostic2.x);
                color = float3(0.85, 0.25, 1.0);
            } else if (row == 5) {
                fill = saturate(transform->diagnostic2.y);
                color = float3(0.1, 0.95, 0.95);
            } else if (row == 6) {
                fill = saturate(transform->diagnostic2.z);
                color = float3(1.0, 0.55, 0.15);
            } else {
                fill = saturate(transform->diagnostic2.w);
                color = float3(0.72, 0.72, 0.72);
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
