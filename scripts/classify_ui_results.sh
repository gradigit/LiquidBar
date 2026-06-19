#!/usr/bin/env bash
set -euo pipefail

STRICT=0
if [[ "${1:-}" == "--strict" ]]; then
  STRICT=1
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "usage: $0 [--strict] <LiquidBarE2E.xcresult>" >&2
  exit 2
fi

RESULT_BUNDLE="$1"
if [[ ! -d "$RESULT_BUNDLE" ]]; then
  echo "error: result bundle not found: $RESULT_BUNDLE" >&2
  exit 2
fi

TESTS_JSON="$(xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" --compact)"
SUMMARY_JSON="$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --format json 2>/dev/null || printf '{"testFailures":[]}\n')"

read -r PASSED_COUNT FAILED_COUNT SKIPPED_COUNT <<<"$(jq -r '
  [ .testNodes[] | .. | objects | select(has("nodeType") and .nodeType == "Test Case") | .result ] as $results
  | [
      ($results | map(select(. == "Passed")) | length),
      ($results | map(select(. == "Failed")) | length),
      ($results | map(select(. == "Skipped")) | length)
    ]
  | @tsv
' <<<"$TESTS_JSON")"

FAILED_TESTS=()
while IFS= read -r test_name; do
  [[ -n "$test_name" ]] || continue
  FAILED_TESTS+=("$test_name")
done < <(jq -r '
  [ .testNodes[] | .. | objects
    | select(has("nodeType") and .nodeType == "Test Case" and .result == "Failed")
    | .name
  ] | .[]
' <<<"$TESTS_JSON")

declare -a HW_GATE_TESTS=(
  "testMultiMonitorPerDisplayFilteringAndSpaceChanges()"
)

declare -a NON_GATE_FAILURES=()
if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  for test_name in "${FAILED_TESTS[@]}"; do
    is_gate=0
    for gate_test in "${HW_GATE_TESTS[@]}"; do
      if [[ "$test_name" == "$gate_test" ]]; then
        is_gate=1
        break
      fi
    done
    if [[ $is_gate -eq 0 ]]; then
      NON_GATE_FAILURES+=("$test_name")
    fi
  done
fi

CLASSIFICATION="PASS"
if [[ "$FAILED_COUNT" -gt 0 ]]; then
  if [[ ${#NON_GATE_FAILURES[@]} -eq 0 ]]; then
    CLASSIFICATION="PASS_WITH_HARDWARE_GATE"
  else
    CLASSIFICATION="FAIL"
  fi
fi

echo "LiquidBar UI Ground-Truth Classification"
echo "  result_bundle: $RESULT_BUNDLE"
echo "  passed: $PASSED_COUNT"
echo "  failed: $FAILED_COUNT"
echo "  skipped: $SKIPPED_COUNT"
echo "  classification: $CLASSIFICATION"

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  echo
  echo "Failing tests:"
  for test_name in "${FAILED_TESTS[@]}"; do
    failure_text="$(jq -r --arg name "$test_name" '
      [ .testFailures[]? | select(.testName == $name) | .failureText ] | first // ""
    ' <<<"$SUMMARY_JSON")"

    if [[ -n "$failure_text" ]]; then
      echo "  - $test_name :: $failure_text"
    else
      echo "  - $test_name"
    fi
  done
fi

if [[ "$STRICT" -eq 1 && "$FAILED_COUNT" -gt 0 ]]; then
  exit 1
fi

if [[ "$CLASSIFICATION" == "FAIL" ]]; then
  exit 1
fi

exit 0
