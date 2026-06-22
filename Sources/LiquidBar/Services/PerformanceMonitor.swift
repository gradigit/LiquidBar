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
    private var segmentDurationsMs: [String: [Double]] = [:]
    private var lastStallLogAtByKey: [String: CFTimeInterval] = [:]
    private var lastDiagnosticLogAtByKey: [String: CFTimeInterval] = [:]
    private var configDevDiagnosticsEnabled = false
    private var didLogDevDiagnosticsEnabled = false

    private let maxSamples = 512
    private let pollStallThresholdMs = 120.0
    private let segmentStallThresholdMs = 60.0
    private let stallLogCooldownSeconds: CFTimeInterval = 5.0
    private let envDevDiagnosticsEnabled = PerformanceMonitor.envBool("LIQUIDBAR_DEV_DIAGNOSTICS") ||
        PerformanceMonitor.envBool("LIQUIDBAR_DEBUG_PERF")

    private init() {}

    var isEnabled: Bool { enabled }
    var isCollecting: Bool { enabled || devDiagnosticsEnabled }
    var isDevDiagnosticsEnabled: Bool { devDiagnosticsEnabled }
    var isGPUFeedbackEnabled: Bool { enabled && gpuTimingEnabled }

    private var devDiagnosticsEnabled: Bool {
        envDevDiagnosticsEnabled || configDevDiagnosticsEnabled
    }

    func apply(config: Config) {
        let nextEnabled = config.performanceLoggingEnabled
        let nextDevDiagnostics = config.performanceHangDiagnosticsEnabled
        let nextGPU = config.performanceGpuTimingEnabled
        let nextInterval = max(0.25, Double(config.performanceLogIntervalMs) / 1000.0)

        let changed =
            nextEnabled != enabled
            || nextGPU != gpuTimingEnabled
            || abs(nextInterval - logIntervalSeconds) > 0.001
        let diagnosticsChanged = nextDevDiagnostics != configDevDiagnosticsEnabled

        enabled = nextEnabled
        configDevDiagnosticsEnabled = nextDevDiagnostics
        gpuTimingEnabled = nextGPU
        logIntervalSeconds = nextInterval

        if changed || diagnosticsChanged {
            resetInterval(now: CACurrentMediaTime())
        }

        if changed {
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

        if devDiagnosticsEnabled, !didLogDevDiagnosticsEnabled {
            didLogDevDiagnosticsEnabled = true
            let intervalMs = Self.fmtMs(self.logIntervalSeconds * 1000)
            let source = envDevDiagnosticsEnabled ? "env" : "preferences"
            Log.perf.info(
                "Developer diagnostics enabled (interval=\(intervalMs, privacy: .public)ms, source=\(source, privacy: .public))"
            )
        } else if !devDiagnosticsEnabled, didLogDevDiagnosticsEnabled {
            didLogDevDiagnosticsEnabled = false
            Log.perf.info("Developer diagnostics disabled")
        }
    }

    func recordPoll(durationMs: Double, enumerated: Bool, reason: String, windowCount: Int) {
        let safeDuration = max(0, durationMs)
        recordStallIfNeeded(
            key: "poll.\(reason)",
            name: "poll",
            durationMs: safeDuration,
            thresholdMs: pollStallThresholdMs,
            details: "reason=\(reason) enumerated=\(enumerated ? 1 : 0) windows=\(max(0, windowCount))"
        )

        guard isCollecting else { return }
        appendCapped(&pollDurationsMs, maxSamples, safeDuration)
        appendCapped(&pollWindowCounts, maxSamples, Double(max(0, windowCount)))
        if enumerated {
            pollExecutedCount += 1
        } else {
            pollSkippedCount += 1
        }
        pollReasonCounts[reason, default: 0] += 1
        flushIfNeeded(now: CACurrentMediaTime())
    }

    @discardableResult
    func measureSegment<T>(
        _ name: String,
        thresholdMs: Double? = nil,
        details: @autoclosure () -> String = "",
        _ work: () -> T
    ) -> T {
        let start = CACurrentMediaTime()
        let result = work()
        let durationMs = (CACurrentMediaTime() - start) * 1000.0
        recordSegmentDuration(name: name, durationMs: durationMs)
        recordStallIfNeeded(
            key: "segment.\(name)",
            name: name,
            durationMs: durationMs,
            thresholdMs: thresholdMs ?? segmentStallThresholdMs,
            details: details()
        )
        return result
    }

    func recordDiagnosticSnapshot(
        _ name: String,
        minIntervalSeconds: CFTimeInterval = 2.0,
        details: () -> String
    ) {
        guard devDiagnosticsEnabled else { return }

        let now = CACurrentMediaTime()
        if let last = lastDiagnosticLogAtByKey[name],
           now - last < minIntervalSeconds {
            return
        }
        lastDiagnosticLogAtByKey[name] = now

        let detailText = details()
        Log.perf.info("diag name=\(name, privacy: .public) \(detailText, privacy: .public)")
    }

    func recordFrame(displayId: CGDirectDisplayID, callbackDurationMs: Double, renderDurationMs: Double) {
        guard isCollecting else { return }
        var agg = displayAggregates[displayId, default: DisplayAggregate()]
        agg.frameCount += 1
        appendCapped(&agg.callbackDurationsMs, maxSamples, max(0, callbackDurationMs))
        appendCapped(&agg.renderDurationsMs, maxSamples, max(0, renderDurationMs))
        displayAggregates[displayId] = agg
        flushIfNeeded(now: CACurrentMediaTime())
    }

    func recordDrawableMiss(displayId: CGDirectDisplayID) {
        guard isCollecting else { return }
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
        guard isCollecting, gpuTimingEnabled else { return }
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
        guard isCollecting else { return }
        let safeAction = action.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let actionName = safeAction.isEmpty ? "unknown" : safeAction
        let successInt = success ? 1 : 0
        Log.perf.info(
            "switcher action=\(actionName, privacy: .public) duration_ms=\(Self.fmt2(max(0, durationMs)), privacy: .public) count=\(max(0, count), privacy: .public) direction=\(direction, privacy: .public) entries=\(max(0, entries), privacy: .public) selected=\(max(-1, selectedIndex), privacy: .public) success=\(successInt, privacy: .public)"
        )
    }

    func recordSwitcherAnimation(
        kind: String,
        durationMs: Double,
        frameCount: Int,
        frameP50Ms: Double?,
        frameP95Ms: Double?,
        frameMaxMs: Double?,
        retargetCount: Int,
        distancePoints: Double,
        success: Bool
    ) {
        guard isCollecting else { return }
        let kindName = Self.safeToken(kind, fallback: "unknown")
        let successInt = success ? 1 : 0
        Log.perf.info(
            "switcher_animation kind=\(kindName, privacy: .public) duration_ms=\(Self.fmt2(max(0, durationMs)), privacy: .public) frames=\(max(0, frameCount), privacy: .public) frame_ms(p50/p95/max)=\(Self.fmt2(frameP50Ms), privacy: .public)/\(Self.fmt2(frameP95Ms), privacy: .public)/\(Self.fmt2(frameMaxMs), privacy: .public) retargets=\(max(0, retargetCount), privacy: .public) distance=\(Self.fmt2(max(0, distancePoints)), privacy: .public) success=\(successInt, privacy: .public)"
        )
    }

    func recordThumbnailEvent(
        producer: String,
        tier: String,
        outcome: String,
        queueWaitMs: Double,
        captureMs: Double,
        totalMs: Double,
        byteCost: Int,
        success: Bool
    ) {
        guard isCollecting else { return }

        let producerName = Self.safeToken(producer, fallback: "unknown")
        let tierName = Self.safeToken(tier, fallback: "unknown")
        let outcomeName = Self.safeToken(outcome, fallback: "unknown")
        let successInt = success ? 1 : 0
        Log.perf.info(
            "thumbnail producer=\(producerName, privacy: .public) tier=\(tierName, privacy: .public) outcome=\(outcomeName, privacy: .public) queue_ms=\(Self.fmt2(max(0, queueWaitMs)), privacy: .public) capture_ms=\(Self.fmt2(max(0, captureMs)), privacy: .public) total_ms=\(Self.fmt2(max(0, totalMs)), privacy: .public) bytes=\(max(0, byteCost)) success=\(successInt, privacy: .public)"
        )
    }

    private func flushIfNeeded(now: CFTimeInterval) {
        guard isCollecting else { return }
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

        for name in segmentDurationsMs.keys.sorted() {
            guard let values = segmentDurationsMs[name], !values.isEmpty else { continue }
            let p50 = percentile(values, p: 0.50)
            let p95 = percentile(values, p: 0.95)
            let maxValue = values.max()
            Log.perf.info(
                "segment name=\(name, privacy: .public) count=\(values.count) duration_ms(p50/p95/max)=\(Self.fmt2(p50), privacy: .public)/\(Self.fmt2(p95), privacy: .public)/\(Self.fmt2(maxValue), privacy: .public)"
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
        segmentDurationsMs.removeAll(keepingCapacity: true)
    }

    private func appendCapped(_ values: inout [Double], _ cap: Int, _ value: Double) {
        values.append(value)
        if values.count > cap {
            values.removeFirst(values.count - cap)
        }
    }

    private func recordStallIfNeeded(
        key: String,
        name: String,
        durationMs: Double,
        thresholdMs: Double,
        details: String
    ) {
        guard durationMs >= thresholdMs else { return }

        let now = CACurrentMediaTime()
        if let last = lastStallLogAtByKey[key],
           now - last < stallLogCooldownSeconds {
            return
        }
        lastStallLogAtByKey[key] = now

        Log.perf.warning(
            "stall name=\(name, privacy: .public) duration_ms=\(Self.fmt2(durationMs), privacy: .public) threshold_ms=\(Self.fmt2(thresholdMs), privacy: .public) \(details, privacy: .public)"
        )
    }

    private func recordSegmentDuration(name: String, durationMs: Double) {
        guard isCollecting else { return }
        var values = segmentDurationsMs[name, default: []]
        appendCapped(&values, maxSamples, max(0, durationMs))
        segmentDurationsMs[name] = values
        flushIfNeeded(now: CACurrentMediaTime())
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

    private static func safeToken(_ raw: String, fallback: String) -> String {
        let filtered = raw.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return filtered.isEmpty ? fallback : filtered
    }

    private static func envBool(_ key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return false
        }
        switch raw.lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }
}
