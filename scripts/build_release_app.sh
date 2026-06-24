#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${LIQUIDBAR_APP_NAME:-LiquidBar.app}"
APP_PATH="${LIQUIDBAR_RELEASE_APP_PATH:-${ROOT_DIR}/build/release/${APP_NAME}}"
ZIP_PATH="${LIQUIDBAR_RELEASE_ZIP_PATH:-${ROOT_DIR}/build/release/LiquidBar-${LIQUIDBAR_RELEASE_VERSION:-1.0.0}.zip}"
DMG_PATH="${LIQUIDBAR_RELEASE_DMG_PATH:-${ROOT_DIR}/build/release/LiquidBar-${LIQUIDBAR_RELEASE_VERSION:-1.0.0}.dmg}"
BUNDLE_ID="${LIQUIDBAR_BUNDLE_ID:-com.gradigit.LiquidBar}"
VERSION="${LIQUIDBAR_RELEASE_VERSION:-1.0.0}"
BUILD="${LIQUIDBAR_RELEASE_BUILD:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${LIQUIDBAR_CODESIGN_IDENTITY:-}"
VOLUME_NAME="${LIQUIDBAR_DMG_VOLUME_NAME:-LiquidBar}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  # Prefer a stable local signing identity so macOS TCC permissions persist
  # across local rebuilds. CI/release machines without an identity fall back
  # to ad-hoc signing below.
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}' || true)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ko</string>
  </array>
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
  <key>NSScreenCaptureUsageDescription</key>
  <string>LiquidBar uses Screen Recording permission to capture static window thumbnails for taskbar previews and the window switcher.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>LiquidBar uses Input Monitoring only for global keyboard shortcuts such as Cmd-Tab before macOS handles them.</string>
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

shopt -s nullglob
resource_bundles=("${BIN_DIR}"/LiquidBar_*.bundle)
shopt -u nullglob
if [[ ${#resource_bundles[@]} -eq 0 ]]; then
  echo "error: expected SwiftPM resource bundle for localized resources in: $BIN_DIR" >&2
  exit 1
fi
for resource_bundle in "${resource_bundles[@]}"; do
  ditto --norsrc --noextattr --noqtn "$resource_bundle" "${APP_PATH}/Contents/Resources/$(basename "$resource_bundle")"
done

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

if [[ "${LIQUIDBAR_CREATE_DMG:-0}" == "1" ]]; then
  DMG_STAGING="${ROOT_DIR}/build/release/dmg-staging"
  if [[ "$DMG_STAGING" != "$ROOT_DIR"/build/release/* ]]; then
    echo "error: refusing to clean staging path outside build/release: $DMG_STAGING" >&2
    exit 1
  fi
  if [[ -e "$DMG_STAGING" ]]; then
    rm -R "$DMG_STAGING"
  fi
  mkdir -p "$DMG_STAGING"
  ditto --norsrc --noextattr --noqtn "$APP_PATH" "${DMG_STAGING}/${APP_NAME}"
  ln -s /Applications "${DMG_STAGING}/Applications"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
  hdiutil verify "$DMG_PATH" >/dev/null
fi

echo "Built: $APP_PATH"
if [[ "${LIQUIDBAR_CREATE_ZIP:-1}" == "1" ]]; then
  echo "Archive: $ZIP_PATH"
fi
if [[ "${LIQUIDBAR_CREATE_DMG:-0}" == "1" ]]; then
  echo "DMG: $DMG_PATH"
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "note: ad-hoc signed. Gatekeeper will warn until a Developer ID signed and notarized build is published." >&2
fi
