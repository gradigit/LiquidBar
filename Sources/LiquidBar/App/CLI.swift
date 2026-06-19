import Foundation

enum CLI {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments

        if args.contains("--print-config-path") {
            print(Config.configPath.path)
            return true
        }

        if args.contains("--print-default-config") {
            do {
                print(try defaultConfigJSON())
                return true
            } catch {
                fputs("error: failed to encode default config: \(error)\n", stderr)
                return true
            }
        }

        if args.contains("--write-default-config") {
            writeDefaultConfig()
            return true
        }

        return false
    }

    private static func defaultConfigJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Config())
        return String(decoding: data, as: UTF8.self)
    }

    private static func writeDefaultConfig() {
        let path = Config.configPath

        // Always keep a backup if the file already exists and has any bytes.
        if let data = try? Data(contentsOf: path),
           !data.isEmpty {
            do {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyyMMdd-HHmmss"
                let stamp = df.string(from: Date())
                let backup = Config.configDirectory.appendingPathComponent("config.json.bak-\(stamp)")
                try? FileManager.default.copyItem(at: path, to: backup)
                print("Backed up existing config to: \(backup.path)")
            }
        }

        let config = Config()
        config.save()
        print("Wrote default config to: \(path.path)")
    }
}

