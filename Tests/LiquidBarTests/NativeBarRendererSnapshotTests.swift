import AppKit
import Testing
@testable import LiquidBar

@Suite("NativeBarRenderer snapshots")
@MainActor
struct NativeBarRendererSnapshotTests {
    @Test func snapshotContainsRetainedItemsAndDecorations() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 600, barHeight: 32, scale: 2)

        let items: [TaskbarItem] = [
            .pinnedApp(bundleId: "com.apple.finder", screenId: 1),
            .pluginTile(id: "tile.attn", providerId: nil, title: "Attention", icon: "sf:bell", visualState: .attention, screenId: 1),
        ]

        renderer.updateItems(items, config: Config(iconsOnly: true), iconCache: IconCache(), displayId: 1)
        let snapshot = renderer.snapshot(displayId: 1)

        #expect(snapshot?.items.count == 2)
        #expect(snapshot?.visualRects.count == 2)
        #expect((snapshot?.decorations.count ?? 0) >= 2)
        renderer.shutdown()
    }

    @Test func nativeBarViewAppliesSnapshotWithoutGpuSurface() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "cpu", text: "CPU 42%", screenId: 1),
        ]
        renderer.updateItems(items, config: Config(), iconCache: IconCache(), displayId: 1)

        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        #expect(view.items.count == 1)
        #expect(view.visualItemRects.count == 1)
        #expect(view.itemRects.count == 1)
        renderer.shutdown()
    }

    @Test func customTextTitleRectUsesNoIconLayout() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "cpu", text: "CPU 42%", screenId: 1),
        ]
        renderer.updateItems(items, config: Config(iconSize: 20, iconsOnly: false, itemSizing: .auto), iconCache: IconCache(), displayId: 1)

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let item = try #require(snapshot.items.first)

        #expect(item.title == "CPU 42%")
        #expect(item.titleRect.width > 40)
        #expect(item.titleRect.minX < item.rect.midX)
        renderer.shutdown()
    }

    @Test func systemIndicatorTextGetsReadableMinimumWidth() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 100%", screenId: 1),
        ]
        let config = Config(itemSizing: .auto)
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .percentage, valueText: "100%", value: 100, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let item = try #require(snapshot.items.first)
        let textWidth = ("CPU 100%" as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
        ]).width

        #expect(item.titleRect.width >= textWidth + 4)
        #expect(item.rect.width < 84)
        #expect(snapshot.decorations.contains { $0.kind == .systemMetricShell })
        renderer.shutdown()
    }

    @Test func temperatureIndicatorTextGetsReadableWidth() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let title = "TEMP 34°C"
        let items: [TaskbarItem] = [
            .customText(id: "system.thermal", text: title, screenId: 1),
        ]
        let config = Config(itemSizing: .auto)
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.thermal": systemVisual(metric: .thermal, mode: .percentage, valueText: "34°C", value: 34, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let item = try #require(snapshot.items.first)
        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
        ]).width

        #expect(item.title == title)
        #expect(item.titleRect.width >= textWidth + 4)
        renderer.shutdown()
    }

    @Test func systemIndicatorVisualModesUseUniformTileWidthAndGraphDecorations() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 420, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 55%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorCpuVisualMode = .percentage
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .percentage, valueText: "55%", value: 55, history: [])
            ]
        )
        let percentageWidth = try #require(renderer.snapshot(displayId: 1)?.items.first?.rect.width)

        config.systemIndicatorCpuVisualMode = .graph
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .graph, valueText: "55%", value: 55, history: [10, 20, 35, 55])
            ]
        )
        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let graphWidth = try #require(snapshot.items.first?.rect.width)

        #expect(graphWidth == percentageWidth)
        #expect(snapshot.decorations.contains { $0.kind == .systemMetricGraph })
        renderer.shutdown()
    }

    @Test func compactSystemIndicatorsUseContentSizedUniformTiles() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 520, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 100%", screenId: 1),
            .customText(id: "system.gpu", text: "GPU --", screenId: 1),
            .customText(id: "system.ram", text: "RAM 74%", screenId: 1),
            .customText(id: "system.thermal", text: "TEMP 35°C", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorChipPreset = .compact
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "100%", value: 100, history: [80, 90, 100]),
                "system.gpu": systemVisual(metric: .gpu, mode: .percentage, valueText: "--", value: nil, history: []),
                "system.ram": systemVisual(metric: .ram, mode: .graph, valueText: "74%", value: 74, history: [44, 60, 74]),
                "system.thermal": systemVisual(metric: .thermal, mode: .percentage, valueText: "35°C", value: 35, history: []),
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let widths = snapshot.items.map { $0.rect.width }
        let widestText = ["CPU 100%", "GPU --", "RAM 74%", "TEMP 35°C"].map { title in
            (title as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
            ]).width
        }.max() ?? 0
        let expectedWidth = ceil(widestText + 16)
        #expect(widths.allSatisfy { abs($0 - expectedWidth) < 0.5 })
        #expect(expectedWidth < 92)

        let shells = snapshot.decorations
            .filter { $0.kind == .systemMetricShell }
            .map(\.rect)
            .sorted { $0.minX < $1.minX }
        let shellGaps = zip(shells, shells.dropFirst()).map { current, next in
            next.minX - current.maxX
        }
        #expect(shellGaps.allSatisfy { abs($0 - CGFloat(LayoutConstants.itemSpacing)) < 0.5 })

        for title in ["CPU 100%", "RAM 74%", "TEMP 35°C"] {
            let item = try #require(snapshot.items.first { $0.title == title })
            let textWidth = (title as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
            ]).width
            #expect(item.titleRect.width >= textWidth + 4)
        }
        renderer.shutdown()
    }

    @Test func microSystemIndicatorPresetAllocatesSmallerTileThanDense() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorChipPreset = .dense
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .percentage, valueText: "55%", value: 55, history: [])
            ]
        )
        let denseWidth = try #require(renderer.snapshot(displayId: 1)?.items.first?.rect.width)

        config.systemIndicatorChipPreset = .micro
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .percentage, valueText: "55%", value: 55, history: [])
            ]
        )
        let microWidth = try #require(renderer.snapshot(displayId: 1)?.items.first?.rect.width)
        let microSnapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(microWidth < denseWidth)
        #expect(microSnapshot.items.first?.title == "")
        #expect(microSnapshot.nativeTextItems.isEmpty)
        #expect(microSnapshot.decorations.contains { $0.kind == .systemMetricGraph })
        renderer.shutdown()
    }

    @Test func denseUnderlineAndMinimalSystemIndicatorsPackAsTightCluster() throws {
        let glassWidth = try denseSystemIndicatorClusterWidth(appearance: .glass)
        let flatWidth = try denseSystemIndicatorClusterWidth(appearance: .flat)
        let underlineWidth = try denseSystemIndicatorClusterWidth(appearance: .underline)
        let minimalWidth = try denseSystemIndicatorClusterWidth(appearance: .minimal)

        #expect(flatWidth <= glassWidth - 5)
        #expect(underlineWidth <= flatWidth - 40)
        #expect(minimalWidth <= flatWidth - 40)
        #expect(abs(underlineWidth - minimalWidth) < 1)
    }

    @Test func denseFlatSystemIndicatorPlatesUseTighterVisualGap() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "55%", screenId: 1),
            .customText(id: "system.ram", text: "74%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorChipPreset = .dense
        config.systemIndicatorAppearance = .flat
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: []),
                "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "74%", value: 74, history: []),
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let shells = snapshot.decorations
            .filter { $0.kind == .systemMetricShell }
            .map(\.rect)
            .sorted { $0.minX < $1.minX }
        #expect(shells.count == 2)
        let first = try #require(shells.first)
        let second = try #require(shells.dropFirst().first)

        #expect(abs(second.minX - first.maxX - 2) < 0.5)
        renderer.shutdown()
    }

    @Test func tightDenseIndicatorRhythmOnlyAppliesWithinIndicatorCluster() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 340, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
            .customText(id: "system.cpu", text: "100%", screenId: 1),
            .customText(id: "system.ram", text: "74%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorChipPreset = .dense
        config.systemIndicatorAppearance = .minimal
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "100%", value: 100, history: []),
                "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "74%", value: 74, history: []),
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let app = try #require(snapshot.items.first?.rect)
        let cpu = try #require(snapshot.items.dropFirst().first?.rect)
        let ram = try #require(snapshot.items.dropFirst(2).first?.rect)
        let cpuItem = try #require(snapshot.items.dropFirst().first)
        let cpuTextWidth = ("100%" as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
        ]).width

        #expect(abs(cpu.minX - app.maxX - 4) < 0.5)
        #expect(abs(ram.minX - cpu.maxX - 1) < 0.5)
        #expect(cpuItem.titleRect.width >= cpuTextWidth)
        renderer.shutdown()
    }

    @Test func systemIndicatorAppearanceCanAvoidGlassShell() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 55%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorAppearance = .underline
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        #expect(!snapshot.decorations.contains { $0.kind == .systemMetricShell })
        #expect(snapshot.decorations.contains { $0.kind == .systemMetricFill })
        renderer.shutdown()
    }

    @Test func customSystemIndicatorColorTintsMetricFill() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 55%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto, systemIndicatorCpuColorHex: "#AF52DE")
        config.systemIndicatorAppearance = .underline
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let fill = try #require(snapshot.decorations.first { $0.kind == .systemMetricFill })
        let expected = try #require(PresentationColorPalette.color(from: "#AF52DE", alpha: 1))
        #expect(PresentationColorPalette.hexString(from: fill.color) == PresentationColorPalette.hexString(from: expected))
        renderer.shutdown()
    }

    @Test func flatSystemIndicatorAppearanceUsesNonGlassPlate() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "CPU 55%", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorAppearance = .flat
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let shell = try #require(snapshot.decorations.first { $0.kind == .systemMetricShell })
        #expect(shell.usesLayeredGlass == false)
        renderer.shutdown()
    }

    @Test func systemIndicatorRightCornerPlacementAnchorsCluster() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 500, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
            .customText(id: "system.ram", text: "RAM 68%", screenId: nil),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorPlacement = .rightCorner
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "42%", value: 42, history: []),
                "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "68%", value: 68, history: []),
            ]
        )

        let rects = renderer.visualItemRects(displayId: 1)
        #expect(rects.count == 3)
        #expect(rects[2].maxX >= 499.5)
        #expect(rects[1].minX > rects[0].maxX)
        renderer.shutdown()
    }

    @Test func rightCornerIndicatorsReserveReadableSpaceWhenBarIsFull() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 520, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One window title long enough to compress", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Two window title long enough to compress", appName: "Two", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(3), bundleId: "com.app.three", title: "Three window title long enough to compress", appName: "Three", isHidden: false, isMinimized: false, screenId: 1),
            .customText(id: "system.cpu", text: "CPU 70%", screenId: nil),
            .customText(id: "system.ram", text: "RAM 77%", screenId: nil),
            .customText(id: "system.thermal", text: "TEMP 34°C", screenId: nil),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorPlacement = .rightCorner

        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "70%", value: 70, history: [40, 55, 70]),
                "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "77%", value: 77, history: [65, 70, 77]),
                "system.thermal": systemVisual(metric: .thermal, mode: .percentage, valueText: "34°C", value: 34, history: []),
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let rects = snapshot.visualRects
        #expect(rects.count == 6)
        #expect(rects[5].maxX <= 520.5)
        #expect(rects[2].maxX <= rects[3].minX - 3.5)
        #expect(rects[0].width < 120)

        for title in ["CPU 70%", "RAM 77%", "TEMP 34°C"] {
            let item = try #require(snapshot.items.first { $0.title == title })
            let textWidth = (title as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(config.fontSize), weight: .medium)
            ]).width
            #expect(item.titleRect.width >= textWidth)
        }
        renderer.shutdown()
    }

    @Test func overflowCompressionCollapsesRegularItemsToIconOnlyPresentation() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 188, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One window title", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.two", title: "Two window title", appName: "Two", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(3), bundleId: "com.app.three", title: "Three window title", appName: "Three", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(4), bundleId: "com.app.four", title: "Four window title", appName: "Four", isHidden: false, isMinimized: false, screenId: 1),
        ]

        renderer.updateItems(
            items,
            config: Config(itemSizing: .auto),
            iconCache: IconCache(),
            displayId: 1
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        #expect(snapshot.items.count == 4)
        #expect(snapshot.items.allSatisfy { $0.title.isEmpty })
        #expect(snapshot.nativeTextItems.isEmpty)
        #expect(snapshot.items.allSatisfy { abs($0.iconRect.midX - $0.rect.midX) < 0.5 })
        renderer.shutdown()
    }

    @Test func systemIndicatorsRemainReadableAfterCollapsedWindowPartition() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 520, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .window(id: WindowId(1), bundleId: "com.app.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
            .window(id: WindowId(2), bundleId: "com.app.hidden", title: "Hidden", appName: "Hidden", isHidden: true, isMinimized: false, screenId: 1),
            .customText(id: "system.cpu", text: "CPU 42%", screenId: nil),
        ]
        var config = Config(itemSizing: .auto)
        config.hiddenWindowMode = .collapsedRight
        config.systemIndicatorPlacement = .trailing

        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "42%", value: 42, history: [])
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let indicator = try #require(snapshot.items.first { $0.item.bundleId == "custom:text:system.cpu" })
        let hidden = try #require(snapshot.items.first { $0.item.bundleId == "com.app.hidden" })

        #expect(hidden.title.isEmpty)
        #expect(indicator.title == "CPU 42%")
        #expect(indicator.titleRect.width >= 40)
        renderer.shutdown()
    }

    @Test func nativeBarViewUsesLayeredGlassDecorationsForHover() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        var config = Config(iconsOnly: true)
        config.visualDepth = .rich
        renderer.updateItems([
            .launcher(screenId: 1),
        ], config: config, iconCache: IconCache(), displayId: 1)
        #expect(renderer.setHoverRect(NSRect(x: 8, y: 4, width: 44, height: 24), for: 1) == true)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        let sublayerNames = view.debugDecorationLayerSublayerNames().flatMap { $0 }
        #expect(sublayerNames.contains("glass-fill"))
        #expect(sublayerNames.contains("glass-top-highlight"))
        #expect(sublayerNames.contains("glass-lower-shade"))
        #expect(sublayerNames.contains("glass-specular-edge"))
        renderer.shutdown()
    }

    @Test func nativeBarViewKeepsDecorationsBehindItemIcons() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        #expect(view.debugRetainedLayerOrder() == ["decorations", "items"])
    }

    private func systemVisual(
        metric: SystemIndicatorMetric,
        mode: SystemIndicatorVisualMode,
        valueText: String,
        value: Float?,
        history: [Float]
    ) -> SystemIndicatorVisual {
        SystemIndicatorVisual(
            metric: metric,
            mode: mode,
            label: metric.label,
            valueText: valueText,
            valuePercent: value,
            history: history,
            severity: 0.2
        )
    }

    private func denseSystemIndicatorClusterWidth(appearance: SystemIndicatorAppearance) throws -> CGFloat {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 420, barHeight: 32, scale: 2)
        let items: [TaskbarItem] = [
            .customText(id: "system.cpu", text: "55%", screenId: 1),
            .customText(id: "system.gpu", text: "--", screenId: 1),
            .customText(id: "system.ram", text: "74%", screenId: 1),
            .customText(id: "system.thermal", text: "35C", screenId: 1),
        ]
        var config = Config(itemSizing: .auto)
        config.systemIndicatorChipPreset = .dense
        config.systemIndicatorAppearance = appearance
        renderer.updateItems(
            items,
            config: config,
            iconCache: IconCache(),
            displayId: 1,
            systemIndicatorVisuals: [
                "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [20, 35, 55]),
                "system.gpu": systemVisual(metric: .gpu, mode: .percentage, valueText: "--", value: nil, history: []),
                "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "74%", value: 74, history: [44, 60, 74]),
                "system.thermal": systemVisual(metric: .thermal, mode: .percentage, valueText: "35C", value: 35, history: []),
            ]
        )

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let rects = snapshot.items.map(\.rect)
        let minX = try #require(rects.map(\.minX).min())
        let maxX = try #require(rects.map(\.maxX).max())
        renderer.shutdown()
        return maxX - minX
    }

    @Test func appGroupStackAndPillBadgeEmitDecorationsAndCountText() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupStackStyle = .filled
        config.appGroupStackGeometry = .subtle
        config.appGroupCountBadgeStyle = .pill

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(snapshot.decorations.filter { $0.kind == .stackPlate }.count == 2)
        #expect(snapshot.decorations.contains { $0.kind == .badge })
        #expect(snapshot.nativeTextItems.contains { $0.title == "3" })
        renderer.shutdown()
    }

    @Test func appGroupPillBadgeDoesNotOverlapIconOrStackFan() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 360, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 24, iconsOnly: true, groupByApp: true)
        config.appGroupStackGeometry = .strong
        config.appGroupStackHoverSpreadEnabled = true
        config.appGroupCountBadgeStyle = .pill

        renderer.updateItems([sampleAppGroup(windowCount: 4)], config: config, iconCache: IconCache(), displayId: 1)
        let idleSnapshot = try #require(renderer.snapshot(displayId: 1))
        #expect(renderer.setHoveredItemIndex(0, for: 1) == true)
        #expect(renderer.setHoverRect(idleSnapshot.visualRects[0], for: 1) == true)

        let snapshot = try #require(renderer.snapshot(displayId: 1))
        let item = try #require(snapshot.items.first)
        let badge = try #require(snapshot.decorations.first { $0.kind == .badge })
        let stackFanMaxX = snapshot.decorations
            .filter { $0.kind == .stackPlate }
            .map(\.rect.maxX)
            .max() ?? item.iconRect.maxX

        #expect(badge.rect.minX >= item.iconRect.maxX + 1)
        #expect(badge.rect.minX >= stackFanMaxX + 1)
        #expect(badge.rect.maxX <= item.rect.maxX - 1)
        renderer.shutdown()
    }

    @Test func appGroupSeparatorBadgeUsesSeparatorDecorationWithoutBadgePlate() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 240, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupCountBadgeStyle = .separator

        renderer.updateItems([sampleAppGroup(windowCount: 4)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(snapshot.decorations.contains { $0.kind == .separator })
        #expect(!snapshot.decorations.contains { $0.kind == .badge })
        #expect(snapshot.nativeTextItems.contains { $0.title == "4" })
        renderer.shutdown()
    }

    @Test func appGroupCountBadgeDoesNotOverlayTitledItems() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 260, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: false, groupByApp: true)
        config.itemSizing = .auto

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let snapshot = try #require(renderer.snapshot(displayId: 1))

        #expect(!snapshot.decorations.contains { $0.kind == .badge })
        #expect(!snapshot.nativeTextItems.contains { $0.title == "3" })
        #expect(snapshot.nativeTextItems.contains { $0.title == "Browser" })
        renderer.shutdown()
    }

    @Test func appGroupHoverSpreadMovesStackPlatesWithinReservedWidth() throws {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 260, barHeight: 36, scale: 2)

        var config = Config(taskbarHeight: 36, iconSize: 22, iconsOnly: true, groupByApp: true)
        config.appGroupStackGeometry = .strong
        config.appGroupStackHoverSpreadEnabled = true

        renderer.updateItems([sampleAppGroup(windowCount: 3)], config: config, iconCache: IconCache(), displayId: 1)
        let idleSnapshot = try #require(renderer.snapshot(displayId: 1))
        let idlePlateX = try #require(idleSnapshot.decorations.first { $0.kind == .stackPlate }?.rect.minX)
        let reservedWidth = try #require(idleSnapshot.visualRects.first?.width)

        #expect(renderer.setHoveredItemIndex(0, for: 1) == true)
        #expect(renderer.setHoverRect(idleSnapshot.visualRects[0], for: 1) == true)

        let hoverSnapshot = try #require(renderer.snapshot(displayId: 1))
        let hoverPlateX = try #require(hoverSnapshot.decorations.first { $0.kind == .stackPlate }?.rect.minX)

        #expect(hoverPlateX > idlePlateX)
        #expect(try #require(hoverSnapshot.visualRects.first?.width) == reservedWidth)
        renderer.shutdown()
    }

    @Test func nativeBarViewVisualDepthSnapshotCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_BAR_VISUAL_QA_PATH"],
              !outputPath.isEmpty else { return }

        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 420, barHeight: 48, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 420, height: 48))
        view.configure(scale: 2)

        var config = Config(taskbarHeight: 48, iconSize: 28, iconsOnly: true, itemSizing: .auto)
        config.groupByApp = true
        config.visualDepth = .rich
        config.hoverIntensity = .pronounced
        config.focusIndicatorStyle = .tile
        renderer.updateItems([
            .launcher(screenId: 1),
            .customText(id: "metric", text: "Liquid", screenId: 1),
            .pluginTile(id: "now-playing", providerId: nil, title: "Music", icon: "sf:music.note", visualState: .active, screenId: 1),
            .appGroup(bundleId: "com.example.browser", appName: "Browser", windowCount: 3, windows: [WindowId(1), WindowId(2), WindowId(3)], isHidden: false, isMinimized: false, screenId: 1),
        ], config: config, iconCache: IconCache(), displayId: 1, focus: FocusInfo(windowId: nil, bundleId: "com.example.browser", tabGroupId: nil))
        _ = renderer.setHoverRect(NSRect(x: 64, y: 6, width: 92, height: 36), for: 1)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 48)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 48))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor
        container.addSubview(view)
        view.displayIfNeeded()
        container.displayIfNeeded()

        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
        renderer.shutdown()
    }

    @Test func systemIndicatorAppearanceSnapshotCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_INDICATOR_VISUAL_QA_PATH"],
              !outputPath.isEmpty else { return }

        let rows: [(label: String, preset: SystemIndicatorChipPreset, appearance: SystemIndicatorAppearance)] = [
            ("Compact Glass", .compact, .glass),
            ("Compact Flat", .compact, .flat),
            ("Compact Underline", .compact, .underline),
            ("Dense Flat", .dense, .flat),
            ("Dense Underline", .dense, .underline),
            ("Dense Minimal", .dense, .minimal),
            ("Micro Minimal", .micro, .minimal),
        ]
        let rowHeight: CGFloat = 36
        let rowGap: CGFloat = 10
        let labelWidth: CGFloat = 150
        let barWidth: CGFloat = 620
        let height = CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowGap
        let container = NSView(frame: NSRect(x: 0, y: 0, width: labelWidth + barWidth, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).cgColor

        for (offset, row) in rows.enumerated() {
            let displayId = CGDirectDisplayID(offset + 1)
            let y = CGFloat(rows.count - offset - 1) * (rowHeight + rowGap)
            let label = NSTextField(labelWithString: row.label)
            label.frame = NSRect(x: 0, y: y + 8, width: labelWidth - 12, height: 18)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            container.addSubview(label)

            let renderer = NativeBarRenderer()
            renderer.registerPanel(displayId: displayId, barWidth: Float(barWidth), barHeight: Float(rowHeight), scale: 2)
            let view = NativeBarView(frame: NSRect(x: labelWidth, y: y, width: barWidth, height: rowHeight))
            view.configure(scale: 2)
            var config = Config(taskbarHeight: Int(rowHeight), iconSize: 20, itemSizing: .auto)
            config.systemIndicatorChipPreset = row.preset
            config.systemIndicatorAppearance = row.appearance
            renderer.updateItems(
                [
                    .customText(id: "system.cpu", text: systemIndicatorFixtureText(metric: .cpu, preset: row.preset, value: "55%"), screenId: 1),
                    .customText(id: "system.gpu", text: systemIndicatorFixtureText(metric: .gpu, preset: row.preset, value: "--"), screenId: 1),
                    .customText(id: "system.ram", text: systemIndicatorFixtureText(metric: .ram, preset: row.preset, value: "74%"), screenId: 1),
                    .customText(id: "system.thermal", text: systemIndicatorFixtureText(metric: .thermal, preset: row.preset, value: "35°C"), screenId: 1),
                ],
                config: config,
                iconCache: IconCache(),
                displayId: displayId,
                systemIndicatorVisuals: [
                    "system.cpu": systemVisual(metric: .cpu, mode: .bar, valueText: "55%", value: 55, history: [20, 35, 55]),
                    "system.gpu": systemVisual(metric: .gpu, mode: .percentage, valueText: "--", value: nil, history: []),
                    "system.ram": systemVisual(metric: .ram, mode: .bar, valueText: "74%", value: 74, history: [44, 60, 74]),
                    "system.thermal": systemVisual(metric: .thermal, mode: .percentage, valueText: "35°C", value: 35, history: []),
                ]
            )
            if let snapshot = renderer.snapshot(displayId: displayId) {
                view.applySnapshot(snapshot, fontSize: CGFloat(config.fontSize), barHeight: rowHeight)
            }
            container.addSubview(view)
            view.displayIfNeeded()
            renderer.shutdown()
        }

        container.displayIfNeeded()
        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
    }

    @Test func systemIndicatorReadmeShowcaseCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SYSTEM_INDICATOR_README_PATH"],
              !outputPath.isEmpty else { return }

        let rows: [(label: String, preset: SystemIndicatorChipPreset, appearance: SystemIndicatorAppearance)] = [
            ("Compact Glass", .compact, .glass),
            ("Compact Flat", .compact, .flat),
            ("Compact Underline", .compact, .underline),
            ("Dense Flat", .dense, .flat),
            ("Dense Underline", .dense, .underline),
            ("Dense Minimal", .dense, .minimal),
            ("Micro Minimal", .micro, .minimal),
        ]
        let rowHeight: CGFloat = 36
        let rowGap: CGFloat = 6
        let labelWidth: CGFloat = 142
        let barWidth: CGFloat = 430
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 12
        let displayScale: CGFloat = 2
        let displayId = CGDirectDisplayID(91)

        func makeConfig(
            preset: SystemIndicatorChipPreset,
            appearance: SystemIndicatorAppearance
        ) -> Config {
            var config = Config(
                taskbarHeight: Int(rowHeight),
                iconSize: 20,
                itemSizing: .auto,
                systemIndicatorRefreshIntervalMs: 250,
                systemIndicatorThermalEnabled: true
            )
            config.systemIndicatorChipPreset = preset
            config.systemIndicatorAppearance = appearance
            config.systemIndicatorCpuVisualMode = .bar
            config.systemIndicatorGpuVisualMode = .bar
            config.systemIndicatorRamVisualMode = .bar
            config.systemIndicatorThermalVisualMode = .bar
            return config
        }

        let provider = SystemMetricsProvider()
        let warmConfig = makeConfig(preset: .compact, appearance: .flat)
        for _ in 0..<3 {
            _ = provider.payload(config: warmConfig, now: CFAbsoluteTimeGetCurrent(), screenId: displayId)
            Thread.sleep(forTimeInterval: 0.28)
        }
        let probePayload = provider.payload(config: warmConfig, now: CFAbsoluteTimeGetCurrent(), screenId: displayId, refresh: false)
        let gpuItem = try #require(probePayload.items.first { $0.bundleId == "custom:text:system.gpu" })
        #expect(!gpuItem.displayTitle(iconsOnly: false).contains("--"))

        let contentWidth = labelWidth + barWidth
        let contentHeight = CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowGap
        let container = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: contentWidth + horizontalPadding * 2,
            height: contentHeight + verticalPadding * 2
        ))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        for (offset, row) in rows.enumerated() {
            let y = verticalPadding + CGFloat(rows.count - offset - 1) * (rowHeight + rowGap)
            let rowBackground = NSView(frame: NSRect(
                x: horizontalPadding,
                y: y,
                width: contentWidth,
                height: rowHeight
            ))
            rowBackground.wantsLayer = true
            rowBackground.layer?.backgroundColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.78).cgColor
            rowBackground.layer?.cornerRadius = 10
            container.addSubview(rowBackground)

            let label = NSTextField(labelWithString: row.label)
            label.frame = NSRect(x: horizontalPadding + 10, y: y + 9, width: labelWidth - 18, height: 17)
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            label.textColor = NSColor.white.withAlphaComponent(0.82)
            label.alignment = .right
            container.addSubview(label)

            let rowDisplayId = displayId + CGDirectDisplayID(offset)
            let config = makeConfig(preset: row.preset, appearance: row.appearance)
            let payload = provider.payload(
                config: config,
                now: CFAbsoluteTimeGetCurrent(),
                screenId: rowDisplayId,
                refresh: false
            )

            let renderer = NativeBarRenderer()
            renderer.registerPanel(displayId: rowDisplayId, barWidth: Float(barWidth), barHeight: Float(rowHeight), scale: Float(displayScale))
            let view = NativeBarView(frame: NSRect(
                x: horizontalPadding + labelWidth,
                y: y,
                width: barWidth,
                height: rowHeight
            ))
            view.configure(scale: displayScale)
            renderer.updateItems(
                payload.items,
                config: config,
                iconCache: IconCache(),
                displayId: rowDisplayId,
                systemIndicatorVisuals: payload.visuals
            )
            if let snapshot = renderer.snapshot(displayId: rowDisplayId) {
                view.applySnapshot(snapshot, fontSize: CGFloat(config.fontSize), barHeight: rowHeight)
            }
            container.addSubview(view)
            view.displayIfNeeded()
            renderer.shutdown()
        }

        container.displayIfNeeded()
        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
    }

    @Test func systemIndicatorSingleRowReadmeShowcaseCanBeExported() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SYSTEM_INDICATOR_SINGLE_ROW_PATH"],
              !outputPath.isEmpty else { return }

        let barWidth: CGFloat = 620
        let barHeight: CGFloat = 40
        let displayId = CGDirectDisplayID(109)
        var config = Config(
            taskbarHeight: Int(barHeight),
            iconSize: 20,
            itemSizing: .auto,
            systemIndicatorRefreshIntervalMs: 250,
            systemIndicatorThermalEnabled: true
        )
        config.systemIndicatorChipPreset = .compact
        config.systemIndicatorAppearance = .flat
        config.systemIndicatorCpuVisualMode = .bar
        config.systemIndicatorGpuVisualMode = .bar
        config.systemIndicatorRamVisualMode = .bar
        config.systemIndicatorThermalVisualMode = .bar

        let provider = SystemMetricsProvider()
        _ = provider.payload(config: config, now: CFAbsoluteTimeGetCurrent(), screenId: displayId)
        Thread.sleep(forTimeInterval: 0.35)
        let payload = provider.payload(config: config, now: CFAbsoluteTimeGetCurrent(), screenId: displayId)
        let gpuItem = try #require(payload.items.first { $0.bundleId == "custom:text:system.gpu" })
        #expect(!gpuItem.displayTitle(iconsOnly: false).contains("--"))

        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: displayId, barWidth: Float(barWidth), barHeight: Float(barHeight), scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        view.configure(scale: 2)
        renderer.updateItems(
            payload.items,
            config: config,
            iconCache: IconCache(),
            displayId: displayId,
            systemIndicatorVisuals: payload.visuals
        )
        if let snapshot = renderer.snapshot(displayId: displayId) {
            view.applySnapshot(snapshot, fontSize: CGFloat(config.fontSize), barHeight: barHeight)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(view)
        view.displayIfNeeded()
        container.displayIfNeeded()

        try writeViewSnapshot(container, to: URL(fileURLWithPath: outputPath))
        renderer.shutdown()
    }

    private func systemIndicatorFixtureText(
        metric: SystemIndicatorMetric,
        preset: SystemIndicatorChipPreset,
        value: String
    ) -> String {
        switch preset {
        case .full, .compact:
            return "\(metric.label) \(value)"
        case .dense:
            return metric == .thermal ? "35C" : value
        case .micro:
            return ""
        }
    }

    private func writeViewSnapshot(_ view: NSView, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    @Test func nativeBarViewPrunesStaleItemLayersAcrossWindowChurn() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        renderer.updateItems([
            .window(id: WindowId(1), bundleId: "com.test.one", title: "One", appName: "One", isHidden: false, isMinimized: false, screenId: 1),
        ], config: Config(iconSize: 20, iconsOnly: false), iconCache: IconCache(), displayId: 1)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }
        #expect(view.debugLayerPoolCounts().items == 1)
        #expect(view.debugLayerPoolCounts().icons == 1)

        renderer.updateItems([
            .window(id: WindowId(2), bundleId: "com.test.two", title: "Two", appName: "Two", isHidden: false, isMinimized: false, screenId: 1),
        ], config: Config(iconSize: 20, iconsOnly: false), iconCache: IconCache(), displayId: 1)
        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        #expect(view.debugLayerPoolCounts().items == 1)
        #expect(view.debugLayerPoolCounts().icons == 1)
        renderer.shutdown()
    }

    @Test func nativeBarViewKeepsIconAndTextLayersAtBackingScale() {
        let renderer = NativeBarRenderer()
        renderer.registerPanel(displayId: 1, barWidth: 300, barHeight: 32, scale: 2)
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        view.configure(scale: 2)

        renderer.updateItems([
            .launcher(screenId: 1),
            .customText(id: "label", text: "Sharp Text", screenId: 1),
        ], config: Config(iconSize: 20, iconsOnly: false), iconCache: IconCache(), displayId: 1)

        if let snapshot = renderer.snapshot(displayId: 1) {
            view.applySnapshot(snapshot, fontSize: 13, barHeight: 32)
        }

        let scales = view.debugLayerScales()
        #expect(scales.root == 2)
        #expect(!scales.icon.isEmpty)
        #expect(scales.icon.allSatisfy { $0 == 2 })
        #expect(!scales.text.isEmpty)
        #expect(scales.text.allSatisfy { $0 == 2 })

        let iconFrames = view.debugIconLayerFrames()
        #expect(!iconFrames.isEmpty)
        #expect(iconFrames.allSatisfy { abs($0.width - 20) < 0.001 })
        #expect(iconFrames.allSatisfy { abs($0.height - 20) < 0.001 })
        #expect(view.debugIconLayerContentTypes().allSatisfy { $0 == "NSImage" })
        renderer.shutdown()
    }

    private func sampleAppGroup(windowCount: Int) -> TaskbarItem {
        .appGroup(
            bundleId: "com.example.browser",
            appName: "Browser",
            windowCount: windowCount,
            windows: (1...windowCount).map { WindowId(UInt32($0)) },
            isHidden: false,
            isMinimized: false,
            screenId: 1
        )
    }
}
