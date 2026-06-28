# Gemini Prompt: Walking Smoothing Debug Review

You are reviewing a native Final Cut Pro FxPlug stabilizer implementation for walking-gimbal outdoor footage.

Repository context:

- The Final Cut Pro effect must stay native FxPlug/Metal code. Do not suggest
  CommandPost, Lua timeline automation, Transform-keyframe writers, or CPU
  analysis fallbacks.
- Analysis generation currently comes from the local Stabilizer Event Analyzer,
  which writes Event-scoped persisted caches. New FxPlug effect instances are
  cache consumers: they validate and render from those caches instead of asking
  Final Cut Pro to start Host Analysis from the Inspector.
- If Metal analysis resources are unavailable, the analysis path should fail
  visibly in logs/status instead of falling back to CPU analysis.
- The effect intentionally avoids Final Cut Pro's built-in Stabilization and
  does not write Final Cut Pro Transform keyframes. `Remove Black Edges` may
  apply dynamic Auto Crop render scale during playback.
- The render path should correct X/Y translation and roll, plus a bundled small-clamp
  `Far-field Warp Strength` for deskew/shear, yaw/pitch proxy, and perspective trim.
- The active walking controls already exist:
  - `Footstep Jitter X Strength`
  - `Footstep Jitter Y Strength`
  - `Footstep Jitter Rotation Strength`
  - `Stride Wobble X Strength`
  - `Stride Wobble Y Strength`
  - `Stride Wobble Rotation Strength`
  - `Far-field Warp Strength`
  - `Turn Smoothing Strength`
  - `Footstep Jitter Rotation Strength` and `Stride Wobble Rotation Strength`
    both default to `0.5`.
  - `Far-field Warp Strength` defaults to `0.5`, keeps the previous `4.0`
    response unchanged, and exposes up to `12.0`.
- Do not add a Footstep Jitter window.
- Do not recommend a separate post-stride Y-only bounce stage, Inspector control, or diagnostic band.
- Do not rerun Host Analysis during render.
- Host Analysis cache schema should be bumped when prepared analysis output semantics change.

Current implementation to review:

- `fxplug/TokyoWalkingStabilizer/Plugin/AutoStabilizationEstimator.swift`
  - `estimate(preparedAnalysis:renderTime:...)` calls `temporallySmoothedEstimate`.
  - `temporallySmoothedEstimate` skips out-of-range neighboring samples at clip edges
    instead of clamping them to the first or last analysis frame.
  - `rawEstimate` calculates the center-frame correction split into:
    - `macroPixelOffset.x` for X-only Turn Smoothing
    - `microPixelOffset` for Footstep Jitter
    - `strideWobblePixelOffset` for Stride Wobble
  - `temporallySmoothedEstimate` samples neighboring render times symmetrically and blends the final automatic transform with zero phase.
  - Turn Smoothing applies only to X translation and requires both tracking evidence and a real X turn band, without a hidden minimum turn-confidence floor.
  - Footstep Jitter X/Y and roll use only a short same-direction, confidence-aware neighborhood around the current center-frame impulse correction so fine ridge-line shake is smoother without being averaged away.
  - Footstep Jitter uses per-frame confidence without a hidden minimum floor before applying X/Y/roll correction, checks local baseline support plus surrounding footstep noise, and stays clamped at full detected-impulse removal.
  - Stride/Turn residual gates use robust window percentiles rather than the single worst residual in the window.
  - Far-field Warp render gating curves medium-confidence tracking/search-headroom evidence upward while preserving zero correction for zero evidence.
  - Far-field Warp estimates conservative deskew/shear, yaw/pitch proxy, and perspective trim from upper-frame residual blocks after translation and roll are removed.
  - `StabilizerAutoTransform` now carries:
    - final smoothed `pixelOffset` and `rotationDegrees`
    - center-frame raw `rawPixelOffset` and `rawRotationDegrees`
    - `temporalSmoothingPixelDelta`
    - `temporalSmoothingRotationDelta`
    - effective Footstep Jitter X/Y/R strength
    - `warpConfidence`, `shear`, `yawPitchProxy`, and `perspective`
    - sample count and smoothing window seconds
- `fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizer.swift`
  - `Debug Overlay` diagnostic bars now represent final X/Y/roll, Footstep Jitter, Stride Wobble, Far-field Warp, Turn Smoothing, temporal smoothing delta, Footstep/Stride/Warp/Turn confidence, tracking quality, sharpness, residual quality, and search-radius headroom.
  - While `Debug Overlay` is enabled, `Host Analysis Status` reports raw transform, smoothed delta, tracking/motion confidence, blur, residual, raw `foot q`, effective Footstep Jitter X/Y/R strength, `stride q`, `warp q`, shear, yaw/pitch proxy, perspective, block counts, edge-hit counts, X turn correction, and Y footstep/stride component split.
- `fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizerTransform.metal`
  - The overlay draws eighteen labeled rows of diagnostic bars.

Please review this implementation for walking-gimbal smoothing quality. Focus on:

1. Whether the temporal smoothing is mathematically zero-phase and does not introduce pan lag.
2. Whether averaging the final transform can weaken Footstep Jitter impulse removal too much.
3. Whether Turn Smoothing stays X-only while Footstep Jitter and Stride Wobble remain correctly ordered for Y correction.
4. Whether the debug output exposes enough information to diagnose overcorrection, undercorrection, and confidence gating.
5. Whether the normalization of the debug bars is useful for 1080p and 4K footage.
6. Any specific code-level changes that would make the walking footage smoother without adding fallbacks, render-time block matching, or extra user-visible zoom controls.

Return concrete recommendations with file/function targets. If you suggest code changes, keep them within the FxPlug render-time path and explain whether they require a Host Analysis cache schema bump.
