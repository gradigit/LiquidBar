import Foundation

struct PluginManifest: Codable, Sendable, Equatable {
    struct Provider: Codable, Sendable, Equatable {
        var id: String
        /// Example: "media".
        var kind: String
        /// Transport strategy (`local` or `xpc`).
        var transport: String?
        /// Required when `transport == "xpc"`.
        var machServiceName: String?
    }

    struct Tile: Codable, Sendable, Equatable {
        var id: String
        var title: String
        var icon: String?
        /// Provider id declared in `providers`.
        var providerId: String?
        var visualState: PluginTileVisualState?
    }

    var id: String
    var name: String
    var version: String
    var apiVersion: Int
    var customItems: [CustomItem]?
    var providers: [Provider]?
    var tiles: [Tile]?
}

enum PluginTileVisualState: String, Codable, Sendable, CaseIterable {
    case idle
    case active
    case attention
}

@MainActor
final class PluginManager {
    static let supportedAPIVersions: Set<Int> = [1]
    private let baseDirectory: URL

    struct LoadedPlugin: Sendable, Equatable {
        var manifest: PluginManifest
        var path: URL
    }

    struct LoadedPluginTile: Sendable, Equatable {
        var id: String
        var pluginId: String
        var title: String
        var icon: String?
        var providerId: String?
        var visualState: PluginTileVisualState
    }

    init(baseDirectory: URL = Config.configDirectory) {
        self.baseDirectory = baseDirectory
    }

    func loadPlugins(config: Config) -> [LoadedPlugin] {
        guard config.pluginsEnabled else { return [] }

        let pluginsDir = baseDirectory.appendingPathComponent("Plugins", isDirectory: true)
        return loadPlugins(at: pluginsDir, disabledPluginIds: Set(config.disabledPluginIds))
    }

    func customItems(from plugins: [LoadedPlugin]) -> [CustomItem] {
        var out: [CustomItem] = []
        for p in plugins {
            guard let items = p.manifest.customItems, !items.isEmpty else { continue }
            out.append(contentsOf: items.map { Self.namespaceCustomItem($0, pluginId: p.manifest.id) })
        }
        return out
    }

    func tiles(from plugins: [LoadedPlugin]) -> [LoadedPluginTile] {
        var out: [LoadedPluginTile] = []
        for p in plugins {
            guard let tiles = p.manifest.tiles, !tiles.isEmpty else { continue }
            for tile in tiles {
                guard !tile.id.isEmpty else { continue }
                let namespacedTileId = "plugin:\(p.manifest.id):tile:\(tile.id)"
                let providerId = tile.providerId.map { "plugin:\(p.manifest.id):provider:\($0)" }
                out.append(LoadedPluginTile(
                    id: namespacedTileId,
                    pluginId: p.manifest.id,
                    title: tile.title.isEmpty ? tile.id : tile.title,
                    icon: tile.icon,
                    providerId: providerId,
                    visualState: tile.visualState ?? .idle
                ))
            }
        }
        out.sort { $0.id < $1.id }
        return out
    }

    // MARK: - Private

    private func loadPlugins(
        at pluginsDir: URL,
        disabledPluginIds: Set<String>
    ) -> [LoadedPlugin] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: pluginsDir.path, isDirectory: &isDir),
              isDir.boolValue else {
            return []
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: pluginsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Log.plugins.error("Failed to list plugins directory: \(pluginsDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var plugins: [LoadedPlugin] = []
        plugins.reserveCapacity(sorted.count)

        for url in sorted {
            let manifestURL: URL
            if url.pathExtension.lowercased() == "json" {
                manifestURL = url
            } else {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                manifestURL = url.appendingPathComponent("manifest.json")
            }

            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let manifest = try decoder.decode(PluginManifest.self, from: data)

                guard !manifest.id.isEmpty else {
                    Log.plugins.warning("Ignoring plugin with empty id: \(manifestURL.path, privacy: .public)")
                    continue
                }

                guard Self.supportedAPIVersions.contains(manifest.apiVersion) else {
                    Log.plugins.warning("Ignoring plugin \(manifest.id, privacy: .public): unsupported apiVersion=\(manifest.apiVersion)")
                    continue
                }

                if disabledPluginIds.contains(manifest.id) {
                    continue
                }

                plugins.append(LoadedPlugin(manifest: manifest, path: manifestURL))
            } catch {
                Log.plugins.error("Failed to load plugin manifest: \(manifestURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        // Deterministic, de-duped by id.
        plugins.sort { $0.manifest.id < $1.manifest.id }
        var seen: Set<String> = []
        var result: [LoadedPlugin] = []
        result.reserveCapacity(plugins.count)
        for p in plugins {
            if seen.contains(p.manifest.id) {
                Log.plugins.warning("Duplicate plugin id found (keeping first): \(p.manifest.id, privacy: .public)")
                continue
            }
            seen.insert(p.manifest.id)
            result.append(p)
        }
        return result
    }

    private static func namespaceCustomItem(_ item: CustomItem, pluginId: String) -> CustomItem {
        func ns(_ id: String) -> String { "plugin:\(pluginId):\(id)" }
        switch item {
        case .spacer(let id, let width):
            return .spacer(id: ns(id), width: width)
        case .text(let id, let text):
            return .text(id: ns(id), text: text)
        case .link(let id, let title, let url, let icon):
            return .link(id: ns(id), title: title, url: url, icon: icon)
        case .folder(let id, let title, let path, let icon):
            return .folder(id: ns(id), title: title, path: path, icon: icon)
        }
    }
}
