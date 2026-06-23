import Foundation

// MARK: - Enums

enum Position: String, Codable, Sendable, CaseIterable {
    case top
    case bottom
    case left
    case right

    var isHorizontal: Bool {
        switch self {
        case .top, .bottom:
            return true
        case .left, .right:
            return false
        }
    }

    var isVertical: Bool { !isHorizontal }

    var isTop: Bool { self == .top }
    var isBottom: Bool { self == .bottom }
    var isLeft: Bool { self == .left }
    var isRight: Bool { self == .right }
}

enum ItemSizing: String, Codable, Sendable, CaseIterable {
    case uniform
    case auto
}

enum Theme: String, Codable, Sendable, CaseIterable {
    case light
    case dark
    case system
}

enum MultiMonitorMode: String, Codable, Sendable, CaseIterable {
    case allDisplays = "all_displays"
    case mainOnly = "main_only"
}

enum WindowDisplayMode: String, Codable, Sendable, CaseIterable {
    case perDisplay = "per_display"
    case allWindows = "all_windows"
}

enum SidebarDefaultState: String, Codable, Sendable, CaseIterable {
    case expanded
    case compactIcons = "compact_icons"
    case hiddenPeek = "hidden_peek"
}

enum SidebarExpandTrigger: String, Codable, Sendable, CaseIterable {
    case click
    case hover
    case hybrid
}

enum AnimationProfile: String, Codable, Sendable, CaseIterable {
    case balancedSpring = "balanced_spring"
    case snappyMinimal = "snappy_minimal"
    case richExpressive = "rich_expressive"
}

enum HiddenWindowMode: String, Codable, Sendable, CaseIterable {
    case inPlace = "in_place"
    case collapsedRight = "collapsed_right"
}

enum PinnedAppsScope: String, Codable, Sendable, CaseIterable {
    /// One pinned apps list shared across all Spaces (App Store safe).
    case global
    /// Separate pinned apps list per Space (requires private Spaces APIs).
    case perSpace = "per_space"
}

enum BarStyle: String, Codable, Sendable, CaseIterable {
    case flush      // Full-width, no margin, no corner radius
    case floating   // 5pt margin, 14pt corner radius
}

enum HoverIntensity: String, Codable, Sendable, CaseIterable {
    case subtle
    case medium
    case pronounced

    var floatValue: Float {
        switch self {
        case .subtle: return 0.0
        case .medium: return 0.5
        case .pronounced: return 1.0
        }
    }
}

enum VisualDepth: String, Codable, Sendable, CaseIterable {
    case subtle
    case balanced
    case rich

    var floatValue: Float {
        switch self {
        case .subtle: return 0.0
        case .balanced: return 0.5
        case .rich: return 1.0
        }
    }
}

enum SecondClickAction: String, Codable, Sendable, CaseIterable {
    /// Hide the focused app (Cmd+H behavior, Windows-style "minimize" equivalent for macOS).
    case hide
    /// Minimize the focused window (requires Accessibility trust).
    case minimize
    /// Do nothing on second click; keep normal activation behavior.
    case none
}

enum ScrollWheelMode: String, Codable, Sendable, CaseIterable {
    /// Scroll over the bar to cycle focus across windows (default).
    case cycleWindows = "cycle_windows"
    /// Scroll over the bar to hide/show LiquidBar.
    case hideShow = "hide_show"
    /// Scroll over the bar to adjust system output volume.
    case volume
    /// Disable scroll wheel interactions.
    case off
}

enum LauncherAction: String, Codable, Sendable, CaseIterable {
    case spotlight
    case raycast
    case alfred
    case customUrl = "custom_url"
}

enum PreviewMode: String, Codable, Sendable, CaseIterable {
    case staticImage = "static"
    case liveLowFps = "live_low_fps"
}

enum SystemIndicatorVisualMode: String, Codable, Sendable, CaseIterable {
    /// Numeric label such as "CPU 42%".
    case percentage
    /// Numeric label plus a subtle inline progress track.
    case bar
    /// Numeric label plus a bounded recent-history graph.
    case graph
}

enum SystemIndicatorChipPreset: String, Codable, Sendable, CaseIterable {
    /// Legacy label-forward chip kept for config compatibility.
    case full
    /// Default labeled chip with enough width for names and values.
    case compact
    /// Numeric-only footprint for dense taskbars.
    case dense
    /// Smallest footprint; renders a tiny chart instead of text.
    case micro
}

enum SystemIndicatorAppearance: String, Codable, Sendable, CaseIterable {
    /// Current layered glass capsule treatment.
    case glass
    /// Low-depth capsule without layered glass highlights.
    case flat
    /// Text-forward treatment with only a small baseline indicator.
    case underline
    /// Bare text/letter with a tiny metric accent.
    case minimal
}

enum SystemIndicatorPlacement: String, Codable, Sendable, CaseIterable {
    /// Normal taskbar flow; drag reorder can place indicators among other items.
    case free
    /// Flow before custom/window items.
    case leading
    /// Flow after pinned/window items.
    case trailing
    /// Affixed to the physical left edge of the bar.
    case leftCorner = "left_corner"
    /// Affixed to the physical right edge of the bar.
    case rightCorner = "right_corner"
}

enum SystemIndicatorTemperatureUnit: String, Codable, Sendable, CaseIterable {
    case celsius
    case fahrenheit
}

enum SystemIndicatorDisplayScope: String, Codable, Sendable, CaseIterable {
    case allDisplays = "all_displays"
    case selectedDisplay = "selected_display"
}

enum FocusIndicatorStyle: String, Codable, Sendable, CaseIterable {
    /// Focused item is indicated by a full-tile liquid glass highlight.
    case tile
    /// Focused item is indicated by a small capsule/dot.
    case dot
}

enum SwitcherLayoutStyle: String, Codable, Sendable, CaseIterable {
    case compactShelf = "compact_shelf"
    case heroCarousel = "hero_carousel"
}

enum SwitcherWindowScope: String, Codable, Sendable, CaseIterable {
    case allDisplays = "all_displays"
    case focusedDisplay = "focused_display"
}

enum AppGroupStackStyle: String, Codable, Sendable, CaseIterable {
    /// Glass-filled panes (more "liquid", can read as focused if overused).
    case filled
    /// Mostly-outline panes (structural indicator, not selection).
    case outline
}

enum AppGroupStackGeometry: String, Codable, Sendable, CaseIterable {
    case subtle
    case strong
}

enum AppGroupCountBadgeStyle: String, Codable, Sendable, CaseIterable {
    /// Current balanced default.
    case minimal
    /// Larger rounded capsule with stronger glass layering.
    case pill
    /// Legacy style kept for backward-compatible decoding only.
    /// No longer exposed in preferences; normalized to `.minimal` in `validate()`.
    case compactDot = "compact_dot"
    /// Minimal count with a subtle separator toward the title.
    case separator
}

// MARK: - Config

struct Config: Codable, Sendable, Equatable {
    var taskbarHeight: Int
    var iconSize: Int
    var fontSize: Int
    /// Maximum width of a single window/app item in the bar (prevents "fill the whole bar" behavior).
    var maxItemWidth: Int
    /// Maximum width of the rendered title text (in points) used by auto sizing.
    var maxTitleWidth: Int
    var iconsOnly: Bool
    var taskbarPosition: Position
    var theme: Theme
    var itemSizing: ItemSizing
    /// Windows-style "tabbed taskbar": focused item expands; others collapse to icons.
    var tabbedTaskbarEnabled: Bool
    var groupByApp: Bool
    /// Enables explicit sidebar behavior/state in addition to legacy top/bottom taskbar mode.
    var sidebarModeEnabled: Bool
    var sidebarStateDefault: SidebarDefaultState
    var sidebarExpandTrigger: SidebarExpandTrigger
    var tileZoneEnabled: Bool
    /// One popup control-card at a time.
    var tilePopupSingleton: Bool
    /// Generic hover opening delay used by sidebar cards/intents.
    var hoverDelayMs: Int
    var hoverIntentGuardEnabled: Bool
    var animationProfile: AnimationProfile
    var showHiddenApps: Bool
    /// Whether minimized windows should remain visible in the bar (dimmed).
    /// This is separate from `showHiddenApps` so users can hide hidden apps while still
    /// keeping minimized windows on the taskbar (Windows-style).
    var showMinimizedWindows: Bool
    /// When enabled, LiquidBar will try to move/resize windows via the AX API so they
    /// don't overlap the taskbar.
    var adjustWindowsForTaskbar: Bool
    var multiMonitorMode: MultiMonitorMode
    var windowDisplayMode: WindowDisplayMode
    var blacklistedApps: [String]
    var pinnedApps: [String]
    var pinnedAppsScope: PinnedAppsScope
    /// Custom user-defined items (spacers, text, links, folders).
    var customItems: [CustomItem]
    /// Built-in CPU/GPU/RAM labels shown before window items.
    var systemIndicatorsEnabled: Bool
    /// Minimum interval for refreshing system indicator labels.
    var systemIndicatorRefreshIntervalMs: Int
    /// Where built-in system indicators are placed relative to app/window items.
    var systemIndicatorPlacement: SystemIndicatorPlacement
    /// Whether built-in system indicators appear on every LiquidBar display or one selected display.
    var systemIndicatorDisplayScope: SystemIndicatorDisplayScope
    /// Selected display for system indicators when `systemIndicatorDisplayScope == .selectedDisplay`.
    var systemIndicatorSelectedDisplayId: UInt32?
    var systemIndicatorCpuEnabled: Bool
    var systemIndicatorGpuEnabled: Bool
    var systemIndicatorRamEnabled: Bool
    var systemIndicatorThermalEnabled: Bool
    var systemIndicatorCpuVisualMode: SystemIndicatorVisualMode
    var systemIndicatorGpuVisualMode: SystemIndicatorVisualMode
    var systemIndicatorRamVisualMode: SystemIndicatorVisualMode
    var systemIndicatorThermalVisualMode: SystemIndicatorVisualMode
    /// Optional per-metric accent colors. `nil` keeps the built-in metric palette.
    var systemIndicatorCpuColorHex: String?
    var systemIndicatorGpuColorHex: String?
    var systemIndicatorRamColorHex: String?
    var systemIndicatorThermalColorHex: String?
    var systemIndicatorTemperatureUnit: SystemIndicatorTemperatureUnit
    var systemIndicatorChipPreset: SystemIndicatorChipPreset
    var systemIndicatorAppearance: SystemIndicatorAppearance
    /// Number of bounded samples retained for graph mode.
    var systemIndicatorGraphSamples: Int
    var centerItems: Bool
    var hideDock: Bool
    var showMenuBarIcon: Bool
    var hiddenWindowMode: HiddenWindowMode
    /// How minimized windows should be presented in the bar.
    /// Default is in-place + dimmed, but can be collapsed separately from hidden apps.
    var minimizedWindowMode: HiddenWindowMode
    var barStyle: BarStyle
    /// Glass rendering style for the bar and overlays.
    var glassStyle: GlassStyle
    var hoverIntensity: HoverIntensity
    /// Retained decoration depth for hover, focus, badges, plugin states, and stacks.
    var visualDepth: VisualDepth
    /// Focus indicator style for the currently focused window/item.
    var focusIndicatorStyle: FocusIndicatorStyle
    /// Visual style for app-group window stacks (icons-only + group-by-app).
    var appGroupStackStyle: AppGroupStackStyle
    /// Geometry preset for the app-group stack fan/offsets.
    var appGroupStackGeometry: AppGroupStackGeometry
    /// When enabled, app-group stacks can spread outward on hover (spring animation).
    var appGroupStackHoverSpreadEnabled: Bool
    /// Show a numeric window-count badge for app groups.
    /// Legacy key name kept for config compatibility; this now controls visibility in all modes.
    var appGroupCountBadgeInIconsOnly: Bool
    /// Visual style preset for app-group count badges.
    var appGroupCountBadgeStyle: AppGroupCountBadgeStyle
    var secondClickAction: SecondClickAction
    var scrollWheelMode: ScrollWheelMode
    var launcherEnabled: Bool
    var launcherAction: LauncherAction
    /// Used when `launcherAction == .customUrl`.
    var launcherCustomUrl: String?
    var previewsEnabled: Bool
    var previewMode: PreviewMode
    var previewHoverDelayMs: Int
    /// Enable interval-based FPS/frame/poll performance logs (`Log.perf`).
    var performanceLoggingEnabled: Bool
    /// Enable extra local diagnostics for investigating hangs and lag.
    var performanceHangDiagnosticsEnabled: Bool
    /// Legacy compatibility flag for detailed renderer timing. The native retained
    /// renderer does not emit GPU commit feedback.
    var performanceGpuTimingEnabled: Bool
    /// Aggregation interval for perf log lines.
    var performanceLogIntervalMs: Int
    /// Enable user-defined window tab groups (group arbitrary windows into chips + tabs).
    var windowTabGroupsEnabled: Bool
    /// While dragging a window, hovering over a tab group chip for this duration expands the group.
    var tabGroupHoverExpandDelayMs: Int
    /// When a tab group is expanded, clicking a window item outside the group collapses it.
    var tabGroupCollapseOnOutsideClick: Bool
    /// Enable the plugin system (plugins are discovered from `configDirectory/Plugins`).
    var pluginsEnabled: Bool
    /// Explicitly disabled plugin IDs (even if present on disk).
    var disabledPluginIds: [String]
    var switcherEnabled: Bool
    /// Serialized shortcut (example: "command+tab").
    var switcherHotkey: String
    var switcherLayoutStyle: SwitcherLayoutStyle
    var switcherWindowScope: SwitcherWindowScope
    var providerRuntimeEnabled: Bool
    var providerTimeoutMs: Int
    var providerCircuitBreakerThreshold: Int

    init(
        taskbarHeight: Int = 32,
        iconSize: Int = 32,
        fontSize: Int = 11,
        maxItemWidth: Int = 150,
        maxTitleWidth: Int = 120,
        iconsOnly: Bool = true,
        taskbarPosition: Position = .bottom,
        theme: Theme = .system,
        itemSizing: ItemSizing = .uniform,
        tabbedTaskbarEnabled: Bool = false,
        groupByApp: Bool = false,
        sidebarModeEnabled: Bool = false,
        sidebarStateDefault: SidebarDefaultState = .expanded,
        sidebarExpandTrigger: SidebarExpandTrigger = .click,
        tileZoneEnabled: Bool = false,
        tilePopupSingleton: Bool = true,
        hoverDelayMs: Int = 0,
        hoverIntentGuardEnabled: Bool = true,
        animationProfile: AnimationProfile = .balancedSpring,
        showHiddenApps: Bool = true,
        showMinimizedWindows: Bool = true,
        adjustWindowsForTaskbar: Bool = false,
        multiMonitorMode: MultiMonitorMode = .allDisplays,
        windowDisplayMode: WindowDisplayMode = .perDisplay,
        blacklistedApps: [String] = [],
        pinnedApps: [String] = [],
        pinnedAppsScope: PinnedAppsScope = .global,
        customItems: [CustomItem] = [],
        systemIndicatorsEnabled: Bool = true,
        systemIndicatorRefreshIntervalMs: Int = 1000,
        systemIndicatorPlacement: SystemIndicatorPlacement = .leading,
        systemIndicatorDisplayScope: SystemIndicatorDisplayScope = .allDisplays,
        systemIndicatorSelectedDisplayId: UInt32? = nil,
        systemIndicatorCpuEnabled: Bool = true,
        systemIndicatorGpuEnabled: Bool = true,
        systemIndicatorRamEnabled: Bool = true,
        systemIndicatorThermalEnabled: Bool = false,
        systemIndicatorCpuVisualMode: SystemIndicatorVisualMode = .percentage,
        systemIndicatorGpuVisualMode: SystemIndicatorVisualMode = .percentage,
        systemIndicatorRamVisualMode: SystemIndicatorVisualMode = .percentage,
        systemIndicatorThermalVisualMode: SystemIndicatorVisualMode = .percentage,
        systemIndicatorCpuColorHex: String? = nil,
        systemIndicatorGpuColorHex: String? = nil,
        systemIndicatorRamColorHex: String? = nil,
        systemIndicatorThermalColorHex: String? = nil,
        systemIndicatorTemperatureUnit: SystemIndicatorTemperatureUnit = .celsius,
        systemIndicatorChipPreset: SystemIndicatorChipPreset = .compact,
        systemIndicatorAppearance: SystemIndicatorAppearance = .glass,
        systemIndicatorGraphSamples: Int = 16,
        centerItems: Bool = false,
        hideDock: Bool = false,
        showMenuBarIcon: Bool = true,
        hiddenWindowMode: HiddenWindowMode = .inPlace,
        minimizedWindowMode: HiddenWindowMode = .inPlace,
        barStyle: BarStyle = .flush,
        glassStyle: GlassStyle = .publicRegular,
        hoverIntensity: HoverIntensity = .subtle,
        visualDepth: VisualDepth = .balanced,
        focusIndicatorStyle: FocusIndicatorStyle = .tile,
        appGroupStackStyle: AppGroupStackStyle = .filled,
        appGroupStackGeometry: AppGroupStackGeometry = .subtle,
        appGroupStackHoverSpreadEnabled: Bool = false,
        appGroupCountBadgeInIconsOnly: Bool = true,
        appGroupCountBadgeStyle: AppGroupCountBadgeStyle = .minimal,
        secondClickAction: SecondClickAction = .hide,
        scrollWheelMode: ScrollWheelMode = .cycleWindows,
        launcherEnabled: Bool = false,
        launcherAction: LauncherAction = .spotlight,
        launcherCustomUrl: String? = nil,
        previewsEnabled: Bool = true,
        previewMode: PreviewMode = .staticImage,
        previewHoverDelayMs: Int = 0,
        performanceLoggingEnabled: Bool = false,
        performanceHangDiagnosticsEnabled: Bool = false,
        performanceGpuTimingEnabled: Bool = false,
        performanceLogIntervalMs: Int = 1000,
        windowTabGroupsEnabled: Bool = false,
        tabGroupHoverExpandDelayMs: Int = 1000,
        tabGroupCollapseOnOutsideClick: Bool = true,
        pluginsEnabled: Bool = false,
        disabledPluginIds: [String] = [],
        switcherEnabled: Bool = true,
        switcherHotkey: String = "command+tab",
        switcherLayoutStyle: SwitcherLayoutStyle = .heroCarousel,
        switcherWindowScope: SwitcherWindowScope = .allDisplays,
        providerRuntimeEnabled: Bool = true,
        providerTimeoutMs: Int = 900,
        providerCircuitBreakerThreshold: Int = 3
    ) {
        self.taskbarHeight = taskbarHeight
        self.iconSize = iconSize
        self.fontSize = fontSize
        self.maxItemWidth = maxItemWidth
        self.maxTitleWidth = maxTitleWidth
        self.iconsOnly = iconsOnly
        self.taskbarPosition = taskbarPosition
        self.theme = theme
        self.itemSizing = itemSizing
        self.tabbedTaskbarEnabled = tabbedTaskbarEnabled
        self.groupByApp = groupByApp
        self.sidebarModeEnabled = sidebarModeEnabled
        self.sidebarStateDefault = sidebarStateDefault
        self.sidebarExpandTrigger = sidebarExpandTrigger
        self.tileZoneEnabled = tileZoneEnabled
        self.tilePopupSingleton = tilePopupSingleton
        self.hoverDelayMs = hoverDelayMs
        self.hoverIntentGuardEnabled = hoverIntentGuardEnabled
        self.animationProfile = animationProfile
        self.showHiddenApps = showHiddenApps
        self.showMinimizedWindows = showMinimizedWindows
        self.adjustWindowsForTaskbar = adjustWindowsForTaskbar
        self.multiMonitorMode = multiMonitorMode
        self.windowDisplayMode = windowDisplayMode
        self.blacklistedApps = blacklistedApps
        self.pinnedApps = pinnedApps
        self.pinnedAppsScope = pinnedAppsScope
        self.customItems = customItems
        self.systemIndicatorsEnabled = systemIndicatorsEnabled
        self.systemIndicatorRefreshIntervalMs = systemIndicatorRefreshIntervalMs
        self.systemIndicatorPlacement = systemIndicatorPlacement
        self.systemIndicatorDisplayScope = systemIndicatorDisplayScope
        self.systemIndicatorSelectedDisplayId = systemIndicatorSelectedDisplayId
        self.systemIndicatorCpuEnabled = systemIndicatorCpuEnabled
        self.systemIndicatorGpuEnabled = systemIndicatorGpuEnabled
        self.systemIndicatorRamEnabled = systemIndicatorRamEnabled
        self.systemIndicatorThermalEnabled = systemIndicatorThermalEnabled
        self.systemIndicatorCpuVisualMode = systemIndicatorCpuVisualMode
        self.systemIndicatorGpuVisualMode = systemIndicatorGpuVisualMode
        self.systemIndicatorRamVisualMode = systemIndicatorRamVisualMode
        self.systemIndicatorThermalVisualMode = systemIndicatorThermalVisualMode
        self.systemIndicatorCpuColorHex = systemIndicatorCpuColorHex
        self.systemIndicatorGpuColorHex = systemIndicatorGpuColorHex
        self.systemIndicatorRamColorHex = systemIndicatorRamColorHex
        self.systemIndicatorThermalColorHex = systemIndicatorThermalColorHex
        self.systemIndicatorTemperatureUnit = systemIndicatorTemperatureUnit
        self.systemIndicatorChipPreset = systemIndicatorChipPreset
        self.systemIndicatorAppearance = systemIndicatorAppearance
        self.systemIndicatorGraphSamples = systemIndicatorGraphSamples
        self.centerItems = centerItems
        self.hideDock = hideDock
        self.showMenuBarIcon = showMenuBarIcon
        self.hiddenWindowMode = hiddenWindowMode
        self.minimizedWindowMode = minimizedWindowMode
        self.barStyle = barStyle
        self.glassStyle = glassStyle
        self.hoverIntensity = hoverIntensity
        self.visualDepth = visualDepth
        self.focusIndicatorStyle = focusIndicatorStyle
        self.appGroupStackStyle = appGroupStackStyle
        self.appGroupStackGeometry = appGroupStackGeometry
        self.appGroupStackHoverSpreadEnabled = appGroupStackHoverSpreadEnabled
        self.appGroupCountBadgeInIconsOnly = appGroupCountBadgeInIconsOnly
        self.appGroupCountBadgeStyle = appGroupCountBadgeStyle
        self.secondClickAction = secondClickAction
        self.scrollWheelMode = scrollWheelMode
        self.launcherEnabled = launcherEnabled
        self.launcherAction = launcherAction
        self.launcherCustomUrl = launcherCustomUrl
        self.previewsEnabled = previewsEnabled
        self.previewMode = previewMode
        self.previewHoverDelayMs = previewHoverDelayMs
        self.performanceLoggingEnabled = performanceLoggingEnabled
        self.performanceHangDiagnosticsEnabled = performanceHangDiagnosticsEnabled
        self.performanceGpuTimingEnabled = performanceGpuTimingEnabled
        self.performanceLogIntervalMs = performanceLogIntervalMs
        self.windowTabGroupsEnabled = windowTabGroupsEnabled
        self.tabGroupHoverExpandDelayMs = tabGroupHoverExpandDelayMs
        self.tabGroupCollapseOnOutsideClick = tabGroupCollapseOnOutsideClick
        self.pluginsEnabled = pluginsEnabled
        self.disabledPluginIds = disabledPluginIds
        self.switcherEnabled = switcherEnabled
        self.switcherHotkey = switcherHotkey
        self.switcherLayoutStyle = switcherLayoutStyle
        self.switcherWindowScope = switcherWindowScope
        self.providerRuntimeEnabled = providerRuntimeEnabled
        self.providerTimeoutMs = providerTimeoutMs
        self.providerCircuitBreakerThreshold = providerCircuitBreakerThreshold
    }

    // MARK: - Codable (backward-compatible decoding for new fields)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskbarHeight = try c.decode(Int.self, forKey: .taskbarHeight)
        iconSize = try c.decode(Int.self, forKey: .iconSize)
        fontSize = try c.decode(Int.self, forKey: .fontSize)
        maxItemWidth = try c.decodeIfPresent(Int.self, forKey: .maxItemWidth) ?? 150
        maxTitleWidth = try c.decodeIfPresent(Int.self, forKey: .maxTitleWidth) ?? 120
        iconsOnly = try c.decode(Bool.self, forKey: .iconsOnly)
        taskbarPosition = try c.decode(Position.self, forKey: .taskbarPosition)
        theme = try c.decode(Theme.self, forKey: .theme)
        itemSizing = try c.decode(ItemSizing.self, forKey: .itemSizing)
        tabbedTaskbarEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabbedTaskbarEnabled) ?? false
        groupByApp = try c.decode(Bool.self, forKey: .groupByApp)
        sidebarModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .sidebarModeEnabled) ?? false
        sidebarStateDefault = try c.decodeIfPresent(SidebarDefaultState.self, forKey: .sidebarStateDefault) ?? .expanded
        sidebarExpandTrigger = try c.decodeIfPresent(SidebarExpandTrigger.self, forKey: .sidebarExpandTrigger) ?? .click
        tileZoneEnabled = try c.decodeIfPresent(Bool.self, forKey: .tileZoneEnabled) ?? false
        tilePopupSingleton = try c.decodeIfPresent(Bool.self, forKey: .tilePopupSingleton) ?? true
        hoverDelayMs = try c.decodeIfPresent(Int.self, forKey: .hoverDelayMs) ?? 0
        hoverIntentGuardEnabled = try c.decodeIfPresent(Bool.self, forKey: .hoverIntentGuardEnabled) ?? true
        animationProfile = try c.decodeIfPresent(AnimationProfile.self, forKey: .animationProfile) ?? .balancedSpring
        showHiddenApps = try c.decode(Bool.self, forKey: .showHiddenApps)
        showMinimizedWindows = try c.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? true
        adjustWindowsForTaskbar = try c.decodeIfPresent(Bool.self, forKey: .adjustWindowsForTaskbar) ?? true
        multiMonitorMode = try c.decode(MultiMonitorMode.self, forKey: .multiMonitorMode)
        windowDisplayMode = try c.decode(WindowDisplayMode.self, forKey: .windowDisplayMode)
        blacklistedApps = try c.decode([String].self, forKey: .blacklistedApps)
        pinnedApps = try c.decode([String].self, forKey: .pinnedApps)
        pinnedAppsScope = try c.decodeIfPresent(PinnedAppsScope.self, forKey: .pinnedAppsScope) ?? .global
        customItems = try c.decodeIfPresent([CustomItem].self, forKey: .customItems) ?? []
        systemIndicatorsEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemIndicatorsEnabled) ?? true
        systemIndicatorRefreshIntervalMs = try c.decodeIfPresent(Int.self, forKey: .systemIndicatorRefreshIntervalMs) ?? 1000
        systemIndicatorPlacement = try c.decodeIfPresent(SystemIndicatorPlacement.self, forKey: .systemIndicatorPlacement) ?? .leading
        systemIndicatorDisplayScope = try c.decodeIfPresent(SystemIndicatorDisplayScope.self, forKey: .systemIndicatorDisplayScope) ?? .allDisplays
        systemIndicatorSelectedDisplayId = try c.decodeIfPresent(UInt32.self, forKey: .systemIndicatorSelectedDisplayId)
        systemIndicatorCpuEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemIndicatorCpuEnabled) ?? true
        systemIndicatorGpuEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemIndicatorGpuEnabled) ?? true
        systemIndicatorRamEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemIndicatorRamEnabled) ?? true
        systemIndicatorThermalEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemIndicatorThermalEnabled) ?? false
        systemIndicatorCpuVisualMode = try c.decodeIfPresent(SystemIndicatorVisualMode.self, forKey: .systemIndicatorCpuVisualMode) ?? .percentage
        systemIndicatorGpuVisualMode = try c.decodeIfPresent(SystemIndicatorVisualMode.self, forKey: .systemIndicatorGpuVisualMode) ?? .percentage
        systemIndicatorRamVisualMode = try c.decodeIfPresent(SystemIndicatorVisualMode.self, forKey: .systemIndicatorRamVisualMode) ?? .percentage
        systemIndicatorThermalVisualMode = try c.decodeIfPresent(SystemIndicatorVisualMode.self, forKey: .systemIndicatorThermalVisualMode) ?? .percentage
        systemIndicatorCpuColorHex = try c.decodeIfPresent(String.self, forKey: .systemIndicatorCpuColorHex)
        systemIndicatorGpuColorHex = try c.decodeIfPresent(String.self, forKey: .systemIndicatorGpuColorHex)
        systemIndicatorRamColorHex = try c.decodeIfPresent(String.self, forKey: .systemIndicatorRamColorHex)
        systemIndicatorThermalColorHex = try c.decodeIfPresent(String.self, forKey: .systemIndicatorThermalColorHex)
        systemIndicatorTemperatureUnit = try c.decodeIfPresent(SystemIndicatorTemperatureUnit.self, forKey: .systemIndicatorTemperatureUnit) ?? .celsius
        systemIndicatorChipPreset = try c.decodeIfPresent(SystemIndicatorChipPreset.self, forKey: .systemIndicatorChipPreset) ?? .compact
        systemIndicatorAppearance = try c.decodeIfPresent(SystemIndicatorAppearance.self, forKey: .systemIndicatorAppearance) ?? .glass
        systemIndicatorGraphSamples = try c.decodeIfPresent(Int.self, forKey: .systemIndicatorGraphSamples) ?? 16
        centerItems = try c.decode(Bool.self, forKey: .centerItems)
        hideDock = try c.decode(Bool.self, forKey: .hideDock)
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        hiddenWindowMode = try c.decodeIfPresent(HiddenWindowMode.self, forKey: .hiddenWindowMode) ?? .inPlace
        minimizedWindowMode = try c.decodeIfPresent(HiddenWindowMode.self, forKey: .minimizedWindowMode) ?? hiddenWindowMode
        barStyle = try c.decodeIfPresent(BarStyle.self, forKey: .barStyle) ?? .flush
        glassStyle = try c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle) ?? .publicRegular
        hoverIntensity = try c.decodeIfPresent(HoverIntensity.self, forKey: .hoverIntensity) ?? .subtle
        visualDepth = try c.decodeIfPresent(VisualDepth.self, forKey: .visualDepth) ?? .balanced
        focusIndicatorStyle = try c.decodeIfPresent(FocusIndicatorStyle.self, forKey: .focusIndicatorStyle) ?? .tile
        appGroupStackStyle = try c.decodeIfPresent(AppGroupStackStyle.self, forKey: .appGroupStackStyle) ?? .filled
        appGroupStackGeometry = try c.decodeIfPresent(AppGroupStackGeometry.self, forKey: .appGroupStackGeometry) ?? .subtle
        appGroupStackHoverSpreadEnabled = try c.decodeIfPresent(Bool.self, forKey: .appGroupStackHoverSpreadEnabled) ?? false
        appGroupCountBadgeInIconsOnly = try c.decodeIfPresent(Bool.self, forKey: .appGroupCountBadgeInIconsOnly) ?? true
        appGroupCountBadgeStyle = try c.decodeIfPresent(AppGroupCountBadgeStyle.self, forKey: .appGroupCountBadgeStyle) ?? .minimal
        secondClickAction = try c.decodeIfPresent(SecondClickAction.self, forKey: .secondClickAction) ?? .hide
        scrollWheelMode = try c.decodeIfPresent(ScrollWheelMode.self, forKey: .scrollWheelMode) ?? .cycleWindows
        launcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .launcherEnabled) ?? false
        launcherAction = try c.decodeIfPresent(LauncherAction.self, forKey: .launcherAction) ?? .spotlight
        launcherCustomUrl = try c.decodeIfPresent(String.self, forKey: .launcherCustomUrl)
        previewsEnabled = try c.decodeIfPresent(Bool.self, forKey: .previewsEnabled) ?? true
        previewMode = try c.decodeIfPresent(PreviewMode.self, forKey: .previewMode) ?? .staticImage
        previewHoverDelayMs = try c.decodeIfPresent(Int.self, forKey: .previewHoverDelayMs) ?? 0
        performanceLoggingEnabled = try c.decodeIfPresent(Bool.self, forKey: .performanceLoggingEnabled) ?? false
        performanceHangDiagnosticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .performanceHangDiagnosticsEnabled) ?? false
        performanceGpuTimingEnabled = try c.decodeIfPresent(Bool.self, forKey: .performanceGpuTimingEnabled) ?? false
        performanceLogIntervalMs = try c.decodeIfPresent(Int.self, forKey: .performanceLogIntervalMs) ?? 1000
        windowTabGroupsEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowTabGroupsEnabled) ?? false
        tabGroupHoverExpandDelayMs = try c.decodeIfPresent(Int.self, forKey: .tabGroupHoverExpandDelayMs) ?? 1000
        tabGroupCollapseOnOutsideClick = try c.decodeIfPresent(Bool.self, forKey: .tabGroupCollapseOnOutsideClick) ?? true
        pluginsEnabled = try c.decodeIfPresent(Bool.self, forKey: .pluginsEnabled) ?? false
        disabledPluginIds = try c.decodeIfPresent([String].self, forKey: .disabledPluginIds) ?? []
        switcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .switcherEnabled) ?? false
        switcherHotkey = try c.decodeIfPresent(String.self, forKey: .switcherHotkey) ?? "option+tab"
        switcherLayoutStyle = try c.decodeIfPresent(SwitcherLayoutStyle.self, forKey: .switcherLayoutStyle) ?? .heroCarousel
        switcherWindowScope = try c.decodeIfPresent(SwitcherWindowScope.self, forKey: .switcherWindowScope) ?? .allDisplays
        providerRuntimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .providerRuntimeEnabled) ?? true
        providerTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .providerTimeoutMs) ?? 900
        providerCircuitBreakerThreshold = try c.decodeIfPresent(Int.self, forKey: .providerCircuitBreakerThreshold) ?? 3
    }

    // MARK: - Paths

    static var configDirectory: URL {
        // Prefer `getenv()` so tests (and tools) can `setenv()` at runtime.
        if let raw = getenv("LIQUIDBAR_CONFIG_DIR").flatMap({ String(cString: $0) }),
           !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiquidBar", isDirectory: true)
    }

    static var configPath: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static var statePath: URL {
        configDirectory.appendingPathComponent("state.json")
    }

    // MARK: - Persistence

    static func load() -> Config {
        load(fallback: Config())
    }

    static func load(fallback: Config) -> Config {
        let path = configPath
        do {
            guard FileManager.default.fileExists(atPath: path.path) else {
                Log.config.notice("Config file missing; writing defaults to: \(path.path)")
                let config = Config()
                config.save()
                return config
            }

            let data = try Data(contentsOf: path)
            if let text = String(data: data, encoding: .utf8),
               text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Log.config.notice("Config file is empty; writing defaults to: \(path.path)")
                backupConfigFile(reason: "empty")
                let config = Config()
                config.save()
                return config
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var config = try decoder.decode(Config.self, from: data)
            config.validate()
            return config
        } catch {
            Log.config.error("Failed to load config: \(error)")
            // Don't overwrite on decode errors: users often edit `config.json` manually and
            // transient syntax errors during save would otherwise wipe their work.
            return fallback
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.configDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.configPath, options: .atomic)
        } catch {
            Log.config.error("Failed to save config: \(error)")
        }
    }

    // MARK: - Validation

    mutating func validate() {
        taskbarHeight = taskbarHeight.clamped(to: 32...64)
        iconSize = iconSize.clamped(to: 16...48)
        fontSize = fontSize.clamped(to: 10...16)
        // Keep item sizing sane. Max item width must at least fit icon + padding.
        maxItemWidth = maxItemWidth.clamped(to: 60...360)
        maxTitleWidth = maxTitleWidth.clamped(to: 20...240)
        previewHoverDelayMs = previewHoverDelayMs.clamped(to: 0...2000)
        hoverDelayMs = hoverDelayMs.clamped(to: 0...2000)
        systemIndicatorRefreshIntervalMs = systemIndicatorRefreshIntervalMs.clamped(to: 250...10000)
        systemIndicatorGraphSamples = systemIndicatorGraphSamples.clamped(to: 4...32)
        systemIndicatorCpuColorHex = PresentationColorPalette.normalizedHex(systemIndicatorCpuColorHex)
        systemIndicatorGpuColorHex = PresentationColorPalette.normalizedHex(systemIndicatorGpuColorHex)
        systemIndicatorRamColorHex = PresentationColorPalette.normalizedHex(systemIndicatorRamColorHex)
        systemIndicatorThermalColorHex = PresentationColorPalette.normalizedHex(systemIndicatorThermalColorHex)
        performanceLogIntervalMs = performanceLogIntervalMs.clamped(to: 250...10000)
        performanceGpuTimingEnabled = false
        if previewMode == .liveLowFps {
            previewMode = .staticImage
        }
        tabGroupHoverExpandDelayMs = tabGroupHoverExpandDelayMs.clamped(to: 100...5000)
        providerTimeoutMs = providerTimeoutMs.clamped(to: 150...5000)
        providerCircuitBreakerThreshold = providerCircuitBreakerThreshold.clamped(to: 1...20)
        switcherHotkey = switcherHotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        if switcherHotkey.isEmpty {
            switcherHotkey = "command+tab"
        }

        // Compact-dot badge style was removed from the UI; normalize legacy configs.
        if appGroupCountBadgeStyle == .compactDot {
            appGroupCountBadgeStyle = .minimal
        }

        // Clamp custom spacer widths.
        customItems = customItems.map { item in
            switch item {
            case .spacer(let id, let width):
                return .spacer(id: id, width: width.clamped(to: 4...240))
            default:
                return item
            }
        }

        // Keep disabled plugins deterministic.
        var seenBlacklistedApps = Set<String>()
        blacklistedApps = blacklistedApps.filter { seenBlacklistedApps.insert($0).inserted }
        var seenPinnedApps = Set<String>()
        pinnedApps = pinnedApps.filter { seenPinnedApps.insert($0).inserted }
        disabledPluginIds = Array(Set(disabledPluginIds)).sorted()
    }

    // MARK: - Helpers

    func isBlacklisted(_ bundleId: String) -> Bool {
        blacklistedApps.contains(bundleId)
    }

    func isPinned(_ bundleId: String) -> Bool {
        pinnedApps.contains(bundleId)
    }

    /// Runtime bar thickness for horizontal taskbars.
    ///
    /// `taskbarHeight` remains the user's preferred minimum. Icons can grow
    /// independently until they fill that space; only then does the runtime
    /// panel grow to keep the requested icon size visible.
    var effectiveTaskbarHeight: Int {
        max(taskbarHeight, iconSize)
    }

    /// Returns true when a config transition requires destroying/recreating panel windows
    /// instead of an in-place data/render refresh.
    ///
    /// This is intentionally conservative and only tracks window-host-affecting fields.
    /// Non-visual runtime settings (e.g. `secondClickAction`) should not trigger panel churn.
    func requiresPanelRebuild(comparedTo previous: Config) -> Bool {
        effectiveTaskbarHeight != previous.effectiveTaskbarHeight ||
        taskbarPosition != previous.taskbarPosition ||
        barStyle != previous.barStyle ||
        theme != previous.theme ||
        glassStyle != previous.glassStyle ||
        multiMonitorMode != previous.multiMonitorMode ||
        sidebarModeEnabled != previous.sidebarModeEnabled ||
        sidebarStateDefault != previous.sidebarStateDefault
    }

    private static func backupConfigFile(reason: String) {
        let fm = FileManager.default
        let src = configPath
        guard fm.fileExists(atPath: src.path) else { return }

        do {
            // Match the existing backup convention, e.g. `config.json.bak-20260214-170855`.
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = df.string(from: Date())
            let dst = configDirectory.appendingPathComponent("config.json.bak-\(stamp)")

            // If copy fails (e.g. already exists), keep going; the goal is not to block startup.
            try? fm.copyItem(at: src, to: dst)
            Log.config.notice("Backed up \(reason) config to: \(dst.path)")
        }
    }
}

// MARK: - Comparable clamping helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
