import AppKit
import CoreGraphics

@MainActor
final class WindowLayoutMemoryService {
    struct RoundedRect: Equatable, Hashable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        init(_ rect: CGRect) {
            x = Int(rect.origin.x.rounded())
            y = Int(rect.origin.y.rounded())
            width = Int(rect.width.rounded())
            height = Int(rect.height.rounded())
        }
    }

    struct DisplaySignature: Equatable, Hashable, Sendable {
        let uuid: String
        let frame: RoundedRect
    }

    struct DisplayTopology: Equatable, Sendable {
        let displays: [DisplaySignature]

        var displayCount: Int { displays.count }
        var displayUUIDs: Set<String> { Set(displays.map(\.uuid)) }
    }

    struct RestoreSummary: Equatable, Sendable {
        let reason: String
        let snapshotID: UInt64?
        let snapshotAgeMilliseconds: Int
        let allowsCrossProcessFallback: Bool
        let capturedWindowCount: Int
        let completedWindowCount: Int
        let restoredWindowCount: Int
        let remainingWindowCount: Int
        let outcomeCounts: [AccessibilityService.WindowFrameRestoreOutcome: Int]
    }

    struct CaptureSummary: Equatable, Sendable {
        let reason: String
        let snapshotID: UInt64?
        let capturedWindowCount: Int
        let replacedExistingSnapshot: Bool
        let recoveryPending: Bool
    }

    enum RestoreEligibility: String, Equatable, Sendable {
        case eligible
        case emptySnapshotTopology = "empty_snapshot_topology"
        case missingDisplays = "missing_displays"
        case incompatibleDisplayGeometry = "incompatible_display_geometry"
    }

    private struct DisplayContext {
        let topology: DisplayTopology
        let uuidByDisplayId: [CGDirectDisplayID: String]
        let boundsByUUID: [String: CGRect]
    }

    private struct SnapshotBatch {
        let id: UInt64
        let topology: DisplayTopology
        let totalWindowCount: Int
        var pendingWindows: [AccessibilityService.RestorableWindowSnapshot]
        let capturedAt: CFAbsoluteTime
        var recoveryPending: Bool
    }

    private enum CaptureMode {
        case displayChange
        case stableRefresh

        var diagnosticName: String {
            switch self {
            case .displayChange: "display_change"
            case .stableRefresh: "stable_refresh"
            }
        }
    }

    private var snapshotBatch: SnapshotBatch?
    private let crossProcessFallbackMaxAge: CFTimeInterval
    private var nextSnapshotID: UInt64 = 0
    private var lastRestoreTopology: DisplayTopology?
    private var lastRestoreTopologyObservedAt: CFAbsoluteTime = 0

    init(crossProcessFallbackMaxAge: CFTimeInterval = 30 * 60) {
        self.crossProcessFallbackMaxAge = crossProcessFallbackMaxAge
    }

    @discardableResult
    func captureBeforeDisplayChange() -> CaptureSummary {
        let summary = captureCurrentLayout(mode: .displayChange)
        noteDisplayChangeStarted()
        return CaptureSummary(
            reason: summary.reason,
            snapshotID: summary.snapshotID,
            capturedWindowCount: summary.capturedWindowCount,
            replacedExistingSnapshot: summary.replacedExistingSnapshot,
            recoveryPending: snapshotBatch?.recoveryPending ?? summary.recoveryPending
        )
    }

    @discardableResult
    func refreshStableSnapshot() -> CaptureSummary {
        captureCurrentLayout(mode: .stableRefresh)
    }

    func noteDisplayChangeStarted() {
        lastRestoreTopology = nil
        lastRestoreTopologyObservedAt = 0
        snapshotBatch?.recoveryPending = true
    }

    private func captureCurrentLayout(mode: CaptureMode) -> CaptureSummary {
        let now = CFAbsoluteTimeGetCurrent()
        if case .stableRefresh = mode,
           let batch = snapshotBatch,
           batch.recoveryPending {
            // Keep the pre-change baseline intact and avoid another WindowServer
            // enumeration while a disconnected topology is waiting to return.
            return CaptureSummary(
                reason: "recovery_pending",
                snapshotID: batch.id,
                capturedWindowCount: 0,
                replacedExistingSnapshot: false,
                recoveryPending: true
            )
        }

        let context = Self.currentDisplayContext()
        guard context.topology.displayCount > 1 else {
            // Preserve a useful multi-display snapshot across reconnect. A reconnect
            // begin event is often emitted while only the built-in display is active.
            return CaptureSummary(
                reason: "single_display",
                snapshotID: snapshotBatch?.id,
                capturedWindowCount: 0,
                replacedExistingSnapshot: false,
                recoveryPending: snapshotBatch?.recoveryPending ?? false
            )
        }

        let windows = AccessibilityService.captureRestorableWindowSnapshots(
            displayUUIDByDisplayId: context.uuidByDisplayId,
            displayBoundsByUUID: context.boundsByUUID
        )
        guard !windows.isEmpty else {
            return CaptureSummary(
                reason: "no_windows",
                snapshotID: snapshotBatch?.id,
                capturedWindowCount: 0,
                replacedExistingSnapshot: false,
                recoveryPending: snapshotBatch?.recoveryPending ?? false
            )
        }

        let replacesExisting = snapshotBatch != nil
        guard Self.shouldReplaceSnapshot(
            existingTopology: snapshotBatch?.topology,
            existingCapturedAt: snapshotBatch?.capturedAt,
            existingRecoveryPending: snapshotBatch?.recoveryPending ?? false,
            newTopology: context.topology,
            now: now,
            maxAge: crossProcessFallbackMaxAge,
            allowsSameDisplaySetReplacement: true
        ) else {
            Log.event.debug("Window layout memory kept existing snapshot id=\(self.snapshotBatch?.id ?? 0) recovery_pending=\(self.snapshotBatch?.recoveryPending ?? false) new_windows=\(windows.count) displays=\(context.topology.displayCount)")
            return CaptureSummary(
                reason: "kept_existing",
                snapshotID: snapshotBatch?.id,
                capturedWindowCount: windows.count,
                replacedExistingSnapshot: false,
                recoveryPending: snapshotBatch?.recoveryPending ?? false
            )
        }

        nextSnapshotID &+= 1
        let snapshotID = nextSnapshotID
        let recoveryPending = mode == .displayChange
        snapshotBatch = SnapshotBatch(
            id: snapshotID,
            topology: context.topology,
            totalWindowCount: windows.count,
            pendingWindows: windows,
            capturedAt: now,
            recoveryPending: recoveryPending
        )
        Log.event.info("Window layout memory captured id=\(snapshotID) mode=\(mode.diagnosticName) recovery_pending=\(recoveryPending) windows=\(windows.count) displays=\(context.topology.displayCount)")
        PerformanceMonitor.shared.recordDiagnosticSnapshot(
            "window_layout_memory_capture",
            minIntervalSeconds: 1.0
        ) {
            "id=\(snapshotID) mode=\(mode.diagnosticName) recovery_pending=\(recoveryPending) windows=\(windows.count) topology=\(Self.topologyGeometrySummary(context.topology))"
        }
        return CaptureSummary(
            reason: "captured",
            snapshotID: snapshotID,
            capturedWindowCount: windows.count,
            replacedExistingSnapshot: replacesExisting,
            recoveryPending: recoveryPending
        )
    }

    @discardableResult
    func restoreAfterDisplayChangeIfPossible(
        minStableDuration: CFTimeInterval = 0
    ) -> RestoreSummary {
        guard let batch = snapshotBatch else {
            return RestoreSummary(
                reason: "no_snapshot",
                snapshotID: nil,
                snapshotAgeMilliseconds: 0,
                allowsCrossProcessFallback: false,
                capturedWindowCount: 0,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: 0,
                outcomeCounts: [:]
            )
        }

        let context = Self.currentDisplayContext()
        let now = CFAbsoluteTimeGetCurrent()
        let allowsCrossProcessFallback = Self.shouldAllowCrossProcessFallback(
            capturedAt: batch.capturedAt,
            now: now,
            maxAge: crossProcessFallbackMaxAge
        )
        if minStableDuration > 0 {
            let stability = Self.topologyStability(
                currentTopology: context.topology,
                previousTopology: lastRestoreTopology,
                previousObservedAt: lastRestoreTopologyObservedAt,
                now: now,
                minStableDuration: minStableDuration
            )
            lastRestoreTopology = context.topology
            lastRestoreTopologyObservedAt = stability.observedAt
            guard stability.isStable else {
                return RestoreSummary(
                    reason: "topology_unstable",
                    snapshotID: batch.id,
                    snapshotAgeMilliseconds: Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now),
                    allowsCrossProcessFallback: allowsCrossProcessFallback,
                    capturedWindowCount: batch.totalWindowCount,
                    completedWindowCount: 0,
                    restoredWindowCount: 0,
                    remainingWindowCount: batch.pendingWindows.count,
                    outcomeCounts: [:]
                )
            }
        }

        let eligibility = Self.restoreEligibility(
            snapshotTopology: batch.topology,
            currentTopology: context.topology,
            capturedAt: batch.capturedAt,
            now: now,
            maxAge: crossProcessFallbackMaxAge
        )
        guard eligibility == .eligible else {
            return RestoreSummary(
                reason: eligibility.rawValue,
                snapshotID: batch.id,
                snapshotAgeMilliseconds: Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now),
                allowsCrossProcessFallback: allowsCrossProcessFallback,
                capturedWindowCount: batch.totalWindowCount,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: batch.pendingWindows.count,
                outcomeCounts: [:]
            )
        }

        guard AXIsProcessTrusted() else {
            return RestoreSummary(
                reason: "accessibility_not_trusted",
                snapshotID: batch.id,
                snapshotAgeMilliseconds: Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now),
                allowsCrossProcessFallback: allowsCrossProcessFallback,
                capturedWindowCount: batch.totalWindowCount,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: batch.pendingWindows.count,
                outcomeCounts: [:]
            )
        }

        var result = AccessibilityService.RestorableWindowRestoreBatchResult(
            completedSnapshots: [],
            restoredWindowCount: 0,
            outcomeCounts: [:]
        )
        PerformanceMonitor.shared.measureSegment("window_layout_memory_restore", thresholdMs: 120.0) {
            result = AccessibilityService.restoreWindowFrames(
                batch.pendingWindows,
                activeDisplayBoundsByUUID: context.boundsByUUID,
                allowCrossProcessFallback: allowsCrossProcessFallback
            )
        }

        let remaining = Self.remainingSnapshots(
            batch.pendingWindows,
            afterCompleting: result.completedSnapshots
        )

        if remaining.isEmpty {
            snapshotBatch = nil
        } else if result.completedWindowCount > 0 {
            snapshotBatch = SnapshotBatch(
                id: batch.id,
                topology: batch.topology,
                totalWindowCount: batch.totalWindowCount,
                pendingWindows: remaining,
                capturedAt: batch.capturedAt,
                recoveryPending: true
            )
        }

        let outcomeSummary = Self.restoreOutcomeSummary(result.outcomeCounts)
        if result.completedWindowCount > 0 {
            Log.event.info("Window layout memory restore pass id=\(batch.id) completed=\(result.completedWindowCount) restored=\(result.restoredWindowCount) remaining=\(remaining.count) captured=\(batch.totalWindowCount) outcomes=\(outcomeSummary)")
            PerformanceMonitor.shared.recordDiagnosticSnapshot(
                "window_layout_memory_restore",
                minIntervalSeconds: 1.0
            ) {
                "id=\(batch.id) age_ms=\(Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now)) cross_process_fallback=\(allowsCrossProcessFallback) completed=\(result.completedWindowCount) restored=\(result.restoredWindowCount) remaining=\(remaining.count) captured=\(batch.totalWindowCount) outcomes=\(outcomeSummary)"
            }
        }
        let reason: String
        if remaining.isEmpty {
            reason = "restored"
        } else if result.completedWindowCount > 0 {
            reason = "partial"
        } else {
            reason = "attempted"
        }
        if result.completedWindowCount == 0 {
            PerformanceMonitor.shared.recordDiagnosticSnapshot(
                "window_layout_memory_restore",
                minIntervalSeconds: 1.0
            ) {
                "id=\(batch.id) age_ms=\(Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now)) cross_process_fallback=\(allowsCrossProcessFallback) reason=\(reason) completed=0 restored=0 remaining=\(remaining.count) captured=\(batch.totalWindowCount) outcomes=\(outcomeSummary)"
            }
            Log.event.debug("Window layout memory restore pass id=\(batch.id) reason=\(reason) remaining=\(remaining.count) captured=\(batch.totalWindowCount) outcomes=\(outcomeSummary)")
        }
        return RestoreSummary(
            reason: reason,
            snapshotID: batch.id,
            snapshotAgeMilliseconds: Self.ageMilliseconds(capturedAt: batch.capturedAt, now: now),
            allowsCrossProcessFallback: allowsCrossProcessFallback,
            capturedWindowCount: batch.totalWindowCount,
            completedWindowCount: result.completedWindowCount,
            restoredWindowCount: result.restoredWindowCount,
            remainingWindowCount: remaining.count,
            outcomeCounts: result.outcomeCounts
        )
    }

    func clear() {
        snapshotBatch = nil
        noteDisplayChangeStarted()
    }

    nonisolated static func shouldAttemptRestore(
        snapshotTopology: DisplayTopology,
        currentTopology: DisplayTopology,
        capturedAt: CFAbsoluteTime,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval
    ) -> Bool {
        restoreEligibility(
            snapshotTopology: snapshotTopology,
            currentTopology: currentTopology,
            capturedAt: capturedAt,
            now: now,
            maxAge: maxAge
        ) == .eligible
    }

    nonisolated static func restoreEligibility(
        snapshotTopology: DisplayTopology,
        currentTopology: DisplayTopology,
        capturedAt _: CFAbsoluteTime,
        now _: CFAbsoluteTime,
        maxAge _: CFTimeInterval
    ) -> RestoreEligibility {
        let snapshotDisplayUUIDs = snapshotTopology.displayUUIDs
        guard !snapshotDisplayUUIDs.isEmpty else { return .emptySnapshotTopology }
        guard snapshotDisplayUUIDs.isSubset(of: currentTopology.displayUUIDs) else { return .missingDisplays }

        let currentDisplaysByUUID = Dictionary(
            currentTopology.displays.map { ($0.uuid, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
        for snapshotDisplay in snapshotTopology.displays {
            guard let currentFrame = currentDisplaysByUUID[snapshotDisplay.uuid],
                  displayFramesAreCompatible(snapshotDisplay.frame, currentFrame) else {
                return .incompatibleDisplayGeometry
            }
        }
        return .eligible
    }

    nonisolated static func displayFramesAreCompatible(
        _ snapshot: RoundedRect,
        _ current: RoundedRect
    ) -> Bool {
        let snapshotWidth = Double(snapshot.width)
        let snapshotHeight = Double(snapshot.height)
        let currentWidth = Double(current.width)
        let currentHeight = Double(current.height)
        guard snapshotWidth > 1,
              snapshotHeight > 1,
              currentWidth > 1,
              currentHeight > 1 else {
            return false
        }

        let widthRatio = currentWidth / snapshotWidth
        let heightRatio = currentHeight / snapshotHeight
        guard widthRatio >= 0.40,
              widthRatio <= 2.50,
              heightRatio >= 0.40,
              heightRatio <= 2.50 else {
            return false
        }

        let snapshotAspect = snapshotWidth / snapshotHeight
        let currentAspect = currentWidth / currentHeight
        let aspectRatio = currentAspect / snapshotAspect
        return aspectRatio >= 0.88 && aspectRatio <= 1.12
    }

    nonisolated static func shouldReplaceSnapshot(
        existingTopology: DisplayTopology?,
        existingCapturedAt: CFAbsoluteTime?,
        existingRecoveryPending: Bool = false,
        newTopology: DisplayTopology,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval,
        allowsSameDisplaySetReplacement: Bool = false
    ) -> Bool {
        guard let existingTopology, let existingCapturedAt else { return true }
        if existingRecoveryPending { return false }
        if now - existingCapturedAt > maxAge { return true }
        if newTopology.displayCount > existingTopology.displayCount { return true }
        if allowsSameDisplaySetReplacement,
           newTopology.displayCount > 1,
           newTopology.displayUUIDs == existingTopology.displayUUIDs {
            return true
        }
        return false
    }

    nonisolated static func shouldDiscardSnapshotAfterFinalAttempt(reason: String) -> Bool {
        reason == RestoreEligibility.emptySnapshotTopology.rawValue
    }

    nonisolated static func shouldAllowCrossProcessFallback(
        capturedAt: CFAbsoluteTime,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval
    ) -> Bool {
        now - capturedAt <= maxAge
    }

    private nonisolated static func ageMilliseconds(
        capturedAt: CFAbsoluteTime,
        now: CFAbsoluteTime
    ) -> Int {
        Int(max(0, (now - capturedAt) * 1000).rounded())
    }

    nonisolated static func restoreOutcomeSummary(
        _ counts: [AccessibilityService.WindowFrameRestoreOutcome: Int]
    ) -> String {
        let values = AccessibilityService.WindowFrameRestoreOutcome.allCases.compactMap { outcome -> String? in
            guard let count = counts[outcome], count > 0 else { return nil }
            return "\(outcome.rawValue):\(count)"
        }
        return values.isEmpty ? "none" : values.joined(separator: ",")
    }

    private nonisolated static func topologyGeometrySummary(_ topology: DisplayTopology) -> String {
        topology.displays.map { display in
            let frame = display.frame
            return "\(frame.x),\(frame.y),\(frame.width)x\(frame.height)"
        }.joined(separator: "|")
    }

    nonisolated static func topologyStability(
        currentTopology: DisplayTopology,
        previousTopology: DisplayTopology?,
        previousObservedAt: CFAbsoluteTime,
        now: CFAbsoluteTime,
        minStableDuration: CFTimeInterval
    ) -> (isStable: Bool, observedAt: CFAbsoluteTime) {
        guard minStableDuration > 0 else {
            return (true, now)
        }
        guard currentTopology.displayCount > 0 else {
            return (false, now)
        }
        guard previousTopology == currentTopology, previousObservedAt > 0 else {
            return (false, now)
        }
        return (now - previousObservedAt >= minStableDuration, previousObservedAt)
    }

    nonisolated static func remainingSnapshots(
        _ pending: [AccessibilityService.RestorableWindowSnapshot],
        afterCompleting completed: [AccessibilityService.RestorableWindowSnapshot]
    ) -> [AccessibilityService.RestorableWindowSnapshot] {
        guard !pending.isEmpty, !completed.isEmpty else { return pending }
        var remaining = pending
        for snapshot in completed {
            if let index = remaining.firstIndex(of: snapshot) {
                remaining.remove(at: index)
            }
        }
        return remaining
    }

    private static func currentDisplayContext() -> DisplayContext {
        var signatures: [DisplaySignature] = []
        var uuidByDisplayId: [CGDirectDisplayID: String] = [:]
        var boundsByUUID: [String: CGRect] = [:]

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return DisplayContext(topology: DisplayTopology(displays: []), uuidByDisplayId: [:], boundsByUUID: [:])
        }

        var displayIds = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIds, &count) == .success else {
            return DisplayContext(topology: DisplayTopology(displays: []), uuidByDisplayId: [:], boundsByUUID: [:])
        }

        for displayId in displayIds.prefix(Int(count)) {
            guard let uuid = displayUUIDString(for: displayId) else { continue }
            let bounds = CGDisplayBounds(displayId)
            uuidByDisplayId[displayId] = uuid
            boundsByUUID[uuid] = bounds
            signatures.append(DisplaySignature(uuid: uuid, frame: RoundedRect(bounds)))
        }

        signatures.sort {
            if $0.uuid != $1.uuid { return $0.uuid < $1.uuid }
            if $0.frame.x != $1.frame.x { return $0.frame.x < $1.frame.x }
            if $0.frame.y != $1.frame.y { return $0.frame.y < $1.frame.y }
            if $0.frame.width != $1.frame.width { return $0.frame.width < $1.frame.width }
            return $0.frame.height < $1.frame.height
        }

        return DisplayContext(
            topology: DisplayTopology(displays: signatures),
            uuidByDisplayId: uuidByDisplayId,
            boundsByUUID: boundsByUUID
        )
    }

    private static func displayUUIDString(for displayId: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return text as String
    }
}
