import Testing
@testable import LiquidBar

@Suite
struct SettingsIconSizeRangeTests {
    @Test func sliderRangeMatchesConfigValidation() {
        #expect(SettingsIconSizeRange.minimum == 16)
        #expect(SettingsIconSizeRange.maximum == 48)
        #expect(SettingsIconSizeRange.tickCount == 9)
    }

    @Test func largerIconSizesDoNotMutateStoredTaskbarHeight() {
        var config = Config(taskbarHeight: 32, iconSize: 20)

        config.iconSize = 40

        #expect(config.taskbarHeight == 32)
        #expect(config.iconSize == 40)
        #expect(config.effectiveTaskbarHeight == 40)
    }

    @Test func loweringIconSizeReturnsEffectiveHeightToUserSetting() {
        var config = Config(taskbarHeight: 32, iconSize: 44)
        #expect(config.effectiveTaskbarHeight == 44)

        config.iconSize = 24

        #expect(config.taskbarHeight == 32)
        #expect(config.effectiveTaskbarHeight == 32)
    }
}
