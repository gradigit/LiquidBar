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
        let checkbox = try findButton(title: L10n.tr("Show menu bar icon"), in: contentView)

        #expect(checkbox.state == .off)

        let labels = recursiveSubviews(of: contentView).compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains(L10n.tr("System")))
        #expect(labels.contains(L10n.tr("Layout")))
        #expect(labels.contains(L10n.tr("Displays")))
        #expect(labels.contains(L10n.tr("Language:")))
        #expect(labels.contains(L10n.tr("Item Sizing:")))
        #expect(labels.contains(L10n.tr("Bar Displays:")))
        #expect(labels.contains(L10n.tr("Scroll Wheel:")))
        #expect(labels.contains(L10n.tr("Launcher Action:")))

        let languagePopup = try findPopup(withItems: localized(["System", "English", "Korean"]), in: contentView)
        #expect(languagePopup.indexOfSelectedItem == 0)
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
        #expect(labels.contains(L10n.tr("Icon Size:")))
        #expect(labels.contains("28 px"))
        #expect(labels.contains(L10n.tr("Title Font Size:")))
        #expect(labels.contains(L10n.tr("Preview")))
        #expect(labels.contains(L10n.tr("Visual Depth:")))

        let chipPresetPopup = try findPopup(withItems: localized(["Compact", "Dense", "Micro"]), in: contentView)
        #expect(chipPresetPopup.indexOfSelectedItem == 0)

        let appearanceDocumentView = try documentView(forTabAt: 1, in: tabController)
        let appearanceContentFrame = try #require(visibleContentFrame(in: appearanceDocumentView))
        #expect(abs(appearanceContentFrame.midX - appearanceDocumentView.bounds.midX) <= 18)
        #expect(appearanceContentFrame.minX >= 70)

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
    @Test func appearanceTabShowsSystemIndicatorColorWells() throws {
        let controller = SettingsWindowController(
            configOverride: Config(
                systemIndicatorCpuColorHex: "#AF52DE",
                systemIndicatorGpuColorHex: "#FF9F0A",
                systemIndicatorRamColorHex: "#34C759",
                systemIndicatorThermalColorHex: "#FFD166"
            )
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 1
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        #expect(PresentationColorPalette.hexString(from: try findColorWell(toolTip: L10n.tr("%@ color", "CPU"), in: contentView).color) == "#AF52DE")
        #expect(PresentationColorPalette.hexString(from: try findColorWell(toolTip: L10n.tr("%@ color", "GPU"), in: contentView).color) == "#FF9F0A")
        #expect(PresentationColorPalette.hexString(from: try findColorWell(toolTip: L10n.tr("%@ color", "RAM"), in: contentView).color) == "#34C759")
        #expect(PresentationColorPalette.hexString(from: try findColorWell(toolTip: L10n.tr("%@ color", "TEMP"), in: contentView).color) == "#FFD166")
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

        #expect(labels.contains(L10n.tr("App Rules")))
        #expect(labels.contains(L10n.tr("Pinned Scope")))
        #expect(labels.contains(L10n.tr("Blacklisted Apps:")))
        #expect(labels.contains(L10n.tr("Pinned Apps:")))
        _ = try findButton(title: L10n.tr("Add App..."), in: contentView)
        _ = try findButton(title: L10n.tr("Clear"), in: contentView)
        _ = try findButton(title: L10n.tr("Clear Pinned Apps"), in: contentView)
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

        #expect(labels.contains(L10n.tr("Permissions")))
        #expect(labels.contains(L10n.tr("Accessibility:")))
        #expect(labels.contains(L10n.tr("Input Monitoring:")))
        #expect(labels.contains(L10n.tr("Screen Recording:")))
        #expect(labels.contains(L10n.tr("Previews")))
        #expect(labels.contains(L10n.tr("Providers")))
        #expect(labels.contains(L10n.tr("Configuration")))
        #expect(labels.contains(L10n.tr("Diagnostics")))
        #expect(labels.contains(L10n.tr("Experimental")))
        #expect(labels.contains(L10n.tr("Log Interval:")))
        #expect(labels.contains(L10n.tr("Preview Memory:")))

        let displayConfigPath = Config.configPath.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~",
            options: [.anchored]
        )
        #expect(labels.contains(displayConfigPath))

        _ = try findButton(title: L10n.tr("Open Config"), in: contentView)
        _ = try findButton(title: L10n.tr("Show in Finder"), in: contentView)
        _ = try findButton(title: L10n.tr("Reset All"), in: contentView)
        _ = try findButton(title: L10n.tr("Show window previews"), in: contentView)
        _ = try findButton(title: L10n.tr("Enable provider runtime"), in: contentView)
        _ = try findButton(title: L10n.tr("Performance logging"), in: contentView)
        _ = try findButton(title: L10n.tr("Hang diagnostics"), in: contentView)
        _ = try findButton(title: L10n.tr("Enable plugins"), in: contentView)
        _ = try findButton(title: L10n.tr("Enable window tab groups"), in: contentView)
    }

    @MainActor
    @Test func advancedTabControlsAlignToSharedFormColumn() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 3
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let documentView = try documentView(forTabAt: 3, in: tabController)
        let previewMemoryPopup = try findPopup(withItems: localized(["Low", "Balanced", "High Quality"]), in: documentView)
        let controlColumnX = previewMemoryPopup.frame.minX
        let buttonsToCheck = [
            L10n.tr("Show window previews"),
            L10n.tr("Enable provider runtime"),
            L10n.tr("Performance logging"),
            L10n.tr("Hang diagnostics"),
            L10n.tr("Enable plugins"),
            L10n.tr("Enable window tab groups"),
            L10n.tr("Collapse group on outside click")
        ]

        for title in buttonsToCheck {
            let button = try findButton(title: title, in: documentView)
            #expect(abs(button.frame.minX - controlColumnX) <= 0.5, "\(title) is not aligned to the Advanced tab form column")
        }

        #expect(previewMemoryPopup.frame.width >= 220)
    }

    @MainActor
    @Test func inputMonitoringPermissionStatusUsesInputMonitoringGrantOnly() {
        #expect(SettingsWindowController.inputMonitoringPermissionStatus(inputMonitoringAllowed: true) == L10n.tr("Allowed"))
        #expect(SettingsWindowController.inputMonitoringPermissionStatus(inputMonitoringAllowed: false) == L10n.tr("Needs Access"))
    }

    @MainActor
    @Test func koreanAdvancedTabActionButtonsFitTheirFrames() throws {
        L10n.applyAppLanguage(.korean)
        let controller = SettingsWindowController(
            configOverride: Config(appLanguage: .korean)
        )
        defer {
            controller.close()
            L10n.applyAppLanguage(.system)
        }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)
        tabController.selectedTabViewItemIndex = 3
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let contentView = try #require(window.contentView)
        let titlesToCheck = [
            "Open Settings",
            "Refresh",
            "Open Config",
            "Show in Finder",
            "Reset All",
            "Reset Tab",
            "Revert",
            "Reload",
            "Apply"
        ].map { L10n.tr($0) }

        for title in titlesToCheck {
            let button = try findButton(title: title, in: contentView)
            #expect(
                button.intrinsicContentSize.width <= button.frame.width + 8,
                "\(title) needs \(button.intrinsicContentSize.width)pt but has \(button.frame.width)pt"
            )
        }

        if let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SETTINGS_ADVANCED_VISUAL_QA_PATH"],
           !outputPath.isEmpty {
            try writeWindowContentSnapshot(contentView, to: URL(fileURLWithPath: outputPath))
        }
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
        #expect(!labels.contains(L10n.tr("Configuration")))
        #expect(!labels.contains(L10n.tr("Diagnostics")))

        let brandImageView = recursiveSubviews(of: contentView).compactMap { $0 as? NSImageView }.first {
            $0.frame.width > $0.frame.height * 3.0
                && $0.image?.accessibilityDescription == "LiquidBar"
        }
        #expect(brandImageView != nil)

        let aboutDocumentView = try documentView(forTabAt: 4, in: tabController)
        let documentBrandImageView = try #require(recursiveSubviews(of: aboutDocumentView).compactMap { $0 as? NSImageView }.first {
            $0.frame.width > $0.frame.height * 3.0
                && $0.image?.accessibilityDescription == "LiquidBar"
        })
        #expect(abs(documentBrandImageView.frame.midX - aboutDocumentView.bounds.midX) <= 1)

        let updateButton = try findButton(title: L10n.tr("Check for Updates"), in: aboutDocumentView)
        let githubButton = try findButton(title: L10n.tr("GitHub"), in: aboutDocumentView)
        let actionFrame = updateButton.frame.union(githubButton.frame)
        #expect(abs(actionFrame.midX - aboutDocumentView.bounds.midX) <= 1)

        if let outputPath = ProcessInfo.processInfo.environment["LIQUIDBAR_SETTINGS_ABOUT_VISUAL_QA_PATH"],
           !outputPath.isEmpty {
            try writeWindowContentSnapshot(contentView, to: URL(fileURLWithPath: outputPath))
        }
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
        let appRulesLabel = try findLabel(L10n.tr("App Rules"), in: appsDocumentView)
        #expect(appsDocumentView.bounds.maxY - appRulesLabel.frame.maxY <= 32)

        let advancedDocumentView = try documentView(forTabAt: 3, in: tabController)
        let permissionsLabel = try findLabel(L10n.tr("Permissions"), in: advancedDocumentView)
        #expect(advancedDocumentView.bounds.maxY - permissionsLabel.frame.maxY <= 32)

        let aboutDocumentView = try documentView(forTabAt: 4, in: tabController)
        let brandImageView = try #require(recursiveSubviews(of: aboutDocumentView).compactMap { $0 as? NSImageView }.first {
            $0.frame.width > $0.frame.height * 3.0
                && $0.image?.accessibilityDescription == "LiquidBar"
        })
        #expect(aboutDocumentView.bounds.maxY - brandImageView.frame.maxY <= 32)
    }

    @MainActor
    @Test func settingsTabsCanScrollToBottom() throws {
        let controller = SettingsWindowController()
        defer { controller.close() }

        let window = try #require(controller.window)
        let tabController = try #require(window.contentViewController as? NSTabViewController)

        for index in 0..<tabController.tabViewItems.count {
            let scrollView = try scrollView(forTabAt: index, in: tabController)
            let documentView = try #require(scrollView.documentView)

            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)

            let visibleRect = scrollView.documentVisibleRect
            let lowestSubviewY = try #require(lowestVisibleSubviewY(in: documentView))
            #expect(visibleRect.minY <= 2)
            #expect(lowestSubviewY >= visibleRect.minY)
            #expect(lowestSubviewY <= visibleRect.maxY - 8)
        }
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

    private func localized(_ keys: [String]) -> [String] {
        keys.map { L10n.tr($0) }
    }

    @MainActor
    private func lowestVisibleSubviewY(in view: NSView) -> CGFloat? {
        view.subviews
            .filter { !$0.isHidden && !$0.frame.isEmpty }
            .map(\.frame.minY)
            .min()
    }

    @MainActor
    private func visibleContentFrame(in view: NSView) -> NSRect? {
        let frames = view.subviews
            .filter { !$0.isHidden && !$0.frame.isEmpty }
            .map(\.frame)
        return frames.reduce(nil) { partial, frame in
            partial?.union(frame) ?? frame
        }
    }

    @MainActor
    private func findColorWell(toolTip: String, in view: NSView) throws -> NSColorWell {
        let wells = recursiveSubviews(of: view).compactMap { $0 as? NSColorWell }
        return try #require(wells.first { $0.toolTip == toolTip })
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
