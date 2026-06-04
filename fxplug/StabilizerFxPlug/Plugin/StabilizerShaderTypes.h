#ifndef StabilizerShaderTypes_h
#define StabilizerShaderTypes_h

#import <simd/simd.h>

typedef enum StabilizerVertexInputIndex {
    SVI_Vertices = 0,
    SVI_ViewportSize = 1
} StabilizerVertexInputIndex;

typedef enum StabilizerTextureIndex {
    STI_InputImage = 0
} StabilizerTextureIndex;

typedef enum StabilizerFragmentIndex {
    SFI_Transform = 0
} StabilizerFragmentIndex;

typedef struct StabilizerVertex2D {
    vector_float2 position;
    vector_float2 textureCoordinate;
} StabilizerVertex2D;

typedef struct StabilizerTransformUniforms {
    vector_float2 pixelOffset;
    float rotationRadians;
    float scale;
    float strength;
    vector_float2 outputSize;
    vector_float4 diagnostic;
    vector_float4 diagnostic2;
    vector_float2 shear;
    vector_float2 perspective;
    float debugOverlay;
} StabilizerTransformUniforms;

#endif
