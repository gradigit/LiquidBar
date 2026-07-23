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

The normal direction is system events and user commands -> `EventLoop` state
and update decisions -> renderer snapshot -> `PanelManager`/`NativeBarView`
application. UI interactions should return through `Command` instead of making
independent mutations to window or rendering state.

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

## Change Guide

Use this as a starting map, then inspect the implementation and focused tests
before editing. A filename is not a complete ownership boundary.

| Change | Start with | Focused tests |
| --- | --- | --- |
| Startup, shutdown, permissions, menu/status integration | `App/AppDelegate.swift` | `AppDelegatePermissionTests.swift` |
| Config, persisted state, custom items | `Config/` | `ConfigTests.swift`, `UserStateTests.swift`, `CustomItemTests.swift` |
| Commands, refresh cadence, focus, switcher sessions | `EventLoop/EventLoop.swift`, `Command.swift`, `SwitcherHotkeySession.swift` | `EventLoop*Tests.swift`, `SwitcherSessionStateTests.swift` |
| Window inventory, filtering, identity, retained state | `Window/WindowManager.swift`, `WindowServerSurface.swift`, `WindowSurfaceClassifier.swift`, `WindowLogicalIdentity.swift`, `WindowStateStore.swift` | `WindowManagerAXGatingTests.swift`, `WindowServerSurfaceTests.swift`, `WindowStateStoreTests.swift` |
| Accessibility actions, observers, Spaces | `Services/AccessibilityService.swift`, `AXObserverService.swift`, `SpacesService.swift` | `AccessibilityService*Tests.swift`, `AXObserverServiceTests.swift`, `SpacesServiceCurrentSpaceInfoTests.swift` |
| Experimental display-layout recovery | `Services/WindowLayoutMemoryService.swift`, `Services/AccessibilityService.swift`, `EventLoop/EventLoop.swift` | `WindowLayoutMemoryServiceTests.swift`, `AppDelegatePermissionTests.swift` |
| Panels, drag, previews, switcher UI | `UI/PanelManager.swift`, `NativeBarView.swift`, preview and switcher panels | `PanelManager*Tests.swift`, `NativeBarView*Tests.swift`, `DragLifecycleTests.swift`, `WindowSwitcherPanelTests.swift` |
| Retained layout and rendering | `Renderer/NativeBarRenderer.swift` | `NativeBarRenderer*Tests.swift` |
| Thumbnail capture, scheduling, and retention | `Services/WindowThumbnailService.swift` | `WindowThumbnail*Tests.swift`, `EventLoopThumbnailIntegrationTests.swift` |

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

Window thumbnails are static, memory-only ScreenCaptureKit images. Requests are
keyed by window and size tier, coalesced through a priority scheduler, and
bounded to two in-flight captures and 24 queued requests by default. Larger
cached tiers may satisfy smaller requests; stale and last-known-good images can
be shown while an asynchronous refresh runs. Memory pressure removes large
entries and queued prewarm work. Do not add disk thumbnail persistence because
captured windows can contain private content.

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

### Experimental Display-Layout Recovery

`WindowLayoutMemoryService` is active only when **Remember window layouts after
display changes** is enabled; applying a saved frame requires Accessibility
access. It keeps a memory-only baseline of eligible windows on stable
multi-display topologies. When display reconfiguration begins, the baseline
becomes recovery-pending and cannot be replaced by transient single-display or
partially connected states.

After the original display UUIDs and compatible geometry return and remain
stable, `EventLoop` schedules bounded restore passes. Window matching prefers
the captured process and window identifier, then a unique same-process title.
A unique bundle-and-title match may bridge an app process restart only during
the first 30 minutes; the stricter original-process matches and the pending
topology baseline remain eligible across longer disconnects. Restored frames
are translated relative to the target display and clamped to its current
bounds.

The baseline is not written to disk. It cannot survive a LiquidBar relaunch,
recreate closed windows, or restore a window whose original display is still
missing. Diagnostic events record aggregate snapshot identifiers, ages,
outcomes, and fallback policy without window titles or application content.

## Runtime Cadence And Expensive Boundaries

`EventLoop` is main-actor isolated. Its timer wakes every 0.2 seconds in normal
operation and every 0.1 seconds while dragging, but a wake does not always
enumerate windows. A full inventory currently runs when forced, while dragging,
after a relevant event marks the inventory dirty, or when the 0.8-second
fallback interval expires. Every debounced AX event batch schedules an
inventory refresh; only batches that require it invalidate the enumeration
caches.

`WindowManager.enumerate` performs an on-screen WindowServer pass and may
perform a separately cached off-screen pass for hidden or minimized windows.
Off-screen candidates require reliable Space information and AX confirmation
where ambiguity would otherwise include compositor surfaces. The result then
passes through title completion, surface classification, logical identity
deduplication, and retained state.

Some correctness paths add more system work around that inventory:

- fullscreen suppression performs a raw on-screen WindowServer pass so
  untracked full-display surfaces can still hide the bar;
- taskbar window adjustment can perform another WindowServer/AX scan when the
  feature is enabled and its trigger interval is due;
- switcher prewarm is considered after each inventory, although a content
  signature prevents unchanged window sets from scheduling new thumbnail work;
- an actual thumbnail miss reaches `SCScreenshotManager.captureImage`, which can
  add work in system capture and compositing processes even when LiquidBar's own
  callback is asynchronous.

These paths favor correctness under Spaces, fullscreen, hidden-window, and
display-transition edge cases. Changes must measure call frequency and host
impact, not only the duration of one LiquidBar callback. See
`docs/PERFORMANCE.md`.

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
