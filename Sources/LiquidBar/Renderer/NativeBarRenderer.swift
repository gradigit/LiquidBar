// NativeBarRenderer.swift - retained AppKit/Core Animation taskbar renderer

import AppKit
import QuartzCore

extension Config {
    var taskbarSurfaceRenderKey: Config {
        var key = self
        key.adjustWindowsForTaskbar = true
        key.performanceLoggingEnabled = false
        key.performanceHangDiagnosticsEnabled = false
        key.performanceGpuTimingEnabled = false
        key.performanceLogIntervalMs = 0
        return key
    }
}

enum StaticUpdateResult {
    case rebuiltStaticState
    case reusedStaticState
}

struct SpringState {
    var current: Float
    var target: Float
    var velocity: Float = 0

    mutating func tick(stiffness: Float, damping: Float, dt: Float) -> Bool {
        let displacement = current - target
        let force = -stiffness * displacement - damping * velocity
        velocity += force * dt
        current += velocity * dt
        return abs(velocity) > SpringConstants.velocityThreshold ||
            abs(current - target) > SpringConstants.positionThreshold
    }

    mutating func snap() {
        current = target
        velocity = 0
    }
}

struct NativeTextOverlayItem: Sendable {
    var itemIndex: Int
    var title: String
    var x: Float
    var maxWidth: Float
    var isDimmed: Bool
    /// Top-left y-origin of the item slot for vertical sidebars.
    var nativeY: Float?
    /// Slot height used to vertically center text in vertical sidebars.
    var slotHeight: Float?
}

struct NativeDecoration {
    enum Kind {
        case hover
        case focus
        case badge
        case pin
        case stackPlate
        case pluginState
        case separator
        case dragShadow
        case systemMetricShell
        case systemMetricTrack
        case systemMetricFill
        case systemMetricGraph
    }

    var kind: Kind
    var rect: NSRect
    var cornerRadius: CGFloat
    var color: NSColor
    var alpha: Float
    var visualDepth: VisualDepth = .balanced
    var usesLayeredGlass: Bool = true
    /// Source item for decorations that should travel with the item during drag.
    var itemIndex: Int? = nil
}

struct NativeBarItemPresentation {
    var identity: String
    var item: TaskbarItem
    var rect: NSRect
    var iconRect: NSRect
    var titleRect: NSRect
    var icon: NSImage?
    var title: String
    var alpha: Float
    var isDimmed: Bool
    var cornerRadius: CGFloat
    var backgroundColor: NSColor?
}

struct NativeBarSnapshot {
    var items: [NativeBarItemPresentation]
    var hitRects: [(bundleId: String, index: Int, rect: NSRect)]
    var visualRects: [NSRect]
    var nativeTextItems: [NativeTextOverlayItem]
    var decorations: [NativeDecoration]
}

private struct StaticUpdateKey: Equatable {
    let itemSignature: Int
    let itemBackgroundSignature: Int
    let systemIndicatorVisualSignature: Int
    let focus: FocusInfo
    let sidebarExpanded: Bool
    let config: Config
    let iconRevision: UInt64
}

private struct NativePanelState {
    var barWidth: Float
    var barHeight: Float
    var scale: Float
    var lastStaticUpdateKey: StaticUpdateKey?
    var staticUpdateBuildCount: Int = 0
    var frameIndex: Int = 0
    var needsLayerSync: Bool = true
}

private struct DragAnimation {
    let sourceIndex: Int
    let sourceWidth: Float
    let leftMargin: Float
    var insertionIndex: Int
    var cursorX: Float
    var cursorOffsetInItem: Float
    var springs: [SpringState]
    var liftScale: Float = 1.0
    var liftVelocity: Float = 0
    var shadowAlpha: Float = 0
    var shadowVelocity: Float = 0
    var isSettling: Bool = false
    var lastTickTime: CFTimeInterval = 0
}

private enum DragLayoutElement {
    case item(Int)
    case gap
}

enum SpringConstants {
    static let gapStiffness: Float = 280
    static let gapDamping: Float = 20
    static let liftStiffness: Float = 400
    static let liftDamping: Float = 25
    static let settleStiffness: Float = 200
    static let settleDamping: Float = 12
    static let hoverStiffness: Float = 520
    static let hoverDamping: Float = 34
    static let hoverAlphaRate: Float = 18
    static let focusStiffness: Float = 360
    static let focusDamping: Float = 28
    static let focusAlphaRate: Float = 14
    static let velocityThreshold: Float = 0.1
    static let positionThreshold: Float = 0.5
    static let scaleThreshold: Float = 0.001
}

enum LayoutConstants {
    static let itemPadding: Float = 4
    static let iconLeftMargin: Float = 10
    static let iconGap: Float = 6
    static let textRightPadding: Float = 10
    static let hoverCornerRadius: Float = 8
    static let focusCornerRadius: Float = 8
    static let minItemWidth: Float = 44
    static let leftMargin: Float = 6
    static let itemSpacing: Float = 4
    static let badgeCornerRadius: Float = 4
    static let groupBadgeIconGap: Float = 5
    static let groupBadgeTextGap: Float = 5
    static let groupBadgeRightInset: Float = 2
    static let groupBadgeYOffset: Float = 0
    static let groupCompoundHorizontalPadding: Float = 7
    static let pinIndicatorWidth: Float = 16
    static let pinIndicatorHeight: Float = 2.5
    static let dragThreshold: Float = 6
}

private enum StackTokens {
    static let maxVisiblePlates = 4
    static let plateOffsetXSubtle: Float = 4.0
    static let plateOffsetXStrong: Float = 6.0
    static let hoverSpreadMultiplier: Float = 1.75
    static let stackBreathingWidthSubtle: Float = 6.0
    static let stackBreathingWidthStrong: Float = 10.0
    static let plateInsetY: Float = 6.0
}

@MainActor
final class NativeBarRenderer {
    private var panelStates: [CGDirectDisplayID: NativePanelState] = [:]
    private var panelItems: [CGDirectDisplayID: [TaskbarItem]] = [:]
    private var panelConfigs: [CGDirectDisplayID: Config] = [:]
    private var panelIconCaches: [CGDirectDisplayID: IconCache] = [:]
    private var itemBackgroundColorsByDisplay: [CGDirectDisplayID: [Int: String]] = [:]
    private var systemIndicatorVisualsByDisplay: [CGDirectDisplayID: [String: SystemIndicatorVisual]] = [:]
    private var itemLayouts: [CGDirectDisplayID: [(x: Float, width: Float)]] = [:]
    private var visualRectsByDisplay: [CGDirectDisplayID: [NSRect]] = [:]
    private var nativeTextOverlayItemsByDisplay: [CGDirectDisplayID: [NativeTextOverlayItem]] = [:]
    private var snapshotsByDisplay: [CGDirectDisplayID: NativeBarSnapshot] = [:]
    private var separatorX: [CGDirectDisplayID: Float] = [:]
    private var partitionIndex: [CGDirectDisplayID: Int] = [:]
    private var hoverRects: [CGDirectDisplayID: NSRect] = [:]
    private var focusRects: [CGDirectDisplayID: NSRect] = [:]
    private var cursorPositions: [CGDirectDisplayID: SIMD2<Float>] = [:]
    private var hoveredItemIndexByDisplay: [CGDirectDisplayID: Int] = [:]
    private var dragAnimations: [CGDirectDisplayID: DragAnimation] = [:]
    private var dragDecorationCount: [CGDirectDisplayID: Int] = [:]
    private var dragIconCount: [CGDirectDisplayID: Int] = [:]
    private var dragTextCount: [CGDirectDisplayID: Int] = [:]
    private var animationTuningByDisplay: [CGDirectDisplayID: RendererAnimationTuning] = [:]
    private let reduceMotion = SystemAccessibilityPreferences.reduceMotion

    init() {}

    func registerPanel(displayId: CGDirectDisplayID, barWidth: Float, barHeight: Float, scale: Float) {
        panelStates[displayId] = NativePanelState(barWidth: barWidth, barHeight: barHeight, scale: scale)
    }

    func unregisterPanel(displayId: CGDirectDisplayID) {
        panelStates.removeValue(forKey: displayId)
        panelItems.removeValue(forKey: displayId)
        panelConfigs.removeValue(forKey: displayId)
        panelIconCaches.removeValue(forKey: displayId)
        itemBackgroundColorsByDisplay.removeValue(forKey: displayId)
        systemIndicatorVisualsByDisplay.removeValue(forKey: displayId)
        itemLayouts.removeValue(forKey: displayId)
        visualRectsByDisplay.removeValue(forKey: displayId)
        nativeTextOverlayItemsByDisplay.removeValue(forKey: displayId)
        snapshotsByDisplay.removeValue(forKey: displayId)
        separatorX.removeValue(forKey: displayId)
        partitionIndex.removeValue(forKey: displayId)
        hoverRects.removeValue(forKey: displayId)
        focusRects.removeValue(forKey: displayId)
        cursorPositions.removeValue(forKey: displayId)
        hoveredItemIndexByDisplay.removeValue(forKey: displayId)
        dragAnimations.removeValue(forKey: displayId)
        dragDecorationCount.removeValue(forKey: displayId)
        dragIconCount.removeValue(forKey: displayId)
        dragTextCount.removeValue(forKey: displayId)
        animationTuningByDisplay.removeValue(forKey: displayId)
    }

    func resizePanel(displayId: CGDirectDisplayID, barWidth: Float, barHeight: Float, scale: Float) {
        guard var state = panelStates[displayId] else { return }
        state.barWidth = barWidth
        state.barHeight = barHeight
        state.scale = scale
        state.lastStaticUpdateKey = nil
        state.needsLayerSync = true
        panelStates[displayId] = state
        rebuildSnapshot(displayId: displayId)
    }

    @discardableResult
    func updateItems(
        _ items: [TaskbarItem],
        config: Config,
        iconCache: IconCache,
        displayId: CGDirectDisplayID,
        focus: FocusInfo = .none,
        sidebarExpanded: Bool = false,
        systemIndicatorVisuals: [String: SystemIndicatorVisual] = [:],
        itemBackgroundColors: [Int: String] = [:]
    ) -> StaticUpdateResult {
        guard var state = panelStates[displayId] else { return .rebuiltStaticState }

        panelItems[displayId] = items
        panelConfigs[displayId] = config
        panelIconCaches[displayId] = iconCache
        itemBackgroundColorsByDisplay[displayId] = itemBackgroundColors
        systemIndicatorVisualsByDisplay[displayId] = systemIndicatorVisuals
        animationTuningByDisplay[displayId] = config.animationProfile.rendererTuning
        hoveredItemIndexByDisplay[displayId] = hoveredItemIndexByDisplay[displayId] ?? -1

        let key = StaticUpdateKey(
            itemSignature: Self.taskbarItemSignature(for: items),
            itemBackgroundSignature: Self.itemBackgroundColorSignature(for: itemBackgroundColors),
            systemIndicatorVisualSignature: Self.systemIndicatorVisualSignature(for: systemIndicatorVisuals),
            focus: focus,
            sidebarExpanded: sidebarExpanded,
            config: config.taskbarSurfaceRenderKey,
            iconRevision: iconCache.revision
        )
        if state.lastStaticUpdateKey == key {
            panelStates[displayId] = state
            return .reusedStaticState
        }

        state.lastStaticUpdateKey = key
        state.staticUpdateBuildCount += 1
        state.frameIndex &+= 1
        state.needsLayerSync = true
        panelStates[displayId] = state

        let position = config.taskbarPosition
        let primaryLength = position.isVertical ? state.barHeight : state.barWidth
        let crossLength = position.isVertical ? state.barWidth : state.barHeight
        let layouts = computeItemLayouts(
            items: items,
            config: config,
            primaryLength: primaryLength,
            displayId: displayId,
            focus: focus,
            systemIndicatorVisuals: systemIndicatorVisuals
        )
        itemLayouts[displayId] = layouts

        let rects = layouts.map {
            layoutRect(origin: $0.x, length: $0.width, crossLength: crossLength, position: position)
        }
        visualRectsByDisplay[displayId] = rects

        if let focusIndex = focusedItemIndexForHighlight(items: items, focus: focus, config: config),
           focusIndex >= 0,
           focusIndex < rects.count {
            setFocusRect(focusIndicatorRect(base: rects[focusIndex], config: config, position: position), for: displayId)
        } else {
            setFocusRect(nil, for: displayId)
        }

        if dragAnimations[displayId] != nil && layouts.count != dragAnimations[displayId]?.springs.count {
            cancelDrag(displayId: displayId)
        }

        rebuildSnapshot(displayId: displayId, focus: focus, sidebarExpanded: sidebarExpanded)
        return .rebuiltStaticState
    }

    func snapshot(displayId: CGDirectDisplayID) -> NativeBarSnapshot? {
        snapshotsByDisplay[displayId]
    }

    func nativeTextOverlayItems(displayId: CGDirectDisplayID) -> [NativeTextOverlayItem] {
        var items = nativeTextOverlayItemsByDisplay[displayId] ?? []
        guard let anim = dragAnimations[displayId],
              let layouts = itemLayouts[displayId],
              layouts.count == anim.springs.count,
              anim.sourceIndex >= 0,
              anim.sourceIndex < layouts.count else {
            return items
        }

        var xByIndex = anim.springs.map(\.current)
        let sourceX = anim.isSettling
            ? anim.springs[anim.sourceIndex].current
            : anim.cursorX - anim.cursorOffsetInItem
        xByIndex[anim.sourceIndex] = sourceX

        for i in items.indices {
            let idx = items[i].itemIndex
            guard idx >= 0, idx < layouts.count else { continue }
            items[i].x += xByIndex[idx] - layouts[idx].x
        }

        return items
    }

    func debugDecorationCount(displayId: CGDirectDisplayID) -> Int {
        snapshotsByDisplay[displayId]?.decorations.count ?? 0
    }

    func debugStaticUpdateBuildCount(displayId: CGDirectDisplayID) -> Int {
        panelStates[displayId]?.staticUpdateBuildCount ?? 0
    }

    func debugFrameIndex(displayId: CGDirectDisplayID) -> Int {
        panelStates[displayId]?.frameIndex ?? 0
    }

    func visualItemRects(displayId: CGDirectDisplayID) -> [NSRect] {
        visualRectsByDisplay[displayId] ?? []
    }

    func computeItemRects(
        items: [TaskbarItem],
        config: Config,
        barWidth: Float,
        barHeight: Float,
        focus: FocusInfo = .none,
        sidebarExpanded: Bool = false
    ) -> [(bundleId: String, index: Int, rect: NSRect)] {
        let position = config.taskbarPosition
        let primaryLength = position.isVertical ? barHeight : barWidth
        let crossLength = position.isVertical ? barWidth : barHeight
        let layouts = computeItemLayouts(items: items, config: config, primaryLength: primaryLength, focus: focus)
        return items.enumerated().map { index, item in
            (
                bundleId: item.bundleId,
                index: index,
                rect: layoutRect(origin: layouts[index].x, length: layouts[index].width, crossLength: crossLength, position: position)
            )
        }
    }

    func forceRedraw(displayId: CGDirectDisplayID) {
        if panelStates[displayId] != nil {
            panelStates[displayId]?.needsLayerSync = true
        }
        rebuildSnapshot(displayId: displayId)
    }

    @discardableResult
    func setHoveredItemIndex(_ index: Int?, for displayId: CGDirectDisplayID) -> Bool {
        let next = index ?? -1
        guard hoveredItemIndexByDisplay[displayId] != next else { return false }
        hoveredItemIndexByDisplay[displayId] = next
        return true
    }

    @discardableResult
    func setCursorPosition(_ point: SIMD2<Float>?, for displayId: CGDirectDisplayID) -> Bool {
        if let point {
            guard cursorPositions[displayId] != point else { return false }
            cursorPositions[displayId] = point
        } else {
            guard cursorPositions[displayId] != nil else { return false }
            cursorPositions.removeValue(forKey: displayId)
        }
        return true
    }

    @discardableResult
    func setHoverRect(_ rect: NSRect?, for displayId: CGDirectDisplayID) -> Bool {
        if let rect {
            let snapped = snapRectToBackingPixels(rect, displayId: displayId)
            guard hoverRects[displayId] != snapped else { return false }
            hoverRects[displayId] = snapped
        } else {
            guard hoverRects[displayId] != nil else { return false }
            hoverRects.removeValue(forKey: displayId)
        }
        rebuildSnapshot(displayId: displayId)
        return true
    }

    func debugHoverRect(displayId: CGDirectDisplayID) -> NSRect? {
        hoverRects[displayId]
    }

    func debugCursorPoint(displayId: CGDirectDisplayID) -> NSPoint? {
        guard let c = cursorPositions[displayId] else { return nil }
        return NSPoint(x: Double(c.x), y: Double(c.y))
    }

    func startDrag(
        sourceIndex: Int,
        cursorX: Float,
        cursorOffsetInItem: Float,
        config: Config,
        displayId: CGDirectDisplayID
    ) {
        guard let layouts = itemLayouts[displayId],
              sourceIndex >= 0,
              sourceIndex < layouts.count else { return }
        if let partition = partitionIndex[displayId], sourceIndex >= partition { return }

        var anim = DragAnimation(
            sourceIndex: sourceIndex,
            sourceWidth: layouts[sourceIndex].width,
            leftMargin: layoutLeftMargin(config: config),
            insertionIndex: sourceIndex,
            cursorX: cursorX,
            cursorOffsetInItem: cursorOffsetInItem,
            springs: layouts.map { SpringState(current: $0.x, target: $0.x) },
            lastTickTime: CACurrentMediaTime()
        )
        computeGapTargets(&anim, layouts: layouts, displayId: displayId)
        dragAnimations[displayId] = anim
        hoverRects.removeValue(forKey: displayId)
        rebuildSnapshot(displayId: displayId)
    }

    func updateDragCursor(cursorX: Float, insertionIndex: Int, displayId: CGDirectDisplayID) {
        guard var anim = dragAnimations[displayId] else { return }
        anim.cursorX = cursorX
        anim.insertionIndex = partitionIndex[displayId].map { min(insertionIndex, $0) } ?? insertionIndex
        if let layouts = itemLayouts[displayId] {
            computeGapTargets(&anim, layouts: layouts, displayId: displayId)
        }
        dragAnimations[displayId] = anim
        rebuildSnapshot(displayId: displayId)
    }

    func endDrag(displayId: CGDirectDisplayID) {
        guard var anim = dragAnimations[displayId] else { return }
        anim.isSettling = true
        if let layouts = itemLayouts[displayId] {
            computeSettleTargets(&anim, layouts: layouts, displayId: displayId)
        }
        dragAnimations[displayId] = anim
        rebuildSnapshot(displayId: displayId)
    }

    func cancelDrag(displayId: CGDirectDisplayID) {
        dragAnimations.removeValue(forKey: displayId)
        dragDecorationCount.removeValue(forKey: displayId)
        dragIconCount.removeValue(forKey: displayId)
        dragTextCount.removeValue(forKey: displayId)
        rebuildSnapshot(displayId: displayId)
    }

    func hasDragAnimation(for displayId: CGDirectDisplayID) -> Bool {
        dragAnimations[displayId] != nil
    }

    func debugDragCounts(displayId: CGDirectDisplayID) -> (decoration: Int, icon: Int, text: Int) {
        (
            dragDecorationCount[displayId] ?? 0,
            dragIconCount[displayId] ?? 0,
            dragTextCount[displayId] ?? 0
        )
    }

    func debugDragSpringTargets(displayId: CGDirectDisplayID) -> [Float] {
        dragAnimations[displayId]?.springs.map(\.target) ?? []
    }

    func tickAndRebuildDragBuffers(displayId: CGDirectDisplayID) -> Bool {
        guard var anim = dragAnimations[displayId] else { return false }
        let tuning = animationTuningByDisplay[displayId] ?? AnimationProfile.balancedSpring.rendererTuning
        let now = CACurrentMediaTime()
        let dt = Float(min(now - anim.lastTickTime, 1.0 / 30.0))
        anim.lastTickTime = now

        if reduceMotion {
            for i in anim.springs.indices { anim.springs[i].snap() }
            anim.liftScale = anim.isSettling ? 1.0 : 1.08
            anim.shadowAlpha = anim.isSettling ? 0 : 0.14
        } else {
            let stiffness = (anim.isSettling ? SpringConstants.settleStiffness : SpringConstants.gapStiffness) * tuning.stiffnessScale
            let damping = (anim.isSettling ? SpringConstants.settleDamping : SpringConstants.gapDamping) * tuning.dampingScale
            for i in anim.springs.indices {
                _ = anim.springs[i].tick(stiffness: stiffness, damping: damping, dt: dt)
            }

            let liftTarget: Float = anim.isSettling ? 1.0 : 1.08
            let liftDisp = anim.liftScale - liftTarget
            let liftForce = -(SpringConstants.liftStiffness * tuning.stiffnessScale) * liftDisp -
                (SpringConstants.liftDamping * tuning.dampingScale) * anim.liftVelocity
            anim.liftVelocity += liftForce * dt
            anim.liftScale += anim.liftVelocity * dt

            let shadowTarget: Float = anim.isSettling ? 0 : 0.14
            let shadowDisp = anim.shadowAlpha - shadowTarget
            let shadowForce = -(SpringConstants.liftStiffness * tuning.stiffnessScale) * shadowDisp -
                (SpringConstants.liftDamping * tuning.dampingScale) * anim.shadowVelocity
            anim.shadowVelocity += shadowForce * dt
            anim.shadowAlpha += anim.shadowVelocity * dt
        }

        var stillAnimating = anim.springs.contains {
            abs($0.velocity) > SpringConstants.velocityThreshold ||
                abs($0.current - $0.target) > SpringConstants.positionThreshold
        }
        let liftTarget: Float = anim.isSettling ? 1.0 : 1.08
        let shadowTarget: Float = anim.isSettling ? 0 : 0.14
        if abs(anim.liftScale - liftTarget) > SpringConstants.scaleThreshold ||
            abs(anim.liftVelocity) > SpringConstants.scaleThreshold ||
            abs(anim.shadowAlpha - shadowTarget) > SpringConstants.scaleThreshold {
            stillAnimating = true
        }

        dragAnimations[displayId] = anim
        rebuildSnapshot(displayId: displayId)

        if anim.isSettling && !stillAnimating {
            dragAnimations.removeValue(forKey: displayId)
            dragDecorationCount.removeValue(forKey: displayId)
            dragIconCount.removeValue(forKey: displayId)
            dragTextCount.removeValue(forKey: displayId)
            rebuildSnapshot(displayId: displayId)
            return false
        }

        return true
    }

    func shutdown() {
        panelStates.removeAll()
        panelItems.removeAll()
        panelConfigs.removeAll()
        panelIconCaches.removeAll()
        itemBackgroundColorsByDisplay.removeAll()
        systemIndicatorVisualsByDisplay.removeAll()
        itemLayouts.removeAll()
        visualRectsByDisplay.removeAll()
        nativeTextOverlayItemsByDisplay.removeAll()
        snapshotsByDisplay.removeAll()
        separatorX.removeAll()
        partitionIndex.removeAll()
        hoverRects.removeAll()
        focusRects.removeAll()
        cursorPositions.removeAll()
        hoveredItemIndexByDisplay.removeAll()
        dragAnimations.removeAll()
    }

    private func rebuildSnapshot(
        displayId: CGDirectDisplayID,
        focus: FocusInfo = .none,
        sidebarExpanded: Bool = false
    ) {
        guard let state = panelStates[displayId],
              let config = panelConfigs[displayId],
              let iconCache = panelIconCaches[displayId] else { return }
        let items = panelItems[displayId] ?? []
        let layouts = itemLayouts[displayId] ?? []
        let position = config.taskbarPosition
        let crossLength = position.isVertical ? state.barWidth : state.barHeight
        let iconSize = Float(config.iconSize)
        let displayIconsOnly = effectiveDisplayIconsOnly(config: config, position: position, sidebarExpanded: sidebarExpanded)
        let rects = visualRectsByDisplay[displayId] ?? []
        let systemIndicatorVisuals = systemIndicatorVisualsByDisplay[displayId] ?? [:]

        var presentations: [NativeBarItemPresentation] = []
        var textItems: [NativeTextOverlayItem] = []
        var decorations: [NativeDecoration] = []
        presentations.reserveCapacity(items.count)

        let visualDepth = config.visualDepth
        let hoverAlpha = 0.12 + 0.10 * config.hoverIntensity.floatValue

        if let hover = hoverRects[displayId] {
            decorations.append(NativeDecoration(kind: .hover, rect: hover, cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius), color: .white, alpha: hoverAlpha, visualDepth: visualDepth))
        }
        if let focus = focusRects[displayId] {
            decorations.append(NativeDecoration(kind: .focus, rect: focus, cornerRadius: CGFloat(LayoutConstants.focusCornerRadius), color: NSColor(calibratedRed: 0.45, green: 0.68, blue: 1.0, alpha: 1), alpha: 0.30, visualDepth: visualDepth))
        }

        for (index, item) in items.enumerated() {
            guard index < layouts.count, index < rects.count else { continue }
            let rect = rects[index]
            let metricVisual = systemIndicatorVisual(for: item, visuals: systemIndicatorVisuals)
            let collapseForIconsOnly = displayIconsOnly && metricVisual == nil
            let forceIconOnlyForCollapsedPartition = metricVisual == nil &&
                (partitionIndex[displayId] != nil && index >= partitionIndex[displayId]!)
            let collapseForOverflow = shouldCollapseTitleForOverflow(
                item: item,
                rect: rect,
                config: config,
                position: position,
                iconSize: iconSize,
                systemIndicatorVisuals: systemIndicatorVisuals
            )
            let title = item.displayTitle(iconsOnly: collapseForIconsOnly || forceIconOnlyForCollapsedPartition || collapseForOverflow)
            let alpha: Float = item.isDimmed ? 0.5 : 1.0
            let icon: NSImage? = item.iconKey.flatMap { iconCache.getIcon(bundleId: $0) }
            let iconRect = iconRectForItem(
                rect: rect,
                item: item,
                title: title,
                iconSize: iconSize,
                config: config,
                position: position,
                sidebarExpanded: sidebarExpanded,
                isHovered: hoveredItemIndexByDisplay[displayId] == index
            )
            let titleRect = titleRectForItem(
                rect: rect,
                item: item,
                iconRect: iconRect,
                title: title,
                position: position,
                config: config,
                systemIndicatorVisual: metricVisual
            )

            presentations.append(NativeBarItemPresentation(
                identity: Self.identity(for: item, index: index),
                item: item,
                rect: rect,
                iconRect: iconRect,
                titleRect: titleRect,
                icon: icon,
                title: title,
                alpha: alpha,
                isDimmed: item.isDimmed,
                cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius),
                backgroundColor: PresentationColorPalette.color(from: itemBackgroundColorsByDisplay[displayId]?[index])
            ))

            if !title.isEmpty {
                textItems.append(NativeTextOverlayItem(
                    itemIndex: index,
                    title: title,
                    x: Float(titleRect.minX),
                    maxWidth: Float(titleRect.width),
                    isDimmed: item.isDimmed,
                    nativeY: position.isVertical ? Float(rect.minY) : nil,
                    slotHeight: position.isVertical ? Float(rect.height) : nil
                ))
            }

            appendDecorations(
                for: item,
                index: index,
                displayId: displayId,
                rect: rect,
                title: title,
                iconRect: iconRect,
                config: config,
                alpha: alpha,
                systemIndicatorVisual: metricVisual,
                into: &decorations,
                textItems: &textItems
            )
        }

        if let sepX = separatorX[displayId] {
            if position.isVertical {
                decorations.append(NativeDecoration(
                    kind: .separator,
                    rect: NSRect(x: Double(crossLength * 0.15), y: Double(sepX + 3), width: Double(crossLength * 0.7), height: 1.5),
                    cornerRadius: 0.75,
                    color: .white,
                    alpha: 0.15,
                    visualDepth: visualDepth
                ))
            } else {
                decorations.append(NativeDecoration(
                    kind: .separator,
                    rect: NSRect(x: Double(sepX + 3), y: Double(crossLength * 0.15), width: 1.5, height: Double(crossLength * 0.7)),
                    cornerRadius: 0.75,
                    color: .white,
                    alpha: 0.15,
                    visualDepth: visualDepth
                ))
            }
        }

        applyDragPresentation(displayId: displayId, presentations: &presentations, decorations: &decorations)

        nativeTextOverlayItemsByDisplay[displayId] = textItems
        snapshotsByDisplay[displayId] = NativeBarSnapshot(
            items: presentations,
            hitRects: items.enumerated().compactMap { index, item in
                guard index < rects.count else { return nil }
                return (bundleId: item.bundleId, index: index, rect: rects[index])
            },
            visualRects: rects,
            nativeTextItems: nativeTextOverlayItems(displayId: displayId),
            decorations: decorations
        )
    }

    private func applyDragPresentation(
        displayId: CGDirectDisplayID,
        presentations: inout [NativeBarItemPresentation],
        decorations: inout [NativeDecoration]
    ) {
        guard let anim = dragAnimations[displayId],
              let layouts = itemLayouts[displayId],
              anim.sourceIndex >= 0,
              anim.sourceIndex < presentations.count,
              layouts.count == presentations.count else {
            dragDecorationCount[displayId] = 0
            dragIconCount[displayId] = 0
            dragTextCount[displayId] = 0
            return
        }
        let position = panelConfigs[displayId]?.taskbarPosition ?? .bottom
        let visualDepth = panelConfigs[displayId]?.visualDepth ?? .balanced
        let participants = Set(dragParticipantIndices(layouts: layouts, sourceIndex: anim.sourceIndex, displayId: displayId))
        var primaryDeltaByIndex: [Int: CGFloat] = [:]

        for index in presentations.indices where index != anim.sourceIndex && participants.contains(index) {
            let delta = CGFloat(anim.springs[index].current - layouts[index].x)
            primaryDeltaByIndex[index] = delta
            applyPrimaryDelta(delta, to: &presentations[index].rect, position: position)
            applyPrimaryDelta(delta, to: &presentations[index].iconRect, position: position)
            applyPrimaryDelta(delta, to: &presentations[index].titleRect, position: position)
            presentations[index].alpha *= 0.72
        }

        let sourcePrimary = CGFloat(anim.isSettling ? anim.springs[anim.sourceIndex].current : anim.cursorX - anim.cursorOffsetInItem)
        let sourceDelta = sourcePrimary - primaryOrigin(of: presentations[anim.sourceIndex].rect, position: position)
        primaryDeltaByIndex[anim.sourceIndex] = sourceDelta
        applyPrimaryDelta(sourceDelta, to: &presentations[anim.sourceIndex].rect, position: position)
        applyPrimaryDelta(sourceDelta, to: &presentations[anim.sourceIndex].iconRect, position: position)
        applyPrimaryDelta(sourceDelta, to: &presentations[anim.sourceIndex].titleRect, position: position)

        for index in decorations.indices {
            guard let itemIndex = decorations[index].itemIndex,
                  let delta = primaryDeltaByIndex[itemIndex] else {
                continue
            }
            applyPrimaryDelta(delta, to: &decorations[index].rect, position: position)
        }

        decorations.append(NativeDecoration(
            kind: .hover,
            rect: presentations[anim.sourceIndex].rect.insetBy(dx: 1, dy: 1),
            cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius),
            color: .white,
            alpha: 0.16,
            visualDepth: visualDepth
        ))

        if anim.shadowAlpha > 0.005 {
            var shadow = presentations[anim.sourceIndex].rect.insetBy(dx: -1.5, dy: -1)
            shadow.origin.y += 1
            decorations.append(NativeDecoration(kind: .dragShadow, rect: shadow, cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius + 1), color: .black, alpha: anim.shadowAlpha * 0.55, visualDepth: visualDepth))
        }

        dragDecorationCount[displayId] = decorations.count
        dragIconCount[displayId] = presentations.count
        dragTextCount[displayId] = nativeTextOverlayItemsByDisplay[displayId]?.count ?? 0
    }

    private func primaryOrigin(of rect: NSRect, position: Position) -> CGFloat {
        position.isVertical ? rect.minY : rect.minX
    }

    private func applyPrimaryDelta(_ delta: CGFloat, to rect: inout NSRect, position: Position) {
        if position.isVertical {
            rect.origin.y += delta
        } else {
            rect.origin.x += delta
        }
    }

    private func appendDecorations(
        for item: TaskbarItem,
        index: Int,
        displayId: CGDirectDisplayID,
        rect: NSRect,
        title: String,
        iconRect: NSRect,
        config: Config,
        alpha: Float,
        systemIndicatorVisual: SystemIndicatorVisual?,
        into decorations: inout [NativeDecoration],
        textItems: inout [NativeTextOverlayItem]
    ) {
        let ownedDecorationStart = decorations.count
        defer {
            if ownedDecorationStart < decorations.count {
                for decorationIndex in ownedDecorationStart..<decorations.count {
                    decorations[decorationIndex].itemIndex = index
                }
            }
        }

        if let systemIndicatorVisual {
            appendSystemIndicatorDecorations(
                metricVisual: systemIndicatorVisual,
                rect: rect,
                config: config,
                alpha: alpha,
                into: &decorations
            )
        }

        if case .pinnedApp = item {
            let pinRect: NSRect
            if config.taskbarPosition.isVertical {
                let w = CGFloat(LayoutConstants.pinIndicatorHeight)
                let h = CGFloat(LayoutConstants.pinIndicatorWidth)
                let x = config.taskbarPosition.isLeft ? rect.maxX - w - 2 : rect.minX + 2
                pinRect = NSRect(x: x, y: rect.minY + (rect.height - h) / 2, width: w, height: h)
            } else {
                let w = CGFloat(LayoutConstants.pinIndicatorWidth)
                let h = CGFloat(LayoutConstants.pinIndicatorHeight)
                pinRect = NSRect(x: rect.minX + (rect.width - w) / 2, y: rect.maxY - h - 2, width: w, height: h)
            }
            decorations.append(NativeDecoration(kind: .pin, rect: pinRect, cornerRadius: min(pinRect.width, pinRect.height) / 2, color: NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1), alpha: 0.8, visualDepth: config.visualDepth))
        }

        if !config.taskbarPosition.isVertical,
           config.groupByApp,
           case .appGroup(_, _, let windowCount, _, _, _, _) = item,
           windowCount > 1 {
            let plateCount = min(windowCount, StackTokens.maxVisiblePlates)
            let baseOffset = config.appGroupStackGeometry == .strong ? StackTokens.plateOffsetXStrong : StackTokens.plateOffsetXSubtle
            let isHovered = hoveredItemIndexByDisplay[displayId] == index
            let spreadOffset = config.appGroupStackHoverSpreadEnabled && isHovered
                ? baseOffset * StackTokens.hoverSpreadMultiplier
                : baseOffset
            let plateAlpha: Float = {
                switch config.appGroupStackStyle {
                case .filled:
                    return 0.16 * alpha
                case .outline:
                    return 0.08 * alpha
                }
            }()
            if plateCount > 1 {
                for plateIndex in stride(from: plateCount - 1, through: 1, by: -1) {
                    let inset = CGFloat(plateIndex) * 0.7
                    let plateRect = NSRect(
                        x: iconRect.minX + CGFloat(spreadOffset * Float(plateIndex)),
                        y: iconRect.minY + inset,
                        width: max(4, iconRect.width - inset),
                        height: max(4, iconRect.height - inset * 2)
                    )
                    decorations.append(NativeDecoration(
                        kind: .stackPlate,
                        rect: plateRect,
                        cornerRadius: min(6, plateRect.height / 2),
                        color: .white,
                        alpha: plateAlpha,
                        visualDepth: config.visualDepth
                    ))
                }
            }
        }

        if !config.taskbarPosition.isVertical,
           config.appGroupCountBadgeInIconsOnly,
           title.isEmpty,
           case .appGroup(_, _, let windowCount, _, _, _, _) = item,
           windowCount > 1 {
            let metrics = appGroupBadgeMetrics(
                windowCount: windowCount,
                titleIsEmpty: title.isEmpty,
                style: config.appGroupCountBadgeStyle,
                alpha: alpha
            )
            let stackExtension = CGFloat(appGroupStackExtension(
                windowCount: windowCount,
                config: config,
                isHovered: hoveredItemIndexByDisplay[displayId] == index
            ))
            let preferredX = iconRect.maxX + stackExtension + CGFloat(LayoutConstants.groupBadgeIconGap)
            let maxX = rect.maxX - metrics.width - CGFloat(LayoutConstants.groupBadgeRightInset)
            let x = min(preferredX, maxX)
            let badgeRect = NSRect(
                x: x,
                y: rect.minY + (rect.height - metrics.height) / 2,
                width: metrics.width,
                height: metrics.height
            )
            if config.appGroupCountBadgeStyle == .separator {
                decorations.append(NativeDecoration(
                    kind: .separator,
                    rect: NSRect(x: badgeRect.minX - 3, y: badgeRect.minY + 2, width: 1.5, height: max(4, badgeRect.height - 4)),
                    cornerRadius: 0.75,
                    color: .white,
                    alpha: 0.18 * alpha,
                    visualDepth: config.visualDepth
                ))
            } else {
                decorations.append(NativeDecoration(
                    kind: .badge,
                    rect: badgeRect,
                    cornerRadius: metrics.cornerRadius,
                    color: .white,
                    alpha: metrics.alpha,
                    visualDepth: config.visualDepth
                ))
            }
            textItems.append(NativeTextOverlayItem(
                itemIndex: index,
                title: metrics.text,
                x: Float(badgeRect.minX + max(2, (badgeRect.width - metrics.textWidth) / 2)),
                maxWidth: Float(max(4, metrics.textWidth + 1)),
                isDimmed: item.isDimmed,
                nativeY: nil,
                slotHeight: nil
            ))
        }

        if case .pluginTile(_, _, _, _, let visualState, _) = item {
            switch visualState {
            case .idle:
                break
            case .active:
                decorations.append(NativeDecoration(kind: .pluginState, rect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 7, color: NSColor(calibratedRed: 0.45, green: 0.78, blue: 1.0, alpha: 1), alpha: 0.18, visualDepth: config.visualDepth))
            case .attention:
                decorations.append(NativeDecoration(kind: .pluginState, rect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 8, color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.26, alpha: 1), alpha: 0.24, visualDepth: config.visualDepth))
                decorations.append(NativeDecoration(kind: .pluginState, rect: NSRect(x: rect.maxX - 10, y: rect.minY + 5, width: 4, height: 4), cornerRadius: 2, color: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.34, alpha: 1), alpha: 0.88, visualDepth: config.visualDepth))
            }
        }
    }

    private func appendSystemIndicatorDecorations(
        metricVisual: SystemIndicatorVisual,
        rect: NSRect,
        config: Config,
        alpha: Float,
        into decorations: inout [NativeDecoration]
    ) {
        guard config.taskbarPosition.isHorizontal else { return }
        let layout = metricChipLayout(for: config.systemIndicatorChipPreset)
        let accent = SystemIndicatorColorPalette.accentColor(
            for: metricVisual.metric,
            severity: metricVisual.severity,
            config: config
        )

        if config.systemIndicatorChipPreset == .micro {
            appendMicroSystemIndicatorDecorations(
                metricVisual: metricVisual,
                rect: rect,
                layout: layout,
                accent: accent,
                config: config,
                alpha: alpha,
                into: &decorations
            )
            return
        }

        if config.systemIndicatorChipPreset == .dense {
            appendDenseSystemIndicatorDecorations(
                metricVisual: metricVisual,
                rect: rect,
                layout: layout,
                accent: accent,
                config: config,
                alpha: alpha,
                into: &decorations
            )
            return
        }

        let shell = rect.insetBy(dx: CGFloat(layout.shellInsetX), dy: CGFloat(layout.shellInsetY))
        switch config.systemIndicatorAppearance {
        case .glass:
            decorations.append(NativeDecoration(
                kind: .systemMetricShell,
                rect: shell,
                cornerRadius: min(8, shell.height / 2),
                color: .white,
                alpha: 0.07 * alpha,
                visualDepth: config.visualDepth
            ))
        case .flat:
            decorations.append(NativeDecoration(
                kind: .systemMetricShell,
                rect: shell,
                cornerRadius: min(7, shell.height / 2),
                color: accent,
                alpha: 0.12 * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))
        case .underline, .minimal:
            break
        }

        let trackW = max(8, rect.width - CGFloat(layout.trackInsetX * 2))
        let trackRect: NSRect = {
            switch config.systemIndicatorAppearance {
            case .underline:
                return NSRect(
                    x: rect.minX + 10,
                    y: rect.maxY - 4.5,
                    width: max(8, rect.width - 20),
                    height: 2
                )
            case .minimal:
                return NSRect(
                    x: rect.minX + 7,
                    y: rect.maxY - 4,
                    width: max(6, rect.width - 14),
                    height: 1.6
                )
            case .glass, .flat:
                return NSRect(
                    x: rect.minX + CGFloat(layout.trackInsetX),
                    y: rect.maxY - CGFloat(layout.trackBottomInset + layout.trackHeight),
                    width: trackW,
                    height: CGFloat(layout.trackHeight)
                )
            }
        }()
        if config.systemIndicatorAppearance != .minimal {
            decorations.append(NativeDecoration(
                kind: .systemMetricTrack,
                rect: trackRect,
                cornerRadius: trackRect.height / 2,
                color: config.systemIndicatorAppearance == .flat ? accent : .white,
                alpha: (config.systemIndicatorAppearance == .underline ? 0.16 : 0.12) * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))
        }

        switch metricVisual.mode {
        case .percentage, .bar:
            guard let value = metricVisual.valuePercent else { return }
            let fraction = CGFloat(min(max(value / 100, 0), 1))
            let fillWidth = max(2, trackRect.width * fraction)
            let fillRect: NSRect
            if config.systemIndicatorAppearance == .minimal {
                fillRect = NSRect(
                    x: trackRect.minX,
                    y: trackRect.minY,
                    width: min(trackRect.width, max(3, fillWidth)),
                    height: trackRect.height
                )
            } else {
                fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height)
            }
            decorations.append(NativeDecoration(
                kind: .systemMetricFill,
                rect: fillRect,
                cornerRadius: trackRect.height / 2,
                color: accent,
                alpha: 0.82 * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))

        case .graph:
            appendSystemIndicatorGraphDecorations(
                metricVisual: metricVisual,
                trackRect: trackRect,
                layout: layout,
                accent: accent,
                alpha: alpha,
                visualDepth: config.visualDepth,
                into: &decorations
            )
        }
    }

    private func appendDenseSystemIndicatorDecorations(
        metricVisual: SystemIndicatorVisual,
        rect: NSRect,
        layout: MetricChipLayout,
        accent: NSColor,
        config: Config,
        alpha: Float,
        into decorations: inout [NativeDecoration]
    ) {
        let shellInsetX = config.systemIndicatorAppearance == .flat ? Float(0) : layout.shellInsetX
        let shell = rect.insetBy(dx: CGFloat(shellInsetX), dy: CGFloat(layout.shellInsetY))
        switch config.systemIndicatorAppearance {
        case .glass:
            decorations.append(NativeDecoration(
                kind: .systemMetricShell,
                rect: shell,
                cornerRadius: min(7, shell.height / 2),
                color: .white,
                alpha: 0.06 * alpha,
                visualDepth: config.visualDepth
            ))
        case .flat:
            decorations.append(NativeDecoration(
                kind: .systemMetricShell,
                rect: shell,
                cornerRadius: min(7, shell.height / 2),
                color: accent,
                alpha: 0.11 * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))
        case .underline, .minimal:
            break
        }

        guard config.systemIndicatorAppearance != .minimal,
              let value = metricVisual.valuePercent else { return }

        let trackRect = NSRect(
            x: rect.minX + CGFloat(layout.trackInsetX),
            y: rect.maxY - CGFloat(layout.trackBottomInset + layout.trackHeight),
            width: max(6, rect.width - CGFloat(layout.trackInsetX * 2)),
            height: CGFloat(layout.trackHeight)
        )
        if config.systemIndicatorAppearance == .underline {
            decorations.append(NativeDecoration(
                kind: .systemMetricTrack,
                rect: trackRect,
                cornerRadius: trackRect.height / 2,
                color: .white,
                alpha: 0.13 * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))
        }

        let fraction = CGFloat(min(max(value / 100, 0), 1))
        decorations.append(NativeDecoration(
            kind: .systemMetricFill,
            rect: NSRect(x: trackRect.minX, y: trackRect.minY, width: max(2, trackRect.width * fraction), height: trackRect.height),
            cornerRadius: trackRect.height / 2,
            color: accent,
            alpha: 0.80 * alpha,
            visualDepth: config.visualDepth,
            usesLayeredGlass: false
        ))
    }

    private func appendMicroSystemIndicatorDecorations(
        metricVisual: SystemIndicatorVisual,
        rect: NSRect,
        layout: MetricChipLayout,
        accent: NSColor,
        config: Config,
        alpha: Float,
        into decorations: inout [NativeDecoration]
    ) {
        let values = microIndicatorValues(metricVisual)
        let shell = rect.insetBy(dx: CGFloat(layout.shellInsetX), dy: CGFloat(layout.shellInsetY))
        if config.systemIndicatorAppearance == .glass || config.systemIndicatorAppearance == .flat {
            decorations.append(NativeDecoration(
                kind: .systemMetricShell,
                rect: shell,
                cornerRadius: min(5, shell.height / 2),
                color: config.systemIndicatorAppearance == .flat ? accent : .white,
                alpha: (config.systemIndicatorAppearance == .flat ? 0.08 : 0.045) * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: config.systemIndicatorAppearance == .glass
            ))
        }

        let count = max(1, min(values.count, 5))
        let barWidth = CGFloat(layout.graphBarWidth)
        let gap = CGFloat(layout.graphBarGap)
        let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
        let baseHeight = max(10, rect.height - CGFloat(layout.shellInsetY * 2 + 3))
        let startX = rect.midX - totalWidth / 2
        let baseline = rect.midY + baseHeight / 2
        for (offset, value) in values.suffix(count).enumerated() {
            let normalized = CGFloat(min(max(value / 100, 0), 1))
            let height = max(2, baseHeight * normalized)
            decorations.append(NativeDecoration(
                kind: .systemMetricGraph,
                rect: NSRect(
                    x: startX + CGFloat(offset) * (barWidth + gap),
                    y: baseline - height,
                    width: barWidth,
                    height: height
                ),
                cornerRadius: min(barWidth / 2, 1.5),
                color: accent,
                alpha: 0.82 * alpha,
                visualDepth: config.visualDepth,
                usesLayeredGlass: false
            ))
        }
    }

    private func microIndicatorValues(_ metricVisual: SystemIndicatorVisual) -> [Float] {
        let values = metricVisual.history.isEmpty ? [] : Array(metricVisual.history.suffix(5))
        if !values.isEmpty { return values }
        if let value = metricVisual.valuePercent { return [value] }
        return [18]
    }

    private func appendSystemIndicatorGraphDecorations(
        metricVisual: SystemIndicatorVisual,
        trackRect: NSRect,
        layout: MetricChipLayout,
        accent: NSColor,
        alpha: Float,
        visualDepth: VisualDepth,
        into decorations: inout [NativeDecoration]
    ) {
        let values = Array(metricVisual.history.suffix(16))
        guard !values.isEmpty else { return }

        let barWidth = CGFloat(layout.graphBarWidth)
        let gap = CGFloat(layout.graphBarGap)
        let stride = max(0.5, barWidth + gap)
        let maxVisible = max(1, Int(floor((trackRect.width + gap) / stride)))
        let visible = Array(values.suffix(maxVisible))
        let totalWidth = min(trackRect.width, CGFloat(visible.count) * stride - gap)
        let startX = trackRect.maxX - totalWidth
        let maxBarHeight = max(4, trackRect.height * 2.6)

        for (index, value) in visible.enumerated() {
            let normalized = CGFloat(min(max(value / 100, 0), 1))
            let height = max(1.5, maxBarHeight * normalized)
            decorations.append(NativeDecoration(
                kind: .systemMetricGraph,
                rect: NSRect(
                    x: startX + CGFloat(index) * stride,
                    y: trackRect.midY - height / 2,
                    width: barWidth,
                    height: height
                ),
                cornerRadius: min(1.5, barWidth / 2),
                color: accent,
                alpha: 0.82 * alpha,
                visualDepth: visualDepth
            ))
        }
    }

    private func computeGapTargets(
        _ anim: inout DragAnimation,
        layouts: [(x: Float, width: Float)],
        displayId: CGDirectDisplayID
    ) {
        let participants = dragParticipantIndices(layouts: layouts, sourceIndex: anim.sourceIndex, displayId: displayId)
        let participantSet = Set(participants)
        let nonSource = participants.filter { $0 != anim.sourceIndex }
        let insert = dragInsertionSlot(
            participants: participants,
            sourceIndex: anim.sourceIndex,
            insertionIndex: anim.insertionIndex
        )
        var sequence = nonSource.map { DragLayoutElement.item($0) }
        sequence.insert(.gap, at: insert)

        for index in layouts.indices where !participantSet.contains(index) {
            anim.springs[index].target = layouts[index].x
        }

        let items = panelItems[displayId] ?? []
        let config = panelConfigs[displayId] ?? Config()
        let systemIndicatorVisuals = systemIndicatorVisualsByDisplay[displayId] ?? [:]

        var x = dragSequenceOrigin(participants: participants, sourceIndex: anim.sourceIndex, layouts: layouts, displayId: displayId, fallback: anim.leftMargin)
        var previous: DragLayoutElement?
        for element in sequence {
            if let previous {
                x += spacingBetweenDragElements(
                    after: previous,
                    before: element,
                    sourceIndex: anim.sourceIndex,
                    items: items,
                    config: config,
                    systemIndicatorVisuals: systemIndicatorVisuals
                )
            }

            switch element {
            case .gap:
                x += anim.sourceWidth
            case .item(let index):
                anim.springs[index].target = x
                x += layouts[index].width
            }
            previous = element
        }
    }

    private func computeSettleTargets(
        _ anim: inout DragAnimation,
        layouts: [(x: Float, width: Float)],
        displayId: CGDirectDisplayID
    ) {
        let participants = dragParticipantIndices(layouts: layouts, sourceIndex: anim.sourceIndex, displayId: displayId)
        let participantSet = Set(participants)
        var finalOrder = participants.filter { $0 != anim.sourceIndex }
        let insert = dragInsertionSlot(
            participants: participants,
            sourceIndex: anim.sourceIndex,
            insertionIndex: anim.insertionIndex
        )
        finalOrder.insert(anim.sourceIndex, at: max(0, insert))

        for index in layouts.indices where !participantSet.contains(index) {
            anim.springs[index].target = layouts[index].x
        }

        let items = panelItems[displayId] ?? []
        let config = panelConfigs[displayId] ?? Config()
        let systemIndicatorVisuals = systemIndicatorVisualsByDisplay[displayId] ?? [:]

        var x = dragSequenceOrigin(participants: participants, sourceIndex: anim.sourceIndex, layouts: layouts, displayId: displayId, fallback: anim.leftMargin)
        for (offset, itemIdx) in finalOrder.enumerated() {
            if offset > 0 {
                x += spacingBetweenItems(
                    after: finalOrder[offset - 1],
                    before: itemIdx,
                    items: items,
                    config: config,
                    systemIndicatorVisuals: systemIndicatorVisuals
                )
            }
            anim.springs[itemIdx].target = x
            x += layouts[itemIdx].width
        }
    }

    private func dragSequenceOrigin(
        participants: [Int],
        sourceIndex: Int,
        layouts: [(x: Float, width: Float)],
        displayId: CGDirectDisplayID,
        fallback: Float
    ) -> Float {
        let indicatorIndices = cornerAffixedSystemIndicatorIndices(displayId: displayId)
        guard indicatorIndices.contains(sourceIndex),
              !participants.isEmpty else {
            return fallback
        }
        return participants.compactMap { layouts.indices.contains($0) ? layouts[$0].x : nil }.min() ?? fallback
    }

    private func dragParticipantIndices(
        layouts: [(x: Float, width: Float)],
        sourceIndex: Int,
        displayId: CGDirectDisplayID
    ) -> [Int] {
        let allIndices = Array(layouts.indices)
        let indicatorIndices = cornerAffixedSystemIndicatorIndices(displayId: displayId)
        guard !indicatorIndices.isEmpty else { return allIndices }

        if indicatorIndices.contains(sourceIndex) {
            return allIndices.filter { indicatorIndices.contains($0) }
        }
        return allIndices.filter { !indicatorIndices.contains($0) }
    }

    private func dragInsertionSlot(
        participants: [Int],
        sourceIndex: Int,
        insertionIndex: Int
    ) -> Int {
        guard let sourceSlot = participants.firstIndex(of: sourceIndex) else { return 0 }
        let slot = participants.filter { $0 < insertionIndex }.count
        let boundedSlot = min(max(slot, 0), participants.count)
        let adjusted = boundedSlot <= sourceSlot ? boundedSlot : boundedSlot - 1
        return min(max(adjusted, 0), max(0, participants.count - 1))
    }

    private func cornerAffixedSystemIndicatorIndices(displayId: CGDirectDisplayID) -> Set<Int> {
        guard let config = panelConfigs[displayId],
              config.taskbarPosition.isHorizontal,
              config.systemIndicatorPlacement == .leftCorner || config.systemIndicatorPlacement == .rightCorner else {
            return []
        }

        let items = panelItems[displayId] ?? []
        let systemIndicatorVisuals = systemIndicatorVisualsByDisplay[displayId] ?? [:]
        return Set(items.indices.filter { isSystemIndicatorItem(items[$0], visuals: systemIndicatorVisuals) })
    }

    private func spacingBetweenDragElements(
        after lhs: DragLayoutElement,
        before rhs: DragLayoutElement,
        sourceIndex: Int,
        items: [TaskbarItem],
        config: Config,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> Float {
        let leftIndex: Int
        let rightIndex: Int
        switch lhs {
        case .item(let index):
            leftIndex = index
        case .gap:
            leftIndex = sourceIndex
        }
        switch rhs {
        case .item(let index):
            rightIndex = index
        case .gap:
            rightIndex = sourceIndex
        }
        return spacingBetweenItems(
            after: leftIndex,
            before: rightIndex,
            items: items,
            config: config,
            systemIndicatorVisuals: systemIndicatorVisuals
        )
    }

    private func layoutLeftMargin(config: Config) -> Float {
        config.barStyle == .flush ? 0 : LayoutConstants.leftMargin
    }

    private func layoutRect(origin: Float, length: Float, crossLength: Float, position: Position) -> NSRect {
        if position.isVertical {
            return NSRect(x: 0, y: Double(origin), width: Double(crossLength), height: Double(length))
        }
        return NSRect(x: Double(origin), y: 0, width: Double(length), height: Double(crossLength))
    }

    private func computeItemLayouts(
        items: [TaskbarItem],
        config: Config,
        primaryLength: Float,
        displayId: CGDirectDisplayID? = nil,
        focus: FocusInfo = .none,
        systemIndicatorVisuals: [String: SystemIndicatorVisual] = [:]
    ) -> [(x: Float, width: Float)] {
        guard !items.isEmpty else { return [] }
        let iconSize = Float(config.iconSize)
        let iconsOnly = config.iconsOnly || config.taskbarPosition.isVertical
        let uniformSizing = config.itemSizing == .uniform
        let uniformWidth = computeUniformItemWidth(config: config, primaryLength: primaryLength, count: items.count)
        let systemIndicatorTileWidth = metricClusterTileWidth(
            items: items,
            config: config,
            systemIndicatorVisuals: systemIndicatorVisuals
        )
        let shouldCollapse: (TaskbarItem) -> Bool = { item in
            (item.isHidden && config.showHiddenApps && config.hiddenWindowMode == .collapsedRight)
                || (item.isMinimized && config.showMinimizedWindows && config.minimizedWindowMode == .collapsedRight)
        }
        let pIndex = items.firstIndex(where: shouldCollapse)
        if let displayId {
            if let pIndex { partitionIndex[displayId] = pIndex } else { partitionIndex.removeValue(forKey: displayId) }
        }
        let tabbedFocusedItemIndex: Int? = {
            guard config.tabbedTaskbarEnabled, !config.iconsOnly else { return nil }
            return focusedItemIndexForHighlight(items: items, focus: focus, config: config)
        }()

        var layouts: [(x: Float, width: Float)] = []
        var minimumWidths: [Float] = []
        var compressible: [Bool] = []
        var x = layoutLeftMargin(config: config)
        var sepX: Float?
        for (index, item) in items.enumerated() {
            if case .customSpacer(_, let width, _) = item {
                let w = Float(max(0, width))
                layouts.append((x, w))
                minimumWidths.append(w)
                compressible.append(false)
                x += w + spacingAfterItem(
                    at: index,
                    items: items,
                    config: config,
                    systemIndicatorVisuals: systemIndicatorVisuals
                )
                continue
            }
            if let pIndex, index == pIndex {
                sepX = x
                x += 8
            }

            let tabbedCollapse = shouldCollapseForTabbedTaskbar(
                item: item,
                index: index,
                focusedItemIndex: tabbedFocusedItemIndex,
                config: config
            )
            let alwaysIconOnly = shouldAlwaysUseIconOnlyLayout(item)
            let metricVisual = systemIndicatorVisual(for: item, visuals: systemIndicatorVisuals)
            let isSystemIndicator = isSystemIndicatorItem(item, visuals: systemIndicatorVisuals)
            let forceIconOnly = metricVisual == nil && pIndex != nil && index >= pIndex!
            let collapseForIconsOnly = iconsOnly && metricVisual == nil
            let title = item.displayTitle(iconsOnly: collapseForIconsOnly || forceIconOnly || tabbedCollapse || alwaysIconOnly)
            let width: Float
            if metricVisual != nil {
                width = systemIndicatorTileWidth
            } else if forceIconOnly || iconsOnly || tabbedCollapse || alwaysIconOnly {
                width = iconOnlyWidth(item: item, config: config, iconSize: iconSize)
            } else if uniformSizing {
                width = uniformWidth
            } else if case .customText(let id, let text, _) = item {
                let minimumWidth: Float = id.hasPrefix("system.") ? 92 : LayoutConstants.minItemWidth
                width = computeAutoWidthNoIcon(
                    config: config,
                    title: text,
                    fontSize: Float(config.fontSize),
                    minimumWidth: minimumWidth
                )
            } else {
                width = computeAutoWidth(config: config, title: title, iconSize: iconSize, fontSize: Float(config.fontSize))
            }
            layouts.append((x, width))
            let desiredMinimumWidth: Float = {
                if isSystemIndicator || alwaysIconOnly || forceIconOnly || collapseForIconsOnly || tabbedCollapse {
                    return width
                }
                if item.iconKey != nil {
                    return iconOnlyWidth(item: item, config: config, iconSize: iconSize)
                }
                return LayoutConstants.minItemWidth
            }()
            let minimumWidth = min(width, desiredMinimumWidth)
            minimumWidths.append(minimumWidth)
            compressible.append(width > minimumWidth + 0.5)
            x += width + spacingAfterItem(
                at: index,
                items: items,
                config: config,
                systemIndicatorVisuals: systemIndicatorVisuals
            )
        }

        let cornerAffixedIndicators = config.taskbarPosition.isHorizontal &&
            (config.systemIndicatorPlacement == .leftCorner || config.systemIndicatorPlacement == .rightCorner)

        let fitResult = fitHorizontalLayoutsToAvailableSpace(
            layouts: layouts,
            items: items,
            minimumWidths: minimumWidths,
            compressible: compressible,
            config: config,
            primaryLength: primaryLength,
            leftMargin: layoutLeftMargin(config: config),
            partitionIndex: pIndex,
            cornerAffixedIndicators: cornerAffixedIndicators,
            systemIndicatorVisuals: systemIndicatorVisuals
        )
        layouts = fitResult.layouts
        sepX = fitResult.separatorX

        if config.iconsOnly && config.taskbarPosition == .bottom && config.centerItems && !cornerAffixedIndicators && !layouts.isEmpty {
            let last = layouts[layouts.count - 1]
            let left = layoutLeftMargin(config: config)
            let totalWidth = last.x + last.width - left
            let offset = (primaryLength - totalWidth) / 2 - left
            for i in layouts.indices {
                layouts[i].x += offset
            }
            if let currentSepX = sepX {
                sepX = currentSepX + offset
            }
        }

        if cornerAffixedIndicators {
            layouts = applySystemIndicatorCornerAffixLayouts(
                layouts: layouts,
                items: items,
                config: config,
                primaryLength: primaryLength,
                leftMargin: layoutLeftMargin(config: config),
                systemIndicatorVisuals: systemIndicatorVisuals
            )
        }

        if let displayId {
            if let sepX { separatorX[displayId] = sepX } else { separatorX.removeValue(forKey: displayId) }
        }

        return layouts
    }

    private func systemIndicatorVisual(
        for item: TaskbarItem,
        visuals: [String: SystemIndicatorVisual]
    ) -> SystemIndicatorVisual? {
        guard case .customText(let id, _, _) = item else { return nil }
        return visuals[id]
    }

    private func isSystemIndicatorItem(
        _ item: TaskbarItem,
        visuals: [String: SystemIndicatorVisual]
    ) -> Bool {
        if systemIndicatorVisual(for: item, visuals: visuals) != nil {
            return true
        }
        guard case .customText(let id, _, _) = item else { return false }
        return id.hasPrefix("system.")
    }

    private func usesTightDenseSystemIndicatorSpacing(config: Config) -> Bool {
        guard config.taskbarPosition.isHorizontal,
              config.systemIndicatorChipPreset == .dense else {
            return false
        }
        return config.systemIndicatorAppearance == .flat ||
            config.systemIndicatorAppearance == .underline ||
            config.systemIndicatorAppearance == .minimal
    }

    private func usesCondensedDenseSystemIndicatorTiles(config: Config) -> Bool {
        guard config.taskbarPosition.isHorizontal,
              config.systemIndicatorChipPreset == .dense else {
            return false
        }
        return config.systemIndicatorAppearance == .underline ||
            config.systemIndicatorAppearance == .minimal
    }

    private func systemIndicatorAdjacentSpacing(config: Config) -> Float {
        guard usesTightDenseSystemIndicatorSpacing(config: config) else {
            return LayoutConstants.itemSpacing
        }
        return config.systemIndicatorAppearance == .flat ? 2 : 1
    }

    private func spacingBetweenItems(
        after lhs: Int,
        before rhs: Int,
        items: [TaskbarItem],
        config: Config,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> Float {
        guard usesTightDenseSystemIndicatorSpacing(config: config),
              items.indices.contains(lhs),
              items.indices.contains(rhs),
              isSystemIndicatorItem(items[lhs], visuals: systemIndicatorVisuals),
              isSystemIndicatorItem(items[rhs], visuals: systemIndicatorVisuals) else {
            return LayoutConstants.itemSpacing
        }
        return systemIndicatorAdjacentSpacing(config: config)
    }

    private func spacingAfterItem(
        at index: Int,
        items: [TaskbarItem],
        config: Config,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> Float {
        guard index + 1 < items.count else { return LayoutConstants.itemSpacing }
        return spacingBetweenItems(
            after: index,
            before: index + 1,
            items: items,
            config: config,
            systemIndicatorVisuals: systemIndicatorVisuals
        )
    }

    private func applySystemIndicatorCornerAffixLayouts(
        layouts: [(x: Float, width: Float)],
        items: [TaskbarItem],
        config: Config,
        primaryLength: Float,
        leftMargin: Float,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> [(x: Float, width: Float)] {
        guard config.taskbarPosition.isHorizontal else { return layouts }
        guard config.systemIndicatorPlacement == .leftCorner || config.systemIndicatorPlacement == .rightCorner else {
            return layouts
        }

        let indicatorIndices = items.indices.filter { index in
            isSystemIndicatorItem(items[index], visuals: systemIndicatorVisuals)
        }
        guard !indicatorIndices.isEmpty else { return layouts }

        let spacing = systemIndicatorAdjacentSpacing(config: config)
        let clusterWidth = indicatorIndices.enumerated().reduce(Float(0)) { partial, element in
            let (offset, index) = element
            return partial + (offset == 0 ? 0 : spacing) + layouts[index].width
        }

        let targetStart: Float = {
            switch config.systemIndicatorPlacement {
            case .leftCorner:
                return leftMargin
            case .rightCorner:
                return max(leftMargin, primaryLength - leftMargin - clusterWidth)
            default:
                return leftMargin
            }
        }()

        var output = layouts
        var cursor = targetStart
        for index in indicatorIndices {
            output[index].x = cursor
            cursor += output[index].width + spacing
        }
        return output
    }

    private func fitHorizontalLayoutsToAvailableSpace(
        layouts: [(x: Float, width: Float)],
        items: [TaskbarItem],
        minimumWidths: [Float],
        compressible: [Bool],
        config: Config,
        primaryLength: Float,
        leftMargin: Float,
        partitionIndex: Int?,
        cornerAffixedIndicators: Bool,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> (layouts: [(x: Float, width: Float)], separatorX: Float?) {
        guard config.taskbarPosition.isHorizontal,
              layouts.count == items.count,
              minimumWidths.count == layouts.count,
              compressible.count == layouts.count else {
            return (layouts, nil)
        }

        let spacing = LayoutConstants.itemSpacing
        let indicatorIndices: [Int] = cornerAffixedIndicators
            ? items.indices.filter { isSystemIndicatorItem(items[$0], visuals: systemIndicatorVisuals) }
            : []
        let indicatorIndexSet = Set(indicatorIndices)
        let regularIndices = items.indices.filter { !indicatorIndexSet.contains($0) }

        let indicatorSpacing = systemIndicatorAdjacentSpacing(config: config)
        let clusterWidth = indicatorIndices.enumerated().reduce(Float(0)) { partial, element in
            let (offset, index) = element
            return partial + (offset == 0 ? 0 : indicatorSpacing) + layouts[index].width
        }
        let reservedGap = indicatorIndices.isEmpty || regularIndices.isEmpty ? Float(0) : spacing
        let contentStart: Float
        let contentEnd: Float
        switch config.systemIndicatorPlacement {
        case .leftCorner where cornerAffixedIndicators:
            contentStart = leftMargin + clusterWidth + reservedGap
            contentEnd = primaryLength - leftMargin
        case .rightCorner where cornerAffixedIndicators:
            contentStart = leftMargin
            contentEnd = primaryLength - leftMargin - clusterWidth - reservedGap
        default:
            contentStart = leftMargin
            contentEnd = primaryLength - leftMargin
        }

        var output = layouts
        var widths = layouts.map(\.width)
        let targetIndices = cornerAffixedIndicators ? regularIndices : Array(items.indices)
        let available = max(0, contentEnd - contentStart)
        let partitionGap: Float = {
            guard let partitionIndex, targetIndices.contains(partitionIndex) else { return 0 }
            return 8
        }()
        let currentRequired = targetIndices.enumerated().reduce(partitionGap) { partial, element in
            let (offset, index) = element
            let itemSpacing = offset == 0
                ? Float(0)
                : spacingBetweenItems(
                    after: targetIndices[offset - 1],
                    before: index,
                    items: items,
                    config: config,
                    systemIndicatorVisuals: systemIndicatorVisuals
                )
            return partial + itemSpacing + widths[index]
        }

        if currentRequired > available {
            shrinkWidthsToFit(
                widths: &widths,
                indices: targetIndices,
                minimumWidths: minimumWidths,
                compressible: compressible,
                excess: currentRequired - available
            )
        }

        var cursor = contentStart
        var separator: Float?
        for (offset, index) in targetIndices.enumerated() {
            if offset > 0 {
                cursor += spacingBetweenItems(
                    after: targetIndices[offset - 1],
                    before: index,
                    items: items,
                    config: config,
                    systemIndicatorVisuals: systemIndicatorVisuals
                )
            }
            if let partitionIndex, index == partitionIndex {
                separator = cursor
                cursor += 8
            }
            output[index].x = cursor
            output[index].width = widths[index]
            cursor += widths[index]
        }

        return (output, separator)
    }

    private func shrinkWidthsToFit(
        widths: inout [Float],
        indices: [Int],
        minimumWidths: [Float],
        compressible: [Bool],
        excess: Float
    ) {
        var remaining = excess
        var candidates = indices.filter { index in
            compressible[index] && widths[index] > minimumWidths[index] + 0.5
        }

        while remaining > 0.5, !candidates.isEmpty {
            let share = remaining / Float(candidates.count)
            var nextCandidates: [Int] = []
            var consumed: Float = 0

            for index in candidates {
                let capacity = max(0, widths[index] - minimumWidths[index])
                let reduction = min(capacity, share)
                widths[index] -= reduction
                consumed += reduction
                if widths[index] > minimumWidths[index] + 0.5 {
                    nextCandidates.append(index)
                }
            }

            if consumed <= 0.001 {
                break
            }
            remaining -= consumed
            candidates = nextCandidates
        }
    }

    private func shouldCollapseTitleForOverflow(
        item: TaskbarItem,
        rect: NSRect,
        config: Config,
        position: Position,
        iconSize: Float,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> Bool {
        guard position.isHorizontal else { return false }
        guard !isSystemIndicatorItem(item, visuals: systemIndicatorVisuals) else { return false }
        guard item.iconKey != nil else { return false }
        let iconOnly = iconOnlyWidth(item: item, config: config, iconSize: iconSize)
        return Float(rect.width) <= iconOnly + 0.5
    }

    private func shouldAlwaysUseIconOnlyLayout(_ item: TaskbarItem) -> Bool {
        if case .launcher = item { return true }
        return false
    }

    private func iconOnlyWidth(item: TaskbarItem, config: Config, iconSize: Float) -> Float {
        let base = max(LayoutConstants.minItemWidth, iconSize + 20)
        guard config.groupByApp,
              case .appGroup(_, _, let windowCount, _, _, _, _) = item,
              windowCount > 1 else {
            return base
        }
        let plates = min(windowCount, StackTokens.maxVisiblePlates)
        let breathing = config.appGroupStackGeometry == .strong ? StackTokens.stackBreathingWidthStrong : StackTokens.stackBreathingWidthSubtle
        let offset = config.appGroupStackGeometry == .strong ? StackTokens.plateOffsetXStrong : StackTokens.plateOffsetXSubtle
        let layoutOffset = config.appGroupStackHoverSpreadEnabled ? offset * StackTokens.hoverSpreadMultiplier : offset
        let stackWidth = base + breathing + Float(plates - 1) * layoutOffset
        let clusterWidth = appGroupIconOnlyClusterWidth(windowCount: windowCount, config: config, iconSize: iconSize, isHovered: config.appGroupStackHoverSpreadEnabled)
        let requiredWidth = clusterWidth + LayoutConstants.groupCompoundHorizontalPadding * 2
        return max(requiredWidth, min(stackWidth, Float(config.maxItemWidth)))
    }

    private func iconRectForItem(
        rect: NSRect,
        item: TaskbarItem,
        title: String,
        iconSize: Float,
        config: Config,
        position: Position,
        sidebarExpanded: Bool,
        isHovered: Bool
    ) -> NSRect {
        let size = CGFloat(iconSize)
        let x: CGFloat
        let y: CGFloat
        if position.isVertical {
            x = sidebarExpanded && !title.isEmpty
                ? rect.minX + CGFloat(LayoutConstants.iconLeftMargin)
                : rect.minX + (rect.width - size) / 2
            y = rect.minY + (rect.height - size) / 2
        } else {
            if title.isEmpty,
               config.groupByApp,
               config.appGroupCountBadgeInIconsOnly,
               case .appGroup(_, _, let windowCount, _, _, _, _) = item,
               windowCount > 1 {
                let clusterWidth = CGFloat(appGroupIconOnlyClusterWidth(
                    windowCount: windowCount,
                    config: config,
                    iconSize: iconSize,
                    isHovered: isHovered
                ))
                let left = max(
                    CGFloat(LayoutConstants.groupCompoundHorizontalPadding),
                    (rect.width - clusterWidth) / 2
                )
                x = rect.minX + left
            } else {
                x = title.isEmpty ? rect.minX + (rect.width - size) / 2 : rect.minX + CGFloat(LayoutConstants.iconLeftMargin)
            }
            y = rect.minY + (rect.height - size) / 2
        }
        return NSRect(x: x, y: y, width: size, height: size)
    }

    private func appGroupIconOnlyClusterWidth(
        windowCount: Int,
        config: Config,
        iconSize: Float,
        isHovered: Bool
    ) -> Float {
        guard windowCount > 1 else { return iconSize }
        var width = iconSize + appGroupStackExtension(windowCount: windowCount, config: config, isHovered: isHovered)
        guard config.appGroupCountBadgeInIconsOnly else { return width }
        let metrics = appGroupBadgeMetrics(
            windowCount: windowCount,
            titleIsEmpty: true,
            style: config.appGroupCountBadgeStyle,
            alpha: 1
        )
        width += LayoutConstants.groupBadgeIconGap + Float(metrics.width)
        return width
    }

    private func appGroupStackExtension(
        windowCount: Int,
        config: Config,
        isHovered: Bool
    ) -> Float {
        let plateCount = min(windowCount, StackTokens.maxVisiblePlates)
        guard plateCount > 1 else { return 0 }
        let baseOffset = config.appGroupStackGeometry == .strong ? StackTokens.plateOffsetXStrong : StackTokens.plateOffsetXSubtle
        let spreadOffset = config.appGroupStackHoverSpreadEnabled && isHovered
            ? baseOffset * StackTokens.hoverSpreadMultiplier
            : baseOffset
        let deepestPlateIndex = Float(plateCount - 1)
        let inset = deepestPlateIndex * 0.7
        return max(0, deepestPlateIndex * spreadOffset - inset)
    }

    private func appGroupBadgeMetrics(
        windowCount: Int,
        titleIsEmpty: Bool,
        style: AppGroupCountBadgeStyle,
        alpha: Float
    ) -> (text: String, textWidth: CGFloat, width: CGFloat, height: CGFloat, alpha: Float, cornerRadius: CGFloat) {
        let badgeText = "\(windowCount)"
        let textWidth = CGFloat(max(8, Float(badgeText.count) * 7))
        switch style {
        case .minimal, .compactDot:
            let height: CGFloat = titleIsEmpty ? 12 : 14
            return (badgeText, textWidth, max(14, textWidth + 8), height, 0.22 * alpha, min(6, height / 2))
        case .pill:
            let height: CGFloat = titleIsEmpty ? 15 : 16
            return (badgeText, textWidth, max(20, textWidth + 14), height, 0.30 * alpha, height / 2)
        case .separator:
            let height: CGFloat = titleIsEmpty ? 13 : 14
            return (badgeText, textWidth, max(12, textWidth + 6), height, 0.0, min(6, height / 2))
        }
    }

    private func titleRectForItem(
        rect: NSRect,
        item: TaskbarItem,
        iconRect: NSRect,
        title: String,
        position: Position,
        config: Config,
        systemIndicatorVisual: SystemIndicatorVisual?
    ) -> NSRect {
        guard !title.isEmpty else { return .zero }
        if item.iconKey == nil {
            let insets = systemIndicatorVisual == nil
                ? (left: CGFloat(LayoutConstants.iconLeftMargin), right: CGFloat(LayoutConstants.textRightPadding))
                : systemIndicatorTitleInsets(config: config)
            let leftInset = insets.left
            let rightInset = insets.right
            let x = rect.minX + leftInset
            let width = max(0, rect.maxX - x - rightInset)
            return NSRect(x: x, y: rect.minY, width: width, height: rect.height)
        }
        let x: CGFloat = iconRect.maxX + CGFloat(LayoutConstants.iconGap)
        let width = max(0, rect.maxX - x - CGFloat(LayoutConstants.textRightPadding))
        return NSRect(x: x, y: rect.minY, width: width, height: rect.height)
    }

    private func computeUniformItemWidth(config: Config, primaryLength: Float, count: Int) -> Float {
        guard count > 0 else { return Float(config.maxItemWidth) }
        let left = layoutLeftMargin(config: config)
        let totalSpacing = left * 2 + LayoutConstants.itemSpacing * Float(count - 1)
        let perItem = (primaryLength - totalSpacing) / Float(count)
        return min(max(perItem, LayoutConstants.minItemWidth), Float(config.maxItemWidth))
    }

    private func computeAutoWidth(config: Config, title: String, iconSize: Float, fontSize: Float) -> Float {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize), weight: .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let textWidth = min(Float(textSize.width), Float(config.maxTitleWidth))
        let width = LayoutConstants.iconLeftMargin + iconSize + LayoutConstants.iconGap + textWidth + LayoutConstants.textRightPadding
        return min(max(width, LayoutConstants.minItemWidth), Float(config.maxItemWidth))
    }

    private func computeAutoWidthNoIcon(
        config: Config,
        title: String,
        fontSize: Float,
        minimumWidth: Float = LayoutConstants.minItemWidth
    ) -> Float {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize), weight: .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let textWidth = min(Float(textSize.width), Float(config.maxTitleWidth))
        let width = LayoutConstants.iconLeftMargin + textWidth + LayoutConstants.textRightPadding
        return min(max(width, minimumWidth), max(Float(config.maxItemWidth), minimumWidth))
    }

    private struct MetricChipLayout {
        let tileWidth: Float
        let shellInsetX: Float
        let shellInsetY: Float
        let trackHeight: Float
        let trackInsetX: Float
        let trackBottomInset: Float
        let graphBarWidth: Float
        let graphBarGap: Float
    }

    private func metricChipLayout(for preset: SystemIndicatorChipPreset) -> MetricChipLayout {
        switch preset {
        case .full:
            return MetricChipLayout(
                tileWidth: 112,
                shellInsetX: 0,
                shellInsetY: 4,
                trackHeight: 3.5,
                trackInsetX: 12,
                trackBottomInset: 5,
                graphBarWidth: 2.5,
                graphBarGap: 2
            )
        case .compact:
            return MetricChipLayout(
                tileWidth: 92,
                shellInsetX: 0,
                shellInsetY: 4,
                trackHeight: 3.5,
                trackInsetX: 12,
                trackBottomInset: 5,
                graphBarWidth: 2.5,
                graphBarGap: 2
            )
        case .dense:
            return MetricChipLayout(
                tileWidth: 56,
                shellInsetX: 1,
                shellInsetY: 5,
                trackHeight: 2,
                trackInsetX: 7,
                trackBottomInset: 4,
                graphBarWidth: 1.6,
                graphBarGap: 1.2
            )
        case .micro:
            return MetricChipLayout(
                tileWidth: 20,
                shellInsetX: 3,
                shellInsetY: 6,
                trackHeight: 2,
                trackInsetX: 4,
                trackBottomInset: 4,
                graphBarWidth: 2,
                graphBarGap: 1
            )
        }
    }

    private func systemIndicatorTitleInsets(config: Config) -> (left: CGFloat, right: CGFloat) {
        if usesCondensedDenseSystemIndicatorTiles(config: config) {
            return (2, 2)
        }
        if config.systemIndicatorChipPreset == .compact {
            return (6, 6)
        }
        return (CGFloat(LayoutConstants.iconLeftMargin), CGFloat(LayoutConstants.textRightPadding))
    }

    private func systemIndicatorTextFitSlack(config: Config) -> Float {
        config.systemIndicatorChipPreset == .micro ? 0 : 4
    }

    private func metricClusterTileWidth(
        items: [TaskbarItem],
        config: Config,
        systemIndicatorVisuals: [String: SystemIndicatorVisual]
    ) -> Float {
        let layout = metricChipLayout(for: config.systemIndicatorChipPreset)
        let fallback = min(Float(config.maxItemWidth), layout.tileWidth)
        guard config.taskbarPosition.isHorizontal,
              config.systemIndicatorChipPreset != .micro else {
            return fallback
        }

        let font = NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
        let textWidth = items.compactMap { item -> Float? in
            guard systemIndicatorVisual(for: item, visuals: systemIndicatorVisuals) != nil else {
                return nil
            }
            let title = item.displayTitle(iconsOnly: false)
            guard !title.isEmpty else { return nil }
            let size = (title as NSString).size(withAttributes: [.font: font])
            return min(Float(size.width), Float(config.maxTitleWidth))
        }.max() ?? 0

        guard textWidth > 0 else { return fallback }

        let insets = systemIndicatorTitleInsets(config: config)
        let contentWidth = ceil(textWidth + Float(insets.left + insets.right) + systemIndicatorTextFitSlack(config: config))
        let minimumWidth: Float = {
            if usesCondensedDenseSystemIndicatorTiles(config: config) {
                return 20
            }
            if config.systemIndicatorChipPreset == .dense {
                return 32
            }
            return LayoutConstants.minItemWidth
        }()
        return min(Float(config.maxItemWidth), max(minimumWidth, contentWidth))
    }

    private func effectiveDisplayIconsOnly(config: Config, position: Position, sidebarExpanded: Bool) -> Bool {
        if config.iconsOnly { return true }
        guard position.isVertical else { return false }
        guard config.sidebarModeEnabled else { return true }
        return !sidebarExpanded
    }

    private func snapRectToBackingPixels(_ rect: NSRect, displayId: CGDirectDisplayID) -> NSRect {
        guard let state = panelStates[displayId] else { return rect }
        let scale = max(state.scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { CGFloat(round(Float(value) * scale) / scale) }
        let x0 = snap(rect.minX)
        let x1 = snap(rect.maxX)
        let y0 = snap(rect.minY)
        let y1 = snap(rect.maxY)
        return NSRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func focusIndicatorRect(base: NSRect, config: Config, position: Position) -> NSRect {
        switch config.focusIndicatorStyle {
        case .tile:
            return base
        case .dot:
            if position.isVertical {
                let w: CGFloat = 3
                let h = min(16, max(8, CGFloat(config.iconSize) * 0.55))
                let x = position.isLeft ? base.maxX - w - 4 : base.minX + 4
                return NSRect(x: x, y: base.minY + (base.height - h) / 2, width: w, height: h)
            }
            let h: CGFloat = 3
            let w = min(16, max(8, CGFloat(config.iconSize) * 0.55))
            return NSRect(x: base.minX + (base.width - w) / 2, y: base.maxY - h - 4, width: w, height: h)
        }
    }

    private func setFocusRect(_ rect: NSRect?, for displayId: CGDirectDisplayID) {
        if let rect {
            focusRects[displayId] = snapRectToBackingPixels(rect, displayId: displayId)
        } else {
            focusRects.removeValue(forKey: displayId)
        }
    }

    private func focusedItemIndexForHighlight(items: [TaskbarItem], focus: FocusInfo, config: Config) -> Int? {
        if let gid = focus.tabGroupId, !gid.isEmpty,
           let idx = items.firstIndex(where: {
               if case .tabGroup(let id, _, _, _, _, _, _, _) = $0 { return id == gid }
               return false
           }) {
            return idx
        }
        if let wid = focus.windowId, wid != 0 {
            if let idx = items.firstIndex(where: {
                if case .window(let id, _, _, _, _, _, _) = $0 { return id.raw == wid }
                return false
            }) { return idx }
            if let idx = items.firstIndex(where: {
                if case .appGroup(_, _, _, let windows, _, _, _) = $0 {
                    return windows.contains(where: { $0.raw == wid })
                }
                return false
            }) { return idx }
        }
        if let bid = focus.bundleId, !bid.isEmpty {
            let matches = items.enumerated().compactMap { index, item -> Int? in
                switch item {
                case .window(_, let bundleId, _, _, _, _, _), .appGroup(let bundleId, _, _, _, _, _, _):
                    return bundleId == bid ? index : nil
                case .tabGroup(_, let representativeBundleId, _, _, _, _, _, _):
                    return representativeBundleId == bid ? index : nil
                default:
                    return nil
                }
            }
            if matches.count == 1 { return matches[0] }
        }
        return nil
    }

    private func shouldCollapseForTabbedTaskbar(
        item: TaskbarItem,
        index: Int,
        focusedItemIndex: Int?,
        config: Config
    ) -> Bool {
        guard config.tabbedTaskbarEnabled, !config.iconsOnly else { return false }
        guard let focusedItemIndex else { return false }
        switch item {
        case .window, .appGroup, .tabGroup:
            return index != focusedItemIndex
        default:
            return false
        }
    }

    private static func identity(for item: TaskbarItem, index: Int) -> String {
        switch item {
        case .window(let id, _, _, _, _, _, _): return "window-\(id.raw)"
        case .appGroup(let bundleId, _, _, _, _, _, let screenId): return "group-\(bundleId)-\(screenId)"
        case .pinnedApp(let bundleId, let screenId): return "pin-\(bundleId)-\(screenId)"
        case .launcher(let screenId): return "launcher-\(screenId)"
        case .pluginTile(let id, _, _, _, _, _): return "plugin-\(id)"
        case .tabGroup(let id, _, _, _, _, _, _, _): return "tab-\(id)"
        case .customSpacer(let id, _, _): return "spacer-\(id)"
        case .customText(let id, _, _): return "text-\(id)"
        case .customLink(let id, _, _, _, _): return "link-\(id)"
        case .customFolder(let id, _, _, _, _): return "folder-\(id)"
        }
    }

    private static func taskbarItemSignature(for items: [TaskbarItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            switch item {
            case .window(let id, let bundleId, let title, let appName, let isHidden, let isMinimized, let screenId):
                hasher.combine(0)
                hasher.combine(id.raw)
                hasher.combine(bundleId)
                hasher.combine(title)
                hasher.combine(appName)
                hasher.combine(isHidden)
                hasher.combine(isMinimized)
                hasher.combine(screenId)
            case .appGroup(let bundleId, let appName, let windowCount, let windows, let isHidden, let isMinimized, let screenId):
                hasher.combine(1)
                hasher.combine(bundleId)
                hasher.combine(appName)
                hasher.combine(windowCount)
                for window in windows { hasher.combine(window.raw) }
                hasher.combine(isHidden)
                hasher.combine(isMinimized)
                hasher.combine(screenId)
            case .pinnedApp(let bundleId, let screenId):
                hasher.combine(2)
                hasher.combine(bundleId)
                hasher.combine(screenId)
            case .launcher(let screenId):
                hasher.combine(3)
                hasher.combine(screenId)
            case .pluginTile(let id, let providerId, let title, let icon, let visualState, let screenId):
                hasher.combine(4)
                hasher.combine(id)
                hasher.combine(providerId)
                hasher.combine(title)
                hasher.combine(icon)
                hasher.combine(visualState.rawValue)
                hasher.combine(screenId)
            case .tabGroup(let id, let representativeBundleId, let name, let emoji, let windowCount, let isHidden, let isMinimized, let screenId):
                hasher.combine(5)
                hasher.combine(id)
                hasher.combine(representativeBundleId)
                hasher.combine(name)
                hasher.combine(emoji)
                hasher.combine(windowCount)
                hasher.combine(isHidden)
                hasher.combine(isMinimized)
                hasher.combine(screenId)
            case .customSpacer(let id, let width, let screenId):
                hasher.combine(6)
                hasher.combine(id)
                hasher.combine(width)
                hasher.combine(screenId)
            case .customText(let id, let text, let screenId):
                hasher.combine(7)
                hasher.combine(id)
                hasher.combine(text)
                hasher.combine(screenId)
            case .customLink(let id, let title, let url, let icon, let screenId):
                hasher.combine(8)
                hasher.combine(id)
                hasher.combine(title)
                hasher.combine(url)
                hasher.combine(icon)
                hasher.combine(screenId)
            case .customFolder(let id, let title, let path, let icon, let screenId):
                hasher.combine(9)
                hasher.combine(id)
                hasher.combine(title)
                hasher.combine(path)
                hasher.combine(icon)
                hasher.combine(screenId)
            }
        }
        return hasher.finalize()
    }

    private static func itemBackgroundColorSignature(for colors: [Int: String]) -> Int {
        var hasher = Hasher()
        hasher.combine(colors.count)
        for (index, color) in colors.sorted(by: { $0.key < $1.key }) {
            hasher.combine(index)
            hasher.combine(color)
        }
        return hasher.finalize()
    }

    private static func systemIndicatorVisualSignature(for visuals: [String: SystemIndicatorVisual]) -> Int {
        var hasher = Hasher()
        hasher.combine(visuals.count)
        for (id, visual) in visuals.sorted(by: { $0.key < $1.key }) {
            hasher.combine(id)
            hasher.combine(visual.metric.rawValue)
            hasher.combine(visual.mode.rawValue)
            hasher.combine(visual.label)
            hasher.combine(visual.valueText)
            hasher.combine(visual.valuePercent)
            hasher.combine(visual.history.count)
            for value in visual.history {
                hasher.combine(value)
            }
            hasher.combine(visual.severity)
        }
        return hasher.finalize()
    }
}
