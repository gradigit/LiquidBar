import Testing
@testable import LiquidBar

@Suite
@MainActor
struct SystemMetricsProviderTests {
    @Test func taskbarItemsUseInjectedSnapshot() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63)
        }

        let items = provider.taskbarItems(config: Config(systemIndicatorsEnabled: true), now: 10)

        #expect(items.count == 3)
        #expect(items.map { $0.displayTitle(iconsOnly: false) } == ["CPU 42%", "GPU 7%", "RAM 63%"])
    }

    @Test func indicatorVisualsProvideDescriptiveToolTips() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63, temperatureCelsius: 34)
        }
        let payload = provider.payload(
            config: Config(systemIndicatorThermalEnabled: true),
            now: 10
        )

        #expect(payload.visuals["system.cpu"]?.toolTipText == L10n.tr("CPU Usage: %@", "42%"))
        #expect(payload.visuals["system.gpu"]?.toolTipText == L10n.tr("GPU Usage: %@", "7%"))
        #expect(payload.visuals["system.ram"]?.toolTipText == L10n.tr("Memory Usage: %@", "63%"))
        #expect(payload.visuals["system.thermal"]?.toolTipText == L10n.tr("Temperature: %@", "34°C"))
    }

    @Test func taskbarItemsCanBeDisabled() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63)
        }

        let payload = provider.payload(config: Config(systemIndicatorsEnabled: false), now: 10)

        #expect(payload.items.isEmpty)
        #expect(payload.visuals.isEmpty)
    }

    @Test func unavailableValuesRenderAsPlaceholders() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: nil, gpuPercent: nil, ramPercent: nil)
        }

        let items = provider.taskbarItems(config: Config(systemIndicatorsEnabled: true), now: 10)

        #expect(items.map { $0.displayTitle(iconsOnly: false) } == ["CPU --", "GPU --", "RAM --"])
    }

    @Test func gpuUtilizationUsesWholeDeviceStatistic() {
        let value = SystemMetricsProvider.gpuUtilizationPercent(from: [
            "Device Utilization %": 49,
            "Renderer Utilization %": 88,
            "Tiler Utilization %": 91,
        ])

        #expect(value == 49)
    }

    @Test func gpuUtilizationFallsBackToPipelineStatistics() {
        let value = SystemMetricsProvider.gpuUtilizationPercent(from: [
            "Renderer Utilization %": 48,
            "Tiler Utilization %": 49,
        ])

        #expect(value == 49)
    }

    @Test func gpuUtilizationClampsAndRejectsInvalidValues() {
        #expect(SystemMetricsProvider.gpuUtilizationPercent(from: ["GPU Activity(%)": 133]) == 100)
        #expect(SystemMetricsProvider.gpuUtilizationPercent(from: ["Device Utilization %": -7]) == 0)
        #expect(SystemMetricsProvider.gpuUtilizationPercent(from: ["Device Utilization %": Double.infinity]) == nil)
        #expect(SystemMetricsProvider.gpuUtilizationPercent(from: [:]) == nil)
    }

    @Test func metricTogglesControlOutputOrder() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63)
        }
        let config = Config(
            systemIndicatorCpuEnabled: false,
            systemIndicatorGpuEnabled: true,
            systemIndicatorRamEnabled: true,
            systemIndicatorThermalEnabled: true
        )

        let payload = provider.payload(config: config, now: 10)

        #expect(payload.items.map { $0.bundleId } == [
            "custom:text:system.gpu",
            "custom:text:system.ram",
            "custom:text:system.thermal",
        ])
    }

    @Test func graphModeBuildsVisualHistory() {
        var sample = 0.0
        let provider = SystemMetricsProvider {
            sample += 10
            return SystemMetricsSnapshot(cpuPercent: sample, gpuPercent: nil, ramPercent: 55)
        }
        let config = Config(
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false,
            systemIndicatorCpuVisualMode: .graph,
            systemIndicatorGraphSamples: 4
        )

        _ = provider.payload(config: config, now: 1)
        _ = provider.payload(config: config, now: 2)
        _ = provider.payload(config: config, now: 3)
        _ = provider.payload(config: config, now: 4)
        let payload = provider.payload(config: config, now: 5)

        let visual = payload.visuals["system.cpu"]
        #expect(visual?.mode == .graph)
        #expect(visual?.history == [20, 30, 40, 50])
        #expect(visual?.valueText == "50%")
    }

    @Test func cachedPayloadDoesNotRefreshSampler() {
        var sampleCount = 0
        let provider = SystemMetricsProvider {
            sampleCount += 1
            return SystemMetricsSnapshot(cpuPercent: Double(sampleCount), gpuPercent: nil, ramPercent: nil)
        }
        let config = Config(
            systemIndicatorRefreshIntervalMs: 250,
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false
        )

        _ = provider.payload(config: config, now: 1)
        let cached = provider.payload(config: config, now: 10, refresh: false)

        #expect(sampleCount == 1)
        #expect(cached.items.map { $0.displayTitle(iconsOnly: false) } == ["CPU 1%"])
    }

    @Test func seriousThermalDegradesGraphToBar() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 70, gpuPercent: nil, ramPercent: nil, thermalLevel: .serious)
        }
        let config = Config(
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false,
            systemIndicatorCpuVisualMode: .graph
        )

        let visual = provider.payload(config: config, now: 10).visuals["system.cpu"]

        #expect(visual?.mode == .bar)
    }

    @Test func densePresetUsesMetricValues() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63)
        }
        let config = Config(systemIndicatorChipPreset: .dense)

        let items = provider.taskbarItems(config: config, now: 10)

        #expect(items.map { $0.displayTitle(iconsOnly: false) } == ["42%", "7%", "63%"])
    }

    @Test func microPresetUsesNoTextIncludingThermal() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63, temperatureCelsius: 34)
        }
        let config = Config(systemIndicatorThermalEnabled: true, systemIndicatorChipPreset: .micro)

        let items = provider.taskbarItems(config: config, now: 10)

        #expect(items.map { $0.displayTitle(iconsOnly: false) } == ["", "", "", ""])
    }

    @Test func thermalIndicatorShowsCelsiusByDefault() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(
                cpuPercent: nil,
                gpuPercent: nil,
                ramPercent: nil,
                temperatureCelsius: 31.6,
                thermalLevel: .nominal
            )
        }
        let config = Config(
            systemIndicatorCpuEnabled: false,
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false,
            systemIndicatorThermalEnabled: true
        )

        let payload = provider.payload(config: config, now: 10)

        #expect(payload.items.map { $0.displayTitle(iconsOnly: false) } == ["TEMP 32°C"])
        #expect(payload.visuals["system.thermal"]?.valueText == "32°C")
        #expect(payload.visuals["system.thermal"]?.valuePercent == Float(31.6))
    }

    @Test func thermalIndicatorCanShowFahrenheit() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(
                cpuPercent: nil,
                gpuPercent: nil,
                ramPercent: nil,
                temperatureCelsius: 30,
                thermalLevel: .nominal
            )
        }
        let config = Config(
            systemIndicatorCpuEnabled: false,
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false,
            systemIndicatorThermalEnabled: true,
            systemIndicatorTemperatureUnit: .fahrenheit
        )

        let payload = provider.payload(config: config, now: 10)

        #expect(payload.items.map { $0.displayTitle(iconsOnly: false) } == ["TEMP 86°F"])
        #expect(payload.visuals["system.thermal"]?.valueText == "86°F")
    }

    @Test func denseThermalIndicatorStillShowsTemperature() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(
                cpuPercent: nil,
                gpuPercent: nil,
                ramPercent: nil,
                temperatureCelsius: 30,
                thermalLevel: .nominal
            )
        }
        let config = Config(
            systemIndicatorCpuEnabled: false,
            systemIndicatorGpuEnabled: false,
            systemIndicatorRamEnabled: false,
            systemIndicatorThermalEnabled: true,
            systemIndicatorChipPreset: .dense
        )

        let items = provider.taskbarItems(config: config, now: 10)

        #expect(items.map { $0.displayTitle(iconsOnly: false) } == ["30C"])
    }

    @Test func taskbarItemsCanTargetSelectedDisplay() {
        let provider = SystemMetricsProvider {
            SystemMetricsSnapshot(cpuPercent: 42, gpuPercent: 7, ramPercent: 63)
        }

        let items = provider.taskbarItems(config: Config(systemIndicatorsEnabled: true), now: 10, screenId: 42)

        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.screenId == 42 })
    }
}
