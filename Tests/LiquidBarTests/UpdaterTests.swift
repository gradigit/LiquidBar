import Testing
@testable import LiquidBar

@Test func testVersionNewer() {
    #expect(Updater.versionIsNewer(remote: "1.1.0", current: "1.0.0"))
    #expect(Updater.versionIsNewer(remote: "2.0.0", current: "1.9.9"))
    #expect(Updater.versionIsNewer(remote: "0.1.1", current: "0.1.0"))
}

@Test func testVersionNotNewer() {
    #expect(!Updater.versionIsNewer(remote: "1.0.0", current: "1.0.0"))
    #expect(!Updater.versionIsNewer(remote: "0.9.0", current: "1.0.0"))
    #expect(!Updater.versionIsNewer(remote: "0.0.9", current: "0.1.0"))
}

@Test func testUpdaterUsesCanonicalReleaseRepository() {
    #expect(Updater.githubRepo == "gradigit/LiquidBar")
    #expect(Updater.currentVersion == "1.0.1")
    #expect(Updater.latestReleaseAPIURL.absoluteString == "https://api.github.com/repos/gradigit/LiquidBar/releases/latest")
    #expect(Updater.repositoryURL.absoluteString == "https://github.com/gradigit/LiquidBar")
}

@Test func testTrustedReleaseURLAcceptsProjectRelease() throws {
    let url = try #require(Updater.trustedReleaseURL(from: "https://github.com/gradigit/LiquidBar/releases/tag/v0.2.0"))
    #expect(url.absoluteString == "https://github.com/gradigit/LiquidBar/releases/tag/v0.2.0")
}

@Test func testTrustedReleaseURLRejectsWrongOriginAndScheme() {
    #expect(Updater.trustedReleaseURL(from: "https://github.com/liquidbar/liquidbar/releases/tag/v0.2.0") == nil)
    #expect(Updater.trustedReleaseURL(from: "http://github.com/gradigit/LiquidBar/releases/tag/v0.2.0") == nil)
    #expect(Updater.trustedReleaseURL(from: "https://example.com/gradigit/LiquidBar/releases/tag/v0.2.0") == nil)
    #expect(Updater.trustedReleaseURL(from: "file:///tmp/fake-release") == nil)
}

@Test func testTrustedReleaseURLRejectsNonReleaseAndTraversalPaths() {
    #expect(Updater.trustedReleaseURL(from: "https://github.com/gradigit/LiquidBar/issues/1") == nil)
    #expect(Updater.trustedReleaseURL(from: "https://github.com/gradigit/LiquidBar/releases/../evil") == nil)
}
