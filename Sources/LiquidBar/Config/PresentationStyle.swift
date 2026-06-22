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

    static func hexString(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.genericRGB) ?? color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = Int((min(max(rgb.redComponent, 0), 1) * 255).rounded())
        let green = Int((min(max(rgb.greenComponent, 0), 1) * 255).rounded())
        let blue = Int((min(max(rgb.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

enum SystemIndicatorColorPalette {
    static func overrideHex(for metric: SystemIndicatorMetric, config: Config) -> String? {
        switch metric {
        case .cpu:
            return config.systemIndicatorCpuColorHex
        case .gpu:
            return config.systemIndicatorGpuColorHex
        case .ram:
            return config.systemIndicatorRamColorHex
        case .thermal:
            return config.systemIndicatorThermalColorHex
        }
    }

    static func defaultHex(for metric: SystemIndicatorMetric) -> String {
        PresentationColorPalette.hexString(from: defaultColor(for: metric, severity: 0.2)) ?? "#4A90E2"
    }

    static func accentColor(for metric: SystemIndicatorMetric, severity: Float, config: Config) -> NSColor {
        if let color = PresentationColorPalette.color(from: overrideHex(for: metric, config: config), alpha: 1) {
            return color
        }
        return defaultColor(for: metric, severity: severity)
    }

    static func defaultColor(for metric: SystemIndicatorMetric, severity: Float) -> NSColor {
        switch metric {
        case .cpu:
            return NSColor(calibratedRed: 0.36, green: 0.68, blue: 1.0, alpha: 1)
        case .gpu:
            return NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.35, alpha: 1)
        case .ram:
            return NSColor(calibratedRed: 0.38, green: 0.84, blue: 0.58, alpha: 1)
        case .thermal:
            let heat = CGFloat(min(max(severity, 0), 1))
            return NSColor(
                calibratedRed: 0.82 + 0.18 * heat,
                green: 0.72 - 0.38 * heat,
                blue: 0.32 - 0.16 * heat,
                alpha: 1
            )
        }
    }
}
