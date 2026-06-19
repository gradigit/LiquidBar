@testable import LiquidBar
import Testing

@Suite("AccessibilityService focus policy")
struct AccessibilityServiceFocusPolicyTests {
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
