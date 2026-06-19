import CoreGraphics
import Foundation
import ImageIO
import XCTest

@MainActor
final class LiquidBarE2ETests: XCTestCase {
    private let testSpaceKey = "uitest-space"
    private let taskbarIdPrefix = "liquidbar.taskbar."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHoverHighlightUsesVisualRectNotHitRect_singleItem() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "item_sizing": "uniform",
            "icons_only": false,
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 1, longTitles: true)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 10.0))
        attachScreenshot(name: "hover-rect-singleitem-before", element: taskbar)

        // Force hover deterministically.
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "0")

        let snapshotURL = runDir.appendingPathComponent("debug_snapshot_single.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
        let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "snapshot-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }

        guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }) else {
            attachText(name: "snapshot-panels", text: "Snapshot panels: \(snapshot.panels.map { $0.displayId })")
            XCTFail("Snapshot did not include panel for display \(displayId)")
            return
        }

        XCTAssertFalse(panel.windowIsOpaque)
        if let alpha = panel.windowBackgroundAlpha {
            XCTAssertLessThan(alpha, 0.02)
        }

        guard let item0 = panel.items.first else {
            XCTFail("Snapshot had no items")
            return
        }

        guard let visual = item0.visualRect, let hit = item0.hitRect else {
            XCTFail("Snapshot missing visual/hit rects")
            return
        }

        // Visual width should be capped (current default max is 150 for uniform sizing).
        XCTAssertLessThanOrEqual(visual.width, 150.5)
        XCTAssertGreaterThanOrEqual(visual.width, 44.0)

        // Hit rect should match the visual rect (empty bar space should not "belong"
        // to the last item).
        XCTAssertEqual(hit.x, visual.x, accuracy: 0.5)
        XCTAssertEqual(hit.width, visual.width, accuracy: 0.5)

        // Hover highlight should match VISUAL rect, not the hit rect.
        guard let hover = panel.hoverRect else {
            XCTFail("Snapshot missing hover rect")
            return
        }
        XCTAssertEqual(hover.x, visual.x, accuracy: 0.5)
        XCTAssertEqual(hover.width, visual.width, accuracy: 0.5)

        attachScreenshot(name: "hover-rect-singleitem-after", element: taskbar)
    }

    func testGroupPreviewDoesNotStackWithSingleWindowPreview_whenChooserVisible() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "group_by_app": true,
            "previews_enabled": true,
            "preview_hover_delay_ms": 0,
            "icons_only": false,
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        let windows: [TestWindow] = [
            makeTestWindow(id: 10_000, title: "Alpha 1", bundleId: "com.liquidbar.alpha", appName: "Alpha"),
            makeTestWindow(id: 10_001, title: "Alpha 2", bundleId: "com.liquidbar.alpha", appName: "Alpha"),
            makeTestWindow(id: 10_002, title: "Beta", bundleId: "com.liquidbar.beta", appName: "Beta"),
        ]
        try writeTestWindows(to: testWindowsPath, windows: windows)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 2, timeout: 10.0))

        // Find the item indices deterministically via the debug snapshot.
        let snapshotURL = runDir.appendingPathComponent("debug_snapshot_group_preview_stack.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
        let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "snapshot-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }
        guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }) else {
            attachText(name: "snapshot-panels", text: "Snapshot panels: \(snapshot.panels.map { $0.displayId })")
            XCTFail("Snapshot did not include panel for display \(displayId)")
            return
        }
        let itemSummary = panel.items
            .map { "\($0.kind):\($0.bundleId):\($0.index)" }
            .joined(separator: ", ")
        guard let groupItem = panel.items.first(where: { $0.kind == "app_group" && $0.bundleId == "com.liquidbar.alpha" }) else {
            attachText(name: "snapshot-items", text: "Items: \(itemSummary)")
            XCTFail("Expected app_group item for com.liquidbar.alpha")
            return
        }
        guard let windowItem = panel.items.first(where: { $0.kind == "window" && $0.bundleId == "com.liquidbar.beta" }) else {
            attachText(name: "snapshot-items", text: "Items: \(itemSummary)")
            XCTFail("Expected window item for com.liquidbar.beta")
            return
        }

        // Open the chooser by hovering the multi-window group.
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "\(groupItem.index)")
        guard let chooserPanel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 2, timeout: 2.0) else {
            XCTFail("Expected panel snapshot while showing group chooser")
            return
        }
        XCTAssertTrue(chooserPanel.groupPreviewVisible, "Expected group preview to be visible before switching hover target")
        attachScreenshot(name: "group-preview-before-switch", element: taskbar)

        // Hover a single-window app item while the chooser is visible.
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "\(windowItem.index)")

        // Ground-truth invariant for the regression:
        // do not present stacked overlays at once (single preview + group chooser).
        // Either overlay can be active depending on product behavior/config.
        let deadline = Date().addingTimeInterval(0.65)
        var sawAnyOverlay = false
        var overlapStreak = 0
        let requiredOverlapStreak = 2
        var lastOverlayState = "none"
        while Date() < deadline {
            guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 2, timeout: 0.2) else {
                usleep(25_000)
                continue
            }
            let groupVisible = panel.groupPreviewVisible
            let singleVisible = panel.previewVisible
            lastOverlayState = "group=\(groupVisible) single=\(singleVisible)"
            if groupVisible || singleVisible {
                sawAnyOverlay = true
            }
            if groupVisible && singleVisible {
                overlapStreak += 1
                if overlapStreak >= requiredOverlapStreak {
                    attachScreenshot(name: "stacked-preview-regression", element: taskbar)
                    attachText(name: "stacked-preview-state", text: "state=\(lastOverlayState)\nstreak=\(overlapStreak)")
                    XCTFail("Both group preview and single preview were visible at the same time")
                    break
                }
            } else {
                overlapStreak = 0
            }
            usleep(25_000)
        }
        XCTAssertTrue(sawAnyOverlay, "Expected either group preview or single preview to be visible after hover change")
        attachScreenshot(name: "group-preview-after-switch", element: taskbar)
    }

    func testColdStartCapturesStartupFlashBurstAndSnapshot() throws {
        let runDir = makeRunDirectory()
        // Force a bright baseline so "opaque black bar" regressions are detectable
        // even when the developer machine is in Dark Mode.
        try writeTestConfig(to: runDir, overrides: ["theme": "light"])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 5, longTitles: true)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BG_LUMA"] = "0.90"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        // Capture potential wallpaper / compositor flashes during cold start.
        attachScreenBurst(namePrefix: "coldstart", delaysMs: [0, 50, 150, 300, 600, 1000])

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 5, timeout: 10.0))
        attachScreenshot(name: "coldstart-taskbar", element: taskbar)

        // Quick pixel sanity: if the bar is opaque black on a bright background, fail early.
        let png = taskbar.screenshot().pngRepresentation
        if let metrics = analyzeLuminance(png: png) {
            attachText(
                name: "coldstart-luminance",
                text: String(format: "avg_luma=%.3f dark_ratio=%.3f", metrics.avgLuma, metrics.darkRatio)
            )
            XCTAssertGreaterThan(metrics.avgLuma, 0.25, "Taskbar average luminance too low (likely opaque/dark flash)")
            XCTAssertLessThan(metrics.darkRatio, 0.55, "Too many dark pixels in taskbar (likely opaque/dark flash)")
        } else {
            attachText(name: "coldstart-luminance", text: "failed_to_decode_png")
        }

        // Dump snapshot for window property assertions (non-opaque, etc.).
        let snapshotURL = runDir.appendingPathComponent("debug_snapshot_coldstart.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
        let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)
        XCTAssertTrue(snapshot.panels.allSatisfy { !$0.windowIsOpaque })
    }

    func testHoverRectAlignmentUnderHighWindowCount() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "item_sizing": "uniform",
            "icons_only": false,
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 120, longTitles: true)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 120, timeout: 10.0))
        attachScreenshot(name: "hover-highcount-initial", element: taskbar)

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "snapshot-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }

        // Assert invariants and hover alignment at a few indices.
        for idx in [0, 60, 119] {
            postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "\(idx)")

            let snapshotURL = runDir.appendingPathComponent("debug_snapshot_highcount_\(idx).json")
            postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
            let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)

            guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }) else {
                XCTFail("Snapshot did not include panel for display \(displayId)")
                return
            }

            XCTAssertEqual(panel.items.count, 120)

            // Visual rects should be monotonic (stable left-to-right ordering).
            var lastMaxX: Double = 0
            for (i, it) in panel.items.enumerated() {
                guard let vr = it.visualRect else {
                    XCTFail("Missing visual rect for item \(i)")
                    return
                }
                XCTAssertGreaterThanOrEqual(vr.x, lastMaxX - 0.5)
                lastMaxX = vr.x + vr.width
            }

            guard let hovered = panel.items.first(where: { $0.index == idx }),
                  let visual = hovered.visualRect,
                  let hover = panel.hoverRect else {
                XCTFail("Missing hovered item visual rect or hover rect")
                return
            }
            XCTAssertEqual(hover.x, visual.x, accuracy: 0.5)
            XCTAssertEqual(hover.width, visual.width, accuracy: 0.5)

            attachScreenshot(name: "hover-highcount-\(idx)", element: taskbar)
        }
    }

    func testShowsFixtureWindows() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let fixture = XCUIApplication(bundleIdentifier: "com.liquidbar.fixture")
        fixture.launchEnvironment["FIXTURE_WINDOW_COUNT"] = "5"
        fixture.launchEnvironment["FIXTURE_LONG_TITLES"] = "0"
        fixture.launch()

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        // Wait for the polling loop to pick up fixture windows.
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 5, timeout: 10.0))

        attachScreenshot(name: "taskbar-fixture-5", element: taskbar)
    }

    func testTruncatesLongTitles() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        // Use a deterministic in-process window list so this test doesn't rely on
        // Screen Recording (CGWindowList window titles) or Accessibility (AX titles).
        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 3, longTitles: true)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 10.0) else {
            XCTFail("Expected at least 3 taskbar items")
            return
        }

        let labels = panel.items.map(\.displayTitle)
        XCTAssertTrue(labels.contains(where: { $0.hasSuffix("...") }), "Expected at least one truncated label. Labels: \(labels)")

        attachScreenshot(name: "taskbar-long-titles", element: taskbar)
    }

    func testTabbedTaskbarCollapsesNonFocusedWindows() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "item_sizing": "auto",
            "icons_only": false,
            "tabbed_taskbar_enabled": true,
        ])

        // Deterministic windows + deterministic focus.
        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 3, longTitles: true)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        // Focus the second window (ids from writeTestWindows: 10000, 10001, 10002).
        app.launchEnvironment["LIQUIDBAR_TEST_FOCUSED_WINDOW_ID"] = "10001"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 10.0))

        let snapshotURL = runDir.appendingPathComponent("debug_snapshot_tabbed.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
        let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "tabbed-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }

        guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }) else {
            attachText(name: "tabbed-panels", text: "Snapshot panels: \(snapshot.panels.map { $0.displayId })")
            XCTFail("Snapshot did not include panel for display \(displayId)")
            return
        }

        let windows = panel.items.filter { $0.kind == "window" }
        XCTAssertEqual(windows.count, 3)

        let collapsedWidth = max(44.0, Double(snapshot.config.iconSize + 20))

        guard let focused = windows.first(where: { $0.windowId == 10001 }),
              let focusedRect = focused.visualRect else {
            let itemsDesc = panel.items
                .map { "\($0.kind):\($0.windowId ?? 0)" }
                .joined(separator: ", ")
            attachText(name: "tabbed-items", text: "Items: [\(itemsDesc)]")
            XCTFail("Missing focused window item")
            return
        }

        XCTAssertGreaterThan(focusedRect.width, collapsedWidth + 1.0)

        let collapsed = windows.filter { $0.windowId != 10001 }
        let collapsedWidths = collapsed.compactMap { $0.visualRect?.width }
        XCTAssertEqual(collapsedWidths.count, collapsed.count, "Missing visual rect for collapsed windows")
        if let first = collapsedWidths.first {
            for w in collapsedWidths.dropFirst() {
                XCTAssertEqual(w, first, accuracy: 0.8)
            }
        }

        for it in collapsed {
            guard let vr = it.visualRect else {
                XCTFail("Missing visual rect for window \(String(describing: it.windowId))")
                return
            }
            XCTAssertEqual(vr.width, collapsedWidth, accuracy: 0.8)
        }

        attachScreenshot(name: "taskbar-tabbed-taskbar", element: taskbar)
    }

    func testSidebarCompactClickTriggerExpandsAndThenReturnsCompact() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "taskbar_position": "left",
            "sidebar_mode_enabled": true,
            "sidebar_state_default": "compact_icons",
            "sidebar_expand_trigger": "click",
            "icons_only": false,
            "window_display_mode": "all_windows",
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 3, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        guard var compactPanel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 10.0) else {
            XCTFail("Expected compact sidebar panel")
            return
        }
        if compactPanel.sidebarPresentation != "compact" {
            let compactDeadline = Date().addingTimeInterval(3.0)
            while Date() < compactDeadline {
                if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 0.5),
                   panel.sidebarPresentation == "compact" {
                    compactPanel = panel
                    break
                }
                usleep(35_000)
            }
        }
        let compactWidth = compactPanel.frame.width
        attachScreenshot(name: "sidebar-compact-before-expand", element: taskbar)

        let clickPoint = taskbar.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.50))
        clickPoint.click()

        let expandedDeadline = Date().addingTimeInterval(2.5)
        var expandedPanel: DebugSnapshot.Panel?
        while Date() < expandedDeadline {
            if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 0.5),
               panel.sidebarPresentation == "expanded",
               panel.frame.width > compactWidth + 10,
               panel.items.contains(where: { !$0.displayTitle.isEmpty }) {
                expandedPanel = panel
                break
            }
            usleep(35_000)
        }
        XCTAssertNotNil(expandedPanel, "Expected click-trigger compact sidebar to expand with labels")
        attachScreenshot(name: "sidebar-compact-expanded", element: taskbar)

        let collapseDeadline = Date().addingTimeInterval(3.5)
        var collapsedAgain = false
        while Date() < collapseDeadline {
            if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 0.6),
               panel.sidebarPresentation == "compact",
               panel.frame.width <= compactWidth + 1.0 {
                collapsedAgain = true
                break
            }
            usleep(40_000)
        }
        XCTAssertTrue(collapsedAgain, "Expected sidebar to return to compact presentation after reveal window")
        attachScreenshot(name: "sidebar-compact-after-collapse", element: taskbar)
    }

    func testTilePopupOpensWhenSingletonDisabled() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "taskbar_position": "left",
            "sidebar_mode_enabled": true,
            "sidebar_state_default": "expanded",
            "tile_zone_enabled": true,
            "plugins_enabled": true,
            "tile_popup_singleton": false,
            "provider_runtime_enabled": false,
            "window_display_mode": "all_windows",
        ])
        try writePluginManifest(
            to: runDir,
            folderName: "FixtureTiles",
            pluginId: "com.liquidbar.fixture.tiles",
            tileId: "spotify",
            tileTitle: "Spotify",
            visualState: "active"
        )

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 1, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        let tileDeadline = Date().addingTimeInterval(4.0)
        var tile: DebugSnapshot.Item?
        while Date() < tileDeadline {
            if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 0.5),
               let panelTile = panel.items.first(where: { $0.kind == "plugin_tile" }) {
                tile = panelTile
                break
            }
            usleep(35_000)
        }
        guard let tile else {
            XCTFail("Expected at least one plugin tile in sidebar tile zone")
            return
        }

        XCTAssertTrue(clickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: tile.accessibilityId,
            timeout: 2.0
        ))

        let firstOpenDeadline = Date().addingTimeInterval(2.0)
        var opened = false
        while Date() < firstOpenDeadline {
            if let snap = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 0.4),
               snap.pluginCardVisible,
               snap.pluginCardTileId == "plugin:com.liquidbar.fixture.tiles:tile:spotify" {
                opened = true
                break
            }
            usleep(30_000)
        }
        XCTAssertTrue(opened, "Expected plugin card to open for tile when singleton is disabled")

        XCTAssertTrue(clickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: tile.accessibilityId,
            timeout: 2.0
        ))

        let secondOpenDeadline = Date().addingTimeInterval(2.0)
        var stillOpens = false
        while Date() < secondOpenDeadline {
            if let snap = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 0.4),
               snap.pluginCardVisible {
                stillOpens = true
                break
            }
            usleep(30_000)
        }
        XCTAssertTrue(stillOpens, "Expected plugin card behavior to remain functional with tile_popup_singleton=false")
        attachScreenshot(name: "sidebar-tile-popup-singleton-disabled", element: taskbar)
    }

    func testTabGroupOverlayShowsTabsAndScreenshot() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "window_tab_groups_enabled": true,
            "item_sizing": "uniform",
            "icons_only": false,
            "window_display_mode": "all_windows",
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(
            to: testWindowsPath,
            windows: [
                makeTestWindow(id: 10_000, title: "Work A"),
                makeTestWindow(id: 10_001, title: "Work B"),
                makeTestWindow(id: 10_002, title: "Other"),
            ]
        )

        let groupId = "work-group"
        try writeTestState(
            to: runDir,
            pinnedAppsBySpace: [:],
            tabGroups: [
                TestTabGroup(
                    id: groupId,
                    name: "Work",
                    emoji: "W",
                    colorHex: "#34C759",
                    windowIds: [10_000, 10_001]
                ),
            ]
        )

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "tabgroup-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }

        // Ensure grouped members are assigned to the active panel display.
        try writeTestWindows(
            to: testWindowsPath,
            windows: [
                makeTestWindow(id: 10_000, title: "Work A", monitorId: UInt32(displayId)),
                makeTestWindow(id: 10_001, title: "Work B", monitorId: UInt32(displayId)),
                makeTestWindow(id: 10_002, title: "Other", monitorId: UInt32(displayId)),
            ]
        )

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.tabgroup.\(groupId)",
            timeout: 10.0
        ))
        attachScreenshot(name: "tabgroup-chip", element: taskbar)

        // Expand and verify overlay appears with per-window tabs.
        XCTAssertTrue(clickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.tabgroup.\(groupId)",
            timeout: 2.0
        ))

        let overlayDeadline = Date().addingTimeInterval(5.0)
        var overlayVisible = false
        while Date() < overlayDeadline {
            if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 0.4),
               panel.tabGroupOverlayVisible,
               panel.tabGroupOverlayId == groupId {
                overlayVisible = true
                break
            }
            usleep(40_000)
        }
        XCTAssertTrue(overlayVisible, "Expected tab-group overlay for \(groupId)")
        attachAllScreenshots(name: "tabgroup-overlay")
    }

    func testGroupsWindowsByAppWhenEnabled() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: ["group_by_app": true])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(
            to: testWindowsPath,
            windows: [
                makeTestWindow(id: 20_001, title: "One"),
                makeTestWindow(id: 20_002, title: "Two"),
                makeTestWindow(id: 20_003, title: "Three"),
            ]
        )

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 10.0) else {
            XCTFail("Expected grouped taskbar item")
            return
        }

        let labels = panel.items.map(\.displayTitle)
        XCTAssertTrue(labels.contains("Fixture"), "Expected grouped label. Labels: \(labels)")

        attachScreenshot(name: "taskbar-grouped-by-app", element: taskbar)
    }

    func testPinnedAppsAppearWithNoWindows() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)
        try writeTestState(to: runDir, pinnedAppsBySpace: [testSpaceKey: ["com.apple.finder"]])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, windows: [])

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 10.0) else {
            XCTFail("Expected at least one pinned item")
            return
        }
        XCTAssertTrue(
            panel.items.contains { $0.kind == "pinned_app" && $0.bundleId == "com.apple.finder" },
            "Expected pinned app item for finder. Items: \(panel.items.map(\.accessibilityId))"
        )

        attachScreenshot(name: "taskbar-pinned-only", element: taskbar)
    }

    func testPinnedAppsArePerSpaceAcrossSpaceSwitch() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let spaceB = "\(testSpaceKey)-b"
        try writeTestState(to: runDir, pinnedAppsBySpace: [
            testSpaceKey: ["com.apple.finder"],
            spaceB: ["com.apple.Safari"],
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, windows: [])

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-space-a", element: taskbar)

        // Switch Spaces (test hook).
        switchToSpaceWithFlashBurst(spaceB, element: taskbar, namePrefix: "pins-switch-to-space-b")

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.Safari",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-space-b", element: taskbar)

        // Switch back to Space A by clearing the override.
        switchToSpaceWithFlashBurst(nil, element: taskbar, namePrefix: "pins-switch-back-space-a")
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-space-a-restored", element: taskbar)
    }

    func testUnpinOnlyAffectsCurrentSpace() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let spaceB = "\(testSpaceKey)-b"
        try writeTestState(to: runDir, pinnedAppsBySpace: [
            testSpaceKey: ["com.apple.finder"],
            spaceB: ["com.apple.Safari"],
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, windows: [])

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 5.0
        ))

        // Unpin on Space A.
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 2.0
        ))
        let unpinItem = app.menuItems["Unpin from Taskbar"]
        XCTAssertTrue(unpinItem.waitForExistence(timeout: 2.0))
        unpinItem.click()

        XCTAssertFalse(try readPinnedApps(from: runDir, spaceKey: testSpaceKey).contains("com.apple.finder"))
        XCTAssertTrue(try readPinnedApps(from: runDir, spaceKey: spaceB).contains("com.apple.Safari"))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, exactCount: 0, timeout: 2.0))
        attachScreenshot(name: "pins-unpinned-space-a", element: taskbar)

        // Space B should still show its pins.
        switchToSpaceWithFlashBurst(spaceB, element: taskbar, namePrefix: "pins-unpin-switch-to-space-b")
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.Safari",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-space-b-still-pinned", element: taskbar)
    }

    func testContextMenuShowsUnpinWhenWindowIsPinned() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)
        try writeTestState(to: runDir, pinnedAppsBySpace: [testSpaceKey: ["com.liquidbar.fixture"]])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(
            to: testWindowsPath,
            windows: [makeTestWindow(id: 50_001, title: "Fixture One")]
        )

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        guard let firstItem = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 5.0)?.items.first else {
            XCTFail("Expected at least one taskbar item")
            return
        }

        // The bundle is pinned, but a window is present, so the item is a window item.
        // Context menu should still show "Unpin from Taskbar".
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: firstItem.accessibilityId,
            timeout: 2.0
        ))
        let unpinItem = app.menuItems["Unpin from Taskbar"]
        XCTAssertTrue(unpinItem.waitForExistence(timeout: 2.0))
        unpinItem.click()

        XCTAssertFalse(try readPinnedApps(from: runDir).contains("com.liquidbar.fixture"))

        // Context menu should now show "Pin to Taskbar".
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: firstItem.accessibilityId,
            timeout: 2.0
        ))
        let pinItem = app.menuItems["Pin to Taskbar"]
        XCTAssertTrue(pinItem.waitForExistence(timeout: 2.0))
        attachScreenshot(name: "contextmenu-window-unpinned", element: taskbar)
    }

    func testGlobalPinnedAppsPersistAcrossSpaceSwitch() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "pinned_apps_scope": "global",
            "pinned_apps": ["com.apple.finder"],
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, windows: [])

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-global-space-a", element: taskbar)

        // Switch Spaces; global pins should remain.
        switchToSpaceWithFlashBurst("\(testSpaceKey)-b", element: taskbar, namePrefix: "pins-global-switch")
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 5.0
        ))
        attachScreenshot(name: "pins-global-space-b", element: taskbar)

        // Unpin should write to config.json (not state.json).
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.apple.finder",
            timeout: 2.0
        ))
        let unpinItem = app.menuItems["Unpin from Taskbar"]
        XCTAssertTrue(unpinItem.waitForExistence(timeout: 2.0))
        unpinItem.click()

        XCTAssertFalse(try readPinnedAppsFromConfig(from: runDir).contains("com.apple.finder"))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, exactCount: 0, timeout: 2.0))
        attachScreenshot(name: "pins-global-unpinned", element: taskbar)
    }

    func testSpaceChangeStressDoesNotHangAndCapturesFlashBursts() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 8, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 8, timeout: 10.0))
        attachScreenshot(name: "stress-initial", element: taskbar)

        for i in 0..<12 {
            // Simulate a Space switch and capture a burst to detect transient flashes.
            switchToSpaceWithFlashBurst("stress-space-\(i)", element: taskbar, namePrefix: "stress-space-\(i)")

            // Create the transient empty window list pattern seen during real swipes.
            try writeTestWindows(to: testWindowsPath, windows: [])
            usleep(50_000)
            try writeTestWindows(
                to: testWindowsPath,
                windows: (0..<8).map { idx in
                    makeTestWindow(id: UInt32(60_000 + i * 100 + idx), title: "Stress \(i)-\(idx)")
                }
            )

            // Bar should remain responsive and repopulate quickly.
            guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 8, timeout: 3.5) else {
                XCTFail("Expected repopulated items after stress iteration \(i)")
                return
            }

            // Basic interactivity probe: context menu should appear quickly.
            // Use a live panel item lookup to avoid stale accessibility IDs while
            // the stress loop repopulates windows.
            XCTAssertTrue(rightClickAnyItem(
                runDir: runDir,
                taskbar: taskbar,
                minimumCount: panel.items.count,
                timeout: 2.0
            ))

            let pinItem = app.menuItems["Pin to Taskbar"]
            let unpinItem = app.menuItems["Unpin from Taskbar"]
            XCTAssertTrue(pinItem.waitForExistence(timeout: 2.0) || unpinItem.waitForExistence(timeout: 2.0))

            // Dismiss menu.
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }

    func testSidebarDragAndReloadConfigStressStaysResponsive() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "taskbar_position": "left",
            "sidebar_mode_enabled": true,
            "sidebar_state_default": "expanded",
            "sidebar_expand_trigger": "click",
            "icons_only": false,
            "window_display_mode": "all_windows",
            "second_click_action": "minimize",
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 10, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        guard let initialPanel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 10, timeout: 10.0) else {
            XCTFail("Expected sidebar panel with seeded windows")
            return
        }
        XCTAssertTrue(initialPanel.items.contains(where: { $0.kind == "window" }))
        attachScreenshot(name: "sidebar-drag-reload-stress-initial", element: taskbar)

        for i in 0..<12 {
            guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 10, timeout: 3.0) else {
                XCTFail("Missing panel snapshot during stress loop iteration \(i)")
                return
            }

            let windowItems = panel.items.filter { $0.kind == "window" }
            guard windowItems.count >= 2 else {
                XCTFail("Need at least two window items for drag/reorder in iteration \(i)")
                return
            }

            let sourceItem = windowItems[i % windowItems.count]
            let targetItem = windowItems[(i + max(1, windowItems.count / 2)) % windowItems.count]
            if sourceItem.accessibilityId != targetItem.accessibilityId {
                XCTAssertTrue(
                    dragItem(taskbar: taskbar, sourceItem: sourceItem, targetItem: targetItem),
                    "Expected drag gesture to execute for iteration \(i)"
                )
            }

            let secondClick: String = (i % 2 == 0) ? "none" : "minimize"
            try writeTestConfig(to: runDir, overrides: [
                "taskbar_position": "left",
                "sidebar_mode_enabled": true,
                "sidebar_state_default": "expanded",
                "sidebar_expand_trigger": "click",
                "icons_only": false,
                "window_display_mode": "all_windows",
                "second_click_action": secondClick,
            ])
            postTestControlNotification("com.liquidbar.testcontrol.reloadConfig")

            guard let reloaded = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 10, timeout: 4.0) else {
                XCTFail("Expected panel to recover after config reload in iteration \(i)")
                return
            }
            XCTAssertTrue(reloaded.items.contains(where: { $0.kind == "window" }))

            XCTAssertTrue(rightClickAnyItem(
                runDir: runDir,
                taskbar: taskbar,
                minimumCount: 1,
                timeout: 2.0
            ))
            let pinItem = app.menuItems["Pin to Taskbar"]
            let unpinItem = app.menuItems["Unpin from Taskbar"]
            XCTAssertTrue(pinItem.waitForExistence(timeout: 1.5) || unpinItem.waitForExistence(timeout: 1.5))
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

            if i == 0 || i == 5 || i == 11 {
                attachScreenshot(name: "sidebar-drag-reload-stress-\(i)", element: taskbar)
            }
        }
    }

    func testMultiMonitorPerDisplayFilteringAndSpaceChanges() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "window_display_mode": "per_display",
            "multi_monitor_mode": "all_displays",
        ])

        // Start empty; we'll populate after discovering display IDs.
        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, windows: [])

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbarsQuery = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", taskbarIdPrefix))
        XCTAssertTrue(waitFor(taskbarsQuery, minimumCount: 1, timeout: 10.0))
        let hasTwoDisplays = waitFor(taskbarsQuery, minimumCount: 2, timeout: 5.0)
        let taskbars = taskbarsQuery.allElementsBoundByIndex

        if !hasTwoDisplays {
            attachText(
                name: "multimonitor-missing",
                text: "Multi-monitor tests require >= 2 displays. Found taskbars: \(taskbars.map { $0.identifier })"
            )
            for (idx, tb) in taskbars.enumerated() {
                if tb.waitForExistence(timeout: 1.0) {
                    attachScreenshot(name: "multimonitor-missing-taskbar-\(idx)", element: tb)
                }
            }
            XCTFail("Multi-monitor tests require an external display. Connect a second monitor and rerun.")
            return
        }

        // Use the first two taskbars as our test pair.
        let tbA = taskbars[0]
        let tbB = taskbars[1]

        XCTAssertTrue(tbA.waitForExistence(timeout: 5.0))
        XCTAssertTrue(tbB.waitForExistence(timeout: 5.0))

        guard let displayA = parseDisplayId(fromTaskbarIdentifier: tbA.identifier),
              let displayB = parseDisplayId(fromTaskbarIdentifier: tbB.identifier) else {
            attachText(name: "multimonitor-parse-failure", text: "Failed to parse display IDs from: \(tbA.identifier), \(tbB.identifier)")
            XCTFail("Could not parse display IDs from taskbar identifiers")
            return
        }

        // Populate windows assigned to each display.
        let winA: TestWindow = makeTestWindow(id: 70_001, title: "On Display A")
        let winB: TestWindow = makeTestWindow(id: 70_002, title: "On Display B")

        try writeTestWindows(
            to: testWindowsPath,
            windows: [
                TestWindow(
                    id: winA.id,
                    bundleId: winA.bundleId,
                    appName: winA.appName,
                    title: winA.title,
                    isHidden: winA.isHidden,
                    isMinimized: winA.isMinimized,
                    monitorId: UInt32(displayA),
                    bounds: winA.bounds
                ),
                TestWindow(
                    id: winB.id,
                    bundleId: winB.bundleId,
                    appName: winB.appName,
                    title: winB.title,
                    isHidden: winB.isHidden,
                    isMinimized: winB.isMinimized,
                    monitorId: UInt32(displayB),
                    bounds: winB.bounds
                ),
            ]
        )

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: tbA,
            accessibilityId: "liquidbar.item.window.70001",
            timeout: 5.0
        ))
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: tbB,
            accessibilityId: "liquidbar.item.window.70002",
            timeout: 5.0
        ))

        // Ensure windows do NOT appear on the other display's taskbar.
        if let panelA = waitForPanelSnapshot(runDir: runDir, taskbar: tbA, minimumCount: 1, timeout: 1.0),
           let panelB = waitForPanelSnapshot(runDir: runDir, taskbar: tbB, minimumCount: 1, timeout: 1.0) {
            XCTAssertFalse(panelA.items.contains(where: { $0.accessibilityId == "liquidbar.item.window.70002" }))
            XCTAssertFalse(panelB.items.contains(where: { $0.accessibilityId == "liquidbar.item.window.70001" }))
        } else {
            XCTFail("Could not read per-display panel snapshots")
        }

        attachScreenshot(name: "multimonitor-before-spacechange-A", element: tbA)
        attachScreenshot(name: "multimonitor-before-spacechange-B", element: tbB)

        // Space transition burst (flash detection) + ensure assignment remains stable.
        switchToSpace("multimonitor-space")
        attachScreenBurst(namePrefix: "multimonitor-space", delaysMs: [0, 50, 150, 300])
        attachScreenshotBurst(namePrefix: "multimonitor-space-A", element: tbA, delaysMs: [0, 50, 150, 300])
        attachScreenshotBurst(namePrefix: "multimonitor-space-B", element: tbB, delaysMs: [0, 50, 150, 300])

        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: tbA,
            accessibilityId: "liquidbar.item.window.70001",
            timeout: 5.0
        ))
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: tbB,
            accessibilityId: "liquidbar.item.window.70002",
            timeout: 5.0
        ))

        // Ensure windows still do NOT appear on the other display's taskbar after a Space change.
        if let panelAAfter = waitForPanelSnapshot(runDir: runDir, taskbar: tbA, minimumCount: 1, timeout: 1.0),
           let panelBAfter = waitForPanelSnapshot(runDir: runDir, taskbar: tbB, minimumCount: 1, timeout: 1.0) {
            XCTAssertFalse(panelAAfter.items.contains(where: { $0.accessibilityId == "liquidbar.item.window.70002" }))
            XCTAssertFalse(panelBAfter.items.contains(where: { $0.accessibilityId == "liquidbar.item.window.70001" }))
        } else {
            XCTFail("Could not read per-display panel snapshots after space change")
        }
    }

    func testHiddenWindowsFilteredWhenDisabled() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: ["show_hidden_apps": false])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(
            to: testWindowsPath,
            windows: [
                makeTestWindow(id: 30_001, title: "Visible A", isHidden: false),
                makeTestWindow(id: 30_002, title: "Hidden B", isHidden: true),
                makeTestWindow(id: 30_003, title: "Visible C", isHidden: false),
            ]
        )

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        guard let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 2, timeout: 10.0) else {
            XCTFail("Expected visible taskbar items")
            return
        }
        let labels = panel.items.map(\.displayTitle)
        XCTAssertFalse(labels.contains(where: { $0.contains("Hidden") }), "Hidden window should be filtered. Labels: \(labels)")

        attachScreenshot(name: "taskbar-hidden-filtered", element: taskbar)
    }

    func testSpaceChangeStabilizesTransientEmptyThenClears() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 3, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 10.0))
        attachScreenshot(name: "spacechange-before", element: taskbar)

        // Simulate active space change without Mission Control automation.
        postTestControlNotification("com.liquidbar.testcontrol.spaceChange")
        attachScreenBurst(namePrefix: "spacechange-transition", delaysMs: [0, 50, 150, 300])
        attachScreenshotBurst(namePrefix: "spacechange-transition-taskbar", element: taskbar, delaysMs: [0, 50, 150, 300])

        // During the transition, the window list can temporarily go empty.
        try writeTestWindows(to: testWindowsPath, windows: [])

        // Our stabilizer should hold the last non-empty list briefly.
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 3, timeout: 0.3))

        // After the hold window, an actually blank space should become blank.
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, exactCount: 0, timeout: 2.0))
        attachScreenshot(name: "spacechange-blank", element: taskbar)

        // Coming back to a non-blank space should repopulate quickly.
        try writeTestWindows(to: testWindowsPath, count: 2, longTitles: false)
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 2, timeout: 2.0))
        attachScreenshot(name: "spacechange-restored", element: taskbar)
    }

    func testContextMenuPinUnpinFlow() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir)

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(
            to: testWindowsPath,
            windows: [makeTestWindow(id: 40_001, title: "Fixture One")]
        )

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        guard let firstItem = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 10.0)?.items.first else {
            XCTFail("Expected at least one initial item")
            return
        }

        // Pin via context menu.
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: firstItem.accessibilityId,
            timeout: 2.0
        ))
        let pinItem = app.menuItems["Pin to Taskbar"]
        XCTAssertTrue(pinItem.waitForExistence(timeout: 2.0))
        pinItem.click()

        // Validate state persistence (per-space pins write to state.json).
        XCTAssertTrue(try readPinnedApps(from: runDir).contains("com.liquidbar.fixture"))

        // Remove all windows; pinned app should remain.
        try writeTestWindows(to: testWindowsPath, windows: [])
        XCTAssertNotNil(waitForPanelItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.liquidbar.fixture",
            timeout: 2.0
        ))
        attachScreenshot(name: "contextmenu-pinned", element: taskbar)

        // Unpin via context menu.
        XCTAssertTrue(rightClickItem(
            runDir: runDir,
            taskbar: taskbar,
            accessibilityId: "liquidbar.item.pinned.com.liquidbar.fixture",
            timeout: 2.0
        ))
        let unpinItem = app.menuItems["Unpin from Taskbar"]
        XCTAssertTrue(unpinItem.waitForExistence(timeout: 2.0))
        unpinItem.click()

        XCTAssertFalse(try readPinnedApps(from: runDir).contains("com.liquidbar.fixture"))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, exactCount: 0, timeout: 2.0))
        attachScreenshot(name: "contextmenu-unpinned", element: taskbar)
    }

    func testHoverHighlightScreenshot() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: ["hover_intensity": "pronounced"])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 10, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 10, timeout: 10.0))

        // Force hover deterministically (no reliance on mouse move events).
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "0")
        attachScreenshot(name: "hover-index-0", element: taskbar)

        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "9")
        attachScreenshot(name: "hover-index-9", element: taskbar)

        // Clear hover for cleanliness.
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: nil)
    }

    func testHoverSpecularHotspotTracksCursorPoint_deterministic() throws {
        let runDir = makeRunDirectory()
        try writeTestConfig(to: runDir, overrides: [
            "item_sizing": "uniform",
            "icons_only": false,
            "hover_intensity": "pronounced",
        ])

        let testWindowsPath = runDir.appendingPathComponent("test_windows.json")
        try writeTestWindows(to: testWindowsPath, count: 5, longTitles: false)

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_WINDOWS_PATH"] = testWindowsPath.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SPACE_ID"] = testSpaceKey
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        app.launch()

        let taskbar = taskbarElement(app)
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))
        XCTAssertNotNil(waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 5, timeout: 10.0))

        // Deterministic hover + deterministic cursor position via test-control.
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: "0")

        let snapshotURL = runDir.appendingPathComponent("debug_snapshot_hotspot.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
        let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: 2.0)

        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "hotspot-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            XCTFail("Could not parse display id from taskbar identifier")
            return
        }

        guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }),
              let hover = panel.hoverRect else {
            attachText(name: "hotspot-snapshot", text: "Snapshot panels: \(snapshot.panels.map { $0.displayId })")
            XCTFail("Missing hover rect in snapshot")
            return
        }

        let y = hover.y + hover.height * 0.35
        let leftX = hover.x + hover.width * 0.25
        let rightX = hover.x + hover.width * 0.75

        postTestControlNotification("com.liquidbar.testcontrol.setCursorPoint", object: "\(leftX),\(y)")
        usleep(60_000)
        attachScreenshot(name: "hotspot-cursor-left", element: taskbar)

        let snapshotURLLeft = runDir.appendingPathComponent("debug_snapshot_hotspot_left.json")
        postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURLLeft.path)
        let snapLeft = try readDebugSnapshot(from: snapshotURLLeft, timeout: 2.0)
        if let p = snapLeft.panels.first(where: { $0.displayId == UInt32(displayId) })?.hoverCursorNormalized {
            XCTAssertEqual(p.x, 0.25, accuracy: 0.08)
            XCTAssertEqual(p.y, 0.35, accuracy: 0.10)
        } else {
            XCTFail("Missing hoverCursorNormalized after setting cursor point")
        }

        postTestControlNotification("com.liquidbar.testcontrol.setCursorPoint", object: "\(rightX),\(y)")
        usleep(60_000)
        attachScreenshot(name: "hotspot-cursor-right", element: taskbar)

        // Clear hover/cursor for cleanliness.
        postTestControlNotification("com.liquidbar.testcontrol.setCursorPoint", object: nil)
        postTestControlNotification("com.liquidbar.testcontrol.setHoverIndex", object: nil)
    }

    // MARK: - Helpers

    private func makeRunDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("liquidbar-uitest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTestConfig(to runDir: URL, overrides: [String: Any] = [:]) throws {
        let configURL = runDir.appendingPathComponent("config.json")

        // Keep UI tests robust across multi-monitor setups by rendering all windows
        // onto each panel for test runs.
        var config: [String: Any] = [
            // Mirrors Sources/LiquidBar/Config/Config.swift defaults.
            "taskbar_height": 30,
            "icon_size": 20,
            "font_size": 11,
            "icons_only": false,
            "taskbar_position": "bottom",
            "theme": "system",
            "item_sizing": "uniform",
            "group_by_app": false,
            "show_hidden_apps": true,
            "multi_monitor_mode": "all_displays",
            "window_display_mode": "all_windows",
            "blacklisted_apps": [],
            "pinned_apps": [],
            "pinned_apps_scope": "per_space",
            "center_items": false,
            "hide_dock": false,
            "hidden_window_mode": "in_place",
            "bar_style": "flush",
            "hover_intensity": "subtle",
        ]

        // Apply overrides.
        for (k, v) in overrides {
            config[k] = v
        }

        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: configURL, options: .atomic)
    }

    private func writePluginManifest(
        to runDir: URL,
        folderName: String,
        pluginId: String,
        tileId: String,
        tileTitle: String,
        visualState: String
    ) throws {
        let fm = FileManager.default
        let pluginsDir = runDir.appendingPathComponent("Plugins", isDirectory: true)
        let pluginDir = pluginsDir.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let manifest: [String: Any] = [
            "id": pluginId,
            "name": "Fixture Tiles",
            "version": "1.0.0",
            "api_version": 1,
            "tiles": [
                [
                    "id": tileId,
                    "title": tileTitle,
                    "icon": "sf:music.note",
                    "visual_state": visualState,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: pluginDir.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private struct TestWindowsRoot: Codable {
        var windows: [TestWindow]
    }

    private struct TestWindow: Codable {
        var id: UInt32
        var bundleId: String
        var appName: String
        var title: String
        var isHidden: Bool
        var isMinimized: Bool
        var monitorId: UInt32
        var bounds: TestBounds
    }

    private struct TestBounds: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    private struct DebugSnapshot: Codable {
        struct DebugConfig: Codable {
            var itemSizing: String
            var iconSize: Int
            var fontSize: Int
            var iconsOnly: Bool
            var windowDisplayMode: String
            var pinnedAppsScope: String
            var showHiddenApps: Bool
            var adjustWindowsForTaskbar: Bool
            var tabbedTaskbarEnabled: Bool
            var windowTabGroupsEnabled: Bool
            var previewsEnabled: Bool
        }

        struct Rect: Codable {
            var x: Double
            var y: Double
            var width: Double
            var height: Double
        }

        struct Point: Codable {
            var x: Double
            var y: Double
        }

        struct Item: Codable {
            var index: Int
            var accessibilityId: String
            var kind: String
            var bundleId: String
            var windowId: UInt32?
            var title: String?
            var displayTitle: String
            var visualRect: Rect?
            var hitRect: Rect?
        }

        struct Panel: Codable {
            var displayId: UInt32
            var frame: Rect
            var barBounds: Rect
            var sidebarPresentation: String?
            var windowIsOpaque: Bool
            var windowAlphaValue: Double
            var windowBackgroundAlpha: Double?
            var hoverRect: Rect?
            var cursorPoint: Point?
            var hoverCursorNormalized: Point?
            var previewVisible: Bool
            var previewWindowId: UInt32?
            var groupPreviewVisible: Bool
            var groupPreviewKey: String?
            var tabGroupOverlayVisible: Bool
            var tabGroupOverlayId: String?
            var pluginCardVisible: Bool
            var pluginCardTileId: String?
            var items: [Item]
        }

        var timestamp: Double
        var config: DebugConfig
        var panels: [Panel]
    }

    private func makeTestWindow(
        id: UInt32,
        title: String,
        isHidden: Bool = false,
        isMinimized: Bool = false,
        bundleId: String = "com.liquidbar.fixture",
        appName: String = "Fixture",
        monitorId: UInt32 = 0
    ) -> TestWindow {
        TestWindow(
            id: id,
            bundleId: bundleId,
            appName: appName,
            title: title,
            isHidden: isHidden,
            isMinimized: isMinimized,
            monitorId: monitorId,
            bounds: TestBounds(x: 100, y: 100, width: 800, height: 600)
        )
    }

    private func writeTestWindows(to url: URL, count: Int, longTitles: Bool) throws {
        let baseTitle = longTitles
            ? "This is a very long window title that should be truncated"
            : "Window"

        let windows: [TestWindow] = (0..<count).map { i in
            makeTestWindow(id: UInt32(10_000 + i), title: "\(baseTitle) \(i + 1)")
        }

        try writeTestWindows(to: url, windows: windows)
    }

    private func writeTestWindows(to url: URL, windows: [TestWindow]) throws {
        let root = TestWindowsRoot(windows: windows)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(root)
        try data.write(to: url, options: .atomic)
    }

    private func readDebugSnapshot(from url: URL, timeout: TimeInterval) throws -> DebugSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                break
            }
            usleep(25_000)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DebugSnapshot.self, from: data)
    }

    private func attachScreenshot(name: String, element: XCUIElement) {
        let shot = element.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachText(name: String, text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreenshotBurst(namePrefix: String, element: XCUIElement, delaysMs: [Int]) {
        for d in delaysMs {
            if d > 0 {
                usleep(useconds_t(d * 1000))
            }
            attachScreenshot(name: "\(namePrefix)-t\(d)ms", element: element)
        }
    }

    private func attachScreenBurst(namePrefix: String, delaysMs: [Int]) {
        for d in delaysMs {
            if d > 0 {
                usleep(useconds_t(d * 1000))
            }
            attachAllScreenshots(name: "\(namePrefix)-t\(d)ms")
        }
    }

    private func attachAllScreenshots(name: String) {
        // Screen flashes (wallpaper black/white) can occur outside the bar's view subtree,
        // so capture full-screen screenshots in addition to element-only attachments.
        let screens = XCUIScreen.screens
        for (idx, screen) in screens.enumerated() {
            let shot = screen.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(name)-screen\(idx)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func waitFor(_ elements: XCUIElementQuery, minimumCount: Int, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "count >= %d", minimumCount)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: elements)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func postTestControlNotification(_ name: String, object: String? = nil) {
        DistributedNotificationCenter.default().post(name: Notification.Name(name), object: object)
    }

    private func switchToSpace(_ spaceKey: String?) {
        postTestControlNotification("com.liquidbar.testcontrol.setSpaceId", object: spaceKey)
        postTestControlNotification("com.liquidbar.testcontrol.spaceChange")
    }

    private func switchToSpaceWithFlashBurst(_ spaceKey: String?, element: XCUIElement, namePrefix: String) {
        // Capture immediate post-switch snapshots to catch transient compositor flashes.
        switchToSpace(spaceKey)
        attachScreenBurst(namePrefix: "\(namePrefix)-screen", delaysMs: [0, 50, 150, 300])
        attachScreenshotBurst(namePrefix: "\(namePrefix)-taskbar", element: element, delaysMs: [0, 50, 150, 300])
    }

    private func taskbarElement(_ app: XCUIApplication) -> XCUIElement {
        // Query by identifier, not element type. XCUITest's element-type mapping for
        // AppKit accessibility roles can change (and differs by OS version).
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", taskbarIdPrefix))
            .firstMatch
    }

    private func parseDisplayId(fromTaskbarIdentifier identifier: String) -> Int? {
        guard identifier.hasPrefix(taskbarIdPrefix) else { return nil }
        let suffix = identifier.dropFirst(taskbarIdPrefix.count)
        return Int(suffix)
    }

    private func waitForPanelSnapshot(
        runDir: URL,
        taskbar: XCUIElement,
        minimumCount: Int = 0,
        exactCount: Int? = nil,
        timeout: TimeInterval
    ) -> DebugSnapshot.Panel? {
        guard let displayId = parseDisplayId(fromTaskbarIdentifier: taskbar.identifier) else {
            attachText(name: "snapshot-taskbar-id", text: "Unexpected taskbar identifier: \(taskbar.identifier)")
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastState = "no snapshots yet"
        while Date() < deadline {
            do {
                let snapshotURL = runDir.appendingPathComponent("debug_snapshot_wait_\(UUID().uuidString).json")
                postTestControlNotification("com.liquidbar.testcontrol.dumpSnapshot", object: snapshotURL.path)
                let readTimeout = min(1.0, max(0.2, deadline.timeIntervalSinceNow))
                let snapshot = try readDebugSnapshot(from: snapshotURL, timeout: readTimeout)
                guard let panel = snapshot.panels.first(where: { $0.displayId == UInt32(displayId) }) else {
                    lastState = "missing panel for display \(displayId); panels=\(snapshot.panels.map { $0.displayId })"
                    usleep(40_000)
                    continue
                }

                let count = panel.items.count
                if let exactCount {
                    if count == exactCount { return panel }
                } else if count >= minimumCount {
                    return panel
                }
                lastState = "count=\(count), ids=\(panel.items.map { $0.accessibilityId })"
            } catch {
                if isSnapshotFileMissing(error) {
                    lastState = "snapshot not produced yet"
                } else {
                    lastState = "snapshot decode error: \(error)"
                }
            }
            usleep(40_000)
        }

        attachText(name: "snapshot-wait-timeout", text: lastState)
        return nil
    }

    private func waitForPanelItem(
        runDir: URL,
        taskbar: XCUIElement,
        accessibilityId: String,
        timeout: TimeInterval
    ) -> (panel: DebugSnapshot.Panel, item: DebugSnapshot.Item)? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastIds: [String] = []
        while Date() < deadline {
            if let panel = waitForPanelSnapshot(runDir: runDir, taskbar: taskbar, minimumCount: 1, timeout: 0.9) {
                if let item = panel.items.first(where: { $0.accessibilityId == accessibilityId }) {
                    return (panel, item)
                }
                lastIds = panel.items.map(\.accessibilityId)
            }
            usleep(40_000)
        }
        attachText(
            name: "panel-item-timeout",
            text: "missing=\(accessibilityId)\nobserved=\(lastIds)"
        )
        return nil
    }

    private func isSnapshotFileMissing(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSFileNoSuchFileError
    }

    private func coordinateForItem(_ item: DebugSnapshot.Item, in taskbar: XCUIElement) -> XCUICoordinate? {
        guard let rect = item.hitRect ?? item.visualRect else { return nil }
        let width = max(1.0, taskbar.frame.width)
        let height = max(1.0, taskbar.frame.height)
        let dx = min(max((rect.x + rect.width * 0.5) / width, 0.001), 0.999)
        let dy = min(max((rect.y + rect.height * 0.5) / height, 0.001), 0.999)
        return taskbar.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    private func clickItem(
        runDir: URL,
        taskbar: XCUIElement,
        accessibilityId: String,
        timeout: TimeInterval
    ) -> Bool {
        guard let result = waitForPanelItem(runDir: runDir, taskbar: taskbar, accessibilityId: accessibilityId, timeout: timeout),
              let coordinate = coordinateForItem(result.item, in: taskbar) else {
            attachText(name: "click-item-failed", text: "Could not locate clickable item: \(accessibilityId)")
            return false
        }
        coordinate.click()
        return true
    }

    private func rightClickItem(
        runDir: URL,
        taskbar: XCUIElement,
        accessibilityId: String,
        timeout: TimeInterval
    ) -> Bool {
        guard let result = waitForPanelItem(runDir: runDir, taskbar: taskbar, accessibilityId: accessibilityId, timeout: timeout),
              let coordinate = coordinateForItem(result.item, in: taskbar) else {
            attachText(name: "right-click-item-failed", text: "Could not locate clickable item: \(accessibilityId)")
            return false
        }
        coordinate.rightClick()
        return true
    }

    private func rightClickAnyItem(
        runDir: URL,
        taskbar: XCUIElement,
        minimumCount: Int = 1,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastIds: [String] = []
        while Date() < deadline {
            guard let panel = waitForPanelSnapshot(
                runDir: runDir,
                taskbar: taskbar,
                minimumCount: minimumCount,
                timeout: 0.6
            ) else {
                usleep(30_000)
                continue
            }

            if let item = panel.items.first, let coordinate = coordinateForItem(item, in: taskbar) {
                coordinate.rightClick()
                return true
            }

            lastIds = panel.items.map(\.accessibilityId)
            usleep(30_000)
        }

        attachText(
            name: "right-click-any-item-failed",
            text: "Could not locate a right-click target in time.\nobserved=\(lastIds)"
        )
        return false
    }

    private func dragItem(taskbar: XCUIElement, sourceItem: DebugSnapshot.Item, targetItem: DebugSnapshot.Item) -> Bool {
        guard let source = coordinateForItem(sourceItem, in: taskbar),
              let target = coordinateForItem(targetItem, in: taskbar) else {
            attachText(
                name: "drag-item-failed",
                text: "Could not resolve drag coordinates.\nsource=\(sourceItem.accessibilityId)\ntarget=\(targetItem.accessibilityId)"
            )
            return false
        }
        source.press(forDuration: 0.05, thenDragTo: target)
        return true
    }

    private func writeTestState(to runDir: URL, pinnedAppsBySpace: [String: [String]] = [:]) throws {
        try writeTestState(to: runDir, pinnedAppsBySpace: pinnedAppsBySpace, tabGroups: [])
    }

    private struct TestTabGroup: Codable {
        var id: String
        var name: String
        var emoji: String?
        var colorHex: String?
        var windowIds: [UInt32]
    }

    private struct TestUserState: Codable {
        var appOrder: [String]
        var pinnedAppsBySpace: [String: [String]]
        var tabGroups: [TestTabGroup]
    }

    private func writeTestState(
        to runDir: URL,
        pinnedAppsBySpace: [String: [String]],
        tabGroups: [TestTabGroup]
    ) throws {
        let stateURL = runDir.appendingPathComponent("state.json")
        let state = TestUserState(appOrder: [], pinnedAppsBySpace: pinnedAppsBySpace, tabGroups: tabGroups)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func readPinnedApps(from runDir: URL, spaceKey: String) throws -> [String] {
        let stateURL = runDir.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return [] }
        let data = try Data(contentsOf: stateURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let bySpace = obj?["pinned_apps_by_space"] as? [String: Any]
        return (bySpace?[spaceKey] as? [String]) ?? []
    }

    private func readPinnedApps(from runDir: URL) throws -> [String] {
        try readPinnedApps(from: runDir, spaceKey: testSpaceKey)
    }

    private func readPinnedAppsFromConfig(from runDir: URL) throws -> [String] {
        let configURL = runDir.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["pinned_apps"] as? [String]) ?? []
    }

    private struct LumaMetrics {
        var avgLuma: Double
        var darkRatio: Double
    }

    private func analyzeLuminance(png: Data) -> LumaMetrics? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let step = max(1, min(width, height) / 200) // sample for speed
        var sum: Double = 0
        var count: Int = 0
        var dark: Int = 0
        let darkThreshold: Double = 0.15

        for y in stride(from: 0, to: height, by: step) {
            let rowBase = y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                let i = rowBase + x * bytesPerPixel
                // premultipliedLast: RGBA
                let r = Double(pixels[i]) / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                sum += luma
                count += 1
                if luma < darkThreshold { dark += 1 }
            }
        }

        guard count > 0 else { return nil }
        return LumaMetrics(
            avgLuma: sum / Double(count),
            darkRatio: Double(dark) / Double(count)
        )
    }
}
