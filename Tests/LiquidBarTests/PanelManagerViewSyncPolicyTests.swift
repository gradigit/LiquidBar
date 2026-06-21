import Testing
import AppKit
@testable import LiquidBar

@Suite
struct PanelManagerViewSyncPolicyTests {
    private func snapshot(
        items: [TaskbarItem],
        focus: FocusInfo = .none,
        sidebarExpanded: Bool = false,
        width: CGFloat = 1200,
        height: CGFloat = 56,
        config: Config = Config()
    ) -> ViewSyncSnapshot {
        PanelManager.makeViewSyncSnapshot(
            items: items,
            config: config,
            focus: focus,
            sidebarExpanded: sidebarExpanded,
            panelWidth: width,
            panelHeight: height
        )
    }

    @Test func reusedStaticStateWithMatchingSnapshotSkipsBarViewSync() {
        let items: [TaskbarItem] = [.customText(id: "cpu", text: "42%", screenId: 1)]
        let current = snapshot(items: items)

        #expect(
            PanelManager.shouldSynchronizeBarView(
                previous: current,
                current: current,
                rendererResult: .reusedStaticState
            ) == false
        )
    }

    @Test func reusedStaticStateStillSyncsWhenGeometryChanges() {
        let items: [TaskbarItem] = [.customText(id: "cpu", text: "42%", screenId: 1)]
        let previous = snapshot(items: items, width: 1200, height: 56)
        let current = snapshot(items: items, width: 1280, height: 56)

        #expect(
            PanelManager.shouldSynchronizeBarView(
                previous: previous,
                current: current,
                rendererResult: .reusedStaticState
            )
        )
    }

    @Test func rebuiltStaticStateAlwaysSyncs() {
        let items: [TaskbarItem] = [.customText(id: "cpu", text: "42%", screenId: 1)]
        let previous = snapshot(items: items)
        let current = snapshot(
            items: [.customText(id: "cpu", text: "55%", screenId: 1)]
        )

        #expect(
            PanelManager.shouldSynchronizeBarView(
                previous: previous,
                current: current,
                rendererResult: .rebuiltStaticState
            )
        )
    }

    @Test func runtimeOnlyConfigChangesDoNotForceViewSyncWhenRendererReusesState() {
        let items: [TaskbarItem] = [.customText(id: "cpu", text: "42%", screenId: 1)]
        var previousConfig = Config()
        previousConfig.performanceLoggingEnabled = false
        previousConfig.adjustWindowsForTaskbar = true

        var currentConfig = previousConfig
        currentConfig.performanceLoggingEnabled = true
        currentConfig.performanceGpuTimingEnabled.toggle()
        currentConfig.performanceLogIntervalMs += 250
        currentConfig.adjustWindowsForTaskbar = false

        #expect(
            PanelManager.shouldSynchronizeBarView(
                previous: snapshot(items: items, config: previousConfig),
                current: snapshot(items: items, config: currentConfig),
                rendererResult: .reusedStaticState
            ) == false
        )
    }

    @Test func panelThicknessUsesEffectiveTaskbarHeight() {
        #expect(PanelManager.panelThickness(for: Config(taskbarHeight: 32, iconSize: 28)) == 32)
        #expect(PanelManager.panelThickness(for: Config(taskbarHeight: 32, iconSize: 40)) == 40)
        #expect(PanelManager.panelThickness(for: Config(taskbarHeight: 48, iconSize: 24)) == 48)
    }
}
