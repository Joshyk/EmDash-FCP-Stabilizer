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
from pathlib import Path
from typing import Iterable

from fcpxml_common import (
    SCHEMA_VERSION,
    event_names,
    local_name,
    parse_time,
    resolve_info_path,
    resources,
    safe_file_component,
)


EFFECT_NAME = "Tokyo Walking Stabilizer"
EFFECT_UID = "~/Effects.localized/Emdash Studios/Tokyo Walking Stabilizer/Tokyo Walking Stabilizer.moef"
PARAM_PREFIX = "9999/10013/10016/3/10036"
FILTER_NAMES = {EFFECT_NAME, "Tokyo Walking Stabilizer copy"}
LEGACY_FILTER_NAMES = {"Stabilizer Transform"}
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
    node = ET.Element("filter-video", {"ref": ref, "name": EFFECT_NAME, "nameOverride": EFFECT_NAME})
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


def time_string(value) -> str:
    if value.denominator == 1:
        return f"{value.numerator}s"
    return f"{value.numerator}/{value.denominator}s"


def resource_by_id(root: ET.Element, resource_id: str) -> ET.Element | None:
    for child in resources(root):
        if child.attrib.get("id") == resource_id:
            return child
    return None


def first_event_asset_clip(root: ET.Element, asset_id: str) -> ET.Element | None:
    for event in root.iter():
        if local_name(event.tag) != "event":
            continue
        for child in list(event):
            if local_name(child.tag) == "asset-clip" and child.attrib.get("ref") == asset_id:
                return child
    return None


def filtered_pre_effect_children(source: ET.Element | None) -> list[ET.Element]:
    if source is None:
        return []
    children = []
    for child in list(source):
        tag = local_name(child.tag)
        if tag not in PRE_EFFECT_CHILD_TAGS:
            continue
        if tag == "filter-video" or filter_name(child) in LEGACY_FILTER_NAMES | FILTER_NAMES:
            continue
        children.append(copy.deepcopy(child))
    return children


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
    for key in ("tcFormat", "audioRole"):
        if source_clip is not None and source_clip.attrib.get(key):
            attrs[key] = source_clip.attrib[key]
    if offset is not None:
        attrs["offset"] = offset
    return attrs


def append_filtered_asset_clip(
    parent: ET.Element,
    asset: ET.Element,
    source_clip: ET.Element | None,
    ref: str,
    result: dict,
    *,
    offset: str | None = None,
) -> ET.Element:
    clip = ET.SubElement(parent, "asset-clip", clip_attributes(asset, source_clip, offset=offset))
    for child in filtered_pre_effect_children(source_clip):
        clip.append(child)
    clip.append(stabilizer_filter(ref, result))
    return clip


def build_analyzed_only_tree(source_root: ET.Element, results: dict[str, dict]) -> ET.Element:
    root = ET.Element("fcpxml", dict(source_root.attrib))
    source_resources = resources(source_root)
    target_resources = ET.SubElement(root, "resources")
    copied_resource_ids: set[str] = set()
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
                target_resources.append(copy.deepcopy(resource))
                copied_resource_ids.add(resource_id)

    ref = ensure_effect_resource(root)
    library = ET.SubElement(root, "library")
    event_name = (event_names(source_root) or ["Stabilized Analysis"])[0]
    event = ET.SubElement(library, "event", {"name": event_name})
    project_duration = sum((parse_time(resource_by_id(source_root, asset_id).attrib["duration"]) for asset_id in results), start=parse_time("0s"))
    first_asset = resource_by_id(source_root, next(iter(results)))
    first_format = first_asset.attrib["format"]
    sequence_attrs = {
        "format": first_format,
        "duration": time_string(project_duration),
        "tcStart": "0s",
        "tcFormat": "NDF",
    }
    project = ET.SubElement(event, "project", {"name": "Tokyo Walking Stabilizer - Analyzed Footage"})
    sequence = ET.SubElement(project, "sequence", sequence_attrs)
    spine = ET.SubElement(sequence, "spine")
    offset = parse_time("0s")
    for asset_id, result in results.items():
        asset = resource_by_id(source_root, asset_id)
        source_clip = first_event_asset_clip(source_root, asset_id)
        append_filtered_asset_clip(event, asset, source_clip, ref, result)
        append_filtered_asset_clip(spine, asset, source_clip, ref, result, offset=time_string(offset))
        offset += parse_time(asset.attrib["duration"])
    return root


def build_single_asset_tree(source_root: ET.Element, asset_id: str, result: dict) -> ET.Element:
    return build_analyzed_only_tree(source_root, {asset_id: result})


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


def analysis_manifest(source_root: ET.Element, asset_id: str, result: dict, cache_root: str | None = None) -> dict:
    asset = resource_by_id(source_root, asset_id)
    source_clip = first_event_asset_clip(source_root, asset_id)
    media_reps = []
    if asset is not None:
        for child in asset:
            if local_name(child.tag) == "media-rep":
                media_reps.append({
                    "kind": child.attrib.get("kind"),
                    "src": child.attrib.get("src"),
                })
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
        "footageName": result.get("name") or (asset.attrib.get("name") if asset is not None else asset_id),
        "footageFileName": result.get("footageFileName") or result.get("name") or (asset.attrib.get("name") if asset is not None else asset_id),
        "mediaPath": result.get("mediaPath"),
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
        "preparedMotionPath": prepared_fields,
        "sourceClip": {
            "start": source_clip.attrib.get("start") if source_clip is not None else None,
            "duration": source_clip.attrib.get("duration") if source_clip is not None else None,
        },
    }


def short_identity(identity: str | None) -> str | None:
    if not identity:
        return None
    return zlib.adler32(identity.encode("utf-8")).to_bytes(4, "big").hex()


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build_per_footage_packages(source_root: ET.Element, results: dict[str, dict], source_path: Path, output_dir: Path, cache_root: str | None) -> list[dict]:
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
        tree = ET.ElementTree(build_single_asset_tree(source_root, asset_id, result))
        tree.write(info_path, encoding="utf-8", xml_declaration=True)
        manifest_path = package_dir / f"{footage}.analysis-manifest.json"
        manifest = analysis_manifest(source_root, asset_id, result, cache_root=cache_root)
        write_json(manifest_path, manifest)
        packages.append({
            "assetId": asset_id,
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
            "preparedMotionPath": manifest["preparedMotionPath"],
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
        help="Build a compact FCPXMLD containing only analyzed video assets and one review project.",
    )
    parser.add_argument(
        "--per-footage-packages",
        action="store_true",
        help="Build one import package directory per analyzed footage with a manifest next to the FCPXMLD.",
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
            if args.per_footage_packages:
                packages = build_per_footage_packages(
                    root,
                    results,
                    args.source_fcpxml,
                    args.output_dir,
                    str(args.cache_root or analysis.get("cacheRoot") or ""),
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
        if args.only_analyzed_assets:
            root = build_analyzed_only_tree(root, results)
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
                "safeName": safe_file_component(package_path.stem),
            }
        )
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
