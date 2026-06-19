#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/artifacts/perf/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

DURATION_SECONDS="${1:-30}"

echo "Collecting LiquidBar performance artifacts for ${DURATION_SECONDS}s..."
echo "Output directory: ${OUT_DIR}"

PREDICATE='subsystem == "com.liquidbar" AND (category == "perf" OR category == "metal" OR category == "event")'

LOG_STREAM_FILE="${OUT_DIR}/perf-stream.log"
log stream --style compact --predicate "$PREDICATE" >"$LOG_STREAM_FILE" 2>&1 &
LOG_STREAM_PID=$!

cleanup() {
  kill "$LOG_STREAM_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep "$DURATION_SECONDS"
cleanup
wait "$LOG_STREAM_PID" 2>/dev/null || true

LIQUIDBAR_PID="$(pgrep -x LiquidBar | head -n 1 || true)"
if [[ -n "$LIQUIDBAR_PID" ]]; then
  sample "$LIQUIDBAR_PID" 5 1 -file "${OUT_DIR}/sample.txt" >/dev/null 2>&1 || true
fi

log collect \
  --last "${DURATION_SECONDS}s" \
  --output "${OUT_DIR}/liquidbar.logarchive" \
  --predicate 'subsystem == "com.liquidbar"' >/dev/null 2>&1 || true

echo "Done. Saved:"
echo "  ${LOG_STREAM_FILE}"
if [[ -f "${OUT_DIR}/sample.txt" ]]; then
  echo "  ${OUT_DIR}/sample.txt"
fi
if [[ -d "${OUT_DIR}/liquidbar.logarchive" ]]; then
  echo "  ${OUT_DIR}/liquidbar.logarchive"
fi
