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

    private enum CaptureMode {
        case displayChange
        case stableRefresh
    }

    private var snapshotBatch: SnapshotBatch?
    private let snapshotMaxAge: CFTimeInterval
    private var lastRestoreTopology: DisplayTopology?
    private var lastRestoreTopologyObservedAt: CFAbsoluteTime = 0

    init(snapshotMaxAge: CFTimeInterval = 30 * 60) {
        self.snapshotMaxAge = snapshotMaxAge
    }

    @discardableResult
    func captureBeforeDisplayChange() -> CaptureSummary {
        captureCurrentLayout(mode: .displayChange)
    }

    @discardableResult
    func refreshStableSnapshot() -> CaptureSummary {
        captureCurrentLayout(mode: .stableRefresh)
    }

    func noteDisplayChangeStarted() {
        lastRestoreTopology = nil
        lastRestoreTopologyObservedAt = 0
    }

    private func captureCurrentLayout(mode: CaptureMode) -> CaptureSummary {
        let context = Self.currentDisplayContext()
        guard context.topology.displayCount > 1 else {
            // Preserve a useful multi-display snapshot across reconnect. A reconnect
            // begin event is often emitted while only the built-in display is active.
            return CaptureSummary(reason: "single_display", capturedWindowCount: 0, replacedExistingSnapshot: false)
        }

        let windows = AccessibilityService.captureRestorableWindowSnapshots(
            displayUUIDByDisplayId: context.uuidByDisplayId,
            displayBoundsByUUID: context.boundsByUUID
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
            maxAge: snapshotMaxAge,
            allowsSameDisplaySetReplacement: mode == .stableRefresh
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
    func restoreAfterDisplayChangeIfPossible(
        minStableDuration: CFTimeInterval = 0
    ) -> RestoreSummary {
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
        let now = CFAbsoluteTimeGetCurrent()
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
                    capturedWindowCount: batch.totalWindowCount,
                    completedWindowCount: 0,
                    restoredWindowCount: 0,
                    remainingWindowCount: batch.pendingWindows.count
                )
            }
        }

        guard Self.shouldAttemptRestore(
            snapshotTopology: batch.topology,
            currentTopology: context.topology,
            capturedAt: batch.capturedAt,
            now: now,
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
        if result.completedWindowCount == 0 {
            PerformanceMonitor.shared.recordDiagnosticSnapshot(
                "window_layout_memory_restore",
                minIntervalSeconds: 1.0
            ) {
                "reason=\(reason) completed=0 restored=0 remaining=\(remaining.count) captured=\(batch.totalWindowCount)"
            }
            Log.event.debug("Window layout memory restore pass reason=\(reason) remaining=\(remaining.count) captured=\(batch.totalWindowCount)")
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
        noteDisplayChangeStarted()
    }

    nonisolated static func shouldAttemptRestore(
        snapshotTopology: DisplayTopology,
        currentTopology: DisplayTopology,
        capturedAt: CFAbsoluteTime,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval
    ) -> Bool {
        guard now - capturedAt <= maxAge else { return false }
        let snapshotDisplayUUIDs = snapshotTopology.displayUUIDs
        guard !snapshotDisplayUUIDs.isEmpty else { return false }
        guard snapshotDisplayUUIDs.isSubset(of: currentTopology.displayUUIDs) else { return false }

        let currentDisplaysByUUID = Dictionary(
            currentTopology.displays.map { ($0.uuid, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
        for snapshotDisplay in snapshotTopology.displays {
            guard let currentFrame = currentDisplaysByUUID[snapshotDisplay.uuid],
                  displayFramesAreCompatible(snapshotDisplay.frame, currentFrame) else {
                return false
            }
        }
        return true
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
        newTopology: DisplayTopology,
        now: CFAbsoluteTime,
        maxAge: CFTimeInterval,
        allowsSameDisplaySetReplacement: Bool = false
    ) -> Bool {
        guard let existingTopology, let existingCapturedAt else { return true }
        if now - existingCapturedAt > maxAge { return true }
        if newTopology.displayCount > existingTopology.displayCount { return true }
        if allowsSameDisplaySetReplacement, newTopology.displayCount > 1 { return true }
        return false
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
