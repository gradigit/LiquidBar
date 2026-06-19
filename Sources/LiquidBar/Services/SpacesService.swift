import Foundation
import CoreGraphics
import ColorSync

final class SpacesService {
    struct CurrentSpaceInfo: Equatable, Sendable {
        static let desktopType = 0

        let key: String
        let type: Int
    }

    #if DEBUG
    /// UI-test hook: runtime override via DistributedNotificationCenter.
    /// When set, `fetchCurrentSpaceKeys` returns this value for all displays.
    @MainActor static var testSpaceIdOverride: String? = nil
    #endif

    init() {}

    /// Fetch current Space keys for the provided displays without blocking the UI.
    /// Completion runs on the main queue.
    @MainActor
    func fetchCurrentSpaceKeys(
        for displayIds: [CGDirectDisplayID],
        completion: @escaping @MainActor ([CGDirectDisplayID: String]) -> Void
    ) {
        fetchCurrentSpaceInfo(for: displayIds) { infoByDisplay in
            completion(infoByDisplay.mapValues(\.key))
        }
    }

    @MainActor
    func fetchCurrentSpaceInfo(
        for displayIds: [CGDirectDisplayID],
        completion: @escaping @MainActor ([CGDirectDisplayID: CurrentSpaceInfo]) -> Void
    ) {
        #if DEBUG
        if let override = Self.testSpaceIdOverride, !override.isEmpty {
            var out: [CGDirectDisplayID: CurrentSpaceInfo] = [:]
            out.reserveCapacity(displayIds.count)
            for did in displayIds {
                out[did] = CurrentSpaceInfo(key: override, type: CurrentSpaceInfo.desktopType)
            }
            completion(out)
            return
        }
        if let override = ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_SPACE_ID"],
           !override.isEmpty {
            var out: [CGDirectDisplayID: CurrentSpaceInfo] = [:]
            out.reserveCapacity(displayIds.count)
            for did in displayIds {
                out[did] = CurrentSpaceInfo(key: override, type: CurrentSpaceInfo.desktopType)
            }
            completion(out)
            return
        }
        #endif

        completion([:])
    }

    nonisolated static func currentSpaceInfo(
        for displayIds: [CGDirectDisplayID],
        displayUUIDByDisplayId: [CGDirectDisplayID: String],
        managedDisplaySpaces: [[String: Any]]
    ) -> [CGDirectDisplayID: CurrentSpaceInfo] {
        var currentByUUID: [String: CurrentSpaceInfo] = [:]
        currentByUUID.reserveCapacity(managedDisplaySpaces.count)

        for display in managedDisplaySpaces {
            guard let id = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let key = currentSpaceKey(from: current) else {
                continue
            }

            let type = currentSpaceType(from: current)
            currentByUUID[id] = CurrentSpaceInfo(key: key, type: type)
        }

        var out: [CGDirectDisplayID: CurrentSpaceInfo] = [:]
        out.reserveCapacity(displayIds.count)
        for did in displayIds {
            guard let uuid = displayUUIDByDisplayId[did],
                  let info = currentByUUID[uuid] else {
                continue
            }
            out[did] = info
        }
        return out
    }

    func copySpacesForWindow(windowId: CGWindowID) -> [UInt64] {
        []
    }

    private static func displayUUIDString(displayId: CGDirectDisplayID) -> String? {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayId) else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        let str = CFUUIDCreateString(nil, uuid)
        return str as String?
    }

    private nonisolated static func currentSpaceKey(from current: [String: Any]) -> String? {
        if let id64 = current["id64"] as? NSNumber {
            return id64.stringValue
        } else if let id64 = current["id64"] as? Int {
            return String(id64)
        } else if let id64 = current["id64"] as? Int64 {
            return String(id64)
        } else if let id64 = current["id64"] as? UInt64 {
            return String(id64)
        }
        return nil
    }

    private nonisolated static func currentSpaceType(from current: [String: Any]) -> Int {
        if let type = current["type"] as? NSNumber {
            return type.intValue
        } else if let type = current["type"] as? Int {
            return type
        }
        return CurrentSpaceInfo.desktopType
    }
}
