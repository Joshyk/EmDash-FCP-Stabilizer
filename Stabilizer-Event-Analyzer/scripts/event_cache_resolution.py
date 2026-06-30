#!/usr/bin/env python3
"""Resolve Stabilizer Event cache roots from package manifests."""

from __future__ import annotations

import json
from pathlib import Path


CACHE_DIR_NAME = "TokyoWalkingStabilizerHostAnalysis"
INDEX_FILE_NAME = "host-analysis-index-v2.json"


def _path_identity(path: Path) -> str:
    try:
        return str(path.expanduser().resolve(strict=False))
    except OSError:
        return str(path.expanduser())


def _fcpbundle_root_for(path: Path) -> Path | None:
    current = path.expanduser()
    for candidate in [current, *current.parents]:
        if candidate.suffix == ".fcpbundle":
            return candidate.resolve(strict=False)
    return None


def _manifest_event_root(manifest: dict) -> Path | None:
    event_root_value = manifest.get("eventRoot")
    if not event_root_value:
        return None
    return Path(str(event_root_value)).expanduser().resolve(strict=False)


def _bundle_roots_from_manifest(manifest: dict, manifest_path: Path) -> tuple[list[Path], list[str]]:
    roots: list[Path] = []
    sources: list[str] = []

    def add(root: Path | None, source: str) -> None:
        if root is None:
            return
        root = root.expanduser().resolve(strict=False)
        if _path_identity(root) in {_path_identity(existing) for existing in roots}:
            return
        roots.append(root)
        sources.append(source)

    event_root = _manifest_event_root(manifest)
    add(_fcpbundle_root_for(event_root), "manifest eventRoot") if event_root else None

    media_path_value = manifest.get("mediaPath")
    if media_path_value:
        add(_fcpbundle_root_for(Path(str(media_path_value))), "manifest mediaPath")

    if not any(root.exists() and root.is_dir() for root in roots):
        for parent in [manifest_path.parent, *manifest_path.parents]:
            if parent.name != "stablizer_analysis":
                continue
            sibling_root = parent.parent
            if sibling_root.is_dir():
                for bundle in sorted(sibling_root.glob("*.fcpbundle"), key=lambda item: item.name.casefold()):
                    add(bundle, "stablizer_analysis sibling bundle")
            break

    return roots, sources


def _candidate_event_roots(bundle_root: Path) -> list[Path]:
    if not bundle_root.exists() or not bundle_root.is_dir():
        return []
    return [
        child.resolve(strict=False)
        for child in sorted(bundle_root.iterdir(), key=lambda item: item.name.casefold())
        if child.is_dir() and not child.name.startswith(".")
    ]


def _event_cache_root(event_root: Path) -> Path:
    return event_root / "Analysis Files" / CACHE_DIR_NAME


def _index_matches_event(cache_root: Path, cache_identity: str, cache_file_name: str | None) -> bool:
    index_path = cache_root / INDEX_FILE_NAME
    if not index_path.exists():
        return False
    try:
        index = json.loads(index_path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return False
    for entry in index.get("entries") or []:
        if (entry.get("cacheIdentity") or "").strip() != cache_identity:
            continue
        entry_file = (entry.get("cacheFileName") or "").strip()
        if cache_file_name and entry_file != cache_file_name:
            continue
        if entry_file and (cache_root / "caches" / entry_file).exists():
            return True
    return False


def _media_name_matches_event(event_root: Path, media_file_name: str | None) -> bool:
    if not media_file_name:
        return False
    original_media = event_root / "Original Media"
    if not original_media.is_dir():
        return False
    wanted = media_file_name.casefold()
    try:
        for media_path in original_media.rglob("*"):
            if media_path.name.casefold() == wanted:
                return True
    except OSError:
        return False
    return False


def resolve_event_root_from_manifest(
    manifest: dict,
    manifest_path: Path,
    cache_identity: str,
    cache_file_name: str | None,
) -> dict:
    """Return a visible resolution payload for a manifest Event root."""

    event_root = _manifest_event_root(manifest)
    if event_root and event_root.exists() and event_root.is_dir():
        return {
            "status": "ok",
            "source": "manifest-event-root",
            "eventRoot": str(event_root),
            "message": "manifest Event root exists",
        }
    if event_root and event_root.exists() and not event_root.is_dir():
        return {
            "status": "error",
            "source": "manifest-event-root",
            "eventRoot": str(event_root),
            "message": f"manifest Event root is not a directory: {event_root}",
        }

    bundle_roots, bundle_sources = _bundle_roots_from_manifest(manifest, manifest_path)
    matches: list[Path] = []
    for bundle_root in bundle_roots:
        for candidate_event in _candidate_event_roots(bundle_root):
            if _index_matches_event(_event_cache_root(candidate_event), cache_identity, cache_file_name):
                matches.append(candidate_event)

    unique_matches: list[Path] = []
    seen: set[str] = set()
    for match in matches:
        key = _path_identity(match)
        if key in seen:
            continue
        seen.add(key)
        unique_matches.append(match)

    searched = [str(root) for root in bundle_roots]
    if len(unique_matches) == 1:
        match = unique_matches[0]
        return {
            "status": "ok",
            "source": "cache-identity-in-current-bundle",
            "eventRoot": str(match),
            "message": f"manifest Event root changed; resolved current Event by cache identity: {match}",
            "searchedBundleRoots": searched,
            "bundleRootSources": bundle_sources,
        }
    if len(unique_matches) > 1:
        return {
            "status": "error",
            "source": "cache-identity-in-current-bundle",
            "message": "manifest Event root changed and cache identity matched multiple Event roots: "
            + " | ".join(str(match) for match in unique_matches),
            "searchedBundleRoots": searched,
        }

    media_file_name = manifest.get("footageFileName")
    if not media_file_name and manifest.get("mediaPath"):
        media_file_name = Path(str(manifest["mediaPath"])).name
    media_matches: list[Path] = []
    for bundle_root, source in zip(bundle_roots, bundle_sources, strict=False):
        if source == "stablizer_analysis sibling bundle":
            continue
        for candidate_event in _candidate_event_roots(bundle_root):
            if _media_name_matches_event(candidate_event, str(media_file_name) if media_file_name else None):
                media_matches.append(candidate_event)
    unique_media_matches: list[Path] = []
    seen.clear()
    for match in media_matches:
        key = _path_identity(match)
        if key in seen:
            continue
        seen.add(key)
        unique_media_matches.append(match)
    if len(unique_media_matches) == 1:
        match = unique_media_matches[0]
        return {
            "status": "ok",
            "source": "unique-original-media-name",
            "eventRoot": str(match),
            "message": f"manifest Event root changed; resolved current Event by unique Original Media file name: {match}",
            "searchedBundleRoots": searched,
            "bundleRootSources": bundle_sources,
        }
    if len(unique_media_matches) > 1:
        return {
            "status": "error",
            "source": "unique-original-media-name",
            "message": "manifest Event root changed and Original Media file name matched multiple Event roots: "
            + " | ".join(str(match) for match in unique_media_matches),
            "searchedBundleRoots": searched,
        }

    missing = f"manifest Event root is missing: {event_root}" if event_root else "manifest is missing eventRoot"
    suffix = f"; no matching current Event cache was found in: {' | '.join(searched)}" if searched else ""
    return {
        "status": "error",
        "source": "unresolved",
        "message": missing + suffix,
        "searchedBundleRoots": searched,
    }
