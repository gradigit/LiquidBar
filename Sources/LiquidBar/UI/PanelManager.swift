// PanelManager.swift — Panel lifecycle per display + per-panel display links
//
// Creates one LiquidBarPanel per screen (based on multiMonitorMode config).
// Each panel gets its own CADisplayLink for short-lived native animations.
// Display links pause after each non-animated snapshot frame and stay active only
// while native drag springs are moving.

import AppKit
import QuartzCore

struct ViewSyncSnapshot: Equatable {
    let itemSignature: Int
    let itemBackgroundSignature: Int
    let systemIndicatorVisualSignature: Int
    let focus: FocusInfo
    let sidebarExpanded: Bool
    let config: Config
    let panelWidth: CGFloat
    let panelHeight: CGFloat
}

enum PanelReconcileResult: Equatable {
    case unchanged
    case updatedGeometry
    case rebuilt
}

@MainActor
final class PanelManager {
    private var panels: [CGDirectDisplayID: LiquidBarPanel] = [:]
    private var displayLinks: [CGDirectDisplayID: CADisplayLink] = [:]
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private weak var renderer: NativeBarRenderer?
    private var lastConfig: Config?
    private var spaceSuppressedDisplayIds: Set<CGDirectDisplayID> = []
    private var fullscreenSuppressedDisplayIds: Set<CGDirectDisplayID> = []
    private var lastViewSyncSnapshotByDisplay: [CGDirectDisplayID: ViewSyncSnapshot] = [:]

    private var suppressedDisplayIds: Set<CGDirectDisplayID> {
        spaceSuppressedDisplayIds.union(fullscreenSuppressedDisplayIds)
    }

    init() {}

    deinit {
        #if DEBUG
        print("[DEINIT] PanelManager")
        #endif
    }

    // MARK: - Create Panels

    func createPanels(config: Config, renderer: NativeBarRenderer) {
        self.renderer = renderer
        for entry in targetScreenEntries(config: config) {
            createPanel(for: entry.screen, displayId: entry.displayId, config: config)
        }
    }

    private func createPanel(for screen: NSScreen, displayId: CGDirectDisplayID, config: Config) {
        guard screen.frame.width > 1, screen.frame.height > 1 else {
            Log.ui.error("Screen frame invalid at panel create: \(screen.frame.debugDescription, privacy: .public)")
            return
        }

        let initialPresentation: SidebarPresentation = {
            guard config.sidebarModeEnabled, config.taskbarPosition.isVertical else { return .compact }
            switch config.sidebarStateDefault {
            case .expanded:
                return .expanded
            case .compactIcons:
                return .compact
            case .hiddenPeek:
                return .hidden
            }
        }()

        let panelThickness = Self.panelThickness(for: config, sidebarPresentation: initialPresentation)

        let panel = LiquidBarPanel(
            screen: screen,
            displayId: displayId,
            barHeight: panelThickness,
            position: config.taskbarPosition,
            barStyle: config.barStyle,
            theme: config.theme,
            glassStyle: config.glassStyle
        )

        panels[displayId] = panel
        if suppressedDisplayIds.contains(displayId) {
            panel.setSpaceSuppressed(true)
        }

        renderer?.registerPanel(
            displayId: displayId,
            barWidth: Float(panel.barView.bounds.width),
            barHeight: Float(panel.barView.bounds.height),
            scale: Float(screen.backingScaleFactor)
        )

        // Create display link for this panel
        let displayLink = panel.barView.displayLink(
            target: DisplayLinkTarget(panelManager: self, displayId: displayId),
            selector: #selector(DisplayLinkTarget.renderFrame(_:))
        )
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        displayLinks[displayId] = displayLink

        // Observe occlusion state changes to recover after space transitions.
        // Three-finger swipe composites the window as a snapshot; relayout the
        // retained taskbar layers when the panel becomes visible again.
        let occObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                if panel.occlusionState.contains(.visible) {
                    self.handleOcclusionRecovery(panel: panel, displayId: displayId)
                } else {
                    // Space transitions can snapshot the panel while retained layers are
                    // being relaid out. Pause until visibility is restored.
                    self.pauseDisplayLink(for: displayId)
                }
            }
        }
        occlusionObservers[displayId] = occObs
    }

    private func targetScreenEntries(config: Config) -> [(screen: NSScreen, displayId: CGDirectDisplayID)] {
        let screens = NSScreen.screens
        let targetScreens: [NSScreen]
        switch config.multiMonitorMode {
        case .allDisplays:
            targetScreens = screens
        case .mainOnly:
            if let main = NSScreen.main ?? screens.first {
                targetScreens = [main]
            } else {
                targetScreens = []
            }
        }

        var seen: Set<CGDirectDisplayID> = []
        var entries: [(screen: NSScreen, displayId: CGDirectDisplayID)] = []
        entries.reserveCapacity(targetScreens.count)

        for screen in targetScreens {
            let displayId: CGDirectDisplayID
            if let did = screen.displayId {
                displayId = did
            } else {
                // Defensive fallback: on some launch races NSScreenNumber can be temporarily nil.
                // Use main display id so we still create a visible bar instead of none.
                displayId = CGMainDisplayID()
                Log.ui.error("Screen had no display ID; falling back to CGMainDisplayID=\(displayId)")
            }
            guard seen.insert(displayId).inserted else { continue }
            entries.append((screen: screen, displayId: displayId))
        }

        return entries
    }

    nonisolated static func panelThickness(
        for config: Config,
        sidebarPresentation: SidebarPresentation = .compact
    ) -> CGFloat {
        if config.sidebarModeEnabled, config.taskbarPosition.isVertical {
            return SidebarRuntimeEvaluator.barThickness(for: sidebarPresentation, config: config)
        }
        return CGFloat(config.effectiveTaskbarHeight)
    }

    // MARK: - Display Geometry Reconciliation

    @discardableResult
    func reconcilePanelsForCurrentScreens(config: Config, renderer: NativeBarRenderer) -> PanelReconcileResult {
        self.renderer = renderer
        let entries = targetScreenEntries(config: config)
        guard !entries.isEmpty else {
            guard !panels.isEmpty else { return .unchanged }
            destroyAllPanels()
            return .rebuilt
        }

        let targetDisplayIds = Set(entries.map(\.displayId))
        if targetDisplayIds != Set(panels.keys) {
            rebuildPanels(config: config, renderer: renderer, preserveSuppression: true)
            return .rebuilt
        }

        var didUpdateGeometry = false
        for entry in entries {
            guard let panel = panels[entry.displayId] else {
                rebuildPanels(config: config, renderer: renderer, preserveSuppression: true)
                return .rebuilt
            }

            let previousFrame = panel.frame
            let previousBackingScale = panel.backingScaleFactor
            panel.updatePosition(
                screen: entry.screen,
                barHeight: panel.barHeight,
                position: config.taskbarPosition,
                barStyle: config.barStyle,
                theme: config.theme
            )
            panel.refreshRetainedLayers()
            renderer.resizePanel(
                displayId: entry.displayId,
                barWidth: Float(panel.barView.bounds.width),
                barHeight: Float(panel.barView.bounds.height),
                scale: Float(entry.screen.backingScaleFactor)
            )
            renderer.forceRedraw(displayId: entry.displayId)
            resumeDisplayLink(for: entry.displayId)

            if panel.frame != previousFrame || panel.backingScaleFactor != previousBackingScale {
                didUpdateGeometry = true
            }
        }

        return didUpdateGeometry ? .updatedGeometry : .unchanged
    }

    // MARK: - Update Items

    nonisolated static func makeViewSyncSnapshot(
        items: [TaskbarItem],
        itemBackgroundColors: [Int: String] = [:],
        systemIndicatorVisuals: [String: SystemIndicatorVisual] = [:],
        config: Config,
        focus: FocusInfo,
        sidebarExpanded: Bool,
        panelWidth: CGFloat,
        panelHeight: CGFloat
    ) -> ViewSyncSnapshot {
        ViewSyncSnapshot(
            itemSignature: taskbarItemSignature(for: items),
            itemBackgroundSignature: itemBackgroundColorSignature(for: itemBackgroundColors),
            systemIndicatorVisualSignature: systemIndicatorVisualSignature(for: systemIndicatorVisuals),
            focus: focus,
            sidebarExpanded: sidebarExpanded,
            config: config.taskbarSurfaceRenderKey,
            panelWidth: panelWidth,
            panelHeight: panelHeight
        )
    }

    private nonisolated static func taskbarItemSignature(for items: [TaskbarItem]) -> Int {
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
                hasher.combine(isHidden)
                hasher.combine(isMinimized)
                hasher.combine(screenId)
                for wid in windows {
                    hasher.combine(wid.raw)
                }
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

    private nonisolated static func itemBackgroundColorSignature(for colors: [Int: String]) -> Int {
        var hasher = Hasher()
        hasher.combine(colors.count)
        for (index, color) in colors.sorted(by: { $0.key < $1.key }) {
            hasher.combine(index)
            hasher.combine(color)
        }
        return hasher.finalize()
    }

    nonisolated static func systemIndicatorVisualSignature(for visuals: [String: SystemIndicatorVisual]) -> Int {
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

    nonisolated static func shouldSynchronizeBarView(
        previous: ViewSyncSnapshot?,
        current: ViewSyncSnapshot,
        rendererResult: StaticUpdateResult
    ) -> Bool {
        switch rendererResult {
        case .rebuiltStaticState:
            return true
        case .reusedStaticState:
            return previous != current
        }
    }

    nonisolated static func shouldSuppressTaskbar(currentSpace: SpacesService.CurrentSpaceInfo?) -> Bool {
        guard let currentSpace else { return false }
        return currentSpace.type != SpacesService.CurrentSpaceInfo.desktopType
    }

    nonisolated static func taskbarSpaceTransition(
        currentSpaceInfoByDisplay: [CGDirectDisplayID: SpacesService.CurrentSpaceInfo],
        previousSuppressed: Set<CGDirectDisplayID>
    ) -> (suppressed: Set<CGDirectDisplayID>, restored: Set<CGDirectDisplayID>) {
        let suppressed = Set(
            currentSpaceInfoByDisplay.compactMap { displayId, info in
                shouldSuppressTaskbar(currentSpace: info) ? displayId : nil
            }
        )
        return (suppressed, previousSuppressed.subtracting(suppressed))
    }

    nonisolated static func fullscreenCoveredDisplayIds(
        windows: [WindowInfo],
        displayBoundsById: [CGDirectDisplayID: CGRect]
    ) -> Set<CGDirectDisplayID> {
        var covered = Set<CGDirectDisplayID>()
        guard !windows.isEmpty, !displayBoundsById.isEmpty else { return covered }

        for window in windows where !window.isHidden && !window.isMinimized {
            guard !systemApps.contains(window.bundleId.raw) else { continue }
            for (displayId, displayBounds) in displayBoundsById {
                if shouldTreatAsFullscreenCover(window: window, displayBounds: displayBounds) {
                    covered.insert(displayId)
                }
            }
        }

        return covered
    }

    struct FullscreenCoverCandidate {
        let pid: pid_t
        let ownerName: String
        let layer: Int
        let bounds: WindowBounds
        let alpha: Double

        init(
            pid: pid_t,
            ownerName: String,
            layer: Int,
            bounds: WindowBounds,
            alpha: Double = 1.0
        ) {
            self.pid = pid
            self.ownerName = ownerName
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
        }
    }

    nonisolated static func fullscreenCoveredDisplayIds(
        candidates: [FullscreenCoverCandidate],
        displayBoundsById: [CGDirectDisplayID: CGRect],
        currentProcessId: pid_t
    ) -> Set<CGDirectDisplayID> {
        var covered = Set<CGDirectDisplayID>()
        guard !candidates.isEmpty, !displayBoundsById.isEmpty else { return covered }

        // Browser video fullscreen surfaces may use an elevated WindowServer
        // layer. Treat every opaque app surface with true display-sized geometry
        // consistently; transient controls and overlays must not expose the bar.
        for candidate in candidates {
            guard isEligibleFullscreenCoverCandidate(
                candidate,
                currentProcessId: currentProcessId
            ) else { continue }

            for (displayId, displayBounds) in displayBoundsById {
                if shouldTreatAsFullscreenCover(
                    bounds: candidate.bounds,
                    displayBounds: displayBounds
                ) {
                    covered.insert(displayId)
                }
            }
        }

        return covered
    }

    private nonisolated static func isEligibleFullscreenCoverCandidate(
        _ candidate: FullscreenCoverCandidate,
        currentProcessId: pid_t
    ) -> Bool {
        candidate.pid != currentProcessId &&
            candidate.alpha > 0.01 &&
            !isSystemFullscreenCoverCandidate(candidate.ownerName)
    }

    private nonisolated static func isSystemFullscreenCoverCandidate(_ ownerName: String) -> Bool {
        switch ownerName.lowercased() {
        case "dock",
             "loginwindow",
             "window server",
             "windowserver",
             "systemuiserver",
             "system ui server",
             "control center",
             "notification center":
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldTreatAsFullscreenCover(
        window: WindowInfo,
        displayBounds: CGRect,
        coverageThreshold: Double = 0.985,
        dimensionTolerance: Double = 32.0
    ) -> Bool {
        shouldTreatAsFullscreenCover(
            bounds: window.bounds,
            displayBounds: displayBounds,
            coverageThreshold: coverageThreshold,
            dimensionTolerance: dimensionTolerance
        )
    }

    private nonisolated static func shouldTreatAsFullscreenCover(
        bounds: WindowBounds,
        displayBounds: CGRect,
        coverageThreshold: Double = 0.985,
        dimensionTolerance: Double = 32.0
    ) -> Bool {
        guard displayBounds.width > 1, displayBounds.height > 1 else { return false }
        let display = WindowBounds(
            x: displayBounds.origin.x,
            y: displayBounds.origin.y,
            width: displayBounds.width,
            height: displayBounds.height
        )
        let displayArea = max(1.0, display.width * display.height)
        let coverage = bounds.intersectionArea(with: display) / displayArea
        guard coverage >= coverageThreshold else { return false }

        return bounds.width >= display.width - dimensionTolerance &&
            bounds.height >= display.height - dimensionTolerance &&
            bounds.width <= display.width + dimensionTolerance &&
            bounds.height <= display.height + dimensionTolerance
    }

    func updateItems(
        _ allItems: [TaskbarItem],
        config: Config,
        iconCache: IconCache,
        renderer: NativeBarRenderer,
        focusByDisplay: [CGDirectDisplayID: FocusInfo] = [:],
        expandedSidebarDisplays: Set<CGDirectDisplayID> = [],
        systemIndicatorVisuals: [String: SystemIndicatorVisual] = [:],
        itemBackgroundColorsByDisplay: [CGDirectDisplayID: [Int: String]] = [:]
    ) {
        lastConfig = config
        for (displayId, panel) in panels {
            let items: [TaskbarItem]
            switch config.windowDisplayMode {
            case .perDisplay:
                items = allItems.filter { item in
                    if let sid = item.screenId {
                        return sid == displayId
                    }
                    return true
                }
            case .allWindows:
                items = allItems.filter { item in
                    // Always keep windows/groups. Filter pinned items to the panel's display
                    // so per-space pins can differ per display without duplicating.
                    if case .pinnedApp(_, let sid) = item {
                        return sid == displayId
                    }
                    if case .pluginTile(_, _, _, _, _, let sid) = item {
                        return sid == displayId
                    }
                    if case .launcher(let sid) = item {
                        return sid == displayId
                    }
                    if case .tabGroup(_, _, _, _, _, _, _, let sid) = item {
                        return sid == displayId
                    }
                    return true
                }
            }

            let focus = focusByDisplay[displayId] ?? .none
            let sidebarExpanded = expandedSidebarDisplays.contains(displayId)
            let itemBackgroundColors = itemBackgroundColorsByDisplay[displayId] ?? [:]
            let rendererResult = renderer.updateItems(
                items,
                config: config,
                iconCache: iconCache,
                displayId: displayId,
                focus: focus,
                sidebarExpanded: sidebarExpanded,
                systemIndicatorVisuals: systemIndicatorVisuals,
                itemBackgroundColors: itemBackgroundColors
            )

            let snapshot = Self.makeViewSyncSnapshot(
                items: items,
                itemBackgroundColors: itemBackgroundColors,
                systemIndicatorVisuals: systemIndicatorVisuals,
                config: config,
                focus: focus,
                sidebarExpanded: sidebarExpanded,
                panelWidth: panel.barView.bounds.width,
                panelHeight: panel.barView.bounds.height
            )

            guard Self.shouldSynchronizeBarView(
                previous: lastViewSyncSnapshotByDisplay[displayId],
                current: snapshot,
                rendererResult: rendererResult
            ) else {
                resumeDisplayLink(for: displayId)
                continue
            }

            if let nativeSnapshot = renderer.snapshot(displayId: displayId) {
                panel.barView.applySnapshot(
                    nativeSnapshot,
                    fontSize: CGFloat(config.fontSize),
                    barHeight: min(panel.barView.bounds.width, panel.barView.bounds.height)
                )
            }
            lastViewSyncSnapshotByDisplay[displayId] = snapshot

            // Resume only long enough to tick transient native animations.
            resumeDisplayLink(for: displayId)
        }
    }

    // MARK: - Occlusion Recovery

    /// Recover a panel after it becomes visible again (e.g., space switch back).
    /// Refreshes retained layers. CABackdropLayer reconnects automatically when
    /// the window becomes visible — no glass rebuild needed.
    private func handleOcclusionRecovery(panel: LiquidBarPanel, displayId: CGDirectDisplayID) {
        if let config = lastConfig,
           let screen = currentScreen(for: displayId) ?? panel.screen {
            panel.updatePosition(
                screen: screen,
                barHeight: panel.barHeight,
                position: config.taskbarPosition,
                barStyle: config.barStyle,
                theme: config.theme
            )
            renderer?.resizePanel(
                displayId: displayId,
                barWidth: Float(panel.barView.bounds.width),
                barHeight: Float(panel.barView.bounds.height),
                scale: Float(screen.backingScaleFactor)
            )
        }
        panel.refreshRetainedLayers()
        renderer?.forceRedraw(displayId: displayId)
        resumeDisplayLink(for: displayId)
    }

    func reconcileTaskbarSpaceState(
        currentSpaceInfoByDisplay: [CGDirectDisplayID: SpacesService.CurrentSpaceInfo],
        config: Config,
        renderer: NativeBarRenderer
    ) {
        let transition = Self.taskbarSpaceTransition(
            currentSpaceInfoByDisplay: currentSpaceInfoByDisplay,
            previousSuppressed: spaceSuppressedDisplayIds
        )
        spaceSuppressedDisplayIds = transition.suppressed
        applyTaskbarSuppression(config: config, renderer: renderer)
    }

    func reconcileFullscreenWindowSuppression(
        windows: [WindowInfo],
        config: Config,
        renderer: NativeBarRenderer
    ) {
        let displayBoundsById = Self.activeDisplayBoundsById()
        let coveredDisplays = Self.fullscreenCoveredDisplayIds(
            windows: windows,
            displayBoundsById: displayBoundsById
        ).union(Self.rawFullscreenCoveredDisplayIds(displayBoundsById: displayBoundsById))
        guard coveredDisplays != fullscreenSuppressedDisplayIds else { return }
        fullscreenSuppressedDisplayIds = coveredDisplays
        applyTaskbarSuppression(config: config, renderer: renderer)
    }

    private func applyTaskbarSuppression(config: Config, renderer: NativeBarRenderer) {
        for (displayId, panel) in panels {
            if suppressedDisplayIds.contains(displayId) {
                panel.setSpaceSuppressed(true)
                pauseDisplayLink(for: displayId)
                continue
            }

            guard panel.isSpaceSuppressed else { continue }
            guard let screen = currentScreen(for: displayId) ?? panel.screen else {
                panel.setSpaceSuppressed(false)
                resumeDisplayLink(for: displayId)
                continue
            }

            panel.updatePosition(
                screen: screen,
                barHeight: panel.barHeight,
                position: config.taskbarPosition,
                barStyle: config.barStyle,
                theme: config.theme
            )
            panel.refreshRetainedLayers()
            renderer.resizePanel(
                displayId: displayId,
                barWidth: Float(panel.barView.bounds.width),
                barHeight: Float(panel.barView.bounds.height),
                scale: Float(screen.backingScaleFactor)
            )
            panel.setSpaceSuppressed(false)
            panel.refreshGlass()
            renderer.forceRedraw(displayId: displayId)
            resumeDisplayLink(for: displayId)
        }
    }

    private static func activeDisplayBoundsById() -> [CGDirectDisplayID: CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [:]
        }

        var displayIds = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIds, &count) == .success else {
            return [:]
        }

        var result: [CGDirectDisplayID: CGRect] = [:]
        result.reserveCapacity(Int(count))
        for displayId in displayIds.prefix(Int(count)) {
            result[displayId] = CGDisplayBounds(displayId)
        }
        return result
    }

    private func currentScreen(for displayId: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: { $0.displayId == displayId })
    }

    private static func rawFullscreenCoveredDisplayIds(
        displayBoundsById: [CGDirectDisplayID: CGRect]
    ) -> Set<CGDirectDisplayID> {
        guard !displayBoundsById.isEmpty else { return [] }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] ?? []
        let candidates = windowList.compactMap(Self.fullscreenCoverCandidate(from:))
        return fullscreenCoveredDisplayIds(
            candidates: candidates,
            displayBoundsById: displayBoundsById,
            currentProcessId: getpid()
        )
    }

    private static func fullscreenCoverCandidate(from dict: [CFString: Any]) -> FullscreenCoverCandidate? {
        guard let surface = WindowServerSurface(dict) else { return nil }
        return FullscreenCoverCandidate(
            pid: surface.pid,
            ownerName: surface.ownerName,
            layer: surface.layer,
            bounds: surface.bounds,
            alpha: (dict[kCGWindowAlpha as CFString] as? NSNumber)?.doubleValue ?? 1.0
        )
    }

    // MARK: - Display Link Management

    func resumeDisplayLink(for displayId: CGDirectDisplayID) {
        displayLinks[displayId]?.isPaused = false
    }

    func resumeAllDisplayLinks() {
        for displayId in displayLinks.keys {
            resumeDisplayLink(for: displayId)
        }
    }

    func pauseDisplayLink(for displayId: CGDirectDisplayID) {
        displayLinks[displayId]?.isPaused = true
    }

    func pauseAllDisplayLinks() {
        for (_, link) in displayLinks {
            link.isPaused = true
        }
    }

    // MARK: - Display Link Callback

    func renderFrame(displayId: CGDirectDisplayID) {
        guard let panel = panels[displayId],
              let renderer = renderer else {
            pauseDisplayLink(for: displayId)
            return
        }
        let callbackStart = CACurrentMediaTime()

        // Do not tick native animations while the panel is occluded.
        guard panel.occlusionState.contains(.visible) else {
            pauseDisplayLink(for: displayId)
            return
        }

        // Tick drag springs before applying the retained snapshot.
        let dragAnimating = renderer.tickAndRebuildDragBuffers(displayId: displayId)

        let renderStart = CACurrentMediaTime()
        if let snapshot = renderer.snapshot(displayId: displayId),
           let cfg = lastConfig {
            panel.barView.applySnapshot(
                snapshot,
                fontSize: CGFloat(cfg.fontSize),
                barHeight: min(panel.barView.bounds.width, panel.barView.bounds.height)
            )
        }
        let callbackEnd = CACurrentMediaTime()
        PerformanceMonitor.shared.recordFrame(
            displayId: displayId,
            callbackDurationMs: (callbackEnd - callbackStart) * 1000.0,
            renderDurationMs: (callbackEnd - renderStart) * 1000.0
        )

        if !dragAnimating {
            pauseDisplayLink(for: displayId)
        }
    }

    // MARK: - Panel Access

    func panel(for displayId: CGDirectDisplayID) -> LiquidBarPanel? {
        panels[displayId]
    }

    @discardableResult
    func applySidebarPresentation(
        for displayId: CGDirectDisplayID,
        presentation: SidebarPresentation,
        config: Config
    ) -> Bool {
        guard config.taskbarPosition.isVertical,
              config.sidebarModeEnabled,
              let panel = panels[displayId],
              let renderer else {
            return false
        }
        guard let screen = currentScreen(for: displayId) ?? panel.screen else {
            return false
        }

        let targetThickness = SidebarRuntimeEvaluator.barThickness(for: presentation, config: config)
        let needsGeometryUpdate = abs(panel.barHeight - targetThickness) > 0.5
            || panel.position != config.taskbarPosition
            || panel.barStyle != config.barStyle
            || panel.theme != config.theme

        guard needsGeometryUpdate else { return false }

        panel.updatePosition(
            screen: screen,
            barHeight: targetThickness,
            position: config.taskbarPosition,
            barStyle: config.barStyle,
            theme: config.theme
        )
        panel.refreshRetainedLayers()
        renderer.resizePanel(
            displayId: displayId,
            barWidth: Float(panel.barView.bounds.width),
            barHeight: Float(panel.barView.bounds.height),
            scale: Float(screen.backingScaleFactor)
        )
        resumeDisplayLink(for: displayId)
        return true
    }

    var allPanels: [LiquidBarPanel] {
        Array(panels.values)
    }

    var allDisplayIds: [CGDirectDisplayID] {
        Array(panels.keys)
    }

    // MARK: - Rebuild

    func rebuildPanels(config: Config, renderer: NativeBarRenderer, preserveSuppression: Bool = false) {
        destroyAllPanels(preserveSuppression: preserveSuppression)
        createPanels(config: config, renderer: renderer)
    }

    // MARK: - Cleanup

    func destroyAllPanels(preserveSuppression: Bool = false) {
        // Invalidate all display links
        for (_, link) in displayLinks {
            link.invalidate()
        }
        displayLinks.removeAll()
        lastViewSyncSnapshotByDisplay.removeAll()
        if !preserveSuppression {
            spaceSuppressedDisplayIds.removeAll(keepingCapacity: true)
            fullscreenSuppressedDisplayIds.removeAll(keepingCapacity: true)
        }

        // Remove occlusion observers
        for (_, obs) in occlusionObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        occlusionObservers.removeAll()

        // Cleanup and unregister panels
        for (displayId, panel) in panels {
            renderer?.unregisterPanel(displayId: displayId)
            panel.cleanup()
        }
        panels.removeAll()
    }
}

// MARK: - Display Link Target

/// Helper class to receive display link callbacks without retain cycles.
/// The display link retains its target, so we use a weak reference back to PanelManager.
@MainActor
private class DisplayLinkTarget: NSObject {
    weak var panelManager: PanelManager?
    let displayId: CGDirectDisplayID

    init(panelManager: PanelManager, displayId: CGDirectDisplayID) {
        self.panelManager = panelManager
        self.displayId = displayId
    }

    @objc func renderFrame(_ displayLink: CADisplayLink) {
        autoreleasepool {
            panelManager?.renderFrame(displayId: displayId)
        }
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    var displayId: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screenNumber = deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(screenNumber.uint32Value)
        }
        if let v = deviceDescription[key] as? Int {
            return CGDirectDisplayID(UInt32(clamping: v))
        }
        if let v = deviceDescription[key] as? Int32 {
            return CGDirectDisplayID(UInt32(bitPattern: v))
        }
        if let v = deviceDescription[key] as? UInt32 {
            return CGDirectDisplayID(v)
        }
        return nil
    }
}
