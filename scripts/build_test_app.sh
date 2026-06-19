#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_DIR="${HOME}/Applications"
APP_NAME="LiquidBar Test.app"
APP_PATH="${APP_DIR}/${APP_NAME}"

# Prefer a stable signing identity so macOS TCC permissions persist across rebuilds.
# Ad-hoc signing (`-`) often triggers re-prompts because the code signature changes.
SIGN_IDENTITY="${LIQUIDBAR_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  # Pick the first Apple Development identity if available (typical on Xcode dev machines).
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}' || true)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT_DIR"

# Build first; `--show-bin-path` alone only prints the path and may reuse a stale binary.
swift build -c debug >/dev/null
BIN_DIR="$(swift build -c debug --show-bin-path)"
BIN_PATH="${BIN_DIR}/LiquidBar"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: expected binary at: $BIN_PATH" >&2
  exit 1
fi

mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

cat > "${APP_PATH}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LiquidBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.liquidbar.test</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LiquidBar Test</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
</dict>
</plist>
PLIST

cp -f "$BIN_PATH" "${APP_PATH}/Contents/MacOS/LiquidBar"

# Ensure the bundle is runnable and stable for System Settings -> Privacy panes.
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH" >/dev/null

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "note: built with ad-hoc codesign (-). If macOS keeps re-prompting for permissions after rebuilds," >&2
  echo "      set LIQUIDBAR_CODESIGN_IDENTITY to a stable identity (Apple Development / Developer ID)." >&2
fi

echo "Installed: $APP_PATH"
