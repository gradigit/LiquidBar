import AppKit
import QuartzCore

@MainActor
final class PluginControlCardPanel: NSPanel {
    private let effectContainer = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let buttonStack = NSStackView()
    private var buttonPool: [NSButton] = []
    private var animationProfile: AnimationProfile = .balancedSpring
    private var visibilityToken: UInt64 = 0

    var onAction: ((String) -> Void)?

    init(theme: Theme, glassStyle: GlassStyle) {
        let frame = NSRect(x: 0, y: 0, width: 360, height: 126)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let cv = NSView(frame: frame)
        cv.wantsLayer = true
        cv.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = cv

        effectContainer.translatesAutoresizingMaskIntoConstraints = false
        effectContainer.state = .active
        effectContainer.blendingMode = .withinWindow
        effectContainer.material = .hudWindow
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = GlassTokens.overlayCornerRadius
        effectContainer.layer?.masksToBounds = true
        cv.addSubview(effectContainer)

        let bg = GlassSurfaceFactory.makeBackground(
            kind: .overlay,
            style: glassStyle,
            reduceTransparency: SystemAccessibilityPreferences.reduceTransparency,
            testSolidBackgroundLuma: nil,
            cornerRadiusOverride: GlassTokens.overlayCornerRadius
        ).view
        bg.translatesAutoresizingMaskIntoConstraints = false
        effectContainer.addSubview(bg, positioned: .below, relativeTo: nil)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        effectContainer.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        effectContainer.addSubview(subtitleLabel)

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.isIndeterminate = false
        progressIndicator.controlSize = .small
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        effectContainer.addSubview(progressIndicator)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fillProportionally
        buttonStack.spacing = 8
        effectContainer.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            effectContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            effectContainer.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            effectContainer.topAnchor.constraint(equalTo: cv.topAnchor),
            effectContainer.bottomAnchor.constraint(equalTo: cv.bottomAnchor),

            bg.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: effectContainer.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: effectContainer.trailingAnchor, constant: -16),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: effectContainer.trailingAnchor, constant: -16),

            progressIndicator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor, constant: -16),
            progressIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 10),

            buttonStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonStack.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 10),
            buttonStack.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor, constant: -12),
        ])

        switch theme {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setAnimationProfile(_ profile: AnimationProfile) {
        animationProfile = profile
    }

    func update(tileTitle: String, state: ProviderPanelState) {
        titleLabel.stringValue = state.title.isEmpty ? tileTitle : state.title
        subtitleLabel.stringValue = state.subtitle

        if let c = state.progressCurrent, let t = state.progressTotal, t > 0 {
            progressIndicator.isHidden = false
            progressIndicator.doubleValue = max(0, min(1, c / t))
        } else {
            progressIndicator.isHidden = true
        }

        while buttonPool.count < state.actions.count {
            let b = NSButton(frame: .zero)
            if let glass = NSButton.BezelStyle(rawValue: 16) {
                b.bezelStyle = glass
            } else {
                b.bezelStyle = .rounded
            }
            b.target = self
            b.action = #selector(actionPressed(_:))
            buttonPool.append(b)
        }

        for view in buttonStack.arrangedSubviews {
            buttonStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (idx, action) in state.actions.enumerated() {
            let b = buttonPool[idx]
            b.title = action.title
            b.isEnabled = action.isEnabled
            b.identifier = NSUserInterfaceItemIdentifier(action.id)
            buttonStack.addArrangedSubview(b)
        }
    }

    func show(anchorRect: NSRect, on screen: NSScreen, position: Position) {
        visibilityToken &+= 1
        let tuning = animationProfile.overlayTuning
        let size = frame.size
        let margin: CGFloat = 10

        var x: CGFloat
        var y: CGFloat
        switch position {
        case .top:
            x = anchorRect.midX - size.width / 2
            y = anchorRect.minY - size.height - 8
        case .bottom:
            x = anchorRect.midX - size.width / 2
            y = anchorRect.maxY + 8
        case .left:
            x = anchorRect.maxX + 8
            y = anchorRect.midY - size.height / 2
        case .right:
            x = anchorRect.minX - size.width - 8
            y = anchorRect.midY - size.height / 2
        }

        let minX = screen.visibleFrame.minX + margin
        let maxX = screen.visibleFrame.maxX - size.width - margin
        let minY = screen.visibleFrame.minY + margin
        let maxY = screen.visibleFrame.maxY - size.height - margin
        x = min(max(x, minX), maxX)
        y = min(max(y, minY), maxY)

        setFrameOrigin(NSPoint(x: x, y: y))
        if SystemAccessibilityPreferences.reduceMotion {
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
                layer.add(spring, forKey: "liquidbar.plugin_card.springIn")
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
        let tuning = animationProfile.overlayTuning

        guard isVisible else { return }
        if SystemAccessibilityPreferences.reduceMotion {
            orderOut(nil)
            return
        }

        if let layer = effectContainer.layer {
            layer.removeAnimation(forKey: "liquidbar.plugin_card.springIn")
            let fromT = layer.presentation()?.transform ?? layer.transform
            let toT = CATransform3DMakeScale(tuning.hideScale, tuning.hideScale, 1)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = fromT
            anim.toValue = toT
            anim.duration = tuning.fadeOutDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.transform = toT
            layer.add(anim, forKey: "liquidbar.plugin_card.scaleOut")
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

    @objc private func actionPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onAction?(id)
    }
}
