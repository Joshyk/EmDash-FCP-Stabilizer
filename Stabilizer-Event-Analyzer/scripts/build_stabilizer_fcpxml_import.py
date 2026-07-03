#!/usr/bin/env python3
"""Build an FCPXMLD package with Tokyo Walking Stabilizer cache identities."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import shutil
import sys
import xml.etree.ElementTree as ET
import zlib
from fractions import Fraction
from pathlib import Path
from typing import Iterable

from fcpxml_common import (
    SCHEMA_VERSION,
    event_name_by_asset_id,
    event_names,
    file_url_to_path,
    local_name,
    parse_time,
    path_to_file_url,
    resolve_info_path,
    resources,
    safe_file_component,
    stable_fcp_asset_uid,
)


EFFECT_NAME = "Tokyo Walking Stabilizer"
EFFECT_UID = "~/Effects.localized/Emdash Studios/Tokyo Walking Stabilizer/Tokyo Walking Stabilizer.moef"
PARAM_PREFIX = "9999/10013/10016/3/10036"
FILTER_NAMES = {EFFECT_NAME, "Tokyo Walking Stabilizer copy"}
LEGACY_FILTER_NAMES = {"Stabilizer Transform"}
STABILIZER_VISIBLE_DEFAULT_PARAMS = [
    ("Footstep Jitter X Strength", 7, "1"),
    ("Footstep Jitter Y Strength", 18, "1"),
    ("Footstep Jitter Rotation Strength", 8, "0.5"),
    ("Stride Wobble X Strength", 29, "1"),
    ("Stride Wobble Y Strength", 30, "1"),
    ("Stride Wobble Rotation Strength", 31, "0.5"),
    ("Overall Strength", 1, "1"),
    ("Far-field Warp Strength", 45, "0.5"),
    ("Turn Smoothing Strength", 23, "2"),
    ("Turn Detection Window", 9, "6"),
    ("Remove Black Edges", 41, "1"),
    ("Auto Crop Zoom-Out Time", 42, "10"),
    ("Auto Crop Zoom-In Time", 43, "10"),
    ("Auto Crop Hold Time", 44, "2"),
    ("Sample Size", 19, "0"),
    ("Edge Display Mode", 27, "1"),
    ("Debug Overlay", 10, "0"),
]
PRE_EFFECT_CHILD_TAGS = {
    "note",
    "conform-rate",
    "timeMap",
    "object-tracker",
    "adjust-crop",
    "adjust-corners",
    "adjust-conform",
    "adjust-transform",
    "adjust-blend",
    "adjust-stabilization",
    "adjust-rollingShutter",
    "adjust-360-transform",
    "adjust-reorient",
    "adjust-orientation",
    "adjust-cinematic",
    "adjust-colorConform",
    "adjust-stereo-3D",
    "adjust-volume",
    "adjust-panner",
    "marker",
}


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return status


def fail(message: str) -> int:
    return emit({"schemaVersion": SCHEMA_VERSION, "status": "error", "error": message}, 1)


def next_resource_id(root: ET.Element) -> str:
    used = {child.attrib.get("id") for child in resources(root) if child.attrib.get("id")}
    max_id = 0
    for value in used:
        if value and value.startswith("r") and value[1:].isdigit():
            max_id = max(max_id, int(value[1:]))
    candidate = max_id + 1
    while f"r{candidate}" in used:
        candidate += 1
    return f"r{candidate}"


def ensure_effect_resource(root: ET.Element) -> str:
    for child in resources(root):
        if local_name(child.tag) == "effect" and child.attrib.get("uid") == EFFECT_UID:
            return child.attrib["id"]
    ref = next_resource_id(root)
    resources(root).append(ET.Element("effect", {"id": ref, "name": EFFECT_NAME, "uid": EFFECT_UID}))
    return ref


def filter_name(element: ET.Element) -> str:
    return element.attrib.get("nameOverride") or element.attrib.get("name") or ""


def remove_existing_stabilizer_filters(clip: ET.Element) -> int:
    removed = 0
    for child in list(clip):
        if local_name(child.tag) == "filter-video" and filter_name(child) in FILTER_NAMES:
            clip.remove(child)
            removed += 1
    return removed


def remove_filters_by_name(root: ET.Element, names: set[str]) -> int:
    parents = parent_map(root)
    removed = 0
    for element in list(root.iter()):
        if local_name(element.tag) != "filter-video" or filter_name(element) not in names:
            continue
        parent = parents.get(element)
        if parent is None:
            continue
        parent.remove(element)
        removed += 1
    return removed


def remove_unused_effect_resources(root: ET.Element, names: set[str]) -> int:
    used_refs = {
        element.attrib["ref"]
        for element in root.iter()
        if local_name(element.tag) == "filter-video" and element.attrib.get("ref")
    }
    removed = 0
    resource_node = resources(root)
    for child in list(resource_node):
        if local_name(child.tag) != "effect" or child.attrib.get("id") in used_refs:
            continue
        if (child.attrib.get("name") or "") in names:
            resource_node.remove(child)
            removed += 1
    return removed


def filter_insert_index(clip: ET.Element) -> int:
    index = 0
    for child in list(clip):
        if local_name(child.tag) not in PRE_EFFECT_CHILD_TAGS:
            break
        index += 1
    return index


def add_param(filter_node: ET.Element, name: str, parameter_id: int, value: str) -> None:
    ET.SubElement(
        filter_node,
        "param",
        {
            "name": name,
            "key": f"{PARAM_PREFIX}/{parameter_id}",
            "value": value,
        },
    )


def stabilizer_filter(ref: str, result: dict) -> ET.Element:
    identity = result["cacheIdentity"]
    sample_width = result.get("sampleWidth")
    sample_height = result.get("sampleHeight")
    sample_percent = result.get("sampleScalePercent")
    frame_count = result.get("frameCount")
    schema = result.get("cacheSchemaVersion", 16)
    revision = str(zlib.adler32(identity.encode("utf-8")) % 999_983)
    node = ET.Element("filter-video", {"ref": ref, "name": EFFECT_NAME})
    for name, parameter_id, value in STABILIZER_VISIBLE_DEFAULT_PARAMS:
        add_param(node, name, parameter_id, value)
    add_param(node, "Host Analysis Status", 15, f"Persisted Analysis Loaded | Schema: {schema}")
    add_param(
        node,
        "Sample Info",
        32,
        f"Sample: {sample_percent:g}% -> {sample_width}x{sample_height} | Analysis: {frame_count}f | Schema: {schema}",
    )
    add_param(node, "Queue", 36, "Queue: -")
    add_param(node, "Host Analysis Cache Identity", 33, identity)
    add_param(node, "Render Revision", 20, revision)
    return node


def parent_map(root: ET.Element) -> dict[ET.Element, ET.Element]:
    return {child: parent for parent in root.iter() for child in list(parent)}


def insert_after_child(parent: ET.Element, child: ET.Element, node: ET.Element) -> None:
    children = list(parent)
    try:
        index = children.index(child) + 1
    except ValueError as exc:
        raise ValueError("matched video node was not a child of its target clip") from exc
    parent.insert(index, node)


def resource_by_id(root: ET.Element, resource_id: str) -> ET.Element | None:
    for child in resources(root):
        if child.attrib.get("id") == resource_id:
            return child
    return None


def normalized_path_identity(path: Path) -> str:
    try:
        return str(path.expanduser().resolve(strict=False))
    except OSError:
        return str(path.expanduser())


def result_media_path(result: dict) -> Path | None:
    value = result.get("mediaPath")
    if not value:
        return None
    return Path(str(value))


def asset_media_paths(asset: ET.Element) -> list[Path]:
    urls = []
    if asset.attrib.get("src"):
        urls.append(asset.attrib["src"])
    urls.extend(
        child.attrib["src"]
        for child in asset
        if local_name(child.tag) == "media-rep" and child.attrib.get("src")
    )
    paths: list[Path] = []
    for url in urls:
        try:
            paths.append(file_url_to_path(url))
        except ValueError:
            continue
    return paths


def media_path_matches(asset: ET.Element, path: Path) -> bool:
    expected = normalized_path_identity(path)
    return any(normalized_path_identity(candidate) == expected for candidate in asset_media_paths(asset))


def asset_media_summary(asset: ET.Element | None) -> str:
    if asset is None:
        return "missing"
    paths = [normalized_path_identity(path) for path in asset_media_paths(asset)]
    return ", ".join(paths) if paths else "no media path"


def find_asset_ids_by_media_path(root: ET.Element, path: Path) -> list[str]:
    matches = []
    for child in resources(root):
        if local_name(child.tag) != "asset" or not child.attrib.get("id"):
            continue
        if media_path_matches(child, path):
            matches.append(child.attrib["id"])
    return matches


def resolve_analysis_asset_id(root: ET.Element, requested_asset_id: str, result: dict) -> tuple[str, dict]:
    copied = dict(result)
    copied["requestedAssetId"] = requested_asset_id
    media_path = result_media_path(result)
    requested_asset = resource_by_id(root, requested_asset_id)
    if requested_asset is not None and (media_path is None or media_path_matches(requested_asset, media_path)):
        copied["assetId"] = requested_asset_id
        return requested_asset_id, copied
    if media_path is None:
        raise ValueError(f"analyzed asset resource is missing: {requested_asset_id}")
    matches = find_asset_ids_by_media_path(root, media_path)
    if len(matches) == 1:
        resolved_asset_id = matches[0]
        copied["assetId"] = resolved_asset_id
        copied["sourceAssetResolution"] = {
            "requestedAssetId": requested_asset_id,
            "resolvedAssetId": resolved_asset_id,
            "mediaPath": normalized_path_identity(media_path),
            "reason": "analysis assetId did not match the source media path; resolved by exact mediaPath",
        }
        return resolved_asset_id, copied
    if len(matches) > 1:
        raise ValueError(
            "analysis mediaPath matched multiple source assets: "
            f"{normalized_path_identity(media_path)} -> {', '.join(matches)}"
        )
    raise ValueError(
        "analysis assetId does not match source media: "
        f"{requested_asset_id} points to {asset_media_summary(requested_asset)}, "
        f"analysis mediaPath is {normalized_path_identity(media_path)}"
    )


def resolve_analysis_results(root: ET.Element, results: dict[str, dict]) -> dict[str, dict]:
    resolved: dict[str, dict] = {}
    for requested_asset_id, result in results.items():
        resolved_asset_id, resolved_result = resolve_analysis_asset_id(root, requested_asset_id, result)
        if resolved_asset_id in resolved:
            raise ValueError(f"multiple analysis results resolved to the same source asset: {resolved_asset_id}")
        resolved[resolved_asset_id] = resolved_result
    return resolved


def source_asset_resolutions(results: dict[str, dict]) -> list[dict]:
    return [
        result["sourceAssetResolution"]
        for result in results.values()
        if isinstance(result.get("sourceAssetResolution"), dict)
    ]


def first_event_asset_clip(root: ET.Element, asset_id: str) -> ET.Element | None:
    for event in root.iter():
        if local_name(event.tag) != "event":
            continue
        for child in list(event):
            if local_name(child.tag) == "asset-clip" and child.attrib.get("ref") == asset_id:
                return child
    return None


def first_asset_clip(root: ET.Element, asset_id: str) -> ET.Element | None:
    for element in root.iter():
        if local_name(element.tag) == "asset-clip" and element.attrib.get("ref") == asset_id:
            return element
    return None


def has_ancestor(element: ET.Element, parents: dict[ET.Element, ET.Element], tag_name: str) -> bool:
    current = parents.get(element)
    while current is not None:
        if local_name(current.tag) == tag_name:
            return True
        current = parents.get(current)
    return False


def is_replaced_stabilizer_filter(element: ET.Element) -> bool:
    return local_name(element.tag) == "filter-video" and filter_name(element) in LEGACY_FILTER_NAMES | FILTER_NAMES


def filtered_pre_effect_children(source: ET.Element | None) -> list[ET.Element]:
    if source is None:
        return []
    children = []
    for child in list(source):
        tag = local_name(child.tag)
        if tag not in PRE_EFFECT_CHILD_TAGS:
            continue
        children.append(copy.deepcopy(child))
    return children


def inherited_filter_children(source: ET.Element | None) -> list[ET.Element]:
    if source is None:
        return []
    children = []
    for child in list(source):
        if local_name(child.tag) != "filter-video" or is_replaced_stabilizer_filter(child):
            continue
        children.append(copy.deepcopy(child))
    return children


def inherited_filter_source_clip(root: ET.Element, asset_id: str) -> ET.Element | None:
    parents = parent_map(root)
    candidates: list[tuple[int, int, int, ET.Element]] = []
    for order, element in enumerate(root.iter()):
        if local_name(element.tag) != "asset-clip" or element.attrib.get("ref") != asset_id:
            continue
        filter_count = len(inherited_filter_children(element))
        if filter_count == 0:
            continue
        timeline_score = 1 if has_ancestor(element, parents, "project") else 0
        candidates.append((filter_count, timeline_score, -order, element))
    if not candidates:
        return None
    return max(candidates, key=lambda item: item[:3])[3]


def inherited_filter_summary(source: ET.Element | None) -> dict:
    filters = inherited_filter_children(source)
    return {
        "inheritedFilterCount": len(filters),
        "inheritedFilterNames": [filter_name(item) for item in filters],
    }


def referenced_resource_ids(element: ET.Element) -> set[str]:
    resource_ids: set[str] = set()
    for node in element.iter():
        ref = node.attrib.get("ref")
        if ref:
            resource_ids.add(ref)
    return resource_ids


def clip_attributes(
    asset: ET.Element,
    source_clip: ET.Element | None,
    *,
    offset: str | None = None,
) -> dict[str, str]:
    attrs: dict[str, str] = {
        "ref": asset.attrib["id"],
        "name": asset.attrib.get("name") or asset.attrib["id"],
    }
    for key in ("start", "duration", "format"):
        if source_clip is not None and source_clip.attrib.get(key):
            attrs[key] = source_clip.attrib[key]
        elif asset.attrib.get(key):
            attrs[key] = asset.attrib[key]
    for key in ("tcStart", "tcFormat", "audioRole"):
        if source_clip is not None and source_clip.attrib.get(key):
            attrs[key] = source_clip.attrib[key]
    if offset is not None:
        attrs["offset"] = offset
    return attrs


def append_event_asset_clip(
    parent: ET.Element,
    asset: ET.Element,
    source_clip: ET.Element | None,
    effect_source_clip: ET.Element | None,
    ref: str,
    result: dict,
    *,
    offset: str | None = None,
) -> ET.Element:
    clip = ET.SubElement(parent, "asset-clip", clip_attributes(asset, source_clip, offset=offset))
    for child in filtered_pre_effect_children(source_clip):
        clip.append(child)
    clip.append(stabilizer_filter(ref, result))
    for child in inherited_filter_children(effect_source_clip):
        clip.append(child)
    return clip


def append_review_clip(
    parent: ET.Element,
    asset: ET.Element,
    source_clip: ET.Element | None,
    effect_source_clip: ET.Element | None,
    ref: str,
    result: dict,
    *,
    offset: str,
) -> ET.Element:
    clip = ET.SubElement(parent, "asset-clip", clip_attributes(asset, source_clip, offset=offset))
    for child in filtered_pre_effect_children(source_clip):
        clip.append(child)
    clip.append(stabilizer_filter(ref, result))
    for child in inherited_filter_children(effect_source_clip):
        clip.append(child)
    return clip


def asset_uid_seed(asset: ET.Element) -> str:
    media_sources = [
        child.attrib.get("src", "")
        for child in asset
        if local_name(child.tag) == "media-rep" and child.attrib.get("src")
    ]
    parts = [
        asset.attrib.get("name", ""),
        asset.attrib.get("start", ""),
        asset.attrib.get("duration", ""),
        asset.attrib.get("format", ""),
        "|".join(media_sources),
    ]
    return "|".join(parts)


def inferred_proxy_media_path(original_path: Path) -> Path | None:
    sibling = original_path.parent.parent / "Transcoded Media" / "Proxy Media" / original_path.name
    if sibling.is_file() or sibling.is_symlink():
        return sibling
    parts = list(original_path.parts)
    for index, part in enumerate(parts):
        if part != "Final Cut Original Media":
            continue
        candidate = Path(*parts[:index], "Final Cut Proxy Media", *parts[index + 1 :])
        if candidate.is_file() or candidate.is_symlink():
            return candidate
    return None


def event_media_path(event_root: Path, relative_dir: Path, file_name: str) -> Path | None:
    media_dir = event_root / relative_dir
    candidate = media_dir / file_name
    if candidate.is_file() or candidate.is_symlink():
        return candidate
    if not media_dir.is_dir():
        return None
    target_lower = file_name.lower()
    for child in media_dir.iterdir():
        if child.name.lower() == target_lower and (child.is_file() or child.is_symlink()):
            return child
    return None


def retarget_asset_media_reps(asset: ET.Element, target_event_root: Path | None) -> None:
    if target_event_root is None:
        return
    event_root = target_event_root.expanduser().resolve()
    if not event_root.is_dir():
        raise ValueError(f"target Event root does not exist: {target_event_root}")
    original_file_names: list[str] = []
    for child in asset:
        if local_name(child.tag) != "media-rep" or not child.attrib.get("src"):
            continue
        try:
            source_path = file_url_to_path(child.attrib["src"])
        except ValueError:
            continue
        file_name = source_path.name
        if child.attrib.get("kind") == "original-media":
            original_file_names.append(file_name)
            target_path = event_media_path(event_root, Path("Original Media"), file_name)
            if target_path is not None:
                child.attrib["src"] = path_to_file_url(target_path)
        elif child.attrib.get("kind") == "proxy-media":
            target_path = event_media_path(event_root, Path("Transcoded Media") / "Proxy Media", file_name)
            if target_path is not None:
                child.attrib["src"] = path_to_file_url(target_path)

    existing_proxy_srcs = {
        child.attrib.get("src")
        for child in asset
        if local_name(child.tag) == "media-rep"
        and child.attrib.get("kind") == "proxy-media"
        and child.attrib.get("src")
    }
    for file_name in original_file_names:
        proxy_path = event_media_path(event_root, Path("Transcoded Media") / "Proxy Media", file_name)
        if proxy_path is None:
            continue
        proxy_src = path_to_file_url(proxy_path)
        if proxy_src in existing_proxy_srcs:
            continue
        ET.SubElement(asset, "media-rep", {"kind": "proxy-media", "src": proxy_src})
        existing_proxy_srcs.add(proxy_src)


def ensure_proxy_media_rep(asset: ET.Element, uid: str) -> None:
    existing_srcs = {
        child.attrib.get("src")
        for child in asset
        if local_name(child.tag) == "media-rep" and child.attrib.get("src")
    }
    original_reps = [
        child
        for child in asset
        if local_name(child.tag) == "media-rep"
        and child.attrib.get("kind") == "original-media"
        and child.attrib.get("src")
    ]
    for rep in original_reps:
        try:
            proxy_path = inferred_proxy_media_path(file_url_to_path(rep.attrib["src"]))
        except ValueError:
            continue
        if proxy_path is None:
            continue
        proxy_src = path_to_file_url(proxy_path)
        if proxy_src in existing_srcs:
            continue
        ET.SubElement(asset, "media-rep", {"kind": "proxy-media", "sig": uid, "src": proxy_src})
        existing_srcs.add(proxy_src)


def normalized_resource_copy(resource: ET.Element, target_event_root: Path | None = None) -> ET.Element:
    copied = copy.deepcopy(resource)
    if local_name(copied.tag) != "asset":
        return copied
    retarget_asset_media_reps(copied, target_event_root)
    uid = copied.attrib.get("uid")
    if not uid:
        uid = stable_fcp_asset_uid(asset_uid_seed(copied))
        copied.attrib["uid"] = uid
    for child in copied:
        if local_name(child.tag) == "media-rep" and child.attrib.get("src") and not child.attrib.get("sig"):
            child.attrib["sig"] = uid
    ensure_proxy_media_rep(copied, uid)
    return copied


def analyzed_asset_resource_copy(asset: ET.Element, result: dict, target_event_root: Path | None = None) -> ET.Element:
    copied = normalized_resource_copy(asset, target_event_root=target_event_root)
    cache_identity = (result.get("cacheIdentity") or "").strip()
    if cache_identity:
        uid = stable_fcp_asset_uid(f"stabilizer-analyzed-import|{asset_uid_seed(copied)}|{cache_identity}")
        copied.attrib["uid"] = uid
        for child in copied:
            if local_name(child.tag) == "media-rep" and child.attrib.get("src"):
                child.attrib["sig"] = uid
    return copied


def source_library_attrs(source_root: ET.Element) -> dict[str, str]:
    for element in source_root:
        if local_name(element.tag) != "library":
            continue
        color_processing = element.attrib.get("colorProcessing")
        if color_processing:
            return {"colorProcessing": color_processing}
        return {}
    return {}


def format_time(value: Fraction) -> str:
    if value.denominator == 1:
        return f"{value.numerator}s"
    return f"{value.numerator}/{value.denominator}s"


def clip_duration(asset: ET.Element, source_clip: ET.Element | None) -> Fraction:
    duration = None
    if source_clip is not None:
        duration = source_clip.attrib.get("duration")
    if not duration:
        duration = asset.attrib.get("duration")
    if not duration:
        raise ValueError(f"analyzed asset {asset.attrib.get('id') or asset.attrib.get('name') or '<unknown>'} has no duration")
    return parse_time(duration)


def review_project_name(source_root: ET.Element, event_name: str, asset_id: str | None, result: dict | None, count: int) -> str:
    if count == 1 and asset_id and result:
        return f"{footage_stem(source_root, asset_id, result)} Stabilized Review"
    return f"{event_name} Stabilized Review"


def build_analyzed_only_tree(
    source_root: ET.Element,
    results: dict[str, dict],
    *,
    target_event_name: str | None = None,
    target_event_root: Path | None = None,
) -> ET.Element:
    root = ET.Element("fcpxml", dict(source_root.attrib))
    target_resources = ET.SubElement(root, "resources")
    copied_resource_ids: set[str] = set()
    extra_resource_ids: set[str] = set()
    effect_source_clips = {
        asset_id: inherited_filter_source_clip(source_root, asset_id)
        for asset_id in results
    }
    for source_clip in effect_source_clips.values():
        if source_clip is None:
            continue
        for child in inherited_filter_children(source_clip):
            extra_resource_ids.update(referenced_resource_ids(child))
    for asset_id in results:
        asset = resource_by_id(source_root, asset_id)
        if asset is None or local_name(asset.tag) != "asset":
            raise ValueError(f"analyzed asset resource was not found in source FCPXML: {asset_id}")
        format_id = asset.attrib.get("format")
        if not format_id:
            raise ValueError(f"analyzed asset has no format resource: {asset_id}")
        fmt = resource_by_id(source_root, format_id)
        if fmt is None or local_name(fmt.tag) != "format":
            raise ValueError(f"format resource {format_id} was not found for analyzed asset {asset_id}")
        for resource in (fmt, asset):
            resource_id = resource.attrib.get("id")
            if resource_id and resource_id not in copied_resource_ids:
                if resource is asset:
                    target_resources.append(analyzed_asset_resource_copy(asset, results[asset_id], target_event_root=target_event_root))
                else:
                    target_resources.append(normalized_resource_copy(resource, target_event_root=target_event_root))
                copied_resource_ids.add(resource_id)
    for resource_id in sorted(extra_resource_ids):
        if resource_id in copied_resource_ids:
            continue
        resource = resource_by_id(source_root, resource_id)
        if resource is not None:
            target_resources.append(normalized_resource_copy(resource, target_event_root=target_event_root))
            copied_resource_ids.add(resource_id)

    ref = ensure_effect_resource(root)
    library = ET.SubElement(root, "library", source_library_attrs(source_root))
    source_event_names = event_name_by_asset_id(source_root)
    fallback_event_name = (event_names(source_root) or ["Stabilized Analysis"])[0]
    event_nodes: dict[str, ET.Element] = {}
    review_projects: dict[str, dict[str, ET.Element | Fraction]] = {}
    result_count = len(results)
    for asset_id, result in results.items():
        asset = resource_by_id(source_root, asset_id)
        source_clip = first_event_asset_clip(source_root, asset_id) or first_asset_clip(source_root, asset_id)
        effect_source_clip = effect_source_clips.get(asset_id)
        event_name = target_event_name or source_event_names.get(asset_id) or fallback_event_name
        event = event_nodes.get(event_name)
        if event is None:
            event = ET.SubElement(library, "event", {"name": event_name})
            event_nodes[event_name] = event
        append_event_asset_clip(event, asset, source_clip, effect_source_clip, ref, result)
        review = review_projects.get(event_name)
        if review is None:
            format_id = (source_clip.attrib.get("format") if source_clip is not None else None) or asset.attrib.get("format")
            if not format_id:
                raise ValueError(f"analyzed asset {asset_id} has no format for review project")
            project = ET.SubElement(
                event,
                "project",
                {"name": review_project_name(source_root, event_name, asset_id, result, result_count)},
            )
            sequence = ET.SubElement(
                project,
                "sequence",
                {
                    "format": format_id,
                    "duration": "0s",
                    "tcStart": "0s",
                    "tcFormat": source_clip.attrib.get("tcFormat", "NDF") if source_clip is not None else "NDF",
                },
            )
            spine = ET.SubElement(sequence, "spine")
            review = {"sequence": sequence, "spine": spine, "offset": Fraction(0)}
            review_projects[event_name] = review
        offset = review["offset"]
        if not isinstance(offset, Fraction):
            raise ValueError("review project offset state is invalid")
        spine = review["spine"]
        if not isinstance(spine, ET.Element):
            raise ValueError("review project spine state is invalid")
        append_review_clip(spine, asset, source_clip, effect_source_clip, ref, result, offset=format_time(offset))
        next_offset = offset + clip_duration(asset, source_clip)
        review["offset"] = next_offset
        sequence = review["sequence"]
        if not isinstance(sequence, ET.Element):
            raise ValueError("review project sequence state is invalid")
        sequence.attrib["duration"] = format_time(next_offset)
    return root


def build_single_asset_tree(
    source_root: ET.Element,
    asset_id: str,
    result: dict,
    *,
    target_event_name: str | None = None,
    target_event_root: Path | None = None,
) -> ET.Element:
    return build_analyzed_only_tree(
        source_root,
        {asset_id: result},
        target_event_name=target_event_name,
        target_event_root=target_event_root,
    )


def output_package_path(output_dir: Path, source_path: Path) -> Path:
    source_name = source_path.name if source_path.suffix == ".fcpxmld" else source_path.stem
    if not source_name.endswith(".fcpxmld"):
        source_name = f"{source_name}.fcpxmld"
    return output_dir / f"{Path(source_name).stem}-stabilizer.fcpxmld"


def footage_stem(source_root: ET.Element, asset_id: str, result: dict) -> str:
    asset = resource_by_id(source_root, asset_id)
    name = result.get("footageFileName") or result.get("name")
    if not name and asset is not None:
        name = asset.attrib.get("name")
    return safe_file_component(Path(str(name or asset_id)).stem)


def package_directory_name(source_root: ET.Element, asset_id: str, result: dict) -> str:
    footage = footage_stem(source_root, asset_id, result)
    sample_percent = result.get("sampleScalePercent")
    sample_label = f"sample{sample_percent:g}" if isinstance(sample_percent, (int, float)) else "sampleunknown"
    schema = result.get("cacheSchemaVersion", "unknown")
    frame_count = result.get("frameCount", "unknown")
    date_label = dt.date.today().isoformat()
    return safe_file_component(f"{footage}__{sample_label}__schema{schema}__{frame_count}f__{date_label}")


def copy_cache_payload(package_dir: Path, footage: str, result: dict, cache_root: str | None) -> dict:
    if not cache_root:
        raise ValueError("cache root is required for per-footage packages")
    cache_root_path = Path(cache_root).expanduser()
    cache_file_name = result.get("cacheFileName")
    cache_identity = (result.get("cacheIdentity") or "").strip()
    if not cache_file_name:
        raise ValueError(f"analysis result for {result.get('name') or result.get('assetId') or 'footage'} is missing cacheFileName")
    if not cache_identity:
        raise ValueError(f"analysis result for {result.get('name') or result.get('assetId') or 'footage'} is missing cacheIdentity")
    source_cache_file = cache_root_path / "caches" / cache_file_name
    if not source_cache_file.exists():
        raise FileNotFoundError(f"cache file is missing: {source_cache_file}")
    source_index_path = cache_root_path / "host-analysis-index-v2.json"
    if not source_index_path.exists():
        raise FileNotFoundError(f"cache index is missing: {source_index_path}")
    source_index = json.loads(source_index_path.read_text(encoding="utf-8"))
    index_entry = next(
        (
            entry
            for entry in source_index.get("entries") or []
            if (entry.get("cacheIdentity") or "").strip() == cache_identity
            and (entry.get("cacheFileName") or "").strip() == cache_file_name
        ),
        None,
    )
    if index_entry is None:
        raise ValueError(f"cache index does not contain the analysis result identity for {cache_file_name}")
    cache_payload = json.loads(source_cache_file.read_text(encoding="utf-8"))
    if cache_payload.get("schemaVersion") != result.get("cacheSchemaVersion"):
        raise ValueError(f"cache file schema does not match analysis result for {cache_file_name}")
    payload_dir = package_dir / f"{footage}.analysis-cache"
    caches_dir = payload_dir / "caches"
    caches_dir.mkdir(parents=True)
    shutil.copy2(source_cache_file, caches_dir / cache_file_name)
    copied = [str((caches_dir / cache_file_name).relative_to(package_dir))]
    payload_index_path = payload_dir / "host-analysis-index-v2.json"
    payload_index_path.write_text(
        json.dumps(
            {
                "schemaVersion": source_index.get("schemaVersion", result.get("cacheSchemaVersion")),
                "entries": [index_entry],
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    copied.append(str(payload_index_path.relative_to(package_dir)))
    payload_latest_path = payload_dir / "host-analysis-v2.json"
    payload_latest_path.write_text(json.dumps(cache_payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    copied.append(str(payload_latest_path.relative_to(package_dir)))
    source_render_offset = cache_root_path / "host-analysis-render-offset-v2.json"
    if source_render_offset.exists():
        shutil.copy2(source_render_offset, payload_dir / source_render_offset.name)
        copied.append(str((payload_dir / source_render_offset.name).relative_to(package_dir)))
    return {
        "cachePayloadDirectory": str(payload_dir.relative_to(package_dir)),
        "cachePayloadFiles": copied,
        "cachePayloadCacheFile": str((caches_dir / cache_file_name).relative_to(package_dir)),
    }


def event_root_for_source(source_path: Path, event_name: str | None) -> str | None:
    if not event_name:
        return None
    source = source_path.expanduser().resolve()
    if source.suffix != ".fcpbundle" or not source.is_dir():
        return None
    event_root = source / event_name
    if event_root.is_dir():
        return str(event_root)
    return None


def source_effect_stack_unavailable_reason(source_path: Path, inherited_filter_count: int) -> str | None:
    if inherited_filter_count > 0:
        return None
    source = source_path.expanduser()
    if source.suffix == ".fcpbundle":
        return "direct .fcpbundle sources synthesize Original/Proxy media refs only; export FCPXMLD from Final Cut Pro to inherit timeline effects"
    return None


def analysis_manifest(
    source_root: ET.Element,
    source_path: Path,
    asset_id: str,
    result: dict,
    cache_root: str | None = None,
    cache_payload: dict | None = None,
    target_event_name: str | None = None,
    target_event_root: Path | None = None,
) -> dict:
    asset = resource_by_id(source_root, asset_id)
    manifest_asset = normalized_resource_copy(asset, target_event_root=target_event_root) if asset is not None else None
    source_clip = first_event_asset_clip(source_root, asset_id) or first_asset_clip(source_root, asset_id)
    effect_source_clip = inherited_filter_source_clip(source_root, asset_id)
    effect_stack = inherited_filter_summary(effect_source_clip)
    unavailable_reason = source_effect_stack_unavailable_reason(source_path, effect_stack["inheritedFilterCount"])
    source_event_name = target_event_name or event_name_by_asset_id(source_root).get(asset_id)
    event_root = str(target_event_root.expanduser().resolve()) if target_event_root is not None else event_root_for_source(source_path, source_event_name)
    media_reps = []
    if manifest_asset is not None:
        for child in manifest_asset:
            if local_name(child.tag) == "media-rep":
                media_reps.append({
                    "kind": child.attrib.get("kind"),
                    "src": child.attrib.get("src"),
                })
    media_path = result.get("mediaPath")
    if manifest_asset is not None:
        for child in manifest_asset:
            if local_name(child.tag) == "media-rep" and child.attrib.get("kind") == "original-media" and child.attrib.get("src"):
                try:
                    media_path = str(file_url_to_path(child.attrib["src"]))
                except ValueError:
                    media_path = result.get("mediaPath")
                break
    frame_count = result.get("frameCount")
    prepared_fields = (
        result.get("preparedMotionPath") is True
        or result.get("preparedMotionPathPresent") is True
        or (isinstance(frame_count, int) and frame_count > 1 and bool(result.get("cacheIdentity")))
    )
    range_start = result.get("rangeStartSeconds")
    range_duration = result.get("rangeDurationSeconds")
    if range_start is None and asset is not None:
        range_start = float(parse_time(asset.attrib.get("start"), parse_time("0s")))
    if range_duration is None and asset is not None and asset.attrib.get("duration"):
        range_duration = float(parse_time(asset.attrib["duration"]))
    return {
        "manifestSchemaVersion": 1,
        "assetId": asset_id,
        "requestedAssetId": result.get("requestedAssetId", asset_id),
        "sourceAssetResolution": result.get("sourceAssetResolution"),
        "footageName": result.get("name") or (asset.attrib.get("name") if asset is not None else asset_id),
        "footageFileName": result.get("footageFileName") or result.get("name") or (asset.attrib.get("name") if asset is not None else asset_id),
        "eventName": source_event_name,
        "eventRoot": event_root,
        "mediaPath": media_path,
        "mediaKind": result.get("mediaKind"),
        "mediaReps": media_reps,
        "sourceMediaFingerprint": result.get("sourceMediaFingerprint") or result.get("firstFingerprint"),
        "firstFingerprint": result.get("firstFingerprint"),
        "middleFingerprint": result.get("middleFingerprint"),
        "lastFingerprint": result.get("lastFingerprint"),
        "analyzedRange": {
            "startSeconds": range_start,
            "durationSeconds": range_duration,
            "endSeconds": result.get("rangeEndSeconds"),
        },
        "durationSeconds": result.get("durationSeconds") or range_duration,
        "sampleScalePercent": result.get("sampleScalePercent"),
        "sampleWidth": result.get("sampleWidth"),
        "sampleHeight": result.get("sampleHeight"),
        "cacheSchemaVersion": result.get("cacheSchemaVersion"),
        "frameCount": frame_count,
        "cacheIdentity": result.get("cacheIdentity"),
        "cacheIdentityShort": short_identity(result.get("cacheIdentity")),
        "cacheFileName": result.get("cacheFileName"),
        "cacheRoot": cache_root,
        "analysisTimings": result.get("analysisTimings"),
        "cachePayloadDirectory": (cache_payload or {}).get("cachePayloadDirectory"),
        "cachePayloadFiles": (cache_payload or {}).get("cachePayloadFiles") or [],
        "cachePayloadCacheFile": (cache_payload or {}).get("cachePayloadCacheFile"),
        "preparedMotionPath": prepared_fields,
        "sourceClip": {
            "start": source_clip.attrib.get("start") if source_clip is not None else None,
            "duration": source_clip.attrib.get("duration") if source_clip is not None else None,
        },
        "sourceEffectStack": {
            **effect_stack,
            "unavailableReason": unavailable_reason,
        },
    }


def short_identity(identity: str | None) -> str | None:
    if not identity:
        return None
    return zlib.adler32(identity.encode("utf-8")).to_bytes(4, "big").hex()


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build_per_footage_packages(
    source_root: ET.Element,
    results: dict[str, dict],
    source_path: Path,
    output_dir: Path,
    cache_root: str | None,
    *,
    target_event_name: str | None = None,
    target_event_root: Path | None = None,
) -> list[dict]:
    packages = []
    output_dir.mkdir(parents=True, exist_ok=True)
    for asset_id, result in results.items():
        package_dir = output_dir / package_directory_name(source_root, asset_id, result)
        if package_dir.exists():
            shutil.rmtree(package_dir)
        package_dir.mkdir(parents=True)
        footage = footage_stem(source_root, asset_id, result)
        fcpxmld_path = package_dir / f"{footage}.fcpxmld"
        fcpxmld_path.mkdir()
        info_path = fcpxmld_path / "Info.fcpxml"
        tree = ET.ElementTree(
            build_single_asset_tree(
                source_root,
                asset_id,
                result,
                target_event_name=target_event_name,
                target_event_root=target_event_root,
            )
        )
        tree.write(info_path, encoding="utf-8", xml_declaration=True)
        manifest_path = package_dir / f"{footage}.analysis-manifest.json"
        cache_payload = copy_cache_payload(package_dir, footage, result, cache_root)
        manifest = analysis_manifest(
            source_root,
            source_path,
            asset_id,
            result,
            cache_root=cache_root,
            cache_payload=cache_payload,
            target_event_name=target_event_name,
            target_event_root=target_event_root,
        )
        write_json(manifest_path, manifest)
        packages.append({
            "assetId": asset_id,
            "requestedAssetId": result.get("requestedAssetId", asset_id),
            "sourceAssetResolution": result.get("sourceAssetResolution"),
            "footageName": manifest["footageName"],
            "packageDirectory": str(package_dir),
            "outputPackage": str(fcpxmld_path),
            "infoPath": str(info_path),
            "manifestPath": str(manifest_path),
            "validationPath": str(package_dir / f"{footage}.validation.json"),
            "cacheIdentity": result.get("cacheIdentity"),
            "cacheIdentityShort": manifest["cacheIdentityShort"],
            "cacheSchemaVersion": result.get("cacheSchemaVersion"),
            "sampleScalePercent": result.get("sampleScalePercent"),
            "sampleWidth": result.get("sampleWidth"),
            "sampleHeight": result.get("sampleHeight"),
            "frameCount": result.get("frameCount"),
            "analysisTimings": result.get("analysisTimings"),
            "preparedMotionPath": manifest["preparedMotionPath"],
            "sourceEffectStack": manifest["sourceEffectStack"],
        })
    return packages


def copy_source_package(source_path: Path, info_path: Path, output_dir: Path) -> tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    package_path = output_package_path(output_dir, source_path)
    if package_path.exists():
        shutil.rmtree(package_path)
    if source_path.is_dir():
        shutil.copytree(source_path, package_path)
    else:
        package_path.mkdir(parents=True)
        shutil.copy2(info_path, package_path / "Info.fcpxml")
    return package_path, package_path / "Info.fcpxml"


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-fcpxml", type=Path, required=True)
    parser.add_argument("--analysis-json", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--only-analyzed-assets",
        action="store_true",
        help="Build a compact FCPXMLD containing only analyzed Event clips.",
    )
    parser.add_argument(
        "--per-footage-packages",
        action="store_true",
        help="Build one import package directory per analyzed footage with a manifest next to the FCPXMLD.",
    )
    parser.add_argument(
        "--target-event-name",
        help="Override the output Event name when importing into an existing Final Cut Pro Event.",
    )
    parser.add_argument(
        "--target-event-root",
        type=Path,
        help="Retarget original/proxy media reps to this existing Final Cut Pro Event folder.",
    )
    parser.add_argument("--cache-root", type=Path)
    return parser.parse_args(argv)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        info_path, _ = resolve_info_path(args.source_fcpxml)
        analysis = json.loads(args.analysis_json.read_text(encoding="utf-8"))
        results = {item["assetId"]: item for item in analysis.get("results", []) if item.get("cacheIdentity")}
        if not results:
            raise ValueError("analysis JSON did not contain cache identities")
        if args.only_analyzed_assets or args.per_footage_packages:
            tree = ET.parse(info_path)
            root = tree.getroot()
            results = resolve_analysis_results(root, results)
            if args.per_footage_packages:
                packages = build_per_footage_packages(
                    root,
                    results,
                    args.source_fcpxml,
                    args.output_dir,
                    str(args.cache_root or analysis.get("cacheRoot") or ""),
                    target_event_name=args.target_event_name,
                    target_event_root=args.target_event_root,
                )
                return emit(
                    {
                        "schemaVersion": SCHEMA_VERSION,
                        "status": "ok",
                        "packages": packages,
                        "outputPackage": packages[0]["outputPackage"] if packages else None,
                        "infoPath": packages[0]["infoPath"] if packages else None,
                        "insertedFilters": len(packages) * 2,
                        "removedExistingFilters": 0,
                        "assetIds": sorted(results),
                        "sourceAssetResolutions": source_asset_resolutions(results),
                        "onlyAnalyzedAssets": True,
                        "perFootagePackages": True,
                    }
                )
            args.output_dir.mkdir(parents=True, exist_ok=True)
            package_path = output_package_path(args.output_dir, args.source_fcpxml)
            if package_path.exists():
                shutil.rmtree(package_path)
            package_path.mkdir(parents=True)
            target_info = package_path / "Info.fcpxml"
        else:
            package_path, target_info = copy_source_package(args.source_fcpxml, info_path, args.output_dir)
            tree = ET.parse(target_info)
        root = tree.getroot()
        if not all("requestedAssetId" in result for result in results.values()):
            results = resolve_analysis_results(root, results)
        if args.only_analyzed_assets:
            root = build_analyzed_only_tree(
                root,
                results,
                target_event_name=args.target_event_name,
                target_event_root=args.target_event_root,
            )
            tree = ET.ElementTree(root)
            tree.write(target_info, encoding="utf-8", xml_declaration=True)
            return emit(
                {
                    "schemaVersion": SCHEMA_VERSION,
                    "status": "ok",
                    "outputPackage": str(package_path),
                    "infoPath": str(target_info),
                    "insertedFilters": len(results) * 2,
                    "removedExistingFilters": 0,
                    "assetIds": sorted(results),
                    "sourceAssetResolutions": source_asset_resolutions(results),
                    "safeName": safe_file_component(package_path.stem),
                    "onlyAnalyzedAssets": True,
                }
            )
        removed = remove_filters_by_name(root, LEGACY_FILTER_NAMES)
        remove_unused_effect_resources(root, LEGACY_FILTER_NAMES)
        ref = ensure_effect_resource(root)
        parents = parent_map(root)
        inserted = 0
        inserted_targets: set[int] = set()
        for element in list(root.iter()):
            tag = local_name(element.tag)
            if tag not in {"asset-clip", "video"}:
                continue
            asset_id = element.attrib.get("ref")
            if asset_id not in results:
                continue
            if tag == "asset-clip":
                target = element
                insertion_anchor = None
            else:
                parent = parents.get(element)
                if parent is None or local_name(parent.tag) != "clip":
                    raise ValueError("matched video reference must be inside a clip to receive a Stabilizer filter")
                target = parent
                insertion_anchor = element
                removed += remove_existing_stabilizer_filters(element)
            removed += remove_existing_stabilizer_filters(target)
            target_key = id(target)
            if target_key in inserted_targets:
                continue
            if insertion_anchor is None:
                target.insert(filter_insert_index(target), stabilizer_filter(ref, results[asset_id]))
            else:
                insert_after_child(target, insertion_anchor, stabilizer_filter(ref, results[asset_id]))
            inserted_targets.add(target_key)
            inserted += 1
        if inserted == 0:
            raise ValueError("no asset-clip/video nodes referenced the analyzed Event assets")
        tree.write(target_info, encoding="utf-8", xml_declaration=True)
        return emit(
            {
                "schemaVersion": SCHEMA_VERSION,
                "status": "ok",
                "outputPackage": str(package_path),
                "infoPath": str(target_info),
                "insertedFilters": inserted,
                "removedExistingFilters": removed,
                "assetIds": sorted(results),
                "sourceAssetResolutions": source_asset_resolutions(results),
                "safeName": safe_file_component(package_path.stem),
            }
        )
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
