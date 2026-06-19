import CoreGraphics
import Testing
@testable import LiquidBar

@Suite("HoverIntentBridge")
struct HoverIntentBridgeTests {
    @Test func testVerticalBridgeKeepsPointerDuringEdgeTraversal() {
        let anchor = CGRect(x: 400, y: 20, width: 140, height: 42)
        let panel = CGRect(x: 360, y: 120, width: 220, height: 180)
        let cursor = CGPoint(x: 468, y: 90)

        #expect(HoverIntentBridge.contains(cursor: cursor, anchorRect: anchor, panelRect: panel))
    }

    @Test func testVerticalBridgeRejectsFarOutsidePoint() {
        let anchor = CGRect(x: 400, y: 20, width: 140, height: 42)
        let panel = CGRect(x: 360, y: 120, width: 220, height: 180)
        let cursor = CGPoint(x: 120, y: 90)

        #expect(!HoverIntentBridge.contains(cursor: cursor, anchorRect: anchor, panelRect: panel))
    }

    @Test func testHorizontalBridgeKeepsPointerDuringEdgeTraversal() {
        let anchor = CGRect(x: 80, y: 320, width: 120, height: 44)
        let panel = CGRect(x: 260, y: 260, width: 220, height: 170)
        let cursor = CGPoint(x: 230, y: 340)

        #expect(HoverIntentBridge.contains(cursor: cursor, anchorRect: anchor, panelRect: panel))
    }

    @Test func testAnchorAndPanelRectsAlwaysCountAsIntentArea() {
        let anchor = CGRect(x: 120, y: 100, width: 120, height: 36)
        let panel = CGRect(x: 100, y: 180, width: 240, height: 180)

        #expect(HoverIntentBridge.contains(
            cursor: CGPoint(x: anchor.midX, y: anchor.midY),
            anchorRect: anchor,
            panelRect: panel
        ))
        #expect(HoverIntentBridge.contains(
            cursor: CGPoint(x: panel.midX, y: panel.midY),
            anchorRect: anchor,
            panelRect: panel
        ))
    }

    @Test func testInvalidRectsReturnFalse() {
        let cursor = CGPoint(x: 10, y: 10)
        #expect(!HoverIntentBridge.contains(
            cursor: cursor,
            anchorRect: .zero,
            panelRect: CGRect(x: 10, y: 10, width: 20, height: 20)
        ))
    }
}
