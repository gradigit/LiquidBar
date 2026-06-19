import Testing
import Foundation
@testable import LiquidBar

@Suite("Plugins")
struct PluginManagerTests {
    @MainActor
    @Test func testDeterministicDiscoveryAndNamespacing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("liquidbar-plugin-tests-\(UUID().uuidString)", isDirectory: true)
        let pluginsDir = root.appendingPathComponent("Plugins", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        defer { try? fm.removeItem(at: root) }

        func writePlugin(id: String, folderName: String, apiVersion: Int, customItemsJSON: String) throws {
            let dir = pluginsDir.appendingPathComponent(folderName, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let manifest = """
            {
              "id": "\(id)",
              "name": "\(folderName)",
              "version": "1.0.0",
              "api_version": \(apiVersion),
              "custom_items": \(customItemsJSON)
            }
            """
            try manifest.data(using: .utf8)!.write(to: dir.appendingPathComponent("manifest.json"))
        }

        try writePlugin(
            id: "com.example.b",
            folderName: "BPlugin",
            apiVersion: 1,
            customItemsJSON: #"[{ "type": "text", "id": "t1", "text": "B" }]"#
        )
        try writePlugin(
            id: "com.example.a",
            folderName: "APlugin",
            apiVersion: 1,
            customItemsJSON: #"[{ "type": "text", "id": "t1", "text": "A" }]"#
        )

        let config = Config(pluginsEnabled: true)
        let mgr = PluginManager(baseDirectory: root)
        let plugins = mgr.loadPlugins(config: config)
        #expect(plugins.map(\.manifest.id) == ["com.example.a", "com.example.b"])

        let items = mgr.customItems(from: plugins)
        #expect(items.count == 2)
        guard items.count == 2 else { return }
        #expect(items[0].id == "plugin:com.example.a:t1")
        #expect(items[1].id == "plugin:com.example.b:t1")
    }

    @MainActor
    @Test func testDisabledPluginIsExcluded() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("liquidbar-plugin-tests-\(UUID().uuidString)", isDirectory: true)
        let pluginsDir = root.appendingPathComponent("Plugins", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pluginDir = pluginsDir.appendingPathComponent("P", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = """
        { "id": "com.example.p", "name": "P", "version": "1.0.0", "api_version": 1 }
        """
        try manifest.data(using: .utf8)!.write(to: pluginDir.appendingPathComponent("manifest.json"))

        let config = Config(pluginsEnabled: true, disabledPluginIds: ["com.example.p"])
        let mgr = PluginManager(baseDirectory: root)
        let plugins = mgr.loadPlugins(config: config)
        #expect(plugins.isEmpty)
    }

    @MainActor
    @Test func testUnsupportedAPIVersionIgnored() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("liquidbar-plugin-tests-\(UUID().uuidString)", isDirectory: true)
        let pluginsDir = root.appendingPathComponent("Plugins", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pluginDir = pluginsDir.appendingPathComponent("Bad", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = """
        { "id": "com.example.bad", "name": "Bad", "version": "1.0.0", "api_version": 999 }
        """
        try manifest.data(using: .utf8)!.write(to: pluginDir.appendingPathComponent("manifest.json"))

        let config = Config(pluginsEnabled: true)
        let mgr = PluginManager(baseDirectory: root)
        let plugins = mgr.loadPlugins(config: config)
        #expect(plugins.isEmpty)
    }

    @MainActor
    @Test func testTileAndProviderNamespacing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("liquidbar-plugin-tests-\(UUID().uuidString)", isDirectory: true)
        let pluginsDir = root.appendingPathComponent("Plugins", isDirectory: true)
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pluginDir = pluginsDir.appendingPathComponent("TilePlugin", isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "com.example.tile",
          "name": "Tile Plugin",
          "version": "1.0.0",
          "api_version": 1,
          "providers": [
            { "id": "media0", "kind": "media" }
          ],
          "tiles": [
            {
              "id": "spotify",
              "title": "Spotify",
              "icon": "sf:music.note",
              "provider_id": "media0",
              "visual_state": "active"
            }
          ]
        }
        """
        try manifest.data(using: .utf8)!.write(to: pluginDir.appendingPathComponent("manifest.json"))

        let config = Config(pluginsEnabled: true)
        let mgr = PluginManager(baseDirectory: root)
        let plugins = mgr.loadPlugins(config: config)
        #expect(plugins.count == 1)

        let tiles = mgr.tiles(from: plugins)
        #expect(tiles.count == 1)
        #expect(tiles[0].id == "plugin:com.example.tile:tile:spotify")
        #expect(tiles[0].providerId == "plugin:com.example.tile:provider:media0")
        #expect(tiles[0].visualState == .active)
    }
}
