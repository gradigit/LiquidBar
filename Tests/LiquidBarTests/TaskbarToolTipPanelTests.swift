import AppKit
import Testing
@testable import LiquidBar

@Suite("Taskbar tooltip panel")
struct TaskbarToolTipPanelTests {
    @MainActor
    @Test func systemMetricLabelsFitWithoutTruncation() {
        let panel = TaskbarToolTipPanel(theme: .system, glassStyle: .publicRegular)

        for text in ["CPU Usage: 91%", "Memory Usage: 100%", "CPU \u{c0ac}\u{c6a9}\u{b7c9}: 91%"] {
            let layout = panel.textLayout(for: text)
            #expect(layout.labelFrame.width >= layout.fittingSize.width + 4)
            #expect(layout.labelFrame.height >= layout.fittingSize.height)
        }
    }

    @Test func horizontalPlacementTracksTaskbarEdgeAndClampsToScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = NSSize(width: 140, height: 28)

        let bottom = TaskbarToolTipPanel.frame(
            size: size,
            anchorRect: NSRect(x: 900, y: 0, width: 90, height: 36),
            screenFrame: screen,
            position: .bottom
        )
        #expect(bottom.minY > 36)
        #expect(bottom.maxX <= screen.maxX - 6)

        let top = TaskbarToolTipPanel.frame(
            size: size,
            anchorRect: NSRect(x: 0, y: 664, width: 90, height: 36),
            screenFrame: screen,
            position: .top
        )
        #expect(top.maxY < 664)
        #expect(top.minX >= screen.minX + 6)
    }

    @Test func verticalPlacementTracksTaskbarEdge() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let size = NSSize(width: 140, height: 28)
        let anchor = NSRect(x: 0, y: 300, width: 40, height: 40)

        let left = TaskbarToolTipPanel.frame(
            size: size,
            anchorRect: anchor,
            screenFrame: screen,
            position: .left
        )
        #expect(left.minX > anchor.maxX)

        let right = TaskbarToolTipPanel.frame(
            size: size,
            anchorRect: NSRect(x: 960, y: 300, width: 40, height: 40),
            screenFrame: screen,
            position: .right
        )
        #expect(right.maxX < 960)
    }
}
