import AppKit
import Testing
@testable import LiquidBar

@Suite("NativeBarViewDrag")
@MainActor
struct NativeBarViewDragTests {
    @Test func testHorizontalInsertionIndexUsesX() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.orientation = .bottom
        view.itemRects = [
            (bundleId: "a", index: 0, rect: NSRect(x: 0, y: 0, width: 90, height: 30)),
            (bundleId: "b", index: 1, rect: NSRect(x: 100, y: 0, width: 90, height: 30)),
            (bundleId: "c", index: 2, rect: NSRect(x: 200, y: 0, width: 90, height: 30)),
        ]

        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 10, y: 15)) == 0)
        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 120, y: 15)) == 1)
        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 250, y: 15)) == 3)
    }

    @Test func testVerticalInsertionIndexUsesY() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 48, height: 300))
        view.orientation = .left
        view.itemRects = [
            (bundleId: "a", index: 0, rect: NSRect(x: 0, y: 0, width: 48, height: 44)),
            (bundleId: "b", index: 1, rect: NSRect(x: 0, y: 52, width: 48, height: 44)),
            (bundleId: "c", index: 2, rect: NSRect(x: 0, y: 104, width: 48, height: 44)),
        ]

        // view.y=280 -> flippedY=20 (first slot)
        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 24, y: 280)) == 0)
        // view.y=230 -> flippedY=70 (second slot)
        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 24, y: 230)) == 1)
        // view.y=40 -> flippedY=260 (past all slots)
        #expect(view.debugInsertionIndexForDrag(at: NSPoint(x: 24, y: 40)) == 3)
    }
}

