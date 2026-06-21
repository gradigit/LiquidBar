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
        #expect(titles.contains("Pin to Taskbar"))
        #expect(titles.contains("Hide from Taskbar"))
        #expect(titles.contains("Preferences\u{2026}"))
        #expect(titles.contains("Reload config.json"))
        #expect(titles.contains("Quit LiquidBar"))
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
}
