import Darwin
import Testing
@testable import LiquidBar

@Suite("WindowManager AX Gating")
struct WindowManagerAXGatingTests {
    @Test func distinctMultiWindowAppsDoNotNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document A", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Document B", bounds: WindowBounds(x: 520, y: 0, width: 500, height: 400)),
            entry(id: 3, pid: 99, title: "Other", bounds: WindowBounds(x: 0, y: 420, width: 500, height: 400)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries).isEmpty)
    }

    @Test func overlappingSameTitleWindowsNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Document", bounds: WindowBounds(x: 10, y: 10, width: 500, height: 400)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries) == [42])
    }

    @Test func tinySurfaceWindowsNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Palette", bounds: WindowBounds(x: 0, y: 0, width: 1, height: 1)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries) == [42])
    }

    @Test func minimizedAXStateIsOnlyQueriedForVisibleMinimizedCandidates() {
        #expect(WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: true,
            axEnabled: true
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: false,
            axEnabled: true
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: true,
            axEnabled: false
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: true,
            showMinimizedWindows: true,
            axEnabled: true
        ))
    }

    private func entry(
        id: UInt32,
        pid: pid_t,
        title: String,
        bounds: WindowBounds
    ) -> (info: WindowInfo, pid: pid_t) {
        (
            info: WindowInfo(
                id: WindowId(id),
                bundleId: BundleId("com.example.app"),
                appName: "Example",
                title: title,
                isHidden: false,
                isMinimized: false,
                monitorId: MonitorId(1),
                bounds: bounds
            ),
            pid: pid
        )
    }
}
