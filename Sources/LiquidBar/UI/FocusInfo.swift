import Foundation

/// Focus information used for "tabbed taskbar" sizing (focused item expanded, others collapsed).
struct FocusInfo: Sendable, Equatable {
    var windowId: UInt32?
    var bundleId: String?
    var tabGroupId: String?

    static let none = FocusInfo(windowId: nil, bundleId: nil, tabGroupId: nil)
}

