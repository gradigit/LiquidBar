# Release

This is the v1 release checklist for maintainers. It is intentionally separate
from the local test-app path so official artifacts do not inherit the
`LiquidBar Test` identity.

## Readiness Gate

Before tagging a release candidate:

```sh
git status --short --branch
swift test -c debug
```

For UI, windowing, permissions, or rendering changes, also run:

```sh
./scripts/run_all_tests.sh
```

For performance-sensitive changes, capture a baseline/candidate pair with
`docs/PERFORMANCE.md` and keep only the durable summary in release notes or a
tracked research note. Do not commit raw logs or local benchmark artifacts.

## Build The App Bundle

Build a release-mode app bundle:

```sh
LIQUIDBAR_RELEASE_VERSION=1.0.0 ./scripts/build_release_app.sh
```

This writes:

```text
build/release/LiquidBar.app
build/release/LiquidBar-1.0.0.zip
```

Without `LIQUIDBAR_CODESIGN_IDENTITY`, the script ad-hoc signs the bundle for
local inspection only. Public releases must use a Developer ID Application
identity:

```sh
LIQUIDBAR_RELEASE_VERSION=1.0.0 \
LIQUIDBAR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
./scripts/build_release_app.sh
```

## Signing And Notarization

Inspect the signed bundle:

```sh
codesign -dvvv --entitlements :- build/release/LiquidBar.app
codesign --verify --strict --verbose=2 build/release/LiquidBar.app
spctl -a -vv --type execute build/release/LiquidBar.app
```

Submit the zip for notarization with the project Apple Developer account:

```sh
xcrun notarytool submit build/release/LiquidBar-1.0.0.zip \
  --keychain-profile "<notary-profile>" \
  --wait
```

After notarization succeeds:

```sh
xcrun stapler staple build/release/LiquidBar.app
spctl -a -vv --type execute build/release/LiquidBar.app
ditto -c -k --keepParent build/release/LiquidBar.app build/release/LiquidBar-1.0.0-notarized.zip
```

Attach only the notarized archive to the GitHub release.

## Release Notes

Release notes should include:

- supported macOS and Swift versions
- new user-facing features and default hotkeys
- permission explanations for Accessibility, Screen Recording, and Input
  Monitoring
- known limitations or experimental features
- the validation commands that passed

Do not publish `LiquidBar Test.app` as an official release artifact.
