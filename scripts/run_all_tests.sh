#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$ROOT_DIR/build/artifacts"
mkdir -p "$ARTIFACTS"

START_UNIX="$(date +%s)"
RUN_ID="${LIQUIDBAR_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
WINDOWSERVER_CRASH_REPORT="$ARTIFACTS/WindowServerCrashes-$RUN_ID.txt"

echo "==> Running SwiftPM tests"
(cd "$ROOT_DIR" && swift test -c debug)

echo "==> Running UI tests"
set +e
(cd "$ROOT_DIR" && LIQUIDBAR_RUN_ID="$RUN_ID" ./scripts/run_ui_tests.sh)
UI_RC=$?
set -e

RESULT_BUNDLE="$ARTIFACTS/LiquidBarE2E-$RUN_ID.xcresult"
CLASSIFY_RC=0
MISSING_RESULT_RC=0
if [[ -d "$RESULT_BUNDLE" ]]; then
  echo "==> Classifying UI results"
  set +e
  if [[ "${LIQUIDBAR_UI_GROUND_TRUTH_STRICT:-0}" == "1" ]]; then
    "$ROOT_DIR/scripts/classify_ui_results.sh" --strict "$RESULT_BUNDLE"
    CLASSIFY_RC=$?
  else
    "$ROOT_DIR/scripts/classify_ui_results.sh" "$RESULT_BUNDLE"
    CLASSIFY_RC=$?
  fi
  set -e
elif [[ "$UI_RC" -ne 0 ]]; then
  echo "error: UI test result bundle missing: $RESULT_BUNDLE" >&2
  MISSING_RESULT_RC="$UI_RC"
fi

if [[ -f "$WINDOWSERVER_CRASH_REPORT" ]]; then
  echo "error: WindowServer crash(es) detected during UI tests:" >&2
  cat "$WINDOWSERVER_CRASH_REPORT" >&2
  WINDOWSERVER_RC=86
else
  WINDOWSERVER_RC=0
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

if [[ "$WINDOWSERVER_RC" -ne 0 ]]; then
  exit "$WINDOWSERVER_RC"
fi
if [[ "$MISSING_RESULT_RC" -ne 0 ]]; then
  exit "$MISSING_RESULT_RC"
fi
if [[ "$CLASSIFY_RC" -ne 0 ]]; then
  exit "$CLASSIFY_RC"
fi
