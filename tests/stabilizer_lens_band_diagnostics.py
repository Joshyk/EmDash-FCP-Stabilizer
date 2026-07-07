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
from typing import Any

import cv2
import numpy as np


PAIR_PATTERN = re.compile(r"([A-Za-z][A-Za-z0-9]*)=([^ |]+)")
PREFIX = "Render frame components csv v1 |"

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


def finite_float(raw: Any, default: float = 0.0) -> float:
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return default
    return value if math.isfinite(value) else default


def parse_render_log(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if PREFIX not in line:
            continue
        values = dict(PAIR_PATTERN.findall(line.split(PREFIX, 1)[1]))
        if "analysisTime" not in values:
            continue
        rows.append(values)
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


def percentile_abs(rows: list[dict[str, Any]], key: str, percentile: float) -> float:
    values = [abs(finite_float(row.get(key))) for row in rows]
    return float(np.percentile(values, percentile)) if values else 0.0


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
    parser.add_argument("--require-band-warp", action="store_true")
    parser.add_argument("--forbid-global-lens", action="store_true")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    render_rows = parse_render_log(args.render_log)
    if not render_rows:
        raise SystemExit(f"lens band diagnostics found no render component rows: {args.render_log}")
    video_rows, summary = analyze_video(args.video, args.window_frames)
    summary["renderLog"] = str(args.render_log)
    summary["renderRows"] = len(render_rows)
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
        "lensBandTopX",
        "lensBandTopY",
        "lensBandRidgeX",
        "lensBandRidgeY",
        "lensBandMidX",
        "lensBandMidY",
        "lensBandTopColumnX",
        "lensBandTopColumnY",
        "lensBandRidgeColumnX",
        "lensBandRidgeColumnY",
        "lensBandMidColumnX",
        "lensBandMidColumnY",
        "lensBandWarpSupport",
        "lensBandWarpApplied",
        "lensBandRollingShutterScore",
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
            video_time = finite_float(video_row.get("time"))
            render_row = nearest_render_row(render_rows, video_time)
            render_relative_time = finite_float(render_row.get("_relativeTime"), math.nan)
            row: dict[str, Any] = {
                "frame": int(video_row["frame"]),
                "time": f"{video_row['time']:.5f}",
                "renderRow": render_row.get("_renderIndex", ""),
                "renderRelativeTime": f"{render_relative_time:.5f}" if math.isfinite(render_relative_time) else "",
                "renderTimeError": f"{render_relative_time - video_time:.5f}" if math.isfinite(render_relative_time) else "",
            }
            for column in runtime_columns:
                row[column] = render_row.get(column, "")
            row["lensBandSupport"] = render_row.get("lensBandWarpSupport", "")
            for column in derived_columns:
                if column == "lensBandSupport":
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
                else:
                    value = video_row.get(column, "")
                row[column] = f"{value:.6f}" if isinstance(value, float) else value
            for column in band_columns:
                value = video_row.get(column, "")
                row[column] = f"{value:.6f}" if isinstance(value, float) else value
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
    summary["focusLensBandWarpAppliedRows"] = sum(
        1 for row in focus_joined if finite_float(row.get("lensBandWarpApplied")) > 0.5
    )
    summary["focusGlobalLensAppliedRows"] = sum(
        1 for row in focus_joined if str(row.get("lensShakeReason")) == "applied"
    )
    summary["focusMaxAbsRenderTimeError"] = max(
        [abs(finite_float(row.get("renderTimeError"))) for row in focus_joined] or [0.0]
    )
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
    summary["focusLensBandResidualDominantModel"] = dominant_model
    summary["focusLensBandResidualDominantModelP95"] = dominant_model_value
    summary["focusLensBandResidualEvidence"] = (
        f"{dominant_model} p95={dominant_model_value:.3f}; "
        f"models={dict(focus_models)}; "
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
                        "runtimeBandWarpApplied": row.get("lensBandWarpApplied", ""),
                    }
                )
    summary["heatmapCsv"] = str(heatmap_path)

    if args.require_band_warp and summary["focusLensBandWarpAppliedRows"] <= 0:
        raise SystemExit(
            "lens band diagnostics failed: target focus window had no rollingRowWarp band application; "
            f"summary={args.output_dir / 'lens_band_source_summary.json'} csv={csv_path}"
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
