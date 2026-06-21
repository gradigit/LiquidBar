# Architecture

LiquidBar is a native macOS window bar. The package builds one executable target
and one Swift Testing target.

## Package Shape

- `Package.swift`: SwiftPM package definition.
- `Sources/LiquidBar`: app source.
- `Tests/LiquidBarTests`: unit and integration tests.
- `UITests`: XCUITest suite and screenshot baselines.
- `XcodeGen/project.yml`: generated Xcode project spec for UI tests.
- `scripts`: build, UI test, screenshot, and performance helpers.
- `docs`: public-safe contributor, architecture, testing, and maintainer docs.

## Runtime Flow

1. `LiquidBarApp` handles CLI-only invocations before starting AppKit.
2. `AppDelegate` loads config, creates panels, starts the event loop, installs
   screen-change observers, and owns menu/status integration.
3. `Config` loads user settings and persisted state from the config directory.
4. `WindowManager` and `WindowStateStore` build the current window inventory,
   display assignment, ordering, hidden/minimized state, and tab group state.
5. `EventLoop` coordinates state updates, focus changes, thumbnails, plugins,
   hotkeys, and UI refreshes.
6. `UI` owns panels, overlays, previews, plugin cards, tab group overlays, and
   the optional keyboard switcher.
7. `Renderer` turns bar data into retained AppKit/Core Animation state.
8. `Services` wraps system integration such as accessibility, hotkeys, icons,
   login items, plugins/providers, thumbnails, logs, updates, and performance
   metrics.

## Source Responsibilities

- `Sources/LiquidBar/App`: lifecycle, status/menu actions, and CLI helpers such
  as `--print-default-config`.
- `Sources/LiquidBar/Config`: config schema, custom item schema, tab groups, and
  persisted user state.
- `Sources/LiquidBar/EventLoop`: command handling, switcher sessions, thumbnail
  capture policy, plugin/provider refresh, and UI synchronization.
- `Sources/LiquidBar/Renderer`: retained native rendering snapshots and layer
  updates.
- `Sources/LiquidBar/Services`: macOS integration, plugin discovery, provider
  runtime, release update checks, performance logging, and test-control support.
- `Sources/LiquidBar/Settings`: AppKit settings window and live-apply behavior.
- `Sources/LiquidBar/UI`: panels, native bar views, previews, popovers,
  switcher UI, glass styling, and item composition.
- `Sources/LiquidBar/Window`: CGWindow/AX-backed inventory, state store, display
  assignment, and stable test window lists.

## Rendering Model

The production surface is retained AppKit/Core Animation. LiquidBar avoids a
permanent full-surface GPU render loop. This keeps idle work low and makes UI
updates event-driven where system APIs allow it.

Rendering-sensitive code lives primarily in:

- `Sources/LiquidBar/Renderer/NativeBarRenderer.swift`
- `Sources/LiquidBar/UI/NativeBarView.swift`
- `Sources/LiquidBar/UI/LiquidBarPanel.swift`
- `Sources/LiquidBar/UI/PanelManager.swift`

Rendering changes should preserve stable dimensions for bar items, avoid layout
churn when only runtime state changes, and keep idle display-link work low.

## Windowing Model

LiquidBar creates per-display panels and keeps app/window state separate from
rendering state. Window movement, display changes, fullscreen transitions, and
screen parameter changes are handled as state changes first, then rendered from
a fresh snapshot.

Windowing-sensitive code lives primarily in:

- `Sources/LiquidBar/Window/WindowManager.swift`
- `Sources/LiquidBar/Window/WindowStateStore.swift`
- `Sources/LiquidBar/Services/AXObserverService.swift`
- `Sources/LiquidBar/Services/AccessibilityService.swift`
- `Sources/LiquidBar/Services/SpacesService.swift`

Accessibility APIs are used for permission-gated window focus, close, minimize,
unminimize, and window adjustment operations. Core Graphics is used for window
inventory. ScreenCaptureKit is used for static preview thumbnails.

## Interaction Model

Bar commands are routed through `Command` and handled by `EventLoop`. Clicks,
context actions, reorder gestures, config reloads, switcher actions, and plugin
provider actions should update state first and then request a renderer sync.

Global keyboard shortcuts use Carbon hotkeys when possible. Cmd-Tab style
shortcuts require a CGEventTap because macOS intercepts them before Carbon
hotkeys fire.

## Plugins And Providers

Plugins are opt-in and loaded from `Plugins` under the active config directory
when `plugins_enabled` is true. The manifest API version is currently `1`.
Plugin custom items and tiles are namespaced by plugin id before being rendered.

Provider-backed tiles use `ProviderRuntime`. Provider state is timeout-bounded,
circuit-breaker protected, and normalized before display so untrusted or broken
providers cannot flood the UI with oversized titles, subtitles, or action lists.

XPC providers are supported through declared Mach service names. Changes that
expand provider transport or trust boundaries should update `SECURITY.md`.

## Configuration and State

By default, LiquidBar stores config under:

```text
~/Library/Application Support/LiquidBar/config.json
```

During tests and local development, set `LIQUIDBAR_CONFIG_DIR` to isolate config
and state from the real user profile.

CLI helpers:

```sh
swift run LiquidBar -- --print-config-path
swift run LiquidBar -- --print-default-config
swift run LiquidBar -- --write-default-config
```

`ConfigFileWatcher` reloads manual config edits when live apply is enabled.

## Release And Update Model

`Updater` checks GitHub release metadata from `gradigit/LiquidBar` and only
opens trusted release URLs under
`https://github.com/gradigit/LiquidBar/releases/tag/...`. CI uses pinned GitHub
Actions references.

## Design Constraints

- Keep idle CPU low.
- Prefer documented macOS APIs and fail closed when system information is not
  available.
- Avoid broad polling when a notification, observer, or explicit invalidation
  path can drive the update.
- Keep UI tests isolated from real user config.
- Do not commit local machine state or generated test artifacts.
- Keep docs public-safe: no local session transcripts, prompt text, private
  paths, or generated handoff state.
