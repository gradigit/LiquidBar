# Development

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
- Automation prompts when running UI tests through Xcode.

Use the stable test app bundle from `scripts/build_test_app.sh` so macOS privacy
settings attach to a stable app identity.

## Local Config Isolation

Set `LIQUIDBAR_CONFIG_DIR` when testing config or state changes:

```sh
LIQUIDBAR_CONFIG_DIR="$(mktemp -d)" swift run LiquidBar
```

Do not use tests to mutate the real user config directory.

## Generated Files

Generated projects, DerivedData, result bundles, app bundles, logs, and local
tool-state folders are ignored by `.gitignore`.

If a generated file needs to become source-controlled, document why in the pull
request and keep it free of local paths.
