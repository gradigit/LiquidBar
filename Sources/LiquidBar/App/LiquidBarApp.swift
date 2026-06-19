import AppKit

@main
@MainActor
struct LiquidBarApp {
    static func main() {
        if CLI.runIfRequested() {
            return
        }
        let app = NSApplication.shared
        let isUITestControl = ProcessInfo.processInfo.environment["LIQUIDBAR_TEST_CONTROL"] == "1"
        // UI tests need the AX tree to be queryable. Accessory apps can expose only
        // partial AX hierarchies depending on macOS/XCTest behavior, so run as regular
        // app in test-control mode.
        app.setActivationPolicy(isUITestControl ? .regular : .accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        if isUITestControl {
            app.activate(ignoringOtherApps: true)
        }
        app.run()
    }
}
