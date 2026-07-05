#!/usr/bin/env python3
"""Evaluate FCP Viewer screen recordings for Stabilizer zoom/crop regressions."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    import cv2
    import numpy as np
except Exception as exc:  # pragma: no cover - exercised only on missing local deps.
    print(f"stabilizer_video_quality.py: OpenCV/numpy is required: {exc}", file=sys.stderr)
    sys.exit(2)


Roi = tuple[int, int, int, int]


def fail(message: str, code: int = 2) -> None:
    print(f"stabilizer_video_quality.py: {message}", file=sys.stderr)
    sys.exit(code)


def parse_roi(text: str) -> Roi:
    parts = text.split(",")
    if len(parts) != 4:
        fail(f"ROI must be x,y,w,h, got: {text}")
    try:
        x, y, w, h = (int(part) for part in parts)
    except ValueError:
        fail(f"ROI values must be integers, got: {text}")
    if w <= 0 or h <= 0:
        fail(f"ROI width/height must be positive, got: {text}")
    return x, y, w, h


def parse_frame_rate(value: Any, fallback: float) -> float:
    if isinstance(value, str):
        text = value.strip().lower()
        if text == "source":
            return fallback
        if "/" in text:
            numerator, denominator = text.split("/", 1)
            try:
                parsed = float(numerator) / float(denominator)
            except ValueError:
                fail(f"invalid frame rate: {value}")
            if parsed > 0.0 and math.isfinite(parsed):
                return parsed
            fail(f"invalid frame rate: {value}")
        try:
            parsed = float(text)
        except ValueError:
            fail(f"invalid frame rate: {value}")
        if parsed > 0.0 and math.isfinite(parsed):
            return parsed
        fail(f"invalid frame rate: {value}")
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return fallback
    if parsed > 0.0 and math.isfinite(parsed):
        return parsed
    return fallback


def roi_from_case(value: dict[str, Any], name: str) -> Roi:
    try:
        roi = (int(value["x"]), int(value["y"]), int(value["w"]), int(value["h"]))
    except KeyError as exc:
        fail(f"case {name} is missing {exc}")
    if roi[2] <= 0 or roi[3] <= 0:
        fail(f"case {name} must have positive width/height")
    return roi


def clamp_roi(roi: Roi, width: int, height: int, label: str) -> Roi:
    x, y, w, h = roi
    if x < 0 or y < 0 or x + w > width or y + h > height:
        fail(f"{label} ROI {roi} is outside frame {width}x{height}")
    return roi


def scale_roi_to_viewer(roi: Roi, source_viewer: Roi, target_viewer: Roi, label: str) -> Roi:
    source_w = max(1, source_viewer[2])
    source_h = max(1, source_viewer[3])
    target_w = max(1, target_viewer[2])
    target_h = max(1, target_viewer[3])
    if source_w == target_w and source_h == target_h:
        return roi

    scale_x = target_w / float(source_w)
    scale_y = target_h / float(source_h)
    x = int(round(roi[0] * scale_x))
    y = int(round(roi[1] * scale_y))
    w = max(1, int(round(roi[2] * scale_x)))
    h = max(1, int(round(roi[3] * scale_y)))
    if x >= target_w or y >= target_h:
        fail(f"{label} ROI {roi} scales outside viewer {target_w}x{target_h}")
    w = min(w, target_w - x)
    h = min(h, target_h - y)
    return x, y, w, h


def derive_ridge_reference_roi(content_roi: Roi, ridge_roi: Roi) -> Roi | None:
    content_x, content_y, content_w, content_h = content_roi
    _ridge_x, ridge_y, _ridge_w, ridge_h = ridge_roi
    content_bottom = content_y + content_h
    reference_y = max(content_y, ridge_y + ridge_h)
    reference_h = content_bottom - reference_y
    if reference_h < 24:
        return None
    return (content_x, reference_y, content_w, reference_h)


def rolling_median(values: list[float], window: int) -> list[float]:
    if not values:
        return []
    half = max(0, window // 2)
    result: list[float] = []
    arr = np.asarray(values, dtype=np.float64)
    for index in range(len(values)):
        start = max(0, index - half)
        end = min(len(values), index + half + 1)
        result.append(float(np.nanmedian(arr[start:end])))
    return result


def rolling_peak_to_peak(values: list[float], window: int) -> list[float]:
    if not values:
        return []
    half = max(0, window // 2)
    result: list[float] = []
    arr = np.asarray(values, dtype=np.float64)
    for index in range(len(values)):
        start = max(0, index - half)
        end = min(len(values), index + half + 1)
        segment = arr[start:end]
        result.append(float(np.nanmax(segment) - np.nanmin(segment)))
    return result


def black_margins(gray: np.ndarray, threshold: int) -> dict[str, int]:
    height, width = gray.shape[:2]
    row_start = max(0, int(height * 0.22))
    row_end = min(height, int(height * 0.78))
    col_start = max(0, int(width * 0.18))
    col_end = min(width, int(width * 0.82))

    central_rows = gray[row_start:row_end, :]
    central_cols = gray[:, col_start:col_end]
    col_mean = central_rows.mean(axis=0)
    row_mean = central_cols.mean(axis=1)

    left = 0
    while left < width and col_mean[left] <= threshold:
        left += 1
    right = 0
    while right < width and col_mean[width - 1 - right] <= threshold:
        right += 1
    top = 0
    while top < height and row_mean[top] <= threshold:
        top += 1
    bottom = 0
    while bottom < height and row_mean[height - 1 - bottom] <= threshold:
        bottom += 1

    return {"left": left, "right": right, "top": top, "bottom": bottom}


def normalize_angle_degrees(value: float) -> float:
    result = float(value)
    while result <= -90.0:
        result += 180.0
    while result > 90.0:
        result -= 180.0
    return result


def angle_delta_degrees(current: float, previous: float) -> float:
    return normalize_angle_degrees(float(current) - float(previous))


def unwrap_angles_degrees(values: list[float]) -> list[float]:
    if not values:
        return []
    result = [float(values[0])]
    for value in values[1:]:
        result.append(result[-1] + angle_delta_degrees(float(value), result[-1]))
    return result


def estimate_black_edge_transform(
    gray: np.ndarray,
    threshold: int,
    quality: dict[str, Any],
) -> dict[str, Any]:
    height, width = gray.shape[:2]
    if height < 8 or width < 8:
        return {"ok": False, "reason": "viewer_too_small"}

    black = (gray <= threshold).astype(np.uint8)
    black_pixel_count = int(np.count_nonzero(black))
    black_ratio = black_pixel_count / float(max(1, black.size))
    min_outside_ratio = float(quality.get("minBlackEdgeOutsideRatio", 0.002))
    if black_ratio < min_outside_ratio:
        return {
            "ok": False,
            "reason": "black_edge_not_visible",
            "blackOutsideRatio": black_ratio,
            "outsideBlackPixelCount": black_pixel_count,
        }

    component_count, labels, _stats, _centroids = cv2.connectedComponentsWithStats(black, connectivity=8)
    if component_count <= 1:
        return {
            "ok": False,
            "reason": "black_edge_not_visible",
            "blackOutsideRatio": black_ratio,
            "outsideBlackPixelCount": black_pixel_count,
        }

    border_labels = set(labels[0, :].tolist())
    border_labels.update(labels[height - 1, :].tolist())
    border_labels.update(labels[:, 0].tolist())
    border_labels.update(labels[:, width - 1].tolist())
    border_labels.discard(0)
    if not border_labels:
        return {
            "ok": False,
            "reason": "black_edge_not_touching_viewer_border",
            "blackOutsideRatio": black_ratio,
            "outsideBlackPixelCount": black_pixel_count,
        }

    outside_black = np.isin(labels, list(border_labels))
    outside_black_count = int(np.count_nonzero(outside_black))
    outside_ratio = outside_black_count / float(max(1, black.size))
    if outside_ratio < min_outside_ratio:
        return {
            "ok": False,
            "reason": "outside_black_edge_too_small",
            "blackOutsideRatio": outside_ratio,
            "outsideBlackPixelCount": outside_black_count,
        }

    content_mask = (~outside_black).astype(np.uint8) * 255
    contours, _hierarchy = cv2.findContours(content_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return {
            "ok": False,
            "reason": "content_contour_missing",
            "blackOutsideRatio": outside_ratio,
            "outsideBlackPixelCount": outside_black_count,
        }

    contour = max(contours, key=cv2.contourArea)
    contour_area = float(cv2.contourArea(contour))
    content_area_ratio = contour_area / float(max(1, width * height))
    min_content_area_ratio = float(quality.get("minBlackEdgeTransformContentAreaRatio", 0.10))
    if content_area_ratio < min_content_area_ratio:
        return {
            "ok": False,
            "reason": "content_contour_too_small",
            "blackOutsideRatio": outside_ratio,
            "outsideBlackPixelCount": outside_black_count,
            "contentAreaRatio": content_area_ratio,
        }

    (center_x, center_y), (rect_width, rect_height), rect_angle = cv2.minAreaRect(contour)
    if rect_width <= 0.0 or rect_height <= 0.0:
        return {
            "ok": False,
            "reason": "content_rect_invalid",
            "blackOutsideRatio": outside_ratio,
            "outsideBlackPixelCount": outside_black_count,
            "contentAreaRatio": content_area_ratio,
        }
    if rect_width < rect_height:
        rect_width, rect_height = rect_height, rect_width
        rect_angle += 90.0
    rotation = normalize_angle_degrees(rect_angle)
    content_scale = math.sqrt((rect_width * rect_height) / float(max(1, width * height)))
    box = cv2.boxPoints(((center_x, center_y), (rect_width, rect_height), rect_angle))
    box_min_x = float(np.min(box[:, 0]))
    box_max_x = float(np.max(box[:, 0]))
    box_min_y = float(np.min(box[:, 1]))
    box_max_y = float(np.max(box[:, 1]))
    return {
        "ok": True,
        "reason": "",
        "blackOutsideRatio": outside_ratio,
        "outsideBlackPixelCount": outside_black_count,
        "contentAreaRatio": content_area_ratio,
        "centerX": float(center_x),
        "centerY": float(center_y),
        "rectWidth": float(rect_width),
        "rectHeight": float(rect_height),
        "rectAreaRatio": float((rect_width * rect_height) / float(max(1, width * height))),
        "scalePercent": (content_scale - 1.0) * 100.0,
        "rotationDegrees": rotation,
        "boxMinX": box_min_x,
        "boxMaxX": box_max_x,
        "boxMinY": box_min_y,
        "boxMaxY": box_max_y,
    }


def crop(frame: np.ndarray, roi: Roi) -> np.ndarray:
    x, y, w, h = roi
    return frame[y : y + h, x : x + w]


def missing_proxy_placeholder_metrics(frame: np.ndarray) -> dict[str, float | bool]:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    b, g, r = cv2.split(frame)
    red_dominance = r.astype(np.int16) - np.maximum(g, b).astype(np.int16)
    mask = (red_dominance > 18) & (r > 35) & (g < 75) & (b < 75)
    ratio = float(np.count_nonzero(mask)) / float(max(1, gray.size))
    height, width = gray.shape[:2]
    center_mask = mask[height // 4 : (3 * height) // 4, width // 4 : (3 * width) // 4]
    center_ratio = float(np.count_nonzero(center_mask)) / float(max(1, center_mask.size))
    mean_value = float(gray.mean())
    std_value = float(gray.std())
    return {
        "placeholderFrame": bool(mean_value < 80.0 and ratio > 0.55 and center_ratio > 0.40),
        "placeholderRatio": ratio,
        "centerPlaceholderRatio": center_ratio,
        "placeholderMean": mean_value,
        "placeholderStd": std_value,
    }


def estimate_transform(
    previous_gray: np.ndarray,
    current_gray: np.ndarray,
    min_inliers: int,
) -> dict[str, Any]:
    points = cv2.goodFeaturesToTrack(
        previous_gray,
        maxCorners=900,
        qualityLevel=0.01,
        minDistance=8,
        blockSize=7,
    )
    if points is None or len(points) < min_inliers:
        return {"ok": False, "reason": "few_features", "featureCount": 0 if points is None else int(len(points))}

    next_points, status, _err = cv2.calcOpticalFlowPyrLK(
        previous_gray,
        current_gray,
        points,
        None,
        winSize=(21, 21),
        maxLevel=3,
        criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01),
    )
    if next_points is None or status is None:
        return {"ok": False, "reason": "flow_failed", "featureCount": int(len(points))}

    keep = status.reshape(-1) == 1
    source = points.reshape(-1, 2)[keep]
    target = next_points.reshape(-1, 2)[keep]
    if len(source) < min_inliers:
        return {
            "ok": False,
            "reason": "few_tracked",
            "featureCount": int(len(points)),
            "trackedCount": int(len(source)),
        }

    matrix, inlier_mask = cv2.estimateAffinePartial2D(
        source,
        target,
        method=cv2.RANSAC,
        ransacReprojThreshold=3.0,
        maxIters=2000,
        confidence=0.99,
        refineIters=10,
    )
    if matrix is None or inlier_mask is None:
        return {
            "ok": False,
            "reason": "affine_failed",
            "featureCount": int(len(points)),
            "trackedCount": int(len(source)),
        }

    inliers = int(inlier_mask.reshape(-1).sum())
    a = float(matrix[0, 0])
    b = float(matrix[1, 0])
    scale = math.sqrt(a * a + b * b)
    rotation = math.degrees(math.atan2(b, a))
    return {
        "ok": inliers >= min_inliers,
        "reason": None if inliers >= min_inliers else "few_inliers",
        "featureCount": int(len(points)),
        "trackedCount": int(len(source)),
        "inliers": inliers,
        "scalePercent": (scale - 1.0) * 100.0,
        "dx": float(matrix[0, 2]),
        "dy": float(matrix[1, 2]),
        "rotationDegrees": rotation,
    }


def estimate_ridge_line(gray: np.ndarray, quality: dict[str, Any]) -> dict[str, Any]:
    height, width = gray.shape[:2]
    if height < 8 or width < 8:
        return {"ok": False, "reason": "ridge_line_roi_too_small"}

    top_fraction = float(quality.get("ridgeLineSearchTopFraction", 0.0))
    bottom_fraction = float(quality.get("ridgeLineSearchBottomFraction", 1.0))
    top = max(1, min(height - 2, int(round(height * top_fraction))))
    bottom = max(top + 3, min(height - 1, int(round(height * bottom_fraction))))
    if bottom <= top:
        return {"ok": False, "reason": "ridge_line_search_empty"}

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    gradient_y = np.abs(cv2.Sobel(blurred, cv2.CV_32F, 0, 1, ksize=3))
    search = gradient_y[top:bottom, :]
    if search.size == 0:
        return {"ok": False, "reason": "ridge_line_search_empty"}

    column_strength = np.max(search, axis=0)
    column_y = np.argmax(search, axis=0).astype(np.float64) + float(top)
    percentile = float(quality.get("ridgeLineEdgeColumnPercentile", 70.0))
    strength_floor = float(quality.get("ridgeLineEdgeStrengthFloor", 4.0))
    strength_threshold = max(strength_floor, float(np.percentile(column_strength, percentile)))
    selected = column_strength >= strength_threshold
    support_ratio = float(np.count_nonzero(selected)) / float(max(1, width))
    min_support_ratio = float(quality.get("minRidgeLineSupportRatio", 0.0))
    if support_ratio < min_support_ratio or not np.any(selected):
        return {
            "ok": False,
            "reason": "ridge_line_low_support",
            "ridgeLineSupportRatio": support_ratio,
            "ridgeLineStrengthThreshold": strength_threshold,
        }

    selected_y = column_y[selected]
    selected_strength = column_strength[selected].astype(np.float64)
    weight_sum = float(np.sum(selected_strength))
    weighted_y = (
        float(np.sum(selected_y * selected_strength) / weight_sum)
        if weight_sum > 0.0
        else float(np.median(selected_y))
    )
    return {
        "ok": True,
        "reason": "",
        "ridgeLineY": float(np.median(selected_y)),
        "ridgeLineWeightedY": weighted_y,
        "ridgeLineSupportRatio": support_ratio,
        "ridgeLineStrengthMean": float(np.mean(selected_strength)),
        "ridgeLineStrengthThreshold": strength_threshold,
        "ridgeLineYSpreadP90": float(np.percentile(selected_y, 95) - np.percentile(selected_y, 5)),
    }


def summarize_ridge_motion(
    ridge_rows: list[dict[str, Any]],
    quality: dict[str, Any],
    effective_sample_fps: float,
    source_baseline: dict[str, Any] | None = None,
) -> tuple[bool, list[str], dict[str, Any]]:
    all_tracking_rows = [row for row in ridge_rows if bool(row.get("trackingOk"))]
    tracking_ratio = (len(all_tracking_rows) / len(ridge_rows)) if ridge_rows else 0.0
    exclude_pts_irregular_from_ridge = bool(
        quality.get(
            "excludePtsIrregularFromRidgeMotion",
            quality.get("excludePtsIrregularFromFrameJump", False),
        )
    )
    pts_cadence_excluded_rows = [
        row
        for row in all_tracking_rows
        if bool(row.get("ptsCadenceAffectedFrame"))
    ]
    tracking_rows = [
        row
        for row in all_tracking_rows
        if not (exclude_pts_irregular_from_ridge and bool(row.get("ptsCadenceAffectedFrame")))
    ]
    median_seconds = float(quality.get("ridgeRollingMedianWindowSeconds", 0.5))
    median_window = max(3, int(round(median_seconds * effective_sample_fps)))
    if median_window % 2 == 0:
        median_window += 1

    for component in ("dx", "dy"):
        medians = rolling_median([float(row.get(component, 0.0)) for row in tracking_rows], median_window)
        for row, median in zip(tracking_rows, medians):
            row[f"{component}Median"] = median
            row[f"{component}Residual"] = float(row.get(component, 0.0)) - median

    residual_vectors: list[float] = []
    vertical_residuals: list[float] = []
    horizontal_residuals: list[float] = []
    ridge_line_vertical_residuals: list[float] = []
    ridge_line_jerks: list[float] = []
    ridge_reference_vertical_deltas: list[float] = []
    ridge_reference_horizontal_deltas: list[float] = []
    ridge_line_rows = [row for row in tracking_rows if bool(row.get("ridgeLineOk"))]
    ridge_reference_rows = [row for row in tracking_rows if bool(row.get("ridgeReferenceTrackingOk"))]
    previous_line_row: dict[str, Any] | None = None
    for row in tracking_rows:
        x_residual = float(row.get("dxResidual", 0.0))
        y_residual = float(row.get("dyResidual", 0.0))
        vector_residual = math.hypot(x_residual, y_residual)
        row["ridgeHighFrequencyResidualPixels"] = vector_residual
        row["ridgeVerticalResidualPixels"] = abs(y_residual)
        row["ridgeHorizontalResidualPixels"] = abs(x_residual)
        residual_vectors.append(vector_residual)
        vertical_residuals.append(abs(y_residual))
        horizontal_residuals.append(abs(x_residual))
        if "ridgeLineDyMinusAffineDy" in row:
            line_residual = float(row.get("ridgeLineDyMinusAffineDy", 0.0))
            row["ridgeLineVerticalResidualPixels"] = abs(line_residual)
            ridge_line_vertical_residuals.append(abs(line_residual))
            if (
                previous_line_row is not None
                and int(row.get("previousFrame", -1)) == int(previous_line_row.get("frame", -2))
                and "ridgeLineDyMinusAffineDy" in previous_line_row
            ):
                line_jerk = line_residual - float(previous_line_row.get("ridgeLineDyMinusAffineDy", 0.0))
                row["ridgeLineVerticalJerkPixelsPerFrame"] = line_jerk
                ridge_line_jerks.append(abs(line_jerk))
            else:
                row["ridgeLineVerticalJerkPixelsPerFrame"] = 0.0
            previous_line_row = row
        if bool(row.get("ridgeReferenceTrackingOk")):
            ridge_reference_vertical_deltas.append(abs(float(row.get("ridgeMinusReferenceDy", 0.0))))
            ridge_reference_horizontal_deltas.append(abs(float(row.get("ridgeMinusReferenceDx", 0.0))))

    max_vector = max(residual_vectors, default=0.0)
    p95_vector = (
        float(np.percentile(np.asarray(residual_vectors, dtype=np.float64), 95))
        if residual_vectors
        else 0.0
    )
    p95_vertical = (
        float(np.percentile(np.asarray(vertical_residuals, dtype=np.float64), 95))
        if vertical_residuals
        else 0.0
    )
    p95_horizontal = (
        float(np.percentile(np.asarray(horizontal_residuals, dtype=np.float64), 95))
        if horizontal_residuals
        else 0.0
    )
    p95_ridge_line_vertical = (
        float(np.percentile(np.asarray(ridge_line_vertical_residuals, dtype=np.float64), 95))
        if ridge_line_vertical_residuals
        else 0.0
    )
    p95_ridge_line_jerk = (
        float(np.percentile(np.asarray(ridge_line_jerks, dtype=np.float64), 95))
        if ridge_line_jerks
        else 0.0
    )
    p95_reference_vertical_delta = (
        float(np.percentile(np.asarray(ridge_reference_vertical_deltas, dtype=np.float64), 95))
        if ridge_reference_vertical_deltas
        else 0.0
    )
    p95_reference_horizontal_delta = (
        float(np.percentile(np.asarray(ridge_reference_horizontal_deltas, dtype=np.float64), 95))
        if ridge_reference_horizontal_deltas
        else 0.0
    )
    residual_threshold = float(quality.get("ridgeResidualRunThresholdPixels", float("inf")))
    max_run = 0
    current_run = 0
    previous_row: dict[str, Any] | None = None
    for row in sorted(tracking_rows, key=lambda item: int(item.get("frame", 0))):
        is_adjacent_sample = False
        if previous_row is not None:
            try:
                is_adjacent_sample = int(row.get("previousFrame", -1)) == int(previous_row.get("frame", -2))
            except (TypeError, ValueError):
                is_adjacent_sample = False
        if float(row.get("ridgeHighFrequencyResidualPixels", 0.0)) > residual_threshold:
            current_run = current_run + 1 if is_adjacent_sample else 1
            max_run = max(max_run, current_run)
        else:
            current_run = 0
        previous_row = row

    tracking_ratio_limit = float(quality.get("minRidgeTrackingRatio", 0.0))
    max_vector_limit = float(quality.get("maxRidgeHighFrequencyResidualPixels", float("inf")))
    p95_vector_limit = float(quality.get("maxRidgeHighFrequencyResidualP95Pixels", float("inf")))
    p95_vertical_limit = float(quality.get("maxRidgeVerticalResidualP95Pixels", float("inf")))
    p95_line_vertical_limit = float(quality.get("maxRidgeLineVerticalResidualP95Pixels", float("inf")))
    p95_line_jerk_limit = float(quality.get("maxRidgeLineVerticalJerkP95PixelsPerFrame", float("inf")))
    p95_reference_vertical_delta_limit = float(quality.get("maxRidgeMinusReferenceVerticalP95Pixels", float("inf")))
    p95_reference_horizontal_delta_limit = float(quality.get("maxRidgeMinusReferenceHorizontalP95Pixels", float("inf")))
    max_run_limit = int(quality.get("maxRidgeResidualRunFrames", 2**31 - 1))

    failures: list[str] = []
    source_ridge_baseline = source_baseline.get("ridge", {}) if source_baseline else {}

    def add_source_ratio_failure(
        label: str,
        value: float,
        baseline_key: str,
        ratio_key: str,
        unit: str = "px",
    ) -> None:
        if ratio_key not in quality:
            return
        baseline_value = source_ridge_baseline.get(baseline_key)
        if not isinstance(baseline_value, (int, float)) or not math.isfinite(float(baseline_value)):
            return
        baseline_float = float(baseline_value)
        if baseline_float <= 0.0:
            return
        ratio_limit = float(quality[ratio_key])
        source_limit = baseline_float * ratio_limit
        if value > source_limit:
            failures.append(
                f"{label} {value:.3f}{unit} exceeds source baseline "
                f"{baseline_float:.3f}{unit} * {ratio_limit:.3f} = {source_limit:.3f}{unit}"
            )

    if tracking_ratio < tracking_ratio_limit:
        failures.append(f"ridge tracking ratio {tracking_ratio:.3f} below {tracking_ratio_limit:.3f}")
    if max_vector > max_vector_limit:
        failures.append(f"ridge high-frequency residual {max_vector:.3f}px exceeds {max_vector_limit:.3f}px")
    if p95_vector > p95_vector_limit:
        failures.append(f"ridge high-frequency residual p95 {p95_vector:.3f}px exceeds {p95_vector_limit:.3f}px")
    if p95_vertical > p95_vertical_limit:
        failures.append(f"ridge vertical residual p95 {p95_vertical:.3f}px exceeds {p95_vertical_limit:.3f}px")
    if p95_ridge_line_vertical > p95_line_vertical_limit:
        failures.append(
            f"ridge line vertical residual p95 {p95_ridge_line_vertical:.3f}px exceeds {p95_line_vertical_limit:.3f}px"
        )
    if p95_ridge_line_jerk > p95_line_jerk_limit:
        failures.append(
            f"ridge line vertical jerk p95 {p95_ridge_line_jerk:.3f}px/frame exceeds {p95_line_jerk_limit:.3f}px/frame"
        )
    if p95_reference_vertical_delta > p95_reference_vertical_delta_limit:
        failures.append(
            f"ridge minus reference vertical p95 {p95_reference_vertical_delta:.3f}px exceeds {p95_reference_vertical_delta_limit:.3f}px"
        )
    if p95_reference_horizontal_delta > p95_reference_horizontal_delta_limit:
        failures.append(
            f"ridge minus reference horizontal p95 {p95_reference_horizontal_delta:.3f}px exceeds {p95_reference_horizontal_delta_limit:.3f}px"
        )
    if max_run > max_run_limit:
        failures.append(f"ridge residual run {max_run} exceeds {max_run_limit}")
    add_source_ratio_failure(
        "ridge high-frequency residual",
        max_vector,
        "maxHighFrequencyResidualPixels",
        "maxRidgeHighFrequencyResidualSourceRatio",
    )
    add_source_ratio_failure(
        "ridge high-frequency residual p95",
        p95_vector,
        "highFrequencyResidualP95Pixels",
        "maxRidgeHighFrequencyResidualP95SourceRatio",
    )
    add_source_ratio_failure(
        "ridge vertical residual p95",
        p95_vertical,
        "verticalResidualP95Pixels",
        "maxRidgeVerticalResidualP95SourceRatio",
    )
    add_source_ratio_failure(
        "ridge line vertical jerk p95",
        p95_ridge_line_jerk,
        "lineVerticalJerkP95PixelsPerFrame",
        "maxRidgeLineVerticalJerkSourceRatio",
        unit="px/frame",
    )

    summary = {
        "enabled": bool(ridge_rows),
        "rowCount": len(ridge_rows),
        "trackingFrameCount": len(all_tracking_rows),
        "measuredTrackingFrameCount": len(tracking_rows),
        "trackingRatio": tracking_ratio,
        "ptsCadenceExcludedFrameCount": len(pts_cadence_excluded_rows) if exclude_pts_irregular_from_ridge else 0,
        "ptsCadenceExcludedFrameRatio": (
            len(pts_cadence_excluded_rows) / len(all_tracking_rows)
            if exclude_pts_irregular_from_ridge and all_tracking_rows
            else 0.0
        ),
        "rollingMedianWindowSeconds": median_seconds,
        "maxHighFrequencyResidualPixels": max_vector,
        "highFrequencyResidualP95Pixels": p95_vector,
        "verticalResidualP95Pixels": p95_vertical,
        "horizontalResidualP95Pixels": p95_horizontal,
        "lineTrackingFrameCount": len(ridge_line_rows),
        "lineTrackingRatio": (len(ridge_line_rows) / len(tracking_rows)) if tracking_rows else 0.0,
        "lineVerticalResidualP95Pixels": p95_ridge_line_vertical,
        "lineVerticalJerkP95PixelsPerFrame": p95_ridge_line_jerk,
        "referenceTrackingFrameCount": len(ridge_reference_rows),
        "referenceTrackingRatio": (len(ridge_reference_rows) / len(tracking_rows)) if tracking_rows else 0.0,
        "minusReferenceVerticalP95Pixels": p95_reference_vertical_delta,
        "minusReferenceHorizontalP95Pixels": p95_reference_horizontal_delta,
        "maxResidualRunFrames": max_run,
        "thresholds": {
            "minRidgeTrackingRatio": tracking_ratio_limit,
            "maxRidgeHighFrequencyResidualPixels": max_vector_limit,
            "maxRidgeHighFrequencyResidualP95Pixels": p95_vector_limit,
            "maxRidgeVerticalResidualP95Pixels": p95_vertical_limit,
            "maxRidgeLineVerticalResidualP95Pixels": p95_line_vertical_limit,
            "maxRidgeLineVerticalJerkP95PixelsPerFrame": p95_line_jerk_limit,
            "maxRidgeMinusReferenceVerticalP95Pixels": p95_reference_vertical_delta_limit,
            "maxRidgeMinusReferenceHorizontalP95Pixels": p95_reference_horizontal_delta_limit,
            "ridgeResidualRunThresholdPixels": residual_threshold,
            "maxRidgeResidualRunFrames": max_run_limit,
            "maxRidgeHighFrequencyResidualSourceRatio": quality.get("maxRidgeHighFrequencyResidualSourceRatio"),
            "maxRidgeHighFrequencyResidualP95SourceRatio": quality.get("maxRidgeHighFrequencyResidualP95SourceRatio"),
            "maxRidgeVerticalResidualP95SourceRatio": quality.get("maxRidgeVerticalResidualP95SourceRatio"),
            "maxRidgeLineVerticalJerkSourceRatio": quality.get("maxRidgeLineVerticalJerkSourceRatio"),
            "excludePtsIrregularFromRidgeMotion": exclude_pts_irregular_from_ridge,
        },
        "sourceBaseline": source_ridge_baseline,
    }
    return not failures, failures, summary


def finalize_black_edge_transform_rows(
    rows: list[dict[str, Any]],
    quality: dict[str, Any],
    median_window: int,
    pulse_median_window: int,
    pulse_peak_window: int,
) -> None:
    transform_rows = [row for row in rows if bool(row.get("trackingOk"))]
    if not transform_rows:
        return

    for component in ("centerX", "centerY", "scalePercent"):
        medians = rolling_median([float(row.get(component, 0.0)) for row in transform_rows], median_window)
        for row, median in zip(transform_rows, medians):
            row[f"{component}Median"] = median
            row[f"{component}Residual"] = float(row.get(component, 0.0)) - median

    unwrapped_angles = unwrap_angles_degrees([float(row.get("rotationDegrees", 0.0)) for row in transform_rows])
    angle_medians = rolling_median(unwrapped_angles, median_window)
    for row, angle, median in zip(transform_rows, unwrapped_angles, angle_medians):
        row["rotationDegreesUnwrapped"] = angle
        row["rotationMedianDegrees"] = median
        row["rotationResidualDegrees"] = angle_delta_degrees(angle, median)

    for row in transform_rows:
        center_x_residual = float(row.get("centerXResidual", 0.0))
        center_y_residual = float(row.get("centerYResidual", 0.0))
        row["centerResidualPixels"] = math.hypot(center_x_residual, center_y_residual)
        row["scalePulseExcludedForPtsCadence"] = False

    exclude_pts_irregular = bool(
        quality.get(
            "excludePtsIrregularFromBlackEdgeTransform",
            quality.get(
                "excludePtsIrregularFromScalePulse",
                quality.get("excludePtsIrregularFromFrameJump", False),
            ),
        )
    )
    pulse_rows = [
        row
        for row in transform_rows
        if not (exclude_pts_irregular and bool(row.get("ptsCadenceAffectedFrame")))
    ]
    pulse_row_ids = {id(row) for row in pulse_rows}
    for row in transform_rows:
        row["scalePulseExcludedForPtsCadence"] = id(row) not in pulse_row_ids

    pulse_values = [float(row.get("scalePercentResidual", 0.0)) for row in pulse_rows]
    pulse_medians = rolling_median(pulse_values, pulse_median_window)
    previous_pulse_row: dict[str, Any] | None = None
    for row, median in zip(pulse_rows, pulse_medians):
        row["scalePulseMedianPercent"] = median
        row["scalePulseResidualPercent"] = float(row.get("scalePercentResidual", 0.0)) - median
        if previous_pulse_row is not None and int(row.get("previousFrame", -1)) == int(previous_pulse_row.get("frame", -2)):
            row["scalePulseDerivativePercentPerFrame"] = (
                float(row.get("scalePulseResidualPercent", 0.0))
                - float(previous_pulse_row.get("scalePulseResidualPercent", 0.0))
            )
        else:
            row["scalePulseDerivativePercentPerFrame"] = 0.0
        previous_pulse_row = row

    pulse_residuals = [float(row.get("scalePulseResidualPercent", 0.0)) for row in pulse_rows]
    pulse_peak_to_peak = rolling_peak_to_peak(pulse_residuals, pulse_peak_window)
    for row, peak_to_peak in zip(pulse_rows, pulse_peak_to_peak):
        row["scalePulsePeakToPeakPercent"] = peak_to_peak

    previous_row: dict[str, Any] | None = None
    for row in transform_rows:
        if previous_row is None or int(row.get("previousFrame", -1)) != int(previous_row.get("frame", -2)):
            previous_row = row
            continue
        center_jump_x = float(row.get("centerX", 0.0)) - float(previous_row.get("centerX", 0.0))
        center_jump_y = float(row.get("centerY", 0.0)) - float(previous_row.get("centerY", 0.0))
        row["centerJumpX"] = center_jump_x
        row["centerJumpY"] = center_jump_y
        row["centerJumpPixels"] = math.hypot(center_jump_x, center_jump_y)
        row["scaleJumpPercent"] = float(row.get("scalePercent", 0.0)) - float(previous_row.get("scalePercent", 0.0))
        row["rotationJumpDegrees"] = angle_delta_degrees(
            float(row.get("rotationDegreesUnwrapped", row.get("rotationDegrees", 0.0))),
            float(previous_row.get("rotationDegreesUnwrapped", previous_row.get("rotationDegrees", 0.0))),
        )
        previous_row = row


def summarize_black_edge_transform(
    rows: list[dict[str, Any]],
    quality: dict[str, Any],
) -> tuple[bool, list[str], dict[str, Any]]:
    diagnostic_required = bool(quality.get("blackEdgeTransformDiagnostic", False)) or bool(
        quality.get("blackEdgeTransformDiagnosticRequired", False)
    )
    tracking_rows = [row for row in rows if bool(row.get("trackingOk"))]
    valid_ratio = len(tracking_rows) / len(rows) if rows else 0.0
    pulse_rows = [
        row
        for row in tracking_rows
        if not bool(row.get("scalePulseExcludedForPtsCadence"))
    ]
    jump_rows = [row for row in tracking_rows if "centerJumpPixels" in row]
    max_center_jump = max((float(row.get("centerJumpPixels", 0.0)) for row in jump_rows), default=0.0)
    max_center_x_jump = max((abs(float(row.get("centerJumpX", 0.0))) for row in jump_rows), default=0.0)
    max_center_y_jump = max((abs(float(row.get("centerJumpY", 0.0))) for row in jump_rows), default=0.0)
    max_scale_jump = max((abs(float(row.get("scaleJumpPercent", 0.0))) for row in jump_rows), default=0.0)
    max_rotation_jump = max((abs(float(row.get("rotationJumpDegrees", 0.0))) for row in jump_rows), default=0.0)
    rotation_jumps = [abs(float(row.get("rotationJumpDegrees", 0.0))) for row in jump_rows]
    rotation_jump_p95 = (
        float(np.percentile(np.asarray(rotation_jumps, dtype=np.float64), 95))
        if rotation_jumps
        else 0.0
    )
    rotation_residuals = [abs(float(row.get("rotationResidualDegrees", 0.0))) for row in tracking_rows]
    rotation_residual_p95 = (
        float(np.percentile(np.asarray(rotation_residuals, dtype=np.float64), 95))
        if rotation_residuals
        else 0.0
    )
    center_residuals = [float(row.get("centerResidualPixels", 0.0)) for row in tracking_rows]
    center_residual_p95 = (
        float(np.percentile(np.asarray(center_residuals, dtype=np.float64), 95))
        if center_residuals
        else 0.0
    )
    max_scale_pulse_peak_to_peak = max(
        (float(row.get("scalePulsePeakToPeakPercent", 0.0)) for row in pulse_rows),
        default=0.0,
    )
    scale_pulse_derivatives = [
        abs(float(row.get("scalePulseDerivativePercentPerFrame", 0.0)))
        for row in pulse_rows
    ]
    scale_pulse_derivative_p95 = (
        float(np.percentile(np.asarray(scale_pulse_derivatives, dtype=np.float64), 95))
        if scale_pulse_derivatives
        else 0.0
    )
    max_black_outside_ratio = max((float(row.get("blackOutsideRatio", 0.0)) for row in rows), default=0.0)
    max_content_area_ratio = max((float(row.get("contentAreaRatio", 0.0)) for row in tracking_rows), default=0.0)

    min_valid_ratio = float(
        quality.get(
            "minBlackEdgeTransformValidRatio",
            0.50 if diagnostic_required else 0.0,
        )
    )
    center_jump_limit = float(quality.get("maxBlackEdgeTransformCenterJumpPixels", float("inf")))
    center_x_jump_limit = float(quality.get("maxBlackEdgeTransformXJumpPixels", center_jump_limit))
    center_y_jump_limit = float(quality.get("maxBlackEdgeTransformYJumpPixels", center_jump_limit))
    scale_jump_limit = float(quality.get("maxBlackEdgeTransformScaleJumpPercent", float("inf")))
    scale_pulse_peak_to_peak_limit = float(
        quality.get("maxBlackEdgeTransformScalePulsePeakToPeakPercent", float("inf"))
    )
    scale_pulse_derivative_p95_limit = float(
        quality.get("maxBlackEdgeTransformScaleDerivativeP95PercentPerFrame", float("inf"))
    )
    rotation_jump_limit = float(quality.get("maxBlackEdgeTransformRotationJumpDegrees", float("inf")))
    rotation_jump_p95_limit = float(quality.get("maxBlackEdgeTransformRotationJumpP95Degrees", float("inf")))
    rotation_residual_p95_limit = float(
        quality.get("maxBlackEdgeTransformRotationResidualP95Degrees", float("inf"))
    )
    center_residual_p95_limit = float(quality.get("maxBlackEdgeTransformCenterResidualP95Pixels", float("inf")))

    failures: list[str] = []
    if valid_ratio < min_valid_ratio:
        failures.append(f"black-edge transform valid ratio {valid_ratio:.3f} below {min_valid_ratio:.3f}")
    if max_center_jump > center_jump_limit:
        failures.append(
            f"black-edge transform center jump {max_center_jump:.3f}px exceeds {center_jump_limit:.3f}px"
        )
    if max_center_x_jump > center_x_jump_limit:
        failures.append(
            f"black-edge transform x jump {max_center_x_jump:.3f}px exceeds {center_x_jump_limit:.3f}px"
        )
    if max_center_y_jump > center_y_jump_limit:
        failures.append(
            f"black-edge transform y jump {max_center_y_jump:.3f}px exceeds {center_y_jump_limit:.3f}px"
        )
    if max_scale_jump > scale_jump_limit:
        failures.append(
            f"black-edge transform scale jump {max_scale_jump:.3f}% exceeds {scale_jump_limit:.3f}%"
        )
    if max_scale_pulse_peak_to_peak > scale_pulse_peak_to_peak_limit:
        failures.append(
            "black-edge transform scale pulse peak-to-peak "
            f"{max_scale_pulse_peak_to_peak:.3f}% exceeds {scale_pulse_peak_to_peak_limit:.3f}%"
        )
    if scale_pulse_derivative_p95 > scale_pulse_derivative_p95_limit:
        failures.append(
            "black-edge transform scale derivative p95 "
            f"{scale_pulse_derivative_p95:.3f}%/frame exceeds {scale_pulse_derivative_p95_limit:.3f}%/frame"
        )
    if max_rotation_jump > rotation_jump_limit:
        failures.append(
            f"black-edge transform rotation jump {max_rotation_jump:.3f}deg exceeds {rotation_jump_limit:.3f}deg"
        )
    if rotation_jump_p95 > rotation_jump_p95_limit:
        failures.append(
            "black-edge transform rotation jump p95 "
            f"{rotation_jump_p95:.3f}deg exceeds {rotation_jump_p95_limit:.3f}deg"
        )
    if rotation_residual_p95 > rotation_residual_p95_limit:
        failures.append(
            "black-edge transform rotation residual p95 "
            f"{rotation_residual_p95:.3f}deg exceeds {rotation_residual_p95_limit:.3f}deg"
        )
    if center_residual_p95 > center_residual_p95_limit:
        failures.append(
            "black-edge transform center residual p95 "
            f"{center_residual_p95:.3f}px exceeds {center_residual_p95_limit:.3f}px"
        )

    summary = {
        "enabled": diagnostic_required or bool(tracking_rows),
        "required": diagnostic_required,
        "rowCount": len(rows),
        "trackingFrameCount": len(tracking_rows),
        "trackingRatio": valid_ratio,
        "pulseFrameCount": len(pulse_rows),
        "jumpPairCount": len(jump_rows),
        "maxBlackOutsideRatio": max_black_outside_ratio,
        "maxContentAreaRatio": max_content_area_ratio,
        "maxCenterJumpPixels": max_center_jump,
        "maxXJumpPixels": max_center_x_jump,
        "maxYJumpPixels": max_center_y_jump,
        "centerResidualP95Pixels": center_residual_p95,
        "maxScaleJumpPercent": max_scale_jump,
        "maxScalePulsePeakToPeakPercent": max_scale_pulse_peak_to_peak,
        "scaleDerivativeP95PercentPerFrame": scale_pulse_derivative_p95,
        "maxRotationJumpDegrees": max_rotation_jump,
        "rotationJumpP95Degrees": rotation_jump_p95,
        "rotationResidualP95Degrees": rotation_residual_p95,
        "thresholds": {
            "minBlackEdgeTransformValidRatio": min_valid_ratio,
            "maxBlackEdgeTransformCenterJumpPixels": center_jump_limit,
            "maxBlackEdgeTransformXJumpPixels": center_x_jump_limit,
            "maxBlackEdgeTransformYJumpPixels": center_y_jump_limit,
            "maxBlackEdgeTransformScaleJumpPercent": scale_jump_limit,
            "maxBlackEdgeTransformScalePulsePeakToPeakPercent": scale_pulse_peak_to_peak_limit,
            "maxBlackEdgeTransformScaleDerivativeP95PercentPerFrame": scale_pulse_derivative_p95_limit,
            "maxBlackEdgeTransformRotationJumpDegrees": rotation_jump_limit,
            "maxBlackEdgeTransformRotationJumpP95Degrees": rotation_jump_p95_limit,
            "maxBlackEdgeTransformRotationResidualP95Degrees": rotation_residual_p95_limit,
            "maxBlackEdgeTransformCenterResidualP95Pixels": center_residual_p95_limit,
            "minBlackEdgeOutsideRatio": quality.get("minBlackEdgeOutsideRatio", 0.002),
            "minBlackEdgeTransformContentAreaRatio": quality.get("minBlackEdgeTransformContentAreaRatio", 0.10),
            "excludePtsIrregularFromBlackEdgeTransform": quality.get(
                "excludePtsIrregularFromBlackEdgeTransform",
                quality.get(
                    "excludePtsIrregularFromScalePulse",
                    quality.get("excludePtsIrregularFromFrameJump", False),
                ),
            ),
        },
    }
    return not failures, failures, summary


def write_csv(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    rows = list(rows)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    fieldnames: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def probe_pts_timing(video_path: Path, tolerance_ratio: float) -> dict[str, Any]:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "frame=best_effort_timestamp_time",
        "-of",
        "csv=p=0",
        str(video_path),
    ]
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True)
    except FileNotFoundError:
        return {"summary": {"available": False, "reason": "ffprobe_not_found"}}

    if result.returncode != 0:
        return {
            "summary": {
                "available": False,
                "reason": "ffprobe_failed",
                "stderr": result.stderr.strip()[:500],
            }
        }

    timestamps: list[float] = []
    for line in result.stdout.splitlines():
        value = line.strip().split(",", 1)[0]
        if not value:
            continue
        try:
            timestamps.append(float(value))
        except ValueError:
            continue

    if len(timestamps) < 2:
        return {
            "summary": {
                "available": False,
                "reason": "insufficient_pts_frames",
                "ptsFrameCount": len(timestamps),
            }
        }

    intervals = [b - a for a, b in zip(timestamps, timestamps[1:]) if b >= a]
    if not intervals:
        return {
            "summary": {
                "available": False,
                "reason": "no_positive_pts_intervals",
                "ptsFrameCount": len(timestamps),
            }
        }

    median_interval = float(np.median(np.asarray(intervals, dtype=np.float64)))
    tolerance = max(0.0, median_interval * tolerance_ratio)
    irregular_frame_indexes: set[int] = set()
    irregular_intervals: list[float] = []
    for interval_index, interval in enumerate(intervals):
        if abs(float(interval) - median_interval) > tolerance:
            irregular_frame_indexes.add(interval_index + 1)
            irregular_intervals.append(float(interval))
    return {
        "summary": {
            "available": True,
            "ptsFrameCount": len(timestamps),
            "ptsIntervalCount": len(intervals),
            "medianPtsIntervalSeconds": median_interval,
            "maxPtsIntervalSeconds": max(intervals),
            "ptsIntervalToleranceRatio": tolerance_ratio,
            "ptsIntervalIrregularCount": len(irregular_intervals),
            "ptsIntervalIrregularRatio": len(irregular_intervals) / len(intervals),
        },
        "timestamps": timestamps,
        "intervals": intervals,
        "irregularFrameIndexes": irregular_frame_indexes,
    }


def probe_pts_interval_metrics(video_path: Path, tolerance_ratio: float) -> dict[str, Any]:
    return dict(probe_pts_timing(video_path, tolerance_ratio).get("summary", {}))


def pts_interval_for_sample(
    pts_timing: dict[str, Any],
    previous_frame_index: int,
    frame_index: int,
) -> dict[str, Any]:
    summary = pts_timing.get("summary", {})
    timestamps = pts_timing.get("timestamps", [])
    if (
        not bool(summary.get("available"))
        or previous_frame_index < 0
        or frame_index <= previous_frame_index
        or frame_index >= len(timestamps)
        or previous_frame_index >= len(timestamps)
    ):
        return {
            "ptsTimeSeconds": "",
            "previousPtsTimeSeconds": "",
            "ptsIntervalSeconds": "",
            "ptsIntervalExpectedSeconds": "",
            "ptsIntervalIrregularFrame": False,
        }

    median_interval = float(summary.get("medianPtsIntervalSeconds", 0.0))
    tolerance_ratio = float(summary.get("ptsIntervalToleranceRatio", 0.0))
    frame_delta = max(1, frame_index - previous_frame_index)
    interval = float(timestamps[frame_index]) - float(timestamps[previous_frame_index])
    expected = median_interval * frame_delta
    tolerance = max(0.0, expected * tolerance_ratio)
    irregular = abs(interval - expected) > tolerance
    return {
        "ptsTimeSeconds": float(timestamps[frame_index]),
        "previousPtsTimeSeconds": float(timestamps[previous_frame_index]),
        "ptsIntervalSeconds": interval,
        "ptsIntervalExpectedSeconds": expected,
        "ptsIntervalIrregularFrame": irregular,
    }


def put_label_lines(frame: np.ndarray, lines: list[str], x: int = 10, y: int = 24) -> None:
    if not lines:
        return
    line_height = 22
    max_lines = min(len(lines), 8)
    clean_lines = [line[:96] for line in lines[:max_lines]]
    text_width = 0
    for line in clean_lines:
        size, _baseline = cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
        text_width = max(text_width, size[0])
    box_width = min(frame.shape[1], x + text_width + 18)
    box_height = min(frame.shape[0], y + (line_height * max_lines) + 8)
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (box_width, box_height), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.58, frame, 0.42, 0, frame)
    for line_index, line in enumerate(clean_lines):
        baseline_y = y + (line_index * line_height)
        cv2.putText(
            frame,
            line,
            (x, baseline_y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            frame,
            line,
            (x, baseline_y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )


def merged_spike_frames(spike_frames: list[tuple[int, str]]) -> list[tuple[int, str]]:
    labels_by_frame: dict[int, list[str]] = {}
    order: list[int] = []
    for frame_index, label in spike_frames:
        if frame_index not in labels_by_frame:
            labels_by_frame[frame_index] = []
            order.append(frame_index)
        if label not in labels_by_frame[frame_index]:
            labels_by_frame[frame_index].append(label)
    return [
        (frame_index, " | ".join(labels_by_frame[frame_index][:3]))
        for frame_index in order
    ]


def write_contact_sheet(
    video_path: Path,
    output_path: Path,
    viewer_roi: Roi,
    spike_frames: list[tuple[int, str]],
) -> bool:
    if not spike_frames:
        return False

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False

    tiles: list[np.ndarray] = []
    for frame_index, label in spike_frames:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok:
            continue
        tile = crop(frame, viewer_roi)
        tile = cv2.resize(tile, (360, 193), interpolation=cv2.INTER_AREA)
        put_label_lines(tile, label.split(" | "))
        tiles.append(tile)
    cap.release()

    if not tiles:
        return False
    cols = 4
    rows = math.ceil(len(tiles) / cols)
    blank = np.zeros_like(tiles[0])
    while len(tiles) < rows * cols:
        tiles.append(blank.copy())
    sheet_rows = []
    for row_index in range(rows):
        start = row_index * cols
        sheet_rows.append(np.hstack(tiles[start : start + cols]))
    cv2.imwrite(str(output_path), np.vstack(sheet_rows))
    return True


def row_by_frame(rows: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for row in rows:
        try:
            result[int(row.get("frame", -1))] = row
        except (TypeError, ValueError):
            continue
    return result


def write_diagnostic_overlay_video(
    video_path: Path,
    output_path: Path,
    viewer_roi: Roi,
    scale_rows: list[dict[str, Any]],
    edge_rows: list[dict[str, Any]],
    ridge_rows: list[dict[str, Any]],
    black_edge_transform_rows: list[dict[str, Any]],
    fps: float,
) -> bool:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False
    writer_fps = fps if fps > 1.0 and math.isfinite(fps) else 30.0
    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        writer_fps,
        (viewer_roi[2], viewer_roi[3]),
    )
    if not writer.isOpened():
        cap.release()
        return False

    scale_by_frame = row_by_frame(scale_rows)
    edge_by_frame = row_by_frame(edge_rows)
    ridge_by_frame = row_by_frame(ridge_rows)
    black_edge_transform_by_frame = row_by_frame(black_edge_transform_rows)
    frame_index = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        viewer = crop(frame, viewer_roi).copy()
        timestamp = frame_index / writer_fps
        lines = [f"f={frame_index} t={timestamp:.2f}s"]
        scale_row = scale_by_frame.get(frame_index)
        if scale_row is not None:
            lines.append(
                "scale "
                f"res={float(scale_row.get('scaleResidualPercent', 0.0)):+.3f}% "
                f"pulse={float(scale_row.get('scalePulseResidualPercent', 0.0)):+.3f}%"
            )
            if "frameJumpPixels" in scale_row:
                lines.append(
                    "jump "
                    f"x={float(scale_row.get('frameJumpX', 0.0)):+.2f}px "
                    f"y={float(scale_row.get('frameJumpY', 0.0)):+.2f}px"
                )
            flags: list[str] = []
            if bool(scale_row.get("nearDuplicateFrame")):
                flags.append("dup")
            if bool(scale_row.get("cadenceHoldFrame")):
                flags.append("hold")
            if bool(scale_row.get("frameJumpSkippedForCadence")):
                flags.append("jump-skip")
            if bool(scale_row.get("ptsIntervalIrregularFrame")):
                flags.append("pts-gap")
            if bool(scale_row.get("frameJumpSkippedForPtsCadence")):
                flags.append("pts-jump-skip")
            if bool(scale_row.get("scalePulseExcludedForPtsCadence")):
                flags.append("pts-pulse-skip")
            if flags:
                lines.append("flags " + ",".join(flags))
            pts_interval = scale_row.get("ptsIntervalSeconds")
            if isinstance(pts_interval, (int, float)) and math.isfinite(float(pts_interval)):
                lines.append(f"pts dt={float(pts_interval):.4f}s")
        ridge_row = ridge_by_frame.get(frame_index)
        if ridge_row is not None and bool(ridge_row.get("trackingOk")):
            lines.append(
                "ridge "
                f"hf={float(ridge_row.get('ridgeHighFrequencyResidualPixels', 0.0)):.3f}px "
                f"v={float(ridge_row.get('ridgeVerticalResidualPixels', 0.0)):.3f}px"
            )
            if "ridgeLineVerticalResidualPixels" in ridge_row:
                lines.append(
                    "ridge-line "
                    f"v={float(ridge_row.get('ridgeLineVerticalResidualPixels', 0.0)):.3f}px "
                    f"jerk={float(ridge_row.get('ridgeLineVerticalJerkPixelsPerFrame', 0.0)):+.3f}px/f"
                )
            if bool(ridge_row.get("ridgeReferenceTrackingOk")):
                lines.append(
                    "ridge-ref "
                    f"dx={float(ridge_row.get('ridgeMinusReferenceDx', 0.0)):+.2f}px "
                    f"dy={float(ridge_row.get('ridgeMinusReferenceDy', 0.0)):+.2f}px"
                )
        edge_row = edge_by_frame.get(frame_index)
        if edge_row is not None:
            lines.append(
                f"edge={float(edge_row.get('edgeResidualPx', 0.0)):.1f}px "
                f"margin={float(edge_row.get('edgeMarginPx', 0.0)):.1f}px"
            )
        black_edge_transform_row = black_edge_transform_by_frame.get(frame_index)
        if black_edge_transform_row is not None and bool(black_edge_transform_row.get("trackingOk")):
            lines.append(
                "black-xform "
                f"jump={float(black_edge_transform_row.get('centerJumpPixels', 0.0)):.2f}px "
                f"scale={float(black_edge_transform_row.get('scalePulseResidualPercent', 0.0)):+.3f}% "
                f"rot={float(black_edge_transform_row.get('rotationJumpDegrees', 0.0)):+.3f}deg"
            )
        put_label_lines(viewer, lines)
        writer.write(viewer)

    writer.release()
    cap.release()
    return True


def summarize_failures(
    scale_rows: list[dict[str, Any]],
    edge_rows: list[dict[str, Any]],
    quality: dict[str, Any],
    source_baseline: dict[str, Any] | None = None,
) -> tuple[bool, list[str], dict[str, Any]]:
    scale_quality_rows = [
        row
        for row in scale_rows
        if bool(row.get("scaleQualityOk", row.get("trackingOk")))
    ]
    max_scale = max((abs(float(row.get("scaleResidualPercent", 0.0))) for row in scale_quality_rows), default=0.0)
    max_edge = max((float(row.get("edgeResidualPx", 0.0)) for row in edge_rows), default=0.0)
    max_edge_margin = max((float(row.get("edgeMarginPx", 0.0)) for row in edge_rows), default=0.0)
    low_inlier_rows = [row for row in scale_rows if not bool(row.get("trackingOk"))]
    low_inlier_ratio = (len(low_inlier_rows) / len(scale_rows)) if scale_rows else 1.0
    scale_quality_ratio = (len(scale_quality_rows) / len(scale_rows)) if scale_rows else 0.0
    max_jump_x = 0.0
    max_jump_y = 0.0
    max_jump_vector = 0.0
    max_jump_frame = None
    max_jump_time = None
    jump_pair_count = 0
    jump_pair_skipped_for_cadence = 0
    jump_pair_skipped_for_pts_cadence = 0
    duplicate_like_rows = [
        row
        for row in scale_rows
        if bool(row.get("nearDuplicateFrame"))
    ]
    duplicate_like_ratio = (len(duplicate_like_rows) / len(scale_rows)) if scale_rows else 0.0
    max_duplicate_run = 0
    duplicate_run = 0
    cadence_hold_rows = [
        row
        for row in scale_rows
        if bool(row.get("cadenceHoldFrame"))
    ]
    cadence_hold_ratio = (len(cadence_hold_rows) / len(scale_rows)) if scale_rows else 0.0
    pts_irregular_rows = [
        row
        for row in scale_rows
        if bool(row.get("ptsIntervalIrregularFrame"))
    ]
    pts_irregular_ratio = (len(pts_irregular_rows) / len(scale_rows)) if scale_rows else 0.0
    scale_pulse_pts_excluded_rows = [
        row
        for row in scale_rows
        if bool(row.get("scalePulseExcludedForPtsCadence"))
    ]
    scale_pulse_pts_excluded_ratio = (
        len(scale_pulse_pts_excluded_rows) / len(scale_rows) if scale_rows else 0.0
    )
    max_cadence_hold_run = 0
    cadence_hold_run = 0
    cumulative_zoom_rows = [
        row
        for row in scale_quality_rows
        if bool(row.get("cumulativeScalePathOk"))
    ]
    cumulative_zoom_values = [float(row.get("cumulativeScalePercent", 0.0)) for row in cumulative_zoom_rows]
    max_cumulative_zoom_in = max(cumulative_zoom_values, default=0.0)
    max_cumulative_zoom_range = (
        max(cumulative_zoom_values) - min(cumulative_zoom_values)
        if cumulative_zoom_values
        else 0.0
    )
    max_scale_pulse_peak_to_peak = max(
        (float(row.get("scalePulsePeakToPeakPercent", 0.0)) for row in cumulative_zoom_rows),
        default=0.0,
    )
    scale_pulse_derivatives = [
        abs(float(row.get("scalePulseDerivativePercentPerFrame", 0.0)))
        for row in cumulative_zoom_rows
    ]
    scale_pulse_derivative_p95 = (
        float(np.percentile(np.asarray(scale_pulse_derivatives, dtype=np.float64), 95))
        if scale_pulse_derivatives
        else 0.0
    )
    max_scale_pulse_residual = max(
        (abs(float(row.get("scalePulseResidualPercent", 0.0))) for row in cumulative_zoom_rows),
        default=0.0,
    )
    scale_pulse_run_threshold = float(quality.get("scalePulseRunThresholdPercent", float("inf")))
    scale_pulse_rows = [
        row
        for row in cumulative_zoom_rows
        if abs(float(row.get("scalePulseResidualPercent", 0.0))) > scale_pulse_run_threshold
    ]
    scale_pulse_frame_ratio = (
        len(scale_pulse_rows) / len(cumulative_zoom_rows)
        if cumulative_zoom_rows
        else 0.0
    )
    max_scale_pulse_run = 0
    scale_pulse_run = 0
    exclude_cadence_hold_from_jump = bool(quality.get("excludeCadenceHoldFromFrameJump", False))
    exclude_pts_irregular_from_jump = bool(
        quality.get("excludePtsIrregularFromFrameJump", exclude_cadence_hold_from_jump)
    )
    previous_row: dict[str, Any] | None = None
    for row in sorted(scale_rows, key=lambda item: int(item.get("frame", 0))):
        is_adjacent_sample = False
        if previous_row is not None:
            try:
                is_adjacent_sample = int(row.get("previousFrame", -1)) == int(previous_row.get("frame", -2))
            except (TypeError, ValueError):
                is_adjacent_sample = False
        if bool(row.get("nearDuplicateFrame")):
            duplicate_run = duplicate_run + 1 if previous_row is None or is_adjacent_sample else 1
            max_duplicate_run = max(max_duplicate_run, duplicate_run)
        else:
            duplicate_run = 0
        if bool(row.get("cadenceHoldFrame")):
            cadence_hold_run = cadence_hold_run + 1 if previous_row is None or is_adjacent_sample else 1
            max_cadence_hold_run = max(max_cadence_hold_run, cadence_hold_run)
        else:
            cadence_hold_run = 0
        if abs(float(row.get("scalePulseResidualPercent", 0.0))) > scale_pulse_run_threshold:
            scale_pulse_run = scale_pulse_run + 1 if previous_row is None or is_adjacent_sample else 1
            max_scale_pulse_run = max(max_scale_pulse_run, scale_pulse_run)
        else:
            scale_pulse_run = 0
        row_quality_ok = bool(row.get("scaleQualityOk", row.get("trackingOk")))
        if previous_row is not None and row_quality_ok and bool(previous_row.get("scaleQualityOk", previous_row.get("trackingOk"))):
            if is_adjacent_sample:
                cadence_pair = bool(row.get("cadenceHoldFrame")) or bool(previous_row.get("cadenceHoldFrame"))
                pts_irregular_pair = bool(row.get("ptsCadenceAffectedFrame")) or bool(
                    previous_row.get("ptsCadenceAffectedFrame")
                )
                skip_cadence_pair = exclude_cadence_hold_from_jump and cadence_pair
                skip_pts_pair = exclude_pts_irregular_from_jump and pts_irregular_pair
                if skip_cadence_pair or skip_pts_pair:
                    row["frameJumpSkippedForCadence"] = True
                    row["frameJumpSkippedForPtsCadence"] = skip_pts_pair
                    if skip_cadence_pair:
                        jump_pair_skipped_for_cadence += 1
                    if skip_pts_pair:
                        jump_pair_skipped_for_pts_cadence += 1
                    previous_row = row
                    continue
                jump_x = float(row.get("dx", 0.0)) - float(previous_row.get("dx", 0.0))
                jump_y = float(row.get("dy", 0.0)) - float(previous_row.get("dy", 0.0))
                jump_vector = math.hypot(jump_x, jump_y)
                row["frameJumpX"] = jump_x
                row["frameJumpY"] = jump_y
                row["frameJumpPixels"] = jump_vector
                jump_pair_count += 1
                if abs(jump_x) > max_jump_x:
                    max_jump_x = abs(jump_x)
                if abs(jump_y) > max_jump_y:
                    max_jump_y = abs(jump_y)
                if jump_vector > max_jump_vector:
                    max_jump_vector = jump_vector
                    max_jump_frame = int(row.get("frame", 0))
                    max_jump_time = float(row.get("time", 0.0))
        previous_row = row

    scale_limit = float(quality.get("maxScaleResidualPercent", 0.85))
    edge_limit = float(quality.get("maxBlackEdgeResidualPixels", 18.0))
    edge_margin_limit = float(quality.get("maxBlackEdgeMarginPixels", float("inf")))
    low_inlier_limit = float(quality.get("maxLowInlierRatio", 0.1))
    scale_quality_limit = float(quality.get("minScaleQualityRatio", 0.5))
    jump_vector_limit = float(quality.get("maxFrameTranslationJumpPixels", float("inf")))
    jump_x_limit = float(quality.get("maxFrameXJumpPixels", jump_vector_limit))
    jump_y_limit = float(quality.get("maxFrameYJumpPixels", jump_vector_limit))
    duplicate_like_ratio_limit = float(quality.get("maxNearDuplicateFrameRatio", float("inf")))
    duplicate_run_limit = int(quality.get("maxNearDuplicateRunFrames", 2**31 - 1))
    cadence_hold_ratio_limit = float(quality.get("maxCadenceHoldFrameRatio", float("inf")))
    cadence_hold_run_limit = int(quality.get("maxCadenceHoldRunFrames", 2**31 - 1))
    operation_duplicate_like_ratio_limit = float(quality.get("maxOperationNearDuplicateFrameRatio", 0.90))
    operation_cadence_hold_ratio_limit = float(quality.get("maxOperationCadenceHoldFrameRatio", 0.90))
    cumulative_zoom_in_limit = float(quality.get("maxCumulativeZoomInPercent", float("inf")))
    cumulative_zoom_range_limit = float(quality.get("maxCumulativeZoomRangePercent", float("inf")))
    scale_pulse_peak_to_peak_limit = float(quality.get("maxScalePulsePeakToPeakPercent", float("inf")))
    scale_pulse_derivative_p95_limit = float(quality.get("maxScalePulseDerivativeP95PercentPerFrame", float("inf")))
    scale_pulse_run_limit = int(quality.get("maxScalePulseRunFrames", 2**31 - 1))
    scale_pulse_frame_ratio_limit = float(quality.get("maxScalePulseFrameRatio", float("inf")))

    failures: list[str] = []
    operation_failures: list[str] = []
    source_baseline = source_baseline or {}

    def add_source_ratio_failure(
        label: str,
        value: float,
        baseline_key: str,
        ratio_key: str,
        unit: str = "",
    ) -> None:
        if ratio_key not in quality:
            return
        baseline_value = source_baseline.get(baseline_key)
        if not isinstance(baseline_value, (int, float)) or not math.isfinite(float(baseline_value)):
            return
        baseline_float = float(baseline_value)
        if baseline_float <= 0.0:
            return
        ratio_limit = float(quality[ratio_key])
        source_limit = baseline_float * ratio_limit
        if value > source_limit:
            failures.append(
                f"{label} {value:.3f}{unit} exceeds source baseline "
                f"{baseline_float:.3f}{unit} * {ratio_limit:.3f} = {source_limit:.3f}{unit}"
            )

    if not scale_rows:
        operation_failures.append("no scale-analysis frames were produced from the recording")
    elif duplicate_like_ratio >= operation_duplicate_like_ratio_limit:
        operation_failures.append(
            "recording appears static or unloaded: "
            f"near-duplicate frame ratio {duplicate_like_ratio:.3f} >= {operation_duplicate_like_ratio_limit:.3f}"
        )
    if scale_rows and cadence_hold_ratio >= operation_cadence_hold_ratio_limit:
        operation_failures.append(
            "recording cadence appears held/static: "
            f"cadence-hold frame ratio {cadence_hold_ratio:.3f} >= {operation_cadence_hold_ratio_limit:.3f}"
        )
    failures.extend(f"operation failure: {item}" for item in operation_failures)

    if max_scale > scale_limit:
        failures.append(f"scale residual {max_scale:.3f}% exceeds {scale_limit:.3f}%")
    if max_edge > edge_limit:
        failures.append(f"black-edge residual {max_edge:.1f}px exceeds {edge_limit:.1f}px")
    if max_edge_margin > edge_margin_limit:
        failures.append(f"black-edge margin {max_edge_margin:.1f}px exceeds {edge_margin_limit:.1f}px")
    if max_jump_vector > jump_vector_limit:
        failures.append(f"frame translation jump {max_jump_vector:.3f}px exceeds {jump_vector_limit:.3f}px")
    if max_jump_x > jump_x_limit:
        failures.append(f"frame x jump {max_jump_x:.3f}px exceeds {jump_x_limit:.3f}px")
    if max_jump_y > jump_y_limit:
        failures.append(f"frame y jump {max_jump_y:.3f}px exceeds {jump_y_limit:.3f}px")
    if duplicate_like_ratio > duplicate_like_ratio_limit:
        failures.append(f"near-duplicate frame ratio {duplicate_like_ratio:.3f} exceeds {duplicate_like_ratio_limit:.3f}")
    if max_duplicate_run > duplicate_run_limit:
        failures.append(f"near-duplicate frame run {max_duplicate_run} exceeds {duplicate_run_limit}")
    if cadence_hold_ratio > cadence_hold_ratio_limit:
        failures.append(f"cadence-hold frame ratio {cadence_hold_ratio:.3f} exceeds {cadence_hold_ratio_limit:.3f}")
    if max_cadence_hold_run > cadence_hold_run_limit:
        failures.append(f"cadence-hold frame run {max_cadence_hold_run} exceeds {cadence_hold_run_limit}")
    if max_cumulative_zoom_in > cumulative_zoom_in_limit:
        failures.append(
            "cumulative zoom-in "
            f"{max_cumulative_zoom_in:.3f}% exceeds {cumulative_zoom_in_limit:.3f}%"
        )
    if max_cumulative_zoom_range > cumulative_zoom_range_limit:
        failures.append(
            "cumulative zoom range "
            f"{max_cumulative_zoom_range:.3f}% exceeds {cumulative_zoom_range_limit:.3f}%"
        )
    if max_scale_pulse_peak_to_peak > scale_pulse_peak_to_peak_limit:
        failures.append(
            "scale pulse peak-to-peak "
            f"{max_scale_pulse_peak_to_peak:.3f}% exceeds {scale_pulse_peak_to_peak_limit:.3f}%"
        )
    if scale_pulse_derivative_p95 > scale_pulse_derivative_p95_limit:
        failures.append(
            "scale pulse derivative p95 "
            f"{scale_pulse_derivative_p95:.3f}%/frame exceeds {scale_pulse_derivative_p95_limit:.3f}%/frame"
        )
    if max_scale_pulse_run > scale_pulse_run_limit:
        failures.append(f"scale pulse run {max_scale_pulse_run} exceeds {scale_pulse_run_limit}")
    if scale_pulse_frame_ratio > scale_pulse_frame_ratio_limit:
        failures.append(
            "scale pulse frame ratio "
            f"{scale_pulse_frame_ratio:.3f} exceeds {scale_pulse_frame_ratio_limit:.3f}"
        )
    if low_inlier_ratio > low_inlier_limit:
        failures.append(f"low tracking ratio {low_inlier_ratio:.3f} exceeds {low_inlier_limit:.3f}")
    if scale_quality_ratio < scale_quality_limit:
        failures.append(f"scale quality ratio {scale_quality_ratio:.3f} below {scale_quality_limit:.3f}")
    add_source_ratio_failure(
        "frame translation jump",
        max_jump_vector,
        "maxFrameTranslationJumpPixels",
        "maxFrameTranslationJumpSourceRatio",
        unit="px",
    )
    add_source_ratio_failure(
        "frame x jump",
        max_jump_x,
        "maxFrameXJumpPixels",
        "maxFrameXJumpSourceRatio",
        unit="px",
    )
    add_source_ratio_failure(
        "frame y jump",
        max_jump_y,
        "maxFrameYJumpPixels",
        "maxFrameYJumpSourceRatio",
        unit="px",
    )
    add_source_ratio_failure(
        "cumulative zoom-in",
        max_cumulative_zoom_in,
        "maxCumulativeZoomInPercent",
        "maxCumulativeZoomInSourceRatio",
        unit="%",
    )
    add_source_ratio_failure(
        "cumulative zoom range",
        max_cumulative_zoom_range,
        "maxCumulativeZoomRangePercent",
        "maxCumulativeZoomRangeSourceRatio",
        unit="%",
    )
    add_source_ratio_failure(
        "scale pulse peak-to-peak",
        max_scale_pulse_peak_to_peak,
        "maxScalePulsePeakToPeakPercent",
        "maxScalePulsePeakToPeakSourceRatio",
        unit="%",
    )
    add_source_ratio_failure(
        "scale pulse derivative p95",
        scale_pulse_derivative_p95,
        "maxScalePulseDerivativeP95PercentPerFrame",
        "maxScalePulseDerivativeP95SourceRatio",
        unit="%/frame",
    )

    summary = {
        "maxAbsScaleResidualPercent": max_scale,
        "maxBlackEdgeResidualPixels": max_edge,
        "maxBlackEdgeMarginPixels": max_edge_margin,
        "maxFrameTranslationJumpPixels": max_jump_vector,
        "maxFrameXJumpPixels": max_jump_x,
        "maxFrameYJumpPixels": max_jump_y,
        "maxFrameJumpFrame": max_jump_frame,
        "maxFrameJumpTimeSeconds": max_jump_time,
        "frameJumpPairCount": jump_pair_count,
        "frameJumpPairSkippedForCadenceCount": jump_pair_skipped_for_cadence,
        "frameJumpPairSkippedForPtsCadenceCount": jump_pair_skipped_for_pts_cadence,
        "nearDuplicateFrameCount": len(duplicate_like_rows),
        "nearDuplicateFrameRatio": duplicate_like_ratio,
        "maxNearDuplicateRunFrames": max_duplicate_run,
        "cadenceHoldFrameCount": len(cadence_hold_rows),
        "cadenceHoldFrameRatio": cadence_hold_ratio,
        "ptsIrregularScaleFrameCount": len(pts_irregular_rows),
        "ptsIrregularScaleFrameRatio": pts_irregular_ratio,
        "scalePulsePtsCadenceExcludedFrameCount": len(scale_pulse_pts_excluded_rows),
        "scalePulsePtsCadenceExcludedFrameRatio": scale_pulse_pts_excluded_ratio,
        "maxCadenceHoldRunFrames": max_cadence_hold_run,
        "maxCumulativeZoomInPercent": max_cumulative_zoom_in,
        "maxCumulativeZoomRangePercent": max_cumulative_zoom_range,
        "maxScalePulsePeakToPeakPercent": max_scale_pulse_peak_to_peak,
        "maxScalePulseDerivativeP95PercentPerFrame": scale_pulse_derivative_p95,
        "maxScalePulseResidualPercent": max_scale_pulse_residual,
        "scalePulseFrameCount": len(scale_pulse_rows),
        "scalePulseFrameRatio": scale_pulse_frame_ratio,
        "maxScalePulseRunFrames": max_scale_pulse_run,
        "cumulativeScalePathFrameCount": len(cumulative_zoom_rows),
        "lowTrackingRatio": low_inlier_ratio,
        "scaleQualityRatio": scale_quality_ratio,
        "scaleFrameCount": len(scale_rows),
        "scaleQualityFrameCount": len(scale_quality_rows),
        "edgeFrameCount": len(edge_rows),
        "operationFailure": bool(operation_failures),
        "operationFailures": operation_failures,
        "thresholds": {
            "maxScaleResidualPercent": scale_limit,
            "maxBlackEdgeResidualPixels": edge_limit,
            "maxBlackEdgeMarginPixels": edge_margin_limit,
            "maxFrameTranslationJumpPixels": jump_vector_limit,
            "maxFrameXJumpPixels": jump_x_limit,
            "maxFrameYJumpPixels": jump_y_limit,
            "maxNearDuplicateFrameRatio": duplicate_like_ratio_limit,
            "maxNearDuplicateRunFrames": duplicate_run_limit,
            "maxCadenceHoldFrameRatio": cadence_hold_ratio_limit,
            "maxCadenceHoldRunFrames": cadence_hold_run_limit,
            "maxOperationNearDuplicateFrameRatio": operation_duplicate_like_ratio_limit,
            "maxOperationCadenceHoldFrameRatio": operation_cadence_hold_ratio_limit,
            "maxCumulativeZoomInPercent": cumulative_zoom_in_limit,
            "maxCumulativeZoomRangePercent": cumulative_zoom_range_limit,
            "maxScalePulsePeakToPeakPercent": scale_pulse_peak_to_peak_limit,
            "maxScalePulseDerivativeP95PercentPerFrame": scale_pulse_derivative_p95_limit,
            "scalePulseRunThresholdPercent": scale_pulse_run_threshold,
            "maxScalePulseRunFrames": scale_pulse_run_limit,
            "maxScalePulseFrameRatio": scale_pulse_frame_ratio_limit,
            "maxLowInlierRatio": low_inlier_limit,
            "minScaleQualityRatio": scale_quality_limit,
            "maxFrameTranslationJumpSourceRatio": quality.get("maxFrameTranslationJumpSourceRatio"),
            "maxFrameXJumpSourceRatio": quality.get("maxFrameXJumpSourceRatio"),
            "maxFrameYJumpSourceRatio": quality.get("maxFrameYJumpSourceRatio"),
            "maxCumulativeZoomInSourceRatio": quality.get("maxCumulativeZoomInSourceRatio"),
            "maxCumulativeZoomRangeSourceRatio": quality.get("maxCumulativeZoomRangeSourceRatio"),
            "maxScalePulsePeakToPeakSourceRatio": quality.get("maxScalePulsePeakToPeakSourceRatio"),
            "maxScalePulseDerivativeP95SourceRatio": quality.get("maxScalePulseDerivativeP95SourceRatio"),
            "excludePtsIrregularFromFrameJump": quality.get(
                "excludePtsIrregularFromFrameJump",
                quality.get("excludeCadenceHoldFromFrameJump", False),
            ),
            "excludePtsIrregularFromScalePulse": quality.get(
                "excludePtsIrregularFromScalePulse",
                quality.get("excludePtsIrregularFromFrameJump", False),
            ),
        },
        "sourceBaseline": source_baseline,
    }
    return not failures, failures, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True, type=Path, help="E2E case JSON file.")
    parser.add_argument("--video", required=True, type=Path, help="FCP Viewer screen recording.")
    parser.add_argument("--viewer-roi", help="Override absolute viewer ROI as x,y,w,h.")
    parser.add_argument("--output-dir", type=Path, help="Directory for JSON/CSV/PNG diagnostics.")
    parser.add_argument("--sample-fps", type=float, help="Override analysis sample rate.")
    parser.add_argument(
        "--visual-review",
        choices=("passed", "failed", "not-reviewed"),
        default=os.environ.get("STABILIZER_E2E_VISUAL_REVIEW", "not-reviewed"),
        help=(
            "Result of human visual review of the recorded FCP Preview video. "
            "Required cases fail acceptance until this is passed."
        ),
    )
    args = parser.parse_args()

    if not args.case.is_file():
        fail(f"case file does not exist: {args.case}")
    if not args.video.is_file():
        fail(f"video file does not exist: {args.video}")

    case = json.loads(args.case.read_text(encoding="utf-8"))
    quality = dict(case.get("quality", {}))
    source_baseline = case.get("sourceBaseline", {})
    case_viewer_roi = roi_from_case(case["viewerRoi"], "viewerRoi")
    viewer_roi = parse_roi(args.viewer_roi) if args.viewer_roi else case_viewer_roi
    content_roi = scale_roi_to_viewer(
        roi_from_case(case["contentRoi"], "contentRoi"),
        case_viewer_roi,
        viewer_roi,
        "content",
    )
    ridge_roi = (
        scale_roi_to_viewer(roi_from_case(case["ridgeRoi"], "ridgeRoi"), case_viewer_roi, viewer_roi, "ridge")
        if "ridgeRoi" in case
        else None
    )
    ridge_reference_roi = (
        scale_roi_to_viewer(
            roi_from_case(case["ridgeReferenceRoi"], "ridgeReferenceRoi"),
            case_viewer_roi,
            viewer_roi,
            "ridgeReference",
        )
        if "ridgeReferenceRoi" in case
        else derive_ridge_reference_roi(content_roi, ridge_roi) if ridge_roi is not None else None
    )
    source_frame_rate = parse_frame_rate(case.get("source", {}).get("frameRate", 30.0), 30.0)
    case_duration = float(case.get("durationSeconds", 0.0) or 0.0)
    sample_fps = parse_frame_rate(args.sample_fps or quality.get("targetSampleFps", "source"), source_frame_rate)
    sample_every_captured_frame = bool(quality.get("sampleEveryCapturedFrame", False))
    require_every_captured_frame = bool(quality.get("requireEveryCapturedFrame", sample_every_captured_frame))
    visual_review_required = bool(quality.get("visualReviewRequired", case.get("visualReviewRequired", False)))
    contact_sheet_navigation_only = bool(quality.get("contactSheetNavigationOnly", True))
    visual_review_focus = quality.get(
        "visualReviewFocus",
        [
            "clouds",
            "distant ridgelines",
            "horizon",
            "crop/zoom breathing",
        ],
    )
    ignore_start = float(quality.get("ignoreStartSeconds", 1.0))
    ignore_end = float(quality.get("ignoreEndSeconds", 0.5))
    median_seconds = float(quality.get("rollingMedianWindowSeconds", 0.5))
    black_threshold = int(quality.get("blackThreshold", 8))
    min_inliers = int(quality.get("minTrackingInliers", 40))
    min_scale_inlier_ratio = float(quality.get("minScaleInlierRatio", 0.65))
    max_scale_displacement_fraction = float(quality.get("maxScaleDisplacementFraction", 0.05))
    min_duration = float(quality.get("minDurationSeconds", case.get("durationSeconds", 0.0)))
    duplicate_mean_threshold = float(quality.get("nearDuplicateMeanAbsDiffThreshold", -1.0))
    duplicate_p95_threshold = float(quality.get("nearDuplicateP95AbsDiffThreshold", float("inf")))
    duplicate_displacement_limit = float(quality.get("nearDuplicateMaxDisplacementFraction", float("inf")))
    cadence_hold_mean_threshold = float(quality.get("cadenceHoldMeanAbsDiffThreshold", -1.0))
    cadence_hold_p95_threshold = float(quality.get("cadenceHoldP95AbsDiffThreshold", float("inf")))
    cadence_hold_displacement_limit = float(quality.get("cadenceHoldMaxDisplacementFraction", float("inf")))
    cadence_hold_scale_limit = float(quality.get("cadenceHoldMaxScalePercent", float("inf")))
    pts_tolerance_ratio = float(quality.get("ptsIntervalToleranceRatio", 0.20))
    pts_timing = probe_pts_timing(args.video, pts_tolerance_ratio)
    exclude_pts_irregular_from_scale_pulse = bool(
        quality.get(
            "excludePtsIrregularFromScalePulse",
            quality.get("excludePtsIrregularFromFrameJump", False),
        )
    )
    min_captured_fps_ratio = float(quality.get("minCapturedFpsRatio", 0.0))
    diagnostic_spikes_per_kind = max(1, int(quality.get("diagnosticSpikeFramesPerKind", 24)))
    diagnostic_contact_sheet_max_frames = max(1, int(quality.get("diagnosticContactSheetMaxFrames", 96)))
    write_overlay_video = bool(quality.get("writeDiagnosticOverlayVideo", True))

    output_dir = args.output_dir or Path("/tmp/stabilizer_e2e") / args.video.stem
    output_dir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        fail(f"could not open video: {args.video}")

    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 1.0:
        fps = sample_fps
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration = frame_count / fps if frame_count > 0 else 0.0
    sample_step = 1 if sample_every_captured_frame else max(1, int(round(fps / sample_fps)))
    effective_sample_fps = fps / sample_step
    if require_every_captured_frame and sample_step != 1:
        fail(
            "case requires every captured frame to be evaluated, "
            f"but sampleStep={sample_step}; set quality.sampleEveryCapturedFrame=true"
        )

    ok, first_frame = cap.read()
    if not ok:
        fail(f"could not read first frame: {args.video}")
    frame_height, frame_width = first_frame.shape[:2]
    clamp_roi(viewer_roi, frame_width, frame_height, "viewer")
    clamp_roi(content_roi, viewer_roi[2], viewer_roi[3], "content")
    if ridge_roi is not None:
        clamp_roi(ridge_roi, viewer_roi[2], viewer_roi[3], "ridge")
    if ridge_reference_roi is not None:
        clamp_roi(ridge_reference_roi, viewer_roi[2], viewer_roi[3], "ridgeReference")
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    edge_rows: list[dict[str, Any]] = []
    scale_rows: list[dict[str, Any]] = []
    ridge_rows: list[dict[str, Any]] = []
    black_edge_transform_rows: list[dict[str, Any]] = []
    placeholder_rows: list[dict[str, Any]] = []
    previous_gray: np.ndarray | None = None
    previous_ridge_gray: np.ndarray | None = None
    previous_ridge_reference_gray: np.ndarray | None = None
    previous_ridge_line: dict[str, Any] | None = None
    previous_frame_index: int | None = None
    frame_index = -1

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        if frame_index % sample_step != 0:
            continue

        timestamp = frame_index / fps
        viewer = crop(frame, viewer_roi)
        placeholder_metrics = missing_proxy_placeholder_metrics(viewer)
        placeholder_rows.append({"frame": frame_index, "time": timestamp, **placeholder_metrics})
        viewer_gray = cv2.cvtColor(viewer, cv2.COLOR_BGR2GRAY)
        content = crop(viewer, content_roi)
        content_gray = cv2.cvtColor(content, cv2.COLOR_BGR2GRAY)
        ridge_gray = None
        ridge_reference_gray = None
        ridge_line = None
        if ridge_roi is not None:
            ridge = crop(viewer, ridge_roi)
            ridge_gray = cv2.cvtColor(ridge, cv2.COLOR_BGR2GRAY)
            ridge_line = estimate_ridge_line(ridge_gray, quality)
        if ridge_reference_roi is not None:
            ridge_reference = crop(viewer, ridge_reference_roi)
            ridge_reference_gray = cv2.cvtColor(ridge_reference, cv2.COLOR_BGR2GRAY)

        margins = black_margins(viewer_gray, black_threshold)
        edge_rows.append(
            {
                "frame": frame_index,
                "time": timestamp,
                "left": margins["left"],
                "right": margins["right"],
                "top": margins["top"],
                "bottom": margins["bottom"],
            }
        )
        black_edge_transform = estimate_black_edge_transform(viewer_gray, black_threshold, quality)
        black_edge_transform_row = {
            "frame": frame_index,
            "time": timestamp,
            "trackingOk": bool(black_edge_transform.get("ok")),
            "reason": black_edge_transform.get("reason") or "",
            **{key: value for key, value in black_edge_transform.items() if key not in ("ok", "reason")},
        }
        if previous_frame_index is not None:
            black_edge_transform_row["previousFrame"] = previous_frame_index
        black_edge_transform_rows.append(black_edge_transform_row)

        if previous_gray is not None and previous_frame_index is not None:
            diff = cv2.absdiff(previous_gray, content_gray)
            frame_diff_mean = float(diff.mean())
            frame_diff_p95 = float(np.percentile(diff, 95))
            near_duplicate_diff = (
                duplicate_mean_threshold >= 0.0
                and frame_diff_mean <= duplicate_mean_threshold
                and frame_diff_p95 <= duplicate_p95_threshold
            )
            transform = estimate_transform(previous_gray, content_gray, min_inliers)
            pts_interval = pts_interval_for_sample(pts_timing, previous_frame_index, frame_index)
            dx = float(transform.get("dx", 0.0))
            dy = float(transform.get("dy", 0.0))
            scale_percent = float(transform.get("scalePercent", 0.0))
            displacement_fraction = max(
                abs(dx) / max(1, content_roi[2]),
                abs(dy) / max(1, content_roi[3]),
            )
            near_duplicate = (
                near_duplicate_diff
                and displacement_fraction <= duplicate_displacement_limit
            )
            cadence_hold = (
                cadence_hold_mean_threshold >= 0.0
                and frame_diff_mean <= cadence_hold_mean_threshold
                and frame_diff_p95 <= cadence_hold_p95_threshold
                and displacement_fraction <= cadence_hold_displacement_limit
                and abs(scale_percent) <= cadence_hold_scale_limit
                and (bool(transform.get("ok")) or near_duplicate)
            )
            row = {
                "frame": frame_index,
                "previousFrame": previous_frame_index,
                "time": timestamp,
                "trackingOk": bool(transform.get("ok")),
                "reason": transform.get("reason") or "",
                "featureCount": int(transform.get("featureCount", 0)),
                "trackedCount": int(transform.get("trackedCount", 0)),
                "inliers": int(transform.get("inliers", 0)),
                "scalePercent": scale_percent,
                "dx": dx,
                "dy": dy,
                "rotationDegrees": float(transform.get("rotationDegrees", 0.0)),
                "frameMeanAbsDiff": frame_diff_mean,
                "frameP95AbsDiff": frame_diff_p95,
                "nearDuplicateFrame": near_duplicate,
                "cadenceHoldFrame": cadence_hold,
                "cadenceHoldDisplacementFraction": displacement_fraction,
                **pts_interval,
            }
            scale_rows.append(row)

            if previous_ridge_gray is not None and ridge_gray is not None:
                ridge_transform = estimate_transform(
                    previous_ridge_gray,
                    ridge_gray,
                    int(quality.get("minRidgeTrackingInliers", min_inliers)),
                )
                ridge_dx = float(ridge_transform.get("dx", 0.0))
                ridge_dy = float(ridge_transform.get("dy", 0.0))
                ridge_row = {
                    "frame": frame_index,
                    "previousFrame": previous_frame_index,
                    "time": timestamp,
                    "trackingOk": bool(ridge_transform.get("ok")),
                    "reason": ridge_transform.get("reason") or "",
                    "featureCount": int(ridge_transform.get("featureCount", 0)),
                    "trackedCount": int(ridge_transform.get("trackedCount", 0)),
                    "inliers": int(ridge_transform.get("inliers", 0)),
                    "scalePercent": float(ridge_transform.get("scalePercent", 0.0)),
                    "dx": ridge_dx,
                    "dy": ridge_dy,
                    "rotationDegrees": float(ridge_transform.get("rotationDegrees", 0.0)),
                }
                if ridge_line is not None:
                    ridge_row.update(
                        {
                            "ridgeLineOk": bool(ridge_line.get("ok")),
                            "ridgeLineReason": ridge_line.get("reason") or "",
                            "ridgeLineY": ridge_line.get("ridgeLineY", ""),
                            "ridgeLineWeightedY": ridge_line.get("ridgeLineWeightedY", ""),
                            "ridgeLineSupportRatio": ridge_line.get("ridgeLineSupportRatio", ""),
                            "ridgeLineStrengthMean": ridge_line.get("ridgeLineStrengthMean", ""),
                            "ridgeLineYSpreadP90": ridge_line.get("ridgeLineYSpreadP90", ""),
                        }
                    )
                if (
                    previous_ridge_line is not None
                    and ridge_line is not None
                    and bool(previous_ridge_line.get("ok"))
                    and bool(ridge_line.get("ok"))
                ):
                    line_dy = float(ridge_line["ridgeLineWeightedY"]) - float(previous_ridge_line["ridgeLineWeightedY"])
                    ridge_row["ridgeLineDy"] = line_dy
                    ridge_row["ridgeLineDyMinusAffineDy"] = line_dy - ridge_dy
                if previous_ridge_reference_gray is not None and ridge_reference_gray is not None:
                    reference_transform = estimate_transform(
                        previous_ridge_reference_gray,
                        ridge_reference_gray,
                        int(quality.get("minRidgeReferenceTrackingInliers", min_inliers)),
                    )
                    reference_dx = float(reference_transform.get("dx", 0.0))
                    reference_dy = float(reference_transform.get("dy", 0.0))
                    ridge_row.update(
                        {
                            "ridgeReferenceTrackingOk": bool(reference_transform.get("ok")),
                            "ridgeReferenceReason": reference_transform.get("reason") or "",
                            "ridgeReferenceInliers": int(reference_transform.get("inliers", 0)),
                            "ridgeReferenceDx": reference_dx,
                            "ridgeReferenceDy": reference_dy,
                            "ridgeMinusReferenceDx": ridge_dx - reference_dx,
                            "ridgeMinusReferenceDy": ridge_dy - reference_dy,
                        }
                    )
                ridge_rows.append(ridge_row)

        previous_gray = content_gray
        previous_ridge_gray = ridge_gray
        previous_ridge_reference_gray = ridge_reference_gray
        previous_ridge_line = ridge_line
        previous_frame_index = frame_index

    cap.release()

    if not edge_rows:
        fail("no sampled frames were read")

    median_window = max(3, int(round(median_seconds * effective_sample_fps)))
    if median_window % 2 == 0:
        median_window += 1

    for key in ("left", "right", "top", "bottom"):
        medians = rolling_median([float(row[key]) for row in edge_rows], median_window)
        for row, median in zip(edge_rows, medians):
            row[f"{key}Median"] = median
            row[f"{key}Residual"] = abs(float(row[key]) - median)
    for row in edge_rows:
        row["edgeMarginPx"] = max(
            float(row["left"]),
            float(row["right"]),
            float(row["top"]),
            float(row["bottom"]),
        )
        row["edgeResidualPx"] = max(
            float(row["leftResidual"]),
            float(row["rightResidual"]),
            float(row["topResidual"]),
            float(row["bottomResidual"]),
        )

    scale_medians = rolling_median([float(row["scalePercent"]) for row in scale_rows], median_window)
    for row, median in zip(scale_rows, scale_medians):
        row["scaleMedianPercent"] = median
        row["scaleResidualPercent"] = float(row["scalePercent"]) - median
        tracked_count = max(1, int(row.get("trackedCount", 0)))
        inlier_ratio = int(row.get("inliers", 0)) / tracked_count
        displacement_fraction = max(
            abs(float(row.get("dx", 0.0))) / max(1, content_roi[2]),
            abs(float(row.get("dy", 0.0))) / max(1, content_roi[3]),
        )
        row["inlierRatio"] = inlier_ratio
        row["displacementFraction"] = displacement_fraction
        row["scaleQualityOk"] = (
            bool(row.get("trackingOk"))
            and inlier_ratio >= min_scale_inlier_ratio
            and displacement_fraction <= max_scale_displacement_fraction
        )
        row["scalePulseExcludedForPtsCadence"] = False

    previous_scale_row: dict[str, Any] | None = None
    for index, row in enumerate(scale_rows):
        previous_pts_irregular = (
            previous_scale_row is not None
            and int(row.get("previousFrame", -1)) == int(previous_scale_row.get("frame", -2))
            and bool(previous_scale_row.get("ptsIntervalIrregularFrame"))
        )
        next_scale_row = scale_rows[index + 1] if index + 1 < len(scale_rows) else None
        next_pts_irregular = (
            next_scale_row is not None
            and int(next_scale_row.get("previousFrame", -1)) == int(row.get("frame", -2))
            and bool(next_scale_row.get("ptsIntervalIrregularFrame"))
        )
        pts_cadence_affected = bool(row.get("ptsIntervalIrregularFrame")) or previous_pts_irregular or next_pts_irregular
        row["ptsCadenceAffectedFrame"] = pts_cadence_affected
        if exclude_pts_irregular_from_scale_pulse and pts_cadence_affected:
            row["scalePulseExcludedForPtsCadence"] = True
        previous_scale_row = row

    scale_pts_flags_by_frame = {
        int(row["frame"]): {
            "ptsIntervalIrregularFrame": bool(row.get("ptsIntervalIrregularFrame")),
            "ptsCadenceAffectedFrame": bool(row.get("ptsCadenceAffectedFrame")),
            "scalePulseExcludedForPtsCadence": bool(row.get("scalePulseExcludedForPtsCadence")),
        }
        for row in scale_rows
    }
    for row in ridge_rows:
        flags = scale_pts_flags_by_frame.get(int(row.get("frame", -1)))
        if flags is not None:
            row.update(flags)
    for row in black_edge_transform_rows:
        flags = scale_pts_flags_by_frame.get(int(row.get("frame", -1)))
        if flags is not None:
            row.update(flags)

    cumulative_scale_log = 0.0
    cumulative_scale_segment = 0
    previous_zoom_row: dict[str, Any] | None = None
    for row in scale_rows:
        row_quality_ok = bool(row.get("scaleQualityOk", row.get("trackingOk"))) and not bool(
            row.get("scalePulseExcludedForPtsCadence")
        )
        if not row_quality_ok:
            row["cumulativeScalePathOk"] = False
            row["scalePulseDerivativePercentPerFrame"] = 0.0
            continue
        is_adjacent_sample = (
            previous_zoom_row is not None
            and int(row.get("previousFrame", -1)) == int(previous_zoom_row.get("frame", -2))
        )
        if previous_zoom_row is None or not is_adjacent_sample:
            cumulative_scale_log = 0.0
            cumulative_scale_segment += 1
            row["scalePulseDerivativePercentPerFrame"] = 0.0
        else:
            frame_scale = max(0.001, 1.0 + float(row.get("scalePercent", 0.0)) / 100.0)
            cumulative_scale_log += math.log(frame_scale)
            row["scalePulseDerivativePercentPerFrame"] = 0.0
        row["cumulativeScalePathOk"] = True
        row["cumulativeScalePathSegment"] = cumulative_scale_segment
        row["cumulativeScaleLog"] = cumulative_scale_log
        row["cumulativeScalePercentRaw"] = (math.exp(cumulative_scale_log) - 1.0) * 100.0
        previous_zoom_row = row

    baseline_seconds = float(quality.get("cumulativeScaleBaselineSeconds", 0.5))
    pulse_median_seconds = float(quality.get("scalePulseMedianWindowSeconds", 1.25))
    pulse_peak_seconds = float(quality.get("scalePulsePeakWindowSeconds", 1.0))
    pulse_median_window = max(3, int(round(pulse_median_seconds * effective_sample_fps)))
    if pulse_median_window % 2 == 0:
        pulse_median_window += 1
    pulse_peak_window = max(3, int(round(pulse_peak_seconds * effective_sample_fps)))
    if pulse_peak_window % 2 == 0:
        pulse_peak_window += 1

    finalize_black_edge_transform_rows(
        black_edge_transform_rows,
        quality,
        median_window,
        pulse_median_window,
        pulse_peak_window,
    )

    zoom_path_rows = [row for row in scale_rows if bool(row.get("cumulativeScalePathOk"))]
    rows_by_segment: dict[int, list[dict[str, Any]]] = {}
    for row in zoom_path_rows:
        rows_by_segment.setdefault(int(row.get("cumulativeScalePathSegment", 0)), []).append(row)
    for segment_rows in rows_by_segment.values():
        segment_start_time = float(segment_rows[0].get("time", 0.0))
        baseline_logs = [
            float(row.get("cumulativeScaleLog", 0.0))
            for row in segment_rows
            if float(row.get("time", 0.0)) <= segment_start_time + baseline_seconds
        ]
        baseline_log = float(np.median(np.asarray(baseline_logs, dtype=np.float64))) if baseline_logs else 0.0
        previous_residual_row: dict[str, Any] | None = None
        for row in segment_rows:
            adjusted_log = float(row.get("cumulativeScaleLog", 0.0)) - baseline_log
            row["cumulativeScaleBaselineLog"] = baseline_log
            row["cumulativeScalePercent"] = (math.exp(adjusted_log) - 1.0) * 100.0
            if previous_residual_row is not None and int(row.get("previousFrame", -1)) == int(previous_residual_row.get("frame", -2)):
                row["scalePulseDerivativePercentPerFrame"] = (
                    float(row.get("cumulativeScalePercent", 0.0))
                    - float(previous_residual_row.get("cumulativeScalePercent", 0.0))
                )
            else:
                row["scalePulseDerivativePercentPerFrame"] = 0.0
            previous_residual_row = row

    zoom_values = [float(row.get("cumulativeScalePercent", 0.0)) for row in zoom_path_rows]
    zoom_medians = rolling_median(zoom_values, pulse_median_window)
    for row, median in zip(zoom_path_rows, zoom_medians):
        row["cumulativeScaleMedianPercent"] = median
        row["cumulativeScaleResidualPercent"] = float(row.get("cumulativeScalePercent", 0.0)) - median

    pulse_rows = [row for row in scale_rows if bool(row.get("cumulativeScalePathOk"))]
    rows_by_pulse_segment: dict[int, list[dict[str, Any]]] = {}
    for row in pulse_rows:
        rows_by_pulse_segment.setdefault(int(row.get("cumulativeScalePathSegment", 0)), []).append(row)

    for segment_rows in rows_by_pulse_segment.values():
        pulse_values = [float(row.get("scaleResidualPercent", 0.0)) for row in segment_rows]
        pulse_medians = rolling_median(pulse_values, pulse_median_window)
        for row, median in zip(segment_rows, pulse_medians):
            row["scalePulseMedianPercent"] = median
            row["scalePulseResidualPercent"] = float(row.get("scaleResidualPercent", 0.0)) - median

        previous_residual_row = None
        for row in segment_rows:
            if previous_residual_row is not None and int(row.get("previousFrame", -1)) == int(previous_residual_row.get("frame", -2)):
                row["scalePulseDerivativePercentPerFrame"] = (
                    float(row.get("scalePulseResidualPercent", 0.0))
                    - float(previous_residual_row.get("scalePulseResidualPercent", 0.0))
                )
            else:
                row["scalePulseDerivativePercentPerFrame"] = 0.0
            previous_residual_row = row

        pulse_residuals = [float(row.get("scalePulseResidualPercent", 0.0)) for row in segment_rows]
        pulse_peak_to_peak = rolling_peak_to_peak(pulse_residuals, pulse_peak_window)
        for row, peak_to_peak in zip(segment_rows, pulse_peak_to_peak):
            row["scalePulsePeakToPeakPercent"] = peak_to_peak

    evaluation_duration = case_duration if case_duration > 0.0 else duration
    if duration > 0.0 and evaluation_duration > 0.0:
        evaluation_duration = min(duration, evaluation_duration)
    cutoff_end = max(0.0, evaluation_duration - ignore_end) if evaluation_duration > 0.0 else float("inf")
    filtered_edges = [row for row in edge_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_scales = [row for row in scale_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_ridge_rows = [row for row in ridge_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_black_edge_transforms = [
        row for row in black_edge_transform_rows if ignore_start <= float(row["time"]) <= cutoff_end
    ]
    filtered_placeholders = [row for row in placeholder_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    placeholder_frame_rows = [row for row in filtered_placeholders if bool(row.get("placeholderFrame"))]
    placeholder_ratio = (len(placeholder_frame_rows) / len(filtered_placeholders)) if filtered_placeholders else 0.0
    max_placeholder_run = 0
    placeholder_run = 0
    previous_placeholder_row: dict[str, Any] | None = None
    for row in filtered_placeholders:
        is_adjacent_sample = (
            previous_placeholder_row is None
            or int(row["frame"]) - int(previous_placeholder_row["frame"]) == sample_step
        )
        if bool(row.get("placeholderFrame")):
            placeholder_run = placeholder_run + 1 if is_adjacent_sample else 1
            max_placeholder_run = max(max_placeholder_run, placeholder_run)
        else:
            placeholder_run = 0
        previous_placeholder_row = row
    max_placeholder_ratio = float(quality.get("maxOperationMissingProxyPlaceholderFrameRatio", 0.02))
    max_placeholder_run_limit = int(quality.get("maxOperationMissingProxyPlaceholderRunFrames", 2))

    passed, failures, summary = summarize_failures(filtered_scales, filtered_edges, quality, source_baseline)
    if placeholder_ratio > max_placeholder_ratio or max_placeholder_run > max_placeholder_run_limit:
        operation_failure = (
            "recording shows Final Cut Pro Missing Proxy/source-media placeholder: "
            f"frame ratio {placeholder_ratio:.3f} (limit {max_placeholder_ratio:.3f}), "
            f"run {max_placeholder_run} (limit {max_placeholder_run_limit})"
        )
        summary.setdefault("operationFailures", []).append(operation_failure)
        summary["operationFailure"] = True
        failures.append(f"operation failure: {operation_failure}")
        passed = False
    ridge_passed, ridge_failures, ridge_summary = summarize_ridge_motion(
        filtered_ridge_rows,
        quality,
        effective_sample_fps,
        source_baseline,
    )
    if ridge_roi is not None and not ridge_passed:
        failures.extend(ridge_failures)
        passed = False
    black_edge_transform_passed, black_edge_transform_failures, black_edge_transform_summary = (
        summarize_black_edge_transform(filtered_black_edge_transforms, quality)
    )
    if not black_edge_transform_passed:
        failures.extend(black_edge_transform_failures)
        passed = False
    captured_fps_ratio = fps / source_frame_rate if source_frame_rate > 0.0 else 1.0
    pts_metrics = dict(pts_timing.get("summary", {}))
    max_pts_irregular_ratio = float(quality.get("maxPtsIntervalIrregularRatio", float("inf")))
    max_pts_interval_seconds = float(quality.get("maxPtsIntervalSeconds", float("inf")))
    if math.isfinite(max_pts_irregular_ratio):
        if not bool(pts_metrics.get("available")):
            failures.append(f"PTS interval metrics unavailable: {pts_metrics.get('reason', 'unknown')}")
            passed = False
        elif float(pts_metrics.get("ptsIntervalIrregularRatio", 0.0)) > max_pts_irregular_ratio:
            failures.append(
                "PTS interval irregular ratio "
                f"{float(pts_metrics.get('ptsIntervalIrregularRatio', 0.0)):.3f} exceeds {max_pts_irregular_ratio:.3f}"
            )
            passed = False
    if math.isfinite(max_pts_interval_seconds):
        if not bool(pts_metrics.get("available")):
            failures.append(f"PTS interval metrics unavailable: {pts_metrics.get('reason', 'unknown')}")
            passed = False
        elif float(pts_metrics.get("maxPtsIntervalSeconds", 0.0)) > max_pts_interval_seconds:
            failures.append(
                "max PTS interval "
                f"{float(pts_metrics.get('maxPtsIntervalSeconds', 0.0)):.6f}s exceeds {max_pts_interval_seconds:.6f}s"
            )
            passed = False
    if captured_fps_ratio + 1e-9 < min_captured_fps_ratio:
        failures.append(f"captured fps ratio {captured_fps_ratio:.3f} below {min_captured_fps_ratio:.3f}")
        passed = False
    if min_duration > 0.0 and duration + 1e-6 < min_duration:
        failures.append(f"recording duration {duration:.3f}s is shorter than required {min_duration:.3f}s")
        passed = False
    metrics_passed = passed
    visual_review_status = args.visual_review
    if visual_review_required:
        if visual_review_status == "failed":
            failures.append(
                "visual review failed: recorded FCP Preview still shows visible shimmer, stepping, or pulse"
            )
            passed = False
        elif visual_review_status == "not-reviewed":
            failures.append(
                "visual review required: inspect the recorded FCP Preview video before accepting this case"
            )
            passed = False
    summary.update(
        {
            "caseId": case.get("caseId"),
            "video": str(args.video),
            "fps": fps,
            "frameCount": frame_count,
            "durationSeconds": duration,
            "caseDurationSeconds": case_duration,
            "evaluationDurationSeconds": evaluation_duration,
            "evaluationEndSeconds": cutoff_end,
            "sampleStep": sample_step,
            "sampleFps": effective_sample_fps,
            "targetSampleFps": sample_fps,
            "sourceFrameRate": source_frame_rate,
            "capturedFpsRatio": captured_fps_ratio,
            "minCapturedFpsRatio": min_captured_fps_ratio,
            "sampleEveryCapturedFrame": sample_every_captured_frame,
            "requireEveryCapturedFrame": require_every_captured_frame,
            "viewerRoi": {"x": viewer_roi[0], "y": viewer_roi[1], "w": viewer_roi[2], "h": viewer_roi[3]},
            "contentRoi": {"x": content_roi[0], "y": content_roi[1], "w": content_roi[2], "h": content_roi[3]},
            "ridgeRoi": (
                {"x": ridge_roi[0], "y": ridge_roi[1], "w": ridge_roi[2], "h": ridge_roi[3]}
                if ridge_roi is not None
                else None
            ),
            "ridgeReferenceRoi": (
                {
                    "x": ridge_reference_roi[0],
                    "y": ridge_reference_roi[1],
                    "w": ridge_reference_roi[2],
                    "h": ridge_reference_roi[3],
                }
                if ridge_reference_roi is not None
                else None
            ),
            "ridge": ridge_summary,
            "blackEdgeTransform": black_edge_transform_summary,
            "ignoreStartSeconds": ignore_start,
            "ignoreEndSeconds": ignore_end,
            "minScaleInlierRatio": min_scale_inlier_ratio,
            "maxScaleDisplacementFraction": max_scale_displacement_fraction,
            "minDurationSeconds": min_duration,
            "nearDuplicateMeanAbsDiffThreshold": duplicate_mean_threshold,
            "nearDuplicateP95AbsDiffThreshold": duplicate_p95_threshold,
            "nearDuplicateMaxDisplacementFraction": duplicate_displacement_limit,
            "cadenceHoldMeanAbsDiffThreshold": cadence_hold_mean_threshold,
            "cadenceHoldP95AbsDiffThreshold": cadence_hold_p95_threshold,
            "cadenceHoldMaxDisplacementFraction": cadence_hold_displacement_limit,
            "cadenceHoldMaxScalePercent": cadence_hold_scale_limit,
            "cumulativeScaleBaselineSeconds": baseline_seconds,
            "scalePulseMedianWindowSeconds": pulse_median_seconds,
            "scalePulsePeakWindowSeconds": pulse_peak_seconds,
            "missingProxyPlaceholderFrameCount": len(placeholder_frame_rows),
            "missingProxyPlaceholderFrameRatio": placeholder_ratio,
            "maxMissingProxyPlaceholderRunFrames": max_placeholder_run,
            "maxOperationMissingProxyPlaceholderFrameRatio": max_placeholder_ratio,
            "maxOperationMissingProxyPlaceholderRunFrames": max_placeholder_run_limit,
            "pts": pts_metrics,
            "maxPtsIntervalIrregularRatio": max_pts_irregular_ratio,
            "maxPtsIntervalSeconds": max_pts_interval_seconds,
            "metricsPass": metrics_passed,
            "visualReview": {
                "required": visual_review_required,
                "status": visual_review_status,
                "focus": visual_review_focus,
                "failureRule": (
                    "Fail if the recorded FCP Preview video visibly shows cloud, ridgeline, horizon, "
                    "crop, zoom, freeze, or cadence instability, even when numeric metrics pass."
                ),
            },
            "videoAcceptancePolicy": {
                "mode": "video-first",
                "requiresRecordedFcpPreview": visual_review_required,
                "requiresEveryCapturedFrame": require_every_captured_frame,
                "contactSheets": "navigation-only" if contact_sheet_navigation_only else "diagnostic",
                "measuredSignals": [
                    "frame-to-frame translation jump",
                    "scale pulse",
                    "black-edge transform jump/scale/rotation",
                    "ridge/horizon residual",
                    "black-edge breathing",
                    "near-duplicate/freeze",
                    "PTS irregularity",
                ],
                "fixedRegressions": [
                    "P1000307 00:01:26-00:01:46 turn",
                    "P1000304 around 00:04:28 ridge/cloud/horizon",
                ],
            },
            "acceptanceEvidence": {
                "primary": [
                    "recorded FCP Preview video",
                    "full per-frame CSV metrics",
                    "PTS/frame-interval metrics",
                    "human visual review",
                ],
                "contactSheetsAreNavigationOnly": contact_sheet_navigation_only,
            },
            "pass": passed,
            "failures": failures,
        }
    )

    write_csv(output_dir / "edge_stats.csv", edge_rows)
    write_csv(output_dir / "scale_stats.csv", scale_rows)
    write_csv(output_dir / "ridge_stats.csv", ridge_rows)
    write_csv(output_dir / "black_edge_transform_stats.csv", black_edge_transform_rows)
    write_csv(output_dir / "placeholder_stats.csv", placeholder_rows)

    scale_spikes = sorted(
        [row for row in filtered_scales if bool(row.get("scaleQualityOk", row.get("trackingOk")))],
        key=lambda row: abs(float(row.get("scaleResidualPercent", 0.0))),
        reverse=True,
    )[:diagnostic_spikes_per_kind]
    jump_spikes = sorted(
        [row for row in filtered_scales if "frameJumpPixels" in row],
        key=lambda row: float(row.get("frameJumpPixels", 0.0)),
        reverse=True,
    )[:diagnostic_spikes_per_kind]
    duplicate_spikes = sorted(
        [row for row in filtered_scales if bool(row.get("nearDuplicateFrame"))],
        key=lambda row: float(row.get("frameMeanAbsDiff", 0.0)),
    )[:diagnostic_spikes_per_kind]
    cadence_hold_spikes = sorted(
        [row for row in filtered_scales if bool(row.get("cadenceHoldFrame"))],
        key=lambda row: float(row.get("frameMeanAbsDiff", 0.0)),
    )[:diagnostic_spikes_per_kind]
    pulse_spikes = sorted(
        [row for row in filtered_scales if bool(row.get("cumulativeScalePathOk"))],
        key=lambda row: float(row.get("scalePulsePeakToPeakPercent", 0.0)),
        reverse=True,
    )[:diagnostic_spikes_per_kind]
    edge_spikes = sorted(
        filtered_edges,
        key=lambda row: float(row.get("edgeResidualPx", 0.0)),
        reverse=True,
    )[:diagnostic_spikes_per_kind]
    black_edge_transform_spikes = sorted(
        [row for row in filtered_black_edge_transforms if bool(row.get("trackingOk"))],
        key=lambda row: max(
            float(row.get("centerJumpPixels", 0.0)),
            abs(float(row.get("scalePulseResidualPercent", 0.0))) * 10.0,
            abs(float(row.get("rotationJumpDegrees", 0.0))) * 10.0,
        ),
        reverse=True,
    )[:diagnostic_spikes_per_kind]
    ridge_spikes = sorted(
        [row for row in filtered_ridge_rows if bool(row.get("trackingOk"))],
        key=lambda row: float(row.get("ridgeHighFrequencyResidualPixels", 0.0)),
        reverse=True,
    )[:diagnostic_spikes_per_kind]

    scale_frames: list[tuple[int, str]] = []
    jump_frames: list[tuple[int, str]] = []
    cadence_frames: list[tuple[int, str]] = []
    pulse_frames: list[tuple[int, str]] = []
    edge_frames: list[tuple[int, str]] = []
    black_edge_transform_frames: list[tuple[int, str]] = []
    ridge_frames: list[tuple[int, str]] = []
    for row in scale_spikes:
        scale_frames.append((int(row["frame"]), f"scale {float(row['scaleResidualPercent']):+.2f}% t={float(row['time']):.2f}s"))
    for row in jump_spikes:
        jump_frames.append((int(row["frame"]), f"jump {float(row['frameJumpX']):+.1f},{float(row['frameJumpY']):+.1f} t={float(row['time']):.2f}s"))
    for row in duplicate_spikes:
        cadence_frames.append((int(row["frame"]), f"dup diff {float(row['frameMeanAbsDiff']):.2f} t={float(row['time']):.2f}s"))
    for row in cadence_hold_spikes:
        cadence_frames.append((int(row["frame"]), f"hold diff {float(row['frameMeanAbsDiff']):.2f} t={float(row['time']):.2f}s"))
    for row in pulse_spikes:
        pulse_frames.append(
            (
                int(row["frame"]),
                f"pulse {float(row['scalePulsePeakToPeakPercent']):.2f}% t={float(row['time']):.2f}s",
            )
        )
    for row in edge_spikes:
        edge_frames.append((int(row["frame"]), f"edge {float(row['edgeResidualPx']):.1f}px t={float(row['time']):.2f}s"))
    for row in black_edge_transform_spikes:
        black_edge_transform_frames.append(
            (
                int(row["frame"]),
                "black-xform "
                f"jump {float(row.get('centerJumpPixels', 0.0)):.1f}px "
                f"scale {float(row.get('scalePulseResidualPercent', 0.0)):+.2f}% "
                f"rot {float(row.get('rotationJumpDegrees', 0.0)):+.2f}deg "
                f"t={float(row['time']):.2f}s",
            )
        )
    for row in ridge_spikes:
        ridge_frames.append(
            (
                int(row["frame"]),
                f"ridge {float(row.get('ridgeHighFrequencyResidualPixels', 0.0)):.2f}px t={float(row['time']):.2f}s",
            )
        )

    diagnostic_artifacts: dict[str, str] = {}
    sheet_specs = [
        ("scaleContactSheet", output_dir / "scale_spikes_contact_sheet.png", scale_frames),
        ("jumpContactSheet", output_dir / "jump_spikes_contact_sheet.png", jump_frames),
        ("cadenceContactSheet", output_dir / "cadence_spikes_contact_sheet.png", cadence_frames),
        ("pulseContactSheet", output_dir / "pulse_spikes_contact_sheet.png", pulse_frames),
        ("edgeContactSheet", output_dir / "edge_spikes_contact_sheet.png", edge_frames),
        (
            "blackEdgeTransformContactSheet",
            output_dir / "black_edge_transform_spikes_contact_sheet.png",
            black_edge_transform_frames,
        ),
        ("ridgeContactSheet", output_dir / "ridge_spikes_contact_sheet.png", ridge_frames),
    ]
    for key, path, frames in sheet_specs:
        frames = merged_spike_frames(frames)[:diagnostic_contact_sheet_max_frames]
        if write_contact_sheet(args.video, path, viewer_roi, frames):
            diagnostic_artifacts[key] = str(path)

    combined_frames = merged_spike_frames(
        scale_frames
        + jump_frames
        + cadence_frames
        + pulse_frames
        + edge_frames
        + black_edge_transform_frames
        + ridge_frames
    )[:diagnostic_contact_sheet_max_frames]
    combined_sheet_path = output_dir / "spikes_contact_sheet.png"
    if write_contact_sheet(args.video, combined_sheet_path, viewer_roi, combined_frames):
        diagnostic_artifacts["combinedContactSheet"] = str(combined_sheet_path)

    overlay_path = output_dir / "diagnostic_overlay.mp4"
    if write_overlay_video and write_diagnostic_overlay_video(
        args.video,
        overlay_path,
        viewer_roi,
        scale_rows,
        edge_rows,
        ridge_rows,
        black_edge_transform_rows,
        fps,
    ):
        diagnostic_artifacts["diagnosticOverlayVideo"] = str(overlay_path)

    summary["diagnosticArtifacts"] = diagnostic_artifacts
    summary["diagnosticSpikeFramesPerKind"] = diagnostic_spikes_per_kind
    summary["diagnosticContactSheetMaxFrames"] = diagnostic_contact_sheet_max_frames
    (output_dir / "metrics.json").write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

    status = "PASS" if passed else "FAIL"
    print(f"{status} {summary['caseId']} video={args.video}")
    print(
        "  acceptance: video-first "
        f"(metricsPass={summary['metricsPass']}, visualReview={summary['visualReview']['status']}, "
        f"required={summary['visualReview']['required']})"
    )
    if summary["acceptanceEvidence"]["contactSheetsAreNavigationOnly"]:
        print("  contact sheets: diagnostic navigation only, not acceptance evidence")
    if bool(summary["operationFailure"]):
        print("  operation failure: recording did not show a valid moving FCP Viewer playback")
        for item in summary["operationFailures"]:
            print(f"    {item}")
    print(
        "  max scale residual: "
        f"{summary['maxAbsScaleResidualPercent']:.3f}% "
        f"(limit {summary['thresholds']['maxScaleResidualPercent']:.3f}%)"
    )
    print(
        "  max black-edge residual: "
        f"{summary['maxBlackEdgeResidualPixels']:.1f}px "
        f"(limit {summary['thresholds']['maxBlackEdgeResidualPixels']:.1f}px)"
    )
    print(
        "  max black-edge margin: "
        f"{summary['maxBlackEdgeMarginPixels']:.1f}px "
        f"(limit {summary['thresholds']['maxBlackEdgeMarginPixels']:.1f}px)"
    )
    if summary["blackEdgeTransform"]["enabled"]:
        print(
            "  black-edge transform: "
            f"tracking {summary['blackEdgeTransform']['trackingRatio']:.3f}, "
            f"center jump {summary['blackEdgeTransform']['maxCenterJumpPixels']:.3f}px, "
            f"scale p2p {summary['blackEdgeTransform']['maxScalePulsePeakToPeakPercent']:.3f}%, "
            f"rot jump {summary['blackEdgeTransform']['maxRotationJumpDegrees']:.3f}deg"
        )
    print(
        "  max frame jump: "
        f"{summary['maxFrameTranslationJumpPixels']:.3f}px "
        f"(x {summary['maxFrameXJumpPixels']:.3f}px, y {summary['maxFrameYJumpPixels']:.3f}px)"
    )
    print(
        "  low tracking ratio: "
        f"{summary['lowTrackingRatio']:.3f} "
        f"(limit {summary['thresholds']['maxLowInlierRatio']:.3f})"
    )
    print(
        "  captured fps: "
        f"{summary['fps']:.2f} "
        f"(ratio {summary['capturedFpsRatio']:.3f}, min {summary['minCapturedFpsRatio']:.3f})"
    )
    print(
        "  near-duplicate frames: "
        f"{summary['nearDuplicateFrameRatio']:.3f} "
        f"(run {summary['maxNearDuplicateRunFrames']}, limit {summary['thresholds']['maxNearDuplicateFrameRatio']:.3f})"
    )
    print(
        "  cadence-hold frames: "
        f"{summary['cadenceHoldFrameRatio']:.3f} "
        f"(run {summary['maxCadenceHoldRunFrames']}, skipped jump pairs {summary['frameJumpPairSkippedForCadenceCount']}, "
        f"PTS skipped {summary['frameJumpPairSkippedForPtsCadenceCount']})"
    )
    print(
        "  cumulative zoom: "
        f"in {summary['maxCumulativeZoomInPercent']:.3f}% "
        f"(limit {summary['thresholds']['maxCumulativeZoomInPercent']:.3f}%), "
        f"range {summary['maxCumulativeZoomRangePercent']:.3f}% "
        f"(limit {summary['thresholds']['maxCumulativeZoomRangePercent']:.3f}%)"
    )
    print(
        "  scale pulse: "
        f"p2p {summary['maxScalePulsePeakToPeakPercent']:.3f}% "
        f"(limit {summary['thresholds']['maxScalePulsePeakToPeakPercent']:.3f}%), "
        f"deriv p95 {summary['maxScalePulseDerivativeP95PercentPerFrame']:.3f}%/frame "
        f"(limit {summary['thresholds']['maxScalePulseDerivativeP95PercentPerFrame']:.3f}), "
        f"run {summary['maxScalePulseRunFrames']}"
    )
    if ridge_roi is not None:
        print(
            "  ridge high-frequency residual: "
            f"max {summary['ridge']['maxHighFrequencyResidualPixels']:.3f}px, "
            f"p95 {summary['ridge']['highFrequencyResidualP95Pixels']:.3f}px, "
            f"vertical p95 {summary['ridge']['verticalResidualP95Pixels']:.3f}px, "
            f"tracking {summary['ridge']['trackingRatio']:.3f}"
        )
        print(
            "  ridge line/reference: "
            f"line v p95 {summary['ridge']['lineVerticalResidualP95Pixels']:.3f}px, "
            f"line jerk p95 {summary['ridge']['lineVerticalJerkP95PixelsPerFrame']:.3f}px/frame, "
            f"minus-ref dx p95 {summary['ridge']['minusReferenceHorizontalP95Pixels']:.3f}px, "
            f"dy p95 {summary['ridge']['minusReferenceVerticalP95Pixels']:.3f}px"
        )
    if bool(summary["pts"].get("available")):
        print(
            "  PTS intervals: "
            f"median {float(summary['pts']['medianPtsIntervalSeconds']):.6f}s, "
            f"max {float(summary['pts']['maxPtsIntervalSeconds']):.6f}s, "
            f"irregular {float(summary['pts']['ptsIntervalIrregularRatio']):.3f}"
        )
    else:
        print(f"  PTS intervals: unavailable ({summary['pts'].get('reason', 'unknown')})")
    print(f"  diagnostics: {output_dir}")
    for item in failures:
        print(f"  failure: {item}")

    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
