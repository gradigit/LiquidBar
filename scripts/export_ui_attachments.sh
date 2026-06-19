#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

XCRESULT_PATH="${1:-"$ROOT_DIR/build/artifacts/LiquidBarE2E.xcresult"}"
OUT_DIR="${2:-"$ROOT_DIR/build/artifacts/ui_attachments"}"
SCREENSHOT_DIR="${3:-"$ROOT_DIR/build/artifacts/screenshots/current"}"

if [[ ! -d "$XCRESULT_PATH" ]]; then
  echo "error: xcresult not found: $XCRESULT_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$SCREENSHOT_DIR"

# Avoid `rm -rf` (some environments block it). Clear directories safely.
find "$OUT_DIR" -mindepth 1 -delete 2>/dev/null || true
find "$SCREENSHOT_DIR" -mindepth 1 -delete 2>/dev/null || true

echo "==> Exporting UI test attachments"
xcrun xcresulttool export attachments \
  --path "$XCRESULT_PATH" \
  --output-path "$OUT_DIR"

MANIFEST="$OUT_DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "error: expected manifest.json at: $MANIFEST" >&2
  exit 1
fi

echo "==> Canonicalizing screenshot filenames"
python3 "$ROOT_DIR/scripts/canonicalize_ui_screenshots.py" \
  --manifest "$MANIFEST" \
  --attachments-dir "$OUT_DIR" \
  --out-dir "$SCREENSHOT_DIR"

echo "Exported screenshots: $SCREENSHOT_DIR"
