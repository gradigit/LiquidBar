import Foundation

enum LiveApplySettings {
    static let defaultsKey = "com.liquidbar.live_apply_enabled"
    static let didChangeNotification = Notification.Name("com.liquidbar.live_apply_changed")

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        // Default is manual Apply (false) to preserve existing behavior.
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
