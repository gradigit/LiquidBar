import Foundation

struct WindowPresentationOverride: Codable, Sendable, Equatable {
    var title: String?
    var colorHex: String?

    var isEmpty: Bool {
        (title?.isEmpty ?? true) && (colorHex?.isEmpty ?? true)
    }
}

struct UserState: Codable, Sendable, Equatable {
    var appOrder: [String] = []
    /// Persistent ordering of taskbar windows/items by window id.
    /// Used to restore drag-reordered positions across LiquidBar restarts.
    var windowOrder: [UInt32] = []
    /// Persistent ordering of visible taskbar item identities for free-placement
    /// surfaces such as movable system indicators.
    var taskbarItemOrder: [String] = []
    /// Persistent metric ordering inside the system-indicator cluster.
    var systemIndicatorOrder: [String] = []
    /// Per-Space pinned apps, keyed by Space `id64` string.
    var pinnedAppsBySpace: [String: [String]] = [:]
    /// Persistent ordering for group-preview thumbnails (mainly app groups).
    /// Keys match EventLoop preview keys (e.g. `app:com.apple.finder`).
    var groupPreviewOrderByKey: [String: [UInt32]] = [:]
    /// User-defined window groups ("tab groups").
    var tabGroups: [TabGroup] = []
    /// LiquidBar-only display overrides for real windows.
    ///
    /// Keys are stable fingerprints derived from the original bundle id + title.
    /// Window ids are not stable across launches, so they are used only as runtime
    /// lookup handles in `EventLoop`.
    var windowPresentationOverrides: [String: WindowPresentationOverride] = [:]

    // MARK: - Codable (backward-compatible decoding)

    private enum CodingKeys: String, CodingKey {
        case appOrder
        case windowOrder
        case taskbarItemOrder
        case systemIndicatorOrder
        case pinnedAppsBySpace
        case groupPreviewOrderByKey
        case tabGroups
        case windowPresentationOverrides
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appOrder = try c.decodeIfPresent([String].self, forKey: .appOrder) ?? []
        windowOrder = try c.decodeIfPresent([UInt32].self, forKey: .windowOrder) ?? []
        taskbarItemOrder = try c.decodeIfPresent([String].self, forKey: .taskbarItemOrder) ?? []
        systemIndicatorOrder = try c.decodeIfPresent([String].self, forKey: .systemIndicatorOrder) ?? []
        pinnedAppsBySpace = try c.decodeIfPresent([String: [String]].self, forKey: .pinnedAppsBySpace) ?? [:]
        groupPreviewOrderByKey = try c.decodeIfPresent([String: [UInt32]].self, forKey: .groupPreviewOrderByKey) ?? [:]
        tabGroups = try c.decodeIfPresent([TabGroup].self, forKey: .tabGroups) ?? []
        windowPresentationOverrides = try c.decodeIfPresent([String: WindowPresentationOverride].self, forKey: .windowPresentationOverrides) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appOrder, forKey: .appOrder)
        try c.encode(windowOrder, forKey: .windowOrder)
        try c.encode(taskbarItemOrder, forKey: .taskbarItemOrder)
        try c.encode(systemIndicatorOrder, forKey: .systemIndicatorOrder)
        try c.encode(pinnedAppsBySpace, forKey: .pinnedAppsBySpace)
        try c.encode(groupPreviewOrderByKey, forKey: .groupPreviewOrderByKey)
        try c.encode(tabGroups, forKey: .tabGroups)
        try c.encode(windowPresentationOverrides, forKey: .windowPresentationOverrides)
    }

    // MARK: - Persistence

    static func load() -> UserState {
        let path = Config.statePath
        guard FileManager.default.fileExists(atPath: path.path) else {
            return UserState()
        }
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(UserState.self, from: data)
        } catch {
            Log.config.error("Failed to load state: \(error)")
            return UserState()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Config.configDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Config.statePath, options: .atomic)
        } catch {
            // Silently ignore save errors
        }
    }

    // MARK: - Mutations (auto-save)

    mutating func updateOrder(_ order: [String]) {
        appOrder = order
        save()
    }

    mutating func updateWindowOrder(_ order: [UInt32]) {
        // Keep deterministic + deduped.
        var seen = Set<UInt32>()
        let normalized = order.filter { seen.insert($0).inserted }
        guard windowOrder != normalized else { return }
        windowOrder = normalized
        save()
    }

    mutating func updateTaskbarItemOrder(_ order: [String]) {
        var seen = Set<String>()
        let normalized = order.filter { seen.insert($0).inserted }
        guard taskbarItemOrder != normalized else { return }
        taskbarItemOrder = normalized
        save()
    }

    mutating func updateSystemIndicatorOrder(_ order: [String]) {
        var seen = Set<String>()
        let normalized = order.filter { $0.hasPrefix("system.") && seen.insert($0).inserted }
        guard systemIndicatorOrder != normalized else { return }
        systemIndicatorOrder = normalized
        save()
    }

    func preferredGroupPreviewOrder(for key: String) -> [UInt32]? {
        groupPreviewOrderByKey[key]
    }

    mutating func updateGroupPreviewOrder(key: String, orderedWindowIds: [UInt32]) {
        var seen = Set<UInt32>()
        let normalized = orderedWindowIds.filter { seen.insert($0).inserted }

        if normalized.isEmpty {
            if groupPreviewOrderByKey.removeValue(forKey: key) != nil {
                save()
            }
            return
        }

        guard groupPreviewOrderByKey[key] != normalized else { return }
        groupPreviewOrderByKey[key] = normalized
        save()
    }

    func pinnedApps(for spaceKey: String) -> [String] {
        pinnedAppsBySpace[spaceKey] ?? []
    }

    mutating func pin(bundleId: String, spaceKey: String) {
        var apps = pinnedAppsBySpace[spaceKey] ?? []
        guard !apps.contains(bundleId) else { return }
        apps.append(bundleId)
        pinnedAppsBySpace[spaceKey] = apps
        save()
    }

    mutating func unpin(bundleId: String, spaceKey: String) {
        guard var apps = pinnedAppsBySpace[spaceKey] else { return }
        apps.removeAll { $0 == bundleId }
        if apps.isEmpty {
            pinnedAppsBySpace.removeValue(forKey: spaceKey)
        } else {
            pinnedAppsBySpace[spaceKey] = apps
        }
        save()
    }

    func isPinned(bundleId: String, spaceKey: String) -> Bool {
        pinnedAppsBySpace[spaceKey]?.contains(bundleId) ?? false
    }

    // MARK: - Tab Groups

    /// Returns the id of the tab group that currently contains `windowId`, if any.
    func tabGroupId(containing windowId: UInt32) -> String? {
        for g in tabGroups where g.windowIds.contains(windowId) {
            return g.id
        }
        return nil
    }

    func tabGroup(withId id: String) -> TabGroup? {
        tabGroups.first(where: { $0.id == id })
    }

    mutating func createTabGroup(name: String, emoji: String? = nil, colorHex: String? = nil, withWindowId windowId: UInt32) -> TabGroup {
        // A window can only belong to one group; remove it from any existing group first.
        removeWindowFromAnyTabGroup(windowId: windowId)

        let group = TabGroup(name: name, emoji: emoji, colorHex: colorHex, windowIds: [windowId])
        tabGroups.append(group)
        save()
        return group
    }

    mutating func renameTabGroup(id: String, name: String, emoji: String? = nil, colorHex: String? = nil) {
        guard let idx = tabGroups.firstIndex(where: { $0.id == id }) else { return }
        tabGroups[idx].name = name
        tabGroups[idx].emoji = emoji
        tabGroups[idx].colorHex = colorHex
        save()
    }

    mutating func deleteTabGroup(id: String) {
        tabGroups.removeAll { $0.id == id }
        save()
    }

    mutating func addWindowToTabGroup(windowId: UInt32, groupId: String) {
        removeWindowFromAnyTabGroup(windowId: windowId)
        guard let idx = tabGroups.firstIndex(where: { $0.id == groupId }) else { return }
        if !tabGroups[idx].windowIds.contains(windowId) {
            tabGroups[idx].windowIds.append(windowId)
            save()
        }
    }

    mutating func removeWindowFromTabGroup(windowId: UInt32, groupId: String) {
        guard let idx = tabGroups.firstIndex(where: { $0.id == groupId }) else { return }
        tabGroups[idx].windowIds.removeAll { $0 == windowId }
        save()
    }

    mutating func removeWindowFromAnyTabGroup(windowId: UInt32) {
        var changed = false
        for i in tabGroups.indices {
            let before = tabGroups[i].windowIds.count
            tabGroups[i].windowIds.removeAll { $0 == windowId }
            if tabGroups[i].windowIds.count != before {
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// Reorder members inside a tab group.
    ///
    /// `orderedWindowIds` is treated as a preferred order for currently-known members.
    /// Unknown IDs are ignored; any existing members not listed are appended in their
    /// previous relative order.
    mutating func reorderTabGroupWindows(groupId: String, orderedWindowIds: [UInt32]) {
        guard let idx = tabGroups.firstIndex(where: { $0.id == groupId }) else { return }
        let existing = tabGroups[idx].windowIds
        guard !existing.isEmpty else { return }

        let existingSet = Set(existing)
        var seen = Set<UInt32>()
        var reordered: [UInt32] = []
        reordered.reserveCapacity(existing.count)

        for wid in orderedWindowIds where existingSet.contains(wid) {
            if seen.insert(wid).inserted {
                reordered.append(wid)
            }
        }

        for wid in existing where seen.insert(wid).inserted {
            reordered.append(wid)
        }

        guard reordered != existing else { return }
        tabGroups[idx].windowIds = reordered
        save()
    }

    // MARK: - Window Presentation Overrides

    func presentationOverride(for key: String) -> WindowPresentationOverride? {
        windowPresentationOverrides[key]
    }

    mutating func setWindowTitleOverride(key: String, title: String?) {
        guard !key.isEmpty else { return }
        var override = windowPresentationOverrides[key] ?? WindowPresentationOverride()
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        override.title = (normalized?.isEmpty == false) ? normalized : nil
        setWindowPresentationOverride(key: key, override: override)
    }

    mutating func setWindowColorOverride(key: String, colorHex: String?) {
        guard !key.isEmpty else { return }
        var override = windowPresentationOverrides[key] ?? WindowPresentationOverride()
        override.colorHex = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        if override.colorHex?.isEmpty == true {
            override.colorHex = nil
        }
        setWindowPresentationOverride(key: key, override: override)
    }

    mutating func clearWindowPresentationOverride(key: String) {
        guard windowPresentationOverrides.removeValue(forKey: key) != nil else { return }
        save()
    }

    mutating func setTabGroupColor(id: String, colorHex: String?) {
        guard let idx = tabGroups.firstIndex(where: { $0.id == id }) else { return }
        let normalized = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard tabGroups[idx].colorHex != next else { return }
        tabGroups[idx].colorHex = next
        save()
    }

    private mutating func setWindowPresentationOverride(key: String, override: WindowPresentationOverride) {
        if override.isEmpty {
            if windowPresentationOverrides.removeValue(forKey: key) != nil {
                save()
            }
            return
        }
        guard windowPresentationOverrides[key] != override else { return }
        windowPresentationOverrides[key] = override
        save()
    }
}
