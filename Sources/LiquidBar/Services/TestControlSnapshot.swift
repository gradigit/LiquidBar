import Foundation
import AppKit

#if DEBUG

/// JSON-serializable debug snapshot for UI tests.
///
/// Goal: allow UI tests to assert layout invariants (visual vs hit rects, hover alignment,
/// window properties) without relying solely on pixel diffs.
struct LiquidBarDebugSnapshot: Codable {
    struct DebugConfig: Codable {
        var itemSizing: String
        var iconSize: Int
        var fontSize: Int
        var iconsOnly: Bool
        var windowDisplayMode: String
        var pinnedAppsScope: String
        var showHiddenApps: Bool
        var adjustWindowsForTaskbar: Bool
        var tabbedTaskbarEnabled: Bool
        var windowTabGroupsEnabled: Bool
        var previewsEnabled: Bool
    }

    struct Rect: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        init(_ rect: NSRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }
    }

    struct Point: Codable, Equatable {
        var x: Double
        var y: Double

        init(_ point: NSPoint) {
            x = point.x
            y = point.y
        }

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    struct Item: Codable {
        var index: Int
        var accessibilityId: String
        var kind: String
        var bundleId: String
        var windowId: UInt32?
        var title: String?
        var displayTitle: String
        var visualRect: Rect?
        var hitRect: Rect?
    }

    struct Panel: Codable {
        var displayId: UInt32
        var frame: Rect
        var barBounds: Rect
        var sidebarPresentation: String?
        var windowIsOpaque: Bool
        var windowAlphaValue: Double
        var windowBackgroundAlpha: Double?
        var hoverRect: Rect?
        /// Cursor position in bar-local native coordinates (origin top-left), when available.
        var cursorPoint: Point?
        /// Cursor position normalized to the hover rect ([0,1] range). `nil` if no hover/cursor.
        var hoverCursorNormalized: Point?
        var previewVisible: Bool
        var previewWindowId: UInt32?
        var groupPreviewVisible: Bool
        var groupPreviewKey: String?
        var tabGroupOverlayVisible: Bool
        var tabGroupOverlayId: String?
        var pluginCardVisible: Bool
        var pluginCardTileId: String?
        var items: [Item]
    }

    var timestamp: Double
    var config: DebugConfig
    var panels: [Panel]
}

#endif
