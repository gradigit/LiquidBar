// MARK: - TaskbarItem

enum TaskbarItem: Sendable {
    case window(id: WindowId, bundleId: String, title: String, appName: String, isHidden: Bool, isMinimized: Bool, screenId: UInt32)
    case appGroup(bundleId: String, appName: String, windowCount: Int, windows: [WindowId], isHidden: Bool, isMinimized: Bool, screenId: UInt32)
    case pinnedApp(bundleId: String, screenId: UInt32)
    /// Launcher / start button (per display).
    case launcher(screenId: UInt32)
    /// Sidebar tile backed by a plugin/provider.
    case pluginTile(id: String, providerId: String?, title: String, icon: String?, visualState: PluginTileVisualState, screenId: UInt32)
    /// User-defined group chip representing multiple windows ("tab group").
    case tabGroup(id: String, representativeBundleId: String, name: String, emoji: String?, windowCount: Int, isHidden: Bool, isMinimized: Bool, screenId: UInt32)
    /// Custom spacer/gap (fixed width).
    case customSpacer(id: String, width: Int, screenId: UInt32? = nil)
    /// Custom text label (no icon).
    case customText(id: String, text: String, screenId: UInt32? = nil)
    /// Custom URL/deeplink item.
    case customLink(id: String, title: String, url: String, icon: String? = nil, screenId: UInt32? = nil)
    /// Custom file/folder shortcut.
    case customFolder(id: String, title: String, path: String, icon: String? = nil, screenId: UInt32? = nil)

    var bundleId: String {
        switch self {
        case .window(_, let bundleId, _, _, _, _, _): bundleId
        case .appGroup(let bundleId, _, _, _, _, _, _): bundleId
        case .pinnedApp(let bundleId, _): bundleId
        case .launcher: "sf:magnifyingglass"
        case .pluginTile(_, let providerId, _, _, _, _): providerId ?? "sf:square.grid.2x2"
        case .tabGroup(_, let representativeBundleId, _, _, _, _, _, _): representativeBundleId
        case .customSpacer(let id, _, _): "custom:spacer:\(id)"
        case .customText(let id, _, _): "custom:text:\(id)"
        case .customLink(let id, _, _, _, _): "custom:link:\(id)"
        case .customFolder(let id, _, _, _, _): "custom:folder:\(id)"
        }
    }

    /// Icon lookup key used by the icon cache. `nil` means "no icon".
    var iconKey: String? {
        switch self {
        case .window: return bundleId
        case .appGroup: return bundleId
        case .pinnedApp: return bundleId
        case .launcher: return "sf:magnifyingglass"
        case .pluginTile(_, _, _, let icon, _, _):
            return icon ?? "sf:square.grid.2x2"
        case .tabGroup: return bundleId
        case .customSpacer: return nil
        case .customText: return nil
        case .customLink(_, _, _, let icon, _):
            return icon ?? "sf:link"
        case .customFolder(_, _, let path, let icon, _):
            return icon ?? "file:\(path)"
        }
    }

    var screenId: UInt32? {
        switch self {
        case .window(_, _, _, _, _, _, let screenId): screenId
        case .appGroup(_, _, _, _, _, _, let screenId): screenId
        case .pinnedApp(_, let screenId): screenId
        case .launcher(let screenId): screenId
        case .pluginTile(_, _, _, _, _, let screenId): screenId
        case .tabGroup(_, _, _, _, _, _, _, let screenId): screenId
        case .customSpacer(_, _, let screenId): screenId
        case .customText(_, _, let screenId): screenId
        case .customLink(_, _, _, _, let screenId): screenId
        case .customFolder(_, _, _, _, let screenId): screenId
        }
    }

    /// Whether this item represents a hidden or minimized window/group
    var isDimmed: Bool {
        switch self {
        case .window(_, _, _, _, let isHidden, let isMinimized, _): isHidden || isMinimized
        case .appGroup(_, _, _, _, let isHidden, let isMinimized, _): isHidden || isMinimized
        case .pinnedApp: false
        case .launcher: false
        case .pluginTile: false
        case .tabGroup(_, _, _, _, _, let isHidden, let isMinimized, _): isHidden || isMinimized
        case .customSpacer: false
        case .customText: false
        case .customLink: false
        case .customFolder: false
        }
    }

    /// Whether this item represents a hidden app/window (Cmd+H).
    var isHidden: Bool {
        switch self {
        case .window(_, _, _, _, let isHidden, _, _): isHidden
        case .appGroup(_, _, _, _, let isHidden, _, _): isHidden
        case .tabGroup(_, _, _, _, _, let isHidden, _, _): isHidden
        default: false
        }
    }

    /// Whether this item represents a minimized window/group (green/yellow button minimize).
    var isMinimized: Bool {
        switch self {
        case .window(_, _, _, _, _, let isMinimized, _): isMinimized
        case .appGroup(_, _, _, _, _, let isMinimized, _): isMinimized
        case .tabGroup(_, _, _, _, _, _, let isMinimized, _): isMinimized
        default: false
        }
    }

    func displayTitle(iconsOnly: Bool) -> String {
        if iconsOnly { return "" }

        switch self {
        case .window(_, _, let title, let appName, _, _, _):
            let text = title.isEmpty ? appName : title
            if text.count > 30 {
                return String(text.prefix(27)) + "..."
            }
            return text

        case .appGroup(_, let appName, _, _, _, _, _):
            // Window count is rendered as a dedicated badge, so keep the title clean.
            return appName

        case .pinnedApp(let bundleId, _):
            return bundleId.split(separator: ".").last.map(String.init) ?? bundleId

        case .launcher:
            return "Launcher"

        case .pluginTile(_, _, let title, _, _, _):
            if title.count > 30 {
                return String(title.prefix(27)) + "..."
            }
            return title

        case .tabGroup(_, _, let name, let emoji, let windowCount, _, _, _):
            let prefix = (emoji?.isEmpty == false) ? "\(emoji!) " : ""
            return "\(prefix)\(name) (\(windowCount))"

        case .customSpacer:
            return ""
        case .customText(_, let text, _):
            if text.count > 30 {
                return String(text.prefix(27)) + "..."
            }
            return text
        case .customLink(_, let title, _, _, _):
            if title.count > 30 {
                return String(title.prefix(27)) + "..."
            }
            return title
        case .customFolder(_, let title, _, _, _):
            if title.count > 30 {
                return String(title.prefix(27)) + "..."
            }
            return title
        }
    }
}

// MARK: - UIRenderer

enum UIRenderer {
    @MainActor
    static func render(from state: WindowStateStore, config: Config) -> [TaskbarItem] {
        var items: [TaskbarItem] = []
        let allWindows = state.getWindows()

        if config.groupByApp {
            var seenKeys: Set<String> = []
            seenKeys.reserveCapacity(allWindows.count)

            for window in allWindows {
                let bid = window.bundleId.raw
                let key: String
                if config.windowDisplayMode == .perDisplay {
                    key = "\(bid)|\(window.monitorId.raw)"
                } else {
                    key = bid
                }

                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)

                let group: [WindowInfo]
                if config.windowDisplayMode == .perDisplay {
                    group = dedupedGroupWindows(
                        allWindows.filter { $0.bundleId.raw == bid && $0.monitorId == window.monitorId }
                    )
                } else {
                    group = dedupedGroupWindows(
                        allWindows.filter { $0.bundleId.raw == bid }
                    )
                }

                if group.count == 1 {
                    let w = group[0]
                    items.append(.window(
                        id: w.id,
                        bundleId: bid,
                        title: w.title,
                        appName: w.appName,
                        isHidden: w.isHidden,
                        isMinimized: w.isMinimized,
                        screenId: w.monitorId.raw
                    ))
                } else if group.count > 1 {
                    let allDimmed = group.allSatisfy { $0.isHidden || $0.isMinimized }
                    let allHidden = group.allSatisfy { $0.isHidden }
                    let allMinimized = allDimmed && !allHidden
                    items.append(.appGroup(
                        bundleId: bid,
                        appName: group[0].appName,
                        windowCount: group.count,
                        windows: group.map(\.id),
                        isHidden: allHidden,
                        isMinimized: allMinimized,
                        screenId: group[0].monitorId.raw
                    ))
                }
            }
        } else {
            for window in allWindows {
                items.append(.window(
                    id: window.id,
                    bundleId: window.bundleId.raw,
                    title: window.title,
                    appName: window.appName,
                    isHidden: window.isHidden,
                    isMinimized: window.isMinimized,
                    screenId: window.monitorId.raw
                ))
            }
        }

        // Filter dimmed items based on separate hidden/minimized toggles.
        if !config.showHiddenApps || !config.showMinimizedWindows {
            items.removeAll { item in
                if item.isHidden && !config.showHiddenApps { return true }
                if item.isMinimized && !config.showMinimizedWindows { return true }
                return false
            }
        }

        // Partition: items that should collapse to icon-only at the end.
        let shouldCollapse: (TaskbarItem) -> Bool = { item in
            (item.isHidden && config.showHiddenApps && config.hiddenWindowMode == .collapsedRight)
                || (item.isMinimized && config.showMinimizedWindows && config.minimizedWindowMode == .collapsedRight)
        }
        if items.contains(where: shouldCollapse) {
            let normal = items.filter { !shouldCollapse($0) }
            let collapsed = items.filter { shouldCollapse($0) }
            items = normal + collapsed
        }

        return items
    }

    /// De-duplicate windows for grouped rendering.
    ///
    /// We always de-dupe by window ID, and additionally collapse pathological duplicates
    /// where the system reports the same visible window multiple times with different IDs.
    ///
    /// Strategy:
    /// 1) strict window-id dedupe
    /// 2) coarse signature dedupe (title + 16pt bounds buckets)
    /// 3) overlap dedupe (same app/title/display + >92% overlap ratio)
    private static func dedupedGroupWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var out: [WindowInfo] = []
        out.reserveCapacity(windows.count)

        var seenIds = Set<UInt32>()
        seenIds.reserveCapacity(windows.count)

        var seenSignatures = Set<String>()
        seenSignatures.reserveCapacity(windows.count)

        for w in windows {
            if !seenIds.insert(w.id.raw).inserted {
                continue
            }

            // Snap bounds to 16pt buckets so tiny reporting jitter doesn't defeat dedupe.
            let bx = Int((w.bounds.x / 16.0).rounded())
            let by = Int((w.bounds.y / 16.0).rounded())
            let bw = Int((w.bounds.width / 16.0).rounded())
            let bh = Int((w.bounds.height / 16.0).rounded())
            let title = w.title.isEmpty ? w.appName : w.title
            let signature = "\(w.bundleId.raw)|\(w.monitorId.raw)|\(title)|\(bx),\(by),\(bw),\(bh)"

            if !seenSignatures.insert(signature).inserted {
                continue
            }

            let area = max(0.0, w.bounds.width) * max(0.0, w.bounds.height)
            var collapsed = false
            for i in out.indices {
                let existing = out[i]
                let existingTitle = existing.title.isEmpty ? existing.appName : existing.title
                guard existing.bundleId.raw == w.bundleId.raw,
                      existing.monitorId == w.monitorId,
                      existingTitle == title else { continue }

                let existingArea = max(0.0, existing.bounds.width) * max(0.0, existing.bounds.height)
                let minArea = max(1.0, min(area, existingArea))
                let overlapRatio = w.bounds.intersectionArea(with: existing.bounds) / minArea
                guard overlapRatio >= 0.92 else { continue }

                // Prefer more informative entries first (real title), then larger surface.
                let currentHasRealTitle = !w.title.isEmpty
                let existingHasRealTitle = !existing.title.isEmpty
                if (currentHasRealTitle && !existingHasRealTitle)
                    || (currentHasRealTitle == existingHasRealTitle && area > existingArea) {
                    out[i] = w
                }
                collapsed = true
                break
            }
            if collapsed {
                continue
            }

            out.append(w)
        }

        return out
    }
}
