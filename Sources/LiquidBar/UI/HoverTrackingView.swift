import AppKit

/// Simple hover enter/exit callbacks for overlay panels.
///
/// We use this to keep hover-driven popups alive while the cursor transitions
/// from the taskbar into the popup (Windows-style thumbnail pickers).
@MainActor
final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let tracking {
            removeTrackingArea(tracking)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseEnteredAndExited,
        ]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }
}

