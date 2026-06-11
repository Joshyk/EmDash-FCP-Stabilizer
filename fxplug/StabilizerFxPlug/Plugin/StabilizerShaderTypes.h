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

typedef enum StabilizerComputeTextureIndex {
    SCTI_InputImage = 0
} StabilizerComputeTextureIndex;

typedef enum StabilizerFragmentIndex {
    SFI_Transform = 0
} StabilizerFragmentIndex;

typedef enum StabilizerComputeBufferIndex {
    SCBI_PreviousFrame = 0,
    SCBI_CurrentFrame = 1,
    SCBI_ShiftScores = 2,
    SCBI_ShiftUniforms = 3,
    SCBI_DownsampleOutput = 0,
    SCBI_DownsampleUniforms = 1
} StabilizerComputeBufferIndex;

typedef struct StabilizerVertex2D {
    vector_float2 position;
    vector_float2 textureCoordinate;
} StabilizerVertex2D;

typedef struct StabilizerShiftUniforms {
    uint width;
    uint height;
    uint x0;
    uint y0;
    uint regionWidth;
    uint regionHeight;
    int centerX;
    int centerY;
    uint radius;
    uint stride;
} StabilizerShiftUniforms;

typedef struct StabilizerDownsampleUniforms {
    uint width;
    uint height;
} StabilizerDownsampleUniforms;

typedef struct StabilizerTransformUniforms {
    vector_float2 pixelOffset;
    float rotationRadians;
    float strength;
    vector_float2 outputSize;
    vector_float4 diagnostic;
    vector_float4 diagnostic2;
    vector_float4 diagnostic3;
    vector_float4 diagnostic4;
    vector_float4 diagnostic5;
    vector_float2 shear;
    vector_float2 perspective;
    float edgeMode;
    float debugOverlay;
    float debugMode;
} StabilizerTransformUniforms;

#endif
