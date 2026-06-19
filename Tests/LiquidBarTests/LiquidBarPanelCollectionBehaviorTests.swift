import AppKit
import Testing
@testable import LiquidBar

@Suite
struct LiquidBarPanelCollectionBehaviorTests {
    @Test func taskbarDoesNotOptIntoFullscreenAuxiliarySpaces() {
        let taskbar = LiquidBarPanel.taskbarCollectionBehavior()
        let cornerFill = LiquidBarPanel.cornerFillCollectionBehavior()

        #expect(taskbar.contains(.canJoinAllSpaces))
        #expect(taskbar.contains(.stationary))
        #expect(taskbar.contains(.ignoresCycle))
        #expect(!taskbar.contains(.fullScreenAuxiliary))
        #expect(cornerFill == taskbar)
    }
}
