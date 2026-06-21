#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DURATION_SECONDS="${1:-30}"
RUN_ID="${LIQUIDBAR_PERF_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_ROOT="${LIQUIDBAR_PERF_OUT_ROOT:-"${ROOT_DIR}/build/artifacts/perf"}"
OUT_DIR="${LIQUIDBAR_PERF_OUT_DIR:-"${OUT_ROOT}/${RUN_ID}"}"
LEDGER="${LIQUIDBAR_PERF_LEDGER:-"${OUT_ROOT}/performance-ledger.jsonl"}"
LABEL="${LIQUIDBAR_PERF_LABEL:-manual}"
PHASE="${LIQUIDBAR_PERF_PHASE:-measurement}"
NOTES="${LIQUIDBAR_PERF_NOTES:-}"
TARGET_PID="${LIQUIDBAR_PERF_PID:-}"
if [[ -n "$TARGET_PID" && ! "$TARGET_PID" =~ ^[0-9]+$ ]]; then
  echo "error: LIQUIDBAR_PERF_PID must be numeric: ${TARGET_PID}" >&2
  exit 2
fi

mkdir -p "$OUT_DIR" "$(dirname "$LEDGER")"

echo "Collecting LiquidBar performance artifacts for ${DURATION_SECONDS}s..."
echo "Run id: ${RUN_ID}"
echo "Label: ${LABEL}"
echo "Phase: ${PHASE}"
if [[ -n "$TARGET_PID" ]]; then
  echo "Target PID: ${TARGET_PID}"
fi
echo "Output directory: ${OUT_DIR}"

PREDICATE='subsystem == "com.liquidbar" AND (category == "perf" OR category == "metal" OR category == "event")'
COLLECT_PREDICATE='subsystem == "com.liquidbar"'
if [[ -n "$TARGET_PID" ]]; then
  PREDICATE="(${PREDICATE}) AND processID == ${TARGET_PID}"
  COLLECT_PREDICATE="(${COLLECT_PREDICATE}) AND processID == ${TARGET_PID}"
fi

LOG_STREAM_FILE="${OUT_DIR}/perf-stream.log"
log stream --style compact --info --predicate "$PREDICATE" >"$LOG_STREAM_FILE" 2>&1 &
LOG_STREAM_PID=$!

cleanup() {
  kill "$LOG_STREAM_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep "$DURATION_SECONDS"
cleanup
wait "$LOG_STREAM_PID" 2>/dev/null || true

LIQUIDBAR_PID="$TARGET_PID"
if [[ -z "$LIQUIDBAR_PID" ]]; then
  LIQUIDBAR_PID="$(pgrep -x LiquidBar | head -n 1 || true)"
fi
if [[ -n "$LIQUIDBAR_PID" ]]; then
  sample "$LIQUIDBAR_PID" 5 1 -file "${OUT_DIR}/sample.txt" >/dev/null 2>&1 || true
fi

log collect \
  --last "${DURATION_SECONDS}s" \
  --output "${OUT_DIR}/liquidbar.logarchive" \
  --predicate "$COLLECT_PREDICATE" >/dev/null 2>&1 || true

SUMMARY_JSON="${OUT_DIR}/summary.json"
SUMMARY_MD="${OUT_DIR}/summary.md"
set +e
"${ROOT_DIR}/scripts/analyze_perf_log.sh" \
  --json-out "$SUMMARY_JSON" \
  --markdown-out "$SUMMARY_MD" \
  "$LOG_STREAM_FILE"
ANALYSIS_RC=$?
set -e

GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
GIT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
GIT_DIRTY_COUNT="$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
SWIFT_VERSION="$(swift --version 2>/dev/null | head -n 1 || true)"
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || true)"

python3 - "$OUT_DIR" "$LEDGER" "$RUN_ID" "$LABEL" "$PHASE" "$DURATION_SECONDS" \
  "$ANALYSIS_RC" "$GIT_COMMIT" "$GIT_BRANCH" "$GIT_DIRTY_COUNT" \
  "$SWIFT_VERSION" "$MACOS_VERSION" "$NOTES" "$LIQUIDBAR_PID" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    out_dir_raw,
    ledger_raw,
    run_id,
    label,
    phase,
    duration_seconds,
    analysis_rc,
    git_commit,
    git_branch,
    git_dirty_count,
    swift_version,
    macos_version,
    notes,
    target_pid,
) = sys.argv[1:]

out_dir = Path(out_dir_raw)
ledger = Path(ledger_raw)
summary_path = out_dir / "summary.json"
summary = {}
if summary_path.is_file():
    summary = json.loads(summary_path.read_text())

metadata = {
    "schema_version": 1,
    "run_id": run_id,
    "label": label,
    "phase": phase,
    "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    "duration_seconds": int(float(duration_seconds)),
    "analysis_exit_code": int(analysis_rc),
    "target_pid": int(target_pid) if target_pid else None,
    "notes": notes,
    "git": {
        "branch": git_branch,
        "commit": git_commit,
        "dirty_file_count": int(git_dirty_count or "0"),
    },
    "toolchain": {
        "swift": swift_version,
        "macos": macos_version,
    },
    "artifacts": {
        "perf_stream_log": "perf-stream.log",
        "summary_json": "summary.json",
        "summary_markdown": "summary.md",
        "sample": "sample.txt" if (out_dir / "sample.txt").is_file() else None,
        "logarchive": "liquidbar.logarchive" if (out_dir / "liquidbar.logarchive").exists() else None,
    },
}

(out_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")

ledger_record = {
    "schema_version": 1,
    "run_id": run_id,
    "label": label,
    "phase": phase,
    "timestamp_utc": metadata["timestamp_utc"],
    "duration_seconds": metadata["duration_seconds"],
    "analysis_exit_code": metadata["analysis_exit_code"],
    "target_pid": metadata["target_pid"],
    "git": metadata["git"],
    "metrics": summary.get("metrics", {}),
    "passed": summary.get("passed"),
    "failures": summary.get("failures", []),
}
ledger.parent.mkdir(parents=True, exist_ok=True)
with ledger.open("a") as handle:
    handle.write(json.dumps(ledger_record, sort_keys=True) + "\n")

report_lines = [
    "# LiquidBar Performance Run",
    "",
    f"- Run id: `{run_id}`",
    f"- Label: `{label}`",
    f"- Phase: `{phase}`",
    f"- Duration seconds: `{metadata['duration_seconds']}`",
    f"- Analysis result: `{'PASS' if summary.get('passed') else 'FAIL'}`",
    f"- Git branch: `{git_branch}`",
    f"- Git commit: `{git_commit}`",
    f"- Dirty file count: `{metadata['git']['dirty_file_count']}`",
    "",
    "## Artifacts",
    "",
]
for key, value in metadata["artifacts"].items():
    if value:
        report_lines.append(f"- {key}: `{value}`")
report_lines.append("")

if summary.get("metrics"):
    report_lines.extend(["## Metrics", "", "| Metric | Value |", "| --- | ---: |"])
    for key, value in summary["metrics"].items():
        if isinstance(value, dict):
            continue
        report_lines.append(f"| `{key}` | {value} |")
    report_lines.append("")

if summary.get("failures"):
    report_lines.extend(["## Failures", ""])
    for failure in summary["failures"]:
        report_lines.append(f"- {failure}")
    report_lines.append("")

(out_dir / "run.md").write_text("\n".join(report_lines))
PY

echo "Done. Saved:"
echo "  ${LOG_STREAM_FILE}"
echo "  ${SUMMARY_JSON}"
echo "  ${SUMMARY_MD}"
echo "  ${OUT_DIR}/metadata.json"
echo "  ${OUT_DIR}/run.md"
echo "  ${LEDGER}"
if [[ -f "${OUT_DIR}/sample.txt" ]]; then
  echo "  ${OUT_DIR}/sample.txt"
fi
if [[ -d "${OUT_DIR}/liquidbar.logarchive" ]]; then
  echo "  ${OUT_DIR}/liquidbar.logarchive"
fi

exit "$ANALYSIS_RC"
