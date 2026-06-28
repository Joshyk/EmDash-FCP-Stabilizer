#!/usr/bin/env python3
"""Shared FCPXMLD helpers for the Stabilizer Event Analyzer."""

from __future__ import annotations

import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path


SCHEMA_VERSION = 1
REPO_ROOT = Path(__file__).resolve().parents[1]
FCPBUNDLE_SOURCE_CACHE = REPO_ROOT / ".cache" / "fcpbundle_sources"
FCPBUNDLE_SYNTHETIC_SCHEMA_VERSION = 8
VIDEO_MEDIA_EXTENSIONS = {
    ".3gp",
    ".avi",
    ".m2t",
    ".m2ts",
    ".m4v",
    ".mov",
    ".mp4",
    ".mts",
    ".mxf",
}


@dataclass(frozen=True)
class EventAsset:
    id: str
    name: str
    media_path: Path | None
    media_kind: str | None
    event_name: str | None
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


@dataclass(frozen=True)
class VideoMetadata:
    width: int
    height: int
    frame_duration: Fraction
    duration: Fraction
    color_space: str | None
    audio_channels: int | None = None
    audio_rate: int | None = None


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def resolve_info_path(path: Path) -> tuple[Path, Path | None]:
    path = path.expanduser()
    if path.is_dir() and path.suffix == ".fcpbundle":
        resolved = path.resolve()
        return materialize_fcpbundle_info(resolved), resolved
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


def time_string(value: Fraction) -> str:
    if value.denominator == 1:
        return f"{value.numerator}s"
    return f"{value.numerator}/{value.denominator}s"


def stable_fcp_asset_uid(seed: str) -> str:
    return hashlib.md5(seed.encode("utf-8")).hexdigest().upper()


def fcpbundle_media_uid(media_path: Path) -> str:
    try:
        target = media_path.resolve(strict=False)
    except OSError:
        target = media_path
    seed_parts = [str(target)]
    try:
        stat = media_path.stat()
        seed_parts.extend([str(stat.st_size), str(stat.st_mtime_ns)])
    except OSError:
        pass
    return stable_fcp_asset_uid("|".join(seed_parts))


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


def event_name_by_asset_id(root: ET.Element) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for event in root.iter():
        if local_name(event.tag) != "event":
            continue
        event_name = event.attrib.get("name")
        if not event_name:
            continue
        for child in event.iter():
            if local_name(child.tag) == "asset-clip" and child.attrib.get("ref"):
                mapping.setdefault(child.attrib["ref"], event_name)
    return mapping


def fcpbundle_event_dirs(bundle_path: Path) -> list[Path]:
    return [
        child
        for child in sorted(bundle_path.iterdir(), key=lambda item: item.name.casefold())
        if child.is_dir() and not child.name.startswith(".") and (child / "Original Media").is_dir()
    ]


def fcpbundle_media_files(bundle_path: Path) -> list[tuple[Path, Path]]:
    media_files: list[tuple[Path, Path]] = []
    for event_dir in fcpbundle_event_dirs(bundle_path):
        original_media = event_dir / "Original Media"
        for media_path in sorted(original_media.rglob("*"), key=lambda item: str(item).casefold()):
            if not media_path.is_file() and not media_path.is_symlink():
                continue
            if media_path.name.startswith(".") or media_path.suffix.lower() not in VIDEO_MEDIA_EXTENSIONS:
                continue
            media_files.append((event_dir, media_path))
    return media_files


def fcpbundle_original_media_link_reason(media_path: Path) -> str | None:
    if not media_path.is_symlink():
        return None
    target_path = media_path.resolve(strict=False)
    if not media_path.exists():
        return f"Broken original link - target not found: {target_path}"
    if not target_path.is_file():
        return f"Broken original link - target is not a file: {target_path}"
    return None


def fcpbundle_media_signature_item(event_dir: Path, media_path: Path) -> dict:
    entry_stat = media_path.lstat()
    item = {
        "event": event_dir.name,
        "path": str(media_path),
        "entrySize": entry_stat.st_size,
        "entryMtimeNs": entry_stat.st_mtime_ns,
        "isSymlink": media_path.is_symlink(),
    }
    if media_path.is_symlink():
        try:
            item["linkTarget"] = str(media_path.readlink())
        except OSError as exc:
            item["linkTargetError"] = str(exc)
    try:
        target_stat = media_path.stat()
        item.update(
            {
                "targetExists": True,
                "targetIsFile": media_path.is_file(),
                "size": target_stat.st_size,
                "mtimeNs": target_stat.st_mtime_ns,
            }
        )
    except OSError as exc:
        item.update(
            {
                "targetExists": False,
                "targetIsFile": False,
                "targetError": str(exc),
                "size": None,
                "mtimeNs": None,
            }
        )
    return item


def fcpbundle_signature(bundle_path: Path, media_files: list[tuple[Path, Path]]) -> dict:
    items = [fcpbundle_media_signature_item(event_dir, media_path) for event_dir, media_path in media_files]
    return {
        "syntheticSchemaVersion": FCPBUNDLE_SYNTHETIC_SCHEMA_VERSION,
        "bundlePath": str(bundle_path),
        "bundleMtimeNs": bundle_path.stat().st_mtime_ns,
        "colorProcessing": fcpbundle_color_processing(bundle_path),
        "settingsMtimeNs": fcpbundle_settings_mtime_ns(bundle_path),
        "items": items,
    }


def fcpbundle_settings_mtime_ns(bundle_path: Path) -> int | None:
    settings_path = bundle_path / "Settings.plist"
    if not settings_path.is_file():
        return None
    return settings_path.stat().st_mtime_ns


def fcpbundle_color_processing(bundle_path: Path) -> str | None:
    settings_path = bundle_path / "Settings.plist"
    if not settings_path.is_file():
        return None
    with settings_path.open("rb") as handle:
        settings = plistlib.load(handle)
    mode = settings.get("colorProcessingMode")
    if mode == 2:
        return "wide-hdr"
    return None


def ffprobe_executable() -> str:
    candidates = [
        shutil.which("ffprobe"),
        "/opt/homebrew/bin/ffprobe",
        "/usr/local/bin/ffprobe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise RuntimeError(
        "ffprobe is required to read media metadata directly from .fcpbundle; "
        "install ffmpeg/ffprobe or use an exported FCPXMLD package"
    )


def positive_fraction(value: str | None) -> Fraction | None:
    if not value or value == "N/A":
        return None
    try:
        fraction = Fraction(value)
    except (ValueError, ZeroDivisionError):
        return None
    return fraction if fraction > 0 else None


def fcp_color_space(color_primaries: str | None, color_transfer: str | None, color_matrix: str | None) -> str | None:
    primaries = (color_primaries or "").lower()
    transfer = (color_transfer or "").lower()
    matrix = (color_matrix or "").lower()
    if primaries == "bt2020" and transfer in {"arib-std-b67", "arib_std_b67"} and matrix in {"bt2020nc", "bt2020_ncl"}:
        return "9-18-9 (Rec. 2020 HLG)"
    if primaries == "bt709" and transfer == "bt709" and matrix == "bt709":
        return "1-1-1 (Rec. 709)"
    return None


def probe_video_metadata(media_path: Path, ffprobe: str) -> VideoMetadata:
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "stream=codec_type,width,height,avg_frame_rate,r_frame_rate,duration,color_space,color_transfer,color_primaries,channels,sample_rate:format=duration",
            "-of",
            "json",
            str(media_path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "ffprobe failed").strip())
    payload = json.loads(result.stdout or "{}")
    streams = payload.get("streams") or []
    stream = next((item for item in streams if item.get("codec_type") == "video"), None)
    if stream is None:
        raise RuntimeError("ffprobe found no video stream")
    width = int(stream.get("width") or 0)
    height = int(stream.get("height") or 0)
    if width <= 0 or height <= 0:
        raise RuntimeError("ffprobe did not return video dimensions")
    fps = positive_fraction(stream.get("avg_frame_rate")) or positive_fraction(stream.get("r_frame_rate"))
    if fps is None:
        raise RuntimeError("ffprobe did not return a usable video frame rate")
    duration = (
        positive_fraction(stream.get("duration"))
        or positive_fraction((payload.get("format") or {}).get("duration"))
    )
    if duration is None:
        raise RuntimeError("ffprobe did not return a usable video duration")
    audio_stream = next((item for item in streams if item.get("codec_type") == "audio"), None)
    audio_channels = None
    audio_rate = None
    if audio_stream is not None:
        try:
            parsed_channels = int(audio_stream.get("channels") or 0)
            audio_channels = parsed_channels if parsed_channels > 0 else None
        except (TypeError, ValueError):
            audio_channels = None
        try:
            parsed_rate = int(audio_stream.get("sample_rate") or 0)
            audio_rate = parsed_rate if parsed_rate > 0 else None
        except (TypeError, ValueError):
            audio_rate = None
    frame_duration = Fraction(fps.denominator, fps.numerator)
    frame_count = max(1, int((duration / frame_duration) + Fraction(1, 2)))
    return VideoMetadata(
        width=width,
        height=height,
        frame_duration=frame_duration,
        duration=frame_duration * frame_count,
        color_space=fcp_color_space(
            stream.get("color_primaries"),
            stream.get("color_transfer"),
            stream.get("color_space"),
        ),
        audio_channels=audio_channels,
        audio_rate=audio_rate,
    )


def fcpbundle_cache_dir(bundle_path: Path) -> Path:
    digest = hashlib.sha256(str(bundle_path).encode("utf-8")).hexdigest()[:16]
    return FCPBUNDLE_SOURCE_CACHE / f"{safe_file_component(bundle_path.stem)}-{digest}.fcpxmld"


def materialize_fcpbundle_info(bundle_path: Path) -> Path:
    if not bundle_path.exists() or not bundle_path.is_dir():
        raise FileNotFoundError(f"FCP library bundle was not found: {bundle_path}")
    media_files = fcpbundle_media_files(bundle_path)
    if not media_files:
        raise ValueError(f"no original video media was found in Event Original Media folders: {bundle_path}")
    cache_dir = fcpbundle_cache_dir(bundle_path)
    info_path = cache_dir / "Info.fcpxml"
    manifest_path = cache_dir / "source-manifest.json"
    signature = fcpbundle_signature(bundle_path, media_files)
    if info_path.exists() and manifest_path.exists():
        try:
            if json.loads(manifest_path.read_text(encoding="utf-8")) == signature:
                return info_path
        except (OSError, json.JSONDecodeError):
            pass

    ffprobe = ffprobe_executable()
    cache_dir.mkdir(parents=True, exist_ok=True)
    root = ET.Element("fcpxml", {"version": "1.11"})
    resource_node = ET.SubElement(root, "resources")
    library_attrs = {}
    color_processing = fcpbundle_color_processing(bundle_path)
    if color_processing:
        library_attrs["colorProcessing"] = color_processing
    library_node = ET.SubElement(root, "library", library_attrs)
    asset_index = 1
    for event_dir in fcpbundle_event_dirs(bundle_path):
        event_node = ET.SubElement(library_node, "event", {"name": event_dir.name})
        event_media = [media_path for media_event, media_path in media_files if media_event == event_dir]
        for media_path in event_media:
            asset_id = f"r{asset_index}"
            asset_index += 1
            attrs = {
                "id": asset_id,
                "name": media_path.stem,
                "uid": fcpbundle_media_uid(media_path),
                "start": "0s",
                "hasVideo": "1",
                "videoSources": "1",
            }
            clip_attrs = {
                "name": media_path.stem,
                "ref": asset_id,
                "start": "0s",
                "offset": "0s",
                "tcFormat": "NDF",
            }
            link_reason = fcpbundle_original_media_link_reason(media_path)
            if link_reason:
                attrs["stabilizerUnsupported"] = link_reason
            else:
                try:
                    metadata = probe_video_metadata(media_path, ffprobe)
                    format_id = f"r{asset_index}"
                    asset_index += 1
                    format_attrs = {
                        "id": format_id,
                        "frameDuration": time_string(metadata.frame_duration),
                        "width": str(metadata.width),
                        "height": str(metadata.height),
                    }
                    if metadata.color_space:
                        format_attrs["colorSpace"] = metadata.color_space
                    ET.SubElement(
                        resource_node,
                        "format",
                        format_attrs,
                    )
                    attrs["format"] = format_id
                    attrs["duration"] = time_string(metadata.duration)
                    if metadata.audio_channels is not None and metadata.audio_rate is not None:
                        attrs["hasAudio"] = "1"
                        attrs["audioSources"] = "1"
                        attrs["audioChannels"] = str(metadata.audio_channels)
                        attrs["audioRate"] = str(metadata.audio_rate)
                        clip_attrs["audioRole"] = "dialogue"
                    clip_attrs["format"] = format_id
                    clip_attrs["duration"] = time_string(metadata.duration)
                except Exception as exc:  # noqa: BLE001
                    attrs["stabilizerUnsupported"] = f"ffprobe metadata failed for original media: {exc}"
            asset = ET.SubElement(resource_node, "asset", attrs)
            ET.SubElement(
                asset,
                "media-rep",
                {"kind": "original-media", "sig": attrs["uid"], "src": path_to_file_url(media_path)},
            )
            ET.SubElement(event_node, "asset-clip", clip_attrs)
    try:
        ET.indent(root, space="  ")
    except AttributeError:
        pass
    ET.ElementTree(root).write(info_path, encoding="utf-8", xml_declaration=True)
    manifest_path.write_text(json.dumps(signature, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return info_path


def load_event_assets(fcpxml_path: Path) -> list[EventAsset]:
    info_path, _ = resolve_info_path(fcpxml_path)
    root = ET.parse(info_path).getroot()
    formats = resource_map(root, "format")
    assets = resource_map(root, "asset")
    asset_events = event_name_by_asset_id(root)
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
        unsupported: str | None = source_unsupported or asset.attrib.get("stabilizerUnsupported")
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
                event_name=asset_events.get(asset_id),
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
