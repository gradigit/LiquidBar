import Testing
@testable import LiquidBar

@Suite
struct WindowStateStoreTests {
    @Test @MainActor func testChangeDetection() {
        let store = WindowStateStore()
        let config = Config()

        let windows1 = [makeTestWindow(id: 1, bundle: "com.test.app", title: "Window 1")]
        #expect(store.update(windows: windows1, config: config) == true)

        // Different windows = changed
        let windows2 = [makeTestWindow(id: 2, bundle: "com.test.app", title: "Window 2")]
        #expect(store.update(windows: windows2, config: config) == true)
    }

    @Test @MainActor func testSameWindows() {
        let store = WindowStateStore()
        let config = Config()

        let windows = [makeTestWindow(id: 1, bundle: "com.test.app", title: "Window 1")]
        _ = store.update(windows: windows, config: config)

        // Same windows again = no change
        let same = [makeTestWindow(id: 1, bundle: "com.test.app", title: "Window 1")]
        #expect(store.update(windows: same, config: config) == false)
    }

    @Test @MainActor func testBlacklist() {
        let store = WindowStateStore()
        let config = Config(blacklistedApps: ["com.blocked.app"])

        let windows = [
            makeTestWindow(id: 1, bundle: "com.test.app", title: "Allowed"),
            makeTestWindow(id: 2, bundle: "com.blocked.app", title: "Blocked"),
        ]
        _ = store.update(windows: windows, config: config)

        let result = store.getWindows()
        #expect(result.count == 1)
        #expect(result[0].bundleId.raw == "com.test.app")
    }

    @Test @MainActor func testReorder() {
        let store = WindowStateStore()
        let config = Config()

        let windows = [
            makeTestWindow(id: 1, bundle: "com.a", title: "A"),
            makeTestWindow(id: 2, bundle: "com.b", title: "B"),
            makeTestWindow(id: 3, bundle: "com.c", title: "C"),
        ]
        _ = store.update(windows: windows, config: config)

        store.reorder(from: 0, to: 2)
        let order = store.windowOrder
        #expect(order.count == 3)
        // `to` is an insertion marker in the original order, so moving 0 -> 2
        // places the first item before the original item at index 2.
        #expect(order.map(\.raw) == [2, 1, 3])
    }

    @Test @MainActor func testApplyPreferredWindowOrder() {
        let store = WindowStateStore()
        let config = Config()

        let windows = [
            makeTestWindow(id: 1, bundle: "com.a", title: "A"),
            makeTestWindow(id: 2, bundle: "com.b", title: "B"),
            makeTestWindow(id: 3, bundle: "com.c", title: "C"),
            makeTestWindow(id: 4, bundle: "com.d", title: "D"),
        ]
        _ = store.update(windows: windows, config: config)

        let changed = store.applyPreferredWindowOrder([3, 1, 999, 3])
        #expect(changed == true)
        #expect(store.windowOrder.map(\.raw) == [3, 1, 2, 4])
    }

    @Test @MainActor func hiddenAppWindowsAreRetainedWhenMissingFromPoll() {
        let store = WindowStateStore()
        var config = Config()
        config.showHiddenApps = true

        let visibleWindow = makeTestWindow(id: 1, bundle: "com.test.hidden", title: "Hidden soon")
        #expect(store.update(windows: [visibleWindow], config: config) == true)

        let changed = store.update(
            windows: [],
            config: config,
            hiddenBundleIds: ["com.test.hidden"]
        )

        let windows = store.getWindows()
        #expect(changed == true)
        #expect(windows.count == 1)
        #expect(windows[0].id.raw == 1)
        #expect(windows[0].isHidden == true)
    }

    @Test @MainActor func hiddenRetentionDropsStaleIdWhenReplacementSurfaceIsObserved() {
        let store = WindowStateStore()
        var config = Config()
        config.showHiddenApps = true
        config.groupByApp = false

        let bounds = WindowBounds(x: 100, y: 120, width: 900, height: 640)
        let original = makeTestWindow(id: 10, bundle: "com.test.hidden", title: "Project", bounds: bounds)
        #expect(store.update(windows: [original], config: config))

        let replacement = makeTestWindow(
            id: 20,
            bundle: "com.test.hidden",
            title: "Project",
            isHidden: true,
            bounds: WindowBounds(x: 108, y: 120, width: 900, height: 640)
        )
        #expect(store.update(
            windows: [replacement],
            config: config,
            hiddenBundleIds: ["com.test.hidden"]
        ))

        let windows = store.getWindows()
        #expect(windows.map(\.id.raw) == [20])
        #expect(windows[0].isHidden)
    }

    @Test @MainActor func hiddenRetentionKeepsDistinctSameTitleWindows() {
        let store = WindowStateStore()
        var config = Config()
        config.showHiddenApps = true

        let first = makeTestWindow(
            id: 10,
            bundle: "com.test.hidden",
            title: "Untitled",
            bounds: WindowBounds(x: 0, y: 0, width: 640, height: 480)
        )
        let second = makeTestWindow(
            id: 20,
            bundle: "com.test.hidden",
            title: "Untitled",
            bounds: WindowBounds(x: 760, y: 0, width: 640, height: 480)
        )
        #expect(store.update(windows: [first, second], config: config))

        let observedSecond = makeTestWindow(
            id: 30,
            bundle: "com.test.hidden",
            title: "Untitled",
            isHidden: true,
            bounds: WindowBounds(x: 760, y: 0, width: 640, height: 480)
        )
        #expect(store.update(
            windows: [observedSecond],
            config: config,
            hiddenBundleIds: ["com.test.hidden"]
        ))

        #expect(store.getWindows().map(\.id.raw) == [10, 30])
    }

    @Test @MainActor func missingHiddenAppWindowsAreDroppedWhenHiddenAppsDisabled() {
        let store = WindowStateStore()
        var config = Config()
        config.showHiddenApps = false

        let visibleWindow = makeTestWindow(id: 1, bundle: "com.test.hidden", title: "Hidden soon")
        #expect(store.update(windows: [visibleWindow], config: config) == true)

        let changed = store.update(
            windows: [],
            config: config,
            hiddenBundleIds: ["com.test.hidden"]
        )

        #expect(changed == true)
        #expect(store.getWindows().isEmpty)
    }

    @Test @MainActor func testReorderSubset() {
        let store = WindowStateStore()
        let config = Config()

        let windows = [
            makeTestWindow(id: 1, bundle: "com.a", title: "A"),
            makeTestWindow(id: 2, bundle: "com.a", title: "B"),
            makeTestWindow(id: 3, bundle: "com.a", title: "C"),
            makeTestWindow(id: 4, bundle: "com.b", title: "D"),
        ]
        _ = store.update(windows: windows, config: config)

        let changed = store.reorderSubset(orderedWindowIds: [3, 1, 2])
        #expect(changed == true)
        #expect(store.windowOrder.map(\.raw) == [3, 1, 2, 4])
    }
}
