#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <perf-stream.log>" >&2
  exit 2
fi

LOG_FILE="$1"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "error: log file not found: $LOG_FILE" >&2
  exit 2
fi

FPS_MIN="${LIQUIDBAR_PERF_FPS_MIN:-58}"
CALLBACK_P95_MAX="${LIQUIDBAR_PERF_CALLBACK_P95_MAX:-12}"
RENDER_P95_MAX="${LIQUIDBAR_PERF_RENDER_P95_MAX:-8}"
DRAWABLE_MISS_MAX="${LIQUIDBAR_PERF_DRAWABLE_MISS_MAX:-3}"
POLL_P95_MAX="${LIQUIDBAR_PERF_POLL_P95_MAX:-40}"

python3 - "$LOG_FILE" "$FPS_MIN" "$CALLBACK_P95_MAX" "$RENDER_P95_MAX" "$DRAWABLE_MISS_MAX" "$POLL_P95_MAX" <<'PY'
import re
import sys
from pathlib import Path

if len(sys.argv) != 7:
    print("internal error: unexpected argv", file=sys.stderr)
    sys.exit(2)

log_path = Path(sys.argv[1])
fps_min_threshold = float(sys.argv[2])
cb_p95_max_threshold = float(sys.argv[3])
render_p95_max_threshold = float(sys.argv[4])
drawable_miss_max_threshold = float(sys.argv[5])
poll_p95_max_threshold = float(sys.argv[6])

frame_re = re.compile(
    r"frame d=(?P<display>\d+).*?"
    r"fps=(?P<fps>[0-9.]+).*?"
    r"callback_ms\(p50/p95\)=(?P<cb50>[^/]+)/(?P<cb95>[^ ]+).*?"
    r"render_ms\(p50/p95\)=(?P<r50>[^/]+)/(?P<r95>[^ ]+).*?"
    r"drawable_miss=(?P<miss>\d+)"
)
poll_re = re.compile(
    r"poll interval_ms=[0-9.]+ .*?"
    r"duration_ms\(p50/p95\)=(?P<p50>[^/]+)/(?P<p95>[^ ]+)"
)

def to_float(value: str):
    value = value.strip()
    if value in ("n/a", ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None

frame_lines = 0
poll_lines = 0
fps_values = []
cb95_values = []
render95_values = []
drawable_miss_total = 0
poll95_values = []

for raw in log_path.read_text(errors="replace").splitlines():
    frame_m = frame_re.search(raw)
    if frame_m:
        frame_lines += 1
        fps = to_float(frame_m.group("fps"))
        cb95 = to_float(frame_m.group("cb95"))
        r95 = to_float(frame_m.group("r95"))
        miss = to_float(frame_m.group("miss"))

        if fps is not None:
            fps_values.append(fps)
        if cb95 is not None:
            cb95_values.append(cb95)
        if r95 is not None:
            render95_values.append(r95)
        if miss is not None:
            drawable_miss_total += int(miss)
        continue

    poll_m = poll_re.search(raw)
    if poll_m:
        poll_lines += 1
        p95 = to_float(poll_m.group("p95"))
        if p95 is not None:
            poll95_values.append(p95)

fps_min_seen = min(fps_values) if fps_values else None
fps_max_seen = max(fps_values) if fps_values else None
cb95_worst = max(cb95_values) if cb95_values else None
render95_worst = max(render95_values) if render95_values else None
poll95_worst = max(poll95_values) if poll95_values else None

print("LiquidBar performance summary")
print(f"  frame_lines: {frame_lines}")
print(f"  poll_lines: {poll_lines}")
if fps_min_seen is not None and fps_max_seen is not None:
    print(f"  fps_min_max: {fps_min_seen:.1f} / {fps_max_seen:.1f}")
else:
    print("  fps_min_max: n/a")
if cb95_worst is not None:
    print(f"  callback_p95_worst_ms: {cb95_worst:.2f}")
else:
    print("  callback_p95_worst_ms: n/a")
if render95_worst is not None:
    print(f"  render_p95_worst_ms: {render95_worst:.2f}")
else:
    print("  render_p95_worst_ms: n/a")
print(f"  drawable_miss_total: {drawable_miss_total}")
if poll95_worst is not None:
    print(f"  poll_p95_worst_ms: {poll95_worst:.2f}")
else:
    print("  poll_p95_worst_ms: n/a")

fail = False
if frame_lines == 0:
    print("FAIL: no frame metrics were found in perf log")
    fail = True
if fps_min_seen is not None and fps_min_seen < fps_min_threshold:
    print(f"FAIL: fps_min {fps_min_seen:.1f} < threshold {fps_min_threshold:.1f}")
    fail = True
if cb95_worst is not None and cb95_worst > cb_p95_max_threshold:
    print(f"FAIL: callback_p95_worst {cb95_worst:.2f} > threshold {cb_p95_max_threshold:.2f}")
    fail = True
if render95_worst is not None and render95_worst > render_p95_max_threshold:
    print(f"FAIL: render_p95_worst {render95_worst:.2f} > threshold {render_p95_max_threshold:.2f}")
    fail = True
if drawable_miss_total > drawable_miss_max_threshold:
    print(f"FAIL: drawable_miss_total {drawable_miss_total} > threshold {drawable_miss_max_threshold:.0f}")
    fail = True
if poll95_worst is not None and poll95_worst > poll_p95_max_threshold:
    print(f"FAIL: poll_p95_worst {poll95_worst:.2f} > threshold {poll_p95_max_threshold:.2f}")
    fail = True

if fail:
    sys.exit(1)

print("PASS: all configured thresholds satisfied")
PY
