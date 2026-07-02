import Testing
import CoreGraphics
@testable import LiquidBar

func makeTestWindow(
    id: UInt32,
    bundle: String,
    title: String,
    isHidden: Bool = false,
    isMinimized: Bool = false,
    monitorId: UInt32 = 0,
    bounds: WindowBounds = WindowBounds()
) -> WindowInfo {
    WindowInfo(
        id: WindowId(id),
        bundleId: BundleId(bundle),
        appName: bundle.split(separator: ".").last.map(String.init) ?? bundle,
        title: title,
        isHidden: isHidden,
        isMinimized: isMinimized,
        monitorId: MonitorId(monitorId),
        bounds: bounds
    )
}

@Suite
struct TaskbarItemTests {
    @Test func launcherDisplayTitleIsAlwaysEmpty() {
        #expect(TaskbarItem.launcher(screenId: 1).displayTitle(iconsOnly: false) == "")
        #expect(TaskbarItem.launcher(screenId: 1).displayTitle(iconsOnly: true) == "")
    }

    @Test @MainActor func testUngrouped() {
        let store = WindowStateStore()
        let config = Config(groupByApp: false)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Safari", title: "GitHub"),
            makeTestWindow(id: 2, bundle: "com.app.Safari", title: "Google"),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 2)
    }

    @Test @MainActor func ungroupedDedupesLogicalDuplicateWindows() {
        let store = WindowStateStore()
        let config = Config(groupByApp: false)
        let bounds = WindowBounds(x: 100, y: 100, width: 1280, height: 800)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Ghostty", title: "~/project", bounds: bounds),
            makeTestWindow(
                id: 2,
                bundle: "com.app.Ghostty",
                title: "~/project",
                isMinimized: true,
                bounds: WindowBounds(x: 108, y: 100, width: 1280, height: 800)
            ),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 1)
        if case .window(let id, _, _, _, _, _, _) = items[0] {
            #expect(id.raw == 1)
        } else {
            Issue.record("Expected a deduped window item")
        }
    }

    @Test @MainActor func ungroupedPreservesDistinctSameTitleWindows() {
        let store = WindowStateStore()
        let config = Config(groupByApp: false)

        let windows = [
            makeTestWindow(
                id: 1,
                bundle: "com.app.Editor",
                title: "Untitled",
                bounds: WindowBounds(x: 0, y: 0, width: 640, height: 480)
            ),
            makeTestWindow(
                id: 2,
                bundle: "com.app.Editor",
                title: "Untitled",
                bounds: WindowBounds(x: 720, y: 0, width: 640, height: 480)
            ),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        let ids = items.compactMap { item -> UInt32? in
            if case .window(let id, _, _, _, _, _, _) = item {
                return id.raw
            }
            return nil
        }
        #expect(ids == [1, 2])
    }

    @Test @MainActor func testGrouped() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Safari", title: "GitHub"),
            makeTestWindow(id: 2, bundle: "com.app.Safari", title: "Google"),
            makeTestWindow(id: 3, bundle: "com.app.VSCode", title: "Editor"),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        // Safari grouped (2 windows) + VSCode single = 2 items
        #expect(items.count == 2)
    }

    @Test @MainActor func testGroupedAllWindowsPreservesFirstSeenBundleOrder() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true, windowDisplayMode: .allWindows)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Safari", title: "GitHub"),
            makeTestWindow(id: 2, bundle: "com.app.VSCode", title: "Editor", monitorId: 1),
            makeTestWindow(id: 3, bundle: "com.app.Safari", title: "Google", monitorId: 1),
            makeTestWindow(id: 4, bundle: "com.app.Terminal", title: "Shell"),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 3)

        if case .appGroup(let bundleId, _, let count, let groupedWindows, _, _, let screenId) = items[0] {
            #expect(bundleId == "com.app.Safari")
            #expect(count == 2)
            #expect(groupedWindows.map(\.raw) == [1, 3])
            #expect(screenId == 0)
        } else {
            Issue.record("Expected Safari to stay first as the first-seen grouped app")
        }

        if case .window(let id, let bundleId, _, _, _, _, let screenId) = items[1] {
            #expect(id.raw == 2)
            #expect(bundleId == "com.app.VSCode")
            #expect(screenId == 1)
        } else {
            Issue.record("Expected VSCode to stay second as the next first-seen app")
        }

        if case .window(let id, let bundleId, _, _, _, _, _) = items[2] {
            #expect(id.raw == 4)
            #expect(bundleId == "com.app.Terminal")
        } else {
            Issue.record("Expected Terminal to stay third as the final first-seen app")
        }
    }

    @Test @MainActor func testGroupedPerDisplay() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true, windowDisplayMode: .perDisplay)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Safari", title: "A", monitorId: 0),
            makeTestWindow(id: 2, bundle: "com.app.Safari", title: "B", monitorId: 1),
            makeTestWindow(id: 3, bundle: "com.app.Safari", title: "C", monitorId: 1),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        // Display 0: single Safari window. Display 1: Safari group.
        #expect(items.count == 2)
        #expect(items.contains { it in
            if case .window(_, let bundleId, _, _, _, _, let screenId) = it {
                return bundleId == "com.app.Safari" && screenId == 0
            }
            return false
        })
        #expect(items.contains { it in
            if case .appGroup(let bundleId, _, let count, _, _, _, let screenId) = it {
                return bundleId == "com.app.Safari" && count == 2 && screenId == 1
            }
            return false
        })
    }

    @Test @MainActor func testGroupedPerDisplayPreservesFirstSeenBundleDisplayOrder() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true, windowDisplayMode: .perDisplay)

        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Safari", title: "A", monitorId: 1),
            makeTestWindow(id: 2, bundle: "com.app.Chrome", title: "B", monitorId: 0),
            makeTestWindow(id: 3, bundle: "com.app.Safari", title: "C", monitorId: 0),
            makeTestWindow(id: 4, bundle: "com.app.Safari", title: "D", monitorId: 1),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 3)

        if case .appGroup(let bundleId, _, let count, let groupedWindows, _, _, let screenId) = items[0] {
            #expect(bundleId == "com.app.Safari")
            #expect(count == 2)
            #expect(groupedWindows.map(\.raw) == [1, 4])
            #expect(screenId == 1)
        } else {
            Issue.record("Expected display-1 Safari group to stay first")
        }

        if case .window(let id, let bundleId, _, _, _, _, let screenId) = items[1] {
            #expect(id.raw == 2)
            #expect(bundleId == "com.app.Chrome")
            #expect(screenId == 0)
        } else {
            Issue.record("Expected Chrome display-0 window to stay second")
        }

        if case .window(let id, let bundleId, _, _, _, _, let screenId) = items[2] {
            #expect(id.raw == 3)
            #expect(bundleId == "com.app.Safari")
            #expect(screenId == 0)
        } else {
            Issue.record("Expected display-0 Safari window to stay third")
        }
    }

    @Test @MainActor func testGroupedDedupesGhostDuplicates() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true)

        let sameBounds = WindowBounds(x: 100, y: 100, width: 1280, height: 800)
        let windows = [
            makeTestWindow(id: 1, bundle: "com.app.Ghostty", title: "~/project", bounds: sameBounds),
            makeTestWindow(id: 2, bundle: "com.app.Ghostty", title: "~/project", bounds: sameBounds),
            makeTestWindow(id: 3, bundle: "com.app.Ghostty", title: "~/project", bounds: sameBounds),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 1)
        if case .window(_, let bundleId, let title, _, _, _, _) = items[0] {
            #expect(bundleId == "com.app.Ghostty")
                #expect(title == "~/project")
        } else {
            Issue.record("Expected a single deduped window item")
        }
    }

    @Test @MainActor func testGroupedDedupesOverlapDuplicatesAcrossBuckets() {
        let store = WindowStateStore()
        let config = Config(groupByApp: true)

        // 17pt x-offset lands in a different 16pt bucket, but these are still
        // effectively the same window surface and should collapse.
        let windows = [
            makeTestWindow(
                id: 11,
                bundle: "com.app.Ghostty",
                title: "~/project",
                bounds: WindowBounds(x: 100, y: 100, width: 1280, height: 800)
            ),
            makeTestWindow(
                id: 12,
                bundle: "com.app.Ghostty",
                title: "~/project",
                bounds: WindowBounds(x: 117, y: 100, width: 1280, height: 800)
            ),
        ]
        _ = store.update(windows: windows, config: config)

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 1)
        if case .window(_, let bundleId, _, _, _, _, _) = items[0] {
            #expect(bundleId == "com.app.Ghostty")
        } else {
            Issue.record("Expected overlap duplicates to collapse to a single window item")
        }
    }

    @Test @MainActor func hiddenRetainedWindowRendersDimmedInPlace() {
        let store = WindowStateStore()
        var config = Config(groupByApp: false)
        config.showHiddenApps = true
        config.hiddenWindowMode = .inPlace

        let first = makeTestWindow(id: 1, bundle: "com.app.Hidden", title: "Hidden Window")
        let second = makeTestWindow(id: 2, bundle: "com.app.Visible", title: "Visible Window")
        _ = store.update(windows: [first, second], config: config)

        _ = store.update(
            windows: [second],
            config: config,
            hiddenBundleIds: ["com.app.Hidden"]
        )

        let items = UIRenderer.render(from: store, config: config)
        #expect(items.count == 2)
        #expect(items[0].bundleId == "com.app.Hidden")
        #expect(items[0].isHidden)
        #expect(items[0].isDimmed)
        #expect(items[1].bundleId == "com.app.Visible")
    }

    @Test @MainActor func testPinned() {
        let store = WindowStateStore()
        let config = Config()

        let windows = [makeTestWindow(id: 1, bundle: "com.app.Safari", title: "GitHub")]
        _ = store.update(windows: windows, config: config)

        let windowItems = UIRenderer.render(from: store, config: config)
        let composed = PinnedAppsComposer.compose(
            windowItems: windowItems,
            displayIds: [CGDirectDisplayID(0)],
            pinnedAppsByDisplay: [CGDirectDisplayID(0): ["com.app.Slack"]],
            windowDisplayMode: .perDisplay
        )
        let items = composed.items

        // Safari + Pinned Slack = 2
        #expect(items.count == 2)
        if case .pinnedApp(let bundleId, let screenId) = items[1] {
            #expect(bundleId == "com.app.Slack")
            #expect(screenId == 0)
        } else {
            Issue.record("Expected pinnedApp")
        }
    }

    @Test func testTruncation() {
        let item = TaskbarItem.window(
            id: WindowId(1),
            bundleId: "com.test",
            title: "A very long window title that should be truncated at some point",
            appName: "Test",
            isHidden: false,
            isMinimized: false,
            screenId: 0
        )
        let title = item.displayTitle(iconsOnly: false)
        #expect(title.count <= 30)
        #expect(title.hasSuffix("..."))
    }

    @Test func testKoreanTruncation() {
        let item = TaskbarItem.window(
            id: WindowId(1),
            bundleId: "com.upbit",
            title: "업비트 | 가장 신뢰받는 디지털 자산 거래소 - 대한민국 최고의 암호화폐",
            appName: "Upbit",
            isHidden: false,
            isMinimized: false,
            screenId: 0
        )
        let title = item.displayTitle(iconsOnly: false)
        #expect(title.count <= 30)
        #expect(title.hasSuffix("..."))
    }

    @Test func testIconsOnly() {
        let item = TaskbarItem.window(
            id: WindowId(1),
            bundleId: "com.test",
            title: "Some Title",
            appName: "Test",
            isHidden: false,
            isMinimized: false,
            screenId: 0
        )
        #expect(item.displayTitle(iconsOnly: true) == "")
    }

    @Test func testAppGroupDisplayTitleOmitsDuplicateCount() {
        let item = TaskbarItem.appGroup(
            bundleId: "com.app.Ghostty",
            appName: "Ghostty",
            windowCount: 3,
            windows: [WindowId(1), WindowId(2), WindowId(3)],
            isHidden: false,
            isMinimized: false,
            screenId: 0
        )
        #expect(item.displayTitle(iconsOnly: false) == "Ghostty")
    }
}
