import AppKit
@testable import LiquidBar
import Testing

@Suite("WindowGroupPreviewPanel", .serialized)
@MainActor
struct WindowGroupPreviewPanelTests {
    @Test func overflowShelfKeepsAllMetadataTilesButBoundsCaptureViewport() throws {
        guard let screen = NSScreen.screens.first else { return }
        let windows = Self.manyWindows(count: 30)
        let panel = WindowGroupPreviewPanel(theme: .dark, glassStyle: .publicRegular)
        defer {
            panel.hide(immediate: true)
            panel.close()
        }

        var requestedIds: [UInt32] = []
        panel.onVisibleWindowIdsChanged = { requestedIds = $0 }
        panel.updateWindows(
            windows,
            mode: .overflowShelf,
            selectedWindowId: 1,
            iconProvider: { _ in NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) }
        )
        panel.show(
            anchorRect: NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY, width: 1, height: 1),
            on: screen,
            position: .bottom
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))

        #expect(panel.debugPresentationMode == .overflowShelf)
        #expect(panel.debugOrderedWindowIds.count == 30)
        #expect(!requestedIds.isEmpty)
        #expect(requestedIds.count <= 12)
        #expect(Set(requestedIds).count == requestedIds.count)

        panel.hide(immediate: true)
        #expect(panel.debugOrderedWindowIds.isEmpty)

        panel.updateWindows(windows, mode: .groupPreview)
        #expect(panel.debugOrderedWindowIds.count == 12)
    }

    @Test func overflowShelfVisualSnapshotCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_OVERFLOW_SHELF_QA_PATH"],
              !outputPath.isEmpty,
              let screen = NSScreen.screens.first else { return }

        let windows = Self.manyWindows(count: 18)
        let panel = WindowGroupPreviewPanel(theme: .dark, glassStyle: .publicRegular)
        defer {
            panel.hide(immediate: true)
            panel.close()
        }

        panel.updateWindows(
            windows,
            mode: .overflowShelf,
            selectedWindowId: 3,
            iconProvider: { _ in NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) }
        )
        panel.show(
            anchorRect: NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY, width: 1, height: 1),
            on: screen,
            position: .bottom
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        for windowId in panel.debugVisibleWindowIds() {
            let hue = CGFloat(windowId % 10) / 10
            panel.updateThumbnail(
                windowId: windowId,
                image: Self.thumbnail(
                    color: NSColor(calibratedHue: hue, saturation: 0.58, brightness: 0.72, alpha: 1),
                    label: "Window \(windowId)",
                    size: NSSize(width: 360, height: 210)
                ),
                title: "Window \(windowId)",
                isDimmed: false
            )
        }

        let content = try #require(panel.contentView)
        content.displayIfNeeded()
        try writeViewSnapshot(content, to: URL(fileURLWithPath: outputPath))
    }

    @Test func groupPreviewReadmeShowcaseCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_GROUP_PREVIEW_README_PATH"],
              !outputPath.isEmpty else { return }

        let panel = WindowGroupPreviewPanel(theme: .dark, glassStyle: .publicRegular)
        defer { panel.close() }

        panel.updateWindows(Self.windows)

        let thumbnails: [(UInt32, NSColor, String, NSSize)] = [
            (101, .systemBlue, "Inbox", NSSize(width: 320, height: 190)),
            (102, .systemPurple, "Roadmap", NSSize(width: 300, height: 210)),
            (103, .systemOrange, "Preview", NSSize(width: 420, height: 180)),
            (104, .systemTeal, "Release", NSSize(width: 210, height: 250)),
        ]
        var imagesByWindowId: [UInt32: NSImage] = [:]
        for (windowId, color, label, size) in thumbnails {
            let image = Self.thumbnail(color: color, label: label, size: size)
            imagesByWindowId[windowId] = image
            panel.updateThumbnail(
                windowId: windowId,
                image: image,
                title: label,
                isDimmed: windowId == 104
            )
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 430))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.050, blue: 0.064, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "Taskbar Thumbnail Preview")
        title.frame = NSRect(x: 44, y: 350, width: 520, height: 34)
        title.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        title.textColor = .white
        container.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Hover a grouped app to pick the exact window, including wide and portrait windows.")
        subtitle.frame = NSRect(x: 44, y: 322, width: 760, height: 22)
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.62)
        container.addSubview(subtitle)

        var x: CGFloat = 44
        for window in Self.windows {
            let image = try #require(imagesByWindowId[window.id.raw])
            let aspect = CGFloat(window.bounds.width / max(window.bounds.height, 1))
            let imageHeight: CGFloat = 142
            let imageWidth = (imageHeight * aspect).clamped(to: 128...272)
            let tileWidth = imageWidth + 24
            addPreviewTile(
                title: window.title,
                appName: window.appName,
                image: image,
                dimmed: window.isMinimized,
                frame: NSRect(x: x, y: 54, width: tileWidth, height: 232),
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                to: container
            )
            x += tileWidth + 24
        }

        container.displayIfNeeded()
        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
    }

    private static let windows: [WindowInfo] = [
        WindowInfo(
            id: WindowId(101),
            bundleId: BundleId("com.example.mail"),
            appName: "Mail",
            title: "Inbox",
            isHidden: false,
            isMinimized: false,
            monitorId: MonitorId(1),
            bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
        ),
        WindowInfo(
            id: WindowId(102),
            bundleId: BundleId("com.example.notes"),
            appName: "Notes",
            title: "Roadmap",
            isHidden: false,
            isMinimized: false,
            monitorId: MonitorId(1),
            bounds: WindowBounds(x: 0, y: 0, width: 1200, height: 840)
        ),
        WindowInfo(
            id: WindowId(103),
            bundleId: BundleId("com.example.browser"),
            appName: "Browser",
            title: "Preview",
            isHidden: false,
            isMinimized: false,
            monitorId: MonitorId(1),
            bounds: WindowBounds(x: 0, y: 0, width: 1680, height: 720)
        ),
        WindowInfo(
            id: WindowId(104),
            bundleId: BundleId("com.example.chat"),
            appName: "Chat",
            title: "Release",
            isHidden: false,
            isMinimized: true,
            monitorId: MonitorId(1),
            bounds: WindowBounds(x: 0, y: 0, width: 720, height: 980)
        ),
    ]

    private static func manyWindows(count: Int) -> [WindowInfo] {
        let sizes: [(Double, Double)] = [
            (1440, 900),
            (1280, 960),
            (900, 1200),
            (1680, 720),
            (1100, 900),
        ]
        return (1...count).map { index in
            let size = sizes[(index - 1) % sizes.count]
            return WindowInfo(
                id: WindowId(UInt32(index)),
                bundleId: BundleId("com.example.app\((index - 1) % 6)"),
                appName: "App \((index - 1) % 6)",
                title: "Window \(index)",
                isHidden: false,
                isMinimized: false,
                monitorId: MonitorId(1),
                bounds: WindowBounds(x: Double(index * 8), y: 0, width: size.0, height: size.1)
            )
        }
    }

    private static func thumbnail(color: NSColor, label: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        color.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18).fill()

        NSColor.white.withAlphaComponent(0.18).setFill()
        let contentWidth = max(42, size.width - 48)
        NSBezierPath(roundedRect: NSRect(x: 24, y: 28, width: contentWidth * 0.70, height: 18), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 58, width: contentWidth, height: 18), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 88, width: contentWidth * 0.55, height: 18), xRadius: 7, yRadius: 7).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
        ]
        NSString(string: label).draw(at: NSPoint(x: 24, y: max(24, size.height - 56)), withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    private func addPreviewTile(
        title: String,
        appName: String,
        image: NSImage,
        dimmed: Bool,
        frame: NSRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        to container: NSView
    ) {
        let tile = NSView(frame: frame)
        tile.alphaValue = dimmed ? 0.64 : 1
        tile.wantsLayer = true
        tile.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        tile.layer?.cornerRadius = 20
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        container.addSubview(tile)

        let imageView = NSImageView(frame: NSRect(
            x: 12,
            y: frame.height - imageHeight - 12,
            width: imageWidth,
            height: imageHeight
        ))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        tile.addSubview(imageView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 14, y: 38, width: frame.width - 28, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        tile.addSubview(titleLabel)

        let appLabel = NSTextField(labelWithString: appName)
        appLabel.frame = NSRect(x: 14, y: 18, width: frame.width - 28, height: 16)
        appLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.usesSingleLineMode = true
        tile.addSubview(appLabel)
    }

    private func writeViewSnapshot(_ view: NSView, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }
}
