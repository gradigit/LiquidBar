@testable import LiquidBar
import AppKit
import Testing

@Suite("AccessibilityService focus policy")
struct AccessibilityServiceFocusPolicyTests {
    @MainActor
    @Test func ownAppWindowIdRejectsInvalidWindowNumbers() {
        #expect(AccessibilityService.ownAppWindowId(windowNumber: -1) == nil)
        #expect(AccessibilityService.ownAppWindowId(windowNumber: 0) == nil)
        #expect(AccessibilityService.ownAppWindowId(windowNumber: 42) == 42)
        #expect(AccessibilityService.ownAppWindowId(windowNumber: Int(UInt32.max) + 1) == nil)
    }

    @MainActor
    @Test func ownAppSwitcherWindowPolicyIncludesPreferencesStyleWindowsOnly() {
        #expect(AccessibilityService.isOwnAppSwitcherWindow(
            isPanel: false,
            styleMask: [.titled, .closable, .miniaturizable],
            collectionBehavior: [],
            canBecomeKey: true
        ))
        #expect(!AccessibilityService.isOwnAppSwitcherWindow(
            isPanel: true,
            styleMask: [.titled, .nonactivatingPanel],
            collectionBehavior: [],
            canBecomeKey: true
        ))
        #expect(!AccessibilityService.isOwnAppSwitcherWindow(
            isPanel: false,
            styleMask: [.titled],
            collectionBehavior: [.ignoresCycle],
            canBecomeKey: true
        ))
        #expect(!AccessibilityService.isOwnAppSwitcherWindow(
            isPanel: false,
            styleMask: [.borderless],
            collectionBehavior: [],
            canBecomeKey: true
        ))
        #expect(!AccessibilityService.isOwnAppSwitcherWindow(
            isPanel: false,
            styleMask: [.titled],
            collectionBehavior: [],
            canBecomeKey: false
        ))
    }

    @MainActor
    @Test func strictWindowScopedPlanUsesSingleWindowStrategiesForFinder() {
        let plan = AccessibilityService.strictWindowScopedFocusPlan(bundleId: "com.apple.finder")

        #expect(plan.matchedStrategies == [
            .axTarget,
            .axAppHandoff,
            .frontWindowOnly,
            .stop,
        ])
        #expect(plan.unmatchedStrategies == [
            .frontWindowOnly,
            .stop,
        ])
    }

    @MainActor
    @Test func strictWindowScopedPlanUsesSingleWindowStrategiesForNonFinderApps() {
        let plan = AccessibilityService.strictWindowScopedFocusPlan(bundleId: "com.google.Chrome")

        #expect(plan.matchedStrategies == [
            .axTarget,
            .axAppHandoff,
            .frontWindowOnly,
            .stop,
        ])
        #expect(plan.unmatchedStrategies == [
            .frontWindowOnly,
            .stop,
        ])
    }
}
