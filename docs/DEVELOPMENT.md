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

Build a local release-mode app bundle:

```sh
./scripts/build_release_app.sh
open build/release/LiquidBar.app
```

Build, install, and relaunch the real app from a stable local path:

```sh
./scripts/install_and_launch_release_app.sh
```

Use this helper for day-to-day manual QA. It installs to
`~/Applications/LiquidBar.app` by default and refuses ad-hoc signing unless
`LIQUIDBAR_ALLOW_ADHOC_INSTALL=1` is set, because ad-hoc rebuilds can make macOS
privacy permissions look stale after each rebuild.

Inspect or initialize config:

```sh
swift run LiquidBar -- --print-config-path
swift run LiquidBar -- --print-default-config
swift run LiquidBar -- --write-default-config
```

Build the stable developer test bundle when you need to reset or preserve macOS
privacy permissions independently from the release identity:

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

Use `scripts/build_release_app.sh` for release-candidate checks. Use the stable
install/relaunch flow from `scripts/install_and_launch_release_app.sh` for
manual QA against the real app identity. Use the stable test app bundle from
`scripts/build_test_app.sh` only when you need a separate developer identity for
repeated privacy-permission testing.

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

For local hang/debug sessions, turn on Preferences -> Advanced -> Diagnostics ->
Hang diagnostics. If preferences are inaccessible, use the launch environment
escape hatch before launching the app:

```sh
launchctl setenv LIQUIDBAR_DEV_DIAGNOSTICS 1
./scripts/build_release_app.sh
open build/release/LiquidBar.app
```

Manual unified-log checks need `--info` to include the aggregate diagnostics:

```sh
log show --last 2m --info --predicate 'subsystem == "com.liquidbar" AND category == "perf"'
```

After the capture, clear it so normal app launches stay quiet:

```sh
launchctl unsetenv LIQUIDBAR_DEV_DIAGNOSTICS
```

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
- Release packaging, signing, and notarization: `docs/RELEASE.md`.
- Permission, plugin, update, or release trust boundaries: `SECURITY.md`.
