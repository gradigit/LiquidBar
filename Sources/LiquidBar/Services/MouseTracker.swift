import os

@MainActor
final class MouseTracker {
    nonisolated(unsafe) static var _isDragging = OSAllocatedUnfairLock(initialState: false)

    static var isDragging: Bool {
        _isDragging.withLock { $0 }
    }

    static func setDragging(_ dragging: Bool) {
        _isDragging.withLock { $0 = dragging }
    }

    func start() {
        // Intentionally no global CGEvent tap.
        //
        // A session event tap requires Input Monitoring permission, which is
        // unexpected for a taskbar-style app. We only need drag state for our
        // own UI interactions, so NativeBarView drives this via setDragging(...).
    }

    func stop() {
        Self.setDragging(false)
    }

    #if DEBUG
    deinit {
        Log.ax.debug("MouseTracker deinit")
    }
    #endif
}
