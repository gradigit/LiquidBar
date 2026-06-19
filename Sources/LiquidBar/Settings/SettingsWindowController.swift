import Cocoa

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    static var shared: SettingsWindowController?

    var onConfigChanged: (() -> Void)?
    var onReloadRequested: (() -> Void)?

    private var applyButtons: [NSButton] = []
    private var liveApplyCheckboxes: [NSButton] = []
    private var autoApplyWorkItem: DispatchWorkItem?

    // General tab controls
    private var heightSlider: NSSlider!
    private var heightLabel: NSTextField!
    private var positionPopup: NSPopUpButton!
    private var sidebarModeCheckbox: NSButton!
    private var sidebarStatePopup: NSPopUpButton!
    private var sidebarExpandTriggerPopup: NSPopUpButton!
    private var tileZoneCheckbox: NSButton!
    private var tilePopupSingletonCheckbox: NSButton!
    private var hoverDelayField: NSTextField!
    private var hoverIntentGuardCheckbox: NSButton!
    private var switcherEnabledCheckbox: NSButton!
    private var switcherHotkeyField: NSTextField!
    private var iconsOnlyCheckbox: NSButton!
    private var groupByAppCheckbox: NSButton!
    private var tabbedTaskbarCheckbox: NSButton!
    private var showHiddenCheckbox: NSButton!
    private var hiddenModePopup: NSPopUpButton!
    private var showMinimizedCheckbox: NSButton!
    private var adjustWindowsCheckbox: NSButton!
    private var minimizedModePopup: NSPopUpButton!
    private var secondClickPopup: NSPopUpButton!
    private var hideDockCheckbox: NSButton!
    private var loginCheckbox: NSButton!

    // Appearance tab controls
    private var themePopup: NSPopUpButton!
    private var barStylePopup: NSPopUpButton!
    private var glassStylePopup: NSPopUpButton!
    private var hoverIntensityPopup: NSPopUpButton!
    private var focusIndicatorPopup: NSPopUpButton!
    private var stackStylePopup: NSPopUpButton!
    private var stackGeometryPopup: NSPopUpButton!
    private var stackHoverSpreadCheckbox: NSButton!
    private var stackCountBadgeCheckbox: NSButton!
    private var stackCountBadgeStylePopup: NSPopUpButton!
    private var animationProfilePopup: NSPopUpButton!

    // Apps tab controls
    private var blacklistField: NSTextField!
    private var pinnedAppsLabel: NSTextField!
    private var providerRuntimeCheckbox: NSButton!
    private var providerTimeoutField: NSTextField!
    private var providerCircuitBreakerField: NSTextField!

    // About tab controls
    private var updateStatusLabel: NSTextField!
    private var configPathLabel: NSTextField!
    private var perfLoggingCheckbox: NSButton!
    private var perfGpuTimingCheckbox: NSButton!
    private var perfLogIntervalField: NSTextField!

    private let tabViewController = NSTabViewController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LiquidBar Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference

        super.init(window: window)
        window.delegate = self
        buildUI()
        loadConfig()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let window else { return }

        tabViewController.tabStyle = .toolbar

        // General tab
        let generalVC = NSViewController()
        generalVC.view = wrapWithApplyButton(buildGeneralTab())
        generalVC.preferredContentSize = generalVC.view.frame.size
        generalVC.title = "General"
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")
        tabViewController.addTabViewItem(generalItem)

        // Appearance tab
        let appearanceVC = NSViewController()
        appearanceVC.view = wrapWithApplyButton(buildAppearanceTab())
        appearanceVC.preferredContentSize = appearanceVC.view.frame.size
        appearanceVC.title = "Appearance"
        let appearanceItem = NSTabViewItem(viewController: appearanceVC)
        appearanceItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Appearance")
        tabViewController.addTabViewItem(appearanceItem)

        // Apps tab
        let appsVC = NSViewController()
        appsVC.view = wrapWithApplyButton(buildAppsTab())
        appsVC.preferredContentSize = appsVC.view.frame.size
        appsVC.title = "Apps"
        let appsItem = NSTabViewItem(viewController: appsVC)
        appsItem.image = NSImage(systemSymbolName: "app.badge.checkmark", accessibilityDescription: "Apps")
        tabViewController.addTabViewItem(appsItem)

        // About tab
        let aboutVC = NSViewController()
        aboutVC.view = wrapWithApplyButton(buildAboutTab())
        aboutVC.preferredContentSize = aboutVC.view.frame.size
        aboutVC.title = "About"
        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        tabViewController.addTabViewItem(aboutItem)

        // NSTabViewController with .toolbar style creates toolbar items automatically
        window.contentViewController = tabViewController
        // Ensure the full tab content (including lower controls) is visible.
        window.setContentSize(generalVC.view.frame.size)
        window.minSize = NSSize(width: 480, height: 500)
    }

    /// Wraps tab content in a container with an Apply button at the bottom-right.
    private func wrapWithApplyButton(_ contentView: NSView) -> NSView {
        let footerHeight: CGFloat = 44
        let scrollViewportHeight: CGFloat = 520
        let containerW = max(460, contentView.frame.width)
        let containerH = scrollViewportHeight + footerHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerW, height: containerH))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: containerW, height: scrollViewportHeight))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        contentView.frame.origin = .zero
        contentView.frame.size.width = containerW
        contentView.autoresizingMask = [.width]
        scrollView.documentView = contentView
        container.addSubview(scrollView)

        let liveCb = NSButton(frame: NSRect(x: 15, y: 14, width: 230, height: 18))
        liveCb.setButtonType(.switch)
        liveCb.title = "Apply changes automatically"
        liveCb.font = NSFont.systemFont(ofSize: 12)
        liveCb.target = self
        liveCb.action = #selector(liveApplyToggled(_:))
        container.addSubview(liveCb)
        liveApplyCheckboxes.append(liveCb)

        let reloadBtn = NSButton(frame: NSRect(x: 235, y: 10, width: 110, height: 30))
        reloadBtn.bezelStyle = .rounded
        reloadBtn.title = "Reload config"
        reloadBtn.target = self
        reloadBtn.action = #selector(reloadConfigClicked(_:))
        container.addSubview(reloadBtn)

        let applyBtn = NSButton(frame: NSRect(x: 350, y: 10, width: 100, height: 30))
        if let glassStyle = NSButton.BezelStyle(rawValue: 16) {
            applyBtn.bezelStyle = glassStyle
        } else {
            applyBtn.bezelStyle = .rounded
        }
        applyBtn.title = "Apply"
        applyBtn.target = self
        applyBtn.action = #selector(applyClicked(_:))
        container.addSubview(applyBtn)
        applyButtons.append(applyBtn)

        updateApplyControls()

        return container
    }

    // MARK: - Tab Builders

    private func buildGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
        var y: CGFloat = view.bounds.height - 30
        let labelW: CGFloat = 150
        let controlX: CGFloat = 165

        // Taskbar height slider + label
        addLabel("Taskbar Height:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        heightSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 180, height: 22))
        heightSlider.minValue = 32
        heightSlider.maxValue = 64
        heightSlider.target = self
        heightSlider.action = #selector(heightChanged(_:))
        view.addSubview(heightSlider)

        heightLabel = makeLabel("", at: NSPoint(x: 355, y: y), width: 60)
        view.addSubview(heightLabel)

        y -= 36

        // Position popup (top/bottom/left/right)
        addLabel("Position:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        positionPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        positionPopup.addItems(withTitles: ["Top", "Bottom", "Left", "Right"])
        positionPopup.target = self
        positionPopup.action = #selector(controlChanged(_:))
        view.addSubview(positionPopup)

        y -= 36

        sidebarModeCheckbox = makeCheckbox("Enable sidebar mode", at: NSPoint(x: 15, y: y))
        sidebarModeCheckbox.target = self
        sidebarModeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(sidebarModeCheckbox)

        y -= 32

        addLabel("Sidebar Default:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        sidebarStatePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        sidebarStatePopup.addItems(withTitles: ["Expanded", "Compact Icons", "Hidden Peek"])
        sidebarStatePopup.target = self
        sidebarStatePopup.action = #selector(controlChanged(_:))
        view.addSubview(sidebarStatePopup)

        y -= 32

        addLabel("Sidebar Trigger:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        sidebarExpandTriggerPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        sidebarExpandTriggerPopup.addItems(withTitles: ["Click", "Hover", "Hybrid"])
        sidebarExpandTriggerPopup.target = self
        sidebarExpandTriggerPopup.action = #selector(controlChanged(_:))
        view.addSubview(sidebarExpandTriggerPopup)

        y -= 32

        tileZoneCheckbox = makeCheckbox("Enable sidebar tile zone", at: NSPoint(x: 15, y: y))
        tileZoneCheckbox.target = self
        tileZoneCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tileZoneCheckbox)

        y -= 28

        tilePopupSingletonCheckbox = makeCheckbox("Tile popups: one at a time", at: NSPoint(x: 15, y: y))
        tilePopupSingletonCheckbox.target = self
        tilePopupSingletonCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tilePopupSingletonCheckbox)

        y -= 32

        addLabel("Overlay Hover Delay:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        hoverDelayField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22))
        hoverDelayField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        hoverDelayField.alignment = .right
        hoverDelayField.delegate = self
        hoverDelayField.target = self
        hoverDelayField.action = #selector(controlChanged(_:))
        view.addSubview(hoverDelayField)

        let hoverDelaySuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        hoverDelaySuffix.textColor = .secondaryLabelColor
        view.addSubview(hoverDelaySuffix)

        y -= 28

        hoverIntentGuardCheckbox = makeCheckbox("Enable hover intent guard", at: NSPoint(x: 15, y: y))
        hoverIntentGuardCheckbox.target = self
        hoverIntentGuardCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(hoverIntentGuardCheckbox)

        y -= 28

        switcherEnabledCheckbox = makeCheckbox("Enable keyboard switcher overlay", at: NSPoint(x: 15, y: y))
        switcherEnabledCheckbox.target = self
        switcherEnabledCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(switcherEnabledCheckbox)

        y -= 32

        addLabel("Switcher Hotkey:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        switcherHotkeyField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 160, height: 22))
        switcherHotkeyField.placeholderString = "option+tab"
        switcherHotkeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        switcherHotkeyField.delegate = self
        switcherHotkeyField.target = self
        switcherHotkeyField.action = #selector(controlChanged(_:))
        view.addSubview(switcherHotkeyField)

        y -= 32

        // Icons only checkbox
        iconsOnlyCheckbox = makeCheckbox("Icons only (hide window titles)", at: NSPoint(x: 15, y: y))
        iconsOnlyCheckbox.target = self
        iconsOnlyCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(iconsOnlyCheckbox)

        y -= 28

        // Group by app checkbox
        groupByAppCheckbox = makeCheckbox("Group windows by app", at: NSPoint(x: 15, y: y))
        groupByAppCheckbox.target = self
        groupByAppCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(groupByAppCheckbox)

        y -= 28

        // Tabbed taskbar checkbox
        tabbedTaskbarCheckbox = makeCheckbox("Tabbed taskbar (focused item expanded)", at: NSPoint(x: 15, y: y))
        tabbedTaskbarCheckbox.target = self
        tabbedTaskbarCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tabbedTaskbarCheckbox)

        y -= 28

        // Show hidden apps checkbox
        showHiddenCheckbox = makeCheckbox("Show hidden apps (dimmed)", at: NSPoint(x: 15, y: y))
        showHiddenCheckbox.target = self
        showHiddenCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(showHiddenCheckbox)

        y -= 32

        // Hidden window mode popup
        addLabel("Hidden Mode:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        hiddenModePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        hiddenModePopup.addItems(withTitles: ["In-place (dimmed)", "Collapsed to right"])
        hiddenModePopup.target = self
        hiddenModePopup.action = #selector(controlChanged(_:))
        view.addSubview(hiddenModePopup)

        y -= 32

        // Show minimized windows checkbox
        showMinimizedCheckbox = makeCheckbox("Show minimized windows (dimmed)", at: NSPoint(x: 15, y: y))
        showMinimizedCheckbox.target = self
        showMinimizedCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(showMinimizedCheckbox)

        y -= 28

        // Adjust windows to avoid taskbar (AX)
        adjustWindowsCheckbox = makeCheckbox("Adjust windows for taskbar (Accessibility)", at: NSPoint(x: 15, y: y))
        adjustWindowsCheckbox.target = self
        adjustWindowsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(adjustWindowsCheckbox)

        y -= 32

        // Minimized window mode popup
        addLabel("Minimized Mode:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        minimizedModePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        minimizedModePopup.addItems(withTitles: ["In-place (dimmed)", "Collapsed to right"])
        minimizedModePopup.target = self
        minimizedModePopup.action = #selector(controlChanged(_:))
        view.addSubview(minimizedModePopup)

        y -= 32

        // Second click action popup
        addLabel("Second Click:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        secondClickPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        secondClickPopup.addItems(withTitles: ["Hide app (Cmd+H)", "Minimize window", "Do nothing"])
        secondClickPopup.target = self
        secondClickPopup.action = #selector(controlChanged(_:))
        view.addSubview(secondClickPopup)

        y -= 32

        // Hide dock checkbox
        hideDockCheckbox = makeCheckbox("Auto-hide macOS Dock", at: NSPoint(x: 15, y: y))
        hideDockCheckbox.target = self
        hideDockCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(hideDockCheckbox)

        y -= 28

        // Launch at login checkbox
        loginCheckbox = makeCheckbox("Launch at login", at: NSPoint(x: 15, y: y))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(loginCheckbox)

        return view
    }

    private func buildAppearanceTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 430))
        var y: CGFloat = view.bounds.height - 40
        let labelW: CGFloat = 150
        let controlX: CGFloat = 165

        // Theme popup
        addLabel("Theme:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        themePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        themePopup.addItems(withTitles: ["System", "Light", "Dark"])
        themePopup.target = self
        themePopup.action = #selector(controlChanged(_:))
        view.addSubview(themePopup)

        y -= 40

        // Bar style popup
        addLabel("Bar Style:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        barStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        barStylePopup.addItems(withTitles: ["Flush (full-width)", "Floating (rounded)"])
        barStylePopup.target = self
        barStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(barStylePopup)

        y -= 40

        // Glass style popup
        addLabel("Glass Style:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        glassStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        glassStylePopup.addItems(withTitles: ["Regular", "Clear"])
        glassStylePopup.target = self
        glassStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(glassStylePopup)

        y -= 40

        // Hover highlight intensity popup
        addLabel("Hover Highlight:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        hoverIntensityPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        hoverIntensityPopup.addItems(withTitles: ["Subtle", "Medium", "Pronounced"])
        hoverIntensityPopup.target = self
        hoverIntensityPopup.action = #selector(controlChanged(_:))
        view.addSubview(hoverIntensityPopup)

        y -= 40

        addLabel("Animation Profile:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        animationProfilePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 210, height: 26), pullsDown: false)
        animationProfilePopup.addItems(withTitles: ["Balanced Spring", "Snappy Minimal", "Rich Expressive"])
        animationProfilePopup.target = self
        animationProfilePopup.action = #selector(controlChanged(_:))
        view.addSubview(animationProfilePopup)

        y -= 40

        // Focus indicator style
        addLabel("Focused Indicator:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        focusIndicatorPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        focusIndicatorPopup.addItems(withTitles: ["Tile highlight", "Dot"])
        focusIndicatorPopup.target = self
        focusIndicatorPopup.action = #selector(controlChanged(_:))
        view.addSubview(focusIndicatorPopup)

        y -= 40

        // App group stack style (icons-only + group-by-app)
        addLabel("Group Stacks:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        stackStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 200, height: 26), pullsDown: false)
        stackStylePopup.addItems(withTitles: ["Filled glass", "Outline panes"])
        stackStylePopup.target = self
        stackStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(stackStylePopup)

        y -= 40

        addLabel("Stack Geometry:", at: NSPoint(x: 15, y: y), width: labelW, to: view)
        stackGeometryPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        stackGeometryPopup.addItems(withTitles: ["Subtle", "Strong"])
        stackGeometryPopup.target = self
        stackGeometryPopup.action = #selector(controlChanged(_:))
        view.addSubview(stackGeometryPopup)

        y -= 30

        stackHoverSpreadCheckbox = makeCheckbox("Spread stacks on hover", at: NSPoint(x: 15, y: y))
        stackHoverSpreadCheckbox.target = self
        stackHoverSpreadCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(stackHoverSpreadCheckbox)

        y -= 28

        stackCountBadgeCheckbox = makeCheckbox("Show group count badge (all modes)", at: NSPoint(x: 15, y: y))
        stackCountBadgeCheckbox.frame.size.width = 210
        stackCountBadgeCheckbox.target = self
        stackCountBadgeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(stackCountBadgeCheckbox)

        addLabel("Style:", at: NSPoint(x: 230, y: y + 2), width: 45, to: view)
        stackCountBadgeStylePopup = NSPopUpButton(frame: NSRect(x: 275, y: y - 2, width: 140, height: 26), pullsDown: false)
        stackCountBadgeStylePopup.addItems(withTitles: ["Minimal", "Pill", "Separator"])
        stackCountBadgeStylePopup.target = self
        stackCountBadgeStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(stackCountBadgeStylePopup)

        return view
    }

    private func buildAppsTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 430))
        var y: CGFloat = 370
        let labelW: CGFloat = 150
        let controlX: CGFloat = 165

        // Blacklisted apps
        addLabel("Blacklisted Apps:", at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        blacklistField = NSTextField(frame: NSRect(x: controlX, y: y, width: 260, height: 22))
        blacklistField.placeholderString = "com.app.one, com.app.two"
        blacklistField.font = NSFont.systemFont(ofSize: 11)
        blacklistField.delegate = self
        view.addSubview(blacklistField)

        y -= 44

        // Pinned apps (read-only)
        addLabel("Pinned Apps:", at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        pinnedAppsLabel = makeLabel("", at: NSPoint(x: controlX, y: y), width: 260)
        pinnedAppsLabel.font = NSFont.systemFont(ofSize: 11)
        pinnedAppsLabel.textColor = .secondaryLabelColor
        view.addSubview(pinnedAppsLabel)

        y -= 44

        addLabel("Provider Runtime:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerRuntimeCheckbox = makeCheckbox("Enable provider runtime", at: NSPoint(x: controlX, y: y - 2))
        providerRuntimeCheckbox.target = self
        providerRuntimeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(providerRuntimeCheckbox)

        y -= 34

        addLabel("Provider Timeout:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerTimeoutField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22))
        providerTimeoutField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        providerTimeoutField.alignment = .right
        providerTimeoutField.delegate = self
        providerTimeoutField.target = self
        providerTimeoutField.action = #selector(controlChanged(_:))
        view.addSubview(providerTimeoutField)
        let timeoutSuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        timeoutSuffix.textColor = .secondaryLabelColor
        view.addSubview(timeoutSuffix)

        y -= 34

        addLabel("Circuit Breaker:", at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerCircuitBreakerField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22))
        providerCircuitBreakerField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        providerCircuitBreakerField.alignment = .right
        providerCircuitBreakerField.delegate = self
        providerCircuitBreakerField.target = self
        providerCircuitBreakerField.action = #selector(controlChanged(_:))
        view.addSubview(providerCircuitBreakerField)

        return view
    }

    private func buildAboutTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 390))
        var y: CGFloat = 340

        // App title (large font, centered)
        let titleLabel = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 30))
        titleLabel.stringValue = "LiquidBar"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.alignment = .center
        view.addSubview(titleLabel)

        y -= 30

        // Version text
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? Updater.currentVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        var versionString = "Version \(version)"
        if let build, !build.isEmpty, build != version {
            versionString += " (\(build))"
        }
        let versionLabel = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 20))
        versionLabel.stringValue = versionString
        versionLabel.isEditable = false
        versionLabel.isBordered = false
        versionLabel.backgroundColor = .clear
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        view.addSubview(versionLabel)

        y -= 40

        // Check for Updates button
        let updateBtn = NSButton(frame: NSRect(x: 150, y: y, width: 140, height: 30))
        updateBtn.bezelStyle = .rounded
        updateBtn.title = "Check for Updates"
        updateBtn.target = self
        updateBtn.action = #selector(checkForUpdatesClicked(_:))
        view.addSubview(updateBtn)

        y -= 28

        // Update status label
        updateStatusLabel = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 20))
        updateStatusLabel.stringValue = ""
        updateStatusLabel.isEditable = false
        updateStatusLabel.isBordered = false
        updateStatusLabel.backgroundColor = .clear
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11)
        updateStatusLabel.alignment = .center
        updateStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(updateStatusLabel)

        y -= 36

        // GitHub link
        let linkLabel = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 20))
        linkLabel.isEditable = false
        linkLabel.isBordered = false
        linkLabel.backgroundColor = .clear
        linkLabel.alignment = .center
        linkLabel.allowsEditingTextAttributes = true
        linkLabel.isSelectable = true

        let urlString = "https://github.com/\(Updater.githubRepo)"
        let attrString = NSMutableAttributedString(
            string: urlString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
                .link: URL(string: urlString)!,
            ]
        )
        linkLabel.attributedStringValue = attrString
        view.addSubview(linkLabel)

        y -= 46

        // Config shortcuts
        let openConfigBtn = NSButton(frame: NSRect(x: 80, y: y, width: 140, height: 30))
        openConfigBtn.bezelStyle = .rounded
        openConfigBtn.title = "Open config.json"
        openConfigBtn.target = self
        openConfigBtn.action = #selector(openConfigFile(_:))
        view.addSubview(openConfigBtn)

        let revealConfigBtn = NSButton(frame: NSRect(x: 220, y: y, width: 140, height: 30))
        revealConfigBtn.bezelStyle = .rounded
        revealConfigBtn.title = "Show in Finder"
        revealConfigBtn.target = self
        revealConfigBtn.action = #selector(revealConfigFile(_:))
        view.addSubview(revealConfigBtn)

        y -= 28

        configPathLabel = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 20))
        configPathLabel.stringValue = Config.configPath.path
        configPathLabel.isEditable = false
        configPathLabel.isBordered = false
        configPathLabel.backgroundColor = .clear
        configPathLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        configPathLabel.textColor = .secondaryLabelColor
        configPathLabel.alignment = .center
        if let cell = configPathLabel.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingMiddle
        }
        view.addSubview(configPathLabel)

        y -= 46

        let perfTitle = NSTextField(frame: NSRect(x: 15, y: y, width: 410, height: 20))
        perfTitle.stringValue = "Performance Debugging"
        perfTitle.isEditable = false
        perfTitle.isBordered = false
        perfTitle.backgroundColor = .clear
        perfTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        perfTitle.alignment = .center
        view.addSubview(perfTitle)

        y -= 26

        perfLoggingCheckbox = NSButton(frame: NSRect(x: 60, y: y, width: 320, height: 20))
        perfLoggingCheckbox.setButtonType(.switch)
        perfLoggingCheckbox.title = "Enable performance logging (FPS / poll / CPU frame)"
        perfLoggingCheckbox.font = NSFont.systemFont(ofSize: 12)
        perfLoggingCheckbox.target = self
        perfLoggingCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(perfLoggingCheckbox)

        y -= 24

        perfGpuTimingCheckbox = NSButton(frame: NSRect(x: 60, y: y, width: 320, height: 20))
        perfGpuTimingCheckbox.setButtonType(.switch)
        perfGpuTimingCheckbox.title = "Include detailed renderer timing (legacy flag)"
        perfGpuTimingCheckbox.font = NSFont.systemFont(ofSize: 12)
        perfGpuTimingCheckbox.target = self
        perfGpuTimingCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(perfGpuTimingCheckbox)

        y -= 30

        addLabel("Log Interval (ms):", at: NSPoint(x: 110, y: y + 2), width: 120, to: view)
        perfLogIntervalField = NSTextField(frame: NSRect(x: 230, y: y - 1, width: 80, height: 22))
        perfLogIntervalField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        perfLogIntervalField.alignment = .right
        perfLogIntervalField.delegate = self
        perfLogIntervalField.target = self
        perfLogIntervalField.action = #selector(controlChanged(_:))
        view.addSubview(perfLogIntervalField)

        return view
    }

    // MARK: - Config

    private func loadConfig() {
        let config = Config.load()
        heightSlider.integerValue = config.taskbarHeight
        heightLabel.stringValue = "\(config.taskbarHeight) px"
        switch config.taskbarPosition {
        case .top: positionPopup.selectItem(at: 0)
        case .bottom: positionPopup.selectItem(at: 1)
        case .left: positionPopup.selectItem(at: 2)
        case .right: positionPopup.selectItem(at: 3)
        }
        sidebarModeCheckbox.state = config.sidebarModeEnabled ? .on : .off
        switch config.sidebarStateDefault {
        case .expanded: sidebarStatePopup.selectItem(at: 0)
        case .compactIcons: sidebarStatePopup.selectItem(at: 1)
        case .hiddenPeek: sidebarStatePopup.selectItem(at: 2)
        }
        switch config.sidebarExpandTrigger {
        case .click: sidebarExpandTriggerPopup.selectItem(at: 0)
        case .hover: sidebarExpandTriggerPopup.selectItem(at: 1)
        case .hybrid: sidebarExpandTriggerPopup.selectItem(at: 2)
        }
        tileZoneCheckbox.state = config.tileZoneEnabled ? .on : .off
        tilePopupSingletonCheckbox.state = config.tilePopupSingleton ? .on : .off
        hoverDelayField.stringValue = "\(config.hoverDelayMs)"
        hoverIntentGuardCheckbox.state = config.hoverIntentGuardEnabled ? .on : .off
        switcherEnabledCheckbox.state = config.switcherEnabled ? .on : .off
        switcherHotkeyField.stringValue = config.switcherHotkey
        iconsOnlyCheckbox.state = config.iconsOnly ? .on : .off
        groupByAppCheckbox.state = config.groupByApp ? .on : .off
        tabbedTaskbarCheckbox.state = config.tabbedTaskbarEnabled ? .on : .off
        showHiddenCheckbox.state = config.showHiddenApps ? .on : .off
        showMinimizedCheckbox.state = config.showMinimizedWindows ? .on : .off
        adjustWindowsCheckbox.state = config.adjustWindowsForTaskbar ? .on : .off

        // Hidden mode
        switch config.hiddenWindowMode {
        case .inPlace: hiddenModePopup.selectItem(at: 0)
        case .collapsedRight: hiddenModePopup.selectItem(at: 1)
        }

        // Minimized mode
        switch config.minimizedWindowMode {
        case .inPlace: minimizedModePopup.selectItem(at: 0)
        case .collapsedRight: minimizedModePopup.selectItem(at: 1)
        }

        switch config.secondClickAction {
        case .hide: secondClickPopup.selectItem(at: 0)
        case .minimize: secondClickPopup.selectItem(at: 1)
        case .none: secondClickPopup.selectItem(at: 2)
        }

        hideDockCheckbox.state = config.hideDock ? .on : .off
        loginCheckbox.state = LoginItem.isEnabled() ? .on : .off

        // Appearance
        switch config.theme {
        case .system: themePopup.selectItem(at: 0)
        case .light: themePopup.selectItem(at: 1)
        case .dark: themePopup.selectItem(at: 2)
        }

        switch config.barStyle {
        case .flush: barStylePopup.selectItem(at: 0)
        case .floating: barStylePopup.selectItem(at: 1)
        }

        switch config.glassStyle {
        case .publicRegular: glassStylePopup.selectItem(at: 0)
        case .publicClear: glassStylePopup.selectItem(at: 1)
        }

        switch config.hoverIntensity {
        case .subtle: hoverIntensityPopup.selectItem(at: 0)
        case .medium: hoverIntensityPopup.selectItem(at: 1)
        case .pronounced: hoverIntensityPopup.selectItem(at: 2)
        }
        switch config.animationProfile {
        case .balancedSpring: animationProfilePopup.selectItem(at: 0)
        case .snappyMinimal: animationProfilePopup.selectItem(at: 1)
        case .richExpressive: animationProfilePopup.selectItem(at: 2)
        }

        switch config.focusIndicatorStyle {
        case .tile: focusIndicatorPopup.selectItem(at: 0)
        case .dot: focusIndicatorPopup.selectItem(at: 1)
        }

        switch config.appGroupStackStyle {
        case .filled: stackStylePopup.selectItem(at: 0)
        case .outline: stackStylePopup.selectItem(at: 1)
        }

        switch config.appGroupStackGeometry {
        case .subtle: stackGeometryPopup.selectItem(at: 0)
        case .strong: stackGeometryPopup.selectItem(at: 1)
        }

        stackHoverSpreadCheckbox.state = config.appGroupStackHoverSpreadEnabled ? .on : .off
        stackCountBadgeCheckbox.state = config.appGroupCountBadgeInIconsOnly ? .on : .off
        switch config.appGroupCountBadgeStyle {
        case .minimal: stackCountBadgeStylePopup.selectItem(at: 0)
        case .pill: stackCountBadgeStylePopup.selectItem(at: 1)
        case .compactDot: stackCountBadgeStylePopup.selectItem(at: 0)
        case .separator: stackCountBadgeStylePopup.selectItem(at: 2)
        }
        updateCountBadgeControlsEnabledState()

        // Apps
        blacklistField.stringValue = config.blacklistedApps.joined(separator: ", ")
        if config.pinnedApps.isEmpty {
            pinnedAppsLabel.stringValue = "(none)"
        } else {
            pinnedAppsLabel.stringValue = config.pinnedApps.joined(separator: ", ")
        }
        providerRuntimeCheckbox.state = config.providerRuntimeEnabled ? .on : .off
        providerTimeoutField.stringValue = "\(config.providerTimeoutMs)"
        providerCircuitBreakerField.stringValue = "\(config.providerCircuitBreakerThreshold)"
        updateSwitcherControlsEnabledState()
        updateSidebarControlsEnabledState()
        updateProviderControlsEnabledState()

        // Reset update status
        updateStatusLabel.stringValue = ""
        perfLoggingCheckbox.state = config.performanceLoggingEnabled ? .on : .off
        perfGpuTimingCheckbox.state = config.performanceGpuTimingEnabled ? .on : .off
        perfLogIntervalField.stringValue = "\(config.performanceLogIntervalMs)"
        updatePerfControlsEnabledState()
    }

    // MARK: - Actions

    @objc private func heightChanged(_ sender: NSSlider) {
        heightLabel.stringValue = "\(sender.integerValue) px"
        scheduleAutoApply()
    }

    @objc private func controlChanged(_ sender: Any) {
        updatePerfControlsEnabledState()
        updateCountBadgeControlsEnabledState()
        updateSwitcherControlsEnabledState()
        updateSidebarControlsEnabledState()
        updateProviderControlsEnabledState()
        scheduleAutoApply()
    }

    @objc private func liveApplyToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        LiveApplySettings.setEnabled(enabled)
        updateApplyControls()
        scheduleAutoApply()
    }

    @objc private func reloadConfigClicked(_ sender: Any) {
        autoApplyWorkItem?.cancel()
        autoApplyWorkItem = nil
        onReloadRequested?()
        loadConfig()
    }

    private func updateApplyControls() {
        let enabled = LiveApplySettings.isEnabled()
        for cb in liveApplyCheckboxes {
            cb.state = enabled ? .on : .off
        }
        for btn in applyButtons {
            btn.isEnabled = !enabled
        }
    }

    private func scheduleAutoApply() {
        guard LiveApplySettings.isEnabled() else { return }
        autoApplyWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applyClicked(self)
        }
        autoApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func updatePerfControlsEnabledState() {
        let enabled = perfLoggingCheckbox.state == .on
        perfGpuTimingCheckbox.isEnabled = enabled
        perfLogIntervalField.isEnabled = enabled
    }

    private func updateCountBadgeControlsEnabledState() {
        stackCountBadgeStylePopup?.isEnabled = stackCountBadgeCheckbox.state == .on
    }

    private func updateProviderControlsEnabledState() {
        let enabled = providerRuntimeCheckbox.state == .on
        providerTimeoutField?.isEnabled = enabled
        providerCircuitBreakerField?.isEnabled = enabled
    }

    private func updateSwitcherControlsEnabledState() {
        switcherHotkeyField?.isEnabled = switcherEnabledCheckbox.state == .on
    }

    private func updateSidebarControlsEnabledState() {
        let sidebarEnabled = sidebarModeCheckbox.state == .on
        sidebarStatePopup?.isEnabled = sidebarEnabled
        sidebarExpandTriggerPopup?.isEnabled = sidebarEnabled
        tileZoneCheckbox?.isEnabled = sidebarEnabled
        tilePopupSingletonCheckbox?.isEnabled = sidebarEnabled && tileZoneCheckbox.state == .on
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === blacklistField ||
            obj.object as? NSTextField === perfLogIntervalField ||
            obj.object as? NSTextField === hoverDelayField ||
            obj.object as? NSTextField === switcherHotkeyField ||
            obj.object as? NSTextField === providerTimeoutField ||
            obj.object as? NSTextField === providerCircuitBreakerField {
            scheduleAutoApply()
        }
    }

    @objc private func applyClicked(_ sender: Any) {
        let blacklist = blacklistField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var config = Config.load()
        config.taskbarHeight = heightSlider.integerValue
        switch positionPopup.indexOfSelectedItem {
        case 0: config.taskbarPosition = .top
        case 1: config.taskbarPosition = .bottom
        case 2: config.taskbarPosition = .left
        case 3: config.taskbarPosition = .right
        default: break
        }
        config.sidebarModeEnabled = sidebarModeCheckbox.state == .on
        switch sidebarStatePopup.indexOfSelectedItem {
        case 0: config.sidebarStateDefault = .expanded
        case 1: config.sidebarStateDefault = .compactIcons
        case 2: config.sidebarStateDefault = .hiddenPeek
        default: break
        }
        switch sidebarExpandTriggerPopup.indexOfSelectedItem {
        case 0: config.sidebarExpandTrigger = .click
        case 1: config.sidebarExpandTrigger = .hover
        case 2: config.sidebarExpandTrigger = .hybrid
        default: break
        }
        config.tileZoneEnabled = tileZoneCheckbox.state == .on
        config.tilePopupSingleton = tilePopupSingletonCheckbox.state == .on
        if let hoverDelay = Int(hoverDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.hoverDelayMs = hoverDelay
        }
        config.hoverIntentGuardEnabled = hoverIntentGuardCheckbox.state == .on
        config.switcherEnabled = switcherEnabledCheckbox.state == .on
        let hotkey = switcherHotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hotkey.isEmpty {
            config.switcherHotkey = hotkey
        }
        config.iconsOnly = iconsOnlyCheckbox.state == .on
        config.groupByApp = groupByAppCheckbox.state == .on
        config.tabbedTaskbarEnabled = tabbedTaskbarCheckbox.state == .on
        config.showHiddenApps = showHiddenCheckbox.state == .on
        config.showMinimizedWindows = showMinimizedCheckbox.state == .on
        let previousAdjustWindows = config.adjustWindowsForTaskbar
        config.adjustWindowsForTaskbar = adjustWindowsCheckbox.state == .on

        // Hidden mode
        switch hiddenModePopup.indexOfSelectedItem {
        case 0: config.hiddenWindowMode = .inPlace
        case 1: config.hiddenWindowMode = .collapsedRight
        default: break
        }

        // Minimized mode
        switch minimizedModePopup.indexOfSelectedItem {
        case 0: config.minimizedWindowMode = .inPlace
        case 1: config.minimizedWindowMode = .collapsedRight
        default: break
        }

        switch secondClickPopup.indexOfSelectedItem {
        case 0: config.secondClickAction = .hide
        case 1: config.secondClickAction = .minimize
        case 2: config.secondClickAction = .none
        default: break
        }

        config.hideDock = hideDockCheckbox.state == .on

        // Appearance
        switch themePopup.indexOfSelectedItem {
        case 0: config.theme = .system
        case 1: config.theme = .light
        case 2: config.theme = .dark
        default: break
        }

        switch barStylePopup.indexOfSelectedItem {
        case 0: config.barStyle = .flush
        case 1: config.barStyle = .floating
        default: break
        }

        switch glassStylePopup.indexOfSelectedItem {
        case 0: config.glassStyle = .publicRegular
        case 1: config.glassStyle = .publicClear
        default: break
        }

        switch hoverIntensityPopup.indexOfSelectedItem {
        case 0: config.hoverIntensity = .subtle
        case 1: config.hoverIntensity = .medium
        case 2: config.hoverIntensity = .pronounced
        default: break
        }
        switch animationProfilePopup.indexOfSelectedItem {
        case 0: config.animationProfile = .balancedSpring
        case 1: config.animationProfile = .snappyMinimal
        case 2: config.animationProfile = .richExpressive
        default: break
        }

        switch focusIndicatorPopup.indexOfSelectedItem {
        case 0: config.focusIndicatorStyle = .tile
        case 1: config.focusIndicatorStyle = .dot
        default: break
        }

        switch stackStylePopup.indexOfSelectedItem {
        case 0: config.appGroupStackStyle = .filled
        case 1: config.appGroupStackStyle = .outline
        default: break
        }

        switch stackGeometryPopup.indexOfSelectedItem {
        case 0: config.appGroupStackGeometry = .subtle
        case 1: config.appGroupStackGeometry = .strong
        default: break
        }

        config.appGroupStackHoverSpreadEnabled = stackHoverSpreadCheckbox.state == .on
        config.appGroupCountBadgeInIconsOnly = stackCountBadgeCheckbox.state == .on
        switch stackCountBadgeStylePopup.indexOfSelectedItem {
        case 0: config.appGroupCountBadgeStyle = .minimal
        case 1: config.appGroupCountBadgeStyle = .pill
        case 2: config.appGroupCountBadgeStyle = .separator
        default: break
        }

        config.performanceLoggingEnabled = perfLoggingCheckbox.state == .on
        config.performanceGpuTimingEnabled = perfGpuTimingCheckbox.state == .on
        if let interval = Int(perfLogIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.performanceLogIntervalMs = interval
        }

        config.blacklistedApps = blacklist
        config.providerRuntimeEnabled = providerRuntimeCheckbox.state == .on
        if let timeout = Int(providerTimeoutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.providerTimeoutMs = timeout
        }
        if let threshold = Int(providerCircuitBreakerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.providerCircuitBreakerThreshold = threshold
        }
        config.validate()
        config.save()

        if config.adjustWindowsForTaskbar && !previousAdjustWindows {
            AccessibilityService.requestPermission()
        }

        onConfigChanged?()

        // Login item (toggle outside config save since it's system state)
        let loginEnabled = loginCheckbox.state == .on
        if loginEnabled != LoginItem.isEnabled() {
            if loginEnabled {
                try? LoginItem.enable()
            } else {
                LoginItem.disable()
            }
        }
    }

    @objc private func checkForUpdatesClicked(_ sender: Any) {
        updateStatusLabel.stringValue = "Checking..."
        Task {
            do {
                if let update = try await Updater.checkForUpdate() {
                    updateStatusLabel.stringValue = "Update available: v\(update.latest)"
                    Updater.openReleasePage(url: update.url)
                } else {
                    updateStatusLabel.stringValue = "You're up to date."
                }
            } catch {
                updateStatusLabel.stringValue = "Update check failed."
            }
        }
    }

    @objc private func openConfigFile(_ sender: Any) {
        ensureConfigFileExists()
        NSWorkspace.shared.open(Config.configPath)
    }

    @objc private func revealConfigFile(_ sender: Any) {
        ensureConfigFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([Config.configPath])
    }

    private func ensureConfigFileExists() {
        if !FileManager.default.fileExists(atPath: Config.configPath.path) {
            Config().save()
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.shared = nil
        }
    }

    // MARK: - Show

    static func showSettings() {
        if shared == nil {
            shared = SettingsWindowController()
        }
        shared?.loadConfig()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Helpers

    @discardableResult
    private func addLabel(_ text: String, at point: NSPoint, width: CGFloat, to parent: NSView) -> NSTextField {
        let label = makeLabel(text, at: point, width: width)
        parent.addSubview(label)
        return label
    }

    private func makeLabel(_ text: String, at point: NSPoint, width: CGFloat) -> NSTextField {
        let label = NSTextField(frame: NSRect(x: point.x, y: point.y, width: width, height: 20))
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }

    private func makeCheckbox(_ title: String, at point: NSPoint) -> NSButton {
        let cb = NSButton(frame: NSRect(x: point.x, y: point.y, width: 300, height: 22))
        cb.setButtonType(.switch)
        cb.title = title
        cb.font = NSFont.systemFont(ofSize: 13)
        return cb
    }

    #if DEBUG
    deinit {
        Log.ui.debug("SettingsWindowController deinit")
    }
    #endif
}
