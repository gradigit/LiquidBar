import AppKit

@MainActor
final class TabGroupOverlayPanel: NSPanel {
    private let groupId: String
    private let glassStyle: GlassStyle
    private let effectContainer = NSView()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()

    var onWindowClicked: ((UInt32) -> Void)?

    var tabGroupId: String { groupId }

    init(groupId: String, theme: Theme, glassStyle: GlassStyle) {
        self.groupId = groupId
        self.glassStyle = glassStyle

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
            // NSGlassEffectView is much more stable when hosted in a titled window
            // (it expects NSThemeFrame infrastructure). We hide the titlebar.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // `.titled` inflates the frame; force exact geometry (titlebar is hidden).
        setFrame(NSRect(x: 0, y: 0, width: 420, height: 56), display: false)

        isOpaque = false
        // Near-transparent white helps CABackdropLayer warm up without flashing dark.
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = true
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Theme affects glass tint in some modes.
        switch theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }

        setupUI()
    }

    private func setupUI() {
        contentView = effectContainer
        effectContainer.setAccessibilityIdentifier("liquidbar.overlay.tabgroup.\(groupId)")
        effectContainer.setAccessibilityElement(true)
        effectContainer.setAccessibilityRole(.group)
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = GlassTokens.overlayCornerRadius
        effectContainer.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: doc.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            // Ensure document view height tracks scrollView height.
            doc.heightAnchor.constraint(equalToConstant: 56),
        ])

        scrollView.documentView = doc
        effectContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])

        // Background behind scrollView (glass/solid).
        rebuildGlassBackground()
    }

    private func rebuildGlassBackground() {
        // Remove any previous background view (keep scrollView if already added).
        for v in effectContainer.subviews where v !== scrollView {
            v.removeFromSuperview()
        }

        let env = ProcessInfo.processInfo.environment
        let reduceTransparency = SystemAccessibilityPreferences.reduceTransparency

        let testLuma: CGFloat? = {
            guard env["LIQUIDBAR_TEST_SOLID_BACKGROUND"] == "1" else { return nil }
            let luma = Double(env["LIQUIDBAR_TEST_SOLID_BG_LUMA"] ?? "") ?? 0.12
            return CGFloat(max(0.0, min(1.0, luma)))
        }()

        let surface = GlassSurfaceFactory.makeBackground(
            kind: .overlay,
            style: glassStyle,
            reduceTransparency: reduceTransparency,
            testSolidBackgroundLuma: testLuma
        )
        let bg = surface.view

        bg.translatesAutoresizingMaskIntoConstraints = false
        if scrollView.superview === effectContainer {
            effectContainer.addSubview(bg, positioned: .below, relativeTo: scrollView)
        } else {
            effectContainer.addSubview(bg, positioned: .below, relativeTo: nil)
        }
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])
    }

    func updateWindows(_ windows: [WindowInfo], iconCache: IconCache) {
        stackView.arrangedSubviews.forEach { v in
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        for w in windows {
            let title = w.title.isEmpty ? w.appName : w.title
            let btn = NSButton(title: title, target: self, action: #selector(windowClicked(_:)))
            btn.setAccessibilityIdentifier("liquidbar.item.tabgroup.\(groupId).tab.\(w.id.raw)")
            btn.bezelStyle = .texturedRounded
            btn.controlSize = .small
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.imagePosition = .imageLeading
            btn.imageScaling = .scaleProportionallyDown
            btn.toolTip = title
            btn.tag = Int(w.id.raw)

            if let icon = iconCache.getIcon(bundleId: w.bundleId.raw) {
                btn.image = icon
            }

            // Width constraints: cap so long titles don't expand endlessly.
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
                btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])

            // Truncate label if needed.
            if let cell = btn.cell as? NSButtonCell {
                cell.lineBreakMode = .byTruncatingTail
            }

            stackView.addArrangedSubview(btn)
        }
    }

    func show(anchorRect: NSRect, on screen: NSScreen, position: Position) {
        let height: CGFloat = 56

        // Width: cap to available screen width; scroll inside handles overflow.
        let maxWidth = min(screen.visibleFrame.width - 40, 900)
        let width = max(260, maxWidth)

        let margin: CGFloat = 8
        var x: CGFloat
        var y: CGFloat
        switch position {
        case .top:
            x = anchorRect.midX - width / 2
            y = anchorRect.minY - height - margin
        case .bottom:
            x = anchorRect.midX - width / 2
            y = anchorRect.maxY + margin
        case .left:
            x = anchorRect.maxX + margin
            y = anchorRect.midY - height / 2
        case .right:
            x = anchorRect.minX - width - margin
            y = anchorRect.midY - height / 2
        }

        let minX = screen.visibleFrame.minX + 20
        let maxX = screen.visibleFrame.maxX - width - 20
        let minY = screen.visibleFrame.minY + 12
        let maxY = screen.visibleFrame.maxY - height - 12
        x = min(max(x, minX), maxX)
        y = min(max(y, minY), maxY)

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        alphaValue = 1
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    @objc private func windowClicked(_ sender: NSButton) {
        onWindowClicked?(UInt32(sender.tag))
    }
}
