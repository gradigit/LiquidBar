# Development

## Required Tools

- macOS 26 or newer.
- Swift 6.2 or newer.
- Xcode command line tools.
- XcodeGen for UI tests.
- `jq` for UI result classification.

Install helper tools with Homebrew if needed:

```sh
brew install xcodegen jq
```

## Common Commands

Build:

```sh
swift build
```

Run unit and integration tests:

```sh
swift test -c debug
```

Run the app directly:

```sh
swift run LiquidBar
```

Inspect or initialize config:

```sh
swift run LiquidBar -- --print-config-path
swift run LiquidBar -- --print-default-config
swift run LiquidBar -- --write-default-config
```

Build a stable app bundle for local permission testing:

```sh
./scripts/build_test_app.sh
open -a "$HOME/Applications/LiquidBar Test.app"
```

## Branch Workflow

Use short-lived branches for changes:

```sh
git checkout main
git pull --ff-only
git switch -c <branch-name>
```

Before merging:

```sh
swift test -c debug
git status --short --branch
```

CI runs the same SwiftPM test command on `macos-26`.

## Local Permissions

Some features require macOS privacy permissions when running the app bundle:

- Accessibility for window management.
- Screen Recording for window previews.
- Input Monitoring for Cmd-Tab style event-tap shortcuts.
- Automation prompts when running UI tests through Xcode.

Use the stable test app bundle from `scripts/build_test_app.sh` so macOS privacy
settings attach to a stable app identity.

## Local Config Isolation

Set `LIQUIDBAR_CONFIG_DIR` when testing config or state changes:

```sh
LIQUIDBAR_CONFIG_DIR="$(mktemp -d)" swift run LiquidBar
```

Do not use tests to mutate the real user config directory.

Plugins and provider manifests are discovered under `Plugins` in the active
config directory, so isolated config directories are also the safest way to test
plugin behavior.

## Performance Work

Enable performance logging in config before collecting runtime logs:

```json
{
  "performance_logging_enabled": true
}
```

Then use the runbook in `docs/PERFORMANCE.md` for baseline/candidate capture and
A/B comparison.

## Generated Files

Generated projects, DerivedData, result bundles, app bundles, logs, and local
tool-state folders are ignored by `.gitignore`.

If a generated file needs to become source-controlled, document why in the pull
request and keep it free of local paths.

## Documentation Updates

When behavior changes, update the most specific public doc in the same change:

- Architecture and subsystem boundaries: `docs/ARCHITECTURE.md`.
- Build and local setup: `docs/DEVELOPMENT.md`.
- Test commands and artifact handling: `docs/TESTING.md`.
- Performance capture or thresholds: `docs/PERFORMANCE.md`.
- Permission, plugin, update, or release trust boundaries: `SECURITY.md`.
