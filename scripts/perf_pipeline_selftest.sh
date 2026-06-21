#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/artifacts/perf-selftest/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

BASELINE_LOG="$OUT_DIR/baseline.log"
CANDIDATE_LOG="$OUT_DIR/candidate.log"
OUTLIER_LOG="$OUT_DIR/outlier.log"
REGRESSION_LOG="$OUT_DIR/regression.log"

cat >"$BASELINE_LOG" <<'EOF'
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=1.00/3.00 render_ms(p50/p95)=1.00/2.00 gpu_ms(p50/p95)=0.20/0.40 gpu_wall_p95=0.50 drawable_miss=0
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.50/2.00 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] switcher action=open duration_ms=4.00 count=1 direction=1 entries=24 selected=1 success=1
2026-06-20 LiquidBar[100] switcher action=cycle duration_ms=12.00 count=30 direction=1 entries=24 selected=7 success=1
EOF

cat >"$CANDIDATE_LOG" <<'EOF'
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=0.80/2.50 render_ms(p50/p95)=0.70/1.50 gpu_ms(p50/p95)=0.15/0.30 gpu_wall_p95=0.40 drawable_miss=0
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.40/1.50 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] switcher action=open duration_ms=3.00 count=1 direction=1 entries=24 selected=1 success=1
2026-06-20 LiquidBar[100] switcher action=cycle duration_ms=9.00 count=30 direction=1 entries=24 selected=7 success=1
EOF

cat >"$OUTLIER_LOG" <<'EOF'
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=0.80/2.50 render_ms(p50/p95)=0.70/1.50 gpu_ms(p50/p95)=0.15/0.30 gpu_wall_p95=0.40 drawable_miss=0
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=0.80/2.50 render_ms(p50/p95)=0.70/1.50 gpu_ms(p50/p95)=0.15/0.30 gpu_wall_p95=0.40 drawable_miss=0
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=0.80/4.00 render_ms(p50/p95)=0.70/3.00 gpu_ms(p50/p95)=0.15/0.50 gpu_wall_p95=0.60 drawable_miss=0
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.40/1.50 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.40/1.50 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.40/20.00 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] switcher action=open duration_ms=3.00 count=1 direction=1 entries=24 selected=1 success=1
2026-06-20 LiquidBar[100] switcher action=cycle duration_ms=9.00 count=30 direction=1 entries=24 selected=7 success=1
EOF

cat >"$REGRESSION_LOG" <<'EOF'
2026-06-20 LiquidBar[100] frame d=1 fps=60.0 callback_ms(p50/p95)=1.50/4.00 render_ms(p50/p95)=1.20/3.00 gpu_ms(p50/p95)=0.20/0.40 gpu_wall_p95=0.50 drawable_miss=0
2026-06-20 LiquidBar[100] poll interval_ms=1000 exec=1 skip=4 duration_ms(p50/p95)=0.70/3.00 windows_p95=10.0 reasons=fallback=1,idle_skip=4
2026-06-20 LiquidBar[100] switcher action=open duration_ms=8.00 count=1 direction=1 entries=24 selected=1 success=1
2026-06-20 LiquidBar[100] switcher action=cycle duration_ms=30.00 count=30 direction=1 entries=24 selected=7 success=1
EOF

"$ROOT_DIR/scripts/analyze_perf_log.sh" \
  --json-out "$OUT_DIR/baseline-summary.json" \
  --markdown-out "$OUT_DIR/baseline-summary.md" \
  "$BASELINE_LOG"

"$ROOT_DIR/scripts/analyze_perf_log.sh" \
  --json-out "$OUT_DIR/candidate-summary.json" \
  --markdown-out "$OUT_DIR/candidate-summary.md" \
  "$CANDIDATE_LOG"

"$ROOT_DIR/scripts/analyze_perf_log.sh" \
  --json-out "$OUT_DIR/outlier-summary.json" \
  --markdown-out "$OUT_DIR/outlier-summary.md" \
  "$OUTLIER_LOG"

"$ROOT_DIR/scripts/analyze_perf_log.sh" \
  --json-out "$OUT_DIR/regression-summary.json" \
  --markdown-out "$OUT_DIR/regression-summary.md" \
  "$REGRESSION_LOG"

"$ROOT_DIR/scripts/compare_perf_runs.py" \
  --include-frame-lines \
  --json-out "$OUT_DIR/ab-pass.json" \
  --markdown-out "$OUT_DIR/ab-pass.md" \
  "$OUT_DIR/baseline-summary.json" \
  "$OUT_DIR/candidate-summary.json"

"$ROOT_DIR/scripts/compare_perf_runs.py" \
  --json-out "$OUT_DIR/ab-outlier-pass.json" \
  --markdown-out "$OUT_DIR/ab-outlier-pass.md" \
  "$OUT_DIR/baseline-summary.json" \
  "$OUT_DIR/outlier-summary.json"

set +e
"$ROOT_DIR/scripts/compare_perf_runs.py" \
  --json-out "$OUT_DIR/ab-regression.json" \
  --markdown-out "$OUT_DIR/ab-regression.md" \
  "$OUT_DIR/baseline-summary.json" \
  "$OUT_DIR/regression-summary.json"
REGRESSION_RC=$?
set -e

if [[ "$REGRESSION_RC" -eq 0 ]]; then
  echo "error: expected regression comparison to fail" >&2
  exit 1
fi

echo "Performance pipeline self-test artifacts: $OUT_DIR"
