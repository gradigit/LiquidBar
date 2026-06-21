import Foundation

#if DEBUG

@MainActor
enum TestWindowList {
    private struct CacheKey: Equatable {
        var path: String
        var modificationDate: Date?
        var fileSize: Int?
    }

    struct Root: Codable {
        var windows: [Window]
    }

    struct Window: Codable {
        var id: UInt32
        var bundleId: String
        var appName: String
        var title: String
        var isHidden: Bool
        var isMinimized: Bool
        var monitorId: UInt32
        var bounds: Bounds
    }

    struct Bounds: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private static var cachedKey: CacheKey?
    private static var cachedWindows: [WindowInfo]?

    static func load(from url: URL) -> [WindowInfo]? {
        do {
            let key = try cacheKey(for: url)
            if cachedKey == key, let cachedWindows {
                return cachedWindows
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let root = try decoder.decode(Root.self, from: data)
            let windows = root.windows.map { w in
                WindowInfo(
                    id: WindowId(w.id),
                    bundleId: BundleId(w.bundleId),
                    appName: w.appName,
                    title: w.title,
                    isHidden: w.isHidden,
                    isMinimized: w.isMinimized,
                    monitorId: MonitorId(w.monitorId),
                    bounds: WindowBounds(
                        x: w.bounds.x,
                        y: w.bounds.y,
                        width: w.bounds.width,
                        height: w.bounds.height
                    )
                )
            }
            cachedKey = key
            cachedWindows = windows
            return windows
        } catch {
            Log.window.error("Failed to load test windows from \(url.path, privacy: .public): \(error)")
            return nil
        }
    }

    static func clearCacheForTests() {
        cachedKey = nil
        cachedWindows = nil
    }

    private static func cacheKey(for url: URL) throws -> CacheKey {
        let standardizedURL = url.standardizedFileURL
        let values = try standardizedURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ])
        return CacheKey(
            path: standardizedURL.path,
            modificationDate: values.contentModificationDate,
            fileSize: values.fileSize
        )
    }
}

#endif
