import AppKit
import Foundation
import Testing
@testable import LiquidBar

@Suite("Taskbar overflow planner")
struct TaskbarOverflowPlannerTests {
    @Test func exactFitPreservesItemsAndSourceIndices() {
        let items = (1...4).map(Self.window)

        let plan = TaskbarOverflowPlanner.plan(
            items: items,
            displayId: 7,
            focusedWindowId: nil,
            fits: { $0.count <= 4 }
        )

        #expect(plan.overflowWindowIds.isEmpty)
        #expect(plan.sourceIndices == [0, 1, 2, 3])
        #expect(Self.windowIds(in: plan.items) == [1, 2, 3, 4])
    }

    @Test func trailingWindowsCollapseIntoOneStableItem() {
        let items = (1...6).map(Self.window)

        let plan = TaskbarOverflowPlanner.plan(
            items: items,
            displayId: 7,
            focusedWindowId: nil,
            fits: { $0.count <= 4 }
        )

        #expect(Self.windowIds(in: plan.items) == [1, 2, 3])
        #expect(plan.overflowWindowIds.map { $0.raw } == [4, 5, 6])
        #expect(plan.sourceIndices == [0, 1, 2, nil])
        guard let overflow = plan.items.last else {
            Issue.record("Expected a trailing overflow item")
            return
        }
        guard case .windowOverflow(let windows, let screenId) = overflow else {
            Issue.record("Expected a trailing overflow item")
            return
        }
        #expect(windows.map { $0.raw } == [4, 5, 6])
        #expect(screenId == 7)
    }

    @Test func focusedTrailingWindowRemainsDirectlyReachable() {
        let items = (1...6).map(Self.window)

        let plan = TaskbarOverflowPlanner.plan(
            items: items,
            displayId: 7,
            focusedWindowId: 6,
            fits: { $0.count <= 4 }
        )

        #expect(Self.windowIds(in: plan.items) == [1, 2, 6])
        #expect(plan.overflowWindowIds.map { $0.raw } == [3, 4, 5])
        #expect(plan.sourceIndices == [0, 1, nil, 5])
    }

    @Test func fixedItemsAreNeverRemoved() {
        let items: [TaskbarItem] = [
            .launcher(screenId: 7),
            Self.window(1),
            Self.window(2),
            Self.window(3),
            Self.window(4),
            .customText(id: "system.cpu", text: "CPU 42%", screenId: 7),
        ]

        let plan = TaskbarOverflowPlanner.plan(
            items: items,
            displayId: 7,
            focusedWindowId: nil,
            fits: { $0.count <= 4 }
        )

        #expect(plan.items.contains { if case .launcher = $0 { return true }; return false })
        #expect(plan.items.contains { if case .customText = $0 { return true }; return false })
        #expect(plan.overflowWindowIds.map { $0.raw } == [2, 3, 4])
    }

    @Test @MainActor func crowdedBarABBenchmarkCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_TASKBAR_OVERFLOW_BENCHMARK_PATH"],
              !outputPath.isEmpty else { return }

        let displayId: CGDirectDisplayID = 77
        let barWidth: Float = 820
        let items = (1...60).map(Self.window)
        let config = Config(taskbarHeight: 36, iconSize: 22, itemSizing: .auto)
        let baselineRenderer = NativeBarRenderer()
        let candidateRenderer = NativeBarRenderer()
        let baselineIcons = IconCache()
        let candidateIcons = IconCache()
        baselineRenderer.registerPanel(displayId: displayId, barWidth: barWidth, barHeight: 36, scale: 2)
        candidateRenderer.registerPanel(displayId: displayId, barWidth: barWidth, barHeight: 36, scale: 2)
        defer {
            baselineRenderer.shutdown()
            candidateRenderer.shutdown()
        }

        func focus(_ iteration: Int) -> FocusInfo {
            let id = UInt32((iteration % items.count) + 1)
            return FocusInfo(windowId: id, bundleId: "com.example.app\(id)", tabGroupId: nil)
        }

        for iteration in 0..<20 {
            let currentFocus = focus(iteration)
            baselineRenderer.updateItems(
                items,
                config: config,
                iconCache: baselineIcons,
                displayId: displayId,
                focus: currentFocus
            )
            let plan = candidateRenderer.overflowPlan(
                for: items,
                config: config,
                primaryLength: barWidth,
                displayId: displayId,
                focus: currentFocus
            )
            candidateRenderer.updateItems(
                plan.items,
                config: config,
                iconCache: candidateIcons,
                displayId: displayId,
                focus: currentFocus
            )
        }

        let iterations = 300
        var baselineMs: [Double] = []
        var candidateMs: [Double] = []
        baselineMs.reserveCapacity(iterations)
        candidateMs.reserveCapacity(iterations)
        var candidateVisibleItemCount = 0

        for iteration in 0..<iterations {
            let currentFocus = focus(iteration)
            var started = CFAbsoluteTimeGetCurrent()
            baselineRenderer.updateItems(
                items,
                config: config,
                iconCache: baselineIcons,
                displayId: displayId,
                focus: currentFocus
            )
            baselineMs.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)

            started = CFAbsoluteTimeGetCurrent()
            let plan = candidateRenderer.overflowPlan(
                for: items,
                config: config,
                primaryLength: barWidth,
                displayId: displayId,
                focus: currentFocus
            )
            candidateRenderer.updateItems(
                plan.items,
                config: config,
                iconCache: candidateIcons,
                displayId: displayId,
                focus: currentFocus
            )
            candidateMs.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)
            candidateVisibleItemCount = plan.items.count
        }

        let baselineP50 = Self.percentile(baselineMs, 0.50)
        let baselineP95 = Self.percentile(baselineMs, 0.95)
        let candidateP50 = Self.percentile(candidateMs, 0.50)
        let candidateP95 = Self.percentile(candidateMs, 0.95)
        let payload: [String: Any] = [
            "schema_version": 1,
            "iterations": iterations,
            "window_count": items.count,
            "candidate_visible_item_count": candidateVisibleItemCount,
            "baseline_direct_render_p50_ms": baselineP50,
            "baseline_direct_render_p95_ms": baselineP95,
            "candidate_overflow_plan_and_render_p50_ms": candidateP50,
            "candidate_overflow_plan_and_render_p95_ms": candidateP95,
        ]
        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)

        print(
            "TASKBAR_OVERFLOW_AB baseline_p95_ms=\(baselineP95) " +
                "candidate_p95_ms=\(candidateP95) visible_items=\(candidateVisibleItemCount)"
        )
        #expect(candidateP95 < max(5.0, baselineP95 * 5.0))
    }

    private static func window(_ id: Int) -> TaskbarItem {
        .window(
            id: WindowId(UInt32(id)),
            bundleId: "com.example.app\(id)",
            title: "Window \(id)",
            appName: "App \(id)",
            isHidden: false,
            isMinimized: false,
            screenId: 7
        )
    }

    private static func windowIds(in items: [TaskbarItem]) -> [UInt32] {
        items.compactMap { item in
            guard case .window(let id, _, _, _, _, _, _) = item else { return nil }
            return id.raw
        }
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * percentile).rounded())
        return sorted[max(0, min(index, sorted.count - 1))]
    }
}
