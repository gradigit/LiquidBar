# Testing

## Fast Test Loop

Run the SwiftPM suite:

```sh
swift test -c debug
```

This is the default local and CI gate.

## UI Tests

UI tests are driven by an Xcode project generated from `XcodeGen/project.yml`.

Install XcodeGen:

```sh
brew install xcodegen
brew install jq
```

Generate the project:

```sh
./scripts/generate_xcodeproj.sh
```

Run UI tests:

```sh
./scripts/run_ui_tests.sh
```

Results are written under:

```text
build/artifacts/
build/DerivedData/
```

## App Bundles

Build the release-mode app bundle for release-candidate checks:

```sh
./scripts/build_release_app.sh
open build/release/LiquidBar.app
```

The script ad-hoc signs by default. Set `LIQUIDBAR_CODESIGN_IDENTITY` for a
stable local or Developer ID identity.

Build the developer test bundle when you need a separate stable identity for
TCC permission reset/regrant loops:

macOS privacy settings work best with a stable app bundle:

```sh
./scripts/build_test_app.sh
open -a "$HOME/Applications/LiquidBar Test.app"
```

If unset, `scripts/build_test_app.sh` uses the first available Apple Development
identity and falls back to ad-hoc signing.

## Visual Regression

Compare screenshots:

```sh
LIQUIDBAR_SNAPSHOT_MODE=compare ./scripts/run_ui_tests.sh
```

Record/update baselines deliberately:

```sh
LIQUIDBAR_SNAPSHOT_MODE=record ./scripts/run_ui_tests.sh
```

Baselines live under:

```text
UITests/Baselines/
```

Use `LIQUIDBAR_BASELINE_FLAVOR` for separate display classes when needed.

## WindowServer Crash Gate

`scripts/run_ui_tests.sh` runs through `scripts/windowserver_crash_gate.sh` by
default. The gate fails the run if a new WindowServer crash report appears
during UI automation.

Disable only when isolating tooling issues:

```sh
LIQUIDBAR_CRASH_GATE_WINDOWSERVER=0 ./scripts/run_ui_tests.sh
```

If Xcode cannot initialize UI automation, `scripts/classify_ui_results.sh`
reports `INFRASTRUCTURE_BLOCKED` and exits 87. Treat this as a local automation
environment blocker, not as product correctness evidence.

`scripts/classify_ui_results.sh` also reports `PASS_WITH_HARDWARE_GATE` for
known hardware-dependent failures when strict mode is not enabled. Set
`LIQUIDBAR_UI_GROUND_TRUTH_STRICT=1` to make every UI test failure fail the
classification step.

## Full Local Run

Run SwiftPM tests, UI tests, result classification, and log collection:

```sh
./scripts/run_all_tests.sh
```

Use this before release-oriented changes or broad UI/windowing refactors.
For packaging and notarization checks, use `docs/RELEASE.md`.

## Performance Capture

Capture performance logs while the app is running:

```sh
./scripts/benchmark_performance.sh 30
```

Artifacts are written under:

```text
build/artifacts/perf/
```

Use this when changing event processing, thumbnail capture, rendering, or
multi-display behavior.

For optimization work, use the full baseline/candidate comparison workflow in
`docs/PERFORMANCE.md`. The performance scripts produce parsed summaries,
metadata, run notes, and local ledger entries under `build/artifacts/perf/`.

Validate parser/comparator changes with:

```sh
./scripts/perf_pipeline_selftest.sh
```
