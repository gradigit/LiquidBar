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

## Stable Test App Bundle

macOS privacy settings work best with a stable app bundle:

```sh
./scripts/build_test_app.sh
open -a "$HOME/Applications/LiquidBar Test.app"
```

Set `LIQUIDBAR_CODESIGN_IDENTITY` if you want to force a specific signing
identity. If unset, the script uses the first available Apple Development
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

## Full Local Run

Run SwiftPM tests, UI tests, result classification, and log collection:

```sh
./scripts/run_all_tests.sh
```

Use this before release-oriented changes or broad UI/windowing refactors.

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
