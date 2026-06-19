import AppKit
import Testing
@testable import LiquidBar

@Suite("Window Adjustment Planner")
@MainActor
struct WindowAdjustmentPlannerTests {
    private let planner = AccessibilityService.WindowAdjustmentPlanner()
    private let screenCG = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let screenNS = NSRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func bottomBarShrinksFullscreenWindowAboveBar() {
        let panel = makePanel(frame: NSRect(x: 0, y: 0, width: 1000, height: 40), position: .bottom)

        let plan = planner.plan(
            forWindowFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan?.usableFrame == CGRect(x: 0, y: 0, width: 1000, height: 760))
        #expect(plan?.targetFrame == CGRect(x: 0, y: 0, width: 1000, height: 760))
        #expect(plan?.needsMove == false)
        #expect(plan?.needsResize == true)
    }

    @Test func topBarMovesAndShrinksWindowBelowBar() {
        let panel = makePanel(frame: NSRect(x: 0, y: 760, width: 1000, height: 40), position: .top)

        let plan = planner.plan(
            forWindowFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan?.usableFrame == CGRect(x: 0, y: 40, width: 1000, height: 760))
        #expect(plan?.targetFrame == CGRect(x: 0, y: 40, width: 1000, height: 760))
        #expect(plan?.needsMove == true)
        #expect(plan?.needsResize == true)
    }

    @Test func leftBarMovesAndShrinksWindowRightward() {
        let panel = makePanel(frame: NSRect(x: 0, y: 0, width: 60, height: 800), position: .left)

        let plan = planner.plan(
            forWindowFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan?.usableFrame == CGRect(x: 60, y: 0, width: 940, height: 800))
        #expect(plan?.targetFrame == CGRect(x: 60, y: 0, width: 940, height: 800))
        #expect(plan?.needsMove == true)
        #expect(plan?.needsResize == true)
    }

    @Test func rightBarClampsTinyOverlapToMinimumWidth() {
        let panel = makePanel(frame: NSRect(x: 900, y: 0, width: 100, height: 800), position: .right)

        let plan = planner.plan(
            forWindowFrame: CGRect(x: 850, y: 100, width: 80, height: 300),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan?.usableFrame == CGRect(x: 0, y: 0, width: 900, height: 800))
        #expect(plan?.targetFrame == CGRect(x: 800, y: 100, width: 100, height: 300))
        #expect(plan?.needsMove == true)
        #expect(plan?.needsResize == true)
    }

    @Test func windowInsideUsableFrameHasNoPlan() {
        let panel = makePanel(frame: NSRect(x: 0, y: 0, width: 60, height: 800), position: .left)

        let plan = planner.plan(
            forWindowFrame: CGRect(x: 80, y: 100, width: 400, height: 300),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan == nil)
    }

    @Test func unusableDisplayReservationHasNoPlan() {
        let narrowPlanner = AccessibilityService.WindowAdjustmentPlanner(minimumSize: 100)
        let panel = makePanel(frame: NSRect(x: 0, y: 0, width: 950, height: 800), position: .left)

        let plan = narrowPlanner.plan(
            forWindowFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            panel: panel,
            screenCGBounds: screenCG,
            screenNSFrame: screenNS
        )

        #expect(plan == nil)
    }

    @Test func spanningWindowDetectionUsesIntersectionArea() {
        let screens: [(displayId: UInt32, bounds: WindowBounds)] = [
            (1, WindowBounds(x: 0, y: 0, width: 1000, height: 800)),
            (2, WindowBounds(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        let spanning = WindowBounds(x: 900, y: 100, width: 200, height: 300)
        let singleDisplay = WindowBounds(x: 100, y: 100, width: 200, height: 300)

        #expect(planner.windowSpansMultipleDisplays(spanning, screens: screens))
        #expect(!planner.windowSpansMultipleDisplays(singleDisplay, screens: screens))
    }

    private func makePanel(frame: NSRect, position: Position) -> AccessibilityService.PanelInfo {
        AccessibilityService.PanelInfo(displayId: 1, frame: frame, position: position)
    }
}
