import Testing
@testable import LiquidBar

@Suite
struct EventLoopFocusInferenceTests {
    @Test func frontmostWindowInStateResolvesBundleAndDisplay() {
        let focused = makeTestWindow(
            id: 42,
            bundle: "com.example.focused",
            title: "Focused",
            monitorId: 7
        )
        let windows = [focused.id: focused]

        let result = EventLoop.makeFocusInfo(
            frontmostWindowId: 42,
            windows: windows,
            tabGroupId: "group-1"
        )

        #expect(result.info == FocusInfo(
            windowId: 42,
            bundleId: "com.example.focused",
            tabGroupId: "group-1"
        ))
        #expect(result.displayId == 7)
    }

    @Test func frontmostWindowMissingFromStateKeepsNoDisplayFocus() {
        let visible = makeTestWindow(
            id: 10,
            bundle: "com.example.visible",
            title: "Visible",
            monitorId: 1
        )
        let windows = [visible.id: visible]

        let result = EventLoop.makeFocusInfo(
            frontmostWindowId: 99,
            windows: windows,
            tabGroupId: nil
        )

        #expect(result.info == FocusInfo(windowId: 99, bundleId: nil, tabGroupId: nil))
        #expect(result.displayId == nil)
    }

    @Test func nilFrontmostWindowClearsFocus() {
        let visible = makeTestWindow(
            id: 10,
            bundle: "com.example.visible",
            title: "Visible",
            monitorId: 1
        )
        let windows = [visible.id: visible]

        let result = EventLoop.makeFocusInfo(
            frontmostWindowId: nil,
            windows: windows,
            tabGroupId: nil
        )

        #expect(result.info == .none)
        #expect(result.displayId == nil)
    }

    @Test func switcherMRUOrderPromotesFocusedWindowAndPrunesDeadIds() {
        let order = EventLoop.updatedSwitcherMRUOrder(
            previous: [2, 99, 1, 2, 3],
            focusedWindowId: 1,
            liveWindowIds: [1, 2, 3]
        )

        #expect(order == [1, 2, 3])
    }

    @Test func switcherWindowOrderUsesMRUBeforeTaskbarOrder() {
        let windows = [
            makeTestWindow(id: 1, bundle: "com.example.one", title: "One"),
            makeTestWindow(id: 2, bundle: "com.example.two", title: "Two"),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Three"),
            makeTestWindow(id: 4, bundle: "com.example.four", title: "Four"),
        ]

        let ordered = EventLoop.orderedSwitcherWindows(
            windows: windows,
            mruWindowIds: [3, 1]
        )

        #expect(ordered.map(\.id.raw) == [3, 1, 2, 4])
    }

    @Test func switcherCandidatesDefaultToAllDisplays() {
        let windows = [
            makeTestWindow(id: 1, bundle: "com.example.one", title: "One", monitorId: 1),
            makeTestWindow(id: 2, bundle: "com.example.two", title: "Two", monitorId: 2),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Duplicate", monitorId: 2),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Duplicate", monitorId: 2),
        ]

        let candidates = EventLoop.switcherCandidateWindows(
            windows: windows,
            scope: .allDisplays,
            focusDisplayId: 1
        )

        #expect(candidates.map(\.id.raw) == [1, 2, 3])
    }

    @Test func switcherCandidatesCanLimitToFocusedDisplay() {
        let windows = [
            makeTestWindow(id: 1, bundle: "com.example.one", title: "One", monitorId: 1),
            makeTestWindow(id: 2, bundle: "com.example.two", title: "Two", monitorId: 2),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Three", monitorId: 2),
        ]

        let candidates = EventLoop.switcherCandidateWindows(
            windows: windows,
            scope: .focusedDisplay,
            focusDisplayId: 2
        )

        #expect(candidates.map(\.id.raw) == [2, 3])
    }

    @Test func switcherInitialSelectionFollowsMRUToggleBehavior() {
        let windows = [
            makeTestWindow(id: 1, bundle: "com.example.one", title: "One"),
            makeTestWindow(id: 2, bundle: "com.example.two", title: "Two"),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Three"),
        ]

        let firstEntries = EventLoop.orderedSwitcherWindows(
            windows: windows,
            mruWindowIds: [1, 2, 3]
        )
        let firstSelected = EventLoop.initialSwitcherSelectedIndex(
            entries: firstEntries,
            focusedWindowId: 1,
            initialDirection: 1
        )
        #expect(firstEntries[firstSelected].id.raw == 2)

        let nextMRU = EventLoop.updatedSwitcherMRUOrder(
            previous: [1, 2, 3],
            focusedWindowId: 2,
            liveWindowIds: [1, 2, 3]
        )
        let secondEntries = EventLoop.orderedSwitcherWindows(
            windows: windows,
            mruWindowIds: nextMRU
        )
        let secondSelected = EventLoop.initialSwitcherSelectedIndex(
            entries: secondEntries,
            focusedWindowId: 2,
            initialDirection: 1
        )

        #expect(nextMRU == [2, 1, 3])
        #expect(secondEntries[secondSelected].id.raw == 1)
    }

    @Test func reverseInitialSwitcherSelectionWrapsFromFocusedMRUWindow() {
        let windows = [
            makeTestWindow(id: 1, bundle: "com.example.one", title: "One"),
            makeTestWindow(id: 2, bundle: "com.example.two", title: "Two"),
            makeTestWindow(id: 3, bundle: "com.example.three", title: "Three"),
        ]
        let entries = EventLoop.orderedSwitcherWindows(
            windows: windows,
            mruWindowIds: [1, 2, 3]
        )
        let selected = EventLoop.initialSwitcherSelectedIndex(
            entries: entries,
            focusedWindowId: 1,
            initialDirection: -1
        )

        #expect(entries[selected].id.raw == 3)
    }
}
