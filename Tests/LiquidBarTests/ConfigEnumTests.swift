import Testing
import Foundation
@testable import LiquidBar

@Suite("Config Enums")
struct ConfigEnumTests {
    // MARK: - Position

    @Test func testPositionRawValues() {
        #expect(Position.top.rawValue == "top")
        #expect(Position.bottom.rawValue == "bottom")
        #expect(Position.left.rawValue == "left")
        #expect(Position.right.rawValue == "right")
    }

    @Test func testPositionAllCases() {
        #expect(Position.allCases.count == 4)
    }

    @Test func testPositionCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for position in Position.allCases {
            let data = try encoder.encode(position)
            let decoded = try decoder.decode(Position.self, from: data)
            #expect(decoded == position)
        }
    }

    // MARK: - ItemSizing

    @Test func testItemSizingRawValues() {
        #expect(ItemSizing.uniform.rawValue == "uniform")
        #expect(ItemSizing.auto.rawValue == "auto")
    }

    @Test func testItemSizingCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for sizing in ItemSizing.allCases {
            let data = try encoder.encode(sizing)
            let decoded = try decoder.decode(ItemSizing.self, from: data)
            #expect(decoded == sizing)
        }
    }

    // MARK: - Theme

    @Test func testThemeRawValues() {
        #expect(Theme.light.rawValue == "light")
        #expect(Theme.dark.rawValue == "dark")
        #expect(Theme.system.rawValue == "system")
    }

    @Test func testThemeAllCases() {
        #expect(Theme.allCases.count == 3)
    }

    // MARK: - MultiMonitorMode

    @Test func testMultiMonitorModeRawValues() {
        #expect(MultiMonitorMode.allDisplays.rawValue == "all_displays")
        #expect(MultiMonitorMode.mainOnly.rawValue == "main_only")
    }

    @Test func testMultiMonitorModeSnakeCaseCodable() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for mode in MultiMonitorMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(MultiMonitorMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - WindowDisplayMode

    @Test func testWindowDisplayModeRawValues() {
        #expect(WindowDisplayMode.perDisplay.rawValue == "per_display")
        #expect(WindowDisplayMode.allWindows.rawValue == "all_windows")
    }

    // MARK: - SidebarDefaultState

    @Test func testSidebarDefaultStateRawValues() {
        #expect(SidebarDefaultState.expanded.rawValue == "expanded")
        #expect(SidebarDefaultState.compactIcons.rawValue == "compact_icons")
        #expect(SidebarDefaultState.hiddenPeek.rawValue == "hidden_peek")
    }

    @Test func testSidebarDefaultStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for state in SidebarDefaultState.allCases {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(SidebarDefaultState.self, from: data)
            #expect(decoded == state)
        }
    }

    // MARK: - SidebarExpandTrigger

    @Test func testSidebarExpandTriggerRawValues() {
        #expect(SidebarExpandTrigger.click.rawValue == "click")
        #expect(SidebarExpandTrigger.hover.rawValue == "hover")
        #expect(SidebarExpandTrigger.hybrid.rawValue == "hybrid")
    }

    @Test func testSidebarExpandTriggerCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for mode in SidebarExpandTrigger.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(SidebarExpandTrigger.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - AnimationProfile

    @Test func testAnimationProfileRawValues() {
        #expect(AnimationProfile.balancedSpring.rawValue == "balanced_spring")
        #expect(AnimationProfile.snappyMinimal.rawValue == "snappy_minimal")
        #expect(AnimationProfile.richExpressive.rawValue == "rich_expressive")
    }

    @Test func testAnimationProfileCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for profile in AnimationProfile.allCases {
            let data = try encoder.encode(profile)
            let decoded = try decoder.decode(AnimationProfile.self, from: data)
            #expect(decoded == profile)
        }
    }

    // MARK: - HoverIntensity

    @Test func testHoverIntensityRawValues() {
        #expect(HoverIntensity.subtle.rawValue == "subtle")
        #expect(HoverIntensity.medium.rawValue == "medium")
        #expect(HoverIntensity.pronounced.rawValue == "pronounced")
    }

    @Test func testHoverIntensityAllCases() {
        #expect(HoverIntensity.allCases.count == 3)
    }

    @Test func testHoverIntensityFloatValue() {
        #expect(HoverIntensity.subtle.floatValue == 0.0)
        #expect(HoverIntensity.medium.floatValue == 0.5)
        #expect(HoverIntensity.pronounced.floatValue == 1.0)
    }

    @Test func testHoverIntensityCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for intensity in HoverIntensity.allCases {
            let data = try encoder.encode(intensity)
            let decoded = try decoder.decode(HoverIntensity.self, from: data)
            #expect(decoded == intensity)
        }
    }

    // MARK: - VisualDepth

    @Test func testVisualDepthRawValues() {
        #expect(VisualDepth.subtle.rawValue == "subtle")
        #expect(VisualDepth.balanced.rawValue == "balanced")
        #expect(VisualDepth.rich.rawValue == "rich")
    }

    @Test func testVisualDepthAllCases() {
        #expect(VisualDepth.allCases.count == 3)
    }

    @Test func testVisualDepthFloatValue() {
        #expect(VisualDepth.subtle.floatValue == 0.0)
        #expect(VisualDepth.balanced.floatValue == 0.5)
        #expect(VisualDepth.rich.floatValue == 1.0)
    }

    @Test func testVisualDepthCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for depth in VisualDepth.allCases {
            let data = try encoder.encode(depth)
            let decoded = try decoder.decode(VisualDepth.self, from: data)
            #expect(decoded == depth)
        }
    }

    // MARK: - SecondClickAction

    @Test func testSecondClickActionRawValues() {
        #expect(SecondClickAction.hide.rawValue == "hide")
        #expect(SecondClickAction.minimize.rawValue == "minimize")
        #expect(SecondClickAction.none.rawValue == "none")
    }

    @Test func testSecondClickActionCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in SecondClickAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(SecondClickAction.self, from: data)
            #expect(decoded == action)
        }
    }

    // MARK: - ScrollWheelMode

    @Test func testScrollWheelModeRawValues() {
        #expect(ScrollWheelMode.cycleWindows.rawValue == "cycle_windows")
        #expect(ScrollWheelMode.hideShow.rawValue == "hide_show")
        #expect(ScrollWheelMode.volume.rawValue == "volume")
        #expect(ScrollWheelMode.off.rawValue == "off")
    }

    @Test func testScrollWheelModeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for mode in ScrollWheelMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(ScrollWheelMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - LauncherAction

    @Test func testLauncherActionRawValues() {
        #expect(LauncherAction.spotlight.rawValue == "spotlight")
        #expect(LauncherAction.raycast.rawValue == "raycast")
        #expect(LauncherAction.alfred.rawValue == "alfred")
        #expect(LauncherAction.customUrl.rawValue == "custom_url")
    }

    @Test func testLauncherActionCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in LauncherAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(LauncherAction.self, from: data)
            #expect(decoded == action)
        }
    }

    @Test func testLauncherActionResolverTargets() {
        #expect(LauncherActionResolver.target(for: Config(launcherAction: .spotlight)) == .application(bundleId: "com.apple.Spotlight"))
        #expect(LauncherActionResolver.target(for: Config(launcherAction: .raycast)) == .url("raycast://"))
        #expect(LauncherActionResolver.target(for: Config(launcherAction: .alfred)) == .url("alfred://"))
        #expect(LauncherActionResolver.target(for: Config(launcherAction: .customUrl, launcherCustomUrl: " raycast://extensions/test ")) == .url("raycast://extensions/test"))
        #expect(LauncherActionResolver.target(for: Config(launcherAction: .customUrl, launcherCustomUrl: " ")) == .none)
    }

    // MARK: - PreviewMode

    @Test func testPreviewModeRawValues() {
        #expect(PreviewMode.staticImage.rawValue == "static")
        #expect(PreviewMode.liveLowFps.rawValue == "live_low_fps")
    }

    @Test func testPreviewModeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for mode in PreviewMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(PreviewMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    // MARK: - FocusIndicatorStyle

    @Test func testFocusIndicatorStyleRawValues() {
        #expect(FocusIndicatorStyle.tile.rawValue == "tile")
        #expect(FocusIndicatorStyle.dot.rawValue == "dot")
    }

    @Test func testFocusIndicatorStyleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for style in FocusIndicatorStyle.allCases {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(FocusIndicatorStyle.self, from: data)
            #expect(decoded == style)
        }
    }

    // MARK: - SwitcherLayoutStyle

    @Test func testSwitcherLayoutStyleRawValues() {
        #expect(SwitcherLayoutStyle.compactShelf.rawValue == "compact_shelf")
        #expect(SwitcherLayoutStyle.heroCarousel.rawValue == "hero_carousel")
    }

    @Test func testSwitcherLayoutStyleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for style in SwitcherLayoutStyle.allCases {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(SwitcherLayoutStyle.self, from: data)
            #expect(decoded == style)
        }
    }

    // MARK: - AppGroupStackStyle

    @Test func testAppGroupStackStyleRawValues() {
        #expect(AppGroupStackStyle.filled.rawValue == "filled")
        #expect(AppGroupStackStyle.outline.rawValue == "outline")
    }

    @Test func testAppGroupStackStyleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for style in AppGroupStackStyle.allCases {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(AppGroupStackStyle.self, from: data)
            #expect(decoded == style)
        }
    }

    // MARK: - AppGroupStackGeometry

    @Test func testAppGroupStackGeometryRawValues() {
        #expect(AppGroupStackGeometry.subtle.rawValue == "subtle")
        #expect(AppGroupStackGeometry.strong.rawValue == "strong")
    }

    @Test func testAppGroupStackGeometryCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for g in AppGroupStackGeometry.allCases {
            let data = try encoder.encode(g)
            let decoded = try decoder.decode(AppGroupStackGeometry.self, from: data)
            #expect(decoded == g)
        }
    }

    // MARK: - AppGroupCountBadgeStyle

    @Test func testAppGroupCountBadgeStyleRawValues() {
        #expect(AppGroupCountBadgeStyle.minimal.rawValue == "minimal")
        #expect(AppGroupCountBadgeStyle.pill.rawValue == "pill")
        #expect(AppGroupCountBadgeStyle.compactDot.rawValue == "compact_dot")
        #expect(AppGroupCountBadgeStyle.separator.rawValue == "separator")
    }

    @Test func testAppGroupCountBadgeStyleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for style in AppGroupCountBadgeStyle.allCases {
            let data = try encoder.encode(style)
            let decoded = try decoder.decode(AppGroupCountBadgeStyle.self, from: data)
            #expect(decoded == style)
        }
    }

    // MARK: - Config Validation

    @Test func testValidationClampsHeight() {
        var config = Config(taskbarHeight: 10)
        config.validate()
        #expect(config.taskbarHeight == 32)

        var config2 = Config(taskbarHeight: 100)
        config2.validate()
        #expect(config2.taskbarHeight == 64)
    }

    @Test func testValidationClampsIconSize() {
        var config = Config(iconSize: 5)
        config.validate()
        #expect(config.iconSize == 16)

        var config2 = Config(iconSize: 100)
        config2.validate()
        #expect(config2.iconSize == 48)
    }

    @Test func testValidationClampsFontSize() {
        var config = Config(fontSize: 5)
        config.validate()
        #expect(config.fontSize == 10)

        var config2 = Config(fontSize: 30)
        config2.validate()
        #expect(config2.fontSize == 16)
    }

    @Test func testValidationClampsPerformanceLogInterval() {
        var config = Config(performanceLogIntervalMs: 100)
        config.validate()
        #expect(config.performanceLogIntervalMs == 250)

        var config2 = Config(performanceLogIntervalMs: 20000)
        config2.validate()
        #expect(config2.performanceLogIntervalMs == 10000)
    }

    @Test func testValidationLeavesValidValues() {
        var config = Config(taskbarHeight: 40, iconSize: 24, fontSize: 12)
        config.validate()
        #expect(config.taskbarHeight == 40)
        #expect(config.iconSize == 24)
        #expect(config.fontSize == 12)
    }

    // MARK: - Config Helpers

    @Test func testIsBlacklisted() {
        let config = Config(blacklistedApps: ["com.bad.app", "com.worse.app"])
        #expect(config.isBlacklisted("com.bad.app") == true)
        #expect(config.isBlacklisted("com.good.app") == false)
    }

    @Test func testIsPinned() {
        let config = Config(pinnedApps: ["com.pinned.app"])
        #expect(config.isPinned("com.pinned.app") == true)
        #expect(config.isPinned("com.other.app") == false)
    }

    // MARK: - Clamped Extension

    @Test func testClampedLower() {
        #expect(5.clamped(to: 10...20) == 10)
    }

    @Test func testClampedUpper() {
        #expect(25.clamped(to: 10...20) == 20)
    }

    @Test func testClampedInRange() {
        #expect(15.clamped(to: 10...20) == 15)
    }

    @Test func testClampedBoundary() {
        #expect(10.clamped(to: 10...20) == 10)
        #expect(20.clamped(to: 10...20) == 20)
    }

    @Test func testClampedFloat() {
        #expect(Float(1.5).clamped(to: 2.0...5.0) == 2.0)
    }
}
