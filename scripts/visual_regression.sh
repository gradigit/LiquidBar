#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-}"
if [[ "$MODE" != "record" && "$MODE" != "compare" ]]; then
  echo "usage: $0 record|compare [xcresult_path]" >&2
  exit 2
fi

XCRESULT_PATH="${2:-"$ROOT_DIR/build/artifacts/LiquidBarE2E.xcresult"}"
FLAVOR="${LIQUIDBAR_BASELINE_FLAVOR:-default}"
BASELINE_DIR="$ROOT_DIR/UITests/Baselines/$FLAVOR"

CURRENT_DIR="$ROOT_DIR/build/artifacts/screenshots/current"
DIFF_DIR="$ROOT_DIR/build/artifacts/screenshots/diff"

"$ROOT_DIR/scripts/export_ui_attachments.sh" "$XCRESULT_PATH"

mkdir -p "$BASELINE_DIR"

if [[ "$MODE" == "record" ]]; then
  # Avoid `rm -rf` (some environments block it). Clear baselines safely.
  find "$BASELINE_DIR" -mindepth 1 -delete 2>/dev/null || true
  cp -R "$CURRENT_DIR"/. "$BASELINE_DIR"/
  echo "Recorded baselines to: $BASELINE_DIR"
  exit 0
fi

mkdir -p "$DIFF_DIR"
find "$DIFF_DIR" -mindepth 1 -delete 2>/dev/null || true

# Defaults tuned for Metal + font AA drift.
MAX_CHANGED_PERCENT="${LIQUIDBAR_VISUAL_MAX_CHANGED_PERCENT:-0.5}"
PER_CHANNEL_THRESHOLD="${LIQUIDBAR_VISUAL_PER_CHANNEL_THRESHOLD:-8}"

./scripts/pixel_diff.swift \
  --baseline-dir "$BASELINE_DIR" \
  --candidate-dir "$CURRENT_DIR" \
  --diff-dir "$DIFF_DIR" \
  --max-changed-percent "$MAX_CHANGED_PERCENT" \
  --per-channel-threshold "$PER_CHANNEL_THRESHOLD"
