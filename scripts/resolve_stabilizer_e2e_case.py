#!/usr/bin/env python3
"""Resolve a portable Stabilizer E2E case using the current environment."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
from typing import Any


VARIABLE_PATTERN = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


class CaseResolutionError(ValueError):
    """Raised when a portable E2E case cannot be resolved explicitly."""


def expand_environment(value: Any, location: str = "case") -> Any:
    if isinstance(value, dict):
        return {
            key: expand_environment(child, f"{location}.{key}")
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [
            expand_environment(child, f"{location}[{index}]")
            for index, child in enumerate(value)
        ]
    if not isinstance(value, str):
        return value

    def replacement(match: re.Match[str]) -> str:
        variable = match.group(1)
        resolved = os.environ.get(variable)
        if not resolved:
            raise CaseResolutionError(
                f"{location} requires non-empty environment variable {variable}"
            )
        return resolved

    return VARIABLE_PATTERN.sub(replacement, value)


def resolve_relative_media(case: dict[str, Any], key: str) -> None:
    relative_key = f"{key}Relative"
    relative_value = case.get(relative_key)
    if relative_value is None:
        return
    if not isinstance(relative_value, str) or not relative_value:
        raise CaseResolutionError(f"case.{relative_key} must be a non-empty string")

    relative_path = Path(relative_value)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise CaseResolutionError(
            f"case.{relative_key} must stay inside the configured E2E library"
        )

    library = Path(case["library"])
    case[key] = str(library / relative_path)


def resolve_case(raw_case: Any) -> dict[str, Any]:
    if not isinstance(raw_case, dict):
        raise CaseResolutionError("case root must be a JSON object")

    case = expand_environment(raw_case)
    library_value = case.get("library")
    if not isinstance(library_value, str) or not library_value:
        raise CaseResolutionError("case.library must be a non-empty string")

    library = Path(library_value).expanduser()
    if not library.is_absolute():
        raise CaseResolutionError("case.library must resolve to an absolute path")
    case["library"] = str(library)

    resolve_relative_media(case, "originalMedia")
    resolve_relative_media(case, "proxyMedia")
    return case


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        with args.input.open(encoding="utf-8") as handle:
            raw_case = json.load(handle)
        resolved = resolve_case(raw_case)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8") as handle:
            json.dump(resolved, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
    except (OSError, json.JSONDecodeError, CaseResolutionError) as error:
        print(f"resolve_stabilizer_e2e_case.py: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
