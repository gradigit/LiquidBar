# Korean Localization

Date: 2026-06-24

## Question

How should LiquidBar add Korean localization for the v1 AppKit/SwiftPM app
without breaking release packaging or test stability?

## Sources

- Apple Developer Documentation: [Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- Apple Developer Documentation: [Localizing package resources](https://developer.apple.com/documentation/xcode/localizing-package-resources)
- Apple Developer Documentation: [Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)
- WWDC20: [Swift packages: Resources and localization](https://developer.apple.com/videos/play/wwdc2020/10169/)
- WWDC23: [Discover String Catalogs](https://developer.apple.com/videos/play/wwdc2023/10155/)
- WWDC25: [Code-along: Explore localization with Xcode](https://developer.apple.com/videos/play/wwdc2025/225/)

## Findings

- Apple’s current Xcode guidance favors String Catalogs, especially for larger
  projects and translator handoff. LiquidBar is currently a SwiftPM-first,
  mostly programmatic AppKit app, so a full String Catalog migration would touch
  most UI construction code without adding immediate runtime coverage.
- Swift package localization depends on localized resources being processed into
  the package resource bundle and then loaded from that bundle. Using
  `Bundle.main` alone would work poorly for SwiftPM tests and can fail once the
  executable is wrapped into a manually assembled `.app`.
- Release packaging must copy the generated SwiftPM resource bundle into
  `Contents/Resources`; otherwise localization can pass `swift test` and still be
  absent from the distributed app.
- Tests should compare against the localized helper where they assert visible UI
  text. Otherwise, a Korean macOS test environment can fail with correct Korean
  strings.

## Translation Review

- Kept product names, hotkey examples, bundle IDs, filenames, and metric
  acronyms literal: `LiquidBar`, `config.json`, `option+tab`, CPU/GPU/RAM/TEMP.
- Used Korean macOS-facing terminology for common UI actions:
  "환경설정", "설정 열기", "화면 기록", "입력 모니터링", "Finder에서 보기".
- Preferred concise control labels to protect the existing fixed-width AppKit
  layout.
- Translated status/fallback strings that users can see in menus, update alerts,
  permissions, provider tiles, and system indicators.

## Decision

Use a small `L10n` helper backed by SwiftPM package resources:

- `Sources/LiquidBar/Resources/en.lproj/Localizable.strings`
- `Sources/LiquidBar/Resources/ko.lproj/Localizable.strings`
- `Package.swift` with `defaultLocalization: "en"` and processed resources
- release script validation that copies `LiquidBar_*.bundle` into the app bundle

String Catalog migration remains a reasonable follow-up once the UI stabilizes
or translator handoff becomes a release requirement.
