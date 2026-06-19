import Foundation

enum LoginItem {
    static let label = "com.liquidbar.daemon"

    static var plistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(label).plist"
    }

    static func enable() throws {
        let exe = ProcessInfo.processInfo.arguments[0]
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(exe)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        let dir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["load", plistPath])
    }

    static func disable() {
        guard FileManager.default.fileExists(atPath: plistPath) else { return }
        Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["unload", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }
}
