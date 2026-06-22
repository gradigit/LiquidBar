import AppKit
import Foundation

enum WindowPresentationKey {
    static func make(bundleId: String, title: String, appName: String) -> String {
        let bundle = normalize(bundleId)
        let originalTitle = normalize(title.isEmpty ? appName : title)
        let app = normalize(appName)
        return "window:\(bundle)|\(app)|\(originalTitle)"
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

enum PresentationColorPalette {
    struct Entry: Sendable, Equatable {
        let name: String
        let hex: String
    }

    static let entries: [Entry] = [
        Entry(name: "Blue", hex: "#4A90E2"),
        Entry(name: "Teal", hex: "#2EC4B6"),
        Entry(name: "Green", hex: "#34C759"),
        Entry(name: "Yellow", hex: "#FFD166"),
        Entry(name: "Orange", hex: "#FF9F0A"),
        Entry(name: "Red", hex: "#FF453A"),
        Entry(name: "Pink", hex: "#FF5AC8"),
        Entry(name: "Purple", hex: "#AF52DE"),
        Entry(name: "Gray", hex: "#8E8E93"),
    ]

    static func normalizedHex(_ value: String?) -> String? {
        guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6,
              raw.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(raw.uppercased())"
    }

    static func color(from hex: String?, alpha: CGFloat = 0.24) -> NSColor? {
        guard let normalized = normalizedHex(hex) else { return nil }
        let raw = String(normalized.dropFirst())
        guard let value = UInt32(raw, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat(value & 0xff) / 255.0
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
