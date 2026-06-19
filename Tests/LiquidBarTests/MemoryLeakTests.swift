import AppKit
import Testing
@testable import LiquidBar

@Suite("Native renderer memory lifecycle")
@MainActor
struct MemoryLeakTests {
    @Test func nativeRendererDeallocatesAfterShutdown() {
        weak var weakRenderer: NativeBarRenderer?
        do {
            let renderer = NativeBarRenderer()
            weakRenderer = renderer
            renderer.shutdown()
        }
        #expect(weakRenderer == nil)
    }

    @Test func nativeRendererWithPanelsDeallocatesAfterShutdown() {
        weak var weakRenderer: NativeBarRenderer?
        do {
            let renderer = NativeBarRenderer()
            weakRenderer = renderer
            renderer.registerPanel(displayId: 1, barWidth: 800, barHeight: 32, scale: 2)
            renderer.unregisterPanel(displayId: 1)
            renderer.shutdown()
        }
        #expect(weakRenderer == nil)
    }

    @Test func nativeRendererDragLifecycleNoLeak() {
        weak var weakRenderer: NativeBarRenderer?
        do {
            let renderer = NativeBarRenderer()
            weakRenderer = renderer
            renderer.registerPanel(displayId: 1, barWidth: 800, barHeight: 32, scale: 2)

            let items: [TaskbarItem] = [
                .window(id: WindowId(1), bundleId: "com.test.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
                .window(id: WindowId(2), bundleId: "com.test.two", title: "Two", appName: "Two", isHidden: false, isMinimized: false, screenId: 1),
            ]
            let config = Config()
            renderer.updateItems(items, config: config, iconCache: IconCache(), displayId: 1)
            renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: config, displayId: 1)
            renderer.updateDragCursor(cursorX: 160, insertionIndex: 1, displayId: 1)
            renderer.cancelDrag(displayId: 1)
            renderer.shutdown()
        }
        #expect(weakRenderer == nil)
    }
}
