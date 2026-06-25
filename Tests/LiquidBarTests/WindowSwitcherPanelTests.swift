import AppKit
@testable import LiquidBar
import Testing

@Suite("WindowSwitcherPanel", .serialized)
@MainActor
struct WindowSwitcherPanelTests {
    @Test func updateKeepsSelectedEntryVisible() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .compactShelf)
        defer { panel.close() }

        panel.setFrame(NSRect(x: 0, y: 0, width: 520, height: 226), display: false)
        panel.update(entries: Self.entries(count: 20), selectedIndex: 12)

        #expect(panel.debugOrderedWindowIds().count == 20)

        let selectedFrame = try #require(panel.debugEntryFrame(windowId: 13))
        let visibleRect = panel.debugDocumentVisibleRect()

        #expect(selectedFrame.minX >= visibleRect.minX - 1)
        #expect(selectedFrame.maxX <= visibleRect.maxX + 1)
    }

    @Test func setSelectedIndexScrollsForward() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .compactShelf)
        defer { panel.close() }

        panel.setFrame(NSRect(x: 0, y: 0, width: 520, height: 226), display: false)
        panel.update(entries: Self.entries(count: 20), selectedIndex: 0)

        #expect(panel.debugHasHorizontalScroller() == false)

        let firstVisibleRect = panel.debugDocumentVisibleRect()
        panel.setSelectedIndex(15)
        let selectedFrame = try #require(panel.debugEntryFrame(windowId: 16))
        let visibleRect = panel.debugDocumentVisibleRect()

        #expect(visibleRect.minX > firstVisibleRect.minX)
        #expect(selectedFrame.minX >= visibleRect.minX - 1)
        #expect(selectedFrame.maxX <= visibleRect.maxX + 1)
    }

    @Test func clickingEntryReportsWindowId() {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .compactShelf)
        defer { panel.close() }

        var clickedWindowId: UInt32?
        panel.onEntryClick = { clickedWindowId = $0 }
        panel.update(entries: Self.entries(count: 5), selectedIndex: 0)

        panel.debugClickEntry(windowId: 4)

        #expect(clickedWindowId == 4)
    }

    @Test func selectedEntryIsStrongerThanHover() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .compactShelf)
        defer { panel.close() }

        panel.update(entries: Self.entries(count: 4), selectedIndex: 1)

        let unhovered = try #require(panel.debugEntryVisualState(windowId: 3))
        panel.debugSetHovered(windowId: 3, hovered: true)
        let hovered = try #require(panel.debugEntryVisualState(windowId: 3))
        let selected = try #require(panel.debugEntryVisualState(windowId: 2))

        #expect(hovered.hoverOpacity > unhovered.hoverOpacity)
        #expect(selected.selectionOpacity > hovered.selectionOpacity)
        #expect(selected.borderWidth > hovered.borderWidth)
    }

    @Test func switcherUsesHiddenTitleChrome() {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular)
        defer { panel.close() }

        #expect(panel.debugUsesHiddenTitleChrome())
    }

    @Test func heroCarouselUsesLargerSelectedVisualTreatment() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        panel.update(entries: Self.entries(count: 5), selectedIndex: 2)

        let before = try #require(panel.debugEntryVisualState(windowId: 2))
        let selected = try #require(panel.debugEntryVisualState(windowId: 3))
        let after = try #require(panel.debugEntryVisualState(windowId: 4))

        #expect(selected.scale > before.scale)
        #expect(selected.scale > after.scale)
        #expect(selected.selectionOpacity > before.selectionOpacity)
    }

    @Test func updateReusesEntryViewsAndKeepsPendingThumbnail() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let thumbnail = Self.thumbnail(color: .systemTeal, label: "Cached")
        var entries = Self.entries(count: 4)
        entries[1].thumbnail = thumbnail
        panel.update(entries: entries, selectedIndex: 1)

        let originalView = try #require(panel.debugEntryViewObjectIdentifier(windowId: 2))
        entries[1].thumbnail = nil
        panel.update(entries: entries, selectedIndex: 2)

        let reusedView = try #require(panel.debugEntryViewObjectIdentifier(windowId: 2))
        let retainedThumbnail = try #require(panel.debugThumbnailImage(windowId: 2))
        #expect(reusedView == originalView)
        #expect(retainedThumbnail === thumbnail)
    }

    @Test func nilThumbnailUpdateDoesNotClearRetainedThumbnail() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let thumbnail = Self.thumbnail(color: .systemOrange, label: "Retained")
        panel.update(entries: [Self.entry(windowId: 1)], selectedIndex: 0)
        panel.updateThumbnail(windowId: 1, image: thumbnail)

        panel.updateThumbnail(windowId: 1, image: nil)

        let retainedThumbnail = try #require(panel.debugThumbnailImage(windowId: 1))
        #expect(retainedThumbnail === thumbnail)
    }

    @Test func heroCarouselCentersSelectedEntryDuringKeyboardTraversal() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let surface = panel.debugSurfaceState()
        panel.setFrame(NSRect(x: 0, y: 0, width: 1180, height: surface.panelHeight), display: false)
        panel.update(entries: Self.entries(count: 18), selectedIndex: 0)
        panel.setSelectedIndex(10)

        let selectedFrame = try #require(panel.debugEntryVisualFrame(windowId: 11))
        let visibleRect = panel.debugDocumentVisibleRect()

        #expect(abs(selectedFrame.midX - visibleRect.midX) < 2)
    }

    @Test func heroCarouselSelectedVisualFrameIsNotClippedAtLeadingEdge() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let surface = panel.debugSurfaceState()
        panel.setFrame(NSRect(x: 0, y: 0, width: 1180, height: surface.panelHeight), display: false)
        panel.update(entries: Self.entries(count: 8), selectedIndex: 0)

        let selectedVisualFrame = try #require(panel.debugEntryVisualFrame(windowId: 1))
        let visibleRect = panel.debugDocumentVisibleRect()

        #expect(selectedVisualFrame.minX >= visibleRect.minX - 1)
        #expect(selectedVisualFrame.maxX <= visibleRect.maxX + 1)
        #expect(selectedVisualFrame.minY >= visibleRect.minY - 1)
        #expect(selectedVisualFrame.maxY <= visibleRect.maxY + 1)
    }

    @Test func heroCarouselUsesFloatingThumbnailCardsWithoutBackpaneOrTextPills() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        panel.update(entries: Self.entries(count: 3), selectedIndex: 1)

        let surface = panel.debugSurfaceState()
        let regularState = try #require(panel.debugEntryVisualState(windowId: 1))
        let selectedState = try #require(panel.debugEntryVisualState(windowId: 2))
        let selectedTarget = WindowSwitcherPanel.thumbnailTargetSize(layoutStyle: .heroCarousel, selected: true)
        let regularTarget = WindowSwitcherPanel.thumbnailTargetSize(layoutStyle: .heroCarousel, selected: false)

        #expect(surface.panelHeight >= 450)
        #expect(surface.documentHeight >= 420)
        #expect(surface.contentInset >= 26)
        #expect(surface.backdropAlpha == 0)
        #expect(surface.borderAlpha == 0)
        #expect(surface.borderWidth == 0)
        #expect(surface.shadow == false)
        #expect(surface.maxVisibleWidthFraction >= 0.96)
        #expect(surface.maxPanelWidth >= 2200)
        #expect(surface.cornerRadius == 0)
        #expect(!panel.debugUsesSharedGlassBackground())
        #expect(panel.debugEntryUsesSystemGlass(windowId: 1))
        #expect(panel.debugEntryUsesSystemGlass(windowId: 2))
        #expect(!panel.debugLabelsDrawBackground(windowId: 1))
        #expect(!panel.debugLabelsDrawBackground(windowId: 2))
        #expect(regularState.backgroundAlpha <= 0.03)
        #expect(regularState.footerBottomAlpha == 0)
        #expect(selectedState.backgroundAlpha >= 0.07)
        #expect(selectedState.footerBottomAlpha == 0)
        #expect(selectedState.backgroundAlpha > regularState.backgroundAlpha)
        #expect(regularTarget.height >= 260)
        #expect(selectedTarget.height >= 278)
        #expect(selectedTarget.width >= 480)
    }

    @Test func heroCarouselCardWidthFollowsWindowAspectRatio() throws {
        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let surface = panel.debugSurfaceState()
        panel.setFrame(NSRect(x: 0, y: 0, width: 1360, height: surface.panelHeight), display: false)
        panel.update(
            entries: [
                Self.entry(windowId: 1, aspectRatio: 0.62),
                Self.entry(windowId: 2, aspectRatio: 1.78),
                Self.entry(windowId: 3, aspectRatio: 2.30),
            ],
            selectedIndex: 1
        )

        let portraitFrame = try #require(panel.debugEntryFrame(windowId: 1))
        let landscapeFrame = try #require(panel.debugEntryFrame(windowId: 2))
        let wideFrame = try #require(panel.debugEntryFrame(windowId: 3))
        let portraitTarget = WindowSwitcherPanel.thumbnailTargetSize(
            layoutStyle: .heroCarousel,
            selected: false,
            aspectRatio: 0.62
        )
        let wideTarget = WindowSwitcherPanel.thumbnailTargetSize(
            layoutStyle: .heroCarousel,
            selected: false,
            aspectRatio: 2.30
        )

        #expect(landscapeFrame.width > portraitFrame.width + 100)
        #expect(wideFrame.width > landscapeFrame.width + 60)
        #expect(wideTarget.width > portraitTarget.width + 220)
    }

    @Test func heroCarouselSkinnyWindowsKeepNarrowCardFootprint() throws {
        let skinnyTarget = WindowSwitcherPanel.thumbnailTargetSize(
            layoutStyle: .heroCarousel,
            selected: false,
            aspectRatio: 0.30
        )

        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular, layoutStyle: .heroCarousel)
        defer { panel.close() }

        let surface = panel.debugSurfaceState()
        panel.setFrame(NSRect(x: 0, y: 0, width: 980, height: surface.panelHeight), display: false)
        panel.update(entries: [Self.entry(windowId: 1, aspectRatio: 0.30)], selectedIndex: 0)

        let skinnyFrame = try #require(panel.debugEntryFrame(windowId: 1))

        #expect(skinnyTarget.width <= 90)
        #expect(skinnyTarget.height >= 260)
        #expect(skinnyFrame.width <= 122)
    }

    @Test func switcherPanelSnapshotCanBeExportedForVisualQA() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_VISUAL_QA_PATH"],
              !outputPath.isEmpty else {
            if let readmePath = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_README_PATH"],
               !readmePath.isEmpty {
                try writeSwitcherReadmeShowcase(
                    entries: Self.visualEntries(),
                    selectedIndex: 1,
                    hoverWindowId: 4,
                    to: URL(fileURLWithPath: readmePath)
                )
            }
            if let framesDir = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_README_GIF_FRAMES_DIR"],
               !framesDir.isEmpty {
                try writeSwitcherReadmeGifFrames(to: URL(fileURLWithPath: framesDir))
            }
            return
        }

        let panel = WindowSwitcherPanel(theme: .dark, glassStyle: .publicRegular)
        defer { panel.close() }

        let surface = panel.debugSurfaceState()
        panel.setFrame(NSRect(x: 0, y: 0, width: 1360, height: surface.panelHeight), display: false)
        panel.update(entries: Self.visualEntries(), selectedIndex: 0)
        panel.debugSetHovered(windowId: 4, hovered: true)

        let view = try #require(panel.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        try writeViewSnapshot(view, to: URL(fileURLWithPath: outputPath))

        if let readmePath = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_README_PATH"],
           !readmePath.isEmpty {
            try writeSwitcherReadmeShowcase(
                entries: Self.visualEntries(),
                selectedIndex: 1,
                hoverWindowId: 4,
                to: URL(fileURLWithPath: readmePath)
            )
        }
        if let framesDir = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_README_GIF_FRAMES_DIR"],
           !framesDir.isEmpty {
            try writeSwitcherReadmeGifFrames(to: URL(fileURLWithPath: framesDir))
        }
    }

    private static func entries(count: Int) -> [WindowSwitcherPanel.Entry] {
        (1...count).map { index in
            entry(windowId: UInt32(index), title: "Window \(index)", appName: "App \(index)")
        }
    }

    private static func entry(
        windowId: UInt32,
        title: String? = nil,
        appName: String? = nil,
        aspectRatio: CGFloat = 16.0 / 9.0
    ) -> WindowSwitcherPanel.Entry {
        WindowSwitcherPanel.Entry(
            windowId: windowId,
            title: title ?? "Window \(windowId)",
            appName: appName ?? "App \(windowId)",
            icon: nil,
            thumbnail: nil,
            aspectRatio: aspectRatio,
            isDimmed: false
        )
    }

    private static func visualEntries() -> [WindowSwitcherPanel.Entry] {
        let items: [(String, String, NSColor, NSSize)] = [
            ("Editor", "Project", NSColor.systemBlue, NSSize(width: 320, height: 184)),
            ("Terminal", "Build", NSColor.systemGreen, NSSize(width: 360, height: 210)),
            ("Browser", "Docs", NSColor.systemOrange, NSSize(width: 360, height: 150)),
            ("Messages", "Thread", NSColor.systemPurple, NSSize(width: 176, height: 260)),
            ("Preview", "Mockup", NSColor.systemPink, NSSize(width: 250, height: 250)),
        ]
        return items.enumerated().map { offset, item in
            WindowSwitcherPanel.Entry(
                windowId: UInt32(offset + 1),
                title: item.1,
                appName: item.0,
                icon: nil,
                thumbnail: thumbnail(color: item.2, label: item.1, size: item.3),
                aspectRatio: item.3.width / item.3.height,
                isDimmed: false
            )
        }
    }

    private static func thumbnail(color: NSColor, label: String, size: NSSize = NSSize(width: 320, height: 184)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18).fill()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: 24, width: min(184, size.width - 44), height: 22), xRadius: 8, yRadius: 8).fill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: 58, width: min(256, size.width - 44), height: 20), xRadius: 8, yRadius: 8).fill()
        NSBezierPath(roundedRect: NSRect(x: 22, y: 92, width: min(132, size.width - 44), height: 20), xRadius: 8, yRadius: 8).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
        ]
        NSString(string: label).draw(at: NSPoint(x: 22, y: max(22, size.height - 52)), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    private func writeSwitcherReadmeShowcase(
        entries: [WindowSwitcherPanel.Entry],
        selectedIndex: Int,
        hoverWindowId: UInt32,
        to url: URL
    ) throws {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1860, height: 500))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.050, blue: 0.064, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "Cmd-Tab, But For Windows")
        title.frame = NSRect(x: 44, y: 418, width: 560, height: 34)
        title.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        title.textColor = .white
        container.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Large thumbnails, MRU traversal, click-to-select, and aspect-aware cards.")
        subtitle.frame = NSRect(x: 44, y: 390, width: 720, height: 22)
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.62)
        container.addSubview(subtitle)

        var x: CGFloat = 44
        for (index, entry) in entries.enumerated() {
            let selected = index == selectedIndex
            let hovered = entry.windowId == hoverWindowId
            let aspect = max(0.30, min(2.40, entry.aspectRatio))
            let imageHeight: CGFloat = selected ? 196 : 178
            let imageWidth = (imageHeight * aspect).clamped(to: selected ? 132...358 : 118...318)
            let tileWidth = imageWidth + 28
            let tileHeight: CGFloat = selected ? 306 : 284
            let tileY: CGFloat = selected ? 52 : 64

            addSwitcherTile(
                entry: entry,
                selected: selected,
                hovered: hovered,
                frame: NSRect(x: x, y: tileY, width: tileWidth, height: tileHeight),
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                to: container
            )
            x += tileWidth + 22
        }

        container.displayIfNeeded()
        try writeViewSnapshot(container, to: url)
    }

    private func writeSwitcherReadmeGifFrames(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entries = Self.visualEntries()
        let frames: [(selectedIndex: Int, hoverWindowId: UInt32)] = [
            (1, 4),
            (2, 4),
            (3, 4),
            (4, 4),
            (3, 3),
            (2, 3),
            (1, 4),
        ]
        for (index, frame) in frames.enumerated() {
            try writeSwitcherReadmeShowcase(
                entries: entries,
                selectedIndex: frame.selectedIndex,
                hoverWindowId: frame.hoverWindowId,
                to: directory.appendingPathComponent(String(format: "frame-%02d.png", index))
            )
        }
    }

    private func addSwitcherTile(
        entry: WindowSwitcherPanel.Entry,
        selected: Bool,
        hovered: Bool,
        frame: NSRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        to container: NSView
    ) {
        let tile = NSView(frame: frame)
        tile.wantsLayer = true
        tile.layer?.backgroundColor = NSColor.white.withAlphaComponent(selected ? 0.145 : hovered ? 0.095 : 0.065).cgColor
        tile.layer?.cornerRadius = selected ? 25 : 22
        tile.layer?.borderWidth = selected ? 1.4 : 1
        tile.layer?.borderColor = NSColor.white.withAlphaComponent(selected ? 0.30 : hovered ? 0.20 : 0.12).cgColor
        container.addSubview(tile)

        let imageView = NSImageView(frame: NSRect(
            x: 14,
            y: frame.height - imageHeight - 14,
            width: imageWidth,
            height: imageHeight
        ))
        imageView.image = entry.thumbnail
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = selected ? 16 : 14
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        tile.addSubview(imageView)

        let titleLabel = NSTextField(labelWithString: entry.title)
        titleLabel.frame = NSRect(x: 16, y: 44, width: frame.width - 32, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: selected ? 15 : 14, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        tile.addSubview(titleLabel)

        let appLabel = NSTextField(labelWithString: entry.appName)
        appLabel.frame = NSRect(x: 16, y: 24, width: frame.width - 32, height: 16)
        appLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.usesSingleLineMode = true
        tile.addSubview(appLabel)
    }

    private func writeViewSnapshot(_ view: NSView, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }
}
