# Performance Testing

LiquidBar performance work should be measured before and after code changes.
Generated logs, samples, summaries, and ledgers belong under
`build/artifacts/perf/`, which is ignored by git.

## When To Use This

Use this workflow for changes touching:

- event-loop cadence or polling
- window inventory, focus, or display assignment
- thumbnail capture or caching
- retained rendering and layer updates
- previews, switcher UI, panels, or multi-display behavior

## Preflight

Start from a known source state:

```sh
git status --short --branch
swift test -c debug
```

Enable performance logging in the config used by the app:

```json
{
  "performance_logging_enabled": true,
  "performance_log_interval_ms": 1000
}
```

Use `LIQUIDBAR_CONFIG_DIR` for benchmark runs so measurement config does not
touch the real user profile.

## Capture A Run

Run the app, exercise the behavior under test, then collect a perf capture:

```sh
LIQUIDBAR_PERF_LABEL=window-churn \
LIQUIDBAR_PERF_PHASE=baseline \
./scripts/benchmark_performance.sh 60
```

If more than one `LiquidBar` process is running, set `LIQUIDBAR_PERF_PID` to
the process under test.

The capture script writes a run directory under:

```text
build/artifacts/perf/<run-id>/
```

Typical artifacts include:

- `perf-stream.log`
- `summary.json`
- `summary.md`
- `metadata.json`
- `run.md`
- `sample.txt`
- `liquidbar.logarchive`

It also appends a compact local record to:

```text
build/artifacts/perf/performance-ledger.jsonl
```

Do not commit raw generated artifacts. Include only concise findings in PR
descriptions or tracked docs.

## Analyze Existing Logs

Analyze a captured log directly:

```sh
./scripts/analyze_perf_log.sh \
  --json-out build/artifacts/perf/manual-summary.json \
  --markdown-out build/artifacts/perf/manual-summary.md \
  build/artifacts/perf/<run-id>/perf-stream.log
```

Use `--no-thresholds` when you need a summary without pass/fail enforcement.

## Compare Baseline And Candidate

Capture a baseline, make the code change, rerun `swift test -c debug`, then
capture a candidate using the same duration, display layout, config, and user
interaction pattern.

Compare two run directories or two `summary.json` files:

```sh
./scripts/compare_perf_runs.py \
  build/artifacts/perf/<baseline-run-id> \
  build/artifacts/perf/<candidate-run-id> \
  --json-out build/artifacts/perf/<candidate-run-id>/ab-comparison.json \
  --markdown-out build/artifacts/perf/<candidate-run-id>/ab-comparison.md
```

The comparator fails when the candidate fails absolute thresholds or when a
tracked sustained metric regresses beyond the allowed relative threshold.

Default relative regression tolerance is 5%, with a 0.5 absolute metric-unit
floor so tiny sub-millisecond noise does not fail a run by percentage alone.
Override those only with an explicit reason:

```sh
./scripts/compare_perf_runs.py \
  --max-regression-percent 3 \
  --min-regression-absolute 0.25 \
  <baseline-summary-or-dir> \
  <candidate-summary-or-dir>
```

For active-animation benchmarks, include FPS in the comparison:

```sh
LIQUIDBAR_PERF_FPS_MIN=58 ./scripts/benchmark_performance.sh 60

./scripts/compare_perf_runs.py \
  --include-fps \
  build/artifacts/perf/<baseline-run-id> \
  build/artifacts/perf/<candidate-run-id>
```

For idle or cursor-churn work where the desired result is fewer display-link
frames, compare frame log count explicitly:

```sh
./scripts/compare_perf_runs.py \
  --include-frame-lines \
  build/artifacts/perf/<baseline-run-id> \
  build/artifacts/perf/<candidate-run-id>
```

For soak-style investigations where the worst interval should also be a
relative regression gate, add `--compare-worst`.

## Thresholds

`scripts/analyze_perf_log.sh` and `scripts/benchmark_performance.sh` use these
environment variables:

```text
LIQUIDBAR_PERF_FPS_MIN=<disabled by default; set for active-animation runs>
LIQUIDBAR_PERF_CALLBACK_P95_MAX=12
LIQUIDBAR_PERF_RENDER_P95_MAX=8
LIQUIDBAR_PERF_DRAWABLE_MISS_MAX=3
LIQUIDBAR_PERF_POLL_P95_MAX=40
LIQUIDBAR_PERF_SWITCHER_OPEN_P95_MAX=<disabled by default>
LIQUIDBAR_PERF_SWITCHER_CYCLE_STEP_P95_MAX=<disabled by default>
```

The absolute thresholds are local gates. The A/B comparator is a relative gate.

## Tooling Self-Test

Run the synthetic parser/comparator self-test after changing performance
scripts:

```sh
./scripts/perf_pipeline_selftest.sh
```

The self-test writes generated evidence under `build/artifacts/perf-selftest/`.
Do not commit that output.

## Reporting

When reporting a performance change, include:

- baseline run id
- candidate run id
- command used for capture
- interaction pattern or automation used
- relevant threshold overrides
- A/B comparison result
- any remaining uncertainty, such as display layout or manual timing variance
