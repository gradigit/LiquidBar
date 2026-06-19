import Foundation

// MARK: - Newtypes

struct WindowId: Hashable, Sendable, CustomStringConvertible {
    let raw: UInt32

    init(_ raw: UInt32) {
        self.raw = raw
    }

    var description: String { "\(raw)" }
}

struct MonitorId: Hashable, Sendable, CustomStringConvertible {
    let raw: UInt32

    init(_ raw: UInt32 = 0) {
        self.raw = raw
    }

    var description: String { "\(raw)" }
}

struct BundleId: Hashable, Sendable, CustomStringConvertible {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var description: String { raw }
}

// MARK: - WindowBounds

struct WindowBounds: Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}

// MARK: - Display Assignment

extension WindowBounds {
    var center: (x: Double, y: Double) {
        (x: x + width / 2.0, y: y + height / 2.0)
    }

    func containsPoint(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    func intersectionArea(with other: WindowBounds) -> Double {
        let ix1 = max(x, other.x)
        let iy1 = max(y, other.y)
        let ix2 = min(x + width, other.x + other.width)
        let iy2 = min(y + height, other.y + other.height)

        let iw = max(0.0, ix2 - ix1)
        let ih = max(0.0, iy2 - iy1)
        return iw * ih
    }
}

enum DisplayAssignment {
    /// Pick the most likely display for a window based on geometry.
    /// We prefer maximum intersection area, then center-point containment, then nearest screen.
    static func monitorId(
        for windowBounds: WindowBounds,
        screens: [(displayId: UInt32, bounds: WindowBounds)]
    ) -> MonitorId {
        guard !screens.isEmpty else { return MonitorId(0) }

        // 1) Max intersection area.
        var best: (displayId: UInt32, area: Double)? = nil
        best = nil
        for screen in screens {
            let area = windowBounds.intersectionArea(with: screen.bounds)
            if best == nil || area > best!.area {
                best = (screen.displayId, area)
            }
        }
        if let best, best.area > 0 {
            return MonitorId(best.displayId)
        }

        // 2) Center point containment.
        let c = windowBounds.center
        for screen in screens {
            if screen.bounds.containsPoint(x: c.x, y: c.y) {
                return MonitorId(screen.displayId)
            }
        }

        // 3) Nearest screen center (for off-screen windows).
        var nearest: (displayId: UInt32, dist2: Double)? = nil
        for screen in screens {
            let sc = screen.bounds.center
            let dx = sc.x - c.x
            let dy = sc.y - c.y
            let d2 = dx * dx + dy * dy
            if nearest == nil || d2 < nearest!.dist2 {
                nearest = (screen.displayId, d2)
            }
        }
        return MonitorId(nearest?.displayId ?? screens[0].displayId)
    }
}

// MARK: - WindowInfo

struct WindowInfo: Sendable {
    let id: WindowId
    let bundleId: BundleId
    let appName: String
    let title: String
    let isHidden: Bool
    let isMinimized: Bool
    let monitorId: MonitorId
    let bounds: WindowBounds
}

// MARK: - Constants

let systemApps: Set<String> = [
    "com.apple.dock",
    "com.apple.WindowServer",
    "com.apple.systemuiserver",
    "com.apple.notificationcenterui",
    "com.apple.controlcenter",
    "com.apple.Spotlight",
]

let maxWindows = 200
