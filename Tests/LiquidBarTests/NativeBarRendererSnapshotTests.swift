import AppKit
import Testing
@testable import LiquidBar

@Suite("NativeBarRenderer snapshots")
@MainActor
struct NativeBarRendererSnapshotTests {
    @Test func snapshotContainsRetainedItemsAndDecorations() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 600, barHeight: 32, scale: 2)

        let items: [TaskbarItem] = [
            .pinnedApp(bundleId: "com.apple.finder", screenId: 1),
            .pluginTile(id: "tile.attn", providerId: nil, title: "Attention", icon: "sf:bell", visualState: .attention, screenId: 1),
        ]

        renderer.updateItems(items, config: Config(iconsOnly: true), iconCache: IconCache(), displayId: 1)
        let snapshot = renderer.snapshot(displayId: 1)

        #expect(snapshot?.items.count == 2)
        #expect(snapshot?.visualRects.count == 2)
        #expect((snapshot?.decorations.count ?? 0) >= 2)
        renderer.shutdown()
    }

    @Test func nativeBarViewAppliesSnapshotWithoutGpuSurface() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "cpu", text: "CPU 42%", screenId: 1),
        ]
        renderer.updateItems(items, config: Config(), iconCache: IconCache(), displayId: 1)

        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        #expect(view.items.count == 1)
        #expect(view.visualItemRects.count == 1)
        #expect(view.itemRects.count == 1)
        renderer.shutdown()
    }

    @Test func nativeBarViewUsesLayeredGlassDecorationsForHover() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        var config = Config(iconsOnly: true)
        config.visualDepth = .rich
        renderer.updateItems([
            .launcher(screenId: 1),
        ], config: config, iconCache: IconCache(), displayId: 1)
        #expect(renderer.setHoverRect(NSRect(x: 8, y: 4, width: 44, height: 24), for: 1) == true)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        let sublayerNames = view.debugDecorationLayerSublayerNames().flatMap { $0 }
        #expect(sublayerNames.contains("glass-fill"))
        #expect(sublayerNames.contains("glass-top-highlight"))
        #expect(sublayerNames.contains("glass-lower-shade"))
        #expect(sublayerNames.contains("glass-specular-edge"))
        renderer.shutdown()
    }

    @Test func nativeBarViewKeepsDecorationsBehindItemIcons() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        #expect(view.debugRetainedLayerOrder() == ["decorations", "items"])
    }

    @Test func appGroupStackAndPillBadgeEmitDecorationsAndCountText() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupStackStyle = .filled
        config.appGroupStackGeometry = .subtle
        config.appGroupCountBadgeStyle = .pill

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(snapshot.decorations.filter { $0.kind == .stackPlate }.count == 2)
        #expect(snapshot.decorations.contains { $0.kind == .badge })
        #expect(snapshot.nativeTextItems.contains { $0.title == "3" })
        renderer.shutdown()
    }

    @Test func appGroupPillBadgeDoesNotOverlapIconOrStackFan() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 360, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 24, iconsOnly: true, groupByApp: true)
        config.appGroupStackGeometry = .strong
        config.appGroupStackHoverSpreadEnabled = true
        config.appGroupCountBadgeStyle = .pill

        renderer.updateItems([sampleAppGroup(windowCount: 4)], config: config, iconCache: IconCache(), displayId: 1)
        let idleSnapshot = try #require(renderer.snapshot(displayId: 1))
        #expect(renderer.setHoveredItemIndex(0, for: 1) == true)
        #expect(renderer.setHoverRect(idleSnapshot.visualRects[0], for: 1) == true)

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let item = try #require(snapshot.items.first)
        let badge = try #require(snapshot.decorations.first { $0.kind == .badge })
        let stackFanMaxX = snapshot.decorations
            .filter { $0.kind == .stackPlate }
            .map(\.rect.maxX)
            .max() ?? item.iconRect.maxX

        #expect(badge.rect.minX >= item.iconRect.maxX + 1)
        #expect(badge.rect.minX >= stackFanMaxX + 1)
        #expect(badge.rect.maxX <= item.rect.maxX - 1)
        renderer.shutdown()
    }

    @Test func appGroupSeparatorBadgeUsesSeparatorDecorationWithoutBadgePlate() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupCountBadgeStyle = .separator

        renderer.updateItems([sampleAppGroup(windowCount: 4)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(snapshot.decorations.contains { $0.kind == .separator })
        #expect(!snapshot.decorations.contains { $0.kind == .badge })
        #expect(snapshot.nativeTextItems.contains { $0.title == "4" })
        renderer.shutdown()
    }

    @Test func appGroupCountBadgeDoesNotOverlayTitledItems() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 260, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: false, groupByApp: true)
        config.itemSizing = .auto

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(!snapshot.decorations.contains { $0.kind == .badge })
        #expect(!snapshot.nativeTextItems.contains { $0.title == "3" })
        #expect(snapshot.nativeTextItems.contains { $0.title == "Browser" })
        renderer.shutdown()
    }

    @Test func appGroupHoverSpreadMovesStackPlatesWithinReservedWidth() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 260, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupStackGeometry = .strong
        config.appGroupStackHoverSpreadEnabled = true

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let idleSnapshot = try #require(renderer.snapshot(displayId: 1))
        let idlePlateX = try #require(idleSnapshot.decorations.first { $0.kind == .stackPlate }?.rect.minX)
        let reservedWidth = try #require(idleSnapshot.visualRects.first?.width)

        #expect(renderer.setHoveredItemIndex(0, for: 1) == true)
        #expect(renderer.setHoverRect(idleSnapshot.visualRects[0], for: 1) == true)

        let hoverSnapshot = try #require(renderer.snapshot(displayId: 1))
        let hoverPlateX = try #require(hoverSnapshot.decorations.first { $0.kind == .stackPlate }?.rect.minX)

        #expect(hoverPlateX > idlePlateX)
        #expect(try #require(hoverSnapshot.visualRects.first?.width) == reservedWidth)
        renderer.shutdown()
    }

    @Test func nativeBarViewVisualDepthSnapshotCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_BAR_VISUAL_QA_PATH"],
              !outputPath.isEmpty else { return }

        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 420, barHeight: 48, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 420, height: 48))
        view.configure(scale: 2)

        var config = Config(taskbarHeight: 48, iconSize: 28, iconsOnly: true, itemSizing: .auto)
        config.groupByApp = true
        config.visualDepth = .rich
        config.hoverIntensity = .pronounced
        config.focusIndicatorStyle = .tile
        renderer.updateItems([
            .launcher(screenId: 1),
            .customText(id: "metric", text: "Liquid", screenId: 1),
            .pluginTile(id: "now-playing", providerId: nil, title: "Music", icon: "sf:music.note", visualState: .active, screenId: 1),
            .appGroup(bundleId: "com.example.browser", appName: "Browser", windowCount: 3, windows: [WindowId(1), WindowId(2), WindowId(3)], isHidden: false, isMinimized: false, screenId: 1),
        ], config: config, iconCache: IconCache(), displayId: 1, focus: FocusInfo(windowId: nil, bundleId: "com.example.browser", tabGroupId: nil))
        _ = renderer.setHoverRect(NSRect(x: 64, y: 6, width: 92, height: 36), for: 1)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 48)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 48))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor
        container.addSubview(view)
        view.displayIfNeeded()
        container.displayIfNeeded()

        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
        renderer.shutdown()
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

    @Test func nativeBarViewPrunesStaleItemLayersAcrossWindowChurn() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        renderer.updateItems([
            .window(id: WindowId(1), bundleId: "com.test.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
        ], config: Config(), iconCache: IconCache(), displayId: 1)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }
        #expect(view.debugLayerPoolCounts().items == 1)
        #expect(view.debugLayerPoolCounts().icons == 1)

        renderer.updateItems([
            .window(id: WindowId(2), bundleId: "com.test.two", title: "Two", appName: "Two", isHidden: false, isMinimized: false, screenId: 1),
        ], config: Config(), iconCache: IconCache(), displayId: 1)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        #expect(view.debugLayerPoolCounts().items == 1)
        #expect(view.debugLayerPoolCounts().icons == 1)
        renderer.shutdown()
    }

    @Test func nativeBarViewKeepsIconAndTextLayersAtBackingScale() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        renderer.updateItems([
            .launcher(screenId: 1),
            .customText(id: "label", text: "Sharp Text", screenId: 1),
        ], config: Config(), iconCache: IconCache(), displayId: 1)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        let scales = view.debugLayerScales()
        #expect(scales.root == 2)
        #expect(!scales.icon.isEmpty)
        #expect(scales.icon.allSatisfy { $0 == 2 })
        #expect(!scales.text.isEmpty)
        #expect(scales.text.allSatisfy { $0 == 2 })

        let iconFrames = view.debugIconLayerFrames()
        #expect(!iconFrames.isEmpty)
        #expect(iconFrames.allSatisfy { abs($0.width - 20) < 0.001 })
        #expect(iconFrames.allSatisfy { abs($0.height - 20) < 0.001 })
        #expect(view.debugIconLayerContentTypes().allSatisfy { $0 == "NSImage" })
        renderer.shutdown()
    }

    private func sampleAppGroup(windowCount: Int) -> TaskbarItem {
        .appGroup(
            bundleId: "com.example.browser",
            appName: "Browser",
            windowCount: windowCount,
            windows: (1...windowCount).map { WindowId(UInt32($0)) },
            isHidden: false,
            isMinimized: false,
            screenId: 1
        )
    }
}
