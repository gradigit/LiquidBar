import AppKit
import QuartzCore

@MainActor
final class WindowGroupPreviewPanel: NSPanel {
    enum PresentationMode: Equatable {
        case groupPreview
        case overflowShelf

        var thumbnailHeight: CGFloat {
            switch self {
            case .groupPreview: 124
            case .overflowShelf: 190
            }
        }

        var minThumbnailWidth: CGFloat {
            switch self {
            case .groupPreview: 140
            case .overflowShelf: 190
            }
        }

        var maxThumbnailWidth: CGFloat {
            switch self {
            case .groupPreview: 240
            case .overflowShelf: 360
            }
        }

        var tileHeight: CGFloat {
            switch self {
            case .groupPreview: 168
            case .overflowShelf: 238
            }
        }

        var panelHeight: CGFloat {
            switch self {
            case .groupPreview: 188
            case .overflowShelf: 258
            }
        }

        var allowsReordering: Bool { self == .groupPreview }
    }

    private final class WindowThumbnailTileView: NSView {
        let windowId: UInt32
        private let imageView = NSImageView()
        private let appIconView = NSImageView()
        private let titleLabel = NSTextField(labelWithString: "")

        var onClicked: ((UInt32) -> Void)?
        var onDragBegan: ((UInt32, NSPoint) -> Void)?
        var onDragMoved: ((UInt32, NSPoint) -> Void)?
        var onDragEnded: ((UInt32, NSPoint) -> Void)?
        private(set) var currentTitle: String = ""
        private(set) var currentIsDimmed: Bool = false
        private(set) var isSelected: Bool = false

        private var tracking: NSTrackingArea?
        private var isHovering: Bool = false {
            didSet { updateHoverAppearance() }
        }
        private var mouseDownLocationInWindow: NSPoint?
        private var didStartDrag = false

        init(windowId: UInt32, thumbnailHeight: CGFloat) {
            self.windowId = windowId
            super.init(frame: .zero)

            setAccessibilityIdentifier("liquidbar.overlay.group_preview.window.\(windowId)")
            setAccessibilityElement(true)
            setAccessibilityRole(.button)

            wantsLayer = true
            layer?.cornerRadius = 10
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 8
            imageView.layer?.masksToBounds = true
            imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor

            appIconView.translatesAutoresizingMaskIntoConstraints = false
            appIconView.imageScaling = .scaleProportionallyUpOrDown
            appIconView.imageAlignment = .alignCenter

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.usesSingleLineMode = true
            titleLabel.maximumNumberOfLines = 1
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleLabel.allowsDefaultTighteningForTruncation = true
            titleLabel.cell?.truncatesLastVisibleLine = true

            addSubview(imageView)
            addSubview(appIconView)
            addSubview(titleLabel)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                imageView.heightAnchor.constraint(equalToConstant: thumbnailHeight),

                appIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                appIconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                appIconView.widthAnchor.constraint(equalToConstant: 17),
                appIconView.heightAnchor.constraint(equalToConstant: 17),

                titleLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 7),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
                titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let tracking { removeTrackingArea(tracking) }
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
            isHovering = true
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            isHovering = false
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            mouseDownLocationInWindow = event.locationInWindow
            didStartDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)

            guard let start = mouseDownLocationInWindow else { return }
            let p = event.locationInWindow
            let dx = p.x - start.x
            let dy = p.y - start.y
            let threshold: CGFloat = 5

            if !didStartDrag {
                let dist = sqrt(dx * dx + dy * dy)
                guard dist >= threshold else { return }
                didStartDrag = true
                onDragBegan?(windowId, p)
            } else {
                onDragMoved?(windowId, p)
            }
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            let p = event.locationInWindow
            if didStartDrag {
                onDragEnded?(windowId, p)
            } else {
                onClicked?(windowId)
            }
            mouseDownLocationInWindow = nil
            didStartDrag = false
        }

        func update(title: String, image: NSImage?, appIcon: NSImage? = nil, isDimmed: Bool, isSelected: Bool? = nil) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            currentTitle = trimmed
            currentIsDimmed = isDimmed
            if let isSelected { self.isSelected = isSelected }
            titleLabel.stringValue = trimmed
            if let image {
                imageView.image = image
            }
            if let appIcon {
                appIconView.image = appIcon
            }
            alphaValue = isDimmed ? 0.60 : 1.0
            updateHoverAppearance()
        }

        func clearRetainedImage() {
            imageView.image = nil
        }

        private func updateHoverAppearance() {
            guard let layer else { return }
            if isSelected {
                layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isHovering ? 0.28 : 0.22).cgColor
                layer.borderWidth = 1.5
                layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.82).cgColor
            } else if isHovering {
                layer.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
                layer.borderWidth = 1
                layer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            } else {
                layer.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
                layer.borderWidth = 0.75
                layer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            }
        }
    }

    private let glassStyle: GlassStyle
    private let effectContainer = HoverTrackingView()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let documentView = NSView()
    private var documentHeightConstraint: NSLayoutConstraint?
    private nonisolated(unsafe) var clipBoundsObserver: NSObjectProtocol?

    private var tilesByWindowId: [UInt32: WindowThumbnailTileView] = [:]
    private var tileWidthsByWindowId: [UInt32: CGFloat] = [:]
    private var orderedWindowIds: [UInt32] = []
    private var dragSourceWindowId: UInt32?
    private var didReorderInCurrentDrag: Bool = false
    private static let tileChromeWidth: CGFloat = 16 // 8pt padding on each side of image view
    private var presentationMode: PresentationMode = .groupPreview

    // Titlebar chrome stripping (same rationale as other overlay panels).
    private var chromeReapTimer: Timer?
    private var chromeReapUntil: CFTimeInterval = 0

    private var visibilityToken: UInt64 = 0
    private var animationProfile: AnimationProfile = .balancedSpring

    var onWindowClicked: ((UInt32) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onWindowsReordered: (([UInt32]) -> Void)?
    var onVisibleWindowIdsChanged: (([UInt32]) -> Void)?

    init(theme: Theme, glassStyle: GlassStyle) {
        self.glassStyle = glassStyle

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            // NSGlassEffectView is much more stable when hosted in a titled window
            // (it expects NSThemeFrame infrastructure). We hide the titlebar.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(NSRect(x: 0, y: 0, width: 420, height: 180), display: false)

        isOpaque = false
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

    deinit {
        if let clipBoundsObserver {
            NotificationCenter.default.removeObserver(clipBoundsObserver)
        }
    }

    func setAnimationProfile(_ profile: AnimationProfile) {
        animationProfile = profile
    }

    private func setupUI() {
        contentView = effectContainer
        effectContainer.setAccessibilityIdentifier("liquidbar.overlay.group_preview")
        effectContainer.setAccessibilityElement(true)
        effectContainer.setAccessibilityRole(.group)
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = GlassTokens.overlayCornerRadius
        effectContainer.layer?.masksToBounds = true
        // A subtle ring helps the surface read against complex backdrops.
        effectContainer.layer?.borderWidth = 0.75
        effectContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        effectContainer.onHoverChanged = { [weak self] inside in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onHoverChanged?(inside)
                if inside {
                    self.scheduleChromeReap(duration: 1.5)
                }
            }
        }

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        stackView.orientation = .horizontal
        stackView.alignment = .top
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
        let documentHeightConstraint = documentView.heightAnchor.constraint(equalToConstant: presentationMode.panelHeight)
        documentHeightConstraint.isActive = true
        self.documentHeightConstraint = documentHeightConstraint

        scrollView.documentView = documentView
        effectContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])

        clipBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyVisibleWindowIds()
            }
        }

        rebuildGlassBackground()
    }

    private func rebuildGlassBackground() {
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
            kind: .preview,
            style: glassStyle,
            reduceTransparency: reduceTransparency,
            testSolidBackgroundLuma: testLuma
        )
        let bg = surface.view

        bg.translatesAutoresizingMaskIntoConstraints = false
        effectContainer.addSubview(bg, positioned: .below, relativeTo: scrollView)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])
    }

    func updateWindows(
        _ windows: [WindowInfo],
        mode: PresentationMode = .groupPreview,
        selectedWindowId: UInt32? = nil,
        iconProvider: ((String) -> NSImage?)? = nil
    ) {
        presentationMode = mode
        documentHeightConstraint?.constant = mode.panelHeight
        scrollView.hasHorizontalScroller = mode == .groupPreview
        scrollView.autohidesScrollers = true
        effectContainer.setAccessibilityIdentifier(
            mode == .overflowShelf
                ? "liquidbar.overlay.window_overflow"
                : "liquidbar.overlay.group_preview"
        )

        // Clear existing.
        stackView.arrangedSubviews.forEach { v in
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        tilesByWindowId.removeAll(keepingCapacity: true)
        tileWidthsByWindowId.removeAll(keepingCapacity: true)
        orderedWindowIds.removeAll(keepingCapacity: true)
        dragSourceWindowId = nil
        didReorderInCurrentDrag = false

        var deduped: [WindowInfo] = []
        deduped.reserveCapacity(windows.count)
        var seenIds = Set<UInt32>()
        var seenSignatures = Set<String>()
        for w in windows {
            if !seenIds.insert(w.id.raw).inserted { continue }
            let title = w.title.isEmpty ? w.appName : w.title
            let bx = Int((w.bounds.x / 16.0).rounded())
            let by = Int((w.bounds.y / 16.0).rounded())
            let bw = Int((w.bounds.width / 16.0).rounded())
            let bh = Int((w.bounds.height / 16.0).rounded())
            let signature = "\(w.bundleId.raw)|\(w.monitorId.raw)|\(title)|\(bx),\(by),\(bw),\(bh)"
            if !seenSignatures.insert(signature).inserted { continue }
            deduped.append(w)
        }

        // Group previews remain bounded. Overflow shelves create lightweight
        // tile views for every hidden window, but capture only the visible range.
        let visible = mode == .groupPreview ? Array(deduped.prefix(12)) : deduped
        for w in visible {
            let title = w.title.isEmpty ? w.appName : w.title
            let tile = WindowThumbnailTileView(windowId: w.id.raw, thumbnailHeight: mode.thumbnailHeight)
            tile.translatesAutoresizingMaskIntoConstraints = false

            let aspect: CGFloat = {
                let bw = CGFloat(w.bounds.width)
                let bh = CGFloat(w.bounds.height)
                guard bw > 20, bh > 20 else { return 16.0 / 9.0 }
                let a = bw / bh
                if !a.isFinite || a <= 0 { return 16.0 / 9.0 }
                return a
            }()
            let thumbW = max(mode.minThumbnailWidth, min(mode.maxThumbnailWidth, mode.thumbnailHeight * aspect))
            let tileW = thumbW + Self.tileChromeWidth
            tileWidthsByWindowId[w.id.raw] = tileW
            orderedWindowIds.append(w.id.raw)

            NSLayoutConstraint.activate([
                tile.widthAnchor.constraint(equalToConstant: tileW),
                tile.heightAnchor.constraint(equalToConstant: mode.tileHeight),
            ])
            tile.onClicked = { [weak self] wid in
                MainActor.assumeIsolated {
                    self?.onWindowClicked?(wid)
                }
            }
            if mode.allowsReordering {
                tile.onDragBegan = { [weak self] wid, p in
                    MainActor.assumeIsolated {
                        self?.beginDragReorder(windowId: wid, locationInWindow: p)
                    }
                }
                tile.onDragMoved = { [weak self] wid, p in
                    MainActor.assumeIsolated {
                        self?.updateDragReorder(windowId: wid, locationInWindow: p)
                    }
                }
                tile.onDragEnded = { [weak self] wid, p in
                    MainActor.assumeIsolated {
                        self?.endDragReorder(windowId: wid, locationInWindow: p)
                    }
                }
            }
            tile.update(
                title: title,
                image: nil,
                appIcon: iconProvider?(w.bundleId.raw),
                isDimmed: w.isHidden || w.isMinimized,
                isSelected: w.id.raw == selectedWindowId
            )
            tilesByWindowId[w.id.raw] = tile
        }

        applyTileOrder()
        documentView.layoutSubtreeIfNeeded()
    }

    func updateThumbnail(windowId: UInt32, image: NSImage?) {
        guard let tile = tilesByWindowId[windowId] else { return }
        // Preserve title/dim state, only replace image.
        tile.update(title: tile.currentTitle, image: image, isDimmed: tile.currentIsDimmed)
    }

    func updateThumbnail(windowId: UInt32, image: NSImage?, title: String, isDimmed: Bool) {
        tilesByWindowId[windowId]?.update(title: title, image: image, isDimmed: isDimmed)
    }

    func thumbnailTargetSize(windowId: UInt32) -> CGSize? {
        guard let tileWidth = tileWidthsByWindowId[windowId] else { return nil }
        return CGSize(
            width: max(1, tileWidth - Self.tileChromeWidth),
            height: presentationMode.thumbnailHeight
        )
    }

    func show(anchorRect: NSRect, on screen: NSScreen, position: Position) {
        visibilityToken &+= 1

        // Size to content until the shelf reaches its screen-relative maximum.
        let tileCount = orderedWindowIds.count
        let spacing: CGFloat = stackView.spacing
        let padding: CGFloat = stackView.edgeInsets.left + stackView.edgeInsets.right
        let sumTileW = orderedWindowIds.prefix(tileCount).reduce(CGFloat(0)) { partial, wid in
            partial + (tileWidthsByWindowId[wid] ?? 0)
        }
        let naturalW = padding + max(1, sumTileW) + CGFloat(max(0, tileCount - 1)) * spacing
        let maxW: CGFloat = {
            switch presentationMode {
            case .groupPreview:
                return min(screen.visibleFrame.width - 40, 900)
            case .overflowShelf:
                return screen.visibleFrame.width - 48
            }
        }()
        let minW: CGFloat = {
            switch presentationMode {
            case .groupPreview:
                return tileCount <= 1 ? 200 : 260
            case .overflowShelf:
                return min(420, maxW)
            }
        }()
        let width = max(minW, min(naturalW, maxW))
        let height = presentationMode.panelHeight

        setFrame(NSRect(origin: frame.origin, size: CGSize(width: ceil(width), height: height)), display: false)
        documentView.setFrameSize(NSSize(width: ceil(max(naturalW, width)), height: height))
        effectContainer.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

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
            notifyVisibleWindowIds()
            notifyVisibleWindowIdsSoon()
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
                spring.duration = min(0.32, spring.settlingDuration)
                spring.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.transform = CATransform3DIdentity
                layer.add(spring, forKey: "liquidbar.group_preview.springIn")
            }
        } else {
            alphaValue = 1
            effectContainer.layer?.transform = CATransform3DIdentity
            orderFrontRegardless()
        }
        notifyVisibleWindowIds()
        notifyVisibleWindowIdsSoon()
    }

    func hide(immediate: Bool = false) {
        visibilityToken &+= 1
        let token = visibilityToken
        let tuning = animationProfile.overlayTuning

        guard isVisible else {
            releaseRetainedImages()
            discardOverflowTiles()
            return
        }
        if immediate || SystemAccessibilityPreferences.reduceMotion {
            effectContainer.layer?.removeAnimation(forKey: "liquidbar.group_preview.springIn")
            effectContainer.layer?.removeAnimation(forKey: "liquidbar.group_preview.scaleOut")
            orderOut(nil)
            alphaValue = 0
            effectContainer.layer?.transform = CATransform3DIdentity
            releaseRetainedImages()
            discardOverflowTiles()
            return
        }

        if let layer = effectContainer.layer {
            layer.removeAnimation(forKey: "liquidbar.group_preview.springIn")
            let fromT = layer.presentation()?.transform ?? layer.transform
            let toT = CATransform3DMakeScale(tuning.hideScale, tuning.hideScale, 1)
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = fromT
            anim.toValue = toT
            anim.duration = tuning.fadeOutDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.transform = toT
            layer.add(anim, forKey: "liquidbar.group_preview.scaleOut")
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
                self.releaseRetainedImages()
                self.discardOverflowTiles()
            }
        }
    }

    func releaseRetainedImages() {
        for tile in tilesByWindowId.values {
            tile.clearRetainedImage()
        }
    }

    private func discardOverflowTiles() {
        guard presentationMode == .overflowShelf else { return }
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        tilesByWindowId.removeAll(keepingCapacity: false)
        tileWidthsByWindowId.removeAll(keepingCapacity: false)
        orderedWindowIds.removeAll(keepingCapacity: false)
        documentView.setFrameSize(NSSize(width: 1, height: presentationMode.panelHeight))
    }

    private func notifyVisibleWindowIdsSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.effectContainer.layoutSubtreeIfNeeded()
            self.scrollView.layoutSubtreeIfNeeded()
            self.documentView.layoutSubtreeIfNeeded()
            self.notifyVisibleWindowIds()
        }
    }

    private func notifyVisibleWindowIds() {
        guard presentationMode == .overflowShelf,
              !orderedWindowIds.isEmpty else { return }

        // Prefetch one viewport on either side. This keeps trackpad scrolling
        // fluid while bounding ScreenCaptureKit work independently of window count.
        let viewport = scrollView.documentVisibleRect
        guard viewport.width > 1 else {
            onVisibleWindowIdsChanged?(Array(orderedWindowIds.prefix(8)))
            return
        }
        let captureRect = viewport.insetBy(dx: -viewport.width, dy: 0)
        let candidates = orderedWindowIds.compactMap { windowId -> (UInt32, CGFloat)? in
            guard let tile = tilesByWindowId[windowId] else { return nil }
            let tileRect = tile.convert(tile.bounds, to: documentView)
            guard tileRect.intersects(captureRect) else { return nil }
            return (windowId, abs(tileRect.midX - viewport.midX))
        }
        let visibleIds = candidates.isEmpty
            ? Array(orderedWindowIds.prefix(8))
            : candidates.sorted { $0.1 < $1.1 }.prefix(12).map(\.0)
        onVisibleWindowIdsChanged?(visibleIds)
    }

    #if DEBUG
    var debugOrderedWindowIds: [UInt32] { orderedWindowIds }
    var debugPresentationMode: PresentationMode { presentationMode }

    func debugVisibleWindowIds() -> [UInt32] {
        let viewport = scrollView.documentVisibleRect
        guard viewport.width > 1 else { return Array(orderedWindowIds.prefix(8)) }
        let captureRect = viewport.insetBy(dx: -viewport.width, dy: 0)
        return orderedWindowIds.compactMap { windowId -> (UInt32, CGFloat)? in
            guard let tile = tilesByWindowId[windowId] else { return nil }
            let tileRect = tile.convert(tile.bounds, to: documentView)
            guard tileRect.intersects(captureRect) else { return nil }
            return (windowId, abs(tileRect.midX - viewport.midX))
        }
        .sorted { $0.1 < $1.1 }
        .prefix(12)
        .map(\.0)
    }
    #endif

    // MARK: - Chrome stripping

    private func hideWindowChrome() {
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

    // MARK: - Reorder Drag

    private func beginDragReorder(windowId: UInt32, locationInWindow: NSPoint) {
        guard orderedWindowIds.contains(windowId) else { return }
        dragSourceWindowId = windowId
        didReorderInCurrentDrag = false
        _ = reorderTile(windowId: windowId, locationInWindow: locationInWindow)
    }

    private func updateDragReorder(windowId: UInt32, locationInWindow: NSPoint) {
        guard dragSourceWindowId == windowId else { return }
        if reorderTile(windowId: windowId, locationInWindow: locationInWindow) {
            didReorderInCurrentDrag = true
        }
    }

    private func endDragReorder(windowId: UInt32, locationInWindow: NSPoint) {
        guard dragSourceWindowId == windowId else { return }
        if reorderTile(windowId: windowId, locationInWindow: locationInWindow) {
            didReorderInCurrentDrag = true
        }
        dragSourceWindowId = nil
        if didReorderInCurrentDrag {
            onWindowsReordered?(orderedWindowIds)
        }
        didReorderInCurrentDrag = false
    }

    @discardableResult
    private func reorderTile(windowId: UInt32, locationInWindow: NSPoint) -> Bool {
        guard let sourceIndex = orderedWindowIds.firstIndex(of: windowId) else { return false }
        let pointInStack = stackView.convert(locationInWindow, from: nil)

        let others = orderedWindowIds.filter { $0 != windowId }
        var insertionIndex = others.count
        for (i, wid) in others.enumerated() {
            guard let tile = tilesByWindowId[wid] else { continue }
            if pointInStack.x < tile.frame.midX {
                insertionIndex = i
                break
            }
        }

        var next = orderedWindowIds
        let moved = next.remove(at: sourceIndex)
        let insertAt = max(0, min(insertionIndex, next.count))
        next.insert(moved, at: insertAt)

        guard next != orderedWindowIds else { return false }
        orderedWindowIds = next
        applyTileOrder()
        return true
    }

    private func applyTileOrder() {
        let orderedTiles: [NSView] = orderedWindowIds.compactMap { tilesByWindowId[$0] }
        stackView.arrangedSubviews.forEach { v in
            stackView.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        for tile in orderedTiles {
            stackView.addArrangedSubview(tile)
        }
    }
}
