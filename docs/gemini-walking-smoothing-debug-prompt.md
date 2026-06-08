# Gemini Prompt: Walking Smoothing Debug Review

You are reviewing a native Final Cut Pro FxPlug stabilizer implementation for walking-gimbal outdoor footage.

Repository context:

- This project is FxPlug-only. Do not suggest CommandPost, Lua, Python, standalone estimators, timeline automation, or CPU analysis fallbacks.
- Host Analysis uses Final Cut Pro FxPlug analysis frames and Metal compute inside the plug-in runtime.
- If Metal analysis resources are unavailable, the Host Analysis path should fail visibly in logs/status.
- The effect intentionally avoids Final Cut Pro's built-in Stabilization and avoids zoom/scale correction.
- The render path should correct X/Y translation and roll only.
- The active walking controls already exist:
  - `Footstep Jitter X Strength`
  - `Footstep Jitter Y Strength`
  - `Footstep Jitter Rotation Strength`
  - `Turn Smoothing Strength`
  - `Walking Bob Window`
  - `Walking Bob Removal`
- Do not add a Footstep Jitter window.
- Do not rerun Host Analysis during render.
- Do not change Host Analysis cache schema for render-only smoothing/debug changes.

Current implementation to review:

- `fxplug/StabilizerFxPlug/Plugin/AutoStabilizationEstimator.swift`
  - `estimate(preparedAnalysis:renderTime:...)` calls `temporallySmoothedEstimate`.
  - `rawEstimate` calculates the center-frame correction split into:
    - `macroPixelOffset` for Turn Smoothing
    - `microPixelOffset` for Footstep Jitter
    - `walkingBobPixelOffset` for Walking Bob
  - `temporallySmoothedEstimate` samples neighboring render times symmetrically and blends the final automatic transform with zero phase.
  - Turn Smoothing and Walking Bob components are temporally smoothed, but Footstep Jitter X/Y and roll use the current center-frame impulse correction so fine ridge-line shake is not averaged away.
  - Footstep Jitter uses a render-time minimum effective confidence floor before applying X/Y/roll correction, still clamped at full detected-impulse removal.
  - `StabilizerAutoTransform` now carries:
    - final smoothed `pixelOffset` and `rotationDegrees`
    - center-frame raw `rawPixelOffset` and `rawRotationDegrees`
    - `temporalSmoothingPixelDelta`
    - `temporalSmoothingRotationDelta`
    - effective Footstep Jitter X/Y/R strength
    - sample count and smoothing window seconds
- `fxplug/StabilizerFxPlug/Plugin/StabilizerFxPlug.swift`
  - `Debug Overlay` diagnostic bars now represent final X/Y/roll, Turn Smoothing, Footstep Jitter, Walking Bob, and temporal smoothing delta.
  - While `Debug Overlay` is enabled, `Host Analysis Status` reports raw transform, smoothed delta, raw `foot q`, effective Footstep Jitter X/Y/R strength, block counts, and Y component split.
- `fxplug/StabilizerFxPlug/Plugin/StabilizerTransform.metal`
  - The overlay draws seven rows of diagnostic bars.

Please review this implementation for walking-gimbal smoothing quality. Focus on:

1. Whether the temporal smoothing is mathematically zero-phase and does not introduce pan lag.
2. Whether averaging the final transform can weaken Footstep Jitter impulse removal too much.
3. Whether Turn Smoothing, Footstep Jitter, and Walking Bob remain correctly ordered for Y correction.
4. Whether the debug output exposes enough information to diagnose overcorrection, undercorrection, and confidence gating.
5. Whether the normalization of the debug bars is useful for 1080p and 4K footage.
6. Any specific code-level changes that would make the walking footage smoother without adding fallbacks, zoom, perspective warp, or render-time block matching.

Return concrete recommendations with file/function targets. If you suggest code changes, keep them within the FxPlug render-time path and explain whether they require a Host Analysis cache schema bump.
