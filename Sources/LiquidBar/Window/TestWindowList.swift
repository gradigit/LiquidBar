import Foundation

#if DEBUG

enum TestWindowList {
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

    static func load(from url: URL) -> [WindowInfo]? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let root = try decoder.decode(Root.self, from: data)
            return root.windows.map { w in
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
        } catch {
            Log.window.error("Failed to load test windows from \(url.path, privacy: .public): \(error)")
            return nil
        }
    }
}

#endif

