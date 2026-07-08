#!/usr/bin/env python3
"""Evaluate source-resolution Stabilizer exports for 1px-class far-field shake."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import cv2
    import numpy as np
except Exception as exc:  # pragma: no cover - local dependency guard.
    print(f"stabilizer_source_frame_quality.py: OpenCV/numpy is required: {exc}", file=sys.stderr)
    sys.exit(2)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stabilizer_video_quality import (  # noqa: E402
    crop,
    estimate_ridge_line,
    estimate_transform,
    parse_frame_rate,
    probe_pts_timing,
    put_label_lines,
)


Roi = tuple[int, int, int, int]
_HANNING_WINDOWS: dict[tuple[int, int], np.ndarray] = {}


def fail(message: str, code: int = 2) -> None:
    print(f"stabilizer_source_frame_quality.py: {message}", file=sys.stderr)
    sys.exit(code)


def finite_float(value: Any, default: float = 0.0) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    return parsed if math.isfinite(parsed) else default


def percentile(values: list[float], p: float) -> float:
    finite = [float(value) for value in values if math.isfinite(float(value))]
    if not finite:
        return 0.0
    return float(np.percentile(np.asarray(finite, dtype=np.float64), p))


def max_run(values: list[float], threshold: float) -> int:
    best = 0
    current = 0
    for value in values:
        if math.isfinite(value) and value >= threshold:
            current += 1
            best = max(best, current)
        else:
            current = 0
    return best


def odd_window(seconds: float, fps: float) -> int:
    frames = max(3, int(round(seconds * fps)))
    if frames % 2 == 0:
        frames += 1
    return frames


def rolling_nan_median(values: list[float], window: int) -> list[float]:
    if not values:
        return []
    arr = np.asarray(values, dtype=np.float64)
    half = max(0, window // 2)
    result: list[float] = []
    for index in range(len(values)):
        segment = arr[max(0, index - half) : min(len(values), index + half + 1)]
        finite = segment[np.isfinite(segment)]
        result.append(float(np.median(finite)) if finite.size else float("nan"))
    return result


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    keys: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for key in row:
            if key not in seen:
                seen.add(key)
                keys.append(key)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def roi_from_case(value: dict[str, Any], label: str) -> Roi:
    try:
        x = int(value["x"])
        y = int(value["y"])
        w = int(value["w"])
        h = int(value["h"])
    except (KeyError, TypeError, ValueError) as exc:
        fail(f"{label} ROI must contain integer x/y/w/h: {exc}")
    if w <= 0 or h <= 0:
        fail(f"{label} ROI must have positive width/height")
    return x, y, w, h


def scale_roi(roi: Roi, source_width: int, source_height: int, width: int, height: int) -> Roi:
    x, y, w, h = roi
    scale_x = width / float(max(1, source_width))
    scale_y = height / float(max(1, source_height))
    result = (
        int(round(x * scale_x)),
        int(round(y * scale_y)),
        max(1, int(round(w * scale_x))),
        max(1, int(round(h * scale_y))),
    )
    return clamp_roi(result, width, height, "scaled source ROI")


def clamp_roi(roi: Roi, width: int, height: int, label: str) -> Roi:
    x, y, w, h = roi
    if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
        fail(f"{label} {roi} is outside frame {width}x{height}")
    return roi


def analysis_gray(gray: np.ndarray, max_dimension: int) -> tuple[np.ndarray, float]:
    height, width = gray.shape[:2]
    longest = max(width, height)
    if max_dimension <= 0 or longest <= max_dimension:
        return gray, 1.0
    scale = max_dimension / float(longest)
    resized = cv2.resize(
        gray,
        (max(1, int(round(width * scale))), max(1, int(round(height * scale)))),
        interpolation=cv2.INTER_AREA,
    )
    return resized, scale


def phase_correlation(previous_gray: np.ndarray, current_gray: np.ndarray) -> dict[str, Any]:
    if previous_gray.shape != current_gray.shape or previous_gray.size == 0:
        return {"ok": False, "reason": "phase_shape_mismatch"}
    previous = previous_gray.astype(np.float32)
    current = current_gray.astype(np.float32)
    window_key = (previous.shape[1], previous.shape[0])
    window = _HANNING_WINDOWS.get(window_key)
    if window is None:
        window = cv2.createHanningWindow(window_key, cv2.CV_32F)
        _HANNING_WINDOWS[window_key] = window
    try:
        shift, response = cv2.phaseCorrelate(previous * window, current * window)
    except cv2.error as exc:
        return {"ok": False, "reason": f"phase_failed:{exc}"}
    dx, dy = shift
    return {
        "ok": math.isfinite(dx) and math.isfinite(dy) and math.isfinite(response),
        "reason": "" if math.isfinite(response) else "phase_nonfinite",
        "dx": float(dx),
        "dy": float(dy),
        "response": float(response),
    }


def detect_crop_off_edges(
    frame: np.ndarray,
    black_threshold: int = 10,
    max_edge_fraction: float = 0.28,
) -> dict[str, Any]:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    height, width = gray.shape[:2]
    if height <= 0 or width <= 0:
        return {"visible": False, "reason": "empty_frame"}
    max_edge_pixels = max(1, int(round(width * max_edge_fraction)))
    left_runs: list[int] = []
    right_runs: list[int] = []
    for row in gray:
        left = 0
        while left < max_edge_pixels and int(row[left]) <= black_threshold:
            left += 1
        if left > 0:
            left_runs.append(left)
        right = 0
        while right < max_edge_pixels and int(row[width - 1 - right]) <= black_threshold:
            right += 1
        if right > 0:
            right_runs.append(right)
    left_visible_ratio = len(left_runs) / float(height)
    right_visible_ratio = len(right_runs) / float(height)
    left_visible = left_visible_ratio >= 0.12
    right_visible = right_visible_ratio >= 0.12
    if not left_visible and not right_visible:
        return {
            "visible": False,
            "reason": "not-visible",
            "leftVisibleRatio": left_visible_ratio,
            "rightVisibleRatio": right_visible_ratio,
        }
    left_edge_x = float(np.median(np.asarray(left_runs, dtype=np.float64))) if left_visible else float("nan")
    right_margin = float(np.median(np.asarray(right_runs, dtype=np.float64))) if right_visible else float("nan")
    right_edge_x = (width - right_margin) if right_visible else float("nan")
    if math.isfinite(left_edge_x) and math.isfinite(right_edge_x):
        edge_center_x = (left_edge_x + right_edge_x) * 0.5
        edge_width = right_edge_x - left_edge_x
    elif math.isfinite(left_edge_x):
        edge_center_x = left_edge_x
        edge_width = float("nan")
    else:
        edge_center_x = right_edge_x
        edge_width = float("nan")
    return {
        "visible": True,
        "reason": "",
        "leftVisibleRatio": left_visible_ratio,
        "rightVisibleRatio": right_visible_ratio,
        "leftEdgeX": left_edge_x,
        "rightEdgeX": right_edge_x,
        "edgeCenterX": edge_center_x,
        "edgeWidth": edge_width,
    }


def fft_band_peak(values: list[float], fps: float, min_period_seconds: float, max_period_seconds: float) -> dict[str, float]:
    finite = np.asarray([value for value in values if math.isfinite(value)], dtype=np.float64)
    if finite.size < max(8, int(round(fps * min_period_seconds))):
        return {
            "amplitudePixels": 0.0,
            "frequencyHz": 0.0,
            "periodSeconds": 0.0,
            "periodFrames": 0.0,
        }
    centered = finite - float(np.mean(finite))
    spectrum = np.fft.rfft(centered)
    freqs = np.fft.rfftfreq(centered.size, d=1.0 / fps)
    min_freq = 1.0 / max_period_seconds
    max_freq = 1.0 / min_period_seconds
    mask = (freqs >= min_freq) & (freqs <= max_freq)
    mask[0] = False
    if not np.any(mask):
        return {
            "amplitudePixels": 0.0,
            "frequencyHz": 0.0,
            "periodSeconds": 0.0,
            "periodFrames": 0.0,
        }
    amplitudes = (2.0 * np.abs(spectrum)) / float(centered.size)
    masked_indexes = np.where(mask)[0]
    peak_index = int(masked_indexes[int(np.argmax(amplitudes[mask]))])
    peak_freq = float(freqs[peak_index])
    return {
        "amplitudePixels": float(amplitudes[peak_index]),
        "frequencyHz": peak_freq,
        "periodSeconds": (1.0 / peak_freq) if peak_freq > 0.0 else 0.0,
        "periodFrames": (fps / peak_freq) if peak_freq > 0.0 else 0.0,
    }


def metric_limit(thresholds: dict[str, Any], key: str, default: float) -> float:
    return finite_float(thresholds.get(key), default)


def load_source_eval_config(case: dict[str, Any]) -> dict[str, Any]:
    config = dict(case.get("sourceFrameEvaluation", {}))
    if not bool(config.get("enabled", False)):
        fail("case sourceFrameEvaluation.enabled is not true")
    if not config.get("rois"):
        fail("case sourceFrameEvaluation.rois must contain at least one ROI")
    return config


def write_source_summary(output_dir: Path, summary: dict[str, Any]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "source_frame_metrics.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def evaluate_source_video(
    case_path: Path,
    video_path: Path,
    output_dir: Path,
    visual_review: str,
    write_diagnostic_videos: bool = True,
    allow_invalid_export_analysis: bool = False,
) -> bool:
    if not case_path.is_file():
        fail(f"case file does not exist: {case_path}")
    if not video_path.is_file():
        fail(f"video file does not exist: {video_path}")
    case = json.loads(case_path.read_text(encoding="utf-8"))
    config = load_source_eval_config(case)
    thresholds = dict(config.get("qualityThresholds", {}))
    source = dict(case.get("source", {}))
    source_width = int(source.get("width") or 0)
    source_height = int(source.get("height") or 0)
    source_fps = parse_frame_rate(source.get("frameRate", 30.0), 30.0)
    if source_width <= 0 or source_height <= 0:
        fail("case source.width/source.height must be positive for source-resolution evaluation")

    output_dir.mkdir(parents=True, exist_ok=True)
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        fail(f"could not open video: {video_path}")
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 1.0 or not math.isfinite(fps):
        fps = source_fps
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    ok, first_frame = cap.read()
    if not ok:
        fail(f"could not read first frame: {video_path}")
    height, width = first_frame.shape[:2]
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    duration_seconds = frame_count / fps if fps > 0.0 else 0.0
    case_duration_seconds = finite_float(case.get("durationSeconds"), 0.0)

    coordinate_space = str(config.get("outputPixelSpace", "source"))
    min_width_ratio = metric_limit(thresholds, "minOutputWidthRatioToSource", 1.0)
    min_height_ratio = metric_limit(thresholds, "minOutputHeightRatioToSource", 1.0)
    if coordinate_space == "source":
        min_width_ratio = max(min_width_ratio, 1.0)
        min_height_ratio = max(min_height_ratio, 1.0)
    failures: list[str] = []
    preflight_failures: list[str] = []
    warnings: list[str] = []
    if width < source_width * min_width_ratio or height < source_height * min_height_ratio:
        preflight_failures.append(
            f"export resolution {width}x{height} below source-ratio limits "
            f"{min_width_ratio:.3f}/{min_height_ratio:.3f} of {source_width}x{source_height}"
        )
    min_duration_seconds = metric_limit(
        thresholds,
        "minDurationSeconds",
        (case_duration_seconds * 0.95) if case_duration_seconds > 0.0 else 0.0,
    )
    max_duration_seconds = metric_limit(
        thresholds,
        "maxDurationSeconds",
        (case_duration_seconds * 1.10 + 0.5) if case_duration_seconds > 0.0 else float("inf"),
    )
    if min_duration_seconds > 0.0 and duration_seconds + 1e-6 < min_duration_seconds:
        preflight_failures.append(
            f"export duration {duration_seconds:.3f}s below case range minimum {min_duration_seconds:.3f}s"
        )
    if math.isfinite(max_duration_seconds) and duration_seconds > max_duration_seconds + 1e-6:
        preflight_failures.append(
            f"export duration {duration_seconds:.3f}s exceeds case range maximum {max_duration_seconds:.3f}s"
        )
    failures.extend(preflight_failures)

    roi_configs = list(config["rois"])
    rois: list[dict[str, Any]] = []
    for index, roi_config in enumerate(roi_configs):
        name = str(roi_config.get("name") or f"roi_{index}")
        raw_roi = roi_from_case(roi_config, f"sourceFrameEvaluation.rois[{index}]")
        if coordinate_space == "source":
            roi = scale_roi(raw_roi, source_width, source_height, width, height)
        elif coordinate_space == "export":
            roi = clamp_roi(raw_roi, width, height, name)
        else:
            fail(f"unsupported sourceFrameEvaluation.outputPixelSpace: {coordinate_space}")
        rois.append({"name": name, "roi": roi, "config": dict(roi_config)})

    if preflight_failures and not allow_invalid_export_analysis:
        summary = {
            "caseId": case.get("caseId"),
            "video": str(video_path),
            "evaluationMode": "source-resolution-export",
            "measurementPixelSpace": "export-video-pixels",
            "frameCount": frame_count,
            "fps": fps,
            "durationSeconds": duration_seconds,
            "caseDurationSeconds": case_duration_seconds,
            "minDurationSeconds": min_duration_seconds,
            "maxDurationSeconds": max_duration_seconds,
            "sourceWidth": source_width,
            "sourceHeight": source_height,
            "exportWidth": width,
            "exportHeight": height,
            "outputPixelSpace": coordinate_space,
            "rois": {},
            "pts": {"available": False, "reason": "not_probed_export_preflight_failed"},
            "visualReview": {
                "required": bool(config.get("visualReviewRequired", True)),
                "status": visual_review,
                "failureRule": "Fail if the FCP export visibly shows 1px-class ridge, cloud, horizon, crop, or scale pulse.",
            },
            "diagnosticArtifacts": {},
            "warnings": warnings,
            "failures": failures,
            "pass": False,
        }
        write_source_summary(output_dir, summary)
        print(f"FAIL {summary['caseId']} sourceExport={video_path}")
        print(f"  resolution: {width}x{height} source={source_width}x{source_height} fps={fps:.3f}")
        for failure in failures:
            print(f"  FAIL: {failure}")
        print(f"  diagnostics: {output_dir}")
        return False

    baseline_seconds = metric_limit(thresholds, "baselineWindowSeconds", 0.5)
    baseline_window = odd_window(baseline_seconds, fps)
    pulse_windows = dict(config.get("pulseWindowsSeconds", {}))
    min_pulse_seconds = finite_float(pulse_windows.get("min"), 10.0 / fps)
    max_pulse_seconds = finite_float(pulse_windows.get("max"), 1.0)
    min_inliers_default = int(thresholds.get("minTrackingInliers", 24))
    min_phase_response = metric_limit(thresholds, "minPhaseCorrelationResponse", 0.08)
    default_analysis_max_dimension = int(config.get("analysisMaxRoiDimension", 0) or 0)
    allow_downsampled_analysis = bool(config.get("allowDownsampledAnalysis", False))
    ignore_start_seconds = metric_limit(
        thresholds,
        "ignoreStartSeconds",
        0.0,
    )
    ignore_end_seconds = metric_limit(
        thresholds,
        "ignoreEndSeconds",
        0.0,
    )
    evaluation_start_seconds = max(0.0, ignore_start_seconds)
    evaluation_end_seconds = max(evaluation_start_seconds, duration_seconds - max(0.0, ignore_end_seconds))
    remove_black_edges = bool(case.get("removeBlackEdges", False))
    edge_black_threshold = int(thresholds.get("cropOffEdgeBlackThreshold", thresholds.get("blackThreshold", 10)))

    previous_analysis_gray_by_roi: dict[str, np.ndarray] = {}
    path_by_roi: dict[str, tuple[float, float]] = {roi["name"]: (0.0, 0.0) for roi in rois}
    previous_line_by_roi: dict[str, dict[str, Any] | None] = {roi["name"]: None for roi in rois}
    frame_rows: list[dict[str, Any]] = []
    edge_rows: list[dict[str, Any]] = []
    downsampled_analysis_seen = False
    frame_index = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        timestamp = frame_index / fps
        if not remove_black_edges:
            edge = detect_crop_off_edges(frame, black_threshold=edge_black_threshold)
            edge_rows.append(
                {
                    "frame": frame_index,
                    "time": timestamp,
                    "visible": bool(edge.get("visible")),
                    "reason": edge.get("reason") or "",
                    "leftVisibleRatio": edge.get("leftVisibleRatio", ""),
                    "rightVisibleRatio": edge.get("rightVisibleRatio", ""),
                    "leftEdgeX": edge.get("leftEdgeX", ""),
                    "rightEdgeX": edge.get("rightEdgeX", ""),
                    "edgeCenterX": edge.get("edgeCenterX", ""),
                    "edgeWidth": edge.get("edgeWidth", ""),
                }
            )
        for roi_info in rois:
            name = roi_info["name"]
            roi = roi_info["roi"]
            roi_config = roi_info["config"]
            gray = cv2.cvtColor(crop(frame, roi), cv2.COLOR_BGR2GRAY)
            analysis_max_dimension = int(roi_config.get("analysisMaxRoiDimension", default_analysis_max_dimension) or 0)
            motion_gray, motion_scale = analysis_gray(gray, analysis_max_dimension)
            if motion_scale < 0.999:
                downsampled_analysis_seen = True
            motion_pixel_scale = 1.0 / motion_scale if motion_scale > 0.0 else 1.0
            ridge_line = estimate_ridge_line(gray, {**thresholds, **dict(roi_config.get("ridgeLine", {}))})
            row: dict[str, Any] = {
                "frame": frame_index,
                "time": timestamp,
                "roi": name,
                "x": roi[0],
                "y": roi[1],
                "w": roi[2],
                "h": roi[3],
                "analysisMaxDimension": analysis_max_dimension,
                "analysisScale": motion_scale,
                "measured": False,
                "motionMethod": "",
                "pathX": path_by_roi[name][0],
                "pathY": path_by_roi[name][1],
                "ridgeLineOk": bool(ridge_line.get("ok")),
                "ridgeLineReason": ridge_line.get("reason") or "",
                "ridgeLineWeightedY": ridge_line.get("ridgeLineWeightedY", ""),
                "ridgeLineSupportRatio": ridge_line.get("ridgeLineSupportRatio", ""),
            }
            previous_motion_gray = previous_analysis_gray_by_roi.get(name)
            if previous_motion_gray is not None:
                min_inliers = int(roi_config.get("minTrackingInliers", min_inliers_default))
                affine = estimate_transform(previous_motion_gray, motion_gray, min_inliers)
                phase = phase_correlation(previous_motion_gray, motion_gray)
                affine_ok = bool(affine.get("ok"))
                phase_ok = bool(phase.get("ok")) and finite_float(phase.get("response")) >= min_phase_response
                row.update(
                    {
                        "affineOk": affine_ok,
                        "affineReason": affine.get("reason") or "",
                        "affineDx": finite_float(affine.get("dx")) * motion_pixel_scale,
                        "affineDy": finite_float(affine.get("dy")) * motion_pixel_scale,
                        "affineRotationDegrees": finite_float(affine.get("rotationDegrees")),
                        "affineScalePercent": finite_float(affine.get("scalePercent")),
                        "affineInliers": int(affine.get("inliers", 0) or 0),
                        "affineTrackedCount": int(affine.get("trackedCount", 0) or 0),
                        "phaseOk": phase_ok,
                        "phaseReason": phase.get("reason") or "",
                        "phaseDx": finite_float(phase.get("dx")) * motion_pixel_scale,
                        "phaseDy": finite_float(phase.get("dy")) * motion_pixel_scale,
                        "phaseResponse": finite_float(phase.get("response")),
                    }
                )
                if affine_ok:
                    dx = finite_float(affine.get("dx")) * motion_pixel_scale
                    dy = finite_float(affine.get("dy")) * motion_pixel_scale
                    method = "affine"
                elif phase_ok:
                    dx = finite_float(phase.get("dx")) * motion_pixel_scale
                    dy = finite_float(phase.get("dy")) * motion_pixel_scale
                    method = "phase"
                else:
                    dx = 0.0
                    dy = 0.0
                    method = ""
                if method:
                    previous_path_x, previous_path_y = path_by_roi[name]
                    path_x = previous_path_x + dx
                    path_y = previous_path_y + dy
                    path_by_roi[name] = (path_x, path_y)
                    row.update(
                        {
                            "measured": True,
                            "motionMethod": method,
                            "dx": dx,
                            "dy": dy,
                            "pathX": path_x,
                            "pathY": path_y,
                            "motionMagnitude": math.hypot(dx, dy),
                        }
                    )
                if previous_line_by_roi.get(name) and bool(previous_line_by_roi[name].get("ok")) and bool(ridge_line.get("ok")):
                    row["ridgeLineDy"] = finite_float(ridge_line.get("ridgeLineWeightedY")) - finite_float(
                        previous_line_by_roi[name].get("ridgeLineWeightedY")
                    )
            previous_analysis_gray_by_roi[name] = motion_gray
            previous_line_by_roi[name] = ridge_line
            frame_rows.append(row)
    cap.release()

    if not frame_rows:
        fail("no frames were evaluated")

    for roi_info in rois:
        name = roi_info["name"]
        rows = [row for row in frame_rows if row["roi"] == name]
        med_x = rolling_nan_median([finite_float(row.get("pathX"), float("nan")) for row in rows], baseline_window)
        med_y = rolling_nan_median([finite_float(row.get("pathY"), float("nan")) for row in rows], baseline_window)
        line_values = [
            finite_float(row.get("ridgeLineWeightedY"), float("nan")) if bool(row.get("ridgeLineOk")) else float("nan")
            for row in rows
        ]
        line_medians = rolling_nan_median(line_values, baseline_window)
        previous_residual_x: float | None = None
        previous_residual_y: float | None = None
        previous_line_residual: float | None = None
        for row, median_x, median_y, line_median in zip(rows, med_x, med_y, line_medians):
            residual_x = finite_float(row.get("pathX"), float("nan")) - median_x
            residual_y = finite_float(row.get("pathY"), float("nan")) - median_y
            residual = math.hypot(residual_x, residual_y) if math.isfinite(residual_x) and math.isfinite(residual_y) else float("nan")
            row["pathMedianX"] = median_x
            row["pathMedianY"] = median_y
            row["residualX"] = residual_x
            row["residualY"] = residual_y
            row["residualPixels"] = residual
            if previous_residual_x is not None and math.isfinite(residual_x) and math.isfinite(previous_residual_x):
                row["residualJerkX"] = residual_x - previous_residual_x
                row["residualJerkY"] = residual_y - previous_residual_y
                row["residualJerkPixelsPerFrame"] = math.hypot(row["residualJerkX"], row["residualJerkY"])
            if math.isfinite(residual_x):
                previous_residual_x = residual_x
                previous_residual_y = residual_y
            if bool(row.get("ridgeLineOk")) and math.isfinite(line_median):
                line_residual = finite_float(row.get("ridgeLineWeightedY")) - line_median
                row["ridgeLineVerticalResidualPixels"] = line_residual
                if previous_line_residual is not None:
                    row["ridgeLineVerticalJerkPixelsPerFrame"] = line_residual - previous_line_residual
                previous_line_residual = line_residual

    summary_rows: list[dict[str, Any]] = []
    roi_summaries: dict[str, dict[str, Any]] = {}
    max_residual_limit = metric_limit(thresholds, "maxHighFrequencyResidualPixels", 1.25)
    p95_residual_limit = metric_limit(thresholds, "maxHighFrequencyResidualP95Pixels", 0.55)
    vertical_p95_limit = metric_limit(thresholds, "maxVerticalResidualP95Pixels", 0.50)
    horizontal_p95_limit = metric_limit(thresholds, "maxHorizontalResidualP95Pixels", 0.50)
    jerk_p95_limit = metric_limit(thresholds, "maxJerkP95PixelsPerFrame", 0.35)
    line_jerk_p95_limit = metric_limit(thresholds, "maxRidgeLineVerticalJerkP95PixelsPerFrame", 0.35)
    residual_run_threshold = metric_limit(thresholds, "residualRunThresholdPixels", 0.35)
    max_residual_run_frames = int(thresholds.get("maxResidualRunFrames", 8))
    pulse_amplitude_limit = metric_limit(thresholds, "maxPulseAmplitudePixels", 0.30)
    min_measured_ratio = metric_limit(thresholds, "minMeasuredFrameRatio", 0.92)
    min_affine_ratio = metric_limit(thresholds, "minAffineTrackingRatio", 0.40)

    for roi_info in rois:
        name = roi_info["name"]
        rows = [row for row in frame_rows if row["roi"] == name]
        evaluation_rows = [
            row for row in rows
            if evaluation_start_seconds <= finite_float(row.get("time"), -1.0) <= evaluation_end_seconds
        ]
        measurement_rows = [row for row in evaluation_rows if bool(row.get("measured"))]
        affine_rows = [row for row in evaluation_rows if bool(row.get("affineOk"))]
        residuals = [finite_float(row.get("residualPixels"), float("nan")) for row in measurement_rows]
        residual_x = [abs(finite_float(row.get("residualX"), float("nan"))) for row in measurement_rows]
        residual_y = [abs(finite_float(row.get("residualY"), float("nan"))) for row in measurement_rows]
        jerks = [finite_float(row.get("residualJerkPixelsPerFrame"), float("nan")) for row in measurement_rows]
        line_jerks = [abs(finite_float(row.get("ridgeLineVerticalJerkPixelsPerFrame"), float("nan"))) for row in evaluation_rows]
        pulse_source = [finite_float(row.get("residualPixels"), float("nan")) for row in measurement_rows]
        pulse = fft_band_peak(pulse_source, fps, min_pulse_seconds, max_pulse_seconds)
        evaluated_count = max(1, len(evaluation_rows))
        measured_ratio = len(measurement_rows) / float(evaluated_count)
        affine_ratio = len(affine_rows) / float(evaluated_count)
        roi_summary = {
            "roi": name,
            "frameCount": len(rows),
            "evaluatedFrameCount": len(evaluation_rows),
            "evaluationStartSeconds": evaluation_start_seconds,
            "evaluationEndSeconds": evaluation_end_seconds,
            "ignoreStartSeconds": ignore_start_seconds,
            "ignoreEndSeconds": ignore_end_seconds,
            "measuredFrameCount": len(measurement_rows),
            "measuredFrameRatio": measured_ratio,
            "affineTrackingRatio": affine_ratio,
            "maxHighFrequencyResidualPixels": max([value for value in residuals if math.isfinite(value)], default=0.0),
            "highFrequencyResidualP95Pixels": percentile(residuals, 95),
            "horizontalResidualP95Pixels": percentile(residual_x, 95),
            "verticalResidualP95Pixels": percentile(residual_y, 95),
            "jerkP95PixelsPerFrame": percentile(jerks, 95),
            "ridgeLineVerticalJerkP95PixelsPerFrame": percentile(line_jerks, 95),
            "residualRunThresholdPixels": residual_run_threshold,
            "maxResidualRunFrames": max_run(residuals, residual_run_threshold),
            "pulseAmplitudePixels": pulse["amplitudePixels"],
            "pulseFrequencyHz": pulse["frequencyHz"],
            "pulsePeriodSeconds": pulse["periodSeconds"],
            "pulsePeriodFrames": pulse["periodFrames"],
            "limits": {
                "minMeasuredFrameRatio": min_measured_ratio,
                "minAffineTrackingRatio": min_affine_ratio,
                "maxHighFrequencyResidualPixels": max_residual_limit,
                "maxHighFrequencyResidualP95Pixels": p95_residual_limit,
                "maxHorizontalResidualP95Pixels": horizontal_p95_limit,
                "maxVerticalResidualP95Pixels": vertical_p95_limit,
                "maxJerkP95PixelsPerFrame": jerk_p95_limit,
                "maxRidgeLineVerticalJerkP95PixelsPerFrame": line_jerk_p95_limit,
                "maxResidualRunFrames": max_residual_run_frames,
                "maxPulseAmplitudePixels": pulse_amplitude_limit,
            },
        }
        roi_failures: list[str] = []
        if measured_ratio < min_measured_ratio:
            roi_failures.append(f"measured frame ratio {measured_ratio:.3f} below {min_measured_ratio:.3f}")
        if affine_ratio < min_affine_ratio:
            roi_failures.append(f"affine tracking ratio {affine_ratio:.3f} below {min_affine_ratio:.3f}")
        if roi_summary["maxHighFrequencyResidualPixels"] > max_residual_limit:
            roi_failures.append(
                f"max residual {roi_summary['maxHighFrequencyResidualPixels']:.3f}px exceeds {max_residual_limit:.3f}px"
            )
        if roi_summary["highFrequencyResidualP95Pixels"] > p95_residual_limit:
            roi_failures.append(
                f"p95 residual {roi_summary['highFrequencyResidualP95Pixels']:.3f}px exceeds {p95_residual_limit:.3f}px"
            )
        if roi_summary["horizontalResidualP95Pixels"] > horizontal_p95_limit:
            roi_failures.append(
                f"horizontal p95 {roi_summary['horizontalResidualP95Pixels']:.3f}px exceeds {horizontal_p95_limit:.3f}px"
            )
        if roi_summary["verticalResidualP95Pixels"] > vertical_p95_limit:
            roi_failures.append(
                f"vertical p95 {roi_summary['verticalResidualP95Pixels']:.3f}px exceeds {vertical_p95_limit:.3f}px"
            )
        if roi_summary["jerkP95PixelsPerFrame"] > jerk_p95_limit:
            roi_failures.append(
                f"jerk p95 {roi_summary['jerkP95PixelsPerFrame']:.3f}px/frame exceeds {jerk_p95_limit:.3f}px/frame"
            )
        if roi_summary["ridgeLineVerticalJerkP95PixelsPerFrame"] > line_jerk_p95_limit:
            roi_failures.append(
                "ridge line jerk p95 "
                f"{roi_summary['ridgeLineVerticalJerkP95PixelsPerFrame']:.3f}px/frame exceeds {line_jerk_p95_limit:.3f}px/frame"
            )
        if roi_summary["maxResidualRunFrames"] > max_residual_run_frames:
            roi_failures.append(
                f"residual run {roi_summary['maxResidualRunFrames']} exceeds {max_residual_run_frames} frames"
            )
        if roi_summary["pulseAmplitudePixels"] > pulse_amplitude_limit:
            roi_failures.append(
                f"pulse amplitude {roi_summary['pulseAmplitudePixels']:.3f}px exceeds {pulse_amplitude_limit:.3f}px"
            )
        roi_summary["pass"] = not roi_failures
        roi_summary["failures"] = roi_failures
        failures.extend([f"{name}: {failure}" for failure in roi_failures])
        roi_summaries[name] = roi_summary
        summary_rows.append(roi_summary)

    crop_off_edge_summary: dict[str, Any]
    if remove_black_edges:
        crop_off_edge_summary = {
            "state": "disabled-remove-black-edges-on",
            "measurementAvailable": False,
            "frameCount": 0,
            "visibleFrameRatio": 0.0,
            "pass": None,
        }
    else:
        edge_evaluation_rows = [
            row for row in edge_rows
            if evaluation_start_seconds <= finite_float(row.get("time"), -1.0) <= evaluation_end_seconds
        ]
        visible_edge_rows = [row for row in edge_evaluation_rows if bool(row.get("visible"))]
        visible_ratio = len(visible_edge_rows) / float(max(1, len(edge_evaluation_rows)))
        min_visible_ratio = metric_limit(thresholds, "minCropOffEdgeVisibleFrameRatio", 0.10)
        max_edge_jitter_p95 = metric_limit(thresholds, "maxCropOffEdgeJitterP95Pixels", 0.70)
        max_edge_pulse = metric_limit(thresholds, "maxCropOffEdgePulseAmplitudePixels", 0.35)
        max_edge_width_delta_p95 = metric_limit(thresholds, "maxCropOffEdgeWidthDeltaP95Pixels", 0.90)
        if visible_ratio < min_visible_ratio:
            warnings.append(
                "crop-off edge tracking not visible enough to score; edge jitter was not used as pass evidence"
            )
            crop_off_edge_summary = {
                "state": "not-visible",
                "measurementAvailable": False,
                "frameCount": len(edge_rows),
                "evaluatedFrameCount": len(edge_evaluation_rows),
                "visibleFrameCount": len(visible_edge_rows),
                "visibleFrameRatio": visible_ratio,
                "limits": {
                    "minCropOffEdgeVisibleFrameRatio": min_visible_ratio,
                    "maxCropOffEdgeJitterP95Pixels": max_edge_jitter_p95,
                    "maxCropOffEdgePulseAmplitudePixels": max_edge_pulse,
                    "maxCropOffEdgeWidthDeltaP95Pixels": max_edge_width_delta_p95,
                },
                "pass": None,
                "failures": [],
            }
        else:
            centers = [finite_float(row.get("edgeCenterX"), float("nan")) for row in visible_edge_rows]
            widths = [finite_float(row.get("edgeWidth"), float("nan")) for row in visible_edge_rows]
            center_medians = rolling_nan_median(centers, baseline_window)
            center_residuals = [
                center - median for center, median in zip(centers, center_medians)
                if math.isfinite(center) and math.isfinite(median)
            ]
            center_steps = [
                centers[index] - centers[index - 1]
                for index in range(1, len(centers))
                if math.isfinite(centers[index]) and math.isfinite(centers[index - 1])
            ]
            width_steps = [
                widths[index] - widths[index - 1]
                for index in range(1, len(widths))
                if math.isfinite(widths[index]) and math.isfinite(widths[index - 1])
            ]
            edge_pulse = fft_band_peak(center_residuals, fps, min_pulse_seconds, max_pulse_seconds)
            edge_failures: list[str] = []
            edge_jitter_p95 = percentile([abs(value) for value in center_steps], 95)
            edge_width_delta_p95 = percentile([abs(value) for value in width_steps], 95)
            if edge_jitter_p95 > max_edge_jitter_p95:
                edge_failures.append(f"crop-off edge X jitter p95 {edge_jitter_p95:.3f}px exceeds {max_edge_jitter_p95:.3f}px")
            if edge_pulse["amplitudePixels"] > max_edge_pulse:
                edge_failures.append(
                    f"crop-off edge pulse {edge_pulse['amplitudePixels']:.3f}px exceeds {max_edge_pulse:.3f}px"
                )
            if edge_width_delta_p95 > max_edge_width_delta_p95:
                edge_failures.append(
                    f"crop-off edge width delta p95 {edge_width_delta_p95:.3f}px exceeds {max_edge_width_delta_p95:.3f}px"
                )
            crop_off_edge_summary = {
                "state": "visible",
                "measurementAvailable": True,
                "frameCount": len(edge_rows),
                "evaluatedFrameCount": len(edge_evaluation_rows),
                "visibleFrameCount": len(visible_edge_rows),
                "visibleFrameRatio": visible_ratio,
                "edgeCenterJitterP95Pixels": edge_jitter_p95,
                "edgeCenterPulseAmplitudePixels": edge_pulse["amplitudePixels"],
                "edgeCenterPulseFrequencyHz": edge_pulse["frequencyHz"],
                "edgeCenterPulsePeriodSeconds": edge_pulse["periodSeconds"],
                "edgeCenterPulsePeriodFrames": edge_pulse["periodFrames"],
                "edgeWidthDeltaP95Pixels": edge_width_delta_p95,
                "limits": {
                    "minCropOffEdgeVisibleFrameRatio": min_visible_ratio,
                    "maxCropOffEdgeJitterP95Pixels": max_edge_jitter_p95,
                    "maxCropOffEdgePulseAmplitudePixels": max_edge_pulse,
                    "maxCropOffEdgeWidthDeltaP95Pixels": max_edge_width_delta_p95,
                },
                "pass": not edge_failures,
                "failures": edge_failures,
            }
            failures.extend(edge_failures)

    pts_tolerance_ratio = metric_limit(thresholds, "ptsIntervalToleranceRatio", 0.20)
    pts_summary = dict(probe_pts_timing(video_path, pts_tolerance_ratio).get("summary", {}))
    max_pts_irregular = metric_limit(thresholds, "maxPtsIntervalIrregularRatio", 0.02)
    require_pts = bool(thresholds.get("requirePtsIntervalMetrics", True))
    if bool(pts_summary.get("available")):
        if finite_float(pts_summary.get("ptsIntervalIrregularRatio")) > max_pts_irregular:
            failures.append(
                "PTS interval irregular ratio "
                f"{finite_float(pts_summary.get('ptsIntervalIrregularRatio')):.3f} exceeds {max_pts_irregular:.3f}"
            )
    else:
        message = f"PTS interval metrics unavailable: {pts_summary.get('reason', 'unknown')}"
        if require_pts:
            failures.append(message)
        else:
            warnings.append(message)

    if downsampled_analysis_seen:
        message = (
            "ROI motion analysis was downsampled; source-resolution acceptance "
            "requires full-resolution ROI analysis unless allowDownsampledAnalysis is explicit"
        )
        if allow_downsampled_analysis:
            warnings.append(message)
        else:
            failures.append(message)

    visual_required = bool(config.get("visualReviewRequired", True))
    if visual_required:
        if visual_review == "failed":
            failures.append("source export visual review failed: far-field pulse/shake remains visible")
        elif visual_review == "not-reviewed":
            failures.append("source export visual review required before acceptance")
        elif not write_diagnostic_videos:
            failures.append("source export diagnostic videos are required for reviewed acceptance")

    write_csv(output_dir / "source_frame_roi_stats.csv", frame_rows)
    write_csv(output_dir / "source_frame_roi_summary.csv", summary_rows)
    write_csv(output_dir / "source_frame_crop_off_edge_stats.csv", edge_rows)

    passed = False
    diagnostic_artifacts: dict[str, str] = {}
    summary = {
        "caseId": case.get("caseId"),
        "video": str(video_path),
        "evaluationMode": "source-resolution-export",
        "measurementPixelSpace": "export-video-pixels",
        "frameCount": frame_count,
        "fps": fps,
        "durationSeconds": frame_count / fps if fps > 0.0 else 0.0,
        "caseDurationSeconds": case_duration_seconds,
        "minDurationSeconds": min_duration_seconds,
        "maxDurationSeconds": max_duration_seconds,
        "sourceWidth": source_width,
        "sourceHeight": source_height,
        "exportWidth": width,
        "exportHeight": height,
        "outputPixelSpace": coordinate_space,
        "baselineWindowFrames": baseline_window,
        "baselineWindowSeconds": baseline_seconds,
        "analysisMaxRoiDimension": default_analysis_max_dimension,
        "allowDownsampledAnalysis": allow_downsampled_analysis,
        "downsampledAnalysisSeen": downsampled_analysis_seen,
        "evaluationStartSeconds": evaluation_start_seconds,
        "evaluationEndSeconds": evaluation_end_seconds,
        "ignoreStartSeconds": ignore_start_seconds,
        "ignoreEndSeconds": ignore_end_seconds,
        "pulseWindowsSeconds": {"min": min_pulse_seconds, "max": max_pulse_seconds},
        "rois": roi_summaries,
        "cropOffEdges": crop_off_edge_summary,
        "pts": pts_summary,
        "visualReview": {
            "required": visual_required,
            "status": visual_review,
            "failureRule": "Fail if the FCP export visibly shows 1px-class ridge, cloud, horizon, crop, or scale pulse.",
        },
        "diagnosticArtifacts": diagnostic_artifacts,
        "warnings": warnings,
        "failures": failures,
        "pass": passed,
    }
    write_source_summary(output_dir, summary)

    if write_diagnostic_videos:
        overlay_path = output_dir / "source_frame_residual_overlay.mp4"
        magnified_path = output_dir / "source_frame_motion_magnified.mp4"
        if write_overlay_video(video_path, overlay_path, rois, frame_rows, fps, magnification=1.0):
            diagnostic_artifacts["residualOverlayVideo"] = str(overlay_path)
        else:
            message = f"could not write source residual overlay video: {overlay_path}"
            if visual_required:
                failures.append(message)
            else:
                warnings.append(message)
        if write_overlay_video(video_path, magnified_path, rois, frame_rows, fps, magnification=float(config.get("motionMagnification", 8.0))):
            diagnostic_artifacts["motionMagnifiedVideo"] = str(magnified_path)
        else:
            message = f"could not write source motion-magnified diagnostic video: {magnified_path}"
            if visual_required:
                failures.append(message)
            else:
                warnings.append(message)
    else:
        warnings.append("diagnostic videos skipped by explicit --skip-diagnostic-videos")

    passed = not failures
    summary["diagnosticArtifacts"] = diagnostic_artifacts
    summary["warnings"] = warnings
    summary["failures"] = failures
    summary["pass"] = passed
    write_source_summary(output_dir, summary)

    status = "PASS" if passed else "FAIL"
    print(f"{status} {summary['caseId']} sourceExport={video_path}")
    print(f"  resolution: {width}x{height} source={source_width}x{source_height} fps={fps:.3f}")
    print(f"  visual review: {visual_review} required={visual_required}")
    for name, roi_summary in roi_summaries.items():
        print(
            "  roi "
            f"{name}: p95={roi_summary['highFrequencyResidualP95Pixels']:.3f}px "
            f"max={roi_summary['maxHighFrequencyResidualPixels']:.3f}px "
            f"pulse={roi_summary['pulseAmplitudePixels']:.3f}px "
            f"run={roi_summary['maxResidualRunFrames']} "
            f"measured={roi_summary['measuredFrameRatio']:.3f}"
        )
    edge_state = crop_off_edge_summary.get("state", "unknown")
    if edge_state == "visible":
        print(
            "  crop-off edges: "
            f"jitterP95={finite_float(crop_off_edge_summary.get('edgeCenterJitterP95Pixels')):.3f}px "
            f"pulse={finite_float(crop_off_edge_summary.get('edgeCenterPulseAmplitudePixels')):.3f}px "
            f"visible={finite_float(crop_off_edge_summary.get('visibleFrameRatio')):.3f}"
        )
    else:
        print(
            "  crop-off edges: "
            f"{edge_state} visible={finite_float(crop_off_edge_summary.get('visibleFrameRatio')):.3f}"
        )
    for failure in failures:
        print(f"  FAIL: {failure}")
    for warning in warnings:
        print(f"  WARN: {warning}")
    print(f"  diagnostics: {output_dir}")
    return passed


def write_overlay_video(
    video_path: Path,
    output_path: Path,
    rois: list[dict[str, Any]],
    frame_rows: list[dict[str, Any]],
    fps: float,
    magnification: float,
) -> bool:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return False
    ok, first_frame = cap.read()
    if not ok:
        cap.release()
        return False
    height, width = first_frame.shape[:2]
    max_width = 1920
    scale = min(1.0, max_width / float(max(1, width)))
    output_size = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
    writer = cv2.VideoWriter(str(output_path), cv2.VideoWriter_fourcc(*"mp4v"), fps if fps > 1.0 else 30.0, output_size)
    if not writer.isOpened():
        cap.release()
        return False
    by_frame_roi: dict[tuple[int, str], dict[str, Any]] = {}
    for row in frame_rows:
        by_frame_roi[(int(row["frame"]), str(row["roi"]))] = row
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    frame_index = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        display = frame.copy()
        lines = [f"source export f={frame_index} mag={magnification:.1f}x"]
        for roi_info in rois:
            name = roi_info["name"]
            x, y, w, h = roi_info["roi"]
            row = by_frame_roi.get((frame_index, name), {})
            color = (80, 220, 255) if bool(row.get("measured")) else (80, 80, 255)
            cv2.rectangle(display, (x, y), (x + w, y + h), color, 2)
            residual_x = finite_float(row.get("residualX"), 0.0)
            residual_y = finite_float(row.get("residualY"), 0.0)
            cx = x + w // 2
            cy = y + h // 2
            end = (int(round(cx + residual_x * magnification)), int(round(cy + residual_y * magnification)))
            cv2.arrowedLine(display, (cx, cy), end, (0, 255, 255), 2, tipLength=0.25)
            if row:
                lines.append(
                    f"{name} res={finite_float(row.get('residualPixels')):.2f}px "
                    f"dx={residual_x:+.2f} dy={residual_y:+.2f}"
                )
        if scale < 1.0:
            display = cv2.resize(display, output_size, interpolation=cv2.INTER_AREA)
        put_label_lines(display, lines)
        writer.write(display)
    writer.release()
    cap.release()
    return True


def create_synthetic_video(path: Path, amplitude: float, width: int = 960, height: int = 506, fps: float = 59.94) -> None:
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    if not writer.isOpened():
        fail(f"could not open synthetic video writer: {path}")
    base = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        base[y, :, :] = int(35 + (y / max(1, height - 1)) * 95)
    cv2.rectangle(base, (0, int(height * 0.55)), (width, height), (35, 55, 35), -1)
    points = []
    for x in range(0, width, 12):
        ridge_y = int(height * (0.30 + 0.04 * math.sin(x / 83.0)))
        points.append((x, ridge_y))
    for left, right in zip(points, points[1:]):
        cv2.line(base, left, right, (190, 190, 190), 2)
    rng = np.random.default_rng(7)
    for _ in range(350):
        x = int(rng.integers(0, width))
        y = int(rng.integers(int(height * 0.08), int(height * 0.48)))
        cv2.circle(base, (x, y), int(rng.integers(1, 3)), (160, 165, 165), -1)
    frame_count = 180
    for frame_index in range(frame_count):
        shift_y = amplitude * math.sin(2.0 * math.pi * frame_index / 30.0)
        matrix = np.asarray([[1.0, 0.0, 0.0], [0.0, 1.0, shift_y]], dtype=np.float32)
        frame = cv2.warpAffine(base, matrix, (width, height), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        writer.write(frame)
    writer.release()


def write_synthetic_case(path: Path, amplitude: float) -> None:
    case = {
        "caseId": f"synthetic_source_eval_{amplitude:.1f}px",
        "source": {"width": 960, "height": 506, "frameRate": "60000/1001"},
        "durationSeconds": 3.0,
        "sourceFrameEvaluation": {
            "enabled": True,
            "outputPixelSpace": "source",
            "visualReviewRequired": False,
            "motionMagnification": 8.0,
            "rois": [
                {"name": "synthetic_ridge", "x": 100, "y": 55, "w": 760, "h": 190},
                {"name": "synthetic_cloud", "x": 160, "y": 45, "w": 620, "h": 150},
            ],
            "pulseWindowsSeconds": {"min": 10.0 / 60.0, "max": 1.0},
            "qualityThresholds": {
                "minOutputWidthRatioToSource": 1.0,
                "minOutputHeightRatioToSource": 1.0,
                "baselineWindowSeconds": 0.8,
                "minMeasuredFrameRatio": 0.85,
                "minAffineTrackingRatio": 0.10,
                "minPhaseCorrelationResponse": 0.04,
                "maxHighFrequencyResidualPixels": 1.20,
                "maxHighFrequencyResidualP95Pixels": 0.24,
                "maxHorizontalResidualP95Pixels": 0.24,
                "maxVerticalResidualP95Pixels": 0.24,
                "maxJerkP95PixelsPerFrame": 0.18,
                "maxRidgeLineVerticalJerkP95PixelsPerFrame": 10.0,
                "residualRunThresholdPixels": 0.20,
                "maxResidualRunFrames": 7,
                "maxPulseAmplitudePixels": 0.18,
                "maxPtsIntervalIrregularRatio": 0.10,
                "requirePtsIntervalMetrics": True,
            },
        },
    }
    path.write_text(json.dumps(case, indent=2), encoding="utf-8")


def run_self_test() -> int:
    temp_dir = Path(tempfile.mkdtemp(prefix="stabilizer-source-quality-selftest-"))
    try:
        results: dict[str, bool] = {}
        stable_video = temp_dir / "stable.mp4"
        stable_case = temp_dir / "stable.json"
        create_synthetic_video(stable_video, 0.0)
        write_synthetic_case(stable_case, 0.0)
        results["stable"] = evaluate_source_video(
            stable_case,
            stable_video,
            temp_dir / "stable_metrics",
            "passed",
            write_diagnostic_videos=False,
        )

        for amplitude in (0.3, 0.5, 1.0):
            video = temp_dir / f"shake_{amplitude:.1f}.mp4"
            case = temp_dir / f"shake_{amplitude:.1f}.json"
            create_synthetic_video(video, amplitude)
            write_synthetic_case(case, amplitude)
            results[f"shake_{amplitude:.1f}"] = evaluate_source_video(
                case,
                video,
                temp_dir / f"shake_{amplitude:.1f}_metrics",
                "passed",
                write_diagnostic_videos=False,
            )

        small_video = temp_dir / "stable_small.mp4"
        create_synthetic_video(small_video, 0.0, width=480, height=254)
        results["downscaled"] = evaluate_source_video(
            stable_case,
            small_video,
            temp_dir / "downscaled_metrics",
            "passed",
            write_diagnostic_videos=False,
        )

        if not results["stable"]:
            fail("self-test stable video should pass", code=1)
        for key in ("shake_0.3", "shake_0.5", "shake_1.0", "downscaled"):
            if results[key]:
                fail(f"self-test {key} should fail", code=1)
        print(f"SELF-TEST PASS diagnostics={temp_dir}")
        return 0
    finally:
        if os.environ.get("STABILIZER_SOURCE_QUALITY_KEEP_SELFTEST") != "1":
            shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", type=Path, help="E2E case JSON with sourceFrameEvaluation.")
    parser.add_argument("--video", type=Path, help="FCP source/project-resolution export video.")
    parser.add_argument("--output-dir", type=Path, help="Diagnostics output directory.")
    parser.add_argument(
        "--visual-review",
        choices=("passed", "failed", "not-reviewed"),
        default=os.environ.get("STABILIZER_SOURCE_VISUAL_REVIEW", "not-reviewed"),
        help="Human review of the exported source-resolution video.",
    )
    parser.add_argument("--self-test", action="store_true", help="Run synthetic subpixel shake evaluator checks.")
    parser.add_argument(
        "--skip-diagnostic-videos",
        action="store_true",
        help="Write CSV/JSON metrics only; skip slow overlay and motion-magnified diagnostic videos.",
    )
    parser.add_argument(
        "--allow-invalid-export-analysis",
        action="store_true",
        help="Continue ROI analysis even when export duration/resolution preflight fails.",
    )
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()
    if args.case is None or args.video is None:
        fail("--case and --video are required unless --self-test is used")
    output_dir = args.output_dir or Path("/tmp/stabilizer_e2e") / args.video.stem / "source_frame_quality"
    return 0 if evaluate_source_video(
        args.case,
        args.video,
        output_dir,
        args.visual_review,
        write_diagnostic_videos=not args.skip_diagnostic_videos,
        allow_invalid_export_analysis=args.allow_invalid_export_analysis,
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
