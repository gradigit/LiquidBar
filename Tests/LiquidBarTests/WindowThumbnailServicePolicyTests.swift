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
    @Test func lastGoodThumbnailRequiresSufficientTierForLargeRequests() {
        let service = WindowThumbnailService()
        let tinyImage = NSImage(size: CGSize(width: 80, height: 80))

        service.debugStoreLastGoodThumbnail(
            windowId: 12,
            image: tinyImage,
            sizePoints: CGSize(width: 80, height: 80)
        )

        let resolved = service.cachedThumbnail(
            windowId: 12,
            targetSizePoints: CGSize(width: 480, height: 260),
            includeLastGood: true
        )

        #expect(resolved == nil)
    }

    @MainActor
    @Test func largeLastGoodThumbnailCanSatisfySmallerRequests() {
        let service = WindowThumbnailService()
        let largeImage = NSImage(size: CGSize(width: 480, height: 260))

        service.debugStoreLastGoodThumbnail(
            windowId: 14,
            image: largeImage,
            sizePoints: CGSize(width: 480, height: 260)
        )

        let resolved = service.cachedThumbnail(
            windowId: 14,
            targetSizePoints: CGSize(width: 140, height: 92),
            includeLastGood: true
        )

        #expect(resolved === largeImage)
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

    @Test func switcherCapturesUseNominalResolution() {
        let largeKey = WindowThumbnailService.requestKey(
            windowId: 21,
            targetSizePoints: CGSize(width: 390, height: 220)
        )
        let tinyKey = WindowThumbnailService.requestKey(
            windowId: 22,
            targetSizePoints: CGSize(width: 90, height: 90)
        )
        let largeSwitcher = WindowThumbnailService.CaptureRequest(
            key: largeKey,
            windowId: 21,
            targetSizePoints: CGSize(width: 390, height: 220),
            screenScale: 2,
            producer: .switcher,
            generation: 0
        )
        let tinySwitcher = WindowThumbnailService.CaptureRequest(
            key: tinyKey,
            windowId: 22,
            targetSizePoints: CGSize(width: 90, height: 90),
            screenScale: 2,
            producer: .switcher,
            generation: 0
        )
        let largePrewarm = WindowThumbnailService.CaptureRequest(
            key: largeKey,
            windowId: 21,
            targetSizePoints: CGSize(width: 390, height: 220),
            screenScale: 2,
            producer: .prewarm,
            generation: 0
        )

        #expect(WindowThumbnailService.captureResolution(for: largeSwitcher) == .nominal)
        #expect(WindowThumbnailService.captureResolution(for: tinySwitcher) == .nominal)
        #expect(WindowThumbnailService.captureResolution(for: largePrewarm) == .nominal)
    }

    @Test func switcherAndPrewarmThumbnailsStayFreshLongerThanInteractivePreviews() {
        let interactive = WindowThumbnailService.freshCacheTTL(for: .interactive)
        let switcher = WindowThumbnailService.freshCacheTTL(for: .switcher)
        let prewarm = WindowThumbnailService.freshCacheTTL(for: .prewarm)

        #expect(interactive == 0.75)
        #expect(switcher == 8.0)
        #expect(prewarm == switcher)
    }
}
