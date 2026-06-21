# Switcher Rewrite Research

Date: 2026-06-21

## Question

How should LiquidBar rewrite the keyboard switcher so it feels closer to
Windows Alt-Tab while remaining Apple-native, Liquid Glass-aligned, and
measurably performant?

## Current Source Findings

- Keep the hotkey capture core. Cmd-Tab is system-reserved, so the existing
  `CGEventTap` + Input Monitoring path is still the right implementation route.
- Keep ScreenCaptureKit as the thumbnail foundation. The current
  `SCScreenshotManager.captureImage` implementation is the modern public API
  path for static window thumbnails.
- Rewrite the switcher presentation layer. The current panel is a horizontal
  stack of small cards. It is functional, but it does not yet express the
  original large-thumbnail Alt-Tab idea.
- Treat Cmd-Shift-Tab as reverse traversal for the primary Cmd-Tab shortcut,
  not as a second user-facing keybind. This matches the expected switcher
  convention and avoids preferences complexity.

## 2026 Apple Research

Sources checked:

- Apple Developer: Platforms State of the Union 2026
- Apple Developer: Modernize your AppKit app
- Apple Developer: Use SwiftUI with AppKit and UIKit
- Apple Developer: WWDC25 Liquid Glass sessions and docs
- Apple Developer: ScreenCaptureKit sessions and docs

Findings:

- macOS 27 refines Liquid Glass with stronger system-managed diffusion,
  darker edge treatment, brighter specular highlights, and user-adjustable
  glass tinting. LiquidBar should rely more on system glass and reduce custom
  opaque fills where possible.
- AppKit on macOS 27 adds more Liquid Glass-native behavior, including subtle
  interactive glass click response and concentric corner configuration for
  child views. LiquidBar should use `#available(macOS 27, *)` paths once the
  SDK is available, while keeping the macOS 26 baseline intact.
- macOS 27 supports stronger border/accessibility affordances in more places.
  Visual QA should cover reduce transparency, reduce motion, increased
  contrast, and show-borders behavior.
- Apple is encouraging incremental SwiftUI adoption inside AppKit apps. A
  SwiftUI-hosted switcher carousel is reasonable to prototype, but it must be
  benchmarked against an AppKit/Core Animation version before choosing it.
- No newer Apple API was found that replaces ScreenCaptureKit for third-party
  window thumbnails. The optimization problem remains sizing, scheduling,
  caching, and optional short-lived low-FPS live previews.

## Skill Evaluation

The installed LiquidBar development-loop skill should be refreshed before it is
used as an authoritative runbook:

- It recommends `swift test`, while current repo docs require
  `swift test -c debug`.
- It references older testing doc paths that are not the current docs layout.
- It assumes an older macOS environment.
- It warns broadly against adding global input hooks, but LiquidBar now has an
  accepted, tested Cmd-Tab `CGEventTap` path for the switcher.
- It does not mention the performance baseline/candidate/A-B workflow in
  `docs/PERFORMANCE.md`.

Do not update the user-local skill from inside this repo-bound task. If skill
maintenance is authorized separately, update it to point to the current docs,
macOS 26/27 split, Cmd-Tab Input Monitoring behavior, visual QA expectations,
and performance gates.

## Rewrite Candidates To Benchmark

Benchmark every option against the same deterministic scenario and the same real
ScreenCaptureKit scenario.

| Option | Rendering model | Thumbnail model | Why test it | Main risk |
| --- | --- | --- | --- | --- |
| A | AppKit `NSCollectionView` carousel | Static `SCScreenshotManager` large selected + medium neighbors | Best fit with current retained AppKit architecture | Layout churn if cells are rebuilt instead of reused |
| B | Custom AppKit/Core Animation layer carousel | Static `SCScreenshotManager` | Lowest animation overhead and most control | More custom layout code |
| C | SwiftUI `NSHostingView` carousel | Static `SCScreenshotManager` | Fastest path to modern animations and future glass APIs | Unknown diffing/layout cost under rapid cycling |
| D | AppKit carousel | Selected-window short-lived low-FPS `SCStream`, static neighbors | Closest to live Alt-Tab feel | Stream startup, memory, and WindowServer cost |

Initial recommendation: build Option A first, prototype B only if layout or
animation metrics are weak, and treat D as an experiment behind a setting.

## Benchmark Plan

Add benchmark hooks before the rewrite:

- Open switcher with deterministic injected windows.
- Cycle forward N times.
- Cycle backward N times.
- Close without commit.
- Commit selected window.
- Record switcher-open latency, cycle latency, selected-card scroll/center
  latency, first thumbnail delivery, cache hit/miss, capture duration p50/p95,
  queue depth, dropped requests, and stale-image usage.

Benchmark scenarios:

- 8 windows, warm cache.
- 24 windows, warm cache.
- 24 windows, cold cache.
- 80 windows, icon-only far items.
- Mixed landscape/portrait/tall windows.
- Hidden/minimized windows with last-good fallback.
- Reduce motion.
- Reduce transparency.
- Increased contrast / show borders.

Acceptance targets for the first rewrite:

- Switcher opens with a visible selected card before thumbnails finish.
- Warm selected thumbnail appears immediately from cache or last-good image.
- Cold selected thumbnail is prioritized ahead of neighbor/far work.
- Repeated Cmd-Tab and Cmd-Shift-Tab keep the selected card centered or visibly
  in focus.
- Active-animation performance passes the existing FPS gate when enabled.
- No material regression in poll/render p95 in the A-B comparator.

## Design Direction

- Make the selected window the hero: large thumbnail, app icon, app name, and
  title.
- Use neighboring thumbnails as context, not equal-weight cards.
- Hide the horizontal scroller; use edge fades and selected-card centering.
- Remove the utility title text from the panel.
- Use one main glass surface, then subtle fills/rings on top. Avoid stacking
  glass cards inside a glass panel.
- Use a small selected-card lift/scale/ring animation and respect reduce motion.
- Prefer system glass behavior and macOS 27 APIs behind availability gates once
  available.

## Decision

Proceed in this order:

1. Add deterministic switcher benchmark/test-control hooks.
2. Capture baseline metrics for the current switcher.
3. Build the AppKit collection/carousel rewrite with static large thumbnails.
4. Run A-B comparison against baseline.
5. Prototype SwiftUI and live-preview variants only if they have a measurable
   chance to improve the selected metrics.
