// EventLoop.swift — Polling + per-panel display link coordination
//
// Two loops, separated concerns:
//   - Polling timer (adaptive): data — enumerate windows, detect changes, update retained state
//   - CADisplayLink (per panel): tick transient native animations only while active
//
// Both run on the main thread (RunLoop-based), inherently serialized.

import AppKit
import QuartzCore

struct BarViewDataSnapshot: Equatable {
    let pinnedBundleSignature: Int
    let sharedSignature: Int
}

@MainActor
final class EventLoop {
    struct VisibleReorderPlan: Equatable {
        let windowOrder: [UInt32]
        let appOrder: [String]
        let pinnedOrder: [String]
        let itemOrder: [String]
    }

    enum ThumbnailCaptureContext {
        case hoveredPreview
        case switcher
        case groupPreview
        case prewarm

        var producer: WindowThumbnailService.ThumbnailProducer {
            switch self {
            case .hoveredPreview:
                return .interactive
            case .switcher:
                return .switcher
            case .groupPreview:
                return .groupPreview
            case .prewarm:
                return .prewarm
            }
        }
    }

    private var pollTimer: Timer?
    private let windowManager: WindowManager
    private let windowListStabilizer = WindowListStabilizer()
    private let windowStateStore: WindowStateStore
    let panelManager: PanelManager
    private let renderer: NativeBarRenderer
    private let mouseTracker: MouseTracker
    private let iconCache: IconCache
    private let spacesService: SpacesService
    private let axObserverService: AXObserverService
    private let pluginManager: PluginManager
    private let providerRuntime: ProviderRuntime
    private let systemMetricsProvider: SystemMetricsProvider
    private let thumbnailService: WindowThumbnailService
    private let windowLayoutMemoryService = WindowLayoutMemoryService()
    // AccessibilityService is all-static, no instance needed
    private var config: Config
    private var userState: UserState
    var onOpenPreferences: (() -> Void)?

    // Space-key cache (per-space pinned apps). Keep private Spaces calls off hot paths.
    private var cachedSpaceKeyByDisplay: [CGDirectDisplayID: String] = [:]
    private var cachedCurrentSpaceInfoByDisplay: [CGDirectDisplayID: SpacesService.CurrentSpaceInfo] = [:]

    // Render state
    private var currentItems: [TaskbarItem] = []
    private var pinnedBundleIdsByDisplay: [CGDirectDisplayID: Set<String>] = [:]
    private var lastBarViewDataSnapshotByDisplay: [CGDirectDisplayID: BarViewDataSnapshot] = [:]
    private var lastBarViewIdentityByDisplay: [CGDirectDisplayID: ObjectIdentifier] = [:]
    private var didSeedPerSpacePinsFromConfig: Bool = false
    private var loadedPlugins: [PluginManager.LoadedPlugin] = []
    private var pluginCustomItems: [CustomItem] = []
    private var pluginTiles: [PluginManager.LoadedPluginTile] = []
    private var windowPresentationKeyByWindowId: [UInt32: String] = [:]
    private var pluginCardPanel: PluginControlCardPanel?
    private var pluginCardTileId: String?
    private var pluginCardProviderId: String?
    private var pluginCardDisplayId: CGDirectDisplayID?
    /// Per-display expanded tab group id (if any).
    private var expandedTabGroupIdByDisplay: [CGDirectDisplayID: String] = [:]
    /// Per-display overlay panel for expanded tab groups.
    private var tabGroupOverlayByDisplay: [CGDirectDisplayID: TabGroupOverlayPanel] = [:]
    private var tabGroupHoverWorkItemByDisplay: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var tabGroupHoverCandidateGroupIdByDisplay: [CGDirectDisplayID: String] = [:]
    private var previewPanelByDisplay: [CGDirectDisplayID: WindowPreviewPanel] = [:]
    private var previewWorkItemByDisplay: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var previewHoveredWindowIdByDisplay: [CGDirectDisplayID: UInt32] = [:]
    private var groupPreviewPanelByDisplay: [CGDirectDisplayID: WindowGroupPreviewPanel] = [:]
    private var groupPreviewShowWorkItemByDisplay: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var groupPreviewHideWorkItemByDisplay: [CGDirectDisplayID: DispatchWorkItem] = [:]
    /// Bar-hover key (cleared when the cursor leaves the taskbar).
    private var groupPreviewHoveredKeyByDisplay: [CGDirectDisplayID: String] = [:]
    /// Active key for the currently visible preview panel content.
    private var groupPreviewActiveKeyByDisplay: [CGDirectDisplayID: String] = [:]
    /// Runtime ordering overrides for group-preview windows (mainly app groups).
    /// Tab-group order is persisted in `UserState`; this map is used for non-persistent groups.
    private var groupPreviewOrderByKey: [String: [UInt32]] = [:]
    private var groupPreviewPointerInsideByDisplay: [CGDirectDisplayID: Bool] = [:]
    private var groupPreviewAnchorRectByDisplay: [CGDirectDisplayID: CGRect] = [:]
    private var isBarHidden: Bool = false
    private var sidebarRevealUntilByDisplay: [CGDirectDisplayID: CFAbsoluteTime] = [:]
    private var sidebarPresentationByDisplay: [CGDirectDisplayID: SidebarPresentation] = [:]
    private var lastAXObserverStateCheck: CFAbsoluteTime = 0
    private var isAXObserverActive: Bool = false
    private let isAXQueriesDisabledByEnv: Bool = ProcessInfo.processInfo.environment["LIQUIDBAR_DISABLE_AX_QUERIES"] == "1"
    private let isSwitcherThumbnailPrewarmDisabledByEnv: Bool = EventLoop.envBool("LIQUIDBAR_DISABLE_SWITCHER_THUMBNAIL_PREWARM")
    private var axObserverRefreshWorkItem: DispatchWorkItem?

    // Focus cache (tabbed taskbar)
    private var cachedFocusInfo: FocusInfo = .none
    private var cachedFocusDisplayId: CGDirectDisplayID?

    // Window tracking for adjustment
    private var knownWindowIds: Set<UInt32> = []
    private var lastWindowPositions: [UInt32: (x: Double, y: Double, w: Double, h: Double)] = [:]
    private var lastAdjustCheck: CFAbsoluteTime = 0
    private var pendingAXWindowAdjustmentCheck: Bool = false
    private var lastScreenParametersChangeAt: CFAbsoluteTime = 0

    // Memory monitoring
    private var memoryBaseline: Int = 0
    private var lastMemoryCheck: CFAbsoluteTime = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Adaptive polling
    private var currentPollInterval: TimeInterval = 0.2
    // Lower base polling frequency; event notifications trigger immediate refreshes.
    private let idlePollInterval: TimeInterval = 0.2
    // Drag visuals are driven by the display link + mouse events; polling window state at
    // 60Hz while dragging can starve the main thread when AX/Spaces queries are enabled.
    private let dragPollInterval: TimeInterval = 0.1
    // Event-first model with slow fallback polling for missed notifications.
    private let fallbackPollInterval: TimeInterval = 0.8
    private let axObserverFallbackRefreshInterval: CFAbsoluteTime = 8.0
    private var needsWindowRefresh: Bool = true
    private var lastWindowEnumerationAt: CFAbsoluteTime = 0

    // Space change
    private var spaceChangeObserver: NSObjectProtocol?
    private var workspaceAppObservers: [NSObjectProtocol] = []
    private var workspaceRefreshWorkItem: DispatchWorkItem?
    private var displayReconfigurationObserver: DisplayReconfigurationObserver?
    private var windowLayoutMemoryRestoreWorkItems: [DispatchWorkItem] = []
    private var localEventMonitor: Any?
    private var hotkeyMonitor: HotkeyMonitor?
    private var lastSpaceChangeAt: CFAbsoluteTime = 0
    private var spaceChangeToken: UInt64 = 0
    private var screenChangeToken: UInt64 = 0
    private var switcherPanel: WindowSwitcherPanel?
    private var switcherEntries: [WindowInfo] = []
    private var switcherMRUWindowIds: [UInt32] = []
    private var switcherSelectedIndex: Int = 0
    private var switcherCommitWorkItem: DispatchWorkItem?
    private var switcherThumbnailWorkItem: DispatchWorkItem?
    private var switcherPrewarmWorkItem: DispatchWorkItem?
    private var switcherPrewarmSignature: String = ""
    private var switcherSelectionVisualUpdateScheduled = false
    private var pendingSwitcherSelectionVisualUpdate: (index: Int, token: UInt64)?
    private var switcherSession = SwitcherHotkeySession()
    private var lastSwitcherEndedAt: CFAbsoluteTime = 0
    // Keep ScreenCaptureKit refreshes out of quick Cmd-Tab traversal; cached/prewarmed
    // thumbnails are used immediately, and held sessions refresh after the overlay settles.
    private let switcherThumbnailStableDelay: TimeInterval = 0.45
    private let switcherPrewarmAfterCloseDelay: TimeInterval = 1.25

    #if DEBUG
    private var testControlObservers: [NSObjectProtocol] = []
    #endif

    nonisolated static func sharedBarViewDataSignature(
        userCustomItemIds: Set<String>,
        windowTabGroupsEnabled: Bool,
        tabGroups: [TabGroup],
        windowIdToGroupId: [UInt32: String]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(windowTabGroupsEnabled)
        for id in userCustomItemIds.sorted() {
            hasher.combine(id)
        }
        hasher.combine(tabGroups.count)
        for group in tabGroups {
            hasher.combine(group.id)
            hasher.combine(group.name)
            hasher.combine(group.emoji)
            hasher.combine(group.colorHex)
            hasher.combine(group.windowIds.count)
            for windowId in group.windowIds {
                hasher.combine(windowId)
            }
        }
        hasher.combine(windowIdToGroupId.count)
        for (windowId, groupId) in windowIdToGroupId.sorted(by: { $0.key < $1.key }) {
            hasher.combine(windowId)
            hasher.combine(groupId)
        }
        return hasher.finalize()
    }

    nonisolated static func makeBarViewDataSnapshot(
        pinnedBundleIds: Set<String>,
        sharedSignature: Int
    ) -> BarViewDataSnapshot {
        var hasher = Hasher()
        hasher.combine(pinnedBundleIds.count)
        for bundleId in pinnedBundleIds.sorted() {
            hasher.combine(bundleId)
        }
        return BarViewDataSnapshot(
            pinnedBundleSignature: hasher.finalize(),
            sharedSignature: sharedSignature
        )
    }

    private nonisolated static func envBool(_ key: String) -> Bool {
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

    nonisolated static func shouldSynchronizeBarViewData(
        previous: BarViewDataSnapshot?,
        current: BarViewDataSnapshot,
        isNewBarView: Bool
    ) -> Bool {
        isNewBarView || previous != current
    }

    nonisolated static func makeFocusInfo(
        frontmostWindowId: UInt32?,
        windows: [WindowId: WindowInfo],
        tabGroupId: String?
    ) -> (info: FocusInfo, displayId: CGDirectDisplayID?) {
        guard let frontmostWindowId else {
            return (.none, nil)
        }

        guard let win = windows[WindowId(frontmostWindowId)] else {
            return (
                FocusInfo(windowId: frontmostWindowId, bundleId: nil, tabGroupId: tabGroupId),
                nil
            )
        }

        return (
            FocusInfo(windowId: frontmostWindowId, bundleId: win.bundleId.raw, tabGroupId: tabGroupId),
            CGDirectDisplayID(win.monitorId.raw)
        )
    }

    nonisolated static func updatedSwitcherMRUOrder(
        previous: [UInt32],
        focusedWindowId: UInt32?,
        liveWindowIds: Set<UInt32>,
        maxCount: Int = maxWindows
    ) -> [UInt32] {
        guard !liveWindowIds.isEmpty, maxCount > 0 else { return [] }

        var result: [UInt32] = []
        result.reserveCapacity(min(maxCount, liveWindowIds.count))
        var seen = Set<UInt32>()
        seen.reserveCapacity(min(maxCount, liveWindowIds.count))

        func append(_ raw: UInt32) {
            guard result.count < maxCount,
                  liveWindowIds.contains(raw),
                  seen.insert(raw).inserted else {
                return
            }
            result.append(raw)
        }

        if let focusedWindowId {
            append(focusedWindowId)
        }
        for raw in previous {
            append(raw)
        }
        return result
    }

    nonisolated static func orderedSwitcherWindows(
        windows: [WindowInfo],
        mruWindowIds: [UInt32]
    ) -> [WindowInfo] {
        guard !windows.isEmpty else { return [] }

        var byId: [UInt32: WindowInfo] = [:]
        byId.reserveCapacity(windows.count)
        for window in windows where byId[window.id.raw] == nil {
            byId[window.id.raw] = window
        }

        var ordered: [WindowInfo] = []
        ordered.reserveCapacity(windows.count)
        var seen = Set<UInt32>()
        seen.reserveCapacity(windows.count)

        for raw in mruWindowIds {
            guard let window = byId[raw],
                  seen.insert(raw).inserted else {
                continue
            }
            ordered.append(window)
        }

        for window in windows where seen.insert(window.id.raw).inserted {
            ordered.append(window)
        }

        return ordered
    }

    nonisolated static func switcherCandidateWindows(
        windows: [WindowInfo],
        scope: SwitcherWindowScope,
        focusDisplayId: CGDirectDisplayID?
    ) -> [WindowInfo] {
        let scoped: [WindowInfo]
        switch scope {
        case .allDisplays:
            scoped = windows
        case .focusedDisplay:
            if let focusDisplayId {
                let filtered = windows.filter { $0.monitorId.raw == focusDisplayId }
                scoped = filtered.isEmpty ? windows : filtered
            } else {
                scoped = windows
            }
        }

        var seen = Set<UInt32>()
        return scoped.filter { seen.insert($0.id.raw).inserted }
    }

    nonisolated static func initialSwitcherSelectedIndex(
        entries: [WindowInfo],
        focusedWindowId: UInt32?,
        initialDirection: Int
    ) -> Int {
        guard !entries.isEmpty else { return 0 }
        let direction = initialDirection < 0 ? -1 : 1
        if let focusedWindowId,
           let idx = entries.firstIndex(where: { $0.id.raw == focusedWindowId }) {
            return (idx + direction + entries.count) % entries.count
        }
        return direction < 0 ? entries.count - 1 : 0
    }

    nonisolated static let screenChangeRecoveryDelays: [TimeInterval] = [0.05, 0.18, 0.40, 0.85, 1.60]
    nonisolated static let screenChangeAdjustmentSuppression: CFTimeInterval = 8.0
    nonisolated static let spaceChangeRecoveryDelays: [TimeInterval] = [0.15, 0.45, 1.00]

    nonisolated static func shouldSuppressWindowAdjustmentForScreenChange(
        now: CFAbsoluteTime,
        lastScreenChangeAt: CFAbsoluteTime
    ) -> Bool {
        lastScreenChangeAt > 0
            && now - lastScreenChangeAt < screenChangeAdjustmentSuppression
    }

    init(
        config: Config,
        renderer: NativeBarRenderer,
        panelManager: PanelManager
    ) {
        self.config = config
        self.renderer = renderer
        self.panelManager = panelManager
        self.windowManager = WindowManager()
        self.windowStateStore = WindowStateStore()
        self.mouseTracker = MouseTracker()
        self.iconCache = IconCache()
        self.spacesService = SpacesService()
        self.axObserverService = AXObserverService()
        self.pluginManager = PluginManager()
        self.providerRuntime = ProviderRuntime()
        self.systemMetricsProvider = SystemMetricsProvider()
        self.thumbnailService = WindowThumbnailService()
        self.userState = UserState.load()
        self.groupPreviewOrderByKey = self.userState.groupPreviewOrderByKey
        self.memoryBaseline = MemoryMonitor.getRSSBytes()
    }

    deinit {
        #if DEBUG
        print("[DEINIT] EventLoop")
        #endif
    }

    // MARK: - Start / Stop

    func start() {
        PerformanceMonitor.shared.apply(config: config)
        thumbnailService.applyMemoryPreset(config.previewMemoryPreset)
        if ProcessInfo.processInfo.environment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] != "1" {
            mouseTracker.start()
        }
        installMemoryPressureMonitor()
        startPollTimer(interval: idlePollInterval)
        lastAXObserverStateCheck = CFAbsoluteTimeGetCurrent()
        scheduleAXObserverRefresh(delay: 1.50)

        reloadPlugins()

        // Prime per-display Space keys before first render so per-space pins
        // don't call private Spaces APIs from inside renderUI().
        refreshSpaceKeyCache(displayIds: panelManager.allDisplayIds)

        // Initial poll
        pollAndUpdate(forceRender: false)

        // Fade in panels after a brief delay so glass can attach to the compositor.
        showPanelsAfterDelay()

        // Observe space changes — three-finger swipe between desktops can leave
        // retained taskbar layers and the window list out of date.
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSpaceChange()
            }
        }
        installWorkspaceAppObservers()

        #if DEBUG
        installTestControl()
        #endif

        installLocalEventMonitor()
        configureSwitcherHotkey()
        configureDisplayReconfigurationObserver()

        Log.event.info("EventLoop started")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
        let workspaceNC = NSWorkspace.shared.notificationCenter
        for obs in workspaceAppObservers {
            workspaceNC.removeObserver(obs)
        }
        workspaceAppObservers.removeAll()
        workspaceRefreshWorkItem?.cancel()
        workspaceRefreshWorkItem = nil
        displayReconfigurationObserver?.stop()
        displayReconfigurationObserver = nil
        cancelWindowLayoutMemoryRestoreWorkItems()
        windowLayoutMemoryService.clear()

        #if DEBUG
        if !testControlObservers.isEmpty {
            let center = DistributedNotificationCenter.default()
            for obs in testControlObservers {
                center.removeObserver(obs)
            }
            testControlObservers.removeAll()
        }
        #endif

        mouseTracker.stop()
        axObserverService.stop()
        isAXObserverActive = false
        axObserverRefreshWorkItem?.cancel()
        axObserverRefreshWorkItem = nil
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        hotkeyMonitor?.unregister()
        hotkeyMonitor = nil
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        switcherPrewarmWorkItem?.cancel()
        switcherPrewarmWorkItem = nil
        hideSwitcher(commitSelection: false)
        hidePluginCard()
        hideAllTabGroupOverlays()
        hideAllPreviews()
        lastBarViewDataSnapshotByDisplay.removeAll()
        lastBarViewIdentityByDisplay.removeAll()
        panelManager.destroyAllPanels()
        renderer.shutdown()
        Log.event.info("EventLoop stopped")
    }

    private func installMemoryPressureMonitor() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {
        let summary = thumbnailService.trimForMemoryPressure()
        iconCache.clearCache()
        releaseHiddenOverlayImages()

        PerformanceMonitor.shared.recordDiagnosticSnapshot(
            "memory_pressure",
            minIntervalSeconds: 0
        ) {
            "cache_entries=\(summary.cacheEntries) cache_bytes=\(summary.cacheBytes) last_good_entries=\(summary.lastGoodEntries) last_good_bytes=\(summary.lastGoodBytes) queued_thumbnails=\(summary.queuedRequests) inflight_thumbnails=\(summary.inFlightRequests) rss=\(MemoryMonitor.getRSSBytes())"
        }
    }

    private func installLocalEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }

            if self.handleSwitcherLocalEvent(event) {
                return nil
            }

            switch event.type {
            case .keyDown:
                if event.keyCode == 53 { // Escape
                    self.hidePluginCard()
                    self.hideAllPreviews()
                    self.hideAllTabGroupOverlays()
                }

            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                handleSidebarPeekMouseDown(event)
                if self.pluginCardPanel?.isVisible == true {
                    let screenPoint = self.screenPointForEvent(event)
                    if self.pluginCardPanel?.frame.contains(screenPoint) != true {
                        self.hidePluginCard()
                    }
                }

            default:
                break
            }
            return event
        }
    }

    private func installWorkspaceAppObservers() {
        let workspaceNC = NSWorkspace.shared.notificationCenter
        let lifecycleNames: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        let activityNames: [NSNotification.Name] = [
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification
        ]

        for name in lifecycleNames {
            let obs = workspaceNC.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.markWindowRefreshNeeded(invalidateCaches: true)
                    if self.isAXObserverActive {
                        self.refreshAXObserversMeasured()
                    }
                    self.scheduleWorkspaceRefresh()
                }
            }
            workspaceAppObservers.append(obs)
        }

        for name in activityNames {
            let obs = workspaceNC.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.markWindowRefreshNeeded(invalidateCaches: true)
                    self?.scheduleWorkspaceRefresh()
                }
            }
            workspaceAppObservers.append(obs)
        }
    }

    private func scheduleWorkspaceRefresh() {
        markWindowRefreshNeeded(invalidateCaches: false)
        workspaceRefreshWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pollAndUpdate(forceRender: false)
            self.panelManager.resumeAllDisplayLinks()
        }

        workspaceRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func markWindowRefreshNeeded(invalidateCaches: Bool) {
        needsWindowRefresh = true
        if invalidateCaches {
            windowManager.invalidateEnumerationCaches()
        }
    }

    private func hiddenRunningBundleIdsForMissingWindows(observedWindowIds: Set<UInt32>) -> Set<String> {
        guard config.showHiddenApps else { return [] }

        let missingBundles = Set(windowStateStore.getWindows().compactMap { window -> String? in
            observedWindowIds.contains(window.id.raw) ? nil : window.bundleId.raw
        })
        guard !missingBundles.isEmpty else { return [] }

        return Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.isHidden,
                  let bundleId = app.bundleIdentifier,
                  missingBundles.contains(bundleId) else {
                return nil
            }
            return bundleId
        })
    }

    // MARK: - Polling Timer

    private func startPollTimer(interval: TimeInterval) {
        pollTimer?.invalidate()
        currentPollInterval = interval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollAndUpdate(forceRender: false)
            }
        }
    }

    private func pollAndUpdate(forceRender: Bool) {
        autoreleasepool {
            let pollStart = CACurrentMediaTime()

            // Adaptive polling: switch interval based on drag state
            let isDragging = MouseTracker.isDragging
            let targetInterval = isDragging ? dragPollInterval : idlePollInterval
            if abs(currentPollInterval - targetInterval) > 0.001 {
                startPollTimer(interval: targetInterval)
            }

            // CGWindowList calls can stall briefly during Spaces transitions. Avoid
            // invoking them in the immediate post-switch window; handleSpaceChange()
            // already schedules a burst of delayed polls for recovery.
            let now = CFAbsoluteTimeGetCurrent()
            let sidebarGeometryChanged = updateSidebarPeekVisibility(now: now)
            if sidebarGeometryChanged {
                // Renderer panel metrics were resized; repopulate current items immediately
                // so sidebars do not appear blank between polling cycles.
                renderUI()
                panelManager.resumeAllDisplayLinks()
            }
            if now - lastAXObserverStateCheck > axObserverFallbackRefreshInterval {
                scheduleAXObserverRefresh(delay: 0.20)
                lastAXObserverStateCheck = now
            }
            if now - lastSpaceChangeAt < 0.12 {
                maybeCheckMemory(now: now)
                recordPollResult(
                    pollStart: pollStart,
                    now: now,
                    enumerated: false,
                    reason: "space_guard",
                    windowCount: currentItems.count,
                    forceRender: forceRender,
                    isDragging: isDragging
                )
                return
            }

            let fallbackDue = (now - lastWindowEnumerationAt) >= fallbackPollInterval
            let eventDrivenDue = needsWindowRefresh
            let shouldEnumerate = forceRender || isDragging || eventDrivenDue || fallbackDue
            if !shouldEnumerate {
                let metricsRefreshed = refreshSystemMetricsIfNeeded(now: now)
                if metricsRefreshed {
                    renderUI()
                    panelManager.resumeAllDisplayLinks()
                }
                maybeCheckMemory(now: now)
                recordPollResult(
                    pollStart: pollStart,
                    now: now,
                    enumerated: false,
                    reason: metricsRefreshed ? "metrics" : "idle_skip",
                    windowCount: currentItems.count,
                    forceRender: forceRender,
                    isDragging: isDragging
                )
                return
            }

            needsWindowRefresh = false
            lastWindowEnumerationAt = now

            // Enumerate windows
            let windows = PerformanceMonitor.shared.measureSegment(
                "window_enumeration",
                thresholdMs: 80.0
            ) {
                windowListStabilizer.stabilize(observed: windowManager.enumerate(
                    config: config,
                    currentSpaceKeysByDisplay: cachedSpaceKeyByDisplay,
                    spacesService: spacesService
                ))
            }
            panelManager.reconcileFullscreenWindowSuppression(
                windows: windows,
                config: config,
                renderer: renderer
            )

            // Detect new and moved windows
            let observedWindowIds = Set(windows.map { $0.id.raw })
            let hasNewWindows = !observedWindowIds.subtracting(knownWindowIds).isEmpty
            let hasMovedWindows = checkForMovedWindows(windows)
            let hiddenBundleIds = hiddenRunningBundleIdsForMissingWindows(observedWindowIds: observedWindowIds)

            // Update state
            let (changed, restoredOrderChanged) = PerformanceMonitor.shared.measureSegment(
                "window_state_update"
            ) {
                let changed = windowStateStore.update(
                    windows: windows,
                    config: config,
                    hiddenBundleIds: hiddenBundleIds
                )
                // Restore persisted item/window ordering across app restarts.
                let restoredOrderChanged = windowStateStore.applyPreferredWindowOrder(preferredWindowOrderForCurrentWindows())
                // Keep persisted order pruned/aligned with the current live set.
                userState.updateWindowOrder(windowStateStore.getWindows().map(\.id.raw))
                return (changed, restoredOrderChanged)
            }
            let liveWindowIds = Set(windowStateStore.getWindows().map { $0.id.raw })
            syncThumbnailLifecycleToLiveWindowIds(liveWindowIds)

            let focusChanged = updateCachedFocusIfNeeded(frontmostWindowId: windowManager.lastFrontmostWindowId)
            let metricsRefreshed = refreshSystemMetricsIfNeeded(now: now)
            let shouldRender = changed || restoredOrderChanged || forceRender || focusChanged || metricsRefreshed

            if shouldRender {
                renderUI()
            }
            scheduleSwitcherPrewarm()

            // Update known state
            knownWindowIds = liveWindowIds
            updateWindowPositions(windows)

            // Window adjustment
            if config.adjustWindowsForTaskbar, AXIsProcessTrusted() {
                let suppressForScreenChange = Self.shouldSuppressWindowAdjustmentForScreenChange(
                    now: now,
                    lastScreenChangeAt: lastScreenParametersChangeAt
                )
                if suppressForScreenChange {
                    pendingAXWindowAdjustmentCheck = false
                }
                let movedTrigger = hasMovedWindows && (now - lastAdjustCheck > 0.80)
                let axEventTrigger = pendingAXWindowAdjustmentCheck && (now - lastAdjustCheck > 0.20)
                let shouldAdjust = !suppressForScreenChange
                    && !isDragging
                    && (hasNewWindows || movedTrigger || axEventTrigger || (now - lastAdjustCheck > 2.0))
                    // Avoid running heavy AX mutations while Spaces are transitioning.
                    && (now - lastSpaceChangeAt > 0.6)
                    && !windows.isEmpty
                if shouldAdjust {
                    PerformanceMonitor.shared.measureSegment(
                        "adjust_windows",
                        thresholdMs: 120.0
                    ) {
                        adjustWindows()
                    }
                    lastAdjustCheck = now
                    pendingAXWindowAdjustmentCheck = false
                }
            }

            maybeCheckMemory(now: now)
            recordPollResult(
                pollStart: pollStart,
                now: now,
                enumerated: true,
                reason: forceRender ? "force" : (isDragging ? "drag" : (eventDrivenDue ? "event" : "fallback")),
                windowCount: windows.count,
                forceRender: forceRender,
                isDragging: isDragging
            )
        }
    }

    private func recordPollResult(
        pollStart: CFTimeInterval,
        now: CFAbsoluteTime,
        enumerated: Bool,
        reason: String,
        windowCount: Int,
        forceRender: Bool,
        isDragging: Bool
    ) {
        let durationMs = (CACurrentMediaTime() - pollStart) * 1000.0
        recordPollDiagnostic(
            now: now,
            durationMs: durationMs,
            enumerated: enumerated,
            reason: reason,
            windowCount: windowCount,
            forceRender: forceRender,
            isDragging: isDragging
        )
        PerformanceMonitor.shared.recordPoll(
            durationMs: durationMs,
            enumerated: enumerated,
            reason: reason,
            windowCount: windowCount
        )
    }

    private func recordPollDiagnostic(
        now: CFAbsoluteTime,
        durationMs: Double,
        enumerated: Bool,
        reason: String,
        windowCount: Int,
        forceRender: Bool,
        isDragging: Bool
    ) {
        guard PerformanceMonitor.shared.isDevDiagnosticsEnabled else { return }

        let spaceAgeMs: Double = lastSpaceChangeAt > 0
            ? max(0, (now - lastSpaceChangeAt) * 1000.0)
            : -1
        let screenAgeMs: Double = lastScreenParametersChangeAt > 0
            ? max(0, (now - lastScreenParametersChangeAt) * 1000.0)
            : -1
        let adjustmentSuppressed = Self.shouldSuppressWindowAdjustmentForScreenChange(
            now: now,
            lastScreenChangeAt: lastScreenParametersChangeAt
        )
        PerformanceMonitor.shared.recordDiagnosticSnapshot(
            "poll_state"
        ) {
            let rss = MemoryMonitor.getRSSBytes()
            let thumbnails = thumbnailService.memorySummary()
            let axTrusted = AXIsProcessTrusted()
            return "reason=\(reason) duration_ms=\(Self.fmt2(durationMs)) enumerated=\(enumerated ? 1 : 0) force=\(forceRender ? 1 : 0) dragging=\(isDragging ? 1 : 0) windows=\(max(0, windowCount)) items=\(currentItems.count) displays=\(panelManager.allPanels.count) poll_interval_ms=\(Self.fmt2(currentPollInterval * 1000.0)) space_age_ms=\(Self.fmt2(spaceAgeMs)) screen_age_ms=\(Self.fmt2(screenAgeMs)) adjust_suppressed=\(adjustmentSuppressed ? 1 : 0) ax_active=\(isAXObserverActive ? 1 : 0) ax_trusted=\(axTrusted ? 1 : 0) metrics=\(config.systemIndicatorsEnabled ? 1 : 0) adjust=\(config.adjustWindowsForTaskbar ? 1 : 0) rss=\(rss) thumbnail_cache_entries=\(thumbnails.cacheEntries) thumbnail_cache_bytes=\(thumbnails.cacheBytes) thumbnail_last_good_entries=\(thumbnails.lastGoodEntries) thumbnail_last_good_bytes=\(thumbnails.lastGoodBytes) thumbnail_queued=\(thumbnails.queuedRequests) thumbnail_inflight=\(thumbnails.inFlightRequests)"
        }
    }

    private func maybeCheckMemory(now: CFAbsoluteTime) {
        guard now - lastMemoryCheck > 30 else { return }
        PerformanceMonitor.shared.measureSegment("memory_check", thresholdMs: 25.0) {
            MemoryMonitor.checkMemoryHealth(baseline: memoryBaseline)
        }
        lastMemoryCheck = now
    }

    @discardableResult
    private func refreshSystemMetricsIfNeeded(now: CFAbsoluteTime) -> Bool {
        guard systemMetricsProvider.needsRefresh(now: now, config: config) else { return false }
        PerformanceMonitor.shared.measureSegment("system_metrics_sample", thresholdMs: 25.0) {
            systemMetricsProvider.refreshIfNeeded(config: config, now: now)
        }
        return true
    }

    private static func fmt2(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Preferred persisted window order for the current live set.
    ///
    /// Primary source is `userState.windowOrder`. If it's empty (older state),
    /// derive a one-time bridge order from legacy `appOrder`, then migrate by
    /// saving `windowOrder` in the poll loop.
    private func preferredWindowOrderForCurrentWindows() -> [UInt32] {
        if !userState.windowOrder.isEmpty {
            return userState.windowOrder
        }
        guard !userState.appOrder.isEmpty else { return [] }

        let current = windowStateStore.getWindows()
        guard !current.isEmpty else { return [] }

        var seen = Set<UInt32>()
        var ordered: [UInt32] = []
        ordered.reserveCapacity(current.count)

        for bundleId in userState.appOrder {
            for w in current where w.bundleId.raw == bundleId {
                if seen.insert(w.id.raw).inserted {
                    ordered.append(w.id.raw)
                }
            }
        }
        for w in current where seen.insert(w.id.raw).inserted {
            ordered.append(w.id.raw)
        }
        return ordered
    }

    // MARK: - Render UI

    private func renderUI() {
        PerformanceMonitor.shared.measureSegment(
            "render_ui",
            thresholdMs: 80.0,
            details: "items=\(currentItems.count) displays=\(panelManager.allPanels.count)"
        ) {
            renderUIBody()
        }
    }

    private func renderUIBody() {
        let displayIds = panelManager.allDisplayIds

        let focusByDisplay: [CGDirectDisplayID: FocusInfo] = {
            // Prefer the cached tab group id derived from the current render pass,
            // so tab group chips expand correctly when focused windows are grouped.
            var focus = cachedFocusInfo
            if let wid = focus.windowId {
                focus.tabGroupId = userState.tabGroupId(containing: wid)
            }
            if focus == .none { return [:] }

            switch config.windowDisplayMode {
            case .allWindows:
                var map: [CGDirectDisplayID: FocusInfo] = [:]
                map.reserveCapacity(displayIds.count)
                for did in displayIds {
                    map[did] = focus
                }
                return map
            case .perDisplay:
                guard let did = cachedFocusDisplayId else { return [:] }
                return [did: focus]
            }
        }()

        // One-time migration: if we're switching to per-space pins and the user had
        // global pins in config.json, seed the active Space with those pins.
        if config.pinnedAppsScope == .perSpace,
           !didSeedPerSpacePinsFromConfig,
           userState.pinnedAppsBySpace.isEmpty,
           !config.pinnedApps.isEmpty {
            if let mainDisplayId = NSScreen.main?.displayId ?? displayIds.first,
               let spaceKey = cachedSpaceKeyByDisplay[mainDisplayId] {
                userState.pinnedAppsBySpace[spaceKey] = config.pinnedApps
                userState.save()
                didSeedPerSpacePinsFromConfig = true
            }
        }

        var renderConfig = config
        if config.windowTabGroupsEnabled {
            // Tab groups operate on individual windows, so disable app grouping for the render pass.
            renderConfig.groupByApp = false
        }
        rebuildWindowPresentationKeyIndex()
        let baseWindowItems = applyWindowPresentationOverrides(
            to: UIRenderer.render(from: windowStateStore, config: renderConfig)
        )
        let (windowItems, windowIdToGroupId) = config.windowTabGroupsEnabled
            ? applyTabGroups(windowItems: baseWindowItems, displayIds: displayIds)
            : (baseWindowItems, [:])
        var windowItemsWithExtras = windowItems

        // Track which custom items are user-defined (config.json) so plugin-provided items
        // can be treated as read-only in the UI (no edit/delete).
        let userCustomItemIds = Set(config.customItems.map(\.id))

        // Custom items (spacers/labels/links/folders). These are global by default and
        // appear on every display unless a future per-display option is added.
        let systemIndicatorPayload = systemMetricsProvider.payload(
            config: config,
            screenId: systemIndicatorScreenId(displayIds: displayIds),
            refresh: false
        )
        let systemIndicatorItems = Self.applyPreferredSystemIndicatorOrder(
            systemIndicatorPayload.items,
            preferred: userState.systemIndicatorOrder
        )
        let systemIndicatorsInFreeFlow = config.systemIndicatorPlacement == .free
        let allCustomItems = config.customItems + pluginCustomItems
        let placeSystemIndicatorsAfterPinnedApps =
            config.systemIndicatorPlacement == .trailing ||
            config.systemIndicatorPlacement == .rightCorner
        if (!systemIndicatorItems.isEmpty && (!placeSystemIndicatorsAfterPinnedApps || systemIndicatorsInFreeFlow)) || !allCustomItems.isEmpty {
            let custom: [TaskbarItem] = allCustomItems.map { item in
                switch item {
                case .spacer(let id, let width):
                    return .customSpacer(id: id, width: width, screenId: nil)
                case .text(let id, let text):
                    return .customText(id: id, text: text, screenId: nil)
                case .link(let id, let title, let url, let icon):
                    return .customLink(id: id, title: title, url: url, icon: icon, screenId: nil)
                case .folder(let id, let title, let path, let icon):
                    return .customFolder(id: id, title: title, path: path, icon: icon, screenId: nil)
                }
            }
            if systemIndicatorsInFreeFlow {
                windowItemsWithExtras = custom + systemIndicatorItems + windowItemsWithExtras
            } else if placeSystemIndicatorsAfterPinnedApps {
                windowItemsWithExtras = custom + windowItemsWithExtras
            } else {
                windowItemsWithExtras = systemIndicatorItems + custom + windowItemsWithExtras
            }
        }

        // Sidebar plugin tile zone (Dia-style).
        if config.tileZoneEnabled,
           config.sidebarModeEnabled,
           config.taskbarPosition.isVertical,
           !pluginTiles.isEmpty {
            let tiles: [TaskbarItem] = displayIds.flatMap { did in
                pluginTiles.map { tile in
                    .pluginTile(
                        id: tile.id,
                        providerId: tile.providerId,
                        title: tile.title,
                        icon: tile.icon,
                        visualState: tile.visualState,
                        screenId: UInt32(did)
                    )
                }
            }
            windowItemsWithExtras = tiles + windowItemsWithExtras
        }

        if config.launcherEnabled {
            // One launcher button per display, inserted before all other items.
            let launcherItems = displayIds.map { TaskbarItem.launcher(screenId: UInt32($0)) }
            windowItemsWithExtras = launcherItems + windowItemsWithExtras
        }

        // When collapsing windows into tab group chips, we still want pinned apps to
        // treat *all* underlying window bundle IDs as "open" (otherwise pinned items
        // can re-appear for apps whose windows are hidden inside a group).
        var openBundleIdsByDisplay: [CGDirectDisplayID: Set<String>]? = nil
        if config.windowTabGroupsEnabled {
            var map: [CGDirectDisplayID: Set<String>] = [:]
            map.reserveCapacity(displayIds.count)

            switch config.windowDisplayMode {
            case .perDisplay:
                for did in displayIds { map[did] = Set<String>() }
                for item in baseWindowItems {
                    guard let sid = item.screenId else { continue }
                    map[CGDirectDisplayID(sid), default: Set<String>()].insert(item.bundleId)
                }
            case .allWindows:
                let all = Set(baseWindowItems.map(\.bundleId))
                for did in displayIds { map[did] = all }
            }

            openBundleIdsByDisplay = map
        }

        // Resolve pinned apps for each panel display.
        var pinnedAppsByDisplay: [CGDirectDisplayID: [String]] = [:]
        pinnedAppsByDisplay.reserveCapacity(displayIds.count)

        for displayId in displayIds {
            switch config.pinnedAppsScope {
            case .global:
                pinnedAppsByDisplay[displayId] = config.pinnedApps
            case .perSpace:
                guard let spaceKey = cachedSpaceKeyByDisplay[displayId] else {
                    pinnedAppsByDisplay[displayId] = []
                    continue
                }
                pinnedAppsByDisplay[displayId] = userState.pinnedAppsBySpace[spaceKey] ?? []
            }
        }

        let composed = PinnedAppsComposer.compose(
            windowItems: windowItemsWithExtras,
            displayIds: displayIds,
            pinnedAppsByDisplay: pinnedAppsByDisplay,
            windowDisplayMode: config.windowDisplayMode,
            openBundleIdsByDisplay: openBundleIdsByDisplay
        )
        currentItems = {
            let items = placeSystemIndicatorsAfterPinnedApps && !systemIndicatorsInFreeFlow
                ? composed.items + systemIndicatorItems
                : composed.items
            guard systemIndicatorsInFreeFlow else { return items }
            return Self.applyPreferredItemOrder(items, preferred: userState.taskbarItemOrder)
        }()
        pinnedBundleIdsByDisplay = composed.pinnedBundleIdsByDisplay
        let itemBackgroundColorsByDisplay = presentationBackgroundColorsByDisplay(displayIds: displayIds)

        let expandedSidebarDisplays: Set<CGDirectDisplayID> = {
            guard config.sidebarModeEnabled, config.taskbarPosition.isVertical else { return [] }
            let explicit = Set(
                sidebarPresentationByDisplay.compactMap { displayId, presentation in
                    presentation == .expanded ? displayId : nil
                }
            )
            if !explicit.isEmpty { return explicit }
            if config.sidebarStateDefault == .expanded {
                return Set(displayIds)
            }
            return []
        }()

        panelManager.updateItems(
            currentItems,
            config: config,
            iconCache: iconCache,
            renderer: renderer,
            focusByDisplay: focusByDisplay,
            expandedSidebarDisplays: expandedSidebarDisplays,
            systemIndicatorVisuals: systemIndicatorPayload.visuals,
            itemBackgroundColorsByDisplay: itemBackgroundColorsByDisplay
        )

        let sharedBarViewSignature = Self.sharedBarViewDataSignature(
            userCustomItemIds: userCustomItemIds,
            windowTabGroupsEnabled: config.windowTabGroupsEnabled,
            tabGroups: userState.tabGroups,
            windowIdToGroupId: windowIdToGroupId
        )
        let activeDisplayIds = Set(panelManager.allPanels.map(\.displayId))
        lastBarViewDataSnapshotByDisplay = lastBarViewDataSnapshotByDisplay.filter { activeDisplayIds.contains($0.key) }
        lastBarViewIdentityByDisplay = lastBarViewIdentityByDisplay.filter { activeDisplayIds.contains($0.key) }

        // Wire up callbacks for each panel
        for panel in panelManager.allPanels {
            let displayId = panel.displayId
            let barViewID = ObjectIdentifier(panel.barView)
            let barViewSnapshot = Self.makeBarViewDataSnapshot(
                pinnedBundleIds: pinnedBundleIdsByDisplay[displayId] ?? [],
                sharedSignature: sharedBarViewSignature
            )
            let shouldSyncBarViewData = Self.shouldSynchronizeBarViewData(
                previous: lastBarViewDataSnapshotByDisplay[displayId],
                current: barViewSnapshot,
                isNewBarView: lastBarViewIdentityByDisplay[displayId] != barViewID
            )
            if shouldSyncBarViewData {
                panel.barView.pinnedBundleIds = pinnedBundleIdsByDisplay[displayId] ?? []
                panel.barView.userCustomItemIds = userCustomItemIds
                panel.barView.windowTabGroupsEnabled = config.windowTabGroupsEnabled
                panel.barView.tabGroups = userState.tabGroups
                panel.barView.windowIdToTabGroupId = windowIdToGroupId
                lastBarViewDataSnapshotByDisplay[displayId] = barViewSnapshot
            }
            lastBarViewIdentityByDisplay[displayId] = barViewID
            panel.barView.onItemClicked = { [weak self] index, button in
                self?.handleClick(displayId: displayId, index: index, button: button)
            }
            panel.barView.onItemReordered = { [weak self] from, to in
                self?.handleReorder(displayId: displayId, from: from, to: to)
            }
            panel.barView.onContextAction = { [weak self] index, action, payload in
                self?.handleContextAction(displayId: displayId, index: index, action: action, payload: payload)
            }
            panel.barView.onAppContextAction = { [weak self] action in
                self?.handleAppContextAction(action)
            }
            panel.barView.onHoverChanged = { [weak self] index in
                guard let self else { return }
                self.renderer.setHoveredItemIndex(index, for: displayId)
                let hoverRectChanged: Bool
                if let index = index,
                   index >= 0,
                   index < panel.barView.visualItemRects.count {
                    // Hover highlight should match what we draw.
                    let rect = panel.barView.visualItemRects[index]
                    hoverRectChanged = self.renderer.setHoverRect(rect, for: displayId)
                } else {
                    hoverRectChanged = self.renderer.setHoverRect(nil, for: displayId)
                }
                self.handlePreviewHover(displayId: displayId, hoverIndex: index, panel: panel)
                if hoverRectChanged {
                    self.panelManager.resumeDisplayLink(for: displayId)
                }
            }
            panel.barView.onCursorMoved = { [weak self] metalPoint in
                guard let self else { return }
                if let metalPoint {
                    self.renderer.setCursorPosition(
                        SIMD2<Float>(Float(metalPoint.x), Float(metalPoint.y)),
                        for: displayId
                    )
                } else {
                    self.renderer.setCursorPosition(nil, for: displayId)
                }
            }
            panel.barView.onDragStateChanged = { [weak self] state in
                guard let self else { return }
                MouseTracker.setDragging(state != nil)
                if let state = state {
                    if !self.renderer.hasDragAnimation(for: displayId) {
                        // First drag frame — start animation
                        self.renderer.startDrag(
                            sourceIndex: state.sourceIndex,
                            cursorX: state.cursorX,
                            cursorOffsetInItem: state.cursorOffsetInItem,
                            config: self.config,
                            displayId: displayId
                        )
                    } else {
                        // Subsequent frames — update cursor position
                        self.renderer.updateDragCursor(
                            cursorX: state.cursorX,
                            insertionIndex: state.insertionIndex,
                            displayId: displayId
                        )
                    }
                } else {
                    // Drop
                    self.renderer.endDrag(displayId: displayId)
                }
                self.panelManager.resumeDisplayLink(for: displayId)
            }

            panel.barView.onDragHoverChanged = { [weak self] hoverIndex in
                self?.handleDragHoverChanged(displayId: displayId, hoverIndex: hoverIndex)
            }

            panel.barView.onDragDropped = { [weak self] sourceIndex, dropIndex in
                self?.handleDragDropped(displayId: displayId, sourceIndex: sourceIndex, dropIndex: dropIndex) ?? false
            }

            panel.barView.onScrollStep = { [weak self] direction in
                self?.handleScroll(displayId: displayId, direction: direction)
            }
        }

        // Re-evaluate hover after callbacks are wired (fixes stale hover after
        // item removal, window close, drag reorder, etc.)
        for panel in panelManager.allPanels {
            panel.barView.invalidateHover()
        }

        // Update tab group overlays after layout + rects have been updated.
        if config.windowTabGroupsEnabled {
            for panel in panelManager.allPanels {
                let did = panel.displayId
                if let gid = expandedTabGroupIdByDisplay[did] {
                    let panelItems = itemsForDisplay(did)
                    if let idx = panelItems.firstIndex(where: { it in
                        if case .tabGroup(let id, _, _, _, _, _, _, _) = it { return id == gid }
                        return false
                    }) {
                        showTabGroupOverlay(displayId: did, groupId: gid, itemIndex: idx)
                    } else {
                        expandedTabGroupIdByDisplay.removeValue(forKey: did)
                        hideTabGroupOverlay(displayId: did)
                    }
                } else {
                    hideTabGroupOverlay(displayId: did)
                }
            }
        } else {
            hideAllTabGroupOverlays()
        }

        if !config.previewsEnabled {
            hideAllPreviews()
        }
        if !config.tileZoneEnabled || !config.sidebarModeEnabled || !config.taskbarPosition.isVertical {
            hidePluginCard()
        }
    }

    private func systemIndicatorScreenId(displayIds: [CGDirectDisplayID]) -> UInt32? {
        guard config.systemIndicatorDisplayScope == .selectedDisplay else { return nil }
        if let selected = config.systemIndicatorSelectedDisplayId,
           displayIds.contains(CGDirectDisplayID(selected)) {
            return selected
        }
        if let mainDisplayId = NSScreen.main?.displayId,
           displayIds.contains(mainDisplayId) {
            return UInt32(mainDisplayId)
        }
        return displayIds.first
    }

    /// Updates cached focus info. Returns true when focus changes in a way that should
    /// cause a redraw (tabbed taskbar widths and focused-item indicator depend on focus).
    private func updateCachedFocusIfNeeded(frontmostWindowId enumeratedFrontmostWindowId: UInt32?) -> Bool {
        let previousInfo = cachedFocusInfo
        let previousDisplay = cachedFocusDisplayId

        let windowId = enumeratedFrontmostWindowId ?? AccessibilityService.focusedWindowId()
        let tabGroupId = windowId.flatMap { userState.tabGroupId(containing: $0) }
        let focus = Self.makeFocusInfo(
            frontmostWindowId: windowId,
            windows: windowStateStore.windows,
            tabGroupId: tabGroupId
        )

        cachedFocusInfo = focus.info
        cachedFocusDisplayId = focus.displayId
        switcherMRUWindowIds = Self.updatedSwitcherMRUOrder(
            previous: switcherMRUWindowIds,
            focusedWindowId: focus.info.windowId,
            liveWindowIds: Set(windowStateStore.windows.keys.map(\.raw))
        )

        let changed = cachedFocusInfo != previousInfo || cachedFocusDisplayId != previousDisplay
        return changed
    }

    // MARK: - Click Handling

    private func ensureAccessibilityTrusted() -> Bool {
        guard AXIsProcessTrusted() else {
            AccessibilityService.requestPermission()
            return false
        }
        return true
    }

    private func handleClick(displayId: CGDirectDisplayID, index: Int, button: MouseButton) {
        let items = itemsForDisplay(displayId)
        guard index >= 0 && index < items.count else { return }
        let item = items[index]

        // Clicking any taskbar item should dismiss hover previews across displays.
        // This avoids stale preview overlays when focus jumps between monitors.
        hideAllPreviews()
        if case .pluginTile = item {
            // keep card toggled by the tile click itself
        } else {
            hidePluginCard()
        }

        // If a tab group is expanded on this display, collapse it when the user
        // clicks outside the group chip (configurable).
        if button == .left,
           config.windowTabGroupsEnabled,
           config.tabGroupCollapseOnOutsideClick,
           let expanded = expandedTabGroupIdByDisplay[displayId] {
            if case .tabGroup(let id, _, _, _, _, _, _, _) = item {
                if id != expanded {
                    expandedTabGroupIdByDisplay.removeValue(forKey: displayId)
                    hideTabGroupOverlay(displayId: displayId)
                }
            } else {
                expandedTabGroupIdByDisplay.removeValue(forKey: displayId)
                hideTabGroupOverlay(displayId: displayId)
            }
        }

        switch button {
        case .left:
            switch item {
            case .window(let id, let bundleId, _, _, let isHidden, let isMinimized, _):
                if isHidden {
                    AccessibilityService.unhideApp(bundleId: bundleId)
                } else if isMinimized {
                    guard ensureAccessibilityTrusted() else { return }
                    AccessibilityService.unminimizeWindow(windowId: id.raw)
                } else {
                    // Only treat this as a "second click" (hide/minimize) when we're confident
                    // the *window* item is actually the focused window. Otherwise, always focus
                    // the clicked window (prevents accidental hide when multiple windows exist).
                    let isFocused: Bool = {
                        let focusedId: UInt32? = {
                            if AXIsProcessTrusted(), let focused = AccessibilityService.focusedWindowId() {
                                return focused
                            }
                            return AccessibilityService.frontmostWindowIdForFrontmostApp()
                        }()

                        if let focusedId { return focusedId == id.raw }

                        // Last-resort fallback: only allow second-click behavior for single-window apps.
                        let isFrontmost = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId)
                        guard isFrontmost else { return false }

                        let sameBundleWindowCount = items.reduce(into: 0) { acc, it in
                            if case .window(_, let bid, _, _, _, _, _) = it, bid == bundleId { acc += 1 }
                        }
                        return sameBundleWindowCount <= 1
                    }()

                    if isFocused {
                        switch config.secondClickAction {
                        case .hide:
                            AccessibilityService.hideApp(bundleId: bundleId)
                        case .minimize:
                            guard ensureAccessibilityTrusted() else { return }
                            AccessibilityService.minimizeWindow(windowId: id.raw)
                        case .none:
                            return
                        }
                    } else {
                        guard ensureAccessibilityTrusted() else { return }
                        AccessibilityService.focusWindow(windowId: id.raw)
                    }
                }
            case .appGroup(let bundleId, _, _, let windows, let isHidden, let isMinimized, _):
                if isHidden {
                    AccessibilityService.unhideApp(bundleId: bundleId)
                } else if isMinimized {
                    guard ensureAccessibilityTrusted() else { return }
                    if let first = windows.first {
                        AccessibilityService.unminimizeWindow(windowId: first.raw)
                        AccessibilityService.focusWindow(windowId: first.raw)
                    }
                } else if let first = windows.first {
                    let focusedWindowId: UInt32? = AccessibilityService.focusedWindowId()
                    let isFocused: Bool = {
                        if let focusedWindowId {
                            return windows.contains(where: { $0.raw == focusedWindowId })
                        }
                        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
                    }()

                    if isFocused {
                        switch config.secondClickAction {
                        case .hide:
                            AccessibilityService.hideApp(bundleId: bundleId)
                        case .minimize:
                            guard ensureAccessibilityTrusted() else { return }
                            let target = focusedWindowId.flatMap { wid in
                                windows.first(where: { $0.raw == wid })?.raw
                            } ?? first.raw
                            AccessibilityService.minimizeWindow(windowId: target)
                        case .none:
                            return
                        }
                    } else {
                        guard ensureAccessibilityTrusted() else { return }
                        AccessibilityService.focusWindow(windowId: first.raw)
                    }
                }
            case .pinnedApp(let bundleId, _):
                AccessibilityService.launchApp(bundleId: bundleId)
            case .launcher:
                handleLauncherClick()
            case .pluginTile(let id, let providerId, let title, _, _, _):
                togglePluginCard(displayId: displayId, itemIndex: index, tileId: id, providerId: providerId, title: title)
            case .tabGroup(let id, _, _, _, _, _, _, _):
                toggleTabGroupExpanded(displayId: displayId, groupId: id, itemIndex: index)
            case .customSpacer:
                break
            case .customText:
                break
            case .customLink(_, _, let url, _, _):
                guard let u = URL(string: url) else { return }
                NSWorkspace.shared.open(u)
            case .customFolder(_, _, let path, _, _):
                let u = URL(fileURLWithPath: path, isDirectory: true)
                NSWorkspace.shared.open(u)
            }

        case .middle:
            if case .window(let id, _, _, _, _, _, _) = item {
                guard ensureAccessibilityTrusted() else { return }
                AccessibilityService.closeWindow(windowId: id.raw)
            }

        case .right:
            break // Handled by context menu
        }

        if button != .right {
            markWindowRefreshNeeded(invalidateCaches: true)
            scheduleWorkspaceRefresh()
        }
    }

    // MARK: - Reorder Handling

    private func handleReorder(displayId: CGDirectDisplayID, from: Int, to: Int) {
        // Cancel any in-flight drag animation before rebuilding state
        renderer.cancelDrag(displayId: displayId)
        let panelItems = itemsForDisplay(displayId)
        let systemIndicatorOrder = Self.systemIndicatorMetricOrderAfterReorder(
            items: panelItems,
            from: from,
            to: to
        )
        if config.systemIndicatorPlacement != .free, let systemIndicatorOrder {
            userState.updateSystemIndicatorOrder(systemIndicatorOrder)
            renderUI()
            return
        }

        guard let plan = Self.visibleReorderPlan(
            items: panelItems,
            from: from,
            to: to,
            tabGroups: userState.tabGroups
        ) else {
            renderUI()
            return
        }

        if let systemIndicatorOrder {
            userState.updateSystemIndicatorOrder(systemIndicatorOrder)
        }
        if !plan.windowOrder.isEmpty {
            _ = windowStateStore.applyPreferredWindowOrder(plan.windowOrder)
            userState.updateWindowOrder(windowStateStore.getWindows().map(\.id.raw))
        }
        if !plan.appOrder.isEmpty {
            userState.updateOrder(plan.appOrder)
        }
        applyPinnedReorder(plan.pinnedOrder, displayId: displayId)
        if config.systemIndicatorPlacement == .free, !plan.itemOrder.isEmpty {
            userState.updateTaskbarItemOrder(plan.itemOrder)
        }
        renderUI()
    }

    nonisolated static func visibleReorderPlan(
        items: [TaskbarItem],
        from: Int,
        to: Int,
        tabGroups: [TabGroup]
    ) -> VisibleReorderPlan? {
        guard from >= 0, from < items.count, to >= 0, to <= items.count else { return nil }
        guard to != from, to != from + 1 else { return nil }

        var reordered = items
        let moved = reordered.remove(at: from)
        let adjustedInsertionIndex = to > from ? to - 1 : to
        reordered.insert(moved, at: min(adjustedInsertionIndex, reordered.count))

        let groupsById = Dictionary(uniqueKeysWithValues: tabGroups.map { ($0.id, $0.windowIds) })
        return VisibleReorderPlan(
            windowOrder: reordered.flatMap { representedWindowIds(for: $0, tabGroupsById: groupsById) },
            appOrder: deduped(reordered.compactMap(reorderBundleId(for:))),
            pinnedOrder: deduped(reordered.compactMap { item in
                if case .pinnedApp(let bundleId, _) = item { return bundleId }
                return nil
            }),
            itemOrder: deduped(reordered.compactMap(reorderItemIdentity(for:)))
        )
    }

    private nonisolated static func representedWindowIds(
        for item: TaskbarItem,
        tabGroupsById: [String: [UInt32]]
    ) -> [UInt32] {
        switch item {
        case .window(let id, _, _, _, _, _, _):
            return [id.raw]
        case .appGroup(_, _, _, let windows, _, _, _):
            return windows.map(\.raw)
        case .tabGroup(let id, _, _, _, _, _, _, _):
            return tabGroupsById[id] ?? []
        case .pinnedApp, .launcher, .pluginTile, .customSpacer, .customText, .customLink, .customFolder:
            return []
        }
    }

    private nonisolated static func reorderBundleId(for item: TaskbarItem) -> String? {
        switch item {
        case .window(_, let bundleId, _, _, _, _, _),
             .appGroup(let bundleId, _, _, _, _, _, _),
             .pinnedApp(let bundleId, _),
             .tabGroup(_, let bundleId, _, _, _, _, _, _):
            return bundleId
        case .launcher, .pluginTile, .customSpacer, .customText, .customLink, .customFolder:
            return nil
        }
    }

    private nonisolated static func reorderItemIdentity(for item: TaskbarItem) -> String? {
        switch item {
        case .window(let id, _, _, _, _, _, _):
            return "window:\(id.raw)"
        case .appGroup(let bundleId, _, _, _, _, _, let screenId):
            return "app-group:\(screenId):\(bundleId)"
        case .pinnedApp(let bundleId, let screenId):
            return "pinned:\(screenId):\(bundleId)"
        case .launcher(let screenId):
            return "launcher:\(screenId)"
        case .pluginTile(let id, _, _, _, _, let screenId):
            return "plugin:\(screenId):\(id)"
        case .tabGroup(let id, _, _, _, _, _, _, let screenId):
            return "tab-group:\(screenId):\(id)"
        case .customSpacer(let id, _, let screenId):
            return "custom-spacer:\(screenId.map(String.init) ?? "all"):\(id)"
        case .customText(let id, _, let screenId):
            if id.hasPrefix("system.") {
                return "system:\(screenId.map(String.init) ?? "all"):\(id)"
            }
            return "custom-text:\(screenId.map(String.init) ?? "all"):\(id)"
        case .customLink(let id, _, _, _, let screenId):
            return "custom-link:\(screenId.map(String.init) ?? "all"):\(id)"
        case .customFolder(let id, _, _, _, let screenId):
            return "custom-folder:\(screenId.map(String.init) ?? "all"):\(id)"
        }
    }

    nonisolated static func applyPreferredSystemIndicatorOrder(
        _ current: [TaskbarItem],
        preferred: [String]
    ) -> [TaskbarItem] {
        guard !current.isEmpty, !preferred.isEmpty else { return current }

        var rankByMetric: [String: Int] = [:]
        rankByMetric.reserveCapacity(preferred.count)
        for (rank, metricId) in preferred.enumerated() where rankByMetric[metricId] == nil {
            rankByMetric[metricId] = rank
        }

        return current.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = systemIndicatorMetricId(for: lhs.element).flatMap { rankByMetric[$0] } ?? Int.max
                let rhsRank = systemIndicatorMetricId(for: rhs.element).flatMap { rankByMetric[$0] } ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    nonisolated static func systemIndicatorMetricOrderAfterReorder(
        items: [TaskbarItem],
        from: Int,
        to: Int
    ) -> [String]? {
        guard from >= 0, from < items.count, to >= 0, to <= items.count else { return nil }
        guard to != from, to != from + 1 else { return nil }
        guard systemIndicatorMetricId(for: items[from]) != nil else { return nil }

        let indicatorIndexes = items.indices.filter { systemIndicatorMetricId(for: items[$0]) != nil }
        guard let first = indicatorIndexes.first, let last = indicatorIndexes.last else { return nil }
        guard from >= first, from <= last, to >= first, to <= last + 1 else { return nil }
        guard (first...last).allSatisfy({ systemIndicatorMetricId(for: items[$0]) != nil }) else { return nil }

        var reordered = items
        let moved = reordered.remove(at: from)
        let adjustedInsertionIndex = to > from ? to - 1 : to
        reordered.insert(moved, at: min(adjustedInsertionIndex, reordered.count))

        let order = deduped(reordered.compactMap(systemIndicatorMetricId(for:)))
        return order.isEmpty ? nil : order
    }

    nonisolated static func systemIndicatorMetricId(for item: TaskbarItem) -> String? {
        if case .customText(let id, _, _) = item, id.hasPrefix("system.") {
            return id
        }
        return nil
    }

    private nonisolated static func deduped<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private nonisolated static func preferredStringOrder(current: [String], preferred: [String]) -> [String] {
        guard !current.isEmpty, !preferred.isEmpty else { return current }
        let currentSet = Set(current)
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(current.count)

        for value in preferred where currentSet.contains(value) && seen.insert(value).inserted {
            result.append(value)
        }
        for value in current where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private nonisolated static func applyPreferredItemOrder(
        _ current: [TaskbarItem],
        preferred: [String]
    ) -> [TaskbarItem] {
        guard !current.isEmpty, !preferred.isEmpty else { return current }

        var rankByIdentity: [String: Int] = [:]
        rankByIdentity.reserveCapacity(preferred.count)
        for (rank, identity) in preferred.enumerated() where rankByIdentity[identity] == nil {
            rankByIdentity[identity] = rank
        }

        return current.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = reorderItemIdentity(for: lhs.element).flatMap { rankByIdentity[$0] } ?? Int.max
                let rhsRank = reorderItemIdentity(for: rhs.element).flatMap { rankByIdentity[$0] } ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func applyPinnedReorder(_ pinnedOrder: [String], displayId: CGDirectDisplayID) {
        guard !pinnedOrder.isEmpty else { return }

        switch config.pinnedAppsScope {
        case .global:
            let reordered = Self.preferredStringOrder(current: config.pinnedApps, preferred: pinnedOrder)
            guard reordered != config.pinnedApps else { return }
            config.pinnedApps = reordered
            config.save()

        case .perSpace:
            guard let spaceKey = cachedSpaceKeyByDisplay[displayId] else { return }
            let current = userState.pinnedAppsBySpace[spaceKey] ?? []
            let reordered = Self.preferredStringOrder(current: current, preferred: pinnedOrder)
            guard reordered != current else { return }
            userState.pinnedAppsBySpace[spaceKey] = reordered
            userState.save()
        }
    }

    // MARK: - Context Action Handling

    private func handleAppContextAction(_ action: AppContextAction) {
        switch action {
        case .openPreferences:
            onOpenPreferences?()
        case .reloadConfig:
            reloadConfig()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func rebuildWindowPresentationKeyIndex() {
        let windows = windowStateStore.getWindows()
        var map: [UInt32: String] = [:]
        map.reserveCapacity(windows.count)
        for window in windows {
            map[window.id.raw] = WindowPresentationKey.make(
                bundleId: window.bundleId.raw,
                title: window.title,
                appName: window.appName
            )
        }
        windowPresentationKeyByWindowId = map
    }

    private func applyWindowPresentationOverrides(to items: [TaskbarItem]) -> [TaskbarItem] {
        items.map { item in
            guard case .window(let id, let bundleId, _, let appName, let isHidden, let isMinimized, let screenId) = item,
                  let key = windowPresentationKeyByWindowId[id.raw],
                  let override = userState.presentationOverride(for: key),
                  let displayTitle = override.title,
                  !displayTitle.isEmpty else {
                return item
            }
            return .window(
                id: id,
                bundleId: bundleId,
                title: displayTitle,
                appName: appName,
                isHidden: isHidden,
                isMinimized: isMinimized,
                screenId: screenId
            )
        }
    }

    private func presentationBackgroundColorsByDisplay(
        displayIds: [CGDirectDisplayID]
    ) -> [CGDirectDisplayID: [Int: String]] {
        var result: [CGDirectDisplayID: [Int: String]] = [:]
        result.reserveCapacity(displayIds.count)

        for displayId in displayIds {
            let items = itemsForDisplay(displayId)
            var colors: [Int: String] = [:]
            colors.reserveCapacity(items.count)

            for (index, item) in items.enumerated() {
                let hex: String?
                switch item {
                case .window(let id, _, _, _, _, _, _):
                    if let key = windowPresentationKeyByWindowId[id.raw] {
                        hex = userState.presentationOverride(for: key)?.colorHex
                    } else {
                        hex = nil
                    }
                case .tabGroup(let groupId, _, _, _, _, _, _, _):
                    hex = userState.tabGroup(withId: groupId)?.colorHex
                default:
                    hex = nil
                }

                if let normalized = PresentationColorPalette.normalizedHex(hex) {
                    colors[index] = normalized
                }
            }

            if !colors.isEmpty {
                result[displayId] = colors
            }
        }

        return result
    }

    private func handleContextAction(displayId: CGDirectDisplayID, index: Int, action: ContextAction, payload: String?) {
        let items = itemsForDisplay(displayId)
        guard index >= 0 && index < items.count else { return }
        let item = items[index]
        let bundleId = item.bundleId

        switch action {
        case .close:
            if case .window(let id, _, _, _, _, _, _) = item {
                guard ensureAccessibilityTrusted() else { return }
                AccessibilityService.closeWindow(windowId: id.raw)
            }
        case .pin:
            switch config.pinnedAppsScope {
            case .global:
                if !config.pinnedApps.contains(bundleId) {
                    config.pinnedApps.append(bundleId)
                }
                config.save()
            case .perSpace:
                if let spaceKey = cachedSpaceKeyByDisplay[displayId] {
                    userState.pin(bundleId: bundleId, spaceKey: spaceKey)
                } else {
                    refreshSpaceKeyCache(displayIds: [displayId]) { [weak self] in
                        guard let self,
                              let spaceKey = self.cachedSpaceKeyByDisplay[displayId] else { return }
                        self.userState.pin(bundleId: bundleId, spaceKey: spaceKey)
                        self.renderUI()
                    }
                    return
                }
            }
            renderUI()
        case .unpin:
            switch config.pinnedAppsScope {
            case .global:
                config.pinnedApps.removeAll { $0 == bundleId }
                config.save()
            case .perSpace:
                if let spaceKey = cachedSpaceKeyByDisplay[displayId] {
                    userState.unpin(bundleId: bundleId, spaceKey: spaceKey)
                } else {
                    refreshSpaceKeyCache(displayIds: [displayId]) { [weak self] in
                        guard let self,
                              let spaceKey = self.cachedSpaceKeyByDisplay[displayId] else { return }
                        self.userState.unpin(bundleId: bundleId, spaceKey: spaceKey)
                        self.renderUI()
                    }
                    return
                }
            }
            renderUI()
        case .blacklist:
            if !config.blacklistedApps.contains(bundleId) {
                config.blacklistedApps.append(bundleId)
                config.save()
            }
            renderUI()

        case .renameWindow:
            guard case .window(let id, _, let title, let appName, _, _, _) = item else { return }
            renameWindowFlow(windowId: id.raw, fallbackTitle: title, fallbackAppName: appName)

        case .setWindowColor:
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            guard let key = windowPresentationKeyByWindowId[id.raw],
                  let colorHex = PresentationColorPalette.normalizedHex(payload) else { return }
            userState.setWindowColorOverride(key: key, colorHex: colorHex)
            renderUI()

        case .resetWindowTitle:
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            guard let key = windowPresentationKeyByWindowId[id.raw] else { return }
            userState.setWindowTitleOverride(key: key, title: nil)
            renderUI()

        case .resetWindowColor:
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            guard let key = windowPresentationKeyByWindowId[id.raw] else { return }
            userState.setWindowColorOverride(key: key, colorHex: nil)
            renderUI()

        case .createTabGroup:
            guard config.windowTabGroupsEnabled else { return }
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            createTabGroupFlow(displayId: displayId, windowId: id.raw)

        case .addToTabGroup:
            guard config.windowTabGroupsEnabled else { return }
            guard let groupId = payload, !groupId.isEmpty else { return }
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            userState.addWindowToTabGroup(windowId: id.raw, groupId: groupId)
            renderUI()

        case .removeFromTabGroup:
            guard config.windowTabGroupsEnabled else { return }
            guard let groupId = payload, !groupId.isEmpty else { return }
            guard case .window(let id, _, _, _, _, _, _) = item else { return }
            userState.removeWindowFromTabGroup(windowId: id.raw, groupId: groupId)
            renderUI()

        case .renameTabGroup:
            guard config.windowTabGroupsEnabled else { return }
            guard let groupId = payload, !groupId.isEmpty else { return }
            renameTabGroupFlow(groupId: groupId)

        case .deleteTabGroup:
            guard config.windowTabGroupsEnabled else { return }
            guard let groupId = payload, !groupId.isEmpty else { return }
            userState.deleteTabGroup(id: groupId)
            expandedTabGroupIdByDisplay.removeValue(forKey: displayId)
            renderUI()

        case .setTabGroupColor:
            guard config.windowTabGroupsEnabled else { return }
            guard case .tabGroup(let groupId, _, _, _, _, _, _, _) = item else { return }
            userState.setTabGroupColor(id: groupId, colorHex: PresentationColorPalette.normalizedHex(payload))
            renderUI()

        case .openCustomItem:
            // Prefer opening from the item itself so plugin-provided custom items work too.
            switch item {
            case .customLink(_, _, let url, _, _):
                guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                NSWorkspace.shared.open(u)
            case .customFolder(_, _, let path, _, _):
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                NSWorkspace.shared.open(URL(fileURLWithPath: trimmed, isDirectory: true))
            default:
                guard let id = payload, !id.isEmpty else { return }
                openCustomItem(id: id)
            }

        case .editCustomItem:
            guard let id = payload, !id.isEmpty else { return }
            editCustomItemFlow(id: id)

        case .deleteCustomItem:
            guard let id = payload, !id.isEmpty else { return }
            config.customItems.removeAll { $0.id == id }
            config.save()
            renderUI()
        }

        markWindowRefreshNeeded(invalidateCaches: true)
        scheduleWorkspaceRefresh()
    }

    // MARK: - Window Tab Groups

    /// Collapse window items into tab group chips (per display), hiding member windows.
    private func applyTabGroups(
        windowItems: [TaskbarItem],
        displayIds: [CGDirectDisplayID]
    ) -> (items: [TaskbarItem], windowIdToGroupId: [UInt32: String]) {
        guard !userState.tabGroups.isEmpty else {
            return (windowItems, [:])
        }

        // Build membership map: windowId -> groupId. A window can only belong to one group.
        var groupIdByWindowId: [UInt32: String] = [:]
        groupIdByWindowId.reserveCapacity(userState.tabGroups.reduce(0) { $0 + $1.windowIds.count })
        for group in userState.tabGroups {
            for wid in group.windowIds {
                groupIdByWindowId[wid] = group.id
            }
        }

        struct GroupStats {
            var count: Int
            var repBundleId: String
            var allHidden: Bool
            var allDimmed: Bool
        }

        // Compute per-display stats from the *currently visible* window items (after hidden filtering).
        var statsByDisplay: [CGDirectDisplayID: [String: GroupStats]] = [:]
        statsByDisplay.reserveCapacity(displayIds.count)

        for item in windowItems {
            guard case .window(let id, let bundleId, _, _, let isHidden, let isMinimized, let screenId) = item else { continue }
            guard let groupId = groupIdByWindowId[id.raw] else { continue }

            let did = CGDirectDisplayID(screenId)
            var byGroup = statsByDisplay[did] ?? [:]
            var stats = byGroup[groupId] ?? GroupStats(count: 0, repBundleId: bundleId, allHidden: true, allDimmed: true)

            stats.count += 1
            if stats.count == 1 {
                stats.repBundleId = bundleId
            }
            stats.allHidden = stats.allHidden && isHidden
            stats.allDimmed = stats.allDimmed && (isHidden || isMinimized)

            byGroup[groupId] = stats
            statsByDisplay[did] = byGroup
        }

        var insertedByDisplay: [CGDirectDisplayID: Set<String>] = [:]
        insertedByDisplay.reserveCapacity(displayIds.count)
        for did in displayIds {
            insertedByDisplay[did] = Set<String>()
        }

        var out: [TaskbarItem] = []
        out.reserveCapacity(windowItems.count)

        for item in windowItems {
            switch item {
            case .window(let id, _, _, _, _, _, let screenId):
                if let groupId = groupIdByWindowId[id.raw] {
                    let did = CGDirectDisplayID(screenId)
                    guard let stats = statsByDisplay[did]?[groupId], stats.count > 0 else {
                        // Group has no visible members on this display; don't show chip here.
                        break
                    }
                    if insertedByDisplay[did]?.contains(groupId) != true {
                        insertedByDisplay[did, default: []].insert(groupId)
                        if let group = userState.tabGroup(withId: groupId) {
                            let allMinimized = stats.allDimmed && !stats.allHidden
                            out.append(.tabGroup(
                                id: group.id,
                                representativeBundleId: stats.repBundleId,
                                name: group.name,
                                emoji: group.emoji,
                                windowCount: stats.count,
                                isHidden: stats.allHidden,
                                isMinimized: allMinimized,
                                screenId: UInt32(did)
                            ))
                        }
                    }
                    // Hide member windows from the bar.
                    break
                } else {
                    out.append(item)
                }

            default:
                out.append(item)
            }
        }

        // If a group is expanded but has no visible chip on this display, collapse it.
        var collapse: [CGDirectDisplayID] = []
        collapse.reserveCapacity(expandedTabGroupIdByDisplay.count)
        for (did, expandedId) in expandedTabGroupIdByDisplay {
            if insertedByDisplay[did]?.contains(expandedId) != true {
                collapse.append(did)
            }
        }
        for did in collapse {
            expandedTabGroupIdByDisplay.removeValue(forKey: did)
            hideTabGroupOverlay(displayId: did)
        }

        return (out, groupIdByWindowId)
    }

    private func toggleTabGroupExpanded(displayId: CGDirectDisplayID, groupId: String, itemIndex: Int) {
        if expandedTabGroupIdByDisplay[displayId] == groupId {
            expandedTabGroupIdByDisplay.removeValue(forKey: displayId)
            hideTabGroupOverlay(displayId: displayId)
        } else {
            expandedTabGroupIdByDisplay[displayId] = groupId
            showTabGroupOverlay(displayId: displayId, groupId: groupId, itemIndex: itemIndex)
        }
    }

    private func handleDragHoverChanged(displayId: CGDirectDisplayID, hoverIndex: Int?) {
        guard config.windowTabGroupsEnabled else { return }

        // Resolve hovered tab group id, if any.
        let hoveredGroupId: String?
        if let hoverIndex {
            let items = itemsForDisplay(displayId)
            if hoverIndex >= 0, hoverIndex < items.count,
               case .tabGroup(let groupId, _, _, _, _, _, _, _) = items[hoverIndex] {
                hoveredGroupId = groupId
            } else {
                hoveredGroupId = nil
            }
        } else {
            hoveredGroupId = nil
        }

        if let previous = tabGroupHoverCandidateGroupIdByDisplay[displayId], previous == hoveredGroupId {
            return
        }

        // Cancel any pending expand.
        tabGroupHoverWorkItemByDisplay[displayId]?.cancel()
        tabGroupHoverWorkItemByDisplay.removeValue(forKey: displayId)

        if let hoveredGroupId {
            tabGroupHoverCandidateGroupIdByDisplay[displayId] = hoveredGroupId

            let delay = TimeInterval(config.tabGroupHoverExpandDelayMs) / 1000.0
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.tabGroupHoverCandidateGroupIdByDisplay[displayId] == hoveredGroupId else { return }

                self.expandedTabGroupIdByDisplay[displayId] = hoveredGroupId
                let panelItems = self.itemsForDisplay(displayId)
                if let idx = panelItems.firstIndex(where: { it in
                    if case .tabGroup(let id, _, _, _, _, _, _, _) = it { return id == hoveredGroupId }
                    return false
                }) {
                    self.showTabGroupOverlay(displayId: displayId, groupId: hoveredGroupId, itemIndex: idx)
                }
            }

            tabGroupHoverWorkItemByDisplay[displayId] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            tabGroupHoverCandidateGroupIdByDisplay.removeValue(forKey: displayId)
        }
    }

    private func handleDragDropped(displayId: CGDirectDisplayID, sourceIndex: Int, dropIndex: Int?) -> Bool {
        guard config.windowTabGroupsEnabled else { return false }
        guard let dropIndex else { return false }

        let items = itemsForDisplay(displayId)
        guard sourceIndex >= 0, sourceIndex < items.count else { return false }
        guard dropIndex >= 0, dropIndex < items.count else { return false }

        guard case .window(let windowId, _, _, _, _, _, _) = items[sourceIndex] else { return false }
        guard case .tabGroup(let groupId, _, _, _, _, _, _, _) = items[dropIndex] else { return false }

        // Stop any pending hover expand for this display.
        tabGroupHoverWorkItemByDisplay[displayId]?.cancel()
        tabGroupHoverWorkItemByDisplay.removeValue(forKey: displayId)
        tabGroupHoverCandidateGroupIdByDisplay.removeValue(forKey: displayId)

        userState.addWindowToTabGroup(windowId: windowId.raw, groupId: groupId)
        expandedTabGroupIdByDisplay[displayId] = groupId
        renderUI()
        return true
    }

    private func showTabGroupOverlay(displayId: CGDirectDisplayID, groupId: String, itemIndex: Int) {
        guard let panel = panelManager.panel(for: displayId) else { return }
        guard let anchor = panel.barView.screenRectForVisualItem(at: itemIndex) else { return }
        guard let group = userState.tabGroup(withId: groupId) else { return }

        // Visible windows for this display + group.
        var windows = windowStateStore.getWindows().filter { group.windowIds.contains($0.id.raw) }
        if config.windowDisplayMode == .perDisplay {
            windows = windows.filter { $0.monitorId.raw == displayId }
        }
        if !config.showHiddenApps {
            windows = windows.filter { !$0.isHidden }
        }
        if !config.showMinimizedWindows {
            windows = windows.filter { !$0.isMinimized }
        }

        guard !windows.isEmpty else {
            expandedTabGroupIdByDisplay.removeValue(forKey: displayId)
            hideTabGroupOverlay(displayId: displayId)
            return
        }

        let overlay: TabGroupOverlayPanel
        if let existing = tabGroupOverlayByDisplay[displayId], existing.tabGroupId == groupId {
            overlay = existing
        } else {
            tabGroupOverlayByDisplay[displayId]?.hide()

            overlay = TabGroupOverlayPanel(groupId: groupId, theme: panel.theme, glassStyle: config.glassStyle)
            overlay.onWindowClicked = { [weak self] wid in
                guard let self else { return }

                if let info = self.windowStateStore.getWindows().first(where: { $0.id.raw == wid }) {
                    if info.isHidden {
                        AccessibilityService.unhideApp(bundleId: info.bundleId.raw)
                        return
                    }
                    if info.isMinimized {
                        guard self.ensureAccessibilityTrusted() else { return }
                        AccessibilityService.unminimizeWindow(windowId: wid)
                        return
                    }
                }

                guard self.ensureAccessibilityTrusted() else { return }
                AccessibilityService.focusWindow(windowId: wid)
            }
            tabGroupOverlayByDisplay[displayId] = overlay
        }

        overlay.updateWindows(windows, iconCache: iconCache)
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        overlay.show(anchorRect: anchor, on: screen, position: panel.position)
    }

    private func hideTabGroupOverlay(displayId: CGDirectDisplayID) {
        tabGroupOverlayByDisplay[displayId]?.hide()
    }

    private func hideAllTabGroupOverlays() {
        for (_, overlay) in tabGroupOverlayByDisplay {
            overlay.hide()
        }
        tabGroupOverlayByDisplay.removeAll()
        expandedTabGroupIdByDisplay.removeAll()

        for (_, work) in tabGroupHoverWorkItemByDisplay {
            work.cancel()
        }
        tabGroupHoverWorkItemByDisplay.removeAll()
        tabGroupHoverCandidateGroupIdByDisplay.removeAll()
    }

    private func renameWindowFlow(windowId: UInt32, fallbackTitle: String, fallbackAppName: String) {
        guard let key = windowPresentationKeyByWindowId[windowId] else { return }

        let originalTitle: String = {
            if let window = windowStateStore.getWindows().first(where: { $0.id.raw == windowId }) {
                return window.title.isEmpty ? window.appName : window.title
            }
            return fallbackTitle.isEmpty ? fallbackAppName : fallbackTitle
        }()
        let currentTitle = userState.presentationOverride(for: key)?.title ?? originalTitle

        let alert = NSAlert()
        alert.messageText = "Rename Window"
        alert.informativeText = "This changes the label shown in LiquidBar only."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        nameField.stringValue = currentTitle
        nameField.placeholderString = originalTitle
        alert.accessoryView = nameField

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == originalTitle {
            userState.setWindowTitleOverride(key: key, title: nil)
        } else {
            userState.setWindowTitleOverride(key: key, title: name)
        }
        renderUI()
    }

    private func createTabGroupFlow(displayId: CGDirectDisplayID, windowId: UInt32) {
        let alert = NSAlert()
        alert.messageText = "Create Tab Group"
        alert.informativeText = "Group arbitrary windows into a named chip."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        nameField.placeholderString = "Name (e.g. Work)"

        let emojiField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        emojiField.placeholderString = "Emoji (optional)"

        let stack = NSStackView(views: [nameField, emojiField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        alert.accessoryView = stack

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let emoji = emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let emojiValue = emoji.isEmpty ? nil : emoji

        let group = userState.createTabGroup(name: name, emoji: emojiValue, colorHex: nil, withWindowId: windowId)
        expandedTabGroupIdByDisplay[displayId] = group.id
        renderUI()
    }

    private func renameTabGroupFlow(groupId: String) {
        guard let group = userState.tabGroup(withId: groupId) else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Tab Group"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        nameField.stringValue = group.name

        let emojiField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        emojiField.placeholderString = "Emoji (optional)"
        emojiField.stringValue = group.emoji ?? ""

        let stack = NSStackView(views: [nameField, emojiField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        alert.accessoryView = stack

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let emoji = emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let emojiValue = emoji.isEmpty ? nil : emoji

        userState.renameTabGroup(id: groupId, name: name, emoji: emojiValue, colorHex: group.colorHex)
        renderUI()
    }

    // MARK: - Launcher

    private func handleLauncherClick() {
        switch LauncherActionResolver.target(for: config) {
        case .application(let bundleId):
            AccessibilityService.launchApp(bundleId: bundleId)
        case .url(let raw):
            guard let url = URL(string: raw) else { return }
            NSWorkspace.shared.open(url)
        case .none:
            return
        }
    }

    // MARK: - Native Switcher

    private func configureSwitcherHotkey() {
        guard config.switcherEnabled else {
            hotkeyMonitor?.unregister()
            switcherSession.unregister()
            hideSwitcher(commitSelection: false)
            return
        }

        let hotkeyRaw = self.config.switcherHotkey
        guard let shortcut = HotkeyShortcut.parse(hotkeyRaw) else {
            Log.ui.error("Invalid switcher hotkey format: \(hotkeyRaw, privacy: .public)")
            hotkeyMonitor?.unregister()
            switcherSession.unregister()
            return
        }

        switcherSession.configure(usesReleaseCommit: shortcut.requiresCGEventTap)

        if hotkeyMonitor == nil {
            hotkeyMonitor = HotkeyMonitor(shouldHandleEventTapPress: { [weak self] in
                guard let self else { return false }
                return MainActor.assumeIsolated {
                    self.shouldHandleSwitcherHotkeyPressFastPath()
                }
            }, onPress: { [weak self] context in
                guard let self else { return false }
                return MainActor.assumeIsolated {
                    self.handleSwitcherHotkeyPressed(direction: context.isReverse ? -1 : 1)
                }
            }, onRelease: { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleSwitcherHotkeyReleased()
                }
            })
        }
        hotkeyMonitor?.register(shortcut: shortcut)
        _ = ensureSwitcherPanel()
    }

    private func shouldHandleSwitcherHotkeyPressFastPath() -> Bool {
        guard config.switcherEnabled else { return false }
        if switcherPanel?.isVisible == true {
            return !switcherEntries.isEmpty
        }
        return !windowStateStore.getWindows().isEmpty
    }

    private func handleSwitcherHotkeyPressed(direction: Int = 1) -> Bool {
        guard config.switcherEnabled else { return false }
        let start = CACurrentMediaTime()
        if switcherPanel?.isVisible == true, !switcherEntries.isEmpty {
            _ = switcherSession.noteVisiblePress(hasEntries: !switcherEntries.isEmpty)
            cycleSwitcherSelection(direction: direction)
            scheduleSwitcherCommit(primary: switcherSession.shouldSchedulePrimaryCommit)
            recordLiveSwitcherAction(
                action: "cycle",
                startedAt: start,
                count: 1,
                direction: direction,
                success: true
            )
            return true
        }
        let success = beginSwitcherSession(initialDirection: direction)
        recordLiveSwitcherAction(
            action: "open",
            startedAt: start,
            count: 1,
            direction: direction,
            success: success
        )
        return success
    }

    private func handleSwitcherHotkeyReleased() {
        guard switcherSession.canCommitOnRelease() else { return }
        let start = CACurrentMediaTime()
        let entries = switcherEntries.count
        let selectedIndex = switcherSelectedIndex
        hideSwitcher(commitSelection: true)
        recordLiveSwitcherAction(
            action: "commit",
            startedAt: start,
            count: 1,
            direction: 0,
            entries: entries,
            selectedIndex: selectedIndex,
            success: true
        )
    }

    private func recordLiveSwitcherAction(
        action: String,
        startedAt: CFTimeInterval,
        count: Int,
        direction: Int,
        entries: Int? = nil,
        selectedIndex: Int? = nil,
        success: Bool
    ) {
        PerformanceMonitor.shared.recordSwitcherAction(
            action: action,
            durationMs: (CACurrentMediaTime() - startedAt) * 1000.0,
            count: count,
            direction: direction,
            entries: entries ?? switcherEntries.count,
            selectedIndex: selectedIndex ?? switcherSelectedIndex,
            success: success
        )
    }

    private func currentSwitcherCandidateWindows() -> [WindowInfo] {
        Self.switcherCandidateWindows(
            windows: windowStateStore.getWindows(),
            scope: config.switcherWindowScope,
            focusDisplayId: cachedFocusDisplayId
        )
    }

    private func makeSwitcherPanelEntries(
        windows: [WindowInfo],
        selectedIndex: Int
    ) -> [WindowSwitcherPanel.Entry] {
        windows.enumerated().map { index, info in
            let aspectRatio = WindowSwitcherPanel.aspectRatio(for: info.bounds)
            let targetSize = WindowSwitcherPanel.thumbnailTargetSize(
                layoutStyle: config.switcherLayoutStyle,
                selected: index == selectedIndex,
                aspectRatio: aspectRatio
            )
            return WindowSwitcherPanel.Entry(
                windowId: info.id.raw,
                title: info.title.isEmpty ? info.appName : info.title,
                appName: info.appName,
                icon: iconCache.getIcon(bundleId: info.bundleId.raw),
                thumbnail: thumbnailService.cachedThumbnail(
                    windowId: CGWindowID(info.id.raw),
                    targetSizePoints: targetSize,
                    includeLastGood: true
                ),
                aspectRatio: aspectRatio,
                isDimmed: info.isHidden || info.isMinimized
            )
        }
    }

    private func makeSwitcherPrewarmSignature(windows: [WindowInfo], selectedIndex: Int) -> String {
        let ids = windows.map { info in
            let width = Int(info.bounds.width.rounded())
            let height = Int(info.bounds.height.rounded())
            return "\(info.id.raw):\(width)x\(height)"
        }.joined(separator: ",")
        return "\(config.switcherLayoutStyle.rawValue)|\(config.glassStyle.rawValue)|\(selectedIndex)|\(ids)"
    }

    private func scheduleSwitcherPrewarm() {
        guard config.switcherEnabled,
              !isSwitcherThumbnailPrewarmDisabledByEnv,
              switcherPanel?.isVisible != true else { return }
        switcherPrewarmWorkItem?.cancel()
        let now = CFAbsoluteTimeGetCurrent()
        let delay = Self.switcherPrewarmDelay(
            now: now,
            lastSwitcherEndedAt: lastSwitcherEndedAt,
            afterCloseDelay: switcherPrewarmAfterCloseDelay
        )
        var work: DispatchWorkItem?
        work = DispatchWorkItem { [weak self] in
            guard let self, let work else { return }
            guard !work.isCancelled, self.switcherPrewarmWorkItem === work else { return }
            self.prewarmSwitcherPanelIfNeeded()
        }
        switcherPrewarmWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work!)
    }

    private func prewarmSwitcherPanelIfNeeded() {
        guard config.switcherEnabled,
              !isSwitcherThumbnailPrewarmDisabledByEnv,
              switcherPanel?.isVisible != true else { return }
        guard CFAbsoluteTimeGetCurrent() - lastSwitcherEndedAt >= switcherPrewarmAfterCloseDelay else {
            scheduleSwitcherPrewarm()
            return
        }
        let windows = Self.orderedSwitcherWindows(
            windows: currentSwitcherCandidateWindows(),
            mruWindowIds: switcherMRUWindowIds
        )
        guard !windows.isEmpty else { return }

        let focusedId = cachedFocusInfo.windowId ?? windowManager.lastFrontmostWindowId
        let selected = Self.initialSwitcherSelectedIndex(
            entries: windows,
            focusedWindowId: focusedId,
            initialDirection: 1
        )
        let signature = makeSwitcherPrewarmSignature(windows: windows, selectedIndex: selected)
        guard signature != switcherPrewarmSignature else { return }

        let panel = ensureSwitcherPanel()
        panel.setAnimationProfile(config.animationProfile)
        let targetScreen = targetScreenForSwitcherSelection(entries: windows, selectedIndex: selected)
        panel.prewarm(
            entries: makeSwitcherPanelEntries(windows: windows, selectedIndex: selected),
            selectedIndex: selected,
            on: targetScreen
        )
        prefetchSwitcherThumbnails(windows: windows, selectedIndex: selected, targetScreen: targetScreen)
        switcherPrewarmSignature = signature
    }

    nonisolated static func switcherPrewarmDelay(
        now: CFAbsoluteTime,
        lastSwitcherEndedAt: CFAbsoluteTime,
        afterCloseDelay: TimeInterval
    ) -> TimeInterval {
        max(0.05, afterCloseDelay - (now - lastSwitcherEndedAt))
    }

    private func beginSwitcherSession(initialDirection: Int = 1, scheduleCommit: Bool = true) -> Bool {
        hideAllPreviews()
        hideAllTabGroupOverlays()
        hidePluginCard()

        let windows = currentSwitcherCandidateWindows()
        if windows.isEmpty { return false }

        let focusedId = AccessibilityService.focusedWindowId() ?? AccessibilityService.frontmostWindowIdForFrontmostApp()
        switcherMRUWindowIds = Self.updatedSwitcherMRUOrder(
            previous: switcherMRUWindowIds,
            focusedWindowId: focusedId,
            liveWindowIds: Set(windows.map(\.id.raw))
        )
        switcherEntries = Self.orderedSwitcherWindows(
            windows: windows,
            mruWindowIds: switcherMRUWindowIds
        )
        switcherSelectedIndex = Self.initialSwitcherSelectedIndex(
            entries: switcherEntries,
            focusedWindowId: focusedId,
            initialDirection: initialDirection
        )

        let sessionToken = switcherSession.beginSession()
        refreshSwitcherPanel(sessionToken: sessionToken)
        if scheduleCommit {
            scheduleSwitcherCommit(primary: switcherSession.shouldSchedulePrimaryCommit)
        }
        return true
    }

    private func cycleSwitcherSelection(direction: Int) {
        guard !switcherEntries.isEmpty else { return }
        let count = switcherEntries.count
        switcherSelectedIndex = (switcherSelectedIndex + direction + count) % count
        scheduleSwitcherSelectionVisualUpdate(sessionToken: switcherSession.token)
    }

    private func scheduleSwitcherSelectionVisualUpdate(sessionToken: UInt64) {
        pendingSwitcherSelectionVisualUpdate = (switcherSelectedIndex, sessionToken)
        guard !switcherSelectionVisualUpdateScheduled else { return }
        switcherSelectionVisualUpdateScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.switcherSelectionVisualUpdateScheduled = false

            guard let pending = self.pendingSwitcherSelectionVisualUpdate else { return }
            self.pendingSwitcherSelectionVisualUpdate = nil
            guard self.switcherSession.isCurrentToken(pending.token),
                  self.switcherPanel?.isVisible == true,
                  self.switcherEntries.indices.contains(pending.index) else {
                return
            }

            self.switcherPanel?.setSelectedIndex(pending.index)
            self.scheduleSwitcherThumbnailCapture(sessionToken: pending.token)
        }
    }

    private func scheduleSwitcherCommit(primary: Bool = true) {
        switcherCommitWorkItem?.cancel()
        switcherCommitWorkItem = nil
        guard primary else { return }

        let hoverDerived = TimeInterval(config.hoverDelayMs) / 1000.0
        // Keep keyboard switcher commit snappy by default; still allow extra time
        // when users configure a non-zero hover delay.
        let delay = min(0.32, max(0.16, hoverDerived + 0.18))
        var work: DispatchWorkItem?
        work = DispatchWorkItem { [weak self] in
            guard let self, let work else { return }
            guard !work.isCancelled, self.switcherCommitWorkItem === work else { return }
            self.hideSwitcher(commitSelection: true)
        }
        switcherCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work!)
    }

    private func refreshSwitcherPanel(sessionToken: UInt64) {
        guard !switcherEntries.isEmpty else { return }
        guard switcherSelectedIndex >= 0 && switcherSelectedIndex < switcherEntries.count else { return }

        let panel = ensureSwitcherPanel()
        panel.setAnimationProfile(config.animationProfile)

        let targetScreen = targetScreenForSwitcherSelection()
        panel.update(
            entries: makeSwitcherPanelEntries(windows: switcherEntries, selectedIndex: switcherSelectedIndex),
            selectedIndex: switcherSelectedIndex,
            ensureSelectedVisible: false
        )

        panel.show(on: targetScreen)

        switcherThumbnailWorkItem?.cancel()
        switcherThumbnailWorkItem = nil
        scheduleSwitcherThumbnailCapture(sessionToken: sessionToken)
    }

    private func ensureSwitcherPanel() -> WindowSwitcherPanel {
        if let panel = switcherPanel, panel.layoutStyle != config.switcherLayoutStyle {
            panel.close()
            switcherPanel = nil
        }
        if switcherPanel == nil {
            let preferredTheme = panelManager.allPanels.first?.theme ?? config.theme
            switcherPanel = WindowSwitcherPanel(
                theme: preferredTheme,
                glassStyle: config.glassStyle,
                layoutStyle: config.switcherLayoutStyle
            )
        }
        let panel = switcherPanel!
        panel.onEntryClick = { [weak self] windowId in
            MainActor.assumeIsolated {
                self?.handleSwitcherEntryClick(windowId: windowId)
            }
        }
        panel.setAnimationProfile(config.animationProfile)
        return panel
    }

    private func targetScreenForSwitcherSelection() -> NSScreen? {
        targetScreenForSwitcherSelection(entries: switcherEntries, selectedIndex: switcherSelectedIndex)
    }

    private func targetScreenForSwitcherSelection(entries: [WindowInfo], selectedIndex: Int) -> NSScreen? {
        guard entries.indices.contains(selectedIndex) else { return nil }
        let selected = entries[selectedIndex]
        return NSScreen.screens.first { $0.displayId == selected.monitorId.raw }
    }

    private func captureSwitcherThumbnails(sessionToken: UInt64, targetScreen: NSScreen?) {
        let fallbackScale = targetScreen?.backingScaleFactor ?? 2.0
        let indices = Self.switcherThumbnailIndices(
            count: switcherEntries.count,
            selectedIndex: switcherSelectedIndex
        )
        for index in indices {
            guard switcherEntries.indices.contains(index) else { continue }
            let info = switcherEntries[index]
            let targetSize = WindowSwitcherPanel.thumbnailTargetSize(
                layoutStyle: config.switcherLayoutStyle,
                selected: index == switcherSelectedIndex,
                aspectRatio: WindowSwitcherPanel.aspectRatio(for: info.bounds)
            )
            thumbnailService.captureWindowThumbnail(
                windowId: CGWindowID(info.id.raw),
                targetSizePoints: targetSize,
                screenScale: fallbackScale,
                producer: ThumbnailCaptureContext.switcher.producer,
                preferCachedImage: info.isHidden || info.isMinimized
            ) { [weak self] image in
                guard let self else { return }
                guard self.switcherSession.isCurrentToken(sessionToken) else { return }
                self.switcherPanel?.updateThumbnail(windowId: info.id.raw, image: image)
            }
        }
    }

    private func prefetchSwitcherThumbnails(
        windows: [WindowInfo],
        selectedIndex: Int,
        targetScreen: NSScreen?
    ) {
        let fallbackScale = targetScreen?.backingScaleFactor ?? 2.0
        let indices = Self.switcherPrewarmThumbnailIndices(
            count: windows.count,
            selectedIndex: selectedIndex
        )
        for index in indices {
            guard windows.indices.contains(index) else { continue }
            let info = windows[index]
            let targetSize = WindowSwitcherPanel.thumbnailTargetSize(
                layoutStyle: config.switcherLayoutStyle,
                selected: index == selectedIndex,
                aspectRatio: WindowSwitcherPanel.aspectRatio(for: info.bounds)
            )
            thumbnailService.prefetchWindowThumbnail(
                windowId: CGWindowID(info.id.raw),
                targetSizePoints: targetSize,
                screenScale: fallbackScale,
                producer: ThumbnailCaptureContext.prewarm.producer,
                preferCachedImage: info.isHidden || info.isMinimized
            )
        }
    }

    private func scheduleSwitcherThumbnailCapture(sessionToken: UInt64) {
        switcherThumbnailWorkItem?.cancel()
        var work: DispatchWorkItem?
        work = DispatchWorkItem { [weak self] in
            guard let self, let work else { return }
            guard !work.isCancelled, self.switcherThumbnailWorkItem === work else { return }
            guard Self.shouldRunSwitcherThumbnailCapture(
                sessionIsCurrent: self.switcherSession.isCurrentToken(sessionToken),
                panelVisible: self.switcherPanel?.isVisible == true,
                releaseCommitActive: self.switcherSession.canCommitOnRelease()
            ) else {
                return
            }
            self.captureSwitcherThumbnails(
                sessionToken: sessionToken,
                targetScreen: self.targetScreenForSwitcherSelection()
            )
        }
        switcherThumbnailWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + switcherThumbnailStableDelay, execute: work!)
    }

    nonisolated static func shouldRunSwitcherThumbnailCapture(
        sessionIsCurrent: Bool,
        panelVisible: Bool,
        releaseCommitActive: Bool
    ) -> Bool {
        sessionIsCurrent && panelVisible && !releaseCommitActive
    }

    nonisolated static func switcherThumbnailIndices(
        count: Int,
        selectedIndex: Int,
        leadingCount: Int = 6,
        neighborRadius: Int = 2,
        maxCount: Int = 8
    ) -> [Int] {
        guard count > 0, maxCount > 0 else { return [] }

        let selected = min(max(selectedIndex, 0), count - 1)
        var result: [Int] = []
        result.reserveCapacity(min(maxCount, count))
        var seen = Set<Int>()
        seen.reserveCapacity(min(maxCount, count))

        func append(_ index: Int) {
            guard result.count < maxCount,
                  index >= 0,
                  index < count,
                  seen.insert(index).inserted else {
                return
            }
            result.append(index)
        }

        append(selected)
        if neighborRadius > 0 {
            for offset in 1...neighborRadius {
                append(selected - offset)
                append(selected + offset)
            }
        }

        for index in 0..<min(max(leadingCount, 0), count) {
            append(index)
        }

        var index = 0
        while result.count < min(maxCount, count), index < count {
            append(index)
            index += 1
        }

        return result
    }

    nonisolated static func switcherPrewarmThumbnailIndices(
        count: Int,
        selectedIndex: Int
    ) -> [Int] {
        switcherThumbnailIndices(
            count: count,
            selectedIndex: selectedIndex,
            leadingCount: 6,
            neighborRadius: 2,
            maxCount: 8
        )
    }

    private func hideSwitcher(commitSelection: Bool) {
        switcherCommitWorkItem?.cancel()
        switcherCommitWorkItem = nil
        switcherThumbnailWorkItem?.cancel()
        switcherThumbnailWorkItem = nil
        pendingSwitcherSelectionVisualUpdate = nil
        switcherSelectionVisualUpdateScheduled = false
        invalidateThumbnailRequests(for: ThumbnailCaptureContext.switcher.producer)
        lastSwitcherEndedAt = CFAbsoluteTimeGetCurrent()

        if commitSelection,
           switcherSelectedIndex >= 0,
           switcherSelectedIndex < switcherEntries.count {
            activateSwitcherWindow(switcherEntries[switcherSelectedIndex])
        }

        switcherPanel?.hide()
        switcherEntries.removeAll(keepingCapacity: false)
        switcherSelectedIndex = 0
        _ = switcherSession.finish(commitSelection: commitSelection)
    }

    private func activateSwitcherWindow(_ info: WindowInfo) {
        if info.isHidden {
            AccessibilityService.unhideApp(bundleId: info.bundleId.raw)
        }
        if info.isMinimized {
            guard ensureAccessibilityTrusted() else { return }
            AccessibilityService.unminimizeWindow(windowId: info.id.raw)
        }
        guard ensureAccessibilityTrusted() else { return }
        AccessibilityService.focusWindow(windowId: info.id.raw)
        switcherMRUWindowIds = Self.updatedSwitcherMRUOrder(
            previous: switcherMRUWindowIds,
            focusedWindowId: info.id.raw,
            liveWindowIds: Set(windowStateStore.windows.keys.map(\.raw))
        )
    }

    private func handleSwitcherEntryClick(windowId: UInt32) {
        guard switcherPanel?.isVisible == true,
              let idx = switcherEntries.firstIndex(where: { $0.id.raw == windowId }) else {
            return
        }
        switcherSelectedIndex = idx
        switcherPanel?.setSelectedIndex(idx)
        hideSwitcher(commitSelection: true)
    }

    private func handleSwitcherLocalEvent(_ event: NSEvent) -> Bool {
        guard switcherPanel?.isVisible == true else { return false }

        switch event.type {
        case .keyDown:
            switch event.keyCode {
            case 48: // tab
                let backwards = event.modifierFlags.contains(.shift)
                cycleSwitcherSelection(direction: backwards ? -1 : 1)
                scheduleSwitcherCommit(primary: switcherSession.shouldSchedulePrimaryCommit)
                return true

            case 123, 126: // left/up
                cycleSwitcherSelection(direction: -1)
                scheduleSwitcherCommit(primary: switcherSession.shouldSchedulePrimaryCommit)
                return true

            case 124, 125: // right/down
                cycleSwitcherSelection(direction: 1)
                scheduleSwitcherCommit(primary: switcherSession.shouldSchedulePrimaryCommit)
                return true

            case 36, 76, 49: // return/enter/space
                hideSwitcher(commitSelection: true)
                return true

            case 53: // escape
                hideSwitcher(commitSelection: false)
                return true

            default:
                // Any other key closes the switcher without consuming the keypress.
                hideSwitcher(commitSelection: false)
                return false
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let point = screenPointForEvent(event)
            if switcherPanel?.frame.contains(point) == true {
                return false
            }
            hideSwitcher(commitSelection: false)
            return false

        default:
            return false
        }
    }

    private func screenPointForEvent(_ event: NSEvent) -> NSPoint {
        if let window = event.window {
            let rect = NSRect(origin: event.locationInWindow, size: .zero)
            return window.convertToScreen(rect).origin
        }
        return NSEvent.mouseLocation
    }

    // MARK: - Plugin Tile Cards

    private func togglePluginCard(
        displayId: CGDirectDisplayID,
        itemIndex: Int,
        tileId: String,
        providerId: String?,
        title: String
    ) {
        guard let panel = panelManager.panel(for: displayId) else { return }
        guard let anchorRect = panel.barView.screenRectForVisualItem(at: itemIndex) else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        if config.tilePopupSingleton,
           pluginCardTileId == tileId,
           pluginCardPanel?.isVisible == true {
            hidePluginCard()
            return
        }

        let card: PluginControlCardPanel
        if let existing = pluginCardPanel {
            card = existing
        } else {
            let created = PluginControlCardPanel(theme: panel.theme, glassStyle: config.glassStyle)
            created.onAction = { [weak self] actionId in
                guard let self,
                      let providerId = self.pluginCardProviderId else { return }
                Task {
                    await self.providerRuntime.performAction(
                        providerId: providerId,
                        actionId: actionId,
                        payload: nil,
                        timeoutMs: self.config.providerTimeoutMs,
                        circuitBreakerThreshold: self.config.providerCircuitBreakerThreshold
                    )
                    await self.refreshPluginCardState(titleFallback: title)
                }
            }
            pluginCardPanel = created
            card = created
        }
        card.setAnimationProfile(config.animationProfile)

        pluginCardTileId = tileId
        pluginCardProviderId = providerId
        pluginCardDisplayId = displayId

        let loadingState: ProviderPanelState = providerId == nil
            ? .disconnected(title: title, subtitle: "No provider configured")
            : ProviderPanelState(
                title: title,
                subtitle: "Loading…",
                progressCurrent: nil,
                progressTotal: nil,
                health: .degraded,
                actions: []
            )
        card.update(tileTitle: title, state: loadingState)
        card.show(anchorRect: anchorRect, on: screen, position: panel.position)

        guard config.providerRuntimeEnabled, let providerId else { return }
        Task {
            await refreshPluginCardState(titleFallback: title)
            guard pluginCardProviderId == providerId else { return }
        }
    }

    private func refreshPluginCardState(titleFallback: String) async {
        guard config.providerRuntimeEnabled,
              let providerId = pluginCardProviderId,
              let card = pluginCardPanel else { return }

        let state = await providerRuntime.fetchPanelState(
            providerId: providerId,
            timeoutMs: config.providerTimeoutMs,
            circuitBreakerThreshold: config.providerCircuitBreakerThreshold,
            fallbackTitle: titleFallback
        )
        await MainActor.run {
            guard self.pluginCardProviderId == providerId else { return }
            card.update(tileTitle: titleFallback, state: state)
        }
    }

    private func hidePluginCard() {
        pluginCardPanel?.hide()
        pluginCardTileId = nil
        pluginCardProviderId = nil
        pluginCardDisplayId = nil
    }

    // MARK: - Custom Items

    private func openCustomItem(id: String) {
        guard let item = config.customItems.first(where: { $0.id == id }) else { return }
        switch item {
        case .spacer, .text:
            return
        case .link(_, _, let url, _):
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: trimmed) else { return }
            NSWorkspace.shared.open(u)
        case .folder(_, _, let path, _):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: trimmed, isDirectory: true))
        }
    }

    private func editCustomItemFlow(id: String) {
        guard let idx = config.customItems.firstIndex(where: { $0.id == id }) else { return }
        let item = config.customItems[idx]

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        switch item {
        case .spacer(let id, let width):
            alert.messageText = "Edit Spacer"
            let widthField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
            widthField.stringValue = "\(width)"
            widthField.placeholderString = "Width (px)"
            alert.accessoryView = widthField
            let resp = alert.runModal()
            guard resp == .alertFirstButtonReturn else { return }
            let newWidth = Int(widthField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? width
            config.customItems[idx] = .spacer(id: id, width: newWidth)

        case .text(let id, let text):
            alert.messageText = "Edit Label"
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            textField.stringValue = text
            alert.accessoryView = textField
            let resp = alert.runModal()
            guard resp == .alertFirstButtonReturn else { return }
            let newText = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newText.isEmpty else { return }
            config.customItems[idx] = .text(id: id, text: newText)

        case .link(let id, let title, let url, let icon):
            alert.messageText = "Edit Link"
            let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            titleField.stringValue = title
            titleField.placeholderString = "Title"

            let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            urlField.stringValue = url
            urlField.placeholderString = "URL (https://… or app://…)"

            let iconField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            iconField.stringValue = icon ?? ""
            iconField.placeholderString = "Icon (optional, e.g. sf:link)"

            let stack = NSStackView(views: [titleField, urlField, iconField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            alert.accessoryView = stack

            let resp = alert.runModal()
            guard resp == .alertFirstButtonReturn else { return }
            let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newUrl = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newIcon = iconField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty, !newUrl.isEmpty else { return }
            config.customItems[idx] = .link(id: id, title: newTitle, url: newUrl, icon: newIcon.isEmpty ? nil : newIcon)

        case .folder(let id, let title, let path, let icon):
            alert.messageText = "Edit Folder"
            let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            titleField.stringValue = title
            titleField.placeholderString = "Title"

            let pathField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            pathField.stringValue = path
            pathField.placeholderString = "Path (/Users/…)"

            let iconField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            iconField.stringValue = icon ?? ""
            iconField.placeholderString = "Icon (optional, e.g. file:/Users/…)"

            let stack = NSStackView(views: [titleField, pathField, iconField])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            alert.accessoryView = stack

            let resp = alert.runModal()
            guard resp == .alertFirstButtonReturn else { return }
            let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newPath = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newIcon = iconField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newTitle.isEmpty, !newPath.isEmpty else { return }
            config.customItems[idx] = .folder(id: id, title: newTitle, path: newPath, icon: newIcon.isEmpty ? nil : newIcon)
        }

        config.validate()
        config.save()
        renderUI()
    }

    // MARK: - Hover Previews

    private func handlePreviewHover(displayId: CGDirectDisplayID, hoverIndex: Int?, panel: LiquidBarPanel) {
        // Cancel any pending show for this display.
        previewWorkItemByDisplay[displayId]?.cancel()
        previewWorkItemByDisplay.removeValue(forKey: displayId)
        groupPreviewShowWorkItemByDisplay[displayId]?.cancel()
        groupPreviewShowWorkItemByDisplay.removeValue(forKey: displayId)
        // Cancel any pending hide; we'll reschedule below if needed.
        groupPreviewHideWorkItemByDisplay[displayId]?.cancel()
        groupPreviewHideWorkItemByDisplay.removeValue(forKey: displayId)

        // Hide immediately; we'll re-show after the hover delay if still hovered.
        hidePreview(displayId: displayId)

        guard config.previewsEnabled else {
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
            hideGroupPreview(displayId: displayId)
            return
        }

        guard let hoverIndex else {
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            hidePreview(displayId: displayId)
            groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
            scheduleHideGroupPreview(displayId: displayId)
            return
        }

        let items = itemsForDisplay(displayId)
        guard hoverIndex >= 0, hoverIndex < items.count else {
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            hidePreview(displayId: displayId)
            groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
            scheduleHideGroupPreview(displayId: displayId)
            return
        }

        // Group previews: show a chooser with thumbnails (Windows-style) so the user
        // can pick a specific window within an app group or a custom tab group.
        //
        // Important UX rule: never show *both* the single-window preview panel and the
        // group chooser at the same time. When the chooser is already visible, hovering
        // other items should update the same chooser (Windows behavior) to avoid
        // "stacked" popups.
        switch items[hoverIndex] {
        case .appGroup(let bundleId, _, _, let windows, _, _, _):
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            let key = "app:\(bundleId)"
            groupPreviewHoveredKeyByDisplay[displayId] = key

            let baseDelay = TimeInterval(config.previewHoverDelayMs) / 1000.0
            let delay = (groupPreviewPanelByDisplay[displayId]?.isVisible == true) ? 0 : baseDelay
            let anchorRect = panel.barView.screenRectForVisualItem(at: hoverIndex)
            guard let anchorRect else {
                groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
                scheduleHideGroupPreview(displayId: displayId)
                return
            }

            let panelPosition = panel.position
            let theme = panel.theme
            let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
            let windowIds = windows.map(\.raw)

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.groupPreviewHoveredKeyByDisplay[displayId] == key else { return }
                guard let screen else { return }
                self.showGroupPreview(
                    displayId: displayId,
                    key: key,
                    windowIds: windowIds,
                    theme: theme,
                    anchorRect: anchorRect,
                    screen: screen,
                    position: panelPosition
                )
            }

            groupPreviewShowWorkItemByDisplay[displayId] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return

        case .tabGroup(let groupId, _, _, _, _, _, _, _):
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            let key = "tab:\(groupId)"
            groupPreviewHoveredKeyByDisplay[displayId] = key

            let baseDelay = TimeInterval(config.previewHoverDelayMs) / 1000.0
            let delay = (groupPreviewPanelByDisplay[displayId]?.isVisible == true) ? 0 : baseDelay
            let anchorRect = panel.barView.screenRectForVisualItem(at: hoverIndex)
            guard let anchorRect else {
                groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
                scheduleHideGroupPreview(displayId: displayId)
                return
            }

            let panelPosition = panel.position
            let theme = panel.theme
            let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
            let windowIds = userState.tabGroup(withId: groupId)?.windowIds ?? []

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.groupPreviewHoveredKeyByDisplay[displayId] == key else { return }
                guard let screen else { return }
                self.showGroupPreview(
                    displayId: displayId,
                    key: key,
                    windowIds: windowIds,
                    theme: theme,
                    anchorRect: anchorRect,
                    screen: screen,
                    position: panelPosition
                )
            }

            groupPreviewShowWorkItemByDisplay[displayId] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return

        default:
            break
        }

        // If we're hovering a non-group item, enforce strict overlay exclusivity:
        // hide any group preview immediately before showing single-window preview.
        groupPreviewHoveredKeyByDisplay.removeValue(forKey: displayId)
        hideGroupPreview(displayId: displayId, immediate: true)

        let hoveredWindow: (id: UInt32, isHidden: Bool, isMinimized: Bool)?
        switch items[hoverIndex] {
        case .window(let id, _, _, _, let isHidden, let isMinimized, _):
            hoveredWindow = (id: id.raw, isHidden: isHidden, isMinimized: isMinimized)
        default:
            hoveredWindow = nil
        }

        guard let hoveredWindow else {
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            return
        }
        let windowId = hoveredWindow.id

        let delay = TimeInterval(config.previewHoverDelayMs) / 1000.0
        let anchorRect = panel.barView.screenRectForVisualItem(at: hoverIndex)
        guard let anchorRect else {
            previewHoveredWindowIdByDisplay.removeValue(forKey: displayId)
            return
        }

        previewHoveredWindowIdByDisplay[displayId] = windowId

        let panelPosition = panel.position
        let theme = panel.theme
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.previewHoveredWindowIdByDisplay[displayId] == windowId else { return }
            guard let screen else { return }

            let title: String
            if let info = self.windowStateStore.getWindows().first(where: { $0.id.raw == windowId }) {
                title = info.title.isEmpty ? info.appName : info.title
            } else {
                title = "\(windowId)"
            }

            let aspectFromBounds: CGFloat? = {
                guard let info = self.windowStateStore.getWindows().first(where: { $0.id.raw == windowId }) else { return nil }
                guard info.bounds.width > 20, info.bounds.height > 20 else { return nil }
                let a = info.bounds.width / info.bounds.height
                if !a.isFinite || a <= 0 { return nil }
                return CGFloat(a)
            }()

            // Capture at an aspect ratio matching the window, otherwise SCK letterboxes
            // portrait windows into a wide thumbnail (which looks like "empty" preview).
            let targetSizePoints: CGSize = {
                let imageH: CGFloat = 180
                let minW: CGFloat = 100
                let maxW: CGFloat = 520
                let aspect = (aspectFromBounds ?? (16.0 / 9.0))
                let w = Swift.min(Swift.max(imageH * aspect, minW), maxW)
                return CGSize(width: w, height: imageH)
            }()
            let scale = screen.backingScaleFactor
            let cachedImage = self.thumbnailService.cachedThumbnail(
                windowId: CGWindowID(windowId),
                targetSizePoints: targetSizePoints,
                includeLastGood: true
            )

            // First paint should use the best retained image we have; SCK refreshes can
            // still replace it asynchronously below.
            self.showPreview(
                displayId: displayId,
                theme: theme,
                anchorRect: anchorRect,
                screen: screen,
                position: panelPosition,
                image: cachedImage,
                title: title,
                aspectRatio: cachedImage == nil ? aspectFromBounds : nil
            )

            self.thumbnailService.captureWindowThumbnail(
                windowId: CGWindowID(windowId),
                targetSizePoints: targetSizePoints,
                screenScale: scale,
                producer: ThumbnailCaptureContext.hoveredPreview.producer,
                preferCachedImage: hoveredWindow.isHidden || hoveredWindow.isMinimized
            ) { [weak self] image in
                guard let self else { return }
                guard self.previewHoveredWindowIdByDisplay[displayId] == windowId else { return }
                // When we have a captured image, prefer its actual aspect ratio to
                // avoid slight mismatch/letterboxing for windows whose bounds are
                // reported inaccurately. If capture failed, keep the bounds aspect.
                let aspect: CGFloat? = (image == nil) ? aspectFromBounds : nil
                self.showPreview(
                    displayId: displayId,
                    theme: theme,
                    anchorRect: anchorRect,
                    screen: screen,
                    position: panelPosition,
                    image: image ?? cachedImage,
                    title: title,
                    aspectRatio: aspect
                )
            }
        }

        previewWorkItemByDisplay[displayId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showPreview(
        displayId: CGDirectDisplayID,
        theme: Theme,
        anchorRect: NSRect,
        screen: NSScreen,
        position: Position,
        image: NSImage?,
        title: String,
        aspectRatio: CGFloat?
    ) {
        let panel: WindowPreviewPanel
        if let existing = previewPanelByDisplay[displayId] {
            panel = existing
        } else {
            panel = WindowPreviewPanel(theme: theme, glassStyle: config.glassStyle)
            previewPanelByDisplay[displayId] = panel
        }
        panel.setAnimationProfile(config.animationProfile)

        panel.update(image: image, title: title, aspectRatio: aspectRatio)
        panel.show(anchorRect: anchorRect, on: screen, position: position)
    }

    private func hidePreview(displayId: CGDirectDisplayID) {
        previewPanelByDisplay[displayId]?.hide()
    }

    private func showGroupPreview(
        displayId: CGDirectDisplayID,
        key: String,
        windowIds: [UInt32],
        theme: Theme,
        anchorRect: NSRect,
        screen: NSScreen,
        position: Position
    ) {
        groupPreviewHideWorkItemByDisplay[displayId]?.cancel()
        groupPreviewHideWorkItemByDisplay.removeValue(forKey: displayId)

        let requestedWindowIds = reorderedWindowIdsForGroupPreview(key: key, baseWindowIds: windowIds)

        guard !requestedWindowIds.isEmpty else {
            groupPreviewActiveKeyByDisplay.removeValue(forKey: displayId)
            hideGroupPreview(displayId: displayId)
            return
        }

        // Resolve visible WindowInfo in the requested order.
        let all = windowStateStore.getWindows()
        let idSet = Set(requestedWindowIds)
        let byId = Dictionary(uniqueKeysWithValues: all.compactMap { w -> (UInt32, WindowInfo)? in
            guard idSet.contains(w.id.raw) else { return nil }
            return (w.id.raw, w)
        })

        var ordered: [WindowInfo] = []
        ordered.reserveCapacity(requestedWindowIds.count)
        var seenIds = Set<UInt32>()
        var seenSignatures = Set<String>()
        for wid in requestedWindowIds {
            if !seenIds.insert(wid).inserted { continue }
            guard let w = byId[wid] else { continue }
            if config.windowDisplayMode == .perDisplay, w.monitorId.raw != displayId { continue }
            if w.isHidden, !config.showHiddenApps { continue }
            if w.isMinimized, !config.showMinimizedWindows { continue }

            // Defensive dedupe for ghost duplicates that may have distinct IDs but represent
            // the same window surface (identical title + near-identical bounds).
            let title = w.title.isEmpty ? w.appName : w.title
            let bx = Int((w.bounds.x / 16.0).rounded())
            let by = Int((w.bounds.y / 16.0).rounded())
            let bw = Int((w.bounds.width / 16.0).rounded())
            let bh = Int((w.bounds.height / 16.0).rounded())
            let signature = "\(w.bundleId.raw)|\(w.monitorId.raw)|\(title)|\(bx),\(by),\(bw),\(bh)"
            if !seenSignatures.insert(signature).inserted { continue }

            // Collapse ghost compositor duplicates (distinct IDs, same visual surface).
            let area = max(0.0, w.bounds.width) * max(0.0, w.bounds.height)
            var collapsed = false
            for i in ordered.indices {
                let existing = ordered[i]
                let existingTitle = existing.title.isEmpty ? existing.appName : existing.title
                guard existing.bundleId.raw == w.bundleId.raw,
                      existing.monitorId == w.monitorId,
                      existingTitle == title else { continue }

                let existingArea = max(0.0, existing.bounds.width) * max(0.0, existing.bounds.height)
                let minArea = max(1.0, min(area, existingArea))
                let overlapRatio = w.bounds.intersectionArea(with: existing.bounds) / minArea
                guard overlapRatio >= 0.92 else { continue }

                let currentHasRealTitle = !w.title.isEmpty
                let existingHasRealTitle = !existing.title.isEmpty
                if (currentHasRealTitle && !existingHasRealTitle)
                    || (currentHasRealTitle == existingHasRealTitle && area > existingArea) {
                    ordered[i] = w
                }
                collapsed = true
                break
            }
            if collapsed { continue }

            ordered.append(w)
        }

        guard !ordered.isEmpty else {
            groupPreviewActiveKeyByDisplay.removeValue(forKey: displayId)
            hideGroupPreview(displayId: displayId)
            return
        }

        let shown = Array(ordered.prefix(12))

        let panel: WindowGroupPreviewPanel
        if let existing = groupPreviewPanelByDisplay[displayId] {
            panel = existing
        } else {
            panel = WindowGroupPreviewPanel(theme: theme, glassStyle: config.glassStyle)
            panel.onHoverChanged = { [weak self] inside in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.groupPreviewPointerInsideByDisplay[displayId] = inside
                    if inside {
                        self.groupPreviewHideWorkItemByDisplay[displayId]?.cancel()
                        self.groupPreviewHideWorkItemByDisplay.removeValue(forKey: displayId)
                    } else {
                        self.scheduleHideGroupPreview(displayId: displayId)
                    }
                }
            }
            panel.onWindowClicked = { [weak self] wid in
                guard let self else { return }

                // Apply the same semantics as clicking a window item.
                if let info = self.windowStateStore.getWindows().first(where: { $0.id.raw == wid }) {
                    if info.isHidden {
                        AccessibilityService.unhideApp(bundleId: info.bundleId.raw)
                        self.hideGroupPreview(displayId: displayId)
                        return
                    }
                    if info.isMinimized {
                        guard self.ensureAccessibilityTrusted() else { return }
                        AccessibilityService.unminimizeWindow(windowId: wid)
                        self.hideGroupPreview(displayId: displayId)
                        return
                    }
                }

                guard self.ensureAccessibilityTrusted() else { return }
                AccessibilityService.focusWindow(windowId: wid)
                self.hideGroupPreview(displayId: displayId)
            }
            panel.onWindowsReordered = { [weak self] orderedIds in
                guard let self else { return }
                guard let activeKey = self.groupPreviewActiveKeyByDisplay[displayId] else { return }
                self.applyGroupPreviewReorder(key: activeKey, orderedWindowIds: orderedIds)
            }
            groupPreviewPanelByDisplay[displayId] = panel
        }
        panel.setAnimationProfile(config.animationProfile)

        groupPreviewActiveKeyByDisplay[displayId] = key
        groupPreviewAnchorRectByDisplay[displayId] = anchorRect
        panel.updateWindows(shown)
        panel.show(anchorRect: anchorRect, on: screen, position: position)

        // Kick thumbnail captures (async). Keep running while the panel is visible.
        let scale = screen.backingScaleFactor
        for w in shown {
            let windowId = w.id.raw
            let title = w.title.isEmpty ? w.appName : w.title
            let isDimmed = w.isHidden || w.isMinimized
            let targetSizePoints: CGSize = {
                let h: CGFloat = 124
                let minW: CGFloat = 96
                let maxW: CGFloat = 240
                let bw = CGFloat(w.bounds.width)
                let bh = CGFloat(w.bounds.height)
                let aspect: CGFloat
                if bw > 20, bh > 20, (bw / bh).isFinite, (bw / bh) > 0 {
                    aspect = bw / bh
                } else {
                    aspect = 16.0 / 9.0
                }
                let w = max(minW, min(maxW, h * aspect))
                return CGSize(width: w, height: h)
            }()
            let cachedImage = thumbnailService.cachedThumbnail(
                windowId: CGWindowID(windowId),
                targetSizePoints: targetSizePoints,
                includeLastGood: true
            )
            if let cachedImage {
                panel.updateThumbnail(windowId: windowId, image: cachedImage, title: title, isDimmed: isDimmed)
            }
            thumbnailService.captureWindowThumbnail(
                windowId: CGWindowID(windowId),
                targetSizePoints: targetSizePoints,
                screenScale: scale,
                producer: ThumbnailCaptureContext.groupPreview.producer,
                preferCachedImage: isDimmed
            ) { [weak self] image in
                guard let self else { return }
                guard self.groupPreviewActiveKeyByDisplay[displayId] == key else { return }
                self.groupPreviewPanelByDisplay[displayId]?.updateThumbnail(
                    windowId: windowId,
                    image: image ?? cachedImage,
                    title: title,
                    isDimmed: isDimmed
                )
            }
        }
    }

    private func reorderedWindowIdsForGroupPreview(key: String, baseWindowIds: [UInt32]) -> [UInt32] {
        guard !baseWindowIds.isEmpty else { return [] }
        let preferred = groupPreviewOrderByKey[key] ?? userState.preferredGroupPreviewOrder(for: key)
        guard let preferred, !preferred.isEmpty else { return baseWindowIds }

        let baseSet = Set(baseWindowIds)
        var seen = Set<UInt32>()
        var ordered: [UInt32] = []
        ordered.reserveCapacity(baseWindowIds.count)

        for wid in preferred where baseSet.contains(wid) {
            if seen.insert(wid).inserted {
                ordered.append(wid)
            }
        }
        for wid in baseWindowIds where seen.insert(wid).inserted {
            ordered.append(wid)
        }

        // Prune stale ids so the cache stays aligned with live windows.
        groupPreviewOrderByKey[key] = ordered
        if key.hasPrefix("app:") {
            userState.updateGroupPreviewOrder(key: key, orderedWindowIds: ordered)
        }
        return ordered
    }

    private func applyGroupPreviewReorder(key: String, orderedWindowIds: [UInt32]) {
        guard !orderedWindowIds.isEmpty else { return }

        if key.hasPrefix("tab:") {
            let groupId = String(key.dropFirst(4))
            userState.reorderTabGroupWindows(groupId: groupId, orderedWindowIds: orderedWindowIds)
        } else if key.hasPrefix("app:") {
            userState.updateGroupPreviewOrder(key: key, orderedWindowIds: orderedWindowIds)
            if windowStateStore.reorderSubset(orderedWindowIds: orderedWindowIds) {
                userState.updateWindowOrder(windowStateStore.getWindows().map(\.id.raw))
                renderUI()
            }
        }

        // Keep runtime cache in sync for immediate/next hover presentation.
        groupPreviewOrderByKey[key] = orderedWindowIds
    }

    private func hideGroupPreview(displayId: CGDirectDisplayID, immediate: Bool = false) {
        groupPreviewPanelByDisplay[displayId]?.hide(immediate: immediate)
        groupPreviewActiveKeyByDisplay.removeValue(forKey: displayId)
        groupPreviewPointerInsideByDisplay.removeValue(forKey: displayId)
        groupPreviewAnchorRectByDisplay.removeValue(forKey: displayId)
        invalidateThumbnailRequests(for: ThumbnailCaptureContext.groupPreview.producer)
    }

    private func scheduleHideGroupPreview(displayId: CGDirectDisplayID, delay: TimeInterval? = nil) {
        // If the cursor is currently inside the preview panel, keep it alive.
        if groupPreviewPointerInsideByDisplay[displayId] == true {
            return
        }

        let baseDelay = max(0.05, TimeInterval(config.hoverDelayMs) / 1000.0)
        let effectiveDelay: TimeInterval = {
            if let delay { return max(0.01, delay) }
            if config.hoverIntentGuardEnabled {
                // Intent guard: keep panel alive slightly longer to allow edge traversal.
                return max(0.35, baseDelay)
            }
            return max(0.08, baseDelay)
        }()

        groupPreviewHideWorkItemByDisplay[displayId]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Only hide when the cursor is no longer over a group item and the popup isn't hovered.
            guard self.groupPreviewHoveredKeyByDisplay[displayId] == nil else { return }
            guard self.groupPreviewPointerInsideByDisplay[displayId] != true else { return }
            if self.shouldKeepGroupPreviewAliveForIntent(displayId: displayId) {
                self.scheduleHideGroupPreview(displayId: displayId, delay: 0.06)
                return
            }
            self.hideGroupPreview(displayId: displayId)
        }

        groupPreviewHideWorkItemByDisplay[displayId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: work)
    }

    private func hideAllPreviews() {
        for (_, work) in previewWorkItemByDisplay {
            work.cancel()
        }
        previewWorkItemByDisplay.removeAll()
        previewHoveredWindowIdByDisplay.removeAll()
        invalidateThumbnailRequests(for: ThumbnailCaptureContext.hoveredPreview.producer)

        for (_, panel) in previewPanelByDisplay {
            panel.hide()
        }
        previewPanelByDisplay.removeAll()

        for (_, work) in groupPreviewShowWorkItemByDisplay {
            work.cancel()
        }
        for (_, work) in groupPreviewHideWorkItemByDisplay {
            work.cancel()
        }
        groupPreviewShowWorkItemByDisplay.removeAll()
        groupPreviewHideWorkItemByDisplay.removeAll()
        groupPreviewHoveredKeyByDisplay.removeAll()
        groupPreviewActiveKeyByDisplay.removeAll()
        groupPreviewPointerInsideByDisplay.removeAll()
        groupPreviewAnchorRectByDisplay.removeAll()
        invalidateThumbnailRequests(for: ThumbnailCaptureContext.groupPreview.producer)

        for (_, panel) in groupPreviewPanelByDisplay {
            panel.hide()
        }
        groupPreviewPanelByDisplay.removeAll()
    }

    private func releaseHiddenOverlayImages() {
        if switcherPanel?.isVisible != true {
            switcherPanel?.releaseRetainedImages()
        }
        for panel in previewPanelByDisplay.values where !panel.isVisible {
            panel.releaseRetainedImage()
        }
        for panel in groupPreviewPanelByDisplay.values where !panel.isVisible {
            panel.releaseRetainedImages()
        }
    }

    private func syncThumbnailLifecycleToLiveWindowIds(_ liveWindowIds: Set<UInt32>) {
        thumbnailService.pruneToLiveWindowIds(Set(liveWindowIds.map { CGWindowID($0) }))
    }

    private func invalidateThumbnailRequests(for producer: WindowThumbnailService.ThumbnailProducer) {
        thumbnailService.invalidateRequests(for: producer)
    }

    private func shouldKeepGroupPreviewAliveForIntent(displayId: CGDirectDisplayID) -> Bool {
        guard config.hoverIntentGuardEnabled else { return false }
        guard let anchorRect = groupPreviewAnchorRectByDisplay[displayId] else { return false }
        guard let panel = groupPreviewPanelByDisplay[displayId], panel.isVisible else { return false }
        return HoverIntentBridge.contains(
            cursor: NSEvent.mouseLocation,
            anchorRect: anchorRect,
            panelRect: panel.frame,
            padding: 8
        )
    }

    // MARK: - Scroll Wheel

    private func handleScroll(displayId: CGDirectDisplayID, direction: Int) {
        guard direction != 0 else { return }

        switch config.scrollWheelMode {
        case .off:
            return

        case .cycleWindows:
            cycleWindowFocus(displayId: displayId, direction: direction)

        case .hideShow:
            setBarHidden(!isBarHidden)

        case .volume:
            // Scroll up increases volume; our direction maps scroll up to -1.
            let delta: Float = direction < 0 ? 0.05 : -0.05
            SystemAudioService.changeOutputVolume(delta: delta)
        }
    }

    private func cycleWindowFocus(displayId: CGDirectDisplayID, direction: Int) {
        guard ensureAccessibilityTrusted() else { return }

        var candidates = windowStateStore.getWindows()

        if config.windowDisplayMode == .perDisplay {
            candidates = candidates.filter { $0.monitorId.raw == displayId }
        }

        if !config.showHiddenApps {
            candidates = candidates.filter { !$0.isHidden }
        }
        if !config.showMinimizedWindows {
            candidates = candidates.filter { !$0.isMinimized }
        }

        guard !candidates.isEmpty else { return }

        let focused = AccessibilityService.focusedWindowId()

        let next: WindowInfo
        if let focused, let idx = candidates.firstIndex(where: { $0.id.raw == focused }) {
            let nextIdx = (idx + direction + candidates.count) % candidates.count
            next = candidates[nextIdx]
        } else {
            next = direction > 0 ? candidates[0] : candidates[candidates.count - 1]
        }

        if next.isHidden {
            AccessibilityService.unhideApp(bundleId: next.bundleId.raw)
        }
        if next.isMinimized {
            AccessibilityService.unminimizeWindow(windowId: next.id.raw)
            return
        }

        AccessibilityService.focusWindow(windowId: next.id.raw)
    }

    private func setBarHidden(_ hidden: Bool) {
        isBarHidden = hidden

        if hidden {
            hideAllPreviews()
            hidePluginCard()
            hideSwitcher(commitSelection: false)
            panelManager.pauseAllDisplayLinks()
            for panel in panelManager.allPanels {
                panel.ignoresMouseEvents = true
                panel.animator().alphaValue = 0
            }
        } else {
            for panel in panelManager.allPanels {
                panel.ignoresMouseEvents = false
                panel.refreshRetainedLayers()
                renderer.forceRedraw(displayId: panel.displayId)
                panelManager.resumeDisplayLink(for: panel.displayId)
                panel.animator().alphaValue = 1
            }
        }
    }

    @discardableResult
    private func updateSidebarPeekVisibility(now: CFAbsoluteTime) -> Bool {
        guard !isBarHidden else { return false }

        let verticalPanels = panelManager.allPanels.filter { $0.position.isVertical }
        guard !verticalPanels.isEmpty else {
            sidebarRevealUntilByDisplay.removeAll()
            sidebarPresentationByDisplay.removeAll()
            return false
        }

        guard config.sidebarModeEnabled, config.taskbarPosition.isVertical else {
            var geometryChanged = false
            for panel in verticalPanels {
                panel.ignoresMouseEvents = false
                if panel.alphaValue < 0.99 {
                    panel.alphaValue = 1.0
                }
                if panelManager.applySidebarPresentation(for: panel.displayId, presentation: .compact, config: config) {
                    geometryChanged = true
                }
            }
            sidebarRevealUntilByDisplay.removeAll()
            sidebarPresentationByDisplay.removeAll()
            return geometryChanged
        }

        let mouse = NSEvent.mouseLocation
        let hasAnyOverlay = (pluginCardPanel?.isVisible == true)
            || previewPanelByDisplay.values.contains(where: { $0.isVisible })
            || groupPreviewPanelByDisplay.values.contains(where: { $0.isVisible })
            || (switcherPanel?.isVisible == true)

        var geometryChanged = false
        var activeDisplays = Set<CGDirectDisplayID>()

        for panel in verticalPanels {
            let did = panel.displayId
            activeDisplays.insert(did)

            let hoveringPanel = panel.frame.contains(mouse)
            let edgeHover: Bool = {
                guard let screen = panel.screen else { return false }
                return isPointAtSidebarEdge(mouse, on: screen, position: panel.position)
            }()

            let currentRevealUntil = sidebarRevealUntilByDisplay[did] ?? 0
            let revealUntil = SidebarRuntimeEvaluator.updatedRevealUntil(
                currentRevealUntil: currentRevealUntil,
                now: now,
                defaultState: config.sidebarStateDefault,
                trigger: config.sidebarExpandTrigger,
                edgeHover: edgeHover,
                hoveringPanel: hoveringPanel,
                hasOverlay: hasAnyOverlay
            )
            sidebarRevealUntilByDisplay[did] = revealUntil

            let presentation = SidebarRuntimeEvaluator.presentation(
                defaultState: config.sidebarStateDefault,
                now: now,
                revealUntil: revealUntil
            )
            sidebarPresentationByDisplay[did] = presentation

            if panelManager.applySidebarPresentation(for: did, presentation: presentation, config: config) {
                geometryChanged = true
            }

            let targetAlpha: CGFloat = (presentation == .hidden) ? 0.04 : 1.0
            panel.ignoresMouseEvents = (presentation == .hidden)
            if abs(panel.alphaValue - targetAlpha) > 0.03 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.10
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = targetAlpha
                }
            } else {
                panel.alphaValue = targetAlpha
            }
        }

        sidebarRevealUntilByDisplay = sidebarRevealUntilByDisplay.filter { activeDisplays.contains($0.key) }
        sidebarPresentationByDisplay = sidebarPresentationByDisplay.filter { activeDisplays.contains($0.key) }
        return geometryChanged
    }

    private func handleSidebarPeekMouseDown(_ event: NSEvent) {
        guard config.sidebarModeEnabled,
              config.taskbarPosition.isVertical,
              config.sidebarStateDefault != .expanded else { return }
        guard config.sidebarExpandTrigger == .click || config.sidebarExpandTrigger == .hybrid else { return }

        let point = screenPointForEvent(event)
        let now = CFAbsoluteTimeGetCurrent()
        for panel in panelManager.allPanels where panel.position.isVertical {
            guard let screen = panel.screen else { continue }
            let did = panel.displayId
            let edgeHit = isPointAtSidebarEdge(point, on: screen, position: panel.position)
            let insidePanel = panel.frame.contains(point)
            let presentation = sidebarPresentationByDisplay[did]
                ?? SidebarRuntimeEvaluator.presentation(
                    defaultState: config.sidebarStateDefault,
                    now: now,
                    revealUntil: sidebarRevealUntilByDisplay[did] ?? 0
                )

            let shouldReveal: Bool = {
                switch config.sidebarStateDefault {
                case .hiddenPeek:
                    return edgeHit
                case .compactIcons:
                    // Click-to-expand should work from the compact bar surface, not only the edge strip.
                    return edgeHit || (presentation == .compact && insidePanel)
                case .expanded:
                    return false
                }
            }()

            if shouldReveal {
                let current = sidebarRevealUntilByDisplay[did] ?? 0
                sidebarRevealUntilByDisplay[did] = max(current, now + SidebarRuntimeEvaluator.revealDuration)
                let geometryChanged = updateSidebarPeekVisibility(now: now)
                if geometryChanged {
                    renderUI()
                    panelManager.resumeAllDisplayLinks()
                }
                break
            }
        }
    }

    private func isPointAtSidebarEdge(_ point: NSPoint, on screen: NSScreen, position: Position) -> Bool {
        let frame = screen.frame
        guard frame.insetBy(dx: -1, dy: -1).contains(point) else { return false }
        let edgeInset: CGFloat = 2.0
        switch position {
        case .left:
            return point.x <= frame.minX + edgeInset
        case .right:
            return point.x >= frame.maxX - edgeInset
        default:
            return false
        }
    }

    // MARK: - Plugins

    private func reloadPlugins() {
        loadedPlugins = pluginManager.loadPlugins(config: config)
        pluginCustomItems = pluginManager.customItems(from: loadedPlugins)
        pluginTiles = pluginManager.tiles(from: loadedPlugins)
        Task {
            await providerRuntime.resetProviders()
            await providerRuntime.registerProviders(from: loadedPlugins)
        }
        if !loadedPlugins.isEmpty {
            Log.plugins.info("Loaded \(self.loadedPlugins.count) plugins (\(self.pluginCustomItems.count) custom items, \(self.pluginTiles.count) tiles)")
        } else if config.pluginsEnabled {
            Log.plugins.info("Plugins enabled; none loaded")
        }
    }

    // MARK: - Config Reload

    func reloadConfig() {
        hideAllTabGroupOverlays()
        hideAllPreviews()
        hidePluginCard()
        hideSwitcher(commitSelection: false)
        let previousConfig = config
        config = Config.load(fallback: previousConfig)
        let requiresPanelRebuild = config.requiresPanelRebuild(comparedTo: previousConfig)
        PerformanceMonitor.shared.apply(config: config)
        thumbnailService.applyMemoryPreset(config.previewMemoryPreset)
        sidebarRevealUntilByDisplay.removeAll()
        sidebarPresentationByDisplay.removeAll()
        configureSwitcherHotkey()
        configureDisplayReconfigurationObserver()
        scheduleAXObserverRefresh(delay: 0.25)
        markWindowRefreshNeeded(invalidateCaches: true)
        userState = UserState.load()
        groupPreviewOrderByKey = userState.groupPreviewOrderByKey
        reloadPlugins()
        if requiresPanelRebuild {
            panelManager.rebuildPanels(config: config, renderer: renderer, preserveSuppression: true)
        }
        refreshSpaceKeyCache(displayIds: panelManager.allDisplayIds)
        renderUI()
        if requiresPanelRebuild {
            showPanelsAfterDelay()
        } else {
            panelManager.resumeAllDisplayLinks()
        }
        Log.config.info("Config reloaded")
    }

    private func configureDisplayReconfigurationObserver() {
        guard config.experimentalWindowLayoutMemoryEnabled else {
            displayReconfigurationObserver?.stop()
            displayReconfigurationObserver = nil
            cancelWindowLayoutMemoryRestoreWorkItems()
            windowLayoutMemoryService.clear()
            return
        }

        if displayReconfigurationObserver == nil {
            displayReconfigurationObserver = DisplayReconfigurationObserver { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleDisplayReconfiguration(event)
                }
            }
        }
        displayReconfigurationObserver?.start()
    }

    private func handleDisplayReconfiguration(_ event: DisplayReconfigurationObserver.Event) {
        guard config.experimentalWindowLayoutMemoryEnabled else { return }
        guard event.isBeginConfiguration else { return }
        windowLayoutMemoryService.captureBeforeDisplayChange()
    }

    private func scheduleAXObserverRefresh(delay: TimeInterval) {
        axObserverRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshAXObserverState()
        }
        axObserverRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshAXObserverState() {
        let axEnabled = AXIsProcessTrusted() && !isAXQueriesDisabledByEnv
        if axEnabled {
            if isAXObserverActive {
                refreshAXObserversMeasured()
            } else {
                PerformanceMonitor.shared.measureSegment("ax_observer_start", thresholdMs: 120.0) {
                    axObserverService.start { [weak self] batch in
                        guard let self else { return }
                        self.handleAXEventBatch(batch)
                    }
                }
                isAXObserverActive = true
            }
        } else if isAXObserverActive {
            axObserverService.stop()
            isAXObserverActive = false
        }
    }

    private func refreshAXObserversMeasured() {
        PerformanceMonitor.shared.measureSegment("ax_observer_refresh", thresholdMs: 120.0) {
            axObserverService.refreshObservedApps()
        }
    }

    private func handleAXEventBatch(_ batch: AXObserverService.EventBatch) {
        markWindowRefreshNeeded(invalidateCaches: batch.invalidatesEnumerationCaches)
        if batch.triggersWindowAdjustmentCheck {
            pendingAXWindowAdjustmentCheck = true
        }
        scheduleWorkspaceRefresh()
    }

    // MARK: - Space Key Cache

    private func refreshSpaceKeyCache(displayIds: [CGDirectDisplayID], completion: (() -> Void)? = nil) {
        guard !displayIds.isEmpty else {
            completion?()
            return
        }

        let previousSuppressedDisplays = Set(
            cachedCurrentSpaceInfoByDisplay.compactMap { displayId, info in
                PanelManager.shouldSuppressTaskbar(currentSpace: info) ? displayId : nil
            }
        )

        spacesService.fetchCurrentSpaceInfo(for: displayIds) { [weak self] infoByDisplay in
            guard let self else { return }

            for displayId in displayIds {
                if let info = infoByDisplay[displayId] {
                    self.cachedCurrentSpaceInfoByDisplay[displayId] = info
                    self.cachedSpaceKeyByDisplay[displayId] = info.key
                } else {
                    self.cachedCurrentSpaceInfoByDisplay.removeValue(forKey: displayId)
                    self.cachedSpaceKeyByDisplay.removeValue(forKey: displayId)
                }
            }

            self.panelManager.reconcileTaskbarSpaceState(
                currentSpaceInfoByDisplay: self.cachedCurrentSpaceInfoByDisplay,
                config: self.config,
                renderer: self.renderer
            )

            let currentSuppressedDisplays = Set(
                self.cachedCurrentSpaceInfoByDisplay.compactMap { displayId, info in
                    PanelManager.shouldSuppressTaskbar(currentSpace: info) ? displayId : nil
                }
            )

            // Per-space pins depend on Space key state; fullscreen suppression depends on
            // current space type. Either change needs an immediate UI pass.
            if self.config.pinnedAppsScope == .perSpace || currentSuppressedDisplays != previousSuppressedDisplays {
                self.renderUI()
            }
            completion?()
        }
    }

    // MARK: - Panel Visibility

    /// Fade in panels after a brief delay, giving the compositor time to
    /// register the window. Glass is created here (not in init) so
    /// CABackdropLayer has a live compositor to sample from.
    private func showPanelsAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            self.panelManager.pauseAllDisplayLinks()
            for panel in self.panelManager.allPanels {
                // Set theme before creating glass so CABackdropLayer
                // initializes with the correct appearance
                switch panel.theme {
                case .system: panel.appearance = nil
                case .light: panel.appearance = NSAppearance(named: .aqua)
                case .dark: panel.appearance = NSAppearance(named: .darkAqua)
                }
                panel.refreshGlass()
                // After glass is installed, clear the initialization background.
                // (We keep a nearly-clear color during init to help CABackdropLayer bootstrap.)
                panel.backgroundColor = .clear

                // Fade the bootstrap surface immediately so the first visible frame reads as glass,
                // not as an opaque window background. (Reduce Motion is handled inside the panel.)
                // Give CABackdropLayer a beat to warm up; fading too early can reveal a dark/opaque
                // frame on cold start on some machines.
                panel.fadeOutBootstrap(after: 0.20, duration: 0.18)
            }

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for panel in self.panelManager.allPanels {
                    panel.animator().alphaValue = 1
                }
            }

            self.panelManager.resumeAllDisplayLinks()
        }
    }

    // MARK: - Space Change

    /// Handle desktop space change (three-finger swipe, Mission Control, etc.).
    /// Forces an immediate re-poll to get the correct window set for the current
    /// space, and resumes all display links in case they paused during transition.
    private func handleSpaceChange() {
        // Expanded tab group overlays should not persist across Space transitions.
        hideAllTabGroupOverlays()
        hideAllPreviews()
        hidePluginCard()

        windowListStabilizer.noteSpaceChange()
        lastSpaceChangeAt = CFAbsoluteTimeGetCurrent()
        markWindowRefreshNeeded(invalidateCaches: true)

        // Coalesce burst re-polls across rapid space switches.
        spaceChangeToken &+= 1
        let token = spaceChangeToken

        // Space transitions can leave retained layer presentation stale; refresh + force sync.
        for panel in panelManager.allPanels {
            panel.refreshRetainedLayers()
            renderer.forceRedraw(displayId: panel.displayId)
        }

        // Immediate poll.
        pollAndUpdate(forceRender: true)
        panelManager.resumeAllDisplayLinks()

        // Burst re-polling: CGWindowList can transiently return 0 windows during
        // three-finger swipes. Keep the recovery burst sparse enough that slow
        // WindowServer replies do not stack on the main queue during the swipe.
        for delay in Self.spaceChangeRecoveryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.spaceChangeToken == token else { return }
                self.pollAndUpdate(forceRender: true)
            }
        }

        // Refresh per-display Space keys after the transition settles. This keeps
        // per-space pinned apps accurate without doing extra work during swipe.
        let keyRefreshDelays: [TimeInterval] = [0.0, 0.25, 0.75]
        for delay in keyRefreshDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.spaceChangeToken == token else { return }
                self.refreshSpaceKeyCache(displayIds: self.panelManager.allDisplayIds)
            }
        }

        Log.event.info("Space changed — re-polled and resumed display links")
    }

    // MARK: - Screen Change

    func handleScreenParametersChanged() {
        hideAllTabGroupOverlays()
        hideAllPreviews()
        hidePluginCard()
        hideSwitcher(commitSelection: false)

        windowListStabilizer.noteSpaceChange()
        let now = CFAbsoluteTimeGetCurrent()
        lastSpaceChangeAt = now
        lastScreenParametersChangeAt = now
        screenChangeToken &+= 1
        let token = screenChangeToken
        let displayCountBeforeReconcile = panelManager.allPanels.count

        knownWindowIds.removeAll(keepingCapacity: true)
        lastWindowPositions.removeAll(keepingCapacity: true)
        lastAdjustCheck = now
        pendingAXWindowAdjustmentCheck = false
        pruneDisplayScopedStateToActivePanels()
        markWindowRefreshNeeded(invalidateCaches: true)

        runScreenChangeRecoveryPass(token: token)

        for delay in Self.screenChangeRecoveryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.screenChangeToken == token else { return }
                self.runScreenChangeRecoveryPass(token: token)
            }
        }

        scheduleWindowLayoutMemoryRestorePasses(token: token)

        PerformanceMonitor.shared.recordDiagnosticSnapshot(
            "screen_change",
            minIntervalSeconds: 0.25
        ) {
            "token=\(token) displays_before=\(displayCountBeforeReconcile) suppress_adjust_ms=\(Self.fmt2(Self.screenChangeAdjustmentSuppression * 1000.0))"
        }
        Log.event.info("Screen parameters changed — scheduled panel recovery and suppressed window adjustment")
    }

    private func scheduleWindowLayoutMemoryRestorePasses(token: UInt64) {
        guard config.experimentalWindowLayoutMemoryEnabled else { return }
        cancelWindowLayoutMemoryRestoreWorkItems()

        let delays: [TimeInterval] = [1.20, 2.80, 5.50, 10.0]
        for (index, delay) in delays.enumerated() {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.screenChangeToken == token else { return }
                guard self.config.experimentalWindowLayoutMemoryEnabled else { return }

                let summary = self.windowLayoutMemoryService.restoreAfterDisplayChangeIfPossible()
                if index == delays.count - 1, summary.remainingWindowCount > 0 {
                    self.windowLayoutMemoryService.clear()
                }

                guard summary.restoredWindowCount > 0 else { return }
                self.markWindowRefreshNeeded(invalidateCaches: true)
                self.pollAndUpdate(forceRender: true)
                self.panelManager.resumeAllDisplayLinks()
            }
            windowLayoutMemoryRestoreWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelWindowLayoutMemoryRestoreWorkItems() {
        for work in windowLayoutMemoryRestoreWorkItems {
            work.cancel()
        }
        windowLayoutMemoryRestoreWorkItems.removeAll()
    }

    private func runScreenChangeRecoveryPass(token: UInt64) {
        guard screenChangeToken == token else { return }

        let reconcileResult = panelManager.reconcilePanelsForCurrentScreens(config: config, renderer: renderer)
        if reconcileResult == .rebuilt {
            lastBarViewDataSnapshotByDisplay.removeAll(keepingCapacity: true)
            lastBarViewIdentityByDisplay.removeAll(keepingCapacity: true)
            if isBarHidden {
                setBarHidden(true)
            } else {
                showPanelsAfterDelay()
            }
        }

        pruneDisplayScopedStateToActivePanels()
        markWindowRefreshNeeded(invalidateCaches: true)

        refreshSpaceKeyCache(displayIds: panelManager.allDisplayIds) { [weak self] in
            guard let self else { return }
            guard self.screenChangeToken == token else { return }
            self.pollAndUpdate(forceRender: true)
            self.panelManager.resumeAllDisplayLinks()
        }
    }

    private func pruneDisplayScopedStateToActivePanels() {
        let activeDisplayIds = Set(panelManager.allDisplayIds)
        cachedSpaceKeyByDisplay = cachedSpaceKeyByDisplay.filter { activeDisplayIds.contains($0.key) }
        cachedCurrentSpaceInfoByDisplay = cachedCurrentSpaceInfoByDisplay.filter { activeDisplayIds.contains($0.key) }
        pinnedBundleIdsByDisplay = pinnedBundleIdsByDisplay.filter { activeDisplayIds.contains($0.key) }
        sidebarRevealUntilByDisplay = sidebarRevealUntilByDisplay.filter { activeDisplayIds.contains($0.key) }
        sidebarPresentationByDisplay = sidebarPresentationByDisplay.filter { activeDisplayIds.contains($0.key) }
        lastBarViewDataSnapshotByDisplay = lastBarViewDataSnapshotByDisplay.filter { activeDisplayIds.contains($0.key) }
        lastBarViewIdentityByDisplay = lastBarViewIdentityByDisplay.filter { activeDisplayIds.contains($0.key) }
    }

    #if DEBUG
    func debugHideAllPreviews() {
        hideAllPreviews()
    }

    func debugHideGroupPreview(displayId: CGDirectDisplayID, immediate: Bool = false) {
        hideGroupPreview(displayId: displayId, immediate: immediate)
    }

    func debugHideSwitcher(commitSelection: Bool = false) {
        hideSwitcher(commitSelection: commitSelection)
    }

    @discardableResult
    func debugEnqueueThumbnailRequest(
        windowId: UInt32,
        targetSizePoints: CGSize,
        producer: WindowThumbnailService.ThumbnailProducer
    ) -> WindowThumbnailService.CaptureRequest? {
        thumbnailService.debugEnqueueRequest(
            windowId: CGWindowID(windowId),
            targetSizePoints: targetSizePoints,
            producer: producer
        )
    }

    func debugQueuedThumbnailRequests() -> [WindowThumbnailService.CaptureRequest] {
        thumbnailService.debugQueuedRequests()
    }

    func debugStoreCachedThumbnail(
        windowId: UInt32,
        sizePoints: CGSize,
        screenScale: CGFloat = 2.0,
        capturedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        thumbnailService.debugStoreCachedThumbnail(
            windowId: CGWindowID(windowId),
            targetSizePoints: sizePoints,
            image: NSImage(size: sizePoints),
            capturedAt: capturedAt,
            screenScale: screenScale
        )
    }

    func debugStoreLastGoodThumbnail(
        windowId: UInt32,
        sizePoints: CGSize,
        screenScale: CGFloat = 2.0,
        capturedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        thumbnailService.debugStoreLastGoodThumbnail(
            windowId: CGWindowID(windowId),
            image: NSImage(size: sizePoints),
            sizePoints: sizePoints,
            capturedAt: capturedAt,
            screenScale: screenScale
        )
    }

    func debugCachedThumbnailWindowIds(for tier: WindowThumbnailService.ThumbnailTier) -> [UInt32] {
        thumbnailService.debugCachedWindowIds(for: tier).map { UInt32($0) }
    }

    func debugLastGoodThumbnailWindowIds() -> [UInt32] {
        thumbnailService.debugLastGoodWindowIds().map { UInt32($0) }
    }

    func debugSyncThumbnailLifecycleToLiveWindowIds(_ liveWindowIds: Set<UInt32>) {
        syncThumbnailLifecycleToLiveWindowIds(liveWindowIds)
    }

    private func installTestControl() {
        guard ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_CONTROL"] == "1" else { return }

        let center = DistributedNotificationCenter.default()
        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.spaceChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSpaceChange()
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.reloadConfig"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadConfig()
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.setHoverIndex"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let idx = (note.object as? String).flatMap(Int.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                for panel in self.panelManager.allPanels {
                    let displayId = panel.displayId
                    panel.barView.setTestHoverIndex(idx)
                    self.renderer.setHoveredItemIndex(idx, for: displayId)
                    if let idx,
                       idx >= 0,
                       idx < panel.barView.visualItemRects.count {
                        _ = self.renderer.setHoverRect(panel.barView.visualItemRects[idx], for: displayId)
                    } else {
                        _ = self.renderer.setHoverRect(nil, for: displayId)
                    }
                    self.handlePreviewHover(displayId: displayId, hoverIndex: idx, panel: panel)
                    self.panelManager.resumeDisplayLink(for: displayId)
                }
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.setCursorPoint"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.object as? String
            let point: SIMD2<Float>? = {
                guard let raw, !raw.isEmpty else { return nil }
                let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2,
                      let x = Float(parts[0]),
                      let y = Float(parts[1]) else { return nil }
                return SIMD2<Float>(x, y)
            }()
            MainActor.assumeIsolated {
                guard let self else { return }
                for panel in self.panelManager.allPanels {
                    self.renderer.setCursorPosition(point, for: panel.displayId)
                }
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.dragState"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = (note.object as? String)?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            MainActor.assumeIsolated {
                guard let self, let raw, let command = raw.first else { return }
                switch command {
                case "start":
                    guard raw.count >= 4,
                          let sourceIndex = Int(raw[1]),
                          let cursorPrimary = Float(raw[2]),
                          let cursorOffset = Float(raw[3]) else { return }
                    MouseTracker.setDragging(true)
                    for panel in self.panelManager.allPanels {
                        self.renderer.startDrag(
                            sourceIndex: sourceIndex,
                            cursorX: cursorPrimary,
                            cursorOffsetInItem: cursorOffset,
                            config: self.config,
                            displayId: panel.displayId
                        )
                        if raw.count >= 5, let insertionIndex = Int(raw[4]) {
                            self.renderer.updateDragCursor(
                                cursorX: cursorPrimary,
                                insertionIndex: insertionIndex,
                                displayId: panel.displayId
                            )
                        }
                        self.panelManager.resumeDisplayLink(for: panel.displayId)
                    }
                case "update":
                    guard raw.count >= 3,
                          let cursorPrimary = Float(raw[1]),
                          let insertionIndex = Int(raw[2]) else { return }
                    MouseTracker.setDragging(true)
                    for panel in self.panelManager.allPanels {
                        self.renderer.updateDragCursor(
                            cursorX: cursorPrimary,
                            insertionIndex: insertionIndex,
                            displayId: panel.displayId
                        )
                        self.panelManager.resumeDisplayLink(for: panel.displayId)
                    }
                case "end":
                    MouseTracker.setDragging(false)
                    for panel in self.panelManager.allPanels {
                        self.renderer.endDrag(displayId: panel.displayId)
                        self.panelManager.resumeDisplayLink(for: panel.displayId)
                    }
                case "cancel":
                    MouseTracker.setDragging(false)
                    for panel in self.panelManager.allPanels {
                        self.renderer.cancelDrag(displayId: panel.displayId)
                        self.panelManager.resumeDisplayLink(for: panel.displayId)
                    }
                default:
                    return
                }
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.setSpaceId"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let key = note.object as? String
            MainActor.assumeIsolated {
                if let key, !key.isEmpty {
                    SpacesService.testSpaceIdOverride = key
                } else {
                    SpacesService.testSpaceIdOverride = nil
                }

                // Keep UI tests deterministic: update the in-memory per-display Space key
                // cache immediately instead of waiting for async space-key refresh polling.
                guard let self else { return }
                let fallbackEnv = ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_SPACE_ID"]
                let resolved = (key?.isEmpty == false) ? key : fallbackEnv
                if let resolved, !resolved.isEmpty {
                    for did in self.panelManager.allDisplayIds {
                        self.cachedSpaceKeyByDisplay[did] = resolved
                    }
                    if self.config.pinnedAppsScope == .perSpace {
                        self.renderUI()
                        self.panelManager.resumeAllDisplayLinks()
                    }
                }
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.switcher"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.object as? String
            MainActor.assumeIsolated {
                self?.handleSwitcherTestControl(raw)
            }
        })

        testControlObservers.append(center.addObserver(
            forName: Notification.Name("com.liquidbar.testcontrol.dumpSnapshot"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let path = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let path, !path.isEmpty else { return }
                self.dumpDebugSnapshot(to: path)
            }
        })
    }

    private func handleSwitcherTestControl(_ raw: String?) {
        let parts = (raw ?? "open")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let command = parts.first?.lowercased() ?? "open"
        let start = CACurrentMediaTime()
        let previousEntries = switcherEntries.count
        var count = 1
        var direction = 0
        var success = false

        switch command {
        case "open", "begin":
            direction = Self.testControlDirection(parts.dropFirst().first)
            success = beginSwitcherSession(initialDirection: direction == 0 ? 1 : direction, scheduleCommit: false)

        case "cycle":
            guard switcherPanel?.isVisible == true, !switcherEntries.isEmpty else {
                break
            }
            count = max(1, parts.dropFirst().first.flatMap(Int.init) ?? 1)
            direction = Self.testControlDirection(parts.dropFirst(2).first)
            if direction == 0 { direction = 1 }
            for _ in 0..<count {
                cycleSwitcherSelection(direction: direction)
            }
            success = true

        case "close", "cancel":
            hideSwitcher(commitSelection: false)
            success = true

        case "commit":
            hideSwitcher(commitSelection: true)
            success = true

        default:
            success = false
        }

        let durationMs = (CACurrentMediaTime() - start) * 1000.0
        let entries = switcherEntries.isEmpty ? previousEntries : switcherEntries.count
        PerformanceMonitor.shared.recordSwitcherAction(
            action: command,
            durationMs: durationMs,
            count: count,
            direction: direction,
            entries: entries,
            selectedIndex: switcherSelectedIndex,
            success: success
        )
    }

    private nonisolated static func testControlDirection(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        switch raw.lowercased() {
        case "-1", "reverse", "backward", "backwards":
            return -1
        case "1", "+1", "forward", "forwards":
            return 1
        default:
            return Int(raw) ?? 0
        }
    }

    private func dumpDebugSnapshot(to path: String) {
        let cfg = LiquidBarDebugSnapshot.DebugConfig(
            itemSizing: config.itemSizing.rawValue,
            iconSize: config.iconSize,
            fontSize: config.fontSize,
            iconsOnly: config.iconsOnly,
            windowDisplayMode: config.windowDisplayMode.rawValue,
            pinnedAppsScope: config.pinnedAppsScope.rawValue,
            showHiddenApps: config.showHiddenApps,
            adjustWindowsForTaskbar: config.adjustWindowsForTaskbar,
            tabbedTaskbarEnabled: config.tabbedTaskbarEnabled,
            windowTabGroupsEnabled: config.windowTabGroupsEnabled,
            previewsEnabled: config.previewsEnabled
        )

        var panels: [LiquidBarDebugSnapshot.Panel] = []
        panels.reserveCapacity(panelManager.allPanels.count)

        for panel in panelManager.allPanels {
            let displayId = panel.displayId

            let hoverRectNS = renderer.debugHoverRect(displayId: displayId)
            let hoverRect = hoverRectNS.map(LiquidBarDebugSnapshot.Rect.init)
            let cursorPointNS = renderer.debugCursorPoint(displayId: displayId)
            let cursorPoint = cursorPointNS.map(LiquidBarDebugSnapshot.Point.init)
            let previewPanel = previewPanelByDisplay[displayId]
            let groupPreviewPanel = groupPreviewPanelByDisplay[displayId]
            let tabGroupOverlay = tabGroupOverlayByDisplay[displayId]
            let sidebarPresentation = sidebarPresentationByDisplay[displayId]?.rawValue
            let pluginCardVisible = (pluginCardDisplayId == displayId) && (pluginCardPanel?.isVisible == true)
            let pluginCardTileId = pluginCardVisible ? self.pluginCardTileId : nil
            let hoverCursorNormalized: LiquidBarDebugSnapshot.Point? = {
                guard let hoverRectNS, let cursorPointNS else { return nil }
                guard hoverRectNS.width > 1, hoverRectNS.height > 1 else { return nil }
                let nx = (cursorPointNS.x - hoverRectNS.minX) / hoverRectNS.width
                let ny = (cursorPointNS.y - hoverRectNS.minY) / hoverRectNS.height
                guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return nil }
                return LiquidBarDebugSnapshot.Point(x: nx, y: ny)
            }()

            var items: [LiquidBarDebugSnapshot.Item] = []
            let panelItems = itemsForDisplay(displayId)
            items.reserveCapacity(panelItems.count)

            for (idx, item) in panelItems.enumerated() {
                let kind: String
                var windowId: UInt32? = nil
                var title: String? = nil
                switch item {
                case .window(let id, _, let t, _, _, _, _):
                    kind = "window"
                    windowId = id.raw
                    title = t
                case .appGroup:
                    kind = "app_group"
                case .pinnedApp:
                    kind = "pinned_app"
                case .launcher:
                    kind = "launcher"
                    title = item.displayTitle(iconsOnly: false)
                case .pluginTile:
                    kind = "plugin_tile"
                    title = item.displayTitle(iconsOnly: false)
                case .tabGroup:
                    kind = "tab_group"
                    title = item.displayTitle(iconsOnly: false)
                case .customSpacer:
                    kind = "custom_spacer"
                    title = item.displayTitle(iconsOnly: false)
                case .customText:
                    kind = "custom_text"
                    title = item.displayTitle(iconsOnly: false)
                case .customLink:
                    kind = "custom_link"
                    title = item.displayTitle(iconsOnly: false)
                case .customFolder:
                    kind = "custom_folder"
                    title = item.displayTitle(iconsOnly: false)
                }

                let accessibilityId: String
                switch item {
                case .window(let id, _, _, _, _, _, _):
                    accessibilityId = "liquidbar.item.window.\(id.raw)"
                case .appGroup(let bundleId, _, _, _, _, _, _):
                    accessibilityId = "liquidbar.item.group.\(bundleId)"
                case .pinnedApp(let bundleId, _):
                    accessibilityId = "liquidbar.item.pinned.\(bundleId)"
                case .launcher:
                    accessibilityId = "liquidbar.item.launcher"
                case .pluginTile(let id, _, _, _, _, _):
                    accessibilityId = "liquidbar.item.plugin.\(id)"
                case .tabGroup(let groupId, _, _, _, _, _, _, _):
                    accessibilityId = "liquidbar.item.tabgroup.\(groupId)"
                case .customSpacer(let id, _, _):
                    accessibilityId = "liquidbar.item.custom.spacer.\(id)"
                case .customText(let id, _, _):
                    accessibilityId = "liquidbar.item.custom.text.\(id)"
                case .customLink(let id, _, _, _, _):
                    accessibilityId = "liquidbar.item.custom.link.\(id)"
                case .customFolder(let id, _, _, _, _):
                    accessibilityId = "liquidbar.item.custom.folder.\(id)"
                }

                let visualRect: LiquidBarDebugSnapshot.Rect?
                if idx < panel.barView.visualItemRects.count {
                    visualRect = LiquidBarDebugSnapshot.Rect(panel.barView.visualItemRects[idx])
                } else {
                    visualRect = nil
                }

                let hitRect: LiquidBarDebugSnapshot.Rect?
                if idx < panel.barView.itemRects.count {
                    hitRect = LiquidBarDebugSnapshot.Rect(panel.barView.itemRects[idx].rect)
                } else {
                    hitRect = nil
                }

                items.append(LiquidBarDebugSnapshot.Item(
                    index: idx,
                    accessibilityId: accessibilityId,
                    kind: kind,
                    bundleId: item.bundleId,
                    windowId: windowId,
                    title: title,
                    displayTitle: item.displayTitle(iconsOnly: false),
                    visualRect: visualRect,
                    hitRect: hitRect
                ))
            }

            let bgAlpha = panel.backgroundColor.map { Double($0.alphaComponent) }

            panels.append(LiquidBarDebugSnapshot.Panel(
                displayId: UInt32(displayId),
                frame: LiquidBarDebugSnapshot.Rect(panel.frame),
                barBounds: LiquidBarDebugSnapshot.Rect(panel.barView.bounds),
                sidebarPresentation: sidebarPresentation,
                windowIsOpaque: panel.isOpaque,
                windowAlphaValue: panel.alphaValue,
                windowBackgroundAlpha: bgAlpha,
                hoverRect: hoverRect,
                cursorPoint: cursorPoint,
                hoverCursorNormalized: hoverCursorNormalized,
                previewVisible: previewPanel?.isVisible == true,
                previewWindowId: previewHoveredWindowIdByDisplay[displayId],
                groupPreviewVisible: groupPreviewPanel?.isVisible == true,
                groupPreviewKey: groupPreviewActiveKeyByDisplay[displayId],
                tabGroupOverlayVisible: tabGroupOverlay?.isVisible == true,
                tabGroupOverlayId: tabGroupOverlay?.tabGroupId,
                pluginCardVisible: pluginCardVisible,
                pluginCardTileId: pluginCardTileId,
                items: items
            ))
        }

        let snapshot = LiquidBarDebugSnapshot(
            timestamp: Date().timeIntervalSince1970,
            config: cfg,
            panels: panels
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            Log.event.error("Failed to dump debug snapshot to \(path): \(error)")
        }
    }
    #endif

    // MARK: - Window Adjustment

    private func adjustWindows() {
        let panelInfos = panelManager.allPanels.map { panel in
            AccessibilityService.PanelInfo(
                displayId: panel.displayId,
                frame: panel.frame,
                position: panel.position
            )
        }
        AccessibilityService.adjustWindowsForTaskbar(panels: panelInfos)
    }

    // MARK: - Helpers

    private func itemsForDisplay(_ displayId: CGDirectDisplayID) -> [TaskbarItem] {
        switch config.windowDisplayMode {
        case .perDisplay:
            return currentItems.filter { item in
                if let sid = item.screenId { return sid == displayId }
                return true
            }
        case .allWindows:
            return currentItems.filter { item in
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
    }

    private func checkForMovedWindows(_ windows: [WindowInfo]) -> Bool {
        for w in windows {
            if let old = lastWindowPositions[w.id.raw] {
                let dx = abs(w.bounds.x - old.x)
                let dy = abs(w.bounds.y - old.y)
                if dx > 5 || dy > 5 { return true }
            }
        }
        return false
    }

    private func updateWindowPositions(_ windows: [WindowInfo]) {
        lastWindowPositions.removeAll(keepingCapacity: true)
        for w in windows {
            lastWindowPositions[w.id.raw] = (w.bounds.x, w.bounds.y, w.bounds.width, w.bounds.height)
        }
    }
}
