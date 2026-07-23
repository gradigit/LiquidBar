import Darwin
import Foundation
import IOKit

enum SystemIndicatorMetric: String, Sendable, CaseIterable {
    case cpu
    case gpu
    case ram
    case thermal

    var id: String { "system.\(rawValue)" }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ram: "RAM"
        case .thermal: "TEMP"
        }
    }

    var denseLabel: String {
        switch self {
        case .cpu: "C"
        case .gpu: "G"
        case .ram: "R"
        case .thermal: "T"
        }
    }
}

enum ThermalLevel: String, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    var label: String {
        switch self {
        case .nominal: L10n.tr("Nominal")
        case .fair: L10n.tr("Fair")
        case .serious: L10n.tr("Serious")
        case .critical: L10n.tr("Critical")
        }
    }

    var compactLabel: String {
        switch self {
        case .nominal: L10n.tr("Nom")
        case .fair: L10n.tr("Fair")
        case .serious: L10n.tr("Hot")
        case .critical: L10n.tr("Crit")
        }
    }

    var severityPercent: Double {
        switch self {
        case .nominal: 18
        case .fair: 44
        case .serious: 74
        case .critical: 100
        }
    }
}

struct SystemMetricsSnapshot: Equatable, Sendable {
    var sampledAt: CFAbsoluteTime = 0
    var cpuPercent: Double?
    var gpuPercent: Double?
    var ramPercent: Double?
    var temperatureCelsius: Double?
    var thermalLevel: ThermalLevel = .nominal
}

struct SystemIndicatorVisual: Equatable, Sendable {
    var metric: SystemIndicatorMetric
    var mode: SystemIndicatorVisualMode
    var label: String
    var valueText: String
    /// Normalized 0...100 value. `nil` means the metric is unavailable.
    var valuePercent: Float?
    /// Recent normalized 0...100 samples, already bounded by config.
    var history: [Float]
    /// 0...1 urgency tint used for thermal-aware accents.
    var severity: Float

    var toolTipText: String {
        switch metric {
        case .cpu:
            L10n.tr("CPU Usage: %@", valueText)
        case .gpu:
            L10n.tr("GPU Usage: %@", valueText)
        case .ram:
            L10n.tr("Memory Usage: %@", valueText)
        case .thermal:
            L10n.tr("Temperature: %@", valueText)
        }
    }
}

struct SystemIndicatorPayload: Sendable {
    var items: [TaskbarItem]
    var visuals: [String: SystemIndicatorVisual]
}

enum SystemMetricsFormatter {
    static func makeTaskbarItems(
        config: Config,
        snapshot: SystemMetricsSnapshot,
        history: [SystemIndicatorMetric: [Double]],
        screenId: UInt32? = nil
    ) -> [TaskbarItem] {
        guard config.systemIndicatorsEnabled else { return [] }
        return enabledMetrics(config: config).map { metric in
            .customText(
                id: metric.id,
                text: displayText(metric: metric, snapshot: snapshot, config: config),
                screenId: screenId
            )
        }
    }

    static func makeVisuals(
        config: Config,
        snapshot: SystemMetricsSnapshot,
        history: [SystemIndicatorMetric: [Double]]
    ) -> [String: SystemIndicatorVisual] {
        guard config.systemIndicatorsEnabled else { return [:] }
        var map: [String: SystemIndicatorVisual] = [:]
        for metric in enabledMetrics(config: config) {
            map[metric.id] = renderVisual(metric: metric, config: config, snapshot: snapshot, history: history)
        }
        return map
    }

    static func enabledMetrics(config: Config) -> [SystemIndicatorMetric] {
        var metrics: [SystemIndicatorMetric] = []
        if config.systemIndicatorCpuEnabled { metrics.append(.cpu) }
        if config.systemIndicatorGpuEnabled { metrics.append(.gpu) }
        if config.systemIndicatorRamEnabled { metrics.append(.ram) }
        if config.systemIndicatorThermalEnabled { metrics.append(.thermal) }
        return metrics
    }

    static func adaptiveMode(
        requested: SystemIndicatorVisualMode,
        thermalLevel: ThermalLevel
    ) -> SystemIndicatorVisualMode {
        switch thermalLevel {
        case .nominal, .fair:
            return requested
        case .serious:
            return requested == .graph ? .bar : requested
        case .critical:
            return .percentage
        }
    }

    static func displayText(
        metric: SystemIndicatorMetric,
        snapshot: SystemMetricsSnapshot,
        config: Config
    ) -> String {
        switch config.systemIndicatorChipPreset {
        case .full, .compact:
            switch metric {
            case .cpu:
                return "\(metric.label) \(formattedPercent(snapshot.cpuPercent))"
            case .gpu:
                return "\(metric.label) \(formattedPercent(snapshot.gpuPercent))"
            case .ram:
                return "\(metric.label) \(formattedPercent(snapshot.ramPercent))"
            case .thermal:
                if let temperature = snapshot.temperatureCelsius {
                    return "\(metric.label) \(formattedTemperature(temperature, unit: config.systemIndicatorTemperatureUnit, compact: false))"
                }
                return "\(metric.label) \(snapshot.thermalLevel.compactLabel)"
            }
        case .dense:
            return denseDisplayText(metric: metric, snapshot: snapshot, config: config)
        case .micro:
            return ""
        }
    }

    private static func denseDisplayText(
        metric: SystemIndicatorMetric,
        snapshot: SystemMetricsSnapshot,
        config: Config
    ) -> String {
        switch metric {
        case .cpu:
            return formattedPercent(snapshot.cpuPercent)
        case .gpu:
            return formattedPercent(snapshot.gpuPercent)
        case .ram:
            return formattedPercent(snapshot.ramPercent)
        case .thermal:
            if let temperature = snapshot.temperatureCelsius {
                return formattedTemperature(temperature, unit: config.systemIndicatorTemperatureUnit, compact: true)
            }
            return snapshot.thermalLevel.compactLabel
        }
    }

    static func renderVisual(
        metric: SystemIndicatorMetric,
        config: Config,
        snapshot: SystemMetricsSnapshot,
        history: [SystemIndicatorMetric: [Double]]
    ) -> SystemIndicatorVisual {
        let requestedMode = mode(for: metric, config: config)
        let effectiveMode = adaptiveMode(requested: requestedMode, thermalLevel: snapshot.thermalLevel)
        let valuePercent: Float?
        let valueText: String

        switch metric {
        case .cpu:
            valuePercent = clampedPercent(snapshot.cpuPercent)
            valueText = formattedPercent(snapshot.cpuPercent)
        case .gpu:
            valuePercent = clampedPercent(snapshot.gpuPercent)
            valueText = formattedPercent(snapshot.gpuPercent)
        case .ram:
            valuePercent = clampedPercent(snapshot.ramPercent)
            valueText = formattedPercent(snapshot.ramPercent)
        case .thermal:
            if let temperature = snapshot.temperatureCelsius {
                valuePercent = clampedPercent(temperature)
                valueText = formattedTemperature(temperature, unit: config.systemIndicatorTemperatureUnit, compact: false)
            } else {
                valuePercent = Float(snapshot.thermalLevel.severityPercent)
                valueText = snapshot.thermalLevel.label
            }
        }

        return SystemIndicatorVisual(
            metric: metric,
            mode: effectiveMode,
            label: metric.label,
            valueText: valueText,
            valuePercent: valuePercent,
            history: normalizedHistory(history[metric] ?? []),
            severity: Float(min(max(snapshot.thermalLevel.severityPercent / 100.0, 0), 1))
        )
    }

    private static func mode(for metric: SystemIndicatorMetric, config: Config) -> SystemIndicatorVisualMode {
        switch metric {
        case .cpu: config.systemIndicatorCpuVisualMode
        case .gpu: config.systemIndicatorGpuVisualMode
        case .ram: config.systemIndicatorRamVisualMode
        case .thermal: config.systemIndicatorThermalVisualMode
        }
    }

    private static func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()).clamped(to: 0...100))%"
    }

    private static func formattedTemperature(
        _ celsius: Double,
        unit: SystemIndicatorTemperatureUnit,
        compact: Bool
    ) -> String {
        let value: Int
        let suffix: String
        switch unit {
        case .celsius:
            value = Int(celsius.rounded())
            suffix = compact ? "C" : "°C"
        case .fahrenheit:
            value = Int((celsius * 9.0 / 5.0 + 32.0).rounded())
            suffix = compact ? "F" : "°F"
        }
        return "\(value)\(suffix)"
    }

    private static func clampedPercent(_ value: Double?) -> Float? {
        value.map { Float(min(max($0, 0), 100)) }
    }

    private static func normalizedHistory(_ values: [Double]) -> [Float] {
        values.map { Float(min(max($0, 0), 100)) }
    }
}

@MainActor
final class SystemMetricsProvider {
    typealias Sampler = () -> SystemMetricsSnapshot

    private let sampler: Sampler?
    private var cached = SystemMetricsSnapshot()
    private var history: [SystemIndicatorMetric: [Double]] = [:]
    private var lastSampleAt: CFAbsoluteTime = 0
    private var previousCPUTicks: [UInt64]?

    init(sampler: Sampler? = nil) {
        self.sampler = sampler
    }

    func needsRefresh(now: CFAbsoluteTime, config: Config) -> Bool {
        guard config.systemIndicatorsEnabled else { return false }
        return now - lastSampleAt >= refreshInterval(config: config)
    }

    func payload(
        config: Config,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        screenId: UInt32? = nil,
        refresh: Bool = true
    ) -> SystemIndicatorPayload {
        guard config.systemIndicatorsEnabled else {
            return SystemIndicatorPayload(items: [], visuals: [:])
        }
        if refresh {
            refreshIfNeeded(config: config, now: now)
        }
        return SystemIndicatorPayload(
            items: SystemMetricsFormatter.makeTaskbarItems(config: config, snapshot: cached, history: history, screenId: screenId),
            visuals: SystemMetricsFormatter.makeVisuals(config: config, snapshot: cached, history: history)
        )
    }

    func taskbarItems(
        config: Config,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        screenId: UInt32? = nil
    ) -> [TaskbarItem] {
        payload(config: config, now: now, screenId: screenId).items
    }

    func taskbarVisuals(config: Config, now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> [String: SystemIndicatorVisual] {
        payload(config: config, now: now).visuals
    }

    func refreshIfNeeded(config: Config, now: CFAbsoluteTime) {
        guard needsRefresh(now: now, config: config) else { return }
        var snapshot = sampler?() ?? sample(config: config)
        snapshot.sampledAt = now
        cached = snapshot
        lastSampleAt = now
        appendHistory(from: snapshot, limit: adaptiveHistoryLimit(config: config, thermalLevel: snapshot.thermalLevel))
    }

    private func refreshInterval(config: Config) -> CFTimeInterval {
        let base = max(0.25, Double(config.systemIndicatorRefreshIntervalMs) / 1000.0)
        switch cached.thermalLevel {
        case .nominal, .fair:
            return base
        case .serious:
            return max(base, 2.0)
        case .critical:
            return max(base * 2.0, 5.0)
        }
    }

    private func adaptiveHistoryLimit(config: Config, thermalLevel: ThermalLevel) -> Int {
        switch thermalLevel {
        case .nominal, .fair:
            return config.systemIndicatorGraphSamples
        case .serious:
            return min(config.systemIndicatorGraphSamples, 12)
        case .critical:
            return min(config.systemIndicatorGraphSamples, 4)
        }
    }

    private func appendHistory(from snapshot: SystemMetricsSnapshot, limit: Int) {
        append(.cpu, snapshot.cpuPercent, limit: limit)
        append(.gpu, snapshot.gpuPercent, limit: limit)
        append(.ram, snapshot.ramPercent, limit: limit)
        append(.thermal, snapshot.temperatureCelsius ?? snapshot.thermalLevel.severityPercent, limit: limit)
    }

    private func append(_ metric: SystemIndicatorMetric, _ value: Double?, limit: Int) {
        guard let value else { return }
        var values = history[metric, default: []]
        values.append(min(max(value, 0), 100))
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
        history[metric] = values
    }

    private func sample(config: Config) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            cpuPercent: config.systemIndicatorCpuEnabled ? sampleCPUPercent() : nil,
            gpuPercent: config.systemIndicatorGpuEnabled ? sampleGPUPercent() : nil,
            ramPercent: config.systemIndicatorRamEnabled ? sampleRAMPercent() : nil,
            temperatureCelsius: config.systemIndicatorThermalEnabled ? sampleBatteryTemperatureCelsius() : nil,
            thermalLevel: ThermalLevel(ProcessInfo.processInfo.thermalState)
        )
    }

    private func sampleCPUPercent() -> Double? {
        guard let ticks = currentCPUTicks(), ticks.count >= 4 else { return nil }
        defer { previousCPUTicks = ticks }

        guard let previous = previousCPUTicks, previous.count == ticks.count else {
            return nil
        }

        var deltas: [UInt64] = []
        deltas.reserveCapacity(ticks.count)
        for index in ticks.indices {
            deltas.append(ticks[index] >= previous[index] ? ticks[index] - previous[index] : 0)
        }

        let idleIndex = Int(CPU_STATE_IDLE)
        let idle = idleIndex < deltas.count ? deltas[idleIndex] : 0
        let total = deltas.reduce(0, +)
        guard total > 0, total >= idle else { return nil }
        let active = total - idle
        return (Double(active) / Double(total) * 100.0).rounded()
    }

    private func sampleGPUPercent() -> Double? {
        // IOAccelerator exposes these statistics on many Macs, but not as a stable public API.
        // Treat it as best-effort and fall back to "GPU --" when the keys are absent.
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var bestUtilization: Double?
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(service) }

            guard let statistics = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
                let utilization = Self.gpuUtilizationPercent(from: statistics)
            else {
                continue
            }

            bestUtilization = max(bestUtilization ?? utilization, utilization)
        }

        return bestUtilization
    }

    static func gpuUtilizationPercent(from statistics: [String: Any]) -> Double? {
        let wholeDeviceKeys = [
            "Device Utilization %",
            "GPU Activity(%)",
            "GPU Activity %",
        ]
        for key in wholeDeviceKeys {
            if let value = percentValue(statistics[key]) {
                return value
            }
        }

        let pipelineValues = [
            percentValue(statistics["Renderer Utilization %"]),
            percentValue(statistics["Tiler Utilization %"]),
        ].compactMap { $0 }
        return pipelineValues.max()
    }

    private static func percentValue(_ value: Any?) -> Double? {
        let percent: Double?
        switch value {
        case let number as NSNumber:
            percent = number.doubleValue
        case let int as Int:
            percent = Double(int)
        case let double as Double:
            percent = double
        case let float as Float:
            percent = Double(float)
        default:
            percent = nil
        }

        guard let percent, percent.isFinite else { return nil }
        return min(max(percent, 0), 100).rounded()
    }

    private func currentCPUTicks() -> [UInt64]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return withUnsafeBytes(of: info.cpu_ticks) { rawBuffer in
            Array(rawBuffer.bindMemory(to: natural_t.self).map(UInt64.init))
        }
    }

    private func sampleRAMPercent() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize = vm_size_t(0)
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }

        let usedPages =
            UInt64(stats.active_count) +
            UInt64(stats.wire_count) +
            UInt64(stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }

        return (Double(usedBytes) / Double(totalBytes) * 100.0).rounded()
    }

    private func sampleBatteryTemperatureCelsius() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else {
            return nil
        }

        let raw = value.doubleValue
        if raw > 1000 {
            return raw / 10.0 - 273.15
        }
        if raw > 0, raw < 150 {
            return raw
        }
        return nil
    }
}
