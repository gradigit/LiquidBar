import Foundation

enum WindowSurfaceClassifier {
    private static let minimumUsableDimension = 2.0
    private static let minimumUsableArea = 4.0
    private static let compactWidth = 180.0
    private static let compactHeight = 96.0
    private static let compactArea = 48_000.0

    static func hasUsableGeometry(_ bounds: WindowBounds) -> Bool {
        let width = max(0.0, bounds.width)
        let height = max(0.0, bounds.height)
        return width >= minimumUsableDimension &&
            height >= minimumUsableDimension &&
            (width * height) >= minimumUsableArea
    }

    static func needsAXSurfaceValidation(_ info: WindowInfo) -> Bool {
        isCompactSurface(info.bounds)
    }

    static func shouldRejectWithoutAXValidation(_ info: WindowInfo) -> Bool {
        isCompactSurface(info.bounds) && info.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isCompactSurface(_ bounds: WindowBounds) -> Bool {
        let width = max(0.0, bounds.width)
        let height = max(0.0, bounds.height)
        let area = width * height

        if width < compactWidth || height < compactHeight {
            return true
        }

        return area < compactArea && (width < 420.0 || height < 160.0)
    }
}
