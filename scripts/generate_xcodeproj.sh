#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/xcode"

mkdir -p "$OUT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate \
  --spec "$ROOT_DIR/XcodeGen/project.yml" \
  --project-root "$ROOT_DIR" \
  --project "$OUT_DIR"

echo "Generated: $OUT_DIR/LiquidBar.xcodeproj"
