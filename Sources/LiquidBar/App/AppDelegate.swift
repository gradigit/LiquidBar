// AppDelegate.swift — Application lifecycle, wires all components together

import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var eventLoop: EventLoop?
    private var renderer: NativeBarRenderer?
    private var screenChangeObserver: NSObjectProtocol?
    private var dockService: DockService?
    private var statusItem: NSStatusItem?
    private var configWatcher: ConfigFileWatcher?
    private var liveApplyObserver: NSObjectProtocol?
    private var panelBootstrapRetryWorkItem: DispatchWorkItem?
    private var didRequestAccessibilityAccess = false
    private var didRequestScreenCaptureAccess = false
    private var didRequestListenEventAccess = false

    // Menu item tags for checkmark updates
    private static let tagPositionTop = 100
    private static let tagPositionBottom = 101
    private static let tagPositionLeft = 102
    private static let tagPositionRight = 103
    private static let tagPositionMenu = 110
    private static let tagScrollWheelCycle = 150
    private static let tagScrollWheelHideShow = 151
    private static let tagScrollWheelVolume = 152
    private static let tagScrollWheelOff = 153
    private static let tagScrollWheelMenu = 160
    private static let tagIconsOnly = 200
    private static let tagShowHidden = 201
    private static let tagShowMinimized = 205
    private static let tagHideDock = 202
    private static let tagLoginItem = 203
    private static let tagAdjustWindows = 204

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Config
        let config = Config.load()
        L10n.applyAppLanguage(config.appLanguage)
        Log.app.info("Config loaded: height=\(config.taskbarHeight), position=\(config.taskbarPosition.rawValue)")

        // 2. Native retained renderer
        let renderer = NativeBarRenderer()
        self.renderer = renderer

        // 3. Panel manager + panels
        let panelManager = PanelManager()
        panelManager.createPanels(config: config, renderer: renderer)

        // 4. Event loop
        let loop = EventLoop(
            config: config,
            renderer: renderer,
            panelManager: panelManager
        )
        loop.onOpenPreferences = { [weak self] in
            self?.showSettings()
        }
        loop.start()
        eventLoop = loop
        schedulePanelBootstrapCheck(attempt: 1)

        // 5. Screen change notification
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.eventLoop?.handleScreenParametersChanged()
            }
        }

        // 6. Accessibility permission
        // Don't auto-prompt on cold start — request only when a feature that needs AX is enabled.
        requestAccessibilityAccessIfNeeded(config: config)
        requestScreenCaptureAccessIfNeeded(config: config)
        requestListenEventAccessIfNeeded(config: config)

        // 7. Dock auto-hide
        dockService = DockService()
        dockService?.restoreIfNeeded()
        applyDockVisibility(config: config)

        // 8. App icon
        NSApp.applicationIconImage = LiquidBarLogo.makeApplicationIcon()

        // 9. Menu bar status item
        updateStatusItemVisibility(config: config)

        // 10. Hot-reload config.json changes (when edited manually).
        configWatcher = ConfigFileWatcher(configPath: Config.configPath) { [weak self] in
            guard let self else { return }
            self.eventLoop?.reloadConfig()
            let config = Config.load()
            L10n.applyAppLanguage(config.appLanguage)
            self.applyDockVisibility(config: config)
            self.updateStatusItemVisibility(config: config)
            self.requestAccessibilityAccessIfNeeded(config: config)
            self.requestScreenCaptureAccessIfNeeded(config: config)
            self.requestListenEventAccessIfNeeded(config: config)
        }
        updateConfigWatcherState()
        liveApplyObserver = NotificationCenter.default.addObserver(
            forName: LiveApplySettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateConfigWatcherState() }
        }

        Log.app.info("LiquidBar started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelBootstrapRetryWorkItem?.cancel()
        panelBootstrapRetryWorkItem = nil
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        if let observer = liveApplyObserver {
            NotificationCenter.default.removeObserver(observer)
            liveApplyObserver = nil
        }
        dockService?.restoreDock()
        eventLoop?.stop()
        eventLoop = nil
        configWatcher?.stop()
        configWatcher = nil
        renderer = nil
        removeStatusItem()
        Log.app.info("LiquidBar terminated")
    }

    private func schedulePanelBootstrapCheck(attempt: Int) {
        panelBootstrapRetryWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self, let loop = self.eventLoop else { return }

            if self.panelsAreHealthy(loop: loop) {
                return
            }

            Log.ui.error("Taskbar panels not healthy at startup (attempt \(attempt)); forcing panel rebuild")
            loop.reloadConfig()

            if !self.panelsAreHealthy(loop: loop), attempt < 10 {
                self.schedulePanelBootstrapCheck(attempt: attempt + 1)
            }
        }

        panelBootstrapRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func panelsAreHealthy(loop: EventLoop) -> Bool {
        let panels = loop.panelManager.allPanels
        guard !panels.isEmpty else { return false }
        return panels.allSatisfy { panel in
            panel.frame.width > 10 &&
            panel.frame.height > 10 &&
            panel.barView.bounds.width > 10 &&
            panel.barView.bounds.height > 10
        }
    }

    // MARK: - Settings

    func showSettings() {
        SettingsWindowController.showSettings()
        SettingsWindowController.shared?.onConfigChanged = { [weak self] in
            guard let self else { return }
            // When Live Apply is enabled, config writes are reloaded via the file watcher.
            if !LiveApplySettings.isEnabled() {
                self.eventLoop?.reloadConfig()
            }
            let config = Config.load()
            L10n.applyAppLanguage(config.appLanguage)
            self.applyDockVisibility(config: config)
            self.updateStatusItemVisibility(config: config)
            self.requestAccessibilityAccessIfNeeded(config: config)
            self.requestScreenCaptureAccessIfNeeded(config: config)
            self.requestListenEventAccessIfNeeded(config: config)
        }
        SettingsWindowController.shared?.onReloadRequested = { [weak self] in
            guard let self else { return }
            self.eventLoop?.reloadConfig()
            let config = Config.load()
            L10n.applyAppLanguage(config.appLanguage)
            self.applyDockVisibility(config: config)
            self.updateStatusItemVisibility(config: config)
            self.requestAccessibilityAccessIfNeeded(config: config)
            self.requestScreenCaptureAccessIfNeeded(config: config)
            self.requestListenEventAccessIfNeeded(config: config)
        }
    }

    private func applyDockVisibility(config: Config = Config.load()) {
        if config.hideDock {
            dockService?.hideDock()
        } else {
            dockService?.restoreDock()
        }
    }

    private func updateConfigWatcherState() {
        if LiveApplySettings.isEnabled() {
            configWatcher?.start()
        } else {
            configWatcher?.stop()
        }
    }

    static func shouldRequestAccessibilityAccess(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preflightGranted: Bool = AXIsProcessTrusted()
    ) -> Bool {
        (config.adjustWindowsForTaskbar || config.experimentalWindowLayoutMemoryEnabled) &&
            environment["LIQUIDBAR_DISABLE_AX_PROMPT"] != "1" &&
            !preflightGranted
    }

    private func requestAccessibilityAccessIfNeeded(config: Config) {
        guard !didRequestAccessibilityAccess,
              Self.shouldRequestAccessibilityAccess(config: config) else { return }
        didRequestAccessibilityAccess = true
        AccessibilityService.requestPermission()
    }

    static func shouldRequestScreenCaptureAccess(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preflightGranted: Bool = CGPreflightScreenCaptureAccess()
    ) -> Bool {
        shouldPrimeScreenCaptureKit(
            config: config,
            environment: environment
        ) && !preflightGranted
    }

    static func shouldPrimeScreenCaptureKit(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        config.previewsEnabled &&
        environment["LIQUIDBAR_DISABLE_SCREEN_RECORDING_PROMPT"] != "1"
    }

    private func requestScreenCaptureAccessIfNeeded(config: Config) {
        guard !didRequestScreenCaptureAccess,
              Self.shouldPrimeScreenCaptureKit(config: config) else { return }
        didRequestScreenCaptureAccess = true
        let shouldRequestCGAccess = Self.shouldRequestScreenCaptureAccess(config: config)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if shouldRequestCGAccess {
                _ = CGRequestScreenCaptureAccess()
            }
            Self.primeScreenCaptureKitPermissionListing()
        }
    }

    private static func primeScreenCaptureKitPermissionListing() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { _, error in
            if let error {
                Log.event.debug("ScreenCaptureKit permission prime failed: \(String(describing: error))")
            }
        }
    }

    static func shouldRequestListenEventAccess(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard config.switcherEnabled,
              environment["LIQUIDBAR_DISABLE_INPUT_MONITORING_PROMPT"] != "1",
              let shortcut = HotkeyShortcut.parse(config.switcherHotkey) else {
            return false
        }
        return shortcut.requiresCGEventTap
    }

    private func requestListenEventAccessIfNeeded(config: Config) {
        guard !didRequestListenEventAccess,
              Self.shouldRequestListenEventAccess(config: config) else { return }
        didRequestListenEventAccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = HotkeyMonitor.requestListenEventAccess()
        }
    }

    // MARK: - Status Item

    private func updateStatusItemVisibility(config: Config = Config.load()) {
        if config.showMenuBarIcon {
            setupStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: LiquidBarLogo.menuBarStatusItemLength)
        } else {
            statusItem?.length = LiquidBarLogo.menuBarStatusItemLength
        }
        if let button = statusItem?.button {
            button.image = LiquidBarLogo.makeMenuBarTemplateImage()
        }
        let menu = buildStatusMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        // Position submenu
        let positionItem = NSMenuItem(title: L10n.tr("Position"), action: nil, keyEquivalent: "")
        positionItem.tag = Self.tagPositionMenu
        let positionSubmenu = NSMenu()

        let topItem = NSMenuItem(title: L10n.tr("Top"), action: #selector(setPositionTop), keyEquivalent: "")
        topItem.target = self
        topItem.tag = Self.tagPositionTop
        positionSubmenu.addItem(topItem)

        let bottomItem = NSMenuItem(title: L10n.tr("Bottom"), action: #selector(setPositionBottom), keyEquivalent: "")
        bottomItem.target = self
        bottomItem.tag = Self.tagPositionBottom
        positionSubmenu.addItem(bottomItem)

        let leftItem = NSMenuItem(title: L10n.tr("Left"), action: #selector(setPositionLeft), keyEquivalent: "")
        leftItem.target = self
        leftItem.tag = Self.tagPositionLeft
        positionSubmenu.addItem(leftItem)

        let rightItem = NSMenuItem(title: L10n.tr("Right"), action: #selector(setPositionRight), keyEquivalent: "")
        rightItem.target = self
        rightItem.tag = Self.tagPositionRight
        positionSubmenu.addItem(rightItem)

        positionItem.submenu = positionSubmenu
        menu.addItem(positionItem)

        // Scroll wheel submenu
        let scrollItem = NSMenuItem(title: L10n.tr("Scroll Wheel"), action: nil, keyEquivalent: "")
        scrollItem.tag = Self.tagScrollWheelMenu
        let scrollSubmenu = NSMenu()

        let cycleItem = NSMenuItem(title: L10n.tr("Cycle Windows"), action: #selector(setScrollWheelCycleWindows), keyEquivalent: "")
        cycleItem.target = self
        cycleItem.tag = Self.tagScrollWheelCycle
        scrollSubmenu.addItem(cycleItem)

        let hideShowItem = NSMenuItem(title: L10n.tr("Hide/Show LiquidBar"), action: #selector(setScrollWheelHideShow), keyEquivalent: "")
        hideShowItem.target = self
        hideShowItem.tag = Self.tagScrollWheelHideShow
        scrollSubmenu.addItem(hideShowItem)

        let volumeItem = NSMenuItem(title: L10n.tr("System Volume"), action: #selector(setScrollWheelVolume), keyEquivalent: "")
        volumeItem.target = self
        volumeItem.tag = Self.tagScrollWheelVolume
        scrollSubmenu.addItem(volumeItem)

        let offItem = NSMenuItem(title: L10n.tr("Off"), action: #selector(setScrollWheelOff), keyEquivalent: "")
        offItem.target = self
        offItem.tag = Self.tagScrollWheelOff
        scrollSubmenu.addItem(offItem)

        scrollItem.submenu = scrollSubmenu
        menu.addItem(scrollItem)

        menu.addItem(.separator())

        // Icons Only toggle
        let iconsOnlyItem = NSMenuItem(title: L10n.tr("Icons Only"), action: #selector(toggleIconsOnly), keyEquivalent: "")
        iconsOnlyItem.target = self
        iconsOnlyItem.tag = Self.tagIconsOnly
        menu.addItem(iconsOnlyItem)

        // Show Hidden Apps toggle
        let showHiddenItem = NSMenuItem(title: L10n.tr("Show Hidden Apps"), action: #selector(toggleShowHidden), keyEquivalent: "")
        showHiddenItem.target = self
        showHiddenItem.tag = Self.tagShowHidden
        menu.addItem(showHiddenItem)

        // Show Minimized Windows toggle
        let showMinItem = NSMenuItem(title: L10n.tr("Show Minimized Windows"), action: #selector(toggleShowMinimized), keyEquivalent: "")
        showMinItem.target = self
        showMinItem.tag = Self.tagShowMinimized
        menu.addItem(showMinItem)

        // Adjust windows toggle (AX)
        let adjustItem = NSMenuItem(title: L10n.tr("Adjust Windows for Taskbar"), action: #selector(toggleAdjustWindows), keyEquivalent: "")
        adjustItem.target = self
        adjustItem.tag = Self.tagAdjustWindows
        menu.addItem(adjustItem)

        // Hide macOS Dock toggle
        let hideDockItem = NSMenuItem(title: L10n.tr("Auto-hide macOS Dock"), action: #selector(toggleHideDock), keyEquivalent: "")
        hideDockItem.target = self
        hideDockItem.tag = Self.tagHideDock
        menu.addItem(hideDockItem)

        // Launch at Login toggle
        let loginItem = NSMenuItem(title: L10n.tr("Launch at Login"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = Self.tagLoginItem
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Reload config.json (useful when live hot-reload is disabled)
        let reloadItem = NSMenuItem(title: L10n.tr("Reload config.json"), action: #selector(reloadConfigFromDisk), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        // Preferences
        let prefsItem = NSMenuItem(title: L10n.tr("Preferences…"), action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.keyEquivalentModifierMask = .command
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Check for Updates
        let updateItem = NSMenuItem(title: L10n.tr("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        // Quit
        let quitItem = NSMenuItem(title: L10n.tr("Quit LiquidBar"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        // NSMenu delegate is always called on the main thread, so assumeIsolated is safe.
        // Use nonisolated(unsafe) let to avoid sending-risk diagnostic for NSMenu.
        nonisolated(unsafe) let m = menu
        MainActor.assumeIsolated {
            let config = Config.load()

            // Update position submenu checkmarks
            if let positionItem = m.item(withTag: Self.tagPositionMenu),
               let submenu = positionItem.submenu {
                submenu.item(withTag: Self.tagPositionTop)?.state = config.taskbarPosition == .top ? .on : .off
                submenu.item(withTag: Self.tagPositionBottom)?.state = config.taskbarPosition == .bottom ? .on : .off
                submenu.item(withTag: Self.tagPositionLeft)?.state = config.taskbarPosition == .left ? .on : .off
                submenu.item(withTag: Self.tagPositionRight)?.state = config.taskbarPosition == .right ? .on : .off
            }

            // Update scroll wheel submenu checkmarks
            if let scrollItem = m.item(withTag: Self.tagScrollWheelMenu),
               let submenu = scrollItem.submenu {
                submenu.item(withTag: Self.tagScrollWheelCycle)?.state = config.scrollWheelMode == .cycleWindows ? .on : .off
                submenu.item(withTag: Self.tagScrollWheelHideShow)?.state = config.scrollWheelMode == .hideShow ? .on : .off
                submenu.item(withTag: Self.tagScrollWheelVolume)?.state = config.scrollWheelMode == .volume ? .on : .off
                submenu.item(withTag: Self.tagScrollWheelOff)?.state = config.scrollWheelMode == .off ? .on : .off
            }

            // Update toggle checkmarks
            m.item(withTag: Self.tagIconsOnly)?.state = config.iconsOnly ? .on : .off
            m.item(withTag: Self.tagShowHidden)?.state = config.showHiddenApps ? .on : .off
            m.item(withTag: Self.tagShowMinimized)?.state = config.showMinimizedWindows ? .on : .off
            m.item(withTag: Self.tagAdjustWindows)?.state = config.adjustWindowsForTaskbar ? .on : .off
            m.item(withTag: Self.tagHideDock)?.state = config.hideDock ? .on : .off
            m.item(withTag: Self.tagLoginItem)?.state = LoginItem.isEnabled() ? .on : .off
        }
    }

    // MARK: - Menu Actions

    @objc private func setPositionTop() {
        var config = Config.load()
        config.taskbarPosition = .top
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setPositionBottom() {
        var config = Config.load()
        config.taskbarPosition = .bottom
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setPositionLeft() {
        var config = Config.load()
        config.taskbarPosition = .left
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setPositionRight() {
        var config = Config.load()
        config.taskbarPosition = .right
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setScrollWheelCycleWindows() {
        var config = Config.load()
        config.scrollWheelMode = .cycleWindows
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setScrollWheelHideShow() {
        var config = Config.load()
        config.scrollWheelMode = .hideShow
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setScrollWheelVolume() {
        var config = Config.load()
        config.scrollWheelMode = .volume
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func setScrollWheelOff() {
        var config = Config.load()
        config.scrollWheelMode = .off
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func toggleIconsOnly() {
        var config = Config.load()
        config.iconsOnly = !config.iconsOnly
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func toggleShowHidden() {
        var config = Config.load()
        config.showHiddenApps = !config.showHiddenApps
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func toggleShowMinimized() {
        var config = Config.load()
        config.showMinimizedWindows = !config.showMinimizedWindows
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func toggleAdjustWindows() {
        var config = Config.load()
        config.adjustWindowsForTaskbar = !config.adjustWindowsForTaskbar
        config.save()
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }

        // If the user just enabled this feature, prompt for accessibility at that moment.
        if config.adjustWindowsForTaskbar {
            AccessibilityService.requestPermission()
        }
    }

    @objc private func toggleHideDock() {
        var config = Config.load()
        config.hideDock = !config.hideDock
        config.save()
        applyDockVisibility(config: config)
        if !LiveApplySettings.isEnabled() {
            eventLoop?.reloadConfig()
        }
    }

    @objc private func toggleLoginItem() {
        if LoginItem.isEnabled() {
            LoginItem.disable()
        } else {
            try? LoginItem.enable()
        }
    }

    @objc private func openPreferences() {
        showSettings()
    }

    @objc private func reloadConfigFromDisk() {
        eventLoop?.reloadConfig()
        let config = Config.load()
        applyDockVisibility(config: config)
        updateStatusItemVisibility(config: config)
    }

    @objc private func checkForUpdates() {
        Task {
            do {
                if let update = try await Updater.checkForUpdate() {
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("Update Available")
                    alert.informativeText = L10n.tr(
                        "A new version (%@) is available. You are running %@.",
                        update.latest,
                        update.current
                    )
                    alert.addButton(withTitle: L10n.tr("Download"))
                    alert.addButton(withTitle: L10n.tr("Later"))
                    alert.alertStyle = .informational
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        Updater.openReleasePage(url: update.url)
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("No Updates Available")
                    alert.informativeText = L10n.tr("You are running the latest version (%@).", Updater.currentVersion)
                    alert.addButton(withTitle: L10n.tr("OK"))
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = L10n.tr("Update Check Failed")
                alert.informativeText = L10n.tr("Could not check for updates: %@", error.localizedDescription)
                alert.addButton(withTitle: L10n.tr("OK"))
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
