import AppKit
import QuartzCore

@MainActor
final class WindowSwitcherPanel: NSPanel {
    struct Entry: Sendable {
        var windowId: UInt32
        var title: String
        var appName: String
        var icon: NSImage?
        var thumbnail: NSImage?
        var isDimmed: Bool
    }

    private final class EntryView: NSView {
        let windowId: UInt32
        private let iconView = NSImageView()
        private let titleLabel = NSTextField(labelWithString: "")
        private let subtitleLabel = NSTextField(labelWithString: "")
        private let thumbnailView = NSImageView()
        private let highlightLayer = CALayer()

        init(windowId: UInt32) {
            self.windowId = windowId
            super.init(frame: .zero)

            wantsLayer = true
            layer?.cornerRadius = 12
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

            highlightLayer.cornerRadius = 12
            highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            highlightLayer.opacity = 0
            layer?.addSublayer(highlightLayer)

            thumbnailView.translatesAutoresizingMaskIntoConstraints = false
            thumbnailView.imageAlignment = .alignCenter
            thumbnailView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailView.wantsLayer = true
            thumbnailView.layer?.cornerRadius = 8
            thumbnailView.layer?.masksToBounds = true
            thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
            addSubview(thumbnailView)

            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageAlignment = .alignCenter
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.wantsLayer = true
            iconView.layer?.cornerRadius = 6
            iconView.layer?.masksToBounds = true
            addSubview(iconView)

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1
            titleLabel.textColor = .labelColor
            addSubview(titleLabel)

            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 1
            subtitleLabel.textColor = NSColor.secondaryLabelColor
            addSubview(subtitleLabel)

            NSLayoutConstraint.activate([
                thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                thumbnailView.heightAnchor.constraint(equalToConstant: 92),

                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                iconView.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20),

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),

                subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }

        override func layout() {
            super.layout()
            highlightLayer.frame = bounds
        }

        func update(entry: Entry, selected: Bool) {
            iconView.image = entry.icon
            thumbnailView.image = entry.thumbnail
            titleLabel.stringValue = entry.title
            subtitleLabel.stringValue = entry.appName
            alphaValue = entry.isDimmed ? 0.58 : 1.0
            setSelected(selected, animated: false)
        }

        func updateThumbnail(_ image: NSImage?) {
            thumbnailView.image = image
        }

        func setSelected(_ selected: Bool, animated: Bool) {
            let bg = selected
                ? NSColor.white.withAlphaComponent(0.12).cgColor
                : NSColor.white.withAlphaComponent(0.05).cgColor
            let border = selected
                ? NSColor.white.withAlphaComponent(0.22).cgColor
                : NSColor.white.withAlphaComponent(0.12).cgColor
            let targetOpacity: Float = selected ? 1 : 0
            if animated {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = highlightLayer.presentation()?.opacity ?? highlightLayer.opacity
                anim.toValue = targetOpacity
                anim.duration = 0.12
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                highlightLayer.add(anim, forKey: "opacity")
            }
            layer?.backgroundColor = bg
            layer?.borderColor = border
            highlightLayer.opacity = targetOpacity
        }
    }

    private let glassStyle: GlassStyle
    private var animationProfile: AnimationProfile = .balancedSpring
    private let effectContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "Window Switcher")
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var entryViews: [UInt32: EntryView] = [:]
    private var orderedWindowIds: [UInt32] = []
    private var visibilityToken: UInt64 = 0

    init(theme: Theme, glassStyle: GlassStyle) {
        self.glassStyle = glassStyle
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 226),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(NSRect(x: 0, y: 0, width: 880, height: 226), display: false)

        isOpaque = false
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = true
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        switch theme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setAnimationProfile(_ profile: AnimationProfile) {
        animationProfile = profile
    }

    func update(entries: [Entry], selectedIndex: Int) {
        let boundedSelected = min(max(selectedIndex, 0), max(entries.count - 1, 0))
        let selectedWindowId = entries.indices.contains(boundedSelected) ? entries[boundedSelected].windowId : nil

        for v in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        entryViews.removeAll(keepingCapacity: true)
        orderedWindowIds.removeAll(keepingCapacity: true)

        for entry in entries.prefix(14) {
            let view = EntryView(windowId: entry.windowId)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 170),
                view.heightAnchor.constraint(equalToConstant: 156),
            ])
            let selected = (entry.windowId == selectedWindowId)
            view.update(entry: entry, selected: selected)
            entryViews[entry.windowId] = view
            orderedWindowIds.append(entry.windowId)
            stackView.addArrangedSubview(view)
        }

        titleLabel.stringValue = "Window Switcher  \(max(1, boundedSelected + 1))/\(max(entries.count, 1))"
    }

    func updateThumbnail(windowId: UInt32, image: NSImage?) {
        entryViews[windowId]?.updateThumbnail(image)
    }

    func setSelectedIndex(_ index: Int) {
        guard !orderedWindowIds.isEmpty else { return }
        let bounded = min(max(index, 0), orderedWindowIds.count - 1)
        for (i, wid) in orderedWindowIds.enumerated() {
            entryViews[wid]?.setSelected(i == bounded, animated: true)
        }
        titleLabel.stringValue = "Window Switcher  \(bounded + 1)/\(orderedWindowIds.count)"
    }

    func show(on screen: NSScreen?) {
        visibilityToken &+= 1
        let tuning = animationProfile.overlayTuning
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = target?.visibleFrame ?? NSRect(x: 200, y: 200, width: 1200, height: 800)

        let maxWidth = min(visibleFrame.width - 30, 1100)
        let naturalW = 20 + CGFloat(max(orderedWindowIds.count, 1)) * 170 + CGFloat(max(orderedWindowIds.count - 1, 0)) * stackView.spacing
        let width = max(420, min(maxWidth, naturalW))
        let height: CGFloat = 226

        setFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        setFrameOrigin(origin)

        let reduceMotion = SystemAccessibilityPreferences.reduceMotion
        if reduceMotion {
            alphaValue = 1
            effectContainer.layer?.removeAllAnimations()
            effectContainer.layer?.transform = CATransform3DIdentity
            orderFrontRegardless()
            return
        }

        if !isVisible {
            alphaValue = 0
            if let layer = effectContainer.layer {
                layer.removeAllAnimations()
                layer.transform = CATransform3DMakeScale(tuning.initialScale, tuning.initialScale, 1)
            }

            orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = tuning.fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }

            if let layer = effectContainer.layer {
                let spring = CASpringAnimation(keyPath: "transform")
                spring.mass = 1
                spring.stiffness = tuning.springStiffness
                spring.damping = tuning.springDamping
                spring.initialVelocity = 0
                spring.fromValue = layer.transform
                spring.toValue = CATransform3DIdentity
                spring.duration = min(0.30, spring.settlingDuration)
                spring.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.transform = CATransform3DIdentity
                layer.add(spring, forKey: "liquidbar.switcher.springIn")
            }
        } else {
            alphaValue = 1
            effectContainer.layer?.transform = CATransform3DIdentity
            orderFrontRegardless()
        }
    }

    func hide() {
        visibilityToken &+= 1
        let token = visibilityToken

        guard isVisible else { return }
        if SystemAccessibilityPreferences.reduceMotion {
            orderOut(nil)
            return
        }

        let tuning = animationProfile.overlayTuning
        if let layer = effectContainer.layer {
            layer.removeAnimation(forKey: "liquidbar.switcher.springIn")
            let fromT = layer.presentation()?.transform ?? layer.transform
            let toT = CATransform3DMakeScale(tuning.hideScale, tuning.hideScale, 1)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = fromT
            anim.toValue = toT
            anim.duration = tuning.fadeOutDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.transform = toT
            layer.add(anim, forKey: "liquidbar.switcher.scaleOut")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = tuning.fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.visibilityToken == token else { return }
                self.orderOut(nil)
                self.alphaValue = 0
                self.effectContainer.layer?.transform = CATransform3DIdentity
            }
        }
    }

    // MARK: - UI

    private func setupUI() {
        contentView = effectContainer
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = GlassTokens.overlayCornerRadius
        effectContainer.layer?.masksToBounds = true
        effectContainer.layer?.borderWidth = 0.75
        effectContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        effectContainer.setAccessibilityIdentifier("liquidbar.overlay.switcher")

        rebuildGlassBackground()

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        effectContainer.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        effectContainer.addSubview(scrollView)

        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: document.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.heightAnchor.constraint(equalToConstant: 158),
        ])
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: effectContainer.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: effectContainer.trailingAnchor, constant: -14),

            scrollView.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor, constant: -12),
        ])
    }

    private func rebuildGlassBackground() {
        for v in effectContainer.subviews where v !== titleLabel && v !== scrollView {
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
            kind: .preview,
            style: glassStyle,
            reduceTransparency: reduceTransparency,
            testSolidBackgroundLuma: testLuma
        )
        let bg = surface.view

        bg.translatesAutoresizingMaskIntoConstraints = false
        effectContainer.addSubview(bg, positioned: .below, relativeTo: titleLabel)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])
    }
}
