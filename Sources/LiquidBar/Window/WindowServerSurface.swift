import CoreGraphics
import Darwin
import Foundation

struct WindowServerSurface: Equatable, Sendable {
    let pid: pid_t
    let windowId: UInt32
    let ownerName: String
    let title: String
    let layer: Int
    let frame: CGRect
    let isOnscreen: Bool

    init(
        pid: pid_t,
        windowId: UInt32,
        frame: CGRect,
        title: String = "",
        ownerName: String = "",
        layer: Int = 0,
        isOnscreen: Bool = false
    ) {
        self.pid = pid
        self.windowId = windowId
        self.ownerName = ownerName
        self.title = title
        self.layer = layer
        self.frame = frame
        self.isOnscreen = isOnscreen
    }

    init?(_ dict: [CFString: Any]) {
        guard let pid = Self.parsePid(dict[kCGWindowOwnerPID as CFString]),
              let windowId = WindowNumber.parse(dict[kCGWindowNumber as CFString]),
              let frame = Self.parseFrame(dict[kCGWindowBounds as CFString]) else {
            return nil
        }

        self.pid = pid
        self.windowId = windowId
        ownerName = dict[kCGWindowOwnerName as CFString] as? String ?? ""
        title = dict[kCGWindowName as CFString] as? String ?? ""
        layer = Self.parseInt(dict[kCGWindowLayer as CFString]) ?? 0
        self.frame = frame
        isOnscreen = Self.parseBool(dict[kCGWindowIsOnscreen as CFString]) ?? false
    }

    var bounds: WindowBounds {
        WindowBounds(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    static func surfaces(from windowList: [[CFString: Any]]) -> [WindowServerSurface] {
        windowList.compactMap(Self.init)
    }

    static func parsePid(_ value: Any?) -> pid_t? {
        if let pid = value as? pid_t { return pid }
        if let pid = value as? Int { return pid_t(clamping: pid) }
        if let pid = value as? Int64 { return pid_t(clamping: pid) }
        if let pid = value as? NSNumber { return pid.int32Value }
        return nil
    }

    static func parseInt(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int32 { return Int(v) }
        if let v = value as? Int64 { return Int(clamping: v) }
        if let v = value as? NSNumber { return v.intValue }
        return nil
    }

    static func parseBool(_ value: Any?) -> Bool? {
        if let v = value as? Bool { return v }
        if let v = value as? Int { return v != 0 }
        if let v = value as? NSNumber { return v.boolValue }
        return nil
    }

    static func parseFrame(_ value: Any?) -> CGRect? {
        if let dict = value as? NSDictionary {
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(dict, &rect) else { return nil }
            return rect
        }

        if let dict = value as? [String: Double] {
            return CGRect(
                x: dict["X"] ?? 0,
                y: dict["Y"] ?? 0,
                width: dict["Width"] ?? 0,
                height: dict["Height"] ?? 0
            )
        }

        if let dict = value as? [String: Any] {
            return CGRect(
                x: numericDouble(dict["X"]) ?? 0,
                y: numericDouble(dict["Y"]) ?? 0,
                width: numericDouble(dict["Width"]) ?? 0,
                height: numericDouble(dict["Height"]) ?? 0
            )
        }

        return nil
    }

    private static func numericDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? CGFloat { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
