import AppKit

@MainActor
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    private(set) var revision: UInt64 = 0

    init() {
        cache.countLimit = 50
    }

    private func store(_ image: NSImage, forKey key: NSString) -> NSImage {
        cache.setObject(image, forKey: key)
        revision &+= 1
        return image
    }

    func getIcon(bundleId: String) -> NSImage? {
        let key = bundleId as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Built-in SF Symbols: "sf:<symbol_name>"
        if bundleId.hasPrefix("sf:") {
            let symbolName = String(bundleId.dropFirst(3))
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let configured = symbol.withSymbolConfiguration(.init(pointSize: 18, weight: .regular)) ?? symbol
                let size = NSSize(width: 48, height: 48)

                // Tint to white for the taskbar surface; retained icon layers use image contents directly.
                let img = NSImage(size: size, flipped: false) { rect in
                    NSColor.white.setFill()
                    NSBezierPath(rect: rect).fill()
                    configured.draw(
                        in: rect,
                        from: .zero,
                        operation: .destinationIn,
                        fraction: 1.0,
                        respectFlipped: false,
                        hints: [.interpolation: NSImageInterpolation.high]
                    )
                    return true
                }

                return store(img, forKey: key)
            }
            return nil
        }

        // File / folder icons: "file:/absolute/path"
        if bundleId.hasPrefix("file:") {
            let path = String(bundleId.dropFirst(5))
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 48, height: 48)
            return store(icon, forKey: key)
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        return store(icon, forKey: key)
    }

    func clearCache() {
        cache.removeAllObjects()
        revision &+= 1
    }

    #if DEBUG
    deinit {
        Log.memory.debug("IconCache deinit")
    }
    #endif
}
