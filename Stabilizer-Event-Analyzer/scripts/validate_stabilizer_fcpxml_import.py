#!/usr/bin/env python3
"""Validate a Tokyo Walking Stabilizer per-footage import package before FCP import."""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path
from typing import Iterable

from fcpxml_common import SCHEMA_VERSION, file_url_to_path, local_name, parse_time, resolve_info_path, resources
from build_stabilizer_fcpxml_import import EFFECT_NAME, EFFECT_UID, LEGACY_FILTER_NAMES
from event_cache_resolution import resolve_event_root_from_manifest


ALWAYS_INVALID_FILTER_VIDEO_ATTRS = {"videoOverride"}
NAME_OVERRIDE_MIN_VERSION = (1, 12)
FCP_RESOURCE_ID_PATTERN = re.compile(r"^r[0-9]+$")
EXPECTED_CACHE_SCHEMA_VERSION = 48


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


def fcpxml_version_tuple(root: ET.Element) -> tuple[int, int]:
    value = root.attrib.get("version") or "0.0"
    try:
        major, minor = value.split(".", 1)
        return int(major), int(minor)
    except ValueError:
        return 0, 0


def invalid_filter_video_attrs(root: ET.Element, element: ET.Element) -> list[str]:
    invalid = set(ALWAYS_INVALID_FILTER_VIDEO_ATTRS).intersection(element.attrib)
    if fcpxml_version_tuple(root) < NAME_OVERRIDE_MIN_VERSION and "nameOverride" in element.attrib:
        invalid.add("nameOverride")
    return sorted(invalid)


def resource_by_id(root: ET.Element) -> dict[str, ET.Element]:
    return {
        child.attrib["id"]: child
        for child in resources(root)
        if child.attrib.get("id")
    }


def valid_fcp_resource_id(value: str | None) -> bool:
    return bool(value and FCP_RESOURCE_ID_PATTERN.fullmatch(value))


def parent_map(root: ET.Element) -> dict[ET.Element, ET.Element]:
    return {child: parent for parent in root.iter() for child in list(parent)}


def has_ancestor(element: ET.Element, parents: dict[ET.Element, ET.Element], tag_name: str) -> bool:
    current = parents.get(element)
    while current is not None:
        if local_name(current.tag) == tag_name:
            return True
        current = parents.get(current)
    return False


def filter_applies_to_project_media(
    element: ET.Element,
    parents: dict[ET.Element, ET.Element],
    asset_id: str | None,
) -> bool:
    current = parents.get(element)
    while current is not None:
        tag = local_name(current.tag)
        if tag in {"asset-clip", "video"} and current.attrib.get("ref") == asset_id:
            return has_ancestor(current, parents, "project")
        current = parents.get(current)
    return False


def filter_applies_to_event_media(
    element: ET.Element,
    parents: dict[ET.Element, ET.Element],
    asset_id: str | None,
) -> bool:
    current = parents.get(element)
    while current is not None:
        tag = local_name(current.tag)
        if tag in {"asset-clip", "video"} and current.attrib.get("ref") == asset_id:
            return has_ancestor(current, parents, "event") and not has_ancestor(current, parents, "project")
        current = parents.get(current)
    return False


def has_media_rep(asset: ET.Element) -> bool:
    return any(local_name(child.tag) == "media-rep" and child.attrib.get("src") for child in asset)


def normalized_path_identity(path: Path) -> str:
    try:
        return str(path.expanduser().resolve(strict=False))
    except OSError:
        return str(path.expanduser())


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


def asset_matches_manifest_media_path(asset: ET.Element, manifest: dict) -> bool:
    media_path = manifest.get("mediaPath")
    if not media_path:
        return True
    expected = normalized_path_identity(Path(str(media_path)))
    return any(normalized_path_identity(path) == expected for path in asset_media_paths(asset))


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
    for key in (
        "pathX",
        "pathY",
        "pathRoll",
        "farFieldRigidShakePathX",
        "farFieldRigidShakePathY",
        "farFieldRigidShakePathRoll",
        "farFieldRigidShakeSupport",
        "farFieldRigidShakeRollSupport",
        "farFieldRigidShakeShapeConsistency",
        "farFieldRigidShakeForwardBackwardConsistency",
    ):
        value = cache_payload.get(key)
        if not isinstance(value, list) or len(value) != frame_count or frame_count == 0:
            return False
    if cache_payload.get("farFieldMeshRows") != 5 or cache_payload.get("farFieldMeshColumns") != 9:
        return False
    mesh_count = frame_count * 45
    for key in ("farFieldMeshPathX", "farFieldMeshPathY", "farFieldMeshSupport"):
        value = cache_payload.get(key)
        if not isinstance(value, list) or len(value) != mesh_count:
            return False
    for key in (
        "farFieldMeshDominantWindowFrames",
        "farFieldMeshDominantWindowSeconds",
        "farFieldMeshDominantSupport",
        "farFieldMeshDominantCell",
    ):
        value = cache_payload.get(key)
        if not isinstance(value, list) or len(value) != frame_count:
            return False
    if cache_payload.get("sourceLensShakeLocalBinCount") != 15:
        return False
    local_count = frame_count * 15
    for key in ("sourceLensShakeLocalPathX", "sourceLensShakeLocalPathY", "sourceLensShakeLocalSupport"):
        value = cache_payload.get(key)
        if not isinstance(value, list) or len(value) != local_count:
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


def manifest_event_root_validation(manifest: dict, manifest_path: Path, cache_identity: str) -> tuple[list[str], dict | None]:
    event_root_value = manifest.get("eventRoot")
    if not event_root_value:
        return [], None

    cache_file_name = manifest.get("cacheFileName")
    resolution = resolve_event_root_from_manifest(
        manifest,
        manifest_path,
        cache_identity,
        str(cache_file_name) if cache_file_name else None,
    )
    if resolution.get("status") != "ok":
        return [str(resolution.get("message") or "manifest Event root could not be resolved")], resolution

    event_root = Path(str(resolution["eventRoot"])).expanduser()
    failures = []
    event_name = manifest.get("eventName")
    if resolution.get("source") == "manifest-event-root" and event_name and event_root.name != event_name:
        failures.append(f"manifest eventName does not match eventRoot folder name: {event_name} != {event_root.name}")
    return failures, resolution


def validate(root: ET.Element, manifest: dict, manifest_path: Path) -> tuple[list[str], dict | None]:
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
    event_root_resolution = None
    if cache_identity:
        event_root_failures, event_root_resolution = manifest_event_root_validation(manifest, manifest_path, cache_identity)
        failures.extend(event_root_failures)
    for resource in resources(root):
        resource_id = resource.attrib.get("id")
        if resource_id and not valid_fcp_resource_id(resource_id):
            failures.append(f"resource id is not FCP numeric r-id: {resource_id}")
    if asset is None or local_name(asset.tag) != "asset":
        failures.append(f"analyzed asset resource is missing: {asset_id}")
    else:
        if asset.attrib.get("hasVideo") != "1":
            failures.append(f"asset is not marked as video: {asset_id}")
        if not asset.attrib.get("uid"):
            failures.append(f"asset is missing FCP media uid: {asset_id}")
        if not asset.attrib.get("format") or asset.attrib.get("format") not in resource_map:
            failures.append(f"asset format resource is missing: {asset_id}")
        if not has_media_rep(asset):
            failures.append(f"asset has no media-rep src: {asset_id}")
        elif not asset_matches_manifest_media_path(asset, manifest):
            failures.append(f"asset media-rep does not match manifest mediaPath: {asset_id}")
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

    project_count = 0
    project_stabilizer_count = 0
    event_stabilizer_count = 0
    for element in root.iter():
        tag = local_name(element.tag)
        if tag == "project":
            project_count += 1
        if tag == "sequence":
            format_id = element.attrib.get("format")
            format_resource = resource_map.get(format_id or "")
            if format_id and format_resource is None:
                failures.append(f"sequence format resource is missing: {format_id}")
            elif format_resource is not None and not (format_resource.attrib.get("name") or format_resource.attrib.get("colorSpace")):
                failures.append(f"sequence format resource lacks FCP format name/colorSpace: {format_id}")
        if tag == "filter-video":
            invalid_attrs = invalid_filter_video_attrs(root, element)
            if invalid_attrs:
                failures.append(f"filter-video contains FCPXML DTD-invalid attribute(s): {', '.join(invalid_attrs)}")
            name = filter_name(element)
            if name in LEGACY_FILTER_NAMES:
                failures.append(f"legacy filter remains: {name}")
            if name == EFFECT_NAME and element.attrib.get("ref") not in effect_ids:
                failures.append("Tokyo Walking Stabilizer filter does not reference the expected effect resource")
            if name == EFFECT_NAME and filter_applies_to_project_media(element, parents, asset_id):
                project_stabilizer_count += 1
            if name == EFFECT_NAME and filter_applies_to_event_media(element, parents, asset_id):
                event_stabilizer_count += 1
        if tag in {"asset-clip", "video"} and element.attrib.get("ref"):
            ref = element.attrib["ref"]
            if ref != asset_id:
                failures.append(f"import package contains non-analyzed footage ref: {ref}")
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

    if project_count != 1:
        failures.append(f"import package must contain exactly one review project, found {project_count}")
    if project_stabilizer_count == 0:
        failures.append("review project clip is missing Tokyo Walking Stabilizer filter")
    if event_stabilizer_count == 0:
        failures.append("event browser clip is missing Tokyo Walking Stabilizer filter")

    prepared = manifest.get("preparedMotionPath")
    if prepared is not True:
        failures.append("manifest does not confirm prepared motion path")
    manifest_schema_version = manifest.get("cacheSchemaVersion")
    if manifest_schema_version is None:
        failures.append("manifest is missing cache schema version")
    elif manifest_schema_version != EXPECTED_CACHE_SCHEMA_VERSION:
        failures.append(
            f"manifest cache schema must be {EXPECTED_CACHE_SCHEMA_VERSION}, found {manifest_schema_version}"
        )
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
                if cache_payload.get("schemaVersion") != manifest_schema_version:
                    failures.append("cache payload schema does not match manifest")
                if cache_payload.get("schemaVersion") != EXPECTED_CACHE_SCHEMA_VERSION:
                    failures.append(
                        f"cache payload schema must be {EXPECTED_CACHE_SCHEMA_VERSION}, "
                        f"found {cache_payload.get('schemaVersion')}"
                    )
                if len(cache_payload.get("frames") or []) != manifest.get("frameCount"):
                    failures.append("cache payload frame count does not match manifest")
                if not cache_prepared_path_present(cache_payload):
                    failures.append("cache payload does not confirm prepared motion path")
            except Exception as exc:  # noqa: BLE001
                failures.append(f"cache payload is unreadable: {exc}")

    return sorted(set(failures)), event_root_resolution


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        info_path, package_path = resolve_info_path(args.fcpxml)
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        root = ET.parse(info_path).getroot()
        failures, event_root_resolution = validate(root, manifest, args.manifest)
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "status": "pass" if not failures else "fail",
            "fcpxml": str(package_path or info_path),
            "infoPath": str(info_path),
            "manifestPath": str(args.manifest),
            "assetId": manifest.get("assetId"),
            "cacheIdentity": manifest.get("cacheIdentity"),
            "cacheIdentityShort": manifest.get("cacheIdentityShort"),
            "eventRootResolution": event_root_resolution,
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
