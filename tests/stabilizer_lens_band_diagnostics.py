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


def crop_band(gray: np.ndarray, y0: float, y1: float) -> tuple[np.ndarray, int]:
    height = gray.shape[0]
    top = max(0, min(height - 1, int(round(height * y0))))
    bottom = max(top + 8, min(height, int(round(height * y1))))
    return gray[top:bottom, :], top


def estimate_flow(previous: np.ndarray, current: np.ndarray, y_offset: int) -> dict[str, float]:
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
                previous_band, y_offset = crop_band(previous_gray, *bounds)
                current_band, _ = crop_band(gray, *bounds)
                metrics = estimate_flow(previous_band, current_band, y_offset)
                for key, value in metrics.items():
                    row[f"{name}.{key}"] = value
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
        summary[band_name] = band_summary
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
        "lensBandWarpSupport",
        "lensBandWarpApplied",
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
            ]
        )
    csv_path = args.output_dir / "lens_band_source_joined.csv"
    joined_rows: list[dict[str, Any]] = []
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        fieldnames = ["frame", "time", "renderRow", "renderRelativeTime", "renderTimeError"] + runtime_columns + band_columns
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
    for band_name in ("cloud_top", "ridge_horizon", "mountain_mid"):
        points = [finite_float(row.get(f"{band_name}.points")) for row in focus_joined]
        summary[f"{band_name}FocusPointsP50"] = float(np.percentile(points, 50)) if points else 0.0

    if args.require_band_warp and summary["focusLensBandWarpAppliedRows"] <= 0:
        raise SystemExit(
            "lens band diagnostics failed: target focus window had no bandWarp application; "
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
