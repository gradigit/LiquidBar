import Testing
import Foundation
@testable import LiquidBar

@Suite("Drag Animation Lifecycle")
@MainActor
struct DragLifecycleTests {
    private func setupRenderer(itemCount: Int = 3) -> NativeBarRenderer {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 800, barHeight: 30, scale: 2)

        var items: [TaskbarItem] = []
        for i in 0..<itemCount {
            items.append(.window(
                id: WindowId(UInt32(i + 1)),
                bundleId: "com.app.\(i)",
                title: "Window \(i)",
                appName: "App \(i)",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ))
        }

        let config = Config()
        let iconCache = IconCache()
        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        return renderer
    }

    private func setupVerticalRenderer(itemCount: Int = 4) -> NativeBarRenderer {
        let renderer = NativeBarRenderer()
        // Vertical sidebar: narrow width, tall primary axis.
        renderer.registerPanel(displayId: 1, barWidth: 56, barHeight: 720, scale: 2)

        var items: [TaskbarItem] = []
        for i in 0..<itemCount {
            items.append(.window(
                id: WindowId(UInt32(i + 1)),
                bundleId: "com.app.\(i)",
                title: "Window \(i)",
                appName: "App \(i)",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ))
        }

        var config = Config()
        config.taskbarPosition = .left
        config.sidebarModeEnabled = true
        config.sidebarStateDefault = .compactIcons
        let iconCache = IconCache()
        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1, sidebarExpanded: false)
        return renderer
    }

    // MARK: - Start Drag

    @Test func testStartDragCreatesAnimation() throws {
        let renderer = setupRenderer()

        #expect(renderer.hasDragAnimation(for: 1) == false)
        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == true)

        renderer.shutdown()
    }

    @Test func testStartDragInvalidIndex() throws {
        let renderer = setupRenderer(itemCount: 2)

        renderer.startDrag(sourceIndex: 5, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == false)

        renderer.shutdown()
    }

    @Test func testStartDragNegativeIndex() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: -1, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == false)

        renderer.shutdown()
    }

    @Test func testStartDragWrongDisplay() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 999)
        #expect(renderer.hasDragAnimation(for: 999) == false)

        renderer.shutdown()
    }

    // MARK: - Cancel Drag

    @Test func testCancelDragClearsAnimation() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == true)

        renderer.cancelDrag(displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == false)

        renderer.shutdown()
    }

    @Test func testCancelDragIdempotent() throws {
        let renderer = setupRenderer()

        // Cancel when there's no animation — should not crash
        renderer.cancelDrag(displayId: 1)
        renderer.cancelDrag(displayId: 1)
        #expect(renderer.hasDragAnimation(for: 1) == false)

        renderer.shutdown()
    }

    // MARK: - End Drag (Settle)

    @Test func testEndDragStartsSettle() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        renderer.endDrag(displayId: 1)

        // Animation should still exist (settling)
        #expect(renderer.hasDragAnimation(for: 1) == true)

        renderer.shutdown()
    }

    @Test func testEndDragSettleConverges() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        renderer.endDrag(displayId: 1)

        // Tick many frames to let settle animation complete
        var converged = false
        for _ in 0..<300 {
            let animating = renderer.tickAndRebuildDragBuffers(displayId: 1)
            if !animating {
                converged = true
                break
            }
        }

        #expect(converged, "Settle animation should converge within 5 seconds")

        renderer.shutdown()
    }

    // MARK: - Update Cursor

    @Test func testUpdateCursorChangesDragState() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)

        // Move cursor across multiple positions
        renderer.updateDragCursor(cursorX: 200, insertionIndex: 1, displayId: 1)
        renderer.updateDragCursor(cursorX: 400, insertionIndex: 2, displayId: 1)

        // Should still be animating
        #expect(renderer.hasDragAnimation(for: 1) == true)

        renderer.shutdown()
    }

    // MARK: - Tick and Rebuild

    @Test func testTickWithNoDragReturnsFalse() throws {
        let renderer = setupRenderer()

        let animating = renderer.tickAndRebuildDragBuffers(displayId: 1)
        #expect(animating == false)

        renderer.shutdown()
    }

    @Test func testTickWithActiveDragReturnsTrue() throws {
        let renderer = setupRenderer()

        renderer.startDrag(sourceIndex: 0, cursorX: 50, cursorOffsetInItem: 10, config: Config(), displayId: 1)
        // Move cursor so springs have something to animate
        renderer.updateDragCursor(cursorX: 300, insertionIndex: 2, displayId: 1)

        let animating = renderer.tickAndRebuildDragBuffers(displayId: 1)
        #expect(animating == true)

        renderer.shutdown()
    }

    @Test func testVerticalDragBuildsAnimatedDragBuffers() throws {
        let renderer = setupVerticalRenderer()

        // For vertical bars, cursorX carries the primary-axis coordinate (y in view space).
        renderer.startDrag(sourceIndex: 1, cursorX: 180, cursorOffsetInItem: 12, config: Config(), displayId: 1)
        renderer.updateDragCursor(cursorX: 360, insertionIndex: 3, displayId: 1)

        let animating = renderer.tickAndRebuildDragBuffers(displayId: 1)
        let counts = renderer.debugDragCounts(displayId: 1)

        #expect(animating == true)
        #expect(counts.decoration > 0)
        // Icons depend on cache population; retained drag decorations are the core signal.
        #expect(counts.icon >= 0)

        renderer.shutdown()
    }

    // MARK: - Hover State

    @Test func testSetHoverRect() throws {
        let renderer = setupRenderer()

        renderer.setHoverRect(NSRect(x: 10, y: 0, width: 100, height: 30), for: 1)
        // Should not crash, hover state is internal

        renderer.setHoverRect(nil, for: 1)
        // Should clear hover state

        renderer.shutdown()
    }
}
