import AppKit
import QuartzCore

@MainActor
final class WindowSwitcherPanel: NSPanel {
    private struct EntryMetrics {
        var width: CGFloat
        var height: CGFloat
        var thumbnailHeight: CGFloat
        var iconSize: CGFloat
        var titleFontSize: CGFloat
        var subtitleFontSize: CGFloat
        var thumbnailInset: CGFloat
        var textGap: CGFloat
        var cardCornerRadius: CGFloat
        var thumbnailCornerRadius: CGFloat
        var scale: CGFloat
    }

    private struct LayoutMetrics {
        var regularEntry: EntryMetrics
        var selectedEntry: EntryMetrics
        var documentHeight: CGFloat
        var spacing: CGFloat
        var panelInset: CGFloat
        var contentInset: CGFloat
        var backdropAlpha: CGFloat
        var containerBorderAlpha: CGFloat
        var containerBorderWidth: CGFloat
        var containerCornerRadius: CGFloat
        var minPanelWidth: CGFloat
        var maxPanelWidth: CGFloat
        var maxVisibleWidthFraction: CGFloat

        var panelHeight: CGFloat {
            documentHeight + panelInset * 2
        }
    }

    struct Entry: Sendable {
        var windowId: UInt32
        var title: String
        var appName: String
        var icon: NSImage?
        var thumbnail: NSImage?
        var aspectRatio: CGFloat
        var isDimmed: Bool

        init(
            windowId: UInt32,
            title: String,
            appName: String,
            icon: NSImage?,
            thumbnail: NSImage?,
            aspectRatio: CGFloat = Self.fallbackAspectRatio,
            isDimmed: Bool
        ) {
            self.windowId = windowId
            self.title = title
            self.appName = appName
            self.icon = icon
            self.thumbnail = thumbnail
            self.aspectRatio = Self.normalizedAspectRatio(aspectRatio)
            self.isDimmed = isDimmed
        }

        fileprivate static let fallbackAspectRatio: CGFloat = 16.0 / 9.0

        fileprivate static func normalizedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
            guard aspectRatio.isFinite, aspectRatio > 0 else { return fallbackAspectRatio }
            return min(2.35, max(0.34, aspectRatio))
        }
    }

    private final class EntryView: NSView {
        let windowId: UInt32
        private let floatingSurface: Bool
        private let glassView: NSGlassEffectView?
        private let contentRoot = NSView()
        private let iconView = NSImageView()
        private let titleLabel = NSTextField(labelWithString: "")
        private let subtitleLabel = NSTextField(labelWithString: "")
        private let thumbnailView = NSImageView()
        private let footerScrimLayer = CAGradientLayer()
        private let hoverLayer = CALayer()
        private let selectionLayer = CALayer()
        private var widthConstraint: NSLayoutConstraint!
        private var heightConstraint: NSLayoutConstraint!
        private var thumbnailLeadingConstraint: NSLayoutConstraint!
        private var thumbnailTrailingConstraint: NSLayoutConstraint!
        private var thumbnailTopConstraint: NSLayoutConstraint!
        private var thumbnailHeightConstraint: NSLayoutConstraint!
        private var iconLeadingConstraint: NSLayoutConstraint!
        private var iconTopConstraint: NSLayoutConstraint!
        private var iconWidthConstraint: NSLayoutConstraint!
        private var iconHeightConstraint: NSLayoutConstraint!
        private var titleTopConstraint: NSLayoutConstraint!
        private var titleTrailingConstraint: NSLayoutConstraint!
        private var subtitleBottomConstraint: NSLayoutConstraint!
        private var trackingArea: NSTrackingArea?
        private var selected = false
        private var hovered = false
        private var currentScale: CGFloat = 1
        private var currentBackgroundAlpha: CGFloat = 0
        private var currentFooterBottomAlpha: CGFloat = 0
        var onClick: ((UInt32) -> Void)?

        init(windowId: UInt32, metrics: EntryMetrics, floatingSurface: Bool, usesCardGlass: Bool) {
            self.windowId = windowId
            self.floatingSurface = floatingSurface
            self.glassView = usesCardGlass ? NSGlassEffectView() : nil
            super.init(frame: .zero)

            wantsLayer = true
            layer?.cornerRadius = metrics.cardCornerRadius
            layer?.masksToBounds = false
            layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.backgroundColor = floatingSurface ? nil : NSColor.white.withAlphaComponent(0.055).cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOffset = CGSize(width: 0, height: -8)
            layer?.shadowRadius = 18
            layer?.shadowOpacity = 0.10

            contentRoot.wantsLayer = true
            contentRoot.layer?.masksToBounds = false
            contentRoot.translatesAutoresizingMaskIntoConstraints = false
            if let glassView {
                glassView.translatesAutoresizingMaskIntoConstraints = false
                glassView.style = .regular
                glassView.cornerRadius = metrics.cardCornerRadius
                glassView.tintColor = NSColor.white.withAlphaComponent(0.04)
                glassView.contentView = contentRoot
                addSubview(glassView)
                NSLayoutConstraint.activate([
                    glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    glassView.topAnchor.constraint(equalTo: topAnchor),
                    glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            } else {
                addSubview(contentRoot)
                NSLayoutConstraint.activate([
                    contentRoot.leadingAnchor.constraint(equalTo: leadingAnchor),
                    contentRoot.trailingAnchor.constraint(equalTo: trailingAnchor),
                    contentRoot.topAnchor.constraint(equalTo: topAnchor),
                    contentRoot.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }

            footerScrimLayer.cornerRadius = 0
            footerScrimLayer.masksToBounds = false
            footerScrimLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
            footerScrimLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
            footerScrimLayer.opacity = 0
            contentRoot.layer?.addSublayer(footerScrimLayer)

            hoverLayer.cornerRadius = metrics.cardCornerRadius
            hoverLayer.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            hoverLayer.opacity = 0
            contentRoot.layer?.addSublayer(hoverLayer)

            selectionLayer.cornerRadius = metrics.cardCornerRadius
            selectionLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            selectionLayer.opacity = 0
            contentRoot.layer?.addSublayer(selectionLayer)

            thumbnailView.translatesAutoresizingMaskIntoConstraints = false
            thumbnailView.imageAlignment = .alignCenter
            thumbnailView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailView.wantsLayer = true
            thumbnailView.layer?.cornerRadius = metrics.thumbnailCornerRadius
            thumbnailView.layer?.masksToBounds = true
            thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
            contentRoot.addSubview(thumbnailView)

            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageAlignment = .alignCenter
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.wantsLayer = true
            iconView.layer?.cornerRadius = 6
            iconView.layer?.masksToBounds = true
            contentRoot.addSubview(iconView)

            let labelShadow = NSShadow()
            labelShadow.shadowColor = NSColor.black.withAlphaComponent(0.58)
            labelShadow.shadowBlurRadius = 4
            labelShadow.shadowOffset = CGSize(width: 0, height: -1)

            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: metrics.titleFontSize, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1
            titleLabel.isBezeled = false
            titleLabel.drawsBackground = false
            titleLabel.isEditable = false
            titleLabel.isSelectable = false
            titleLabel.textColor = floatingSurface ? .white : .labelColor
            titleLabel.shadow = labelShadow
            contentRoot.addSubview(titleLabel)

            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subtitleLabel.font = .systemFont(ofSize: metrics.subtitleFontSize, weight: .regular)
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 1
            subtitleLabel.isBezeled = false
            subtitleLabel.drawsBackground = false
            subtitleLabel.isEditable = false
            subtitleLabel.isSelectable = false
            subtitleLabel.textColor = floatingSurface ? NSColor.white.withAlphaComponent(0.78) : NSColor.secondaryLabelColor
            subtitleLabel.shadow = labelShadow
            contentRoot.addSubview(subtitleLabel)

            widthConstraint = widthAnchor.constraint(equalToConstant: metrics.width)
            heightConstraint = heightAnchor.constraint(equalToConstant: metrics.height)
            thumbnailLeadingConstraint = thumbnailView.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor, constant: metrics.thumbnailInset)
            thumbnailTrailingConstraint = thumbnailView.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor, constant: -metrics.thumbnailInset)
            thumbnailTopConstraint = thumbnailView.topAnchor.constraint(equalTo: contentRoot.topAnchor, constant: metrics.thumbnailInset)
            thumbnailHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: metrics.thumbnailHeight)
            iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor, constant: metrics.thumbnailInset + 2)
            iconTopConstraint = iconView.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: metrics.textGap)
            iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize)
            iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: metrics.iconSize)
            titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: metrics.textGap)
            titleTrailingConstraint = titleLabel.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor, constant: -(metrics.thumbnailInset + 2))
            subtitleBottomConstraint = subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentRoot.bottomAnchor, constant: -(metrics.thumbnailInset - 2))

            NSLayoutConstraint.activate([
                widthConstraint,
                heightConstraint,
                thumbnailLeadingConstraint,
                thumbnailTrailingConstraint,
                thumbnailTopConstraint,
                thumbnailHeightConstraint,

                iconLeadingConstraint,
                iconTopConstraint,
                iconWidthConstraint,
                iconHeightConstraint,

                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                titleTrailingConstraint,
                titleTopConstraint,

                subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                subtitleBottomConstraint,
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }

        override func layout() {
            super.layout()
            let rootBounds = contentRoot.bounds
            let footerHeight = min(rootBounds.height, max(48, rootBounds.height - thumbnailView.frame.maxY + 8))
            footerScrimLayer.frame = CGRect(x: 0, y: 0, width: rootBounds.width, height: footerHeight)
            hoverLayer.frame = rootBounds
            selectionLayer.frame = rootBounds
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            trackingArea = area
            addTrackingArea(area)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseEntered(with event: NSEvent) {
            setHovered(true, animated: true)
        }

        override func mouseExited(with event: NSEvent) {
            setHovered(false, animated: true)
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(windowId)
        }

        func update(entry: Entry, selected: Bool, metrics: EntryMetrics) {
            iconView.image = entry.icon
            if let thumbnail = entry.thumbnail {
                thumbnailView.image = thumbnail
            } else if thumbnailView.image == nil {
                thumbnailView.image = nil
            }
            titleLabel.stringValue = entry.title
            subtitleLabel.stringValue = entry.appName
            alphaValue = entry.isDimmed ? 0.58 : 1.0
            self.selected = selected
            apply(metrics: metrics, animateScale: false)
            updateChrome(animated: false)
        }

        func updateThumbnail(_ image: NSImage?) {
            thumbnailView.image = image
        }

        func setSelected(_ selected: Bool, metrics: EntryMetrics, animated: Bool) {
            self.selected = selected
            apply(metrics: metrics, animateScale: animated)
            updateChrome(animated: animated)
        }

        private func apply(metrics: EntryMetrics, animateScale: Bool) {
            widthConstraint.constant = metrics.width
            heightConstraint.constant = metrics.height
            thumbnailLeadingConstraint.constant = metrics.thumbnailInset
            thumbnailTrailingConstraint.constant = -metrics.thumbnailInset
            thumbnailTopConstraint.constant = metrics.thumbnailInset
            thumbnailHeightConstraint.constant = metrics.thumbnailHeight
            iconLeadingConstraint.constant = metrics.thumbnailInset + 2
            iconTopConstraint.constant = metrics.textGap
            iconWidthConstraint.constant = metrics.iconSize
            iconHeightConstraint.constant = metrics.iconSize
            titleTopConstraint.constant = metrics.textGap
            titleTrailingConstraint.constant = -(metrics.thumbnailInset + 2)
            subtitleBottomConstraint.constant = -(metrics.thumbnailInset - 2)

            titleLabel.font = .systemFont(ofSize: metrics.titleFontSize, weight: .semibold)
            subtitleLabel.font = .systemFont(ofSize: metrics.subtitleFontSize, weight: .regular)
            glassView?.cornerRadius = metrics.cardCornerRadius
            layer?.cornerRadius = metrics.cardCornerRadius
            footerScrimLayer.cornerRadius = 0
            hoverLayer.cornerRadius = metrics.cardCornerRadius
            selectionLayer.cornerRadius = metrics.cardCornerRadius
            thumbnailView.layer?.cornerRadius = metrics.thumbnailCornerRadius
            currentScale = metrics.scale
            let targetTransform = CATransform3DMakeScale(metrics.scale, metrics.scale, 1)
            let currentTransform = layer?.transform ?? CATransform3DIdentity
            if abs(currentTransform.m11 - targetTransform.m11) > 0.001 {
                if animateScale && !SystemAccessibilityPreferences.reduceMotion {
                    let anim = CABasicAnimation(keyPath: "transform")
                    anim.fromValue = layer?.presentation()?.transform ?? currentTransform
                    anim.toValue = targetTransform
                    anim.duration = 0.15
                    anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    layer?.add(anim, forKey: "liquidbar.switcher.cardScale")
                }
                layer?.transform = targetTransform
            }
            layer?.zPosition = metrics.scale > 1.001 ? 10 : 0
        }

        private func setHovered(_ hovered: Bool, animated: Bool) {
            self.hovered = hovered
            updateChrome(animated: animated)
        }

        private func updateChrome(animated: Bool) {
            let tintAlpha: CGFloat
            let borderAlpha: CGFloat
            let borderWidth: CGFloat
            if selected {
                tintAlpha = hovered ? 0.12 : (floatingSurface ? 0.075 : 0.24)
                borderAlpha = hovered ? 0.78 : (floatingSurface ? 0.66 : 0.54)
                borderWidth = 1.35
            } else if hovered {
                tintAlpha = floatingSurface ? 0.052 : 0.13
                borderAlpha = floatingSurface ? 0.48 : 0.32
                borderWidth = 0.95
            } else {
                tintAlpha = floatingSurface ? 0.018 : 0.045
                borderAlpha = floatingSurface ? 0.22 : 0.11
                borderWidth = 0.6
            }

            let selectionOpacity: Float = selected ? 1 : 0
            let hoverOpacity: Float = hovered ? (selected ? 0.10 : 0.20) : 0
            let footerTopAlpha: CGFloat = floatingSurface ? 0.0 : 0
            let footerBottomAlpha: CGFloat = 0

            if animated {
                animateOpacity(layer: selectionLayer, to: selectionOpacity)
                animateOpacity(layer: hoverLayer, to: hoverOpacity)
            }
            glassView?.tintColor = floatingSurface ? NSColor.white.withAlphaComponent(tintAlpha) : nil
            layer?.backgroundColor = floatingSurface ? nil : NSColor.white.withAlphaComponent(tintAlpha).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
            layer?.borderWidth = borderWidth
            layer?.shadowOpacity = selected ? 0.24 : (hovered ? 0.16 : 0.08)
            layer?.shadowRadius = selected ? 24 : (hovered ? 20 : 14)
            currentBackgroundAlpha = tintAlpha
            currentFooterBottomAlpha = footerBottomAlpha
            footerScrimLayer.colors = [
                NSColor.black.withAlphaComponent(footerTopAlpha).cgColor,
                NSColor.black.withAlphaComponent(footerBottomAlpha).cgColor,
            ]
            selectionLayer.opacity = selectionOpacity
            hoverLayer.opacity = hoverOpacity
        }

        private func animateOpacity(layer: CALayer, to targetOpacity: Float) {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
            anim.toValue = targetOpacity
            anim.duration = 0.14
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "opacity")
        }

        #if DEBUG
        func debugSetHovered(_ hovered: Bool) {
            setHovered(hovered, animated: false)
        }

        func debugVisualState() -> (borderWidth: CGFloat, selectionOpacity: Float, hoverOpacity: Float, scale: CGFloat, backgroundAlpha: CGFloat, footerBottomAlpha: CGFloat) {
            return (
                layer?.borderWidth ?? 0,
                selectionLayer.opacity,
                hoverLayer.opacity,
                currentScale,
                currentBackgroundAlpha,
                currentFooterBottomAlpha
            )
        }

        func debugThumbnailImage() -> NSImage? {
            thumbnailView.image
        }

        func debugUsesSystemGlass() -> Bool {
            floatingSurface && glassView != nil
        }

        func debugLabelsDrawBackground() -> Bool {
            titleLabel.drawsBackground || subtitleLabel.drawsBackground || titleLabel.isBezeled || subtitleLabel.isBezeled
        }

        func debugVisualFrame(in document: NSView) -> NSRect {
            visualFrame(in: document)
        }
        #endif

        func visualFrame(in document: NSView) -> NSRect {
            let frame = convert(bounds, to: document)
            let dx = frame.width * max(0, currentScale - 1) / 2
            let dy = frame.height * max(0, currentScale - 1) / 2
            let selectedOutset: CGFloat = currentScale > 1.001 ? 8 : 0
            return frame.insetBy(dx: -(dx + selectedOutset), dy: -(dy + selectedOutset))
        }
    }

    private let glassStyle: GlassStyle
    let layoutStyle: SwitcherLayoutStyle
    private let metrics: LayoutMetrics
    private var animationProfile: AnimationProfile = .balancedSpring
    private let effectContainer: NSView
    private let effectContentView = NSView()
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let stackView = NSStackView()
    private var documentWidthConstraint: NSLayoutConstraint?
    private var usesSharedGlassBackground = false
    private var entryViews: [UInt32: EntryView] = [:]
    private var entryAspectRatioByWindowId: [UInt32: CGFloat] = [:]
    private var orderedWindowIds: [UInt32] = []
    private var selectedIndex: Int = 0
    private var visibilityToken: UInt64 = 0
    private var scrollDisplayLink: CADisplayLink?
    private var scrollAnimation: ScrollAnimationState?
    private var pendingSpringScrollTarget: NSPoint?
    private var springScrollDispatchScheduled = false
    var onEntryClick: ((UInt32) -> Void)?

    private struct ScrollAnimationState {
        var kind: String
        var targetOrigin: NSPoint
        var currentX: CGFloat
        var velocityX: CGFloat
        var startedAt: CFTimeInterval
        var lastTimestamp: CFTimeInterval
        var lastFrameTimestamp: CFTimeInterval?
        var frameIntervalsMs: [Double]
        var retargetCount: Int
        var distancePoints: CGFloat
        var drivesScroll: Bool
        var deadline: CFTimeInterval?
    }

    init(theme: Theme, glassStyle: GlassStyle, layoutStyle: SwitcherLayoutStyle = .heroCarousel) {
        self.glassStyle = glassStyle
        self.layoutStyle = layoutStyle
        self.metrics = Self.metrics(for: layoutStyle)
        self.effectContainer = NSView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: metrics.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(NSRect(x: 0, y: 0, width: 880, height: metrics.panelHeight), display: false)

        isOpaque = false
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = layoutStyle != .heroCarousel
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
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

    static func aspectRatio(for bounds: WindowBounds) -> CGFloat {
        guard bounds.width > 1, bounds.height > 1 else { return Entry.fallbackAspectRatio }
        return Entry.normalizedAspectRatio(CGFloat(bounds.width / bounds.height))
    }

    static func thumbnailTargetSize(
        layoutStyle: SwitcherLayoutStyle,
        selected: Bool,
        aspectRatio: CGFloat = Entry.fallbackAspectRatio
    ) -> CGSize {
        let entry = Self.entryMetrics(
            for: layoutStyle,
            selected: selected,
            aspectRatio: aspectRatio
        )
        let width = entry.width * entry.scale - entry.thumbnailInset * 2
        return CGSize(width: width, height: entry.thumbnailHeight * entry.scale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setAnimationProfile(_ profile: AnimationProfile) {
        animationProfile = profile
    }

    func update(entries: [Entry], selectedIndex: Int, ensureSelectedVisible: Bool = true) {
        let boundedSelected = min(max(selectedIndex, 0), max(entries.count - 1, 0))
        let selectedWindowId = entries.indices.contains(boundedSelected) ? entries[boundedSelected].windowId : nil
        self.selectedIndex = boundedSelected

        let nextWindowIds = entries.map(\.windowId)
        entryAspectRatioByWindowId = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.windowId, Entry.normalizedAspectRatio($0.aspectRatio))
        })
        if nextWindowIds == orderedWindowIds,
           nextWindowIds.allSatisfy({ entryViews[$0] != nil }) {
            for (index, entry) in entries.enumerated() {
                let entryMetrics = metricsForEntry(at: index, entry: entry)
                let view = entryViews[entry.windowId]
                view?.update(
                    entry: entry,
                    selected: entry.windowId == selectedWindowId,
                    metrics: entryMetrics
                )
            }
            documentWidthConstraint?.constant = documentWidth(forEntryCount: entries.count, selectedIndex: boundedSelected)
            documentView.needsLayout = true
            effectContainer.setAccessibilityLabel("Window Switcher \(max(1, boundedSelected + 1)) of \(max(entries.count, 1))")
            if ensureSelectedVisible {
                documentView.layoutSubtreeIfNeeded()
                ensureSelectedEntryVisible(index: boundedSelected, animated: false)
            }
            return
        }

        let reusableViews = entryViews
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        entryViews.removeAll(keepingCapacity: true)
        orderedWindowIds = nextWindowIds

        for (index, entry) in entries.enumerated() {
            let entryMetrics = metricsForEntry(at: index, entry: entry)
            let view = reusableViews[entry.windowId] ?? EntryView(
                windowId: entry.windowId,
                metrics: entryMetrics,
                floatingSurface: layoutStyle == .heroCarousel,
                usesCardGlass: layoutStyle == .heroCarousel
            )
            view.translatesAutoresizingMaskIntoConstraints = false
            view.onClick = { [weak self] windowId in
                self?.onEntryClick?(windowId)
            }
            let selected = (entry.windowId == selectedWindowId)
            view.update(entry: entry, selected: selected, metrics: entryMetrics)
            entryViews[entry.windowId] = view
            stackView.addArrangedSubview(view)
        }

        documentWidthConstraint?.constant = documentWidth(forEntryCount: entries.count, selectedIndex: boundedSelected)
        documentView.needsLayout = true

        effectContainer.setAccessibilityLabel("Window Switcher \(max(1, boundedSelected + 1)) of \(max(entries.count, 1))")
        if ensureSelectedVisible {
            documentView.layoutSubtreeIfNeeded()
            ensureSelectedEntryVisible(index: boundedSelected, animated: false)
        }
    }

    func updateThumbnail(windowId: UInt32, image: NSImage?) {
        entryViews[windowId]?.updateThumbnail(image)
    }

    func setSelectedIndex(_ index: Int) {
        guard !orderedWindowIds.isEmpty else { return }
        let bounded = min(max(index, 0), orderedWindowIds.count - 1)
        let previous = selectedIndex
        selectedIndex = bounded
        let affectedIndices = Set([previous, bounded])
        for i in affectedIndices where orderedWindowIds.indices.contains(i) {
            let wid = orderedWindowIds[i]
            entryViews[wid]?.setSelected(i == bounded, metrics: metricsForEntry(at: i), animated: true)
        }
        effectContainer.setAccessibilityLabel("Window Switcher \(bounded + 1) of \(orderedWindowIds.count)")
        ensureSelectedEntryVisible(index: bounded, animated: true)
    }

    func prewarm(entries: [Entry], selectedIndex: Int, on screen: NSScreen?) {
        guard !isVisible else { return }
        update(entries: entries, selectedIndex: selectedIndex, ensureSelectedVisible: false)
        prepareFrame(on: screen)
        contentView?.layoutSubtreeIfNeeded()
        effectContainer.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
    }

    func show(on screen: NSScreen?) {
        visibilityToken &+= 1
        let tuning = animationProfile.overlayTuning
        prepareFrame(on: screen)

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

    private func prepareFrame(on screen: NSScreen?) {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = target?.visibleFrame ?? NSRect(x: 200, y: 200, width: 1200, height: 800)

        let maxWidth = max(
            320,
            min(visibleFrame.width - 30, metrics.maxPanelWidth, visibleFrame.width * metrics.maxVisibleWidthFraction)
        )
        let minWidth = min(metrics.minPanelWidth, maxWidth)
        let naturalW = metrics.panelInset * 2 + documentWidth(forEntryCount: max(orderedWindowIds.count, 1), selectedIndex: selectedIndex)
        let width = max(minWidth, min(maxWidth, naturalW))
        let height = metrics.panelHeight

        setFrame(NSRect(x: 0, y: 0, width: width, height: height), display: false)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        setFrameOrigin(origin)
        ensureSelectedEntryVisible(index: selectedIndex, animated: false)
    }

    func hide() {
        visibilityToken &+= 1
        let token = visibilityToken

        guard isVisible else { return }
        pendingSpringScrollTarget = nil
        springScrollDispatchScheduled = false
        finishScrollAnimationForExpectedCancellation()
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
        let glassContainer = effectContainer as? NSGlassEffectContainerView
        glassContainer?.spacing = 0
        effectContainer.wantsLayer = true
        effectContainer.layer?.cornerRadius = metrics.containerCornerRadius
        effectContainer.layer?.masksToBounds = layoutStyle != .heroCarousel
        effectContainer.layer?.borderWidth = metrics.containerBorderWidth
        effectContainer.layer?.borderColor = NSColor.white.withAlphaComponent(metrics.containerBorderAlpha).cgColor
        effectContainer.layer?.shadowColor = NSColor.black.cgColor
        effectContainer.layer?.shadowOffset = CGSize(width: 0, height: -18)
        effectContainer.layer?.shadowRadius = 0
        effectContainer.layer?.shadowOpacity = 0
        effectContainer.setAccessibilityIdentifier("liquidbar.overlay.switcher")

        effectContentView.translatesAutoresizingMaskIntoConstraints = false
        effectContentView.wantsLayer = true
        effectContentView.layer?.masksToBounds = false
        if let glassContainer {
            glassContainer.contentView = effectContentView
            if effectContentView.superview == nil {
                effectContainer.addSubview(effectContentView)
            }
        } else {
            effectContainer.addSubview(effectContentView)
        }
        NSLayoutConstraint.activate([
            effectContentView.leadingAnchor.constraint(equalTo: effectContainer.leadingAnchor),
            effectContentView.trailingAnchor.constraint(equalTo: effectContainer.trailingAnchor),
            effectContentView.topAnchor.constraint(equalTo: effectContainer.topAnchor),
            effectContentView.bottomAnchor.constraint(equalTo: effectContainer.bottomAnchor),
        ])

        if metrics.backdropAlpha > 0 {
            rebuildGlassBackground()
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.wantsLayer = true
        effectContentView.addSubview(scrollView)

        stackView.orientation = .horizontal
        stackView.spacing = metrics.spacing
        stackView.alignment = layoutStyle == .heroCarousel ? .centerY : .top
        stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: metrics.contentInset,
            bottom: 0,
            right: metrics.contentInset
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.wantsLayer = true
        documentView.layer?.masksToBounds = false
        documentView.addSubview(stackView)
        let widthConstraint = documentView.widthAnchor.constraint(equalToConstant: documentWidth(forEntryCount: 0, selectedIndex: 0))
        documentWidthConstraint = widthConstraint
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            widthConstraint,
            documentView.heightAnchor.constraint(equalToConstant: metrics.documentHeight),
        ])
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectContentView.leadingAnchor, constant: metrics.panelInset),
            scrollView.trailingAnchor.constraint(equalTo: effectContentView.trailingAnchor, constant: -metrics.panelInset),
            scrollView.topAnchor.constraint(equalTo: effectContentView.topAnchor, constant: metrics.panelInset),
            scrollView.bottomAnchor.constraint(equalTo: effectContentView.bottomAnchor, constant: -metrics.panelInset),
        ])
    }

    private func metricsForEntry(at index: Int, selectedIndex overrideSelectedIndex: Int? = nil) -> EntryMetrics {
        let aspectRatio = orderedWindowIds.indices.contains(index)
            ? entryAspectRatioByWindowId[orderedWindowIds[index]]
            : nil
        return metricsForEntry(at: index, aspectRatio: aspectRatio, selectedIndex: overrideSelectedIndex)
    }

    private func metricsForEntry(
        at index: Int,
        entry: Entry,
        selectedIndex overrideSelectedIndex: Int? = nil
    ) -> EntryMetrics {
        metricsForEntry(at: index, aspectRatio: entry.aspectRatio, selectedIndex: overrideSelectedIndex)
    }

    private func metricsForEntry(
        at index: Int,
        aspectRatio: CGFloat?,
        selectedIndex overrideSelectedIndex: Int? = nil
    ) -> EntryMetrics {
        let activeIndex = overrideSelectedIndex ?? selectedIndex
        return Self.entryMetrics(
            for: layoutStyle,
            selected: layoutStyle == .heroCarousel && index == activeIndex,
            aspectRatio: aspectRatio ?? Entry.fallbackAspectRatio
        )
    }

    private static func entryMetrics(
        for style: SwitcherLayoutStyle,
        selected: Bool,
        aspectRatio: CGFloat
    ) -> EntryMetrics {
        let layout = metrics(for: style)
        var entry = selected ? layout.selectedEntry : layout.regularEntry
        guard style == .heroCarousel else { return entry }

        let normalizedAspect = Entry.normalizedAspectRatio(aspectRatio)
        let thumbnailWidth = min(560, max(82, entry.thumbnailHeight * normalizedAspect))
        entry.width = thumbnailWidth + entry.thumbnailInset * 2
        return entry
    }

    private static func metrics(for style: SwitcherLayoutStyle) -> LayoutMetrics {
        switch style {
        case .compactShelf:
            let entry = EntryMetrics(
                width: 170,
                height: 156,
                thumbnailHeight: 92,
                iconSize: 20,
                titleFontSize: 13,
                subtitleFontSize: 11,
                thumbnailInset: 10,
                textGap: 8,
                cardCornerRadius: 12,
                thumbnailCornerRadius: 8,
                scale: 1
            )
            return LayoutMetrics(
                regularEntry: entry,
                selectedEntry: entry,
                documentHeight: 156,
                spacing: 10,
                panelInset: 12,
                contentInset: 0,
                backdropAlpha: 1,
                containerBorderAlpha: 0.12,
                containerBorderWidth: 0.75,
                containerCornerRadius: GlassTokens.overlayCornerRadius,
                minPanelWidth: 420,
                maxPanelWidth: 1100,
                maxVisibleWidthFraction: 1.0
            )

        case .heroCarousel:
            let regular = EntryMetrics(
                width: 500,
                height: 344,
                thumbnailHeight: 260,
                iconSize: 28,
                titleFontSize: 15,
                subtitleFontSize: 12,
                thumbnailInset: 14,
                textGap: 10,
                cardCornerRadius: 24,
                thumbnailCornerRadius: 16,
                scale: 1
            )
            return LayoutMetrics(
                regularEntry: regular,
                selectedEntry: EntryMetrics(
                    width: regular.width,
                    height: regular.height,
                    thumbnailHeight: regular.thumbnailHeight,
                    iconSize: regular.iconSize,
                    titleFontSize: regular.titleFontSize,
                    subtitleFontSize: regular.subtitleFontSize,
                    thumbnailInset: regular.thumbnailInset,
                    textGap: regular.textGap,
                    cardCornerRadius: 26,
                    thumbnailCornerRadius: 18,
                    scale: 1.07
                ),
                documentHeight: 420,
                spacing: 24,
                panelInset: 16,
                contentInset: 26,
                backdropAlpha: 0,
                containerBorderAlpha: 0,
                containerBorderWidth: 0,
                containerCornerRadius: 0,
                minPanelWidth: 980,
                maxPanelWidth: 2200,
                maxVisibleWidthFraction: 0.96
            )
        }
    }

    private func documentWidth(forEntryCount count: Int, selectedIndex: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let boundedSelected = min(max(selectedIndex, 0), count - 1)
        let entryWidth = (0..<count).reduce(CGFloat(0)) { partial, index in
            partial + metricsForEntry(at: index, selectedIndex: boundedSelected).width
        }
        return entryWidth + CGFloat(max(count - 1, 0)) * metrics.spacing + metrics.contentInset * 2
    }

    private func rebuildGlassBackground() {
        for v in effectContentView.subviews where v !== scrollView {
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
            testSolidBackgroundLuma: testLuma,
            cornerRadiusOverride: metrics.containerCornerRadius
        )
        let bg = surface.view
        usesSharedGlassBackground = true
        if let glass = bg as? NSGlassEffectView, layoutStyle == .heroCarousel {
            glass.tintColor = NSColor.white.withAlphaComponent(0.05)
        }

        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.alphaValue = metrics.backdropAlpha
        if scrollView.superview === effectContentView {
            effectContentView.addSubview(bg, positioned: .below, relativeTo: scrollView)
        } else {
            effectContentView.addSubview(bg)
        }
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: effectContentView.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: effectContentView.trailingAnchor),
            bg.topAnchor.constraint(equalTo: effectContentView.topAnchor),
            bg.bottomAnchor.constraint(equalTo: effectContentView.bottomAnchor),
        ])
    }

    private func ensureSelectedEntryVisible(index: Int, animated: Bool) {
        guard orderedWindowIds.indices.contains(index),
              let view = entryViews[orderedWindowIds[index]],
              let document = scrollView.documentView else {
            return
        }

        if !animated {
            contentView?.layoutSubtreeIfNeeded()
            effectContainer.layoutSubtreeIfNeeded()
            scrollView.layoutSubtreeIfNeeded()
            document.layoutSubtreeIfNeeded()
        }

        let target = view.visualFrame(in: document).insetBy(dx: -10, dy: 0)
        let visible = scrollView.documentVisibleRect
        guard visible.width > 0, document.bounds.width > visible.width else { return }

        var targetX: CGFloat
        if layoutStyle == .heroCarousel {
            targetX = target.midX - visible.width / 2
        } else {
            targetX = visible.origin.x
            let comfortInset = min(80, max(0, visible.width * 0.18))
            let comfortVisible = visible.insetBy(dx: comfortInset, dy: 0)
            if target.minX < comfortVisible.minX || target.maxX > comfortVisible.maxX {
                targetX = target.midX - visible.width / 2
            } else {
                return
            }
        }

        let maxX = max(0, document.bounds.width - visible.width)
        targetX = min(max(0, targetX), maxX)
        guard abs(targetX - visible.origin.x) > 0.5 else { return }

        scrollToSelectedTarget(x: targetX, y: visible.origin.y, animated: animated)
    }

    private func scrollToSelectedTarget(x targetX: CGFloat, y: CGFloat, animated: Bool) {
        let clipView = scrollView.contentView
        let targetOrigin = NSPoint(x: targetX, y: y)
        clipView.layer?.removeAnimation(forKey: "liquidbar.switcher.clipScroll")

        if animated && isVisible && !SystemAccessibilityPreferences.reduceMotion {
            if !Self.usesLegacySwitcherScrollAnimation {
                scheduleSpringScrollAnimation(to: targetOrigin)
                return
            }
            startLegacyScrollProbe(to: targetOrigin)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.21
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.20, 1.0)
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: { [weak self, weak clipView] in
                MainActor.assumeIsolated {
                    guard let self, let clipView else { return }
                    self.scrollView.reflectScrolledClipView(clipView)
                }
            }
        } else {
            pendingSpringScrollTarget = nil
            springScrollDispatchScheduled = false
            finishScrollAnimation(success: false)
            clipView.scroll(to: targetOrigin)
        }
        scrollView.reflectScrolledClipView(clipView)
    }

    private func scheduleSpringScrollAnimation(to targetOrigin: NSPoint) {
        pendingSpringScrollTarget = targetOrigin
        guard !springScrollDispatchScheduled else { return }
        springScrollDispatchScheduled = true
        let token = visibilityToken

        Task { @MainActor [weak self] in
            guard let self, self.visibilityToken == token else { return }
            self.springScrollDispatchScheduled = false
            guard self.isVisible, let targetOrigin = self.pendingSpringScrollTarget else {
                self.pendingSpringScrollTarget = nil
                return
            }
            self.pendingSpringScrollTarget = nil
            if Self.usesDisplayLinkSpringScrollAnimation {
                self.startSpringScrollAnimation(to: targetOrigin)
            } else if Self.usesAppKitClipScrollAnimation {
                self.startAppKitClipScrollAnimation(to: targetOrigin)
            } else {
                self.startTransformScrollAnimation(to: targetOrigin)
            }
        }
    }

    private func startTransformScrollAnimation(to targetOrigin: NSPoint) {
        guard let layer = documentView.layer else {
            startAppKitClipScrollAnimation(to: targetOrigin)
            return
        }

        let now = CACurrentMediaTime()
        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let presentationTranslation = layer.presentation()?.transform.m41 ?? layer.transform.m41
        let initialTranslation = targetOrigin.x - currentOrigin.x + presentationTranslation
        let distance = abs(targetOrigin.x - currentOrigin.x)

        finishScrollAnimation(success: false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
        layer.rasterizationScale = backingScaleFactor
        layer.shouldRasterize = true
        layer.transform = CATransform3DMakeTranslation(initialTranslation, 0, 0)
        CATransaction.commit()

        scrollAnimation = ScrollAnimationState(
            kind: "transform_scroll",
            targetOrigin: targetOrigin,
            currentX: targetOrigin.x,
            velocityX: 0,
            startedAt: now,
            lastTimestamp: now,
            lastFrameTimestamp: nil,
            frameIntervalsMs: [],
            retargetCount: 0,
            distancePoints: distance,
            drivesScroll: false,
            deadline: nil
        )
        ensureScrollDisplayLink()

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = layer.transform
        anim.toValue = CATransform3DIdentity
        anim.duration = 0.11
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.88, 0.18, 1.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let state = self.scrollAnimation,
                      state.kind == "transform_scroll",
                      abs(state.startedAt - now) < 0.0001 else {
                    return
                }
                self.documentView.layer?.transform = CATransform3DIdentity
                self.finishScrollAnimation(success: true)
            }
        }
        layer.transform = CATransform3DIdentity
        layer.add(anim, forKey: "liquidbar.switcher.documentTranslate")
        CATransaction.commit()
    }

    private func startAppKitClipScrollAnimation(to targetOrigin: NSPoint) {
        let now = CACurrentMediaTime()
        let clipView = scrollView.contentView
        finishScrollAnimation(success: false)
        let currentX = clipView.bounds.origin.x
        scrollAnimation = ScrollAnimationState(
            kind: "system_scroll",
            targetOrigin: targetOrigin,
            currentX: currentX,
            velocityX: 0,
            startedAt: now,
            lastTimestamp: now,
            lastFrameTimestamp: nil,
            frameIntervalsMs: [],
            retargetCount: 0,
            distancePoints: abs(targetOrigin.x - currentX),
            drivesScroll: false,
            deadline: nil
        )
        ensureScrollDisplayLink()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.90, 0.18, 1.0)
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(targetOrigin)
        } completionHandler: { [weak self, weak clipView] in
            MainActor.assumeIsolated {
                guard let self, let clipView else { return }
                self.scrollView.reflectScrolledClipView(clipView)
                guard let state = self.scrollAnimation,
                      state.kind == "system_scroll",
                      abs(state.startedAt - now) < 0.0001 else {
                    return
                }
                self.finishScrollAnimation(success: true)
            }
        }
    }

    private func startLegacyScrollProbe(to targetOrigin: NSPoint) {
        let now = CACurrentMediaTime()
        let currentX = scrollView.contentView.bounds.origin.x
        if var state = scrollAnimation, state.kind == "legacy_scroll", !state.drivesScroll {
            state.targetOrigin = targetOrigin
            state.retargetCount += 1
            state.distancePoints += abs(targetOrigin.x - currentX)
            state.deadline = now + 0.24
            scrollAnimation = state
            ensureScrollDisplayLink()
            return
        }

        finishScrollAnimation(success: false)
        scrollAnimation = ScrollAnimationState(
            kind: "legacy_scroll",
            targetOrigin: targetOrigin,
            currentX: currentX,
            velocityX: 0,
            startedAt: now,
            lastTimestamp: now,
            lastFrameTimestamp: nil,
            frameIntervalsMs: [],
            retargetCount: 0,
            distancePoints: abs(targetOrigin.x - currentX),
            drivesScroll: false,
            deadline: now + 0.24
        )
        ensureScrollDisplayLink()
    }

    private func startSpringScrollAnimation(to targetOrigin: NSPoint) {
        let now = CACurrentMediaTime()
        let clipView = scrollView.contentView
        if var state = scrollAnimation, state.drivesScroll {
            state.targetOrigin = targetOrigin
            state.retargetCount += 1
            state.distancePoints += abs(targetOrigin.x - state.currentX)
            state.deadline = nil
            scrollAnimation = state
            ensureScrollDisplayLink()
            return
        }

        finishScrollAnimation(success: false)
        let currentX = clipView.bounds.origin.x
        scrollAnimation = ScrollAnimationState(
            kind: "spring_scroll",
            targetOrigin: targetOrigin,
            currentX: currentX,
            velocityX: 0,
            startedAt: now,
            lastTimestamp: now,
            lastFrameTimestamp: nil,
            frameIntervalsMs: [],
            retargetCount: 0,
            distancePoints: abs(targetOrigin.x - currentX),
            drivesScroll: true,
            deadline: nil
        )
        ensureScrollDisplayLink()
    }

    private func ensureScrollDisplayLink() {
        guard scrollDisplayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleScrollDisplayLink(_:)))
        if #available(macOS 14.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        scrollDisplayLink = link
    }

    @objc private func handleScrollDisplayLink(_ displayLink: CADisplayLink) {
        guard var state = scrollAnimation else {
            scrollDisplayLink?.invalidate()
            scrollDisplayLink = nil
            return
        }

        let now = displayLink.targetTimestamp > 0 ? displayLink.targetTimestamp : CACurrentMediaTime()
        if let lastFrame = state.lastFrameTimestamp {
            state.frameIntervalsMs.append(max(0, (now - lastFrame) * 1000.0))
            if state.frameIntervalsMs.count > 240 {
                state.frameIntervalsMs.removeFirst(state.frameIntervalsMs.count - 240)
            }
        }
        state.lastFrameTimestamp = now

        if !state.drivesScroll {
            scrollAnimation = state
            if let deadline = state.deadline, CACurrentMediaTime() >= deadline {
                finishScrollAnimation(success: true)
            }
            return
        }

        let rawDelta = max(0.001, now - state.lastTimestamp)
        let dt = min(rawDelta, 1.0 / 30.0)
        state.lastTimestamp = now

        // High-damping spring: fast magnetic travel with little overshoot.
        let angularFrequency: CGFloat = 38.0
        let dampingRatio: CGFloat = 0.92
        let displacement = state.targetOrigin.x - state.currentX
        let acceleration = angularFrequency * angularFrequency * displacement
            - 2 * dampingRatio * angularFrequency * state.velocityX
        state.velocityX += acceleration * CGFloat(dt)
        state.currentX += state.velocityX * CGFloat(dt)

        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: state.currentX, y: state.targetOrigin.y))
        scrollView.reflectScrolledClipView(clipView)

        let remaining = abs(state.targetOrigin.x - state.currentX)
        if remaining < 0.75, abs(state.velocityX) < 18.0 {
            clipView.scroll(to: state.targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            scrollAnimation = state
            finishScrollAnimation(success: true)
        } else {
            scrollAnimation = state
        }
    }

    private func finishScrollAnimation(success: Bool) {
        guard let state = scrollAnimation else { return }
        scrollAnimation = nil
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        documentView.layer?.removeAnimation(forKey: "liquidbar.switcher.documentTranslate")
        documentView.layer?.transform = CATransform3DIdentity
        documentView.layer?.shouldRasterize = false

        PerformanceMonitor.shared.recordSwitcherAnimation(
            kind: state.kind,
            durationMs: (CACurrentMediaTime() - state.startedAt) * 1000.0,
            frameCount: state.frameIntervalsMs.count,
            frameP50Ms: Self.percentile(state.frameIntervalsMs, p: 0.50),
            frameP95Ms: Self.percentile(state.frameIntervalsMs, p: 0.95),
            frameMaxMs: state.frameIntervalsMs.max(),
            retargetCount: state.retargetCount,
            distancePoints: Double(state.distancePoints),
            success: success
        )
    }

    private func finishScrollAnimationForExpectedCancellation() {
        guard let state = scrollAnimation else { return }
        let hasFrameSample = !state.frameIntervalsMs.isEmpty
        let isNativeProbe = state.kind == "legacy_scroll" || state.kind == "system_scroll"
        finishScrollAnimation(success: hasFrameSample || isNativeProbe)
    }

    private static var usesLegacySwitcherScrollAnimation: Bool {
        let env = ProcessInfo.processInfo.environment
        if envBool("LIQUIDBAR_DISABLE_SWITCHER_SPRING_SCROLL") {
            return true
        }
        let mode = env["LIQUIDBAR_SWITCHER_SCROLL_ANIMATION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let mode, !mode.isEmpty else { return true }
        return mode == "legacy" || mode == "native" || mode == "native_scroll"
    }

    private static var usesDisplayLinkSpringScrollAnimation: Bool {
        let mode = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_SCROLL_ANIMATION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mode == "displaylink_spring" || mode == "spring_displaylink" || mode == "manual_spring"
    }

    private static var usesAppKitClipScrollAnimation: Bool {
        let mode = ProcessInfo.processInfo.environment["LIQUIDBAR_SWITCHER_SCROLL_ANIMATION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mode == "appkit_scroll" || mode == "system_scroll" || mode == "clip_scroll"
    }

    private static func envBool(_ key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return false
        }
        switch raw.lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private static func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((Double(sorted.count - 1) * p).rounded(.toNearestOrAwayFromZero))
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    #if DEBUG
    func debugOrderedWindowIds() -> [UInt32] {
        orderedWindowIds
    }

    func debugDocumentVisibleRect() -> NSRect {
        contentView?.layoutSubtreeIfNeeded()
        effectContainer.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        return scrollView.documentVisibleRect
    }

    func debugEntryFrame(windowId: UInt32) -> NSRect? {
        contentView?.layoutSubtreeIfNeeded()
        effectContainer.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        guard let view = entryViews[windowId],
              let document = scrollView.documentView else {
            return nil
        }
        return view.convert(view.bounds, to: document)
    }

    func debugEntryVisualFrame(windowId: UInt32) -> NSRect? {
        contentView?.layoutSubtreeIfNeeded()
        effectContainer.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        guard let view = entryViews[windowId],
              let document = scrollView.documentView else {
            return nil
        }
        return view.debugVisualFrame(in: document)
    }

    func debugHasHorizontalScroller() -> Bool {
        scrollView.hasHorizontalScroller
    }

    func debugClickEntry(windowId: UInt32) {
        entryViews[windowId]?.onClick?(windowId)
    }

    func debugSetHovered(windowId: UInt32, hovered: Bool) {
        entryViews[windowId]?.debugSetHovered(hovered)
    }

    func debugEntryVisualState(windowId: UInt32) -> (borderWidth: CGFloat, selectionOpacity: Float, hoverOpacity: Float, scale: CGFloat, backgroundAlpha: CGFloat, footerBottomAlpha: CGFloat)? {
        entryViews[windowId]?.debugVisualState()
    }

    func debugEntryViewObjectIdentifier(windowId: UInt32) -> ObjectIdentifier? {
        guard let view = entryViews[windowId] else { return nil }
        return ObjectIdentifier(view)
    }

    func debugEntryUsesSystemGlass(windowId: UInt32) -> Bool {
        entryViews[windowId]?.debugUsesSystemGlass() ?? false
    }

    func debugUsesSharedGlassBackground() -> Bool {
        usesSharedGlassBackground
    }

    func debugLabelsDrawBackground(windowId: UInt32) -> Bool {
        entryViews[windowId]?.debugLabelsDrawBackground() ?? true
    }

    func debugThumbnailImage(windowId: UInt32) -> NSImage? {
        entryViews[windowId]?.debugThumbnailImage()
    }

    func debugUsesHiddenTitleChrome() -> Bool {
        let buttonsHidden = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ].allSatisfy { standardWindowButton($0)?.isHidden ?? true }

        return titleVisibility == .hidden
            && titlebarAppearsTransparent
            && buttonsHidden
    }

    func debugSurfaceState() -> (panelHeight: CGFloat, documentHeight: CGFloat, backdropAlpha: CGFloat, borderAlpha: CGFloat, borderWidth: CGFloat, contentInset: CGFloat, shadow: Bool, maxVisibleWidthFraction: CGFloat, maxPanelWidth: CGFloat, cornerRadius: CGFloat) {
        (
            metrics.panelHeight,
            metrics.documentHeight,
            metrics.backdropAlpha,
            metrics.containerBorderAlpha,
            metrics.containerBorderWidth,
            metrics.contentInset,
            hasShadow,
            metrics.maxVisibleWidthFraction,
            metrics.maxPanelWidth,
            metrics.containerCornerRadius
        )
    }
    #endif
}
