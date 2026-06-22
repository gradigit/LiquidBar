import AppKit
import Testing
@testable import LiquidBar

@Suite("AXObserverService")
struct AXObserverServiceTests {
    @Test func testObservablePidsDedupeAndFilterOwnProcess() {
        let ownPid: pid_t = 100
        let windows: [[CFString: Any]] = [
            [
                kCGWindowOwnerPID as CFString: Int32(42),
                kCGWindowLayer as CFString: 0,
            ],
            [
                kCGWindowOwnerPID as CFString: Int32(42),
                kCGWindowLayer as CFString: 0,
            ],
            [
                kCGWindowOwnerPID as CFString: ownPid,
                kCGWindowLayer as CFString: 0,
            ],
            [
                kCGWindowOwnerPID as CFString: Int32(77),
                kCGWindowLayer as CFString: 25,
            ],
            [
                kCGWindowOwnerPID as CFString: Int32(88),
                kCGWindowOwnerName as CFString: "CursorUIViewService",
                kCGWindowLayer as CFString: 0,
            ],
        ]

        let pids = AXObserverService.observablePids(from: windows, ownPid: ownPid)

        #expect(pids == [42])
    }

    @Test func testParsePidAcceptsCommonCGWindowTypes() {
        #expect(AXObserverService.parsePid(Int32(42)) == 42)
        #expect(AXObserverService.parsePid(NSNumber(value: Int32(43))) == 43)
        #expect(AXObserverService.parsePid(Int(44)) == 44)
        #expect(AXObserverService.parsePid("not-a-pid") == nil)
    }

    @Test func testObserverBackoffDelaysAndThenAllowsRetry() {
        var backoff = AXObserverService.ObserverBackoffState(baseDelay: 2.0, maxDelay: 16.0)

        backoff.recordFailure(pid: 42, now: 100.0)

        #expect(backoff.failuresByPid[42]?.attempts == 1)
        #expect(backoff.isBackedOff(pid: 42, now: 101.9))
        #expect(!backoff.isBackedOff(pid: 42, now: 102.0))
        #expect(backoff.nextRetryDelay(now: 101.0) == 1.0)
    }

    @Test func testObserverBackoffDoublesAndCapsDelay() {
        var backoff = AXObserverService.ObserverBackoffState(baseDelay: 2.0, maxDelay: 5.0)

        backoff.recordFailure(pid: 42, now: 100.0)
        backoff.recordFailure(pid: 42, now: 102.0)
        backoff.recordFailure(pid: 42, now: 106.0)

        #expect(backoff.failuresByPid[42]?.attempts == 3)
        #expect(backoff.failuresByPid[42]?.nextRetryAt == 111.0)
    }

    @Test func testObserverBackoffClearsSuccessAndPrunesDeadPids() {
        var backoff = AXObserverService.ObserverBackoffState(baseDelay: 2.0, maxDelay: 16.0)

        backoff.recordFailure(pid: 42, now: 100.0)
        backoff.recordFailure(pid: 99, now: 100.0)
        backoff.prune(keeping: [7, 42])

        #expect(backoff.failuresByPid[42]?.attempts == 1)
        #expect(backoff.failuresByPid[99] == nil)

        backoff.recordSuccess(pid: 42)

        #expect(backoff.failuresByPid.isEmpty)
    }

    @Test func testNotificationReasonMapping() {
        #expect(AXObserverService.reason(for: kAXWindowCreatedNotification) == .windowCreated)
        #expect(AXObserverService.reason(for: kAXUIElementDestroyedNotification) == .windowDestroyed)
        #expect(AXObserverService.reason(for: kAXWindowMovedNotification) == .windowMoved)
        #expect(AXObserverService.reason(for: kAXWindowResizedNotification) == .windowResized)
        #expect(AXObserverService.reason(for: kAXWindowMiniaturizedNotification) == .windowMiniaturized)
        #expect(AXObserverService.reason(for: kAXWindowDeminiaturizedNotification) == .windowDeminiaturized)
        #expect(AXObserverService.reason(for: kAXFocusedWindowChangedNotification) == .focusChanged)
        #expect(AXObserverService.reason(for: kAXMainWindowChangedNotification) == .mainWindowChanged)
        #expect(AXObserverService.reason(for: kAXTitleChangedNotification) == .titleChanged)
        #expect(AXObserverService.reason(for: kAXApplicationHiddenNotification) == .applicationHidden)
        #expect(AXObserverService.reason(for: kAXApplicationShownNotification) == .applicationShown)
        #expect(AXObserverService.reason(for: "com.example.UnknownAXNotification") == .other)
    }

    @Test func testEventBatchInvalidationPolicy() {
        let geometryOnlyBatch = AXObserverService.EventBatch(
            reasons: [.windowMoved, .windowResized, .focusChanged, .titleChanged],
            sourcePids: [42],
            notifications: []
        )
        #expect(!geometryOnlyBatch.invalidatesEnumerationCaches)
        #expect(geometryOnlyBatch.triggersWindowAdjustmentCheck)

        let structuralBatch = AXObserverService.EventBatch(
            reasons: [.windowCreated],
            sourcePids: [42],
            notifications: []
        )
        #expect(structuralBatch.invalidatesEnumerationCaches)
        #expect(structuralBatch.triggersWindowAdjustmentCheck)

        let focusOnlyBatch = AXObserverService.EventBatch(
            reasons: [.focusChanged, .mainWindowChanged],
            sourcePids: [42],
            notifications: []
        )
        #expect(!focusOnlyBatch.invalidatesEnumerationCaches)
        #expect(!focusOnlyBatch.triggersWindowAdjustmentCheck)
    }
}
