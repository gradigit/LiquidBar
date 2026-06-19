# LiquidBar

LiquidBar is a native macOS window bar built with Swift, AppKit panels, retained Core Animation layers, and system accessibility APIs.

## Requirements

- macOS 26 or newer
- Swift 6.2 or newer
- Accessibility permission for window management features

## Build

```sh
swift build
```

## Test

```sh
swift test -c debug
```

## Run

```sh
swift run LiquidBar
```

Configuration is stored in `~/Library/Application Support/LiquidBar/config.json`.
Set `LIQUIDBAR_CONFIG_DIR` during development or tests to isolate config and state files.

## Test App Bundle

```sh
./scripts/build_test_app.sh
open -a "$HOME/Applications/LiquidBar Test.app"
```

## Architecture

- `Sources/LiquidBar/App`: application lifecycle and command-line entry points
- `Sources/LiquidBar/Config`: user configuration, custom items, tab groups, and persisted state
- `Sources/LiquidBar/EventLoop`: event coordination and UI update flow
- `Sources/LiquidBar/Renderer`: retained native layout and layer rendering
- `Sources/LiquidBar/Services`: accessibility, hotkeys, icons, plugins, thumbnails, and system helpers
- `Sources/LiquidBar/UI`: panels, native views, previews, and switcher UI
- `Sources/LiquidBar/Window`: window inventory, state, and ordering

The production surface is retained AppKit/Core Animation. It does not use a permanent full-surface GPU render loop.

## Documentation

- `CONTRIBUTING.md`: contribution workflow
- `docs/START_HERE.md`: fresh-session onboarding packet
- `docs/ARCHITECTURE.md`: source map and runtime flow
- `docs/DEVELOPMENT.md`: local setup and common development commands
- `docs/TESTING.md`: SwiftPM, UI, visual regression, and performance test flows
- `docs/MAINTAINER_NOTES.md`: repository hygiene and documentation policy

## License

LiquidBar is released under the MIT License. See `LICENSE`.
