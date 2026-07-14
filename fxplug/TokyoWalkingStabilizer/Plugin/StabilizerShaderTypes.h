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
    SCBI_ShiftBatchUniforms = 3,
    SCBI_DownsampleOutput = 0,
    SCBI_DownsampleUniforms = 1,
    SCBI_ShiftScorePartials = 4,
    SCBI_ShiftResults = 5,
    SCBI_ShiftResolveUniforms = 6,
    SCBI_GlobalShiftResult = 7
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

typedef struct StabilizerShiftBatchUniforms {
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
} StabilizerShiftBatchUniforms;

typedef struct StabilizerDownsampleUniforms {
    uint width;
    uint height;
} StabilizerDownsampleUniforms;

typedef struct StabilizerShiftScorePartial {
    float total;
    uint samples;
} StabilizerShiftScorePartial;

typedef struct StabilizerShiftResult {
    float dx;
    float dy;
    float score;
    uint searchRadiusHit;
} StabilizerShiftResult;

typedef struct StabilizerShiftResolveUniforms {
    uint radius;
    uint chunkCount;
    uint blockCount;
    int centerX;
    int centerY;
    uint refine;
} StabilizerShiftResolveUniforms;

#define STABILIZER_DEBUG_OVERLAY_ROW_COUNT 21

typedef enum StabilizerDebugOverlayRow {
    StabilizerDebugOverlayRowXOffset = 0,
    StabilizerDebugOverlayRowYOffset = 1,
    StabilizerDebugOverlayRowRoll = 2,
    StabilizerDebugOverlayRowCrop = 3,
    StabilizerDebugOverlayRowTurn = 4,
    StabilizerDebugOverlayRowMacroJitter = 5,
    StabilizerDebugOverlayRowMicroJitter = 6,
    StabilizerDebugOverlayRowFarFieldWarp = 7,
    StabilizerDebugOverlayRowLens = 8,
    StabilizerDebugOverlayRowSmoothing = 9,
    StabilizerDebugOverlayRowTrackingQuality = 10,
    StabilizerDebugOverlayRowWalkingQuality = 11,
    StabilizerDebugOverlayRowSharpnessQuality = 12,
    StabilizerDebugOverlayRowResidualQuality = 13,
    StabilizerDebugOverlayRowSearchRadiusHeadroomQuality = 14,
    StabilizerDebugOverlayRowTurnConfidence = 15,
    StabilizerDebugOverlayRowMacroConfidence = 16,
    StabilizerDebugOverlayRowMicroConfidence = 17,
    StabilizerDebugOverlayRowWarpConfidence = 18,
    StabilizerDebugOverlayRowLensConfidence = 19,
    StabilizerDebugOverlayRowRuntime = 20
} StabilizerDebugOverlayRow;

typedef struct StabilizerDebugOverlayDiagnostics {
    float xOffset;
    float yOffset;
    float roll;
    float crop;
    float turn;
    float macroJitter;
    float microJitter;
    float farFieldWarp;
    float lens;
    float smoothing;
    float trackingQuality;
    float walkingQuality;
    float sharpnessQuality;
    float residualQuality;
    float searchRadiusHeadroomQuality;
    float turnConfidence;
    float macroConfidence;
    float microConfidence;
    float warpConfidence;
    float lensConfidence;
} StabilizerDebugOverlayDiagnostics;

typedef struct TokyoWalkingStabilizerTransformUniforms {
    vector_float2 pixelOffset;
    float rotationRadians;
    vector_float2 rotationSinCos;
    float strength;
    vector_float2 outputSize;
    StabilizerDebugOverlayDiagnostics debugDiagnostics;
    vector_float2 shear;
    vector_float2 perspective;
    float edgeMode;
    float debugOverlay;
    float debugMode;
    float debugRuntimeBuild;
    vector_float4 debugRuntimeVersion;
    float debugOverlayScale;
    float debugMeshOverlayMode;
    float autoCropScale;
    vector_float2 autoCropPositionPixels;
    vector_float2 lensBandTopOffset;
    vector_float2 lensBandRidgeOffset;
    vector_float2 lensBandMidOffset;
    vector_float2 lensBandTopColumnOffset;
    vector_float2 lensBandRidgeColumnOffset;
    vector_float2 lensBandMidColumnOffset;
    vector_float2 lensBandTopRowPhaseOffset;
    vector_float2 lensBandRidgeRowPhaseOffset;
    vector_float2 lensBandMidRowPhaseOffset;
    float lensBandTopLocalRoll;
    float lensBandRidgeLocalRoll;
    float lensBandMidLocalRoll;
    float lensBandWarpSupport;
    float lensBandWarpApplied;
    float lensFarFieldRigidOnlyApplied;
    vector_float2 sourceLensShakeRidgeOffset;
    float sourceLensShakeRidgeSupport;
    float sourceLensShakeRidgeApplied;
    vector_float2 sourceLensShakeLocalTopLeftOffset;
    vector_float2 sourceLensShakeLocalTopCenterOffset;
    vector_float2 sourceLensShakeLocalTopRightOffset;
    vector_float2 sourceLensShakeLocalRidgeLeftOffset;
    vector_float2 sourceLensShakeLocalRidgeCenterOffset;
    vector_float2 sourceLensShakeLocalRidgeRightOffset;
    vector_float2 sourceLensShakeLocalMidLeftOffset;
    vector_float2 sourceLensShakeLocalMidCenterOffset;
    vector_float2 sourceLensShakeLocalMidRightOffset;
    float sourceLensShakeLocalSupport;
    float sourceLensShakeLocalApplied;
    vector_float4 debugFarFieldMesh;
    vector_float4 debugFarFieldMeshWindow;
} TokyoWalkingStabilizerTransformUniforms;

#endif
