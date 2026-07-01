#!/usr/bin/env python3
"""Evaluate FCP Viewer screen recordings for Stabilizer zoom/crop regressions."""

from __future__ import annotations

import argparse
import csv
import json
import math
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


def write_csv(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    rows = list(rows)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_contact_sheet(
    video_path: Path,
    output_path: Path,
    viewer_roi: Roi,
    spike_frames: list[tuple[int, str]],
) -> None:
    if not spike_frames:
        return

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return

    tiles: list[np.ndarray] = []
    for frame_index, label in spike_frames[:12]:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok:
            continue
        tile = crop(frame, viewer_roi)
        tile = cv2.resize(tile, (360, 193), interpolation=cv2.INTER_AREA)
        cv2.putText(
            tile,
            label,
            (10, 24),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2,
            cv2.LINE_AA,
        )
        cv2.putText(
            tile,
            label,
            (10, 24),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )
        tiles.append(tile)
    cap.release()

    if not tiles:
        return
    cols = 3
    rows = math.ceil(len(tiles) / cols)
    blank = np.zeros_like(tiles[0])
    while len(tiles) < rows * cols:
        tiles.append(blank.copy())
    sheet_rows = []
    for row_index in range(rows):
        start = row_index * cols
        sheet_rows.append(np.hstack(tiles[start : start + cols]))
    cv2.imwrite(str(output_path), np.vstack(sheet_rows))


def summarize_failures(
    scale_rows: list[dict[str, Any]],
    edge_rows: list[dict[str, Any]],
    quality: dict[str, Any],
) -> tuple[bool, list[str], dict[str, Any]]:
    max_scale = max((abs(float(row.get("scaleResidualPercent", 0.0))) for row in scale_rows), default=0.0)
    max_edge = max((float(row.get("edgeResidualPx", 0.0)) for row in edge_rows), default=0.0)
    low_inlier_rows = [row for row in scale_rows if not bool(row.get("trackingOk"))]
    low_inlier_ratio = (len(low_inlier_rows) / len(scale_rows)) if scale_rows else 1.0

    scale_limit = float(quality.get("maxScaleResidualPercent", 0.85))
    edge_limit = float(quality.get("maxBlackEdgeResidualPixels", 18.0))
    low_inlier_limit = float(quality.get("maxLowInlierRatio", 0.1))

    failures: list[str] = []
    if max_scale > scale_limit:
        failures.append(f"scale residual {max_scale:.3f}% exceeds {scale_limit:.3f}%")
    if max_edge > edge_limit:
        failures.append(f"black-edge residual {max_edge:.1f}px exceeds {edge_limit:.1f}px")
    if low_inlier_ratio > low_inlier_limit:
        failures.append(f"low tracking ratio {low_inlier_ratio:.3f} exceeds {low_inlier_limit:.3f}")

    summary = {
        "maxAbsScaleResidualPercent": max_scale,
        "maxBlackEdgeResidualPixels": max_edge,
        "lowTrackingRatio": low_inlier_ratio,
        "scaleFrameCount": len(scale_rows),
        "edgeFrameCount": len(edge_rows),
        "thresholds": {
            "maxScaleResidualPercent": scale_limit,
            "maxBlackEdgeResidualPixels": edge_limit,
            "maxLowInlierRatio": low_inlier_limit,
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
    sample_fps = float(args.sample_fps or quality.get("targetSampleFps", 30.0))
    ignore_start = float(quality.get("ignoreStartSeconds", 1.0))
    ignore_end = float(quality.get("ignoreEndSeconds", 0.5))
    median_seconds = float(quality.get("rollingMedianWindowSeconds", 0.5))
    black_threshold = int(quality.get("blackThreshold", 8))
    min_inliers = int(quality.get("minTrackingInliers", 40))
    min_duration = float(quality.get("minDurationSeconds", case.get("durationSeconds", 0.0)))

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
    sample_step = max(1, int(round(fps / sample_fps)))

    ok, first_frame = cap.read()
    if not ok:
        fail(f"could not read first frame: {args.video}")
    frame_height, frame_width = first_frame.shape[:2]
    clamp_roi(viewer_roi, frame_width, frame_height, "viewer")
    clamp_roi(content_roi, viewer_roi[2], viewer_roi[3], "content")
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)

    edge_rows: list[dict[str, Any]] = []
    scale_rows: list[dict[str, Any]] = []
    previous_gray: np.ndarray | None = None
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
            transform = estimate_transform(previous_gray, content_gray, min_inliers)
            row = {
                "frame": frame_index,
                "previousFrame": previous_frame_index,
                "time": timestamp,
                "trackingOk": bool(transform.get("ok")),
                "reason": transform.get("reason") or "",
                "featureCount": int(transform.get("featureCount", 0)),
                "trackedCount": int(transform.get("trackedCount", 0)),
                "inliers": int(transform.get("inliers", 0)),
                "scalePercent": float(transform.get("scalePercent", 0.0)),
                "dx": float(transform.get("dx", 0.0)),
                "dy": float(transform.get("dy", 0.0)),
                "rotationDegrees": float(transform.get("rotationDegrees", 0.0)),
            }
            scale_rows.append(row)

        previous_gray = content_gray
        previous_frame_index = frame_index

    cap.release()

    if not edge_rows:
        fail("no sampled frames were read")

    median_window = max(3, int(round(median_seconds * sample_fps)))
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

    cutoff_end = max(0.0, duration - ignore_end) if duration > 0 else float("inf")
    filtered_edges = [row for row in edge_rows if ignore_start <= float(row["time"]) <= cutoff_end]
    filtered_scales = [row for row in scale_rows if ignore_start <= float(row["time"]) <= cutoff_end]

    passed, failures, summary = summarize_failures(filtered_scales, filtered_edges, quality)
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
            "sampleFps": fps / sample_step,
            "viewerRoi": {"x": viewer_roi[0], "y": viewer_roi[1], "w": viewer_roi[2], "h": viewer_roi[3]},
            "contentRoi": {"x": content_roi[0], "y": content_roi[1], "w": content_roi[2], "h": content_roi[3]},
            "ignoreStartSeconds": ignore_start,
            "ignoreEndSeconds": ignore_end,
            "minDurationSeconds": min_duration,
            "pass": passed,
            "failures": failures,
        }
    )

    write_csv(output_dir / "edge_stats.csv", edge_rows)
    write_csv(output_dir / "scale_stats.csv", scale_rows)
    (output_dir / "metrics.json").write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

    scale_spikes = sorted(
        filtered_scales,
        key=lambda row: abs(float(row.get("scaleResidualPercent", 0.0))),
        reverse=True,
    )[:6]
    edge_spikes = sorted(
        filtered_edges,
        key=lambda row: float(row.get("edgeResidualPx", 0.0)),
        reverse=True,
    )[:6]
    spike_frames: list[tuple[int, str]] = []
    for row in scale_spikes:
        spike_frames.append((int(row["frame"]), f"scale {float(row['scaleResidualPercent']):+.2f}% t={float(row['time']):.2f}s"))
    for row in edge_spikes:
        spike_frames.append((int(row["frame"]), f"edge {float(row['edgeResidualPx']):.1f}px t={float(row['time']):.2f}s"))
    write_contact_sheet(args.video, output_dir / "spikes_contact_sheet.png", viewer_roi, spike_frames)

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
        "  low tracking ratio: "
        f"{summary['lowTrackingRatio']:.3f} "
        f"(limit {summary['thresholds']['maxLowInlierRatio']:.3f})"
    )
    print(f"  diagnostics: {output_dir}")
    for item in failures:
        print(f"  failure: {item}")

    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
