#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BASE="$ROOT_DIR/build/artifacts/bursts"

LABEL="${1:-burst}"
COUNT="${LIQUIDBAR_BURST_COUNT:-20}"
INTERVAL="${LIQUIDBAR_BURST_INTERVAL:-0.05}"
DELAY="${LIQUIDBAR_BURST_DELAY:-0.3}"

TS="$(date +"%Y%m%d-%H%M%S")"
OUT_DIR="$OUT_BASE/${TS}-${LABEL}"

mkdir -p "$OUT_DIR"

cat <<EOF
Capturing $COUNT screenshots to:
  $OUT_DIR

Settings:
  delay:    ${DELAY}s
  interval: ${INTERVAL}s

Tip:
  Start a three-finger swipe (Space switch) during the capture window to catch transient flashes.
  Override defaults with:
    LIQUIDBAR_BURST_DELAY=0.5 LIQUIDBAR_BURST_COUNT=40 LIQUIDBAR_BURST_INTERVAL=0.03 \\
      ./scripts/capture_burst_screenshots.sh spaces-swipe
EOF

sleep "$DELAY"

for i in $(seq -w 1 "$COUNT"); do
  screencapture -x "$OUT_DIR/${LABEL}-${i}.png"
  sleep "$INTERVAL"
done

echo "Done: $OUT_DIR"

