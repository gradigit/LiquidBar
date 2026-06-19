import Testing
@testable import LiquidBar

@Test func testGetRSSBytesNonzero() {
    let rss = MemoryMonitor.getRSSBytes()
    #expect(rss > 0)
}
