import AppKit

@main
@MainActor
struct FixtureApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let delegate = FixtureAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

