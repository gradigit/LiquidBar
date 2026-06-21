import AppKit
import CoreGraphics
import ApplicationServices

@MainActor
final class WindowManager {
    private(set) var lastFrontmostWindowId: UInt32?

    private struct AXWindowSnapshot {
        var title: String
        var isMinimized: Bool?
        var position: CGPoint?
        var size: CGSize?
    }

    private struct AppInfoCacheEntry {
        let bundleId: String
        let isHidden: Bool
        let capturedAt: CFAbsoluteTime
    }

    // Window title fallback cache (used when Screen Recording permission is not granted).
    private var axTitleCache: [UInt32: String] = [:]
    private var lastAXTitleRefresh: CFAbsoluteTime = 0
    private let axTitleRefreshInterval: CFAbsoluteTime = 0.75
    private let axMessagingTimeout: Float = 0.08
    private struct AXSnapshotCacheEntry {
        let snapshots: [AXWindowSnapshot]
        let capturedAt: CFAbsoluteTime
    }
    private var axSnapshotCacheByPid: [pid_t: AXSnapshotCacheEntry] = [:]
    private let axSnapshotCacheTTL: CFAbsoluteTime = 10.00
    // Off-screen pass (hidden/minimized windows) is expensive: it scans .optionAll,
    // may query AX per process, and filters via Spaces APIs. Refresh at a lower cadence
    // and reuse results between polls to keep hover/drag rendering smooth.
    private var offscreenCacheEntries: [(info: WindowInfo, pid: pid_t)] = []
    private var lastOffscreenRefresh: CFAbsoluteTime = 0
    private var lastOffscreenSpaceSignature: String = ""
    private let offscreenRefreshInterval: CFAbsoluteTime = 30.00
    private var appInfoCacheByPid: [pid_t: AppInfoCacheEntry] = [:]
    private let appInfoCacheTTL: CFAbsoluteTime = 10.00
    private let isAXQueriesDisabledByEnv: Bool = ProcessInfo.processInfo.environment["LIQUIDBAR_DISABLE_AX_QUERIES"] == "1"

    /// Enumerate windows for the *current Space* (per display), including:
    /// - visible windows (CGWindowList on-screen)
    /// - optional hidden windows (app hidden via Cmd+H)
    /// - optional minimized windows (window minimized to Dock)
    ///
    /// `currentSpaceKeysByDisplay` should map displayId -> Space id64 string.
    /// When provided with a working `SpacesService`, off-screen windows can be
    /// filtered to the active Space so minimized windows don't leak across Spaces.
    func enumerate(
        config: Config,
        currentSpaceKeysByDisplay: [CGDirectDisplayID: String] = [:],
        spacesService: SpacesService? = nil
    ) -> [WindowInfo] {
        lastFrontmostWindowId = nil

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_WINDOWS_PATH"],
           !path.isEmpty {
            if let windows = TestWindowList.load(from: URL(fileURLWithPath: path)) {
                Log.window.debug("Using test window list: \(path, privacy: .public) (\(windows.count) windows)")
                lastFrontmostWindowId = windows.first { !$0.isHidden && !$0.isMinimized }?.id.raw
                return Array(windows.prefix(maxWindows))
            }
        }
        #endif

        let axEnabled = AXIsProcessTrusted() && !isAXQueriesDisabledByEnv
        let now = CFAbsoluteTimeGetCurrent()
        var axSnapshotsByPid: [pid_t: [AXWindowSnapshot]] = [:]
        var appInfoByPid: [pid_t: (bundleId: String, isHidden: Bool)] = [:]
        func snapshots(for pid: pid_t) -> [AXWindowSnapshot] {
            if let cached = axSnapshotsByPid[pid] { return cached }
            if let cached = axSnapshotCacheByPid[pid], (now - cached.capturedAt) < axSnapshotCacheTTL {
                axSnapshotsByPid[pid] = cached.snapshots
                return cached.snapshots
            }
            let snaps = axWindowSnapshots(pid: pid)
            axSnapshotsByPid[pid] = snaps
            axSnapshotCacheByPid[pid] = AXSnapshotCacheEntry(snapshots: snaps, capturedAt: now)
            return snaps
        }
        func appInfo(for pid: pid_t) -> (bundleId: String, isHidden: Bool) {
            if let cached = appInfoByPid[pid] { return cached }
            if let cached = appInfoCacheByPid[pid], (now - cached.capturedAt) < appInfoCacheTTL {
                let info = (cached.bundleId, cached.isHidden)
                appInfoByPid[pid] = info
                return info
            }

            let info = getAppInfo(pid: pid)
            appInfoByPid[pid] = info
            appInfoCacheByPid[pid] = AppInfoCacheEntry(
                bundleId: info.bundleId,
                isHidden: info.isHidden,
                capturedAt: now
            )
            return info
        }

        let screens = getScreenFrames()
        var parsedWindows: [(info: WindowInfo, pid: pid_t)] = []
        var seenWindowIds: Set<UInt32> = []

        // Pass 1: On-screen windows (visible)
        //
        // During Spaces / Mission Control transitions, `.optionOnScreenOnly` can
        // transiently return an empty list. If that happens, fall back to `.optionAll`
        // and filter on-screen ourselves.
        let onScreenOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let allOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]

        let onScreenList = CGWindowListCopyWindowInfo(onScreenOptions, kCGNullWindowID) as? [[CFString: Any]] ?? []
        var windowList = onScreenList
        var usingAllFallback = false
        if windowList.isEmpty {
            windowList = CGWindowListCopyWindowInfo(allOptions, kCGNullWindowID) as? [[CFString: Any]] ?? []
            usingAllFallback = true
            if !windowList.isEmpty {
                Log.window.debug("CGWindowList on-screen returned empty; falling back to .optionAll")
            }
        }
        lastFrontmostWindowId = frontmostWindowId(in: windowList, usingAllFallback: usingAllFallback)

        for dict in windowList {
            if usingAllFallback && !isOnscreen(dict) { continue }
            guard let parsed = parseWindowDict(dict, screens: screens, appInfoProvider: appInfo),
                  shouldInclude(parsed.info) else { continue }
            parsedWindows.append(parsed)
            seenWindowIds.insert(parsed.info.id.raw)
            if parsedWindows.count >= maxWindows { break }
        }

        // Pass 2: Off-screen windows on the active Space (hidden/minimized).
        if config.showHiddenApps || config.showMinimizedWindows {
            if let spacesService, !currentSpaceKeysByDisplay.isEmpty {
                let spaceSignature = makeSpaceSignature(currentSpaceKeysByDisplay)
                let shouldRefreshOffscreen =
                    usingAllFallback
                    || onScreenList.isEmpty
                    || (spaceSignature != lastOffscreenSpaceSignature)
                    || ((now - lastOffscreenRefresh) >= offscreenRefreshInterval)

                if shouldRefreshOffscreen {
                    var refreshed: [(info: WindowInfo, pid: pid_t)] = []
                    refreshed.reserveCapacity(32)

                    // Parse per-display space IDs (id64). If we can't parse (e.g. UI test override),
                    // skip the off-screen pass rather than showing windows from other Spaces.
                    var currentSpaceIdsByDisplay: [UInt32: UInt64] = [:]
                    currentSpaceIdsByDisplay.reserveCapacity(currentSpaceKeysByDisplay.count)
                    for (did, key) in currentSpaceKeysByDisplay {
                        if let id = UInt64(key) {
                            currentSpaceIdsByDisplay[UInt32(did)] = id
                        }
                    }

                    if !currentSpaceIdsByDisplay.isEmpty {
                        let allList = CGWindowListCopyWindowInfo(allOptions, kCGNullWindowID) as? [[CFString: Any]] ?? []
                        for dict in allList {
                            // Skip windows already included from the on-screen pass.
                            if isOnscreen(dict) { continue }

                            guard let parsed = parseWindowDict(dict, screens: screens, appInfoProvider: appInfo),
                                  shouldInclude(parsed.info) else { continue }

                            // Respect user prefs: hidden vs minimized are separate.
                            if parsed.info.isHidden {
                                guard config.showHiddenApps else { continue }
                            } else {
                                // Without AX trust, "off-screen + not hidden" includes many transient
                                // compositor surfaces that are not true minimized windows.
                                guard Self.shouldQueryAXMinimizedState(
                                    isHidden: parsed.info.isHidden,
                                    showMinimizedWindows: config.showMinimizedWindows,
                                    axEnabled: axEnabled
                                ) else { continue }

                                guard Self.matchesMinimizedAXWindow(
                                    parsed.info,
                                    snapshots: snapshots(for: parsed.pid)
                                ) else { continue }
                            }

                            let monitorRaw = parsed.info.monitorId.raw
                            guard let currentSpaceId = currentSpaceIdsByDisplay[monitorRaw] else { continue }

                            // Filter to windows that belong to this display's active Space after
                            // rejecting non-minimized off-screen surfaces; per-window Spaces calls
                            // are more expensive than cached per-process minimized-ID checks.
                            let spaces = spacesService.copySpacesForWindow(windowId: CGWindowID(parsed.info.id.raw))
                            guard spaces.contains(currentSpaceId) else { continue }

                            // Off-screen + not hidden => treat as minimized.
                            let info: WindowInfo = parsed.info.isHidden
                                ? parsed.info
                                : replacingMinimized(parsed.info, minimized: true)

                            refreshed.append((info: info, pid: parsed.pid))
                            if refreshed.count >= maxWindows { break }
                        }
                    }

                    offscreenCacheEntries = refreshed
                    lastOffscreenRefresh = now
                    lastOffscreenSpaceSignature = spaceSignature
                }

                for entry in offscreenCacheEntries {
                    guard !seenWindowIds.contains(entry.info.id.raw) else { continue }
                    parsedWindows.append(entry)
                    seenWindowIds.insert(entry.info.id.raw)
                    if parsedWindows.count >= maxWindows { break }
                }
            } else {
                // No reliable space filter available; avoid stale cross-space reuse.
                offscreenCacheEntries.removeAll(keepingCapacity: true)
                lastOffscreenSpaceSignature = ""
            }
        } else {
            offscreenCacheEntries.removeAll(keepingCapacity: true)
            lastOffscreenSpaceSignature = ""
        }

        // Title fallback: some apps return empty `kCGWindowName` (and Screen Recording
        // permission can also blank titles). Prefer AX titles when available, but cache
        // aggressively to avoid per-poll stalls.
        if axEnabled, parsedWindows.contains(where: { $0.info.title.isEmpty }) {
            parsedWindows = populateMissingTitlesFromAX(parsedWindows) { pid in
                snapshots(for: pid)
            }
        }

        parsedWindows = dedupeGhostWindows(parsedWindows)

        let windows = parsedWindows.map(\.info)
        Log.window.debug("Enumerated \(windows.count) windows")
        return windows
    }

    func invalidateEnumerationCaches() {
        axSnapshotCacheByPid.removeAll(keepingCapacity: true)
        appInfoCacheByPid.removeAll(keepingCapacity: true)
        offscreenCacheEntries.removeAll(keepingCapacity: true)
        lastOffscreenRefresh = 0
        lastOffscreenSpaceSignature = ""
    }

    // MARK: - Private

    private func getScreenFrames() -> [(displayId: UInt32, bounds: WindowBounds)] {
        var count: UInt32 = 0

        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displayIds = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIds, &count) == .success else {
            return []
        }

        return displayIds.prefix(Int(count)).map { did in
            let rect = CGDisplayBounds(did)
            return (did, WindowBounds(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.size.width,
                height: rect.size.height
            ))
        }
    }

    private func isOnscreen(_ dict: [CFString: Any]) -> Bool {
        // kCGWindowIsOnscreen is documented but the value type varies.
        if let v = dict[kCGWindowIsOnscreen as CFString] as? Bool { return v }
        if let v = dict[kCGWindowIsOnscreen as CFString] as? Int { return v != 0 }
        if let v = dict[kCGWindowIsOnscreen as CFString] as? NSNumber { return v.boolValue }
        return false
    }

    private func frontmostWindowId(in windowList: [[CFString: Any]], usingAllFallback: Bool) -> UInt32? {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        for dict in windowList {
            if usingAllFallback && !isOnscreen(dict) { continue }
            let layer = dict[kCGWindowLayer as CFString] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let pid = dict[kCGWindowOwnerPID] as? Int32,
                  pid != ownPid,
                  let windowId = dict[kCGWindowNumber] as? UInt32 else {
                continue
            }
            return windowId
        }
        return nil
    }

    private func monitorForWindow(_ bounds: WindowBounds, screens: [(displayId: UInt32, bounds: WindowBounds)]) -> MonitorId {
        DisplayAssignment.monitorId(for: bounds, screens: screens)
    }

    private func parseWindowDict(
        _ dict: [CFString: Any],
        screens: [(displayId: UInt32, bounds: WindowBounds)],
        appInfoProvider: ((pid_t) -> (bundleId: String, isHidden: Bool))? = nil
    ) -> (info: WindowInfo, pid: pid_t)? {
        guard let windowNumber = dict[kCGWindowNumber] as? UInt32,
              let pid = dict[kCGWindowOwnerPID] as? Int32 else {
            return nil
        }

        let appName = dict[kCGWindowOwnerName as CFString] as? String ?? ""
        let title = dict[kCGWindowName as CFString] as? String ?? ""
        let layer = dict[kCGWindowLayer as CFString] as? Int ?? 0

        guard layer == 0 else { return nil }

        let (bundleId, isHidden) = (appInfoProvider ?? getAppInfo)(pid)

        let bounds: WindowBounds
        if let boundsDict = dict[kCGWindowBounds as CFString] as? [String: Double] {
            bounds = WindowBounds(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
        } else {
            bounds = WindowBounds()
        }

        let monitorId = monitorForWindow(bounds, screens: screens)

        return (
            info: WindowInfo(
                id: WindowId(windowNumber),
                bundleId: BundleId(bundleId),
                appName: appName,
                title: title,
                isHidden: isHidden,
                isMinimized: false,
                monitorId: monitorId,
                bounds: bounds
            ),
            pid: pid
        )
    }

    private func makeSpaceSignature(_ keys: [CGDirectDisplayID: String]) -> String {
        keys
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")
    }

    private func populateMissingTitlesFromAX(
        _ parsed: [(info: WindowInfo, pid: pid_t)],
        snapshotProvider: (pid_t) -> [AXWindowSnapshot]
    ) -> [(info: WindowInfo, pid: pid_t)] {
        let now = CFAbsoluteTimeGetCurrent()

        // 1) Apply cached titles (fast path).
        var result = parsed.map { entry -> (info: WindowInfo, pid: pid_t) in
            guard entry.info.title.isEmpty, let cached = axTitleCache[entry.info.id.raw], !cached.isEmpty else {
                return entry
            }
            return (replacingTitle(entry.info, title: cached), entry.pid)
        }

        // 2) If everything is filled from cache (or nothing is missing), done.
        let missing = result.filter { $0.info.title.isEmpty }
        guard !missing.isEmpty else { return result }

        // 3) Throttle AX scans aggressively (poll timer runs at ~100ms).
        guard now - lastAXTitleRefresh >= axTitleRefreshInterval else { return result }
        lastAXTitleRefresh = now

        // Group missing windows by pid so we only copy AX window arrays once per app.
        var missingByPid: [pid_t: [WindowInfo]] = [:]
        for entry in missing {
            missingByPid[entry.pid, default: []].append(entry.info)
        }

        var resolved: [UInt32: String] = [:]
        resolved.reserveCapacity(missing.count)

        for (pid, needed) in missingByPid {
            let snapshots = snapshotProvider(pid)
            guard !snapshots.isEmpty else { continue }

            for info in needed {
                guard let title = matchAXTitle(info: info, snapshots: snapshots),
                      !title.isEmpty else { continue }
                resolved[info.id.raw] = title
                axTitleCache[info.id.raw] = title
            }
        }

        if resolved.isEmpty { return result }

        result = result.map { entry -> (info: WindowInfo, pid: pid_t) in
            guard entry.info.title.isEmpty, let title = resolved[entry.info.id.raw], !title.isEmpty else { return entry }
            return (replacingTitle(entry.info, title: title), entry.pid)
        }
        return result
    }

    private func axWindowSnapshots(pid: pid_t) -> [AXWindowSnapshot] {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, axMessagingTimeout)

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = Self.cfArray(from: value) else {
            return []
        }

        let count = CFArrayGetCount(axWindows)
        if count <= 0 { return [] }

        var snapshots: [AXWindowSnapshot] = []
        snapshots.reserveCapacity(count)

        for i in 0..<count {
            guard let axWin = Self.axElement(at: i, in: axWindows) else { continue }
            AXUIElementSetMessagingTimeout(axWin, axMessagingTimeout)

            var titleVal: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal)
            let title = titleVal as? String ?? ""

            var isMinimized: Bool? = nil
            var minimizedVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minimizedVal) == .success {
                if let b = minimizedVal as? Bool {
                    isMinimized = b
                } else if let n = minimizedVal as? NSNumber {
                    isMinimized = n.boolValue
                }
            }

            snapshots.append(AXWindowSnapshot(
                title: title,
                isMinimized: isMinimized,
                position: Self.axPosition(from: axWin),
                size: Self.axSize(from: axWin)
            ))
        }

        return snapshots
    }

    private nonisolated static func axBool(from value: CFTypeRef?) -> Bool? {
        guard let v = value else { return nil }
        if CFGetTypeID(v) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((v as! CFBoolean))
        }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    private nonisolated static func cfArray(from value: AnyObject?) -> CFArray? {
        guard let value,
              CFGetTypeID(value as CFTypeRef) == CFArrayGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: CFArray.self)
    }

    private nonisolated static func axElement(at index: CFIndex, in array: CFArray) -> AXUIElement? {
        guard index >= 0, index < CFArrayGetCount(array),
              let raw = CFArrayGetValueAtIndex(array, index) else {
            return nil
        }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return element
    }

    private nonisolated static func axPosition(from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    private nonisolated static func axSize(from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    private nonisolated static func bestAXSnapshotMatch(
        info: WindowInfo,
        snapshots: [AXWindowSnapshot]
    ) -> AXWindowSnapshot? {
        var best: (snapshot: AXWindowSnapshot, score: Double)?
        let target = info.bounds
        let targetArea = max(0.0, target.width) * max(0.0, target.height)

        for snapshot in snapshots {
            guard let position = snapshot.position, let size = snapshot.size else { continue }
            if !info.title.isEmpty, !snapshot.title.isEmpty, snapshot.title != info.title {
                continue
            }

            let bounds = WindowBounds(
                x: Double(position.x),
                y: Double(position.y),
                width: Double(size.width),
                height: Double(size.height)
            )
            let area = max(0.0, bounds.width) * max(0.0, bounds.height)
            let minArea = max(1.0, min(targetArea, area))
            let overlapRatio = bounds.intersectionArea(with: target) / minArea
            let centerDx = abs(bounds.center.x - target.center.x)
            let centerDy = abs(bounds.center.y - target.center.y)
            let widthDelta = abs(bounds.width - target.width)
            let heightDelta = abs(bounds.height - target.height)

            guard overlapRatio >= 0.70 ||
                  (centerDx <= 60 && centerDy <= 90 && widthDelta <= 220 && heightDelta <= 220) else {
                continue
            }

            let score = (1.0 - overlapRatio) * 300.0 + centerDx + centerDy + widthDelta * 0.03 + heightDelta * 0.03
            if best == nil || score < best!.score {
                best = (snapshot, score)
            }
        }

        return best?.snapshot
    }

    private nonisolated static func matchesMinimizedAXWindow(
        _ info: WindowInfo,
        snapshots: [AXWindowSnapshot]
    ) -> Bool {
        let minimized = snapshots.filter { $0.isMinimized == true }
        guard !minimized.isEmpty else { return false }

        if bestAXSnapshotMatch(info: info, snapshots: minimized) != nil {
            return true
        }

        return !info.title.isEmpty && minimized.contains { $0.title == info.title }
    }

    private func matchAXTitle(info: WindowInfo, snapshots: [AXWindowSnapshot]) -> String? {
        let titled = snapshots.filter { !$0.title.isEmpty }
        guard !titled.isEmpty else { return nil }

        if let bestGeometry = Self.bestAXSnapshotMatch(info: info, snapshots: titled) {
            return bestGeometry.title
        }

        return titled.count == 1 ? titled[0].title : nil
    }

    private func replacingTitle(_ info: WindowInfo, title: String) -> WindowInfo {
        WindowInfo(
            id: info.id,
            bundleId: info.bundleId,
            appName: info.appName,
            title: title,
            isHidden: info.isHidden,
            isMinimized: info.isMinimized,
            monitorId: info.monitorId,
            bounds: info.bounds
        )
    }

    private func replacingMinimized(_ info: WindowInfo, minimized: Bool) -> WindowInfo {
        WindowInfo(
            id: info.id,
            bundleId: info.bundleId,
            appName: info.appName,
            title: info.title,
            isHidden: info.isHidden,
            isMinimized: minimized,
            monitorId: info.monitorId,
            bounds: info.bounds
        )
    }

    private func getAppInfo(pid: Int32) -> (bundleId: String, isHidden: Bool) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return ("", false)
        }
        return (app.bundleIdentifier ?? "", app.isHidden)
    }

    private func shouldInclude(_ info: WindowInfo) -> Bool {
        if systemApps.contains(info.bundleId.raw) {
            return false
        }
        if info.bundleId.raw.isEmpty && info.title.isEmpty && info.appName.isEmpty {
            return false
        }
        return true
    }

    /// Defensive de-duplication for compositor edge cases where a single logical
    /// window can be reported multiple times with different CGWindow IDs.
    ///
    /// We keep the first entry per ID, then collapse "same surface" entries by
    /// app/pid/title/display and coarse bounds buckets.
    private func dedupeGhostWindows(_ entries: [(info: WindowInfo, pid: pid_t)]) -> [(info: WindowInfo, pid: pid_t)] {
        var out: [(info: WindowInfo, pid: pid_t)] = []
        out.reserveCapacity(entries.count)

        var seenIds = Set<UInt32>()
        seenIds.reserveCapacity(entries.count)

        var seenSignatures = Set<String>()
        seenSignatures.reserveCapacity(entries.count)

        for entry in entries {
            let w = entry.info

            if !seenIds.insert(w.id.raw).inserted {
                continue
            }

            let title = w.title.isEmpty ? w.appName : w.title
            // 16pt buckets absorb tiny reporting jitter while preserving genuinely
            // separate windows that are not fully overlapped.
            let bx = Int((w.bounds.x / 16.0).rounded())
            let by = Int((w.bounds.y / 16.0).rounded())
            let bw = Int((w.bounds.width / 16.0).rounded())
            let bh = Int((w.bounds.height / 16.0).rounded())
            let dim = (w.isHidden || w.isMinimized) ? "1" : "0"
            let sig = "\(w.bundleId.raw)|\(entry.pid)|\(w.monitorId.raw)|\(dim)|\(title)|\(bx),\(by),\(bw),\(bh)"
            if !seenSignatures.insert(sig).inserted {
                continue
            }

            // Near-overlap collapse for same app/process/display/title:
            // keep only one surface when two windows are effectively the same rectangle.
            let titleKey = title
            let area = max(0.0, w.bounds.width) * max(0.0, w.bounds.height)
            var replaced = false
            for i in out.indices {
                let e = out[i]
                let ow = e.info
                let otherTitle = ow.title.isEmpty ? ow.appName : ow.title
                guard e.pid == entry.pid,
                      ow.bundleId.raw == w.bundleId.raw,
                      ow.monitorId.raw == w.monitorId.raw,
                      otherTitle == titleKey else { continue }

                let otherArea = max(0.0, ow.bounds.width) * max(0.0, ow.bounds.height)
                let minArea = max(1.0, min(area, otherArea))
                let overlap = w.bounds.intersectionArea(with: ow.bounds)
                let overlapRatio = overlap / minArea
                guard overlapRatio >= 0.92 else { continue }

                // Prefer the entry that has a real title, then larger area.
                let currentHasTitle = !w.title.isEmpty
                let otherHasTitle = !ow.title.isEmpty
                if (currentHasTitle && !otherHasTitle) || (currentHasTitle == otherHasTitle && area > otherArea) {
                    out[i] = entry
                }
                replaced = true
                break
            }
            if replaced { continue }

            out.append(entry)
        }

        if out.count < entries.count {
            Log.window.debug("Deduped ghost windows: \(entries.count) -> \(out.count)")
        }

        return out
    }

    nonisolated static func ghostCollapseCandidatePids(
        _ entries: [(info: WindowInfo, pid: pid_t)]
    ) -> Set<pid_t> {
        guard entries.count > 1 else { return [] }

        var byPid: [pid_t: [(info: WindowInfo, pid: pid_t)]] = [:]
        byPid.reserveCapacity(16)
        for entry in entries {
            byPid[entry.pid, default: []].append(entry)
        }

        var result = Set<pid_t>()
        result.reserveCapacity(byPid.count)

        for (pid, group) in byPid {
            guard group.count > 1 else { continue }

            if group.contains(where: { isTinyGhostCandidate($0.info) }) {
                result.insert(pid)
                continue
            }

            var byVisualKey: [String: [WindowInfo]] = [:]
            byVisualKey.reserveCapacity(group.count)
            for entry in group {
                byVisualKey[ghostCollapseVisualKey(for: entry.info), default: []].append(entry.info)
            }

            for candidates in byVisualKey.values where candidates.count > 1 {
                if hasOverlappingGhostCandidate(candidates) {
                    result.insert(pid)
                    break
                }
            }
        }

        return result
    }

    nonisolated static func shouldQueryAXMinimizedState(
        isHidden: Bool,
        showMinimizedWindows: Bool,
        axEnabled: Bool
    ) -> Bool {
        !isHidden && showMinimizedWindows && axEnabled
    }

    private nonisolated static func ghostCollapseVisualKey(for info: WindowInfo) -> String {
        let title = info.title.isEmpty ? info.appName : info.title
        return "\(info.bundleId.raw)|\(info.monitorId.raw)|\(title)"
    }

    private nonisolated static func isTinyGhostCandidate(_ info: WindowInfo) -> Bool {
        let width = max(0.0, info.bounds.width)
        let height = max(0.0, info.bounds.height)
        return width <= 1.0 || height <= 1.0 || (width * height) <= 4.0
    }

    private nonisolated static func hasOverlappingGhostCandidate(_ windows: [WindowInfo]) -> Bool {
        guard windows.count > 1 else { return false }
        for i in 0..<(windows.count - 1) {
            for j in (i + 1)..<windows.count {
                let a = windows[i]
                let b = windows[j]
                let areaA = max(0.0, a.bounds.width) * max(0.0, a.bounds.height)
                let areaB = max(0.0, b.bounds.width) * max(0.0, b.bounds.height)
                let minArea = max(1.0, min(areaA, areaB))
                let overlapRatio = a.bounds.intersectionArea(with: b.bounds) / minArea
                if overlapRatio >= 0.25 {
                    return true
                }
            }
        }
        return false
    }

    #if DEBUG
    deinit {
        Log.window.debug("WindowManager deinit")
    }
    #endif
}
