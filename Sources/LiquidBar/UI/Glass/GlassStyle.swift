import Foundation

/// Background glass style selection.
enum GlassStyle: String, Codable, Sendable, CaseIterable {
    /// Public API: `NSGlassEffectView.Style.regular`.
    case publicRegular = "public_regular"
    /// Public API: `NSGlassEffectView.Style.clear`.
    case publicClear = "public_clear"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.publicClear.rawValue:
            self = .publicClear
        default:
            self = .publicRegular
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
