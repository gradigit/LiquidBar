import Foundation

/// Stabilizes transient empty window lists during Space transitions.
///
/// Problem: During a three-finger swipe / Mission Control transition, macOS may
/// briefly report an empty on-screen window list. If we immediately commit that
/// empty list, the bar can flash blank and, in some failure modes, appear to
/// "lose" windows until a later recovery.
///
/// Design goals:
/// - Keep the bar visually stable during the transition window.
/// - Still allow a truly blank Space to become blank after a short settling period.
@MainActor
final class WindowListStabilizer {
    struct Config: Sendable {
        /// During this window after a space change, an empty list will return the
        /// last non-empty list (if any).
        var holdLastNonEmptyAfterSpaceChange: TimeInterval = 0.20
    }

    private let config: Config
    private var spaceChangeAt: CFAbsoluteTime? = nil
    private var lastNonEmpty: [WindowInfo] = []

    init(config: Config = Config()) {
        self.config = config
    }

    func noteSpaceChange(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        spaceChangeAt = now
    }

    func stabilize(observed: [WindowInfo], now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> [WindowInfo] {
        if !observed.isEmpty {
            lastNonEmpty = observed
            return observed
        }

        guard let spaceChangeAt else {
            return observed
        }

        if now - spaceChangeAt <= config.holdLastNonEmptyAfterSpaceChange, !lastNonEmpty.isEmpty {
            return lastNonEmpty
        }

        return observed
    }
}

