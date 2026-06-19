@MainActor
final class WindowStateStore {
    private(set) var windows: [WindowId: WindowInfo] = [:]
    private(set) var windowOrder: [WindowId] = []
    private(set) var seenApps: Set<String> = []
    private var newApps: [String] = []

    /// Update state with new window list. Returns true if anything changed.
    func update(windows newWindows: [WindowInfo], config: Config) -> Bool {
        let oldIds = Set(windows.keys)
        let newIds = Set(newWindows.map(\.id))

        let changed = oldIds != newIds || newWindows.contains { w in
            windows[w.id].map { old in
                old.title != w.title
                    || old.isHidden != w.isHidden
                    || old.isMinimized != w.isMinimized
                    || old.monitorId != w.monitorId
            } ?? true
        }

        guard changed else { return false }

        // Track new apps
        for window in newWindows {
            let bundleId = window.bundleId.raw
            if !seenApps.contains(bundleId) {
                seenApps.insert(bundleId)
                if !config.isBlacklisted(bundleId) {
                    newApps.append(bundleId)
                }
            }
        }

        // Update windows map, filtering blacklisted
        windows.removeAll()
        for window in newWindows {
            if !config.isBlacklisted(window.bundleId.raw) {
                windows[window.id] = window
            }
        }

        // Update order: retain existing, append new (preserving input order)
        let currentIds = Set(windows.keys)
        windowOrder.removeAll { !currentIds.contains($0) }

        for window in newWindows where currentIds.contains(window.id) {
            if !windowOrder.contains(window.id) {
                windowOrder.append(window.id)
            }
        }

        return true
    }

    /// Get all windows ordered by windowOrder.
    func getWindows() -> [WindowInfo] {
        windowOrder.compactMap { windows[$0] }
    }

    /// Get windows grouped by bundle ID.
    func getWindowsGrouped() -> [(bundleId: String, windows: [WindowInfo])] {
        var grouped: [(String, [WindowInfo])] = []
        var seen: Set<String> = []

        for window in getWindows() {
            let bid = window.bundleId.raw
            if !seen.contains(bid) {
                seen.insert(bid)
                let group = getWindows().filter { $0.bundleId.raw == bid }
                grouped.append((bid, group))
            }
        }
        return grouped
    }

    /// Take and clear newly seen apps.
    func takeNewApps() -> [String] {
        let apps = newApps
        newApps.removeAll()
        return apps
    }

    /// Move a window in the order.
    func reorder(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex >= 0, fromIndex < windowOrder.count,
              toIndex >= 0, toIndex <= windowOrder.count else { return }
        let id = windowOrder.remove(at: fromIndex)
        // `toIndex` is an insertion marker in the original visible order. When
        // moving forward, the target slot shifts left after removing the source.
        let adjustedToIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let insertAt = min(adjustedToIndex, windowOrder.count)
        windowOrder.insert(id, at: insertAt)
    }

    /// Apply a persisted preferred order (window IDs) to current live windows.
    ///
    /// Unknown/stale IDs are ignored. Any live windows not listed are appended
    /// in their existing relative order.
    @discardableResult
    func applyPreferredWindowOrder(_ preferred: [UInt32]) -> Bool {
        guard !windowOrder.isEmpty else { return false }
        guard !preferred.isEmpty else { return false }

        let currentSet = Set(windowOrder)
        var seen = Set<WindowId>()
        var reordered: [WindowId] = []
        reordered.reserveCapacity(windowOrder.count)

        for raw in preferred {
            let wid = WindowId(raw)
            guard currentSet.contains(wid) else { continue }
            if seen.insert(wid).inserted {
                reordered.append(wid)
            }
        }

        for wid in windowOrder where seen.insert(wid).inserted {
            reordered.append(wid)
        }

        guard reordered != windowOrder else { return false }
        windowOrder = reordered
        return true
    }

    /// Reorder a subset of windows in-place according to `orderedWindowIds`.
    ///
    /// This preserves every non-target window and preserves the exact "slots" of
    /// target windows in the global order. Useful for app-group thumbnail reorders.
    @discardableResult
    func reorderSubset(orderedWindowIds: [UInt32]) -> Bool {
        guard !windowOrder.isEmpty else { return false }
        guard !orderedWindowIds.isEmpty else { return false }

        let currentSet = Set(windowOrder)
        var targetOrder: [WindowId] = []
        targetOrder.reserveCapacity(orderedWindowIds.count)
        var seenTargets = Set<WindowId>()
        for raw in orderedWindowIds {
            let wid = WindowId(raw)
            guard currentSet.contains(wid) else { continue }
            if seenTargets.insert(wid).inserted {
                targetOrder.append(wid)
            }
        }
        guard !targetOrder.isEmpty else { return false }

        let targetSet = Set(targetOrder)
        var nextTargetIndex = 0
        var rebuilt: [WindowId] = []
        rebuilt.reserveCapacity(windowOrder.count)

        for wid in windowOrder {
            if targetSet.contains(wid), nextTargetIndex < targetOrder.count {
                rebuilt.append(targetOrder[nextTargetIndex])
                nextTargetIndex += 1
            } else if !targetSet.contains(wid) {
                rebuilt.append(wid)
            }
        }

        // If some targets were filtered out during slot replacement, append them.
        while nextTargetIndex < targetOrder.count {
            rebuilt.append(targetOrder[nextTargetIndex])
            nextTargetIndex += 1
        }

        guard rebuilt != windowOrder else { return false }
        windowOrder = rebuilt
        return true
    }

    #if DEBUG
    deinit {
        Log.window.debug("WindowStateStore deinit")
    }
    #endif
}
