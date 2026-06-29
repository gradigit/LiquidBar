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

For UI, windowing, permissions, or rendering changes, also run the automated UI
suite when the local automation environment is healthy:

```sh
./scripts/run_all_tests.sh
```

If the Xcode UI harness is blocked by local permissions, hardware, or
environment-specific flake, do not treat that alone as product correctness
evidence. Capture a live visual QA pass against the real app instead, using
screenshots or video plus a short checklist covering taskbar rendering,
thumbnail previews, Cmd-Tab switching, preferences, menu bar behavior, and
permission prompts. Keep raw screenshots/videos as release artifacts only when
they are intentionally public-safe.

For performance-sensitive changes, capture a baseline/candidate pair with
`docs/PERFORMANCE.md` and keep only the durable summary in release notes or a
tracked research note. Do not commit raw logs or local benchmark artifacts.

## Build The App Bundle

Build a release-mode app bundle:

```sh
LIQUIDBAR_RELEASE_VERSION=1.0.1 \
LIQUIDBAR_CODESIGN_IDENTITY=- \
LIQUIDBAR_CREATE_DMG=1 \
LIQUIDBAR_CREATE_ZIP=0 \
./scripts/build_release_app.sh
```

This writes:

```text
build/release/LiquidBar.app
build/release/LiquidBar-1.0.1.dmg
```

Set `LIQUIDBAR_CODESIGN_IDENTITY=-` for an explicit unsigned/ad-hoc public
artifact. Without `LIQUIDBAR_CODESIGN_IDENTITY`, the script uses the first local
Apple Development signing identity when one is available, then falls back to
ad-hoc signing. An ad-hoc binary can be attached to an early GitHub release only
if the release notes clearly label it as unsigned/ad-hoc and mention that macOS
Gatekeeper will warn. The preferred public distribution path is a Developer ID
Application identity:

```sh
LIQUIDBAR_RELEASE_VERSION=1.0.1 \
LIQUIDBAR_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
./scripts/build_release_app.sh
```

## Signing And Notarization

Developer ID signing and notarization are preferred for public distribution, but
they are not required for an initial source-first or unsigned/ad-hoc release.
When they are unavailable, skip notarization and include the unsigned/ad-hoc
caveat in release notes.

Inspect the signed bundle:

```sh
codesign -dvvv --entitlements :- build/release/LiquidBar.app
codesign --verify --strict --verbose=2 build/release/LiquidBar.app
spctl -a -vv --type execute build/release/LiquidBar.app
```

Submit the DMG for notarization with the project Apple Developer account:

```sh
xcrun notarytool submit build/release/LiquidBar-1.0.1.dmg \
  --keychain-profile "<notary-profile>" \
  --wait
```

After notarization succeeds:

```sh
xcrun stapler staple build/release/LiquidBar.app
xcrun stapler staple build/release/LiquidBar-1.0.1.dmg
spctl -a -vv --type execute build/release/LiquidBar.app
hdiutil verify build/release/LiquidBar-1.0.1.dmg
```

When notarization is complete, attach the notarized archive to the GitHub
release and replace any unsigned/ad-hoc artifact.

## Release Notes

Release notes should include:

- supported macOS and Swift versions
- new user-facing features and default hotkeys
- permission explanations for Accessibility, Screen Recording, and Input
  Monitoring
- known limitations or experimental features
- the validation commands that passed
- whether the binary is unsigned/ad-hoc, Developer ID signed, or notarized

Do not publish `LiquidBar Test.app` as an official release artifact.
