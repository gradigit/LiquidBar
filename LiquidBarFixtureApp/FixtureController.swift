import AppKit

@MainActor
final class FixtureController {
    private var windows: [NSWindow] = []

    func bootstrapFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if env["FIXTURE_README_DEMO"] == "1" {
            createReadmeDemoWindows()
            return
        }

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

    private func createReadmeDemoWindows() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 120, width: 1440, height: 840)
        let specs = readmeDemoWindowSpecs(in: visible)

        for (idx, spec) in specs.enumerated() {
            createDemoWindow(
                index: idx + 1,
                title: spec.title,
                subtitle: spec.subtitle,
                rect: spec.rect,
                paletteIndex: idx
            )
        }
    }

    private struct DemoWindowSpec {
        var title: String
        var subtitle: String
        var rect: NSRect
    }

    private func readmeDemoWindowSpecs(in screen: NSRect) -> [DemoWindowSpec] {
        func clampedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
            let w = min(width, max(320, screen.width - 80))
            let h = min(height, max(240, screen.height - 120))
            let minX = screen.minX + 32
            let maxX = screen.maxX - w - 32
            let minY = screen.minY + 92
            let maxY = screen.maxY - h - 44
            return NSRect(
                x: min(max(x, minX), max(minX, maxX)),
                y: min(max(y, minY), max(minY, maxY)),
                width: w,
                height: h
            )
        }

        let wide = min(max(screen.width * 0.38, 620), 900)
        let mid = min(max(screen.width * 0.32, 520), 760)
        let portrait = min(max(screen.width * 0.20, 340), 440)
        let square = min(max(screen.width * 0.25, 420), 560)

        return [
            DemoWindowSpec(
                title: "Design Review",
                subtitle: "Wide document window",
                rect: clampedRect(
                    x: screen.minX + 72,
                    y: screen.maxY - 80 - 500,
                    width: wide,
                    height: 500
                )
            ),
            DemoWindowSpec(
                title: "Metrics Dashboard",
                subtitle: "Compact analytics window",
                rect: clampedRect(
                    x: screen.midX - 220,
                    y: screen.maxY - 114 - 420,
                    width: mid,
                    height: 420
                )
            ),
            DemoWindowSpec(
                title: "Notes",
                subtitle: "Portrait window",
                rect: clampedRect(
                    x: screen.midX - 120,
                    y: screen.minY + 150,
                    width: portrait,
                    height: 640
                )
            ),
            DemoWindowSpec(
                title: "Release Checklist",
                subtitle: "Square utility window",
                rect: clampedRect(
                    x: screen.maxX - square - 92,
                    y: screen.minY + 180,
                    width: square,
                    height: square
                )
            ),
            DemoWindowSpec(
                title: "Terminal Session",
                subtitle: "Narrow tool window",
                rect: clampedRect(
                    x: screen.maxX - 440,
                    y: screen.maxY - 96 - 610,
                    width: 360,
                    height: 610
                )
            ),
        ]
    }

    private func createDemoWindow(index: Int, title: String, subtitle: String, rect: NSRect, paletteIndex: Int) {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("fixture.readme.window.\(index)")
        window.contentView = DemoContentView(
            frame: NSRect(origin: .zero, size: rect.size),
            title: title,
            subtitle: subtitle,
            palette: demoPalette(index: paletteIndex)
        )
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    fileprivate struct DemoPalette {
        var top: NSColor
        var bottom: NSColor
        var accent: NSColor
    }

    private func demoPalette(index: Int) -> DemoPalette {
        let palettes: [DemoPalette] = [
            DemoPalette(
                top: NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.29, alpha: 1.0),
                bottom: NSColor(calibratedRed: 0.18, green: 0.37, blue: 0.58, alpha: 1.0),
                accent: NSColor(calibratedRed: 0.51, green: 0.78, blue: 1.00, alpha: 1.0)
            ),
            DemoPalette(
                top: NSColor(calibratedRed: 0.18, green: 0.11, blue: 0.22, alpha: 1.0),
                bottom: NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.52, alpha: 1.0),
                accent: NSColor(calibratedRed: 0.92, green: 0.68, blue: 1.00, alpha: 1.0)
            ),
            DemoPalette(
                top: NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.18, alpha: 1.0),
                bottom: NSColor(calibratedRed: 0.17, green: 0.45, blue: 0.35, alpha: 1.0),
                accent: NSColor(calibratedRed: 0.58, green: 0.92, blue: 0.72, alpha: 1.0)
            ),
            DemoPalette(
                top: NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.08, alpha: 1.0),
                bottom: NSColor(calibratedRed: 0.62, green: 0.45, blue: 0.16, alpha: 1.0),
                accent: NSColor(calibratedRed: 1.00, green: 0.79, blue: 0.34, alpha: 1.0)
            ),
            DemoPalette(
                top: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1.0),
                bottom: NSColor(calibratedRed: 0.31, green: 0.34, blue: 0.43, alpha: 1.0),
                accent: NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.93, alpha: 1.0)
            ),
        ]
        return palettes[index % palettes.count]
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

private final class DemoContentView: NSView {
    private let title: String
    private let subtitle: String
    private let palette: FixtureController.DemoPalette

    init(frame: NSRect, title: String, subtitle: String, palette: FixtureController.DemoPalette) {
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let gradient = NSGradient(starting: palette.top, ending: palette.bottom)
        gradient?.draw(in: bounds, angle: 270)

        drawChrome(in: bounds)
        drawCards(in: bounds)
        drawTitle(in: bounds)
    }

    private func drawChrome(in bounds: NSRect) {
        let header = NSRect(x: 0, y: 0, width: bounds.width, height: 58)
        NSColor.black.withAlphaComponent(0.22).setFill()
        NSBezierPath(rect: header).fill()

        let dots: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.32, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.77, blue: 0.23, alpha: 1.0),
            NSColor(calibratedRed: 0.30, green: 0.83, blue: 0.38, alpha: 1.0),
        ]
        for (idx, color) in dots.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18 + CGFloat(idx) * 22, y: 22, width: 11, height: 11)).fill()
        }

        let search = NSRect(x: 92, y: 17, width: min(260, max(80, bounds.width - 180)), height: 22)
        NSColor.white.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: search, xRadius: 11, yRadius: 11).fill()
    }

    private func drawCards(in bounds: NSRect) {
        let inset: CGFloat = 26
        let top = max(84, bounds.height * 0.24)
        let cardHeight = max(38, min(82, bounds.height * 0.13))
        let columns = bounds.width > 520 ? 3 : 2
        let gap: CGFloat = 14
        let cardWidth = (bounds.width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)

        for row in 0..<3 {
            for col in 0..<columns {
                let x = inset + CGFloat(col) * (cardWidth + gap)
                let y = top + CGFloat(row) * (cardHeight + gap)
                guard y + cardHeight < bounds.height - 24 else { continue }
                let rect = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)
                NSColor.white.withAlphaComponent(row == 0 ? 0.20 : 0.13).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()

                palette.accent.withAlphaComponent(0.68).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 14, width: 34, height: 8), xRadius: 4, yRadius: 4).fill()
                NSColor.white.withAlphaComponent(0.26).setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 14, y: y + 32, width: max(48, cardWidth - 42), height: 7), xRadius: 3.5, yRadius: 3.5).fill()
            }
        }
    }

    private func drawTitle(in bounds: NSRect) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(32, max(22, bounds.width * 0.045)), weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.76),
        ]

        title.draw(in: NSRect(x: 28, y: 82, width: bounds.width - 56, height: 40), withAttributes: titleAttrs)
        subtitle.draw(in: NSRect(x: 30, y: 124, width: bounds.width - 60, height: 24), withAttributes: subtitleAttrs)

        palette.accent.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: NSRect(x: 30, y: 158, width: min(120, bounds.width * 0.28), height: 7), xRadius: 3.5, yRadius: 3.5).fill()
    }
}
