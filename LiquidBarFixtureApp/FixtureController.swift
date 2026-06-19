import AppKit

@MainActor
final class FixtureController {
    private var windows: [NSWindow] = []

    func bootstrapFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        let count = Int(env["FIXTURE_WINDOW_COUNT"] ?? "") ?? 5
        let longTitles = (env["FIXTURE_LONG_TITLES"] ?? "0") == "1"

        for i in 1...max(0, count) {
            createWindow(index: i, longTitle: longTitles)
        }
    }

    func teardown() {
        for w in windows {
            w.close()
        }
        windows.removeAll()
    }

    private func createWindow(index: Int, longTitle: Bool) {
        let baseTitle = "Fixture Window \(index)"
        let title: String
        if longTitle {
            title = "\(baseTitle) - This is a deliberately long title used to validate truncation behavior in LiquidBar"
        } else {
            title = baseTitle
        }

        let rect = NSRect(x: 100 + (index * 30), y: 200 + (index * 20), width: 640, height: 420)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("fixture.window.\(index)")

        // Deterministic, visually distinct content (useful for thumbnail/previews).
        let content = NSView(frame: NSRect(x: 0, y: 0, width: rect.width, height: rect.height))
        content.wantsLayer = true
        content.layer?.backgroundColor = colorForIndex(index).cgColor

        let label = NSTextField(labelWithString: "Fixture Window \(index)")
        label.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        window.contentView = content
        window.makeKeyAndOrderFront(nil)

        windows.append(window)
    }

    private func colorForIndex(_ index: Int) -> NSColor {
        // Fixed palette to keep UI tests + visual diffs stable.
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.95, alpha: 1.0),
            NSColor(calibratedRed: 0.75, green: 0.25, blue: 0.35, alpha: 1.0),
            NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.45, alpha: 1.0),
            NSColor(calibratedRed: 0.65, green: 0.35, blue: 0.85, alpha: 1.0),
            NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.20, alpha: 1.0),
        ]
        return palette[(index - 1) % palette.count]
    }
}
