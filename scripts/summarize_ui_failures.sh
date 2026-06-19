#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <ui_tests.log>" >&2
  exit 2
fi

LOG_FILE="$1"
if [[ ! -f "$LOG_FILE" ]]; then
  echo "error: log file not found: $LOG_FILE" >&2
  exit 2
fi

python3 - "$LOG_FILE" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
text = log_path.read_text(errors="replace")
lines = text.splitlines()

executed_re = re.compile(
    r"Executed\s+(?P<count>\d+)\s+tests?,\s+with\s+(?P<failures>\d+)\s+failures?"
)
error_re = re.compile(
    r"^(?P<source>.*?):(?P<line>\d+):\s+error:\s+-\[(?P<class>[^\s]+)\s+(?P<name>[^\]]+)\]\s+:\s+(?P<message>.*)$"
)
case_fail_re = re.compile(
    r"^Test Case '-\[(?P<class>[^\s]+)\s+(?P<name>[^\]]+)\]' failed \((?P<duration>[0-9.]+) seconds\)\.$"
)
case_skip_re = re.compile(
    r"^Test Case '-\[(?P<class>[^\s]+)\s+(?P<name>[^\]]+)\]' skipped \((?P<duration>[0-9.]+) seconds\)\.$"
)

executed_count = None
failure_count = None

errors_by_test = {}
duration_by_test = {}
skipped_tests = []

for line in lines:
    m_exec = executed_re.search(line)
    if m_exec:
        executed_count = int(m_exec.group("count"))
        failure_count = int(m_exec.group("failures"))

    m_error = error_re.match(line)
    if m_error:
        key = f"{m_error.group('class')}/{m_error.group('name')}"
        errors_by_test[key] = {
            "source": m_error.group("source"),
            "line": m_error.group("line"),
            "message": m_error.group("message"),
        }
        continue

    m_fail = case_fail_re.match(line)
    if m_fail:
        key = f"{m_fail.group('class')}/{m_fail.group('name')}"
        duration_by_test[key] = m_fail.group("duration")
        continue

    m_skip = case_skip_re.match(line)
    if m_skip:
        key = f"{m_skip.group('class')}/{m_skip.group('name')}"
        skipped_tests.append((key, m_skip.group("duration")))

failed_tests = sorted(set(errors_by_test.keys()) | set(duration_by_test.keys()))

print("LiquidBar UI Test Summary")
print(f"  log_file: {log_path}")
print(f"  executed: {executed_count if executed_count is not None else 'n/a'}")
print(f"  failed: {failure_count if failure_count is not None else len(failed_tests)}")
print(f"  skipped: {len(skipped_tests)}")
print()

if failed_tests:
    print("Failing tests:")
    for idx, test in enumerate(failed_tests, start=1):
        print(f"{idx}. {test}")
        err = errors_by_test.get(test)
        if err:
            print(f"   - error: {err['message']}")
            print(f"   - source: {err['source']}:{err['line']}")
        dur = duration_by_test.get(test)
        if dur:
            print(f"   - duration_s: {dur}")
else:
    print("No failing tests were detected in the log.")

if skipped_tests:
    print()
    print("Skipped tests:")
    for idx, (test, duration) in enumerate(skipped_tests, start=1):
        print(f"{idx}. {test} ({duration}s)")
PY
