import Testing
@testable import LiquidBar

@Suite
struct AppDelegatePermissionTests {
    @MainActor
    @Test func windowLayoutFeaturesRequestMissingAccessibilityAccess() {
        #expect(AppDelegate.shouldRequestAccessibilityAccess(
            config: Config(adjustWindowsForTaskbar: true),
            environment: [:],
            preflightGranted: false
        ))
        #expect(AppDelegate.shouldRequestAccessibilityAccess(
            config: Config(experimentalWindowLayoutMemoryEnabled: true),
            environment: [:],
            preflightGranted: false
        ))
        #expect(!AppDelegate.shouldRequestAccessibilityAccess(
            config: Config(adjustWindowsForTaskbar: true, experimentalWindowLayoutMemoryEnabled: true),
            environment: [:],
            preflightGranted: true
        ))
        #expect(!AppDelegate.shouldRequestAccessibilityAccess(
            config: Config(experimentalWindowLayoutMemoryEnabled: true),
            environment: ["LIQUIDBAR_DISABLE_AX_PROMPT": "1"],
            preflightGranted: false
        ))
    }

    @MainActor
    @Test func previewsEnabledRequestsMissingScreenCaptureAccess() {
        let config = Config(previewsEnabled: true)

        #expect(AppDelegate.shouldRequestScreenCaptureAccess(
            config: config,
            environment: [:],
            preflightGranted: false
        ))
    }

    @MainActor
    @Test func previewsDisabledDoesNotRequestScreenCaptureAccess() {
        let config = Config(previewsEnabled: false)

        #expect(!AppDelegate.shouldRequestScreenCaptureAccess(
            config: config,
            environment: [:],
            preflightGranted: false
        ))
    }

    @MainActor
    @Test func existingGrantOrDisabledPromptDoesNotRequestScreenCaptureAccess() {
        let config = Config(previewsEnabled: true)

        #expect(!AppDelegate.shouldRequestScreenCaptureAccess(
            config: config,
            environment: [:],
            preflightGranted: true
        ))
        #expect(!AppDelegate.shouldRequestScreenCaptureAccess(
            config: config,
            environment: ["LIQUIDBAR_DISABLE_SCREEN_RECORDING_PROMPT": "1"],
            preflightGranted: false
        ))
    }

    @MainActor
    @Test func previewsEnabledPrimesScreenCaptureKitEvenWhenPreflightIsGranted() {
        let config = Config(previewsEnabled: true)

        #expect(AppDelegate.shouldPrimeScreenCaptureKit(
            config: config,
            environment: [:]
        ))
        #expect(!AppDelegate.shouldPrimeScreenCaptureKit(
            config: Config(previewsEnabled: false),
            environment: [:]
        ))
        #expect(!AppDelegate.shouldPrimeScreenCaptureKit(
            config: config,
            environment: ["LIQUIDBAR_DISABLE_SCREEN_RECORDING_PROMPT": "1"]
        ))
    }

    @MainActor
    @Test func cmdTabSwitcherRequestsListenEventAccess() {
        #expect(AppDelegate.shouldRequestListenEventAccess(
            config: Config(switcherEnabled: true, switcherHotkey: "cmd+tab"),
            environment: [:]
        ))
        #expect(!AppDelegate.shouldRequestListenEventAccess(
            config: Config(switcherEnabled: false, switcherHotkey: "cmd+tab"),
            environment: [:]
        ))
        #expect(!AppDelegate.shouldRequestListenEventAccess(
            config: Config(switcherEnabled: true, switcherHotkey: "option+tab"),
            environment: [:]
        ))
        #expect(!AppDelegate.shouldRequestListenEventAccess(
            config: Config(switcherEnabled: true, switcherHotkey: "cmd+tab"),
            environment: ["LIQUIDBAR_DISABLE_INPUT_MONITORING_PROMPT": "1"]
        ))
    }
}
