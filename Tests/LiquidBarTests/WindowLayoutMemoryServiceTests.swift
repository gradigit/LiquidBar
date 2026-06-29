import CoreGraphics
import Testing
@testable import LiquidBar

@Suite("Window Layout Memory")
struct WindowLayoutMemoryServiceTests {
    @Test func restoreRequiresSameTopologyAndFreshSnapshot() {
        let displayA = WindowLayoutMemoryService.DisplaySignature(
            uuid: "display-a",
            frame: WindowLayoutMemoryService.RoundedRect(CGRect(x: 0, y: 0, width: 1440, height: 900))
        )
        let displayB = WindowLayoutMemoryService.DisplaySignature(
            uuid: "display-b",
            frame: WindowLayoutMemoryService.RoundedRect(CGRect(x: 1440, y: 0, width: 2560, height: 1440))
        )
        let snapshotTopology = WindowLayoutMemoryService.DisplayTopology(displays: [displayA, displayB])
        let singleDisplayTopology = WindowLayoutMemoryService.DisplayTopology(displays: [displayA])

        #expect(WindowLayoutMemoryService.shouldAttemptRestore(
            snapshotTopology: snapshotTopology,
            currentTopology: snapshotTopology,
            capturedAt: 100,
            now: 120,
            maxAge: 60
        ))
        #expect(!WindowLayoutMemoryService.shouldAttemptRestore(
            snapshotTopology: snapshotTopology,
            currentTopology: singleDisplayTopology,
            capturedAt: 100,
            now: 120,
            maxAge: 60
        ))
        #expect(!WindowLayoutMemoryService.shouldAttemptRestore(
            snapshotTopology: snapshotTopology,
            currentTopology: snapshotTopology,
            capturedAt: 100,
            now: 200,
            maxAge: 60
        ))
    }

    @Test func frameToleranceSkipsAlreadyRestoredWindows() {
        let target = CGRect(x: 100, y: 200, width: 900, height: 600)

        #expect(AccessibilityService.framesAreClose(
            target,
            CGRect(x: 102, y: 199, width: 901, height: 598),
            tolerance: 3
        ))
        #expect(!AccessibilityService.framesAreClose(
            target,
            CGRect(x: 108, y: 200, width: 900, height: 600),
            tolerance: 3
        ))
    }

    @Test func freshSnapshotIsProtectedFromIntermediateDisplayEvents() {
        let displayA = WindowLayoutMemoryService.DisplaySignature(
            uuid: "display-a",
            frame: WindowLayoutMemoryService.RoundedRect(CGRect(x: 0, y: 0, width: 1440, height: 900))
        )
        let displayB = WindowLayoutMemoryService.DisplaySignature(
            uuid: "display-b",
            frame: WindowLayoutMemoryService.RoundedRect(CGRect(x: 1440, y: 0, width: 2560, height: 1440))
        )
        let displayC = WindowLayoutMemoryService.DisplaySignature(
            uuid: "display-c",
            frame: WindowLayoutMemoryService.RoundedRect(CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        )
        let twoDisplayTopology = WindowLayoutMemoryService.DisplayTopology(displays: [displayA, displayB])
        let oneDisplayTopology = WindowLayoutMemoryService.DisplayTopology(displays: [displayA])
        let threeDisplayTopology = WindowLayoutMemoryService.DisplayTopology(displays: [displayA, displayB, displayC])

        #expect(!WindowLayoutMemoryService.shouldReplaceSnapshot(
            existingTopology: twoDisplayTopology,
            existingCapturedAt: 100,
            newTopology: twoDisplayTopology,
            now: 120,
            maxAge: 60
        ))
        #expect(!WindowLayoutMemoryService.shouldReplaceSnapshot(
            existingTopology: twoDisplayTopology,
            existingCapturedAt: 100,
            newTopology: oneDisplayTopology,
            now: 120,
            maxAge: 60
        ))
        #expect(WindowLayoutMemoryService.shouldReplaceSnapshot(
            existingTopology: oneDisplayTopology,
            existingCapturedAt: 100,
            newTopology: twoDisplayTopology,
            now: 120,
            maxAge: 60
        ))
        #expect(WindowLayoutMemoryService.shouldReplaceSnapshot(
            existingTopology: twoDisplayTopology,
            existingCapturedAt: 100,
            newTopology: twoDisplayTopology,
            now: 200,
            maxAge: 60
        ))
        #expect(WindowLayoutMemoryService.shouldReplaceSnapshot(
            existingTopology: twoDisplayTopology,
            existingCapturedAt: 100,
            newTopology: threeDisplayTopology,
            now: 120,
            maxAge: 60
        ))
    }

    @Test func partialRestoreKeepsUncompletedSnapshotsPending() {
        let first = makeSnapshot(windowId: 1)
        let second = makeSnapshot(windowId: 2)
        let third = makeSnapshot(windowId: 3)

        #expect(WindowLayoutMemoryService.remainingSnapshots(
            [first, second, third],
            afterCompleting: [second]
        ) == [first, third])
        #expect(WindowLayoutMemoryService.remainingSnapshots(
            [first, second],
            afterCompleting: []
        ) == [first, second])
    }

    private func makeSnapshot(windowId: UInt32) -> AccessibilityService.RestorableWindowSnapshot {
        AccessibilityService.RestorableWindowSnapshot(
            pid: 100,
            bundleId: "com.example.app",
            windowId: windowId,
            title: "Window \(windowId)",
            frame: CGRect(x: Int(windowId) * 10, y: 20, width: 800, height: 600),
            displayUUID: "display-a"
        )
    }
}
