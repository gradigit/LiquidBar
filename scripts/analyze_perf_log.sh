#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: analyze_perf_log.sh [options] <perf-stream.log>

Options:
  --json-out <path>       write machine-readable summary JSON
  --markdown-out <path>   write Markdown summary
  --no-thresholds         summarize without failing configured thresholds

Environment thresholds:
  LIQUIDBAR_PERF_FPS_MIN             default: disabled (set for active-animation runs)
  LIQUIDBAR_PERF_CALLBACK_P95_MAX    default: 12
  LIQUIDBAR_PERF_RENDER_P95_MAX      default: 8
  LIQUIDBAR_PERF_DRAWABLE_MISS_MAX   default: 3
  LIQUIDBAR_PERF_POLL_P95_MAX        default: 40
  LIQUIDBAR_PERF_SWITCHER_OPEN_P95_MAX       default: disabled
  LIQUIDBAR_PERF_SWITCHER_CYCLE_STEP_P95_MAX default: disabled
  LIQUIDBAR_PERF_SWITCHER_ANIMATION_FRAME_P95_MAX default: disabled
  LIQUIDBAR_PERF_THUMBNAIL_CAPTURE_P95_MAX   default: disabled
EOF
}

JSON_OUT=""
MARKDOWN_OUT=""
ENFORCE_THRESHOLDS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json-out)
      JSON_OUT="${2:-}"
      if [[ -z "$JSON_OUT" ]]; then
        usage
        exit 2
      fi
      shift 2
      ;;
    --markdown-out)
      MARKDOWN_OUT="${2:-}"
      if [[ -z "$MARKDOWN_OUT" ]]; then
        usage
        exit 2
      fi
      shift 2
      ;;
    --no-thresholds)
      ENFORCE_THRESHOLDS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

LOG_FILE="$1"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "error: log file not found: $LOG_FILE" >&2
  exit 2
fi

FPS_MIN="${LIQUIDBAR_PERF_FPS_MIN:-}"
CALLBACK_P95_MAX="${LIQUIDBAR_PERF_CALLBACK_P95_MAX:-12}"
RENDER_P95_MAX="${LIQUIDBAR_PERF_RENDER_P95_MAX:-8}"
DRAWABLE_MISS_MAX="${LIQUIDBAR_PERF_DRAWABLE_MISS_MAX:-3}"
POLL_P95_MAX="${LIQUIDBAR_PERF_POLL_P95_MAX:-40}"
SWITCHER_OPEN_P95_MAX="${LIQUIDBAR_PERF_SWITCHER_OPEN_P95_MAX:-}"
SWITCHER_CYCLE_STEP_P95_MAX="${LIQUIDBAR_PERF_SWITCHER_CYCLE_STEP_P95_MAX:-}"
SWITCHER_ANIMATION_FRAME_P95_MAX="${LIQUIDBAR_PERF_SWITCHER_ANIMATION_FRAME_P95_MAX:-}"
THUMBNAIL_CAPTURE_P95_MAX="${LIQUIDBAR_PERF_THUMBNAIL_CAPTURE_P95_MAX:-}"

python3 - "$LOG_FILE" "$JSON_OUT" "$MARKDOWN_OUT" "$ENFORCE_THRESHOLDS" \
  "$FPS_MIN" "$CALLBACK_P95_MAX" "$RENDER_P95_MAX" "$DRAWABLE_MISS_MAX" "$POLL_P95_MAX" \
  "$SWITCHER_OPEN_P95_MAX" "$SWITCHER_CYCLE_STEP_P95_MAX" "$SWITCHER_ANIMATION_FRAME_P95_MAX" \
  "$THUMBNAIL_CAPTURE_P95_MAX" <<'PY'
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 14:
    print("internal error: unexpected argv", file=sys.stderr)
    sys.exit(2)

log_path = Path(sys.argv[1])
json_out = sys.argv[2]
markdown_out = sys.argv[3]
enforce_thresholds = sys.argv[4] == "1"
thresholds = {
    "fps_min": float(sys.argv[5]) if sys.argv[5] else None,
    "callback_p95_max_ms": float(sys.argv[6]),
    "render_p95_max_ms": float(sys.argv[7]),
    "drawable_miss_max": float(sys.argv[8]),
    "poll_p95_max_ms": float(sys.argv[9]),
    "switcher_open_p95_max_ms": float(sys.argv[10]) if sys.argv[10] else None,
    "switcher_cycle_step_p95_max_ms": float(sys.argv[11]) if sys.argv[11] else None,
    "switcher_animation_frame_p95_max_ms": float(sys.argv[12]) if sys.argv[12] else None,
    "thumbnail_capture_p95_max_ms": float(sys.argv[13]) if sys.argv[13] else None,
}

frame_re = re.compile(
    r"frame d=(?P<display>\d+).*?"
    r"fps=(?P<fps>[0-9.]+).*?"
    r"callback_ms\(p50/p95\)=(?P<cb50>[^/]+)/(?P<cb95>[^ ]+).*?"
    r"render_ms\(p50/p95\)=(?P<r50>[^/]+)/(?P<r95>[^ ]+).*?"
    r"gpu_ms\(p50/p95\)=(?P<gpu50>[^/]+)/(?P<gpu95>[^ ]+).*?"
    r"gpu_wall_p95=(?P<gpuwall>[^ ]+).*?"
    r"drawable_miss=(?P<miss>\d+)"
)
poll_re = re.compile(
    r"poll interval_ms=(?P<interval>[0-9.]+).*?"
    r"exec=(?P<exec>\d+) skip=(?P<skip>\d+).*?"
    r"duration_ms\(p50/p95\)=(?P<p50>[^/]+)/(?P<p95>[^ ]+).*?"
    r"windows_p95=(?P<windows>[^ ]+)"
    r"(?: reasons=(?P<reasons>.*))?"
)
switcher_re = re.compile(
    r"switcher action=(?P<action>[-_a-zA-Z0-9]+).*?"
    r"duration_ms=(?P<duration>[0-9.]+).*?"
    r"count=(?P<count>\d+).*?"
    r"direction=(?P<direction>-?\d+).*?"
    r"entries=(?P<entries>\d+).*?"
    r"selected=(?P<selected>-?\d+).*?"
    r"success=(?P<success>[01])"
)
switcher_animation_re = re.compile(
    r"switcher_animation kind=(?P<kind>[-_a-zA-Z0-9]+).*?"
    r"duration_ms=(?P<duration>[0-9.]+).*?"
    r"frames=(?P<frames>\d+).*?"
    r"frame_ms\(p50/p95/max\)=(?P<frame50>[^/]+)/(?P<frame95>[^/]+)/(?P<framemax>[^ ]+).*?"
    r"retargets=(?P<retargets>\d+).*?"
    r"distance=(?P<distance>[0-9.]+).*?"
    r"success=(?P<success>[01])"
)
segment_re = re.compile(
    r"segment name=(?P<name>[-_a-zA-Z0-9]+).*?"
    r"count=(?P<count>\d+).*?"
    r"duration_ms\(p50/p95/max\)=(?P<p50>[^/]+)/(?P<p95>[^/]+)/(?P<max>[^ ]+)"
)
stall_re = re.compile(
    r"stall name=(?P<name>[-_a-zA-Z0-9]+).*?"
    r"duration_ms=(?P<duration>[0-9.]+)"
)
diag_re = re.compile(r"diag name=(?P<name>[-_a-zA-Z0-9]+)")
thumbnail_re = re.compile(
    r"thumbnail producer=(?P<producer>[-_a-zA-Z0-9]+).*?"
    r"tier=(?P<tier>[-_a-zA-Z0-9]+).*?"
    r"outcome=(?P<outcome>[-_a-zA-Z0-9]+).*?"
    r"queue_ms=(?P<queue>[0-9.]+).*?"
    r"capture_ms=(?P<capture>[0-9.]+).*?"
    r"total_ms=(?P<total>[0-9.]+).*?"
    r"bytes=(?P<bytes>\d+).*?"
    r"success=(?P<success>[01])"
)


def to_float(value: str):
    value = value.strip()
    if value in ("n/a", ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def max_or_none(values):
    values = [value for value in values if value is not None]
    return max(values) if values else None


def min_or_none(values):
    values = [value for value in values if value is not None]
    return min(values) if values else None


def percentile_or_none(values, p):
    values = sorted(value for value in values if value is not None)
    if not values:
        return None
    n = len(values)
    rank = int(((n - 1) * p) + 0.5)
    idx = min(max(int(rank), 0), n - 1)
    return values[idx]


def parse_reasons(raw):
    reasons: dict[str, int] = {}
    if not raw:
        return reasons
    for part in raw.split(","):
        part = part.strip()
        if not part or "=" not in part:
            continue
        key, value = part.rsplit("=", 1)
        try:
            reasons[key] = reasons.get(key, 0) + int(value)
        except ValueError:
            continue
    return reasons


frame_lines = 0
poll_lines = 0
fps_values: list[float] = []
callback_p95_values: list[float] = []
render_p95_values: list[float] = []
gpu_p95_values: list[float] = []
gpu_wall_p95_values: list[float] = []
drawable_miss_total = 0
poll_p95_values: list[float] = []
poll_windows_p95_values: list[float] = []
poll_exec_total = 0
poll_skip_total = 0
poll_reasons: dict[str, int] = {}
switcher_lines = 0
switcher_failed_total = 0
switcher_entries_max = 0
switcher_durations_by_action: dict[str, list[float]] = {}
switcher_step_durations_by_action: dict[str, list[float]] = {}
switcher_action_counts: dict[str, int] = {}
switcher_animation_lines = 0
switcher_animation_failed_total = 0
switcher_animation_duration_ms: list[float] = []
switcher_animation_frame_p50_ms: list[float] = []
switcher_animation_frame_p95_ms: list[float] = []
switcher_animation_frame_max_ms: list[float] = []
switcher_animation_frames: list[float] = []
switcher_animation_retargets_total = 0
switcher_animation_distance_total = 0.0
switcher_animation_counts_by_kind: dict[str, int] = {}
segment_lines = 0
segment_counts_by_name: dict[str, int] = {}
segment_p95_by_name: dict[str, list[float]] = {}
segment_max_by_name: dict[str, list[float]] = {}
stall_lines = 0
stall_counts_by_name: dict[str, int] = {}
stall_max_by_name: dict[str, list[float]] = {}
diag_lines = 0
diag_counts_by_name: dict[str, int] = {}
thumbnail_lines = 0
thumbnail_failed_total = 0
thumbnail_bytes_total = 0
thumbnail_queue_ms: list[float] = []
thumbnail_capture_ms: list[float] = []
thumbnail_total_ms: list[float] = []
thumbnail_capture_ms_by_producer_tier: dict[str, list[float]] = {}
thumbnail_total_ms_by_producer_tier: dict[str, list[float]] = {}
thumbnail_counts_by_producer: dict[str, int] = {}
thumbnail_counts_by_tier: dict[str, int] = {}
thumbnail_counts_by_outcome: dict[str, int] = {}

for raw in log_path.read_text(errors="replace").splitlines():
    frame_m = frame_re.search(raw)
    if frame_m:
        frame_lines += 1
        fps = to_float(frame_m.group("fps"))
        callback_p95 = to_float(frame_m.group("cb95"))
        render_p95 = to_float(frame_m.group("r95"))
        gpu_p95 = to_float(frame_m.group("gpu95"))
        gpu_wall_p95 = to_float(frame_m.group("gpuwall"))
        miss = to_float(frame_m.group("miss"))

        if fps is not None:
            fps_values.append(fps)
        if callback_p95 is not None:
            callback_p95_values.append(callback_p95)
        if render_p95 is not None:
            render_p95_values.append(render_p95)
        if gpu_p95 is not None:
            gpu_p95_values.append(gpu_p95)
        if gpu_wall_p95 is not None:
            gpu_wall_p95_values.append(gpu_wall_p95)
        if miss is not None:
            drawable_miss_total += int(miss)
        continue

    poll_m = poll_re.search(raw)
    if poll_m:
        poll_lines += 1
        poll_exec_total += int(poll_m.group("exec"))
        poll_skip_total += int(poll_m.group("skip"))
        p95 = to_float(poll_m.group("p95"))
        windows_p95 = to_float(poll_m.group("windows"))
        if p95 is not None:
            poll_p95_values.append(p95)
        if windows_p95 is not None:
            poll_windows_p95_values.append(windows_p95)
        for key, value in parse_reasons(poll_m.group("reasons")).items():
            poll_reasons[key] = poll_reasons.get(key, 0) + value
        continue

    switcher_m = switcher_re.search(raw)
    if switcher_m:
        switcher_lines += 1
        action = switcher_m.group("action")
        duration = to_float(switcher_m.group("duration"))
        count = max(1, int(switcher_m.group("count")))
        entries = int(switcher_m.group("entries"))
        success = switcher_m.group("success") == "1"

        switcher_action_counts[action] = switcher_action_counts.get(action, 0) + 1
        switcher_entries_max = max(switcher_entries_max, entries)
        if not success:
            switcher_failed_total += 1
        if duration is not None:
            switcher_durations_by_action.setdefault(action, []).append(duration)
            switcher_step_durations_by_action.setdefault(action, []).append(duration / count)
        continue

    switcher_animation_m = switcher_animation_re.search(raw)
    if switcher_animation_m:
        switcher_animation_lines += 1
        kind = switcher_animation_m.group("kind")
        duration = to_float(switcher_animation_m.group("duration"))
        frames = int(switcher_animation_m.group("frames"))
        frame50 = to_float(switcher_animation_m.group("frame50"))
        frame95 = to_float(switcher_animation_m.group("frame95"))
        frame_max = to_float(switcher_animation_m.group("framemax"))
        retargets = int(switcher_animation_m.group("retargets"))
        distance = to_float(switcher_animation_m.group("distance"))
        success = switcher_animation_m.group("success") == "1"

        switcher_animation_counts_by_kind[kind] = switcher_animation_counts_by_kind.get(kind, 0) + 1
        switcher_animation_frames.append(float(frames))
        switcher_animation_retargets_total += retargets
        if distance is not None:
            switcher_animation_distance_total += distance
        if not success:
            switcher_animation_failed_total += 1
        if duration is not None:
            switcher_animation_duration_ms.append(duration)
        if frame50 is not None:
            switcher_animation_frame_p50_ms.append(frame50)
        if frame95 is not None:
            switcher_animation_frame_p95_ms.append(frame95)
        if frame_max is not None:
            switcher_animation_frame_max_ms.append(frame_max)
        continue

    segment_m = segment_re.search(raw)
    if segment_m:
        segment_lines += 1
        name = segment_m.group("name")
        count = int(segment_m.group("count"))
        p95 = to_float(segment_m.group("p95"))
        max_value = to_float(segment_m.group("max"))
        segment_counts_by_name[name] = segment_counts_by_name.get(name, 0) + count
        if p95 is not None:
            segment_p95_by_name.setdefault(name, []).append(p95)
        if max_value is not None:
            segment_max_by_name.setdefault(name, []).append(max_value)
        continue

    stall_m = stall_re.search(raw)
    if stall_m:
        stall_lines += 1
        name = stall_m.group("name")
        duration = to_float(stall_m.group("duration"))
        stall_counts_by_name[name] = stall_counts_by_name.get(name, 0) + 1
        if duration is not None:
            stall_max_by_name.setdefault(name, []).append(duration)
        continue

    diag_m = diag_re.search(raw)
    if diag_m:
        diag_lines += 1
        name = diag_m.group("name")
        diag_counts_by_name[name] = diag_counts_by_name.get(name, 0) + 1
        continue

    thumbnail_m = thumbnail_re.search(raw)
    if thumbnail_m:
        thumbnail_lines += 1
        producer = thumbnail_m.group("producer")
        tier = thumbnail_m.group("tier")
        outcome = thumbnail_m.group("outcome")
        queue_ms = to_float(thumbnail_m.group("queue"))
        capture_ms = to_float(thumbnail_m.group("capture"))
        total_ms = to_float(thumbnail_m.group("total"))
        byte_count = int(thumbnail_m.group("bytes"))
        success = thumbnail_m.group("success") == "1"
        key = f"{producer}:{tier}"

        thumbnail_counts_by_producer[producer] = thumbnail_counts_by_producer.get(producer, 0) + 1
        thumbnail_counts_by_tier[tier] = thumbnail_counts_by_tier.get(tier, 0) + 1
        thumbnail_counts_by_outcome[outcome] = thumbnail_counts_by_outcome.get(outcome, 0) + 1
        thumbnail_bytes_total += byte_count
        if not success:
            thumbnail_failed_total += 1
        if queue_ms is not None:
            thumbnail_queue_ms.append(queue_ms)
        if capture_ms is not None:
            thumbnail_capture_ms.append(capture_ms)
            thumbnail_capture_ms_by_producer_tier.setdefault(key, []).append(capture_ms)
        if total_ms is not None:
            thumbnail_total_ms.append(total_ms)
            thumbnail_total_ms_by_producer_tier.setdefault(key, []).append(total_ms)


segment_p95_worst_by_name = {
    key: max_or_none(values)
    for key, values in sorted(segment_p95_by_name.items())
}
segment_max_worst_by_name = {
    key: max_or_none(values)
    for key, values in sorted(segment_max_by_name.items())
}
stall_max_by_name_summary = {
    key: max_or_none(values)
    for key, values in sorted(stall_max_by_name.items())
}
thumbnail_capture_p95_by_producer_tier = {
    key: percentile_or_none(values, 0.95)
    for key, values in sorted(thumbnail_capture_ms_by_producer_tier.items())
}
thumbnail_total_p95_by_producer_tier = {
    key: percentile_or_none(values, 0.95)
    for key, values in sorted(thumbnail_total_ms_by_producer_tier.items())
}

metrics = {
    "frame_lines": frame_lines,
    "poll_lines": poll_lines,
    "fps_min": min_or_none(fps_values),
    "fps_max": max_or_none(fps_values),
    "callback_p95_worst_ms": max_or_none(callback_p95_values),
    "callback_p95_median_ms": percentile_or_none(callback_p95_values, 0.50),
    "render_p95_worst_ms": max_or_none(render_p95_values),
    "render_p95_median_ms": percentile_or_none(render_p95_values, 0.50),
    "gpu_p95_worst_ms": max_or_none(gpu_p95_values),
    "gpu_p95_median_ms": percentile_or_none(gpu_p95_values, 0.50),
    "gpu_wall_p95_worst_ms": max_or_none(gpu_wall_p95_values),
    "gpu_wall_p95_median_ms": percentile_or_none(gpu_wall_p95_values, 0.50),
    "drawable_miss_total": drawable_miss_total,
    "poll_p95_worst_ms": max_or_none(poll_p95_values),
    "poll_p95_median_ms": percentile_or_none(poll_p95_values, 0.50),
    "poll_windows_p95_worst": max_or_none(poll_windows_p95_values),
    "poll_windows_p95_median": percentile_or_none(poll_windows_p95_values, 0.50),
    "poll_exec_total": poll_exec_total,
    "poll_skip_total": poll_skip_total,
    "poll_reasons": dict(sorted(poll_reasons.items())),
    "switcher_lines": switcher_lines,
    "switcher_failed_total": switcher_failed_total,
    "switcher_entries_max": switcher_entries_max,
    "switcher_action_counts": dict(sorted(switcher_action_counts.items())),
    "switcher_open_count": len(switcher_durations_by_action.get("open", [])),
    "switcher_open_cold_ms": (switcher_durations_by_action.get("open", []) or [None])[0],
    "switcher_open_median_ms": percentile_or_none(switcher_durations_by_action.get("open", []), 0.50),
    "switcher_open_p95_ms": percentile_or_none(switcher_durations_by_action.get("open", []), 0.95),
    "switcher_open_worst_ms": max_or_none(switcher_durations_by_action.get("open", [])),
    "switcher_open_warm_median_ms": percentile_or_none(switcher_durations_by_action.get("open", [])[1:], 0.50),
    "switcher_open_warm_p95_ms": percentile_or_none(switcher_durations_by_action.get("open", [])[1:], 0.95),
    "switcher_open_warm_worst_ms": max_or_none(switcher_durations_by_action.get("open", [])[1:]),
    "switcher_cycle_median_ms": percentile_or_none(switcher_durations_by_action.get("cycle", []), 0.50),
    "switcher_cycle_p95_ms": percentile_or_none(switcher_durations_by_action.get("cycle", []), 0.95),
    "switcher_cycle_worst_ms": max_or_none(switcher_durations_by_action.get("cycle", [])),
    "switcher_cycle_step_median_ms": percentile_or_none(
        switcher_step_durations_by_action.get("cycle", []),
        0.50,
    ),
    "switcher_cycle_step_p95_ms": percentile_or_none(
        switcher_step_durations_by_action.get("cycle", []),
        0.95,
    ),
    "switcher_cycle_step_worst_ms": max_or_none(switcher_step_durations_by_action.get("cycle", [])),
    "switcher_animation_lines": switcher_animation_lines,
    "switcher_animation_failed_total": switcher_animation_failed_total,
    "switcher_animation_counts_by_kind": dict(sorted(switcher_animation_counts_by_kind.items())),
    "switcher_animation_duration_p50_ms": percentile_or_none(switcher_animation_duration_ms, 0.50),
    "switcher_animation_duration_p95_ms": percentile_or_none(switcher_animation_duration_ms, 0.95),
    "switcher_animation_frame_count_p50": percentile_or_none(switcher_animation_frames, 0.50),
    "switcher_animation_frame_count_p95": percentile_or_none(switcher_animation_frames, 0.95),
    "switcher_animation_frame_p50_ms": percentile_or_none(switcher_animation_frame_p50_ms, 0.50),
    "switcher_animation_frame_p95_ms": percentile_or_none(switcher_animation_frame_p95_ms, 0.95),
    "switcher_animation_frame_max_ms": max_or_none(switcher_animation_frame_max_ms),
    "switcher_animation_retargets_total": switcher_animation_retargets_total,
    "switcher_animation_distance_total": switcher_animation_distance_total,
    "segment_lines": segment_lines,
    "segment_counts": dict(sorted(segment_counts_by_name.items())),
    "segment_p95_worst_by_name_ms": segment_p95_worst_by_name,
    "segment_max_worst_by_name_ms": segment_max_worst_by_name,
    "stall_lines": stall_lines,
    "stall_counts": dict(sorted(stall_counts_by_name.items())),
    "stall_max_by_name_ms": stall_max_by_name_summary,
    "diag_lines": diag_lines,
    "diag_counts": dict(sorted(diag_counts_by_name.items())),
    "thumbnail_lines": thumbnail_lines,
    "thumbnail_failed_total": thumbnail_failed_total,
    "thumbnail_success_total": thumbnail_lines - thumbnail_failed_total,
    "thumbnail_bytes_total": thumbnail_bytes_total,
    "thumbnail_queue_p95_ms": percentile_or_none(thumbnail_queue_ms, 0.95),
    "thumbnail_capture_p95_ms": percentile_or_none(thumbnail_capture_ms, 0.95),
    "thumbnail_total_p95_ms": percentile_or_none(thumbnail_total_ms, 0.95),
    "thumbnail_capture_p95_by_producer_tier_ms": thumbnail_capture_p95_by_producer_tier,
    "thumbnail_total_p95_by_producer_tier_ms": thumbnail_total_p95_by_producer_tier,
    "thumbnail_counts_by_producer": dict(sorted(thumbnail_counts_by_producer.items())),
    "thumbnail_counts_by_tier": dict(sorted(thumbnail_counts_by_tier.items())),
    "thumbnail_counts_by_outcome": dict(sorted(thumbnail_counts_by_outcome.items())),
}

failures: list[str] = []
if enforce_thresholds:
    if frame_lines == 0 and poll_lines == 0 and switcher_lines == 0 and switcher_animation_lines == 0 and thumbnail_lines == 0:
        failures.append("no frame, poll, switcher, switcher animation, or thumbnail metrics were found in perf log")
    if thresholds["fps_min"] is not None and metrics["fps_min"] is None:
        failures.append("no frame metrics were found for active fps threshold")
    if (
        thresholds["fps_min"] is not None
        and metrics["fps_min"] is not None
        and metrics["fps_min"] < thresholds["fps_min"]
    ):
        failures.append(f"fps_min {metrics['fps_min']:.1f} < threshold {thresholds['fps_min']:.1f}")
    if (
        metrics["callback_p95_worst_ms"] is not None
        and metrics["callback_p95_worst_ms"] > thresholds["callback_p95_max_ms"]
    ):
        failures.append(
            f"callback_p95_worst {metrics['callback_p95_worst_ms']:.2f} > "
            f"threshold {thresholds['callback_p95_max_ms']:.2f}"
        )
    if (
        metrics["render_p95_worst_ms"] is not None
        and metrics["render_p95_worst_ms"] > thresholds["render_p95_max_ms"]
    ):
        failures.append(
            f"render_p95_worst {metrics['render_p95_worst_ms']:.2f} > "
            f"threshold {thresholds['render_p95_max_ms']:.2f}"
        )
    if metrics["drawable_miss_total"] > thresholds["drawable_miss_max"]:
        failures.append(
            f"drawable_miss_total {metrics['drawable_miss_total']} > "
            f"threshold {thresholds['drawable_miss_max']:.0f}"
        )
    if (
        metrics["poll_p95_worst_ms"] is not None
        and metrics["poll_p95_worst_ms"] > thresholds["poll_p95_max_ms"]
    ):
        failures.append(
            f"poll_p95_worst {metrics['poll_p95_worst_ms']:.2f} > "
            f"threshold {thresholds['poll_p95_max_ms']:.2f}"
        )
    if metrics["switcher_failed_total"] > 0:
        failures.append(f"switcher_failed_total {metrics['switcher_failed_total']} > threshold 0")
    if thresholds["switcher_open_p95_max_ms"] is not None:
        if metrics["switcher_open_p95_ms"] is None:
            failures.append("no switcher open metrics were found for open p95 threshold")
        elif metrics["switcher_open_p95_ms"] > thresholds["switcher_open_p95_max_ms"]:
            failures.append(
                f"switcher_open_p95 {metrics['switcher_open_p95_ms']:.2f} > "
                f"threshold {thresholds['switcher_open_p95_max_ms']:.2f}"
            )
    if thresholds["switcher_cycle_step_p95_max_ms"] is not None:
        if metrics["switcher_cycle_step_p95_ms"] is None:
            failures.append("no switcher cycle metrics were found for cycle step p95 threshold")
        elif metrics["switcher_cycle_step_p95_ms"] > thresholds["switcher_cycle_step_p95_max_ms"]:
            failures.append(
                f"switcher_cycle_step_p95 {metrics['switcher_cycle_step_p95_ms']:.2f} > "
                f"threshold {thresholds['switcher_cycle_step_p95_max_ms']:.2f}"
            )
    if thresholds["switcher_animation_frame_p95_max_ms"] is not None:
        if metrics["switcher_animation_frame_p95_ms"] is None:
            failures.append("no switcher animation metrics were found for frame p95 threshold")
        elif metrics["switcher_animation_frame_p95_ms"] > thresholds["switcher_animation_frame_p95_max_ms"]:
            failures.append(
                f"switcher_animation_frame_p95 {metrics['switcher_animation_frame_p95_ms']:.2f} > "
                f"threshold {thresholds['switcher_animation_frame_p95_max_ms']:.2f}"
            )
    if thresholds["thumbnail_capture_p95_max_ms"] is not None:
        if metrics["thumbnail_capture_p95_ms"] is None:
            failures.append("no thumbnail metrics were found for capture p95 threshold")
        elif metrics["thumbnail_capture_p95_ms"] > thresholds["thumbnail_capture_p95_max_ms"]:
            failures.append(
                f"thumbnail_capture_p95 {metrics['thumbnail_capture_p95_ms']:.2f} > "
                f"threshold {thresholds['thumbnail_capture_p95_max_ms']:.2f}"
            )

summary = {
    "schema_version": 2,
    "source_log": log_path.name,
    "thresholds_enforced": enforce_thresholds,
    "thresholds": thresholds,
    "metrics": metrics,
    "failures": failures,
    "passed": not failures,
}


def fmt(value, places=2):
    if value is None:
        return "n/a"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{places}f}"


print("LiquidBar performance summary")
print(f"  frame_lines: {metrics['frame_lines']}")
print(f"  poll_lines: {metrics['poll_lines']}")
if metrics["fps_min"] is not None and metrics["fps_max"] is not None:
    print(f"  fps_min_max: {metrics['fps_min']:.1f} / {metrics['fps_max']:.1f}")
else:
    print("  fps_min_max: n/a")
print(f"  callback_p95_worst_ms: {fmt(metrics['callback_p95_worst_ms'])}")
print(f"  callback_p95_median_ms: {fmt(metrics['callback_p95_median_ms'])}")
print(f"  render_p95_worst_ms: {fmt(metrics['render_p95_worst_ms'])}")
print(f"  render_p95_median_ms: {fmt(metrics['render_p95_median_ms'])}")
print(f"  gpu_p95_worst_ms: {fmt(metrics['gpu_p95_worst_ms'])}")
print(f"  gpu_p95_median_ms: {fmt(metrics['gpu_p95_median_ms'])}")
print(f"  gpu_wall_p95_worst_ms: {fmt(metrics['gpu_wall_p95_worst_ms'])}")
print(f"  gpu_wall_p95_median_ms: {fmt(metrics['gpu_wall_p95_median_ms'])}")
print(f"  drawable_miss_total: {metrics['drawable_miss_total']}")
print(f"  poll_p95_worst_ms: {fmt(metrics['poll_p95_worst_ms'])}")
print(f"  poll_p95_median_ms: {fmt(metrics['poll_p95_median_ms'])}")
print(f"  poll_exec_skip_total: {metrics['poll_exec_total']} / {metrics['poll_skip_total']}")
print(f"  switcher_lines: {metrics['switcher_lines']}")
print(f"  switcher_failed_total: {metrics['switcher_failed_total']}")
print(f"  switcher_open_count: {metrics['switcher_open_count']}")
print(f"  switcher_open_cold_ms: {fmt(metrics['switcher_open_cold_ms'])}")
print(f"  switcher_open_median_ms: {fmt(metrics['switcher_open_median_ms'])}")
print(f"  switcher_open_p95_ms: {fmt(metrics['switcher_open_p95_ms'])}")
print(f"  switcher_open_warm_median_ms: {fmt(metrics['switcher_open_warm_median_ms'])}")
print(f"  switcher_open_warm_p95_ms: {fmt(metrics['switcher_open_warm_p95_ms'])}")
print(f"  switcher_cycle_step_median_ms: {fmt(metrics['switcher_cycle_step_median_ms'])}")
print(f"  switcher_cycle_step_p95_ms: {fmt(metrics['switcher_cycle_step_p95_ms'])}")
print(f"  switcher_animation_lines: {metrics['switcher_animation_lines']}")
print(f"  switcher_animation_failed_total: {metrics['switcher_animation_failed_total']}")
print(f"  switcher_animation_duration_p95_ms: {fmt(metrics['switcher_animation_duration_p95_ms'])}")
print(f"  switcher_animation_frame_p95_ms: {fmt(metrics['switcher_animation_frame_p95_ms'])}")
print(f"  switcher_animation_frame_max_ms: {fmt(metrics['switcher_animation_frame_max_ms'])}")
print(f"  switcher_animation_retargets_total: {metrics['switcher_animation_retargets_total']}")
print(f"  segment_lines: {metrics['segment_lines']}")
print(f"  stall_lines: {metrics['stall_lines']}")
print(f"  diag_lines: {metrics['diag_lines']}")
print(f"  thumbnail_lines: {metrics['thumbnail_lines']}")
print(f"  thumbnail_failed_total: {metrics['thumbnail_failed_total']}")
print(f"  thumbnail_queue_p95_ms: {fmt(metrics['thumbnail_queue_p95_ms'])}")
print(f"  thumbnail_capture_p95_ms: {fmt(metrics['thumbnail_capture_p95_ms'])}")
print(f"  thumbnail_total_p95_ms: {fmt(metrics['thumbnail_total_p95_ms'])}")

if failures:
    for failure in failures:
        print(f"FAIL: {failure}")
else:
    if enforce_thresholds:
        print("PASS: all configured thresholds satisfied")
    else:
        print("SUMMARY: thresholds were not enforced")

if json_out:
    out_path = Path(json_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

if markdown_out:
    out_path = Path(markdown_out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# LiquidBar Performance Summary",
        "",
        f"- Source log: `{log_path.name}`",
        f"- Thresholds enforced: `{str(enforce_thresholds).lower()}`",
        f"- Result: `{'PASS' if not failures else 'FAIL'}`",
        "",
        "| Metric | Value |",
        "| --- | ---: |",
        f"| Frame lines | {metrics['frame_lines']} |",
        f"| Poll lines | {metrics['poll_lines']} |",
        f"| FPS min | {fmt(metrics['fps_min'], 1)} |",
        f"| FPS max | {fmt(metrics['fps_max'], 1)} |",
        f"| Callback p95 worst ms | {fmt(metrics['callback_p95_worst_ms'])} |",
        f"| Callback p95 median ms | {fmt(metrics['callback_p95_median_ms'])} |",
        f"| Render p95 worst ms | {fmt(metrics['render_p95_worst_ms'])} |",
        f"| Render p95 median ms | {fmt(metrics['render_p95_median_ms'])} |",
        f"| GPU p95 worst ms | {fmt(metrics['gpu_p95_worst_ms'])} |",
        f"| GPU p95 median ms | {fmt(metrics['gpu_p95_median_ms'])} |",
        f"| GPU wall p95 worst ms | {fmt(metrics['gpu_wall_p95_worst_ms'])} |",
        f"| GPU wall p95 median ms | {fmt(metrics['gpu_wall_p95_median_ms'])} |",
        f"| Drawable misses | {metrics['drawable_miss_total']} |",
        f"| Poll p95 worst ms | {fmt(metrics['poll_p95_worst_ms'])} |",
        f"| Poll p95 median ms | {fmt(metrics['poll_p95_median_ms'])} |",
        f"| Poll exec total | {metrics['poll_exec_total']} |",
        f"| Poll skip total | {metrics['poll_skip_total']} |",
        f"| Switcher lines | {metrics['switcher_lines']} |",
        f"| Switcher failed actions | {metrics['switcher_failed_total']} |",
        f"| Switcher max entries | {metrics['switcher_entries_max']} |",
        f"| Switcher open count | {metrics['switcher_open_count']} |",
        f"| Switcher open cold ms | {fmt(metrics['switcher_open_cold_ms'])} |",
        f"| Switcher open median ms | {fmt(metrics['switcher_open_median_ms'])} |",
        f"| Switcher open p95 ms | {fmt(metrics['switcher_open_p95_ms'])} |",
        f"| Switcher open worst ms | {fmt(metrics['switcher_open_worst_ms'])} |",
        f"| Switcher open warm median ms | {fmt(metrics['switcher_open_warm_median_ms'])} |",
        f"| Switcher open warm p95 ms | {fmt(metrics['switcher_open_warm_p95_ms'])} |",
        f"| Switcher open warm worst ms | {fmt(metrics['switcher_open_warm_worst_ms'])} |",
        f"| Switcher cycle median ms | {fmt(metrics['switcher_cycle_median_ms'])} |",
        f"| Switcher cycle p95 ms | {fmt(metrics['switcher_cycle_p95_ms'])} |",
        f"| Switcher cycle worst ms | {fmt(metrics['switcher_cycle_worst_ms'])} |",
        f"| Switcher cycle step median ms | {fmt(metrics['switcher_cycle_step_median_ms'])} |",
        f"| Switcher cycle step p95 ms | {fmt(metrics['switcher_cycle_step_p95_ms'])} |",
        f"| Switcher cycle step worst ms | {fmt(metrics['switcher_cycle_step_worst_ms'])} |",
        f"| Switcher animation lines | {metrics['switcher_animation_lines']} |",
        f"| Switcher animation failed events | {metrics['switcher_animation_failed_total']} |",
        f"| Switcher animation duration p50 ms | {fmt(metrics['switcher_animation_duration_p50_ms'])} |",
        f"| Switcher animation duration p95 ms | {fmt(metrics['switcher_animation_duration_p95_ms'])} |",
        f"| Switcher animation frame count p50 | {fmt(metrics['switcher_animation_frame_count_p50'])} |",
        f"| Switcher animation frame count p95 | {fmt(metrics['switcher_animation_frame_count_p95'])} |",
        f"| Switcher animation frame p50 ms | {fmt(metrics['switcher_animation_frame_p50_ms'])} |",
        f"| Switcher animation frame p95 ms | {fmt(metrics['switcher_animation_frame_p95_ms'])} |",
        f"| Switcher animation frame max ms | {fmt(metrics['switcher_animation_frame_max_ms'])} |",
        f"| Switcher animation retargets total | {metrics['switcher_animation_retargets_total']} |",
        f"| Switcher animation distance total | {fmt(metrics['switcher_animation_distance_total'])} |",
        f"| Segment lines | {metrics['segment_lines']} |",
        f"| Stall lines | {metrics['stall_lines']} |",
        f"| Diagnostic lines | {metrics['diag_lines']} |",
        f"| Thumbnail lines | {metrics['thumbnail_lines']} |",
        f"| Thumbnail failed events | {metrics['thumbnail_failed_total']} |",
        f"| Thumbnail queue p95 ms | {fmt(metrics['thumbnail_queue_p95_ms'])} |",
        f"| Thumbnail capture p95 ms | {fmt(metrics['thumbnail_capture_p95_ms'])} |",
        f"| Thumbnail total p95 ms | {fmt(metrics['thumbnail_total_p95_ms'])} |",
        f"| Thumbnail bytes total | {metrics['thumbnail_bytes_total']} |",
        "",
    ]
    if metrics["poll_reasons"]:
        lines.extend(["## Poll Reasons", "", "| Reason | Count |", "| --- | ---: |"])
        for key, value in metrics["poll_reasons"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
    if metrics["switcher_action_counts"]:
        lines.extend(["## Switcher Actions", "", "| Action | Count |", "| --- | ---: |"])
        for key, value in metrics["switcher_action_counts"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
    if metrics["switcher_animation_counts_by_kind"]:
        lines.extend(["## Switcher Animations", "", "| Kind | Count |", "| --- | ---: |"])
        for key, value in metrics["switcher_animation_counts_by_kind"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
    if metrics["segment_counts"]:
        lines.extend([
            "## Segments",
            "",
            "| Segment | Count | P95 worst ms | Max worst ms |",
            "| --- | ---: | ---: | ---: |",
        ])
        for key, value in metrics["segment_counts"].items():
            p95 = metrics["segment_p95_worst_by_name_ms"].get(key)
            max_value = metrics["segment_max_worst_by_name_ms"].get(key)
            lines.append(f"| `{key}` | {value} | {fmt(p95)} | {fmt(max_value)} |")
        lines.append("")
    if metrics["stall_counts"]:
        lines.extend([
            "## Stalls",
            "",
            "| Name | Count | Max ms |",
            "| --- | ---: | ---: |",
        ])
        for key, value in metrics["stall_counts"].items():
            lines.append(f"| `{key}` | {value} | {fmt(metrics['stall_max_by_name_ms'].get(key))} |")
        lines.append("")
    if metrics["diag_counts"]:
        lines.extend(["## Diagnostics", "", "| Name | Count |", "| --- | ---: |"])
        for key, value in metrics["diag_counts"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
    if metrics["thumbnail_counts_by_outcome"]:
        lines.extend(["## Thumbnails", "", "| Outcome | Count |", "| --- | ---: |"])
        for key, value in metrics["thumbnail_counts_by_outcome"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
        lines.extend(["| Producer | Count |", "| --- | ---: |"])
        for key, value in metrics["thumbnail_counts_by_producer"].items():
            lines.append(f"| `{key}` | {value} |")
        lines.append("")
        lines.extend(["| Producer tier | Capture p95 ms | Total p95 ms |", "| --- | ---: | ---: |"])
        producer_tiers = sorted(set(metrics["thumbnail_capture_p95_by_producer_tier_ms"]) | set(metrics["thumbnail_total_p95_by_producer_tier_ms"]))
        for key in producer_tiers:
            capture_p95 = metrics["thumbnail_capture_p95_by_producer_tier_ms"].get(key)
            total_p95 = metrics["thumbnail_total_p95_by_producer_tier_ms"].get(key)
            lines.append(f"| `{key}` | {fmt(capture_p95)} | {fmt(total_p95)} |")
        lines.append("")
    if failures:
        lines.extend(["## Failures", ""])
        for failure in failures:
            lines.append(f"- {failure}")
        lines.append("")
    out_path.write_text("\n".join(lines))

if failures:
    sys.exit(1)
PY
