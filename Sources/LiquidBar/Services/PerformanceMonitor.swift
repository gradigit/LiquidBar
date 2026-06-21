import Foundation
import QuartzCore
import CoreGraphics

/// Lightweight, interval-based performance counters for renderer + event-loop timing.
///
/// Notes:
/// - Default-off in config.
/// - Aggregates in-memory and emits one concise log line per interval.
/// - Intended for benchmark sessions and regression tracking, not always-on telemetry.
@MainActor
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private struct DisplayAggregate {
        var frameCount: Int = 0
        var drawableMissCount: Int = 0
        var callbackDurationsMs: [Double] = []
        var renderDurationsMs: [Double] = []
        var gpuDurationsMs: [Double] = []
        var gpuWallDurationsMs: [Double] = []
    }

    private var enabled = false
    private var gpuTimingEnabled = false
    private var logIntervalSeconds: CFTimeInterval = 1.0

    private var intervalStart: CFTimeInterval = CACurrentMediaTime()
    private var displayAggregates: [CGDirectDisplayID: DisplayAggregate] = [:]

    private var pollDurationsMs: [Double] = []
    private var pollWindowCounts: [Double] = []
    private var pollExecutedCount: Int = 0
    private var pollSkippedCount: Int = 0
    private var pollReasonCounts: [String: Int] = [:]

    private let maxSamples = 512

    private init() {}

    var isEnabled: Bool { enabled }
    var isGPUFeedbackEnabled: Bool { enabled && gpuTimingEnabled }

    func apply(config: Config) {
        let nextEnabled = config.performanceLoggingEnabled
        let nextGPU = config.performanceGpuTimingEnabled
        let nextInterval = max(0.25, Double(config.performanceLogIntervalMs) / 1000.0)

        let changed =
            nextEnabled != enabled
            || nextGPU != gpuTimingEnabled
            || abs(nextInterval - logIntervalSeconds) > 0.001

        enabled = nextEnabled
        gpuTimingEnabled = nextGPU
        logIntervalSeconds = nextInterval

        if changed {
            resetInterval(now: CACurrentMediaTime())
            if enabled {
                let intervalMs = Self.fmtMs(self.logIntervalSeconds * 1000)
                let gpuMode = self.gpuTimingEnabled ? "on" : "off"
                Log.perf.info(
                    "Performance logging enabled (interval=\(intervalMs, privacy: .public)ms, gpu=\(gpuMode, privacy: .public))"
                )
            } else {
                Log.perf.info("Performance logging disabled")
            }
        }
    }

    func recordPoll(durationMs: Double, enumerated: Bool, reason: String, windowCount: Int) {
        guard enabled else { return }
        appendCapped(&pollDurationsMs, maxSamples, max(0, durationMs))
        appendCapped(&pollWindowCounts, maxSamples, Double(max(0, windowCount)))
        if enumerated {
            pollExecutedCount += 1
        } else {
            pollSkippedCount += 1
        }
        pollReasonCounts[reason, default: 0] += 1
        flushIfNeeded(now: CACurrentMediaTime())
    }

    func recordFrame(displayId: CGDirectDisplayID, callbackDurationMs: Double, renderDurationMs: Double) {
        guard enabled else { return }
        var agg = displayAggregates[displayId, default: DisplayAggregate()]
        agg.frameCount += 1
        appendCapped(&agg.callbackDurationsMs, maxSamples, max(0, callbackDurationMs))
        appendCapped(&agg.renderDurationsMs, maxSamples, max(0, renderDurationMs))
        displayAggregates[displayId] = agg
        flushIfNeeded(now: CACurrentMediaTime())
    }

    func recordDrawableMiss(displayId: CGDirectDisplayID) {
        guard enabled else { return }
        var agg = displayAggregates[displayId, default: DisplayAggregate()]
        agg.drawableMissCount += 1
        displayAggregates[displayId] = agg
    }

    func recordGPUFrame(
        displayId: CGDirectDisplayID,
        gpuDurationMs: Double,
        gpuWallDurationMs: Double,
        errorDescription: String?
    ) {
        guard enabled, gpuTimingEnabled else { return }
        var agg = displayAggregates[displayId, default: DisplayAggregate()]
        appendCapped(&agg.gpuDurationsMs, maxSamples, max(0, gpuDurationMs))
        appendCapped(&agg.gpuWallDurationsMs, maxSamples, max(0, gpuWallDurationMs))
        displayAggregates[displayId] = agg
        if let errorDescription, !errorDescription.isEmpty {
            Log.perf.error("GPU feedback error: \(errorDescription, privacy: .public)")
        }
        flushIfNeeded(now: CACurrentMediaTime())
    }

    func recordSwitcherAction(
        action: String,
        durationMs: Double,
        count: Int,
        direction: Int,
        entries: Int,
        selectedIndex: Int,
        success: Bool
    ) {
        guard enabled else { return }
        let safeAction = action.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let actionName = safeAction.isEmpty ? "unknown" : safeAction
        let successInt = success ? 1 : 0
        Log.perf.info(
            "switcher action=\(actionName, privacy: .public) duration_ms=\(Self.fmt2(max(0, durationMs)), privacy: .public) count=\(max(0, count), privacy: .public) direction=\(direction, privacy: .public) entries=\(max(0, entries), privacy: .public) selected=\(max(-1, selectedIndex), privacy: .public) success=\(successInt, privacy: .public)"
        )
    }

    private func flushIfNeeded(now: CFTimeInterval) {
        guard enabled else { return }
        let elapsed = now - intervalStart
        guard elapsed >= logIntervalSeconds else { return }

        let fpsDenominator = max(elapsed, 0.001)
        for displayId in displayAggregates.keys.sorted() {
            guard let agg = displayAggregates[displayId] else { continue }
            if agg.frameCount == 0,
               agg.drawableMissCount == 0,
               agg.callbackDurationsMs.isEmpty,
               agg.renderDurationsMs.isEmpty,
               agg.gpuDurationsMs.isEmpty {
                continue
            }

            let fps = Double(agg.frameCount) / fpsDenominator
            let callbackP50 = percentile(agg.callbackDurationsMs, p: 0.50)
            let callbackP95 = percentile(agg.callbackDurationsMs, p: 0.95)
            let renderP50 = percentile(agg.renderDurationsMs, p: 0.50)
            let renderP95 = percentile(agg.renderDurationsMs, p: 0.95)
            let gpuP50 = percentile(agg.gpuDurationsMs, p: 0.50)
            let gpuP95 = percentile(agg.gpuDurationsMs, p: 0.95)
            let gpuWallP95 = percentile(agg.gpuWallDurationsMs, p: 0.95)

            Log.perf.info(
                "frame d=\(displayId) fps=\(Self.fmt1(fps), privacy: .public) callback_ms(p50/p95)=\(Self.fmt2(callbackP50), privacy: .public)/\(Self.fmt2(callbackP95), privacy: .public) render_ms(p50/p95)=\(Self.fmt2(renderP50), privacy: .public)/\(Self.fmt2(renderP95), privacy: .public) gpu_ms(p50/p95)=\(Self.fmt2(gpuP50), privacy: .public)/\(Self.fmt2(gpuP95), privacy: .public) gpu_wall_p95=\(Self.fmt2(gpuWallP95), privacy: .public) drawable_miss=\(agg.drawableMissCount)"
            )
        }

        if pollExecutedCount > 0 || pollSkippedCount > 0 {
            let pollP50 = percentile(pollDurationsMs, p: 0.50)
            let pollP95 = percentile(pollDurationsMs, p: 0.95)
            let windowsP95 = percentile(pollWindowCounts, p: 0.95)
            let reasons = pollReasonCounts
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            let exec = self.pollExecutedCount
            let skip = self.pollSkippedCount

            Log.perf.info(
                "poll interval_ms=\(Self.fmtMs(elapsed * 1000), privacy: .public) exec=\(exec) skip=\(skip) duration_ms(p50/p95)=\(Self.fmt2(pollP50), privacy: .public)/\(Self.fmt2(pollP95), privacy: .public) windows_p95=\(Self.fmt1(windowsP95), privacy: .public) reasons=\(reasons, privacy: .public)"
            )
        }

        resetInterval(now: now)
    }

    private func resetInterval(now: CFTimeInterval) {
        intervalStart = now
        displayAggregates.removeAll(keepingCapacity: true)
        pollDurationsMs.removeAll(keepingCapacity: true)
        pollWindowCounts.removeAll(keepingCapacity: true)
        pollExecutedCount = 0
        pollSkippedCount = 0
        pollReasonCounts.removeAll(keepingCapacity: true)
    }

    private func appendCapped(_ values: inout [Double], _ cap: Int, _ value: Double) {
        values.append(value)
        if values.count > cap {
            values.removeFirst(values.count - cap)
        }
    }

    private func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let n = sorted.count
        let rank = Int((Double(n - 1) * p).rounded(.toNearestOrAwayFromZero))
        let idx = min(max(rank, 0), n - 1)
        return sorted[idx]
    }

    private static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }

    private static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private static func fmtMs(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
