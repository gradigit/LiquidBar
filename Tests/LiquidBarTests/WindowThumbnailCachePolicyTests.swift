import AppKit
@testable import LiquidBar
import Testing

@Suite("WindowThumbnailService cache policy")
struct WindowThumbnailCachePolicyTests {
    private func makePolicy(
        maxTinyEntries: Int = 8,
        maxTinyBytes: Int = 8 * 1_024 * 1_024,
        maxStandardEntries: Int = 8,
        maxStandardBytes: Int = 8 * 1_024 * 1_024,
        maxLargeEntries: Int = 8,
        maxLargeBytes: Int = 8 * 1_024 * 1_024,
        maxLastGoodEntries: Int = 8,
        maxLastGoodBytes: Int = 8 * 1_024 * 1_024,
        staleCacheAge: CFAbsoluteTime = 20,
        staleLastGoodAge: CFAbsoluteTime = 60
    ) -> WindowThumbnailService.RetentionPolicy {
        .init(
            maxEntriesPerTier: [
                .tiny: maxTinyEntries,
                .standard: maxStandardEntries,
                .large: maxLargeEntries,
            ],
            maxBytesPerTier: [
                .tiny: maxTinyBytes,
                .standard: maxStandardBytes,
                .large: maxLargeBytes,
            ],
            maxLastGoodEntries: maxLastGoodEntries,
            maxLastGoodBytes: maxLastGoodBytes,
            staleCacheAge: staleCacheAge,
            staleLastGoodAge: staleLastGoodAge
        )
    }

    @MainActor
    @Test func staleEntriesPruneCorrectly() {
        let now: CFAbsoluteTime = 100
        let service = WindowThumbnailService(retentionPolicy: makePolicy(staleCacheAge: 5, staleLastGoodAge: 8))

        service.debugStoreCachedThumbnail(
            windowId: 1,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: NSImage(size: CGSize(width: 80, height: 80)),
            capturedAt: now - 9
        )
        service.debugStoreCachedThumbnail(
            windowId: 2,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: NSImage(size: CGSize(width: 80, height: 80)),
            capturedAt: now - 1
        )
        service.debugStoreLastGoodThumbnail(
            windowId: 3,
            image: NSImage(size: CGSize(width: 120, height: 80)),
            sizePoints: CGSize(width: 120, height: 80),
            capturedAt: now - 11
        )
        service.debugStoreLastGoodThumbnail(
            windowId: 4,
            image: NSImage(size: CGSize(width: 120, height: 80)),
            sizePoints: CGSize(width: 120, height: 80),
            capturedAt: now - 1
        )

        service.debugSweepRetainedThumbnails(now: now)

        #expect(service.debugCachedKeys(windowId: 1).isEmpty)
        #expect(!service.debugCachedKeys(windowId: 2).isEmpty)
        #expect(service.debugLastGoodWindowIds() == [4])
    }

    @MainActor
    @Test func closedWindowIdsAreEvictedFromCacheLastGoodAndQueue() {
        let scheduler = WindowThumbnailService.ThumbnailRequestScheduler(maxConcurrentCaptures: 1, maxQueuedRequests: 8)
        let service = WindowThumbnailService(retentionPolicy: makePolicy(), scheduler: scheduler)

        service.debugStoreCachedThumbnail(
            windowId: 10,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: NSImage(size: CGSize(width: 80, height: 80))
        )
        service.debugStoreLastGoodThumbnail(
            windowId: 11,
            image: NSImage(size: CGSize(width: 80, height: 80)),
            sizePoints: CGSize(width: 80, height: 80)
        )

        _ = service.debugEnqueueRequest(
            windowId: 21,
            targetSizePoints: CGSize(width: 80, height: 80),
            producer: .interactive
        )
        _ = service.debugEnqueueRequest(
            windowId: 22,
            targetSizePoints: CGSize(width: 80, height: 80),
            producer: .prewarm
        )

        service.debugPruneToLiveWindowIds([21])

        #expect(service.debugCachedKeys(windowId: 10).isEmpty)
        #expect(service.debugLastGoodWindowIds().isEmpty)
        #expect(service.debugQueuedRequests().isEmpty)
        #expect(service.debugInFlightKeys(windowId: 21).count == 1)
    }

    @MainActor
    @Test func lastGoodFallbackRemainsBounded() {
        let service = WindowThumbnailService(
            retentionPolicy: makePolicy(maxLastGoodEntries: 2, maxLastGoodBytes: Int.max)
        )

        service.debugStoreLastGoodThumbnail(
            windowId: 1,
            image: NSImage(size: CGSize(width: 80, height: 80)),
            sizePoints: CGSize(width: 80, height: 80),
            capturedAt: 1
        )
        service.debugStoreLastGoodThumbnail(
            windowId: 2,
            image: NSImage(size: CGSize(width: 80, height: 80)),
            sizePoints: CGSize(width: 80, height: 80),
            capturedAt: 2
        )
        service.debugStoreLastGoodThumbnail(
            windowId: 3,
            image: NSImage(size: CGSize(width: 80, height: 80)),
            sizePoints: CGSize(width: 80, height: 80),
            capturedAt: 3
        )

        #expect(service.debugLastGoodWindowIds() == [2, 3])
    }

    @MainActor
    @Test func configuredBudgetsAreEnforced() {
        let byteBudget = WindowThumbnailService.approximateByteCost(
            sizePoints: CGSize(width: 80, height: 80),
            screenScale: 2.0
        ) + 1

        let service = WindowThumbnailService(
            retentionPolicy: makePolicy(
                maxTinyEntries: 8,
                maxTinyBytes: byteBudget,
                maxStandardEntries: 8,
                maxStandardBytes: Int.max,
                maxLargeEntries: 8,
                maxLargeBytes: Int.max
            )
        )

        service.debugStoreCachedThumbnail(
            windowId: 1,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: NSImage(size: CGSize(width: 80, height: 80)),
            capturedAt: 1
        )
        service.debugStoreCachedThumbnail(
            windowId: 2,
            targetSizePoints: CGSize(width: 80, height: 80),
            image: NSImage(size: CGSize(width: 80, height: 80)),
            capturedAt: 2
        )

        #expect(service.debugCachedWindowIds(for: .tiny) == [2])
    }

    @MainActor
    @Test func hoverTargetChangeInvalidatesOldQueuedWorkBeforeDispatch() {
        let service = WindowThumbnailService(
            retentionPolicy: makePolicy(),
            scheduler: .init(maxConcurrentCaptures: 1, maxQueuedRequests: 8)
        )

        _ = service.debugEnqueueRequest(
            windowId: 1,
            targetSizePoints: CGSize(width: 80, height: 80),
            producer: .prewarm
        )
        _ = service.debugEnqueueRequest(
            windowId: 2,
            targetSizePoints: CGSize(width: 160, height: 92),
            producer: .interactive
        )

        service.debugInvalidateRequests(for: .interactive)

        #expect(service.debugQueuedRequests().isEmpty)
    }

    @MainActor
    @Test func switcherHideInvalidatesQueuedWorkBeforeDispatch() {
        let service = WindowThumbnailService(
            retentionPolicy: makePolicy(),
            scheduler: .init(maxConcurrentCaptures: 1, maxQueuedRequests: 8)
        )

        _ = service.debugEnqueueRequest(
            windowId: 1,
            targetSizePoints: CGSize(width: 80, height: 80),
            producer: .interactive
        )
        _ = service.debugEnqueueRequest(
            windowId: 3,
            targetSizePoints: CGSize(width: 160, height: 92),
            producer: .switcher
        )

        service.debugInvalidateRequests(for: .switcher)

        #expect(service.debugQueuedRequests().isEmpty)
    }

    @MainActor
    @Test func groupPreviewHideInvalidatesQueuedWorkBeforeDispatch() {
        let service = WindowThumbnailService(
            retentionPolicy: makePolicy(),
            scheduler: .init(maxConcurrentCaptures: 1, maxQueuedRequests: 8)
        )

        _ = service.debugEnqueueRequest(
            windowId: 1,
            targetSizePoints: CGSize(width: 80, height: 80),
            producer: .interactive
        )
        _ = service.debugEnqueueRequest(
            windowId: 4,
            targetSizePoints: CGSize(width: 160, height: 92),
            producer: .groupPreview
        )

        service.debugInvalidateRequests(for: .groupPreview)

        #expect(service.debugQueuedRequests().isEmpty)
    }
}
