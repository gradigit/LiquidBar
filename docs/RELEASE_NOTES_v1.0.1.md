# LiquidBar v1.0.1

LiquidBar v1.0.1 is a patch release focused on stability, visual polish, and
release-readiness after the first public `v1.0.0` build.

## Fixes And Polish

- Keeps LiquidBar out of the way during fullscreen apps and fullscreen video.
- Hardens display reconnect handling so the bar restores itself without
  unnecessarily displacing normal windows.
- Improves experimental window layout memory for display changes while keeping
  it opt-in.
- Fixes hidden-window taskbar handling so the in-place dimmed option remains
  visible when configured.
- Keeps the selected taskbar highlight synchronized while window items are
  dragged.
- Reduces thumbnail memory pressure with explicit cleanup and bounded caching.
- Refines preferences alignment and release-facing documentation.

## Documentation

- Updates the English and Korean README files for the `v1.0.1` release line.
- Clarifies the unsigned/ad-hoc build path versus local Apple Development
  signing in the release checklist.
- Adds these release notes as the canonical notes file for the GitHub release.

## Distribution

The attached DMG is an unsigned/ad-hoc build. macOS Gatekeeper may warn because
Developer ID signing and notarization are not enabled yet. The source code,
release process, and permission model are documented in the repository so users
can inspect or build the app themselves.

## Validation

- `swift test -c debug`
- `LIQUIDBAR_RUN_ID=release-v1.0.1 ./scripts/run_all_tests.sh`
  - UI classification: PASS
  - 24 UI tests passed
  - 1 opt-in system integration test skipped unless `LIQUIDBAR_SYSTEM_E2E=1`
- Release app bundle build with `LIQUIDBAR_CODESIGN_IDENTITY=-`
- `codesign --verify --strict --verbose=2 build/release/LiquidBar.app`
- `hdiutil verify build/release/LiquidBar-1.0.1.dmg`

## Known Limitations

- Developer ID signing and notarization are still pending.
- Sidebar mode and provider plugins remain experimental.
- Per-Space pinning remains experimental because macOS does not expose a public,
  fully reliable Spaces API for this use case.
