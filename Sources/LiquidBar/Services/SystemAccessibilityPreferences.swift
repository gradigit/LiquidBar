import AppKit

/// Centralized access to macOS accessibility display preferences.
///
/// In UI tests, these can be overridden via environment variables to avoid
/// mutating global system settings:
/// - `LIQUIDBAR_TEST_REDUCE_TRANSPARENCY` ("1"/"0")
/// - `LIQUIDBAR_TEST_REDUCE_MOTION` ("1"/"0")
/// - `LIQUIDBAR_TEST_INCREASE_CONTRAST` ("1"/"0")
enum SystemAccessibilityPreferences {
    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_CONTROL"] == "1"
    }

    private static func envBool(_ key: String) -> Bool? {
        guard isUITestMode else { return nil }
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "1", "true", "yes", "y": return true
        case "0", "false", "no", "n": return false
        default: return nil
        }
    }

    static var reduceTransparency: Bool {
        envBool("LIQUIDBAR_TEST_REDUCE_TRANSPARENCY") ?? NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var reduceMotion: Bool {
        envBool("LIQUIDBAR_TEST_REDUCE_MOTION") ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var increaseContrast: Bool {
        envBool("LIQUIDBAR_TEST_INCREASE_CONTRAST") ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}

