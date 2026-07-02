#!/usr/bin/env python3
"""Evaluate FCP Viewer screen recordings for Stabilizer zoom/crop regressions."""

from __future__ import annotations

import argparse
import csv
import json
import math
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


def crop(frame: np.ndarray, roi: Roi) -> np.ndarray:
    x, y, w, h = roi
    return frame[y : y + h, x : x + w]


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


def summarize_ridge_motion(
    ridge_rows: list[dict[str, Any]],
    quality: dict[str, Any],
    effective_sample_fps: float,
) -> tuple[bool, list[str], dict[str, Any]]:
    tracking_rows = [row for row in ridge_rows if bool(row.get("trackingOk"))]
    tracking_ratio = (len(tracking_rows) / len(ridge_rows)) if ridge_rows else 0.0
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
    max_run_limit = int(quality.get("maxRidgeResidualRunFrames", 2**31 - 1))

    failures: list[str] = []
    if tracking_ratio < tracking_ratio_limit:
        failures.append(f"ridge tracking ratio {tracking_ratio:.3f} below {tracking_ratio_limit:.3f}")
    if max_vector > max_vector_limit:
        failures.append(f"ridge high-frequency residual {max_vector:.3f}px exceeds {max_vector_limit:.3f}px")
    if p95_vector > p95_vector_limit:
        failures.append(f"ridge high-frequency residual p95 {p95_vector:.3f}px exceeds {p95_vector_limit:.3f}px")
    if p95_vertical > p95_vertical_limit:
        failures.append(f"ridge vertical residual p95 {p95_vertical:.3f}px exceeds {p95_vertical_limit:.3f}px")
    if max_run > max_run_limit:
        failures.append(f"ridge residual run {max_run} exceeds {max_run_limit}")

    summary = {
        "enabled": bool(ridge_rows),
        "rowCount": len(ridge_rows),
        "trackingFrameCount": len(tracking_rows),
        "trackingRatio": tracking_ratio,
        "rollingMedianWindowSeconds": median_seconds,
        "maxHighFrequencyResidualPixels": max_vector,
        "highFrequencyResidualP95Pixels": p95_vector,
        "verticalResidualP95Pixels": p95_vertical,
        "horizontalResidualP95Pixels": p95_horizontal,
        "maxResidualRunFrames": max_run,
        "thresholds": {
            "minRidgeTrackingRatio": tracking_ratio_limit,
            "maxRidgeHighFrequencyResidualPixels": max_vector_limit,
            "maxRidgeHighFrequencyResidualP95Pixels": p95_vector_limit,
            "maxRidgeVerticalResidualP95Pixels": p95_vertical_limit,
            "ridgeResidualRunThresholdPixels": residual_threshold,
            "maxRidgeResidualRunFrames": max_run_limit,
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


def probe_pts_interval_metrics(video_path: Path, tolerance_ratio: float) -> dict[str, Any]:
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
        return {"available": False, "reason": "ffprobe_not_found"}

    if result.returncode != 0:
        return {
            "available": False,
            "reason": "ffprobe_failed",
            "stderr": result.stderr.strip()[:500],
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
            "available": False,
            "reason": "insufficient_pts_frames",
            "ptsFrameCount": len(timestamps),
        }

    intervals = [b - a for a, b in zip(timestamps, timestamps[1:]) if b >= a]
    if not intervals:
        return {
            "available": False,
            "reason": "no_positive_pts_intervals",
            "ptsFrameCount": len(timestamps),
        }

    median_interval = float(np.median(np.asarray(intervals, dtype=np.float64)))
    tolerance = max(0.0, median_interval * tolerance_ratio)
    irregular_intervals = [
        interval
        for interval in intervals
        if abs(float(interval) - median_interval) > tolerance
    ]
    return {
        "available": True,
        "ptsFrameCount": len(timestamps),
        "ptsIntervalCount": len(intervals),
        "medianPtsIntervalSeconds": median_interval,
        "maxPtsIntervalSeconds": max(intervals),
        "ptsIntervalToleranceRatio": tolerance_ratio,
        "ptsIntervalIrregularCount": len(irregular_intervals),
        "ptsIntervalIrregularRatio": len(irregular_intervals) / len(intervals),
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
            if flags:
                lines.append("flags " + ",".join(flags))
        ridge_row = ridge_by_frame.get(frame_index)
        if ridge_row is not None and bool(ridge_row.get("trackingOk")):
            lines.append(
                "ridge "
                f"hf={float(ridge_row.get('ridgeHighFrequencyResidualPixels', 0.0)):.3f}px "
                f"v={float(ridge_row.get('ridgeVerticalResidualPixels', 0.0)):.3f}px"
            )
        edge_row = edge_by_frame.get(frame_index)
        if edge_row is not None:
            lines.append(f"edge={float(edge_row.get('edgeResidualPx', 0.0)):.1f}px")
        put_label_lines(viewer, lines)
        writer.write(viewer)

    writer.release()
    cap.release()
    return True


def summarize_failures(
    scale_rows: list[dict[str, Any]],
    edge_rows: list[dict[str, Any]],
    quality: dict[str, Any],
) -> tuple[bool, list[str], dict[str, Any]]:
    scale_quality_rows = [
        row
        for row in scale_rows
        if bool(row.get("scaleQualityOk", row.get("trackingOk")))
    ]
    max_scale = max((abs(float(row.get("scaleResidualPercent", 0.0))) for row in scale_quality_rows), default=0.0)
    max_edge = max((float(row.get("edgeResidualPx", 0.0)) for row in edge_rows), default=0.0)
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
                if exclude_cadence_hold_from_jump and cadence_pair:
                    row["frameJumpSkippedForCadence"] = True
                    jump_pair_skipped_for_cadence += 1
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
    low_inlier_limit = float(quality.get("maxLowInlierRatio", 0.1))
    scale_quality_limit = float(quality.get("minScaleQualityRatio", 0.5))
    jump_vector_limit = float(quality.get("maxFrameTranslationJumpPixels", float("inf")))
    jump_x_limit = float(quality.get("maxFrameXJumpPixels", jump_vector_limit))
    jump_y_limit = float(quality.get("maxFrameYJumpPixels", jump_vector_limit))
    duplicate_like_ratio_limit = float(quality.get("maxNearDuplicateFrameRatio", float("inf")))
    duplicate_run_limit = int(quality.get("maxNearDuplicateRunFrames", 2**31 - 1))
    cadence_hold_ratio_limit = float(quality.get("maxCadenceHoldFrameRatio", float("inf")))
    cadence_hold_run_limit = int(quality.get("maxCadenceHoldRunFrames", 2**31 - 1))
    cumulative_zoom_in_limit = float(quality.get("maxCumulativeZoomInPercent", float("inf")))
    cumulative_zoom_range_limit = float(quality.get("maxCumulativeZoomRangePercent", float("inf")))
    scale_pulse_peak_to_peak_limit = float(quality.get("maxScalePulsePeakToPeakPercent", float("inf")))
    scale_pulse_derivative_p95_limit = float(quality.get("maxScalePulseDerivativeP95PercentPerFrame", float("inf")))
    scale_pulse_run_limit = int(quality.get("maxScalePulseRunFrames", 2**31 - 1))
    scale_pulse_frame_ratio_limit = float(quality.get("maxScalePulseFrameRatio", float("inf")))

    failures: list[str] = []
    if max_scale > scale_limit:
        failures.append(f"scale residual {max_scale:.3f}% exceeds {scale_limit:.3f}%")
    if max_edge > edge_limit:
        failures.append(f"black-edge residual {max_edge:.1f}px exceeds {edge_limit:.1f}px")
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

    summary = {
        "maxAbsScaleResidualPercent": max_scale,
        "maxBlackEdgeResidualPixels": max_edge,
        "maxFrameTranslationJumpPixels": max_jump_vector,
        "maxFrameXJumpPixels": max_jump_x,
        "maxFrameYJumpPixels": max_jump_y,
        "maxFrameJumpFrame": max_jump_frame,
        "maxFrameJumpTimeSeconds": max_jump_time,
        "frameJumpPairCount": jump_pair_count,
        "frameJumpPairSkippedForCadenceCount": jump_pair_skipped_for_cadence,
        "nearDuplicateFrameCount": len(duplicate_like_rows),
        "nearDuplicateFrameRatio": duplicate_like_ratio,
        "maxNearDuplicateRunFrames": max_duplicate_run,
        "cadenceHoldFrameCount": len(cadence_hold_rows),
        "cadenceHoldFrameRatio": cadence_hold_ratio,
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
        "thresholds": {
            "maxScaleResidualPercent": scale_limit,
            "maxBlackEdgeResidualPixels": edge_limit,
            "maxFrameTranslationJumpPixels": jump_vector_limit,
            "maxFrameXJumpPixels": jump_x_limit,
            "maxFrameYJumpPixels": jump_y_limit,
            "maxNearDuplicateFrameRatio": duplicate_like_ratio_limit,
            "maxNearDuplicateRunFrames": duplicate_run_limit,
            "maxCadenceHoldFrameRatio": cadence_hold_ratio_limit,
            "maxCadenceHoldRunFrames": cadence_hold_run_limit,
            "maxCumulativeZoomInPercent": cumulative_zoom_in_limit,
            "maxCumulativeZoomRangePercent": cumulative_zoom_range_limit,
            "maxScalePulsePeakToPeakPercent": scale_pulse_peak_to_peak_limit,
            "maxScalePulseDerivativeP95PercentPerFrame": scale_pulse_derivative_p95_limit,
            "scalePulseRunThresholdPercent": scale_pulse_run_threshold,
            "maxScalePulseRunFrames": scale_pulse_run_limit,
            "maxScalePulseFrameRatio": scale_pulse_frame_ratio_limit,
            "maxLowInlierRatio": low_inlier_limit,
            "minScaleQualityRatio": scale_quality_limit,
        },
    }
    return not failures, failures, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True, type=Path, help="E2E case JSON file.")
    parser.add_argument("--video", required=True, type=Path, help="FCP Viewer screen recording.")
    parser.add_argument("--viewer-roi", help="Override absolute viewer ROI as x,y,w,h.")
    parser.add_argument("--output-dir", type=Path, help="Directory for JSON/CSV/PNG diagnostics.")
    parser.add_argument("--sample-fps", type=float, help="Override analysis sample rate.")
    args = parser.parse_args()

    if not args.case.is_file():
        fail(f"case file does not exist: {args.case}")
    if not args.video.is_file():
        fail(f"video file does not exist: {args.video}")

    case = json.loads(args.case.read_text(encoding="utf-8"))
    quality = dict(case.get("quality", {}))
    viewer_roi = parse_roi(args.viewer_roi) if args.viewer_roi else roi_from_case(case["viewerRoi"], "viewerRoi")
    content_roi = roi_from_case(case["contentRoi"], "contentRoi")
    ridge_roi = roi_from_case(case["ridgeRoi"], "ridgeRoi") if "ridgeRoi" in case else None
    source_frame_rate = parse_frame_rate(case.get("source", {}).get("frameRate", 30.0), 30.0)
    sample_fps = parse_frame_rate(args.sample_fps or quality.get("targetSampleFps", "source"), source_frame_rate)
    sample_every_captured_frame = bool(quality.get("sampleEveryCapturedFrame", False))
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
    cadence_hold_mean_threshold = float(quality.get("cadenceHoldMeanAbsDiffThreshold", -1.0))
    cadence_hold_p95_threshold = float(quality.get("cadenceHoldP95AbsDiffThreshold", float("inf")))
    cadence_hold_displacement_limit = float(quality.get("cadenceHoldMaxDisplacementFraction", float("inf")))
    cadence_hold_scale_limit = float(quality.get("cadenceHoldMaxScalePercent", float("inf")))
    pts_tolerance_ratio = float(quality.get("ptsIntervalToleranceRatio", 0.20))
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

    ok, first_frame = cap.read()
    if not ok:
        fail(f"could not read first frame: {args.video}")
    frame_height, frame_width = first_frame.shape[:2]
    clamp_roi(viewer_roi, frame_width, frame_height, "viewer")
    clamp_roi(content_roi, viewer_roi[2], viewer_roi[3], "content")
    if ridge_roi is not None:
        clamp_roi(ridge_roi, viewer_roi[2], viewer_roi[3], "ridge")
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    edge_rows: list[dict[str, Any]] = []
    scale_rows: list[dict[str, Any]] = []
    ridge_rows: list[dict[str, Any]] = []
    previous_gray: np.ndarray | None = None
    previous_ridge_gray: np.ndarray | None = None
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
        viewer_gray = cv2.cvtColor(viewer, cv2.COLOR_BGR2GRAY)
        content = crop(viewer, content_roi)
        content_gray = cv2.cvtColor(content, cv2.COLOR_BGR2GRAY)
        ridge_gray = None
        if ridge_roi is not None:
            ridge = crop(viewer, ridge_roi)
            ridge_gray = cv2.cvtColor(ridge, cv2.COLOR_BGR2GRAY)

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

        if previous_gray is not None and previous_frame_index is not None:
            diff = cv2.absdiff(previous_gray, content_gray)
            frame_diff_mean = float(diff.mean())
            frame_diff_p95 = float(np.percentile(diff, 95))
            near_duplicate = (
                duplicate_mean_threshold >= 0.0
                and frame_diff_mean <= duplicate_mean_threshold
                and frame_diff_p95 <= duplicate_p95_threshold
            )
            transform = estimate_transform(previous_gray, content_gray, min_inliers)
            dx = float(transform.get("dx", 0.0))
            dy = float(transform.get("dy", 0.0))
            scale_percent = float(transform.get("scalePercent", 0.0))
            displacement_fraction = max(
                abs(dx) / max(1, content_roi[2]),
                abs(dy) / max(1, content_roi[3]),
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
            }
            scale_rows.append(row)

            if previous_ridge_gray is not None and ridge_gray is not None:
                ridge_transform = estimate_transform(
                    previous_ridge_gray,
                    ridge_gray,
                    int(quality.get("minRidgeTrackingInliers", min_inliers)),
                )
                ridge_rows.append(
                    {
                        "frame": frame_index,
                        "previousFrame": previous_frame_index,
                        "time": timestamp,
                        "trackingOk": bool(ridge_transform.get("ok")),
                        "reason": ridge_transform.get("reason") or "",
                        "featureCount": int(ridge_transform.get("featureCount", 0)),
                        "trackedCount": int(ridge_transform.get("trackedCount", 0)),
                        "inliers": int(ridge_transform.get("inliers", 0)),
                        "scalePercent": float(ridge_transform.get("scalePercent", 0.0)),
                        "dx": float(ridge_transform.get("dx", 0.0)),
                        "dy": float(ridge_transform.get("dy", 0.0)),
                        "rotationDegrees": float(ridge_transform.get("rotationDegrees", 0.0)),
                    }
                )

        previous_gray = content_gray
        previous_ridge_gray = ridge_gray
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

    cumulative_scale_log = 0.0
    cumulative_scale_segment = 0
    previous_zoom_row: dict[str, Any] | None = None
    for row in scale_rows:
        row_quality_ok = bool(row.get("scaleQualityOk", row.get("trackingOk")))
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

    pulse_rows = [row for row in scale_rows if bool(row.get("scaleQualityOk", row.get("trackingOk")))]
    pulse_values = [float(row.get("scaleResidualPercent", 0.0)) for row in pulse_rows]
    pulse_medians = rolling_median(pulse_values, pulse_median_window)
    for row, median in zip(pulse_rows, pulse_medians):
        row["scalePulseMedianPercent"] = median
        row["scalePulseResidualPercent"] = float(row.get("scaleResidualPercent", 0.0)) - median

    rows_by_pulse_segment: dict[int, list[dict[str, Any]]] = {}
    for row in pulse_rows:
        rows_by_pulse_segment.setdefault(int(row.get("cumulativeScalePathSegment", 0)), []).append(row)
    for segment_rows in rows_by_segment.values():
        previous_residual_row: dict[str, Any] | None = None
        for row in segment_rows:
            if previous_residual_row is not None and int(row.get("previousFrame", -1)) == int(previous_residual_row.get("frame", -2)):
                row["scalePulseDerivativePercentPerFrame"] = (
                    float(row.get("scalePulseResidualPercent", 0.0))
                    - float(previous_residual_row.get("scalePulseResidualPercent", 0.0))
                )
            else:
                row["scalePulseDerivativePercentPerFrame"] = 0.0
            previous_residual_row = row

    for segment_rows in rows_by_pulse_segment.values():
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

    pulse_residuals = [float(row.get("scalePulseResidualPercent", 0.0)) for row in pulse_rows]
    pulse_peak_to_peak = rolling_peak_to_peak(pulse_residuals, pulse_peak_window)
    for row, peak_to_peak in zip(pulse_rows, pulse_peak_to_peak):
        row["scalePulsePeakToPeakPercent"] = peak_to_peak

    cutoff_end = max(0.0, duration - ignore_end) if duration > 0 else float("inf")
    filtered_edges = [row for row in edge_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_scales = [row for row in scale_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_ridge_rows = [row for row in ridge_rows if ignore_start <= float(row["time"]) <= cutoff_end]

    passed, failures, summary = summarize_failures(filtered_scales, filtered_edges, quality)
    ridge_passed, ridge_failures, ridge_summary = summarize_ridge_motion(
        filtered_ridge_rows,
        quality,
        effective_sample_fps,
    )
    if ridge_roi is not None and not ridge_passed:
        failures.extend(ridge_failures)
        passed = False
    captured_fps_ratio = fps / source_frame_rate if source_frame_rate > 0.0 else 1.0
    pts_metrics = probe_pts_interval_metrics(args.video, pts_tolerance_ratio)
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
    summary.update(
        {
            "caseId": case.get("caseId"),
            "video": str(args.video),
            "fps": fps,
            "frameCount": frame_count,
            "durationSeconds": duration,
            "sampleStep": sample_step,
            "sampleFps": effective_sample_fps,
            "targetSampleFps": sample_fps,
            "sourceFrameRate": source_frame_rate,
            "capturedFpsRatio": captured_fps_ratio,
            "minCapturedFpsRatio": min_captured_fps_ratio,
            "sampleEveryCapturedFrame": sample_every_captured_frame,
            "viewerRoi": {"x": viewer_roi[0], "y": viewer_roi[1], "w": viewer_roi[2], "h": viewer_roi[3]},
            "contentRoi": {"x": content_roi[0], "y": content_roi[1], "w": content_roi[2], "h": content_roi[3]},
            "ridgeRoi": (
                {"x": ridge_roi[0], "y": ridge_roi[1], "w": ridge_roi[2], "h": ridge_roi[3]}
                if ridge_roi is not None
                else None
            ),
            "ridge": ridge_summary,
            "ignoreStartSeconds": ignore_start,
            "ignoreEndSeconds": ignore_end,
            "minScaleInlierRatio": min_scale_inlier_ratio,
            "maxScaleDisplacementFraction": max_scale_displacement_fraction,
            "minDurationSeconds": min_duration,
            "nearDuplicateMeanAbsDiffThreshold": duplicate_mean_threshold,
            "nearDuplicateP95AbsDiffThreshold": duplicate_p95_threshold,
            "cadenceHoldMeanAbsDiffThreshold": cadence_hold_mean_threshold,
            "cadenceHoldP95AbsDiffThreshold": cadence_hold_p95_threshold,
            "cadenceHoldMaxDisplacementFraction": cadence_hold_displacement_limit,
            "cadenceHoldMaxScalePercent": cadence_hold_scale_limit,
            "cumulativeScaleBaselineSeconds": baseline_seconds,
            "scalePulseMedianWindowSeconds": pulse_median_seconds,
            "scalePulsePeakWindowSeconds": pulse_peak_seconds,
            "pts": pts_metrics,
            "maxPtsIntervalIrregularRatio": max_pts_irregular_ratio,
            "maxPtsIntervalSeconds": max_pts_interval_seconds,
            "pass": passed,
            "failures": failures,
        }
    )

    write_csv(output_dir / "edge_stats.csv", edge_rows)
    write_csv(output_dir / "scale_stats.csv", scale_rows)
    write_csv(output_dir / "ridge_stats.csv", ridge_rows)

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
        f"(run {summary['maxCadenceHoldRunFrames']}, skipped jump pairs {summary['frameJumpPairSkippedForCadenceCount']})"
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
