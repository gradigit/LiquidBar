import AppKit
import ApplicationServices

/// AX-driven invalidation for window/app state changes.
///
/// One observer is installed per target app process. Notifications are coalesced
/// into a debounced callback so we don't flood the main run loop with refreshes.
@MainActor
final class AXObserverService {
    typealias EventHandler = @MainActor (EventBatch) -> Void

    enum EventReason: Hashable, Sendable {
        case windowCreated
        case windowDestroyed
        case windowMoved
        case windowResized
        case windowMiniaturized
        case windowDeminiaturized
        case focusChanged
        case mainWindowChanged
        case titleChanged
        case applicationHidden
        case applicationShown
        case other
    }

    struct EventBatch: Equatable, Sendable {
        let reasons: Set<EventReason>
        let sourcePids: Set<pid_t>
        let notifications: [String]

        var invalidatesEnumerationCaches: Bool {
            !reasons.isDisjoint(with: [
                .windowCreated,
                .windowDestroyed,
                .windowMiniaturized,
                .windowDeminiaturized,
                .applicationHidden,
                .applicationShown,
                .other,
            ])
        }

        var triggersWindowAdjustmentCheck: Bool {
            !reasons.isDisjoint(with: [
                .windowCreated,
                .windowMoved,
                .windowResized,
                .windowDeminiaturized,
                .applicationShown,
                .other,
            ])
        }
    }

    struct ObserverBackoffState {
        struct Failure: Equatable {
            let attempts: Int
            let nextRetryAt: CFAbsoluteTime
        }

        private(set) var failuresByPid: [pid_t: Failure] = [:]
        private let baseDelay: CFTimeInterval
        private let maxDelay: CFTimeInterval

        init(baseDelay: CFTimeInterval = 30.0, maxDelay: CFTimeInterval = 300.0) {
            self.baseDelay = baseDelay
            self.maxDelay = maxDelay
        }

        mutating func recordFailure(pid: pid_t, now: CFAbsoluteTime) {
            let attempts = (failuresByPid[pid]?.attempts ?? 0) + 1
            let shift = min(max(attempts - 1, 0), 8)
            let delay = min(maxDelay, baseDelay * CFTimeInterval(1 << shift))
            failuresByPid[pid] = Failure(
                attempts: attempts,
                nextRetryAt: now + delay
            )
        }

        mutating func recordSuccess(pid: pid_t) {
            failuresByPid.removeValue(forKey: pid)
        }

        mutating func prune(keeping wantedPids: Set<pid_t>) {
            failuresByPid = failuresByPid.filter { wantedPids.contains($0.key) }
        }

        func isBackedOff(pid: pid_t, now: CFAbsoluteTime) -> Bool {
            guard let failure = failuresByPid[pid] else { return false }
            return failure.nextRetryAt > now
        }

        func nextRetryDelay(now: CFAbsoluteTime) -> TimeInterval? {
            let next = failuresByPid.values.map(\.nextRetryAt).min()
            guard let next else { return nil }
            return max(0.0, next - now)
        }
    }

    private struct Entry {
        let observer: AXObserver
        let appElement: AXUIElement
        let notifications: [String]
    }

    private var entriesByPid: [pid_t: Entry] = [:]
    private var observerBackoff = ObserverBackoffState()
    private var onEvent: EventHandler?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.02
    private var pendingReasons: Set<EventReason> = []
    private var pendingSourcePids: Set<pid_t> = []
    private var pendingNotifications: [String] = []
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var isStarted = false
    private var reconcileWorkItem: DispatchWorkItem?
    private let maxObserverAddsPerPass = 1
    private let batchReconcileDelay: TimeInterval = 0.25
    private let minimumReconcileDelay: TimeInterval = 0.25
    private let axMessagingTimeout: Float = 0.05

    private static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXTitleChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    func start(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
        if isStarted { return }
        isStarted = true
        refreshObservedApps()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingReasons.removeAll(keepingCapacity: true)
        pendingSourcePids.removeAll(keepingCapacity: true)
        pendingNotifications.removeAll(keepingCapacity: true)
        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil

        for pid in Array(entriesByPid.keys) {
            removeObserver(for: pid)
        }
        entriesByPid.removeAll()
        observerBackoff = ObserverBackoffState()
        onEvent = nil
        isStarted = false
    }

    /// Reconcile installed observers with currently running applications.
    func refreshObservedApps() {
        guard isStarted else { return }
        guard AXIsProcessTrusted() else {
            for pid in Array(entriesByPid.keys) {
                removeObserver(for: pid)
            }
            entriesByPid.removeAll()
            observerBackoff = ObserverBackoffState()
            return
        }

        let wantedPids = PerformanceMonitor.shared.measureSegment(
            "ax_observer_window_list",
            thresholdMs: 60.0
        ) {
            observablePids()
        }
        observerBackoff.prune(keeping: wantedPids)

        for pid in Array(entriesByPid.keys) where !wantedPids.contains(pid) {
            removeObserver(for: pid)
        }

        let missing = wantedPids.subtracting(entriesByPid.keys).sorted()
        guard !missing.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let retryableMissing = missing.filter { !observerBackoff.isBackedOff(pid: $0, now: now) }
        guard !retryableMissing.isEmpty else {
            if let delay = observerBackoff.nextRetryDelay(now: now) {
                scheduleReconcile(after: delay)
            }
            return
        }

        var attempted = 0
        for pid in retryableMissing {
            attempted += 1
            let added = PerformanceMonitor.shared.measureSegment(
                "ax_observer_add",
                thresholdMs: 80.0,
                details: "pid=\(pid)"
            ) {
                addObserver(for: pid)
            }
            if added {
                observerBackoff.recordSuccess(pid: pid)
            } else {
                observerBackoff.recordFailure(pid: pid, now: now)
            }
            if attempted >= maxObserverAddsPerPass {
                break
            }
        }

        if retryableMissing.count > attempted {
            scheduleReconcile(after: batchReconcileDelay)
        } else if let delay = observerBackoff.nextRetryDelay(now: CFAbsoluteTimeGetCurrent()) {
            scheduleReconcile(after: delay)
        }
    }

    private func scheduleReconcile(after delay: TimeInterval) {
        reconcileWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshObservedApps()
        }
        reconcileWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(minimumReconcileDelay, delay), execute: work)
    }

    private func observablePids() -> Set<pid_t> {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return []
        }

        return Self.observablePids(from: windowList, ownPid: ownPid)
    }

    nonisolated static func observablePids(from windowList: [[CFString: Any]], ownPid: pid_t) -> Set<pid_t> {
        var pids: Set<pid_t> = []
        pids.reserveCapacity(windowList.count)

        for dict in windowList {
            if let layer = parseInt(dict[kCGWindowLayer as CFString]), layer != 0 {
                continue
            }
            let ownerName = dict[kCGWindowOwnerName as CFString] as? String
            guard let pid = parsePid(dict[kCGWindowOwnerPID as CFString]),
                  shouldObserve(pid: pid, ownPid: ownPid, ownerName: ownerName) else {
                continue
            }
            pids.insert(pid)
        }

        return pids
    }

    nonisolated static func shouldObserve(pid: pid_t, ownPid: pid_t) -> Bool {
        shouldObserve(pid: pid, ownPid: ownPid, ownerName: nil)
    }

    nonisolated static func shouldObserve(pid: pid_t, ownPid: pid_t, ownerName: String?) -> Bool {
        guard pid > 0, pid != ownPid else { return false }
        guard let ownerName else { return true }
        return !isIgnoredSystemUIOwner(ownerName)
    }

    private nonisolated static func isIgnoredSystemUIOwner(_ ownerName: String) -> Bool {
        switch ownerName {
        case "CursorUIViewService",
             "TextInputMenuAgent",
             "TextInputSwitcher",
             "TextInputUIMacHelper":
            return true
        default:
            return false
        }
    }

    nonisolated static func parsePid(_ value: Any?) -> pid_t? {
        if let pid = value as? pid_t { return pid }
        if let pid = value as? Int { return pid_t(clamping: pid) }
        if let pid = value as? Int64 { return pid_t(clamping: pid) }
        if let pid = value as? NSNumber { return pid.int32Value }
        return nil
    }

    private nonisolated static func parseInt(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int32 { return Int(v) }
        if let v = value as? Int64 { return Int(clamping: v) }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }

    private func addObserver(for pid: pid_t) -> Bool {
        var rawObserver: AXObserver?
        let createErr = AXObserverCreate(pid, liquidBarAXObserverCallback, &rawObserver)
        guard createErr == .success, let observer = rawObserver else { return false }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        var registered: [String] = []
        registered.reserveCapacity(Self.notifications.count)

        for note in Self.notifications {
            let err = AXObserverAddNotification(observer, appElement, note as CFString, refcon)
            switch err {
            case .success, .notificationAlreadyRegistered:
                registered.append(note)
            case .notificationUnsupported, .cannotComplete, .apiDisabled:
                continue
            default:
                continue
            }
        }

        guard !registered.isEmpty else { return false }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        entriesByPid[pid] = Entry(
            observer: observer,
            appElement: appElement,
            notifications: registered
        )
        return true
    }

    private func removeObserver(for pid: pid_t) {
        guard let entry = entriesByPid.removeValue(forKey: pid) else { return }

        for note in entry.notifications {
            _ = AXObserverRemoveNotification(entry.observer, entry.appElement, note as CFString)
        }

        let source = AXObserverGetRunLoopSource(entry.observer)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    nonisolated static func reason(for notification: String) -> EventReason {
        switch notification {
        case kAXWindowCreatedNotification:
            return .windowCreated
        case kAXUIElementDestroyedNotification:
            return .windowDestroyed
        case kAXWindowMovedNotification:
            return .windowMoved
        case kAXWindowResizedNotification:
            return .windowResized
        case kAXWindowMiniaturizedNotification:
            return .windowMiniaturized
        case kAXWindowDeminiaturizedNotification:
            return .windowDeminiaturized
        case kAXFocusedWindowChangedNotification:
            return .focusChanged
        case kAXMainWindowChangedNotification:
            return .mainWindowChanged
        case kAXTitleChangedNotification:
            return .titleChanged
        case kAXApplicationHiddenNotification:
            return .applicationHidden
        case kAXApplicationShownNotification:
            return .applicationShown
        default:
            return .other
        }
    }

    nonisolated func handleNotification(_ notification: String, element: AXUIElement) {
        // The callback may come from AX run loop plumbing outside actor isolation.
        // Coalesce updates on the main actor.
        var pid: pid_t = 0
        let sourcePid: pid_t? = AXUIElementGetPid(element, &pid) == .success && pid > 0 ? pid : nil
        let reason = Self.reason(for: notification)
        Task { @MainActor [weak self] in
            self?.scheduleDebouncedEvent(
                reason: reason,
                sourcePid: sourcePid,
                notification: notification
            )
        }
    }

    private func scheduleDebouncedEvent(
        reason: EventReason,
        sourcePid: pid_t?,
        notification: String
    ) {
        pendingReasons.insert(reason)
        if let sourcePid {
            pendingSourcePids.insert(sourcePid)
        }
        pendingNotifications.append(notification)

        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = EventBatch(
                reasons: self.pendingReasons,
                sourcePids: self.pendingSourcePids,
                notifications: self.pendingNotifications
            )
            self.pendingReasons.removeAll(keepingCapacity: true)
            self.pendingSourcePids.removeAll(keepingCapacity: true)
            self.pendingNotifications.removeAll(keepingCapacity: true)
            self.onEvent?(batch)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }
}

private func liquidBarAXObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    _ = observer
    guard let refcon else { return }
    let service = Unmanaged<AXObserverService>.fromOpaque(refcon).takeUnretainedValue()
    service.handleNotification(notification as String, element: element)
}
