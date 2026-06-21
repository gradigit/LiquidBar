import Foundation

enum LauncherActionTarget: Equatable {
    case application(bundleId: String)
    case url(String)
    case none
}

enum LauncherActionResolver {
    static func target(for config: Config) -> LauncherActionTarget {
        switch config.launcherAction {
        case .spotlight:
            return .application(bundleId: "com.apple.Spotlight")
        case .raycast:
            return .url("raycast://")
        case .alfred:
            return .url("alfred://")
        case .customUrl:
            guard let raw = config.launcherCustomUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return .none
            }
            return .url(raw)
        }
    }
}
