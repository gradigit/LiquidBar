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
