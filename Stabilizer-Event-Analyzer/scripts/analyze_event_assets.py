#!/usr/bin/env python3
"""Run serial full-media Stabilizer analysis for FCPXMLD Event assets."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable

from fcpxml_common import SCHEMA_VERSION, event_names, fraction_seconds, load_event_assets, resolve_info_path
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[1]
NATIVE_PACKAGE = REPO_ROOT / "native_analyzer"
EXECUTABLE_NAME = "StabilizerEventAnalyzer"
CACHE_DIR_NAME = "TokyoWalkingStabilizerHostAnalysis"


def emit(payload: dict, status: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return status


def fail(message: str) -> int:
    return emit({"schemaVersion": SCHEMA_VERSION, "status": "error", "error": message}, 1)


def normalize_cache_root(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if resolved.name == CACHE_DIR_NAME:
        return resolved
    if resolved.name == "Analysis Files":
        return resolved / CACHE_DIR_NAME
    return resolved / "Analysis Files" / CACHE_DIR_NAME


def swift_command(plan_path: Path, progress: bool) -> list[str]:
    built_executables = [
        NATIVE_PACKAGE / ".build" / "release" / EXECUTABLE_NAME,
        *sorted((NATIVE_PACKAGE / ".build").glob("*-apple-macosx/release/" + EXECUTABLE_NAME)),
    ]
    for built_executable in built_executables:
        if built_executable.exists():
            command = [str(built_executable), "--plan", str(plan_path)]
            if progress:
                command.append("--progress")
            return command
    swift = shutil.which("swift")
    if not swift:
        raise RuntimeError("swift was not found on PATH; native analyzer cannot run")
    if progress:
        print("prebuilt native analyzer was not found; building with swift run", file=sys.stderr)
    command = [
        swift,
        "run",
        "--package-path",
        str(NATIVE_PACKAGE),
        "-c",
        "release",
        EXECUTABLE_NAME,
        "--plan",
        str(plan_path),
    ]
    if progress:
        command.append("--progress")
    return command


def selected_assets(fcpxml_path: Path, asset_ids: list[str], all_assets: bool) -> tuple[Path, Path | None, list[dict], list[str]]:
    info_path, package_path = resolve_info_path(fcpxml_path)
    assets = load_event_assets(info_path)
    selected_ids = set(asset_ids)
    payloads: list[dict] = []
    skipped: list[str] = []
    for asset in assets:
        if not all_assets and asset.id not in selected_ids:
            continue
        if asset.unsupported:
            skipped.append(f"{asset.id}: {asset.unsupported}")
            continue
        if not asset.media_path or asset.duration is None or asset.frame_duration is None:
            skipped.append(f"{asset.id}: missing media path, duration, or frame duration")
            continue
        payloads.append(
            {
                "assetId": asset.id,
                "name": asset.name,
                "mediaPath": str(asset.media_path),
                "mediaKind": asset.media_kind,
                "durationSeconds": fraction_seconds(asset.duration),
                "frameDurationSeconds": fraction_seconds(asset.frame_duration),
                "sourceStartSeconds": fraction_seconds(asset.source_start) or 0,
                "width": asset.width,
                "height": asset.height,
            }
        )
    if not payloads:
        raise ValueError("no supported Event assets were selected")
    return info_path, package_path, payloads, skipped


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fcpxml", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--asset-id", action="append", default=[])
    parser.add_argument("--all", action="store_true", help="Analyze every supported Event media asset.")
    parser.add_argument("--sample-scale-percent", type=float, default=100.0)
    parser.add_argument("--max-frames", type=int)
    parser.add_argument("--progress", action="store_true")
    return parser.parse_args(argv)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    try:
        if not args.all and not args.asset_id:
            raise ValueError("select at least one --asset-id or pass --all")
        info_path, package_path, assets, skipped = selected_assets(args.fcpxml, args.asset_id, args.all)
        root = ET.parse(info_path).getroot()
        cache_root = normalize_cache_root(args.cache_root)
        cache_root.mkdir(parents=True, exist_ok=True)
        plan = {
            "schemaVersion": SCHEMA_VERSION,
            "sourcePath": str(args.fcpxml),
            "infoPath": str(info_path),
            "packagePath": str(package_path) if package_path else None,
            "cacheRoot": str(cache_root),
            "eventName": (event_names(root) or [None])[0],
            "sampleScalePercent": args.sample_scale_percent,
            "maxFrames": args.max_frames,
            "assets": assets,
        }
        with tempfile.TemporaryDirectory(prefix="stabilizer-event-analysis-") as tmp:
            plan_path = Path(tmp) / "plan.json"
            plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
            process = subprocess.run(
                swift_command(plan_path, args.progress),
                text=True,
                stdout=subprocess.PIPE,
                stderr=sys.stderr if args.progress else subprocess.PIPE,
                check=False,
            )
            if process.returncode != 0:
                stderr = "" if args.progress else process.stderr
                raise RuntimeError(f"native analyzer failed with exit code {process.returncode}: {stderr.strip()}")
            try:
                payload = json.loads(process.stdout)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"native analyzer did not return JSON: {process.stdout[:500]}") from exc
        payload["schemaVersion"] = SCHEMA_VERSION
        payload["status"] = "ok"
        payload["sourcePath"] = str(args.fcpxml)
        payload["infoPath"] = str(info_path)
        payload["packagePath"] = str(package_path) if package_path else None
        payload["cacheRoot"] = str(cache_root)
        payload["skipped"] = skipped
        return emit(payload)
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
