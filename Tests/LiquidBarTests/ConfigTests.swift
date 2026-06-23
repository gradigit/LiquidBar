import Testing
import Foundation
@testable import LiquidBar

@Suite
struct ConfigTests {
    @Test func testDefaults() {
        let config = Config()
        #expect(config.taskbarHeight == 32)
        #expect(config.iconSize == 32)
        #expect(config.fontSize == 11)
        #expect(config.maxItemWidth == 150)
        #expect(config.maxTitleWidth == 120)
        #expect(config.iconsOnly == true)
        #expect(config.taskbarPosition == .bottom)
        #expect(config.theme == .system)
        #expect(config.appLanguage == .system)
        #expect(config.itemSizing == .uniform)
        #expect(config.tabbedTaskbarEnabled == false)
        #expect(config.groupByApp == false)
        #expect(config.sidebarModeEnabled == false)
        #expect(config.sidebarStateDefault == .expanded)
        #expect(config.sidebarExpandTrigger == .click)
        #expect(config.tileZoneEnabled == false)
        #expect(config.tilePopupSingleton == true)
        #expect(config.hoverDelayMs == 0)
        #expect(config.hoverIntentGuardEnabled == true)
        #expect(config.animationProfile == .balancedSpring)
        #expect(config.showHiddenApps == true)
        #expect(config.showMinimizedWindows == true)
        #expect(config.adjustWindowsForTaskbar == false)
        #expect(config.previewsEnabled == true)
        #expect(config.previewHoverDelayMs == 0)
        #expect(config.performanceLoggingEnabled == false)
        #expect(config.performanceHangDiagnosticsEnabled == false)
        #expect(config.performanceGpuTimingEnabled == false)
        #expect(config.performanceLogIntervalMs == 1000)
        #expect(config.multiMonitorMode == .allDisplays)
        #expect(config.windowDisplayMode == .perDisplay)
        #expect(config.blacklistedApps.isEmpty)
        #expect(config.pinnedApps.isEmpty)
        #expect(config.pinnedAppsScope == .global)
        #expect(config.customItems.isEmpty)
        #expect(config.systemIndicatorsEnabled == true)
        #expect(config.systemIndicatorRefreshIntervalMs == 1000)
        #expect(config.systemIndicatorPlacement == .rightCorner)
        #expect(config.systemIndicatorDisplayScope == .allDisplays)
        #expect(config.systemIndicatorSelectedDisplayId == nil)
        #expect(config.systemIndicatorCpuEnabled == true)
        #expect(config.systemIndicatorGpuEnabled == true)
        #expect(config.systemIndicatorRamEnabled == true)
        #expect(config.systemIndicatorThermalEnabled == false)
        #expect(config.systemIndicatorCpuVisualMode == .percentage)
        #expect(config.systemIndicatorGpuVisualMode == .percentage)
        #expect(config.systemIndicatorRamVisualMode == .percentage)
        #expect(config.systemIndicatorThermalVisualMode == .percentage)
        #expect(config.systemIndicatorCpuColorHex == nil)
        #expect(config.systemIndicatorGpuColorHex == nil)
        #expect(config.systemIndicatorRamColorHex == nil)
        #expect(config.systemIndicatorThermalColorHex == nil)
        #expect(config.systemIndicatorTemperatureUnit == .celsius)
        #expect(config.systemIndicatorChipPreset == .compact)
        #expect(config.systemIndicatorAppearance == .glass)
        #expect(config.systemIndicatorGraphSamples == 16)
        #expect(config.hoverIntensity == .subtle)
        #expect(config.visualDepth == .balanced)
        #expect(config.appGroupCountBadgeInIconsOnly == true)
        #expect(config.appGroupCountBadgeStyle == .minimal)
        #expect(config.secondClickAction == .hide)
        #expect(config.scrollWheelMode == .cycleWindows)
        #expect(config.pluginsEnabled == false)
        #expect(config.disabledPluginIds.isEmpty)
        #expect(config.switcherEnabled == true)
        #expect(config.switcherHotkey == "command+tab")
        #expect(config.switcherLayoutStyle == .heroCarousel)
        #expect(config.switcherWindowScope == .allDisplays)
        #expect(config.providerRuntimeEnabled == true)
        #expect(config.providerTimeoutMs == 900)
        #expect(config.providerCircuitBreakerThreshold == 3)
        #expect(config.showMenuBarIcon == true)
    }

    @Test func testValidation() {
        var tooLow = Config(taskbarHeight: 20, iconSize: 5, fontSize: 5)
        tooLow.validate()
        #expect(tooLow.taskbarHeight == 32)
        #expect(tooLow.iconSize == 16)
        #expect(tooLow.fontSize == 10)

        var tooHigh = Config(taskbarHeight: 100, iconSize: 100, fontSize: 100)
        tooHigh.validate()
        #expect(tooHigh.taskbarHeight == 64)
        #expect(tooHigh.iconSize == 48)
        #expect(tooHigh.fontSize == 16)
    }

    @Test func effectiveTaskbarHeightKeepsUserMinimumUntilIconsOutgrowIt() {
        #expect(Config(taskbarHeight: 32, iconSize: 20).effectiveTaskbarHeight == 32)
        #expect(Config(taskbarHeight: 32, iconSize: 32).effectiveTaskbarHeight == 32)
        #expect(Config(taskbarHeight: 32, iconSize: 36).effectiveTaskbarHeight == 36)
        #expect(Config(taskbarHeight: 48, iconSize: 20).effectiveTaskbarHeight == 48)
    }

    @Test func testJSONRoundtrip() throws {
        let original = Config(
            taskbarHeight: 40,
            iconSize: 32,
            fontSize: 14,
            iconsOnly: true,
            taskbarPosition: .bottom,
            theme: .dark,
            appLanguage: .korean,
            itemSizing: .auto,
            groupByApp: true,
            showHiddenApps: false,
            multiMonitorMode: .mainOnly,
            windowDisplayMode: .allWindows,
            blacklistedApps: ["com.test.blocked"],
            pinnedApps: ["com.test.pinned"],
            pinnedAppsScope: .global,
            systemIndicatorCpuColorHex: "#AF52DE",
            systemIndicatorGpuColorHex: "#FF9F0A",
            systemIndicatorRamColorHex: "#34C759",
            systemIndicatorThermalColorHex: "#FFD166",
            hoverIntensity: .medium,
            visualDepth: .rich
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Config.self, from: data)

        #expect(decoded == original)
    }

    @Test func testSnakeCaseKeys() throws {
        let config = Config(
            systemIndicatorCpuColorHex: "#AF52DE",
            systemIndicatorGpuColorHex: "#FF9F0A",
            systemIndicatorRamColorHex: "#34C759",
            systemIndicatorThermalColorHex: "#FFD166"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("taskbar_height"))
        #expect(!json.contains("taskbarHeight"))
        #expect(json.contains("icon_size"))
        #expect(json.contains("max_item_width"))
        #expect(json.contains("max_title_width"))
        #expect(json.contains("icons_only"))
        #expect(json.contains("taskbar_position"))
        #expect(json.contains("app_language"))
        #expect(json.contains("group_by_app"))
        #expect(json.contains("sidebar_mode_enabled"))
        #expect(json.contains("sidebar_state_default"))
        #expect(json.contains("sidebar_expand_trigger"))
        #expect(json.contains("tile_zone_enabled"))
        #expect(json.contains("tile_popup_singleton"))
        #expect(json.contains("hover_delay_ms"))
        #expect(json.contains("hover_intent_guard_enabled"))
        #expect(json.contains("animation_profile"))
        #expect(json.contains("show_hidden_apps"))
        #expect(json.contains("show_menu_bar_icon"))
        #expect(json.contains("tabbed_taskbar_enabled"))
        #expect(json.contains("multi_monitor_mode"))
        #expect(json.contains("window_display_mode"))
        #expect(json.contains("blacklisted_apps"))
        #expect(json.contains("pinned_apps"))
        #expect(json.contains("pinned_apps_scope"))
        #expect(json.contains("custom_items"))
        #expect(json.contains("system_indicators_enabled"))
        #expect(json.contains("system_indicator_refresh_interval_ms"))
        #expect(json.contains("system_indicator_placement"))
        #expect(json.contains("system_indicator_display_scope"))
        #expect(json.contains("system_indicator_cpu_enabled"))
        #expect(json.contains("system_indicator_gpu_enabled"))
        #expect(json.contains("system_indicator_ram_enabled"))
        #expect(json.contains("system_indicator_thermal_enabled"))
        #expect(json.contains("system_indicator_cpu_visual_mode"))
        #expect(json.contains("system_indicator_gpu_visual_mode"))
        #expect(json.contains("system_indicator_ram_visual_mode"))
        #expect(json.contains("system_indicator_thermal_visual_mode"))
        #expect(json.contains("system_indicator_cpu_color_hex"))
        #expect(json.contains("system_indicator_gpu_color_hex"))
        #expect(json.contains("system_indicator_ram_color_hex"))
        #expect(json.contains("system_indicator_thermal_color_hex"))
        #expect(json.contains("system_indicator_temperature_unit"))
        #expect(json.contains("system_indicator_chip_preset"))
        #expect(json.contains("system_indicator_graph_samples"))
        #expect(json.contains("hover_intensity"))
        #expect(json.contains("visual_depth"))
        #expect(json.contains("app_group_count_badge_in_icons_only"))
        #expect(json.contains("app_group_count_badge_style"))
        #expect(json.contains("second_click_action"))
        #expect(json.contains("scroll_wheel_mode"))
        #expect(json.contains("performance_logging_enabled"))
        #expect(json.contains("performance_hang_diagnostics_enabled"))
        #expect(json.contains("performance_gpu_timing_enabled"))
        #expect(json.contains("performance_log_interval_ms"))
        #expect(json.contains("plugins_enabled"))
        #expect(json.contains("disabled_plugin_ids"))
        #expect(json.contains("switcher_enabled"))
        #expect(json.contains("switcher_hotkey"))
        #expect(json.contains("switcher_layout_style"))
        #expect(json.contains("switcher_window_scope"))
        #expect(json.contains("provider_runtime_enabled"))
        #expect(json.contains("provider_timeout_ms"))
        #expect(json.contains("provider_circuit_breaker_threshold"))
    }

    @Test func testBackwardCompatDecodeWithoutHoverIntensity() throws {
        // Simulate a config.json saved before hoverIntensity was added
        let json = """
        {
            "taskbar_height": 30, "icon_size": 20, "font_size": 11,
            "icons_only": false, "taskbar_position": "bottom", "theme": "system",
            "item_sizing": "uniform", "group_by_app": false, "show_hidden_apps": true,
            "multi_monitor_mode": "all_displays", "window_display_mode": "per_display",
            "blacklisted_apps": [], "pinned_apps": [], "center_items": false,
            "hide_dock": false, "hidden_window_mode": "in_place", "bar_style": "flush"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(Config.self, from: json.data(using: .utf8)!)
        #expect(config.hoverIntensity == .subtle)
        #expect(config.visualDepth == .balanced)
        #expect(config.pinnedAppsScope == .global)
        #expect(config.customItems.isEmpty)
        #expect(config.systemIndicatorsEnabled == true)
        #expect(config.systemIndicatorRefreshIntervalMs == 1000)
        #expect(config.systemIndicatorPlacement == .rightCorner)
        #expect(config.systemIndicatorDisplayScope == .allDisplays)
        #expect(config.systemIndicatorSelectedDisplayId == nil)
        #expect(config.systemIndicatorCpuEnabled == true)
        #expect(config.systemIndicatorGpuEnabled == true)
        #expect(config.systemIndicatorRamEnabled == true)
        #expect(config.systemIndicatorThermalEnabled == false)
        #expect(config.systemIndicatorCpuColorHex == nil)
        #expect(config.systemIndicatorGpuColorHex == nil)
        #expect(config.systemIndicatorRamColorHex == nil)
        #expect(config.systemIndicatorThermalColorHex == nil)
        #expect(config.systemIndicatorTemperatureUnit == .celsius)
        #expect(config.systemIndicatorChipPreset == .compact)
        #expect(config.systemIndicatorAppearance == .glass)
        #expect(config.systemIndicatorGraphSamples == 16)
        #expect(config.tabbedTaskbarEnabled == false)
        #expect(config.secondClickAction == .hide)
        #expect(config.appGroupCountBadgeInIconsOnly == true)
        #expect(config.appGroupCountBadgeStyle == .minimal)
        #expect(config.scrollWheelMode == .cycleWindows)
        #expect(config.performanceLoggingEnabled == false)
        #expect(config.performanceHangDiagnosticsEnabled == false)
        #expect(config.performanceGpuTimingEnabled == false)
        #expect(config.performanceLogIntervalMs == 1000)
        #expect(config.pluginsEnabled == false)
        #expect(config.disabledPluginIds.isEmpty)
        #expect(config.sidebarModeEnabled == false)
        #expect(config.tileZoneEnabled == false)
        #expect(config.switcherEnabled == false)
        #expect(config.switcherLayoutStyle == .heroCarousel)
        #expect(config.switcherWindowScope == .allDisplays)
        #expect(config.providerRuntimeEnabled == true)
        #expect(config.showMenuBarIcon == true)
        #expect(config.appLanguage == .system)
    }

    @Test func testHelpers() {
        let config = Config(
            blacklistedApps: ["com.blocked.app"],
            pinnedApps: ["com.pinned.app"]
        )
        #expect(config.isBlacklisted("com.blocked.app") == true)
        #expect(config.isBlacklisted("com.other.app") == false)
        #expect(config.isPinned("com.pinned.app") == true)
        #expect(config.isPinned("com.other.app") == false)
    }

    @Test func testValidationNormalizesLegacyAndDuplicateSettings() {
        var config = Config(
            blacklistedApps: ["com.blocked.app", "com.blocked.app", "com.other.app"],
            pinnedApps: ["com.pinned.app", "com.pinned.app"],
            systemIndicatorCpuColorHex: "af52de",
            systemIndicatorGpuColorHex: "#nothex",
            systemIndicatorRamColorHex: "#34c759",
            systemIndicatorThermalColorHex: "",
            previewsEnabled: true,
            previewMode: .liveLowFps,
            performanceGpuTimingEnabled: true
        )
        config.validate()

        #expect(config.blacklistedApps == ["com.blocked.app", "com.other.app"])
        #expect(config.pinnedApps == ["com.pinned.app"])
        #expect(config.previewMode == .staticImage)
        #expect(config.performanceGpuTimingEnabled == false)
        #expect(config.systemIndicatorCpuColorHex == "#AF52DE")
        #expect(config.systemIndicatorGpuColorHex == nil)
        #expect(config.systemIndicatorRamColorHex == "#34C759")
        #expect(config.systemIndicatorThermalColorHex == nil)
    }

    @Test func testValidationClampsSystemIndicatorRefreshInterval() {
        var low = Config(systemIndicatorRefreshIntervalMs: 10, systemIndicatorGraphSamples: 1)
        low.validate()
        #expect(low.systemIndicatorRefreshIntervalMs == 250)
        #expect(low.systemIndicatorGraphSamples == 4)

        var high = Config(systemIndicatorRefreshIntervalMs: 60000, systemIndicatorGraphSamples: 99)
        high.validate()
        #expect(high.systemIndicatorRefreshIntervalMs == 10000)
        #expect(high.systemIndicatorGraphSamples == 32)
    }

    @Test func testRequiresPanelRebuildIgnoresNonVisualRuntimeOptions() {
        let base = Config()
        var changed = base
        changed.secondClickAction = .none
        changed.scrollWheelMode = .volume
        changed.previewHoverDelayMs = 300
        changed.performanceLoggingEnabled = true
        changed.performanceHangDiagnosticsEnabled = true

        #expect(changed.requiresPanelRebuild(comparedTo: base) == false)
    }

    @Test func testRequiresPanelRebuildDetectsPanelHostChanges() {
        let base = Config()

        var changedPosition = base
        changedPosition.taskbarPosition = .left
        #expect(changedPosition.requiresPanelRebuild(comparedTo: base) == true)

        var changedStyle = base
        changedStyle.barStyle = .floating
        #expect(changedStyle.requiresPanelRebuild(comparedTo: base) == true)

        var changedMultiMonitor = base
        changedMultiMonitor.multiMonitorMode = .mainOnly
        #expect(changedMultiMonitor.requiresPanelRebuild(comparedTo: base) == true)
    }

    @Test func testRequiresPanelRebuildTracksEffectiveHeightNotRawIconSize() {
        let base = Config(taskbarHeight: 32, iconSize: 20)

        var iconStillFits = base
        iconStillFits.iconSize = 28
        #expect(iconStillFits.requiresPanelRebuild(comparedTo: base) == false)

        var iconOutgrowsBar = base
        iconOutgrowsBar.iconSize = 36
        #expect(iconOutgrowsBar.requiresPanelRebuild(comparedTo: base) == true)

        var preferredHeightHiddenByLargerIcon = Config(taskbarHeight: 40, iconSize: 48)
        preferredHeightHiddenByLargerIcon.taskbarHeight = 32
        #expect(preferredHeightHiddenByLargerIcon.requiresPanelRebuild(comparedTo: Config(taskbarHeight: 40, iconSize: 48)) == false)
    }
}
