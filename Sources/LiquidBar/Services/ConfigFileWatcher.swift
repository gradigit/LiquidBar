import Foundation
import os
import Darwin

/// Watches LiquidBar's config directory and invokes a callback when `config.json` changes.
///
/// Notes:
/// - `Config.save()` uses atomic writes (tmp + rename), so we watch the directory, not the file.
/// - We coalesce events and only fire when the config file modification timestamp changes.
final class ConfigFileWatcher {
    private let configPath: URL
    private let onChange: @MainActor () -> Void

    private var dirFD: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?

    private var lastSeenMTime: TimeInterval = 0

    init(configPath: URL, onChange: @escaping @MainActor () -> Void) {
        self.configPath = configPath
        self.onChange = onChange
        self.lastSeenMTime = Self.mtime(of: configPath)
    }

    deinit {
        stop()
    }

    func start() {
        guard source == nil else { return }

        let dir = configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        dirFD = open(dir.path, O_EVTONLY)
        guard dirFD >= 0 else {
            Log.config.error("ConfigFileWatcher failed to open directory: \(dir.path, privacy: .public)")
            return
        }

        let mask: DispatchSource.FileSystemEvent = [.write, .rename, .delete, .attrib, .extend, .link, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: mask,
            queue: DispatchQueue.global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }

        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.dirFD >= 0 {
                close(self.dirFD)
                self.dirFD = -1
            }
        }

        source = src
        src.resume()
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
        if dirFD >= 0 {
            close(dirFD)
            dirFD = -1
        }
    }

    private func handleDirectoryEvent() {
        debounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }

            let mtime = Self.mtime(of: self.configPath)
            guard mtime > 0 else { return }
            guard mtime != self.lastSeenMTime else { return }
            self.lastSeenMTime = mtime

            let onChange = self.onChange
            Task { @MainActor in onChange() }
        }

        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private static func mtime(of url: URL) -> TimeInterval {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return 0
        }
        return date.timeIntervalSince1970
    }
}
