import AppKit
@testable import LiquidBar
import Testing

@Suite("WindowThumbnailService policy")
struct WindowThumbnailServicePolicyTests {
    @MainActor
    @Test func requestKeySeparatesTinyAndLargeTiersForSameWindow() {
        let tiny = WindowThumbnailService.requestKey(
            windowId: 42,
            targetSizePoints: CGSize(width: 80, height: 80)
        )
        let large = WindowThumbnailService.requestKey(
            windowId: 42,
            targetSizePoints: CGSize(width: 260, height: 160)
        )

        #expect(tiny.windowId == large.windowId)
        #expect(tiny.tier == .tiny)
        #expect(large.tier == .large)
        #expect(tiny != large)
    }

    @MainActor
    @Test func largeRequestDoesNotReuseTinyOnlyCachedThumbnail() {
        let service = WindowThumbnailService()
        let tinyImage = NSImage(size: CGSize(width: 80, height: 80))

        service.debugStoreCachedThumbnail(
            windowId: 7,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: tinyImage
        )

        let resolved = service.cachedThumbnail(
            windowId: 7,
            targetSizePoints: CGSize(width: 260, height: 160),
            includeLastGood: false
        )

        #expect(resolved == nil)
    }

    @MainActor
    @Test func smallerRequestCanReuseLargerCachedThumbnail() {
        let service = WindowThumbnailService()
        let largeImage = NSImage(size: CGSize(width: 260, height: 160))

        service.debugStoreCachedThumbnail(
            windowId: 9,
            targetSizePoints: CGSize(width: 260, height: 160),
            image: largeImage
        )

        let resolved = service.cachedThumbnail(
            windowId: 9,
            targetSizePoints: CGSize(width: 80, height: 80),
            includeLastGood: false
        )

        #expect(resolved === largeImage)
    }

    @MainActor
    @Test func storingTinyTierAfterLargeTierKeepsBothCacheEntries() {
        let service = WindowThumbnailService()
        let largeImage = NSImage(size: CGSize(width: 260, height: 160))
        let tinyImage = NSImage(size: CGSize(width: 80, height: 80))

        service.debugStoreCachedThumbnail(
            windowId: 11,
            targetSizePoints: CGSize(width: 260, height: 160),
            image: largeImage
        )
        service.debugStoreCachedThumbnail(
            windowId: 11,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: tinyImage
        )

        let keys = service.debugCachedKeys(windowId: 11)
        let largeResolved = service.cachedThumbnail(
            windowId: 11,
            targetSizePoints: CGSize(width: 260, height: 160),
            includeLastGood: false
        )
        let tinyResolved = service.cachedThumbnail(
            windowId: 11,
            targetSizePoints: CGSize(width: 80, height: 80),
            includeLastGood: false
        )

        #expect(keys.count == 2)
        #expect(keys.contains(WindowThumbnailService.requestKey(windowId: 11, targetSizePoints: CGSize(width: 260, height: 160))))
        #expect(keys.contains(WindowThumbnailService.requestKey(windowId: 11, targetSizePoints: CGSize(width: 80, height: 80))))
        #expect(largeResolved === largeImage)
        #expect(tinyResolved === tinyImage)
    }

    @MainActor
    @Test func inFlightIdentityIsTierAwareForSameWindow() {
        let service = WindowThumbnailService()

        service.debugStartInFlight(windowId: 13, targetSizePoints: CGSize(width: 80, height: 80))
        service.debugStartInFlight(windowId: 13, targetSizePoints: CGSize(width: 260, height: 160))

        let keys = service.debugInFlightKeys(windowId: 13)
        #expect(keys.count == 2)
        #expect(keys.contains(WindowThumbnailService.requestKey(windowId: 13, targetSizePoints: CGSize(width: 80, height: 80))))
        #expect(keys.contains(WindowThumbnailService.requestKey(windowId: 13, targetSizePoints: CGSize(width: 260, height: 160))))
    }
}
