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

## Runtime Flow

1. `App` starts the application and owns top-level lifecycle.
2. `Config` loads user settings and persisted state.
3. `Window` builds a current inventory of windows and their display assignment.
4. `EventLoop` coordinates state updates, focus changes, thumbnails, plugins,
   and UI refreshes.
5. `UI` owns panels, overlays, previews, and interaction surfaces.
6. `Renderer` turns bar data into retained AppKit/Core Animation state.
7. `Services` wraps system integration such as accessibility, icons, login
   items, thumbnails, logs, and performance metrics.

## Rendering Model

The production surface is retained AppKit/Core Animation. LiquidBar avoids a
permanent full-surface GPU render loop. This keeps idle work low and makes UI
updates event-driven where system APIs allow it.

Rendering-sensitive code lives primarily in:

- `Sources/LiquidBar/Renderer/NativeBarRenderer.swift`
- `Sources/LiquidBar/UI/NativeBarView.swift`
- `Sources/LiquidBar/UI/LiquidBarPanel.swift`
- `Sources/LiquidBar/UI/PanelManager.swift`

## Windowing Model

LiquidBar creates per-display panels and keeps app/window state separate from
rendering state. Window movement, display changes, fullscreen transitions, and
screen parameter changes should be handled as state changes first, then rendered
from a fresh snapshot.

Windowing-sensitive code lives primarily in:

- `Sources/LiquidBar/Window/WindowManager.swift`
- `Sources/LiquidBar/Window/WindowStateStore.swift`
- `Sources/LiquidBar/Services/AXObserverService.swift`
- `Sources/LiquidBar/Services/AccessibilityService.swift`
- `Sources/LiquidBar/Services/SpacesService.swift`

## Configuration and State

By default, LiquidBar stores config under:

```text
~/Library/Application Support/LiquidBar/config.json
```

During tests and local development, set `LIQUIDBAR_CONFIG_DIR` to isolate config
and state from the real user profile.

## Design Constraints

- Keep idle CPU low.
- Prefer documented macOS APIs and fail closed when system information is not
  available.
- Avoid broad polling when a notification, observer, or explicit invalidation
  path can drive the update.
- Keep UI tests isolated from real user config.
- Do not commit local machine state or generated test artifacts.
