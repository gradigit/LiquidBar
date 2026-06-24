import AppKit
import QuartzCore

@MainActor
final class WindowPreviewPanel: NSPanel {
    private let effectContainer = NSView()
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let glassStyle: GlassStyle
    private static let imageHeight: CGFloat = 180
    private static let minImageWidth: CGFloat = 100
    private static let maxImageWidth: CGFloat = 520
    private static let horizontalPadding: CGFloat = 10
    private static let verticalPaddingTop: CGFloat = 10
    private static let verticalPaddingBottom: CGFloat = 10
    private static let titleSpacing: CGFloat = 8
    private static let titleHeight: CGFloat = 20

    private var currentAspectRatio: CGFloat? = nil
    private var chromeReapTimer: Timer?
    private var chromeReapUntil: CFTimeInterval = 0
    private var visibilityToken: UInt64 = 0
    private var animationProfile: AnimationProfile = .balancedSpring

    init(theme: Theme, glassStyle: GlassStyle) {
        self.glassStyle = glassStyle
        let initialSize = Self.preferredSize(aspectRatio: nil)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            // NSGlassEffectView is much more stable when hosted in a titled window
            // (it expects NSThemeFrame infrastructure). We hide the titlebar.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // `.titled` inflates the frame; force exact geometry (titlebar is hidden).
        setFrame(NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height), display: false)

        isOpaque = false
        // Near-transparent white helps CABackdropLayer warm up without flashing dark.
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = true
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hideWindowChrome()

        switch theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }

        setupUI()
    }

    private func hideWindowChrome() {
        // Ensure standard window controls are not present (AppKit can create these lazily).
        styleMask.remove([.closable, .miniaturizable, .resizable])
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none

        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton),
        ].compactMap { $0 }
        for b in buttons {
            b.isHidden = true
            b.alphaValue = 0
            b.isEnabled = false
            b.removeFromSuperview()
        }
    }

    private func scheduleChromeReap(duration: CFTimeInterval) {
        chromeReapUntil = max(chromeReapUntil, CACurrentMediaTime() + duration)
        guard chromeReapTimer == nil else { return }

        chromeReapTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.hideWindowChrome()
                if CACurrentMediaTime() >= self.chromeReapUntil {
                    self.chromeReapTimer?.invalidate()
                    self.chromeReapTimer = nil
                    self.chromeReapUntil = 0
                }
            }
        }
    }

    private func setupUI() {
        contentView = effectContainer
        effectContainer.setAccessibilityIdentifier("liquidbar.overlay.preview")
        effectContainer.setAccessibilityElement(true)
        effectContainer.setAccessibilityRole(.group)
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = GlassTokens.overlayCornerRadius
        effectContainer.layer?.masksToBounds = true
        // A subtle ring helps the preview read as a glass surface on busy backdrops.
        effectContainer.layer?.borderWidth = 0.75
        effectContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        // Background behind content.
        rebuildGlassBackground()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = GlassTokens.previewCornerRadius
        imageView.layer?.masksToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        // Ensure long titles don't expand layout; they should truncate.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.allowsDefaultTighteningForTruncation = true
        titleLabel.cell?.truncatesLastVisibleLine = true

        effectContainer.addSubview(imageView)
        effectContainer.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor, constant: 10),
            imageView.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor, constant: -10),
            imageView.topAnchor.constraint(equalTo: effectContainer.topAnchor, constant: 10),
            imageView.heightAnchor.constraint(equalToConstant: Self.imageHeight),

            titleLabel.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor, constant: -10),
        ])
    }

    private func rebuildGlassBackground() {
        // Remove any existing background view (keep content views).
        for v in effectContainer.subviews {
            if v === imageView || v === titleLabel { continue }
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
        effectContainer.addSubview(bg, positioned: .below, relativeTo: imageView)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])
    }

    func update(image: NSImage?, title: String, aspectRatio: CGFloat?) {
        imageView.image = image
        titleLabel.stringValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredAspect: CGFloat? = {
            if let aspectRatio { return aspectRatio }
            guard let image, image.size.height > 1 else { return nil }
            let a = image.size.width / image.size.height
            if !a.isFinite || a <= 0.05 { return nil }
            return a
        }()
        currentAspectRatio = inferredAspect
        applyPreferredSize(aspectRatio: inferredAspect)
    }

    func releaseRetainedImage() {
        imageView.image = nil
        currentAspectRatio = nil
    }

    func setAnimationProfile(_ profile: AnimationProfile) {
        animationProfile = profile
    }

    func show(anchorRect: NSRect, on screen: NSScreen, position: Position) {
        visibilityToken &+= 1
        applyPreferredSize(aspectRatio: currentAspectRatio)
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
        hideWindowChrome()
        scheduleChromeReap(duration: 1.5)

        let reduceMotion = SystemAccessibilityPreferences.reduceMotion
        let tuning = animationProfile.overlayTuning
        if reduceMotion {
            alphaValue = 1
            effectContainer.layer?.removeAllAnimations()
            effectContainer.layer?.transform = CATransform3DIdentity
            orderFrontRegardless()
            return
        }

        if !isVisible {
            // Start hidden + slightly scaled down, then spring in.
            alphaValue = 0
            if let layer = effectContainer.layer {
                layer.removeAllAnimations()
                let fromT = CATransform3DMakeScale(tuning.initialScale, tuning.initialScale, 1)
                layer.transform = fromT
            }

            orderFrontRegardless()

            // Fade in window.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = tuning.fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }

            // Spring scale content to 1.0.
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
                layer.add(spring, forKey: "liquidbar.preview.springIn")
            }
        } else {
            // Already visible (e.g., async image update). Keep it snappy.
            alphaValue = 1
            effectContainer.layer?.transform = CATransform3DIdentity
            orderFrontRegardless()
        }
    }

    func hide() {
        visibilityToken &+= 1
        let token = visibilityToken
        let tuning = animationProfile.overlayTuning

        guard isVisible else {
            releaseRetainedImage()
            return
        }
        if SystemAccessibilityPreferences.reduceMotion {
            orderOut(nil)
            releaseRetainedImage()
            return
        }

        // Scale down slightly + fade out, then order out.
        if let layer = effectContainer.layer {
            layer.removeAnimation(forKey: "liquidbar.preview.springIn")
            let fromT = layer.presentation()?.transform ?? layer.transform
            let toT = CATransform3DMakeScale(tuning.hideScale, tuning.hideScale, 1)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = fromT
            anim.toValue = toT
            anim.duration = tuning.fadeOutDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.transform = toT
            layer.add(anim, forKey: "liquidbar.preview.scaleOut")
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
                self.releaseRetainedImage()
            }
        }
    }

    private static func preferredSize(aspectRatio: CGFloat?) -> CGSize {
        let aspect = {
            let a = aspectRatio ?? (16.0 / 9.0)
            // Avoid pathological values (minimized windows can report 0).
            if !a.isFinite || a <= 0.05 { return 16.0 / 9.0 }
            return min(max(a, 0.25), 3.0)
        }()

        let imageW = (Self.imageHeight * aspect)
            .clamped(to: Self.minImageWidth...Self.maxImageWidth)
        let w = Self.horizontalPadding * 2 + imageW
        let h = Self.verticalPaddingTop + Self.imageHeight + Self.titleSpacing + Self.titleHeight + Self.verticalPaddingBottom
        return CGSize(width: ceil(w), height: ceil(h))
    }

    private func applyPreferredSize(aspectRatio: CGFloat?) {
        let size = Self.preferredSize(aspectRatio: aspectRatio)
        if abs(frame.size.width - size.width) < 0.5,
           abs(frame.size.height - size.height) < 0.5 {
            return
        }
        setFrame(NSRect(origin: frame.origin, size: size), display: false)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            scheduleChromeReap(duration: 1.5)
        default:
            break
        }
        super.sendEvent(event)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
