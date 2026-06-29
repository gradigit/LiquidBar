import CoreGraphics
import Testing
@testable import LiquidBar

@Suite
struct PanelManagerSpaceVisibilityTests {
    @Test func desktopSpacesDoNotSuppressTaskbar() {
        #expect(
            PanelManager.shouldSuppressTaskbar(
                currentSpace: .init(key: "123", type: SpacesService.CurrentSpaceInfo.desktopType)
            ) == false
        )
    }

    @Test func fullscreenOrSpecialSpacesSuppressTaskbar() {
        #expect(
            PanelManager.shouldSuppressTaskbar(
                currentSpace: .init(key: "456", type: 4)
            ) == true
        )
    }

    @Test func taskbarSpaceTransitionTracksSuppressedAndRestoredDisplays() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let transition = PanelManager.taskbarSpaceTransition(
            currentSpaceInfoByDisplay: [
                display1: .init(key: "111", type: 4),
                display2: .init(key: "222", type: SpacesService.CurrentSpaceInfo.desktopType)
            ],
            previousSuppressed: [display2]
        )

        #expect(transition.suppressed == [display1])
        #expect(transition.restored == [display2])
    }

    @Test func fullscreenWindowCoverSuppressesOnlyCoveredDisplay() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900),
                    monitorId: display1
                )
            ],
            displayBoundsById: [
                display1: CGRect(x: 0, y: 0, width: 1440, height: 900),
                display2: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
            ]
        )

        #expect(covered == [display1])
    }

    @Test func maximizedWindowBelowMenuBarDoesNotSuppressTaskbar() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(
                    bounds: WindowBounds(x: 0, y: 25, width: 1440, height: 875),
                    monitorId: display
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ]
        )

        #expect(covered.isEmpty)
    }

    @Test func hiddenMinimizedAndSystemWindowsDoNotSuppressTaskbar() {
        let display: CGDirectDisplayID = 1
        let bounds = WindowBounds(x: 0, y: 0, width: 1440, height: 900)
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(id: 1, bundleId: "com.example.hidden", isHidden: true, bounds: bounds, monitorId: display),
                makeWindow(id: 2, bundleId: "com.example.minimized", isMinimized: true, bounds: bounds, monitorId: display),
                makeWindow(id: 3, bundleId: "com.apple.dock", bounds: bounds, monitorId: display)
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ]
        )

        #expect(covered.isEmpty)
    }

    private func makeWindow(
        id: UInt32 = 1,
        bundleId: String = "com.example.app",
        isHidden: Bool = false,
        isMinimized: Bool = false,
        bounds: WindowBounds,
        monitorId: CGDirectDisplayID
    ) -> WindowInfo {
        WindowInfo(
            id: WindowId(id),
            bundleId: BundleId(bundleId),
            appName: "Example",
            title: "Window",
            isHidden: isHidden,
            isMinimized: isMinimized,
            monitorId: MonitorId(UInt32(monitorId)),
            bounds: bounds
        )
    }
}
