import Testing
@testable import LiquidBar

@Suite
@MainActor
struct WindowListStabilizerTests {
    private func makeWindow(id: UInt32, title: String = "T") -> WindowInfo {
        WindowInfo(
            id: WindowId(id),
            bundleId: BundleId("com.example.app"),
            appName: "App",
            title: title,
            isHidden: false,
            isMinimized: false,
            monitorId: MonitorId(0),
            bounds: WindowBounds(x: 0, y: 0, width: 100, height: 100)
        )
    }

    @Test func testEmptyPassesThroughWithoutSpaceChange() {
        let stabilizer = WindowListStabilizer()
        let out = stabilizer.stabilize(observed: [], now: 1.0)
        #expect(out.isEmpty)
    }

    @Test func testHoldsLastNonEmptyBrieflyAfterSpaceChange() {
        let stabilizer = WindowListStabilizer(config: .init(holdLastNonEmptyAfterSpaceChange: 0.20))

        let initial = [makeWindow(id: 1)]
        #expect(stabilizer.stabilize(observed: initial, now: 1.0).map(\.id.raw) == [1])

        stabilizer.noteSpaceChange(now: 2.0)

        // Within hold window: keep last non-empty list.
        let held = stabilizer.stabilize(observed: [], now: 2.10)
        #expect(held.map(\.id.raw) == [1])

        // Past hold window: allow truly empty list through.
        let empty = stabilizer.stabilize(observed: [], now: 2.30)
        #expect(empty.isEmpty)
    }

    @Test func testNonEmptyAlwaysWins() {
        let stabilizer = WindowListStabilizer(config: .init(holdLastNonEmptyAfterSpaceChange: 10.0))

        stabilizer.noteSpaceChange(now: 1.0)
        let out = stabilizer.stabilize(observed: [makeWindow(id: 2)], now: 1.01)
        #expect(out.map(\.id.raw) == [2])
    }
}

