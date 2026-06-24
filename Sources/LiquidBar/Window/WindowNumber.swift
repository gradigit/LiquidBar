import Foundation

enum WindowNumber {
    static func parse(_ rawValue: Any?) -> UInt32? {
        switch rawValue {
        case let n as UInt32:
            return valid(n)
        case let n as UInt64:
            return exactUnsigned(n)
        case let n as UInt:
            return exactUnsigned(UInt64(n))
        case let n as Int:
            return exactSigned(Int64(n))
        case let n as Int64:
            return exactSigned(n)
        case let n as Int32:
            return exactSigned(Int64(n))
        case let n as NSNumber:
            return parseNumber(n)
        default:
            return nil
        }
    }

    static func appKitWindowNumber(_ windowNumber: Int) -> UInt32? {
        exactSigned(Int64(windowNumber))
    }

    static func tag(_ tag: Int) -> UInt32? {
        exactSigned(Int64(tag))
    }

    private static func parseNumber(_ number: NSNumber) -> UInt32? {
        exactSigned(number.int64Value)
    }

    private static func exactSigned(_ value: Int64) -> UInt32? {
        guard value > 0, value <= Int64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    private static func exactUnsigned(_ value: UInt64) -> UInt32? {
        guard value > 0, value <= UInt64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    private static func valid(_ value: UInt32) -> UInt32? {
        value == 0 ? nil : value
    }
}
