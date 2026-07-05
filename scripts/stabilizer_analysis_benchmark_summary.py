#!/usr/bin/env python3
"""Summarize Stabilizer Event Analyzer timing JSON for benchmark comparisons."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


TIMING_KEYS = [
    "frameCount",
    "totalWallSeconds",
    "readFramesWallSeconds",
    "readerLaneWallSeconds",
    "decoderCopyNextFrameSeconds",
    "metalEncodeSeconds",
    "metalCompleteSeconds",
    "preparedPathSeconds",
    "cacheBuildSeconds",
    "cacheWriteSeconds",
    "readerLaneCount",
    "framesPerWallSecond",
]

STAGE_KEYS = [
    "decoderCopyNextFrameSeconds",
    "metalEncodeSeconds",
    "metalCompleteSeconds",
    "preparedPathSeconds",
    "cacheBuildSeconds",
    "cacheWriteSeconds",
]


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return payload


def aggregate_timings(rows: list[dict[str, Any]]) -> dict[str, Any] | None:
    usable = [
        row
        for row in rows
        if isinstance(row, dict) and isinstance(row.get("totalWallSeconds"), (int, float))
    ]
    if not usable:
        return None
    totals: dict[str, Any] = {}
    for row in usable:
        for key in TIMING_KEYS:
            value = row.get(key)
            if isinstance(value, (int, float)):
                totals[key] = totals.get(key, 0) + value
    frame_count = totals.get("frameCount")
    total_seconds = totals.get("totalWallSeconds")
    if isinstance(frame_count, (int, float)) and isinstance(total_seconds, (int, float)) and total_seconds > 0:
        totals["framesPerWallSecond"] = frame_count / total_seconds
    totals["resultCount"] = len(usable)
    return totals


def timing_from_payload(payload: dict[str, Any]) -> dict[str, Any] | None:
    direct = payload.get("analysisTimings")
    if isinstance(direct, dict):
        return direct
    direct = payload.get("summaryAnalysisTimings")
    if isinstance(direct, dict):
        return direct
    results = payload.get("results")
    if isinstance(results, list):
        result_timings = [
            item.get("analysisTimings")
            for item in results
            if isinstance(item, dict) and isinstance(item.get("analysisTimings"), dict)
        ]
        aggregated = aggregate_timings(result_timings)
        if aggregated:
            return aggregated
    summary = payload.get("summary")
    if isinstance(summary, dict):
        summary_timing = summary.get("analysisTimings")
        if isinstance(summary_timing, dict):
            return summary_timing
    source_results = payload.get("sourceResults")
    if isinstance(source_results, list):
        source_timings = [
            item.get("summaryAnalysisTimings")
            for item in source_results
            if isinstance(item, dict) and isinstance(item.get("summaryAnalysisTimings"), dict)
        ]
        aggregated = aggregate_timings(source_timings)
        if aggregated:
            return aggregated
    return None


def clip_name(payload: dict[str, Any], path: Path) -> str:
    for key in ("footageName", "sourceClip", "sourceName", "name"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value
    results = payload.get("results")
    if isinstance(results, list) and len(results) == 1 and isinstance(results[0], dict):
        value = results[0].get("name")
        if isinstance(value, str) and value.strip():
            return value
    return path.stem


def summarize_file(path: Path) -> dict[str, Any]:
    payload = load_json(path)
    timing = timing_from_payload(payload)
    summary: dict[str, Any] = {
        "path": str(path),
        "clip": clip_name(payload, path),
        "hasAnalysisTimings": timing is not None,
    }
    if timing is None:
        summary["missingReason"] = "analysisTimings was not present in this artifact"
        return summary
    for key in TIMING_KEYS:
        if key in timing:
            summary[key] = timing[key]
    total_seconds = summary.get("totalWallSeconds")
    if isinstance(total_seconds, (int, float)) and total_seconds > 0:
        stages = [
            {
                "key": key,
                "seconds": float(timing.get(key, 0) or 0),
                "wallRatio": float(timing.get(key, 0) or 0) / float(total_seconds),
            }
            for key in STAGE_KEYS
        ]
        summary["stages"] = stages
        summary["bottleneck"] = max(stages, key=lambda item: item["seconds"])
    if "frameCount" not in summary:
        frame_count = payload.get("frameCount")
        if isinstance(frame_count, int):
            summary["frameCount"] = frame_count
    if "framesPerWallSecond" not in summary:
        frame_count = summary.get("frameCount")
        total_seconds = summary.get("totalWallSeconds")
        if isinstance(frame_count, (int, float)) and isinstance(total_seconds, (int, float)) and total_seconds > 0:
            summary["framesPerWallSecond"] = frame_count / total_seconds
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_paths", nargs="+", type=Path, help="Analysis manifest or analyzer output JSON files.")
    parser.add_argument("--output", type=Path, help="Optional path to write the benchmark summary JSON.")
    args = parser.parse_args()

    summaries = [summarize_file(path) for path in args.json_paths]
    payload = {
        "schemaVersion": 1,
        "benchmarkType": "stabilizer-analysis-timing-summary",
        "results": summaries,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
        print(args.output)
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
