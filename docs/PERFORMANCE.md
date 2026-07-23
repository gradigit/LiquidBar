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

## Measurement Layers

A performance claim is stronger when it covers all affected layers:

1. **LiquidBar internals:** poll, render, switcher, animation, and thumbnail
   timings emitted by `PerformanceMonitor`.
2. **LiquidBar process:** sustained CPU and resident memory, including idle and
   interaction phases.
3. **System impact:** correlated `WindowServer` and capture-service load while
   LiquidBar enumerates windows, composites panels, or captures thumbnails.
4. **User-visible behavior:** frame cadence, thumbnail availability, input
   latency, and correctness on the same display topology.

The checked-in comparator currently gates the first layer. It can optionally
gate logged FPS and frame-line churn, and `benchmark_performance.sh` records a
five-second post-capture process sample for diagnosis. It does **not** currently
calculate or A/B-gate sustained LiquidBar CPU/RSS, `WindowServer` CPU, capture
service CPU, or system screenshot activity. An internal benchmark `PASS` alone
therefore does not prove low machine-wide overhead.

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

For developer-only hang diagnosis, turn on Preferences -> Advanced ->
Diagnostics -> Hang diagnostics. If preferences are inaccessible, launch the app
with:

```sh
launchctl setenv LIQUIDBAR_DEV_DIAGNOSTICS 1
```

This keeps normal release logging quiet, but adds local-only `perf` lines for:

- per-segment aggregate timings (`segment name=...`)
- rate-limited stall warnings (`stall name=...`)
- occasional privacy-safe state snapshots (`diag name=poll_state ...`)

The diagnostics intentionally avoid window titles, URLs, and per-window dumps.
Manual unified-log checks need `--info` to include aggregate `Logger.info`
diagnostics:

```sh
log show --last 2m --info --predicate 'subsystem == "com.liquidbar" AND category == "perf"'
```

Clear the variable after the run:

```sh
launchctl unsetenv LIQUIDBAR_DEV_DIAGNOSTICS
```

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

When developer diagnostics are enabled, `summary.json` and `summary.md` also
include segment, stall, and diagnostic-line counts.

When thumbnail capture runs during the sample, summaries also include
privacy-safe thumbnail counts and p95 timings for queue wait, ScreenCaptureKit
capture, and total delivery latency. These lines are grouped only by producer,
size tier, and outcome; they do not include window titles or URLs.

When the window switcher scrolls during a sample, summaries also include
privacy-safe animation telemetry: animation kind, duration, frame interval p50,
p95, max, retarget count, and travel distance. These rows are emitted only when
performance logging or developer diagnostics collection is active.

The privacy-safe poll-state diagnostic also reports whether a poll enumerated,
its trigger reason, window/item/display counts, RSS, and thumbnail cache/queue
counts. These diagnostic lines are useful for investigation, but the current
analyzer does not turn them into comparator metrics.

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

## Host-Impact A/B

Add a host-impact pass whenever a change can alter inventory frequency,
Accessibility work, panel compositing, thumbnail capture, or multi-display
behavior. Use the same app build mode, config, window set, interaction script,
display topology, duration, and settling time for baseline and candidate.

Record at minimum:

- LiquidBar CPU and RSS over time, separating idle and interaction phases;
- `WindowServer` CPU over the same interval;
- capture-service CPU and thumbnail event counts for preview/switcher work;
- display count, scaling, refresh rate, and whether windows were moving;
- screenshot permission state and whether caches started cold or warm.

Activity Monitor, Instruments, or a reviewed local process sampler can provide
the process-level series. Store raw samples under the ignored run directory and
summarize only aggregate, privacy-safe values in a PR or tracked research note.
Do not record window titles, URLs, screenshots, or unrelated process details.

Interpret system processes carefully. `WindowServer` is shared by every visible
application and display, while capture services are shared system components.
Higher load that lines up with LiquidBar activity is evidence of correlation;
attribute it to a specific LiquidBar path only after an A/B toggle or source
instrumentation changes that path while the rest of the workload stays stable.

For thumbnail investigations, compare cold and warm phases separately. A cache
hit should not call `SCScreenshotManager.captureImage`; a miss can involve both
the capture service and `WindowServer`. Include capture counts alongside latency
so a faster p95 cannot hide a much higher request rate.

### Switcher Thumbnail Cache A/B

The switcher uses an in-memory thumbnail cache with idle prewarm. To measure
that policy against a cold no-prewarm baseline, run the same switcher benchmark
twice:

```sh
LIQUIDBAR_DISABLE_SWITCHER_THUMBNAIL_PREWARM=1 \
LIQUIDBAR_SWITCHER_RUN_ID=<baseline-run-id> \
./scripts/benchmark_switcher.sh

LIQUIDBAR_SWITCHER_RUN_ID=<candidate-run-id> \
./scripts/benchmark_switcher.sh

./scripts/compare_perf_runs.py \
  build/artifacts/perf/<baseline-run-id> \
  build/artifacts/perf/<candidate-run-id>
```

Do not use disk thumbnail caches in benchmark or product builds. Window
thumbnails can contain private user content; keep this cache memory-only.

### Switcher Scroll Animation A/B

The switcher scroll animation can be compared in the same built app by toggling
the animation mode at launch. The default product path is `displaylink_spring`,
because live hotkey A/B showed the most stable frame cadence once thumbnail
capture was kept out of the held Cmd-Tab path. Use the native path as the
baseline when testing changes:

```sh
LIQUIDBAR_SWITCHER_APP_SETTLE_SECONDS=8 \
LIQUIDBAR_SWITCHER_SCROLL_ANIMATION=legacy \
LIQUIDBAR_SWITCHER_RUN_ID=<baseline-run-id> \
./scripts/benchmark_switcher.sh

LIQUIDBAR_SWITCHER_APP_SETTLE_SECONDS=8 \
LIQUIDBAR_SWITCHER_SCROLL_ANIMATION=displaylink_spring \
LIQUIDBAR_SWITCHER_RUN_ID=<candidate-run-id> \
./scripts/benchmark_switcher.sh

./scripts/compare_perf_runs.py \
  --compare-worst \
  build/artifacts/perf/<baseline-run-id> \
  build/artifacts/perf/<candidate-run-id> \
  --json-out build/artifacts/perf/<candidate-run-id>/ab-comparison.json \
  --markdown-out build/artifacts/perf/<candidate-run-id>/ab-comparison.md
```

`displaylink_spring` coalesces rapid selected-window changes onto the next
main-actor turn and drives the scroll position with a high-damping display-link
spring. `legacy`, `native`, and `native_scroll` use the AppKit clip-view
animation path for baseline comparisons. `spring` uses the compositor transform
path and remains an explicit experimental mode until it is stable across
repeated live runs.

Live Cmd-Tab sessions intentionally do not start active `switcher` thumbnail
captures while the modifier is held. They use memory-only cached/prewarmed
thumbnails during traversal and defer prewarm work after close, so
ScreenCaptureKit does not compete with the animation.

The 8-second settle window gives switcher thumbnail prewarm time to populate
memory caches before the timed interaction begins; keep it for scroll-only A/B
unless the change under test is thumbnail loading itself.

For live hotkey validation, use the same `LIQUIDBAR_SWITCHER_SCROLL_ANIMATION`
toggle with `./scripts/benchmark_switcher_live_hotkey.sh`. Live hotkey runs are
closer to the real input path, but can be affected by Input Monitoring
permission state and foreground app focus; keep the synthetic switcher benchmark
as the repeatable gate.

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
LIQUIDBAR_PERF_SWITCHER_ANIMATION_FRAME_P95_MAX=<disabled by default>
LIQUIDBAR_PERF_THUMBNAIL_CAPTURE_P95_MAX=<disabled by default>
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
- process and system-impact aggregates when the changed path affects them
- any remaining uncertainty, such as display layout or manual timing variance
