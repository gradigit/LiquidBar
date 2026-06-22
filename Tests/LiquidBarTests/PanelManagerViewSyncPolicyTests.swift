import Testing
import AppKit
@testable import LiquidBar

@Suite
struct PanelManagerViewSyncPolicyTests {
    private func snapshot(
        items: [TaskbarItem],
        systemIndicatorVisuals: [String: SystemIndicatorVisual] = [:],
        focus: FocusInfo = .none,
        sidebarExpanded: Bool = false,
        width: CGFloat = 1200,
        height: CGFloat = 56,
        config: Config = Config()
    ) -> ViewSyncSnapshot {
        PanelManager.makeViewSyncSnapshot(
            items: items,
            systemIndicatorVisuals: systemIndicatorVisuals,
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

    @Test func reusedStaticStateStillSyncsWhenSystemIndicatorVisualChanges() {
        let items: [TaskbarItem] = [.customText(id: "system.cpu", text: "CPU 42%", screenId: 1)]
        let previous = snapshot(
            items: items,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "42%", value: 42, history: [31, 42])
            ]
        )
        let current = snapshot(
            items: items,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [31, 42, 55])
            ]
        )

        #expect(
            PanelManager.shouldSynchronizeBarView(
                previous: previous,
                current: current,
                rendererResult: .reusedStaticState
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
        currentConfig.performanceHangDiagnosticsEnabled = true
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

    private func systemVisual(
        metric: SystemIndicatorMetric,
        mode: SystemIndicatorVisualMode,
        valueText: String,
        value: Float?,
        history: [Float]
    ) -> SystemIndicatorVisual {
        SystemIndicatorVisual(
            metric: metric,
            mode: mode,
            label: metric.label,
            valueText: valueText,
            valuePercent: value,
            history: history,
            severity: 0.2
        )
    }
}
