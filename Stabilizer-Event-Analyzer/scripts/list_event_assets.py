#!/usr/bin/env python3
"""List full-media Event assets from an FCPXML or FCPXMLD package."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable

from fcpxml_common import (
    SCHEMA_VERSION,
    duration_timecode,
    event_names,
    fraction_seconds,
    load_event_assets,
    resolve_info_path,
)
import xml.etree.ElementTree as ET


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return status


def fail(message: str) -> int:
    return emit({"schemaVersion": SCHEMA_VERSION, "status": "error", "error": message}, 1)


def asset_payload(asset, index: int) -> dict:
    return {
        "id": asset.id,
        "index": index,
        "name": asset.name,
        "eventName": asset.event_name,
        "assetId": asset.id,
        "mediaPath": str(asset.media_path) if asset.media_path else None,
        "mediaKind": asset.media_kind,
        "frameDuration": (
            f"{asset.frame_duration.numerator}/{asset.frame_duration.denominator}s"
            if asset.frame_duration
            else None
        ),
        "frameDurationSeconds": fraction_seconds(asset.frame_duration),
        "duration": f"{asset.duration.numerator}/{asset.duration.denominator}s" if asset.duration else None,
        "durationSeconds": fraction_seconds(asset.duration),
        "durationTimecode": duration_timecode(asset.duration, asset.frame_duration),
        "sourceStart": f"{asset.source_start.numerator}/{asset.source_start.denominator}s",
        "sourceStartSeconds": fraction_seconds(asset.source_start),
        "width": asset.width,
        "height": asset.height,
        "unsupported": asset.unsupported,
        "supported": asset.unsupported is None,
    }


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fcpxml", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        info_path, package_path = resolve_info_path(args.fcpxml)
        root = ET.parse(info_path).getroot()
        assets = load_event_assets(info_path)
        return emit(
            {
                "schemaVersion": SCHEMA_VERSION,
                "status": "ok",
                "sourcePath": str(args.fcpxml),
                "infoPath": str(info_path),
                "packagePath": str(package_path) if package_path else None,
                "eventNames": event_names(root),
                "assetCount": len(assets),
                "assets": [asset_payload(asset, index) for index, asset in enumerate(assets)],
            }
        )
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
