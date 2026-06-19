import Foundation

struct SwitcherHotkeySession: Equatable {
    enum State: Equatable {
        case idle
        case active
        case cancelled
        case committed
    }

    private(set) var token: UInt64 = 0
    private(set) var state: State = .idle
    private(set) var usesReleaseCommit: Bool = false

    var shouldSchedulePrimaryCommit: Bool {
        !usesReleaseCommit
    }

    mutating func configure(usesReleaseCommit: Bool) {
        self.usesReleaseCommit = usesReleaseCommit
        if !usesReleaseCommit {
            state = .idle
        }
    }

    @discardableResult
    mutating func beginSession() -> UInt64 {
        token &+= 1
        state = usesReleaseCommit ? .active : .idle
        return token
    }

    @discardableResult
    mutating func noteVisiblePress(hasEntries: Bool) -> Bool {
        guard hasEntries else { return false }
        if usesReleaseCommit {
            state = .active
        }
        return true
    }

    func canCommitOnRelease() -> Bool {
        usesReleaseCommit && state == .active
    }

    @discardableResult
    mutating func finish(commitSelection: Bool) -> UInt64 {
        if usesReleaseCommit {
            state = commitSelection ? .committed : .cancelled
        } else {
            state = .idle
        }
        token &+= 1
        return token
    }

    mutating func unregister() {
        token &+= 1
        state = .idle
        usesReleaseCommit = false
    }

    func isCurrentToken(_ candidate: UInt64) -> Bool {
        token == candidate
    }
}
