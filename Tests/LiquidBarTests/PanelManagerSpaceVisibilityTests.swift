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
}
