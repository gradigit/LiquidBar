import Cocoa
import ApplicationServices
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

enum SettingsIconSizeRange {
    static let minimum = 16
    static let maximum = 48
    static let tickCount = 9
}

private enum SettingsWindowLayout {
    static let contentWidth: CGFloat = 680
    static let scrollViewportHeight: CGFloat = 560
    static let footerHeight: CGFloat = 52
}

private final class SettingsBarPreviewView: NSView {
    var config = Config() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barHeight = CGFloat(config.effectiveTaskbarHeight).clamped(to: 30...54)
        let barWidth = min(bounds.width - 40, 410)
        let barRect = NSRect(
            x: (bounds.width - barWidth) / 2,
            y: (bounds.height - barHeight) / 2,
            width: barWidth,
            height: barHeight
        )
        let cornerRadius = config.barStyle == .floating ? min(18, barHeight / 2) : 8
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
        let fillAlpha: CGFloat = config.glassStyle == .publicClear ? 0.36 : 0.68
        NSColor.windowBackgroundColor.withAlphaComponent(fillAlpha).setFill()
        barPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        barPath.lineWidth = 1
        barPath.stroke()

        let iconSize = CGFloat(config.iconSize).clamped(to: 16...48)
        let itemGap: CGFloat = config.groupByApp ? 10 : 8
        let itemY = barRect.midY - iconSize / 2
        var itemX = barRect.minX + 18

        for index in 0..<5 {
            let isFocused = index == 1
            let itemWidth: CGFloat = config.iconsOnly ? iconSize + 10 : min(CGFloat(config.maxItemWidth), 72)
            let itemRect = NSRect(x: itemX, y: barRect.midY - (iconSize + 10) / 2, width: itemWidth, height: iconSize + 10)
            if isFocused {
                let focusPath = NSBezierPath(roundedRect: itemRect, xRadius: 9, yRadius: 9)
                let focusAlpha: CGFloat = config.focusIndicatorStyle == .tile ? 0.44 : 0.18
                NSColor.controlAccentColor.withAlphaComponent(focusAlpha).setFill()
                focusPath.fill()
            }

            let iconRect = NSRect(x: itemX + 5, y: itemY, width: iconSize, height: iconSize)
            let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: min(8, iconSize / 4), yRadius: min(8, iconSize / 4))
            let hue = CGFloat(index) / 7.0
            NSColor(calibratedHue: hue, saturation: 0.45, brightness: 0.78, alpha: 0.9).setFill()
            iconPath.fill()

            if !config.iconsOnly {
                let titleRect = NSRect(x: iconRect.maxX + 8, y: barRect.midY - 4, width: max(18, itemWidth - iconSize - 18), height: 8)
                let titlePath = NSBezierPath(roundedRect: titleRect, xRadius: 4, yRadius: 4)
                NSColor.labelColor.withAlphaComponent(isFocused ? 0.45 : 0.24).setFill()
                titlePath.fill()
            }

            if isFocused, config.focusIndicatorStyle == .dot {
                let dotRect = NSRect(x: itemRect.midX - 8, y: barRect.maxY - 6, width: 16, height: 3)
                let dotPath = NSBezierPath(roundedRect: dotRect, xRadius: 2, yRadius: 2)
                NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
                dotPath.fill()
            }

            itemX += itemWidth + itemGap
        }
    }
}

private final class FocusClearingTabViewController: NSTabViewController {
    var onDidSelectTabViewItem: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onDidSelectTabViewItem?()
    }
}

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
    private var switcherScopePopup: NSPopUpButton!
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
    private var showMenuBarIconCheckbox: NSButton!
    private var appLanguagePopup: NSPopUpButton!
    private var loginCheckbox: NSButton!
    private var itemSizingPopup: NSPopUpButton!
    private var maxItemWidthSlider: NSSlider!
    private var maxItemWidthLabel: NSTextField!
    private var maxTitleWidthSlider: NSSlider!
    private var maxTitleWidthLabel: NSTextField!
    private var centerItemsCheckbox: NSButton!
    private var multiMonitorPopup: NSPopUpButton!
    private var windowDisplayPopup: NSPopUpButton!
    private var scrollWheelPopup: NSPopUpButton!
    private var launcherEnabledCheckbox: NSButton!
    private var launcherActionPopup: NSPopUpButton!
    private var launcherCustomUrlField: NSTextField!

    // Appearance tab controls
    private var appearancePreviewView: SettingsBarPreviewView!
    private var themePopup: NSPopUpButton!
    private var barStylePopup: NSPopUpButton!
    private var glassStylePopup: NSPopUpButton!
    private var iconSizeSlider: NSSlider!
    private var iconSizeLabel: NSTextField!
    private var titleFontSizeSlider: NSSlider!
    private var titleFontSizeLabel: NSTextField!
    private var hoverIntensityPopup: NSPopUpButton!
    private var visualDepthPopup: NSPopUpButton!
    private var focusIndicatorPopup: NSPopUpButton!
    private var stackStylePopup: NSPopUpButton!
    private var stackGeometryPopup: NSPopUpButton!
    private var stackHoverSpreadCheckbox: NSButton!
    private var stackCountBadgeCheckbox: NSButton!
    private var stackCountBadgeStylePopup: NSPopUpButton!
    private var animationProfilePopup: NSPopUpButton!
    private var systemIndicatorsCheckbox: NSButton!
    private var systemIndicatorPlacementPopup: NSPopUpButton!
    private var systemIndicatorDisplayScopePopup: NSPopUpButton!
    private var systemIndicatorSelectedDisplayPopup: NSPopUpButton!
    private var systemIndicatorChipPresetPopup: NSPopUpButton!
    private var systemIndicatorAppearancePopup: NSPopUpButton!
    private var systemIndicatorTemperatureUnitPopup: NSPopUpButton!
    private var systemIndicatorRefreshField: NSTextField!
    private var systemIndicatorCpuCheckbox: NSButton!
    private var systemIndicatorCpuModePopup: NSPopUpButton!
    private var systemIndicatorCpuColorWell: NSColorWell!
    private var systemIndicatorGpuCheckbox: NSButton!
    private var systemIndicatorGpuModePopup: NSPopUpButton!
    private var systemIndicatorGpuColorWell: NSColorWell!
    private var systemIndicatorRamCheckbox: NSButton!
    private var systemIndicatorRamModePopup: NSPopUpButton!
    private var systemIndicatorRamColorWell: NSColorWell!
    private var systemIndicatorThermalCheckbox: NSButton!
    private var systemIndicatorThermalModePopup: NSPopUpButton!
    private var systemIndicatorThermalColorWell: NSColorWell!
    private var systemIndicatorGraphSamplesSlider: NSSlider!
    private var systemIndicatorGraphSamplesLabel: NSTextField!

    // Apps tab controls
    private var blacklistField: NSTextField!
    private var pinnedAppsLabel: NSTextField!
    private var pinnedAppsScopePopup: NSPopUpButton!
    private var pendingPinnedApps: [String]?

    // Advanced tab controls
    private var accessibilityStatusLabel: NSTextField!
    private var inputMonitoringStatusLabel: NSTextField!
    private var screenRecordingStatusLabel: NSTextField!
    private var previewsEnabledCheckbox: NSButton!
    private var previewHoverDelayField: NSTextField!
    private var previewMemoryPresetPopup: NSPopUpButton!
    private var providerRuntimeCheckbox: NSButton!
    private var providerTimeoutField: NSTextField!
    private var providerCircuitBreakerField: NSTextField!
    private var perfLoggingCheckbox: NSButton!
    private var perfHangDiagnosticsCheckbox: NSButton!
    private var perfLogIntervalField: NSTextField!
    private var pluginsEnabledCheckbox: NSButton!
    private var windowTabGroupsCheckbox: NSButton!
    private var tabGroupHoverDelayField: NSTextField!
    private var tabGroupCollapseCheckbox: NSButton!

    // About tab controls
    private var updateStatusLabel: NSTextField!
    private var configPathLabel: NSTextField!

    private let tabViewController = FocusClearingTabViewController()

    init(configOverride: Config? = nil) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindowLayout.contentWidth,
                height: SettingsWindowLayout.scrollViewportHeight + SettingsWindowLayout.footerHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("LiquidBar Preferences")
        window.center()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)
        window.delegate = self
        buildUI()
        if let configOverride {
            applyConfigToControls(configOverride)
        } else {
            loadConfig()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let window else { return }

        tabViewController.tabStyle = .toolbar
        tabViewController.onDidSelectTabViewItem = { [weak self] in
            self?.clearTransientTextFocus()
        }

        // General tab
        let generalVC = NSViewController()
        generalVC.view = wrapWithApplyButton(buildGeneralTab())
        generalVC.preferredContentSize = generalVC.view.frame.size
        generalVC.title = L10n.tr("General")
        let generalItem = NSTabViewItem(viewController: generalVC)
        generalItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L10n.tr("General"))
        tabViewController.addTabViewItem(generalItem)

        // Appearance tab
        let appearanceVC = NSViewController()
        appearanceVC.view = wrapWithApplyButton(buildAppearanceTab())
        appearanceVC.preferredContentSize = appearanceVC.view.frame.size
        appearanceVC.title = L10n.tr("Appearance")
        let appearanceItem = NSTabViewItem(viewController: appearanceVC)
        appearanceItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: L10n.tr("Appearance"))
        tabViewController.addTabViewItem(appearanceItem)

        // Apps tab
        let appsVC = NSViewController()
        appsVC.view = wrapWithApplyButton(buildAppsTab())
        appsVC.preferredContentSize = appsVC.view.frame.size
        appsVC.title = L10n.tr("Apps")
        let appsItem = NSTabViewItem(viewController: appsVC)
        appsItem.image = NSImage(systemSymbolName: "app.badge.checkmark", accessibilityDescription: L10n.tr("Apps"))
        tabViewController.addTabViewItem(appsItem)

        // Advanced tab
        let advancedVC = NSViewController()
        advancedVC.view = wrapWithApplyButton(buildAdvancedTab())
        advancedVC.preferredContentSize = advancedVC.view.frame.size
        advancedVC.title = L10n.tr("Advanced")
        let advancedItem = NSTabViewItem(viewController: advancedVC)
        advancedItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: L10n.tr("Advanced"))
        tabViewController.addTabViewItem(advancedItem)

        // About tab
        let aboutVC = NSViewController()
        aboutVC.view = wrapWithApplyButton(buildAboutTab())
        aboutVC.preferredContentSize = aboutVC.view.frame.size
        aboutVC.title = L10n.tr("About")
        let aboutItem = NSTabViewItem(viewController: aboutVC)
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: L10n.tr("About"))
        tabViewController.addTabViewItem(aboutItem)

        // NSTabViewController with .toolbar style creates toolbar items automatically
        window.contentViewController = tabViewController
        // Ensure the full tab content (including lower controls) is visible.
        window.setContentSize(generalVC.view.frame.size)
        window.minSize = NSSize(width: 620, height: 560)
    }

    private func rebuildUI(applying config: Config) {
        guard let window else { return }
        let selectedIndex = max(0, tabViewController.selectedTabViewItemIndex)
        applyButtons.removeAll()
        liveApplyCheckboxes.removeAll()
        for item in tabViewController.tabViewItems.reversed() {
            tabViewController.removeTabViewItem(item)
        }
        window.title = L10n.tr("LiquidBar Preferences")
        buildUI()
        if selectedIndex < tabViewController.tabViewItems.count {
            tabViewController.selectedTabViewItemIndex = selectedIndex
        }
        applyConfigToControls(config)
        scrollSelectedTabToTop()
    }

    /// Wraps tab content in a container with an Apply button at the bottom-right.
    private func wrapWithApplyButton(_ contentView: NSView) -> NSView {
        let footerHeight = SettingsWindowLayout.footerHeight
        let scrollViewportHeight = SettingsWindowLayout.scrollViewportHeight
        let containerW = max(SettingsWindowLayout.contentWidth, contentView.frame.width)
        let containerH = scrollViewportHeight + footerHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerW, height: containerH))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: containerW, height: scrollViewportHeight))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let horizontalShift = max(0, (containerW - contentView.frame.width) / 2)
        if horizontalShift > 0 {
            for subview in contentView.subviews {
                subview.frame.origin.x += horizontalShift
            }
        }

        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = 24
        let minimumSubviewY = contentView.subviews
            .filter { !$0.isHidden && !$0.frame.isEmpty }
            .map(\.frame.minY)
            .min() ?? 0
        let bottomShift = max(bottomPadding, bottomPadding - minimumSubviewY)
        for subview in contentView.subviews {
            subview.frame.origin.y += bottomShift
        }
        contentView.frame.size.height += topPadding + bottomShift

        let minimumDocumentHeight = scrollViewportHeight
        let documentHeightDelta = max(0, minimumDocumentHeight - contentView.frame.height)
        if documentHeightDelta > 0 {
            for subview in contentView.subviews {
                subview.frame.origin.y += documentHeightDelta
            }
            contentView.frame.size.height += documentHeightDelta
        }
        contentView.frame.origin = .zero
        contentView.frame.size.width = containerW
        contentView.autoresizingMask = [.width]
        scrollView.documentView = contentView
        scrollDocumentViewToTop(in: scrollView, fallbackViewportHeight: scrollViewportHeight)
        container.addSubview(scrollView)

        let footer = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: containerW, height: footerHeight))
        footer.material = .contentBackground
        footer.blendingMode = .withinWindow
        footer.state = .active
        footer.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(footer)

        let separator = NSBox(frame: NSRect(x: 0, y: footerHeight - 1, width: containerW, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .minYMargin]
        footer.addSubview(separator)

        let liveCb = NSButton(frame: NSRect(x: 18, y: 17, width: 152, height: 18))
        liveCb.setButtonType(.switch)
        liveCb.title = L10n.tr("Auto Apply")
        liveCb.font = NSFont.systemFont(ofSize: 12)
        liveCb.target = self
        liveCb.action = #selector(liveApplyToggled(_:))
        footer.addSubview(liveCb)
        liveApplyCheckboxes.append(liveCb)

        let trailingPadding: CGFloat = 18
        let buttonGap: CGFloat = 10
        let resetWidth: CGFloat = 112
        let revertWidth: CGFloat = 94
        let reloadWidth: CGFloat = 126
        let applyWidth: CGFloat = 84
        var trailingX = containerW - trailingPadding

        let applyBtn = NSButton(frame: NSRect(x: trailingX - applyWidth, y: 10, width: applyWidth, height: 30))
        trailingX = applyBtn.frame.minX - buttonGap
        if let glassStyle = NSButton.BezelStyle(rawValue: 16) {
            applyBtn.bezelStyle = glassStyle
        } else {
            applyBtn.bezelStyle = .rounded
        }
        applyBtn.title = L10n.tr("Apply")
        applyBtn.toolTip = applyBtn.title
        applyBtn.keyEquivalent = "\r"
        applyBtn.target = self
        applyBtn.action = #selector(applyClicked(_:))
        applyBtn.autoresizingMask = [.minXMargin]
        footer.addSubview(applyBtn)
        applyButtons.append(applyBtn)

        let reloadBtn = NSButton(frame: NSRect(x: trailingX - reloadWidth, y: 10, width: reloadWidth, height: 30))
        trailingX = reloadBtn.frame.minX - buttonGap
        reloadBtn.bezelStyle = .rounded
        reloadBtn.title = L10n.tr("Reload")
        reloadBtn.toolTip = L10n.tr("Reload config.json")
        reloadBtn.target = self
        reloadBtn.action = #selector(reloadConfigClicked(_:))
        reloadBtn.autoresizingMask = [.minXMargin]
        footer.addSubview(reloadBtn)

        let revertBtn = NSButton(frame: NSRect(x: trailingX - revertWidth, y: 10, width: revertWidth, height: 30))
        trailingX = revertBtn.frame.minX - buttonGap
        revertBtn.bezelStyle = .rounded
        revertBtn.title = L10n.tr("Revert")
        revertBtn.toolTip = revertBtn.title
        revertBtn.target = self
        revertBtn.action = #selector(revertClicked(_:))
        revertBtn.autoresizingMask = [.minXMargin]
        footer.addSubview(revertBtn)

        let resetBtn = NSButton(frame: NSRect(x: trailingX - resetWidth, y: 10, width: resetWidth, height: 30))
        resetBtn.bezelStyle = .rounded
        resetBtn.title = L10n.tr("Reset Tab")
        resetBtn.toolTip = resetBtn.title
        resetBtn.target = self
        resetBtn.action = #selector(resetSelectedTabClicked(_:))
        resetBtn.autoresizingMask = [.minXMargin]
        footer.addSubview(resetBtn)

        updateApplyControls()

        return container
    }

    // MARK: - Tab Builders

    private func buildGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 1200))
        var y: CGFloat = view.bounds.height - 30
        let labelW: CGFloat = 160
        let controlX: CGFloat = 180

        addSectionHeader(L10n.tr("Taskbar"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        // Taskbar height slider + label
        addLabel(L10n.tr("Taskbar Height:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
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
        addLabel(L10n.tr("Position:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        positionPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        positionPopup.addItems(withTitles: localizedItems(["Top", "Bottom", "Left", "Right"]))
        positionPopup.target = self
        positionPopup.action = #selector(controlChanged(_:))
        view.addSubview(positionPopup)

        y -= 36

        addSectionHeader(L10n.tr("Layout"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        addLabel(L10n.tr("Item Sizing:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        itemSizingPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        itemSizingPopup.addItems(withTitles: localizedItems(["Uniform", "Auto"]))
        itemSizingPopup.target = self
        itemSizingPopup.action = #selector(controlChanged(_:))
        view.addSubview(itemSizingPopup)

        y -= 36

        addLabel(L10n.tr("Max Item Width:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        maxItemWidthSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 210, height: 22))
        maxItemWidthSlider.minValue = 60
        maxItemWidthSlider.maxValue = 360
        maxItemWidthSlider.numberOfTickMarks = 7
        maxItemWidthSlider.allowsTickMarkValuesOnly = false
        maxItemWidthSlider.target = self
        maxItemWidthSlider.action = #selector(maxItemWidthChanged(_:))
        view.addSubview(maxItemWidthSlider)

        maxItemWidthLabel = makeLabel("", at: NSPoint(x: controlX + 220, y: y + 2), width: 60)
        maxItemWidthLabel.textColor = .secondaryLabelColor
        view.addSubview(maxItemWidthLabel)

        y -= 36

        addLabel(L10n.tr("Max Title Width:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        maxTitleWidthSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 210, height: 22))
        maxTitleWidthSlider.minValue = 20
        maxTitleWidthSlider.maxValue = 240
        maxTitleWidthSlider.numberOfTickMarks = 6
        maxTitleWidthSlider.allowsTickMarkValuesOnly = false
        maxTitleWidthSlider.target = self
        maxTitleWidthSlider.action = #selector(maxTitleWidthChanged(_:))
        view.addSubview(maxTitleWidthSlider)

        maxTitleWidthLabel = makeLabel("", at: NSPoint(x: controlX + 220, y: y + 2), width: 60)
        maxTitleWidthLabel.textColor = .secondaryLabelColor
        view.addSubview(maxTitleWidthLabel)

        y -= 32

        centerItemsCheckbox = makeCheckbox(L10n.tr("Center icons-only bottom bar"), at: NSPoint(x: 15, y: y))
        centerItemsCheckbox.target = self
        centerItemsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(centerItemsCheckbox)

        y -= 36

        addSectionHeader(L10n.tr("Displays"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        addLabel(L10n.tr("Bar Displays:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        multiMonitorPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        multiMonitorPopup.addItems(withTitles: localizedItems(["All Displays", "Main Display Only"]))
        multiMonitorPopup.target = self
        multiMonitorPopup.action = #selector(controlChanged(_:))
        view.addSubview(multiMonitorPopup)

        y -= 36

        addLabel(L10n.tr("Window Scope:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        windowDisplayPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        windowDisplayPopup.addItems(withTitles: localizedItems(["Per Display", "All Windows Everywhere"]))
        windowDisplayPopup.target = self
        windowDisplayPopup.action = #selector(controlChanged(_:))
        view.addSubview(windowDisplayPopup)

        y -= 36

        addSectionHeader(L10n.tr("Sidebar"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        sidebarModeCheckbox = makeCheckbox(L10n.tr("Enable sidebar mode"), at: NSPoint(x: 15, y: y))
        sidebarModeCheckbox.target = self
        sidebarModeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(sidebarModeCheckbox)

        y -= 32

        addLabel(L10n.tr("Sidebar Default:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        sidebarStatePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        sidebarStatePopup.addItems(withTitles: localizedItems(["Expanded", "Compact Icons", "Hidden Peek"]))
        sidebarStatePopup.target = self
        sidebarStatePopup.action = #selector(controlChanged(_:))
        view.addSubview(sidebarStatePopup)

        y -= 32

        addLabel(L10n.tr("Sidebar Trigger:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        sidebarExpandTriggerPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        sidebarExpandTriggerPopup.addItems(withTitles: localizedItems(["Click", "Hover", "Hybrid"]))
        sidebarExpandTriggerPopup.target = self
        sidebarExpandTriggerPopup.action = #selector(controlChanged(_:))
        view.addSubview(sidebarExpandTriggerPopup)

        y -= 32

        tileZoneCheckbox = makeCheckbox(L10n.tr("Enable sidebar tile zone"), at: NSPoint(x: 15, y: y))
        tileZoneCheckbox.target = self
        tileZoneCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tileZoneCheckbox)

        y -= 28

        tilePopupSingletonCheckbox = makeCheckbox(L10n.tr("Tile popups: one at a time"), at: NSPoint(x: 15, y: y))
        tilePopupSingletonCheckbox.target = self
        tilePopupSingletonCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tilePopupSingletonCheckbox)

        y -= 32

        addLabel(L10n.tr("Overlay Hover Delay:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        hoverDelayField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 0, max: 2000)
        hoverDelayField.delegate = self
        hoverDelayField.target = self
        hoverDelayField.action = #selector(controlChanged(_:))
        view.addSubview(hoverDelayField)

        let hoverDelaySuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        hoverDelaySuffix.textColor = .secondaryLabelColor
        view.addSubview(hoverDelaySuffix)

        y -= 28

        hoverIntentGuardCheckbox = makeCheckbox(L10n.tr("Enable hover intent guard"), at: NSPoint(x: 15, y: y))
        hoverIntentGuardCheckbox.target = self
        hoverIntentGuardCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(hoverIntentGuardCheckbox)

        y -= 28

        addSectionHeader(L10n.tr("Switcher"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        switcherEnabledCheckbox = makeCheckbox(L10n.tr("Enable keyboard switcher overlay"), at: NSPoint(x: 15, y: y))
        switcherEnabledCheckbox.target = self
        switcherEnabledCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(switcherEnabledCheckbox)

        y -= 32

        addLabel(L10n.tr("Switcher Hotkey:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        switcherHotkeyField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 160, height: 22))
        switcherHotkeyField.placeholderString = "option+tab"
        switcherHotkeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        switcherHotkeyField.delegate = self
        switcherHotkeyField.target = self
        switcherHotkeyField.action = #selector(controlChanged(_:))
        view.addSubview(switcherHotkeyField)

        y -= 32

        addLabel(L10n.tr("Switcher Windows:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        switcherScopePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 210, height: 26), pullsDown: false)
        switcherScopePopup.addItems(withTitles: localizedItems(["All displays", "Focused display"]))
        switcherScopePopup.target = self
        switcherScopePopup.action = #selector(controlChanged(_:))
        view.addSubview(switcherScopePopup)

        y -= 32

        addLabel(L10n.tr("Scroll Wheel:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        scrollWheelPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 210, height: 26), pullsDown: false)
        scrollWheelPopup.addItems(withTitles: localizedItems(["Cycle Windows", "Hide / Show Bar", "System Volume", "Off"]))
        scrollWheelPopup.target = self
        scrollWheelPopup.action = #selector(controlChanged(_:))
        view.addSubview(scrollWheelPopup)

        y -= 36

        launcherEnabledCheckbox = makeCheckbox(L10n.tr("Show launcher button"), at: NSPoint(x: 15, y: y))
        launcherEnabledCheckbox.target = self
        launcherEnabledCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(launcherEnabledCheckbox)

        y -= 32

        addLabel(L10n.tr("Launcher Action:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        launcherActionPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        launcherActionPopup.addItems(withTitles: localizedItems(["Spotlight", "Raycast", "Alfred", "Custom URL"]))
        launcherActionPopup.target = self
        launcherActionPopup.action = #selector(controlChanged(_:))
        view.addSubview(launcherActionPopup)

        y -= 32

        addLabel(L10n.tr("Custom URL:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        launcherCustomUrlField = NSTextField(frame: NSRect(x: controlX, y: y - 1, width: 260, height: 22))
        launcherCustomUrlField.placeholderString = "raycast://extensions/..."
        launcherCustomUrlField.font = NSFont.systemFont(ofSize: 12)
        launcherCustomUrlField.delegate = self
        launcherCustomUrlField.target = self
        launcherCustomUrlField.action = #selector(controlChanged(_:))
        view.addSubview(launcherCustomUrlField)

        y -= 36

        addSectionHeader(L10n.tr("Window Behavior"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        // Icons only checkbox
        iconsOnlyCheckbox = makeCheckbox(L10n.tr("Icons only (hide window titles)"), at: NSPoint(x: 15, y: y))
        iconsOnlyCheckbox.target = self
        iconsOnlyCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(iconsOnlyCheckbox)

        y -= 28

        // Group by app checkbox
        groupByAppCheckbox = makeCheckbox(L10n.tr("Group windows by app"), at: NSPoint(x: 15, y: y))
        groupByAppCheckbox.target = self
        groupByAppCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(groupByAppCheckbox)

        y -= 28

        // Tabbed taskbar checkbox
        tabbedTaskbarCheckbox = makeCheckbox(L10n.tr("Tabbed taskbar (focused item expanded)"), at: NSPoint(x: 15, y: y))
        tabbedTaskbarCheckbox.target = self
        tabbedTaskbarCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tabbedTaskbarCheckbox)

        y -= 28

        // Show hidden apps checkbox
        showHiddenCheckbox = makeCheckbox(L10n.tr("Show hidden apps (dimmed)"), at: NSPoint(x: 15, y: y))
        showHiddenCheckbox.target = self
        showHiddenCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(showHiddenCheckbox)

        y -= 32

        // Hidden window mode popup
        addLabel(L10n.tr("Hidden Mode:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        hiddenModePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        hiddenModePopup.addItems(withTitles: localizedItems(["In-place (dimmed)", "Collapsed to right"]))
        hiddenModePopup.target = self
        hiddenModePopup.action = #selector(controlChanged(_:))
        view.addSubview(hiddenModePopup)

        y -= 32

        // Show minimized windows checkbox
        showMinimizedCheckbox = makeCheckbox(L10n.tr("Show minimized windows (dimmed)"), at: NSPoint(x: 15, y: y))
        showMinimizedCheckbox.target = self
        showMinimizedCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(showMinimizedCheckbox)

        y -= 28

        // Adjust windows to avoid taskbar (AX)
        adjustWindowsCheckbox = makeCheckbox(L10n.tr("Adjust windows for taskbar (Accessibility)"), at: NSPoint(x: 15, y: y))
        adjustWindowsCheckbox.target = self
        adjustWindowsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(adjustWindowsCheckbox)

        y -= 32

        // Minimized window mode popup
        addLabel(L10n.tr("Minimized Mode:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        minimizedModePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        minimizedModePopup.addItems(withTitles: localizedItems(["In-place (dimmed)", "Collapsed to right"]))
        minimizedModePopup.target = self
        minimizedModePopup.action = #selector(controlChanged(_:))
        view.addSubview(minimizedModePopup)

        y -= 32

        // Second click action popup
        addLabel(L10n.tr("Second Click:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        secondClickPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        secondClickPopup.addItems(withTitles: localizedItems(["Hide app (Cmd+H)", "Minimize window", "Do nothing"]))
        secondClickPopup.target = self
        secondClickPopup.action = #selector(controlChanged(_:))
        view.addSubview(secondClickPopup)

        y -= 32

        addSectionHeader(L10n.tr("System"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        addLabel(L10n.tr("Language:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        appLanguagePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        appLanguagePopup.addItems(withTitles: localizedItems(["System", "English", "Korean"]))
        appLanguagePopup.target = self
        appLanguagePopup.action = #selector(controlChanged(_:))
        view.addSubview(appLanguagePopup)

        y -= 36

        // Hide dock checkbox
        hideDockCheckbox = makeCheckbox(L10n.tr("Auto-hide macOS Dock"), at: NSPoint(x: 15, y: y))
        hideDockCheckbox.target = self
        hideDockCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(hideDockCheckbox)

        y -= 28

        showMenuBarIconCheckbox = makeCheckbox(L10n.tr("Show menu bar icon"), at: NSPoint(x: 15, y: y))
        showMenuBarIconCheckbox.target = self
        showMenuBarIconCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(showMenuBarIconCheckbox)

        y -= 28

        // Launch at login checkbox
        loginCheckbox = makeCheckbox(L10n.tr("Launch at login"), at: NSPoint(x: 15, y: y))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(loginCheckbox)

        return view
    }

    private func buildAppearanceTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 1200))
        var y: CGFloat = view.bounds.height - 36
        let labelW: CGFloat = 160
        let controlX: CGFloat = 180

        addSectionHeader(L10n.tr("Preview"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 110

        appearancePreviewView = SettingsBarPreviewView(frame: NSRect(x: 34, y: y, width: 472, height: 88))
        view.addSubview(appearancePreviewView)

        y -= 38

        addSectionHeader(L10n.tr("Surface"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        // Theme popup
        addLabel(L10n.tr("Theme:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        themePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        themePopup.addItems(withTitles: localizedItems(["System", "Light", "Dark"]))
        themePopup.target = self
        themePopup.action = #selector(controlChanged(_:))
        view.addSubview(themePopup)

        y -= 40

        // Bar style popup
        addLabel(L10n.tr("Bar Style:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        barStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        barStylePopup.addItems(withTitles: localizedItems(["Flush (full-width)", "Floating (rounded)"]))
        barStylePopup.target = self
        barStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(barStylePopup)

        y -= 40

        // Glass style popup
        addLabel(L10n.tr("Glass Style:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        glassStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        glassStylePopup.addItems(withTitles: localizedItems(["Regular", "Clear"]))
        glassStylePopup.target = self
        glassStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(glassStylePopup)

        y -= 40

        addLabel(L10n.tr("Icon Size:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        iconSizeSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 210, height: 22))
        iconSizeSlider.minValue = Double(SettingsIconSizeRange.minimum)
        iconSizeSlider.maxValue = Double(SettingsIconSizeRange.maximum)
        iconSizeSlider.numberOfTickMarks = SettingsIconSizeRange.tickCount
        iconSizeSlider.allowsTickMarkValuesOnly = false
        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(iconSizeChanged(_:))
        view.addSubview(iconSizeSlider)

        iconSizeLabel = makeLabel("", at: NSPoint(x: controlX + 220, y: y + 2), width: 55)
        iconSizeLabel.textColor = .secondaryLabelColor
        view.addSubview(iconSizeLabel)

        y -= 40

        addLabel(L10n.tr("Title Font Size:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        titleFontSizeSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 210, height: 22))
        titleFontSizeSlider.minValue = 10
        titleFontSizeSlider.maxValue = 16
        titleFontSizeSlider.numberOfTickMarks = 7
        titleFontSizeSlider.allowsTickMarkValuesOnly = true
        titleFontSizeSlider.target = self
        titleFontSizeSlider.action = #selector(titleFontSizeChanged(_:))
        view.addSubview(titleFontSizeSlider)

        titleFontSizeLabel = makeLabel("", at: NSPoint(x: controlX + 220, y: y + 2), width: 55)
        titleFontSizeLabel.textColor = .secondaryLabelColor
        view.addSubview(titleFontSizeLabel)

        y -= 40

        addSectionHeader(L10n.tr("Motion & Depth"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        // Hover highlight intensity popup
        addLabel(L10n.tr("Hover Highlight:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        hoverIntensityPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        hoverIntensityPopup.addItems(withTitles: localizedItems(["Subtle", "Medium", "Pronounced"]))
        hoverIntensityPopup.target = self
        hoverIntensityPopup.action = #selector(controlChanged(_:))
        view.addSubview(hoverIntensityPopup)

        y -= 40

        addLabel(L10n.tr("Visual Depth:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        visualDepthPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        visualDepthPopup.addItems(withTitles: localizedItems(["Subtle", "Balanced", "Rich"]))
        visualDepthPopup.target = self
        visualDepthPopup.action = #selector(controlChanged(_:))
        view.addSubview(visualDepthPopup)

        y -= 40

        addLabel(L10n.tr("Animation Profile:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        animationProfilePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 210, height: 26), pullsDown: false)
        animationProfilePopup.addItems(withTitles: localizedItems(["Balanced Spring", "Snappy Minimal", "Rich Expressive"]))
        animationProfilePopup.target = self
        animationProfilePopup.action = #selector(controlChanged(_:))
        view.addSubview(animationProfilePopup)

        y -= 40

        addSectionHeader(L10n.tr("Focus & Groups"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        // Focus indicator style
        addLabel(L10n.tr("Focused Indicator:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        focusIndicatorPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        focusIndicatorPopup.addItems(withTitles: localizedItems(["Tile highlight", "Dot"]))
        focusIndicatorPopup.target = self
        focusIndicatorPopup.action = #selector(controlChanged(_:))
        view.addSubview(focusIndicatorPopup)

        y -= 40

        // App group stack style (icons-only + group-by-app)
        addLabel(L10n.tr("Group Stacks:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        stackStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 200, height: 26), pullsDown: false)
        stackStylePopup.addItems(withTitles: localizedItems(["Filled glass", "Outline panes"]))
        stackStylePopup.target = self
        stackStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(stackStylePopup)

        y -= 40

        addLabel(L10n.tr("Stack Geometry:"), at: NSPoint(x: 15, y: y), width: labelW, to: view)
        stackGeometryPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        stackGeometryPopup.addItems(withTitles: localizedItems(["Subtle", "Strong"]))
        stackGeometryPopup.target = self
        stackGeometryPopup.action = #selector(controlChanged(_:))
        view.addSubview(stackGeometryPopup)

        y -= 30

        stackHoverSpreadCheckbox = makeCheckbox(L10n.tr("Spread stacks on hover"), at: NSPoint(x: 15, y: y))
        stackHoverSpreadCheckbox.target = self
        stackHoverSpreadCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(stackHoverSpreadCheckbox)

        y -= 28

        stackCountBadgeCheckbox = makeCheckbox(L10n.tr("Show group count badge"), at: NSPoint(x: 15, y: y))
        stackCountBadgeCheckbox.frame.size.width = 300
        stackCountBadgeCheckbox.target = self
        stackCountBadgeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(stackCountBadgeCheckbox)

        y -= 32

        addLabel(L10n.tr("Badge Style:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        stackCountBadgeStylePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        stackCountBadgeStylePopup.addItems(withTitles: localizedItems(["Minimal", "Pill", "Separator"]))
        stackCountBadgeStylePopup.target = self
        stackCountBadgeStylePopup.action = #selector(controlChanged(_:))
        view.addSubview(stackCountBadgeStylePopup)

        y -= 42

        addSectionHeader(L10n.tr("System Indicators"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 30

        systemIndicatorsCheckbox = makeCheckbox(L10n.tr("Show system indicators"), at: NSPoint(x: 15, y: y))
        systemIndicatorsCheckbox.target = self
        systemIndicatorsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorsCheckbox)

        y -= 32

        addLabel(L10n.tr("Placement:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorPlacementPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        systemIndicatorPlacementPopup.addItems(withTitles: localizedItems(["Free", "Leading", "Trailing", "Pinned Left", "Pinned Right"]))
        systemIndicatorPlacementPopup.target = self
        systemIndicatorPlacementPopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorPlacementPopup)

        y -= 36

        addLabel(L10n.tr("Display:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorDisplayScopePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        systemIndicatorDisplayScopePopup.addItems(withTitles: localizedItems(["Every Display", "Selected Display"]))
        systemIndicatorDisplayScopePopup.target = self
        systemIndicatorDisplayScopePopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorDisplayScopePopup)

        systemIndicatorSelectedDisplayPopup = NSPopUpButton(frame: NSRect(x: controlX + 190, y: y - 2, width: 138, height: 26), pullsDown: false)
        systemIndicatorSelectedDisplayPopup.target = self
        systemIndicatorSelectedDisplayPopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorSelectedDisplayPopup)

        y -= 36

        addLabel(L10n.tr("Chip Size:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorChipPresetPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        systemIndicatorChipPresetPopup.addItems(withTitles: localizedItems(["Compact", "Dense", "Micro"]))
        systemIndicatorChipPresetPopup.target = self
        systemIndicatorChipPresetPopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorChipPresetPopup)

        y -= 36

        addLabel(L10n.tr("Appearance:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorAppearancePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        systemIndicatorAppearancePopup.addItems(withTitles: localizedItems(["Glass", "Flat", "Underline", "Minimal"]))
        systemIndicatorAppearancePopup.target = self
        systemIndicatorAppearancePopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorAppearancePopup)

        y -= 36

        addLabel(L10n.tr("Temperature:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorTemperatureUnitPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 180, height: 26), pullsDown: false)
        systemIndicatorTemperatureUnitPopup.addItems(withTitles: localizedItems(["Celsius", "Fahrenheit"]))
        systemIndicatorTemperatureUnitPopup.target = self
        systemIndicatorTemperatureUnitPopup.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorTemperatureUnitPopup)

        y -= 36

        addLabel(L10n.tr("Refresh:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorRefreshField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 250, max: 10000)
        systemIndicatorRefreshField.delegate = self
        systemIndicatorRefreshField.target = self
        systemIndicatorRefreshField.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorRefreshField)
        let indicatorRefreshSuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        indicatorRefreshSuffix.textColor = .secondaryLabelColor
        view.addSubview(indicatorRefreshSuffix)

        y -= 34

        let indicatorColorX = controlX + 162

        systemIndicatorCpuCheckbox = makeCheckbox(L10n.tr("CPU"), at: NSPoint(x: 15, y: y))
        systemIndicatorCpuCheckbox.target = self
        systemIndicatorCpuCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorCpuCheckbox)
        systemIndicatorCpuModePopup = makeSystemIndicatorModePopup(at: NSPoint(x: controlX, y: y - 2))
        view.addSubview(systemIndicatorCpuModePopup)
        systemIndicatorCpuColorWell = makeSystemIndicatorColorWell(metric: .cpu, at: NSPoint(x: indicatorColorX, y: y - 1))
        view.addSubview(systemIndicatorCpuColorWell)

        y -= 30

        systemIndicatorGpuCheckbox = makeCheckbox(L10n.tr("GPU"), at: NSPoint(x: 15, y: y))
        systemIndicatorGpuCheckbox.target = self
        systemIndicatorGpuCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorGpuCheckbox)
        systemIndicatorGpuModePopup = makeSystemIndicatorModePopup(at: NSPoint(x: controlX, y: y - 2))
        view.addSubview(systemIndicatorGpuModePopup)
        systemIndicatorGpuColorWell = makeSystemIndicatorColorWell(metric: .gpu, at: NSPoint(x: indicatorColorX, y: y - 1))
        view.addSubview(systemIndicatorGpuColorWell)

        y -= 30

        systemIndicatorRamCheckbox = makeCheckbox(L10n.tr("RAM"), at: NSPoint(x: 15, y: y))
        systemIndicatorRamCheckbox.target = self
        systemIndicatorRamCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorRamCheckbox)
        systemIndicatorRamModePopup = makeSystemIndicatorModePopup(at: NSPoint(x: controlX, y: y - 2))
        view.addSubview(systemIndicatorRamModePopup)
        systemIndicatorRamColorWell = makeSystemIndicatorColorWell(metric: .ram, at: NSPoint(x: indicatorColorX, y: y - 1))
        view.addSubview(systemIndicatorRamColorWell)

        y -= 30

        systemIndicatorThermalCheckbox = makeCheckbox(L10n.tr("Temperature"), at: NSPoint(x: 15, y: y))
        systemIndicatorThermalCheckbox.target = self
        systemIndicatorThermalCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(systemIndicatorThermalCheckbox)
        systemIndicatorThermalModePopup = makeSystemIndicatorModePopup(at: NSPoint(x: controlX, y: y - 2))
        view.addSubview(systemIndicatorThermalModePopup)
        systemIndicatorThermalColorWell = makeSystemIndicatorColorWell(metric: .thermal, at: NSPoint(x: indicatorColorX, y: y - 1))
        view.addSubview(systemIndicatorThermalColorWell)

        y -= 36

        addLabel(L10n.tr("Graph Samples:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        systemIndicatorGraphSamplesSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: 210, height: 22))
        systemIndicatorGraphSamplesSlider.minValue = 4
        systemIndicatorGraphSamplesSlider.maxValue = 32
        systemIndicatorGraphSamplesSlider.numberOfTickMarks = 8
        systemIndicatorGraphSamplesSlider.allowsTickMarkValuesOnly = false
        systemIndicatorGraphSamplesSlider.target = self
        systemIndicatorGraphSamplesSlider.action = #selector(systemIndicatorGraphSamplesChanged(_:))
        view.addSubview(systemIndicatorGraphSamplesSlider)

        systemIndicatorGraphSamplesLabel = makeLabel("", at: NSPoint(x: controlX + 220, y: y + 2), width: 55)
        systemIndicatorGraphSamplesLabel.textColor = .secondaryLabelColor
        view.addSubview(systemIndicatorGraphSamplesLabel)

        return view
    }

    private func buildAppsTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 470))
        var y: CGFloat = 430
        let labelW: CGFloat = 160
        let controlX: CGFloat = 180

        addSectionHeader(L10n.tr("App Rules"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        // Blacklisted apps
        addLabel(L10n.tr("Blacklisted Apps:"), at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        blacklistField = NSTextField(frame: NSRect(x: controlX, y: y, width: 320, height: 22))
        blacklistField.placeholderString = "com.app.one, com.app.two"
        blacklistField.font = NSFont.systemFont(ofSize: 11)
        blacklistField.delegate = self
        view.addSubview(blacklistField)

        y -= 34

        let addBlacklistedAppBtn = makeActionButton(
            title: L10n.tr("Add App..."),
            symbolName: "plus.app",
            frame: NSRect(x: controlX, y: y, width: 122, height: 28),
            action: #selector(addBlacklistedAppClicked(_:))
        )
        view.addSubview(addBlacklistedAppBtn)

        let clearBlacklistBtn = makeActionButton(
            title: L10n.tr("Clear"),
            symbolName: "xmark.circle",
            frame: NSRect(x: controlX + 132, y: y, width: 88, height: 28),
            action: #selector(clearBlacklistClicked(_:))
        )
        view.addSubview(clearBlacklistBtn)

        y -= 44

        // Pinned apps (read-only)
        addLabel(L10n.tr("Pinned Apps:"), at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        pinnedAppsLabel = makeLabel("", at: NSPoint(x: controlX, y: y), width: 320)
        pinnedAppsLabel.font = NSFont.systemFont(ofSize: 11)
        pinnedAppsLabel.textColor = .secondaryLabelColor
        view.addSubview(pinnedAppsLabel)

        y -= 34

        let clearPinnedAppsBtn = makeActionButton(
            title: L10n.tr("Clear Pinned Apps"),
            symbolName: "pin.slash",
            frame: NSRect(x: controlX, y: y, width: 158, height: 28),
            action: #selector(clearPinnedAppsClicked(_:))
        )
        view.addSubview(clearPinnedAppsBtn)

        y -= 42

        addSectionHeader(L10n.tr("Pinned Scope"), at: NSPoint(x: 15, y: y), width: 500, to: view)
        y -= 34

        addLabel(L10n.tr("Pinned Apps:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        pinnedAppsScopePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        pinnedAppsScopePopup.addItems(withTitles: localizedItems(["Global", "Per Space (Experimental)"]))
        pinnedAppsScopePopup.target = self
        pinnedAppsScopePopup.action = #selector(controlChanged(_:))
        view.addSubview(pinnedAppsScopePopup)

        return view
    }

    private func buildAdvancedTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: SettingsWindowLayout.contentWidth, height: 940))
        var y: CGFloat = view.bounds.height - 30
        let labelW: CGFloat = 176
        let controlX: CGFloat = 206
        let permissionStatusW: CGFloat = 134
        let permissionButtonW: CGFloat = 168
        let permissionRefreshW: CGFloat = 128
        let permissionButtonX = controlX + permissionStatusW + 10
        let contentWidth: CGFloat = SettingsWindowLayout.contentWidth - 30

        addSectionHeader(L10n.tr("Permissions"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 36

        addLabel(L10n.tr("Accessibility:"), at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        accessibilityStatusLabel = makeLabel("", at: NSPoint(x: controlX, y: y + 4), width: permissionStatusW)
        accessibilityStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(accessibilityStatusLabel)
        let accessibilityBtn = makeActionButton(
            title: L10n.tr("Open Settings"),
            symbolName: "figure",
            frame: NSRect(x: permissionButtonX, y: y, width: permissionButtonW, height: 28),
            action: #selector(openAccessibilitySettings(_:))
        )
        view.addSubview(accessibilityBtn)

        y -= 34

        addLabel(L10n.tr("Input Monitoring:"), at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        inputMonitoringStatusLabel = makeLabel("", at: NSPoint(x: controlX, y: y + 4), width: permissionStatusW)
        inputMonitoringStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(inputMonitoringStatusLabel)
        let inputBtn = makeActionButton(
            title: L10n.tr("Open Settings"),
            symbolName: "keyboard",
            frame: NSRect(x: permissionButtonX, y: y, width: permissionButtonW, height: 28),
            action: #selector(openInputMonitoringSettings(_:))
        )
        view.addSubview(inputBtn)

        y -= 34

        addLabel(L10n.tr("Screen Recording:"), at: NSPoint(x: 15, y: y + 4), width: labelW, to: view)
        screenRecordingStatusLabel = makeLabel("", at: NSPoint(x: controlX, y: y + 4), width: permissionStatusW)
        screenRecordingStatusLabel.textColor = .secondaryLabelColor
        view.addSubview(screenRecordingStatusLabel)
        let screenBtn = makeActionButton(
            title: L10n.tr("Open Settings"),
            symbolName: "rectangle.on.rectangle",
            frame: NSRect(x: permissionButtonX, y: y, width: permissionButtonW, height: 28),
            action: #selector(openScreenRecordingSettings(_:))
        )
        view.addSubview(screenBtn)

        let refreshBtn = makeActionButton(
            title: L10n.tr("Refresh"),
            symbolName: "arrow.clockwise",
            frame: NSRect(x: permissionButtonX + permissionButtonW + 8, y: y, width: permissionRefreshW, height: 28),
            action: #selector(refreshPermissionStatusClicked(_:))
        )
        view.addSubview(refreshBtn)

        y -= 46

        addSectionHeader(L10n.tr("Previews"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 34

        previewsEnabledCheckbox = makeCheckbox(L10n.tr("Show window previews"), at: NSPoint(x: controlX, y: y))
        previewsEnabledCheckbox.target = self
        previewsEnabledCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(previewsEnabledCheckbox)

        y -= 32

        addLabel(L10n.tr("Preview Delay:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        previewHoverDelayField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 0, max: 2000)
        previewHoverDelayField.delegate = self
        previewHoverDelayField.target = self
        previewHoverDelayField.action = #selector(controlChanged(_:))
        view.addSubview(previewHoverDelayField)
        let previewDelaySuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        previewDelaySuffix.textColor = .secondaryLabelColor
        view.addSubview(previewDelaySuffix)

        y -= 32

        addLabel(L10n.tr("Preview Memory:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        previewMemoryPresetPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 2, width: 220, height: 26), pullsDown: false)
        previewMemoryPresetPopup.addItems(withTitles: localizedItems(["Low", "Balanced", "High Quality"]))
        previewMemoryPresetPopup.target = self
        previewMemoryPresetPopup.action = #selector(controlChanged(_:))
        view.addSubview(previewMemoryPresetPopup)

        y -= 46

        addSectionHeader(L10n.tr("Providers"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 34

        addLabel(L10n.tr("Provider Runtime:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerRuntimeCheckbox = makeCheckbox(L10n.tr("Enable provider runtime"), at: NSPoint(x: controlX, y: y - 2))
        providerRuntimeCheckbox.target = self
        providerRuntimeCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(providerRuntimeCheckbox)

        y -= 34

        addLabel(L10n.tr("Provider Timeout:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerTimeoutField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 150, max: 5000)
        providerTimeoutField.delegate = self
        providerTimeoutField.target = self
        providerTimeoutField.action = #selector(controlChanged(_:))
        view.addSubview(providerTimeoutField)
        let timeoutSuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        timeoutSuffix.textColor = .secondaryLabelColor
        view.addSubview(timeoutSuffix)

        y -= 34

        addLabel(L10n.tr("Circuit Breaker:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        providerCircuitBreakerField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 1, max: 20)
        providerCircuitBreakerField.delegate = self
        providerCircuitBreakerField.target = self
        providerCircuitBreakerField.action = #selector(controlChanged(_:))
        view.addSubview(providerCircuitBreakerField)

        y -= 46

        addSectionHeader(L10n.tr("Configuration"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 42

        let openConfigBtn = makeActionButton(
            title: L10n.tr("Open Config"),
            symbolName: "doc.text",
            frame: NSRect(x: controlX, y: y, width: 154, height: 30),
            action: #selector(openConfigFile(_:))
        )
        view.addSubview(openConfigBtn)

        let revealConfigBtn = makeActionButton(
            title: L10n.tr("Show in Finder"),
            symbolName: "folder",
            frame: NSRect(x: controlX + 166, y: y, width: 162, height: 30),
            action: #selector(revealConfigFile(_:))
        )
        view.addSubview(revealConfigBtn)

        let resetAllBtn = makeActionButton(
            title: L10n.tr("Reset All"),
            symbolName: "arrow.counterclockwise",
            frame: NSRect(x: controlX, y: y - 36, width: 112, height: 30),
            action: #selector(resetAllSettingsClicked(_:))
        )
        view.addSubview(resetAllBtn)

        configPathLabel = NSTextField(frame: NSRect(x: controlX, y: y - 67, width: contentWidth - controlX - 15, height: 20))
        configPathLabel.stringValue = Self.displayPath(for: Config.configPath)
        configPathLabel.isEditable = false
        configPathLabel.isBordered = false
        configPathLabel.backgroundColor = .clear
        configPathLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        configPathLabel.textColor = .secondaryLabelColor
        if let cell = configPathLabel.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingMiddle
        }
        view.addSubview(configPathLabel)

        y -= 106

        addSectionHeader(L10n.tr("Diagnostics"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 34

        perfLoggingCheckbox = makeCheckbox(L10n.tr("Performance logging"), at: NSPoint(x: controlX, y: y))
        perfLoggingCheckbox.target = self
        perfLoggingCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(perfLoggingCheckbox)

        y -= 34

        perfHangDiagnosticsCheckbox = makeCheckbox(L10n.tr("Hang diagnostics"), at: NSPoint(x: controlX, y: y))
        perfHangDiagnosticsCheckbox.target = self
        perfHangDiagnosticsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(perfHangDiagnosticsCheckbox)

        y -= 34

        addLabel(L10n.tr("Log Interval:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        perfLogIntervalField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 250, max: 10000)
        perfLogIntervalField.delegate = self
        perfLogIntervalField.target = self
        perfLogIntervalField.action = #selector(controlChanged(_:))
        view.addSubview(perfLogIntervalField)
        let intervalSuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        intervalSuffix.textColor = .secondaryLabelColor
        view.addSubview(intervalSuffix)

        y -= 46

        addSectionHeader(L10n.tr("Experimental"), at: NSPoint(x: 15, y: y), width: contentWidth, to: view)
        y -= 34

        pluginsEnabledCheckbox = makeCheckbox(L10n.tr("Enable plugins"), at: NSPoint(x: controlX, y: y))
        pluginsEnabledCheckbox.target = self
        pluginsEnabledCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(pluginsEnabledCheckbox)

        y -= 30

        windowTabGroupsCheckbox = makeCheckbox(L10n.tr("Enable window tab groups"), at: NSPoint(x: controlX, y: y))
        windowTabGroupsCheckbox.target = self
        windowTabGroupsCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(windowTabGroupsCheckbox)

        y -= 34

        addLabel(L10n.tr("Group Hover Delay:"), at: NSPoint(x: 15, y: y + 2), width: labelW, to: view)
        tabGroupHoverDelayField = makeNumberField(frame: NSRect(x: controlX, y: y - 1, width: 80, height: 22), min: 100, max: 5000)
        tabGroupHoverDelayField.delegate = self
        tabGroupHoverDelayField.target = self
        tabGroupHoverDelayField.action = #selector(controlChanged(_:))
        view.addSubview(tabGroupHoverDelayField)
        let groupDelaySuffix = makeLabel("ms", at: NSPoint(x: controlX + 86, y: y + 2), width: 30)
        groupDelaySuffix.textColor = .secondaryLabelColor
        view.addSubview(groupDelaySuffix)

        y -= 30

        tabGroupCollapseCheckbox = makeCheckbox(L10n.tr("Collapse group on outside click"), at: NSPoint(x: controlX, y: y))
        tabGroupCollapseCheckbox.target = self
        tabGroupCollapseCheckbox.action = #selector(controlChanged(_:))
        view.addSubview(tabGroupCollapseCheckbox)

        return view
    }

    private func buildAboutTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: SettingsWindowLayout.contentWidth, height: 500))
        var y: CGFloat = 408
        let centerX = view.frame.width / 2

        let brandSize = NSSize(width: 292, height: 70)
        let brandView = NSImageView(frame: NSRect(
            x: centerX - brandSize.width / 2,
            y: y,
            width: brandSize.width,
            height: brandSize.height
        ))
        brandView.image = LiquidBarLogo.makeBrandBarImage(displaySize: brandSize)
        brandView.imageScaling = .scaleProportionallyUpOrDown
        brandView.autoresizingMask = [.minXMargin, .maxXMargin]
        view.addSubview(brandView)

        y -= 42

        let titleLabel = NSTextField(frame: NSRect(x: 0, y: y, width: view.frame.width, height: 32))
        titleLabel.stringValue = "LiquidBar"
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.autoresizingMask = [.width]
        view.addSubview(titleLabel)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? Updater.currentVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        var versionString = L10n.tr("Version %@", version)
        if let build, !build.isEmpty, build != version {
            versionString = L10n.tr("Version %@ (%@)", version, build)
        }
        y -= 22

        let versionLabel = NSTextField(frame: NSRect(x: 0, y: y, width: view.frame.width, height: 20))
        versionLabel.stringValue = versionString
        versionLabel.isEditable = false
        versionLabel.isBordered = false
        versionLabel.backgroundColor = .clear
        versionLabel.font = NSFont.systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.autoresizingMask = [.width]
        view.addSubview(versionLabel)

        y -= 22

        updateStatusLabel = NSTextField(frame: NSRect(x: 0, y: y, width: view.frame.width, height: 18))
        updateStatusLabel.stringValue = ""
        updateStatusLabel.isEditable = false
        updateStatusLabel.isBordered = false
        updateStatusLabel.backgroundColor = .clear
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.alignment = .center
        updateStatusLabel.autoresizingMask = [.width]
        view.addSubview(updateStatusLabel)

        y -= 42
        let actionButtonWidth: CGFloat = 166
        let actionGap: CGFloat = 14
        let actionStartX = centerX - actionButtonWidth - actionGap / 2

        let updateBtn = makeActionButton(
            title: L10n.tr("Check for Updates"),
            symbolName: "arrow.triangle.2.circlepath",
            frame: NSRect(x: actionStartX, y: y, width: actionButtonWidth, height: 30),
            action: #selector(checkForUpdatesClicked(_:))
        )
        updateBtn.autoresizingMask = [.minXMargin, .maxXMargin]
        view.addSubview(updateBtn)

        let githubBtn = makeActionButton(
            title: L10n.tr("GitHub"),
            symbolName: "arrow.up.right.square",
            frame: NSRect(x: actionStartX + actionButtonWidth + actionGap, y: y, width: actionButtonWidth, height: 30),
            action: #selector(openGitHub(_:))
        )
        githubBtn.autoresizingMask = [.minXMargin, .maxXMargin]
        view.addSubview(githubBtn)

        return view
    }

    // MARK: - Config

    private func loadConfig() {
        let config = Config.load()
        applyConfigToControls(config)
    }

    private func applyConfigToControls(_ config: Config) {
        heightSlider.integerValue = config.taskbarHeight
        heightLabel.stringValue = formatPixels(config.taskbarHeight)
        switch config.taskbarPosition {
        case .top: positionPopup.selectItem(at: 0)
        case .bottom: positionPopup.selectItem(at: 1)
        case .left: positionPopup.selectItem(at: 2)
        case .right: positionPopup.selectItem(at: 3)
        }
        switch config.itemSizing {
        case .uniform: itemSizingPopup.selectItem(at: 0)
        case .auto: itemSizingPopup.selectItem(at: 1)
        }
        maxItemWidthSlider.integerValue = config.maxItemWidth
        maxItemWidthLabel.stringValue = formatPixels(config.maxItemWidth)
        maxTitleWidthSlider.integerValue = config.maxTitleWidth
        maxTitleWidthLabel.stringValue = formatPixels(config.maxTitleWidth)
        centerItemsCheckbox.state = config.centerItems ? .on : .off
        switch config.multiMonitorMode {
        case .allDisplays: multiMonitorPopup.selectItem(at: 0)
        case .mainOnly: multiMonitorPopup.selectItem(at: 1)
        }
        switch config.windowDisplayMode {
        case .perDisplay: windowDisplayPopup.selectItem(at: 0)
        case .allWindows: windowDisplayPopup.selectItem(at: 1)
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
        switch config.switcherWindowScope {
        case .allDisplays: switcherScopePopup.selectItem(at: 0)
        case .focusedDisplay: switcherScopePopup.selectItem(at: 1)
        }
        switch config.scrollWheelMode {
        case .cycleWindows: scrollWheelPopup.selectItem(at: 0)
        case .hideShow: scrollWheelPopup.selectItem(at: 1)
        case .volume: scrollWheelPopup.selectItem(at: 2)
        case .off: scrollWheelPopup.selectItem(at: 3)
        }
        launcherEnabledCheckbox.state = config.launcherEnabled ? .on : .off
        switch config.launcherAction {
        case .spotlight: launcherActionPopup.selectItem(at: 0)
        case .raycast: launcherActionPopup.selectItem(at: 1)
        case .alfred: launcherActionPopup.selectItem(at: 2)
        case .customUrl: launcherActionPopup.selectItem(at: 3)
        }
        launcherCustomUrlField.stringValue = config.launcherCustomUrl ?? ""

        iconsOnlyCheckbox.state = config.iconsOnly ? .on : .off
        groupByAppCheckbox.state = config.groupByApp ? .on : .off
        tabbedTaskbarCheckbox.state = config.tabbedTaskbarEnabled ? .on : .off
        showHiddenCheckbox.state = config.showHiddenApps ? .on : .off
        showMinimizedCheckbox.state = config.showMinimizedWindows ? .on : .off
        adjustWindowsCheckbox.state = config.adjustWindowsForTaskbar ? .on : .off
        switch config.hiddenWindowMode {
        case .inPlace: hiddenModePopup.selectItem(at: 0)
        case .collapsedRight: hiddenModePopup.selectItem(at: 1)
        }
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
        showMenuBarIconCheckbox.state = config.showMenuBarIcon ? .on : .off
        switch config.appLanguage {
        case .system: appLanguagePopup.selectItem(at: 0)
        case .english: appLanguagePopup.selectItem(at: 1)
        case .korean: appLanguagePopup.selectItem(at: 2)
        }
        loginCheckbox.state = LoginItem.isEnabled() ? .on : .off

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
        updateIconSizeControl(for: config.iconSize)
        titleFontSizeSlider.integerValue = config.fontSize
        titleFontSizeLabel.stringValue = formatPoints(config.fontSize)
        switch config.hoverIntensity {
        case .subtle: hoverIntensityPopup.selectItem(at: 0)
        case .medium: hoverIntensityPopup.selectItem(at: 1)
        case .pronounced: hoverIntensityPopup.selectItem(at: 2)
        }
        switch config.visualDepth {
        case .subtle: visualDepthPopup.selectItem(at: 0)
        case .balanced: visualDepthPopup.selectItem(at: 1)
        case .rich: visualDepthPopup.selectItem(at: 2)
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
        systemIndicatorsCheckbox.state = config.systemIndicatorsEnabled ? .on : .off
        switch config.systemIndicatorPlacement {
        case .free: systemIndicatorPlacementPopup.selectItem(at: 0)
        case .leading: systemIndicatorPlacementPopup.selectItem(at: 1)
        case .trailing: systemIndicatorPlacementPopup.selectItem(at: 2)
        case .leftCorner: systemIndicatorPlacementPopup.selectItem(at: 3)
        case .rightCorner: systemIndicatorPlacementPopup.selectItem(at: 4)
        }
        switch config.systemIndicatorDisplayScope {
        case .allDisplays: systemIndicatorDisplayScopePopup.selectItem(at: 0)
        case .selectedDisplay: systemIndicatorDisplayScopePopup.selectItem(at: 1)
        }
        populateSystemIndicatorSelectedDisplayPopup(selectedDisplayId: config.systemIndicatorSelectedDisplayId)
        switch config.systemIndicatorChipPreset {
        case .full, .compact: systemIndicatorChipPresetPopup.selectItem(at: 0)
        case .dense: systemIndicatorChipPresetPopup.selectItem(at: 1)
        case .micro: systemIndicatorChipPresetPopup.selectItem(at: 2)
        }
        switch config.systemIndicatorAppearance {
        case .glass: systemIndicatorAppearancePopup.selectItem(at: 0)
        case .flat: systemIndicatorAppearancePopup.selectItem(at: 1)
        case .underline: systemIndicatorAppearancePopup.selectItem(at: 2)
        case .minimal: systemIndicatorAppearancePopup.selectItem(at: 3)
        }
        switch config.systemIndicatorTemperatureUnit {
        case .celsius: systemIndicatorTemperatureUnitPopup.selectItem(at: 0)
        case .fahrenheit: systemIndicatorTemperatureUnitPopup.selectItem(at: 1)
        }
        systemIndicatorRefreshField.stringValue = "\(config.systemIndicatorRefreshIntervalMs)"
        systemIndicatorCpuCheckbox.state = config.systemIndicatorCpuEnabled ? .on : .off
        selectSystemIndicatorMode(config.systemIndicatorCpuVisualMode, in: systemIndicatorCpuModePopup)
        systemIndicatorCpuColorWell.color = systemIndicatorColor(hex: config.systemIndicatorCpuColorHex, metric: .cpu)
        systemIndicatorGpuCheckbox.state = config.systemIndicatorGpuEnabled ? .on : .off
        selectSystemIndicatorMode(config.systemIndicatorGpuVisualMode, in: systemIndicatorGpuModePopup)
        systemIndicatorGpuColorWell.color = systemIndicatorColor(hex: config.systemIndicatorGpuColorHex, metric: .gpu)
        systemIndicatorRamCheckbox.state = config.systemIndicatorRamEnabled ? .on : .off
        selectSystemIndicatorMode(config.systemIndicatorRamVisualMode, in: systemIndicatorRamModePopup)
        systemIndicatorRamColorWell.color = systemIndicatorColor(hex: config.systemIndicatorRamColorHex, metric: .ram)
        systemIndicatorThermalCheckbox.state = config.systemIndicatorThermalEnabled ? .on : .off
        selectSystemIndicatorMode(config.systemIndicatorThermalVisualMode, in: systemIndicatorThermalModePopup)
        systemIndicatorThermalColorWell.color = systemIndicatorColor(hex: config.systemIndicatorThermalColorHex, metric: .thermal)
        systemIndicatorGraphSamplesSlider.integerValue = config.systemIndicatorGraphSamples
        systemIndicatorGraphSamplesLabel.stringValue = "\(config.systemIndicatorGraphSamples)"

        blacklistField.stringValue = Self.uniquePreservingOrder(config.blacklistedApps).joined(separator: ", ")
        pendingPinnedApps = nil
        pinnedAppsLabel.stringValue = config.pinnedApps.isEmpty ? L10n.tr("(none)") : config.pinnedApps.joined(separator: ", ")
        switch config.pinnedAppsScope {
        case .global: pinnedAppsScopePopup.selectItem(at: 0)
        case .perSpace: pinnedAppsScopePopup.selectItem(at: 1)
        }

        previewsEnabledCheckbox.state = config.previewsEnabled ? .on : .off
        previewHoverDelayField.stringValue = "\(config.previewHoverDelayMs)"
        switch config.previewMemoryPreset {
        case .low: previewMemoryPresetPopup.selectItem(at: 0)
        case .balanced: previewMemoryPresetPopup.selectItem(at: 1)
        case .highQuality: previewMemoryPresetPopup.selectItem(at: 2)
        }
        providerRuntimeCheckbox.state = config.providerRuntimeEnabled ? .on : .off
        providerTimeoutField.stringValue = "\(config.providerTimeoutMs)"
        providerCircuitBreakerField.stringValue = "\(config.providerCircuitBreakerThreshold)"
        perfLoggingCheckbox.state = config.performanceLoggingEnabled ? .on : .off
        perfHangDiagnosticsCheckbox.state = config.performanceHangDiagnosticsEnabled ? .on : .off
        perfLogIntervalField.stringValue = "\(config.performanceLogIntervalMs)"
        pluginsEnabledCheckbox.state = config.pluginsEnabled ? .on : .off
        windowTabGroupsCheckbox.state = config.windowTabGroupsEnabled ? .on : .off
        tabGroupHoverDelayField.stringValue = "\(config.tabGroupHoverExpandDelayMs)"
        tabGroupCollapseCheckbox.state = config.tabGroupCollapseOnOutsideClick ? .on : .off

        updateStatusLabel.stringValue = ""
        updateCountBadgeControlsEnabledState()
        updateSwitcherControlsEnabledState()
        updateSidebarControlsEnabledState()
        updateWindowStateControlsEnabledState()
        updateLauncherControlsEnabledState()
        updatePreviewControlsEnabledState()
        updateProviderControlsEnabledState()
        updatePerfControlsEnabledState()
        updateSystemIndicatorControlsEnabledState()
        updateTabGroupControlsEnabledState()
        refreshPermissionStatus()
        updateAppearancePreview()
    }

    // MARK: - Actions

    @objc private func heightChanged(_ sender: NSSlider) {
        heightLabel.stringValue = formatPixels(sender.integerValue)
        updateAppearancePreview()
        scheduleAutoApply()
    }

    @objc private func iconSizeChanged(_ sender: NSSlider) {
        iconSizeLabel.stringValue = formatPixels(sender.integerValue)
        updateAppearancePreview()
        scheduleAutoApply()
    }

    @objc private func titleFontSizeChanged(_ sender: NSSlider) {
        titleFontSizeLabel.stringValue = formatPoints(sender.integerValue)
        updateAppearancePreview()
        scheduleAutoApply()
    }

    @objc private func maxItemWidthChanged(_ sender: NSSlider) {
        maxItemWidthLabel.stringValue = formatPixels(sender.integerValue)
        updateAppearancePreview()
        scheduleAutoApply()
    }

    @objc private func maxTitleWidthChanged(_ sender: NSSlider) {
        maxTitleWidthLabel.stringValue = formatPixels(sender.integerValue)
        updateAppearancePreview()
        scheduleAutoApply()
    }

    @objc private func systemIndicatorGraphSamplesChanged(_ sender: NSSlider) {
        systemIndicatorGraphSamplesLabel.stringValue = "\(sender.integerValue)"
        scheduleAutoApply()
    }

    @objc private func controlChanged(_ sender: Any) {
        updatePerfControlsEnabledState()
        updateCountBadgeControlsEnabledState()
        updateSwitcherControlsEnabledState()
        updateSidebarControlsEnabledState()
        updateWindowStateControlsEnabledState()
        updateLauncherControlsEnabledState()
        updatePreviewControlsEnabledState()
        updateProviderControlsEnabledState()
        updateSystemIndicatorControlsEnabledState()
        updateTabGroupControlsEnabledState()
        updateAppearancePreview()
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

    @objc private func revertClicked(_ sender: Any) {
        autoApplyWorkItem?.cancel()
        autoApplyWorkItem = nil
        loadConfig()
    }

    @objc private func resetSelectedTabClicked(_ sender: Any) {
        var config = Config.load()
        var defaults = Config()
        defaults.validate()
        switch tabViewController.selectedTabViewItemIndex {
        case 0:
            config.taskbarHeight = defaults.taskbarHeight
            config.taskbarPosition = defaults.taskbarPosition
            config.itemSizing = defaults.itemSizing
            config.maxItemWidth = defaults.maxItemWidth
            config.maxTitleWidth = defaults.maxTitleWidth
            config.centerItems = defaults.centerItems
            config.multiMonitorMode = defaults.multiMonitorMode
            config.windowDisplayMode = defaults.windowDisplayMode
            config.sidebarModeEnabled = defaults.sidebarModeEnabled
            config.sidebarStateDefault = defaults.sidebarStateDefault
            config.sidebarExpandTrigger = defaults.sidebarExpandTrigger
            config.tileZoneEnabled = defaults.tileZoneEnabled
            config.tilePopupSingleton = defaults.tilePopupSingleton
            config.hoverDelayMs = defaults.hoverDelayMs
            config.hoverIntentGuardEnabled = defaults.hoverIntentGuardEnabled
            config.switcherEnabled = defaults.switcherEnabled
            config.switcherHotkey = defaults.switcherHotkey
            config.switcherWindowScope = defaults.switcherWindowScope
            config.scrollWheelMode = defaults.scrollWheelMode
            config.launcherEnabled = defaults.launcherEnabled
            config.launcherAction = defaults.launcherAction
            config.launcherCustomUrl = defaults.launcherCustomUrl
            config.iconsOnly = defaults.iconsOnly
            config.groupByApp = defaults.groupByApp
            config.tabbedTaskbarEnabled = defaults.tabbedTaskbarEnabled
            config.showHiddenApps = defaults.showHiddenApps
            config.hiddenWindowMode = defaults.hiddenWindowMode
            config.showMinimizedWindows = defaults.showMinimizedWindows
            config.minimizedWindowMode = defaults.minimizedWindowMode
            config.adjustWindowsForTaskbar = defaults.adjustWindowsForTaskbar
            config.secondClickAction = defaults.secondClickAction
            config.hideDock = defaults.hideDock
            config.showMenuBarIcon = defaults.showMenuBarIcon
            config.appLanguage = defaults.appLanguage
        case 1:
            config.theme = defaults.theme
            config.barStyle = defaults.barStyle
            config.glassStyle = defaults.glassStyle
            config.iconSize = defaults.iconSize
            config.fontSize = defaults.fontSize
            config.hoverIntensity = defaults.hoverIntensity
            config.visualDepth = defaults.visualDepth
            config.animationProfile = defaults.animationProfile
            config.focusIndicatorStyle = defaults.focusIndicatorStyle
            config.appGroupStackStyle = defaults.appGroupStackStyle
            config.appGroupStackGeometry = defaults.appGroupStackGeometry
            config.appGroupStackHoverSpreadEnabled = defaults.appGroupStackHoverSpreadEnabled
            config.appGroupCountBadgeInIconsOnly = defaults.appGroupCountBadgeInIconsOnly
            config.appGroupCountBadgeStyle = defaults.appGroupCountBadgeStyle
            config.systemIndicatorsEnabled = defaults.systemIndicatorsEnabled
            config.systemIndicatorRefreshIntervalMs = defaults.systemIndicatorRefreshIntervalMs
            config.systemIndicatorPlacement = defaults.systemIndicatorPlacement
            config.systemIndicatorDisplayScope = defaults.systemIndicatorDisplayScope
            config.systemIndicatorSelectedDisplayId = defaults.systemIndicatorSelectedDisplayId
            config.systemIndicatorCpuEnabled = defaults.systemIndicatorCpuEnabled
            config.systemIndicatorGpuEnabled = defaults.systemIndicatorGpuEnabled
            config.systemIndicatorRamEnabled = defaults.systemIndicatorRamEnabled
            config.systemIndicatorThermalEnabled = defaults.systemIndicatorThermalEnabled
            config.systemIndicatorCpuVisualMode = defaults.systemIndicatorCpuVisualMode
            config.systemIndicatorGpuVisualMode = defaults.systemIndicatorGpuVisualMode
            config.systemIndicatorRamVisualMode = defaults.systemIndicatorRamVisualMode
            config.systemIndicatorThermalVisualMode = defaults.systemIndicatorThermalVisualMode
            config.systemIndicatorCpuColorHex = defaults.systemIndicatorCpuColorHex
            config.systemIndicatorGpuColorHex = defaults.systemIndicatorGpuColorHex
            config.systemIndicatorRamColorHex = defaults.systemIndicatorRamColorHex
            config.systemIndicatorThermalColorHex = defaults.systemIndicatorThermalColorHex
            config.systemIndicatorTemperatureUnit = defaults.systemIndicatorTemperatureUnit
            config.systemIndicatorChipPreset = defaults.systemIndicatorChipPreset
            config.systemIndicatorAppearance = defaults.systemIndicatorAppearance
            config.systemIndicatorGraphSamples = defaults.systemIndicatorGraphSamples
        case 2:
            config.blacklistedApps = defaults.blacklistedApps
            config.pinnedApps = defaults.pinnedApps
            config.pinnedAppsScope = defaults.pinnedAppsScope
        case 3:
            config.previewsEnabled = defaults.previewsEnabled
            config.previewMode = defaults.previewMode
            config.previewHoverDelayMs = defaults.previewHoverDelayMs
            config.previewMemoryPreset = defaults.previewMemoryPreset
            config.providerRuntimeEnabled = defaults.providerRuntimeEnabled
            config.providerTimeoutMs = defaults.providerTimeoutMs
            config.providerCircuitBreakerThreshold = defaults.providerCircuitBreakerThreshold
            config.performanceLoggingEnabled = defaults.performanceLoggingEnabled
            config.performanceHangDiagnosticsEnabled = defaults.performanceHangDiagnosticsEnabled
            config.performanceGpuTimingEnabled = defaults.performanceGpuTimingEnabled
            config.performanceLogIntervalMs = defaults.performanceLogIntervalMs
            config.pluginsEnabled = defaults.pluginsEnabled
            config.windowTabGroupsEnabled = defaults.windowTabGroupsEnabled
            config.tabGroupHoverExpandDelayMs = defaults.tabGroupHoverExpandDelayMs
            config.tabGroupCollapseOnOutsideClick = defaults.tabGroupCollapseOnOutsideClick
        default:
            return
        }
        applyConfigToControls(config)
        scheduleAutoApply()
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
        let enabled = perfLoggingCheckbox.state == .on || perfHangDiagnosticsCheckbox.state == .on
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
        let enabled = switcherEnabledCheckbox.state == .on
        switcherHotkeyField?.isEnabled = enabled
        switcherScopePopup?.isEnabled = enabled
    }

    private func updateSidebarControlsEnabledState() {
        let sidebarEnabled = sidebarModeCheckbox.state == .on
        sidebarStatePopup?.isEnabled = sidebarEnabled
        sidebarExpandTriggerPopup?.isEnabled = sidebarEnabled
        tileZoneCheckbox?.isEnabled = sidebarEnabled
        tilePopupSingletonCheckbox?.isEnabled = sidebarEnabled && tileZoneCheckbox.state == .on
    }

    private func updateWindowStateControlsEnabledState() {
        hiddenModePopup?.isEnabled = showHiddenCheckbox.state == .on
        minimizedModePopup?.isEnabled = showMinimizedCheckbox.state == .on
    }

    private func updateLauncherControlsEnabledState() {
        let enabled = launcherEnabledCheckbox.state == .on
        launcherActionPopup?.isEnabled = enabled
        launcherCustomUrlField?.isEnabled = enabled && launcherActionPopup.indexOfSelectedItem == 3
    }

    private func updatePreviewControlsEnabledState() {
        let enabled = previewsEnabledCheckbox.state == .on
        previewHoverDelayField?.isEnabled = enabled
        previewMemoryPresetPopup?.isEnabled = enabled || switcherEnabledCheckbox.state == .on
    }

    private func updateSystemIndicatorControlsEnabledState() {
        let enabled = systemIndicatorsCheckbox.state == .on
        systemIndicatorPlacementPopup?.isEnabled = enabled
        systemIndicatorDisplayScopePopup?.isEnabled = enabled
        systemIndicatorSelectedDisplayPopup?.isEnabled = enabled && systemIndicatorDisplayScopePopup.indexOfSelectedItem == 1
        systemIndicatorChipPresetPopup?.isEnabled = enabled
        systemIndicatorAppearancePopup?.isEnabled = enabled
        systemIndicatorTemperatureUnitPopup?.isEnabled = enabled
        systemIndicatorRefreshField?.isEnabled = enabled
        systemIndicatorCpuCheckbox?.isEnabled = enabled
        systemIndicatorGpuCheckbox?.isEnabled = enabled
        systemIndicatorRamCheckbox?.isEnabled = enabled
        systemIndicatorThermalCheckbox?.isEnabled = enabled
        systemIndicatorCpuModePopup?.isEnabled = enabled && systemIndicatorCpuCheckbox.state == .on
        systemIndicatorGpuModePopup?.isEnabled = enabled && systemIndicatorGpuCheckbox.state == .on
        systemIndicatorRamModePopup?.isEnabled = enabled && systemIndicatorRamCheckbox.state == .on
        systemIndicatorThermalModePopup?.isEnabled = enabled && systemIndicatorThermalCheckbox.state == .on
        systemIndicatorCpuColorWell?.isEnabled = enabled && systemIndicatorCpuCheckbox.state == .on
        systemIndicatorGpuColorWell?.isEnabled = enabled && systemIndicatorGpuCheckbox.state == .on
        systemIndicatorRamColorWell?.isEnabled = enabled && systemIndicatorRamCheckbox.state == .on
        systemIndicatorThermalColorWell?.isEnabled = enabled && systemIndicatorThermalCheckbox.state == .on
        systemIndicatorGraphSamplesSlider?.isEnabled = enabled
    }

    private func updateTabGroupControlsEnabledState() {
        let enabled = windowTabGroupsCheckbox.state == .on
        tabGroupHoverDelayField?.isEnabled = enabled
        tabGroupCollapseCheckbox?.isEnabled = enabled
    }

    private func updateIconSizeControl(for iconSize: Int) {
        iconSizeLabel.stringValue = formatPixels(iconSize)
        iconSizeSlider.integerValue = iconSize
    }

    private func selectSystemIndicatorMode(_ mode: SystemIndicatorVisualMode, in popup: NSPopUpButton) {
        switch mode {
        case .percentage: popup.selectItem(at: 0)
        case .bar: popup.selectItem(at: 1)
        case .graph: popup.selectItem(at: 2)
        }
    }

    private func populateSystemIndicatorSelectedDisplayPopup(selectedDisplayId: UInt32?) {
        guard let popup = systemIndicatorSelectedDisplayPopup else { return }
        popup.removeAllItems()

        let screens = NSScreen.screens
        let fallbackDisplayId = NSScreen.main?.displayId ?? CGMainDisplayID()
        let entries: [(title: String, displayId: CGDirectDisplayID)] = screens.enumerated().compactMap { index, screen in
            guard let displayId = screen.displayId ?? (index == 0 ? fallbackDisplayId : nil) else {
                return nil
            }
            let title = screen.localizedName.isEmpty ? L10n.tr("Display %d", index + 1) : screen.localizedName
            return (title, displayId)
        }

        let nonEmptyEntries = entries.isEmpty ? [(L10n.tr("Main Display"), fallbackDisplayId)] : entries
        for (index, entry) in nonEmptyEntries.enumerated() {
            let title = nonEmptyEntries.count == 1 ? entry.title : "\(entry.title) \(index + 1)"
            popup.addItem(withTitle: title)
            popup.item(at: index)?.representedObject = NSNumber(value: UInt32(entry.displayId))
        }

        let target = selectedDisplayId ?? UInt32(fallbackDisplayId)
        if let index = nonEmptyEntries.firstIndex(where: { UInt32($0.displayId) == target }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func selectedSystemIndicatorDisplayId() -> UInt32? {
        (systemIndicatorSelectedDisplayPopup.selectedItem?.representedObject as? NSNumber)?.uint32Value
    }

    private func systemIndicatorMode(from popup: NSPopUpButton) -> SystemIndicatorVisualMode {
        switch popup.indexOfSelectedItem {
        case 1: return .bar
        case 2: return .graph
        default: return .percentage
        }
    }

    private func systemIndicatorColor(hex: String?, metric: SystemIndicatorMetric) -> NSColor {
        PresentationColorPalette.color(from: hex, alpha: 1)
            ?? SystemIndicatorColorPalette.defaultColor(for: metric, severity: 0.2)
    }

    private func systemIndicatorColorHex(from well: NSColorWell, metric: SystemIndicatorMetric) -> String? {
        guard let hex = PresentationColorPalette.hexString(from: well.color) else { return nil }
        return hex == SystemIndicatorColorPalette.defaultHex(for: metric) ? nil : hex
    }

    private func updateAppearancePreview() {
        guard appearancePreviewView != nil else { return }
        var previewConfig = Config()
        previewConfig.taskbarHeight = heightSlider.integerValue
        previewConfig.iconSize = iconSizeSlider.integerValue
        previewConfig.fontSize = titleFontSizeSlider.integerValue
        previewConfig.maxItemWidth = maxItemWidthSlider.integerValue
        previewConfig.maxTitleWidth = maxTitleWidthSlider.integerValue
        previewConfig.iconsOnly = iconsOnlyCheckbox.state == .on
        previewConfig.groupByApp = groupByAppCheckbox.state == .on
        previewConfig.centerItems = centerItemsCheckbox.state == .on
        switch barStylePopup.indexOfSelectedItem {
        case 0: previewConfig.barStyle = .flush
        case 1: previewConfig.barStyle = .floating
        default: break
        }
        switch glassStylePopup.indexOfSelectedItem {
        case 0: previewConfig.glassStyle = .publicRegular
        case 1: previewConfig.glassStyle = .publicClear
        default: break
        }
        switch focusIndicatorPopup.indexOfSelectedItem {
        case 0: previewConfig.focusIndicatorStyle = .tile
        case 1: previewConfig.focusIndicatorStyle = .dot
        default: break
        }
        previewConfig.validate()
        appearancePreviewView.config = previewConfig
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === blacklistField ||
            obj.object as? NSTextField === perfLogIntervalField ||
            obj.object as? NSTextField === hoverDelayField ||
            obj.object as? NSTextField === switcherHotkeyField ||
            obj.object as? NSTextField === launcherCustomUrlField ||
            obj.object as? NSTextField === systemIndicatorRefreshField ||
            obj.object as? NSTextField === previewHoverDelayField ||
            obj.object as? NSTextField === providerTimeoutField ||
            obj.object as? NSTextField === providerCircuitBreakerField ||
            obj.object as? NSTextField === tabGroupHoverDelayField {
            scheduleAutoApply()
        }
    }

    @objc private func applyClicked(_ sender: Any) {
        let blacklist = Self.uniquePreservingOrder(
            blacklistField.stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let previousConfig = Config.load()
        var config = previousConfig
        config.taskbarHeight = heightSlider.integerValue
        switch positionPopup.indexOfSelectedItem {
        case 0: config.taskbarPosition = .top
        case 1: config.taskbarPosition = .bottom
        case 2: config.taskbarPosition = .left
        case 3: config.taskbarPosition = .right
        default: break
        }
        switch itemSizingPopup.indexOfSelectedItem {
        case 0: config.itemSizing = .uniform
        case 1: config.itemSizing = .auto
        default: break
        }
        config.maxItemWidth = maxItemWidthSlider.integerValue
        config.maxTitleWidth = maxTitleWidthSlider.integerValue
        config.centerItems = centerItemsCheckbox.state == .on
        switch multiMonitorPopup.indexOfSelectedItem {
        case 0: config.multiMonitorMode = .allDisplays
        case 1: config.multiMonitorMode = .mainOnly
        default: break
        }
        switch windowDisplayPopup.indexOfSelectedItem {
        case 0: config.windowDisplayMode = .perDisplay
        case 1: config.windowDisplayMode = .allWindows
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
        switch switcherScopePopup.indexOfSelectedItem {
        case 0: config.switcherWindowScope = .allDisplays
        case 1: config.switcherWindowScope = .focusedDisplay
        default: break
        }
        switch scrollWheelPopup.indexOfSelectedItem {
        case 0: config.scrollWheelMode = .cycleWindows
        case 1: config.scrollWheelMode = .hideShow
        case 2: config.scrollWheelMode = .volume
        case 3: config.scrollWheelMode = .off
        default: break
        }
        config.launcherEnabled = launcherEnabledCheckbox.state == .on
        switch launcherActionPopup.indexOfSelectedItem {
        case 0: config.launcherAction = .spotlight
        case 1: config.launcherAction = .raycast
        case 2: config.launcherAction = .alfred
        case 3: config.launcherAction = .customUrl
        default: break
        }
        let customLauncherUrl = launcherCustomUrlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.launcherCustomUrl = customLauncherUrl.isEmpty ? nil : customLauncherUrl
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
        config.showMenuBarIcon = showMenuBarIconCheckbox.state == .on
        switch appLanguagePopup.indexOfSelectedItem {
        case 0: config.appLanguage = .system
        case 1: config.appLanguage = .english
        case 2: config.appLanguage = .korean
        default: break
        }

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

        config.iconSize = iconSizeSlider.integerValue
        config.fontSize = titleFontSizeSlider.integerValue

        switch hoverIntensityPopup.indexOfSelectedItem {
        case 0: config.hoverIntensity = .subtle
        case 1: config.hoverIntensity = .medium
        case 2: config.hoverIntensity = .pronounced
        default: break
        }
        switch visualDepthPopup.indexOfSelectedItem {
        case 0: config.visualDepth = .subtle
        case 1: config.visualDepth = .balanced
        case 2: config.visualDepth = .rich
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

        config.systemIndicatorsEnabled = systemIndicatorsCheckbox.state == .on
        switch systemIndicatorPlacementPopup.indexOfSelectedItem {
        case 0: config.systemIndicatorPlacement = .free
        case 1: config.systemIndicatorPlacement = .leading
        case 2: config.systemIndicatorPlacement = .trailing
        case 3: config.systemIndicatorPlacement = .leftCorner
        case 4: config.systemIndicatorPlacement = .rightCorner
        default: break
        }
        switch systemIndicatorDisplayScopePopup.indexOfSelectedItem {
        case 0: config.systemIndicatorDisplayScope = .allDisplays
        case 1: config.systemIndicatorDisplayScope = .selectedDisplay
        default: break
        }
        config.systemIndicatorSelectedDisplayId = selectedSystemIndicatorDisplayId()
        switch systemIndicatorChipPresetPopup.indexOfSelectedItem {
        case 0: config.systemIndicatorChipPreset = .compact
        case 1: config.systemIndicatorChipPreset = .dense
        case 2: config.systemIndicatorChipPreset = .micro
        default: break
        }
        switch systemIndicatorAppearancePopup.indexOfSelectedItem {
        case 0: config.systemIndicatorAppearance = .glass
        case 1: config.systemIndicatorAppearance = .flat
        case 2: config.systemIndicatorAppearance = .underline
        case 3: config.systemIndicatorAppearance = .minimal
        default: break
        }
        switch systemIndicatorTemperatureUnitPopup.indexOfSelectedItem {
        case 0: config.systemIndicatorTemperatureUnit = .celsius
        case 1: config.systemIndicatorTemperatureUnit = .fahrenheit
        default: break
        }
        if let refresh = Int(systemIndicatorRefreshField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.systemIndicatorRefreshIntervalMs = refresh
        }
        config.systemIndicatorCpuEnabled = systemIndicatorCpuCheckbox.state == .on
        config.systemIndicatorGpuEnabled = systemIndicatorGpuCheckbox.state == .on
        config.systemIndicatorRamEnabled = systemIndicatorRamCheckbox.state == .on
        config.systemIndicatorThermalEnabled = systemIndicatorThermalCheckbox.state == .on
        config.systemIndicatorCpuVisualMode = systemIndicatorMode(from: systemIndicatorCpuModePopup)
        config.systemIndicatorGpuVisualMode = systemIndicatorMode(from: systemIndicatorGpuModePopup)
        config.systemIndicatorRamVisualMode = systemIndicatorMode(from: systemIndicatorRamModePopup)
        config.systemIndicatorThermalVisualMode = systemIndicatorMode(from: systemIndicatorThermalModePopup)
        config.systemIndicatorCpuColorHex = systemIndicatorColorHex(from: systemIndicatorCpuColorWell, metric: .cpu)
        config.systemIndicatorGpuColorHex = systemIndicatorColorHex(from: systemIndicatorGpuColorWell, metric: .gpu)
        config.systemIndicatorRamColorHex = systemIndicatorColorHex(from: systemIndicatorRamColorWell, metric: .ram)
        config.systemIndicatorThermalColorHex = systemIndicatorColorHex(from: systemIndicatorThermalColorWell, metric: .thermal)
        config.systemIndicatorGraphSamples = systemIndicatorGraphSamplesSlider.integerValue

        config.performanceLoggingEnabled = perfLoggingCheckbox.state == .on
        config.performanceHangDiagnosticsEnabled = perfHangDiagnosticsCheckbox.state == .on
        if let interval = Int(perfLogIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.performanceLogIntervalMs = interval
        }

        config.blacklistedApps = blacklist
        if let pendingPinnedApps {
            config.pinnedApps = pendingPinnedApps
        }
        switch pinnedAppsScopePopup.indexOfSelectedItem {
        case 0: config.pinnedAppsScope = .global
        case 1: config.pinnedAppsScope = .perSpace
        default: break
        }
        config.previewsEnabled = previewsEnabledCheckbox.state == .on
        config.previewMode = .staticImage
        if let delay = Int(previewHoverDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.previewHoverDelayMs = delay
        }
        switch previewMemoryPresetPopup.indexOfSelectedItem {
        case 0: config.previewMemoryPreset = .low
        case 1: config.previewMemoryPreset = .balanced
        case 2: config.previewMemoryPreset = .highQuality
        default: break
        }
        config.providerRuntimeEnabled = providerRuntimeCheckbox.state == .on
        if let timeout = Int(providerTimeoutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.providerTimeoutMs = timeout
        }
        if let threshold = Int(providerCircuitBreakerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.providerCircuitBreakerThreshold = threshold
        }
        config.pluginsEnabled = pluginsEnabledCheckbox.state == .on
        config.windowTabGroupsEnabled = windowTabGroupsCheckbox.state == .on
        if let delay = Int(tabGroupHoverDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            config.tabGroupHoverExpandDelayMs = delay
        }
        config.tabGroupCollapseOnOutsideClick = tabGroupCollapseCheckbox.state == .on
        config.validate()
        config.save()
        L10n.applyAppLanguage(config.appLanguage)
        let languageChanged = config.appLanguage != previousConfig.appLanguage

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

        if languageChanged {
            rebuildUI(applying: config)
        }
    }

    @objc private func checkForUpdatesClicked(_ sender: Any) {
        updateStatusLabel.stringValue = L10n.tr("Checking...")
        Task {
            do {
                if let update = try await Updater.checkForUpdate() {
                    updateStatusLabel.stringValue = L10n.tr("Update available: v%@", update.latest)
                    Updater.openReleasePage(url: update.url)
                } else {
                    updateStatusLabel.stringValue = L10n.tr("You're up to date.")
                }
            } catch {
                updateStatusLabel.stringValue = L10n.tr("Update check failed.")
            }
        }
    }

    @objc private func openGitHub(_ sender: Any) {
        NSWorkspace.shared.open(Updater.repositoryURL)
    }

    @objc private func addBlacklistedAppClicked(_ sender: Any) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Choose an app to hide from LiquidBar")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK,
                  let url = panel.url,
                  let bundleId = Bundle(url: url)?.bundleIdentifier
            else { return }
            Task { @MainActor in
                self?.appendBlacklistBundleId(bundleId)
            }
        }
    }

    @objc private func clearBlacklistClicked(_ sender: Any) {
        blacklistField.stringValue = ""
        scheduleAutoApply()
    }

    @objc private func clearPinnedAppsClicked(_ sender: Any) {
        pendingPinnedApps = []
        pinnedAppsLabel.stringValue = L10n.tr("(none)")
        scheduleAutoApply()
    }

    @objc private func openAccessibilitySettings(_ sender: Any) {
        AccessibilityService.requestPermission()
        openPrivacyPane("Privacy_Accessibility")
        refreshPermissionStatus()
    }

    @objc private func openInputMonitoringSettings(_ sender: Any) {
        _ = HotkeyMonitor.requestListenEventAccess()
        openPrivacyPane("Privacy_ListenEvent")
        refreshPermissionStatus()
    }

    @objc private func openScreenRecordingSettings(_ sender: Any) {
        _ = CGRequestScreenCaptureAccess()
        Self.primeScreenCaptureKitPermissionListing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.openPrivacyPane("Privacy_ScreenCapture")
            self?.refreshPermissionStatus()
        }
    }

    @objc private func refreshPermissionStatusClicked(_ sender: Any) {
        refreshPermissionStatus()
    }

    @objc private func resetAllSettingsClicked(_ sender: Any) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Reset all LiquidBar settings?")
        alert.informativeText = L10n.tr("This restores default preferences and keeps the current app installed.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("Reset All"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        let response: NSApplication.ModalResponse
        if let window {
            response = alert.runModal()
            window.makeKey()
        } else {
            response = alert.runModal()
        }
        guard response == .alertFirstButtonReturn else { return }

        var defaults = Config()
        defaults.validate()
        defaults.save()
        L10n.applyAppLanguage(defaults.appLanguage)
        applyConfigToControls(defaults)
        onConfigChanged?()
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

    private func appendBlacklistBundleId(_ bundleId: String) {
        var ids = blacklistField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !ids.contains(bundleId) {
            ids.append(bundleId)
        }
        blacklistField.stringValue = Self.uniquePreservingOrder(ids).joined(separator: ", ")
        scheduleAutoApply()
    }

    private func refreshPermissionStatus() {
        let accessibilityAllowed = AXIsProcessTrusted()
        accessibilityStatusLabel?.stringValue = accessibilityAllowed ? L10n.tr("Allowed") : L10n.tr("Needs Access")
        inputMonitoringStatusLabel?.stringValue = Self.inputMonitoringPermissionStatus(
            inputMonitoringAllowed: HotkeyMonitor.inputMonitoringAccessGranted()
        )
        screenRecordingStatusLabel?.stringValue = CGPreflightScreenCaptureAccess() ? L10n.tr("Allowed") : L10n.tr("Needs Access")
    }

    static func inputMonitoringPermissionStatus(inputMonitoringAllowed: Bool) -> String {
        inputMonitoringAllowed ? L10n.tr("Allowed") : L10n.tr("Needs Access")
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func primeScreenCaptureKitPermissionListing() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { _, error in
            if let error {
                Log.event.debug("ScreenCaptureKit permission prime failed from Preferences: \(String(describing: error))")
            }
        }
    }

    private func clearTransientTextFocus() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.window?.endEditing(for: nil)
            self?.window?.makeFirstResponder(nil)
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
        shared?.scrollSelectedTabToTop()
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI Helpers

    private func localizedItems(_ keys: [String]) -> [String] {
        keys.map { L10n.tr($0) }
    }

    private func formatPixels(_ value: Int) -> String {
        L10n.tr("%d px", value)
    }

    private func formatPoints(_ value: Int) -> String {
        L10n.tr("%d pt", value)
    }

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

    private func makeNumberField(frame: NSRect, min: Int, max: Int) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .right
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: min)
        formatter.maximum = NSNumber(value: max)
        formatter.allowsFloats = false
        formatter.generatesDecimalNumbers = false
        field.formatter = formatter
        return field
    }

    private func makeActionButton(title: String, symbolName: String, frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(frame: frame)
        button.bezelStyle = .rounded
        button.title = title
        button.toolTip = title
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        if let cell = button.cell as? NSButtonCell {
            cell.lineBreakMode = .byTruncatingTail
        }
        return button
    }

    private func makeSystemIndicatorModePopup(at point: NSPoint) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: point.x, y: point.y, width: 150, height: 26), pullsDown: false)
        popup.addItems(withTitles: localizedItems(["Percent", "Bar", "Graph"]))
        popup.target = self
        popup.action = #selector(controlChanged(_:))
        return popup
    }

    private func makeSystemIndicatorColorWell(metric: SystemIndicatorMetric, at point: NSPoint) -> NSColorWell {
        let well = NSColorWell(frame: NSRect(x: point.x, y: point.y, width: 44, height: 24))
        well.color = SystemIndicatorColorPalette.defaultColor(for: metric, severity: 0.2)
        well.target = self
        well.action = #selector(controlChanged(_:))
        let label = L10n.tr("%@ color", metric.label)
        well.toolTip = label
        well.setAccessibilityLabel(label)
        return well
    }

    private func scrollSelectedTabToTop() {
        let selectedIndex = tabViewController.selectedTabViewItemIndex
        guard selectedIndex >= 0,
              selectedIndex < tabViewController.tabViewItems.count,
              let tabView = tabViewController.tabViewItems[selectedIndex].viewController?.view,
              let scrollView = firstScrollView(in: tabView)
        else { return }

        scrollDocumentViewToTop(in: scrollView)
    }

    private func scrollDocumentViewToTop(in scrollView: NSScrollView, fallbackViewportHeight: CGFloat? = nil) {
        guard let documentView = scrollView.documentView else { return }

        let measuredViewportHeight = scrollView.contentView.bounds.height
        let viewportHeight = measuredViewportHeight > 0
            ? measuredViewportHeight
            : fallbackViewportHeight ?? scrollView.frame.height
        let topY = max(0, documentView.bounds.height - viewportHeight)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private static func displayPath(for url: URL) -> String {
        let path = url.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func addSectionHeader(_ text: String, at point: NSPoint, width: CGFloat, to parent: NSView) {
        let label = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 140, height: 18))
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let labelWidth = min(max(90, ceil(label.intrinsicContentSize.width) + 10), width * 0.45)
        label.frame.size.width = labelWidth
        parent.addSubview(label)

        let separatorX = point.x + labelWidth + 10
        let separator = NSBox(frame: NSRect(x: separatorX, y: point.y + 7, width: max(0, point.x + width - separatorX), height: 1))
        separator.boxType = .separator
        parent.addSubview(separator)
    }

    private func makeCheckbox(_ title: String, at point: NSPoint) -> NSButton {
        let cb = NSButton(frame: NSRect(x: point.x, y: point.y, width: 420, height: 22))
        cb.setButtonType(.switch)
        cb.title = title
        cb.toolTip = title
        cb.font = NSFont.systemFont(ofSize: 13)
        return cb
    }

    deinit {
        #if DEBUG
        Log.ui.debug("SettingsWindowController deinit")
        #endif
    }
}
