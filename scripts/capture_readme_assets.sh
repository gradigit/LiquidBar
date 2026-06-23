#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${LIQUIDBAR_README_RUN_ID:-readme-$(date +%Y%m%d-%H%M%S)}"
ARTIFACT_DIR="${LIQUIDBAR_README_ARTIFACT_DIR:-${ROOT_DIR}/build/artifacts/readme-capture/${RUN_ID}}"
FRAMES_DIR="${ARTIFACT_DIR}/frames"
GIFS_DIR="${ARTIFACT_DIR}/review-gifs"
STILLS_DIR="${ARTIFACT_DIR}/review-stills"
CONFIG_DIR="${ARTIFACT_DIR}/config"
ASSETS_DIR="${ROOT_DIR}/Assets/Screenshots"
DERIVED="${ROOT_DIR}/build/DerivedData"
PROJ="${ROOT_DIR}/build/xcode/LiquidBar.xcodeproj"
APP_PATH="${LIQUIDBAR_README_APP_PATH:-${HOME}/Applications/LiquidBar Test.app}"
APP_EXEC="${APP_PATH}/Contents/MacOS/LiquidBar"
BACKDROP_APP="${ARTIFACT_DIR}/LiquidBarReadmeBackdrop.app"
BACKDROP_EXEC="${BACKDROP_APP}/Contents/MacOS/LiquidBarReadmeBackdrop"
STOP_EXISTING="${LIQUIDBAR_README_STOP_EXISTING:-0}"
GIF_WIDTH="${LIQUIDBAR_README_GIF_WIDTH:-1488}"
PNG_WIDTH="${LIQUIDBAR_README_PNG_WIDTH:-1488}"
PREVIEW_CROP_HEIGHT="${LIQUIDBAR_README_PREVIEW_CROP_HEIGHT:-430}"
CAPTURE_DISPLAY="${LIQUIDBAR_README_CAPTURE_DISPLAY:-1}"
CAPTURE_GIFS="${LIQUIDBAR_README_CAPTURE_GIFS:-0}"
UPDATE_TRACKED_ASSETS="${LIQUIDBAR_README_UPDATE_TRACKED_ASSETS:-0}"
SWITCHER_CAPTURE_MARGIN="${LIQUIDBAR_README_SWITCHER_CAPTURE_MARGIN:-80}"
MAGICK="${LIQUIDBAR_MAGICK:-$(command -v magick || true)}"

if [[ -z "$MAGICK" ]]; then
  echo "error: ImageMagick 'magick' not found. Install with: brew install imagemagick" >&2
  exit 2
fi

mkdir -p "$FRAMES_DIR" "$GIFS_DIR" "$STILLS_DIR" "$CONFIG_DIR" "$ASSETS_DIR"

"${ROOT_DIR}/scripts/generate_xcodeproj.sh"

xcodebuild build \
  -project "$PROJ" \
  -scheme LiquidBarE2E \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES >/dev/null

if [[ ! -x "$APP_EXEC" || "${LIQUIDBAR_README_REBUILD_TEST_APP:-1}" == "1" ]]; then
  "${ROOT_DIR}/scripts/build_test_app.sh"
fi

if [[ ! -x "$APP_EXEC" ]]; then
  echo "error: LiquidBar debug app not found at: $APP_EXEC" >&2
  echo "run ./scripts/build_test_app.sh or set LIQUIDBAR_README_APP_PATH" >&2
  exit 2
fi

FIXTURE_APP="$(find "$DERIVED/Build/Products" -path "*/Debug/LiquidBarFixture.app" -type d | head -n 1)"
if [[ -z "$FIXTURE_APP" || ! -x "$FIXTURE_APP/Contents/MacOS/LiquidBarFixture" ]]; then
  echo "error: LiquidBarFixture.app not found under $DERIVED" >&2
  exit 2
fi

CONTROL_SWIFT="${ARTIFACT_DIR}/readme_capture_control.swift"
cat > "$CONTROL_SWIFT" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments

func fail(_ message: String, code: Int32 = 2) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(code)
}

func boundsDict(_ dict: [CFString: Any]) -> CGRect? {
    guard let raw = dict[kCGWindowBounds as CFString] as? NSDictionary else { return nil }
    return CGRect(
        x: raw["X"] as? CGFloat ?? 0,
        y: raw["Y"] as? CGFloat ?? 0,
        width: raw["Width"] as? CGFloat ?? 0,
        height: raw["Height"] as? CGFloat ?? 0
    )
}

func visibleDisplayUnion() -> CGRect {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
        return NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
        return NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
    return displays.prefix(Int(count)).map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
}

switch args.dropFirst().first {
case "post":
    guard args.count >= 3 else { fail("post requires notification name") }
    let name = Notification.Name(args[2])
    let object = args.count >= 4 && !args[3].isEmpty ? args[3] : nil
    DistributedNotificationCenter.default().post(name: name, object: object)
    Thread.sleep(forTimeInterval: 0.05)

case "blacklist":
    let allowed = Set(args.dropFirst(2))
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
    var bundleIds = Set<String>()
    let ownPid = ProcessInfo.processInfo.processIdentifier
    for dict in list {
        let layer = dict[kCGWindowLayer as CFString] as? Int ?? 0
        guard layer == 0 else { continue }
        guard let pid = dict[kCGWindowOwnerPID as CFString] as? pid_t, pid != ownPid else { continue }
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier,
              !bundleId.isEmpty,
              !allowed.contains(bundleId) else {
            continue
        }
        bundleIds.insert(bundleId)
    }
    let data = try JSONSerialization.data(withJSONObject: Array(bundleIds).sorted(), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))

case "bounds":
    guard args.count >= 5, let pid = pid_t(args[2]) else {
        fail("bounds requires pid, mode, and margin")
    }
    let mode = args[3]
    let margin = CGFloat(Double(args[4]) ?? 20)
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
    var rect = CGRect.null
    for dict in list {
        guard (dict[kCGWindowOwnerPID as CFString] as? pid_t) == pid,
              let bounds = boundsDict(dict),
              bounds.width >= 24,
              bounds.height >= 20 else {
            continue
        }
        let alpha = dict[kCGWindowAlpha as CFString] as? Double ?? 1.0
        guard alpha > 0.01 else { continue }

        switch mode {
        case "switcher":
            guard bounds.width >= 300, bounds.height >= 120 else { continue }
        case "preview":
            guard bounds.width >= 120, bounds.height >= 20 else { continue }
        default:
            break
        }
        rect = rect.union(bounds)
    }
    guard !rect.isNull, !rect.isEmpty else {
        fail("no LiquidBar capture bounds found for mode \(mode)", code: 1)
    }
    let display = visibleDisplayUnion()
    if !display.isNull, !display.isEmpty {
        let rawRect = rect
        let rawClipped = rawRect.intersection(display)
        let rawClippedByDisplay = abs(rawClipped.minX - rawRect.minX) > 0.5
            || abs(rawClipped.minY - rawRect.minY) > 0.5
            || abs(rawClipped.width - rawRect.width) > 0.5
            || abs(rawClipped.height - rawRect.height) > 0.5
        if rawClippedByDisplay && mode == "switcher" {
            fail("switcher bounds are clipped by display bounds: requested=\(rawRect) clipped=\(rawClipped)", code: 1)
        }
        rect = rect.insetBy(dx: -margin, dy: -margin).intersection(display)
    } else {
        rect = rect.insetBy(dx: -margin, dy: -margin)
    }
    print("\(Int(floor(rect.origin.x))),\(Int(floor(rect.origin.y))),\(Int(ceil(rect.width))),\(Int(ceil(rect.height)))")

default:
    fail("expected subcommand: post, blacklist, bounds")
}
SWIFT

post_control() {
  swift "$CONTROL_SWIFT" post "$1" "${2:-}"
}

capture_region() {
  local mode="$1"
  local output="$2"
  local margin="${3:-24}"
  local geometry
  geometry="$(swift "$CONTROL_SWIFT" bounds "$APP_PID" "$mode" "$margin")"
  echo "${mode},${output},${geometry}" >> "${ARTIFACT_DIR}/capture-geometries.csv"
  /usr/sbin/screencapture -x -R"$geometry" "$output"
}

capture_geometry() {
  local geometry="$1"
  local output="$2"
  /usr/sbin/screencapture -x -R"$geometry" "$output"
}

capture_preview_band() {
  local output="$1"
  local full="${output%.png}-display.png"
  /usr/sbin/screencapture -x -D "$CAPTURE_DISPLAY" "$full"
  "$MAGICK" "$full" -gravity south -crop "x${PREVIEW_CROP_HEIGHT}+0+0" +repage "$output"
}

dump_snapshot() {
  local output="$1"
  post_control "com.liquidbar.testcontrol.dumpSnapshot" "$output"
  for _ in {1..20}; do
    [[ -s "$output" ]] && return 0
    sleep 0.05
  done
  return 1
}

wait_for_fixture_group_index() {
  local snapshot="${ARTIFACT_DIR}/snapshot-fixture-group.json"
  local idx
  for _ in {1..50}; do
    rm -f "$snapshot"
    if dump_snapshot "$snapshot"; then
      idx="$(python3 - "$snapshot" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    print("")
    raise SystemExit

for panel in data.get("panels", []):
    for item in panel.get("items", []):
        if item.get("kind") == "app_group" and item.get("bundle_id") == "com.liquidbar.fixture":
            print(item.get("index", ""))
            raise SystemExit
print("")
PY
)"
      if [[ -n "$idx" ]]; then
        echo "$idx"
        return 0
      fi
    fi
    sleep 0.1
  done

  echo "error: timed out waiting for fixture app group in LiquidBar snapshot" >&2
  return 1
}

wait_for_group_preview() {
  local hover_index="${1:-}"
  local snapshot="${ARTIFACT_DIR}/snapshot-group-preview.json"
  for _ in {1..30}; do
    if [[ -n "$hover_index" ]]; then
      post_control "com.liquidbar.testcontrol.setHoverIndex" "$hover_index"
    fi
    rm -f "$snapshot"
    if dump_snapshot "$snapshot" && python3 - "$snapshot" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    raise SystemExit(1)

raise SystemExit(0 if any(panel.get("group_preview_visible") for panel in data.get("panels", [])) else 1)
PY
    then
      return 0
    fi
    sleep 0.1
  done

  echo "error: timed out waiting for group preview to become visible" >&2
  return 1
}

encode_switcher_gif() {
  "$MAGICK" \
    -delay 28 "${FRAMES_DIR}/switcher-01.png" \
    -delay 22 "${FRAMES_DIR}/switcher-02.png" \
    -delay 22 "${FRAMES_DIR}/switcher-03.png" \
    -delay 34 "${FRAMES_DIR}/switcher-04.png" \
    -layers Optimize \
    -resize "${GIF_WIDTH}x>" \
    "${GIFS_DIR}/cmd-tab-switcher.gif"
}

encode_preview_gif() {
  "$MAGICK" \
    -delay 55 "${FRAMES_DIR}/taskbar-thumbnail-preview-before.png" \
    -delay 95 "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png" \
    -layers Optimize \
    -resize "${PNG_WIDTH}x>" \
    "${GIFS_DIR}/taskbar-thumbnail-preview.gif"
}

image_size() {
  "$MAGICK" identify -format "%w,%h" "$1"
}

require_same_size() {
  local label="$1"
  shift
  local first="$1"
  local expected
  expected="$(image_size "$first")"
  local image
  for image in "$@"; do
    local actual
    actual="$(image_size "$image")"
    if [[ "$actual" != "$expected" ]]; then
      echo "error: ${label} frame size mismatch: expected ${expected}, got ${actual} for ${image}" >&2
      return 1
    fi
  done
}

write_contact_sheet() {
  "$MAGICK" \
    "${FRAMES_DIR}/switcher-01.png" \
    "${FRAMES_DIR}/switcher-02.png" \
    "${FRAMES_DIR}/switcher-03.png" \
    "${FRAMES_DIR}/switcher-04.png" \
    -resize 420x \
    +append \
    "${ARTIFACT_DIR}/switcher-contact.png"

  "$MAGICK" \
    "${FRAMES_DIR}/taskbar-thumbnail-preview-before.png" \
    "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png" \
    -resize 520x \
    +append \
    "${ARTIFACT_DIR}/preview-contact.png"
}

write_capture_config() {
  local blacklist_json="$1"
  "$APP_EXEC" --print-default-config > "${CONFIG_DIR}/config.json"
  python3 - "${CONFIG_DIR}/config.json" "$blacklist_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
blacklist = json.loads(sys.argv[2])
data = json.loads(path.read_text())
data.update({
    "adjust_windows_for_taskbar": False,
    "bar_style": "flush",
    "blacklisted_apps": blacklist,
    "center_items": True,
    "group_by_app": True,
    "hide_dock": False,
    "hover_intent_guard_enabled": False,
    "icons_only": True,
    "multi_monitor_mode": "main_only",
    "performance_hang_diagnostics_enabled": False,
    "performance_logging_enabled": False,
    "plugins_enabled": False,
    "preview_hover_delay_ms": 0,
    "previews_enabled": True,
    "provider_runtime_enabled": False,
    "show_hidden_apps": False,
    "show_menu_bar_icon": False,
    "show_minimized_windows": False,
    "sidebar_mode_enabled": False,
    "switcher_enabled": True,
    "switcher_hotkey": "command+tab",
    "switcher_layout_style": "hero_carousel",
    "switcher_window_scope": "all_displays",
    "system_indicators_enabled": False,
    "taskbar_height": 32,
    "taskbar_position": "bottom",
    "window_display_mode": "all_windows",
})
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

create_backdrop_app() {
  local source="${ARTIFACT_DIR}/LiquidBarReadmeBackdrop.swift"
  mkdir -p "${BACKDROP_APP}/Contents/MacOS" "${BACKDROP_APP}/Contents/Resources"
  cat > "$source" <<'SWIFT'
import AppKit

private final class BackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.15, alpha: 1.0),
            ending: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.25, alpha: 1.0)
        )
        gradient?.draw(in: bounds, angle: 270)

        NSColor.white.withAlphaComponent(0.045).setStroke()
        for x in stride(from: CGFloat(40), to: bounds.width, by: 120) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            path.stroke()
        }
        for y in stride(from: CGFloat(56), to: bounds.height, by: 96) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            path.stroke()
        }

        let glow = NSRect(
            x: bounds.midX - bounds.width * 0.24,
            y: bounds.midY - bounds.height * 0.34,
            width: bounds.width * 0.48,
            height: bounds.height * 0.42
        )
        NSColor(calibratedRed: 0.35, green: 0.58, blue: 0.72, alpha: 0.08).setFill()
        NSBezierPath(ovalIn: glow).fill()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "LiquidBar README Backdrop"
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = BackdropView(frame: NSRect(origin: .zero, size: frame.size))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
private struct LiquidBarReadmeBackdrop {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
SWIFT

  cat > "${BACKDROP_APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LiquidBarReadmeBackdrop</string>
  <key>CFBundleIdentifier</key>
  <string>com.liquidbar.readme.backdrop</string>
  <key>CFBundleName</key>
  <string>LiquidBarReadmeBackdrop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
</dict>
</plist>
PLIST

  swiftc -parse-as-library "$source" -o "$BACKDROP_EXEC"
  codesign --force --sign - "$BACKDROP_APP" >/dev/null
}

APP_PID=""
FIXTURE_PID=""
BACKDROP_PID=""
RESTART_EXISTING=0
EXISTING_PIDS="$(pgrep -f "$APP_EXEC" || true)"

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ -n "$FIXTURE_PID" ]]; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  if [[ -n "$BACKDROP_PID" ]]; then
    kill "$BACKDROP_PID" 2>/dev/null || true
    wait "$BACKDROP_PID" 2>/dev/null || true
  fi
  if [[ "$RESTART_EXISTING" == "1" ]]; then
    /usr/bin/open -n "$APP_PATH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ -n "$EXISTING_PIDS" ]]; then
  if [[ "$STOP_EXISTING" != "1" ]]; then
    echo "error: $APP_PATH is already running." >&2
    echo "set LIQUIDBAR_README_STOP_EXISTING=1 to stop it temporarily and restart it after capture." >&2
    exit 2
  fi
  RESTART_EXISTING=1
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done <<< "$EXISTING_PIDS"
  sleep 1
fi

create_backdrop_app
/usr/bin/open -n "$BACKDROP_APP"
for _ in {1..30}; do
  BACKDROP_PID="$(pgrep -f "$BACKDROP_EXEC" | head -n 1 || true)"
  [[ -n "$BACKDROP_PID" ]] && break
  sleep 0.1
done
if [[ -z "$BACKDROP_PID" ]]; then
  echo "error: failed to launch README backdrop app" >&2
  exit 1
fi
sleep 0.7

FIXTURE_README_DEMO=1 "$FIXTURE_APP/Contents/MacOS/LiquidBarFixture" &
FIXTURE_PID=$!
sleep 2

BLACKLIST_JSON="$(swift "$CONTROL_SWIFT" blacklist com.liquidbar.fixture com.liquidbar.test com.liquidbar.testhost com.gradigit.LiquidBar)"
write_capture_config "$BLACKLIST_JSON"

LIQUIDBAR_CONFIG_DIR="$CONFIG_DIR" \
LIQUIDBAR_TEST_CONTROL=1 \
LIQUIDBAR_DISABLE_AX_PROMPT=1 \
"$APP_EXEC" &
APP_PID=$!

sleep 4
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "error: LiquidBar exited before capture could start" >&2
  exit 1
fi

HOVER_INDEX="$(wait_for_fixture_group_index)"
post_control "com.liquidbar.testcontrol.setHoverIndex" "$HOVER_INDEX"
wait_for_group_preview "$HOVER_INDEX"
sleep 0.35
capture_preview_band "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png"

post_control "com.liquidbar.testcontrol.setHoverIndex" ""
sleep 0.35
capture_preview_band "${FRAMES_DIR}/taskbar-thumbnail-preview-before.png"

post_control "com.liquidbar.testcontrol.setHoverIndex" "$HOVER_INDEX"
wait_for_group_preview "$HOVER_INDEX"
sleep 0.35
capture_preview_band "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png"
"$MAGICK" "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png" -resize "${PNG_WIDTH}x>" "${STILLS_DIR}/taskbar-thumbnail-preview.png"
if [[ "$UPDATE_TRACKED_ASSETS" == "1" ]]; then
  cp "${STILLS_DIR}/taskbar-thumbnail-preview.png" "${ASSETS_DIR}/taskbar-thumbnail-preview.png"
fi
if [[ "$CAPTURE_GIFS" == "1" ]]; then
  encode_preview_gif
fi

post_control "com.liquidbar.testcontrol.setHoverIndex" ""
sleep 0.25

post_control "com.liquidbar.testcontrol.switcher" "open"
sleep 0.8
capture_region "switcher" "${FRAMES_DIR}/switcher-01.png" "$SWITCHER_CAPTURE_MARGIN"

post_control "com.liquidbar.testcontrol.switcher" "cycle,1,forward"
sleep 0.35
capture_region "switcher" "${FRAMES_DIR}/switcher-02.png" "$SWITCHER_CAPTURE_MARGIN"

post_control "com.liquidbar.testcontrol.switcher" "cycle,1,forward"
sleep 0.35
capture_region "switcher" "${FRAMES_DIR}/switcher-03.png" "$SWITCHER_CAPTURE_MARGIN"

post_control "com.liquidbar.testcontrol.switcher" "cycle,1,backward"
sleep 0.35
capture_region "switcher" "${FRAMES_DIR}/switcher-04.png" "$SWITCHER_CAPTURE_MARGIN"

post_control "com.liquidbar.testcontrol.switcher" "close"
require_same_size "switcher" \
  "${FRAMES_DIR}/switcher-01.png" \
  "${FRAMES_DIR}/switcher-02.png" \
  "${FRAMES_DIR}/switcher-03.png" \
  "${FRAMES_DIR}/switcher-04.png"
require_same_size "preview" \
  "${FRAMES_DIR}/taskbar-thumbnail-preview-before.png" \
  "${FRAMES_DIR}/taskbar-thumbnail-preview-after.png"
"$MAGICK" "${FRAMES_DIR}/switcher-02.png" -resize "${PNG_WIDTH}x>" "${STILLS_DIR}/cmd-tab-switcher.png"
if [[ "$UPDATE_TRACKED_ASSETS" == "1" ]]; then
  cp "${STILLS_DIR}/cmd-tab-switcher.png" "${ASSETS_DIR}/cmd-tab-switcher.png"
fi
if [[ "$CAPTURE_GIFS" == "1" ]]; then
  encode_switcher_gif
fi
write_contact_sheet

echo "Captured candidate stills:"
echo "  ${STILLS_DIR}/cmd-tab-switcher.png"
echo "  ${STILLS_DIR}/taskbar-thumbnail-preview.png"
if [[ "$UPDATE_TRACKED_ASSETS" == "1" ]]; then
  echo "Updated tracked README assets:"
  echo "  ${ASSETS_DIR}/cmd-tab-switcher.png"
  echo "  ${ASSETS_DIR}/taskbar-thumbnail-preview.png"
fi
echo "Review contact sheets:"
echo "  ${ARTIFACT_DIR}/switcher-contact.png"
echo "  ${ARTIFACT_DIR}/preview-contact.png"
if [[ "$CAPTURE_GIFS" == "1" ]]; then
  echo "Review GIFs:"
  echo "  ${GIFS_DIR}/cmd-tab-switcher.gif"
  echo "  ${GIFS_DIR}/taskbar-thumbnail-preview.gif"
fi
echo "Raw frames: ${FRAMES_DIR}"
