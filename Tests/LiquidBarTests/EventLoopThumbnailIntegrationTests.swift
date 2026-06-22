import Testing
import Foundation
import CoreGraphics
@testable import LiquidBar

@Suite("EventLoop thumbnail integration", .serialized)
@MainActor
struct EventLoopThumbnailIntegrationTests {
    private func makeLoop() throws -> (loop: EventLoop, renderer: NativeBarRenderer) {
        let renderer = NativeBarRenderer()
        let panelManager = PanelManager()
        let loop = EventLoop(config: Config(), renderer: renderer, panelManager: panelManager)
        return (loop, renderer)
    }

    @Test func thumbnailCaptureContextMapsToExpectedProducers() {
        #expect(EventLoop.ThumbnailCaptureContext.hoveredPreview.producer == .interactive)
        #expect(EventLoop.ThumbnailCaptureContext.switcher.producer == .switcher)
        #expect(EventLoop.ThumbnailCaptureContext.groupPreview.producer == .groupPreview)
        #expect(EventLoop.ThumbnailCaptureContext.prewarm.producer == .prewarm)
    }

    @Test func switcherThumbnailPolicyPrioritizesSelectedWindowOutsideInitialPage() {
        let indices = EventLoop.switcherThumbnailIndices(count: 40, selectedIndex: 20)

        #expect(indices.first == 20)
        #expect(indices.contains(17))
        #expect(indices.contains(23))
        #expect(indices.contains(0))
        #expect(indices.count <= 12)
        #expect(Set(indices).count == indices.count)
    }

    @Test func switcherThumbnailPolicyBoundsSelection() {
        #expect(EventLoop.switcherThumbnailIndices(count: 5, selectedIndex: 50).first == 4)
        #expect(EventLoop.switcherThumbnailIndices(count: 0, selectedIndex: 0).isEmpty)
    }

    @Test func switcherPrewarmThumbnailPolicyUsesSmallerPrioritySet() {
        let indices = EventLoop.switcherPrewarmThumbnailIndices(count: 40, selectedIndex: 20)

        #expect(indices.first == 20)
        #expect(indices.contains(18))
        #expect(indices.contains(22))
        #expect(indices.contains(0))
        #expect(indices.count <= 8)
        #expect(Set(indices).count == indices.count)
    }

    @Test func hideSwitcherInvalidatesQueuedSwitcherRequests() throws {
        let (loop, renderer) = try makeLoop()
        defer { renderer.shutdown() }

        _ = loop.debugEnqueueThumbnailRequest(windowId: 1, targetSizePoints: CGSize(width: 160, height: 92), producer: .interactive)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 2, targetSizePoints: CGSize(width: 160, height: 92), producer: .interactive)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 3, targetSizePoints: CGSize(width: 160, height: 92), producer: .switcher)

        #expect(loop.debugQueuedThumbnailRequests().map(\.producer) == [.switcher])

        loop.debugHideSwitcher(commitSelection: false)

        #expect(loop.debugQueuedThumbnailRequests().allSatisfy { $0.producer != .switcher })
    }

    @Test func hideGroupPreviewInvalidatesQueuedGroupPreviewRequests() throws {
        let (loop, renderer) = try makeLoop()
        defer { renderer.shutdown() }

        _ = loop.debugEnqueueThumbnailRequest(windowId: 10, targetSizePoints: CGSize(width: 160, height: 92), producer: .interactive)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 11, targetSizePoints: CGSize(width: 160, height: 92), producer: .interactive)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 12, targetSizePoints: CGSize(width: 160, height: 92), producer: .groupPreview)

        #expect(loop.debugQueuedThumbnailRequests().map(\.producer) == [.groupPreview])

        loop.debugHideGroupPreview(displayId: 1, immediate: true)

        #expect(loop.debugQueuedThumbnailRequests().allSatisfy { $0.producer != .groupPreview })
    }

    @Test func hideAllPreviewsInvalidatesQueuedInteractiveAndGroupPreviewRequests() throws {
        let (loop, renderer) = try makeLoop()
        defer { renderer.shutdown() }

        _ = loop.debugEnqueueThumbnailRequest(windowId: 20, targetSizePoints: CGSize(width: 160, height: 92), producer: .switcher)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 21, targetSizePoints: CGSize(width: 160, height: 92), producer: .switcher)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 22, targetSizePoints: CGSize(width: 160, height: 92), producer: .interactive)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 23, targetSizePoints: CGSize(width: 160, height: 92), producer: .groupPreview)

        let queuedProducers = loop.debugQueuedThumbnailRequests().map(\.producer)
        #expect(queuedProducers == [.interactive, .groupPreview] || queuedProducers == [.groupPreview, .interactive])

        loop.debugHideAllPreviews()

        #expect(loop.debugQueuedThumbnailRequests().isEmpty)
    }

    @Test func syncThumbnailLifecyclePrunesDeadWindowIdsFromRuntimeCaches() throws {
        let (loop, renderer) = try makeLoop()
        defer { renderer.shutdown() }

        loop.debugStoreCachedThumbnail(windowId: 1, sizePoints: CGSize(width: 80, height: 80))
        loop.debugStoreCachedThumbnail(windowId: 2, sizePoints: CGSize(width: 80, height: 80))
        loop.debugStoreLastGoodThumbnail(windowId: 1, sizePoints: CGSize(width: 80, height: 80))
        loop.debugStoreLastGoodThumbnail(windowId: 2, sizePoints: CGSize(width: 80, height: 80))

        _ = loop.debugEnqueueThumbnailRequest(windowId: 30, targetSizePoints: CGSize(width: 160, height: 92), producer: .switcher)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 31, targetSizePoints: CGSize(width: 160, height: 92), producer: .switcher)
        _ = loop.debugEnqueueThumbnailRequest(windowId: 32, targetSizePoints: CGSize(width: 160, height: 92), producer: .groupPreview)

        loop.debugSyncThumbnailLifecycleToLiveWindowIds([1, 30, 31])

        #expect(loop.debugCachedThumbnailWindowIds(for: .tiny) == [1])
        #expect(loop.debugLastGoodThumbnailWindowIds() == [1])
        #expect(loop.debugQueuedThumbnailRequests().isEmpty)
    }
}
