import AppKit
import Testing
@testable import LiquidBar

@Suite("NativeBarViewDragDecision")
@MainActor
struct NativeBarViewDragDecisionTests {
    @Test func dragThresholdRequiresMovementBeyondLimit() {
        #expect(
            NativeBarView.shouldBeginDrag(
                startPoint: NSPoint(x: 10, y: 10),
                currentPoint: NSPoint(x: 14, y: 13),
                threshold: 6
            ) == false
        )
        #expect(
            NativeBarView.shouldBeginDrag(
                startPoint: NSPoint(x: 10, y: 10),
                currentPoint: NSPoint(x: 16, y: 10),
                threshold: 6
            )
        )
    }

    @Test func clickDecisionWinsWhenDragNeverStarted() {
        #expect(
            NativeBarView.resolveDragCompletionDecision(
                sourceIndex: 2,
                isDragging: false,
                isInsideReorderLane: true,
                dropIndex: 2,
                finalInsertionIndex: 3,
                specialDropHandled: false
            ) == .click(sourceIndex: 2)
        )
    }

    @Test func reorderDecisionRequiresLaneMembership() {
        #expect(
            NativeBarView.resolveDragCompletionDecision(
                sourceIndex: 1,
                isDragging: true,
                isInsideReorderLane: false,
                dropIndex: nil,
                finalInsertionIndex: 3,
                specialDropHandled: false
            ) == .cancel
        )
    }

    @Test func specialDropSuppressesReorder() {
        #expect(
            NativeBarView.resolveDragCompletionDecision(
                sourceIndex: 1,
                isDragging: true,
                isInsideReorderLane: true,
                dropIndex: 2,
                finalInsertionIndex: 3,
                specialDropHandled: true
            ) == .specialDrop(sourceIndex: 1, dropIndex: 2)
        )
    }

    @Test func immediateSelfInsertionCancelsNoOpReorder() {
        #expect(
            NativeBarView.resolveDragCompletionDecision(
                sourceIndex: 1,
                isDragging: true,
                isInsideReorderLane: true,
                dropIndex: 1,
                finalInsertionIndex: 2,
                specialDropHandled: false
            ) == .cancel
        )
    }

    @Test func validInLaneMoveProducesReorderDecision() {
        #expect(
            NativeBarView.resolveDragCompletionDecision(
                sourceIndex: 1,
                isDragging: true,
                isInsideReorderLane: true,
                dropIndex: 3,
                finalInsertionIndex: 4,
                specialDropHandled: false
            ) == .reorder(from: 1, to: 4, dropIndex: 3)
        )
    }

    @Test func dragLaneUsesVisualRectsNotStaleHitRects() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.orientation = .bottom
        view.itemRects = [
            (bundleId: "stale", index: 0, rect: NSRect(x: 0, y: 0, width: 300, height: 30))
        ]
        view.visualItemRects = [
            NSRect(x: 0, y: 0, width: 90, height: 30),
            NSRect(x: 100, y: 0, width: 90, height: 30),
            NSRect(x: 200, y: 0, width: 90, height: 30),
        ]

        #expect(view.debugIsPointInsideDragLane(NSPoint(x: 150, y: 15)))
        #expect(view.debugIsPointInsideDragLane(NSPoint(x: 150, y: 40)) == false)
    }
}
