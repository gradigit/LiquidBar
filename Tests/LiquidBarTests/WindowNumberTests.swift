@testable import LiquidBar
import Foundation
import Testing

@Suite("WindowNumber")
struct WindowNumberTests {
    @Test func parseAcceptsValidWindowIds() {
        #expect(WindowNumber.parse(UInt32(42)) == 42)
        #expect(WindowNumber.parse(UInt64(UInt32.max)) == UInt32.max)
        #expect(WindowNumber.parse(Int(42)) == 42)
        #expect(WindowNumber.parse(Int64(42)) == 42)
        #expect(WindowNumber.parse(Int32(42)) == 42)
        #expect(WindowNumber.parse(NSNumber(value: UInt32.max)) == UInt32.max)
    }

    @Test func parseRejectsInvalidWindowIds() {
        #expect(WindowNumber.parse(UInt32(0)) == nil)
        #expect(WindowNumber.parse(Int(0)) == nil)
        #expect(WindowNumber.parse(Int(-1)) == nil)
        #expect(WindowNumber.parse(Int64(UInt32.max) + 1) == nil)
        #expect(WindowNumber.parse(UInt64(UInt32.max) + 1) == nil)
        #expect(WindowNumber.parse(NSNumber(value: -1)) == nil)
        #expect(WindowNumber.parse(NSNumber(value: UInt64(UInt32.max) + 1)) == nil)
    }

    @Test func appKitWindowNumberRejectsStatusBarSentinelValues() {
        #expect(WindowNumber.appKitWindowNumber(-1) == nil)
        #expect(WindowNumber.appKitWindowNumber(0) == nil)
        #expect(WindowNumber.appKitWindowNumber(42) == 42)
        #expect(WindowNumber.appKitWindowNumber(Int(UInt32.max) + 1) == nil)
    }
}
