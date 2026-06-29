import CoreGraphics
import Foundation

private let liquidBarDisplayReconfigurationCallback: CGDisplayReconfigurationCallBack = { displayId, flags, userInfo in
    guard let userInfo else { return }
    let observer = Unmanaged<DisplayReconfigurationObserver>.fromOpaque(userInfo).takeUnretainedValue()
    Task { @MainActor [weak observer] in
        observer?.handle(displayId: displayId, flags: flags)
    }
}

@MainActor
final class DisplayReconfigurationObserver {
    struct Event: Equatable {
        let displayId: CGDirectDisplayID
        let flags: CGDisplayChangeSummaryFlags

        var isBeginConfiguration: Bool {
            flags.contains(.beginConfigurationFlag)
        }
    }

    private let onEvent: (Event) -> Void
    private var isStarted = false

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        guard !isStarted else { return }
        let result = CGDisplayRegisterReconfigurationCallback(
            liquidBarDisplayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if result == .success {
            isStarted = true
        } else {
            Log.event.error("Failed to register display reconfiguration callback result=\(result.rawValue)")
        }
    }

    func stop() {
        guard isStarted else { return }
        CGDisplayRemoveReconfigurationCallback(
            liquidBarDisplayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        isStarted = false
    }

    fileprivate func handle(displayId: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard isStarted else { return }
        onEvent(Event(displayId: displayId, flags: flags))
    }

}
