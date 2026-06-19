import Testing
@testable import LiquidBar

@Suite
struct IconCacheTests {
    @Test @MainActor func testBasicCacheOps() {
        let cache = IconCache()

        // Non-existent bundle should return nil
        #expect(cache.getIcon(bundleId: "com.nonexistent.fake.app") == nil)

        // Finder should exist on every macOS system
        let icon = cache.getIcon(bundleId: "com.apple.finder")
        #expect(icon != nil)

        // Second call should hit cache and return same result
        let cached = cache.getIcon(bundleId: "com.apple.finder")
        #expect(cached != nil)

        // Clear should not crash
        cache.clearCache()
    }
}
