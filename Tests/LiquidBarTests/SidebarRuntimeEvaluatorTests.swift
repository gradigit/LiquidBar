import Testing
import Foundation
@testable import LiquidBar

@Suite
struct SidebarRuntimeEvaluatorTests {
    @Test
    func testPresentationExpandedAlwaysExpanded() {
        let now: CFAbsoluteTime = 100
        let p = SidebarRuntimeEvaluator.presentation(
            defaultState: .expanded,
            now: now,
            revealUntil: 0
        )
        #expect(p == .expanded)
    }

    @Test
    func testPresentationCompactUsesRevealWindow() {
        let now: CFAbsoluteTime = 100
        let hidden = SidebarRuntimeEvaluator.presentation(
            defaultState: .compactIcons,
            now: now,
            revealUntil: 99
        )
        let shown = SidebarRuntimeEvaluator.presentation(
            defaultState: .compactIcons,
            now: now,
            revealUntil: 101
        )
        #expect(hidden == .compact)
        #expect(shown == .expanded)
    }

    @Test
    func testPresentationHiddenPeekUsesRevealWindow() {
        let now: CFAbsoluteTime = 100
        let hidden = SidebarRuntimeEvaluator.presentation(
            defaultState: .hiddenPeek,
            now: now,
            revealUntil: 99
        )
        let shown = SidebarRuntimeEvaluator.presentation(
            defaultState: .hiddenPeek,
            now: now,
            revealUntil: 101
        )
        #expect(hidden == .hidden)
        #expect(shown == .expanded)
    }

    @Test
    func testUpdatedRevealUntilHoverTriggerExtendsOnEdgeHover() {
        let now: CFAbsoluteTime = 100
        let updated = SidebarRuntimeEvaluator.updatedRevealUntil(
            currentRevealUntil: 95,
            now: now,
            defaultState: .hiddenPeek,
            trigger: .hover,
            edgeHover: true,
            hoveringPanel: false,
            hasOverlay: false
        )
        #expect(updated > now)
    }

    @Test
    func testUpdatedRevealUntilClickTriggerIgnoresEdgeHover() {
        let now: CFAbsoluteTime = 100
        let updated = SidebarRuntimeEvaluator.updatedRevealUntil(
            currentRevealUntil: 95,
            now: now,
            defaultState: .compactIcons,
            trigger: .click,
            edgeHover: true,
            hoveringPanel: false,
            hasOverlay: false
        )
        #expect(updated == 95)
    }

    @Test
    func testUpdatedRevealUntilKeepsAliveForHoverTriggerAndOverlay() {
        let now: CFAbsoluteTime = 100
        let updatedHoverWithHoverTrigger = SidebarRuntimeEvaluator.updatedRevealUntil(
            currentRevealUntil: 95,
            now: now,
            defaultState: .compactIcons,
            trigger: .hover,
            edgeHover: false,
            hoveringPanel: true,
            hasOverlay: false
        )
        let updatedHoverWithClickTrigger = SidebarRuntimeEvaluator.updatedRevealUntil(
            currentRevealUntil: 95,
            now: now,
            defaultState: .compactIcons,
            trigger: .click,
            edgeHover: false,
            hoveringPanel: true,
            hasOverlay: false
        )
        let updatedOverlay = SidebarRuntimeEvaluator.updatedRevealUntil(
            currentRevealUntil: 95,
            now: now,
            defaultState: .compactIcons,
            trigger: .click,
            edgeHover: false,
            hoveringPanel: false,
            hasOverlay: true
        )
        #expect(updatedHoverWithHoverTrigger > now)
        #expect(updatedHoverWithClickTrigger == 95)
        #expect(updatedOverlay > now)
    }

    @Test
    func testBarThicknessOrdering() {
        let config = Config(taskbarHeight: 30, iconSize: 20, maxItemWidth: 150, maxTitleWidth: 120)
        let hidden = SidebarRuntimeEvaluator.barThickness(for: .hidden, config: config)
        let compact = SidebarRuntimeEvaluator.barThickness(for: .compact, config: config)
        let expanded = SidebarRuntimeEvaluator.barThickness(for: .expanded, config: config)

        #expect(hidden < compact)
        #expect(compact <= expanded)
        #expect(expanded >= CGFloat(config.maxItemWidth))
    }
}
