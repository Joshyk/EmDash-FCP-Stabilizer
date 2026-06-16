#!/usr/bin/env python3
"""Shared FCPXMLD helpers for the Stabilizer Event Analyzer."""

from __future__ import annotations

import re
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path


SCHEMA_VERSION = 1


@dataclass(frozen=True)
class EventAsset:
    id: str
    name: str
    media_path: Path | None
    media_kind: str | None
    frame_duration: Fraction | None
    duration: Fraction | None
    source_start: Fraction
    width: int | None
    height: int | None
    unsupported: str | None = None


@dataclass(frozen=True)
class MediaRep:
    kind: str | None
    src: str


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def resolve_info_path(path: Path) -> tuple[Path, Path | None]:
    if path.is_dir():
        info = path / "Info.fcpxml"
        if not info.is_file():
            raise ValueError(f"FCPXMLD package did not contain Info.fcpxml: {path}")
        return info, path
    if path.is_file() and path.name == "Info.fcpxml" and path.parent.suffix == ".fcpxmld":
        return path, path.parent
    if path.is_file():
        return path, None
    raise FileNotFoundError(f"FCPXML source was not found: {path}")


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


def fraction_seconds(value: Fraction | None) -> float | None:
    if value is None:
        return None
    return round(float(value), 6)


def duration_timecode(duration: Fraction | None, frame_duration: Fraction | None) -> str | None:
    if duration is None or frame_duration is None or frame_duration <= 0:
        return None
    nominal_fps = max(1, int((Fraction(1, 1) / frame_duration) + Fraction(1, 2)))
    total_frames = int(duration / frame_duration + Fraction(1, 2))
    frames = total_frames % nominal_fps
    total_seconds = total_frames // nominal_fps
    seconds = total_seconds % 60
    total_minutes = total_seconds // 60
    minutes = total_minutes % 60
    hours = total_minutes // 60
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}:{frames:02d}"


def file_url_to_path(url: str) -> Path:
    if not url.startswith("file://"):
        raise ValueError(f"unsupported asset URL: {url}")
    parsed = urllib.parse.urlparse(url)
    return Path(urllib.parse.unquote(parsed.path))


def path_to_file_url(path: Path) -> str:
    return urllib.parse.urljoin("file:", urllib.parse.quote(str(path.resolve())))


def transcoded_media_reason(path: Path) -> str | None:
    parts = {part.lower() for part in path.parts}
    if "proxy media" in parts:
        return f"media path points to FCP Proxy Media; original media is required: {path}"
    if "high quality media" in parts:
        return f"media path points to FCP optimized media; original media is required: {path}"
    return None


def media_reps(asset: ET.Element) -> list[MediaRep]:
    reps: list[MediaRep] = []
    for child in asset:
        if local_name(child.tag) == "media-rep" and child.attrib.get("src"):
            reps.append(MediaRep(kind=child.attrib.get("kind"), src=child.attrib["src"]))
    return reps


def choose_original_asset_src(asset: ET.Element) -> tuple[str | None, str | None, str | None]:
    if asset.attrib.get("src"):
        return asset.attrib["src"], "asset-src", None
    reps = media_reps(asset)
    original_reps = [rep for rep in reps if rep.kind == "original-media"]
    if not original_reps:
        if reps:
            kinds = ", ".join(sorted({rep.kind or "unknown" for rep in reps}))
            return None, None, f"asset has no original-media media-rep; refusing {kinds}"
        return None, None, "asset has no media src or original-media media-rep"
    for rep in original_reps:
        try:
            if file_url_to_path(rep.src).exists():
                return rep.src, rep.kind, None
        except ValueError:
            pass
    first = original_reps[0]
    return first.src, first.kind, None


def resources(root: ET.Element) -> ET.Element:
    node = root.find("resources")
    if node is None:
        raise ValueError("FCPXML has no resources section")
    return node


def resource_map(root: ET.Element, tag_name: str) -> dict[str, ET.Element]:
    return {
        child.attrib["id"]: child
        for child in resources(root)
        if local_name(child.tag) == tag_name and child.attrib.get("id")
    }


def event_names(root: ET.Element) -> list[str]:
    names = []
    for element in root.iter():
        if local_name(element.tag) == "event" and element.attrib.get("name"):
            names.append(element.attrib["name"])
    return names


def parse_dimension(value: str | None) -> int | None:
    if not value:
        return None
    match = re.match(r"^\d+", value)
    return int(match.group(0)) if match else None


def load_event_assets(fcpxml_path: Path) -> list[EventAsset]:
    info_path, _ = resolve_info_path(fcpxml_path)
    root = ET.parse(info_path).getroot()
    formats = resource_map(root, "format")
    assets = resource_map(root, "asset")
    results: list[EventAsset] = []
    seen: set[str] = set()
    for asset_id, asset in assets.items():
        if asset.attrib.get("hasVideo") != "1":
            continue
        if asset_id in seen:
            continue
        seen.add(asset_id)
        src, media_kind, source_unsupported = choose_original_asset_src(asset)
        media_path: Path | None = None
        unsupported: str | None = source_unsupported
        if src:
            try:
                media_path = file_url_to_path(src)
            except ValueError as exc:
                unsupported = str(exc)

        fmt = formats.get(asset.attrib.get("format", ""))
        frame_duration = None
        width = None
        height = None
        if fmt is not None:
            if fmt.attrib.get("frameDuration"):
                frame_duration = parse_time(fmt.attrib.get("frameDuration"))
            width = parse_dimension(fmt.attrib.get("width"))
            height = parse_dimension(fmt.attrib.get("height"))
        if frame_duration is None and unsupported is None:
            unsupported = "asset format has no frameDuration"

        duration = None
        if asset.attrib.get("duration"):
            duration = parse_time(asset.attrib.get("duration"))
        elif unsupported is None:
            unsupported = "asset has no duration"

        if media_path is not None and not media_path.exists() and unsupported is None:
            if media_kind == "original-media":
                unsupported = f"original media file does not exist: {media_path}"
            else:
                unsupported = f"media file does not exist: {media_path}"
        if media_path is not None and unsupported is None:
            unsupported = transcoded_media_reason(media_path)

        results.append(
            EventAsset(
                id=asset_id,
                name=asset.attrib.get("name") or asset_id,
                media_path=media_path,
                media_kind=media_kind,
                frame_duration=frame_duration,
                duration=duration,
                source_start=parse_time(asset.attrib.get("start"), Fraction(0)),
                width=width,
                height=height,
                unsupported=unsupported,
            )
        )
    return results


def safe_file_component(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    normalized = normalized.strip("-._")
    return normalized[:80] or "clip"
