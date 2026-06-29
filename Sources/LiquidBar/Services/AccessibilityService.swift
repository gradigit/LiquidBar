import Cocoa
import ApplicationServices
import Darwin

@MainActor
final class AccessibilityService {
    private static var didPromptThisRun: Bool = false
    private struct AdjustmentKey: Hashable {
        let pid: pid_t
        let windowId: UInt32
    }
    private struct AdjustmentRecord {
        let targetX: CGFloat
        let targetY: CGFloat
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        let appliedAt: CFAbsoluteTime
    }
    private static var recentAdjustments: [AdjustmentKey: AdjustmentRecord] = [:]
    private static let adjustTolerance: CGFloat = 1.0
    private static let adjustCooldown: CFTimeInterval = 0.40
    private static let adjustmentMinHeight: CGFloat = 100.0
    private static let adjustmentCacheTTL: CFTimeInterval = 8.0
    private static let matchedFocusMaxAttempts = 4

    private enum FocusFailureReason: String {
        case windowMissing
        case verificationFailed
    }

    enum FocusPlanStrategy: String, Equatable {
        case axTarget
        case axAppHandoff
        case frontWindowOnly
        case stop
    }

    struct WindowScopedFocusPlan: Equatable {
        let matchedStrategies: [FocusPlanStrategy]
        let unmatchedStrategies: [FocusPlanStrategy]
    }

    struct WindowLookupResult: Equatable {
        let pid: pid_t
        let bounds: CGRect
        let title: String
    }

    private enum FrontmostWindowVerification {
        case exactMatch
        case wrongWindow
        case windowIdUnavailable
        case wrongApplication
    }

    struct FocusWindowRoutingHooks {
        var findOnScreenWindow: (UInt32) -> WindowLookupResult?
        var findOffScreenWindow: (UInt32) -> WindowLookupResult?
        var bundleIdForPid: (pid_t) -> String
        var createApplicationElement: (pid_t) -> AXUIElement
        var copyWindows: (AXUIElement) -> CFArray?
        var matchWindow: (CFArray, UInt32, CGRect, String) -> AXUIElement?
        var focusMatched: (AXUIElement, AXUIElement, pid_t, String, UInt32?) -> Void
        var focusUnmatched: (pid_t, String, UInt32) -> Void
    }

    #if DEBUG
    private static var debugFocusWindowRoutingHooks: FocusWindowRoutingHooks?
    #endif

    static func requestPermission() {
        // Avoid spamming the system prompt; once per launch is enough.
        guard !didPromptThisRun else { return }
        didPromptThisRun = true

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Focus Window

    static func strictWindowScopedFocusPlan(bundleId: String) -> WindowScopedFocusPlan {
        WindowScopedFocusPlan(
            matchedStrategies: [
                .axTarget,
                .axAppHandoff,
                .frontWindowOnly,
                .stop,
            ],
            unmatchedStrategies: [
                .frontWindowOnly,
                .stop,
            ]
        )
    }

    static func focusWindow(windowId: UInt32) {
        if focusOwnAppSwitcherWindow(windowId: windowId) {
            return
        }

        let hooks = currentFocusWindowRoutingHooks()
        guard let window = hooks.findOnScreenWindow(windowId) ?? hooks.findOffScreenWindow(windowId) else { return }
        let bundleId = hooks.bundleIdForPid(window.pid)
        let appEl = hooks.createApplicationElement(window.pid)

        if let axWindows = hooks.copyWindows(appEl),
           let axWin = hooks.matchWindow(
               axWindows,
               windowId,
               window.bounds,
               window.title
           ) {
            hooks.focusMatched(
                appEl,
                axWin,
                window.pid,
                bundleId,
                windowId
            )
        } else {
            hooks.focusUnmatched(window.pid, bundleId, windowId)
        }
    }

    /// Returns the frontmost window's CGWindowID when available.
    /// Useful for scroll-wheel window cycling without maintaining our own focus state.
    static func focusedWindowId() -> UInt32? {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_FOCUSED_WINDOW_ID"],
           let n = UInt32(raw),
           n != 0 {
            return n
        }
        #endif

        return frontmostWindowIdForFrontmostApp()
    }

    /// Best-effort fallback when AX focus can't be resolved: returns the frontmost
    /// on-screen layer-0 window id.
    ///
    /// This uses the documented front-to-back ordering of `CGWindowListCopyWindowInfo`.
    static func frontmostWindowIdForFrontmostApp() -> UInt32? {
        frontmostOnScreenWindowCandidate()?.windowId
    }

    private static func frontmostOnScreenWindowCandidate() -> (pid: pid_t, windowId: UInt32)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let ownSwitcherWindowIds = ownAppSwitcherWindowIds()
        for dict in windowList {
            let layer = parseInt(dict[kCGWindowLayer as CFString]) ?? 0
            guard layer == 0 else { continue }
            guard let ownerPid = parsePid(dict[kCGWindowOwnerPID as CFString]),
                  let windowId = parseWindowNumber(dict[kCGWindowNumber as CFString]) else {
                continue
            }
            if ownerPid == ownPid, !ownSwitcherWindowIds.contains(windowId) {
                continue
            }
            return (pid: ownerPid, windowId: windowId)
        }

        return nil
    }

    static func isOwnAppSwitcherWindow(_ window: NSWindow) -> Bool {
        isOwnAppSwitcherWindow(
            isPanel: window is NSPanel,
            styleMask: window.styleMask,
            collectionBehavior: window.collectionBehavior,
            canBecomeKey: window.canBecomeKey
        )
    }

    static func isOwnAppSwitcherWindow(
        isPanel: Bool,
        styleMask: NSWindow.StyleMask,
        collectionBehavior: NSWindow.CollectionBehavior,
        canBecomeKey: Bool
    ) -> Bool {
        if isPanel { return false }
        if collectionBehavior.contains(.ignoresCycle) { return false }
        if !styleMask.contains(.titled) { return false }
        return canBecomeKey
    }

    static func ownAppWindowId(windowNumber: Int) -> UInt32? {
        WindowNumber.appKitWindowNumber(windowNumber)
    }

    private static func ownAppSwitcherWindowIds() -> Set<UInt32> {
        guard let app = NSApp else { return [] }
        return Set(app.windows.compactMap { window in
            guard window.isVisible,
                  !window.isMiniaturized,
                  isOwnAppSwitcherWindow(window),
                  let windowId = ownAppWindowId(windowNumber: window.windowNumber) else {
                return nil
            }
            return windowId
        })
    }

    @discardableResult
    private static func focusOwnAppSwitcherWindow(windowId: UInt32) -> Bool {
        guard let app = NSApp,
              let window = app.windows.first(where: {
            isOwnAppSwitcherWindow($0)
                && ownAppWindowId(windowNumber: $0.windowNumber) == windowId
        }) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - Close Window

    /// Close a window without focusing it. Uses Cmd+W via CGEvent to avoid the
    /// focus flash that AX close button press causes on background windows.
    /// Falls back to AX close button + re-focus if CGEvent approach fails.
    static func closeWindow(windowId: UInt32) {
        guard let (pid, bounds, title) = findCGWindow(windowId: windowId) else { return }

        // Use AX close button — this closes the window without focusing the app.
        // Cmd+W (sendCmdW) causes macOS to bring the app to the foreground.
        let appEl = AXUIElementCreateApplication(pid)
        guard let axWindows = copyAXWindows(appEl) else {
            // AX unavailable — fall back to Cmd+W
            _ = sendCmdW(to: pid)
            return
        }

        if let axWin = matchAXWindow(
            in: axWindows,
            targetWindowId: windowId,
            targetBounds: bounds,
            targetTitle: title
        ) {
            var closeButton: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeButton)
            if let btn = axElement(from: closeButton) {
                AXUIElementPerformAction(btn, kAXPressAction as CFString)
            } else {
                // No close button (e.g. dialog) — fall back to Cmd+W
                _ = sendCmdW(to: pid)
            }
            return
        }

        // Window not found via deterministic AX matching — fall back to Cmd+W
        _ = sendCmdW(to: pid)
    }

    /// Send Cmd+W keypress to a specific process. Returns true if the event was posted.
    private static func sendCmdW(to pid: pid_t) -> Bool {
        // Key code 13 = W on US keyboard layout
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    // MARK: - Launcher helpers

    /// Open Apple's Spotlight app directly, independent of the user's Cmd+Space binding.
    static func openSpotlight() {
        launchApp(bundleId: "com.apple.Spotlight")
    }

    // MARK: - Adjust Windows for Taskbar

    struct PanelInfo: Sendable {
        let displayId: CGDirectDisplayID
        let frame: NSRect
        let position: Position
    }

    struct WindowAdjustmentPlan: Equatable, Sendable {
        let originalFrame: CGRect
        let targetFrame: CGRect
        let usableFrame: CGRect
        let needsMove: Bool
        let needsResize: Bool
    }

    struct RestorableWindowSnapshot: Equatable, Sendable {
        let pid: pid_t
        let bundleId: String
        let windowId: UInt32
        let title: String
        let frame: CGRect
        let displayUUID: String
    }

    struct RestorableLiveWindow: Equatable, Sendable {
        let pid: pid_t
        let windowId: UInt32
        let frame: CGRect
        let title: String
    }

    struct RestorableWindowRestoreBatchResult: Equatable, Sendable {
        let completedSnapshots: [RestorableWindowSnapshot]
        let restoredWindowCount: Int

        var completedWindowCount: Int {
            completedSnapshots.count
        }
    }

    struct WindowAdjustmentPlanner: Sendable {
        let tolerance: CGFloat
        let minimumSize: CGFloat

        init(tolerance: CGFloat = 1.0, minimumSize: CGFloat = 100.0) {
            self.tolerance = tolerance
            self.minimumSize = minimumSize
        }

        func plan(
            forWindowFrame windowFrame: CGRect,
            panel: PanelInfo,
            screenCGBounds: CGRect,
            screenNSFrame: NSRect
        ) -> WindowAdjustmentPlan? {
            guard let usableFrame = usableFrame(
                panel: panel,
                screenCGBounds: screenCGBounds,
                screenNSFrame: screenNSFrame
            ) else {
                return nil
            }

            let overlapsLeft = windowFrame.minX < (usableFrame.minX - tolerance)
            let overlapsRight = windowFrame.maxX > (usableFrame.maxX + tolerance)
            let overlapsTop = windowFrame.minY < (usableFrame.minY - tolerance)
            let overlapsBottom = windowFrame.maxY > (usableFrame.maxY + tolerance)
            let tooWide = windowFrame.width > (usableFrame.width + tolerance)
            let tooTall = windowFrame.height > (usableFrame.height + tolerance)
            guard overlapsLeft || overlapsRight || overlapsTop || overlapsBottom || tooWide || tooTall else {
                return nil
            }

            var newX = windowFrame.origin.x
            var newY = windowFrame.origin.y
            var newW = windowFrame.width
            var newH = windowFrame.height

            if newX < usableFrame.minX { newX = usableFrame.minX }
            if newY < usableFrame.minY { newY = usableFrame.minY }

            let maxWidthAtX = usableFrame.maxX - newX
            let maxHeightAtY = usableFrame.maxY - newY
            if newW > maxWidthAtX { newW = maxWidthAtX }
            if newH > maxHeightAtY { newH = maxHeightAtY }

            if newW < minimumSize {
                newW = min(max(minimumSize, newW), usableFrame.width)
                newX = max(usableFrame.minX, usableFrame.maxX - newW)
            }
            if newH < minimumSize {
                newH = min(max(minimumSize, newH), usableFrame.height)
                newY = max(usableFrame.minY, usableFrame.maxY - newH)
            }

            if newX + newW > usableFrame.maxX { newX = usableFrame.maxX - newW }
            if newY + newH > usableFrame.maxY { newY = usableFrame.maxY - newH }

            if newX < usableFrame.minX {
                newX = usableFrame.minX
                newW = min(newW, usableFrame.width)
            }
            if newY < usableFrame.minY {
                newY = usableFrame.minY
                newH = min(newH, usableFrame.height)
            }

            guard newW >= minimumSize, newH >= minimumSize else { return nil }

            let targetFrame = CGRect(x: newX, y: newY, width: newW, height: newH)
            let needsMove = abs(targetFrame.origin.x - windowFrame.origin.x) > tolerance
                || abs(targetFrame.origin.y - windowFrame.origin.y) > tolerance
            let needsResize = abs(targetFrame.width - windowFrame.width) > tolerance
                || abs(targetFrame.height - windowFrame.height) > tolerance
            guard needsMove || needsResize else { return nil }

            return WindowAdjustmentPlan(
                originalFrame: windowFrame,
                targetFrame: targetFrame,
                usableFrame: usableFrame,
                needsMove: needsMove,
                needsResize: needsResize
            )
        }

        func usableFrame(
            panel: PanelInfo,
            screenCGBounds: CGRect,
            screenNSFrame: NSRect
        ) -> CGRect? {
            let panelInsetFromTop = max(0, screenNSFrame.maxY - panel.frame.minY)
            let panelInsetFromBottom = max(0, panel.frame.maxY - screenNSFrame.minY)
            let panelInsetFromLeft = max(0, panel.frame.maxX - screenNSFrame.minX)
            let panelInsetFromRight = max(0, screenNSFrame.maxX - panel.frame.minX)

            let clampedTopInset = min(panelInsetFromTop, screenCGBounds.height)
            let clampedBottomInset = min(panelInsetFromBottom, screenCGBounds.height)
            let clampedLeftInset = min(panelInsetFromLeft, screenCGBounds.width)
            let clampedRightInset = min(panelInsetFromRight, screenCGBounds.width)

            let reservedLeft: CGFloat
            let reservedRight: CGFloat
            let reservedTop: CGFloat
            let reservedBottom: CGFloat
            switch panel.position {
            case .top:
                reservedLeft = screenCGBounds.minX
                reservedRight = screenCGBounds.maxX
                reservedTop = screenCGBounds.minY + clampedTopInset
                reservedBottom = screenCGBounds.maxY
            case .bottom:
                reservedLeft = screenCGBounds.minX
                reservedRight = screenCGBounds.maxX
                reservedTop = screenCGBounds.minY
                reservedBottom = screenCGBounds.maxY - clampedBottomInset
            case .left:
                reservedLeft = screenCGBounds.minX + clampedLeftInset
                reservedRight = screenCGBounds.maxX
                reservedTop = screenCGBounds.minY
                reservedBottom = screenCGBounds.maxY
            case .right:
                reservedLeft = screenCGBounds.minX
                reservedRight = screenCGBounds.maxX - clampedRightInset
                reservedTop = screenCGBounds.minY
                reservedBottom = screenCGBounds.maxY
            }

            let usableWidth = reservedRight - reservedLeft
            let usableHeight = reservedBottom - reservedTop
            guard usableWidth >= minimumSize, usableHeight >= minimumSize else { return nil }

            return CGRect(x: reservedLeft, y: reservedTop, width: usableWidth, height: usableHeight)
        }

        func windowSpansMultipleDisplays(
            _ window: WindowBounds,
            screens: [(displayId: UInt32, bounds: WindowBounds)]
        ) -> Bool {
            var count = 0
            for screen in screens {
                if window.intersectionArea(with: screen.bounds) > 4.0 {
                    count += 1
                    if count > 1 { return true }
                }
            }
            return false
        }
    }

    static func adjustWindowsForTaskbar(panels: [PanelInfo]) {
        guard !MouseTracker.isDragging else { return }
        guard !panels.isEmpty else { return }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return }

        let now = CFAbsoluteTimeGetCurrent()
        if !recentAdjustments.isEmpty {
            recentAdjustments = recentAdjustments.filter { now - $0.value.appliedAt <= adjustmentCacheTTL }
        }

        let activeDisplayBounds = activeDisplayBoundsById()
        guard !activeDisplayBounds.isEmpty else { return }
        let assignmentScreens: [(displayId: UInt32, bounds: WindowBounds)] = activeDisplayBounds.map { (did, rect) in
            (
                UInt32(did),
                WindowBounds(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            )
        }
        let nsScreensByDisplayId: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                guard let did = screen.displayId else { return nil }
                return (did, screen)
            }
        )
        let panelsByDisplayId: [CGDirectDisplayID: PanelInfo] = Dictionary(
            uniqueKeysWithValues: panels.map { ($0.displayId, $0) }
        )
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let planner = WindowAdjustmentPlanner(tolerance: adjustTolerance, minimumSize: adjustmentMinHeight)

        for dict in windowList {
            guard let layer = dict[kCGWindowLayer] as? Int32, layer == 0 else { continue }
            guard let pid = dict[kCGWindowOwnerPID] as? pid_t, pid != ownPid else { continue }
            guard let windowId = parseWindowNumber(dict[kCGWindowNumber]) else { continue }
            guard let boundsDict = dict[kCGWindowBounds] as? NSDictionary else { continue }

            var wr = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &wr) else { continue }

            let windowBounds = WindowBounds(x: wr.origin.x, y: wr.origin.y, width: wr.width, height: wr.height)

            // Skip windows spanning multiple displays — these are often special utility/palette windows.
            if planner.windowSpansMultipleDisplays(windowBounds, screens: assignmentScreens) { continue }

            // Resolve monitor using the same geometry assignment logic as window enumeration.
            let monitorId = DisplayAssignment.monitorId(for: windowBounds, screens: assignmentScreens)
            let displayId = CGDirectDisplayID(monitorId.raw)

            guard let panel = panelsByDisplayId[displayId],
                  let screenCG = activeDisplayBounds[displayId],
                  let screenNS = nsScreensByDisplayId[displayId] else { continue }

            guard let plan = planner.plan(
                forWindowFrame: wr,
                panel: panel,
                screenCGBounds: screenCG,
                screenNSFrame: screenNS.frame
            ) else {
                continue
            }
            let targetFrame = plan.targetFrame
            let newX = targetFrame.origin.x
            let newY = targetFrame.origin.y
            let newW = targetFrame.width
            let newH = targetFrame.height
            let needsMove = plan.needsMove
            let needsResize = plan.needsResize

            let key = AdjustmentKey(pid: pid, windowId: windowId)
            if let last = recentAdjustments[key],
               now - last.appliedAt < adjustCooldown,
               abs(last.targetX - newX) <= adjustTolerance,
               abs(last.targetY - newY) <= adjustTolerance,
               abs(last.targetWidth - newW) <= adjustTolerance,
               abs(last.targetHeight - newH) <= adjustTolerance {
                continue
            }
            let title = dict[kCGWindowName as CFString] as? String ?? ""

            // Apply via AX API
            let appEl = AXUIElementCreateApplication(pid)
            guard let axWindows = copyAXWindows(appEl) else { continue }

            if let axWin = matchAXWindow(
                in: axWindows,
                targetWindowId: windowId,
                targetBounds: wr,
                targetTitle: title
            ) {
                // Apply size first, then position to keep the final rect deterministic.
                if needsResize {
                    setAXSize(axWin, size: CGSize(width: newW, height: newH))
                }
                if needsMove {
                    setAXPosition(axWin, point: CGPoint(x: newX, y: newY))
                }
                recentAdjustments[key] = AdjustmentRecord(targetX: newX, targetY: newY, targetWidth: newW, targetHeight: newH, appliedAt: now)
                Log.ax.debug(
                    "Adjusted window id=\(windowId) pid=\(pid) display=\(displayId) x:\(wr.minX, format: .fixed(precision: 1))->\(newX, format: .fixed(precision: 1)) y:\(wr.minY, format: .fixed(precision: 1))->\(newY, format: .fixed(precision: 1)) w:\(wr.width, format: .fixed(precision: 1))->\(newW, format: .fixed(precision: 1)) h:\(wr.height, format: .fixed(precision: 1))->\(newH, format: .fixed(precision: 1))"
                )
                continue
            }

            // Fallback: match by geometry when the target window cannot be matched exactly.
            for j in 0..<CFArrayGetCount(axWindows) {
                guard let axWin = axElement(at: j, in: axWindows) else { continue }
                guard let axPos = getAXPosition(axWin) else { continue }

                if abs(axPos.x - wr.origin.x) < 5 && abs(axPos.y - wr.origin.y) < 5 {
                    if needsResize {
                        setAXSize(axWin, size: CGSize(width: newW, height: newH))
                    }
                    if needsMove {
                        setAXPosition(axWin, point: CGPoint(x: newX, y: newY))
                    }
                    recentAdjustments[key] = AdjustmentRecord(targetX: newX, targetY: newY, targetWidth: newW, targetHeight: newH, appliedAt: now)
                    Log.ax.debug(
                        "Adjusted window(fallback) id=\(windowId) pid=\(pid) display=\(displayId) x:\(wr.minX, format: .fixed(precision: 1))->\(newX, format: .fixed(precision: 1)) y:\(wr.minY, format: .fixed(precision: 1))->\(newY, format: .fixed(precision: 1)) w:\(wr.width, format: .fixed(precision: 1))->\(newW, format: .fixed(precision: 1)) h:\(wr.height, format: .fixed(precision: 1))->\(newH, format: .fixed(precision: 1))"
                    )
                    break
                }
            }
        }
    }

    // MARK: - Experimental Window Layout Memory

    static func captureRestorableWindowSnapshots(
        displayUUIDByDisplayId: [CGDirectDisplayID: String]
    ) -> [RestorableWindowSnapshot] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        let activeDisplayBounds = activeDisplayBoundsById()
        guard !activeDisplayBounds.isEmpty else { return [] }
        let assignmentScreens: [(displayId: UInt32, bounds: WindowBounds)] = activeDisplayBounds.map { displayId, rect in
            (
                UInt32(displayId),
                WindowBounds(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            )
        }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let planner = WindowAdjustmentPlanner()
        var snapshots: [RestorableWindowSnapshot] = []
        snapshots.reserveCapacity(windowList.count)

        for dict in windowList {
            let layer = parseInt(dict[kCGWindowLayer as CFString]) ?? 0
            guard layer == 0 else { continue }
            guard let pid = parsePid(dict[kCGWindowOwnerPID as CFString]), pid != ownPid else { continue }
            guard let windowId = parseWindowNumber(dict[kCGWindowNumber as CFString]) else { continue }
            guard let boundsDict = dict[kCGWindowBounds as CFString] as? NSDictionary else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            guard rect.width >= 80, rect.height >= 80 else { continue }

            let windowBounds = WindowBounds(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            if planner.windowSpansMultipleDisplays(windowBounds, screens: assignmentScreens) { continue }

            let monitorId = DisplayAssignment.monitorId(for: windowBounds, screens: assignmentScreens)
            let displayId = CGDirectDisplayID(monitorId.raw)
            guard let displayUUID = displayUUIDByDisplayId[displayId] else { continue }

            let title = dict[kCGWindowName as CFString] as? String ?? ""
            let bundleId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            snapshots.append(
                RestorableWindowSnapshot(
                    pid: pid,
                    bundleId: bundleId,
                    windowId: windowId,
                    title: title,
                    frame: rect,
                    displayUUID: displayUUID
                )
            )
        }

        return snapshots
    }

    @discardableResult
    static func restoreWindowFrame(
        _ snapshot: RestorableWindowSnapshot,
        activeDisplayBoundsByUUID: [String: CGRect]
    ) -> Bool {
        let catalog = makeRestorableWindowCatalog()
        var axWindowsByPID: [pid_t: CFArray] = [:]
        return restoreWindowFrameResult(
            snapshot,
            activeDisplayBoundsByUUID: activeDisplayBoundsByUUID,
            liveWindowCatalog: catalog,
            axWindowsByPID: &axWindowsByPID
        ).restored
    }

    static func restoreWindowFrames(
        _ snapshots: [RestorableWindowSnapshot],
        activeDisplayBoundsByUUID: [String: CGRect]
    ) -> RestorableWindowRestoreBatchResult {
        guard !snapshots.isEmpty else {
            return RestorableWindowRestoreBatchResult(completedSnapshots: [], restoredWindowCount: 0)
        }

        let catalog = makeRestorableWindowCatalog()
        var axWindowsByPID: [pid_t: CFArray] = [:]
        var completed: [RestorableWindowSnapshot] = []
        completed.reserveCapacity(snapshots.count)
        var restored = 0

        for snapshot in snapshots {
            let result = restoreWindowFrameResult(
                snapshot,
                activeDisplayBoundsByUUID: activeDisplayBoundsByUUID,
                liveWindowCatalog: catalog,
                axWindowsByPID: &axWindowsByPID
            )
            if result.completed {
                completed.append(snapshot)
            }
            if result.restored {
                restored += 1
            }
        }

        return RestorableWindowRestoreBatchResult(
            completedSnapshots: completed,
            restoredWindowCount: restored
        )
    }

    private struct WindowFrameRestoreResult {
        let completed: Bool
        let restored: Bool
    }

    private static func restoreWindowFrameResult(
        _ snapshot: RestorableWindowSnapshot,
        activeDisplayBoundsByUUID: [String: CGRect],
        liveWindowCatalog: RestorableWindowCatalog,
        axWindowsByPID: inout [pid_t: CFArray]
    ) -> WindowFrameRestoreResult {
        guard !MouseTracker.isDragging else {
            return WindowFrameRestoreResult(completed: false, restored: false)
        }
        guard let displayBounds = activeDisplayBoundsByUUID[snapshot.displayUUID],
              displayBounds.insetBy(dx: -8, dy: -8).intersects(snapshot.frame) else {
            return WindowFrameRestoreResult(completed: false, restored: false)
        }
        guard let liveWindow = findRestorableLiveWindow(for: snapshot, in: liveWindowCatalog) else {
            return WindowFrameRestoreResult(completed: false, restored: false)
        }
        guard !framesAreClose(liveWindow.frame, snapshot.frame, tolerance: 3.0) else {
            return WindowFrameRestoreResult(completed: true, restored: false)
        }

        let appEl = AXUIElementCreateApplication(liveWindow.pid)
        guard let axWindows = copyAXWindows(for: liveWindow.pid, appElement: appEl, cache: &axWindowsByPID) else {
            return WindowFrameRestoreResult(completed: false, restored: false)
        }

        let targetTitle = liveWindow.title.isEmpty ? snapshot.title : liveWindow.title
        if let axWin = matchAXWindow(
            in: axWindows,
            targetWindowId: liveWindow.windowId,
            targetBounds: liveWindow.frame,
            targetTitle: targetTitle
        ) {
            let resized = setAXSize(axWin, size: snapshot.frame.size)
            let moved = setAXPosition(axWin, point: snapshot.frame.origin)
            guard resized || moved,
                  let finalPosition = getAXPosition(axWin),
                  let finalSize = getAXSize(axWin) else {
                return WindowFrameRestoreResult(completed: false, restored: false)
            }

            let finalFrame = CGRect(origin: finalPosition, size: finalSize)
            let completed = framesAreClose(finalFrame, snapshot.frame, tolerance: 4.0)
            return WindowFrameRestoreResult(completed: completed, restored: completed)
        }

        return WindowFrameRestoreResult(completed: false, restored: false)
    }

    nonisolated static func framesAreClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    // MARK: - Unhide / Unminimize

    /// Hide an app by bundle identifier (Cmd+H behavior).
    static func hideApp(bundleId: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else { return }
        app.hide()
    }

    /// Unhide an app by bundle identifier
    static func unhideApp(bundleId: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else { return }
        app.unhide()
        app.activate()
    }

    /// Unminimize a specific window by its CGWindow ID
    static func unminimizeWindow(windowId: UInt32) {
        guard let (pid, bounds, title) = findCGWindowOffScreen(windowId: windowId) ?? findCGWindow(windowId: windowId) else {
            return
        }

        let appEl = AXUIElementCreateApplication(pid)
        guard let axWindows = copyAXWindows(appEl) else { return }

        if let axWin = matchAXWindow(
            in: axWindows,
            targetWindowId: windowId,
            targetBounds: bounds,
            targetTitle: title,
            requireMinimized: true
        ) {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            focusAXWindow(
                appEl: appEl,
                axWindow: axWin,
                pid: pid,
                bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "",
                windowId: windowId
            )
            return
        }

        // Fallback: unminimize the first minimized AX window.
        for i in 0..<CFArrayGetCount(axWindows) {
            guard let axWin = axElement(at: i, in: axWindows) else { continue }
            if getAXBool(axWin, attribute: kAXMinimizedAttribute as CFString) == true {
                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                focusAXWindow(
                    appEl: appEl,
                    axWindow: axWin,
                    pid: pid,
                    bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "",
                    windowId: nil
                )
                return
            }
        }
    }

    /// Minimize a specific window by its CGWindow ID (Windows-style "click focused item again").
    static func minimizeWindow(windowId: UInt32) {
        guard let (pid, bounds, title) = findCGWindow(windowId: windowId) else { return }

        let appEl = AXUIElementCreateApplication(pid)
        guard let axWindows = copyAXWindows(appEl) else { return }

        if let axWin = matchAXWindow(
            in: axWindows,
            targetWindowId: windowId,
            targetBounds: bounds,
            targetTitle: title
        ) {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            return
        }

        // Fallback: minimize the first AX window.
        if CFArrayGetCount(axWindows) > 0 {
            if let axWin = axElement(at: 0, in: axWindows) {
                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        }
    }

    // MARK: - Launch App

    static func launchApp(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: - Private Helpers

    private struct RestorableWindowKey: Hashable {
        let pid: pid_t
        let windowId: UInt32
    }

    private struct RestorableWindowTitleKey: Hashable {
        let pid: pid_t
        let title: String
    }

    private struct RestorableWindowCatalog {
        let byWindowKey: [RestorableWindowKey: RestorableLiveWindow]
        let uniqueByTitleKey: [RestorableWindowTitleKey: RestorableLiveWindow]
    }

    private static func findRestorableLiveWindow(
        for snapshot: RestorableWindowSnapshot,
        in catalog: RestorableWindowCatalog
    ) -> RestorableLiveWindow? {
        if !snapshot.bundleId.isEmpty,
           NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier != snapshot.bundleId {
            return nil
        }

        if let exact = catalog.byWindowKey[RestorableWindowKey(pid: snapshot.pid, windowId: snapshot.windowId)] {
            return exact
        }

        guard !snapshot.title.isEmpty else { return nil }
        return catalog.uniqueByTitleKey[RestorableWindowTitleKey(pid: snapshot.pid, title: snapshot.title)]
    }

    private static func makeRestorableWindowCatalog() -> RestorableWindowCatalog {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return RestorableWindowCatalog(byWindowKey: [:], uniqueByTitleKey: [:])
        }

        var byWindowKey: [RestorableWindowKey: RestorableLiveWindow] = [:]
        var titleBuckets: [RestorableWindowTitleKey: [RestorableLiveWindow]] = [:]
        byWindowKey.reserveCapacity(windowList.count)
        for dict in windowList {
            let layer = parseInt(dict[kCGWindowLayer as CFString]) ?? 0
            guard layer == 0 else { continue }
            guard let pid = parsePid(dict[kCGWindowOwnerPID as CFString]) else { continue }
            guard let windowId = parseWindowNumber(dict[kCGWindowNumber as CFString]) else { continue }
            guard let boundsDict = dict[kCGWindowBounds as CFString] as? NSDictionary else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            let title = dict[kCGWindowName as CFString] as? String ?? ""
            let candidate = RestorableLiveWindow(pid: pid, windowId: windowId, frame: rect, title: title)
            byWindowKey[RestorableWindowKey(pid: pid, windowId: windowId)] = candidate

            if !title.isEmpty {
                titleBuckets[RestorableWindowTitleKey(pid: pid, title: title), default: []].append(candidate)
            }
        }

        let uniqueByTitleKey = titleBuckets.compactMapValues { matches in
            matches.count == 1 ? matches[0] : nil
        }
        return RestorableWindowCatalog(
            byWindowKey: byWindowKey,
            uniqueByTitleKey: uniqueByTitleKey
        )
    }

    private static func findCGWindow(windowId: UInt32) -> (pid_t, CGRect, String)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for dict in windowList {
            guard parseWindowNumber(dict[kCGWindowNumber]) == windowId else { continue }
            guard let pid = dict[kCGWindowOwnerPID] as? pid_t else { continue }
            guard let boundsDict = dict[kCGWindowBounds] as? NSDictionary else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            let title = dict[kCGWindowName as CFString] as? String ?? ""
            return (pid, rect, title)
        }
        return nil
    }

    /// Find a window that may be off-screen (minimized/hidden)
    private static func findCGWindowOffScreen(windowId: UInt32) -> (pid_t, CGRect, String)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for dict in windowList {
            guard parseWindowNumber(dict[kCGWindowNumber]) == windowId else { continue }
            guard let pid = dict[kCGWindowOwnerPID] as? pid_t else { continue }
            guard let boundsDict = dict[kCGWindowBounds] as? NSDictionary else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) else { continue }
            let title = dict[kCGWindowName as CFString] as? String ?? ""
            return (pid, rect, title)
        }
        return nil
    }

    private static func focusAXWindow(
        appEl: AXUIElement,
        axWindow: AXUIElement,
        pid: pid_t,
        bundleId: String,
        windowId: UInt32? = nil
    ) {
        let targetWindowId = windowId

        for strategy in strictWindowScopedFocusPlan(bundleId: bundleId).matchedStrategies.prefix(matchedFocusMaxAttempts) {
            guard performMatchedFocusStrategy(
                strategy,
                appEl: appEl,
                axWindow: axWindow,
                pid: pid
            ) else { continue }

            if isMatchedFocusVerified(
                appEl: appEl,
                axWindow: axWindow,
                pid: pid,
                targetWindowId: targetWindowId
            ) {
                return
            }
        }

        logFocusFailure(
            pid: pid,
            bundleId: bundleId,
            targetWindowId: targetWindowId,
            reason: .verificationFailed
        )
    }

    private static func focusWindowWithoutAX(
        pid: pid_t,
        bundleId: String,
        targetWindowId: UInt32
    ) {
        let plan = strictWindowScopedFocusPlan(bundleId: bundleId)

        for strategy in plan.unmatchedStrategies {
            switch strategy {
            case .frontWindowOnly:
                guard activateFrontWindowOnly(pid: pid) else { continue }
                if isFrontmostTargetWindowVerified(
                    pid: pid,
                    targetWindowId: targetWindowId,
                    allowPidOnlyFallbackWhenWindowIdUnavailable: false
                ) {
                    return
                }
            case .axTarget, .axAppHandoff, .stop:
                break
            }
        }

        logFocusFailure(
            pid: pid,
            bundleId: bundleId,
            targetWindowId: targetWindowId,
            reason: .verificationFailed
        )
    }

    private static func performMatchedFocusStrategy(
        _ strategy: FocusPlanStrategy,
        appEl: AXUIElement,
        axWindow: AXUIElement,
        pid: pid_t
    ) -> Bool {
        switch strategy {
        case .axTarget:
            applyAXFocus(appEl: appEl, axWindow: axWindow)
            return true
        case .axAppHandoff:
            focusApplicationAX(appEl)
            applyAXFocus(appEl: appEl, axWindow: axWindow)
            return true
        case .frontWindowOnly:
            guard activateFrontWindowOnly(pid: pid) else { return false }
            applyAXFocus(appEl: appEl, axWindow: axWindow)
            return true
        case .stop:
            return false
        }
    }

    private static func frontmostMatches(pid: pid_t, windowId: UInt32?) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        guard let windowId else { return true }
        return frontmostWindowIdForFrontmostApp() == windowId
    }

    private static func currentFocusWindowRoutingHooks() -> FocusWindowRoutingHooks {
        #if DEBUG
        debugFocusWindowRoutingHooks ?? makeLiveFocusWindowRoutingHooks()
        #else
        makeLiveFocusWindowRoutingHooks()
        #endif
    }

    private static func makeLiveFocusWindowRoutingHooks() -> FocusWindowRoutingHooks {
        FocusWindowRoutingHooks(
            findOnScreenWindow: { windowId in
                guard let (pid, bounds, title) = findCGWindow(windowId: windowId) else { return nil }
                return WindowLookupResult(pid: pid, bounds: bounds, title: title)
            },
            findOffScreenWindow: { windowId in
                guard let (pid, bounds, title) = findCGWindowOffScreen(windowId: windowId) else { return nil }
                return WindowLookupResult(pid: pid, bounds: bounds, title: title)
            },
            bundleIdForPid: { pid in
                NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            },
            createApplicationElement: { AXUIElementCreateApplication($0) },
            copyWindows: { copyAXWindows($0) },
            matchWindow: { axWindows, targetWindowId, targetBounds, targetTitle in
                matchAXWindow(
                    in: axWindows,
                    targetWindowId: targetWindowId,
                    targetBounds: targetBounds,
                    targetTitle: targetTitle
                )
            },
            focusMatched: { appEl, axWindow, pid, bundleId, windowId in
                focusAXWindow(
                    appEl: appEl,
                    axWindow: axWindow,
                    pid: pid,
                    bundleId: bundleId,
                    windowId: windowId
                )
            },
            focusUnmatched: { pid, bundleId, targetWindowId in
                focusWindowWithoutAX(
                    pid: pid,
                    bundleId: bundleId,
                    targetWindowId: targetWindowId
                )
            }
        )
    }

    private static func isMatchedFocusVerified(
        appEl: AXUIElement,
        axWindow: AXUIElement,
        pid: pid_t,
        targetWindowId: UInt32?
    ) -> Bool {
        if let targetWindowId {
            switch frontmostWindowVerification(pid: pid, targetWindowId: targetWindowId) {
            case .exactMatch:
                return true
            case .wrongWindow, .wrongApplication:
                return false
            case .windowIdUnavailable:
                break
            }
        }

        return isTargetWindowFocused(
            appEl: appEl,
            axWindow: axWindow,
            pid: pid,
            requireFrontmost: true,
            targetWindowId: targetWindowId
        )
    }

    private static func isFrontmostTargetWindowVerified(
        pid: pid_t,
        targetWindowId: UInt32,
        allowPidOnlyFallbackWhenWindowIdUnavailable: Bool
    ) -> Bool {
        switch frontmostWindowVerification(pid: pid, targetWindowId: targetWindowId) {
        case .exactMatch:
            return true
        case .windowIdUnavailable:
            return allowPidOnlyFallbackWhenWindowIdUnavailable
        case .wrongWindow, .wrongApplication:
            return false
        }
    }

    private static func frontmostWindowVerification(
        pid: pid_t,
        targetWindowId: UInt32
    ) -> FrontmostWindowVerification {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return .wrongApplication
        }
        guard let frontmostWindowId = frontmostWindowIdForFrontmostApp() else {
            return .windowIdUnavailable
        }
        return frontmostWindowId == targetWindowId ? .exactMatch : .wrongWindow
    }

    private static func logFocusFailure(
        pid: pid_t,
        bundleId: String,
        targetWindowId: UInt32?,
        reason: FocusFailureReason
    ) {
        let windowDescription = targetWindowId.map(String.init) ?? "nil"
        Log.ax.notice(
            "Focus policy exited without verification pid=\(pid, privacy: .public) bundle=\(bundleId, privacy: .public) window=\(windowDescription, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
        )
    }

    private static func applyAXFocus(appEl: AXUIElement, axWindow: AXUIElement) {
        AXUIElementSetAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private static func focusApplicationAX(_ appEl: AXUIElement) {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, appEl)
    }

    #if DEBUG
    static func debugInstallFocusWindowRoutingHooks(_ hooks: FocusWindowRoutingHooks) {
        debugFocusWindowRoutingHooks = hooks
    }

    static func debugResetFocusWindowRoutingHooks() {
        debugFocusWindowRoutingHooks = nil
    }
    #endif

    @discardableResult
    private static func activateFrontWindowOnly(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate() ?? false
    }

    private static func isTargetWindowFocused(
        appEl: AXUIElement,
        axWindow: AXUIElement,
        pid: pid_t,
        requireFrontmost: Bool = true,
        targetWindowId: UInt32? = nil
    ) -> Bool {
        if requireFrontmost,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            return false
        }

        if let targetWindowId {
            switch frontmostWindowVerification(pid: pid, targetWindowId: targetWindowId) {
            case .exactMatch:
                return true
            case .wrongWindow, .wrongApplication:
                return false
            case .windowIdUnavailable:
                break
            }
        }

        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused,
              let focusedWindow = axElement(from: focused as CFTypeRef) else {
            return false
        }

        if CFEqual(focusedWindow, axWindow) {
            return true
        }

        if let targetPos = getAXPosition(axWindow),
           let targetSize = getAXSize(axWindow),
           let focusedPos = getAXPosition(focusedWindow),
           let focusedSize = getAXSize(focusedWindow) {
            let targetRect = CGRect(origin: targetPos, size: targetSize)
            let focusedRect = CGRect(origin: focusedPos, size: focusedSize)
            let centerDx = abs(targetRect.midX - focusedRect.midX)
            let centerDy = abs(targetRect.midY - focusedRect.midY)
            let widthDelta = abs(targetRect.width - focusedRect.width)
            let heightDelta = abs(targetRect.height - focusedRect.height)
            if centerDx <= 1.0, centerDy <= 1.0, widthDelta <= 1.0, heightDelta <= 1.0 {
                return true
            }
        }

        return false
    }

    static func parseWindowNumber(_ rawValue: Any?) -> UInt32? {
        WindowNumber.parse(rawValue)
    }

    private static func parsePid(_ rawValue: Any?) -> pid_t? {
        if let n = rawValue as? pid_t { return n }
        if let n = rawValue as? Int { return pid_t(clamping: n) }
        if let n = rawValue as? Int64 { return pid_t(clamping: n) }
        if let n = rawValue as? NSNumber { return n.int32Value }
        return nil
    }

    private static func parseInt(_ rawValue: Any?) -> Int? {
        if let n = rawValue as? Int { return n }
        if let n = rawValue as? Int32 { return Int(n) }
        if let n = rawValue as? Int64 { return Int(clamping: n) }
        if let n = rawValue as? NSNumber { return n.intValue }
        return nil
    }

    private static func getAXString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func getAXBool(_ element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    private static func matchAXWindow(
        in axWindows: CFArray,
        targetWindowId _: UInt32,
        targetBounds: CGRect,
        targetTitle: String,
        requireMinimized: Bool? = nil
    ) -> AXUIElement? {
        struct Candidate {
            let window: AXUIElement
            let score: Double
        }

        var titleCandidates: [Candidate] = []
        var geometryCandidates: [Candidate] = []
        var relaxedGeometryCandidates: [Candidate] = []
        titleCandidates.reserveCapacity(4)
        geometryCandidates.reserveCapacity(4)
        relaxedGeometryCandidates.reserveCapacity(4)

        for i in 0..<CFArrayGetCount(axWindows) {
            guard let axWin = axElement(at: i, in: axWindows) else { continue }

            if let requireMinimized {
                let minimized = getAXBool(axWin, attribute: kAXMinimizedAttribute as CFString) ?? false
                if minimized != requireMinimized {
                    continue
                }
            }

            let axPos = getAXPosition(axWin)
            let axSize = getAXSize(axWin)
            let dx = axPos.map { abs($0.x - targetBounds.origin.x) } ?? 10_000
            let dy = axPos.map { abs($0.y - targetBounds.origin.y) } ?? 10_000
            let dw = axSize.map { abs($0.width - targetBounds.width) } ?? 10_000
            let dh = axSize.map { abs($0.height - targetBounds.height) } ?? 10_000
            let score = Double(dx + dy + (dw * 0.06) + (dh * 0.06))

            if !targetTitle.isEmpty,
               let axTitle = getAXString(axWin, attribute: kAXTitleAttribute as CFString),
               axTitle == targetTitle {
                titleCandidates.append(Candidate(window: axWin, score: score))
                continue
            }

            if dx <= 8, dy <= 8 {
                geometryCandidates.append(Candidate(window: axWin, score: score))
            }

            if let axPos, let axSize {
                let axRect = CGRect(origin: axPos, size: axSize)
                let overlap = axRect.intersection(targetBounds)
                let overlapArea = max(0, overlap.width * overlap.height)
                let minArea = max(1.0, min(axRect.width * axRect.height, targetBounds.width * targetBounds.height))
                let overlapRatio = overlapArea / minArea

                let centerDx = abs(axRect.midX - targetBounds.midX)
                let centerDy = abs(axRect.midY - targetBounds.midY)
                let relaxedScore = Double((1.0 - overlapRatio) * 300.0 + centerDx + centerDy + (dw * 0.03) + (dh * 0.03))

                if overlapRatio >= 0.70 {
                    relaxedGeometryCandidates.append(Candidate(window: axWin, score: relaxedScore))
                } else if centerDx <= 60, centerDy <= 90, dw <= 220, dh <= 220 {
                    relaxedGeometryCandidates.append(Candidate(window: axWin, score: relaxedScore + 120.0))
                }
            }
        }

        if let bestTitleMatch = titleCandidates.min(by: { $0.score < $1.score }) {
            return bestTitleMatch.window
        }
        if let bestGeometryMatch = geometryCandidates.min(by: { $0.score < $1.score }) {
            return bestGeometryMatch.window
        }
        if let relaxedGeometryMatch = relaxedGeometryCandidates.min(by: { $0.score < $1.score }) {
            return relaxedGeometryMatch.window
        }
        return nil
    }

    private static func copyAXWindows(_ app: AXUIElement) -> CFArray? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        return cfArray(from: value)
    }

    private static func copyAXWindows(
        for pid: pid_t,
        appElement: AXUIElement,
        cache: inout [pid_t: CFArray]
    ) -> CFArray? {
        if let cached = cache[pid] {
            return cached
        }
        guard let windows = copyAXWindows(appElement) else { return nil }
        cache[pid] = windows
        return windows
    }

    private static func getAXPosition(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
        guard let val = axValue(from: value) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(val, .cgPoint, &point) else { return nil }
        return point
    }

    private static func getAXSize(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard let val = axValue(from: value) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(val, .cgSize, &size) else { return nil }
        return size
    }

    private static func cfArray(from value: AnyObject?) -> CFArray? {
        guard let value,
              CFGetTypeID(value as CFTypeRef) == CFArrayGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: CFArray.self)
    }

    private static func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func axElement(at index: CFIndex, in array: CFArray) -> AXUIElement? {
        guard index >= 0, index < CFArrayGetCount(array),
              let raw = CFArrayGetValueAtIndex(array, index) else {
            return nil
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return element
    }

    private static func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }

    #if DEBUG
    static func debugIsAXElementValue(_ value: CFTypeRef) -> Bool {
        axElement(from: value) != nil
    }

    static func debugIsAXValue(_ value: CFTypeRef) -> Bool {
        axValue(from: value) != nil
    }
    #endif

    @discardableResult
    private static func setAXPosition(_ element: AXUIElement, point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    private static func setAXSize(_ element: AXUIElement, size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
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
        for did in displayIds.prefix(Int(count)) {
            result[did] = CGDisplayBounds(did)
        }
        return result
    }

    #if DEBUG
    deinit {
        Log.ax.debug("AccessibilityService deinit")
    }
    #endif
}
