# LiquidBar

[한국어](README.ko.md)

![LiquidBar wordmark](Assets/Brand/liquidbar-brand-bar-transparent.png)

**An open-source Liquid Glass taskbar and Cmd-Tab window switcher for macOS.**

LiquidBar gives Mac power users the window control they keep missing: a real
taskbar, large window thumbnails, Windows Alt-Tab style switching, system
indicators, and deep configuration without taking over macOS.

## Open By Design

Many macOS taskbar utilities are closed source while asking for Accessibility,
Screen Recording, or Input Monitoring permissions. LiquidBar takes the opposite
approach: the code is inspectable, the release path is documented, and the
permission-sensitive pieces are kept small enough to review, build, and disable.

LiquidBar is for users who want:

- a real taskbar on macOS, including hidden and minimized windows
- a Windows Alt-Tab style switcher with macOS Cmd-Tab muscle memory
- large window thumbnails and click-to-select switching
- a bar that visually belongs on modern macOS instead of fighting it
- configuration that can be edited, tested, and extended
- an open foundation for future plugins such as media controls

## Highlights

### Cmd-Tab, But Window-First

![LiquidBar Cmd-Tab switcher animation](Assets/Screenshots/cmd-tab-switcher.gif)

LiquidBar turns Cmd-Tab into a window switcher: large thumbnails, MRU
back-and-forth behavior, Cmd-Shift-Tab reverse traversal, click-to-select, and
aspect-aware cards for wide, square, and portrait windows.

### A Taskbar That Belongs On macOS

![LiquidBar taskbar modes](Assets/Brand/liquidbar-taskbar-showcase-zoom.png)

LiquidBar supports labeled windows, icon-only mode, app grouping, pinned apps,
custom items, launcher/search entries, and per-display panels. The v1 default
is an icon-first 32 px bottom bar with Liquid Glass styling.

### Right-Click Controls

<img src="Assets/Screenshots/taskbar-context-menu.png" alt="LiquidBar taskbar right-click menu" width="260">

Right-click a window to rename it, apply a color, close it, pin it, hide it
from the bar, reload config, or open preferences. Window actions stay at the
top; app controls stay at the bottom.

### System Indicators

![LiquidBar system indicators](Assets/Brand/liquidbar-system-indicators-showcase.png)

CPU, GPU, memory, and thermal indicators can live inside the bar with compact,
dense, graph, underline, or minimal presentations. Indicators are configurable
by metric, color, placement, display scope, refresh interval, and visual style.

### Preferences

<img src="Assets/Screenshots/preferences-appearance.png" alt="LiquidBar appearance preferences" width="560">

Most v1 behavior can be tuned without editing JSON by hand: bar size, icon
size, glass style, hover intensity, visual depth, animations, indicators,
multi-monitor behavior, language, previews, permissions, diagnostics, and plugins.

## Features

- **Native taskbar:** bottom, top, left, and right AppKit panels with retained
  Core Animation rendering rather than a permanent full-surface render loop.
- **Window control:** focus, hide, minimize, close, cycle, group, and show
  hidden/minimized windows from the bar.
- **Context menus:** right-click taskbar items for focused window actions,
  pinning, hiding, config reload, preferences, and quit.
- **Keyboard switcher:** Cmd-Tab by default, Cmd-Shift-Tab for reverse
  traversal, click-to-select thumbnails, all-display scope, and MRU-style
  back-and-forth switching.
- **Large thumbnails:** static ScreenCaptureKit thumbnails optimized for quick
  switcher open time without continuous background capture.
- **Liquid Glass appearance:** native vibrancy/material backdrops, glass tile
  treatments, hover states, and focus indicators tuned for modern macOS.
- **System indicators:** CPU, GPU, RAM, and optional temperature readouts with
  multiple compact presentation modes.
- **Multi-monitor support:** choose all displays, main display only, or
  per-display window behavior.
- **Custom items:** pinned apps, files, folders, URLs, spacers, launcher items,
  and user-defined tab groups.
- **Stable pinned apps:** global pinned apps are the v1 default. Per-Space
  pinned apps remain experimental because macOS does not expose a public,
  fully reliable Spaces API for this use case.
- **Plugin groundwork:** experimental provider/plugin runtime for future
  extensibility, including media-control style tiles.

## Default Hotkeys And Controls

| Action | Default |
| --- | --- |
| Open switcher / next window | `Cmd-Tab` |
| Previous window in switcher | `Cmd-Shift-Tab` |
| Select hovered/clicked switcher item | Mouse click |
| Cycle windows from taskbar | Scroll wheel over the bar |
| Open preferences | Menu bar icon or taskbar context menu |

The switcher hotkey is configurable. If you do not want LiquidBar to intercept
Cmd-Tab, change `switcher_hotkey` or disable `switcher_enabled` in config.

## Permissions And Trust

LiquidBar can run with different feature sets, but the full taskbar/switcher
experience uses macOS privacy permissions:

- **Accessibility** is used for window actions such as focus, hide, minimize,
  close, and optional window resizing around the bar.
- **Screen Recording** is used to capture window thumbnails for previews and
  the switcher. LiquidBar uses static thumbnails, not a constant recording loop.
- **Input Monitoring** is used only when a global shortcut needs to intercept
  keystrokes before macOS handles them, especially Cmd-Tab.
- **Automation** may appear for optional provider/media-control actions that
  control another app.

Other system-facing features are narrower in scope: update checks read GitHub
release metadata from the canonical `gradigit/LiquidBar` repository, Launch at
Login uses a user-visible LaunchAgent, and Dock auto-hide changes the standard
macOS Dock preference only when that setting is enabled.

These permissions are powerful. The advantage here is that LiquidBar is open
source: you can inspect the code, build the app yourself, verify the release
artifact, and turn off features you do not use. That is a materially better
trust model than a closed-source taskbar requesting the same system access.

## Requirements

- macOS 26 or newer
- Swift 6.2 or newer for source builds
- Xcode command line tools

## Build And Run

Run from source:

```sh
swift build
swift test -c debug
swift run LiquidBar
```

Build the real release-mode app bundle locally:

```sh
LIQUIDBAR_CREATE_DMG=1 LIQUIDBAR_CREATE_ZIP=0 ./scripts/build_release_app.sh
open build/release/LiquidBar.app
```

The release builder can produce `build/release/LiquidBar-1.0.0.dmg` and applies
ad-hoc signing by default. Early GitHub binaries may be published this way when
they are clearly labeled as unsigned/ad-hoc; macOS Gatekeeper will warn until
Developer ID signing and notarization are added. See `docs/RELEASE.md`.

The developer test bundle still exists for local TCC reset/regrant workflows,
but it is not a release artifact:

```sh
./scripts/build_test_app.sh
open -a "$HOME/Applications/LiquidBar Test.app"
```

## Configuration

Configuration is stored in:

```text
~/Library/Application Support/LiquidBar/config.json
```

Useful config commands:

```sh
swift run LiquidBar -- --print-config-path
swift run LiquidBar -- --print-default-config
swift run LiquidBar -- --write-default-config
```

The v1 default config enables the icon-first taskbar, right-aligned system
indicators, Cmd-Tab switcher, all-display switcher scope, and Liquid Glass
styling. Developer performance logging is disabled by default.

Change the app language in **Preferences -> General -> System -> Language**.
Choose System, English, or Korean.

Set `LIQUIDBAR_CONFIG_DIR` during development or tests to isolate config and
state files:

```sh
LIQUIDBAR_CONFIG_DIR="$(mktemp -d)" swift run LiquidBar
```

## Documentation

- `CONTRIBUTING.md`: contribution workflow
- `SECURITY.md`: security reporting, permissions, and release trust model
- `docs/START_HERE.md`: fresh-session onboarding packet
- `docs/ARCHITECTURE.md`: source map and runtime flow
- `docs/DEVELOPMENT.md`: local setup and common development commands
- `docs/TESTING.md`: SwiftPM, UI, visual regression, and release-oriented test flows
- `docs/PERFORMANCE.md`: local performance capture and A/B comparison workflow
- `docs/RELEASE.md`: release packaging, signing, notarization, and notes
- `docs/MAINTAINER_NOTES.md`: repository hygiene and documentation policy

## Release Trust

Official update metadata and binary releases must come from:

```text
https://github.com/gradigit/LiquidBar/releases
```

Do not install release assets from similarly named repositories or package
mirrors unless they are explicitly linked from this repository. Official
artifacts should be traceable to the documented release process. Prefer signed
and notarized assets when available; unsigned/ad-hoc assets must be labeled.

## Status

LiquidBar v1 is the first public release line. Initial binaries may be ad-hoc
signed and clearly labeled unsigned/ad-hoc while Developer ID notarization
remains pending. Sidebar mode and provider plugins remain experimental and are
not part of the primary v1 showcase until their UX is release-grade.

## License

LiquidBar is released under the MIT License. See `LICENSE`.
