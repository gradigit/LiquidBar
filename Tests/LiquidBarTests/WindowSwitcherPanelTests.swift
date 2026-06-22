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
              !outputPath.isEmpty else { return }

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
            ("Codex", "Chat", NSColor.systemBlue, NSSize(width: 320, height: 184)),
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
