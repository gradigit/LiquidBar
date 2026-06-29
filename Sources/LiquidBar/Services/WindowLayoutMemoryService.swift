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
    }

    struct RestoreSummary: Equatable, Sendable {
        let reason: String
        let capturedWindowCount: Int
        let completedWindowCount: Int
        let restoredWindowCount: Int
        let remainingWindowCount: Int
    }

    struct CaptureSummary: Equatable, Sendable {
        let reason: String
        let capturedWindowCount: Int
        let replacedExistingSnapshot: Bool
    }

    private struct DisplayContext {
        let topology: DisplayTopology
        let uuidByDisplayId: [CGDirectDisplayID: String]
        let boundsByUUID: [String: CGRect]
    }

    private struct SnapshotBatch {
        let topology: DisplayTopology
        let totalWindowCount: Int
        var pendingWindows: [AccessibilityService.RestorableWindowSnapshot]
        let capturedAt: CFAbsoluteTime
    }

    private var snapshotBatch: SnapshotBatch?
    private let snapshotMaxAge: CFTimeInterval

    init(snapshotMaxAge: CFTimeInterval = 30 * 60) {
        self.snapshotMaxAge = snapshotMaxAge
    }

    @discardableResult
    func captureBeforeDisplayChange() -> CaptureSummary {
        let context = Self.currentDisplayContext()
        guard context.topology.displayCount > 1 else {
            // Preserve a useful multi-display snapshot across reconnect. A reconnect
            // begin event is often emitted while only the built-in display is active.
            return CaptureSummary(reason: "single_display", capturedWindowCount: 0, replacedExistingSnapshot: false)
        }

        let windows = AccessibilityService.captureRestorableWindowSnapshots(
            displayUUIDByDisplayId: context.uuidByDisplayId
        )
        guard !windows.isEmpty else {
            return CaptureSummary(reason: "no_windows", capturedWindowCount: 0, replacedExistingSnapshot: false)
        }

        let now = CFAbsoluteTimeGetCurrent()
        let replacesExisting = snapshotBatch != nil
        guard Self.shouldReplaceSnapshot(
            existingTopology: snapshotBatch?.topology,
            existingCapturedAt: snapshotBatch?.capturedAt,
            newTopology: context.topology,
            now: now,
            maxAge: snapshotMaxAge
        ) else {
            Log.event.debug("Window layout memory kept existing snapshot; new capture ignored windows=\(windows.count) displays=\(context.topology.displayCount)")
            return CaptureSummary(reason: "kept_existing", capturedWindowCount: windows.count, replacedExistingSnapshot: false)
        }

        snapshotBatch = SnapshotBatch(
            topology: context.topology,
            totalWindowCount: windows.count,
            pendingWindows: windows,
            capturedAt: now
        )
        Log.event.info("Window layout memory captured windows=\(windows.count) displays=\(context.topology.displayCount)")
        PerformanceMonitor.shared.recordDiagnosticSnapshot(
            "window_layout_memory_capture",
            minIntervalSeconds: 1.0
        ) {
            "windows=\(windows.count) displays=\(context.topology.displayCount)"
        }
        return CaptureSummary(
            reason: "captured",
            capturedWindowCount: windows.count,
            replacedExistingSnapshot: replacesExisting
        )
    }

    @discardableResult
    func restoreAfterDisplayChangeIfPossible() -> RestoreSummary {
        guard let batch = snapshotBatch else {
            return RestoreSummary(
                reason: "no_snapshot",
                capturedWindowCount: 0,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: 0
            )
        }

        let context = Self.currentDisplayContext()
        guard Self.shouldAttemptRestore(
            snapshotTopology: batch.topology,
            currentTopology: context.topology,
            capturedAt: batch.capturedAt,
            now: CFAbsoluteTimeGetCurrent(),
            maxAge: snapshotMaxAge
        ) else {
            return RestoreSummary(
                reason: "topology_mismatch_or_stale",
                capturedWindowCount: batch.totalWindowCount,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: batch.pendingWindows.count
            )
        }

        guard AXIsProcessTrusted() else {
            return RestoreSummary(
                reason: "accessibility_not_trusted",
                capturedWindowCount: batch.totalWindowCount,
                completedWindowCount: 0,
                restoredWindowCount: 0,
                remainingWindowCount: batch.pendingWindows.count
            )
        }

        var result = AccessibilityService.RestorableWindowRestoreBatchResult(completedSnapshots: [], restoredWindowCount: 0)
        PerformanceMonitor.shared.measureSegment("window_layout_memory_restore", thresholdMs: 120.0) {
            result = AccessibilityService.restoreWindowFrames(
                batch.pendingWindows,
                activeDisplayBoundsByUUID: context.boundsByUUID
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
                topology: batch.topology,
                totalWindowCount: batch.totalWindowCount,
                pendingWindows: remaining,
                capturedAt: batch.capturedAt
            )
        }

        if result.completedWindowCount > 0 {
            Log.event.info("Window layout memory restore pass completed=\(result.completedWindowCount) restored=\(result.restoredWindowCount) remaining=\(remaining.count) captured=\(batch.totalWindowCount)")
            PerformanceMonitor.shared.recordDiagnosticSnapshot(
                "window_layout_memory_restore",
                minIntervalSeconds: 1.0
            ) {
                "completed=\(result.completedWindowCount) restored=\(result.restoredWindowCount) remaining=\(remaining.count) captured=\(batch.totalWindowCount)"
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
        return RestoreSummary(
            reason: reason,
            capturedWindowCount: batch.totalWindowCount,
            completedWindowCount: result.completedWindowCount,
            restoredWindowCount: result.restoredWindowCount,
            remainingWindowCount: remaining.count
        )
    }

    func clear() {
        snapshotBatch = nil
    }

    nonisolated static func shouldAttemptRestore(
        snapshotTopology: DisplayTopology,
        currentTopology: DisplayTopology,
        capturedAt: CFAbsoluteTime,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval
    ) -> Bool {
        snapshotTopology == currentTopology && now - capturedAt <= maxAge
    }

    nonisolated static func shouldReplaceSnapshot(
        existingTopology: DisplayTopology?,
        existingCapturedAt: CFAbsoluteTime?,
        newTopology: DisplayTopology,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval
    ) -> Bool {
        guard let existingTopology, let existingCapturedAt else { return true }
        if now - existingCapturedAt > maxAge { return true }
        return newTopology.displayCount > existingTopology.displayCount
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
