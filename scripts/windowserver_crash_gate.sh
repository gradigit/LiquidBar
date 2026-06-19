#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: windowserver_crash_gate.sh -- <command> [args...]

Runs a command and fails if new WindowServer crash reports appear while it runs.

Environment:
  LIQUIDBAR_CRASH_GATE_REPORT   optional file path to write detected crash paths
  LIQUIDBAR_CRASH_GATE_WAIT_SECS optional delayed-report grace period (default: 6)
  LIQUIDBAR_CRASH_GATE_POLL_INTERVAL_SECS optional poll interval during grace period (default: 1)
EOF
}

if [[ "${1:-}" != "--" ]]; then
  usage
  exit 2
fi
shift

if [[ "$#" -eq 0 ]]; then
  usage
  exit 2
fi

REPORT_DIR="/Library/Logs/DiagnosticReports"
REPORT_GLOB="WindowServer-*.ips"

list_reports() {
  if [[ ! -d "$REPORT_DIR" ]]; then
    return 0
  fi

  find "$REPORT_DIR" -maxdepth 1 -type f -name "$REPORT_GLOB" -print0 \
    | while IFS= read -r -d '' file; do
        mtime="$(stat -f '%m' "$file" 2>/dev/null || printf '0')"
        printf '%s\t%s\n' "$mtime" "$file"
      done \
    | LC_ALL=C sort
}

before_file="$(mktemp -t liquidbar-ws-before.XXXXXX)"
after_file="$(mktemp -t liquidbar-ws-after.XXXXXX)"
cleanup() {
  rm -f "$before_file" "$after_file"
}
trap cleanup EXIT

list_reports >"$before_file"

set +e
"$@"
cmd_rc=$?
set -e

collect_new_reports() {
  list_reports >"$after_file"
  new_reports=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    new_reports+=("$line")
  done < <(
    awk 'NR==FNR { seen[$0]=1; next } !($0 in seen) { sub(/^[0-9]+\t/, "", $0); print }' "$before_file" "$after_file"
  )
}

wait_secs="${LIQUIDBAR_CRASH_GATE_WAIT_SECS:-6}"
poll_secs="${LIQUIDBAR_CRASH_GATE_POLL_INTERVAL_SECS:-1}"

if ! [[ "$wait_secs" =~ ^[0-9]+$ ]]; then
  wait_secs=6
fi
if ! [[ "$poll_secs" =~ ^[0-9]+$ ]] || ((poll_secs < 1)); then
  poll_secs=1
fi

collect_new_reports

attempts=0
if ((wait_secs > 0)); then
  attempts=$(((wait_secs + poll_secs - 1) / poll_secs))
fi

for ((i = 0; i < attempts; i++)); do
  if ((${#new_reports[@]} > 0)); then
    break
  fi
  sleep "$poll_secs"
  collect_new_reports
done

if ((${#new_reports[@]} > 0)); then
  {
    echo "Detected new WindowServer crash reports during command:"
    for report in "${new_reports[@]}"; do
      echo "$report"
    done
  } >&2

  if [[ -n "${LIQUIDBAR_CRASH_GATE_REPORT:-}" ]]; then
    mkdir -p "$(dirname "$LIQUIDBAR_CRASH_GATE_REPORT")"
    printf '%s\n' "${new_reports[@]}" >"$LIQUIDBAR_CRASH_GATE_REPORT"
  fi

  exit 86
fi

exit "$cmd_rc"
