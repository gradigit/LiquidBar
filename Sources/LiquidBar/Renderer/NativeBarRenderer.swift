// NativeBarRenderer.swift - retained AppKit/Core Animation taskbar renderer

import AppKit
import QuartzCore

extension Config {
    var taskbarSurfaceRenderKey: Config {
        var key = self
        key.adjustWindowsForTaskbar = true
        key.performanceLoggingEnabled = false
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
    }

    var kind: Kind
    var rect: NSRect
    var cornerRadius: CGFloat
    var color: NSColor
    var alpha: Float
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
    static let pinIndicatorWidth: Float = 16
    static let pinIndicatorHeight: Float = 2.5
    static let dragThreshold: Float = 6
}

private enum StackTokens {
    static let maxPlates = 30
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
        sidebarExpanded: Bool = false
    ) -> StaticUpdateResult {
        guard var state = panelStates[displayId] else { return .rebuiltStaticState }

        panelItems[displayId] = items
        panelConfigs[displayId] = config
        panelIconCaches[displayId] = iconCache
        animationTuningByDisplay[displayId] = config.animationProfile.rendererTuning
        hoveredItemIndexByDisplay[displayId] = hoveredItemIndexByDisplay[displayId] ?? -1

        let key = StaticUpdateKey(
            itemSignature: Self.taskbarItemSignature(for: items),
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
            focus: focus
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

    func setHoveredItemIndex(_ index: Int?, for displayId: CGDirectDisplayID) {
        hoveredItemIndexByDisplay[displayId] = index ?? -1
        rebuildSnapshot(displayId: displayId)
    }

    func setCursorPosition(_ point: SIMD2<Float>?, for displayId: CGDirectDisplayID) {
        if let point {
            cursorPositions[displayId] = point
        } else {
            cursorPositions.removeValue(forKey: displayId)
        }
        rebuildSnapshot(displayId: displayId)
    }

    func setHoverRect(_ rect: NSRect?, for displayId: CGDirectDisplayID) {
        if let rect {
            hoverRects[displayId] = snapRectToBackingPixels(rect, displayId: displayId)
        } else {
            hoverRects.removeValue(forKey: displayId)
        }
        rebuildSnapshot(displayId: displayId)
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
        computeGapTargets(&anim, layouts: layouts)
        dragAnimations[displayId] = anim
        hoverRects.removeValue(forKey: displayId)
        rebuildSnapshot(displayId: displayId)
    }

    func updateDragCursor(cursorX: Float, insertionIndex: Int, displayId: CGDirectDisplayID) {
        guard var anim = dragAnimations[displayId] else { return }
        anim.cursorX = cursorX
        anim.insertionIndex = partitionIndex[displayId].map { min(insertionIndex, $0) } ?? insertionIndex
        if let layouts = itemLayouts[displayId] {
            computeGapTargets(&anim, layouts: layouts)
        }
        dragAnimations[displayId] = anim
        rebuildSnapshot(displayId: displayId)
    }

    func endDrag(displayId: CGDirectDisplayID) {
        guard var anim = dragAnimations[displayId] else { return }
        anim.isSettling = true
        if let layouts = itemLayouts[displayId] {
            computeSettleTargets(&anim, layouts: layouts)
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

        var presentations: [NativeBarItemPresentation] = []
        var textItems: [NativeTextOverlayItem] = []
        var decorations: [NativeDecoration] = []
        presentations.reserveCapacity(items.count)

        if let hover = hoverRects[displayId] {
            decorations.append(NativeDecoration(kind: .hover, rect: hover, cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius), color: .white, alpha: 0.18))
        }
        if let focus = focusRects[displayId] {
            decorations.append(NativeDecoration(kind: .focus, rect: focus, cornerRadius: CGFloat(LayoutConstants.focusCornerRadius), color: NSColor(calibratedRed: 0.45, green: 0.68, blue: 1.0, alpha: 1), alpha: 0.32))
        }

        for (index, item) in items.enumerated() {
            guard index < layouts.count, index < rects.count else { continue }
            let rect = rects[index]
            let title = item.displayTitle(iconsOnly: displayIconsOnly || (partitionIndex[displayId] != nil && index >= partitionIndex[displayId]!))
            let alpha: Float = item.isDimmed ? 0.5 : 1.0
            let icon: NSImage? = item.iconKey.flatMap { iconCache.getIcon(bundleId: $0) }
            let iconRect = iconRectForItem(rect: rect, title: title, iconSize: iconSize, position: position, sidebarExpanded: sidebarExpanded)
            let titleRect = titleRectForItem(rect: rect, iconRect: iconRect, title: title, position: position)

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
                backgroundColor: nil
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

            appendDecorations(for: item, rect: rect, title: title, iconRect: iconRect, config: config, alpha: alpha, into: &decorations)
        }

        if let sepX = separatorX[displayId] {
            if position.isVertical {
                decorations.append(NativeDecoration(
                    kind: .separator,
                    rect: NSRect(x: Double(crossLength * 0.15), y: Double(sepX + 3), width: Double(crossLength * 0.7), height: 1.5),
                    cornerRadius: 0.75,
                    color: .white,
                    alpha: 0.15
                ))
            } else {
                decorations.append(NativeDecoration(
                    kind: .separator,
                    rect: NSRect(x: Double(sepX + 3), y: Double(crossLength * 0.15), width: 1.5, height: Double(crossLength * 0.7)),
                    cornerRadius: 0.75,
                    color: .white,
                    alpha: 0.15
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

        for index in presentations.indices where index != anim.sourceIndex {
            let dx = CGFloat(anim.springs[index].current - layouts[index].x)
            presentations[index].rect.origin.x += dx
            presentations[index].iconRect.origin.x += dx
            presentations[index].titleRect.origin.x += dx
            presentations[index].alpha *= 0.72
        }

        let sourceX = CGFloat(anim.isSettling ? anim.springs[anim.sourceIndex].current : anim.cursorX - anim.cursorOffsetInItem)
        let sourceDx = sourceX - presentations[anim.sourceIndex].rect.minX
        presentations[anim.sourceIndex].rect.origin.x += sourceDx
        presentations[anim.sourceIndex].iconRect.origin.x += sourceDx
        presentations[anim.sourceIndex].titleRect.origin.x += sourceDx

        decorations.append(NativeDecoration(
            kind: .hover,
            rect: presentations[anim.sourceIndex].rect.insetBy(dx: 1, dy: 1),
            cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius),
            color: .white,
            alpha: 0.16
        ))

        if anim.shadowAlpha > 0.005 {
            var shadow = presentations[anim.sourceIndex].rect.insetBy(dx: -1.5, dy: -1)
            shadow.origin.y += 1
            decorations.append(NativeDecoration(kind: .dragShadow, rect: shadow, cornerRadius: CGFloat(LayoutConstants.hoverCornerRadius + 1), color: .black, alpha: anim.shadowAlpha * 0.55))
        }

        dragDecorationCount[displayId] = decorations.count
        dragIconCount[displayId] = presentations.count
        dragTextCount[displayId] = nativeTextOverlayItemsByDisplay[displayId]?.count ?? 0
    }

    private func appendDecorations(
        for item: TaskbarItem,
        rect: NSRect,
        title: String,
        iconRect: NSRect,
        config: Config,
        alpha: Float,
        into decorations: inout [NativeDecoration]
    ) {
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
            decorations.append(NativeDecoration(kind: .pin, rect: pinRect, cornerRadius: min(pinRect.width, pinRect.height) / 2, color: NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1), alpha: 0.8))
        }

        if !config.taskbarPosition.isVertical,
           config.appGroupCountBadgeInIconsOnly,
           case .appGroup(_, _, let windowCount, _, _, _, _) = item,
           windowCount > 1 {
            let badgeText = "\(windowCount)"
            let width = CGFloat(max(12, Float(badgeText.count) * 7 + 8))
            let height: CGFloat = title.isEmpty ? 12 : 14
            let x = min(iconRect.maxX + CGFloat(LayoutConstants.groupBadgeIconGap), rect.maxX - width - CGFloat(LayoutConstants.groupBadgeRightInset))
            let badgeRect = NSRect(x: x, y: rect.minY + (rect.height - height) / 2, width: width, height: height)
            decorations.append(NativeDecoration(kind: .badge, rect: badgeRect, cornerRadius: min(6, height / 2), color: .white, alpha: 0.22 * alpha))
        }

        if case .pluginTile(_, _, _, _, let visualState, _) = item {
            switch visualState {
            case .idle:
                break
            case .active:
                decorations.append(NativeDecoration(kind: .pluginState, rect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 7, color: NSColor(calibratedRed: 0.45, green: 0.78, blue: 1.0, alpha: 1), alpha: 0.18))
            case .attention:
                decorations.append(NativeDecoration(kind: .pluginState, rect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 8, color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.26, alpha: 1), alpha: 0.24))
                decorations.append(NativeDecoration(kind: .pluginState, rect: NSRect(x: rect.maxX - 10, y: rect.minY + 5, width: 4, height: 4), cornerRadius: 2, color: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.34, alpha: 1), alpha: 0.88))
            }
        }
    }

    private func computeGapTargets(_ anim: inout DragAnimation, layouts: [(x: Float, width: Float)]) {
        let gapWidth = anim.sourceWidth + LayoutConstants.itemSpacing
        var x = anim.leftMargin
        var logicalIdx = 0
        for i in layouts.indices {
            if i == anim.sourceIndex { continue }
            let adjustedInsert = anim.insertionIndex <= anim.sourceIndex ? anim.insertionIndex : anim.insertionIndex - 1
            if logicalIdx == adjustedInsert {
                x += gapWidth
            }
            anim.springs[i].target = x
            x += layouts[i].width + LayoutConstants.itemSpacing
            logicalIdx += 1
        }
    }

    private func computeSettleTargets(_ anim: inout DragAnimation, layouts: [(x: Float, width: Float)]) {
        var finalOrder = layouts.indices.filter { $0 != anim.sourceIndex }
        let insert = anim.insertionIndex <= anim.sourceIndex
            ? min(anim.insertionIndex, finalOrder.count)
            : min(anim.insertionIndex - 1, finalOrder.count)
        finalOrder.insert(anim.sourceIndex, at: max(0, insert))

        var x = anim.leftMargin
        for itemIdx in finalOrder {
            anim.springs[itemIdx].target = x
            x += layouts[itemIdx].width + LayoutConstants.itemSpacing
        }
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
        focus: FocusInfo = .none
    ) -> [(x: Float, width: Float)] {
        guard !items.isEmpty else { return [] }
        let iconSize = Float(config.iconSize)
        let iconsOnly = config.iconsOnly || config.taskbarPosition.isVertical
        let uniformSizing = config.itemSizing == .uniform
        let uniformWidth = computeUniformItemWidth(config: config, primaryLength: primaryLength, count: items.count)
        let shouldCollapse: (TaskbarItem) -> Bool = { item in
            (item.isHidden && config.showHiddenApps && config.hiddenWindowMode == .collapsedRight)
                || (item.isMinimized && config.showMinimizedWindows && config.minimizedWindowMode == .collapsedRight)
        }
        let pIndex = items.firstIndex(where: shouldCollapse)
        if let displayId {
            if let pIndex { partitionIndex[displayId] = pIndex } else { partitionIndex.removeValue(forKey: displayId) }
        }

        var layouts: [(x: Float, width: Float)] = []
        var x = layoutLeftMargin(config: config)
        var sepX: Float?
        for (index, item) in items.enumerated() {
            if case .customSpacer(_, let width, _) = item {
                let w = Float(max(0, width))
                layouts.append((x, w))
                x += w + LayoutConstants.itemSpacing
                continue
            }
            if let pIndex, index == pIndex {
                sepX = x
                x += 8
            }

            let forceIconOnly = pIndex != nil && index >= pIndex!
            let tabbedCollapse = shouldCollapseForTabbedTaskbar(item: item, focus: focus, config: config)
            let title = item.displayTitle(iconsOnly: iconsOnly || forceIconOnly || tabbedCollapse)
            let width: Float
            if forceIconOnly || iconsOnly || tabbedCollapse {
                width = iconOnlyWidth(item: item, config: config, iconSize: iconSize)
            } else if uniformSizing {
                width = uniformWidth
            } else if case .customText(_, let text, _) = item {
                width = computeAutoWidthNoIcon(config: config, title: text, fontSize: Float(config.fontSize))
            } else {
                width = computeAutoWidth(config: config, title: title, iconSize: iconSize, fontSize: Float(config.fontSize))
            }
            layouts.append((x, width))
            x += width + LayoutConstants.itemSpacing
        }

        if let displayId {
            if let sepX { separatorX[displayId] = sepX } else { separatorX.removeValue(forKey: displayId) }
        }

        if config.iconsOnly && config.taskbarPosition == .bottom && config.centerItems && !layouts.isEmpty {
            let last = layouts[layouts.count - 1]
            let left = layoutLeftMargin(config: config)
            let totalWidth = last.x + last.width - left
            let offset = (primaryLength - totalWidth) / 2 - left
            for i in layouts.indices {
                layouts[i].x += offset
            }
        }

        return layouts
    }

    private func iconOnlyWidth(item: TaskbarItem, config: Config, iconSize: Float) -> Float {
        let base = max(LayoutConstants.minItemWidth, iconSize + 20)
        guard config.groupByApp,
              case .appGroup(_, _, let windowCount, _, _, _, _) = item,
              windowCount > 1 else {
            return base
        }
        let plates = min(windowCount, StackTokens.maxPlates)
        let breathing = config.appGroupStackGeometry == .strong ? StackTokens.stackBreathingWidthStrong : StackTokens.stackBreathingWidthSubtle
        let offset = config.appGroupStackGeometry == .strong ? StackTokens.plateOffsetXStrong : StackTokens.plateOffsetXSubtle
        let layoutOffset = config.appGroupStackHoverSpreadEnabled ? offset * StackTokens.hoverSpreadMultiplier : offset
        return min(base + breathing + Float(plates - 1) * layoutOffset, Float(config.maxItemWidth))
    }

    private func iconRectForItem(rect: NSRect, title: String, iconSize: Float, position: Position, sidebarExpanded: Bool) -> NSRect {
        let size = CGFloat(iconSize)
        let x: CGFloat
        let y: CGFloat
        if position.isVertical {
            x = sidebarExpanded && !title.isEmpty
                ? rect.minX + CGFloat(LayoutConstants.iconLeftMargin)
                : rect.minX + (rect.width - size) / 2
            y = rect.minY + (rect.height - size) / 2
        } else {
            x = title.isEmpty ? rect.minX + (rect.width - size) / 2 : rect.minX + CGFloat(LayoutConstants.iconLeftMargin)
            y = rect.minY + (rect.height - size) / 2
        }
        return NSRect(x: x, y: y, width: size, height: size)
    }

    private func titleRectForItem(rect: NSRect, iconRect: NSRect, title: String, position: Position) -> NSRect {
        guard !title.isEmpty else { return .zero }
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

    private func computeAutoWidthNoIcon(config: Config, title: String, fontSize: Float) -> Float {
        let font = NSFont.systemFont(ofSize: CGFloat(fontSize), weight: .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let textWidth = min(Float(textSize.width), Float(config.maxTitleWidth))
        let width = LayoutConstants.iconLeftMargin + textWidth + LayoutConstants.textRightPadding
        return min(max(width, LayoutConstants.minItemWidth), Float(config.maxItemWidth))
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

    private func shouldCollapseForTabbedTaskbar(item: TaskbarItem, focus: FocusInfo, config: Config) -> Bool {
        guard config.tabbedTaskbarEnabled, !config.iconsOnly else { return false }
        let hasFocus = focus.windowId != nil ||
            (focus.bundleId?.isEmpty == false) ||
            (focus.tabGroupId?.isEmpty == false)
        guard hasFocus else { return false }
        switch item {
        case .window, .appGroup, .tabGroup:
            return focusedItemIndexForHighlight(items: [item], focus: focus, config: config) == nil
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
}
