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
}
