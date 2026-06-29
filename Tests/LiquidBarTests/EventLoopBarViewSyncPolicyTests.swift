import CoreFoundation
import Testing
@testable import LiquidBar

@Suite
struct EventLoopBarViewSyncPolicyTests {
    private func snapshot(
        pinnedBundleIds: Set<String> = [],
        userCustomItemIds: Set<String> = [],
        windowTabGroupsEnabled: Bool = false,
        tabGroups: [TabGroup] = [],
        windowIdToGroupId: [UInt32: String] = [:]
    ) -> BarViewDataSnapshot {
        let sharedSignature = EventLoop.sharedBarViewDataSignature(
            userCustomItemIds: userCustomItemIds,
            windowTabGroupsEnabled: windowTabGroupsEnabled,
            tabGroups: tabGroups,
            windowIdToGroupId: windowIdToGroupId
        )
        return EventLoop.makeBarViewDataSnapshot(
            pinnedBundleIds: pinnedBundleIds,
            sharedSignature: sharedSignature
        )
    }

    @Test func identicalSnapshotSkipsExistingBarViewSync() {
        let current = snapshot(
            pinnedBundleIds: ["com.apple.Terminal"],
            userCustomItemIds: ["cpu"],
            windowTabGroupsEnabled: true,
            tabGroups: [TabGroup(name: "Research", windowIds: [10, 20])],
            windowIdToGroupId: [10: "research"]
        )

        #expect(
            EventLoop.shouldSynchronizeBarViewData(
                previous: current,
                current: current,
                isNewBarView: false
            ) == false
        )
    }

    @Test func newBarViewAlwaysSyncs() {
        let current = snapshot(pinnedBundleIds: ["com.apple.Terminal"])

        #expect(
            EventLoop.shouldSynchronizeBarViewData(
                previous: current,
                current: current,
                isNewBarView: true
            )
        )
    }

    @Test func pinnedBundleChangeForcesSync() {
        let previous = snapshot(pinnedBundleIds: ["com.apple.Terminal"])
        let current = snapshot(pinnedBundleIds: ["com.apple.Terminal", "com.apple.finder"])

        #expect(
            EventLoop.shouldSynchronizeBarViewData(
                previous: previous,
                current: current,
                isNewBarView: false
            )
        )
    }

    @Test func sharedTabGroupMappingChangeForcesSync() {
        let previous = snapshot(
            userCustomItemIds: ["cpu"],
            windowTabGroupsEnabled: true,
            tabGroups: [TabGroup(id: "research", name: "Research", windowIds: [10])],
            windowIdToGroupId: [10: "research"]
        )
        let current = snapshot(
            userCustomItemIds: ["cpu"],
            windowTabGroupsEnabled: true,
            tabGroups: [TabGroup(id: "research", name: "Research", windowIds: [10, 11])],
            windowIdToGroupId: [10: "research", 11: "research"]
        )

        #expect(
            EventLoop.shouldSynchronizeBarViewData(
                previous: previous,
                current: current,
                isNewBarView: false
            )
        )
    }

    @Test func screenChangeRecoveryUsesStaggeredPollingOnly() {
        let delays = EventLoop.screenChangeRecoveryDelays
        #expect(delays == delays.sorted())
        #expect(delays.first == 0.05)
        #expect(delays.contains(where: { $0 >= 1.0 }))
    }

    @Test func screenChangeSuppressesWindowAdjustmentDuringDisplayRestore() {
        let lastScreenChangeAt: CFAbsoluteTime = 100

        #expect(
            EventLoop.shouldSuppressWindowAdjustmentForScreenChange(
                now: 100,
                lastScreenChangeAt: lastScreenChangeAt
            )
        )
        #expect(
            EventLoop.shouldSuppressWindowAdjustmentForScreenChange(
                now: 107.99,
                lastScreenChangeAt: lastScreenChangeAt
            )
        )
        #expect(
            EventLoop.shouldSuppressWindowAdjustmentForScreenChange(
                now: 108.01,
                lastScreenChangeAt: lastScreenChangeAt
            ) == false
        )
        #expect(
            EventLoop.shouldSuppressWindowAdjustmentForScreenChange(
                now: 108.01,
                lastScreenChangeAt: 0
            ) == false
        )
    }

    @Test func spaceChangeRecoveryUsesSparseDelayedPolls() {
        let delays = EventLoop.spaceChangeRecoveryDelays
        #expect(delays == delays.sorted())
        #expect(delays == [0.15, 0.45, 1.00])
        #expect(delays.count == 3)
    }

    @Test func visibleReorderPlanUsesVisibleItemIndicesForWindowOrder() {
        let items: [TaskbarItem] = [
            .launcher(screenId: 1),
            .appGroup(
                bundleId: "com.app.alpha",
                appName: "Alpha",
                windowCount: 2,
                windows: [WindowId(10), WindowId(11)],
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
            .pinnedApp(bundleId: "com.app.pinned", screenId: 1),
        ]

        let plan = EventLoop.visibleReorderPlan(items: items, from: 1, to: 3, tabGroups: [])

        #expect(plan?.windowOrder == [20, 10, 11])
        #expect(plan?.appOrder == ["com.app.beta", "com.app.alpha", "com.app.pinned"])
        #expect(plan?.pinnedOrder == ["com.app.pinned"])
        #expect(plan?.itemOrder == [
            "launcher:1",
            "window:20",
            "app-group:1:com.app.alpha",
            "pinned:1:com.app.pinned",
        ])
    }

    @Test func visibleReorderPlanExpandsTabGroupWindowIds() {
        let items: [TaskbarItem] = [
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
            .tabGroup(
                id: "research",
                representativeBundleId: "com.app.alpha",
                name: "Research",
                emoji: nil,
                windowCount: 2,
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
        ]
        let groups = [TabGroup(id: "research", name: "Research", windowIds: [10, 11])]

        let plan = EventLoop.visibleReorderPlan(items: items, from: 1, to: 0, tabGroups: groups)

        #expect(plan?.windowOrder == [10, 11, 20])
        #expect(plan?.appOrder == ["com.app.alpha", "com.app.beta"])
        #expect(plan?.itemOrder == ["tab-group:1:research", "window:20"])
    }

    @Test func visibleReorderPlanIncludesSystemIndicatorItemIdentity() {
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
        ]

        let plan = EventLoop.visibleReorderPlan(items: items, from: 0, to: 2, tabGroups: [])

        #expect(plan?.itemOrder == ["window:20", "system:all:system.cpu"])
    }

    @Test func preferredSystemIndicatorOrderReordersMetricClusterOnly() {
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
            .customText(id: "system.gpu", text: "GPU 7%", screenId: nil),
            .customText(id: "system.ram", text: "RAM 63%", screenId: nil),
        ]

        let reordered = EventLoop.applyPreferredSystemIndicatorOrder(
            items,
            preferred: ["system.ram", "system.cpu"]
        )

        #expect(reordered.map(\.bundleId) == [
            "custom:text:system.ram",
            "custom:text:system.cpu",
            "custom:text:system.gpu",
        ])
    }

    @Test func systemIndicatorMetricOrderAfterReorderAllowsInternalClusterMove() {
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
            .customText(id: "system.gpu", text: "GPU 7%", screenId: nil),
            .customText(id: "system.ram", text: "RAM 63%", screenId: nil),
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
        ]

        let order = EventLoop.systemIndicatorMetricOrderAfterReorder(items: items, from: 0, to: 3)

        #expect(order == ["system.gpu", "system.ram", "system.cpu"])
    }

    @Test func systemIndicatorMetricOrderAfterReorderRejectsMovesOutsideCluster() {
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
            .customText(id: "system.gpu", text: "GPU 7%", screenId: nil),
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
        ]

        #expect(EventLoop.systemIndicatorMetricOrderAfterReorder(items: items, from: 0, to: 3) == nil)
        #expect(EventLoop.systemIndicatorMetricOrderAfterReorder(items: items, from: 2, to: 0) == nil)
    }

    @Test func visibleReorderPlanRejectsNoOpMoves() {
        let items: [TaskbarItem] = [
            .window(
                id: WindowId(20),
                bundleId: "com.app.beta",
                title: "Beta",
                appName: "Beta",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
            .window(
                id: WindowId(30),
                bundleId: "com.app.gamma",
                title: "Gamma",
                appName: "Gamma",
                isHidden: false,
                isMinimized: false,
                screenId: 1
            ),
        ]

        #expect(EventLoop.visibleReorderPlan(items: items, from: 0, to: 0, tabGroups: []) == nil)
        #expect(EventLoop.visibleReorderPlan(items: items, from: 0, to: 1, tabGroups: []) == nil)
        #expect(EventLoop.visibleReorderPlan(items: items, from: -1, to: 1, tabGroups: []) == nil)
    }
}
