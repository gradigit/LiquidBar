import Testing
@testable import LiquidBar

@Suite("Window Types")
struct WindowTypesTests {
    // MARK: - WindowId

    @Test func testWindowIdRaw() {
        let id = WindowId(42)
        #expect(id.raw == 42)
    }

    @Test func testWindowIdHashable() {
        let id1 = WindowId(1)
        let id2 = WindowId(1)
        let id3 = WindowId(2)
        #expect(id1 == id2)
        #expect(id1 != id3)

        var set = Set<WindowId>()
        set.insert(id1)
        set.insert(id2)
        #expect(set.count == 1)
    }

    @Test func testWindowIdDescription() {
        let id = WindowId(99)
        #expect(id.description == "99")
    }

    // MARK: - MonitorId

    @Test func testMonitorIdDefault() {
        let id = MonitorId()
        #expect(id.raw == 0)
    }

    @Test func testMonitorIdRaw() {
        let id = MonitorId(5)
        #expect(id.raw == 5)
    }

    @Test func testMonitorIdHashable() {
        let id1 = MonitorId(1)
        let id2 = MonitorId(1)
        let id3 = MonitorId(2)
        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    // MARK: - BundleId

    @Test func testBundleIdRaw() {
        let id = BundleId("com.apple.finder")
        #expect(id.raw == "com.apple.finder")
    }

    @Test func testBundleIdHashable() {
        let id1 = BundleId("com.app.one")
        let id2 = BundleId("com.app.one")
        let id3 = BundleId("com.app.two")
        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    @Test func testBundleIdDescription() {
        let id = BundleId("com.test.app")
        #expect(id.description == "com.test.app")
    }

    @Test func testBundleIdAsSetKey() {
        let ids: Set<BundleId> = [BundleId("a"), BundleId("b"), BundleId("a")]
        #expect(ids.count == 2)
    }

    @Test func testBundleIdAsDictionaryKey() {
        var dict: [BundleId: Int] = [:]
        dict[BundleId("com.a")] = 1
        dict[BundleId("com.b")] = 2
        dict[BundleId("com.a")] = 3
        #expect(dict.count == 2)
        #expect(dict[BundleId("com.a")] == 3)
    }

    // MARK: - WindowBounds

    @Test func testWindowBoundsDefaults() {
        let bounds = WindowBounds()
        #expect(bounds.x == 0)
        #expect(bounds.y == 0)
        #expect(bounds.width == 0)
        #expect(bounds.height == 0)
    }

    @Test func testWindowBoundsMutable() {
        var bounds = WindowBounds()
        bounds.x = 100
        bounds.y = 200
        bounds.width = 800
        bounds.height = 600
        #expect(bounds.x == 100)
        #expect(bounds.width == 800)
    }

    // MARK: - WindowInfo

    @Test func testWindowInfoProperties() {
        let info = WindowInfo(
            id: WindowId(42),
            bundleId: BundleId("com.test.app"),
            appName: "Test App",
            title: "My Window",
            isHidden: false,
            isMinimized: true,
            monitorId: MonitorId(1),
            bounds: WindowBounds(x: 10, y: 20, width: 800, height: 600)
        )
        #expect(info.id.raw == 42)
        #expect(info.bundleId.raw == "com.test.app")
        #expect(info.appName == "Test App")
        #expect(info.title == "My Window")
        #expect(info.isHidden == false)
        #expect(info.isMinimized == true)
        #expect(info.monitorId.raw == 1)
        #expect(info.bounds.width == 800)
    }

    // MARK: - System Apps

    @Test func testSystemAppsContainsDock() {
        #expect(systemApps.contains("com.apple.dock"))
    }

    @Test func testSystemAppsContainsWindowServer() {
        #expect(systemApps.contains("com.apple.WindowServer"))
    }

    @Test func testSystemAppsDoesNotContainFinder() {
        #expect(!systemApps.contains("com.apple.finder"))
    }

    @Test func testSystemAppsCount() {
        #expect(systemApps.count == 6)
    }

    // MARK: - Constants

    @Test func testMaxWindows() {
        #expect(maxWindows == 200)
    }
}
