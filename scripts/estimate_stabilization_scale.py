#!/usr/bin/env python3
"""Estimate dynamic stabilization/scale keyframes from selected Final Cut Pro media."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 5
FXPLUG_CACHE_SCHEMA_VERSION = 1
SAMPLE_WIDTH = 96
SAMPLE_HEIGHT = 54
MIN_SCALE = 100.0
MAX_SCALE = 118.0
GLOBAL_SEARCH_RADIUS = 16
LOCAL_SEARCH_RADIUS = 5
MIN_MATCH_WIDTH = 18
MIN_MATCH_HEIGHT = 12
PAN_VELOCITY_THRESHOLD_PX = 1.25
SMOOTHING_RADIUS = 4
BLACK_STRIP_LUMA_THRESHOLD = 8
BLACK_STRIP_MIN_CONTENT_FRACTION = 0.06
BLACK_STRIP_SCALE_PADDING = 1.01
SCALE_SMOOTH_SECONDS = 4.0
POSITION_COMPENSATION_GAIN = 1.75
FXPLUG_MAX_SCALE = 1.35


@dataclass
class Candidate:
    name: str
    asset_id: str
    media_path: Path
    frame_duration: Fraction
    duration: Fraction
    source_start: Fraction
    unsupported: str | None = None


UNSUPPORTED_TIMING_TAGS = {"timeMap", "timept", "mc-clip", "ref-clip", "sync-clip"}


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return status


def fail(message: str, status: int = 1) -> int:
    return emit({"schemaVersion": SCHEMA_VERSION, "error": message}, status)


def write_progress(progress_file: Path | None, percent: float, message: str) -> None:
    if progress_file is None:
        return
    payload = {
        "percent": round(clamp(percent, 0.0, 1.0), 4),
        "message": message,
    }
    progress_file.parent.mkdir(parents=True, exist_ok=True)
    progress_file.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")


def parse_time(value: str | None, default: Fraction | None = None) -> Fraction:
    if value is None or value == "":
        if default is not None:
            return default
        raise ValueError("missing time value")
    text = value.strip()
    if text.endswith("s"):
        text = text[:-1]
    if "/" in text:
        return Fraction(text)
    return Fraction(text)


def file_url_to_path(url: str) -> Path:
    if not url.startswith("file://"):
        raise ValueError(f"unsupported asset URL: {url}")
    parsed = urllib.parse.urlparse(url)
    return Path(urllib.parse.unquote(parsed.path))


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def media_rep_sources(asset: ET.Element) -> list[str]:
    sources = []
    for child in asset:
        if local_name(child.tag) == "media-rep" and child.attrib.get("src"):
            sources.append(child.attrib["src"])
    return sources


def choose_asset_src(asset: ET.Element) -> str | None:
    if asset.attrib.get("src"):
        return asset.attrib["src"]
    sources = media_rep_sources(asset)
    for src in sources:
        try:
            if file_url_to_path(src).exists():
                return src
        except ValueError:
            pass
    return sources[0] if sources else None


def has_unsupported_timing(element: ET.Element) -> str | None:
    for child in element.iter():
        tag = local_name(child.tag)
        if tag in UNSUPPORTED_TIMING_TAGS:
            return tag
    return None


def unsupported_ancestor(ancestors: Iterable[ET.Element]) -> str | None:
    for ancestor in ancestors:
        tag = local_name(ancestor.tag)
        if tag in UNSUPPORTED_TIMING_TAGS:
            return tag
    return None


def candidate_context(element: ET.Element, ancestors: list[ET.Element]) -> ET.Element:
    for candidate in [element, *reversed(ancestors)]:
        if local_name(candidate.tag) in {"asset-clip", "clip"} and candidate.attrib.get("duration"):
            return candidate
    return element


def load_candidates(fcpxml_path: Path) -> list[Candidate]:
    root = ET.parse(fcpxml_path).getroot()
    resources = root.find("resources")
    if resources is None:
        raise ValueError("FCPXML has no resources section")

    formats = {}
    assets = {}
    for child in resources:
        tag = local_name(child.tag)
        if tag == "format":
            formats[child.attrib["id"]] = child.attrib
        elif tag == "asset":
            assets[child.attrib["id"]] = child

    candidates: list[Candidate] = []

    def visit(element: ET.Element, ancestors: list[ET.Element]) -> None:
        tag = local_name(element.tag)
        if tag in {"asset-clip", "video"}:
            asset_id = element.attrib.get("ref")
            if asset_id and asset_id in assets:
                asset = assets[asset_id]
                asset_attrib = asset.attrib
                if asset_attrib.get("hasVideo") == "1":
                    src = choose_asset_src(asset)
                    if src:
                        context = candidate_context(element, ancestors)
                        format_id = element.attrib.get("format") or context.attrib.get("format") or asset_attrib.get("format")
                        fmt = formats.get(format_id or "")
                        if not fmt or "frameDuration" not in fmt:
                            raise ValueError(f"clip {context.attrib.get('name', asset_id)} has no frameDuration format")

                        duration = parse_time(context.attrib.get("duration") or element.attrib.get("duration") or asset_attrib.get("duration"))
                        asset_start = parse_time(asset_attrib.get("start"), Fraction(0))
                        context_start = parse_time(context.attrib.get("start"), asset_start)
                        element_start = parse_time(element.attrib.get("start"), context_start)
                        source_start = max(Fraction(0), element_start - asset_start)
                        candidates.append(
                            Candidate(
                                name=context.attrib.get("name") or element.attrib.get("name") or asset_attrib.get("name") or asset_id,
                                asset_id=asset_id,
                                media_path=file_url_to_path(src),
                                frame_duration=parse_time(fmt["frameDuration"]),
                                duration=duration,
                                source_start=source_start,
                                unsupported=unsupported_ancestor(ancestors) or has_unsupported_timing(context),
                            )
                        )

        next_ancestors = [*ancestors, element]
        for child in element:
            visit(child, next_ancestors)

    visit(root, [])
    return candidates


def choose_candidate(candidates: list[Candidate], duration_seconds: float | None) -> Candidate:
    if not candidates:
        raise ValueError("FCPXML contains no supported asset-clip/video entries")
    if duration_seconds and duration_seconds > 0:
        matching = [
            candidate
            for candidate in candidates
            if abs(float(candidate.duration) - duration_seconds) <= max(0.25, float(candidate.frame_duration) * 3)
        ]
        if len(matching) == 1:
            return matching[0]
    if len(candidates) == 1:
        return candidates[0]
    details = ", ".join(f"{c.name} duration={float(c.duration):.3f}s" for c in candidates[:8])
    raise ValueError("FCPXML has multiple candidate clips; selected duration did not match uniquely. Candidates: " + details)


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def percentile(values: list[float], percent: float) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    position = (len(sorted_values) - 1) * (percent / 100.0)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return sorted_values[lower]
    lower_weight = upper - position
    upper_weight = position - lower
    return (sorted_values[lower] * lower_weight) + (sorted_values[upper] * upper_weight)


def extract_gray_frames(media_path: Path, source_start: float, duration: float, sample_fps: float) -> list[bytes]:
    frame_size = SAMPLE_WIDTH * SAMPLE_HEIGHT
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{max(0.0, source_start):.6f}",
        "-hwaccel",
        "videotoolbox",
        "-i",
        str(media_path),
        "-t",
        f"{max(0.01, duration):.6f}",
        "-vf",
        f"fps={sample_fps:.6f},scale={SAMPLE_WIDTH}:{SAMPLE_HEIGHT},format=gray",
        "-f",
        "rawvideo",
        "pipe:1",
    ]
    proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip() or "ffmpeg failed")
    data = proc.stdout
    if not data or len(data) < frame_size:
        raise RuntimeError("ffmpeg returned no grayscale frame data")
    usable = len(data) - (len(data) % frame_size)
    return [data[index : index + frame_size] for index in range(0, usable, frame_size)]


def probe_media_dimensions(media_path: Path) -> tuple[int, int]:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "json",
        str(media_path),
    ]
    proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip() or "ffprobe failed")
    payload = json.loads(proc.stdout.decode("utf-8", "replace"))
    streams = payload.get("streams") or []
    if not streams:
        raise RuntimeError("ffprobe returned no video stream dimensions")
    width = int(streams[0].get("width") or 0)
    height = int(streams[0].get("height") or 0)
    if width <= 0 or height <= 0:
        raise RuntimeError("ffprobe returned invalid video stream dimensions")
    return width, height


def mean_abs_diff(previous: bytes, current: bytes) -> float:
    total = 0
    for a, b in zip(previous, current):
        total += abs(a - b)
    return total / max(1, len(current)) / 255.0


def black_strip_metrics(frame: bytes, media_width: int, media_height: int) -> dict:
    column_min = max(1, int(SAMPLE_HEIGHT * BLACK_STRIP_MIN_CONTENT_FRACTION))
    row_min = max(1, int(SAMPLE_WIDTH * BLACK_STRIP_MIN_CONTENT_FRACTION))

    content_columns = []
    for x in range(SAMPLE_WIDTH):
        count = 0
        for y in range(SAMPLE_HEIGHT):
            if frame[(y * SAMPLE_WIDTH) + x] > BLACK_STRIP_LUMA_THRESHOLD:
                count += 1
        content_columns.append(count >= column_min)

    content_rows = []
    for y in range(SAMPLE_HEIGHT):
        row = frame[y * SAMPLE_WIDTH : (y + 1) * SAMPLE_WIDTH]
        content_rows.append(sum(1 for value in row if value > BLACK_STRIP_LUMA_THRESHOLD) >= row_min)

    if not any(content_columns) or not any(content_rows):
        return {
            "blackStripLeft": 0.0,
            "blackStripRight": 0.0,
            "blackStripTop": 0.0,
            "blackStripBottom": 0.0,
            "blackStripScale": MIN_SCALE,
            "blackStripOffsetX": 0.0,
            "blackStripOffsetY": 0.0,
        }

    left = next(index for index, has_content in enumerate(content_columns) if has_content)
    right = SAMPLE_WIDTH - next(index for index, has_content in enumerate(reversed(content_columns)) if has_content)
    top = next(index for index, has_content in enumerate(content_rows) if has_content)
    bottom = SAMPLE_HEIGHT - next(index for index, has_content in enumerate(reversed(content_rows)) if has_content)

    content_width = max(1, right - left)
    content_height = max(1, bottom - top)
    required_scale = max(SAMPLE_WIDTH / content_width, SAMPLE_HEIGHT / content_height) * 100.0 * BLACK_STRIP_SCALE_PADDING
    center_x = (left + right) * 0.5
    center_y = (top + bottom) * 0.5
    offset_x = -((center_x - (SAMPLE_WIDTH * 0.5)) * (media_width / SAMPLE_WIDTH))
    offset_y = -((center_y - (SAMPLE_HEIGHT * 0.5)) * (media_height / SAMPLE_HEIGHT))

    return {
        "blackStripLeft": round(left * (media_width / SAMPLE_WIDTH), 4),
        "blackStripRight": round((SAMPLE_WIDTH - right) * (media_width / SAMPLE_WIDTH), 4),
        "blackStripTop": round(top * (media_height / SAMPLE_HEIGHT), 4),
        "blackStripBottom": round((SAMPLE_HEIGHT - bottom) * (media_height / SAMPLE_HEIGHT), 4),
        "blackStripScale": round(clamp(required_scale, MIN_SCALE, MAX_SCALE), 4),
        "blackStripOffsetX": round(offset_x, 4),
        "blackStripOffsetY": round(offset_y, 4),
    }


def shifted_abs_diff(
    previous: bytes,
    current: bytes,
    dx: int,
    dy: int,
    x0: int,
    y0: int,
    width: int,
    height: int,
    stride: int = 2,
) -> float:
    x_start = max(x0, -dx, 0)
    y_start = max(y0, -dy, 0)
    x_end = min(x0 + width, SAMPLE_WIDTH - dx, SAMPLE_WIDTH)
    y_end = min(y0 + height, SAMPLE_HEIGHT - dy, SAMPLE_HEIGHT)
    if x_end - x_start < MIN_MATCH_WIDTH or y_end - y_start < MIN_MATCH_HEIGHT:
        return float("inf")

    total = 0
    count = 0
    for y in range(y_start, y_end, stride):
        previous_row = y * SAMPLE_WIDTH
        current_row = (y + dy) * SAMPLE_WIDTH
        for x in range(x_start, x_end, stride):
            total += abs(previous[previous_row + x] - current[current_row + x + dx])
            count += 1
    if count == 0:
        return float("inf")
    return total / count / 255.0


def estimate_shift(
    previous: bytes,
    current: bytes,
    x0: int,
    y0: int,
    width: int,
    height: int,
    radius: int,
    center: tuple[int, int] = (0, 0),
    refine: bool = False,
) -> tuple[float, float, float]:
    center_x, center_y = int(round(center[0])), int(round(center[1]))
    best_dx = center_x
    best_dy = center_y
    best_score = float("inf")
    for dy in range(center_y - radius, center_y + radius + 1):
        for dx in range(center_x - radius, center_x + radius + 1):
            score = shifted_abs_diff(previous, current, dx, dy, x0, y0, width, height)
            if score < best_score:
                best_dx = dx
                best_dy = dy
                best_score = score
    if not refine:
        return best_dx, best_dy, best_score

    def axis_offset(score_before: float, score_center: float, score_after: float) -> float:
        if not all(math.isfinite(score) for score in (score_before, score_center, score_after)):
            return 0.0
        denominator = score_before - (2.0 * score_center) + score_after
        if abs(denominator) < 1e-9:
            return 0.0
        return clamp(0.5 * (score_before - score_after) / denominator, -0.5, 0.5)

    x_before = shifted_abs_diff(previous, current, best_dx - 1, best_dy, x0, y0, width, height)
    x_after = shifted_abs_diff(previous, current, best_dx + 1, best_dy, x0, y0, width, height)
    y_before = shifted_abs_diff(previous, current, best_dx, best_dy - 1, x0, y0, width, height)
    y_after = shifted_abs_diff(previous, current, best_dx, best_dy + 1, x0, y0, width, height)
    refined_dx = best_dx + axis_offset(x_before, best_score, x_after)
    refined_dy = best_dy + axis_offset(y_before, best_score, y_after)
    return refined_dx, refined_dy, best_score


def moving_average(values: list[float], radius: int = 2) -> list[float]:
    if not values:
        return []
    averaged = []
    for index in range(len(values)):
        start = max(0, index - radius)
        end = min(len(values), index + radius + 1)
        window = values[start:end]
        averaged.append(sum(window) / len(window))
    return averaged


def moving_max(values: list[float], radius: int = 2) -> list[float]:
    if not values:
        return []
    radius = max(0, int(radius))
    output = []
    for index in range(len(values)):
        start = max(0, index - radius)
        end = min(len(values), index + radius + 1)
        output.append(max(values[start:end]))
    return output


def cumulative_sum(values: list[float]) -> list[float]:
    total = 0.0
    result = []
    for value in values:
        total += value
        result.append(total)
    return result


def smooth_values(values: list[float]) -> list[float]:
    if len(values) < 3:
        return values
    result = []
    for index, value in enumerate(values):
        if index == 0 or index == len(values) - 1:
            result.append(value)
            continue
        total = value * 0.5
        weight = 0.5
        if index > 0:
            total += values[index - 1] * 0.25
            weight += 0.25
        if index + 1 < len(values):
            total += values[index + 1] * 0.25
            weight += 0.25
        result.append(total / weight)
    return result


def normalize_series(values: list[float]) -> list[float]:
    if not values:
        return [0.0]
    low = percentile(values, 20)
    high = percentile(values, 92)
    if high <= low:
        high = max(low + 0.01, max(values))
    return [clamp((value - low) / (high - low), 0.0, 1.0) for value in values]


def pair_motion(previous: bytes, current: bytes) -> dict:
    raw_motion = mean_abs_diff(previous, current)
    dx, dy, residual = estimate_shift(
        previous,
        current,
        8,
        6,
        SAMPLE_WIDTH - 16,
        SAMPLE_HEIGHT - 12,
        GLOBAL_SEARCH_RADIUS,
        refine=True,
    )
    center = (int(round(dx)), int(round(dy)))
    left = estimate_shift(previous, current, 4, 8, 28, SAMPLE_HEIGHT - 16, LOCAL_SEARCH_RADIUS, center)
    right = estimate_shift(previous, current, SAMPLE_WIDTH - 32, 8, 28, SAMPLE_HEIGHT - 16, LOCAL_SEARCH_RADIUS, center)
    top = estimate_shift(previous, current, 12, 4, SAMPLE_WIDTH - 24, 20, LOCAL_SEARCH_RADIUS, center)
    bottom = estimate_shift(previous, current, 12, SAMPLE_HEIGHT - 24, SAMPLE_WIDTH - 24, 20, LOCAL_SEARCH_RADIUS, center)
    top_left = estimate_shift(previous, current, 6, 5, 24, 16, LOCAL_SEARCH_RADIUS, center)
    top_right = estimate_shift(previous, current, SAMPLE_WIDTH - 30, 5, 24, 16, LOCAL_SEARCH_RADIUS, center)
    bottom_left = estimate_shift(previous, current, 6, SAMPLE_HEIGHT - 21, 24, 16, LOCAL_SEARCH_RADIUS, center)
    bottom_right = estimate_shift(previous, current, SAMPLE_WIDTH - 30, SAMPLE_HEIGHT - 21, 24, 16, LOCAL_SEARCH_RADIUS, center)

    roll_from_vertical = (right[1] - left[1]) / max(1, SAMPLE_WIDTH - 32)
    horizontal_slope = (bottom[0] - top[0]) / max(1, SAMPLE_HEIGHT - 16)
    roll_from_horizontal = -horizontal_slope
    signed_roll = (roll_from_vertical + roll_from_horizontal) * 0.5
    roll_motion = max(abs(roll_from_vertical), abs(roll_from_horizontal))
    yaw_proxy = (right[0] - left[0]) / max(1, SAMPLE_WIDTH - 32)
    pitch_proxy = (bottom[1] - top[1]) / max(1, SAMPLE_HEIGHT - 16)
    shear_x = horizontal_slope + signed_roll
    shear_y = roll_from_vertical - signed_roll
    top_spread = top_right[0] - top_left[0]
    bottom_spread = bottom_right[0] - bottom_left[0]
    left_vertical_spread = bottom_left[1] - top_left[1]
    right_vertical_spread = bottom_right[1] - top_right[1]
    perspective_x = (top_spread - bottom_spread) / max(1, SAMPLE_WIDTH - 12)
    perspective_y = (left_vertical_spread - right_vertical_spread) / max(1, SAMPLE_HEIGHT - 10)

    return {
        "rawMotion": raw_motion,
        "globalDx": float(dx),
        "globalDy": float(dy),
        "residualMotion": residual,
        "rollMotion": roll_motion,
        "signedRollMotion": signed_roll,
        "yawProxy": yaw_proxy,
        "pitchProxy": pitch_proxy,
        "shearX": shear_x,
        "shearY": shear_y,
        "perspectiveX": perspective_x,
        "perspectiveY": perspective_y,
    }


def centered_difference(values: list[float], index: int) -> float:
    if len(values) < 3:
        return 0.0
    previous_index = max(0, index - 1)
    next_index = min(len(values) - 1, index + 1)
    return values[index] - ((values[previous_index] + values[next_index]) * 0.5)


def blur_amount(frame: bytes) -> float:
    total_gradient = 0.0
    count = 0
    for y in range(1, SAMPLE_HEIGHT - 1):
        row = y * SAMPLE_WIDTH
        for x in range(1, SAMPLE_WIDTH - 1):
            horizontal = abs(frame[row + x + 1] - frame[row + x - 1])
            vertical = abs(frame[row + SAMPLE_WIDTH + x] - frame[row - SAMPLE_WIDTH + x])
            total_gradient += (horizontal + vertical) / 510.0
            count += 1
    if count <= 0:
        return 1.0
    sharpness = total_gradient / count
    return 1.0 - clamp((sharpness - 0.015) / 0.11, 0.0, 1.0)


def closest_index(times: list[float], target: float) -> int:
    best_index = 0
    best_distance = float("inf")
    for index, value in enumerate(times):
        distance = abs(value - target)
        if distance < best_distance:
            best_index = index
            best_distance = distance
    return best_index


def time_weighted_average(values: list[float], times: list[float], indices: list[int], center_time: float, window_seconds: float) -> float:
    if not indices:
        return 0.0
    if len(indices) == 1:
        return values[indices[0]]

    sorted_indices = sorted(indices)
    window_start = center_time - (window_seconds * 0.5)
    window_end = center_time + (window_seconds * 0.5)
    weighted_total = 0.0
    total_weight = 0.0
    for position, index in enumerate(sorted_indices):
        current_time = times[index]
        if position > 0:
            left_boundary = max(window_start, (times[sorted_indices[position - 1]] + current_time) * 0.5)
        else:
            left_boundary = window_start
        if position + 1 < len(sorted_indices):
            right_boundary = min(window_end, (current_time + times[sorted_indices[position + 1]]) * 0.5)
        else:
            right_boundary = window_end
        weight = max(0.0, right_boundary - left_boundary)
        weighted_total += values[index] * weight
        total_weight += weight

    if total_weight <= 1e-9:
        return sum(values[index] for index in indices) / len(indices)
    return weighted_total / total_weight


def max_value(values: list[float], indices: list[int]) -> float:
    if not indices:
        return 0.0
    return max(values[index] for index in indices)


def build_fxplug_cache_samples(
    motions: list[dict],
    blur_values: list[float],
    sample_fps: float,
    duration: float,
    media_width: int,
    media_height: int,
    pan_smooth_seconds: float,
) -> list[dict]:
    if not motions:
        motions = [{"globalDx": 0.0, "globalDy": 0.0, "residualMotion": 0.0, "rollMotion": 0.0, "signedRollMotion": 0.0}]
    if not blur_values:
        blur_values = [0.0 for _ in motions]

    count = min(len(motions), len(blur_values))
    motions = motions[:count]
    blur_values = blur_values[:count]
    times = [min(duration, index / sample_fps) for index in range(count)]
    dx_values = [motion.get("globalDx", 0.0) for motion in motions]
    dy_values = [motion.get("globalDy", 0.0) for motion in motions]
    residual_values = [motion.get("residualMotion", 0.0) for motion in motions]
    signed_roll_values = [motion.get("signedRollMotion", 0.0) for motion in motions]
    roll_motion_values = [motion.get("rollMotion", 0.0) for motion in motions]
    yaw_values = [motion.get("yawProxy", 0.0) for motion in motions]
    pitch_values = [motion.get("pitchProxy", 0.0) for motion in motions]
    shear_x_values = [motion.get("shearX", 0.0) for motion in motions]
    shear_y_values = [motion.get("shearY", 0.0) for motion in motions]
    perspective_x_values = [motion.get("perspectiveX", 0.0) for motion in motions]
    perspective_y_values = [motion.get("perspectiveY", 0.0) for motion in motions]

    path_x = cumulative_sum(dx_values)
    path_y = cumulative_sum(dy_values)
    path_roll = [math.degrees(value) for value in cumulative_sum(signed_roll_values)]
    path_yaw = cumulative_sum(yaw_values)
    path_pitch = cumulative_sum(pitch_values)
    path_shear_x = cumulative_sum(shear_x_values)
    path_shear_y = cumulative_sum(shear_y_values)
    path_perspective_x = cumulative_sum(perspective_x_values)
    path_perspective_y = cumulative_sum(perspective_y_values)

    window_seconds = max(0.1, pan_smooth_seconds)
    x_scale = media_width / SAMPLE_WIDTH
    y_scale = media_height / SAMPLE_HEIGHT
    samples = []
    for index, seconds in enumerate(times):
        window_indices = [item for item, item_time in enumerate(times) if abs(item_time - seconds) <= window_seconds * 0.5]
        active_indices = window_indices or list(range(count))
        smooth_x = time_weighted_average(path_x, times, active_indices, seconds, window_seconds)
        smooth_y = time_weighted_average(path_y, times, active_indices, seconds, window_seconds)
        smooth_roll = time_weighted_average(path_roll, times, active_indices, seconds, window_seconds)
        smooth_yaw = time_weighted_average(path_yaw, times, active_indices, seconds, window_seconds)
        smooth_pitch = time_weighted_average(path_pitch, times, active_indices, seconds, window_seconds)
        smooth_shear_x = time_weighted_average(path_shear_x, times, active_indices, seconds, window_seconds)
        smooth_shear_y = time_weighted_average(path_shear_y, times, active_indices, seconds, window_seconds)
        smooth_perspective_x = time_weighted_average(path_perspective_x, times, active_indices, seconds, window_seconds)
        smooth_perspective_y = time_weighted_average(path_perspective_y, times, active_indices, seconds, window_seconds)
        residual = max_value(residual_values, active_indices)
        blur = time_weighted_average(blur_values, times, active_indices, seconds, window_seconds)
        confidence = clamp(1.0 - (residual * 1.6) - (blur * 0.35), 0.25, 1.0)
        compensation_x = -(path_x[index] - smooth_x) * x_scale * POSITION_COMPENSATION_GAIN * confidence
        compensation_y = -(path_y[index] - smooth_y) * y_scale * POSITION_COMPENSATION_GAIN * confidence
        compensation_rotation = -(path_roll[index] - smooth_roll) * confidence
        compensation_yaw = clamp(-(path_yaw[index] - smooth_yaw) * 1.4 * confidence, -0.18, 0.18)
        compensation_pitch = clamp(-(path_pitch[index] - smooth_pitch) * 1.4 * confidence, -0.18, 0.18)
        compensation_shear_x = clamp(-(path_shear_x[index] - smooth_shear_x) * 1.3 * confidence, -0.16, 0.16)
        compensation_shear_y = clamp(-(path_shear_y[index] - smooth_shear_y) * 1.3 * confidence, -0.16, 0.16)
        compensation_perspective_x = clamp(-(path_perspective_x[index] - smooth_perspective_x) * 1.2 * confidence, -0.16, 0.16)
        compensation_perspective_y = clamp(-(path_perspective_y[index] - smooth_perspective_y) * 1.2 * confidence, -0.16, 0.16)

        local_motion_indices = [item for item, item_time in enumerate(times) if abs(item_time - seconds) <= (4.5 / 30.0)]
        active_motion_indices = local_motion_indices or [index]
        roll_motion = max_value(roll_motion_values, active_motion_indices)
        translation_scale = max(
            1.0 + (2.0 * abs(compensation_x) / max(1.0, media_width)),
            1.0 + (2.0 * abs(compensation_y) / max(1.0, media_height)),
        )
        rotation_scale = 1.0 + min(0.12, abs(compensation_rotation) * 0.006)
        jitter_scale = 1.0 + min(0.10, (residual * 0.10) + (roll_motion * 0.45))
        warp_scale = 1.0 + min(
            0.20,
            (
                abs(compensation_yaw)
                + abs(compensation_pitch)
                + abs(compensation_shear_x)
                + abs(compensation_shear_y)
                + abs(compensation_perspective_x)
                + abs(compensation_perspective_y)
            )
            * 0.55,
        )
        blur_scale = 1.0 + min(0.06, blur * 0.06)
        crop_safety = max(1.0, translation_scale, rotation_scale, warp_scale)
        scale = min(FXPLUG_MAX_SCALE, max(crop_safety, jitter_scale, blur_scale))

        samples.append(
            {
                "timeSeconds": round(seconds, 6),
                "pixelOffsetX": round(compensation_x, 4),
                "pixelOffsetY": round(compensation_y, 4),
                "rotationDegrees": round(compensation_rotation, 4),
                "scaleMultiplier": round(scale, 6),
                "yawPitchProxyX": round(compensation_yaw, 6),
                "yawPitchProxyY": round(compensation_pitch, 6),
                "shearX": round(compensation_shear_x, 6),
                "shearY": round(compensation_shear_y, 6),
                "perspectiveX": round(compensation_perspective_x, 6),
                "perspectiveY": round(compensation_perspective_y, 6),
                "cropSafety": round(crop_safety, 6),
                "blurAmount": round(blur, 6),
            }
        )

    if samples and samples[-1]["timeSeconds"] < duration - 0.05:
        last = dict(samples[-1])
        last["timeSeconds"] = round(duration, 6)
        samples.append(last)
    return samples


def build_samples(motions: list[dict], black_metrics: list[dict], sample_fps: float, duration: float, media_width: int, media_height: int) -> list[dict]:
    if not motions:
        motions = [{"rawMotion": 0.0, "globalDx": 0.0, "globalDy": 0.0, "residualMotion": 0.0, "rollMotion": 0.0, "signedRollMotion": 0.0}]

    dx_values = [motion["globalDx"] for motion in motions]
    dy_values = [motion["globalDy"] for motion in motions]
    raw_values = [motion["rawMotion"] for motion in motions]
    residual_values = [motion["residualMotion"] for motion in motions]
    signed_roll_values = [motion.get("signedRollMotion", 0.0) for motion in motions]
    path_x = cumulative_sum(dx_values)
    path_y = cumulative_sum(dy_values)
    path_roll_degrees = [math.degrees(value) for value in cumulative_sum(signed_roll_values)]
    smooth_x = moving_average(path_x, radius=SMOOTHING_RADIUS)
    smooth_y = moving_average(path_y, radius=SMOOTHING_RADIUS)
    smooth_roll = moving_average(path_roll_degrees, radius=SMOOTHING_RADIUS)
    pan_trend = moving_average(dx_values, radius=3)

    gimbal_values = []
    pan_rotation_values = []
    scale_values = []
    for index, motion in enumerate(motions):
        dx_jitter = centered_difference(dx_values, index)
        dy_jitter = centered_difference(dy_values, index)
        gimbal_jitter = math.hypot(dx_jitter, dy_jitter) + (motion["residualMotion"] * 10.0)
        pan_velocity = abs(pan_trend[index])
        pan_irregularity = abs(dx_values[index] - pan_trend[index])
        pan_rotation = motion["rollMotion"] * 80.0
        if pan_velocity >= PAN_VELOCITY_THRESHOLD_PX:
            pan_rotation += pan_irregularity * 0.75
        gimbal_values.append(gimbal_jitter)
        pan_rotation_values.append(pan_rotation)
        scale_values.append(max(gimbal_jitter * 0.85, pan_rotation * 0.9, residual_values[index] * 8.0))

    gimbal_strengths = smooth_values(normalize_series(gimbal_values))
    pan_rotation_strengths = smooth_values(normalize_series(pan_rotation_values))
    residual_strengths = smooth_values(normalize_series(residual_values))
    raw_strengths = smooth_values(normalize_series(raw_values))
    scale_strengths = smooth_values(normalize_series(scale_values))

    samples = []
    raw_transform_scales = []
    for index, motion in enumerate(motions):
        seconds = min(duration, index / sample_fps)
        gimbal_strength = gimbal_strengths[index]
        pan_rotation_strength = pan_rotation_strengths[index]
        residual_strength = residual_strengths[index]
        raw_strength = raw_strengths[index]
        strength = clamp(
            max(gimbal_strength * 0.9, pan_rotation_strength, residual_strength * 0.45, raw_strength * 0.25),
            0.0,
            1.0,
        )
        scale_strength = clamp(max(scale_strengths[index], strength * 0.75), 0.0, 1.0)
        scale = MIN_SCALE + (scale_strength * (MAX_SCALE - MIN_SCALE))
        compensation_x = -(path_x[index] - smooth_x[index]) * (media_width / SAMPLE_WIDTH) * POSITION_COMPENSATION_GAIN
        compensation_y = -(path_y[index] - smooth_y[index]) * (media_height / SAMPLE_HEIGHT) * POSITION_COMPENSATION_GAIN
        compensation_rotation = -(path_roll_degrees[index] - smooth_roll[index])
        black_metric = black_metrics[index] if index < len(black_metrics) else {}
        black_strip_scale = float(black_metric.get("blackStripScale", MIN_SCALE))
        black_strip_offset_x = float(black_metric.get("blackStripOffsetX", 0.0))
        black_strip_offset_y = float(black_metric.get("blackStripOffsetY", 0.0))
        transform_x = compensation_x + black_strip_offset_x
        transform_y = compensation_y + black_strip_offset_y
        translation_scale = max(
            100.0 * (1.0 + (2.0 * abs(transform_x) / max(1, media_width))),
            100.0 * (1.0 + (2.0 * abs(transform_y) / max(1, media_height))),
        )
        transform_scale = clamp(max(scale, black_strip_scale, translation_scale), MIN_SCALE, MAX_SCALE)
        raw_transform_scales.append(transform_scale)
        samples.append(
            {
                "timelineSeconds": round(seconds, 6),
                "rawMotion": round(motion["rawMotion"], 6),
                "globalDx": round(motion["globalDx"], 4),
                "globalDy": round(motion["globalDy"], 4),
                "residualMotion": round(motion["residualMotion"], 6),
                "gimbalJitter": round(gimbal_values[index], 6),
                "panRotation": round(pan_rotation_values[index], 6),
                "signedRollMotion": round(motion.get("signedRollMotion", 0.0), 6),
                "strength": round(strength, 4),
                "gimbalStrength": round(gimbal_strength, 4),
                "panRotationStrength": round(pan_rotation_strength, 4),
                "scaleStrength": round(scale_strength, 4),
                "rawScale": round(transform_scale, 4),
                "scale": round(transform_scale, 4),
                "transformX": round(transform_x, 4),
                "transformY": round(transform_y, 4),
                "transformRotation": round(compensation_rotation, 4),
                "stabilizerTransformX": round(compensation_x, 4),
                "stabilizerTransformY": round(compensation_y, 4),
                "positionGain": POSITION_COMPENSATION_GAIN,
                "blackStripOffsetX": round(black_strip_offset_x, 4),
                "blackStripOffsetY": round(black_strip_offset_y, 4),
                "blackStripScale": round(black_strip_scale, 4),
                "blackStripLeft": black_metric.get("blackStripLeft", 0.0),
                "blackStripRight": black_metric.get("blackStripRight", 0.0),
                "blackStripTop": black_metric.get("blackStripTop", 0.0),
                "blackStripBottom": black_metric.get("blackStripBottom", 0.0),
            }
        )

    scale_smooth_radius = max(1, int(round(sample_fps * SCALE_SMOOTH_SECONDS * 0.5)))
    scale_envelope = moving_max(raw_transform_scales, radius=scale_smooth_radius)
    smoothed_scales = moving_average(scale_envelope, radius=scale_smooth_radius)
    for index, sample in enumerate(samples):
        raw_scale = raw_transform_scales[index]
        sample["scale"] = round(clamp(max(raw_scale, smoothed_scales[index]), MIN_SCALE, MAX_SCALE), 4)
        sample["scaleSmoothSeconds"] = SCALE_SMOOTH_SECONDS

    if samples[-1]["timelineSeconds"] < duration - 0.05:
        last = dict(samples[-1])
        last["timelineSeconds"] = round(duration, 6)
        samples.append(last)
    return samples


def estimate(candidate: Candidate, interval_frames: int, max_samples: int, duration_seconds: float | None) -> dict:
    if candidate.unsupported:
        raise ValueError(f"unsupported FCPXML timing/clip structure for V1: {candidate.unsupported}")
    if not candidate.media_path.exists():
        raise FileNotFoundError(f"media file does not exist: {candidate.media_path}")
    if interval_frames < 1:
        raise ValueError("interval frames must be >= 1")

    frame_rate = float(Fraction(1, 1) / candidate.frame_duration)
    duration = min(float(candidate.duration), duration_seconds) if duration_seconds and duration_seconds > 0 else float(candidate.duration)
    media_width, media_height = probe_media_dimensions(candidate.media_path)
    sample_fps = frame_rate / interval_frames
    if sample_fps <= 0:
        sample_fps = 2.0
    expected_samples = max(1, int(math.ceil(duration * sample_fps)))
    if expected_samples > max_samples:
        sample_fps = max_samples / duration

    frames = extract_gray_frames(candidate.media_path, float(candidate.source_start), duration, sample_fps)
    black_metrics = [black_strip_metrics(frame, media_width, media_height) for frame in frames]
    motions = [
        {"rawMotion": 0.0, "globalDx": 0.0, "globalDy": 0.0, "residualMotion": 0.0, "rollMotion": 0.0, "signedRollMotion": 0.0}
    ]
    for index in range(1, len(frames)):
        motions.append(pair_motion(frames[index - 1], frames[index]))
    samples = build_samples(motions, black_metrics, sample_fps, duration, media_width, media_height)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "model": "transform-keyframe-stabilization-v5",
        "clipName": candidate.name,
        "assetId": candidate.asset_id,
        "mediaPath": str(candidate.media_path),
        "mediaWidth": media_width,
        "mediaHeight": media_height,
        "frameRate": round(frame_rate, 6),
        "intervalFrames": interval_frames,
        "durationSeconds": round(duration, 6),
        "sampleFps": round(sample_fps, 6),
        "samples": samples,
        "warnings": [
            "Transform compensation is estimated from low-resolution global frame motion; foreground-only movement can still affect the estimate.",
            "Final Cut Pro built-in Stabilization is intentionally not used, so crop/scale is controlled only by Transform Scale All.",
            "Black strip removal is estimated from source media frames; effects that create black after Final Cut Pro rendering may need extra scale tuning.",
            f"Transform Position uses sub-pixel global motion refinement and a {POSITION_COMPENSATION_GAIN:.2f}x compensation gain.",
            f"Transform Scale All is smoothed over about {SCALE_SMOOTH_SECONDS:.1f} seconds to avoid visible zoom stepping.",
        ],
    }


def estimate_fxplug_cache(
    candidate: Candidate,
    cache_fps: float,
    max_samples: int,
    duration_seconds: float | None,
    pan_smooth_seconds: float,
    progress_file: Path | None,
) -> dict:
    write_progress(progress_file, 0.02, "Preparing selected clip analysis")
    if candidate.unsupported:
        raise ValueError(f"unsupported FCPXML timing/clip structure for FxPlug cache: {candidate.unsupported}")
    if not candidate.media_path.exists():
        raise FileNotFoundError(f"media file does not exist: {candidate.media_path}")

    write_progress(progress_file, 0.06, "Probing source media")
    frame_rate = float(Fraction(1, 1) / candidate.frame_duration)
    duration = min(float(candidate.duration), duration_seconds) if duration_seconds and duration_seconds > 0 else float(candidate.duration)
    if duration <= 0:
        raise ValueError("duration must be positive for FxPlug cache analysis")
    media_width, media_height = probe_media_dimensions(candidate.media_path)
    sample_fps = cache_fps if cache_fps and cache_fps > 0 else min(frame_rate, 15.0)
    sample_fps = min(max(1.0, sample_fps), max(1.0, frame_rate))
    expected_samples = max(1, int(math.ceil(duration * sample_fps)))
    if max_samples > 0 and expected_samples > max_samples:
        sample_fps = max_samples / duration

    write_progress(progress_file, 0.10, "Extracting analysis frames")
    frames = extract_gray_frames(candidate.media_path, float(candidate.source_start), duration, sample_fps)
    write_progress(progress_file, 0.50, f"Analyzing {len(frames)} frame samples")
    blur_values = [blur_amount(frame) for frame in frames]
    motions = [
        {
            "rawMotion": 0.0,
            "globalDx": 0.0,
            "globalDy": 0.0,
            "residualMotion": 0.0,
            "rollMotion": 0.0,
            "signedRollMotion": 0.0,
            "yawProxy": 0.0,
            "pitchProxy": 0.0,
            "shearX": 0.0,
            "shearY": 0.0,
            "perspectiveX": 0.0,
            "perspectiveY": 0.0,
        }
    ]
    progress_step = max(1, len(frames) // 80)
    for index in range(1, len(frames)):
        motions.append(pair_motion(frames[index - 1], frames[index]))
        if index % progress_step == 0:
            write_progress(progress_file, 0.50 + (0.32 * (index / max(1, len(frames) - 1))), f"Analyzing motion {index}/{len(frames) - 1}")

    write_progress(progress_file, 0.86, "Building cached stabilization values")
    samples = build_fxplug_cache_samples(
        motions,
        blur_values,
        sample_fps,
        duration,
        media_width,
        media_height,
        pan_smooth_seconds,
    )
    write_progress(progress_file, 0.96, "Writing FxPlug cache")

    return {
        "schemaVersion": FXPLUG_CACHE_SCHEMA_VERSION,
        "model": "fxplug-precomputed-stabilization-v1",
        "clipName": candidate.name,
        "assetId": candidate.asset_id,
        "mediaPath": str(candidate.media_path),
        "mediaWidth": media_width,
        "mediaHeight": media_height,
        "frameRate": round(frame_rate, 6),
        "durationSeconds": round(duration, 6),
        "sourceStartSeconds": round(float(candidate.source_start), 6),
        "sampleFps": round(sample_fps, 6),
        "panSmoothSeconds": round(max(0.1, pan_smooth_seconds), 6),
        "samples": samples,
        "warnings": [
            "FxPlug cache values are precomputed. Changing Pan Smooth Seconds in Final Cut Pro does not change cached motion until the cache is rebuilt.",
            "If the cache file is missing, the FxPlug effect uses its live frame analysis path.",
        ],
    }


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fcpxml", type=Path)
    parser.add_argument("--media-path", type=Path)
    parser.add_argument("--frame-duration")
    parser.add_argument("--source-start")
    parser.add_argument("--duration")
    parser.add_argument("--clip-name")
    parser.add_argument("--interval-frames", type=int, default=1)
    parser.add_argument("--duration-seconds", type=float)
    parser.add_argument("--max-samples", type=int, default=180)
    parser.add_argument("--fxplug-cache-output", type=Path)
    parser.add_argument("--fxplug-cache-fps", type=float, default=15.0)
    parser.add_argument("--fxplug-cache-max-samples", type=int, default=7200)
    parser.add_argument("--pan-smooth-seconds", type=float, default=6.0)
    parser.add_argument("--progress-file", type=Path)
    return parser.parse_args(argv)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        if args.media_path:
            if not args.frame_duration or not args.duration:
                raise ValueError("--media-path requires --frame-duration and --duration")
            candidate = Candidate(
                name=args.clip_name or args.media_path.name,
                asset_id="selected-pasteboard",
                media_path=args.media_path,
                frame_duration=parse_time(args.frame_duration),
                duration=parse_time(args.duration),
                source_start=parse_time(args.source_start, Fraction(0)),
            )
        else:
            if not args.fcpxml:
                raise ValueError("either --fcpxml or --media-path is required")
            candidates = load_candidates(args.fcpxml)
            candidate = choose_candidate(candidates, args.duration_seconds)
        if args.fxplug_cache_output:
            payload = estimate_fxplug_cache(
                candidate,
                args.fxplug_cache_fps,
                args.fxplug_cache_max_samples,
                args.duration_seconds,
                args.pan_smooth_seconds,
                args.progress_file,
            )
            args.fxplug_cache_output.parent.mkdir(parents=True, exist_ok=True)
            args.fxplug_cache_output.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
            write_progress(args.progress_file, 1.0, "FxPlug cache complete")
            return emit(
                {
                    "schemaVersion": FXPLUG_CACHE_SCHEMA_VERSION,
                    "model": payload["model"],
                    "cachePath": str(args.fxplug_cache_output),
                    "clipName": payload["clipName"],
                    "durationSeconds": payload["durationSeconds"],
                    "sampleFps": payload["sampleFps"],
                    "sampleCount": len(payload.get("samples") or []),
                    "panSmoothSeconds": payload["panSmoothSeconds"],
                }
            )
        return emit(estimate(candidate, args.interval_frames, args.max_samples, args.duration_seconds))
    except Exception as exc:  # noqa: BLE001 - command-line tool must return JSON errors.
        write_progress(args.progress_file, 1.0, "FxPlug cache failed")
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
