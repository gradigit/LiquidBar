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

    @Test func flushBarsUseBorderlessHostForEveryPosition() {
        for position in [Position.top, .bottom, .left, .right] {
            let style = LiquidBarPanel.panelStyleMask(position: position, barStyle: .flush)
            #expect(style == [.nonactivatingPanel])
            #expect(style.contains(.nonactivatingPanel))
            #expect(!style.contains(.titled))
            #expect(!style.contains(.fullSizeContentView))
        }
    }

    @Test func floatingBarsKeepTitledHostForGlassCompatibility() {
        let style = LiquidBarPanel.panelStyleMask(position: .bottom, barStyle: .floating)

        #expect(style.contains(.titled))
        #expect(style.contains(.fullSizeContentView))
        #expect(style.contains(.nonactivatingPanel))
    }

    @Test func borderlessBottomFlushDoesNotOverscanOuterDesktopEdges() {
        let geometry = LiquidBarPanel.computeGeometry(
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 870),
            globalFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            barHeight: 32,
            position: .bottom,
            barStyle: .flush
        )

        #expect(geometry.frame == NSRect(x: 0, y: 0, width: 1440, height: 32))
        #expect(geometry.contentInsetLeft == 0)
        #expect(geometry.contentInsetRight == 0)
    }

    @Test func borderlessTopFlushUsesVisibleTopWithoutHorizontalOverscan() {
        let geometry = LiquidBarPanel.computeGeometry(
            screenFrame: NSRect(x: -1440, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: -1440, y: 0, width: 1440, height: 870),
            globalFrame: NSRect(x: -1440, y: 0, width: 2880, height: 900),
            barHeight: 32,
            position: .top,
            barStyle: .flush
        )

        #expect(geometry.frame == NSRect(x: -1440, y: 838, width: 1440, height: 32))
        #expect(geometry.contentInsetLeft == 0)
        #expect(geometry.contentInsetRight == 0)
    }
}
