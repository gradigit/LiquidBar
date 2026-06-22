enum MouseButton: Sendable {
    case left
    case middle
    case right
}

enum ContextAction: Int, Sendable {
    case close = 0
    case pin = 1
    case unpin = 2
    case blacklist = 3

    // Window tab groups (payload = groupId when needed)
    case createTabGroup = 10
    case addToTabGroup = 11
    case removeFromTabGroup = 12
    case renameTabGroup = 13
    case deleteTabGroup = 14
    case setTabGroupColor = 15

    // Custom items (payload = customItemId)
    case openCustomItem = 20
    case editCustomItem = 21
    case deleteCustomItem = 22

    // LiquidBar-only window presentation (payload = color hex when needed)
    case renameWindow = 40
    case setWindowColor = 41
    case resetWindowTitle = 42
    case resetWindowColor = 43
}

enum AppContextAction: Int, Sendable {
    case openPreferences = 30
    case reloadConfig = 31
    case quit = 32
}

enum Command: Sendable {
    case shutdown
    case refresh
    case click(screenId: UInt32, index: Int, button: MouseButton)
    case reorder(screenId: UInt32, from: Int, to: Int)
    case contextAction(screenId: UInt32, index: Int, action: ContextAction)
    case reloadConfig
}
