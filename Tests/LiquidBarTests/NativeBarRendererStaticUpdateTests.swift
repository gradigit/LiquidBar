import Testing
import CoreGraphics
import AppKit
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

    @Test func cursorPositionUpdatesDebugStateWithoutSnapshotChurn() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .customText(id: "metric", text: "CPU 42%", screenId: 1),
        ]
        let config = Config()

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)
        let initialBuildCount = renderer.debugStaticUpdateBuildCount(displayId: 1)
        let initialFrameIndex = renderer.debugFrameIndex(displayId: 1)
        let initialDecorationCount = renderer.debugDecorationCount(displayId: 1)

        #expect(renderer.setCursorPosition(SIMD2<Float>(10, 12), for: 1) == true)
        #expect(renderer.debugCursorPoint(displayId: 1) == NSPoint(x: 10, y: 12))
        #expect(renderer.debugStaticUpdateBuildCount(displayId: 1) == initialBuildCount)
        #expect(renderer.debugFrameIndex(displayId: 1) == initialFrameIndex)
        #expect(renderer.debugDecorationCount(displayId: 1) == initialDecorationCount)

        #expect(renderer.setCursorPosition(SIMD2<Float>(10, 12), for: 1) == false)
        #expect(renderer.setCursorPosition(nil, for: 1) == true)
        #expect(renderer.setCursorPosition(nil, for: 1) == false)
        renderer.shutdown()
    }

    @Test func duplicateHoverStateSkipsSnapshotRebuild() throws {
        let renderer = try makeRenderer()
        let iconCache = IconCache()
        let items: [TaskbarItem] = [
            .customText(id: "metric", text: "CPU 42%", screenId: 1),
        ]
        let config = Config()

        renderer.updateItems(items, config: config, iconCache: iconCache, displayId: 1)

        #expect(renderer.setHoveredItemIndex(0, for: 1) == true)
        #expect(renderer.setHoveredItemIndex(0, for: 1) == false)
        #expect(renderer.setHoveredItemIndex(nil, for: 1) == true)
        #expect(renderer.setHoveredItemIndex(nil, for: 1) == false)

        #expect(renderer.setHoverRect(NSRect(x: 10, y: 4, width: 30, height: 20), for: 1) == true)
        let decorationCountAfterHover = renderer.debugDecorationCount(displayId: 1)
        #expect(decorationCountAfterHover > 0)
        #expect(renderer.setHoverRect(NSRect(x: 10, y: 4, width: 30, height: 20), for: 1) == false)
        #expect(renderer.debugDecorationCount(displayId: 1) == decorationCountAfterHover)
        #expect(renderer.setHoverRect(nil, for: 1) == true)
        #expect(renderer.setHoverRect(nil, for: 1) == false)
        renderer.shutdown()
    }
}
