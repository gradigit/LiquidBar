#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_ID="${LIQUIDBAR_SWITCHER_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
APP_PATH="${LIQUIDBAR_SWITCHER_APP_PATH:-${HOME}/Applications/LiquidBar Test.app}"
APP_EXEC="${APP_PATH}/Contents/MacOS/LiquidBar"
CONFIG_DIR="${LIQUIDBAR_SWITCHER_CONFIG_DIR:-${ROOT_DIR}/build/artifacts/perf-switcher-config/${RUN_ID}}"
CYCLES="${LIQUIDBAR_SWITCHER_BENCH_CYCLES:-10}"
STEPS="${LIQUIDBAR_SWITCHER_BENCH_STEPS:-30}"
DIRECTION="${LIQUIDBAR_SWITCHER_BENCH_DIRECTION:-1}"
SWITCHER_LAYOUT="${LIQUIDBAR_SWITCHER_LAYOUT:-hero_carousel}"
WARMUP_MS="${LIQUIDBAR_SWITCHER_BENCH_WARMUP_MS:-1200}"
OPEN_PAUSE_MS="${LIQUIDBAR_SWITCHER_BENCH_OPEN_PAUSE_MS:-180}"
CYCLE_PAUSE_MS="${LIQUIDBAR_SWITCHER_BENCH_CYCLE_PAUSE_MS:-120}"
CLOSE_PAUSE_MS="${LIQUIDBAR_SWITCHER_BENCH_CLOSE_PAUSE_MS:-90}"
COOLDOWN_MS="${LIQUIDBAR_SWITCHER_BENCH_COOLDOWN_MS:-1500}"
APP_SETTLE_SECONDS="${LIQUIDBAR_SWITCHER_APP_SETTLE_SECONDS:-5}"
# The inline Swift notification driver can cold-start slowly after local rebuilds.
# Keep the default perf window wide enough that the switcher workload lands in
# the captured interval instead of producing under-sampled runs.
DRIVER_STARTUP_SECONDS="${LIQUIDBAR_SWITCHER_DRIVER_STARTUP_SECONDS:-30}"

if [[ ! -x "$APP_EXEC" ]]; then
  echo "error: LiquidBar test app not found at: $APP_EXEC" >&2
  echo "run ./scripts/build_test_app.sh first, or set LIQUIDBAR_SWITCHER_APP_PATH" >&2
  exit 2
fi

if [[ ! "$CYCLES" =~ ^[0-9]+$ || "$CYCLES" -lt 1 ]]; then
  echo "error: LIQUIDBAR_SWITCHER_BENCH_CYCLES must be a positive integer" >&2
  exit 2
fi
if [[ ! "$STEPS" =~ ^[0-9]+$ || "$STEPS" -lt 1 ]]; then
  echo "error: LIQUIDBAR_SWITCHER_BENCH_STEPS must be a positive integer" >&2
  exit 2
fi
case "$DIRECTION" in
  1|+1|forward|forwards|-1|reverse|backward|backwards) ;;
  *)
    echo "error: LIQUIDBAR_SWITCHER_BENCH_DIRECTION must be forward/1 or reverse/-1" >&2
    exit 2
    ;;
esac
case "$SWITCHER_LAYOUT" in
  compact_shelf|hero_carousel) ;;
  *)
    echo "error: LIQUIDBAR_SWITCHER_LAYOUT must be compact_shelf or hero_carousel" >&2
    exit 2
    ;;
esac

mkdir -p "$CONFIG_DIR"
cat >"${CONFIG_DIR}/config.json" <<'JSON'
{
  "adjust_windows_for_taskbar" : false,
  "animation_profile" : "balanced_spring",
  "app_group_count_badge_in_icons_only" : true,
  "app_group_count_badge_style" : "minimal",
  "app_group_stack_geometry" : "subtle",
  "app_group_stack_hover_spread_enabled" : false,
  "app_group_stack_style" : "filled",
  "bar_style" : "flush",
  "blacklisted_apps" : [

  ],
  "center_items" : false,
  "custom_items" : [

  ],
  "disabled_plugin_ids" : [

  ],
  "focus_indicator_style" : "tile",
  "font_size" : 11,
  "glass_style" : "public_regular",
  "group_by_app" : false,
  "hidden_window_mode" : "in_place",
  "hide_dock" : false,
  "hover_delay_ms" : 0,
  "hover_intensity" : "subtle",
  "hover_intent_guard_enabled" : true,
  "icon_size" : 32,
  "icons_only" : true,
  "item_sizing" : "uniform",
  "launcher_action" : "spotlight",
  "launcher_custom_url" : null,
  "launcher_enabled" : false,
  "max_item_width" : 150,
  "max_title_width" : 120,
  "minimized_window_mode" : "in_place",
  "multi_monitor_mode" : "all_displays",
  "performance_gpu_timing_enabled" : false,
  "performance_log_interval_ms" : 250,
  "performance_logging_enabled" : true,
  "pinned_apps" : [

  ],
  "pinned_apps_scope" : "global",
  "plugins_enabled" : false,
  "preview_hover_delay_ms" : 0,
  "preview_mode" : "static",
  "previews_enabled" : true,
  "provider_circuit_breaker_threshold" : 3,
  "provider_runtime_enabled" : false,
  "provider_timeout_ms" : 900,
  "scroll_wheel_mode" : "cycle_windows",
  "second_click_action" : "hide",
  "show_hidden_apps" : true,
  "show_menu_bar_icon" : false,
  "show_minimized_windows" : true,
  "sidebar_expand_trigger" : "click",
  "sidebar_mode_enabled" : false,
  "sidebar_state_default" : "expanded",
  "switcher_enabled" : true,
  "switcher_hotkey" : "command+tab",
  "switcher_layout_style" : "hero_carousel",
  "tab_group_collapse_on_outside_click" : true,
  "tab_group_hover_expand_delay_ms" : 1000,
  "tabbed_taskbar_enabled" : false,
  "taskbar_height" : 32,
  "taskbar_position" : "bottom",
  "theme" : "system",
  "tile_popup_singleton" : true,
  "tile_zone_enabled" : false,
  "visual_depth" : "balanced",
  "window_display_mode" : "all_windows",
  "window_tab_groups_enabled" : false
}
JSON

python3 - "$CONFIG_DIR/config.json" "$SWITCHER_LAYOUT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
layout = sys.argv[2]
data = json.loads(path.read_text())
data["switcher_layout_style"] = layout
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

DRIVER_MS=$((WARMUP_MS + (CYCLES * (OPEN_PAUSE_MS + CYCLE_PAUSE_MS + CYCLE_PAUSE_MS + CLOSE_PAUSE_MS)) + COOLDOWN_MS))
DEFAULT_DURATION_SECONDS=$(((DRIVER_MS + 999) / 1000 + DRIVER_STARTUP_SECONDS + 3))
DURATION_SECONDS="${1:-$DEFAULT_DURATION_SECONDS}"

APP_PID=""
BENCH_PID=""
cleanup() {
  if [[ -n "$BENCH_PID" ]]; then
    wait "$BENCH_PID" 2>/dev/null || true
  fi
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Launching LiquidBar switcher benchmark app..."
echo "Run id: $RUN_ID"
echo "Config directory: $CONFIG_DIR"

LIQUIDBAR_CONFIG_DIR="$CONFIG_DIR" \
LIQUIDBAR_TEST_CONTROL=1 \
LIQUIDBAR_DISABLE_MOUSE_TRACKER=1 \
"$APP_EXEC" &
APP_PID=$!

sleep "$APP_SETTLE_SECONDS"
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "error: LiquidBar test app exited before benchmark could start" >&2
  exit 1
fi

LIQUIDBAR_PERF_RUN_ID="$RUN_ID" \
LIQUIDBAR_PERF_LABEL="${LIQUIDBAR_PERF_LABEL:-switcher}" \
LIQUIDBAR_PERF_PHASE="${LIQUIDBAR_PERF_PHASE:-baseline}" \
LIQUIDBAR_PERF_PID="$APP_PID" \
"${ROOT_DIR}/scripts/benchmark_performance.sh" "$DURATION_SECONDS" &
BENCH_PID=$!

swift - "$CYCLES" "$STEPS" "$DIRECTION" "$WARMUP_MS" "$OPEN_PAUSE_MS" "$CYCLE_PAUSE_MS" "$CLOSE_PAUSE_MS" "$COOLDOWN_MS" <<'SWIFT'
import Foundation

let args = CommandLine.arguments
guard args.count == 9,
      let cycles = Int(args[1]),
      let steps = Int(args[2]),
      let warmupMs = Int(args[4]),
      let openPauseMs = Int(args[5]),
      let cyclePauseMs = Int(args[6]),
      let closePauseMs = Int(args[7]),
      let cooldownMs = Int(args[8]) else {
    fputs("error: invalid switcher driver arguments\n", stderr)
    exit(2)
}

let rawDirection = args[3].lowercased()
let direction = ["-1", "reverse", "backward", "backwards"].contains(rawDirection) ? -1 : 1
let center = DistributedNotificationCenter.default()
let name = Notification.Name("com.liquidbar.testcontrol.switcher")

func sleepMs(_ milliseconds: Int) {
    Thread.sleep(forTimeInterval: max(0, Double(milliseconds)) / 1000.0)
}

func post(_ value: String) {
    center.postNotificationName(name, object: value, userInfo: nil, deliverImmediately: true)
}

sleepMs(warmupMs)
for _ in 0..<cycles {
    post("open,\(direction)")
    sleepMs(openPauseMs)
    post("cycle,\(steps),\(direction)")
    sleepMs(cyclePauseMs)
    post("cycle,\(steps),\(-direction)")
    sleepMs(cyclePauseMs)
    post("close")
    sleepMs(closePauseMs)
}
sleepMs(cooldownMs)
SWIFT

wait "$BENCH_PID"
BENCH_PID=""

SUMMARY_JSON="${ROOT_DIR}/build/artifacts/perf/${RUN_ID}/summary.json"
EXPECTED_SWITCHER_LINES=$((CYCLES * 4))
ACTUAL_SWITCHER_LINES="$(python3 - "$SUMMARY_JSON" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    print("0")
    raise SystemExit
summary = json.loads(path.read_text())
print(int(summary.get("metrics", {}).get("switcher_lines") or 0))
PY
)"
if [[ "$ACTUAL_SWITCHER_LINES" -lt "$EXPECTED_SWITCHER_LINES" ]]; then
  echo "error: captured ${ACTUAL_SWITCHER_LINES} switcher actions, expected at least ${EXPECTED_SWITCHER_LINES}" >&2
  echo "increase LIQUIDBAR_SWITCHER_DRIVER_STARTUP_SECONDS or the benchmark duration" >&2
  exit 1
fi
