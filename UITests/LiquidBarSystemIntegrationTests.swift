import Foundation
import XCTest

/// Optional "real system" UI tests.
///
/// These validate integration with actual macOS window enumeration instead of the
/// deterministic JSON window injector (`LIQUIDBAR_TEST_WINDOWS_PATH`).
///
/// They are intentionally gated behind `LIQUIDBAR_SYSTEM_E2E=1` because they may
/// require TCC permissions (Screen Recording) and can be flakier than the
/// deterministic suite.
@MainActor
final class LiquidBarSystemIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        if ProcessInfo.processInfo.environment["LIQUIDBAR_SYSTEM_E2E"] != "1" {
            throw XCTSkip("Set LIQUIDBAR_SYSTEM_E2E=1 to enable system integration UI tests.")
        }
    }

    func testRealEnumerationShowsDistinctFixtureWindowTitles() throws {
        let runDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("liquidbar-system-uitest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        // Minimal config written to the sandbox dir.
        let configURL = runDir.appendingPathComponent("config.json")
        let config: [String: Any] = [
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
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: configURL, options: .atomic)

        let fixture = XCUIApplication(bundleIdentifier: "com.liquidbar.fixture")
        fixture.launchEnvironment["FIXTURE_WINDOW_COUNT"] = "2"
        fixture.launchEnvironment["FIXTURE_LONG_TITLES"] = "0"
        fixture.launch()

        let app = XCUIApplication(bundleIdentifier: "com.liquidbar.testhost")
        app.launchEnvironment["LIQUIDBAR_CONFIG_DIR"] = runDir.path
        app.launchEnvironment["LIQUIDBAR_TEST_CONTROL"] = "1"
        app.launchEnvironment["LIQUIDBAR_TEST_SOLID_BACKGROUND"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_PROMPT"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_MOUSE_TRACKER"] = "1"
        app.launchEnvironment["LIQUIDBAR_DISABLE_AX_QUERIES"] = "1"
        // Intentionally do NOT set LIQUIDBAR_TEST_WINDOWS_PATH so the app uses real enumeration.
        app.launch()

        let taskbar = app.tables
            .matching(NSPredicate(format: "label == %@", "Taskbar"))
            .firstMatch
        XCTAssertTrue(taskbar.waitForExistence(timeout: 10.0))

        let buttons = taskbar.buttons
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10.0))

        // Assert we see distinct titles from the fixture windows.
        let labels = (0..<min(10, buttons.count)).map { buttons.element(boundBy: $0).label }
        if !labels.contains("Fixture Window 1") || !labels.contains("Fixture Window 2") {
            let attachment = XCTAttachment(string: """
Expected to see fixture window titles via real enumeration.
This typically requires Screen Recording permission for the test host build.

Observed labels: \(labels)
""")
            attachment.name = "system-e2e-missing-titles"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Missing expected fixture titles (likely missing Screen Recording permission).")
        }
    }
}

