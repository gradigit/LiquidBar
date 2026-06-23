# LiquidBar v1.0.0

LiquidBar v1.0.0 is the first public release of the open-source Liquid Glass
taskbar and Cmd-Tab window switcher for macOS.

## Highlights

- Native macOS taskbar with a 32 px icon-first default, Liquid Glass styling,
  previews, grouping, hidden/minimized window visibility, and configurable
  placement.
- Windows-style Cmd-Tab window switcher with large thumbnails, MRU
  back-and-forth behavior, Cmd-Shift-Tab reverse traversal, all-display scope,
  hover states, and click-to-select.
- Right-pinned system indicators for CPU, GPU, and memory by default, with
  configurable placement, metric visibility, refresh interval, and appearance.
- Preferences for bar sizing, icon sizing, menu bar visibility, switcher
  behavior, multi-monitor scope, diagnostics, permissions, and visual tuning.
- Release packaging now produces a real `LiquidBar.app` bundle and DMG instead
  of the local `LiquidBar Test.app` used for development.

## Privacy And Trust

LiquidBar asks for powerful macOS permissions only for features that need them:

- Accessibility: focus, hide, minimize, close, and optional window adjustment.
- Screen Recording: static window thumbnails for previews and the switcher.
- Input Monitoring: global shortcuts such as Cmd-Tab before macOS handles them.
- Automation: optional provider/media-control actions that control another app.

This release is open source, so the permission-sensitive code, release scripts,
and update path are inspectable. That is the main trust difference versus a
closed-source taskbar asking for the same system access.

## Distribution Status

The v1.0.0 DMG is ad-hoc signed and not notarized. macOS Gatekeeper will warn on
first launch. Developer ID signing and notarization are planned for a later
release once the project has the required signing identity.

Official releases and update metadata come only from:

https://github.com/gradigit/LiquidBar/releases

## Validation

- `swift test -c debug`
- `LIQUIDBAR_RUN_ID=release-v1-post-triage ./scripts/run_all_tests.sh`
- Live visual QA against the real app for taskbar layout, right-pinned system
  indicators, multi-monitor behavior, and Cmd-Tab switcher behavior.
