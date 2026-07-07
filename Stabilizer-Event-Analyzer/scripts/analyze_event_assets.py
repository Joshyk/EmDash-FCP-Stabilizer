#!/usr/bin/env python3
"""Run serial full-media Stabilizer analysis for FCPXMLD Event assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterable

from fcpxml_common import (
    SCHEMA_VERSION,
    event_names,
    fraction_seconds,
    load_event_assets,
    resolve_info_path,
    safe_file_component,
)
import xml.etree.ElementTree as ET


REPO_ROOT = Path(__file__).resolve().parents[1]
NATIVE_PACKAGE = REPO_ROOT / "native_analyzer"
NATIVE_MAIN = NATIVE_PACKAGE / "Sources" / "StabilizerEventAnalyzer" / "main.swift"
EXECUTABLE_NAME = "StabilizerEventAnalyzer"
CACHE_DIR_NAME = "TokyoWalkingStabilizerHostAnalysis"
KERNEL_SOURCE_MARKER = 'fileprivate static let kernelSource = """'


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


def fcpbundle_source_path(package_path: Path | None) -> Path | None:
    if package_path is None:
        return None
    resolved = package_path.expanduser().resolve()
    if resolved.suffix == ".fcpbundle" and resolved.is_dir():
        return resolved
    return None


def event_scoped_cache_root(base_root: Path, event_name: str | None) -> Path:
    if not str(event_name or "").strip():
        raise ValueError(".fcpbundle analysis asset is missing an Event name; refusing an ambiguous retained cache path")
    event_label = safe_file_component(str(event_name))
    return base_root / event_label / "Analysis Files" / CACHE_DIR_NAME


def assign_asset_cache_roots(
    assets: list[dict],
    requested_cache_root: Path,
    package_path: Path | None,
) -> tuple[Path, list[Path]]:
    bundle_path = fcpbundle_source_path(package_path)
    if bundle_path is None:
        cache_root = normalize_cache_root(requested_cache_root)
        for asset in assets:
            asset["cacheRoot"] = str(cache_root)
        return cache_root, [cache_root]

    requested_root = requested_cache_root.expanduser().resolve()
    analysis_root = requested_root if requested_root.name == bundle_path.name else requested_root / bundle_path.name
    if analysis_root.resolve(strict=False) == bundle_path.resolve(strict=False):
        raise ValueError("retained analysis cache for .fcpbundle sources must not be inside the source .fcpbundle; use a sibling analysis directory")
    cache_roots: list[Path] = []
    seen: set[str] = set()
    for asset in assets:
        cache_root = event_scoped_cache_root(analysis_root, asset.get("eventName"))
        asset["cacheRoot"] = str(cache_root)
        cache_key = str(cache_root)
        if cache_key not in seen:
            seen.add(cache_key)
            cache_roots.append(cache_root)
    return analysis_root, cache_roots


def native_source_mtime() -> float:
    source_paths = [NATIVE_PACKAGE / "Package.swift"]
    source_paths.extend((NATIVE_PACKAGE / "Sources").rglob("*.swift"))
    existing = [path.stat().st_mtime for path in source_paths if path.exists()]
    if not existing:
        raise RuntimeError(f"native analyzer source files were not found: {NATIVE_PACKAGE}")
    return max(existing)


def fresh_built_executables() -> tuple[list[Path], list[Path]]:
    source_mtime = native_source_mtime()
    built_executables = [
        NATIVE_PACKAGE / ".build" / "release" / EXECUTABLE_NAME,
        *sorted((NATIVE_PACKAGE / ".build").glob("*-apple-macosx/release/" + EXECUTABLE_NAME)),
    ]
    fresh: list[Path] = []
    stale: list[Path] = []
    for built_executable in built_executables:
        if not built_executable.exists():
            continue
        if built_executable.stat().st_mtime >= source_mtime:
            fresh.append(built_executable)
        else:
            stale.append(built_executable)
    return fresh, stale


def extract_metal_kernel_source() -> str:
    text = NATIVE_MAIN.read_text(encoding="utf-8")
    try:
        start = text.index(KERNEL_SOURCE_MARKER) + len(KERNEL_SOURCE_MARKER)
        end = text.index('    """', start)
    except ValueError as exc:
        raise RuntimeError(f"could not find embedded Metal kernel source in {NATIVE_MAIN}") from exc
    source = text[start:end]
    if source.startswith("\n"):
        source = source[1:]
    if not source.strip():
        raise RuntimeError(f"embedded Metal kernel source was empty in {NATIVE_MAIN}")
    return source


def metal_tools() -> tuple[Path, Path]:
    metal = shutil.which("metal")
    if not metal:
        result = subprocess.run(
            ["xcrun", "-sdk", "macosx", "-f", "metal"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            raise RuntimeError(f"metal compiler was not found: {result.stderr.strip()}")
        metal = result.stdout.strip()
    metal_path = Path(metal)
    metallib_path = metal_path.with_name("metallib")
    if not metallib_path.exists():
        found = shutil.which("metallib")
        if found:
            metallib_path = Path(found)
    if not metallib_path.exists():
        raise RuntimeError(f"metallib tool was not found next to metal compiler: {metal_path}")
    return metal_path, metallib_path


def run_tool(command: list[str]) -> None:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        details = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"{Path(command[0]).name} failed with exit code {result.returncode}: {details}")


def precompiled_metallib(progress: bool) -> Path:
    source = extract_metal_kernel_source()
    digest = hashlib.sha256(source.encode("utf-8")).hexdigest()[:16]
    cache_dir = NATIVE_PACKAGE / ".build" / "stabilizer-analyzer-kernels"
    cache_dir.mkdir(parents=True, exist_ok=True)
    metal_source_path = cache_dir / f"AnalyzerKernels-{digest}.metal"
    air_path = cache_dir / f"AnalyzerKernels-{digest}.air"
    metallib_path = cache_dir / f"AnalyzerKernels-{digest}.metallib"
    if metallib_path.exists():
        return metallib_path
    metal_source_path.write_text(source, encoding="utf-8")
    metal, metallib = metal_tools()
    if progress:
        print(f"precompiling Stabilizer Metal analyzer kernels: {metallib_path}", file=sys.stderr)
    run_tool([str(metal), "-c", str(metal_source_path), "-o", str(air_path)])
    run_tool([str(metallib), str(air_path), "-o", str(metallib_path)])
    return metallib_path


def native_environment(metallib_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["STABILIZER_ANALYZER_METALLIB"] = str(metallib_path)
    return env


def swift_command(plan_path: Path, progress: bool) -> list[str]:
    fresh_executables, stale_executables = fresh_built_executables()
    for built_executable in fresh_executables:
        command = [str(built_executable), "--plan", str(plan_path)]
        if progress:
            command.append("--progress")
        return command
    swift = shutil.which("swift")
    if not swift:
        if stale_executables:
            stale_names = ", ".join(str(path) for path in stale_executables)
            raise RuntimeError(f"prebuilt native analyzer is stale and swift was not found on PATH; refusing stale executable(s): {stale_names}")
        raise RuntimeError("swift was not found on PATH; native analyzer cannot run")
    if progress:
        reason = "stale" if stale_executables else "not found"
        print(f"prebuilt native analyzer was {reason}; building with swift run", file=sys.stderr)
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
                "eventName": asset.event_name,
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
        analysis_root, cache_roots = assign_asset_cache_roots(assets, args.cache_root, package_path)
        for cache_root in cache_roots:
            cache_root.mkdir(parents=True, exist_ok=True)
        plan = {
            "schemaVersion": SCHEMA_VERSION,
            "sourcePath": str(args.fcpxml),
            "infoPath": str(info_path),
            "packagePath": str(package_path) if package_path else None,
            "cacheRoot": str(analysis_root),
            "eventName": (event_names(root) or [None])[0],
            "sampleScalePercent": args.sample_scale_percent,
            "maxFrames": args.max_frames,
            "assets": assets,
        }
        with tempfile.TemporaryDirectory(prefix="stabilizer-event-analysis-") as tmp:
            plan_path = Path(tmp) / "plan.json"
            plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
            metallib_path = precompiled_metallib(args.progress)
            process = subprocess.run(
                swift_command(plan_path, args.progress),
                env=native_environment(metallib_path),
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
        payload["cacheRoot"] = str(analysis_root)
        payload["cacheRoots"] = [str(cache_root) for cache_root in cache_roots]
        payload["skipped"] = skipped
        return emit(payload)
    except Exception as exc:  # noqa: BLE001
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
