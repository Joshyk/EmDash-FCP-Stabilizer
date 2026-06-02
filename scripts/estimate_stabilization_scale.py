#!/usr/bin/env python3
"""Estimate dynamic stabilization/scale keyframes from FCPXML-backed media."""

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


SCHEMA_VERSION = 1
SAMPLE_WIDTH = 96
SAMPLE_HEIGHT = 54
MIN_SCALE = 100.0
MAX_SCALE = 112.0


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


def mean_abs_diff(previous: bytes, current: bytes) -> float:
    total = 0
    for a, b in zip(previous, current):
        total += abs(a - b)
    return total / max(1, len(current)) / 255.0


def smooth_strengths(strengths: list[float]) -> list[float]:
    if len(strengths) < 3:
        return strengths
    result = []
    for index, value in enumerate(strengths):
        if index == 0 or index == len(strengths) - 1:
            result.append(value)
            continue
        total = value * 0.5
        weight = 0.5
        if index > 0:
            total += strengths[index - 1] * 0.25
            weight += 0.25
        if index + 1 < len(strengths):
            total += strengths[index + 1] * 0.25
            weight += 0.25
        result.append(total / weight)
    return result


def build_samples(raw_motion: list[float], sample_fps: float, duration: float) -> list[dict]:
    if not raw_motion:
        raw_motion = [0.0]
    low = percentile(raw_motion, 20)
    high = percentile(raw_motion, 92)
    if high <= low:
        high = max(low + 0.01, max(raw_motion))
    strengths = [clamp((value - low) / (high - low), 0.0, 1.0) for value in raw_motion]
    strengths = smooth_strengths(strengths)

    samples = []
    for index, strength in enumerate(strengths):
        seconds = min(duration, index / sample_fps)
        scale = MIN_SCALE + (strength * (MAX_SCALE - MIN_SCALE))
        samples.append(
            {
                "timelineSeconds": round(seconds, 6),
                "rawMotion": round(raw_motion[index], 6),
                "strength": round(strength, 4),
                "scale": round(scale, 4),
                "translationSmooth": round(0.45 + (strength * 2.75), 4),
                "rotationSmooth": round(0.2 + (strength * 1.3), 4),
                "scaleSmooth": round(0.1 + (strength * 1.1), 4),
            }
        )

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
    sample_fps = frame_rate / interval_frames
    if sample_fps <= 0:
        sample_fps = 2.0
    expected_samples = max(1, int(math.ceil(duration * sample_fps)))
    if expected_samples > max_samples:
        sample_fps = max_samples / duration

    frames = extract_gray_frames(candidate.media_path, float(candidate.source_start), duration, sample_fps)
    raw_motion = [0.0]
    for index in range(1, len(frames)):
        raw_motion.append(mean_abs_diff(frames[index - 1], frames[index]))
    samples = build_samples(raw_motion, sample_fps, duration)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "model": "frame-difference-motion-v1",
        "clipName": candidate.name,
        "assetId": candidate.asset_id,
        "mediaPath": str(candidate.media_path),
        "frameRate": round(frame_rate, 6),
        "intervalFrames": interval_frames,
        "durationSeconds": round(duration, 6),
        "sampleFps": round(sample_fps, 6),
        "samples": samples,
        "warnings": [
            "Motion strength is estimated from frame differences; subject movement can increase the scale estimate."
        ],
    }


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fcpxml", required=True, type=Path)
    parser.add_argument("--interval-frames", required=True, type=int)
    parser.add_argument("--duration-seconds", type=float)
    parser.add_argument("--max-samples", type=int, default=180)
    return parser.parse_args(argv)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        candidates = load_candidates(args.fcpxml)
        candidate = choose_candidate(candidates, args.duration_seconds)
        return emit(estimate(candidate, args.interval_frames, args.max_samples, args.duration_seconds))
    except Exception as exc:  # noqa: BLE001 - command-line tool must return JSON errors.
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
