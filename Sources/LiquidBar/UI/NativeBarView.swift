// NativeBarView.swift — NSView with native retained layer + mouse events + accessibility
//
// This view hosts a retained Core Animation layer tree and handles mouse
// interaction (click, hover, drag-to-reorder, context menu). It also provides
// NSAccessibility support for VoiceOver.

import AppKit
import QuartzCore

// MARK: - Drag state

private struct DragState {
    let sourceIndex: Int
    let startPoint: NSPoint
    let cursorOffsetInItem: CGFloat
    var isDragging: Bool = false
    var insertionIndex: Int = -1
}

private struct IconLayerRenderIdentity: Equatable {
    let source: ObjectIdentifier
    let widthPointsKey: Int
    let heightPointsKey: Int
    let scaleKey: Int
}

private struct DecorationDepthTokens {
    let fillScale: CGFloat
    let edgeAlpha: CGFloat
    let topHighlightAlpha: CGFloat
    let lowerShadeAlpha: CGFloat
    let shadowAlpha: Float
    let shadowRadius: CGFloat
    let shadowOffsetY: CGFloat
}

enum DragCompletionDecision: Equatable {
    case click(sourceIndex: Int)
    case reorder(from: Int, to: Int, dropIndex: Int?)
    case specialDrop(sourceIndex: Int, dropIndex: Int?)
    case cancel
}

/// Overlay container that never intercepts pointer events.
private final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - NativeBarView

@MainActor
final class NativeBarView: NSView {
    private let retainedRootLayer = CALayer()
    private let itemContainerLayer = CALayer()
    private let decorationContainerLayer = CALayer()
    private var itemLayerPool: [String: CALayer] = [:]
    private var iconLayerPool: [String: CALayer] = [:]
    private var iconRenderIdentityByKey: [String: IconLayerRenderIdentity] = [:]
    weak var renderer: NativeBarRenderer?
    var displayId: CGDirectDisplayID = 0 {
        didSet {
            // Makes UI automation stable across multi-monitor setups.
            setAccessibilityIdentifier("liquidbar.taskbar.\(displayId)")
        }
    }
    var orientation: Position = .bottom

    // Layout: populated by PanelManager after updateItems
    /// Hit-testing rects (includes Fitts' law extension to screen edges).
    var itemRects: [(bundleId: String, index: Int, rect: NSRect)] = []
    /// Visual rects (no edge-extension). Used for hover highlight alignment and debug dumps.
    var visualItemRects: [NSRect] = []
    var items: [TaskbarItem] = []
    /// Used for context menu pin/unpin state (includes apps that are pinned even
    /// when the running window item is shown instead of a dedicated pinned item).
    var pinnedBundleIds: Set<String> = []
    /// IDs of user-defined custom items (config.json). Plugin-provided custom items are read-only.
    var userCustomItemIds: Set<String> = []
    /// User-defined tab groups (for context menu + interactions).
    var tabGroups: [TabGroup] = []
    /// Map of visible windowId -> tabGroupId (if the window belongs to a group).
    var windowIdToTabGroupId: [UInt32: String] = [:]
    /// Feature flag: enable window tab group actions in the UI.
    var windowTabGroupsEnabled: Bool = false

    // Mouse state
    private var hoveredIndex: Int? = nil
    private var lastCursorPosition: NSPoint?
    private var dragState: DragState? = nil
    private var dragHoverIndex: Int? = nil
    private var trackingArea: NSTrackingArea?
    private var scrollAccumulator: CGFloat = 0
    private var nativeTextOverlayView: PassthroughOverlayView?
    private var nativeTextLabels: [NSTextField] = []

    // Callbacks (caller sets these with [weak self])
    var onItemClicked: ((Int, MouseButton) -> Void)?
    var onItemReordered: ((Int, Int) -> Void)?
    var onContextAction: ((Int, ContextAction, String?) -> Void)?
    var onAppContextAction: ((AppContextAction) -> Void)?
    var onHoverChanged: ((Int?) -> Void)?
    /// Cursor position in bar-local native coordinates (origin top-left). `nil` when exited.
    var onCursorMoved: ((NSPoint?) -> Void)?
    var onDragStateChanged: (((sourceIndex: Int, insertionIndex: Int, cursorX: Float, cursorOffsetInItem: Float)?) -> Void)?
    /// Drag-hover index while dragging (used for tab group hover-expand).
    var onDragHoverChanged: ((Int?) -> Void)?
    /// Drag drop hook. Return true if drop is handled and reorder should be skipped.
    var onDragDropped: ((Int, Int?) -> Bool)?
    /// Scroll-wheel steps while the cursor is over the bar. `direction` is +1 (next) or -1 (prev).
    var onScrollStep: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Expose this custom NSView as a first-class AX element so XCUITest can
        // deterministically discover the taskbar by identifier.
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        #if DEBUG
        print("[DEINIT] NativeBarView")
        #endif
    }

    // MARK: - Layer Setup

    override func makeBackingLayer() -> CALayer {
        retainedRootLayer
    }

    func configure(scale: CGFloat) {
        wantsLayer = true
        setAccessibilityElement(true)
        retainedRootLayer.isOpaque = false
        retainedRootLayer.backgroundColor = NSColor.clear.cgColor
        retainedRootLayer.masksToBounds = false
        if decorationContainerLayer.superlayer == nil {
            retainedRootLayer.addSublayer(decorationContainerLayer)
        }
        if itemContainerLayer.superlayer == nil {
            retainedRootLayer.addSublayer(itemContainerLayer)
        }
        if decorationContainerLayer.superlayer === retainedRootLayer,
           itemContainerLayer.superlayer === retainedRootLayer {
            retainedRootLayer.insertSublayer(decorationContainerLayer, below: itemContainerLayer)
        }

        ensureNativeTextOverlayView()
        synchronizeLayerScale(scale)
        updateTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        retainedRootLayer.frame = bounds
        itemContainerLayer.frame = bounds
        decorationContainerLayer.frame = bounds
        nativeTextOverlayView?.frame = bounds
    }

    func refreshRetainedLayers() {
        retainedRootLayer.setNeedsLayout()
        itemContainerLayer.setNeedsLayout()
        decorationContainerLayer.setNeedsDisplay()
    }

    func applySnapshot(
        _ snapshot: NativeBarSnapshot,
        fontSize: CGFloat,
        barHeight: CGFloat
    ) {
        let backingScale = currentBackingScale()
        synchronizeLayerScale(backingScale)

        itemRects = snapshot.hitRects
        visualItemRects = snapshot.visualRects
        items = snapshot.items.map(\.item)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSubtreeIfNeeded()

        var activeKeys: Set<String> = []
        for presentation in snapshot.items {
            let key = presentation.identity
            activeKeys.insert(key)

            let container = itemLayerPool[key] ?? makeItemContainerLayer(key: key)
            container.isHidden = false
            container.opacity = presentation.alpha
            container.frame = pixelAlignedRect(viewRect(fromTopLeft: presentation.rect), scale: backingScale)
            container.cornerRadius = CGFloat(presentation.cornerRadius)
            container.backgroundColor = presentation.backgroundColor?.cgColor

            let iconLayer = iconLayerPool[key] ?? makeIconLayer(key: key, parent: container)
            iconLayer.isHidden = presentation.icon == nil
            if let icon = presentation.icon {
                let rawIconFrame = container.boundsForTopLeftRect(presentation.iconRect, in: presentation.rect)
                let iconFrame = pixelAlignedRect(rawIconFrame, scale: backingScale)
                let identity = iconRenderIdentity(
                    for: icon,
                    targetSize: iconFrame.size,
                    scale: backingScale
                )
                if iconRenderIdentityByKey[key] != identity || iconLayer.contents == nil {
                    iconLayer.contents = icon
                    iconRenderIdentityByKey[key] = identity
                }
            } else {
                iconLayer.contents = nil
                iconRenderIdentityByKey.removeValue(forKey: key)
            }
            iconLayer.opacity = presentation.alpha
            iconLayer.frame = pixelAlignedRect(
                container.boundsForTopLeftRect(presentation.iconRect, in: presentation.rect),
                scale: backingScale
            )

        }

        pruneInactiveItemLayers(activeKeys: activeKeys)

        decorationContainerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for decoration in snapshot.decorations {
            decorationContainerLayer.addSublayer(makeDecorationLayer(decoration, scale: backingScale))
        }

        CATransaction.commit()

        updateNativeTextItems(snapshot.nativeTextItems, fontSize: fontSize, barHeight: barHeight)
        refreshRetainedLayers()
    }

    private func makeItemContainerLayer(key: String) -> CALayer {
        let layer = CALayer()
        layer.name = "item-\(key)"
        layer.masksToBounds = false
        configureLayerQuality(layer, scale: retainedRootLayer.contentsScale)
        itemContainerLayer.addSublayer(layer)
        itemLayerPool[key] = layer
        return layer
    }

    private func makeIconLayer(key: String, parent: CALayer) -> CALayer {
        let layer = CALayer()
        layer.name = "icon-\(key)"
        layer.contentsGravity = .resizeAspect
        configureIconLayerQuality(layer, scale: retainedRootLayer.contentsScale)
        parent.addSublayer(layer)
        iconLayerPool[key] = layer
        return layer
    }

    private func pruneInactiveItemLayers(activeKeys: Set<String>) {
        let staleKeys = itemLayerPool.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            iconLayerPool.removeValue(forKey: key)?.removeFromSuperlayer()
            itemLayerPool.removeValue(forKey: key)?.removeFromSuperlayer()
            iconRenderIdentityByKey.removeValue(forKey: key)
        }
    }

    func debugLayerPoolCounts() -> (items: Int, icons: Int) {
        (itemLayerPool.count, iconLayerPool.count)
    }

    func debugLayerScales() -> (root: CGFloat, item: [CGFloat], icon: [CGFloat], text: [CGFloat]) {
        (
            retainedRootLayer.contentsScale,
            itemLayerPool.values.map(\.contentsScale),
            iconLayerPool.values.map(\.contentsScale),
            nativeTextLabels.compactMap { $0.layer?.contentsScale }
        )
    }

    func debugIconLayerFrames() -> [NSRect] {
        iconLayerPool.values.filter { !$0.isHidden }.map(\.frame)
    }

    func debugIconLayerContentTypes() -> [String] {
        iconLayerPool.values.filter { !$0.isHidden }.map { layer in
            guard let contents = layer.contents else { return "nil" }
            return String(describing: type(of: contents))
        }
    }

    func debugDecorationLayerSublayerNames() -> [[String]] {
        decorationContainerLayer.sublayers?.map { decorationLayer in
            recursiveLayerNames(in: decorationLayer)
        } ?? []
    }

    func debugRetainedLayerOrder() -> [String] {
        retainedRootLayer.sublayers?.compactMap { layer in
            if layer === decorationContainerLayer { return "decorations" }
            if layer === itemContainerLayer { return "items" }
            return layer.name
        } ?? []
    }

    private func recursiveLayerNames(in layer: CALayer) -> [String] {
        (layer.sublayers ?? []).flatMap { sublayer in
            [sublayer.name].compactMap { $0 } + recursiveLayerNames(in: sublayer)
        }
    }

    private func makeDecorationLayer(_ decoration: NativeDecoration, scale: CGFloat) -> CALayer {
        if shouldUseLayeredGlass(for: decoration) {
            return makeLayeredGlassDecorationLayer(decoration, scale: scale)
        }

        let layer = CALayer()
        layer.frame = pixelAlignedRect(viewRect(fromTopLeft: decoration.rect), scale: scale)
        layer.cornerRadius = CGFloat(decoration.cornerRadius)
        layer.backgroundColor = decoration.color.withAlphaComponent(CGFloat(decoration.alpha)).cgColor
        layer.opacity = 1
        configureLayerQuality(layer, scale: scale)
        return layer
    }

    private func shouldUseLayeredGlass(for decoration: NativeDecoration) -> Bool {
        switch decoration.kind {
        case .hover, .focus, .badge, .pluginState, .stackPlate:
            return decoration.rect.width >= 4 && decoration.rect.height >= 4
        case .pin, .separator, .dragShadow:
            return false
        }
    }

    private func makeLayeredGlassDecorationLayer(_ decoration: NativeDecoration, scale: CGFloat) -> CALayer {
        let frame = pixelAlignedRect(viewRect(fromTopLeft: decoration.rect), scale: scale)
        let radius = CGFloat(decoration.cornerRadius)
        let tokens = decorationDepthTokens(for: decoration)

        let container = CALayer()
        container.name = "glass-\(decoration.kind)"
        container.frame = frame
        container.cornerRadius = radius
        container.masksToBounds = false
        container.opacity = 1
        configureLayerQuality(container, scale: scale)

        if tokens.shadowAlpha > 0 {
            container.shadowColor = NSColor.black.cgColor
            container.shadowOpacity = tokens.shadowAlpha
            container.shadowRadius = tokens.shadowRadius
            container.shadowOffset = CGSize(width: 0, height: tokens.shadowOffsetY)
            container.shadowPath = CGPath(
                roundedRect: container.bounds,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        }

        let base = CALayer()
        base.name = "glass-fill"
        base.frame = container.bounds
        base.cornerRadius = radius
        base.masksToBounds = true
        base.backgroundColor = decoration.color
            .withAlphaComponent(CGFloat(decoration.alpha) * tokens.fillScale)
            .cgColor
        base.borderWidth = max(0.5, 1.0 / max(scale, 1.0))
        base.borderColor = NSColor.white.withAlphaComponent(tokens.edgeAlpha).cgColor
        configureLayerQuality(base, scale: scale)
        container.addSublayer(base)

        let topHighlight = CAGradientLayer()
        topHighlight.name = "glass-top-highlight"
        topHighlight.frame = CGRect(
            x: 1 / max(scale, 1),
            y: container.bounds.height * 0.52,
            width: max(0, container.bounds.width - 2 / max(scale, 1)),
            height: max(1, container.bounds.height * 0.48)
        )
        topHighlight.cornerRadius = max(0, radius - 1)
        topHighlight.masksToBounds = true
        topHighlight.colors = [
            NSColor.white.withAlphaComponent(tokens.topHighlightAlpha).cgColor,
            NSColor.white.withAlphaComponent(tokens.topHighlightAlpha * 0.22).cgColor,
            NSColor.clear.cgColor,
        ]
        topHighlight.locations = [0, 0.42, 1]
        topHighlight.startPoint = CGPoint(x: 0.5, y: 1)
        topHighlight.endPoint = CGPoint(x: 0.5, y: 0)
        configureLayerQuality(topHighlight, scale: scale)
        base.addSublayer(topHighlight)

        let lowerShade = CAGradientLayer()
        lowerShade.name = "glass-lower-shade"
        lowerShade.frame = CGRect(
            x: 0,
            y: 0,
            width: container.bounds.width,
            height: max(1, container.bounds.height * 0.50)
        )
        lowerShade.colors = [
            NSColor.black.withAlphaComponent(tokens.lowerShadeAlpha).cgColor,
            NSColor.clear.cgColor,
        ]
        lowerShade.locations = [0, 1]
        lowerShade.startPoint = CGPoint(x: 0.5, y: 0)
        lowerShade.endPoint = CGPoint(x: 0.5, y: 1)
        configureLayerQuality(lowerShade, scale: scale)
        base.addSublayer(lowerShade)

        if decoration.visualDepth == .rich && decoration.rect.width > 12 && decoration.rect.height > 8 {
            let specular = CALayer()
            specular.name = "glass-specular-edge"
            specular.frame = CGRect(
                x: max(2, container.bounds.width * 0.10),
                y: container.bounds.height - max(1, 1.5 / max(scale, 1)) - 2 / max(scale, 1),
                width: container.bounds.width * 0.58,
                height: max(1, 1.5 / max(scale, 1))
            )
            specular.cornerRadius = specular.frame.height / 2
            specular.backgroundColor = NSColor.white.withAlphaComponent(tokens.topHighlightAlpha * 0.86).cgColor
            configureLayerQuality(specular, scale: scale)
            base.addSublayer(specular)
        }

        return container
    }

    private func decorationDepthTokens(for decoration: NativeDecoration) -> DecorationDepthTokens {
        let depth = CGFloat(decoration.visualDepth.floatValue)
        let contrastBoost: CGFloat = SystemAccessibilityPreferences.increaseContrast ? 0.08 : 0
        let shadowScale: Float = SystemAccessibilityPreferences.increaseContrast ? 0.65 : 1.0

        switch decoration.kind {
        case .focus:
            return DecorationDepthTokens(
                fillScale: 0.72 + depth * 0.22,
                edgeAlpha: 0.20 + depth * 0.16 + contrastBoost,
                topHighlightAlpha: 0.24 + depth * 0.20 + contrastBoost,
                lowerShadeAlpha: 0.06 + depth * 0.08,
                shadowAlpha: Float(0.05 + depth * 0.08) * shadowScale,
                shadowRadius: 3 + depth * 5,
                shadowOffsetY: -0.5
            )
        case .pluginState:
            return DecorationDepthTokens(
                fillScale: 0.76 + depth * 0.20,
                edgeAlpha: 0.16 + depth * 0.14 + contrastBoost,
                topHighlightAlpha: 0.18 + depth * 0.18 + contrastBoost,
                lowerShadeAlpha: 0.05 + depth * 0.07,
                shadowAlpha: Float(0.03 + depth * 0.05) * shadowScale,
                shadowRadius: 2 + depth * 4,
                shadowOffsetY: -0.4
            )
        case .badge:
            return DecorationDepthTokens(
                fillScale: 0.82 + depth * 0.16,
                edgeAlpha: 0.18 + depth * 0.16 + contrastBoost,
                topHighlightAlpha: 0.22 + depth * 0.18 + contrastBoost,
                lowerShadeAlpha: 0.06 + depth * 0.07,
                shadowAlpha: Float(0.02 + depth * 0.04) * shadowScale,
                shadowRadius: 1.5 + depth * 3,
                shadowOffsetY: -0.3
            )
        case .hover, .stackPlate:
            fallthrough
        default:
            return DecorationDepthTokens(
                fillScale: 0.66 + depth * 0.20,
                edgeAlpha: 0.13 + depth * 0.14 + contrastBoost,
                topHighlightAlpha: 0.18 + depth * 0.18 + contrastBoost,
                lowerShadeAlpha: 0.04 + depth * 0.08,
                shadowAlpha: Float(0.02 + depth * 0.06) * shadowScale,
                shadowRadius: 2 + depth * 5,
                shadowOffsetY: -0.4
            )
        }
    }

    private func currentBackingScale() -> CGFloat {
        max(1.0, window?.backingScaleFactor ?? retainedRootLayer.contentsScale)
    }

    private func synchronizeLayerScale(_ scale: CGFloat) {
        let scale = max(1.0, scale)
        configureLayerQuality(retainedRootLayer, scale: scale)
        configureLayerQuality(itemContainerLayer, scale: scale)
        configureLayerQuality(decorationContainerLayer, scale: scale)
        nativeTextOverlayView?.layer?.contentsScale = scale
        nativeTextOverlayView?.layer?.rasterizationScale = scale

        for layer in itemLayerPool.values {
            configureLayerQuality(layer, scale: scale)
        }
        for layer in iconLayerPool.values {
            configureIconLayerQuality(layer, scale: scale)
        }
        for label in nativeTextLabels {
            configureTextLabelQuality(label, scale: scale)
        }
    }

    private func configureLayerQuality(_ layer: CALayer, scale: CGFloat) {
        layer.contentsScale = scale
        layer.rasterizationScale = scale
        layer.allowsEdgeAntialiasing = true
    }

    private func configureIconLayerQuality(_ layer: CALayer, scale: CGFloat) {
        configureLayerQuality(layer, scale: scale)
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        layer.minificationFilterBias = 0
    }

    private func configureTextLabelQuality(_ label: NSTextField, scale: CGFloat) {
        label.wantsLayer = true
        label.layer?.contentsScale = scale
        label.layer?.rasterizationScale = scale
        label.layer?.allowsEdgeAntialiasing = true
    }

    private func pixelAlignedRect(_ rect: NSRect, scale: CGFloat) -> NSRect {
        let scale = max(1.0, scale)
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return NSRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private func iconRenderIdentity(
        for image: NSImage,
        targetSize: NSSize,
        scale: CGFloat
    ) -> IconLayerRenderIdentity {
        IconLayerRenderIdentity(
            source: ObjectIdentifier(image),
            widthPointsKey: Int((targetSize.width * 1000).rounded()),
            heightPointsKey: Int((targetSize.height * 1000).rounded()),
            scaleKey: Int((scale * 1000).rounded())
        )
    }

    private func viewRect(fromTopLeft rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX,
            y: bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Native Text Overlay

    private func ensureNativeTextOverlayView() {
        if nativeTextOverlayView != nil { return }
        let overlay = PassthroughOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(overlay)
        nativeTextOverlayView = overlay
    }

    private func makeNativeTextLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.backgroundColor = .clear
        label.isBordered = false
        label.isBezeled = false
        label.isSelectable = false
        label.wantsLayer = true
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.cell?.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        return label
    }

    func updateNativeTextItems(
        _ items: [NativeTextOverlayItem],
        fontSize: CGFloat,
        barHeight: CGFloat
    ) {
        ensureNativeTextOverlayView()
        guard let overlay = nativeTextOverlayView else { return }

        while nativeTextLabels.count < items.count {
            let label = makeNativeTextLabel()
            nativeTextLabels.append(label)
            overlay.addSubview(label)
        }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let backingScale = currentBackingScale()

        for (idx, item) in items.enumerated() {
            let label = nativeTextLabels[idx]
            configureTextLabelQuality(label, scale: backingScale)
            label.isHidden = false
            label.font = font
            label.textColor = NSColor.white.withAlphaComponent(item.isDimmed ? 0.45 : 0.9)
            label.stringValue = item.title
            let measuredHeight = ceil(label.intrinsicContentSize.height)
            let lineHeight = max(1, measuredHeight)
            let y: CGFloat = {
                if let nativeY = item.nativeY, let slotHeight = item.slotHeight {
                    // Vertical sidebar path:
                    // renderer provides top-left (native top-left space) slot bounds per item.
                    // Convert to NSView bottom-left coordinates and center text per row.
                    let top = CGFloat(nativeY) + (CGFloat(slotHeight) - lineHeight) / 2.0
                    let viewY = bounds.height - top - lineHeight
                    return (viewY * backingScale).rounded() / backingScale
                }

                // Horizontal path: center within bar height.
                let centeredY = (barHeight - lineHeight) / 2.0
                return (centeredY * backingScale).rounded() / backingScale
            }()
            let x = (CGFloat(item.x) * backingScale).rounded() / backingScale
            let width = (max(0, CGFloat(item.maxWidth)) * backingScale).rounded() / backingScale
            label.frame = NSRect(
                x: x,
                y: y,
                width: width,
                height: lineHeight
            )
        }

        if nativeTextLabels.count > items.count {
            for idx in items.count..<nativeTextLabels.count {
                nativeTextLabels[idx].isHidden = true
                nativeTextLabels[idx].stringValue = ""
            }
        }
    }

    // MARK: - Hit Testing

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func indexForPoint(_ point: NSPoint) -> Int? {
        // NSView coordinates: origin at bottom-left
        // Our rects are in native/top-left coords, so flip Y
        let flippedY = bounds.height - point.y
        let testPoint = NSPoint(x: point.x, y: flippedY)

        for item in itemRects {
            if item.rect.contains(testPoint) {
                return item.index
            }
        }

        for (idx, rect) in visualItemRects.enumerated() where rect.contains(testPoint) {
            return idx
        }
        return nil
    }

    private func dragIndexForPoint(_ point: NSPoint) -> Int? {
        let flippedY = bounds.height - point.y
        let testPoint = NSPoint(x: point.x, y: flippedY)

        for (idx, rect) in visualItemRects.enumerated() where rect.contains(testPoint) {
            return idx
        }
        for item in itemRects where item.rect.contains(testPoint) {
            return item.index
        }
        return nil
    }

    private func dragRects() -> [(index: Int, rect: NSRect)] {
        if !visualItemRects.isEmpty {
            return visualItemRects.enumerated().map { (index: $0.offset, rect: $0.element) }
        }
        return itemRects.map { (index: $0.index, rect: $0.rect) }
    }

    private func dragPrimaryCoordinate(point: NSPoint, flippedY: CGFloat) -> CGFloat {
        orientation.isVertical ? flippedY : point.x
    }

    private func insertionIndexForDrag(primaryCoordinate: CGFloat) -> Int {
        let rects = dragRects()
        var insertAt = rects.count
        for item in rects {
            let mid = orientation.isVertical ? item.rect.midY : item.rect.midX
            if primaryCoordinate < mid {
                insertAt = item.index
                break
            }
        }
        return insertAt
    }

    private func dragLaneRect() -> NSRect? {
        let rects = dragRects().map(\.rect)
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union
    }

    private func isPointInsideDragLane(_ point: NSPoint) -> Bool {
        guard let laneRect = dragLaneRect() else { return false }
        let flippedY = bounds.height - point.y
        let testPoint = NSPoint(x: point.x, y: flippedY)
        return laneRect.contains(testPoint)
    }

    nonisolated static func shouldBeginDrag(
        startPoint: NSPoint,
        currentPoint: NSPoint,
        threshold: CGFloat = CGFloat(LayoutConstants.dragThreshold)
    ) -> Bool {
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        return dist >= threshold
    }

    nonisolated static func resolveDragCompletionDecision(
        sourceIndex: Int,
        isDragging: Bool,
        isInsideReorderLane: Bool,
        dropIndex: Int?,
        finalInsertionIndex: Int?,
        specialDropHandled: Bool
    ) -> DragCompletionDecision {
        guard sourceIndex >= 0 else { return .cancel }
        guard isDragging else { return .click(sourceIndex: sourceIndex) }
        if specialDropHandled {
            return .specialDrop(sourceIndex: sourceIndex, dropIndex: dropIndex)
        }
        guard isInsideReorderLane else { return .cancel }
        guard let finalInsertionIndex, finalInsertionIndex >= 0 else { return .cancel }
        guard finalInsertionIndex != sourceIndex, finalInsertionIndex != sourceIndex + 1 else {
            return .cancel
        }
        return .reorder(from: sourceIndex, to: finalInsertionIndex, dropIndex: dropIndex)
    }

    // Internal test hook (uses view coordinates).
    func debugInsertionIndexForDrag(at point: NSPoint) -> Int {
        let flippedY = bounds.height - point.y
        let primary = dragPrimaryCoordinate(point: point, flippedY: flippedY)
        return insertionIndexForDrag(primaryCoordinate: primary)
    }

    // Internal test hook (uses view coordinates).
    func debugIndexForPoint(_ point: NSPoint) -> Int? {
        indexForPoint(point)
    }

    // Internal test hook (uses view coordinates).
    func debugIsPointInsideDragLane(_ point: NSPoint) -> Bool {
        isPointInsideDragLane(point)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = dragIndexForPoint(point) else { return }

        // Record potential drag start
        let itemRect = dragRects().first { $0.index == index }?.rect ?? .zero
        let flippedY = bounds.height - point.y
        let offsetInItem: CGFloat = orientation.isVertical
            ? (flippedY - itemRect.minY)
            : (point.x - itemRect.minX)

        dragState = DragState(
            sourceIndex: index,
            startPoint: NSPoint(x: point.x, y: flippedY),
            cursorOffsetInItem: offsetInItem
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard var state = dragState else { return }
        let point = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - point.y

        if !state.isDragging {
            if !Self.shouldBeginDrag(
                startPoint: state.startPoint,
                currentPoint: NSPoint(x: point.x, y: flippedY)
            ) {
                return
            }
            state.isDragging = true
            // Clear hover when drag starts
            onHoverChanged?(nil)
            dragHoverIndex = nil
            onDragHoverChanged?(nil)
        }

        // Compute insertion index on the primary axis (x for horizontal, y for vertical).
        let cursorPrimary = dragPrimaryCoordinate(point: point, flippedY: flippedY)
        let insertAt = insertionIndexForDrag(primaryCoordinate: cursorPrimary)

        state.insertionIndex = insertAt
        dragState = state

        // Track hover target while dragging (separate from normal hover highlight).
        let hover = dragIndexForPoint(point)
        if hover != dragHoverIndex {
            dragHoverIndex = hover
            onDragHoverChanged?(hover)
        }

        // Fire every frame for smooth cursor tracking
        onDragStateChanged?((
            sourceIndex: state.sourceIndex,
            insertionIndex: insertAt,
            cursorX: Float(cursorPrimary),
            cursorOffsetInItem: Float(state.cursorOffsetInItem)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        // Update cursor position for invalidateHover() after reorder
        lastCursorPosition = convert(event.locationInWindow, from: nil)

        if let state = dragState, state.isDragging {
            let dropPoint = lastCursorPosition ?? .zero
            let dropIndex = dragIndexForPoint(dropPoint)
            let flippedY = bounds.height - dropPoint.y
            let finalInsertionIndex = insertionIndexForDrag(
                primaryCoordinate: dragPrimaryCoordinate(point: dropPoint, flippedY: flippedY)
            )
            let decision = Self.resolveDragCompletionDecision(
                sourceIndex: state.sourceIndex,
                isDragging: state.isDragging,
                isInsideReorderLane: isPointInsideDragLane(dropPoint),
                dropIndex: dropIndex,
                finalInsertionIndex: finalInsertionIndex,
                specialDropHandled: onDragDropped?(state.sourceIndex, dropIndex) == true
            )

            if case .specialDrop = decision {
                onDragStateChanged?(nil)
                dragHoverIndex = nil
                onDragHoverChanged?(nil)
                dragState = nil
                return
            }

            if case .reorder(let from, let to, _) = decision {
                onItemReordered?(from, to)
            }

            // Then clear drag visual (endDrag is a no-op if cancelDrag already ran)
            onDragStateChanged?(nil)
            dragHoverIndex = nil
            onDragHoverChanged?(nil)
        } else if let state = dragState {
            // Simple click (no drag)
            onItemClicked?(state.sourceIndex, .left)
        }

        dragState = nil
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = indexForPoint(point) else { return }
        onItemClicked?(index, .middle)
        // Clear hover immediately — closed window shouldn't stay highlighted
        hoveredIndex = nil
        onHoverChanged?(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        // Keep this local to the bar: no global event taps or Input Monitoring required.
        let deltaY = event.scrollingDeltaY
        guard deltaY != 0 else { return }

        scrollAccumulator += deltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 12.0 : 1.0

        while abs(scrollAccumulator) >= threshold {
            // macOS: scroll up is positive deltaY. Map to "previous" by default.
            let direction = scrollAccumulator > 0 ? -1 : 1
            onScrollStep?(direction)
            scrollAccumulator -= threshold * (scrollAccumulator > 0 ? 1 : -1)
        }

        if event.phase == .ended || event.phase == .cancelled {
            scrollAccumulator = 0
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastCursorPosition = point

        // Convert to our render coordinate space (origin top-left).
        let nativePoint = NSPoint(x: point.x, y: bounds.height - point.y)
        onCursorMoved?(nativePoint)

        let index = indexForPoint(point)

        if index != hoveredIndex {
            hoveredIndex = index
            onHoverChanged?(index)
        }

        if let idx = hoveredIndex, idx < items.count {
            self.toolTip = items[idx].displayTitle(iconsOnly: false)
        } else {
            self.toolTip = nil
        }
    }

    override func mouseExited(with event: NSEvent) {
        lastCursorPosition = nil
        self.toolTip = nil
        onCursorMoved?(nil)
        if hoveredIndex != nil {
            hoveredIndex = nil
            onHoverChanged?(nil)
        }
    }

    /// Re-evaluate hover state using the last known cursor position.
    /// Call after item rects change (window close, reorder, etc.) to clear stale hover.
    func invalidateHover() {
        guard let point = lastCursorPosition else {
            if hoveredIndex != nil {
                hoveredIndex = nil
                onHoverChanged?(nil)
            }
            return
        }
        let newIndex = indexForPoint(point)
        if newIndex != hoveredIndex {
            hoveredIndex = newIndex
            onHoverChanged?(newIndex)
        }
    }

    /// Screen-space rect for the given visual item index (matches what we draw, not hit rects).
    func screenRectForVisualItem(at index: Int) -> NSRect? {
        guard index >= 0, index < visualItemRects.count else { return nil }
        guard let window = self.window else { return nil }

        // visualItemRects are in native top-left coordinates. Convert to view coords.
        let rect = visualItemRects[index]
        let viewRect = NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        let windowRect = convert(viewRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = indexForPoint(point) else { return makeAppContextMenu() }

        let menu = NSMenu()

        guard index < items.count else { return makeAppContextMenu() }
        let item = items[index]

        switch item {
        case .customSpacer(let id, _, _):
            if userCustomItemIds.contains(id) {
                let edit = NSMenuItem(title: "Edit Spacer…", action: #selector(contextEditCustomItem(_:)), keyEquivalent: "")
                edit.target = self
                edit.tag = index
                edit.representedObject = id
                menu.addItem(edit)

                let delete = NSMenuItem(title: "Delete Spacer", action: #selector(contextDeleteCustomItem(_:)), keyEquivalent: "")
                delete.target = self
                delete.tag = index
                delete.representedObject = id
                menu.addItem(delete)
            } else {
                let info = NSMenuItem(title: "Provided by plugin", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            appendAppContextItems(to: menu)
            return menu

        case .customText(let id, _, _):
            if userCustomItemIds.contains(id) {
                let edit = NSMenuItem(title: "Edit Label…", action: #selector(contextEditCustomItem(_:)), keyEquivalent: "")
                edit.target = self
                edit.tag = index
                edit.representedObject = id
                menu.addItem(edit)

                let delete = NSMenuItem(title: "Delete Label", action: #selector(contextDeleteCustomItem(_:)), keyEquivalent: "")
                delete.target = self
                delete.tag = index
                delete.representedObject = id
                menu.addItem(delete)
            } else {
                let info = NSMenuItem(title: "Provided by plugin", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            appendAppContextItems(to: menu)
            return menu

        case .customLink(let id, _, _, _, _):
            let open = NSMenuItem(title: "Open Link", action: #selector(contextOpenCustomItem(_:)), keyEquivalent: "")
            open.target = self
            open.tag = index
            open.representedObject = id
            menu.addItem(open)

            if userCustomItemIds.contains(id) {
                menu.addItem(.separator())

                let edit = NSMenuItem(title: "Edit Link…", action: #selector(contextEditCustomItem(_:)), keyEquivalent: "")
                edit.target = self
                edit.tag = index
                edit.representedObject = id
                menu.addItem(edit)

                let delete = NSMenuItem(title: "Delete Link", action: #selector(contextDeleteCustomItem(_:)), keyEquivalent: "")
                delete.target = self
                delete.tag = index
                delete.representedObject = id
                menu.addItem(delete)
            } else {
                menu.addItem(.separator())
                let info = NSMenuItem(title: "Provided by plugin", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            appendAppContextItems(to: menu)
            return menu

        case .customFolder(let id, _, _, _, _):
            let open = NSMenuItem(title: "Open Folder", action: #selector(contextOpenCustomItem(_:)), keyEquivalent: "")
            open.target = self
            open.tag = index
            open.representedObject = id
            menu.addItem(open)

            if userCustomItemIds.contains(id) {
                menu.addItem(.separator())

                let edit = NSMenuItem(title: "Edit Folder…", action: #selector(contextEditCustomItem(_:)), keyEquivalent: "")
                edit.target = self
                edit.tag = index
                edit.representedObject = id
                menu.addItem(edit)

                let delete = NSMenuItem(title: "Delete Folder", action: #selector(contextDeleteCustomItem(_:)), keyEquivalent: "")
                delete.target = self
                delete.tag = index
                delete.representedObject = id
                menu.addItem(delete)
            } else {
                menu.addItem(.separator())
                let info = NSMenuItem(title: "Provided by plugin", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            appendAppContextItems(to: menu)
            return menu

        case .tabGroup(let groupId, _, _, _, _, _, _, _):
            let rename = NSMenuItem(title: "Rename Tab Group…", action: #selector(contextRenameTabGroup(_:)), keyEquivalent: "")
            rename.target = self
            rename.tag = index
            rename.representedObject = groupId
            menu.addItem(rename)

            let delete = NSMenuItem(title: "Delete Tab Group", action: #selector(contextDeleteTabGroup(_:)), keyEquivalent: "")
            delete.target = self
            delete.tag = index
            delete.representedObject = groupId
            menu.addItem(delete)

            appendAppContextItems(to: menu)
            return menu

        case .launcher:
            return makeAppContextMenu()

        case .pluginTile:
            return makeAppContextMenu()

        case .window(let id, _, _, _, _, _, _):
            let closeItem = NSMenuItem(title: "Close Window", action: #selector(contextClose(_:)), keyEquivalent: "")
            closeItem.target = self
            closeItem.tag = index
            menu.addItem(closeItem)

            menu.addItem(.separator())

            // Pin/unpin
            let isPinned: Bool
            if case .pinnedApp = item {
                isPinned = true
            } else {
                isPinned = pinnedBundleIds.contains(item.bundleId)
            }

            if isPinned {
                let unpinItem = NSMenuItem(title: "Unpin from Taskbar", action: #selector(contextUnpin(_:)), keyEquivalent: "")
                unpinItem.target = self
                unpinItem.tag = index
                menu.addItem(unpinItem)
            } else {
                let pinItem = NSMenuItem(title: "Pin to Taskbar", action: #selector(contextPin(_:)), keyEquivalent: "")
                pinItem.target = self
                pinItem.tag = index
                menu.addItem(pinItem)
            }

            let hideItem = NSMenuItem(title: "Hide from Taskbar", action: #selector(contextBlacklist(_:)), keyEquivalent: "")
            hideItem.target = self
            hideItem.tag = index
            menu.addItem(hideItem)

            if windowTabGroupsEnabled {
                menu.addItem(.separator())

                let createGroup = NSMenuItem(title: "Create Tab Group…", action: #selector(contextCreateTabGroup(_:)), keyEquivalent: "")
                createGroup.target = self
                createGroup.tag = index
                menu.addItem(createGroup)

                if let existingGroupId = windowIdToTabGroupId[id.raw] {
                    let remove = NSMenuItem(title: "Remove from Tab Group", action: #selector(contextRemoveFromTabGroup(_:)), keyEquivalent: "")
                    remove.target = self
                    remove.tag = index
                    remove.representedObject = existingGroupId
                    menu.addItem(remove)
                }

                if !tabGroups.isEmpty {
                    let addItem = NSMenuItem(title: "Add to Tab Group", action: nil, keyEquivalent: "")
                    let addSub = NSMenu()
                    for group in tabGroups {
                        let titlePrefix = (group.emoji?.isEmpty == false) ? "\(group.emoji!) " : ""
                        let gItem = NSMenuItem(title: "\(titlePrefix)\(group.name)", action: #selector(contextAddToTabGroup(_:)), keyEquivalent: "")
                        gItem.target = self
                        gItem.tag = index
                        gItem.representedObject = group.id
                        addSub.addItem(gItem)
                    }
                    addItem.submenu = addSub
                    menu.addItem(addItem)
                }
            }

            appendAppContextItems(to: menu)
            return menu

        default:
            // For pinned apps and app-group items, keep the existing menu actions for now.
            break
        }

        // Check if bundle is pinned in the current Space.
        let isPinned: Bool
        if case .pinnedApp = item {
            isPinned = true
        } else {
            isPinned = pinnedBundleIds.contains(item.bundleId)
        }

        if isPinned {
            let unpinItem = NSMenuItem(title: "Unpin from Taskbar", action: #selector(contextUnpin(_:)), keyEquivalent: "")
            unpinItem.target = self
            unpinItem.tag = index
            menu.addItem(unpinItem)
        } else {
            let pinItem = NSMenuItem(title: "Pin to Taskbar", action: #selector(contextPin(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.tag = index
            menu.addItem(pinItem)
        }

        let hideItem = NSMenuItem(title: "Hide from Taskbar", action: #selector(contextBlacklist(_:)), keyEquivalent: "")
        hideItem.target = self
        hideItem.tag = index
        menu.addItem(hideItem)

        appendAppContextItems(to: menu)
        return menu
    }

    private func makeAppContextMenu() -> NSMenu {
        let menu = NSMenu()
        appendAppContextItems(to: menu, includeSeparator: false)
        return menu
    }

    private func appendAppContextItems(to menu: NSMenu, includeSeparator: Bool = true) {
        if includeSeparator, !menu.items.isEmpty {
            menu.addItem(.separator())
        }

        let preferences = NSMenuItem(title: "Preferences\u{2026}", action: #selector(contextOpenPreferences(_:)), keyEquivalent: ",")
        preferences.target = self
        preferences.keyEquivalentModifierMask = .command
        menu.addItem(preferences)

        let reload = NSMenuItem(title: "Reload config.json", action: #selector(contextReloadConfig(_:)), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit LiquidBar", action: #selector(contextQuit(_:)), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
    }

    @objc private func contextOpenPreferences(_ sender: NSMenuItem) {
        onAppContextAction?(.openPreferences)
    }

    @objc private func contextReloadConfig(_ sender: NSMenuItem) {
        onAppContextAction?(.reloadConfig)
    }

    @objc private func contextQuit(_ sender: NSMenuItem) {
        onAppContextAction?(.quit)
    }

    @objc private func contextClose(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .close, nil)
    }

    @objc private func contextPin(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .pin, nil)
    }

    @objc private func contextUnpin(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .unpin, nil)
    }

    @objc private func contextBlacklist(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .blacklist, nil)
    }

    @objc private func contextCreateTabGroup(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .createTabGroup, nil)
    }

    @objc private func contextAddToTabGroup(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .addToTabGroup, sender.representedObject as? String)
    }

    @objc private func contextRemoveFromTabGroup(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .removeFromTabGroup, sender.representedObject as? String)
    }

    @objc private func contextRenameTabGroup(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .renameTabGroup, sender.representedObject as? String)
    }

    @objc private func contextDeleteTabGroup(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .deleteTabGroup, sender.representedObject as? String)
    }

    @objc private func contextOpenCustomItem(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .openCustomItem, sender.representedObject as? String)
    }

    @objc private func contextEditCustomItem(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .editCustomItem, sender.representedObject as? String)
    }

    @objc private func contextDeleteCustomItem(_ sender: NSMenuItem) {
        onContextAction?(sender.tag, .deleteCustomItem, sender.representedObject as? String)
    }

    // MARK: - NSAccessibility

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .list
    }

    override func accessibilityLabel() -> String? {
        "Taskbar"
    }

    override func accessibilityChildren() -> [Any]? {
        items.enumerated().map { (i, item) in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(item.displayTitle(iconsOnly: false))
            element.setAccessibilityParent(self)
            element.setAccessibilityIdentifier(accessibilityIdentifierForItem(item, index: i))

            if i < itemRects.count {
                let rect = itemRects[i].rect
                // Convert to screen coordinates
                if let window = self.window {
                    let viewRect = NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
                    let windowRect = convert(viewRect, to: nil)
                    let screenRect = window.convertToScreen(windowRect)
                    element.setAccessibilityFrame(screenRect)
                }
            }

            return element
        }
    }

    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        let children = accessibilityChildren() ?? []
        return children.compactMap { $0 as? any NSAccessibilityElementProtocol }
    }

    private func accessibilityIdentifierForItem(_ item: TaskbarItem, index: Int) -> String {
        switch item {
        case .window(let id, _, _, _, _, _, _):
            return "liquidbar.item.window.\(id.raw)"
        case .appGroup(let bundleId, _, _, _, _, _, _):
            return "liquidbar.item.group.\(bundleId)"
        case .pinnedApp(let bundleId, _):
            return "liquidbar.item.pinned.\(bundleId)"
        case .launcher:
            return "liquidbar.item.launcher"
        case .pluginTile(let id, _, _, _, _, _):
            return "liquidbar.item.plugin.\(id)"
        case .tabGroup(let id, _, _, _, _, _, _, _):
            return "liquidbar.item.tabgroup.\(id)"
        case .customSpacer(let id, _, _):
            return "liquidbar.item.custom.spacer.\(id)"
        case .customText(let id, _, _):
            return "liquidbar.item.custom.text.\(id)"
        case .customLink(let id, _, _, _, _):
            return "liquidbar.item.custom.link.\(id)"
        case .customFolder(let id, _, _, _, _):
            return "liquidbar.item.custom.folder.\(id)"
        }
    }

    #if DEBUG
    /// UI-test hook: force hover state deterministically (without mouse motion).
    func setTestHoverIndex(_ index: Int?) {
        if hoveredIndex != index {
            hoveredIndex = index
            onHoverChanged?(index)
        }
    }
    #endif
}

private extension CALayer {
    func boundsForTopLeftRect(_ childRect: NSRect, in parentRect: NSRect) -> NSRect {
        guard !childRect.isEmpty else { return .zero }
        return NSRect(
            x: childRect.minX - parentRect.minX,
            y: parentRect.maxY - childRect.maxY,
            width: childRect.width,
            height: childRect.height
        )
    }
}
