import Foundation
import AppKit

struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let htmlUrl: String
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case prerelease
    }
}

struct UpdateInfo: Sendable {
    let current: String
    let latest: String
    let url: String
}

enum Updater {
    static let githubRepo = "liquidbar/liquidbar"
    static let currentVersion = "0.1.0"

    static func checkForUpdate() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.prerelease else { return nil }
        let remote = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName
        guard versionIsNewer(remote: remote, current: currentVersion) else { return nil }
        return UpdateInfo(current: currentVersion, latest: remote, url: release.htmlUrl)
    }

    static func versionIsNewer(remote: String, current: String) -> Bool {
        func parse(_ v: String) -> (Int, Int, Int) {
            let parts = v.split(separator: ".").map { Int($0) ?? 0 }
            return (
                parts.count > 0 ? parts[0] : 0,
                parts.count > 1 ? parts[1] : 0,
                parts.count > 2 ? parts[2] : 0
            )
        }
        let r = parse(remote)
        let c = parse(current)
        return (r.0, r.1, r.2) > (c.0, c.1, c.2)
    }

    @MainActor
    static func openReleasePage(url: String) {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
