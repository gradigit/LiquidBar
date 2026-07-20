import AppKit
import CoreGraphics
import Testing
@testable import LiquidBar

@Suite
struct PanelManagerSpaceVisibilityTests {
    @Test func desktopSpacesDoNotSuppressTaskbar() {
        #expect(
            PanelManager.shouldSuppressTaskbar(
                currentSpace: .init(key: "123", type: SpacesService.CurrentSpaceInfo.desktopType)
            ) == false
        )
    }

    @Test func fullscreenOrSpecialSpacesSuppressTaskbar() {
        #expect(
            PanelManager.shouldSuppressTaskbar(
                currentSpace: .init(key: "456", type: 4)
            ) == true
        )
    }

    @Test func taskbarSpaceTransitionTracksSuppressedAndRestoredDisplays() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let transition = PanelManager.taskbarSpaceTransition(
            currentSpaceInfoByDisplay: [
                display1: .init(key: "111", type: 4),
                display2: .init(key: "222", type: SpacesService.CurrentSpaceInfo.desktopType)
            ],
            previousSuppressed: [display2]
        )

        #expect(transition.suppressed == [display1])
        #expect(transition.restored == [display2])
    }

    @Test func fullscreenWindowCoverSuppressesOnlyCoveredDisplay() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900),
                    monitorId: display1
                )
            ],
            displayBoundsById: [
                display1: CGRect(x: 0, y: 0, width: 1440, height: 900),
                display2: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
            ]
        )

        #expect(covered == [display1])
    }

    @Test func maximizedWindowBelowMenuBarDoesNotSuppressTaskbar() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(
                    bounds: WindowBounds(x: 0, y: 25, width: 1440, height: 875),
                    monitorId: display
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ]
        )

        #expect(covered.isEmpty)
    }

    @Test func hiddenMinimizedAndSystemWindowsDoNotSuppressTaskbar() {
        let display: CGDirectDisplayID = 1
        let bounds = WindowBounds(x: 0, y: 0, width: 1440, height: 900)
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            windows: [
                makeWindow(id: 1, bundleId: "com.example.hidden", isHidden: true, bounds: bounds, monitorId: display),
                makeWindow(id: 2, bundleId: "com.example.minimized", isMinimized: true, bounds: bounds, monitorId: display),
                makeWindow(id: 3, bundleId: "com.apple.dock", bounds: bounds, monitorId: display)
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ]
        )

        #expect(covered.isEmpty)
    }

    @Test func rawFullscreenVideoSurfaceSuppressesCoveredDisplay() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 101,
                    ownerName: "Google Chrome",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 999
        )

        #expect(covered == [display])
    }

    @Test func elevatedBrowserVideoSurfaceSuppressesCoveredDisplay() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func safariMenuBarCompositeSuppressesCoveredDisplay() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 26,
                    bounds: WindowBounds(x: 0, y: 0, width: 1710, height: 39),
                    alpha: 0
                ),
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 39, width: 1710, height: 1073)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1710, height: 1112)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func menuBarInsetWindowWithoutTransparentCompanionIsNotFullscreen() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 39, width: 1710, height: 1073)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1710, height: 1112)
            ],
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
    }

    @Test func unrelatedTransparentStripDoesNotMakeWindowFullscreen() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 103,
                    ownerName: "Overlay",
                    layer: 26,
                    bounds: WindowBounds(x: 0, y: 0, width: 1710, height: 39),
                    alpha: 0
                ),
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 39, width: 1710, height: 1073)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1710, height: 1112)
            ],
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
    }

    @Test func fullscreenDiagnosticsIdentifyCompositeSurfaceWithoutWindowTitles() {
        let display: CGDirectDisplayID = 1
        let evidence = PanelManager.fullscreenSuppressionDiagnosticEvidence(
            windows: [],
            candidates: [
                .init(
                    pid: 102,
                    windowId: 11,
                    ownerName: "Safari",
                    layer: 26,
                    bounds: WindowBounds(x: 0, y: 0, width: 1710, height: 39),
                    alpha: 0
                ),
                .init(
                    pid: 102,
                    windowId: 12,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 39, width: 1710, height: 1073)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1710, height: 1112)
            ],
            currentProcessId: 100
        )

        #expect(evidence.count == 1)
        #expect(evidence[0].contains("raw_composite"))
        #expect(evidence[0].contains("owner=Safari"))
        #expect(evidence[0].contains("wid=12"))
        #expect(evidence[0].contains("companions={wid=11"))
    }

    @Test func fullscreenDiagnosticsExcludeUnrelatedTransparentCompanion() {
        let display: CGDirectDisplayID = 1
        let evidence = PanelManager.fullscreenSuppressionDiagnosticEvidence(
            windows: [],
            candidates: [
                .init(
                    pid: 103,
                    windowId: 11,
                    ownerName: "Overlay",
                    layer: 26,
                    bounds: WindowBounds(x: 0, y: 0, width: 1710, height: 39),
                    alpha: 0
                ),
                .init(
                    pid: 102,
                    windowId: 12,
                    ownerName: "Safari",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 39, width: 1710, height: 1073)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1710, height: 1112)
            ],
            currentProcessId: 100
        )

        #expect(evidence.isEmpty)
    }

    @Test func browserControlsDoNotExposeBarOverElevatedFullscreenSurface() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 104,
                    ownerName: "Safari Web Content",
                    layer: 30,
                    bounds: WindowBounds(x: 0, y: 700, width: 1440, height: 200)
                ),
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func unrelatedOverlayDoesNotExposeBarOverFullscreenSurface() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 103,
                    ownerName: "Notes",
                    layer: 0,
                    bounds: WindowBounds(x: 100, y: 100, width: 1000, height: 650)
                ),
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func smallAuxiliaryWindowDoesNotBlockFullscreenSurface() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 103,
                    ownerName: "Password Manager",
                    layer: 40,
                    bounds: WindowBounds(x: 1120, y: 40, width: 240, height: 160)
                ),
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900)
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func elevatedFullscreenSurfaceSuppressesOnlyItsDisplay() {
        let primary: CGDirectDisplayID = 1
        let secondary: CGDirectDisplayID = 2
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 102,
                    ownerName: "Safari",
                    layer: 25,
                    bounds: WindowBounds(x: 1440, y: -180, width: 2560, height: 1440)
                ),
                .init(
                    pid: 103,
                    ownerName: "Codex",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 25, width: 1440, height: 875)
                )
            ],
            displayBoundsById: [
                primary: CGRect(x: 0, y: 0, width: 1440, height: 900),
                secondary: CGRect(x: 1440, y: -180, width: 2560, height: 1440)
            ],
            currentProcessId: 100
        )

        #expect(covered == [secondary])
    }

    @Test func windowSpanningDisplaysDoesNotCountAsFullscreenOnEitherDisplay() {
        let primary: CGDirectDisplayID = 1
        let secondary: CGDirectDisplayID = 2
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 102,
                    ownerName: "Presentation App",
                    layer: 0,
                    bounds: WindowBounds(x: 0, y: 0, width: 4000, height: 1440)
                )
            ],
            displayBoundsById: [
                primary: CGRect(x: 0, y: 0, width: 1440, height: 900),
                secondary: CGRect(x: 1440, y: 0, width: 2560, height: 1440)
            ],
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
    }

    @Test func rawFullscreenCoverIgnoresOwnSystemAndTransparentSurfaces() {
        let display: CGDirectDisplayID = 1
        let bounds = WindowBounds(x: 0, y: 0, width: 1440, height: 900)
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(pid: 100, ownerName: "LiquidBar", layer: 0, bounds: bounds),
                .init(pid: 101, ownerName: "Dock", layer: 0, bounds: bounds),
                .init(pid: 102, ownerName: "loginwindow", layer: 2004, bounds: bounds),
                .init(pid: 103, ownerName: "Safari", layer: 25, bounds: bounds, alpha: 0)
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
    }

    @Test func backgroundOnlyElevatedOverlayDoesNotSuppressTaskbar() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let display3: CGDirectDisplayID = 3
        let backgroundOnly = NSApplication.ActivationPolicy.prohibited.rawValue
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 67996,
                    windowId: 30439,
                    ownerName: "confetti",
                    layer: 25,
                    bounds: WindowBounds(x: 3, y: 1442, width: 1704, height: 1108),
                    activationPolicyRawValue: backgroundOnly
                ),
                .init(
                    pid: 67996,
                    windowId: 30438,
                    ownerName: "confetti",
                    layer: 25,
                    bounds: WindowBounds(x: 7, y: 4, width: 2546, height: 1432),
                    activationPolicyRawValue: backgroundOnly
                ),
                .init(
                    pid: 67996,
                    windowId: 30440,
                    ownerName: "confetti",
                    layer: 25,
                    bounds: WindowBounds(x: -2553, y: 4, width: 2546, height: 1432),
                    activationPolicyRawValue: backgroundOnly
                )
            ],
            displayBoundsById: [
                display1: CGRect(x: 0, y: 1440, width: 1710, height: 1112),
                display2: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                display3: CGRect(x: -2560, y: 0, width: 2560, height: 1440)
            ],
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
    }

    @Test func unresolvedProcessPolicyStillAllowsFullscreenSurface() {
        let display: CGDirectDisplayID = 1
        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: [
                .init(
                    pid: 104,
                    ownerName: "Browser Helper",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900),
                    activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(covered == [display])
    }

    @Test func unresolvedGlobalOverlayDoesNotSuppressAnyDisplay() {
        let display1: CGDirectDisplayID = 1
        let display2: CGDirectDisplayID = 2
        let display3: CGDirectDisplayID = 3
        let candidates: [PanelManager.FullscreenCoverCandidate] = [
            .init(
                pid: 67996,
                windowId: 30439,
                ownerName: "confetti",
                layer: 25,
                bounds: WindowBounds(x: 3, y: 1442, width: 1704, height: 1108),
                activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
            ),
            .init(
                pid: 67996,
                windowId: 30438,
                ownerName: "confetti",
                layer: 25,
                bounds: WindowBounds(x: 7, y: 4, width: 2546, height: 1432),
                activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
            ),
            .init(
                pid: 67996,
                windowId: 30440,
                ownerName: "confetti",
                layer: 25,
                bounds: WindowBounds(x: -2553, y: 4, width: 2546, height: 1432),
                activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
            )
        ]
        let displays: [CGDirectDisplayID: CGRect] = [
            display1: CGRect(x: 0, y: 1440, width: 1710, height: 1112),
            display2: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            display3: CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        ]

        let covered = PanelManager.fullscreenCoveredDisplayIds(
            candidates: candidates,
            displayBoundsById: displays,
            currentProcessId: 100
        )
        let evidence = PanelManager.ignoredGlobalOverlayDiagnosticEvidence(
            candidates: candidates,
            displayBoundsById: displays,
            currentProcessId: 100
        )

        #expect(covered.isEmpty)
        #expect(evidence.count == 1)
        #expect(evidence[0].contains("displays=[1,2,3]"))
        #expect(evidence[0].contains("windows=[30438,30439,30440]"))
    }

    @Test func activationPolicyLookupIsLimitedToFullscreenGeometry() {
        let display: CGDirectDisplayID = 1
        let pids = PanelManager.fullscreenGeometryCandidatePids(
            candidates: [
                .init(
                    pid: 101,
                    ownerName: "Regular Window",
                    layer: 0,
                    bounds: WindowBounds(x: 100, y: 100, width: 800, height: 600),
                    activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
                ),
                .init(
                    pid: 102,
                    ownerName: "Fullscreen Surface",
                    layer: 25,
                    bounds: WindowBounds(x: 0, y: 0, width: 1440, height: 900),
                    activationPolicyRawValue: PanelManager.unresolvedActivationPolicyRawValue
                )
            ],
            displayBoundsById: [
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ],
            currentProcessId: 100
        )

        #expect(pids == [102])
    }

    private func makeWindow(
        id: UInt32 = 1,
        bundleId: String = "com.example.app",
        isHidden: Bool = false,
        isMinimized: Bool = false,
        bounds: WindowBounds,
        monitorId: CGDirectDisplayID
    ) -> WindowInfo {
        WindowInfo(
            id: WindowId(id),
            bundleId: BundleId(bundleId),
            appName: "Example",
            title: "Window",
            isHidden: isHidden,
            isMinimized: isMinimized,
            monitorId: MonitorId(UInt32(monitorId)),
            bounds: bounds
        )
    }
}
