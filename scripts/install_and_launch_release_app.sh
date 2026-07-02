#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${LIQUIDBAR_APP_NAME:-LiquidBar.app}"
BUNDLE_ID="${LIQUIDBAR_BUNDLE_ID:-com.gradigit.LiquidBar}"
INSTALL_DIR="${LIQUIDBAR_INSTALL_DIR:-${HOME}/Applications}"
INSTALLED_APP_PATH="${LIQUIDBAR_INSTALLED_APP_PATH:-${INSTALL_DIR}/${APP_NAME}}"
BUILT_APP_PATH="${LIQUIDBAR_RELEASE_APP_PATH:-${ROOT_DIR}/build/release/${APP_NAME}}"
SIGN_IDENTITY="${LIQUIDBAR_CODESIGN_IDENTITY:-}"

if [[ "$APP_NAME" != *.app ]]; then
  echo "error: LIQUIDBAR_APP_NAME must end with .app: $APP_NAME" >&2
  exit 1
fi

if [[ "$INSTALLED_APP_PATH" != *.app ]]; then
  echo "error: install target must end with .app: $INSTALLED_APP_PATH" >&2
  exit 1
fi

if [[ "$BUILT_APP_PATH" != "$ROOT_DIR"/build/release/* ]]; then
  echo "error: install helper expects a build/release app bundle: $BUILT_APP_PATH" >&2
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}' || true)"
fi

if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
  if [[ "${LIQUIDBAR_ALLOW_ADHOC_INSTALL:-0}" != "1" ]]; then
    cat >&2 <<'EOF'
error: no Apple Development signing identity found.

This helper refuses ad-hoc installs by default because ad-hoc rebuilds can make
macOS privacy permissions look like a new app after each rebuild.

Set LIQUIDBAR_CODESIGN_IDENTITY to a stable certificate, or set
LIQUIDBAR_ALLOW_ADHOC_INSTALL=1 if you intentionally want an ad-hoc build.
EOF
    exit 1
  fi
  SIGN_IDENTITY="-"
fi

export LIQUIDBAR_CODESIGN_IDENTITY="$SIGN_IDENTITY"
export LIQUIDBAR_CREATE_ZIP="${LIQUIDBAR_CREATE_ZIP:-0}"

"${ROOT_DIR}/scripts/build_release_app.sh"

codesign --verify --strict --verbose=2 "$BUILT_APP_PATH" >/dev/null
designated_requirement="$(codesign -d -r- "$BUILT_APP_PATH" 2>&1 || true)"
if [[ "$designated_requirement" != *"identifier \"${BUNDLE_ID}\""* ]]; then
  echo "error: built app does not have expected bundle identifier: $BUNDLE_ID" >&2
  echo "$designated_requirement" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
sleep 1

installed_executable="${INSTALLED_APP_PATH}/Contents/MacOS/LiquidBar"
if pgrep -f "$installed_executable" >/dev/null 2>&1; then
  pkill -f "$installed_executable" >/dev/null 2>&1 || true
  sleep 1
fi

ditto --norsrc --noextattr --noqtn "$BUILT_APP_PATH" "$INSTALLED_APP_PATH"
codesign --verify --strict --verbose=2 "$INSTALLED_APP_PATH" >/dev/null

/usr/bin/open -n "$INSTALLED_APP_PATH"
sleep 1

echo "Installed: $INSTALLED_APP_PATH"
echo "Launched: ${BUNDLE_ID}"
echo "Signing: ${SIGN_IDENTITY}"
