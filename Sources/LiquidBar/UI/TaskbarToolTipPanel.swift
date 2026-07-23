import AppKit
import QuartzCore

@MainActor
final class TaskbarToolTipPanel: NSPanel {
    nonisolated private static let horizontalPadding: CGFloat = 11
    nonisolated private static let verticalPadding: CGFloat = 6
    nonisolated private static let screenMargin: CGFloat = 6
    nonisolated private static let anchorGap: CGFloat = 8
    nonisolated private static let cornerRadius: CGFloat = 8
    nonisolated private static let maxTextWidth: CGFloat = 300
    nonisolated private static let textLayoutSlack: CGFloat = 8

    struct TextLayout {
        let panelSize: NSSize
        let labelFrame: NSRect
        let fittingSize: NSSize
    }

    private let rootView = NSView()
    private let textLabel = NSTextField(labelWithString: "")

    init(theme: Theme, glassStyle: GlassStyle) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        switch theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }

        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Self.cornerRadius
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 0.5
        rootView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        contentView = rootView

        let glass = GlassSurfaceFactory.makeBackground(
            kind: .overlay,
            style: glassStyle,
            reduceTransparency: SystemAccessibilityPreferences.reduceTransparency,
            testSolidBackgroundLuma: nil,
            cornerRadiusOverride: Self.cornerRadius
        ).view
        glass.frame = rootView.bounds
        glass.autoresizingMask = [.width, .height]
        rootView.addSubview(glass)

        textLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textLabel.textColor = .labelColor
        textLabel.alignment = .center
        textLabel.usesSingleLineMode = true
        textLabel.maximumNumberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setAccessibilityElement(false)
        rootView.addSubview(textLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("TaskbarToolTipPanel does not support NSCoding")
    }

    func show(
        text: String,
        anchorRect: NSRect,
        on screen: NSScreen,
        position: Position,
        parentWindow: NSWindow
    ) {
        let layout = textLayout(for: text)
        let size = layout.panelSize
        textLabel.frame = layout.labelFrame

        let targetFrame = Self.frame(
            size: size,
            anchorRect: anchorRect,
            screenFrame: screen.frame,
            position: position
        )
        setFrame(targetFrame, display: true)
        level = NSWindow.Level(rawValue: parentWindow.level.rawValue + 1)

        if parent !== parentWindow {
            parent?.removeChildWindow(self)
            parentWindow.addChildWindow(self, ordered: .above)
        }

        let wasVisible = isVisible
        alphaValue = wasVisible ? 1 : 0
        orderFrontRegardless()
        guard !wasVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide() {
        alphaValue = 0
        orderOut(nil)
        parent?.removeChildWindow(self)
    }

    func textLayout(for text: String) -> TextLayout {
        textLabel.stringValue = text
        textLabel.sizeToFit()
        let fittingSize = textLabel.fittingSize
        let panelSize = NSSize(
            width: min(
                max(
                    44,
                    ceil(fittingSize.width) + Self.horizontalPadding * 2 + Self.textLayoutSlack
                ),
                Self.maxTextWidth + Self.horizontalPadding * 2
            ),
            height: max(26, ceil(fittingSize.height) + Self.verticalPadding * 2)
        )
        return TextLayout(
            panelSize: panelSize,
            labelFrame: NSRect(
                x: Self.horizontalPadding,
                y: Self.verticalPadding,
                width: panelSize.width - Self.horizontalPadding * 2,
                height: panelSize.height - Self.verticalPadding * 2
            ),
            fittingSize: fittingSize
        )
    }

    nonisolated static func frame(
        size: NSSize,
        anchorRect: NSRect,
        screenFrame: NSRect,
        position: Position
    ) -> NSRect {
        var origin: NSPoint
        switch position {
        case .bottom:
            origin = NSPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.maxY + anchorGap)
        case .top:
            origin = NSPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - size.height - anchorGap)
        case .left:
            origin = NSPoint(x: anchorRect.maxX + anchorGap, y: anchorRect.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: anchorRect.minX - size.width - anchorGap, y: anchorRect.midY - size.height / 2)
        }

        let minimumX = screenFrame.minX + screenMargin
        let maximumX = screenFrame.maxX - screenMargin - size.width
        let minimumY = screenFrame.minY + screenMargin
        let maximumY = screenFrame.maxY - screenMargin - size.height
        origin.x = min(max(origin.x, minimumX), max(minimumX, maximumX))
        origin.y = min(max(origin.y, minimumY), max(minimumY, maximumY))
        return NSRect(origin: origin, size: size)
    }
}
