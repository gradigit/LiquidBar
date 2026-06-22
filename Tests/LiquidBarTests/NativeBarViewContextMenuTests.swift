import AppKit
import Testing
@testable import LiquidBar

@Suite("NativeBarView Context Menu")
@MainActor
struct NativeBarViewContextMenuTests {
    @Test func emptyTaskbarShowsAppControls() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 12, y: 15))))
        let titles = Self.titles(in: menu)

        #expect(titles.contains("Preferences\u{2026}"))
        #expect(titles.contains("Reload config.json"))
        #expect(titles.contains("Quit LiquidBar"))
    }

    @Test func launcherItemShowsAppControls() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.items = [.launcher(screenId: 0)]
        view.itemRects = [
            (bundleId: "sf:magnifyingglass", index: 0, rect: NSRect(x: 0, y: 0, width: 44, height: 30)),
        ]

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 20, y: 15))))
        let titles = Self.titles(in: menu)

        #expect(titles == ["Preferences\u{2026}", "Reload config.json", "Quit LiquidBar"])
    }

    @Test func windowItemKeepsWindowControlsAndAddsAppControls() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.items = [
            .window(
                id: WindowId(42),
                bundleId: "com.fixture.window",
                title: "Fixture Window",
                appName: "Fixture",
                isHidden: false,
                isMinimized: false,
                screenId: 0
            ),
        ]
        view.itemRects = [
            (bundleId: "com.fixture.window", index: 0, rect: NSRect(x: 0, y: 0, width: 100, height: 30)),
        ]

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 20, y: 15))))
        let titles = Self.titles(in: menu)

        #expect(titles.contains("Close Window"))
        #expect(titles.contains("Rename Window\u{2026}"))
        #expect(titles.contains("Color Window"))
        #expect(titles.contains("Reset Window Title"))
        #expect(titles.contains("Pin to Taskbar"))
        #expect(titles.contains("Hide from Taskbar"))
        #expect(titles.contains("Preferences\u{2026}"))
        #expect(titles.contains("Reload config.json"))
        #expect(titles.contains("Quit LiquidBar"))
    }

    @Test func windowPresentationItemsDispatchActions() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.items = [
            .window(
                id: WindowId(42),
                bundleId: "com.fixture.window",
                title: "Fixture Window",
                appName: "Fixture",
                isHidden: false,
                isMinimized: false,
                screenId: 0
            ),
        ]
        view.itemRects = [
            (bundleId: "com.fixture.window", index: 0, rect: NSRect(x: 0, y: 0, width: 100, height: 30)),
        ]

        var actions: [(Int, ContextAction, String?)] = []
        view.onContextAction = { actions.append(($0, $1, $2)) }

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 20, y: 15))))
        try Self.perform(menu, title: "Rename Window\u{2026}")
        try Self.performSubmenu(menu, title: "Color Window", itemTitle: "Blue")
        try Self.perform(menu, title: "Reset Window Title")
        try Self.performSubmenu(menu, title: "Color Window", itemTitle: "Clear Window Color")

        #expect(actions.map { $0.1 } == [.renameWindow, .setWindowColor, .resetWindowTitle, .resetWindowColor])
        #expect(actions[1].2 == "#4A90E2")
    }

    @Test func tabGroupMenuIncludesColorControls() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        view.items = [
            .tabGroup(
                id: "work",
                representativeBundleId: "com.fixture.window",
                name: "Work",
                emoji: nil,
                windowCount: 2,
                isHidden: false,
                isMinimized: false,
                screenId: 0
            ),
        ]
        view.itemRects = [
            (bundleId: "com.fixture.window", index: 0, rect: NSRect(x: 0, y: 0, width: 100, height: 30)),
        ]

        var actions: [(Int, ContextAction, String?)] = []
        view.onContextAction = { actions.append(($0, $1, $2)) }

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 20, y: 15))))
        let titles = Self.titles(in: menu)

        #expect(titles.contains("Rename Tab Group\u{2026}"))
        #expect(titles.contains("Color Tab Group"))
        #expect(titles.contains("Delete Tab Group"))

        try Self.performSubmenu(menu, title: "Color Tab Group", itemTitle: "Purple")
        try Self.performSubmenu(menu, title: "Color Tab Group", itemTitle: "Clear Tab Group Color")

        #expect(actions.map { $0.1 } == [.setTabGroupColor, .setTabGroupColor])
        #expect(actions[0].2 == "#AF52DE")
        #expect(actions[1].2 == nil)
    }

    @Test func appContextItemsDispatchActions() throws {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        var actions: [AppContextAction] = []
        view.onAppContextAction = { actions.append($0) }

        let menu = try #require(view.menu(for: Self.rightClick(at: NSPoint(x: 12, y: 15))))
        try Self.perform(menu, title: "Preferences\u{2026}")
        try Self.perform(menu, title: "Reload config.json")
        try Self.perform(menu, title: "Quit LiquidBar")

        #expect(actions == [.openPreferences, .reloadConfig, .quit])
    }

    private static func rightClick(at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    private static func titles(in menu: NSMenu) -> [String] {
        menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
    }

    private static func perform(_ menu: NSMenu, title: String) throws {
        let item = try #require(menu.item(withTitle: title))
        let target = try #require(item.target)
        let action = try #require(item.action)
        _ = target.perform(action, with: item)
    }

    private static func performSubmenu(_ menu: NSMenu, title: String, itemTitle: String) throws {
        let item = try #require(menu.item(withTitle: title))
        let submenu = try #require(item.submenu)
        try perform(submenu, title: itemTitle)
    }
}
