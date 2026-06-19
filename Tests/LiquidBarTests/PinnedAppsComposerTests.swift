import Testing
import CoreGraphics
@testable import LiquidBar

@Suite
struct PinnedAppsComposerTests {
    private func makeWindowItem(id: UInt32, bundleId: String, screenId: UInt32) -> TaskbarItem {
        .window(
            id: WindowId(id),
            bundleId: bundleId,
            title: "Title \(id)",
            appName: bundleId.split(separator: ".").last.map(String.init) ?? bundleId,
            isHidden: false,
            isMinimized: false,
            screenId: screenId
        )
    }

    @Test func testComposePerDisplayPinsOnlyWhenBundleNotOpenOnThatDisplay() {
        let d0 = CGDirectDisplayID(0)
        let d1 = CGDirectDisplayID(1)

        let windows: [TaskbarItem] = [
            makeWindowItem(id: 1, bundleId: "com.apple.Safari", screenId: 0),
            makeWindowItem(id: 2, bundleId: "com.apple.Terminal", screenId: 1),
        ]

        let pinned: [CGDirectDisplayID: [String]] = [
            d0: ["com.apple.Safari", "com.apple.Slack"],
            d1: ["com.apple.Terminal", "com.apple.Notes"],
        ]

        let composed = PinnedAppsComposer.compose(
            windowItems: windows,
            displayIds: [d0, d1],
            pinnedAppsByDisplay: pinned,
            windowDisplayMode: .perDisplay
        )

        // Open bundles should suppress pinned-only items for those bundles on that display.
        let pinnedItems = composed.items.compactMap { item -> (String, UInt32)? in
            if case .pinnedApp(let bundleId, let screenId) = item {
                return (bundleId, screenId)
            }
            return nil
        }

        #expect(pinnedItems.contains { $0.0 == "com.apple.Slack" && $0.1 == 0 })
        #expect(pinnedItems.contains { $0.0 == "com.apple.Notes" && $0.1 == 1 })
        #expect(!pinnedItems.contains { $0.0 == "com.apple.Safari" })
        #expect(!pinnedItems.contains { $0.0 == "com.apple.Terminal" })

        #expect(composed.pinnedBundleIdsByDisplay[d0] == Set(["com.apple.Safari", "com.apple.Slack"]))
        #expect(composed.pinnedBundleIdsByDisplay[d1] == Set(["com.apple.Terminal", "com.apple.Notes"]))
    }

    @Test func testComposeAllWindowsSuppressesPinnedIfBundleOpenAnywhere() {
        let d0 = CGDirectDisplayID(0)
        let d1 = CGDirectDisplayID(1)

        let windows: [TaskbarItem] = [
            makeWindowItem(id: 1, bundleId: "com.apple.Safari", screenId: 0),
        ]

        let pinned: [CGDirectDisplayID: [String]] = [
            d0: ["com.apple.Safari"],
            d1: ["com.apple.Safari"],
        ]

        let composed = PinnedAppsComposer.compose(
            windowItems: windows,
            displayIds: [d0, d1],
            pinnedAppsByDisplay: pinned,
            windowDisplayMode: .allWindows
        )

        // Since Safari is open anywhere, no pinned-only Safari item should be added.
        #expect(!composed.items.contains { item in
            if case .pinnedApp(let bundleId, _) = item { return bundleId == "com.apple.Safari" }
            return false
        })
    }
}

