import AppKit
import Testing
@testable import LiquidBar

@Suite(.serialized)
struct SettingsWindowControllerTests {
    @MainActor
    @Test func generalTabShowsMenuBarIconToggle() throws {
        let controller = SettingsWindowController(
            configOverride: Config(showMenuBarIcon: false)
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 0
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let checkbox = try findButton(title: "Show menu bar icon", in: contentView)

        #expect(checkbox.state == .off)

        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("System"))
        #expect(labels.contains("Layout"))
        #expect(labels.contains("Displays"))
        #expect(labels.contains("Item Sizing:"))
        #expect(labels.contains("Bar Displays:"))
        #expect(labels.contains("Scroll Wheel:"))
        #expect(labels.contains("Launcher Action:"))
    }

    @MainActor
    @Test func appearanceTabShowsIconSizeSlider() throws {
        let controller = SettingsWindowController(
            configOverride: Config(taskbarHeight: 40, iconSize: 28)
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 1
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let iconSizeSlider = try findIconSizeSlider(in: contentView)

        #expect(iconSizeSlider.integerValue == 28)
        #expect(iconSizeSlider.minValue == Double(SettingsIconSizeRange.minimum))
        #expect(iconSizeSlider.maxValue == Double(SettingsIconSizeRange.maximum))

        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("Icon Size:"))
        #expect(labels.contains("28 px"))
        #expect(labels.contains("Title Font Size:"))
        #expect(labels.contains("Preview"))
        #expect(labels.contains("Visual Depth:"))

        let chipPresetPopup = try findPopup(withItems: ["Compact", "Dense", "Micro"], in: contentView)
        #expect(chipPresetPopup.indexOfSelectedItem == 0)

        if let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SETTINGS_VISUAL_QA_PATH"],
           !outputPath.isEmpty {
            try writeWindowContentSnapshot(contentView, to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    @Test func iconSizeSliderShowsCustomSize() throws {
        let controller = SettingsWindowController(
            configOverride: Config(taskbarHeight: 40, iconSize: 24)
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 1
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let iconSizeSlider = try findIconSizeSlider(in: contentView)
        #expect(iconSizeSlider.integerValue == 24)

        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("24 px"))
    }

    @MainActor
    @Test func changingIconSizeDoesNotMoveConfiguredBarHeightSlider() throws {
        let controller = SettingsWindowController(
            configOverride: Config(taskbarHeight: 32, iconSize: 20)
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 1
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let generalDocumentView = try documentView(forTabAt: 0, in: tabController)
        let appearanceDocumentView = try documentView(forTabAt: 1, in: tabController)
        let heightSlider = try findHeightSlider(in: generalDocumentView)
        let iconSizeSlider = try findIconSizeSlider(in: appearanceDocumentView)

        iconSizeSlider.integerValue = 40
        _ = iconSizeSlider.sendAction(iconSizeSlider.action, to: iconSizeSlider.target)

        #expect(heightSlider.integerValue == 32)

        let labels = recursiveSubviews(of: [generalDocumentView, appearanceDocumentView])
            .compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("40 px"))
        #expect(labels.contains("32 px"))
    }

    @MainActor
    @Test func appsTabExposesAppManagementControls() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }

        #expect(labels.contains("App Rules"))
        #expect(labels.contains("Pinned Scope"))
        #expect(labels.contains("Blacklisted Apps:"))
        #expect(labels.contains("Pinned Apps:"))
        _ = try findButton(title: "Add App...", in: contentView)
        _ = try findButton(title: "Clear", in: contentView)
        _ = try findButton(title: "Clear Pinned Apps", in: contentView)
    }

    @MainActor
    @Test func advancedTabShowsPermissionsConfigDiagnosticsAndExperimentalControls() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 3
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }

        #expect(labels.contains("Permissions"))
        #expect(labels.contains("Accessibility:"))
        #expect(labels.contains("Input Monitoring:"))
        #expect(labels.contains("Screen Recording:"))
        #expect(labels.contains("Previews"))
        #expect(labels.contains("Providers"))
        #expect(labels.contains("Configuration"))
        #expect(labels.contains("Diagnostics"))
        #expect(labels.contains("Experimental"))
        #expect(labels.contains("Log Interval:"))

        let displayConfigPath = Config.configPath.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~",
            options: [.anchored]
        )
        #expect(labels.contains(displayConfigPath))

        _ = try findButton(title: "Open Config", in: contentView)
        _ = try findButton(title: "Show in Finder", in: contentView)
        _ = try findButton(title: "Reset All", in: contentView)
        _ = try findButton(title: "Show window previews", in: contentView)
        _ = try findButton(title: "Enable provider runtime", in: contentView)
        _ = try findButton(title: "Performance logging", in: contentView)
        _ = try findButton(title: "Hang diagnostics", in: contentView)
        _ = try findButton(title: "Enable plugins", in: contentView)
        _ = try findButton(title: "Enable window tab groups", in: contentView)
    }

    @MainActor
    @Test func aboutTabShowsIdentityActionsOnly() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 4
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }

        #expect(labels.contains("LiquidBar"))
        #expect(!labels.contains("Configuration"))
        #expect(!labels.contains("Diagnostics"))

        let brandImageView = recursiveSubviews(of: contentView).compactMap { $0 as? NSImageView }.first {
            $0.frame.width > $0.frame.height * 3.0
                && $0.image?.accessibilityDescription == "LiquidBar"
        }
        #expect(brandImageView != nil)

        _ = try findButton(title: "Check for Updates", in: contentView)
        _ = try findButton(title: "GitHub", in: contentView)
    }

    @MainActor
    @Test func shortSettingsTabsAnchorContentNearTop() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)

        let generalScrollView = try scrollView(forTabAt: 0, in: tabController)
        let generalDocumentView = try #require(generalScrollView.documentView)
        #expect(generalScrollView.documentVisibleRect.maxY >= generalDocumentView.bounds.maxY - 2)

        let appsDocumentView = try documentView(forTabAt: 2, in: tabController)
        let appRulesLabel = try findLabel("App Rules", in: appsDocumentView)
        #expect(appsDocumentView.bounds.maxY - appRulesLabel.frame.maxY <= 32)

        let advancedDocumentView = try documentView(forTabAt: 3, in: tabController)
        let permissionsLabel = try findLabel("Permissions", in: advancedDocumentView)
        #expect(advancedDocumentView.bounds.maxY - permissionsLabel.frame.maxY <= 32)

        let aboutDocumentView = try documentView(forTabAt: 4, in: tabController)
        let brandImageView = try #require(recursiveSubviews(of: aboutDocumentView).compactMap { $0 as? NSImageView }.first {
            $0.frame.width > $0.frame.height * 3.0
                && $0.image?.accessibilityDescription == "LiquidBar"
        })
        #expect(aboutDocumentView.bounds.maxY - brandImageView.frame.maxY <= 32)
    }

    @MainActor
    private func writeWindowContentSnapshot(_ view: NSView, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: bounds))
        view.cacheDisplay(in: bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url, options: .atomic)
    }

    @MainActor
    private func recursiveSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { recursiveSubviews(of: $0) }
    }

    @MainActor
    private func recursiveSubviews(of views: [NSView]) -> [NSView] {
        views + views.flatMap { recursiveSubviews(of: $0) }
    }

    @MainActor
    private func findIconSizeSlider(in view: NSView) throws -> NSSlider {
        let sliders = recursiveSubviews(of: view).compactMap { $0 as? NSSlider }
        return try #require(sliders.first { slider in
            slider.minValue == Double(SettingsIconSizeRange.minimum)
                && slider.maxValue == Double(SettingsIconSizeRange.maximum)
        })
    }

    @MainActor
    private func findHeightSlider(in view: NSView) throws -> NSSlider {
        let sliders = recursiveSubviews(of: view).compactMap { $0 as? NSSlider }
        return try #require(sliders.first { slider in
            slider.minValue == 32 && slider.maxValue == 64
        })
    }

    @MainActor
    private func findButton(title: String, in view: NSView) throws -> NSButton {
        let buttons = recursiveSubviews(of: view).compactMap { $0 as? NSButton }
        return try #require(buttons.first { $0.title == title })
    }

    @MainActor
    private func findPopup(withItems titles: [String], in view: NSView) throws -> NSPopUpButton {
        let popups = recursiveSubviews(of: view).compactMap { $0 as? NSPopUpButton }
        return try #require(popups.first { popup in
            popup.itemArray.map(\.title) == titles
        })
    }

    @MainActor
    private func findLabel(_ title: String, in view: NSView) throws -> NSTextField {
        let labels = recursiveSubviews(of: view).compactMap { $0 as? NSTextField }
        return try #require(labels.first { $0.stringValue == title })
    }

    @MainActor
    private func documentView(forTabAt index: Int, in tabController: NSTabViewController) throws -> NSView {
        let scrollView = try scrollView(forTabAt: index, in: tabController)
        return try #require(scrollView.documentView)
    }

    @MainActor
    private func scrollView(forTabAt index: Int, in tabController: NSTabViewController) throws -> NSScrollView {
        let tabView = try #require(tabController.tabViewItems[index].viewController?.view)
        return try #require(recursiveSubviews(of: tabView).compactMap { $0 as? NSScrollView }.first)
    }
}
