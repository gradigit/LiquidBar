import Darwin
import Testing
@testable import LiquidBar

@Suite("WindowManager AX Gating")
struct WindowManagerAXGatingTests {
    @Test func distinctMultiWindowAppsDoNotNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document A", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Document B", bounds: WindowBounds(x: 520, y: 0, width: 500, height: 400)),
            entry(id: 3, pid: 99, title: "Other", bounds: WindowBounds(x: 0, y: 420, width: 500, height: 400)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries).isEmpty)
    }

    @Test func overlappingSameTitleWindowsNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Document", bounds: WindowBounds(x: 10, y: 10, width: 500, height: 400)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries) == [42])
    }

    @Test func tinySurfaceWindowsNeedAXGhostCollapse() {
        let entries = [
            entry(id: 1, pid: 42, title: "Document", bounds: WindowBounds(x: 0, y: 0, width: 500, height: 400)),
            entry(id: 2, pid: 42, title: "Palette", bounds: WindowBounds(x: 0, y: 0, width: 1, height: 1)),
        ]

        #expect(WindowManager.ghostCollapseCandidatePids(entries) == [42])
    }

    @Test func minimizedAXStateIsOnlyQueriedForVisibleMinimizedCandidates() {
        #expect(WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: true,
            axEnabled: true
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: false,
            axEnabled: true
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: false,
            showMinimizedWindows: true,
            axEnabled: false
        ))
        #expect(!WindowManager.shouldQueryAXMinimizedState(
            isHidden: true,
            showMinimizedWindows: true,
            axEnabled: true
        ))
    }

    @Test func invalidCompositorSurfacesHaveNoUsableGeometry() {
        let surface = entry(
            id: 10,
            pid: 42,
            title: "Palette",
            bounds: WindowBounds(x: 0, y: 0, width: 1, height: 1)
        ).info

        #expect(!WindowSurfaceClassifier.hasUsableGeometry(surface.bounds))
    }

    @Test func compactUntitledSurfacesAreRejectedWithoutAXValidation() {
        let surface = entry(
            id: 10,
            pid: 42,
            title: "",
            bounds: WindowBounds(x: 400, y: 180, width: 360, height: 72)
        ).info

        #expect(WindowSurfaceClassifier.hasUsableGeometry(surface.bounds))
        #expect(WindowSurfaceClassifier.needsAXSurfaceValidation(surface))
        #expect(WindowSurfaceClassifier.shouldRejectWithoutAXValidation(surface))
    }

    @Test func compactTitledSurfacesNeedAXValidationButAreNotRejectedWithoutIt() {
        let surface = entry(
            id: 10,
            pid: 42,
            title: "Small Utility",
            bounds: WindowBounds(x: 400, y: 180, width: 360, height: 72)
        ).info

        #expect(WindowSurfaceClassifier.needsAXSurfaceValidation(surface))
        #expect(!WindowSurfaceClassifier.shouldRejectWithoutAXValidation(surface))
    }

    @Test func normalUntitledWindowsCanStillUseAXTitleFallback() {
        let surface = entry(
            id: 10,
            pid: 42,
            title: "",
            bounds: WindowBounds(x: 100, y: 100, width: 900, height: 600)
        ).info

        #expect(WindowSurfaceClassifier.hasUsableGeometry(surface.bounds))
        #expect(!WindowSurfaceClassifier.needsAXSurfaceValidation(surface))
        #expect(!WindowSurfaceClassifier.shouldRejectWithoutAXValidation(surface))
    }

    @Test func logicalIdentityCollapsesStaleDimmedReplacement() {
        let live = entry(
            id: 10,
            pid: 42,
            title: "Document",
            bounds: WindowBounds(x: 100, y: 100, width: 900, height: 600)
        ).info
        let stale = WindowInfo(
            id: WindowId(20),
            bundleId: live.bundleId,
            appName: live.appName,
            title: live.title,
            isHidden: false,
            isMinimized: true,
            monitorId: live.monitorId,
            bounds: WindowBounds(x: 112, y: 100, width: 900, height: 600)
        )

        #expect(WindowLogicalIdentity.isLikelySameWindow(live, stale))
        #expect(WindowLogicalIdentity.deduped([stale, live]).map(\.id.raw) == [10])
    }

    @Test func logicalIdentityPreservesSeparatedSameTitleWindows() {
        let first = entry(
            id: 10,
            pid: 42,
            title: "Document",
            bounds: WindowBounds(x: 100, y: 100, width: 700, height: 500)
        ).info
        let second = entry(
            id: 20,
            pid: 42,
            title: "Document",
            bounds: WindowBounds(x: 900, y: 100, width: 700, height: 500)
        ).info

        #expect(!WindowLogicalIdentity.isLikelySameWindow(first, second))
        #expect(WindowLogicalIdentity.deduped([first, second]).map(\.id.raw) == [10, 20])
    }

    @Test func logicalIdentityCollapsesContainedSameTitleAuxiliarySurface() {
        let main = entry(
            id: 10,
            pid: 42,
            bundleId: "org.mozilla.firefox",
            title: "Models - Venice.ai - Venice Uncensored AI",
            appName: "Firefox",
            bounds: WindowBounds(x: 0, y: 30, width: 1280, height: 1378)
        ).info
        let auxiliary = entry(
            id: 20,
            pid: 42,
            bundleId: "org.mozilla.firefox",
            title: "Models - Venice.ai - Venice Uncensored AI",
            appName: "Firefox",
            bounds: WindowBounds(x: 186, y: 1236, width: 280, height: 194)
        ).info

        #expect(WindowLogicalIdentity.isLikelySameWindow(main, auxiliary))
        #expect(WindowLogicalIdentity.deduped([auxiliary, main]).map(\.id.raw) == [10])
    }

    @Test func logicalIdentityCollapsesLowInformationTitleDuplicateAtSameBounds() {
        let real = entry(
            id: 10,
            pid: 42,
            title: "axis terminal - Admin | axis",
            appName: "axis terminal",
            bounds: WindowBounds(x: 1280, y: 30, width: 1280, height: 1378)
        ).info
        let duplicate = entry(
            id: 20,
            pid: 42,
            title: "axis terminal",
            appName: "axis terminal",
            bounds: WindowBounds(x: 1280, y: 30, width: 1280, height: 1378)
        ).info

        #expect(WindowLogicalIdentity.isLikelySameWindow(real, duplicate))
        #expect(WindowLogicalIdentity.deduped([duplicate, real]).map(\.id.raw) == [10])
    }

    @Test func logicalIdentityPreservesSameBoundsWithDifferentRealTitles() {
        let first = entry(
            id: 10,
            pid: 42,
            title: "Document A",
            bounds: WindowBounds(x: 1280, y: 30, width: 1280, height: 1378)
        ).info
        let second = entry(
            id: 20,
            pid: 42,
            title: "Document B",
            bounds: WindowBounds(x: 1280, y: 30, width: 1280, height: 1378)
        ).info

        #expect(!WindowLogicalIdentity.isLikelySameWindow(first, second))
        #expect(WindowLogicalIdentity.deduped([first, second]).map(\.id.raw) == [10, 20])
    }

    @Test func logicalIdentityCollapsesChromeWrapperFindSurface() {
        let real = entry(
            id: 10,
            pid: 42,
            bundleId: "com.google.Chrome.app.ncnapjhjgoahlhgibcjoppohjidfieoo",
            title: "axis terminal - Admin | axis",
            appName: "axis terminal",
            bounds: WindowBounds(x: 0, y: 30, width: 1280, height: 1378)
        ).info
        let chromeSurface = entry(
            id: 20,
            pid: 99,
            bundleId: "com.google.Chrome",
            title: "axis terminal",
            appName: "Google Chrome",
            bounds: WindowBounds(x: 0, y: 30, width: 1280, height: 1378)
        ).info

        #expect(WindowLogicalIdentity.isLikelySameWindow(real, chromeSurface))
        #expect(WindowLogicalIdentity.deduped([chromeSurface, real]).map(\.id.raw) == [10])
    }

    @Test func logicalIdentityPreservesUnrelatedLowInformationSurface() {
        let real = entry(
            id: 10,
            pid: 42,
            bundleId: "com.example.real",
            title: "axis terminal - Admin | axis",
            appName: "axis terminal",
            bounds: WindowBounds(x: 0, y: 30, width: 1280, height: 1378)
        ).info
        let unrelated = entry(
            id: 20,
            pid: 99,
            bundleId: "com.example.other",
            title: "axis terminal",
            appName: "Other",
            bounds: WindowBounds(x: 0, y: 30, width: 1280, height: 1378)
        ).info

        #expect(!WindowLogicalIdentity.isLikelySameWindow(real, unrelated))
        #expect(WindowLogicalIdentity.deduped([real, unrelated]).map(\.id.raw) == [10, 20])
    }

    private func entry(
        id: UInt32,
        pid: pid_t,
        bundleId: String = "com.example.app",
        title: String,
        appName: String = "Example",
        bounds: WindowBounds
    ) -> (info: WindowInfo, pid: pid_t) {
        (
            info: WindowInfo(
                id: WindowId(id),
                bundleId: BundleId(bundleId),
                appName: appName,
                title: title,
                isHidden: false,
                isMinimized: false,
                monitorId: MonitorId(1),
                bounds: bounds
            ),
            pid: pid
        )
    }
}
