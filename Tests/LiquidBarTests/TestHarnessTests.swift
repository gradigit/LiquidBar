import Testing
import Foundation
import AppKit
@testable import LiquidBar

@Suite("Test Harness", .serialized)
@MainActor
struct TestHarnessTests {
    @Test func testConfigDirectoryOverrideEnvVar() {
        let key = "LIQUIDBAR_CONFIG_DIR"
        let path = "/tmp/liquidbar-test-\(UUID().uuidString)"

        setenv(key, path, 1)
        defer { unsetenv(key) }

        #expect(Config.configDirectory.path == path)
        #expect(Config.configPath.path == "\(path)/config.json")
        #expect(Config.statePath.path == "\(path)/state.json")
    }

    @Test func testConfigLoadWritesDefaultsWhenMissing() throws {
        let key = "LIQUIDBAR_CONFIG_DIR"
        let root = URL(fileURLWithPath: "/tmp/liquidbar-config-\(UUID().uuidString)", isDirectory: true)

        setenv(key, root.path, 1)
        defer { unsetenv(key) }

        // Ensure the directory doesn't exist yet.
        try? FileManager.default.removeItem(at: root)

        let loaded = Config.load()
        #expect(loaded == Config())

        let data = try Data(contentsOf: Config.configPath)
        #expect(!data.isEmpty)
    }

    @Test func testConfigLoadWritesDefaultsWhenEmptyFile() throws {
        let key = "LIQUIDBAR_CONFIG_DIR"
        let root = URL(fileURLWithPath: "/tmp/liquidbar-config-\(UUID().uuidString)", isDirectory: true)

        setenv(key, root.path, 1)
        defer { unsetenv(key) }

        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Create an empty config.json; Config.load should back it up and write defaults.
        try Data().write(to: Config.configPath, options: .atomic)

        let loaded = Config.load()
        #expect(loaded == Config())

        let data = try Data(contentsOf: Config.configPath)
        #expect(!data.isEmpty)

        let children = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let backups = children.filter { $0.hasPrefix("config.json.bak-") }
        #expect(backups.count == 1)
    }

    @Test func testNativeBarViewAccessibilityIdentifiers() {
        let view = NativeBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        view.displayId = 123
        #expect(view.accessibilityIdentifier() == "liquidbar.taskbar.123")

        view.items = [
            .window(id: WindowId(42), bundleId: "com.fixture", title: "Fixture Window 1", appName: "Fixture", isHidden: false, isMinimized: false, screenId: 0),
            .pluginTile(id: "plugin:fixture:tile:spotify", providerId: "plugin:fixture:provider:media", title: "Spotify", icon: "sf:music.note", visualState: .active, screenId: 0),
            .pinnedApp(bundleId: "com.pinned.app", screenId: 0),
        ]
        view.itemRects = [
            (bundleId: "com.fixture", index: 0, rect: NSRect(x: 0, y: 0, width: 100, height: 30)),
            (bundleId: "plugin:fixture:provider:media", index: 1, rect: NSRect(x: 100, y: 0, width: 100, height: 30)),
            (bundleId: "com.pinned.app", index: 2, rect: NSRect(x: 200, y: 0, width: 100, height: 30)),
        ]

        let children = view.accessibilityChildren() as? [NSAccessibilityElement]
        #expect(children?.count == 3)
        #expect(children?[0].accessibilityIdentifier() == "liquidbar.item.window.42")
        #expect(children?[1].accessibilityIdentifier() == "liquidbar.item.plugin.plugin:fixture:tile:spotify")
        #expect(children?[2].accessibilityIdentifier() == "liquidbar.item.pinned.com.pinned.app")
    }
}
