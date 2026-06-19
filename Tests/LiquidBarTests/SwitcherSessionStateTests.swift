@testable import LiquidBar
import Testing

@Suite("Switcher hotkey session state")
struct SwitcherSessionStateTests {
    @Test func releaseDrivenBeginSessionStartsActiveAndDisablesPrimaryTimerCommit() {
        var session = SwitcherHotkeySession()
        session.configure(usesReleaseCommit: true)

        let token = session.beginSession()

        #expect(token == 1)
        #expect(session.state == .active)
        #expect(!session.shouldSchedulePrimaryCommit)
    }

    @Test func nonReleaseDrivenSessionStaysIdleAndUsesPrimaryTimerCommit() {
        var session = SwitcherHotkeySession()
        session.configure(usesReleaseCommit: false)

        let token = session.beginSession()

        #expect(token == 1)
        #expect(session.state == .idle)
        #expect(session.shouldSchedulePrimaryCommit)
        #expect(!session.canCommitOnRelease())
    }

    @Test func cancelSuppressesLateReleaseCommit() {
        var session = SwitcherHotkeySession()
        session.configure(usesReleaseCommit: true)
        _ = session.beginSession()

        _ = session.finish(commitSelection: false)

        #expect(session.state == .cancelled)
        #expect(!session.canCommitOnRelease())
    }

    @Test func unregisterSuppressesLateReleaseCommitAndInvalidatesToken() {
        var session = SwitcherHotkeySession()
        session.configure(usesReleaseCommit: true)
        let activeToken = session.beginSession()

        session.unregister()

        #expect(session.state == .idle)
        #expect(!session.canCommitOnRelease())
        #expect(!session.isCurrentToken(activeToken))
    }

    @Test func duplicateReleaseIsNoOpAfterCommittedHide() {
        var session = SwitcherHotkeySession()
        session.configure(usesReleaseCommit: true)
        _ = session.beginSession()

        _ = session.finish(commitSelection: true)

        #expect(session.state == .committed)
        #expect(!session.canCommitOnRelease())
    }
}
