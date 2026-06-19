import Testing
import Foundation
@testable import LiquidBar

@Suite
struct UserStateTests {
    @Test func testDecodeIgnoresLegacyPinnedAppsKey() throws {
        let json = """
        {
          "app_order": ["com.app.a"],
          "window_order": [101, 202],
          "pinned_apps": ["com.legacy.pinned"]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(UserState.self, from: Data(json.utf8))

        #expect(decoded.appOrder == ["com.app.a"])
        #expect(decoded.windowOrder == [101, 202])
    }

    @Test func testJSONRoundtrip() throws {
        var original = UserState()
        original.appOrder = ["com.app.a", "com.app.b"]
        original.windowOrder = [11, 22, 33]
        original.pinnedAppsBySpace = [
            "111": ["com.apple.finder"],
            "222": ["com.apple.Safari"],
        ]
        original.groupPreviewOrderByKey = [
            "app:com.apple.finder": [11, 33, 22]
        ]

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(UserState.self, from: data)

        #expect(decoded == original)
    }

    @Test func testPinUnpinMutations() {
        // Ensure we don't write to the real Application Support directory.
        let key = "LIQUIDBAR_CONFIG_DIR"
        let path = "/tmp/liquidbar-userstate-test-\(UUID().uuidString)"
        setenv(key, path, 1)
        defer { unsetenv(key) }

        var state = UserState()
        #expect(state.isPinned(bundleId: "com.apple.finder", spaceKey: "1") == false)

        state.pin(bundleId: "com.apple.finder", spaceKey: "1")
        #expect(state.isPinned(bundleId: "com.apple.finder", spaceKey: "1") == true)

        // Idempotent pin.
        state.pin(bundleId: "com.apple.finder", spaceKey: "1")
        #expect(state.pinnedAppsBySpace["1"] == ["com.apple.finder"])

        state.unpin(bundleId: "com.apple.finder", spaceKey: "1")
        #expect(state.isPinned(bundleId: "com.apple.finder", spaceKey: "1") == false)
        #expect(state.pinnedAppsBySpace["1"] == nil)
    }

    @Test func testReorderTabGroupWindows() {
        var state = UserState()
        let groupId = "g1"
        state.tabGroups = [
            TabGroup(id: groupId, name: "Work", windowIds: [11, 22, 33, 44])
        ]

        // Partial preferred order: listed IDs first, leftovers keep prior relative order.
        state.reorderTabGroupWindows(groupId: groupId, orderedWindowIds: [33, 11])
        #expect(state.tabGroups[0].windowIds == [33, 11, 22, 44])

        // Unknown IDs are ignored; duplicates are de-duped.
        state.reorderTabGroupWindows(groupId: groupId, orderedWindowIds: [999, 44, 44, 22])
        #expect(state.tabGroups[0].windowIds == [44, 22, 33, 11])
    }

    @Test func testUpdateGroupPreviewOrderDedupesAndClears() {
        var state = UserState()

        state.updateGroupPreviewOrder(key: "app:com.example", orderedWindowIds: [3, 2, 3, 1])
        #expect(state.groupPreviewOrderByKey["app:com.example"] == [3, 2, 1])

        state.updateGroupPreviewOrder(key: "app:com.example", orderedWindowIds: [])
        #expect(state.groupPreviewOrderByKey["app:com.example"] == nil)
    }
}
