#!/usr/bin/env python3
"""Install a per-footage Stabilizer package cache into an FCP Event cache root."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Iterable

from fcpxml_common import SCHEMA_VERSION


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return status


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument(
        "--event-root",
        type=Path,
        required=False,
        help="FCP Event directory inside the .fcpbundle, for example .../Library.fcpbundle/Event Name",
    )
    return parser.parse_args(argv)


def infer_event_root(manifest: dict) -> Path:
    media_path_value = manifest.get("mediaPath")
    if not media_path_value:
        raise ValueError("manifest is missing mediaPath; pass --event-root explicitly")
    media_path = Path(media_path_value).expanduser().resolve()
    bundle_root = None
    for parent in media_path.parents:
        if parent.suffix == ".fcpbundle":
            bundle_root = parent
            break
    if bundle_root is None:
        raise ValueError("mediaPath is not inside an .fcpbundle; pass --event-root explicitly")
    relative_parts = media_path.relative_to(bundle_root).parts
    if len(relative_parts) < 2:
        raise ValueError("mediaPath does not include an Event directory inside the .fcpbundle")
    return bundle_root / relative_parts[0]


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        manifest_path = args.manifest.resolve()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        cache_identity = (manifest.get("cacheIdentity") or "").strip()
        payload_cache_file = manifest.get("cachePayloadCacheFile")
        if not cache_identity:
            raise ValueError("manifest is missing cacheIdentity")
        if not payload_cache_file:
            raise ValueError("manifest is missing cachePayloadCacheFile")
        source_cache_file = (manifest_path.parent / payload_cache_file).resolve()
        if not source_cache_file.exists():
            raise FileNotFoundError(f"cache payload file is missing: {source_cache_file}")
        cache_payload = json.loads(source_cache_file.read_text(encoding="utf-8"))
        if cache_payload.get("schemaVersion") != manifest.get("cacheSchemaVersion"):
            raise ValueError("cache payload schema does not match manifest")
        if len(cache_payload.get("frames") or []) != manifest.get("frameCount"):
            raise ValueError("cache payload frame count does not match manifest")
        payload_dir = manifest_path.parent / (manifest.get("cachePayloadDirectory") or "")
        index_path = payload_dir / "host-analysis-index-v2.json"
        if not index_path.exists():
            raise FileNotFoundError(f"cache payload index is missing: {index_path}")
        index = json.loads(index_path.read_text(encoding="utf-8"))
        index_entry = next(
            (entry for entry in index.get("entries") or [] if (entry.get("cacheIdentity") or "").strip() == cache_identity),
            None,
        )
        if index_entry is None:
            raise ValueError("cache payload index does not contain manifest identity")
        if index_entry.get("cacheFileName") != source_cache_file.name:
            raise ValueError("cache payload index file name does not match manifest")

        event_root = args.event_root.expanduser().resolve() if args.event_root else infer_event_root(manifest)
        if not event_root.exists() or not event_root.is_dir():
            raise FileNotFoundError(f"FCP Event root is missing: {event_root}")
        cache_root = event_root / "Analysis Files" / "TokyoWalkingStabilizerHostAnalysis"
        caches_dir = cache_root / "caches"
        caches_dir.mkdir(parents=True, exist_ok=True)

        installed_files = []
        target_cache_file = caches_dir / source_cache_file.name
        shutil.copy2(source_cache_file, target_cache_file)
        installed_files.append(str(target_cache_file))
        for sidecar in ("host-analysis-index-v2.json", "host-analysis-v2.json", "host-analysis-render-offset-v2.json"):
            source_sidecar = payload_dir / sidecar
            if source_sidecar.exists():
                target_sidecar = cache_root / sidecar
                shutil.copy2(source_sidecar, target_sidecar)
                installed_files.append(str(target_sidecar))

        return emit(
            {
                "schemaVersion": SCHEMA_VERSION,
                "status": "ok",
                "eventRoot": str(event_root),
                "cacheRoot": str(cache_root),
                "cacheIdentity": cache_identity,
                "cacheIdentityShort": manifest.get("cacheIdentityShort"),
                "installedFiles": installed_files,
            }
        )
    except Exception as exc:  # noqa: BLE001
        return emit({"schemaVersion": SCHEMA_VERSION, "status": "error", "error": str(exc)}, 1)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
