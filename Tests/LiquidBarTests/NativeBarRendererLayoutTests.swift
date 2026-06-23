import Testing
import Foundation
@testable import LiquidBar

@Suite
@MainActor
struct NativeBarRendererLayoutTests {
    @Test func testLayoutUniformSizing() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "Window One", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Window Two", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(3), bundleId: "com.app.three", title: "Window Three", appName: "App Three", isHidden: false, isMinimized: false, screenId: 1),
        ]

        let config = Config(itemSizing: .uniform)
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 600,
            barHeight: 30
        )

        #expect(rects.count == 3)

        // Middle items should have equal width; first/last are wider due to
        // Fitts' law extension (hit rects extend to window edges)
        let widths = rects.map { Float($0.rect.width) }
        #expect(widths[0] >= widths[1])  // first item extended to left edge
        #expect(widths[2] >= widths[1])  // last item extended to right edge

        // Items should not overlap
        for i in 0..<rects.count - 1 {
            let endOfCurrent = rects[i].rect.maxX
            let startOfNext = rects[i + 1].rect.minX
            #expect(endOfCurrent <= startOfNext)
        }

        renderer.shutdown()
    }

    @Test func testLayoutAutoSizing() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.short", title: "Hi", appName: "Short", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.long", title: "A Very Long Window Title Here", appName: "Long", isHidden: false, isMinimized: false, screenId: 1),
        ]

        let config = Config(iconSize: 20, iconsOnly: false, itemSizing: .auto)
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 800,
            barHeight: 30
        )

        #expect(rects.count == 2)

        // Longer title should get wider item
        let shortWidth = rects[0].rect.width
        let longWidth = rects[1].rect.width
        #expect(longWidth > shortWidth)

        renderer.shutdown()
    }

    @Test func testLayoutIconsOnly() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "Window One", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Window Two", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
        ]

        let config = Config(iconsOnly: true)
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 600,
            barHeight: 30
        )

        #expect(rects.count == 2)

        // Icons-only items should be at least (iconSize + 20 = 40);
        // first/last are wider due to Fitts' law hit rect extension
        let expectedWidth = Float(config.iconSize) + 20
        for (i, rect) in rects.enumerated() {
            let w = Float(rect.rect.width)
            if i == 0 || i == rects.count - 1 {
                #expect(w >= expectedWidth)
            } else {
                #expect(w == expectedWidth)
            }
        }

        renderer.shutdown()
    }

    @Test func testLauncherUsesIconOnlyWidthInTitledUniformMode() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .launcher(screenId: 1),
            .window(id: WindowId(1), bundleId: "com.app.one", title: "Window One", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
        ]

        var config = Config(iconsOnly: false)
        config.itemSizing = .uniform
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 600,
            barHeight: 30
        )

        #expect(rects.count == 2)
        #expect(abs(rects[0].rect.width - Double(max(44, config.iconSize + 20))) < 0.001)
        #expect(rects[1].rect.width > rects[0].rect.width)
        renderer.shutdown()
    }

    @Test func testLayoutSingleItem() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "Solo", appName: "Solo App", isHidden: false, isMinimized: false, screenId: 1),
        ]

        let config = Config()
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 400,
            barHeight: 30
        )

        #expect(rects.count == 1)
        #expect(rects[0].rect.width > 0)
        #expect(rects[0].rect.height == 30)

        renderer.shutdown()
    }

    @Test func testLayoutEmptyItems() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = []
        let config = Config()
        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 400,
            barHeight: 30
        )

        #expect(rects.isEmpty)

        renderer.shutdown()
    }

    @Test func testLayoutTabbedTaskbarCollapsesNonFocused() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 800, barHeight: 30, scale: 2)

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One window title long enough", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Focused window title long enough to expand", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(3), bundleId: "com.app.three", title: "Three window title long enough", appName: "App Three", isHidden: false, isMinimized: false, screenId: 1),
        ]

        var config = Config(iconSize: 20, iconsOnly: false, itemSizing: .auto)
        config.tabbedTaskbarEnabled = true

        let iconCache = IconCache()
        renderer.updateItems(
            items,
            config: config,
            iconCache: iconCache,
            displayId: 1,
            focus: FocusInfo(windowId: 2, bundleId: "com.app.two", tabGroupId: nil)
        )

        let rects = renderer.visualItemRects(displayId: 1)
        #expect(rects.count == 3)

        // Icon-only (collapsed) items have a minimum width for hit-testing/visual breathing room.
        let collapsedWidth = Double(max(44, config.iconSize + 20))
        #expect(abs(rects[0].width - collapsedWidth) < 0.001)
        #expect(rects[1].width > collapsedWidth)
        #expect(abs(rects[2].width - collapsedWidth) < 0.001)

        renderer.shutdown()
    }

    @Test func testLayoutTabbedTaskbarNoFocusDoesNotCollapse() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 800, barHeight: 30, scale: 2)

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One window title long enough", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Two window title long enough", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
        ]

        var config = Config(iconSize: 20, iconsOnly: false, itemSizing: .auto)
        config.tabbedTaskbarEnabled = true

        let iconCache = IconCache()
        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1, focus: .none)

        let rects = renderer.visualItemRects(displayId: 1)
        #expect(rects.count == 2)

        let collapsedWidth = Double(max(44, config.iconSize + 20))
        #expect(rects.allSatisfy { $0.width > collapsedWidth })

        renderer.shutdown()
    }

    @Test func testLayoutVerticalSidebarComputeRects() throws {
        let renderer = NativeBarRenderer()

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Two", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
        ]

        var config = Config(iconsOnly: false)
        config.taskbarPosition = .left

        let rects = renderer.computeItemRects(
            items: items,
            config: config,
            barWidth: 48,
            barHeight: 900
        )

        #expect(rects.count == 2)
        #expect(abs(rects[0].rect.width - 48.0) < 0.001)
        #expect(abs(rects[1].rect.width - 48.0) < 0.001)
        #expect(rects[0].rect.minY < rects[1].rect.minY)

        let minExpectedLength = Double(max(44, config.iconSize + 20))
        #expect(rects[0].rect.height >= minExpectedLength)
        #expect(rects[1].rect.height >= minExpectedLength)

        renderer.shutdown()
    }

    @Test func testLayoutVerticalSidebarVisualRectsAfterUpdate() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 48, barHeight: 900, scale: 2)

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Two", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(3), bundleId: "com.app.three", title: "Three", appName: "App Three", isHidden: false, isMinimized: false, screenId: 1),
        ]

        var config = Config(iconsOnly: false)
        config.taskbarPosition = .right

        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            focus: .none
        )

        let rects = renderer.visualItemRects(displayId: 1)
        #expect(rects.count == 3)
        #expect(rects.allSatisfy { abs($0.width - 48.0) < 0.001 })
        #expect(rects[0].minY < rects[1].minY)
        #expect(rects[1].minY < rects[2].minY)

        renderer.shutdown()
    }

    @Test func testVerticalSidebarExpandedModeEmitsNativeTextOverlayItems() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 180, barHeight: 900, scale: 2)

        var config = Config(iconsOnly: false)
        config.sidebarModeEnabled = true
        config.taskbarPosition = .left

        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "Alpha Window", appName: "App One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Beta Window", appName: "App Two", isHidden: false, isMinimized: false, screenId: 1),
        ]

        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            focus: .none,
            sidebarExpanded: true
        )
        let expandedText = renderer.nativeTextOverlayItems(displayId: 1)
        #expect(!expandedText.isEmpty)
        #expect(expandedText.allSatisfy { $0.nativeY != nil && $0.slotHeight != nil })

        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            focus: .none,
            sidebarExpanded: false
        )
        let compactText = renderer.nativeTextOverlayItems(displayId: 1)
        #expect(compactText.isEmpty)

        renderer.shutdown()
    }

    @Test func testPluginTileVisualStatesEmitExtraDecorations() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 56, barHeight: 800, scale: 2)

        var config = Config(iconsOnly: true)
        config.sidebarModeEnabled = true
        config.taskbarPosition = .left

        let idleItems: [TaskbarItem] = [
            .pluginTile(id: "tile.idle", providerId: nil, title: "Idle", icon: "sf:square.grid.2x2", visualState: .idle, screenId: 1),
            .pluginTile(id: "tile.active", providerId: nil, title: "Active", icon: "sf:music.note", visualState: .idle, screenId: 1),
            .pluginTile(id: "tile.attn", providerId: nil, title: "Attention", icon: "sf:bell", visualState: .idle, screenId: 1),
        ]

        renderer.updateItems(
            idleItems,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            focus: .none,
            sidebarExpanded: false
        )
        let idleDecorationCount = renderer.debugDecorationCount(displayId: 1)

        let styledItems: [TaskbarItem] = [
            .pluginTile(id: "tile.idle", providerId: nil, title: "Idle", icon: "sf:square.grid.2x2", visualState: .idle, screenId: 1),
            .pluginTile(id: "tile.active", providerId: nil, title: "Active", icon: "sf:music.note", visualState: .active, screenId: 1),
            .pluginTile(id: "tile.attn", providerId: nil, title: "Attention", icon: "sf:bell", visualState: .attention, screenId: 1),
        ]

        renderer.updateItems(
            styledItems,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            focus: .none,
            sidebarExpanded: false
        )
        let styledDecorationCount = renderer.debugDecorationCount(displayId: 1)

        #expect(styledDecorationCount >= idleDecorationCount + 2)
        renderer.shutdown()
    }
}
