import ApplicationServices
@testable import LiquidBar
import Testing

@Suite("AccessibilityService focus entrypoint routing")
struct AccessibilityServiceFocusEntrypointTests {
    private struct UnmatchedCall: Equatable {
        let pid: pid_t
        let bundleId: String
        let windowId: UInt32
    }

    @MainActor
    @Test func publicFocusWindowRoutesAXMissIntoUnmatchedPath() {
        let targetWindowId: UInt32 = 42
        let expectedPID: pid_t = 123
        let expectedBundle = "com.apple.finder"

        final class Probe {
            var matchedCalls = 0
            var unmatchedCalls: [UnmatchedCall] = []
        }
        let probe = Probe()

        AccessibilityService.debugInstallFocusWindowRoutingHooks(
            .init(
                findOnScreenWindow: { windowId in
                    windowId == targetWindowId
                        ? .init(pid: expectedPID, bounds: .init(x: 10, y: 20, width: 30, height: 40), title: "Finder Target")
                        : nil
                },
                findOffScreenWindow: { _ in nil },
                bundleIdForPid: { _ in expectedBundle },
                createApplicationElement: { _ in AXUIElementCreateSystemWide() },
                copyWindows: { _ in nil },
                matchWindow: { _, _, _, _ in nil },
                focusMatched: { _, _, _, _, _ in
                    probe.matchedCalls += 1
                },
                focusUnmatched: { pid, bundleId, windowId in
                    probe.unmatchedCalls.append(.init(pid: pid, bundleId: bundleId, windowId: windowId))
                }
            )
        )
        defer { AccessibilityService.debugResetFocusWindowRoutingHooks() }

        AccessibilityService.focusWindow(windowId: targetWindowId)

        #expect(probe.matchedCalls == 0)
        #expect(probe.unmatchedCalls.count == 1)
        #expect(probe.unmatchedCalls[0].pid == expectedPID)
        #expect(probe.unmatchedCalls[0].bundleId == expectedBundle)
        #expect(probe.unmatchedCalls[0].windowId == targetWindowId)
    }

    @MainActor
    @Test func publicFocusWindowRoutesAXMatchIntoMatchedPath() {
        let targetWindowId: UInt32 = 7
        let expectedPID: pid_t = 222
        let expectedBundle = "com.google.Chrome"
        let fakeWindow = AXUIElementCreateSystemWide()

        final class Probe {
            var matchedCalls = 0
            var unmatchedCalls = 0
        }
        let probe = Probe()

        AccessibilityService.debugInstallFocusWindowRoutingHooks(
            .init(
                findOnScreenWindow: { windowId in
                    windowId == targetWindowId
                        ? .init(pid: expectedPID, bounds: .init(x: 1, y: 2, width: 3, height: 4), title: "Chrome Target")
                        : nil
                },
                findOffScreenWindow: { _ in nil },
                bundleIdForPid: { _ in expectedBundle },
                createApplicationElement: { _ in AXUIElementCreateSystemWide() },
                copyWindows: { _ in [fakeWindow] as CFArray },
                matchWindow: { _, _, _, _ in fakeWindow },
                focusMatched: { _, _, pid, bundleId, windowId in
                    probe.matchedCalls += 1
                    #expect(pid == expectedPID)
                    #expect(bundleId == expectedBundle)
                    #expect(windowId == targetWindowId)
                },
                focusUnmatched: { _, _, _ in
                    probe.unmatchedCalls += 1
                }
            )
        )
        defer { AccessibilityService.debugResetFocusWindowRoutingHooks() }

        AccessibilityService.focusWindow(windowId: targetWindowId)

        #expect(probe.matchedCalls == 1)
        #expect(probe.unmatchedCalls == 0)
    }
}
