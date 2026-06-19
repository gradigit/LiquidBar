import Testing
import CoreGraphics
@testable import LiquidBar

@Suite
@MainActor
struct NativeBarRendererStaticUpdateTests {
    private func makeRenderer(displayId: CGDirectDisplayID = 1) throws -> NativeBarRenderer {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: displayId, barWidth: 900, barHeight: 32, scale: 2)
        return renderer
    }

    @Test func identicalStaticInputsReuseExistingBuffers() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .customText(id: "metric", text: "CPU 42%", screenId: 1),
        ]
        let config = Config()

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        let initialBuildCount = renderer.debugStaticUpdateBuildCount(displayId: 1)
        let initialFrameIndex = renderer.debugFrameIndex(displayId: 1)

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)

        #expect(renderer.debugStaticUpdateBuildCount(displayId: 1) == initialBuildCount)
        #expect(renderer.debugFrameIndex(displayId: 1) == initialFrameIndex)
        renderer.shutdown()
    }

    @Test func focusChangeForcesStaticRebuild() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .customText(id: "metric", text: "RAM 51%", screenId: 1),
        ]
        let config = Config(tabbedTaskbarEnabled: true)

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1, focus: FocusInfo.none)
        let initialBuildCount = renderer.debugStaticUpdateBuildCount(displayId: 1)
        let initialFrameIndex = renderer.debugFrameIndex(displayId: 1)

        renderer.updateItems(
            items,
            config: config,
            iconCache: iconCache,
            displayId: 1,
            focus: FocusInfo(windowId: 7, bundleId: "com.example.app", tabGroupId: nil)
        )

        #expect(renderer.debugStaticUpdateBuildCount(displayId: 1) == initialBuildCount + 1)
        #expect(renderer.debugFrameIndex(displayId: 1) != initialFrameIndex)
        renderer.shutdown()
    }

    @Test func iconCacheRevisionInvalidatesOneAdditionalStaticPass() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .launcher(screenId: 1),
        ]
        let config = Config()

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        let buildAfterFirstPass = renderer.debugStaticUpdateBuildCount(displayId: 1)
        #expect(iconCache.revision > 0)

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        let buildAfterIconWarmPass = renderer.debugStaticUpdateBuildCount(displayId: 1)

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)

        #expect(buildAfterIconWarmPass == buildAfterFirstPass + 1)
        #expect(renderer.debugStaticUpdateBuildCount(displayId: 1) == buildAfterIconWarmPass)
        renderer.shutdown()
    }

    @Test func nonSurfaceConfigChangesReuseStaticState() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .customText(id: "metric", text: "CPU 42%", screenId: 1),
        ]
        let config = Config()

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        let initialBuildCount = renderer.debugStaticUpdateBuildCount(displayId: 1)
        let initialFrameIndex = renderer.debugFrameIndex(displayId: 1)

        var runtimeOnlyConfig = config
        runtimeOnlyConfig.adjustWindowsForTaskbar.toggle()
        runtimeOnlyConfig.performanceLoggingEnabled.toggle()
        runtimeOnlyConfig.performanceGpuTimingEnabled.toggle()
        runtimeOnlyConfig.performanceLogIntervalMs += 250

        renderer.updateItems(items, config: runtimeOnlyConfig, iconCache: iconCache, displayId: 1)

        #expect(renderer.debugStaticUpdateBuildCount(displayId: 1) == initialBuildCount)
        #expect(renderer.debugFrameIndex(displayId: 1) == initialFrameIndex)
        renderer.shutdown()
    }
}
