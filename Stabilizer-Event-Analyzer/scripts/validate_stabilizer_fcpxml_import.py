#!/usr/bin/env python3
"""Validate a Tokyo Walking Stabilizer per-footage import package before FCP import."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path
from typing import Iterable

from fcpxml_common import SCHEMA_VERSION, local_name, parse_time, resolve_info_path, resources
from build_stabilizer_fcpxml_import import EFFECT_NAME, EFFECT_UID, LEGACY_FILTER_NAMES


FCPXML_DTD_INVALID_FILTER_VIDEO_ATTRS = {"nameOverride", "videoOverride"}


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return status


def failure(message: str, failures: list[str] | None = None) -> int:
    return emit(
        {
            "schemaVersion": SCHEMA_VERSION,
            "status": "fail",
            "error": message,
            "failures": failures or [message],
        },
        1,
    )


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fcpxml", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    return parser.parse_args(argv)


def filter_name(element: ET.Element) -> str:
    return element.attrib.get("nameOverride") or element.attrib.get("name") or ""


def resource_by_id(root: ET.Element) -> dict[str, ET.Element]:
    return {
        child.attrib["id"]: child
        for child in resources(root)
        if child.attrib.get("id")
    }


def parent_map(root: ET.Element) -> dict[ET.Element, ET.Element]:
    return {child: parent for parent in root.iter() for child in list(parent)}


def has_ancestor(element: ET.Element, parents: dict[ET.Element, ET.Element], tag_name: str) -> bool:
    current = parents.get(element)
    while current is not None:
        if local_name(current.tag) == tag_name:
            return True
        current = parents.get(current)
    return False


def has_media_rep(asset: ET.Element) -> bool:
    return any(local_name(child.tag) == "media-rep" and child.attrib.get("src") for child in asset)


def valid_time(value: str | None, *, positive: bool = False) -> bool:
    try:
        parsed = parse_time(value)
    except Exception:
        return False
    if positive:
        return parsed > Fraction(0)
    return parsed >= Fraction(0)


def stabilizer_filter_identities(root: ET.Element) -> list[str]:
    identities = []
    for element in root.iter():
        if local_name(element.tag) != "filter-video" or filter_name(element) != EFFECT_NAME:
            continue
        identity = None
        for child in element:
            if local_name(child.tag) == "param" and child.attrib.get("name") == "Host Analysis Cache Identity":
                identity = child.attrib.get("value", "").strip()
                break
        identities.append(identity or "")
    return identities


def cache_prepared_path_present(cache_payload: dict) -> bool:
    frame_count = len(cache_payload.get("frames") or [])
    for key in ("pathX", "pathY", "pathRoll"):
        value = cache_payload.get(key)
        if not isinstance(value, list) or len(value) != frame_count or frame_count == 0:
            return False
    return True


def cache_index_entry(manifest_path: Path, manifest: dict, cache_identity: str) -> dict | None:
    payload_dir = manifest.get("cachePayloadDirectory")
    if not payload_dir:
        return None
    index_path = manifest_path.parent / payload_dir / "host-analysis-index-v2.json"
    if not index_path.exists():
        return None
    index = json.loads(index_path.read_text(encoding="utf-8"))
    for entry in index.get("entries") or []:
        if (entry.get("cacheIdentity") or "").strip() == cache_identity:
            return entry
    return None


def validate(root: ET.Element, manifest: dict, manifest_path: Path) -> list[str]:
    failures: list[str] = []
    asset_id = manifest.get("assetId")
    cache_identity = (manifest.get("cacheIdentity") or "").strip()
    resource_map = resource_by_id(root)
    asset = resource_map.get(asset_id or "")
    parents = parent_map(root)

    if not asset_id:
        failures.append("manifest is missing assetId")
    if not cache_identity:
        failures.append("manifest is missing cacheIdentity")
    if asset is None or local_name(asset.tag) != "asset":
        failures.append(f"analyzed asset resource is missing: {asset_id}")
    else:
        if asset.attrib.get("hasVideo") != "1":
            failures.append(f"asset is not marked as video: {asset_id}")
        if not asset.attrib.get("format") or asset.attrib.get("format") not in resource_map:
            failures.append(f"asset format resource is missing: {asset_id}")
        if not has_media_rep(asset):
            failures.append(f"asset has no media-rep src: {asset_id}")
        if not valid_time(asset.attrib.get("start"), positive=False):
            failures.append(f"asset start is invalid: {asset_id}")
        if not valid_time(asset.attrib.get("duration"), positive=True):
            failures.append(f"asset duration is invalid: {asset_id}")

    effect_ids = {
        child.attrib["id"]
        for child in resources(root)
        if local_name(child.tag) == "effect" and child.attrib.get("uid") == EFFECT_UID and child.attrib.get("id")
    }
    if not effect_ids:
        failures.append("Tokyo Walking Stabilizer effect resource is missing")
    identities = stabilizer_filter_identities(root)
    if not identities:
        failures.append("Tokyo Walking Stabilizer filter is missing")
    for identity in identities:
        if not identity:
            failures.append("Host Analysis Cache Identity parameter is empty")
        elif identity != cache_identity:
            failures.append("Host Analysis Cache Identity does not match manifest")

    for element in root.iter():
        tag = local_name(element.tag)
        if tag == "filter-video":
            invalid_attrs = sorted(FCPXML_DTD_INVALID_FILTER_VIDEO_ATTRS.intersection(element.attrib))
            if invalid_attrs:
                failures.append(f"filter-video contains FCPXML DTD-invalid attribute(s): {', '.join(invalid_attrs)}")
            name = filter_name(element)
            if name in LEGACY_FILTER_NAMES:
                failures.append(f"legacy filter remains: {name}")
            if name == EFFECT_NAME and element.attrib.get("ref") not in effect_ids:
                failures.append("Tokyo Walking Stabilizer filter does not reference the expected effect resource")
        if tag in {"asset-clip", "video"} and element.attrib.get("ref"):
            ref = element.attrib["ref"]
            if ref != asset_id:
                failures.append(f"import package contains non-analyzed footage ref: {ref}")
            if tag == "asset-clip":
                if has_ancestor(element, parents, "project"):
                    failures.append("project edit uses asset-clip directly instead of video")
            if not valid_time(element.attrib.get("start"), positive=False):
                failures.append(f"{tag} start is invalid for ref {ref}")
            if not valid_time(element.attrib.get("duration"), positive=True):
                failures.append(f"{tag} duration is invalid for ref {ref}")
        if tag == "ref-clip" and element.attrib.get("ref"):
            ref = element.attrib["ref"]
            failures.append(f"import package contains ref-clip instead of direct video edit: {ref}")
            if not valid_time(element.attrib.get("start"), positive=False):
                failures.append(f"ref-clip start is invalid for ref {ref}")
            if not valid_time(element.attrib.get("duration"), positive=True):
                failures.append(f"ref-clip duration is invalid for ref {ref}")

    prepared = manifest.get("preparedMotionPath")
    if prepared is not True:
        failures.append("manifest does not confirm prepared motion path")
    if manifest.get("cacheSchemaVersion") is None:
        failures.append("manifest is missing cache schema version")
    if manifest.get("sampleWidth") is None or manifest.get("sampleHeight") is None:
        failures.append("manifest is missing sample size")
    if not manifest.get("frameCount"):
        failures.append("manifest is missing frame count")
    payload_cache_file = manifest.get("cachePayloadCacheFile")
    if not payload_cache_file:
        failures.append("manifest is missing cache payload file")
    else:
        payload_path = (manifest_path.parent / payload_cache_file).resolve()
        if not payload_path.exists():
            failures.append(f"cache payload file is missing: {payload_cache_file}")
        else:
            try:
                cache_payload = json.loads(payload_path.read_text(encoding="utf-8"))
                index_entry = cache_index_entry(manifest_path, manifest, cache_identity)
                if index_entry is None:
                    failures.append("cache payload index does not contain manifest identity")
                elif index_entry.get("cacheFileName") != Path(payload_cache_file).name:
                    failures.append("cache payload index file name does not match manifest")
                if cache_payload.get("schemaVersion") != manifest.get("cacheSchemaVersion"):
                    failures.append("cache payload schema does not match manifest")
                if len(cache_payload.get("frames") or []) != manifest.get("frameCount"):
                    failures.append("cache payload frame count does not match manifest")
                if not cache_prepared_path_present(cache_payload):
                    failures.append("cache payload does not confirm prepared motion path")
            except Exception as exc:  # noqa: BLE001
                failures.append(f"cache payload is unreadable: {exc}")

    return sorted(set(failures))


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        info_path, package_path = resolve_info_path(args.fcpxml)
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        root = ET.parse(info_path).getroot()
        failures = validate(root, manifest, args.manifest)
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "status": "pass" if not failures else "fail",
            "fcpxml": str(package_path or info_path),
            "infoPath": str(info_path),
            "manifestPath": str(args.manifest),
            "assetId": manifest.get("assetId"),
            "cacheIdentity": manifest.get("cacheIdentity"),
            "cacheIdentityShort": manifest.get("cacheIdentityShort"),
            "failures": failures,
            "importReady": not failures,
        }
        if args.output:
            args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return emit(payload, 0 if not failures else 1)
    except Exception as exc:  # noqa: BLE001
        return failure(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
