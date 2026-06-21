import Foundation
import Testing
@testable import LiquidBar

@Suite
struct TestWindowListTests {
    @Test @MainActor func reloadsWhenFixtureMetadataChanges() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "liquidbar-test-window-list-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        defer { TestWindowList.clearCacheForTests() }

        let fixtureURL = root.appendingPathComponent("windows.json")
        try writeFixture(to: fixtureURL, id: 1, title: "One")

        let firstLoad = try #require(TestWindowList.load(from: fixtureURL))
        #expect(firstLoad.map(\.id.raw) == [1])
        #expect(firstLoad.map(\.title) == ["One"])

        try writeFixture(to: fixtureURL, id: 2, title: "Two with different file size")

        let secondLoad = try #require(TestWindowList.load(from: fixtureURL))
        #expect(secondLoad.map(\.id.raw) == [2])
        #expect(secondLoad.map(\.title) == ["Two with different file size"])
    }

    private func writeFixture(to url: URL, id: UInt32, title: String) throws {
        let json = """
        {
          "windows": [
            {
              "id": \(id),
              "bundle_id": "com.app.Test",
              "app_name": "Test",
              "title": "\(title)",
              "is_hidden": false,
              "is_minimized": false,
              "monitor_id": 0,
              "bounds": {
                "x": 10,
                "y": 20,
                "width": 640,
                "height": 480
              }
            }
          ]
        }
        """
        try Data(json.utf8).write(to: url, options: .atomic)
    }
}
