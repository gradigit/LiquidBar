import Foundation

enum LoginItem {
    static let label = "com.liquidbar.daemon"

    static var plistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(label).plist"
    }

    static func enable() throws {
        let exe = currentExecutablePath()
        let dir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try launchAgentPlistData(executablePath: exe)
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
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

    static func currentExecutablePath() -> String {
        Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
    }

    static func launchAgentPlistData(executablePath: String) throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
