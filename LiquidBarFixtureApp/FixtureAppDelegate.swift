import AppKit

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = FixtureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.bootstrapFromEnvironment()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.teardown()
    }
}

