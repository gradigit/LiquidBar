import Foundation

/// User-defined grouping of arbitrary windows ("tab groups").
///
/// Notes:
/// - Window IDs are `CGWindowID` values (aka `kCGWindowNumber`).
/// - A window can belong to at most one group at a time (enforced by helpers in `UserState`).
struct TabGroup: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var emoji: String?
    /// Optional hex color (e.g. "#34C759"). UI uses this for future styling.
    var colorHex: String?
    /// Member window IDs (CGWindowID).
    var windowIds: [UInt32]

    init(
        id: String = UUID().uuidString,
        name: String,
        emoji: String? = nil,
        colorHex: String? = nil,
        windowIds: [UInt32] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.windowIds = windowIds
    }
}

