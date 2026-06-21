// LiquidBarPanel.swift — NSPanel with Liquid Glass + NativeBarView
//
// View hierarchy:
//   NSPanel (titled/fullSize or borderless depending on mode)
//     └── contentView (system NSThemeFrame)
//           ├── NSGlassEffectView (macOS 26+ public API — true Liquid Glass)
//           └── NativeBarView (retained Core Animation layers) on top
//
// Uses NSGlassEffectView (macOS 26+) for native Liquid Glass.

import AppKit
import QuartzCore

@MainActor
final class LiquidBarPanel: NSPanel {
    /// A/B guard: vertical+flush can use a borderless host to avoid titled-window
    /// top-corner chrome artifacts. Set to false for immediate rollback.
    private static let useBorderlessHostForVerticalFlush = true

    private(set) var displayId: CGDirectDisplayID = 0
    private(set) var barView: NativeBarView!
    private(set) var barHeight: CGFloat = 0
    private(set) var position: Position = .bottom
    private(set) var barStyle: BarStyle = .flush
    private(set) var theme: Theme = .system
    private(set) var glassStyle: GlassStyle = .publicRegular

    private var backgroundView: NSView?
    /// Temporary bootstrap surface to avoid opaque/dark flashes before glass is warmed up.
    /// This is faded out shortly after `refreshGlass()`.
    private var bootstrapView: NSVisualEffectView?
    private var reduceTransparencyObservation: NSKeyValueObservation?
    private var chromeReapTimer: Timer?
    private var chromeReapUntil: CFTimeInterval = 0
    private(set) var isSpaceSuppressed: Bool = false
    private var contentInsetLeft: CGFloat = 0
    private var contentInsetRight: CGFloat = 0
    private var contentInsetTop: CGFloat = 0
    private var contentInsetBottom: CGFloat = 0

    var atTop: Bool { position.isTop }


    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    convenience init(
        screen: NSScreen,
        displayId: CGDirectDisplayID,
        barHeight: CGFloat,
        position: Position,
        barStyle: BarStyle,
        theme: Theme,
        glassStyle: GlassStyle
    ) {
        let geometry = Self.computeGeometry(screen: screen, barHeight: barHeight, position: position, barStyle: barStyle)
        let frame = geometry.frame
        let panelStyleMask = Self.panelStyleMask(position: position, barStyle: barStyle)

        self.init(
            contentRect: frame,
            styleMask: panelStyleMask,
            backing: .buffered,
            defer: false
        )
        // Force exact frame (especially for titled hosts where titlebar inflates geometry).
        setFrame(frame, display: false)
        contentInsetLeft = geometry.contentInsetLeft
        contentInsetRight = geometry.contentInsetRight
        contentInsetTop = geometry.contentInsetTop
        contentInsetBottom = geometry.contentInsetBottom

        self.displayId = displayId
        self.barHeight = barHeight
        self.position = position
        self.barStyle = barStyle
        self.theme = theme
        self.glassStyle = glassStyle
        self.barView = NativeBarView(frame: NSRect(origin: .zero, size: frame.size))
        self.barView.displayId = displayId
        self.barView.orientation = position

        configurePanel()
        applyCornerRadius()

        // Configure barView without glass — glass is deferred to showPanelsAfterDelay()
        // so NSGlassEffectView's CABackdropLayer has a live compositor to sample from.
        barView.configure(scale: screen.backingScaleFactor)
        if let cv = contentView {
            // UI tests need stable pixels for screenshot diffs. When enabled, paint a
            // deterministic backdrop before any visual effects initialize.
            let env = ProcessInfo.processInfo.environment
            if env["LIQUIDBAR_TEST_SOLID_BACKGROUND"] == "1" {
                let luma = Double(env["LIQUIDBAR_TEST_SOLID_BG_LUMA"] ?? "") ?? 0.12
                let clamped = CGFloat(max(0.0, min(1.0, luma)))
                let bg = NSView(frame: cv.bounds)
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor(calibratedWhite: clamped, alpha: 1.0).cgColor
                bg.autoresizingMask = [.width, .height]
                cv.addSubview(bg)
            }

            // Bootstrap background: before we install NSGlassEffectView, the window's
            // NSThemeFrame can flash dark/opaque on cold start. Keep a VisualEffect
            // behind the taskbar layer until refreshGlass() swaps in true glass.
            let bootstrap = NSVisualEffectView(frame: cv.bounds)
            bootstrap.state = .active
            // Bootstrap should never sample a not-yet-ready backdrop (black/dark flash).
            // We keep this deterministic and swap to true glass in `refreshGlass()`.
            bootstrap.material = .windowBackground
            bootstrap.blendingMode = .withinWindow
            bootstrap.autoresizingMask = [.width, .height]
            cv.addSubview(bootstrap)
            bootstrapView = bootstrap

            barView.frame = barContentRect(in: cv.bounds)
            barView.autoresizingMask = [.width, .height]
            cv.addSubview(barView)
        }

        // Start nearly invisible — alphaValue must be > 0 so WindowServer composites the
        // window and CABackdropLayer can warm up before we fade in, but keep it low
        // so we don't show a "dark strip" on cold start.
        alphaValue = 0.001
        orderFrontRegardless()

        // Some parts of the window chrome are created lazily. Re-hide after the first
        // ordering so we never show the traffic-light controls in the bar.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.hideWindowChrome()
                self?.scheduleChromeReap(duration: 2.5)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("LiquidBarPanel does not support NSCoding")
    }

    deinit {
        reduceTransparencyObservation?.invalidate()
        #if DEBUG
        print("[DEINIT] LiquidBarPanel")
        #endif
    }

    // MARK: - Panel Configuration

    private static func panelStyleMask(position: Position, barStyle: BarStyle) -> NSWindow.StyleMask {
        if useBorderlessHostForVerticalFlush, barStyle == .flush, position.isVertical {
            return [.borderless, .nonactivatingPanel]
        }
        return [.titled, .fullSizeContentView, .nonactivatingPanel]
    }

    private static func panelWindowLevel(for position: Position) -> NSWindow.Level {
        // Keep taskbar above app windows by default.
        let defaultLevel = Int(CGWindowLevelForKey(.statusWindow)) - 1
        // Right sidebar can intersect Notification Center banners; lower it to dock level
        // so system notifications reliably render above the bar.
        if position == .right {
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        }
        return NSWindow.Level(rawValue: defaultLevel)
    }

    nonisolated static func taskbarCollectionBehavior() -> NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    nonisolated static func cornerFillCollectionBehavior() -> NSWindow.CollectionBehavior {
        taskbarCollectionBehavior()
    }

    private func configurePanel() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = Self.panelWindowLevel(for: position)
        collectionBehavior = Self.taskbarCollectionBehavior()
        isMovable = false
        isOpaque = false
        // Near-transparent white, not .clear — CABackdropLayer (used by NSGlassEffectView)
        // needs a non-clear background to properly initialize its compositing pipeline.
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hasShadow = barStyle == .floating

        // Hide titlebar visually (NSThemeFrame infrastructure kept for glass).
        //
        // Note: standard window buttons can be created lazily by AppKit. Hide them here
        // and re-hide during refreshGlass() after the panel is in the compositor.
        hideWindowChrome()
    }

    private func hideWindowChrome() {
        // Ensure standard window controls are not present (some NSPanel configurations
        // can add these implicitly).
        styleMask.remove([.closable, .miniaturizable, .resizable])

        if styleMask.contains(.titled) {
            titlebarAppearsTransparent = true
            titleVisibility = .hidden
            // Remove the titlebar separator line so nothing "window-y" bleeds through the glass.
            titlebarSeparatorStyle = .none
        }
        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton),
        ].compactMap { $0 }

        for b in buttons {
            b.isHidden = true
            b.alphaValue = 0
            b.isEnabled = false
            // Be aggressive: remove the traffic-light controls from the view hierarchy.
            // These can be re-created lazily; we call hideWindowChrome() multiple times.
            b.removeFromSuperview()
        }
    }

    private func scheduleChromeReap(duration: CFTimeInterval) {
        chromeReapUntil = max(chromeReapUntil, CACurrentMediaTime() + duration)
        guard chromeReapTimer == nil else { return }

        // AppKit can re-create standard window controls lazily (often on first hover
        // or after ordering). Re-apply chrome stripping briefly around those events.
        chromeReapTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                self.hideWindowChrome()
                if CACurrentMediaTime() >= self.chromeReapUntil {
                    self.chromeReapTimer?.invalidate()
                    self.chromeReapTimer = nil
                    self.chromeReapUntil = 0
                }
            }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        let needsChromeReap = styleMask.contains(.titled)
        switch event.type {
        case .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            // Traffic lights are most likely to appear the first time the user interacts
            // with the panel. Schedule a short chrome reap window to ensure they never
            // become visible.
            if needsChromeReap {
                scheduleChromeReap(duration: 2.0)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func barContentRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: contentInsetLeft,
            y: contentInsetBottom,
            width: max(1, bounds.width - contentInsetLeft - contentInsetRight),
            height: max(1, bounds.height - contentInsetTop - contentInsetBottom)
        )
    }

    /// Apply public layer-backed corner rounding to the visible content surfaces.
    private func applyCornerRadius() {
        let radius = barStyle == .floating ? GlassTokens.barCornerRadius : 0

        // The NSThemeFrame has its own layer-backed corner rounding that leaks
        // through as grey artifacts at the edges. Zero it out for flush mode.
        if let themeFrame = contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.cornerRadius = radius
            themeFrame.layer?.masksToBounds = true
        }
    }

    /// Apply theme appearance to the panel — affects NSGlassEffectView tint.
    private func applyTheme() {
        switch theme {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
    }

    override var canBecomeKey: Bool { false }

    /// Allow window to extend past screen edges in flush mode.
    /// macOS normally constrains windows to screen boundaries; we override
    /// to keep the .titled window's rounded corners off-screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // MARK: - Glass Setup

    /// Builds the glass/fallback view hierarchy. Called from refreshGlass()
    /// (after window is in compositor) and when Reduce Transparency changes.
    private func rebuildGlassViews() {
        guard let cv = contentView else { return }

        // Tear down old glass views (keep bootstrapView until after the first fade-in).
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        barView.removeFromSuperview()

        let env = ProcessInfo.processInfo.environment
        let reduceTransparency = SystemAccessibilityPreferences.reduceTransparency

        let testLuma: CGFloat? = {
            guard env["LIQUIDBAR_TEST_SOLID_BACKGROUND"] == "1" else { return nil }
            let luma = Double(env["LIQUIDBAR_TEST_SOLID_BG_LUMA"] ?? "") ?? 0.12
            return CGFloat(max(0.0, min(1.0, luma)))
        }()

        let surface = GlassSurfaceFactory.makeBackground(
            kind: .bar,
            style: glassStyle,
            reduceTransparency: reduceTransparency,
            testSolidBackgroundLuma: testLuma,
            cornerRadiusOverride: barStyle == .floating ? GlassTokens.barCornerRadius : 0
        )

        let baseView = surface.view
        baseView.frame = cv.bounds
        baseView.autoresizingMask = [.width, .height]
        cv.addSubview(baseView, positioned: .below, relativeTo: nil)
        backgroundView = baseView

        // Keep bootstrap above the first glass install to avoid transient dark/opaque frames.
        if let boot = bootstrapView {
            boot.frame = cv.bounds
            boot.autoresizingMask = [.width, .height]
            if boot.superview != cv {
                cv.addSubview(boot)
            }
            cv.addSubview(boot, positioned: .above, relativeTo: baseView)
            boot.alphaValue = 1
        }

        // NativeBarView always on top
        barView.frame = barContentRect(in: cv.bounds)
        barView.autoresizingMask = [.width, .height]
        cv.addSubview(barView)
        // Ensure retained layers are laid out immediately after reattaching.
        barView.needsLayout = true
        barView.layoutSubtreeIfNeeded()

        cv.wantsLayer = true
        let radius = barStyle == .floating ? GlassTokens.barCornerRadius : 0
        cv.layer?.cornerRadius = radius
        cv.layer?.masksToBounds = true
        cv.layer?.backgroundColor = NSColor.clear.cgColor

        // Strip NSThemeFrame artifacts (dark strip / borders) that can show up during init.
        if let themeFrame = cv.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.borderWidth = 0
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
            themeFrame.layer?.shadowOpacity = 0
            themeFrame.layer?.mask = nil
        }
    }

    // MARK: - Reduce Transparency Observation

    private func observeReduceTransparency() {
        reduceTransparencyObservation = NSWorkspace.shared.observe(
            \.accessibilityDisplayShouldReduceTransparency,
            options: [.new]
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.rebuildGlassViews()
            }
        }
    }

    // MARK: - Frame Computation

    private struct PanelGeometry {
        let frame: NSRect
        let contentInsetLeft: CGFloat
        let contentInsetRight: CGFloat
        let contentInsetTop: CGFloat
        let contentInsetBottom: CGFloat
    }

    private static func computeGeometry(screen: NSScreen, barHeight: CGFloat, position: Position, barStyle: BarStyle) -> PanelGeometry {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let overscan: CGFloat = 24

        switch barStyle {
        case .flush:
            // `.titled` windows keep NSThemeFrame corner rendering even when we try to
            // set a 0pt radius. Slight overscan pushes those corners off-screen.
            let global = NSScreen.screens.map(\.frame).reduce(screenFrame) { $0.union($1) }
            let leftOverscan: CGFloat = abs(screenFrame.minX - global.minX) < 0.5 ? overscan : 0
            let rightOverscan: CGFloat = abs(screenFrame.maxX - global.maxX) < 0.5 ? overscan : 0

            switch position {
            case .top:
                let y = visibleFrame.origin.y + visibleFrame.height - barHeight
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x - leftOverscan,
                        y: y,
                        width: screenFrame.width + leftOverscan + rightOverscan,
                        height: barHeight
                    ),
                    contentInsetLeft: leftOverscan,
                    contentInsetRight: rightOverscan,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .bottom:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x - leftOverscan,
                        y: screenFrame.origin.y,
                        width: screenFrame.width + leftOverscan + rightOverscan,
                        height: barHeight
                    ),
                    contentInsetLeft: leftOverscan,
                    contentInsetRight: rightOverscan,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .left:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x,
                        // Respect menu bar / dock-reserved vertical bounds in sidebar mode.
                        y: visibleFrame.minY,
                        width: barHeight,
                        height: visibleFrame.height
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .right:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.maxX - barHeight,
                        // Respect menu bar / dock-reserved vertical bounds in sidebar mode.
                        y: visibleFrame.minY,
                        width: barHeight,
                        height: visibleFrame.height
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            }

        case .floating:
            let margin: CGFloat = 5
            switch position {
            case .top:
                let y = visibleFrame.origin.y + visibleFrame.height - barHeight - margin
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x + margin,
                        y: y,
                        width: screenFrame.width - margin * 2,
                        height: barHeight
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .bottom:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x + margin,
                        y: screenFrame.origin.y + margin,
                        width: screenFrame.width - margin * 2,
                        height: barHeight
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .left:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.origin.x + margin,
                        y: visibleFrame.minY + margin,
                        width: barHeight,
                        height: max(1, visibleFrame.height - margin * 2)
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            case .right:
                return PanelGeometry(
                    frame: NSRect(
                        x: screenFrame.maxX - barHeight - margin,
                        y: visibleFrame.minY + margin,
                        width: barHeight,
                        height: max(1, visibleFrame.height - margin * 2)
                    ),
                    contentInsetLeft: 0,
                    contentInsetRight: 0,
                    contentInsetTop: 0,
                    contentInsetBottom: 0
                )
            }
        }
    }

    // MARK: - Update Position

    func updatePosition(screen: NSScreen, barHeight: CGFloat, position: Position, barStyle: BarStyle, theme: Theme) {
        let previousPosition = self.position
        let previousBarStyle = self.barStyle
        let previousTheme = self.theme

        self.barHeight = barHeight
        self.position = position
        self.barStyle = barStyle
        self.theme = theme
        let geometry = Self.computeGeometry(screen: screen, barHeight: barHeight, position: position, barStyle: barStyle)
        contentInsetLeft = geometry.contentInsetLeft
        contentInsetRight = geometry.contentInsetRight
        contentInsetTop = geometry.contentInsetTop
        contentInsetBottom = geometry.contentInsetBottom
        level = Self.panelWindowLevel(for: position)
        let frame = geometry.frame
        setFrame(frame, display: true)
        barView?.orientation = position
        hasShadow = barStyle == .floating

        // Sidebar state transitions (expanded/compact/hidden) can update geometry frequently.
        // Rebuilding glass every step is expensive and has caused compositor instability.
        let visualConfigurationChanged =
            previousPosition != position ||
            previousBarStyle != barStyle ||
            previousTheme != theme

        if visualConfigurationChanged {
            applyCornerRadius()
            applyTheme()
            rebuildGlassViews()
            return
        }

        // Geometry-only update: keep existing glass host and just relayout subviews.
        if let cv = contentView {
            backgroundView?.frame = cv.bounds
            bootstrapView?.frame = cv.bounds
            barView?.frame = barContentRect(in: cv.bounds)
        }
    }

    // MARK: - Glass Refresh

    /// Rebuild glass views after the window is in the compositor.
    /// Must be called after the window is ordered front so CABackdropLayer can capture the backdrop.
    func refreshGlass() {
        // Ensure window chrome is hidden once the panel is in the compositor.
        hideWindowChrome()
        scheduleChromeReap(duration: 1.0)
        rebuildGlassViews()
        // Set up reduce-transparency observer on first glass install
        if reduceTransparencyObservation == nil {
            observeReduceTransparency()
        }
    }

    /// Fade out and remove the startup bootstrap view (if present).
    /// This should be called shortly after the panel becomes visible.
    func fadeOutBootstrap(after delay: TimeInterval = 0.20, duration: TimeInterval = 0.18) {
        guard bootstrapView != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let boot = self.bootstrapView else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    boot.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        boot.removeFromSuperview()
                        self?.bootstrapView = nil
                    }
                }
            }
        }
    }

    // MARK: - Retained Layer Refresh

    /// Refresh the retained native layer tree after Space or occlusion transitions.
    func refreshRetainedLayers() {
        barView.refreshRetainedLayers()
    }

    func setSpaceSuppressed(_ suppressed: Bool) {
        guard isSpaceSuppressed != suppressed else { return }
        isSpaceSuppressed = suppressed
        if suppressed {
            orderOut(nil)
        } else {
            orderFrontRegardless()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        reduceTransparencyObservation?.invalidate()
        reduceTransparencyObservation = nil
        chromeReapTimer?.invalidate()
        chromeReapTimer = nil
        chromeReapUntil = 0
        barView?.onItemClicked = nil
        barView?.onItemReordered = nil
        barView?.onContextAction = nil
        barView?.onAppContextAction = nil
        barView?.onHoverChanged = nil
        barView?.onCursorMoved = nil
        barView?.onDragStateChanged = nil
        barView?.onScrollStep = nil
        backgroundView = nil
        bootstrapView = nil
        contentView = nil
        orderOut(nil)
    }
}
