#!/usr/bin/env python3
"""Compare two LiquidBar performance summary JSON files or run directories."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, NamedTuple


class MetricSpec(NamedTuple):
    key: str
    label: str
    higher_better: bool
    fallback_key: str | None = None


DEFAULT_METRICS = [
    MetricSpec("callback_p95_median_ms", "Callback p95 median ms", False, "callback_p95_worst_ms"),
    MetricSpec("render_p95_median_ms", "Render p95 median ms", False, "render_p95_worst_ms"),
    MetricSpec("gpu_p95_median_ms", "GPU p95 median ms", False, "gpu_p95_worst_ms"),
    MetricSpec("gpu_wall_p95_median_ms", "GPU wall p95 median ms", False, "gpu_wall_p95_worst_ms"),
    MetricSpec("drawable_miss_total", "Drawable misses", False),
    MetricSpec("poll_p95_median_ms", "Poll p95 median ms", False, "poll_p95_worst_ms"),
    MetricSpec("switcher_open_p95_ms", "Switcher open p95 ms", False, "switcher_open_worst_ms"),
    MetricSpec(
        "switcher_cycle_step_p95_ms",
        "Switcher cycle step p95 ms",
        False,
        "switcher_cycle_step_worst_ms",
    ),
    MetricSpec("switcher_failed_total", "Switcher failed actions", False),
]

WORST_METRICS = [
    MetricSpec("callback_p95_worst_ms", "Callback p95 worst ms", False),
    MetricSpec("render_p95_worst_ms", "Render p95 worst ms", False),
    MetricSpec("gpu_p95_worst_ms", "GPU p95 worst ms", False),
    MetricSpec("gpu_wall_p95_worst_ms", "GPU wall p95 worst ms", False),
    MetricSpec("poll_p95_worst_ms", "Poll p95 worst ms", False),
    MetricSpec("switcher_open_worst_ms", "Switcher open worst ms", False),
    MetricSpec("switcher_cycle_step_worst_ms", "Switcher cycle step worst ms", False),
]

ACTIVE_FPS_METRIC = MetricSpec("fps_min", "FPS min", True)
FRAME_LINES_METRIC = MetricSpec("frame_lines", "Frame log lines", False)


def resolve_summary_path(value: str) -> Path:
    path = Path(value)
    if path.is_dir():
        path = path / "summary.json"
    return path


def load_summary(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"summary not found: {path}")
    return json.loads(path.read_text())


def numeric(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def get_metric(metrics: dict[str, Any], key: str, fallback_key: str | None) -> tuple[float | None, str | None]:
    value = numeric(metrics.get(key))
    if value is not None:
        return value, key
    if fallback_key:
        value = numeric(metrics.get(fallback_key))
        if value is not None:
            return value, fallback_key
    return None, None


def compare_metric(
    spec: MetricSpec,
    baseline_metrics: dict[str, Any],
    candidate_metrics: dict[str, Any],
    max_regression_percent: float,
    min_regression_absolute: float,
    min_signal_percent: float,
) -> dict[str, Any]:
    baseline, baseline_source = get_metric(baseline_metrics, spec.key, spec.fallback_key)
    candidate, candidate_source = get_metric(candidate_metrics, spec.key, spec.fallback_key)
    result: dict[str, Any] = {
        "metric": spec.key,
        "label": spec.label,
        "higher_better": spec.higher_better,
        "baseline_metric": baseline_source,
        "candidate_metric": candidate_source,
        "baseline": baseline,
        "candidate": candidate,
        "improvement_percent": None,
        "absolute_delta": None,
        "status": "missing",
    }

    if baseline is None or candidate is None:
        return result

    if baseline == 0:
        if candidate == 0:
            improvement_percent = 0.0
        elif spec.higher_better:
            improvement_percent = 100.0
        else:
            improvement_percent = -100.0
    elif spec.higher_better:
        improvement_percent = ((candidate - baseline) / abs(baseline)) * 100.0
    else:
        improvement_percent = ((baseline - candidate) / abs(baseline)) * 100.0

    absolute_delta = candidate - baseline
    regression_magnitude = (baseline - candidate) if spec.higher_better else (candidate - baseline)

    if improvement_percent < -max_regression_percent and regression_magnitude > min_regression_absolute:
        status = "regression"
    elif improvement_percent > min_signal_percent:
        status = "improvement"
    else:
        status = "flat"

    result["improvement_percent"] = improvement_percent
    result["absolute_delta"] = absolute_delta
    result["status"] = status
    return result


def fmt(value: Any, places: int = 2) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, int):
        return str(value)
    try:
        return f"{float(value):.{places}f}"
    except (TypeError, ValueError):
        return str(value)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", help="baseline summary.json or run directory")
    parser.add_argument("candidate", help="candidate summary.json or run directory")
    parser.add_argument("--json-out", help="write comparison JSON")
    parser.add_argument("--markdown-out", help="write comparison Markdown")
    parser.add_argument(
        "--max-regression-percent",
        type=float,
        default=5.0,
        help="fail when a metric regresses by more than this percentage (default: 5)",
    )
    parser.add_argument(
        "--min-signal-percent",
        type=float,
        default=1.0,
        help="label improvements only when they exceed this percentage (default: 1)",
    )
    parser.add_argument(
        "--min-regression-absolute",
        type=float,
        default=0.5,
        help="ignore relative regressions smaller than this absolute metric delta (default: 0.5)",
    )
    parser.add_argument(
        "--include-fps",
        action="store_true",
        help="include fps_min in regression checks for active-animation runs",
    )
    parser.add_argument(
        "--include-frame-lines",
        action="store_true",
        help="include frame log line count as a lower-is-better churn metric for idle/cursor runs",
    )
    parser.add_argument(
        "--compare-worst",
        action="store_true",
        help="also compare worst interval p95 metrics relatively; absolute worst thresholds are always enforced",
    )
    args = parser.parse_args()

    baseline_path = resolve_summary_path(args.baseline)
    candidate_path = resolve_summary_path(args.candidate)
    baseline_summary = load_summary(baseline_path)
    candidate_summary = load_summary(candidate_path)
    baseline_metrics = baseline_summary.get("metrics", {})
    candidate_metrics = candidate_summary.get("metrics", {})

    metric_specs = list(DEFAULT_METRICS)
    if args.include_fps:
        metric_specs.insert(0, ACTIVE_FPS_METRIC)
    if args.include_frame_lines:
        metric_specs.insert(0, FRAME_LINES_METRIC)
    if args.compare_worst:
        metric_specs.extend(WORST_METRICS)

    comparisons = [
        compare_metric(
            spec,
            baseline_metrics,
            candidate_metrics,
            args.max_regression_percent,
            args.min_regression_absolute,
            args.min_signal_percent,
        )
        for spec in metric_specs
    ]

    regressions = [row for row in comparisons if row["status"] == "regression"]
    candidate_threshold_passed = bool(candidate_summary.get("passed", False))
    passed = candidate_threshold_passed and not regressions

    result = {
        "schema_version": 2,
        "baseline": baseline_path.name,
        "candidate": candidate_path.name,
        "candidate_threshold_passed": candidate_threshold_passed,
        "max_regression_percent": args.max_regression_percent,
        "min_regression_absolute": args.min_regression_absolute,
        "min_signal_percent": args.min_signal_percent,
        "include_fps": args.include_fps,
        "include_frame_lines": args.include_frame_lines,
        "compare_worst": args.compare_worst,
        "comparisons": comparisons,
        "regressions": regressions,
        "passed": passed,
    }

    print("LiquidBar performance A/B comparison")
    print(f"  baseline: {baseline_path}")
    print(f"  candidate: {candidate_path}")
    print(f"  candidate_threshold_passed: {str(candidate_threshold_passed).lower()}")
    for row in comparisons:
        print(
            "  "
            f"{row['metric']}: "
            f"baseline={fmt(row['baseline'])} "
            f"candidate={fmt(row['candidate'])} "
            f"delta={fmt(row['absolute_delta'])} "
            f"improvement={fmt(row['improvement_percent'])}% "
            f"status={row['status']}"
        )
    print(f"  result: {'PASS' if passed else 'FAIL'}")

    if args.json_out:
        out_path = Path(args.json_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")

    if args.markdown_out:
        out_path = Path(args.markdown_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# LiquidBar Performance A/B Comparison",
            "",
            f"- Baseline: `{baseline_path.name}`",
            f"- Candidate: `{candidate_path.name}`",
            f"- Candidate absolute thresholds passed: `{str(candidate_threshold_passed).lower()}`",
            f"- FPS included: `{str(args.include_fps).lower()}`",
            f"- Frame lines included: `{str(args.include_frame_lines).lower()}`",
            f"- Worst metrics compared relatively: `{str(args.compare_worst).lower()}`",
            f"- Result: `{'PASS' if passed else 'FAIL'}`",
            "",
            "| Metric | Baseline | Candidate | Delta | Improvement % | Status |",
            "| --- | ---: | ---: | ---: | ---: | --- |",
        ]
        for row in comparisons:
            lines.append(
                f"| {row['label']} | {fmt(row['baseline'])} | "
                f"{fmt(row['candidate'])} | {fmt(row['absolute_delta'])} | "
                f"{fmt(row['improvement_percent'])} | "
                f"`{row['status']}` |"
            )
        if regressions:
            lines.extend(["", "## Regressions", ""])
            for row in regressions:
                lines.append(
                    f"- {row['label']}: {fmt(row['improvement_percent'])}% "
                    "relative change"
                )
        lines.append("")
        out_path.write_text("\n".join(lines))

    return 0 if passed else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
