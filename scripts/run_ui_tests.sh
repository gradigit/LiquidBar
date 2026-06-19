#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/generate_xcodeproj.sh"

PROJ="$ROOT_DIR/build/xcode/LiquidBar.xcodeproj"
DERIVED="$ROOT_DIR/build/DerivedData"
ARTIFACTS="$ROOT_DIR/build/artifacts"

mkdir -p "$ARTIFACTS"

SCHEME="LiquidBarE2E"
RUN_ID="${LIQUIDBAR_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_BUNDLE="$ARTIFACTS/$SCHEME-$RUN_ID.xcresult"
WINDOWSERVER_CRASH_REPORT="$ARTIFACTS/WindowServerCrashes-$RUN_ID.txt"

# Note: UI tests may require interactive permission prompts the first time
# (Automation / Accessibility / Screen Recording), and code signing may require
# Xcode authentication depending on the machine configuration.

set +e
if [[ "${LIQUIDBAR_CRASH_GATE_WINDOWSERVER:-1}" == "1" ]]; then
  LIQUIDBAR_CRASH_GATE_REPORT="$WINDOWSERVER_CRASH_REPORT" \
    "$ROOT_DIR/scripts/windowserver_crash_gate.sh" -- \
    xcodebuild test \
      -project "$PROJ" \
      -scheme "$SCHEME" \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath "$RESULT_BUNDLE" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY=- \
      CODE_SIGNING_ALLOWED=YES
  XCODE_STATUS=$?
else
  xcodebuild test \
    -project "$PROJ" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$RESULT_BUNDLE" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES
  XCODE_STATUS=$?
fi
set -e

echo "UI test results: $RESULT_BUNDLE"
if [[ -f "$WINDOWSERVER_CRASH_REPORT" ]]; then
  echo "WindowServer crash report list: $WINDOWSERVER_CRASH_REPORT"
fi

set +e
if [[ "${LIQUIDBAR_SNAPSHOT_MODE:-}" == "record" || "${LIQUIDBAR_SNAPSHOT_MODE:-}" == "compare" ]]; then
  echo "==> Visual regression (${LIQUIDBAR_SNAPSHOT_MODE})"
  "$ROOT_DIR/scripts/visual_regression.sh" "${LIQUIDBAR_SNAPSHOT_MODE}" "$RESULT_BUNDLE"
else
  echo "==> Exporting UI test screenshots"
  "$ROOT_DIR/scripts/export_ui_attachments.sh" "$RESULT_BUNDLE"
fi
set -e

exit "$XCODE_STATUS"
