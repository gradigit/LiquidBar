import CoreGraphics

/// Pure helper: builds pinned app items per display from the current window items.
enum PinnedAppsComposer {
    /// - Parameters:
    ///   - windowItems: The items produced from the current window list (no pinned apps).
    ///   - displayIds: Displays that have an active LiquidBar panel.
    ///   - pinnedAppsByDisplay: Pinned bundle IDs for each display's active Space.
    ///   - windowDisplayMode: Whether the bar is per-display or all-windows.
    ///   - openBundleIdsByDisplay: Optional override for which bundles should be treated as "open".
    ///     Use this when transforming windowItems (e.g., collapsing into tab group chips) so pinned apps
    ///     don't appear for apps that still have open windows.
    static func compose(
        windowItems: [TaskbarItem],
        displayIds: [CGDirectDisplayID],
        pinnedAppsByDisplay: [CGDirectDisplayID: [String]],
        windowDisplayMode: WindowDisplayMode,
        openBundleIdsByDisplay: [CGDirectDisplayID: Set<String>]? = nil
    ) -> (items: [TaskbarItem], pinnedBundleIdsByDisplay: [CGDirectDisplayID: Set<String>]) {
        var items = windowItems

        var pinnedBundleIdsByDisplay: [CGDirectDisplayID: Set<String>] = [:]
        pinnedBundleIdsByDisplay.reserveCapacity(displayIds.count)

        for displayId in displayIds {
            let pinned = pinnedAppsByDisplay[displayId] ?? []
            pinnedBundleIdsByDisplay[displayId] = Set(pinned)

            let openBundles: Set<String>
            if let override = openBundleIdsByDisplay?[displayId] {
                openBundles = override
            } else {
                switch windowDisplayMode {
                case .perDisplay:
                    openBundles = Set(windowItems.compactMap { item in
                        guard item.screenId == displayId else { return nil }
                        switch item {
                        case .window(_, let bundleId, _, _, _, _, _):
                            return bundleId
                        case .appGroup(let bundleId, _, _, _, _, _, _):
                            return bundleId
                        case .tabGroup(_, let representativeBundleId, _, _, _, _, _, _):
                            return representativeBundleId
                        default:
                            return nil
                        }
                    })
                case .allWindows:
                    openBundles = Set(windowItems.compactMap { item in
                        switch item {
                        case .window(_, let bundleId, _, _, _, _, _):
                            return bundleId
                        case .appGroup(let bundleId, _, _, _, _, _, _):
                            return bundleId
                        case .tabGroup(_, let representativeBundleId, _, _, _, _, _, _):
                            return representativeBundleId
                        default:
                            return nil
                        }
                    })
                }
            }

            for bundleId in pinned where !openBundles.contains(bundleId) {
                items.append(.pinnedApp(bundleId: bundleId, screenId: displayId))
            }
        }

        return (items, pinnedBundleIdsByDisplay)
    }
}
