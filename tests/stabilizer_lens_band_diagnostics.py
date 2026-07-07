#!/usr/bin/env python3
"""Join FCP render lens-shake logs with per-frame far-field band flow."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

import cv2
import numpy as np


PAIR_PATTERN = re.compile(r"([A-Za-z][A-Za-z0-9]*)=([^ |]+)")
PREFIX = "Render frame components csv v1 |"
LENS_PREFIX = "Render lens band csv v1 |"
RIGID_PREFIX = "Render lens rigid csv v1 |"
LOCAL_PREFIX = "Render lens local csv v1 |"
RIDGE_LINE_PREFIX = "Render lens ridge line csv v1 |"

BANDS = {
    "cloud_top": (0.06, 0.22),
    "ridge_horizon": (0.18, 0.34),
    "mountain_mid": (0.30, 0.50),
    "near_ground": (0.58, 0.82),
}

FAR_FIELD_BANDS = ("cloud_top", "ridge_horizon", "mountain_mid")
MODEL_COMPONENTS = {
    "row": "lensBandRollingShutterRowScore",
    "column": "lensBandRollingShutterColScore",
    "roll": "lensBandRollingShutterRollScore",
    "interBand": "lensBandRollingShutterInterBandScore",
}
REGIONS = {
    "left": (0.00, 0.38, 0.00, 1.00),
    "center": (0.28, 0.72, 0.00, 1.00),
    "right": (0.62, 1.00, 0.00, 1.00),
    "upper": (0.00, 1.00, 0.00, 0.58),
    "lower": (0.00, 1.00, 0.42, 1.00),
}

LENS_BAND_TOP_CENTER = 0.10
LENS_BAND_RIDGE_CENTER = 0.25
LENS_BAND_MID_CENTER = 0.40
LENS_BAND_TOP_RADIUS = 0.18
LENS_BAND_RIDGE_RADIUS = 0.20
LENS_BAND_MID_RADIUS = 0.19
LENS_BAND_FADE_START = 0.46
LENS_BAND_FADE_END = 0.58
LENS_BAND_INTER_BAND_DIFFERENTIAL_GAIN = 0.10
LENS_BAND_COLUMN_DIFFERENTIAL_GAIN = 0.08
LENS_BAND_ROW_PHASE_GAIN = 0.05
LENS_BAND_LOCAL_ROLL_GAIN = 0.04
SOURCE_LENS_LOCAL_TOP_CENTER = 0.10
SOURCE_LENS_LOCAL_RIDGE_CENTER = 0.25
SOURCE_LENS_LOCAL_MID_CENTER = 0.42
SOURCE_LENS_LOCAL_TOP_RADIUS = 0.18
SOURCE_LENS_LOCAL_RIDGE_RADIUS = 0.19
SOURCE_LENS_LOCAL_MID_RADIUS = 0.18
SOURCE_LENS_LOCAL_FADE_START = 0.48
SOURCE_LENS_LOCAL_FADE_END = 0.58
SOURCE_LENS_LOCAL_COLUMN_DIFFERENTIAL_GAIN = 0.08
SOURCE_LENS_LOCAL_BAND_DIFFERENTIAL_GAIN = 0.08
SOURCE_LENS_RIDGE_CENTER = 0.25
SOURCE_LENS_RIDGE_RADIUS = 0.14
SOURCE_LENS_RIDGE_FADE_START = 0.38
SOURCE_LENS_RIDGE_FADE_END = 0.52
BOUNDARY_BAND_PROBE_Y = 0.54
NEAR_GROUND_PROBE_Y = 0.62


def finite_float(raw: Any, default: float = 0.0) -> float:
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return default
    return value if math.isfinite(value) else default


def parse_render_log(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    lens_rows: dict[tuple[str, str], dict[str, str]] = {}
    rigid_rows: dict[tuple[str, str], dict[str, str]] = {}
    local_rows: dict[tuple[str, str], dict[str, str]] = {}
    ridge_line_rows: dict[tuple[str, str], dict[str, str]] = {}
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if LENS_PREFIX in line:
            values = dict(PAIR_PATTERN.findall(line.split(LENS_PREFIX, 1)[1]))
            analysis_time = values.get("analysisTime")
            sample = values.get("sample")
            if analysis_time and sample:
                lens_rows[(analysis_time, sample)] = values
            continue
        if RIGID_PREFIX in line:
            values = dict(PAIR_PATTERN.findall(line.split(RIGID_PREFIX, 1)[1]))
            analysis_time = values.get("analysisTime")
            sample = values.get("sample")
            if analysis_time and sample:
                rigid_rows[(analysis_time, sample)] = values
            continue
        if LOCAL_PREFIX in line:
            values = dict(PAIR_PATTERN.findall(line.split(LOCAL_PREFIX, 1)[1]))
            analysis_time = values.get("analysisTime")
            sample = values.get("sample")
            if analysis_time and sample:
                local_rows[(analysis_time, sample)] = values
            continue
        if RIDGE_LINE_PREFIX in line:
            values = dict(PAIR_PATTERN.findall(line.split(RIDGE_LINE_PREFIX, 1)[1]))
            analysis_time = values.get("analysisTime")
            sample = values.get("sample")
            if analysis_time and sample:
                ridge_line_rows[(analysis_time, sample)] = values
            continue
        if PREFIX not in line:
            continue
        values = dict(PAIR_PATTERN.findall(line.split(PREFIX, 1)[1]))
        if "analysisTime" not in values:
            continue
        rows.append(values)
    for row in rows:
        lens_row = lens_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
        if lens_row:
            row.update(lens_row)
        rigid_row = rigid_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
        if rigid_row:
            row.update(rigid_row)
        local_row = local_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
        if local_row:
            row.update(local_row)
        ridge_line_row = ridge_line_rows.get((row.get("analysisTime", ""), row.get("sample", "")))
        if ridge_line_row:
            row.update(ridge_line_row)
    rows.sort(key=lambda row: finite_float(row.get("analysisTime")))
    first_time = finite_float(rows[0].get("analysisTime")) if rows else 0.0
    for index, row in enumerate(rows):
        row["_renderIndex"] = str(index)
        row["_relativeTime"] = f"{finite_float(row.get('analysisTime')) - first_time:.5f}"
    return rows


def crop_region(
    gray: np.ndarray,
    y0: float,
    y1: float,
    x0: float = 0.0,
    x1: float = 1.0,
) -> np.ndarray:
    height = gray.shape[0]
    width = gray.shape[1]
    top = max(0, min(height - 1, int(round(height * y0))))
    bottom = max(top + 8, min(height, int(round(height * y1))))
    left = max(0, min(width - 1, int(round(width * x0))))
    right = max(left + 8, min(width, int(round(width * x1))))
    return gray[top:bottom, left:right]


def estimate_flow(previous: np.ndarray, current: np.ndarray) -> dict[str, float]:
    points = cv2.goodFeaturesToTrack(
        previous,
        maxCorners=180,
        qualityLevel=0.01,
        minDistance=7,
        blockSize=5,
    )
    if points is None or len(points) < 8:
        return {
            "dx": 0.0,
            "dy": 0.0,
            "roll": 0.0,
            "scale": 1.0,
            "points": 0.0,
            "inlierRatio": 0.0,
        }
    next_points, status, _err = cv2.calcOpticalFlowPyrLK(
        previous,
        current,
        points,
        None,
        winSize=(21, 21),
        maxLevel=3,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
    )
    if next_points is None or status is None:
        return {
            "dx": 0.0,
            "dy": 0.0,
            "roll": 0.0,
            "scale": 1.0,
            "points": 0.0,
            "inlierRatio": 0.0,
        }
    valid = status.reshape(-1) == 1
    src = points.reshape(-1, 2)[valid]
    dst = next_points.reshape(-1, 2)[valid]
    if len(src) < 8:
        return {
            "dx": 0.0,
            "dy": 0.0,
            "roll": 0.0,
            "scale": 1.0,
            "points": float(len(src)),
            "inlierRatio": 0.0,
        }
    matrix, inliers = cv2.estimateAffinePartial2D(
        src,
        dst,
        method=cv2.RANSAC,
        ransacReprojThreshold=2.0,
        maxIters=800,
        confidence=0.98,
    )
    if matrix is None:
        delta = dst - src
        return {
            "dx": float(np.median(delta[:, 0])),
            "dy": float(np.median(delta[:, 1])),
            "roll": 0.0,
            "scale": 1.0,
            "points": float(len(src)),
            "inlierRatio": 0.0,
        }
    inlier_ratio = float(np.mean(inliers.reshape(-1))) if inliers is not None and len(inliers) else 0.0
    a = float(matrix[0, 0])
    b = float(matrix[1, 0])
    scale = math.sqrt((a * a) + (b * b))
    roll = math.degrees(math.atan2(b, a))
    return {
        "dx": float(matrix[0, 2]),
        "dy": float(matrix[1, 2]),
        "roll": roll,
        "scale": scale,
        "points": float(len(src)),
        "inlierRatio": inlier_ratio,
    }


def residual_window(values: list[float], index: int, radius: int) -> float:
    if index <= 0 or index >= len(values):
        return 0.0
    left = max(0, index - radius)
    right = min(len(values), index + radius + 1)
    baseline_indices = list(range(left, max(left, index - 1))) + list(range(min(right, index + 2), right))
    if len(baseline_indices) < 2:
        return 0.0
    xs = np.array(baseline_indices, dtype=np.float64)
    ys = np.array([values[i] for i in baseline_indices], dtype=np.float64)
    slope, intercept = np.polyfit(xs, ys, 1)
    return float(values[index] - ((slope * index) + intercept))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge1 <= edge0:
        return 1.0 if value >= edge1 else 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - (2.0 * t))


def lens_band_gain(row: dict[str, Any]) -> float:
    applied = max(0.0, min(1.0, finite_float(row.get("lensBandWarpApplied"))))
    support = max(0.0, min(1.0, finite_float(row.get("lensBandWarpSupport"))))
    return applied * smoothstep(0.08, 0.55, support)


def lens_band_weight(y: float, center: float, radius: float) -> float:
    normalized = max(0.0, min(1.0, 1.0 - (abs(y - center) / max(radius, 0.0001))))
    return normalized * normalized * (3.0 - (2.0 * normalized))


def lens_band_render_offset_y(row: dict[str, Any], y: float) -> float:
    top_weight = lens_band_weight(y, LENS_BAND_TOP_CENTER, LENS_BAND_TOP_RADIUS)
    ridge_weight = lens_band_weight(y, LENS_BAND_RIDGE_CENTER, LENS_BAND_RIDGE_RADIUS)
    mid_weight = lens_band_weight(y, LENS_BAND_MID_CENTER, LENS_BAND_MID_RADIUS)
    total_weight = top_weight + ridge_weight + mid_weight
    if total_weight <= 0.0001:
        return 0.0
    top_y = render_value(row, "lensBandTopY")
    ridge_y = render_value(row, "lensBandRidgeY")
    mid_y = render_value(row, "lensBandMidY")
    weighted_band_y = (
        (top_y * top_weight)
        + (ridge_y * ridge_weight)
        + (mid_y * mid_weight)
    ) / total_weight
    common_band_y = (top_y + ridge_y + mid_y) / 3.0
    band_y = common_band_y + (
        (weighted_band_y - common_band_y) * LENS_BAND_INTER_BAND_DIFFERENTIAL_GAIN
    )
    far_field_fade = 1.0 - smoothstep(LENS_BAND_FADE_START, LENS_BAND_FADE_END, y)
    return band_y * lens_band_gain(row) * far_field_fade


def lens_band_inter_band_detail_y(row: dict[str, Any], y: float) -> float:
    top_weight = lens_band_weight(y, LENS_BAND_TOP_CENTER, LENS_BAND_TOP_RADIUS)
    ridge_weight = lens_band_weight(y, LENS_BAND_RIDGE_CENTER, LENS_BAND_RIDGE_RADIUS)
    mid_weight = lens_band_weight(y, LENS_BAND_MID_CENTER, LENS_BAND_MID_RADIUS)
    total_weight = top_weight + ridge_weight + mid_weight
    if total_weight <= 0.0001:
        return 0.0
    top_y = render_value(row, "lensBandTopY")
    ridge_y = render_value(row, "lensBandRidgeY")
    mid_y = render_value(row, "lensBandMidY")
    weighted_band_y = ((top_y * top_weight) + (ridge_y * ridge_weight) + (mid_y * mid_weight)) / total_weight
    common_band_y = (top_y + ridge_y + mid_y) / 3.0
    far_field_fade = 1.0 - smoothstep(LENS_BAND_FADE_START, LENS_BAND_FADE_END, y)
    return (weighted_band_y - common_band_y) * lens_band_gain(row) * far_field_fade


def lens_band_core_remaining_differential_y(row: dict[str, Any]) -> float:
    return max(
        (abs(lens_band_inter_band_detail_y(row, y) * LENS_BAND_INTER_BAND_DIFFERENTIAL_GAIN)
         for y in np.linspace(0.02, NEAR_GROUND_PROBE_Y, 25)),
        default=0.0,
    )


def lens_band_core_suppressed_differential_y(row: dict[str, Any]) -> float:
    return max(
        (abs(lens_band_inter_band_detail_y(row, y) * (1.0 - LENS_BAND_INTER_BAND_DIFFERENTIAL_GAIN))
         for y in np.linspace(0.02, NEAR_GROUND_PROBE_Y, 25)),
        default=0.0,
    )


def lens_band_spatial_profile(row: dict[str, Any]) -> list[tuple[float, float]]:
    return [
        (y, lens_band_render_offset_y(row, y))
        for y in np.linspace(0.02, NEAR_GROUND_PROBE_Y, 25)
    ]


def lens_band_core_spatial_gradient(row: dict[str, Any]) -> float:
    profile = lens_band_spatial_profile(row)
    gradients = [
        abs((current_value - previous_value) / max(current_y - previous_y, 0.0001))
        for (previous_y, previous_value), (current_y, current_value) in zip(profile, profile[1:])
    ]
    return max(gradients or [0.0])


def lens_band_core_spatial_curvature(row: dict[str, Any]) -> float:
    profile = lens_band_spatial_profile(row)
    curvatures: list[float] = []
    for previous, current, next_value in zip(profile, profile[1:], profile[2:]):
        y0, value0 = previous
        y1, value1 = current
        y2, value2 = next_value
        step = max(min(y1 - y0, y2 - y1), 0.0001)
        curvatures.append(abs((value2 - (2.0 * value1) + value0) / (step * step)))
    return max(curvatures or [0.0])


def lens_band_core_active_height(row: dict[str, Any]) -> float:
    profile = lens_band_spatial_profile(row)
    magnitudes = [abs(value) for _y, value in profile]
    peak = max(magnitudes or [0.0])
    if peak <= 0.0001:
        return 0.0
    active_rows = [y for y, value in profile if abs(value) >= peak * 0.25]
    if not active_rows:
        return 0.0
    return max(active_rows) - min(active_rows)


def average_keys(row: dict[str, Any], keys: Iterable[str]) -> float:
    values = [render_value(row, key) for key in keys]
    return sum(values) / len(values) if values else 0.0


def source_lens_local_gain(row: dict[str, Any]) -> float:
    applied = max(0.0, min(1.0, finite_float(row.get("sourceLensShakeLocalApplied"))))
    support = max(0.0, min(1.0, finite_float(row.get("sourceLensShakeLocalSupport"))))
    return applied * smoothstep(0.08, 0.55, support)


def source_lens_local_band_common_y(row: dict[str, Any], band: str) -> float:
    return average_keys(
        row,
        (
            f"sourceLensShakeLocal{band}LeftY",
            f"sourceLensShakeLocal{band}CenterY",
            f"sourceLensShakeLocal{band}RightY",
        ),
    )


def source_lens_local_regularized_band_y(row: dict[str, Any], band: str, column: str) -> float:
    raw = render_value(row, f"sourceLensShakeLocal{band}{column}Y")
    common = source_lens_local_band_common_y(row, band)
    return common + ((raw - common) * SOURCE_LENS_LOCAL_COLUMN_DIFFERENTIAL_GAIN)


def source_lens_local_band_weighted_y(
    row: dict[str, Any],
    y: float,
    column: str | None = None,
) -> tuple[float, float]:
    top_weight = lens_band_weight(y, SOURCE_LENS_LOCAL_TOP_CENTER, SOURCE_LENS_LOCAL_TOP_RADIUS)
    ridge_weight = lens_band_weight(y, SOURCE_LENS_LOCAL_RIDGE_CENTER, SOURCE_LENS_LOCAL_RIDGE_RADIUS)
    mid_weight = lens_band_weight(y, SOURCE_LENS_LOCAL_MID_CENTER, SOURCE_LENS_LOCAL_MID_RADIUS)
    total_weight = top_weight + ridge_weight + mid_weight
    if total_weight <= 0.0001:
        return 0.0, 0.0
    if column:
        top_y = source_lens_local_regularized_band_y(row, "Top", column)
        ridge_y = source_lens_local_regularized_band_y(row, "Ridge", column)
        mid_y = source_lens_local_regularized_band_y(row, "Mid", column)
    else:
        top_y = source_lens_local_band_common_y(row, "Top")
        ridge_y = source_lens_local_band_common_y(row, "Ridge")
        mid_y = source_lens_local_band_common_y(row, "Mid")
    weighted_y = ((top_y * top_weight) + (ridge_y * ridge_weight) + (mid_y * mid_weight)) / total_weight
    common_y = (top_y + ridge_y + mid_y) / 3.0
    band_y = common_y + ((weighted_y - common_y) * SOURCE_LENS_LOCAL_BAND_DIFFERENTIAL_GAIN)
    return band_y, weighted_y - common_y


def source_lens_local_offset_y(row: dict[str, Any], y: float) -> float:
    far_field_fade = 1.0 - smoothstep(SOURCE_LENS_LOCAL_FADE_START, SOURCE_LENS_LOCAL_FADE_END, y)
    band_y, _detail_y = source_lens_local_band_weighted_y(row, y)
    return band_y * source_lens_local_gain(row) * far_field_fade


def source_lens_local_max_abs_offset_y(row: dict[str, Any], y: float) -> float:
    far_field_fade = 1.0 - smoothstep(SOURCE_LENS_LOCAL_FADE_START, SOURCE_LENS_LOCAL_FADE_END, y)
    gain = source_lens_local_gain(row) * far_field_fade
    values = []
    for column in ("Left", "Center", "Right"):
        band_y, _detail_y = source_lens_local_band_weighted_y(row, y, column)
        values.append(band_y * gain)
    return max((abs(value) for value in values), default=0.0)


def source_lens_local_column_suppressed_y(row: dict[str, Any]) -> float:
    values = []
    gain = source_lens_local_gain(row)
    for band, center in (("Top", SOURCE_LENS_LOCAL_TOP_CENTER), ("Ridge", SOURCE_LENS_LOCAL_RIDGE_CENTER), ("Mid", SOURCE_LENS_LOCAL_MID_CENTER)):
        far_field_fade = 1.0 - smoothstep(SOURCE_LENS_LOCAL_FADE_START, SOURCE_LENS_LOCAL_FADE_END, center)
        common = source_lens_local_band_common_y(row, band)
        for column in ("Left", "Center", "Right"):
            raw = render_value(row, f"sourceLensShakeLocal{band}{column}Y")
            values.append(abs((raw - common) * (1.0 - SOURCE_LENS_LOCAL_COLUMN_DIFFERENTIAL_GAIN) * gain * far_field_fade))
    return max(values or [0.0])


def source_lens_local_band_suppressed_y(row: dict[str, Any]) -> float:
    values = []
    gain = source_lens_local_gain(row)
    for y in np.linspace(0.02, NEAR_GROUND_PROBE_Y, 25):
        far_field_fade = 1.0 - smoothstep(SOURCE_LENS_LOCAL_FADE_START, SOURCE_LENS_LOCAL_FADE_END, y)
        for column in (None, "Left", "Center", "Right"):
            _band_y, detail_y = source_lens_local_band_weighted_y(row, y, column)
            values.append(abs(detail_y * (1.0 - SOURCE_LENS_LOCAL_BAND_DIFFERENTIAL_GAIN) * gain * far_field_fade))
    return max(values or [0.0])


def source_lens_ridge_gain(row: dict[str, Any]) -> float:
    applied = max(0.0, min(1.0, finite_float(row.get("sourceLensShakeRidgeApplied"))))
    support = max(0.0, min(1.0, finite_float(row.get("sourceLensShakeRidgeSupport"))))
    return applied * smoothstep(0.08, 0.55, support)


def source_lens_ridge_offset_y(row: dict[str, Any], y: float) -> float:
    weight = lens_band_weight(y, SOURCE_LENS_RIDGE_CENTER, SOURCE_LENS_RIDGE_RADIUS)
    far_field_fade = 1.0 - smoothstep(SOURCE_LENS_RIDGE_FADE_START, SOURCE_LENS_RIDGE_FADE_END, y)
    return render_value(row, "sourceLensShakeRidgeY") * source_lens_ridge_gain(row) * weight * far_field_fade


def render_value(row: dict[str, Any], key: str) -> float:
    return finite_float(row.get(key))


def derivative_at(rows: list[dict[str, Any]], index: int, key: str, order: int) -> float:
    if index < order or index >= len(rows):
        return 0.0
    if order == 1:
        return render_value(rows[index], key) - render_value(rows[index - 1], key)
    if order == 2:
        return (
            render_value(rows[index], key)
            - (2.0 * render_value(rows[index - 1], key))
            + render_value(rows[index - 2], key)
        )
    if order == 3:
        return (
            render_value(rows[index], key)
            - (3.0 * render_value(rows[index - 1], key))
            + (3.0 * render_value(rows[index - 2], key))
            - render_value(rows[index - 3], key)
        )
    return 0.0


def derived_derivative_at(
    rows: list[dict[str, Any]],
    index: int,
    value_fn,
    order: int,
) -> float:
    if index < order or index >= len(rows):
        return 0.0
    values = [value_fn(rows[index - offset]) for offset in range(order + 1)]
    if order == 1:
        return values[0] - values[1]
    if order == 2:
        return values[0] - (2.0 * values[1]) + values[2]
    if order == 3:
        return values[0] - (3.0 * values[1]) + (3.0 * values[2]) - values[3]
    return 0.0


def inter_band_delta_y(row: dict[str, Any]) -> float:
    top = render_value(row, "lensBandTopY")
    ridge = render_value(row, "lensBandRidgeY")
    mid = render_value(row, "lensBandMidY")
    return max(abs(top - ridge), abs(ridge - mid), abs(top - mid))


def inter_band_scale_like(row: dict[str, Any]) -> float:
    top = render_value(row, "lensBandTopY")
    ridge = render_value(row, "lensBandRidgeY")
    mid = render_value(row, "lensBandMidY")
    top_ridge = abs(top - ridge) / abs(LENS_BAND_RIDGE_CENTER - LENS_BAND_TOP_CENTER)
    ridge_mid = abs(ridge - mid) / abs(LENS_BAND_MID_CENTER - LENS_BAND_RIDGE_CENTER)
    top_mid = abs(top - mid) / abs(LENS_BAND_MID_CENTER - LENS_BAND_TOP_CENTER)
    return max(top_ridge, ridge_mid, top_mid)


def model_switch_count(rows: list[dict[str, Any]], index: int, radius: int = 5) -> int:
    left = max(0, index - radius)
    right = min(len(rows), index + radius + 1)
    models = [str(rows[i].get("lensBandCorrectionModel", "")) for i in range(left, right)]
    models = [model for model in models if model]
    if len(models) < 2:
        return 0
    return sum(1 for previous, current in zip(models, models[1:]) if previous != current)


def boundary_pulse_score(rows: list[dict[str, Any]], index: int) -> float:
    if not rows or index < 0 or index >= len(rows):
        return 0.0
    inter_band_velocity = abs(derived_derivative_at(rows, index, inter_band_delta_y, 1))
    inter_band_scale_velocity = abs(derived_derivative_at(rows, index, inter_band_scale_like, 1))
    ridge_y_jerk = abs(derivative_at(rows, index, "lensBandRidgeY", 3))
    ridge_row_jerk = abs(derivative_at(rows, index, "lensBandRidgeRowPhaseY", 3))
    gain_derivative = abs(derived_derivative_at(rows, index, lens_band_gain, 1))
    spatial_gradient_velocity = abs(derived_derivative_at(rows, index, lens_band_core_spatial_gradient, 1))
    switch_penalty = float(model_switch_count(rows, index)) * 0.18
    return max(
        inter_band_velocity,
        inter_band_scale_velocity,
        ridge_y_jerk,
        ridge_row_jerk,
        gain_derivative * 2.0,
        spatial_gradient_velocity,
        switch_penalty,
    )


def percentile_abs(rows: list[dict[str, Any]], key: str, percentile: float) -> float:
    values = [abs(finite_float(row.get(key))) for row in rows]
    return float(np.percentile(values, percentile)) if values else 0.0


def bool_value(raw: Any) -> bool:
    return str(raw).strip().lower() in {"1", "true", "yes", "y"}


def read_csv_by_frame(path: Path) -> dict[int, dict[str, str]]:
    if not path.exists():
        return {}
    rows: dict[int, dict[str, str]] = {}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            try:
                frame = int(float(row.get("frame", "")))
            except (TypeError, ValueError):
                continue
            rows[frame] = row
    return rows


def longest_true_run(values: Iterable[bool]) -> int:
    longest = 0
    current = 0
    for value in values:
        if value:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def runtime_decision(row: dict[str, Any]) -> str:
    reason = str(row.get("lensShakeReason", ""))
    correction_model = str(row.get("lensBandCorrectionModel", ""))
    if reason == "applied":
        return "globalApplied"
    if reason == "rollingRowWarp":
        return "bandApplied" if correction_model else "bandReasonNoModel"
    if reason == "rollingShutterCandidate":
        return "detectedRollingCandidateNoOp"
    if reason:
        return reason
    return "noRuntimeSignal"


def failure_class(row: dict[str, Any], window_frames: int) -> str:
    if bool_value(row.get("ptsCadenceAffectedFrame")) or bool_value(row.get("captureHoldAffectedFrame")):
        return "cadenceAffected"
    if abs(finite_float(row.get("scalePulseDerivativePercent"))) >= 0.25:
        return "scalePulseDerivative"
    if (
        abs(finite_float(row.get("sourceLensShakeRidgeLineRawY"))) >= 0.35
        and finite_float(row.get("sourceLensShakeRidgeLineSupport")) <= 0.05
        and finite_float(row.get("sourceLensShakeRidgeLineApplied")) <= 0.0
    ):
        return "ridgeLineDetectedSupportNoOp"
    decision = runtime_decision(row)
    residual_model = str(row.get("lensBandResidualModel", ""))
    residual_strength = abs(finite_float(row.get(f"lensBandRollingShutterScoreHF{window_frames}")))
    if decision == "detectedRollingCandidateNoOp" and residual_strength >= 0.35:
        return "rollingCandidateDetectedNoBandCorrection"
    if decision == "bandApplied" and residual_model != "noSignal" and residual_strength >= 0.35:
        return "bandCorrectionResidual"
    if residual_model != "noSignal" and residual_strength >= 0.35:
        return "detectedBandSignalNoRuntimeCorrection"
    return "noDominantFailureSignal"


def dominant_key(values: dict[str, float]) -> tuple[str, float]:
    if not values:
        return "", 0.0
    key = max(values, key=lambda item: values[item])
    return key, values[key]


def classify_residual_model(row: dict[str, Any], window_frames: int) -> tuple[str, str, str]:
    component_values = {
        label: abs(finite_float(row.get(f"{component}HF{window_frames}")))
        for label, component in MODEL_COMPONENTS.items()
    }
    component, component_value = dominant_key(component_values)
    band_values: dict[str, float] = {}
    for band_name in FAR_FIELD_BANDS:
        band_values[f"{band_name}.row"] = abs(
            finite_float(row.get(f"{band_name}.rowPhaseMagnitudeHF{window_frames}"))
        )
        band_values[f"{band_name}.column"] = abs(
            finite_float(row.get(f"{band_name}.colPhaseMagnitudeHF{window_frames}"))
        )
        band_values[f"{band_name}.roll"] = abs(
            finite_float(row.get(f"{band_name}.localRollSpreadHF{window_frames}"))
        )
    band_component, band_value = dominant_key(band_values)
    if component_value < 0.35 and band_value < 0.35:
        return "noSignal", component, band_component
    if component == "row":
        return "rowPhaseWarp", component, band_component
    if component == "column":
        return "columnPhaseWarp", component, band_component
    if component == "interBand":
        return "regionClusterWarp", component, band_component
    if component == "roll":
        return "localRollWarp", component, band_component
    return "unknown", component, band_component


def correction_model_covers(residual_model: str, correction_model: str) -> bool:
    required = {
        "rowPhaseWarp": {"rowPhase", "sourceRidge", "sourceRidgeLine", "sourceLocal"},
        "columnPhaseWarp": {"columnPhase", "sourceLocal"},
        "regionClusterWarp": {"regionCluster", "sourceRidge", "sourceRidgeLine", "sourceLocal"},
        "localRollWarp": {"localRoll"},
    }.get(residual_model)
    if required is None:
        return residual_model == "noSignal"
    present = {
        item.strip() for item in str(correction_model).split(",") if item.strip()
    }
    return bool(required.intersection(present))


def runtime_model_applied(row: dict[str, Any], residual_model: str) -> bool:
    if finite_float(row.get("lensBandWarpApplied")) <= 0.5:
        return False
    if not correction_model_covers(residual_model, str(row.get("lensBandCorrectionModel", ""))):
        return False

    def max_vector_magnitude(columns: tuple[tuple[str, str], ...]) -> float:
        return max(
            [
                math.hypot(finite_float(row.get(x_column)), finite_float(row.get(y_column)))
                for x_column, y_column in columns
            ] or [0.0]
        )

    local_magnitude = max_vector_magnitude(
        (
            ("sourceLensShakeLocalTopLeftX", "sourceLensShakeLocalTopLeftY"),
            ("sourceLensShakeLocalTopCenterX", "sourceLensShakeLocalTopCenterY"),
            ("sourceLensShakeLocalTopRightX", "sourceLensShakeLocalTopRightY"),
            ("sourceLensShakeLocalRidgeLeftX", "sourceLensShakeLocalRidgeLeftY"),
            ("sourceLensShakeLocalRidgeCenterX", "sourceLensShakeLocalRidgeCenterY"),
            ("sourceLensShakeLocalRidgeRightX", "sourceLensShakeLocalRidgeRightY"),
            ("sourceLensShakeLocalMidLeftX", "sourceLensShakeLocalMidLeftY"),
            ("sourceLensShakeLocalMidCenterX", "sourceLensShakeLocalMidCenterY"),
            ("sourceLensShakeLocalMidRightX", "sourceLensShakeLocalMidRightY"),
        )
    )

    if residual_model == "rowPhaseWarp":
        return max(
            max_vector_magnitude(
                (
                    ("lensBandTopRowPhaseX", "lensBandTopRowPhaseY"),
                    ("lensBandRidgeRowPhaseX", "lensBandRidgeRowPhaseY"),
                    ("lensBandMidRowPhaseX", "lensBandMidRowPhaseY"),
                )
            ),
            abs(finite_float(row.get("sourceLensShakeRidgeY"))),
            local_magnitude,
        ) >= 0.02
    if residual_model == "columnPhaseWarp":
        return max(
            max_vector_magnitude(
                (
                    ("lensBandTopColumnX", "lensBandTopColumnY"),
                    ("lensBandRidgeColumnX", "lensBandRidgeColumnY"),
                    ("lensBandMidColumnX", "lensBandMidColumnY"),
                )
            ),
            local_magnitude,
        ) >= 0.02
    if residual_model == "regionClusterWarp":
        return max(abs(finite_float(row.get("sourceLensShakeRidgeY"))), local_magnitude) >= 0.02
    if residual_model == "localRollWarp":
        return max(
            abs(finite_float(row.get("lensBandTopLocalRoll"))),
            abs(finite_float(row.get("lensBandRidgeLocalRoll"))),
            abs(finite_float(row.get("lensBandMidLocalRoll"))),
        ) >= 0.00001
    return residual_model == "noSignal"


def add_region_phase_metrics(row: dict[str, float], band_name: str) -> None:
    left_dx = finite_float(row.get(f"{band_name}.left.dx"))
    right_dx = finite_float(row.get(f"{band_name}.right.dx"))
    left_dy = finite_float(row.get(f"{band_name}.left.dy"))
    right_dy = finite_float(row.get(f"{band_name}.right.dy"))
    upper_dx = finite_float(row.get(f"{band_name}.upper.dx"))
    lower_dx = finite_float(row.get(f"{band_name}.lower.dx"))
    upper_dy = finite_float(row.get(f"{band_name}.upper.dy"))
    lower_dy = finite_float(row.get(f"{band_name}.lower.dy"))
    row_dx = upper_dx - lower_dx
    row_dy = upper_dy - lower_dy
    col_dx = left_dx - right_dx
    col_dy = left_dy - right_dy
    row["%s.rowPhaseDx" % band_name] = row_dx
    row["%s.rowPhaseDy" % band_name] = row_dy
    row["%s.rowPhaseMagnitude" % band_name] = math.hypot(row_dx, row_dy)
    row["%s.colPhaseDx" % band_name] = col_dx
    row["%s.colPhaseDy" % band_name] = col_dy
    row["%s.colPhaseMagnitude" % band_name] = math.hypot(col_dx, col_dy)
    rolls = [finite_float(row.get(f"{band_name}.{region}.roll")) for region in REGIONS]
    row["%s.localRollSpread" % band_name] = max(rolls) - min(rolls) if rolls else 0.0
    center_points = finite_float(row.get(f"{band_name}.center.points"))
    upper_points = finite_float(row.get(f"{band_name}.upper.points"))
    lower_points = finite_float(row.get(f"{band_name}.lower.points"))
    row["%s.localSupport" % band_name] = min(center_points, max(upper_points, lower_points))


def analyze_video(video_path: Path, window_frames: int) -> tuple[list[dict[str, float]], dict[str, Any]]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise SystemExit(f"could not open video: {video_path}")
    fps = finite_float(cap.get(cv2.CAP_PROP_FPS), 60.0)
    rows: list[dict[str, float]] = []
    previous_gray: np.ndarray | None = None
    frame_index = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        row: dict[str, float] = {"frame": float(frame_index), "time": float(frame_index / fps)}
        if previous_gray is not None:
            for name, bounds in BANDS.items():
                previous_band = crop_region(previous_gray, *bounds)
                current_band = crop_region(gray, *bounds)
                metrics = estimate_flow(previous_band, current_band)
                for key, value in metrics.items():
                    row[f"{name}.{key}"] = value
                y0, y1 = bounds
                for region_name, (x0, x1, local_y0, local_y1) in REGIONS.items():
                    region_previous = crop_region(
                        previous_gray,
                        y0 + ((y1 - y0) * local_y0),
                        y0 + ((y1 - y0) * local_y1),
                        x0,
                        x1,
                    )
                    region_current = crop_region(
                        gray,
                        y0 + ((y1 - y0) * local_y0),
                        y0 + ((y1 - y0) * local_y1),
                        x0,
                        x1,
                    )
                    region_metrics = estimate_flow(region_previous, region_current)
                    for key, value in region_metrics.items():
                        row[f"{name}.{region_name}.{key}"] = value
                add_region_phase_metrics(row, name)
            far_row_phase = [
                finite_float(row.get(f"{band_name}.rowPhaseMagnitude"))
                for band_name in FAR_FIELD_BANDS
            ]
            far_col_phase = [
                finite_float(row.get(f"{band_name}.colPhaseMagnitude"))
                for band_name in FAR_FIELD_BANDS
            ]
            far_roll_spread = [
                abs(finite_float(row.get(f"{band_name}.localRollSpread")))
                for band_name in FAR_FIELD_BANDS
            ]
            cloud_ridge_delta = math.hypot(
                finite_float(row.get("cloud_top.dx")) - finite_float(row.get("ridge_horizon.dx")),
                finite_float(row.get("cloud_top.dy")) - finite_float(row.get("ridge_horizon.dy")),
            )
            row["lensBandRollingShutterRowScore"] = max(far_row_phase)
            row["lensBandRollingShutterColScore"] = max(far_col_phase)
            row["lensBandRollingShutterRollScore"] = max(far_roll_spread)
            row["lensBandRollingShutterInterBandScore"] = cloud_ridge_delta
            row["lensBandRollingShutterScore"] = max(
                far_row_phase + far_col_phase + far_roll_spread + [cloud_ridge_delta]
            )
        rows.append(row)
        previous_gray = gray
    cap.release()

    radius = max(2, window_frames // 2)
    for band_name in BANDS:
        for axis in ("dx", "dy"):
            key = f"{band_name}.{axis}"
            values = [finite_float(row.get(key)) for row in rows]
            for index, row in enumerate(rows):
                row[f"{key}HF{window_frames}"] = residual_window(values, index, radius)
        for key in ("rowPhaseMagnitude", "colPhaseMagnitude", "localRollSpread"):
            full_key = f"{band_name}.{key}"
            values = [finite_float(row.get(full_key)) for row in rows]
            for index, row in enumerate(rows):
                row[f"{full_key}HF{window_frames}"] = residual_window(values, index, radius)
    for key in (
        "lensBandRollingShutterScore",
        "lensBandRollingShutterRowScore",
        "lensBandRollingShutterColScore",
        "lensBandRollingShutterRollScore",
        "lensBandRollingShutterInterBandScore",
    ):
        rolling_values = [finite_float(row.get(key)) for row in rows]
        for index, row in enumerate(rows):
            row[f"{key}HF{window_frames}"] = residual_window(rolling_values, index, radius)

    focus_start = 4.25
    focus_end = 6.75
    focus_rows = [row for row in rows if focus_start <= row["time"] <= focus_end]
    summary: dict[str, Any] = {
        "video": str(video_path),
        "frameCount": len(rows),
        "fps": fps,
        "focusRows": len(focus_rows),
    }
    for band_name in BANDS:
        band_summary: dict[str, float] = {}
        for axis in ("dx", "dy"):
            values = [abs(finite_float(row.get(f"{band_name}.{axis}HF{window_frames}"))) for row in focus_rows]
            band_summary[f"{axis}HF{window_frames}P95"] = float(np.percentile(values, 95)) if values else 0.0
            band_summary[f"{axis}HF{window_frames}Max"] = max(values) if values else 0.0
        for key in ("rowPhaseMagnitude", "colPhaseMagnitude", "localRollSpread"):
            values = [abs(finite_float(row.get(f"{band_name}.{key}HF{window_frames}"))) for row in focus_rows]
            band_summary[f"{key}HF{window_frames}P95"] = float(np.percentile(values, 95)) if values else 0.0
            band_summary[f"{key}HF{window_frames}Max"] = max(values) if values else 0.0
        summary[band_name] = band_summary
    rolling_focus = [abs(finite_float(row.get(f"lensBandRollingShutterScoreHF{window_frames}"))) for row in focus_rows]
    summary[f"lensBandRollingShutterScoreHF{window_frames}P95"] = (
        float(np.percentile(rolling_focus, 95)) if rolling_focus else 0.0
    )
    summary[f"lensBandRollingShutterScoreHF{window_frames}Max"] = max(rolling_focus) if rolling_focus else 0.0
    for key in (
        "lensBandRollingShutterRowScore",
        "lensBandRollingShutterColScore",
        "lensBandRollingShutterRollScore",
        "lensBandRollingShutterInterBandScore",
    ):
        values = [abs(finite_float(row.get(f"{key}HF{window_frames}"))) for row in focus_rows]
        summary[f"{key}HF{window_frames}P95"] = float(np.percentile(values, 95)) if values else 0.0
        summary[f"{key}HF{window_frames}Max"] = max(values) if values else 0.0
    if focus_rows:
        cloud = [finite_float(row.get(f"cloud_top.dyHF{window_frames}")) for row in focus_rows]
        ridge = [finite_float(row.get(f"ridge_horizon.dyHF{window_frames}")) for row in focus_rows]
        summary["cloudMinusRidgeDyP95"] = float(np.percentile([abs(a - b) for a, b in zip(cloud, ridge)], 95))
    return rows, summary


def nearest_render_row(render_rows: list[dict[str, str]], video_time: float) -> dict[str, str]:
    if not render_rows:
        return {}
    return min(render_rows, key=lambda row: abs(finite_float(row.get("_relativeTime")) - video_time))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--render-log", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--window-frames", type=int, default=10)
    parser.add_argument(
        "--quality-dir",
        type=Path,
        help="Optional stabilizer_video_quality.py output directory with scale_stats.csv/ridge_stats.csv.",
    )
    parser.add_argument("--require-band-warp", action="store_true")
    parser.add_argument("--forbid-global-lens", action="store_true")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    render_rows = parse_render_log(args.render_log)
    if not render_rows:
        raise SystemExit(f"lens band diagnostics found no render component rows: {args.render_log}")
    quality_dir = args.quality_dir
    scale_rows = read_csv_by_frame(quality_dir / "scale_stats.csv") if quality_dir else {}
    ridge_rows = read_csv_by_frame(quality_dir / "ridge_stats.csv") if quality_dir else {}
    video_rows, summary = analyze_video(args.video, args.window_frames)
    summary["renderLog"] = str(args.render_log)
    summary["renderRows"] = len(render_rows)
    summary["qualityDir"] = str(quality_dir) if quality_dir else ""
    summary["scaleStatsRows"] = len(scale_rows)
    summary["ridgeStatsRows"] = len(ridge_rows)
    summary["lensReasonCounts"] = dict(Counter(row.get("lensShakeReason", "") for row in render_rows if row.get("lensShakeReason")))
    summary["lensBandWarpAppliedRows"] = sum(
        1 for row in render_rows if finite_float(row.get("lensBandWarpApplied")) > 0.5
    )

    runtime_columns = [
        "analysisTime",
        "sample",
        "lensShakeReason",
        "lensShakeAxis",
        "lensShakeRollingShutterCandidate",
        "lensShakeScore",
        "lensShakeSupport",
        "lensShakeYaw",
        "lensShakePitch",
        "lensShakeShearX",
        "lensShakeShearY",
        "lensShakePerspectiveX",
        "lensShakePerspectiveY",
        "lensBandCorrectionModel",
        "lensBandTopX",
        "lensBandTopY",
        "lensBandRidgeX",
        "lensBandRidgeY",
        "lensBandMidX",
        "lensBandMidY",
        "lensBandRawTopX",
        "lensBandRawTopY",
        "lensBandRawRidgeX",
        "lensBandRawRidgeY",
        "lensBandRawMidX",
        "lensBandRawMidY",
        "lensBandPulseDeltaTopX",
        "lensBandPulseDeltaTopY",
        "lensBandPulseDeltaRidgeX",
        "lensBandPulseDeltaRidgeY",
        "lensBandPulseDeltaMidX",
        "lensBandPulseDeltaMidY",
        "lensBandPulseWindowFrames",
        "lensBandTopColumnX",
        "lensBandTopColumnY",
        "lensBandRidgeColumnX",
        "lensBandRidgeColumnY",
        "lensBandMidColumnX",
        "lensBandMidColumnY",
        "lensBandTopRowPhaseX",
        "lensBandTopRowPhaseY",
        "lensBandRidgeRowPhaseX",
        "lensBandRidgeRowPhaseY",
        "lensBandMidRowPhaseX",
        "lensBandMidRowPhaseY",
        "lensBandTopLocalRoll",
        "lensBandRidgeLocalRoll",
        "lensBandMidLocalRoll",
        "lensBandWarpSupport",
        "lensBandWarpApplied",
        "lensBandRollingShutterScore",
        "lensFarFieldRigidX",
        "lensFarFieldRigidY",
        "lensFarFieldRigidResidualX",
        "lensFarFieldRigidResidualY",
        "lensFarFieldRigidSupport",
        "lensFarFieldRigidApplied",
        "lensFarFieldRigidShapeConsistency",
        "lensFarFieldRigidForwardBackwardConsistency",
        "lensFarFieldRigidLocalWarpSuppressed",
        "sourceLensShakeRidgeY",
        "sourceLensShakeRidgeSupport",
        "sourceLensShakeRidgeApplied",
        "sourceLensShakeRidgeLineRawY",
        "sourceLensShakeRidgeLineY",
        "sourceLensShakeRidgeLineSupport",
        "sourceLensShakeRidgeLineBandSupported",
        "sourceLensShakeRidgeLineApplied",
        "sourceLensShakeRidgeCombinedY",
        "sourceLensShakeLocalSupport",
        "sourceLensShakeLocalApplied",
        "sourceLensShakeLocalTopLeftX",
        "sourceLensShakeLocalTopLeftY",
        "sourceLensShakeLocalTopCenterX",
        "sourceLensShakeLocalTopCenterY",
        "sourceLensShakeLocalTopRightX",
        "sourceLensShakeLocalTopRightY",
        "sourceLensShakeLocalRidgeLeftX",
        "sourceLensShakeLocalRidgeLeftY",
        "sourceLensShakeLocalRidgeCenterX",
        "sourceLensShakeLocalRidgeCenterY",
        "sourceLensShakeLocalRidgeRightX",
        "sourceLensShakeLocalRidgeRightY",
        "sourceLensShakeLocalMidLeftX",
        "sourceLensShakeLocalMidLeftY",
        "sourceLensShakeLocalMidCenterX",
        "sourceLensShakeLocalMidCenterY",
        "sourceLensShakeLocalMidRightX",
        "sourceLensShakeLocalMidRightY",
    ]
    band_columns: list[str] = []
    for band_name in BANDS:
        band_columns.extend(
            [
                f"{band_name}.dx",
                f"{band_name}.dy",
                f"{band_name}.roll",
                f"{band_name}.scale",
                f"{band_name}.points",
                f"{band_name}.inlierRatio",
                f"{band_name}.dxHF{args.window_frames}",
                f"{band_name}.dyHF{args.window_frames}",
                f"{band_name}.rowPhaseDx",
                f"{band_name}.rowPhaseDy",
                f"{band_name}.rowPhaseMagnitude",
                f"{band_name}.rowPhaseMagnitudeHF{args.window_frames}",
                f"{band_name}.colPhaseDx",
                f"{band_name}.colPhaseDy",
                f"{band_name}.colPhaseMagnitude",
                f"{band_name}.colPhaseMagnitudeHF{args.window_frames}",
                f"{band_name}.localRollSpread",
                f"{band_name}.localRollSpreadHF{args.window_frames}",
                f"{band_name}.localSupport",
            ]
        )
        for region_name in REGIONS:
            band_columns.extend(
                [
                    f"{band_name}.{region_name}.dx",
                    f"{band_name}.{region_name}.dy",
                    f"{band_name}.{region_name}.roll",
                    f"{band_name}.{region_name}.scale",
                    f"{band_name}.{region_name}.points",
                    f"{band_name}.{region_name}.inlierRatio",
                ]
            )
    derived_columns = [
        "runtimeDecision",
        "failureClass",
        "scaleResidualPercent",
        "scalePulseResidualPercent",
        "scalePulseDerivativePercent",
        "scaleQualityOk",
        "scalePulseExcludedForPtsCadence",
        "ptsCadenceAffectedFrame",
        "captureHoldAffectedFrame",
        "cadenceHoldFrame",
        "ptsIntervalIrregularFrame",
        "ridgeLineOk",
        "ridgeLineReason",
        "ridgeLineDy",
        "ridgeLineDyMinusAffineDy",
        "ridgeReferenceTrackingOk",
        "ridgeMinusReferenceDx",
        "ridgeMinusReferenceDy",
        "lensBandSupport",
        "lensBandRollingShutterScore",
        "lensBandRollingShutterRowScore",
        "lensBandRollingShutterColScore",
        "lensBandRollingShutterRollScore",
        "lensBandRollingShutterInterBandScore",
        f"lensBandRollingShutterScoreHF{args.window_frames}",
        f"lensBandRollingShutterRowScoreHF{args.window_frames}",
        f"lensBandRollingShutterColScoreHF{args.window_frames}",
        f"lensBandRollingShutterRollScoreHF{args.window_frames}",
        f"lensBandRollingShutterInterBandScoreHF{args.window_frames}",
        "lensBandTopXVelocity",
        "lensBandTopYVelocity",
        "lensBandTopXAcceleration",
        "lensBandTopYAcceleration",
        "lensBandTopXJerk",
        "lensBandTopYJerk",
        "lensBandRidgeXVelocity",
        "lensBandRidgeYVelocity",
        "lensBandRidgeXAcceleration",
        "lensBandRidgeYAcceleration",
        "lensBandRidgeXJerk",
        "lensBandRidgeYJerk",
        "lensBandMidXVelocity",
        "lensBandMidYVelocity",
        "lensBandMidXAcceleration",
        "lensBandMidYAcceleration",
        "lensBandMidXJerk",
        "lensBandMidYJerk",
        "interBandDeltaY",
        "interBandDeltaScaleLike",
        "boundaryPulseScore",
        "modelSwitchCount",
        "bandWarpGain",
        "bandWarpGainDerivative",
        "bandWarpCoreSpatialGradient",
        "bandWarpCoreSpatialCurvature",
        "bandWarpCoreActiveHeight",
        "bandWarpCoreSpatialGradientDerivative",
        "bandWarpCoreRemainingDifferentialY",
        "bandWarpCoreSuppressedDifferentialY",
        "bandWarpCoreBoundaryLeak",
        "bandWarpCoreNearGroundLeak",
        "sourceLensLocalColumnSuppressedY",
        "sourceLensLocalBandSuppressedY",
        "sourceLensLocalBoundaryLeak",
        "sourceLensLocalNearGroundLeak",
        "sourceLensRidgeBoundaryLeak",
        "sourceLensRidgeNearGroundLeak",
        "lensBandResidualModel",
        "lensBandResidualDominantComponent",
        "lensBandResidualDominantBand",
    ]
    csv_path = args.output_dir / "lens_band_source_joined.csv"
    joined_rows: list[dict[str, Any]] = []
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = (
            ["frame", "time", "renderRow", "renderRelativeTime", "renderTimeError"]
            + runtime_columns
            + derived_columns
            + band_columns
        )
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for index, video_row in enumerate(video_rows):
            frame = int(video_row["frame"])
            video_time = finite_float(video_row.get("time"))
            render_row = nearest_render_row(render_rows, video_time)
            render_relative_time = finite_float(render_row.get("_relativeTime"), math.nan)
            scale_row = scale_rows.get(frame, {})
            ridge_row = ridge_rows.get(frame, {})
            scale_residual = finite_float(scale_row.get("scaleResidualPercent"), math.nan)
            scale_pulse_residual = finite_float(scale_row.get("scalePulseResidualPercent"), math.nan)
            scale_derivative = finite_float(scale_row.get("scalePulseDerivativePercentPerFrame"), math.nan)
            row: dict[str, Any] = {
                "frame": frame,
                "time": f"{video_row['time']:.5f}",
                "renderRow": render_row.get("_renderIndex", ""),
                "renderRelativeTime": f"{render_relative_time:.5f}" if math.isfinite(render_relative_time) else "",
                "renderTimeError": f"{render_relative_time - video_time:.5f}" if math.isfinite(render_relative_time) else "",
            }
            for column in runtime_columns:
                row[column] = render_row.get(column, "")
            row["runtimeDecision"] = runtime_decision(row)
            row["scaleResidualPercent"] = (
                f"{scale_residual:.6f}" if math.isfinite(scale_residual) else ""
            )
            row["scalePulseResidualPercent"] = (
                f"{scale_pulse_residual:.6f}" if math.isfinite(scale_pulse_residual) else ""
            )
            row["scalePulseDerivativePercent"] = (
                f"{scale_derivative:.6f}" if math.isfinite(scale_derivative) else ""
            )
            for column in (
                "scaleQualityOk",
                "scalePulseExcludedForPtsCadence",
                "ptsCadenceAffectedFrame",
                "captureHoldAffectedFrame",
                "cadenceHoldFrame",
                "ptsIntervalIrregularFrame",
            ):
                row[column] = scale_row.get(column, "")
            for column in (
                "ridgeLineOk",
                "ridgeLineReason",
                "ridgeLineDy",
                "ridgeLineDyMinusAffineDy",
                "ridgeReferenceTrackingOk",
                "ridgeMinusReferenceDx",
                "ridgeMinusReferenceDy",
            ):
                row[column] = ridge_row.get(column, "")
            row["lensBandSupport"] = render_row.get("lensBandWarpSupport", "")
            for column in derived_columns:
                if column in {
                    "runtimeDecision",
                    "scaleResidualPercent",
                    "scalePulseResidualPercent",
                    "scalePulseDerivativePercent",
                    "scaleQualityOk",
                    "scalePulseExcludedForPtsCadence",
                    "ptsCadenceAffectedFrame",
                    "captureHoldAffectedFrame",
                    "cadenceHoldFrame",
                    "ptsIntervalIrregularFrame",
                    "ridgeLineOk",
                    "ridgeLineReason",
                    "ridgeLineDy",
                    "ridgeLineDyMinusAffineDy",
                    "ridgeReferenceTrackingOk",
                    "ridgeMinusReferenceDx",
                    "ridgeMinusReferenceDy",
                    "lensBandSupport",
                }:
                    continue
                if column in (
                    "lensBandResidualModel",
                    "lensBandResidualDominantComponent",
                    "lensBandResidualDominantBand",
                ):
                    model, component, band_component = classify_residual_model(video_row, args.window_frames)
                    value = {
                        "lensBandResidualModel": model,
                        "lensBandResidualDominantComponent": component,
                        "lensBandResidualDominantBand": band_component,
                    }[column]
                elif column in {
                    "lensBandTopXVelocity",
                    "lensBandTopYVelocity",
                    "lensBandTopXAcceleration",
                    "lensBandTopYAcceleration",
                    "lensBandTopXJerk",
                    "lensBandTopYJerk",
                    "lensBandRidgeXVelocity",
                    "lensBandRidgeYVelocity",
                    "lensBandRidgeXAcceleration",
                    "lensBandRidgeYAcceleration",
                    "lensBandRidgeXJerk",
                    "lensBandRidgeYJerk",
                    "lensBandMidXVelocity",
                    "lensBandMidYVelocity",
                    "lensBandMidXAcceleration",
                    "lensBandMidYAcceleration",
                    "lensBandMidXJerk",
                    "lensBandMidYJerk",
                    "interBandDeltaY",
                    "interBandDeltaScaleLike",
                    "boundaryPulseScore",
                    "modelSwitchCount",
                    "bandWarpGain",
                    "bandWarpGainDerivative",
                    "bandWarpCoreSpatialGradient",
                    "bandWarpCoreSpatialCurvature",
                    "bandWarpCoreActiveHeight",
                    "bandWarpCoreSpatialGradientDerivative",
                    "bandWarpCoreRemainingDifferentialY",
                    "bandWarpCoreSuppressedDifferentialY",
                    "bandWarpCoreBoundaryLeak",
                    "bandWarpCoreNearGroundLeak",
                    "sourceLensLocalColumnSuppressedY",
                    "sourceLensLocalBandSuppressedY",
                    "sourceLensLocalBoundaryLeak",
                    "sourceLensLocalNearGroundLeak",
                    "sourceLensRidgeBoundaryLeak",
                    "sourceLensRidgeNearGroundLeak",
                }:
                    render_index = int(finite_float(render_row.get("_renderIndex"), -1))
                    if column.startswith("lensBand") and column.endswith("Velocity"):
                        key = column.removesuffix("Velocity")
                        value = derivative_at(render_rows, render_index, key, 1)
                    elif column.startswith("lensBand") and column.endswith("Acceleration"):
                        key = column.removesuffix("Acceleration")
                        value = derivative_at(render_rows, render_index, key, 2)
                    elif column.startswith("lensBand") and column.endswith("Jerk"):
                        key = column.removesuffix("Jerk")
                        value = derivative_at(render_rows, render_index, key, 3)
                    elif column == "interBandDeltaY":
                        value = inter_band_delta_y(render_row)
                    elif column == "interBandDeltaScaleLike":
                        value = inter_band_scale_like(render_row)
                    elif column == "boundaryPulseScore":
                        value = boundary_pulse_score(render_rows, render_index)
                    elif column == "modelSwitchCount":
                        value = float(model_switch_count(render_rows, render_index))
                    elif column == "bandWarpGain":
                        value = lens_band_gain(render_row)
                    elif column == "bandWarpGainDerivative":
                        value = derived_derivative_at(render_rows, render_index, lens_band_gain, 1)
                    elif column == "bandWarpCoreSpatialGradient":
                        value = lens_band_core_spatial_gradient(render_row)
                    elif column == "bandWarpCoreSpatialCurvature":
                        value = lens_band_core_spatial_curvature(render_row)
                    elif column == "bandWarpCoreActiveHeight":
                        value = lens_band_core_active_height(render_row)
                    elif column == "bandWarpCoreSpatialGradientDerivative":
                        value = derived_derivative_at(render_rows, render_index, lens_band_core_spatial_gradient, 1)
                    elif column == "bandWarpCoreRemainingDifferentialY":
                        value = lens_band_core_remaining_differential_y(render_row)
                    elif column == "bandWarpCoreSuppressedDifferentialY":
                        value = lens_band_core_suppressed_differential_y(render_row)
                    elif column == "bandWarpCoreBoundaryLeak":
                        value = lens_band_render_offset_y(render_row, BOUNDARY_BAND_PROBE_Y)
                    elif column == "bandWarpCoreNearGroundLeak":
                        value = lens_band_render_offset_y(render_row, NEAR_GROUND_PROBE_Y)
                    elif column == "sourceLensLocalColumnSuppressedY":
                        value = source_lens_local_column_suppressed_y(render_row)
                    elif column == "sourceLensLocalBandSuppressedY":
                        value = source_lens_local_band_suppressed_y(render_row)
                    elif column == "sourceLensLocalBoundaryLeak":
                        value = source_lens_local_max_abs_offset_y(render_row, BOUNDARY_BAND_PROBE_Y)
                    elif column == "sourceLensLocalNearGroundLeak":
                        value = source_lens_local_max_abs_offset_y(render_row, NEAR_GROUND_PROBE_Y)
                    elif column == "sourceLensRidgeBoundaryLeak":
                        value = source_lens_ridge_offset_y(render_row, BOUNDARY_BAND_PROBE_Y)
                    elif column == "sourceLensRidgeNearGroundLeak":
                        value = source_lens_ridge_offset_y(render_row, NEAR_GROUND_PROBE_Y)
                    else:
                        value = 0.0
                else:
                    value = video_row.get(column, "")
                row[column] = f"{value:.6f}" if isinstance(value, float) else value
            for column in band_columns:
                value = video_row.get(column, "")
                row[column] = f"{value:.6f}" if isinstance(value, float) else value
            row["failureClass"] = failure_class(row, args.window_frames)
            joined_rows.append(row)
            writer.writerow(row)
    summary["csv"] = str(csv_path)

    focus_joined = [
        row for row in joined_rows
        if 4.25 <= finite_float(row.get("time"), -1.0) <= 6.75
    ]
    summary["focusLensReasonCounts"] = dict(
        Counter(str(row.get("lensShakeReason", "")) for row in focus_joined if row.get("lensShakeReason"))
    )
    summary["focusRuntimeDecisionCounts"] = dict(
        Counter(str(row.get("runtimeDecision", "")) for row in focus_joined if row.get("runtimeDecision"))
    )
    summary["focusFailureClassCounts"] = dict(
        Counter(str(row.get("failureClass", "")) for row in focus_joined if row.get("failureClass"))
    )
    summary["focusRollingCandidateRunMax"] = longest_true_run(
        str(row.get("lensShakeReason", "")) == "rollingShutterCandidate" for row in focus_joined
    )
    summary["focusBandAppliedRunMax"] = longest_true_run(
        str(row.get("runtimeDecision", "")) == "bandApplied" for row in focus_joined
    )
    scale_derivatives = [
        abs(finite_float(row.get("scalePulseDerivativePercent"), math.nan))
        for row in focus_joined
        if math.isfinite(finite_float(row.get("scalePulseDerivativePercent"), math.nan))
    ]
    summary["focusScalePulseDerivativePercentP95"] = (
        float(np.percentile(scale_derivatives, 95)) if scale_derivatives else 0.0
    )
    summary["focusScalePulseDerivativeRowsOverLimit"] = sum(value >= 0.25 for value in scale_derivatives)
    summary["focusPtsCadenceAffectedRows"] = sum(
        bool_value(row.get("ptsCadenceAffectedFrame")) for row in focus_joined
    )
    summary["focusCaptureHoldAffectedRows"] = sum(
        bool_value(row.get("captureHoldAffectedFrame")) for row in focus_joined
    )
    summary["focusRidgeLineDetectedSupportNoOpRows"] = sum(
        str(row.get("failureClass", "")) == "ridgeLineDetectedSupportNoOp" for row in focus_joined
    )
    summary["focusRidgeLineSupportGateEvidence"] = {
        "rawYAbsP95": percentile_abs(focus_joined, "sourceLensShakeRidgeLineRawY", 95),
        "supportP95": percentile_abs(focus_joined, "sourceLensShakeRidgeLineSupport", 95),
        "bandSupportedRows": sum(
            finite_float(row.get("sourceLensShakeRidgeLineBandSupported")) > 0.5 for row in focus_joined
        ),
        "appliedRows": sum(
            finite_float(row.get("sourceLensShakeRidgeLineApplied")) > 0.5 for row in focus_joined
        ),
        "rawPresentRows": sum(
            abs(finite_float(row.get("sourceLensShakeRidgeLineRawY"))) >= 0.35 for row in focus_joined
        ),
    }
    summary["focusLensBandWarpAppliedRows"] = sum(
        1 for row in focus_joined if finite_float(row.get("lensBandWarpApplied")) > 0.5
    )
    summary["focusLensBandBoundaryPulseScoreP95"] = percentile_abs(focus_joined, "boundaryPulseScore", 95)
    summary["focusLensBandBoundaryPulseScoreMax"] = max(
        [abs(finite_float(row.get("boundaryPulseScore"))) for row in focus_joined] or [0.0]
    )
    summary["focusLensBandGainDerivativeP95"] = percentile_abs(focus_joined, "bandWarpGainDerivative", 95)
    summary["focusLensBandCoreSpatialGradientP95"] = percentile_abs(focus_joined, "bandWarpCoreSpatialGradient", 95)
    summary["focusLensBandCoreSpatialCurvatureP95"] = percentile_abs(focus_joined, "bandWarpCoreSpatialCurvature", 95)
    summary["focusLensBandCoreActiveHeightP50"] = float(
        np.percentile(
            [finite_float(row.get("bandWarpCoreActiveHeight")) for row in focus_joined],
            50,
        )
    ) if focus_joined else 0.0
    summary["focusLensBandCoreSpatialGradientDerivativeP95"] = percentile_abs(
        focus_joined,
        "bandWarpCoreSpatialGradientDerivative",
        95,
    )
    summary["focusLensBandCoreRemainingDifferentialP95"] = percentile_abs(
        focus_joined,
        "bandWarpCoreRemainingDifferentialY",
        95,
    )
    summary["focusLensBandCoreSuppressedDifferentialP95"] = percentile_abs(
        focus_joined,
        "bandWarpCoreSuppressedDifferentialY",
        95,
    )
    summary["focusLensBandCoreBoundaryLeakP95"] = percentile_abs(focus_joined, "bandWarpCoreBoundaryLeak", 95)
    summary["focusLensBandCoreNearGroundLeakP95"] = percentile_abs(focus_joined, "bandWarpCoreNearGroundLeak", 95)
    summary["focusSourceLensLocalColumnSuppressedP95"] = percentile_abs(
        focus_joined,
        "sourceLensLocalColumnSuppressedY",
        95,
    )
    summary["focusSourceLensLocalBandSuppressedP95"] = percentile_abs(
        focus_joined,
        "sourceLensLocalBandSuppressedY",
        95,
    )
    summary["focusSourceLensLocalBoundaryLeakP95"] = percentile_abs(
        focus_joined,
        "sourceLensLocalBoundaryLeak",
        95,
    )
    summary["focusSourceLensLocalNearGroundLeakP95"] = percentile_abs(
        focus_joined,
        "sourceLensLocalNearGroundLeak",
        95,
    )
    summary["focusSourceLensRidgeBoundaryLeakP95"] = percentile_abs(
        focus_joined,
        "sourceLensRidgeBoundaryLeak",
        95,
    )
    summary["focusSourceLensRidgeNearGroundLeakP95"] = percentile_abs(
        focus_joined,
        "sourceLensRidgeNearGroundLeak",
        95,
    )
    summary["focusLensBandModelSwitchCountMax"] = max(
        [finite_float(row.get("modelSwitchCount")) for row in focus_joined] or [0.0]
    )
    for band_name in ("Top", "Ridge", "Mid"):
        for axis in ("X", "Y"):
            summary[f"focusLensBandRaw{band_name}{axis}P95"] = percentile_abs(
                focus_joined,
                f"lensBandRaw{band_name}{axis}",
                95,
            )
            summary[f"focusLensBandPulseDelta{band_name}{axis}P95"] = percentile_abs(
                focus_joined,
                f"lensBandPulseDelta{band_name}{axis}",
                95,
            )
            summary[f"focusLensBand{band_name}{axis}VelocityP95"] = percentile_abs(
                focus_joined,
                f"lensBand{band_name}{axis}Velocity",
                95,
            )
            summary[f"focusLensBand{band_name}{axis}AccelerationP95"] = percentile_abs(
                focus_joined,
                f"lensBand{band_name}{axis}Acceleration",
                95,
            )
            summary[f"focusLensBand{band_name}{axis}JerkP95"] = percentile_abs(
                focus_joined,
                f"lensBand{band_name}{axis}Jerk",
                95,
            )
    summary["focusGlobalLensAppliedRows"] = sum(
        1 for row in focus_joined if str(row.get("lensShakeReason")) == "applied"
    )
    summary["focusMaxAbsRenderTimeError"] = max(
        [abs(finite_float(row.get("renderTimeError"))) for row in focus_joined] or [0.0]
    )
    render_row_counts = Counter(
        str(row.get("renderRow", "")) for row in joined_rows if str(row.get("renderRow", ""))
    )
    focus_render_row_counts = Counter(
        str(row.get("renderRow", "")) for row in focus_joined if str(row.get("renderRow", ""))
    )
    summary["renderJoinRows"] = len(joined_rows)
    summary["renderJoinMissingRows"] = sum(1 for row in joined_rows if not str(row.get("renderRow", "")))
    summary["renderJoinUniqueRenderRows"] = len(render_row_counts)
    summary["renderJoinDuplicateVideoRows"] = sum(count - 1 for count in render_row_counts.values() if count > 1)
    summary["renderJoinMaxAbsTimeError"] = max(
        [abs(finite_float(row.get("renderTimeError"))) for row in joined_rows] or [0.0]
    )
    summary["focusRenderJoinUniqueRenderRows"] = len(focus_render_row_counts)
    summary["focusRenderJoinDuplicateVideoRows"] = sum(
        count - 1 for count in focus_render_row_counts.values() if count > 1
    )
    summary["focusQualityScaleJoinRows"] = sum(1 for row in focus_joined if str(row.get("scaleResidualPercent", "")))
    summary["focusQualityRidgeJoinRows"] = sum(1 for row in focus_joined if str(row.get("ridgeLineOk", "")))
    summary["focusQualityScaleMissingRows"] = len(focus_joined) - summary["focusQualityScaleJoinRows"]
    summary["focusQualityRidgeMissingRows"] = len(focus_joined) - summary["focusQualityRidgeJoinRows"]
    focus_rolling = [abs(finite_float(row.get(f"lensBandRollingShutterScoreHF{args.window_frames}"))) for row in focus_joined]
    summary[f"focusLensBandRollingShutterScoreHF{args.window_frames}P95"] = (
        float(np.percentile(focus_rolling, 95)) if focus_rolling else 0.0
    )
    summary[f"focusLensBandRollingShutterScoreHF{args.window_frames}Max"] = max(focus_rolling) if focus_rolling else 0.0
    focus_components: dict[str, float] = {}
    for key in (
        "lensBandRollingShutterRowScore",
        "lensBandRollingShutterColScore",
        "lensBandRollingShutterRollScore",
        "lensBandRollingShutterInterBandScore",
    ):
        values = [abs(finite_float(row.get(f"{key}HF{args.window_frames}"))) for row in focus_joined]
        p95 = float(np.percentile(values, 95)) if values else 0.0
        focus_components[key] = p95
        summary[f"focus{key[0].upper()}{key[1:]}HF{args.window_frames}P95"] = p95
    if focus_components:
        summary["focusLensBandRollingShutterDominantComponent"] = max(
            focus_components,
            key=lambda key: focus_components[key],
        )
    focus_models = Counter(str(row.get("lensBandResidualModel", "")) for row in focus_joined if row.get("lensBandResidualModel"))
    focus_model_p95 = {
        "rowPhaseWarp": percentile_abs(focus_joined, f"lensBandRollingShutterRowScoreHF{args.window_frames}", 95),
        "columnPhaseWarp": percentile_abs(focus_joined, f"lensBandRollingShutterColScoreHF{args.window_frames}", 95),
        "localRollWarp": percentile_abs(focus_joined, f"lensBandRollingShutterRollScoreHF{args.window_frames}", 95),
        "regionClusterWarp": percentile_abs(focus_joined, f"lensBandRollingShutterInterBandScoreHF{args.window_frames}", 95),
    }
    dominant_model, dominant_model_value = dominant_key(focus_model_p95)
    summary["focusLensBandResidualModelCounts"] = dict(focus_models)
    summary["focusLensBandCorrectionModelCounts"] = dict(
        Counter(str(row.get("lensBandCorrectionModel", "")) for row in focus_joined if row.get("lensBandCorrectionModel"))
    )
    source_local_rows = [
        row for row in focus_joined
        if "sourceLocal" in str(row.get("lensBandCorrectionModel", ""))
    ]
    missing_source_local_rows = [
        row for row in source_local_rows
        if str(row.get("sourceLensShakeLocalApplied", "")) == ""
    ]
    summary["focusSourceLocalRows"] = len(source_local_rows)
    summary["focusSourceLocalMissingRows"] = len(missing_source_local_rows)
    source_ridge_line_rows = [
        row for row in focus_joined
        if "sourceRidgeLine" in str(row.get("lensBandCorrectionModel", ""))
    ]
    missing_source_ridge_line_rows = [
        row for row in source_ridge_line_rows
        if str(row.get("sourceLensShakeRidgeLineApplied", "")) == ""
    ]
    summary["focusSourceRidgeLineRows"] = len(source_ridge_line_rows)
    summary["focusSourceRidgeLineMissingRows"] = len(missing_source_ridge_line_rows)
    covered_rows = sum(
        1 for row in focus_joined
        if correction_model_covers(dominant_model, str(row.get("lensBandCorrectionModel", "")))
    )
    applied_covered_rows = sum(
        1 for row in focus_joined
        if runtime_model_applied(row, dominant_model)
    )
    summary["focusLensBandDominantModelCoveredRows"] = covered_rows
    summary["focusLensBandDominantModelCoveredRatio"] = (
        covered_rows / len(focus_joined) if focus_joined else 0.0
    )
    summary["focusLensBandDominantModelAppliedRows"] = applied_covered_rows
    summary["focusLensBandDominantModelAppliedRatio"] = (
        applied_covered_rows / len(focus_joined) if focus_joined else 0.0
    )
    summary["focusLensBandResidualDominantModel"] = dominant_model
    summary["focusLensBandResidualDominantModelP95"] = dominant_model_value
    summary["focusLensBandResidualEvidence"] = (
        f"{dominant_model} p95={dominant_model_value:.3f}; "
        f"models={dict(focus_models)}; "
        f"correctionModels={summary.get('focusLensBandCorrectionModelCounts', {})}; "
        f"coveredRatio={summary.get('focusLensBandDominantModelCoveredRatio', 0.0):.3f}; "
        f"appliedRatio={summary.get('focusLensBandDominantModelAppliedRatio', 0.0):.3f}; "
        f"reasonCounts={summary.get('focusLensReasonCounts', {})}; "
        f"bandWarpAppliedRows={summary.get('focusLensBandWarpAppliedRows', 0)}"
    )
    for band_name in ("cloud_top", "ridge_horizon", "mountain_mid"):
        points = [finite_float(row.get(f"{band_name}.points")) for row in focus_joined]
        summary[f"{band_name}FocusPointsP50"] = float(np.percentile(points, 50)) if points else 0.0
        local_support = [finite_float(row.get(f"{band_name}.localSupport")) for row in focus_joined]
        summary[f"{band_name}FocusLocalSupportP50"] = float(np.percentile(local_support, 50)) if local_support else 0.0

    heatmap_path = args.output_dir / "lens_band_residual_heatmap.csv"
    with heatmap_path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = [
            "frame",
            "time",
            "analysisTime",
            "band",
            "dxHF",
            "dyHF",
            "rowPhaseHF",
            "columnPhaseHF",
            "localRollHF",
            "dominantLocalModel",
            "runtimeReason",
            "runtimeCorrectionModel",
            "runtimeBandWarpApplied",
        ]
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in focus_joined:
            for band_name in FAR_FIELD_BANDS:
                local_values = {
                    "rowPhaseWarp": abs(finite_float(row.get(f"{band_name}.rowPhaseMagnitudeHF{args.window_frames}"))),
                    "columnPhaseWarp": abs(finite_float(row.get(f"{band_name}.colPhaseMagnitudeHF{args.window_frames}"))),
                    "localRollWarp": abs(finite_float(row.get(f"{band_name}.localRollSpreadHF{args.window_frames}"))),
                }
                local_model, _ = dominant_key(local_values)
                writer.writerow(
                    {
                        "frame": row.get("frame", ""),
                        "time": row.get("time", ""),
                        "analysisTime": row.get("analysisTime", ""),
                        "band": band_name,
                        "dxHF": row.get(f"{band_name}.dxHF{args.window_frames}", ""),
                        "dyHF": row.get(f"{band_name}.dyHF{args.window_frames}", ""),
                        "rowPhaseHF": row.get(f"{band_name}.rowPhaseMagnitudeHF{args.window_frames}", ""),
                        "columnPhaseHF": row.get(f"{band_name}.colPhaseMagnitudeHF{args.window_frames}", ""),
                        "localRollHF": row.get(f"{band_name}.localRollSpreadHF{args.window_frames}", ""),
                        "dominantLocalModel": local_model,
                        "runtimeReason": row.get("lensShakeReason", ""),
                        "runtimeCorrectionModel": row.get("lensBandCorrectionModel", ""),
                        "runtimeBandWarpApplied": row.get("lensBandWarpApplied", ""),
                    }
                )
    summary["heatmapCsv"] = str(heatmap_path)

    if args.require_band_warp and summary["focusLensBandWarpAppliedRows"] <= 0:
        raise SystemExit(
            "lens band diagnostics failed: target focus window had no rollingRowWarp band application; "
            f"summary={args.output_dir / 'lens_band_source_summary.json'} csv={csv_path}"
        )
    if args.require_band_warp and missing_source_local_rows:
        raise SystemExit(
            "lens band diagnostics failed: sourceLocal correction model was present but local lens rows "
            "were missing from the joined runtime diagnostics; "
            f"missing={len(missing_source_local_rows)} sourceLocalRows={len(source_local_rows)} csv={csv_path}"
        )
    if args.require_band_warp and missing_source_ridge_line_rows:
        raise SystemExit(
            "lens band diagnostics failed: sourceRidgeLine correction model was present but ridge line "
            "lens rows were missing from the joined runtime diagnostics; "
            f"missing={len(missing_source_ridge_line_rows)} sourceRidgeLineRows={len(source_ridge_line_rows)} csv={csv_path}"
        )
    if (
        args.require_band_warp
        and dominant_model_value >= 0.35
        and dominant_model != "noSignal"
        and summary["focusLensBandDominantModelAppliedRatio"] < 0.55
    ):
        raise SystemExit(
            "lens band diagnostics failed: dominant residual model was not consistently applied by runtime correction; "
            f"model={dominant_model} evidence={summary['focusLensBandResidualEvidence']} csv={csv_path}"
        )
    if args.forbid_global_lens and summary["focusGlobalLensAppliedRows"] > 0:
        raise SystemExit(
            "lens band diagnostics failed: target focus window used global lensShake applied path; "
            f"rows={summary['focusGlobalLensAppliedRows']} csv={csv_path}"
        )
    if args.require_band_warp:
        weak_bands = [
            name for name in ("cloud_top", "ridge_horizon", "mountain_mid")
            if float(summary.get(f"{name}FocusPointsP50", 0.0)) < 8.0
        ]
        if weak_bands:
            raise SystemExit(
                "lens band diagnostics failed: insufficient far-field feature support "
                f"for {weak_bands}; csv={csv_path}"
            )

    (args.output_dir / "lens_band_source_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
