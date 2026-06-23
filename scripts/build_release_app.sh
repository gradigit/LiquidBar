#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${LIQUIDBAR_APP_NAME:-LiquidBar.app}"
APP_PATH="${LIQUIDBAR_RELEASE_APP_PATH:-${ROOT_DIR}/build/release/${APP_NAME}}"
ZIP_PATH="${LIQUIDBAR_RELEASE_ZIP_PATH:-${ROOT_DIR}/build/release/LiquidBar-${LIQUIDBAR_RELEASE_VERSION:-1.0.0}.zip}"
BUNDLE_ID="${LIQUIDBAR_BUNDLE_ID:-com.gradigit.LiquidBar}"
VERSION="${LIQUIDBAR_RELEASE_VERSION:-1.0.0}"
BUILD="${LIQUIDBAR_RELEASE_BUILD:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${LIQUIDBAR_CODESIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

cd "$ROOT_DIR"

swift build -c release >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/LiquidBar"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: expected release binary at: $BIN_PATH" >&2
  exit 1
fi

if [[ -e "$APP_PATH" && "$APP_PATH" != "$ROOT_DIR"/build/release/* ]]; then
  echo "error: refusing to replace app outside build/release: $APP_PATH" >&2
  exit 1
fi

mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

cat > "${APP_PATH}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LiquidBar</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>LiquidBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LiquidBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
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

plutil -lint "${APP_PATH}/Contents/Info.plist" >/dev/null

cp -f "$BIN_PATH" "${APP_PATH}/Contents/MacOS/LiquidBar"
cp -f "${ROOT_DIR}/Assets/AppIcon/LiquidBar.icns" "${APP_PATH}/Contents/Resources/LiquidBar.icns"
cp -f "${ROOT_DIR}/Assets/MenuBar/liquidbar-menubar-template.png" "${APP_PATH}/Contents/Resources/liquidbar-menubar-template.png"
cp -f "${ROOT_DIR}/Assets/Brand/liquidbar-brand-bar-transparent.png" "${APP_PATH}/Contents/Resources/liquidbar-brand-bar-transparent.png"

codesign_args=(--force --sign "$SIGN_IDENTITY" --options runtime)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign_args+=(--timestamp)
fi

codesign "${codesign_args[@]}" "$APP_PATH" >/dev/null
codesign --verify --strict --verbose=2 "$APP_PATH" >/dev/null

if [[ "${LIQUIDBAR_CREATE_ZIP:-1}" == "1" ]]; then
  mkdir -p "$(dirname "$ZIP_PATH")"
  ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP_PATH" "$ZIP_PATH"
fi

echo "Built: $APP_PATH"
if [[ "${LIQUIDBAR_CREATE_ZIP:-1}" == "1" ]]; then
  echo "Archive: $ZIP_PATH"
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "note: ad-hoc signed. Use a Developer ID Application identity plus notarization for public releases." >&2
fi
