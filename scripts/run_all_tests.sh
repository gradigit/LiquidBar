#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$ROOT_DIR/build/artifacts"
mkdir -p "$ARTIFACTS"

START_UNIX="$(date +%s)"
RUN_ID="${LIQUIDBAR_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
WINDOWSERVER_CRASH_REPORT="$ARTIFACTS/WindowServerCrashes-$RUN_ID.txt"

echo "==> Running SwiftPM tests"
(cd "$ROOT_DIR" && swift test)

echo "==> Running UI tests"
set +e
(cd "$ROOT_DIR" && LIQUIDBAR_RUN_ID="$RUN_ID" ./scripts/run_ui_tests.sh)
UI_RC=$?
set -e

RESULT_BUNDLE="$ARTIFACTS/LiquidBarE2E-$RUN_ID.xcresult"
if [[ -d "$RESULT_BUNDLE" ]]; then
  echo "==> Classifying UI results"
  if [[ "${LIQUIDBAR_UI_GROUND_TRUTH_STRICT:-0}" == "1" ]]; then
    "$ROOT_DIR/scripts/classify_ui_results.sh" --strict "$RESULT_BUNDLE"
  else
    "$ROOT_DIR/scripts/classify_ui_results.sh" "$RESULT_BUNDLE"
  fi
elif [[ "$UI_RC" -ne 0 ]]; then
  echo "error: UI test result bundle missing: $RESULT_BUNDLE" >&2
  exit "$UI_RC"
fi

if [[ -f "$WINDOWSERVER_CRASH_REPORT" ]]; then
  echo "error: WindowServer crash(es) detected during UI tests:" >&2
  cat "$WINDOWSERVER_CRASH_REPORT" >&2
  exit 86
fi

echo "==> Collecting unified logs"
LOG_ARCHIVE="$ARTIFACTS/liquidbar-$RUN_ID.logarchive"
/usr/bin/log collect \
  --start "@$START_UNIX" \
  --output "$LOG_ARCHIVE" \
  --predicate 'subsystem == "com.liquidbar"'

echo "Artifacts:"
echo "  $LOG_ARCHIVE"
echo "  $RESULT_BUNDLE"
if [[ -f "$WINDOWSERVER_CRASH_REPORT" ]]; then
  echo "  $WINDOWSERVER_CRASH_REPORT"
fi
