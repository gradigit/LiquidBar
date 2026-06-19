import Foundation

@MainActor
final class DockService {
    private var originalAutohide: Bool = false
    private var isManaging: Bool = false

    private static let breadcrumbURL: URL = {
        Config.configDirectory.appendingPathComponent(".dock-state")
    }()

    // Check and restore dock state from a previous crash
    func restoreIfNeeded() {
        guard let data = try? Data(contentsOf: Self.breadcrumbURL),
              let state = try? JSONDecoder().decode(DockBreadcrumb.self, from: data) else { return }

        // Check if the PID that wrote the breadcrumb is still running
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", "\(state.pid)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // Process is dead — restore dock and clean up
            setDockAutohide(state.originalAutohide)
            try? FileManager.default.removeItem(at: Self.breadcrumbURL)
            Log.app.info("Restored dock autohide to \(state.originalAutohide) after crash recovery")
        }
    }

    func hideDock() {
        guard !isManaging else { return }
        originalAutohide = getDockAutohide()
        isManaging = true
        writeBreadcrumb()
        setDockAutohide(true)
        Log.app.info("Dock hidden (original autohide: \(self.originalAutohide))")
    }

    func restoreDock() {
        guard isManaging else { return }
        setDockAutohide(originalAutohide)
        isManaging = false
        removeBreadcrumb()
        Log.app.info("Dock restored to autohide: \(self.originalAutohide)")
    }

    private func getDockAutohide() -> Bool {
        return readDefaultsAutohide()
    }

    private func setDockAutohide(_ enabled: Bool) {
        writeDefaultsAutohide(enabled)
    }

    // MARK: - defaults fallback

    private func readDefaultsAutohide() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "autohide"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "1"
    }

    private func writeDefaultsAutohide(_ enabled: Bool) {
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        write.arguments = ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"]
        write.standardOutput = FileHandle.nullDevice
        write.standardError = FileHandle.nullDevice
        try? write.run()
        write.waitUntilExit()

        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        killall.standardOutput = FileHandle.nullDevice
        killall.standardError = FileHandle.nullDevice
        try? killall.run()
        killall.waitUntilExit()
    }

    // MARK: - Breadcrumb

    private func writeBreadcrumb() {
        let breadcrumb = DockBreadcrumb(
            originalAutohide: originalAutohide,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        do {
            try FileManager.default.createDirectory(at: Config.configDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(breadcrumb)
            try data.write(to: Self.breadcrumbURL, options: .atomic)
        } catch {
            Log.app.error("Failed to write dock breadcrumb: \(error)")
        }
    }

    private func removeBreadcrumb() {
        try? FileManager.default.removeItem(at: Self.breadcrumbURL)
    }
}

private struct DockBreadcrumb: Codable {
    let originalAutohide: Bool
    let pid: Int32
}
