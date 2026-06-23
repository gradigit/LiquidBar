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

enum UpdaterError: Error {
    case untrustedReleaseURL(String)
}

enum Updater {
    static let githubRepo = "gradigit/LiquidBar"
    static let currentVersion = "1.0.0"

    static var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(githubRepo)")!
    }

    static func checkForUpdate() async throws -> UpdateInfo? {
        let (data, _) = try await URLSession.shared.data(from: latestReleaseAPIURL)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.prerelease else { return nil }
        let remote = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName
        guard versionIsNewer(remote: remote, current: currentVersion) else { return nil }
        guard let releaseURL = trustedReleaseURL(from: release.htmlUrl) else {
            throw UpdaterError.untrustedReleaseURL(release.htmlUrl)
        }
        return UpdateInfo(current: currentVersion, latest: remote, url: releaseURL.absoluteString)
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

    static func trustedReleaseURL(from rawURL: String) -> URL? {
        guard let url = URL(string: rawURL),
              url.scheme == "https",
              url.host?.caseInsensitiveCompare("github.com") == .orderedSame else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 5,
              !components.contains("."),
              !components.contains(".."),
              components[0].caseInsensitiveCompare("gradigit") == .orderedSame,
              components[1].caseInsensitiveCompare("LiquidBar") == .orderedSame,
              components[2] == "releases",
              components[3] == "tag" else {
            return nil
        }
        return url
    }

    @MainActor
    static func openReleasePage(url: String) {
        guard let u = trustedReleaseURL(from: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
