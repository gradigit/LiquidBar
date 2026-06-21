# Contributing

LiquidBar is a SwiftPM-first macOS project. Use the checked-in source tree as
the source of truth; do not import generated work logs or local machine state
into commits.

## Setup

Required tools:

- macOS 26 or newer
- Swift 6.2 or newer
- Xcode command line tools
- XcodeGen for UI test project generation
- `jq` for UI result classification

Install helper tools with Homebrew if needed:

```sh
brew install xcodegen
brew install jq
```

## Development Loop

Start with a clean branch:

```sh
git checkout main
git pull --ff-only
git switch -c <branch-name>
```

Run the fast validation loop:

```sh
swift test -c debug
```

For changes involving the app bundle, panels, thumbnails, or UI automation, also
read [docs/TESTING.md](docs/TESTING.md).

For performance-sensitive changes, capture a baseline and candidate run using
[docs/PERFORMANCE.md](docs/PERFORMANCE.md) before claiming an improvement.

For changes involving Accessibility, ScreenCaptureKit, global hotkeys, update
checks, login items, plugin/provider loading, or release automation, read
[SECURITY.md](SECURITY.md) and update it if the permission or trust boundary
changes.

## Commit Hygiene

- Keep changes focused.
- Do not commit local build products, generated projects, crash logs, machine
  paths, or tool-state folders.
- Do not paste historical transcripts or private working notes into public docs.
- If prior work contains useful conclusions, rewrite them as current,
  source-grounded documentation.
- Prefer GitHub issues or small markdown docs for public planning.

## Pull Request Checklist

- `swift test -c debug` passes locally.
- Performance-sensitive changes include baseline/candidate evidence or explain
  why runtime measurement was not applicable.
- GitHub Actions CI passes.
- User-facing behavior changes update README or docs.
- Permission-sensitive behavior changes update `SECURITY.md`.
- New files are intentional and pass a marker scan for local paths and private
  working notes.
