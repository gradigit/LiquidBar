import CoreGraphics
@testable import LiquidBar
import Testing

@Suite("WindowThumbnailScheduler")
struct WindowThumbnailSchedulerTests {
    private func makeRequest(
        windowId: CGWindowID,
        size: CGSize = CGSize(width: 160, height: 92),
        producer: WindowThumbnailService.ThumbnailProducer,
        generation: Int
    ) -> WindowThumbnailService.CaptureRequest {
        let key = WindowThumbnailService.requestKey(windowId: windowId, targetSizePoints: size)
        return WindowThumbnailService.CaptureRequest(
            key: key,
            windowId: windowId,
            targetSizePoints: size,
            screenScale: 2.0,
            producer: producer,
            generation: generation
        )
    }

    @Test func interactiveRequestDispatchesBeforeQueuedPrewarmWork() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let prewarmA = makeRequest(windowId: 1, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let prewarmB = makeRequest(windowId: 2, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let interactive = makeRequest(windowId: 3, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))

        #expect(scheduler.enqueue(prewarmA).dispatch == [prewarmA])
        #expect(scheduler.enqueue(prewarmB).dispatch.isEmpty)
        #expect(scheduler.enqueue(interactive).dispatch.isEmpty)

        let next = scheduler.finish(prewarmA.key)
        #expect(next == [interactive])
    }

    @Test func queuedRequestUpgradesWhenHigherPriorityProducerArrivesForSameKey() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let active = makeRequest(windowId: 1, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))
        let prewarm = makeRequest(windowId: 2, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let switcher = makeRequest(windowId: 2, producer: .switcher, generation: scheduler.currentGeneration(for: .switcher))

        _ = scheduler.enqueue(active)
        _ = scheduler.enqueue(prewarm)
        let result = scheduler.enqueue(switcher)

        #expect(result.droppedQueued == [prewarm])
        #expect(result.trackedRequest == switcher)
        #expect(scheduler.finish(active.key) == [switcher])
    }

    @Test func switcherInvalidationDropsQueuedWorkBeforeDispatch() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let active = makeRequest(windowId: 1, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))
        let switcherA = makeRequest(windowId: 2, producer: .switcher, generation: scheduler.currentGeneration(for: .switcher))
        let switcherB = makeRequest(windowId: 3, producer: .switcher, generation: scheduler.currentGeneration(for: .switcher))

        _ = scheduler.enqueue(active)
        _ = scheduler.enqueue(switcherA)
        _ = scheduler.enqueue(switcherB)

        let invalidation = scheduler.invalidate(producer: .switcher)
        #expect(Set(invalidation.droppedQueued.map(\.windowId)) == Set([switcherA.windowId, switcherB.windowId]))
        #expect(scheduler.finish(active.key).isEmpty)
    }

    @Test func groupPreviewInvalidationDropsQueuedWorkBeforeDispatch() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let active = makeRequest(windowId: 1, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))
        let groupA = makeRequest(windowId: 2, producer: .groupPreview, generation: scheduler.currentGeneration(for: .groupPreview))
        let groupB = makeRequest(windowId: 3, producer: .groupPreview, generation: scheduler.currentGeneration(for: .groupPreview))

        _ = scheduler.enqueue(active)
        _ = scheduler.enqueue(groupA)
        _ = scheduler.enqueue(groupB)

        let invalidation = scheduler.invalidate(producer: .groupPreview)
        #expect(Set(invalidation.droppedQueued.map(\.windowId)) == Set([groupA.windowId, groupB.windowId]))
        #expect(scheduler.finish(active.key).isEmpty)
    }

    @Test func backgroundQueueCapDropsOldestPrewarmWork() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 2
        )

        let active = makeRequest(windowId: 1, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))
        let prewarmA = makeRequest(windowId: 2, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let prewarmB = makeRequest(windowId: 3, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let prewarmC = makeRequest(windowId: 4, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))

        _ = scheduler.enqueue(active)
        #expect(scheduler.enqueue(prewarmA).droppedQueued.isEmpty)
        #expect(scheduler.enqueue(prewarmB).droppedQueued.isEmpty)
        let result = scheduler.enqueue(prewarmC)

        #expect(result.droppedQueued == [prewarmA])
        #expect(scheduler.debugQueuedRequests().map(\.windowId) == [prewarmB.windowId, prewarmC.windowId])
    }

    @Test func staleInFlightRequestAllowsFreshFollowUpForSameKey() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let original = makeRequest(windowId: 5, producer: .switcher, generation: scheduler.currentGeneration(for: .switcher))
        #expect(scheduler.enqueue(original).dispatch == [original])

        _ = scheduler.invalidate(producer: .switcher)
        let refreshed = makeRequest(windowId: 5, producer: .switcher, generation: scheduler.currentGeneration(for: .switcher))
        let result = scheduler.enqueue(refreshed)

        #expect(result.trackedRequest == refreshed)
        #expect(result.dispatch.isEmpty)
        #expect(scheduler.finish(original.key) == [refreshed])
    }

    @Test func interactiveInvalidationDropsQueuedHoverWorkBeforeDispatch() {
        var scheduler = WindowThumbnailService.ThumbnailRequestScheduler(
            maxConcurrentCaptures: 1,
            maxQueuedRequests: 8
        )

        let active = makeRequest(windowId: 1, producer: .prewarm, generation: scheduler.currentGeneration(for: .prewarm))
        let hover = makeRequest(windowId: 9, producer: .interactive, generation: scheduler.currentGeneration(for: .interactive))

        _ = scheduler.enqueue(active)
        _ = scheduler.enqueue(hover)

        let invalidation = scheduler.invalidate(producer: .interactive)
        #expect(invalidation.droppedQueued == [hover])
        #expect(scheduler.finish(active.key).isEmpty)
    }
}
