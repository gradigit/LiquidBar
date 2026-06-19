import Testing
@testable import LiquidBar

@Suite("Display Assignment")
struct DisplayAssignmentTests {
    @Test func testWindowInsideLeftScreen() {
        let screens: [(displayId: UInt32, bounds: WindowBounds)] = [
            (1, WindowBounds(x: 0, y: 0, width: 1000, height: 800)),
            (2, WindowBounds(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        let w = WindowBounds(x: 100, y: 100, width: 400, height: 300)
        #expect(DisplayAssignment.monitorId(for: w, screens: screens).raw == 1)
    }

    @Test func testIntersectionAreaWins() {
        let screens: [(displayId: UInt32, bounds: WindowBounds)] = [
            (1, WindowBounds(x: 0, y: 0, width: 1000, height: 800)),
            (2, WindowBounds(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        // Spans both screens: 100px on display 1, 200px on display 2.
        let w = WindowBounds(x: 900, y: 50, width: 300, height: 200)
        #expect(DisplayAssignment.monitorId(for: w, screens: screens).raw == 2)
    }

    @Test func testOffscreenFallsBackToNearest() {
        let screens: [(displayId: UInt32, bounds: WindowBounds)] = [
            (1, WindowBounds(x: 0, y: 0, width: 1000, height: 800)),
            (2, WindowBounds(x: 1000, y: 0, width: 1000, height: 800)),
        ]

        // Far to the right; nearest should be display 2.
        let w = WindowBounds(x: 2600, y: 100, width: 400, height: 300)
        #expect(DisplayAssignment.monitorId(for: w, screens: screens).raw == 2)
    }
}

