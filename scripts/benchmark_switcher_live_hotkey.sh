#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_ID="${LIQUIDBAR_SWITCHER_RUN_ID:-live-hotkey-$(date +%Y%m%d-%H%M%S)}"
APP_PATH="${LIQUIDBAR_SWITCHER_APP_PATH:-${HOME}/Applications/LiquidBar Test.app}"
APP_EXEC="${APP_PATH}/Contents/MacOS/LiquidBar"
CONFIG_DIR="${LIQUIDBAR_SWITCHER_CONFIG_DIR:-${ROOT_DIR}/build/artifacts/perf-switcher-config/${RUN_ID}}"
CYCLES="${LIQUIDBAR_SWITCHER_LIVE_CYCLES:-1}"
STEPS="${LIQUIDBAR_SWITCHER_LIVE_STEPS:-8}"
DIRECTION="${LIQUIDBAR_SWITCHER_BENCH_DIRECTION:-1}"
SWITCHER_LAYOUT="${LIQUIDBAR_SWITCHER_LAYOUT:-hero_carousel}"
APP_SETTLE_SECONDS="${LIQUIDBAR_SWITCHER_APP_SETTLE_SECONDS:-5}"
WARMUP_MS="${LIQUIDBAR_SWITCHER_LIVE_WARMUP_MS:-1200}"
OPEN_HOLD_MS="${LIQUIDBAR_SWITCHER_LIVE_OPEN_HOLD_MS:-180}"
STEP_PAUSE_MS="${LIQUIDBAR_SWITCHER_LIVE_STEP_PAUSE_MS:-80}"
RELEASE_PAUSE_MS="${LIQUIDBAR_SWITCHER_LIVE_RELEASE_PAUSE_MS:-280}"
COOLDOWN_MS="${LIQUIDBAR_SWITCHER_LIVE_COOLDOWN_MS:-1500}"
SCREENSHOT_DIR="${LIQUIDBAR_SWITCHER_LIVE_SCREENSHOT_DIR:-}"

if [[ ! -x "$APP_EXEC" ]]; then
  echo "error: LiquidBar test app not found at: $APP_EXEC" >&2
  echo "run ./scripts/build_test_app.sh first, or set LIQUIDBAR_SWITCHER_APP_PATH" >&2
  exit 2
fi

if [[ ! "$CYCLES" =~ ^[0-9]+$ || "$CYCLES" -lt 1 ]]; then
  echo "error: LIQUIDBAR_SWITCHER_LIVE_CYCLES must be a positive integer" >&2
  exit 2
fi
if [[ ! "$STEPS" =~ ^[0-9]+$ || "$STEPS" -lt 0 ]]; then
  echo "error: LIQUIDBAR_SWITCHER_LIVE_STEPS must be a non-negative integer" >&2
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
if [[ -n "$SCREENSHOT_DIR" ]]; then
  mkdir -p "$SCREENSHOT_DIR"
fi

python3 - "$CONFIG_DIR/config.json" "$SWITCHER_LAYOUT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
layout = sys.argv[2]
data = {
    "adjust_windows_for_taskbar": False,
    "animation_profile": "balanced_spring",
    "app_group_count_badge_in_icons_only": True,
    "app_group_count_badge_style": "minimal",
    "app_group_stack_geometry": "subtle",
    "app_group_stack_hover_spread_enabled": False,
    "app_group_stack_style": "filled",
    "bar_style": "flush",
    "blacklisted_apps": [],
    "center_items": False,
    "custom_items": [],
    "disabled_plugin_ids": [],
    "focus_indicator_style": "tile",
    "font_size": 11,
    "glass_style": "public_regular",
    "group_by_app": False,
    "hidden_window_mode": "in_place",
    "hide_dock": False,
    "hover_delay_ms": 0,
    "hover_intensity": "subtle",
    "hover_intent_guard_enabled": True,
    "icon_size": 32,
    "icons_only": True,
    "item_sizing": "uniform",
    "launcher_action": "spotlight",
    "launcher_custom_url": None,
    "launcher_enabled": False,
    "max_item_width": 150,
    "max_title_width": 120,
    "minimized_window_mode": "in_place",
    "multi_monitor_mode": "all_displays",
    "performance_gpu_timing_enabled": False,
    "performance_log_interval_ms": 250,
    "performance_logging_enabled": True,
    "pinned_apps": [],
    "pinned_apps_scope": "global",
    "plugins_enabled": False,
    "preview_hover_delay_ms": 0,
    "preview_mode": "static",
    "previews_enabled": True,
    "provider_circuit_breaker_threshold": 3,
    "provider_runtime_enabled": False,
    "provider_timeout_ms": 900,
    "scroll_wheel_mode": "cycle_windows",
    "second_click_action": "hide",
    "show_hidden_apps": True,
    "show_menu_bar_icon": False,
    "show_minimized_windows": True,
    "sidebar_expand_trigger": "click",
    "sidebar_mode_enabled": False,
    "sidebar_state_default": "expanded",
    "switcher_enabled": True,
    "switcher_hotkey": "command+tab",
    "switcher_layout_style": layout,
    "tab_group_collapse_on_outside_click": True,
    "tab_group_hover_expand_delay_ms": 1000,
    "tabbed_taskbar_enabled": False,
    "taskbar_height": 32,
    "taskbar_position": "bottom",
    "theme": "system",
    "tile_popup_singleton": True,
    "tile_zone_enabled": False,
    "visual_depth": "balanced",
    "window_display_mode": "all_windows",
    "window_tab_groups_enabled": False,
}
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

DRIVER_MS=$((WARMUP_MS + (CYCLES * (OPEN_HOLD_MS + (STEPS * STEP_PAUSE_MS) + RELEASE_PAUSE_MS)) + COOLDOWN_MS))
DURATION_SECONDS="${1:-$(((DRIVER_MS + 999) / 1000 + APP_SETTLE_SECONDS + 8))}"

APP_PID=""
BENCH_PID=""
cleanup() {
  if [[ -n "$BENCH_PID" ]]; then
    wait "$BENCH_PID" 2>/dev/null || true
  fi
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    pkill -f "Applications/LiquidBar Test.app/Contents/MacOS/LiquidBar" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Launching LiquidBar live hotkey benchmark app..."
echo "Run id: $RUN_ID"
echo "Config directory: $CONFIG_DIR"
if [[ -n "$SCREENSHOT_DIR" ]]; then
  echo "Screenshot directory: $SCREENSHOT_DIR"
fi

LIQUIDBAR_CONFIG_DIR="$CONFIG_DIR" "$APP_EXEC" &
APP_PID=$!

sleep "$APP_SETTLE_SECONDS"
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "error: LiquidBar test app exited before benchmark could start" >&2
  exit 1
fi

LIQUIDBAR_PERF_RUN_ID="$RUN_ID" \
LIQUIDBAR_PERF_LABEL="${LIQUIDBAR_PERF_LABEL:-switcher-live-hotkey}" \
LIQUIDBAR_PERF_PHASE="${LIQUIDBAR_PERF_PHASE:-live}" \
LIQUIDBAR_PERF_PID="$APP_PID" \
LIQUIDBAR_PERF_SWITCHER_OPEN_P95_MAX="${LIQUIDBAR_PERF_SWITCHER_OPEN_P95_MAX:-60}" \
LIQUIDBAR_PERF_SWITCHER_CYCLE_STEP_P95_MAX="${LIQUIDBAR_PERF_SWITCHER_CYCLE_STEP_P95_MAX:-4}" \
"${ROOT_DIR}/scripts/benchmark_performance.sh" "$DURATION_SECONDS" &
BENCH_PID=$!

swift - "$CYCLES" "$STEPS" "$DIRECTION" "$WARMUP_MS" "$OPEN_HOLD_MS" "$STEP_PAUSE_MS" "$RELEASE_PAUSE_MS" "$COOLDOWN_MS" "$SCREENSHOT_DIR" <<'SWIFT'
import ApplicationServices
import Carbon
import Foundation

let args = CommandLine.arguments
guard args.count == 10,
      let cycles = Int(args[1]),
      let steps = Int(args[2]),
      let warmupMs = Int(args[4]),
      let openHoldMs = Int(args[5]),
      let stepPauseMs = Int(args[6]),
      let releasePauseMs = Int(args[7]),
      let cooldownMs = Int(args[8]) else {
    fputs("error: invalid live hotkey driver arguments\n", stderr)
    exit(2)
}

let rawDirection = args[3].lowercased()
let reverse = ["-1", "reverse", "backward", "backwards"].contains(rawDirection)
let screenshotDir = args[9].isEmpty ? nil : args[9]
let source = CGEventSource(stateID: .hidSystemState)

func sleepMs(_ milliseconds: Int) {
    Thread.sleep(forTimeInterval: max(0, Double(milliseconds)) / 1000.0)
}

func postKey(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
        fputs("error: failed to create keyboard event\n", stderr)
        exit(1)
    }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func pressTab(flags: CGEventFlags) {
    postKey(CGKeyCode(kVK_Tab), keyDown: true, flags: flags)
    sleepMs(14)
    postKey(CGKeyCode(kVK_Tab), keyDown: false, flags: flags)
}

func setCommand(_ down: Bool) {
    postKey(CGKeyCode(kVK_Command), keyDown: down, flags: down ? [.maskCommand] : [])
}

func capture(_ filename: String) {
    guard let screenshotDir else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "\(screenshotDir)/\(filename)"]
    try? process.run()
    process.waitUntilExit()
}

let tabFlags: CGEventFlags = reverse ? [.maskCommand, .maskShift] : [.maskCommand]

sleepMs(warmupMs)
for cycle in 0..<cycles {
    setCommand(true)
    sleepMs(24)
    pressTab(flags: tabFlags)
    sleepMs(openHoldMs)
    if cycle == 0 {
        capture("live-hotkey-open.png")
    }

    if steps > 0 {
        for step in 0..<steps {
            pressTab(flags: tabFlags)
            sleepMs(stepPauseMs)
            if cycle == 0 && step == min(2, steps - 1) {
                capture("live-hotkey-after-cycle.png")
            }
        }
    }

    setCommand(false)
    sleepMs(releasePauseMs)
}
sleepMs(cooldownMs)
SWIFT

wait "$BENCH_PID"
BENCH_PID=""

SUMMARY_JSON="${ROOT_DIR}/build/artifacts/perf/${RUN_ID}/summary.json"
EXPECTED_SWITCHER_LINES=$((CYCLES * (STEPS + 2)))
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
  echo "error: captured ${ACTUAL_SWITCHER_LINES} live switcher actions, expected at least ${EXPECTED_SWITCHER_LINES}" >&2
  echo "verify LiquidBar Test has Input Monitoring permission and Cmd+Tab is not passing through to the system switcher" >&2
  exit 1
fi
