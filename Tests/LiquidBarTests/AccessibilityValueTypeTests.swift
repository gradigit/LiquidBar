import ApplicationServices
import Foundation
import Testing
@testable import LiquidBar

@Suite("Accessibility value type guards")
struct AccessibilityValueTypeTests {
    @MainActor
    @Test func rejectsNonAXElementValues() {
        let string = "not an accessibility element" as CFString
        #expect(!AccessibilityService.debugIsAXElementValue(string))
    }

    @MainActor
    @Test func acceptsAXValueAndRejectsPlainCFValues() {
        var point = CGPoint(x: 1, y: 2)
        let axValue = AXValueCreate(.cgPoint, &point)!
        let string = "not an AXValue" as CFString

        #expect(AccessibilityService.debugIsAXValue(axValue))
        #expect(!AccessibilityService.debugIsAXValue(string))
    }
}
