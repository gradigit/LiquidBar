import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class WindowThumbnailService {
    enum ThumbnailProducer: String, CaseIterable, Sendable {
        case interactive
        case switcher
        case groupPreview
        case overflowShelf
        case prewarm
    }

    enum ThumbnailTier: Int, CaseIterable, Comparable, Sendable {
        case tiny
        case standard
        case large

        static func < (lhs: ThumbnailTier, rhs: ThumbnailTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        static func forTargetSize(_ targetSizePoints: CGSize) -> ThumbnailTier {
            let maxDimension = max(targetSizePoints.width, targetSizePoints.height)
            switch maxDimension {
            case ..<120:
                return .tiny
            case ..<220:
                return .standard
            default:
                return .large
            }
        }
    }

    struct ThumbnailRequestKey: Hashable, Sendable {
        let windowId: CGWindowID
        let tier: ThumbnailTier
    }

    private struct CacheEntry {
        let image: NSImage
        let capturedAt: CFAbsoluteTime
        let sizePoints: CGSize
        let byteCost: Int
    }

    private struct LastGoodEntry {
        let image: NSImage
        let capturedAt: CFAbsoluteTime
        let sizePoints: CGSize
        let byteCost: Int
    }

    struct RetentionPolicy: Equatable, Sendable {
        let maxEntriesPerTier: [ThumbnailTier: Int]
        let maxBytesPerTier: [ThumbnailTier: Int]
        let maxLastGoodEntries: Int
        let maxLastGoodBytes: Int
        let staleCacheAge: CFAbsoluteTime
        let staleLastGoodAge: CFAbsoluteTime

        static let balanced = RetentionPolicy(
            maxEntriesPerTier: [
                .tiny: 48,
                .standard: 40,
                .large: 24,
            ],
            maxBytesPerTier: [
                .tiny: 18 * 1_024 * 1_024,
                .standard: 28 * 1_024 * 1_024,
                .large: 48 * 1_024 * 1_024,
            ],
            maxLastGoodEntries: 32,
            maxLastGoodBytes: 64 * 1_024 * 1_024,
            staleCacheAge: 20.0,
            staleLastGoodAge: 90.0
        )

        static let `default` = balanced

        static func forMemoryPreset(_ preset: PreviewMemoryPreset) -> RetentionPolicy {
            switch preset {
            case .low:
                return RetentionPolicy(
                    maxEntriesPerTier: [
                        .tiny: 24,
                        .standard: 16,
                        .large: 8,
                    ],
                    maxBytesPerTier: [
                        .tiny: 8 * 1_024 * 1_024,
                        .standard: 12 * 1_024 * 1_024,
                        .large: 18 * 1_024 * 1_024,
                    ],
                    maxLastGoodEntries: 12,
                    maxLastGoodBytes: 18 * 1_024 * 1_024,
                    staleCacheAge: 12.0,
                    staleLastGoodAge: 30.0
                )
            case .balanced:
                return .balanced
            case .highQuality:
                return RetentionPolicy(
                    maxEntriesPerTier: [
                        .tiny: 64,
                        .standard: 56,
                        .large: 36,
                    ],
                    maxBytesPerTier: [
                        .tiny: 24 * 1_024 * 1_024,
                        .standard: 40 * 1_024 * 1_024,
                        .large: 72 * 1_024 * 1_024,
                    ],
                    maxLastGoodEntries: 48,
                    maxLastGoodBytes: 96 * 1_024 * 1_024,
                    staleCacheAge: 30.0,
                    staleLastGoodAge: 120.0
                )
            }
        }
    }

    struct MemorySummary: Equatable, Sendable {
        let cacheEntries: Int
        let cacheBytes: Int
        let lastGoodEntries: Int
        let lastGoodBytes: Int
        let queuedRequests: Int
        let inFlightRequests: Int
    }

    struct CaptureRequestIdentity: Hashable, Sendable {
        let key: ThumbnailRequestKey
        let producer: ThumbnailProducer
        let generation: Int
    }

    struct CaptureRequest: Equatable, Sendable {
        let key: ThumbnailRequestKey
        let windowId: CGWindowID
        let targetSizePoints: CGSize
        let screenScale: CGFloat
        let producer: ThumbnailProducer
        let generation: Int

        var identity: CaptureRequestIdentity {
            CaptureRequestIdentity(key: key, producer: producer, generation: generation)
        }
    }

    struct ThumbnailRequestScheduler {
        struct EnqueueResult {
            let trackedRequest: CaptureRequest?
            let dispatch: [CaptureRequest]
            let droppedQueued: [CaptureRequest]
        }

        struct InvalidationResult {
            let droppedQueued: [CaptureRequest]
        }

        private struct RankedRequest {
            let request: CaptureRequest
            let order: UInt64
        }

        private(set) var maxConcurrentCaptures: Int
        private(set) var maxQueuedRequests: Int
        private var nextOrder: UInt64 = 0
        private var activeGenerationByProducer: [ThumbnailProducer: Int]
        private var inFlightByKey: [ThumbnailRequestKey: RankedRequest] = [:]
        private var queuedByKey: [ThumbnailRequestKey: RankedRequest] = [:]

        init(maxConcurrentCaptures: Int = 2, maxQueuedRequests: Int = 24) {
            self.maxConcurrentCaptures = max(1, maxConcurrentCaptures)
            self.maxQueuedRequests = max(0, maxQueuedRequests)
            self.activeGenerationByProducer = Dictionary(
                uniqueKeysWithValues: ThumbnailProducer.allCases.map { ($0, 0) }
            )
        }

        func currentGeneration(for producer: ThumbnailProducer) -> Int {
            activeGenerationByProducer[producer, default: 0]
        }

        func isCurrent(_ request: CaptureRequest) -> Bool {
            request.generation == currentGeneration(for: request.producer)
        }

        var queuedRequestCount: Int {
            queuedByKey.count
        }

        var inFlightRequestCount: Int {
            inFlightByKey.count
        }

        mutating func invalidate(producer: ThumbnailProducer) -> InvalidationResult {
            activeGenerationByProducer[producer, default: 0] += 1

            let droppedQueued = queuedByKey.values
                .map(\.request)
                .filter { $0.producer == producer }

            for request in droppedQueued {
                queuedByKey.removeValue(forKey: request.key)
            }

            return InvalidationResult(droppedQueued: droppedQueued)
        }

        mutating func pruneToLiveWindowIds(_ liveWindowIds: Set<CGWindowID>) -> InvalidationResult {
            let droppedQueued = queuedByKey.values
                .map(\.request)
                .filter { !liveWindowIds.contains($0.windowId) }

            for request in droppedQueued {
                queuedByKey.removeValue(forKey: request.key)
            }

            return InvalidationResult(droppedQueued: droppedQueued)
        }

        mutating func enqueue(_ request: CaptureRequest) -> EnqueueResult {
            guard isCurrent(request) else {
                return EnqueueResult(trackedRequest: nil, dispatch: [], droppedQueued: [])
            }

            if let existingInFlight = inFlightByKey[request.key]?.request {
                if existingInFlight.identity == request.identity || isCurrent(existingInFlight) {
                    return EnqueueResult(trackedRequest: existingInFlight, dispatch: [], droppedQueued: [])
                }
                return enqueueQueued(request)
            }

            if let existingQueued = queuedByKey[request.key]?.request {
                if existingQueued.identity == request.identity {
                    return EnqueueResult(trackedRequest: existingQueued, dispatch: [], droppedQueued: [])
                }
                if shouldReplace(existingQueued, with: request) {
                    queuedByKey[request.key] = ranked(request)
                    return EnqueueResult(
                        trackedRequest: request,
                        dispatch: [],
                        droppedQueued: [existingQueued]
                    )
                }
                return EnqueueResult(trackedRequest: existingQueued, dispatch: [], droppedQueued: [])
            }

            if inFlightByKey.count < maxConcurrentCaptures {
                inFlightByKey[request.key] = ranked(request)
                return EnqueueResult(trackedRequest: request, dispatch: [request], droppedQueued: [])
            }

            return enqueueQueued(request)
        }

        mutating func finish(_ key: ThumbnailRequestKey) -> [CaptureRequest] {
            _ = inFlightByKey.removeValue(forKey: key)
            return promoteQueuedRequests()
        }

        #if DEBUG
        mutating func debugInsertInFlight(_ request: CaptureRequest) {
            inFlightByKey[request.key] = ranked(request)
        }

        func debugQueuedRequests() -> [CaptureRequest] {
            queuedByKey.values
                .sorted { lhs, rhs in
                    compare(lhs, rhs)
                }
                .map(\.request)
        }

        func debugInFlightRequests() -> [CaptureRequest] {
            inFlightByKey.values
                .sorted { lhs, rhs in
                    compare(lhs, rhs)
                }
                .map(\.request)
        }
        #endif

        private mutating func enqueueQueued(_ request: CaptureRequest) -> EnqueueResult {
            queuedByKey[request.key] = ranked(request)
            let droppedQueued = compactQueuedRequestsIfNeeded()
            let trackedRequest = queuedByKey[request.key]?.request
            return EnqueueResult(
                trackedRequest: trackedRequest,
                dispatch: [],
                droppedQueued: droppedQueued
            )
        }

        private mutating func promoteQueuedRequests() -> [CaptureRequest] {
            var dispatch: [CaptureRequest] = []

            while inFlightByKey.count < maxConcurrentCaptures {
                guard let nextKey = nextQueuedKeyForDispatch(),
                      let rankedRequest = queuedByKey.removeValue(forKey: nextKey) else {
                    break
                }

                if !isCurrent(rankedRequest.request) {
                    continue
                }

                inFlightByKey[nextKey] = rankedRequest
                dispatch.append(rankedRequest.request)
            }

            return dispatch
        }

        private mutating func compactQueuedRequestsIfNeeded() -> [CaptureRequest] {
            guard maxQueuedRequests >= 0 else { return [] }

            var dropped: [CaptureRequest] = []
            while queuedByKey.count > maxQueuedRequests {
                guard let key = worstDroppableQueuedKey(),
                      let removed = queuedByKey.removeValue(forKey: key) else {
                    break
                }
                dropped.append(removed.request)
            }
            return dropped
        }

        private func nextQueuedKeyForDispatch() -> ThumbnailRequestKey? {
            queuedByKey.values
                .sorted { lhs, rhs in
                    compare(lhs, rhs)
                }
                .first?
                .request
                .key
        }

        private func worstDroppableQueuedKey() -> ThumbnailRequestKey? {
            queuedByKey.values
                .sorted { lhs, rhs in
                    let lhsPriority = priority(for: lhs.request.producer)
                    let rhsPriority = priority(for: rhs.request.producer)
                    if lhsPriority != rhsPriority {
                        return lhsPriority > rhsPriority
                    }
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.request.windowId < rhs.request.windowId
                }
                .first?
                .request
                .key
        }

        private func compare(_ lhs: RankedRequest, _ rhs: RankedRequest) -> Bool {
            let lhsPriority = priority(for: lhs.request.producer)
            let rhsPriority = priority(for: rhs.request.producer)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.request.windowId < rhs.request.windowId
        }

        private func shouldReplace(_ existing: CaptureRequest, with incoming: CaptureRequest) -> Bool {
            if incoming.generation != existing.generation {
                return incoming.generation > existing.generation
            }
            let existingPriority = priority(for: existing.producer)
            let incomingPriority = priority(for: incoming.producer)
            return incomingPriority < existingPriority
        }

        private func priority(for producer: ThumbnailProducer) -> Int {
            switch producer {
            case .interactive:
                return 0
            case .switcher, .groupPreview, .overflowShelf:
                return 1
            case .prewarm:
                return 2
            }
        }

        private mutating func ranked(_ request: CaptureRequest) -> RankedRequest {
            defer { nextOrder += 1 }
            return RankedRequest(request: request, order: nextOrder)
        }
    }

    // Capture results are noisy if the user hasn't granted Screen Recording. Avoid log spam.
    private var didLogScreenRecordingMissing: Bool = false
    private var didRequestScreenRecordingAccess: Bool = false

    // Cache window IDs -> SCWindow. Refresh periodically.
    private var cachedContentAt: CFAbsoluteTime = 0
    private var cachedWindowsById: [CGWindowID: SCWindow] = [:]
    private var isRefreshingContent: Bool = false
    private var pendingContentCallbacks: [(windowId: CGWindowID, callback: (SCWindow?) -> Void)] = []

    private var imageCacheByKey: [ThumbnailRequestKey: CacheEntry] = [:]
    private var callbacksByIdentity: [CaptureRequestIdentity: [(NSImage?) -> Void]] = [:]
    private var scheduler = ThumbnailRequestScheduler()
    /// Last known-good image for a window, kept longer than the short TTL cache.
    /// Used to show previews for hidden/minimized windows when live capture fails.
    private var lastGoodImageByKey: [ThumbnailRequestKey: LastGoodEntry] = [:]
    private var requestQueuedAtByIdentity: [CaptureRequestIdentity: CFTimeInterval] = [:]
    private var retentionPolicy: RetentionPolicy
    private var lastMaintenanceAt: CFAbsoluteTime = 0

    private let staleServeTTL: CFAbsoluteTime = 8.0
    private let contentCacheTTL: CFAbsoluteTime = 12.0

    init(
        retentionPolicy: RetentionPolicy = .default,
        scheduler: ThumbnailRequestScheduler = ThumbnailRequestScheduler()
    ) {
        self.retentionPolicy = retentionPolicy
        self.scheduler = scheduler
    }

    @inline(__always)
    private func isEntry(
        _ entry: CacheEntry,
        sufficientFor targetSizePoints: CGSize
    ) -> Bool {
        entry.sizePoints.width >= targetSizePoints.width * 0.85
            && entry.sizePoints.height >= targetSizePoints.height * 0.85
    }

    /// Capture a static thumbnail of a given window. Returns `nil` if capture isn't permitted or the window can't be found.
    ///
    /// - Important: Requires Screen Recording permission for most third-party apps. Keep this behind a user setting.
    func captureWindowThumbnail(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        screenScale: CGFloat,
        producer: ThumbnailProducer = .interactive,
        preferCachedImage: Bool = false,
        completion: @escaping (NSImage?) -> Void
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        performMaintenance(now: now)
        let requestKey = Self.requestKey(windowId: windowId, targetSizePoints: targetSizePoints)
        let request = CaptureRequest(
            key: requestKey,
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            screenScale: screenScale,
            producer: producer,
            generation: scheduler.currentGeneration(for: producer)
        )

        if preferCachedImage {
            if let entry = bestCachedEntry(windowId: windowId, targetSizePoints: targetSizePoints) {
                recordThumbnailCacheEvent(request: request, outcome: "cache_preferred", entry: entry)
                completion(entry.image)
                return
            }
            if let entry = bestLastGoodEntry(windowId: windowId, targetSizePoints: targetSizePoints) {
                recordThumbnailLastGoodEvent(request: request, outcome: "last_good_preferred", entry: entry)
                completion(entry.image)
                return
            }
        }

        if let entry = bestCachedEntry(windowId: windowId, targetSizePoints: targetSizePoints) {
            let age = now - entry.capturedAt
            if age < Self.freshCacheTTL(for: producer) {
                recordThumbnailCacheEvent(request: request, outcome: "cache_fresh", entry: entry)
                completion(entry.image)
                return
            }
            let outcome = age < staleServeTTL ? "cache_stale_served" : "cache_retained_fallback"
            recordThumbnailCacheEvent(request: request, outcome: outcome, entry: entry)
            completion(entry.image)
            scheduleCapture(request, completion: completion)
            return
        }

        if let entry = bestLastGoodEntry(windowId: windowId, targetSizePoints: targetSizePoints) {
            recordThumbnailLastGoodEvent(request: request, outcome: "last_good_stale_served", entry: entry)
            completion(entry.image)
            scheduleCapture(request, completion: completion)
            return
        }

        scheduleCapture(request, completion: completion)
    }

    /// Returns best currently cached thumbnail without triggering capture.
    /// Prefers short-term cache, then (optionally) last-known-good image.
    func cachedThumbnail(
        windowId: CGWindowID,
        maxAge: CFAbsoluteTime? = nil,
        includeLastGood: Bool = true
    ) -> NSImage? {
        let now = CFAbsoluteTimeGetCurrent()
        performMaintenance(now: now)
        if let entry = bestAnyCachedEntry(windowId: windowId) {
            if let maxAge {
                if (now - entry.capturedAt) <= maxAge {
                    return entry.image
                }
            } else {
                return entry.image
            }
        }
        if includeLastGood {
            return bestAnyLastGoodEntry(windowId: windowId)?.image
        }
        return nil
    }

    /// Returns the best cached thumbnail that is sufficient for the requested target size.
    /// Larger cached tiers may satisfy smaller requests, but undersized tiers do not satisfy larger requests.
    func cachedThumbnail(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        maxAge: CFAbsoluteTime? = nil,
        includeLastGood: Bool = true
    ) -> NSImage? {
        let now = CFAbsoluteTimeGetCurrent()
        performMaintenance(now: now)
        if let entry = bestCachedEntry(windowId: windowId, targetSizePoints: targetSizePoints) {
            if let maxAge {
                if (now - entry.capturedAt) <= maxAge {
                    return entry.image
                }
            } else {
                return entry.image
            }
        }
        if includeLastGood {
            return bestLastGoodEntry(windowId: windowId, targetSizePoints: targetSizePoints)?.image
        }
        return nil
    }

    /// Starts capture warmup for a window without requiring a consumer callback yet.
    /// If another request arrives while capture is in-flight, it is coalesced.
    func prefetchWindowThumbnail(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        screenScale: CGFloat,
        producer: ThumbnailProducer = .prewarm,
        preferCachedImage: Bool = false
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        performMaintenance(now: now)
        let requestKey = Self.requestKey(windowId: windowId, targetSizePoints: targetSizePoints)
        let request = CaptureRequest(
            key: requestKey,
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            screenScale: screenScale,
            producer: producer,
            generation: scheduler.currentGeneration(for: producer)
        )

        if preferCachedImage,
           bestCachedEntry(windowId: windowId, targetSizePoints: targetSizePoints) != nil ||
           bestLastGoodEntry(windowId: windowId, targetSizePoints: targetSizePoints) != nil {
            return
        }

        if let entry = bestCachedEntry(windowId: windowId, targetSizePoints: targetSizePoints),
           (now - entry.capturedAt) < Self.freshCacheTTL(for: producer) {
            return
        }

        scheduleCapture(request)
    }

    func invalidateRequests(for producer: ThumbnailProducer) {
        let result = scheduler.invalidate(producer: producer)
        dropCallbacks(for: result.droppedQueued)
    }

    func pruneToLiveWindowIds(_ liveWindowIds: Set<CGWindowID>) {
        imageCacheByKey = imageCacheByKey.filter { liveWindowIds.contains($0.key.windowId) }
        lastGoodImageByKey = lastGoodImageByKey.filter { liveWindowIds.contains($0.key.windowId) }
        cachedWindowsById = cachedWindowsById.filter { liveWindowIds.contains($0.key) }
        let result = scheduler.pruneToLiveWindowIds(liveWindowIds)
        dropCallbacks(for: result.droppedQueued)
        callbacksByIdentity = callbacksByIdentity.filter { liveWindowIds.contains($0.key.key.windowId) }
        requestQueuedAtByIdentity = requestQueuedAtByIdentity.filter { liveWindowIds.contains($0.key.key.windowId) }
    }

    func sweepRetainedThumbnails(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        sweepStaleEntries(now: now)
        enforceRetentionBudgets()
    }

    func applyMemoryPreset(_ preset: PreviewMemoryPreset) {
        let next = RetentionPolicy.forMemoryPreset(preset)
        guard retentionPolicy != next else { return }
        retentionPolicy = next
        sweepRetainedThumbnails()
    }

    func trimForMemoryPressure() -> MemorySummary {
        let result = scheduler.invalidate(producer: .prewarm)
        dropCallbacks(for: result.droppedQueued)
        imageCacheByKey = imageCacheByKey.filter { $0.key.tier != .large }
        lastGoodImageByKey.removeAll(keepingCapacity: false)
        enforceRetentionBudgets()
        return memorySummary()
    }

    func memorySummary() -> MemorySummary {
        MemorySummary(
            cacheEntries: imageCacheByKey.count,
            cacheBytes: imageCacheByKey.values.reduce(0) { $0 + $1.byteCost },
            lastGoodEntries: lastGoodImageByKey.count,
            lastGoodBytes: lastGoodImageByKey.values.reduce(0) { $0 + $1.byteCost },
            queuedRequests: scheduler.queuedRequestCount,
            inFlightRequests: scheduler.inFlightRequestCount
        )
    }

    private func scheduleCapture(
        _ request: CaptureRequest,
        completion: ((NSImage?) -> Void)? = nil
    ) {
        let result = scheduler.enqueue(request)
        let now = CACurrentMediaTime()
        if let completion, let trackedRequest = result.trackedRequest {
            callbacksByIdentity[trackedRequest.identity, default: []].append(completion)
            requestQueuedAtByIdentity[trackedRequest.identity, default: now] = now
        } else if let trackedRequest = result.trackedRequest {
            requestQueuedAtByIdentity[trackedRequest.identity, default: now] = now
        }
        dropCallbacks(for: result.droppedQueued)
        dispatchCaptures(result.dispatch)
    }

    private func dispatchCaptures(_ requests: [CaptureRequest]) {
        for request in requests {
            performCapture(request)
        }
    }

    private func dropCallbacks(for requests: [CaptureRequest]) {
        for request in requests {
            callbacksByIdentity.removeValue(forKey: request.identity)
            requestQueuedAtByIdentity.removeValue(forKey: request.identity)
        }
    }

    private func performCapture(_ request: CaptureRequest) {
        let captureStart = CACurrentMediaTime()
        let queuedAt = requestQueuedAtByIdentity[request.identity] ?? captureStart
        // Note: macOS typically does not list an app in Screen Recording privacy settings
        // until it has attempted to request access. We only request when the user has
        // explicitly enabled previews (this codepath).
        let screenRecordingMissingAtStart = !CGPreflightScreenCaptureAccess()
        if screenRecordingMissingAtStart {
            if !didLogScreenRecordingMissing {
                Log.event.warning("Screen Recording permission missing; window previews will be blank until enabled in System Settings -> Privacy & Security -> Screen Recording.")
                didLogScreenRecordingMissing = true
            }

            let env = ProcessInfo.processInfo.environment
            guard Self.shouldAttemptScreenCapturePermissionFlow(environment: env) else {
                recordThumbnailCaptureEvent(
                    request: request,
                    outcome: "screen_recording_missing",
                    queuedAt: queuedAt,
                    captureStart: captureStart,
                    image: nil,
                    success: false
                )
                completeCapture(request: request, image: nil)
                return
            }

            // Trigger the system prompt once per launch and continue into ScreenCaptureKit.
            // SCShareableContent can also cause macOS to list the app for approval.
            if !didRequestScreenRecordingAccess {
                didRequestScreenRecordingAccess = true
                Task { @MainActor in
                    _ = CGRequestScreenCaptureAccess()
                }
            }
        }

        resolveSCWindow(windowId: request.windowId) { [weak self] scWindow in
            guard let self else { return }
            guard let scWindow else {
                self.recordThumbnailCaptureEvent(
                    request: request,
                    outcome: screenRecordingMissingAtStart ? "screen_recording_missing" : "window_missing",
                    queuedAt: queuedAt,
                    captureStart: captureStart,
                    image: nil,
                    success: false
                )
                self.completeCapture(request: request, image: nil)
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let cfg = SCStreamConfiguration()

            // Request a small scaled image; SCK will preserve aspect ratio if asked.
            cfg.width = max(1, Int((request.targetSizePoints.width * request.screenScale).rounded(.up)))
            cfg.height = max(1, Int((request.targetSizePoints.height * request.screenScale).rounded(.up)))
            cfg.scalesToFit = true
            cfg.preservesAspectRatio = true
            cfg.showsCursor = false

            // Window thumbnails should look "clean" (no drop shadows / clipping artifacts).
            cfg.includeChildWindows = true
            cfg.ignoreShadowsSingleWindow = true
            cfg.ignoreGlobalClipSingleWindow = true
            cfg.captureResolution = Self.captureResolution(for: request)

            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { [weak self] cgImage, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        Log.event.debug("Preview capture failed for window \(request.windowId): \(String(describing: error))")
                    }

                    guard let cgImage else {
                        let fallback = self.bestLastGoodEntry(
                            windowId: request.windowId,
                            targetSizePoints: request.targetSizePoints
                        )?.image
                        self.recordThumbnailCaptureEvent(
                            request: request,
                            outcome: fallback == nil ? "capture_failed" : "last_good_fallback",
                            queuedAt: queuedAt,
                            captureStart: captureStart,
                            image: fallback,
                            success: fallback != nil
                        )
                        self.completeCapture(
                            request: request,
                            image: fallback
                        )
                        return
                    }

                    let capturedAt = CFAbsoluteTimeGetCurrent()
                    let sizePoints = CGSize(
                        width: CGFloat(cgImage.width) / request.screenScale,
                        height: CGFloat(cgImage.height) / request.screenScale
                    )
                    let nsImage = NSImage(cgImage: cgImage, size: sizePoints)
                    self.imageCacheByKey[request.key] = CacheEntry(
                        image: nsImage,
                        capturedAt: capturedAt,
                        sizePoints: sizePoints,
                        byteCost: Self.approximateByteCost(sizePoints: sizePoints, screenScale: request.screenScale)
                    )
                    if Self.shouldStoreLastGood(for: request.producer) {
                        self.lastGoodImageByKey[request.key] = LastGoodEntry(
                            image: nsImage,
                            capturedAt: capturedAt,
                            sizePoints: sizePoints,
                            byteCost: Self.approximateByteCost(sizePoints: sizePoints, screenScale: request.screenScale)
                        )
                    }
                    self.enforceRetentionBudgets()
                    self.recordThumbnailCaptureEvent(
                        request: request,
                        outcome: "captured",
                        queuedAt: queuedAt,
                        captureStart: captureStart,
                        image: nsImage,
                        success: true
                    )
                    self.completeCapture(request: request, image: nsImage)
                }
            }
        }
    }

    nonisolated static func shouldAttemptScreenCapturePermissionFlow(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["LIQUIDBAR_TEST_CONTROL"] != "1" &&
        environment["LIQUIDBAR_DISABLE_SCREEN_RECORDING_PROMPT"] != "1"
    }

    private func completeCapture(request: CaptureRequest, image: NSImage?) {
        requestQueuedAtByIdentity.removeValue(forKey: request.identity)
        let shouldDeliver = scheduler.isCurrent(request)
        let callbacks = callbacksByIdentity.removeValue(forKey: request.identity) ?? []
        let nextDispatch = scheduler.finish(request.key)
        guard shouldDeliver else {
            dispatchCaptures(nextDispatch)
            return
        }
        for callback in callbacks {
            callback(image)
        }
        dispatchCaptures(nextDispatch)
    }

    private func bestCachedEntry(windowId: CGWindowID, targetSizePoints: CGSize) -> CacheEntry? {
        guard let key = Self.bestAvailableCacheKey(
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            availableKeys: Set(imageCacheByKey.keys)
        ) else {
            return nil
        }
        guard let entry = imageCacheByKey[key], isEntry(entry, sufficientFor: targetSizePoints) else {
            return nil
        }
        return entry
    }

    private func bestAnyCachedEntry(windowId: CGWindowID) -> CacheEntry? {
        imageCacheByKey
            .filter { $0.key.windowId == windowId }
            .sorted {
                if $0.key.tier != $1.key.tier {
                    return $0.key.tier > $1.key.tier
                }
                return $0.value.capturedAt > $1.value.capturedAt
            }
            .first?
            .value
    }

    private func bestLastGoodEntry(windowId: CGWindowID, targetSizePoints: CGSize) -> LastGoodEntry? {
        guard let key = Self.bestAvailableCacheKey(
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            availableKeys: Set(lastGoodImageByKey.keys)
        ) else {
            return nil
        }
        guard let entry = lastGoodImageByKey[key],
              entry.sizePoints.width >= targetSizePoints.width * 0.85,
              entry.sizePoints.height >= targetSizePoints.height * 0.85 else {
            return nil
        }
        return entry
    }

    private func bestAnyLastGoodEntry(windowId: CGWindowID) -> LastGoodEntry? {
        lastGoodImageByKey
            .filter { $0.key.windowId == windowId }
            .sorted {
                if $0.key.tier != $1.key.tier {
                    return $0.key.tier > $1.key.tier
                }
                return $0.value.capturedAt > $1.value.capturedAt
            }
            .first?
            .value
    }

    nonisolated static func requestKey(windowId: CGWindowID, targetSizePoints: CGSize) -> ThumbnailRequestKey {
        ThumbnailRequestKey(windowId: windowId, tier: ThumbnailTier.forTargetSize(targetSizePoints))
    }

    nonisolated static func captureResolution(for request: CaptureRequest) -> SCCaptureResolutionType {
        return .nominal
    }

    nonisolated static func freshCacheTTL(for producer: ThumbnailProducer) -> CFAbsoluteTime {
        switch producer {
        case .switcher, .prewarm:
            return 8.0
        case .interactive, .groupPreview, .overflowShelf:
            return 0.75
        }
    }

    nonisolated static func shouldStoreLastGood(for _: ThumbnailProducer) -> Bool {
        true
    }

    nonisolated static func approximateByteCost(sizePoints: CGSize, screenScale: CGFloat) -> Int {
        let pixelWidth = max(1, Int((sizePoints.width * screenScale).rounded(.up)))
        let pixelHeight = max(1, Int((sizePoints.height * screenScale).rounded(.up)))
        return pixelWidth * pixelHeight * 4
    }

    nonisolated static func bestAvailableCacheKey(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        availableKeys: Set<ThumbnailRequestKey>
    ) -> ThumbnailRequestKey? {
        let requiredTier = ThumbnailTier.forTargetSize(targetSizePoints)
        return availableKeys
            .filter { $0.windowId == windowId && $0.tier >= requiredTier }
            .sorted {
                if $0.tier != $1.tier {
                    return $0.tier < $1.tier
                }
                return $0.windowId < $1.windowId
            }
            .first
    }

    private func performMaintenance(now: CFAbsoluteTime) {
        guard (now - lastMaintenanceAt) >= 0.5 else { return }
        lastMaintenanceAt = now
        sweepStaleEntries(now: now)
        enforceRetentionBudgets()
    }

    private func sweepStaleEntries(now: CFAbsoluteTime) {
        imageCacheByKey = imageCacheByKey.filter { (now - $0.value.capturedAt) <= retentionPolicy.staleCacheAge }
        lastGoodImageByKey = lastGoodImageByKey.filter { (now - $0.value.capturedAt) <= retentionPolicy.staleLastGoodAge }
    }

    private func enforceRetentionBudgets() {
        for tier in ThumbnailTier.allCases {
            enforceTierBudget(for: tier)
        }
        enforceLastGoodBudget()
    }

    private func enforceTierBudget(for tier: ThumbnailTier) {
        let maxEntries = retentionPolicy.maxEntriesPerTier[tier, default: Int.max]
        let maxBytes = retentionPolicy.maxBytesPerTier[tier, default: Int.max]

        var tierEntries = imageCacheByKey
            .filter { $0.key.tier == tier }
            .sorted {
                if $0.value.capturedAt != $1.value.capturedAt {
                    return $0.value.capturedAt < $1.value.capturedAt
                }
                return $0.key.windowId < $1.key.windowId
            }

        var totalBytes = tierEntries.reduce(0) { $0 + $1.value.byteCost }
        while tierEntries.count > maxEntries || totalBytes > maxBytes {
            guard let evicted = tierEntries.first else { break }
            tierEntries.removeFirst()
            totalBytes -= evicted.value.byteCost
            imageCacheByKey.removeValue(forKey: evicted.key)
        }
    }

    private func enforceLastGoodBudget() {
        let maxEntries = retentionPolicy.maxLastGoodEntries
        let maxBytes = retentionPolicy.maxLastGoodBytes

        var entries = lastGoodImageByKey
            .sorted {
                if $0.value.capturedAt != $1.value.capturedAt {
                    return $0.value.capturedAt < $1.value.capturedAt
                }
                if $0.key.windowId != $1.key.windowId {
                    return $0.key.windowId < $1.key.windowId
                }
                return $0.key.tier < $1.key.tier
            }

        var totalBytes = entries.reduce(0) { $0 + $1.value.byteCost }
        while entries.count > maxEntries || totalBytes > maxBytes {
            guard let evicted = entries.first else { break }
            entries.removeFirst()
            totalBytes -= evicted.value.byteCost
            lastGoodImageByKey.removeValue(forKey: evicted.key)
        }
    }

    private func recordThumbnailCacheEvent(
        request: CaptureRequest,
        outcome: String,
        entry: CacheEntry
    ) {
        PerformanceMonitor.shared.recordThumbnailEvent(
            producer: request.producer.rawValue,
            tier: Self.tierName(request.key.tier),
            outcome: outcome,
            queueWaitMs: 0,
            captureMs: 0,
            totalMs: 0,
            byteCost: entry.byteCost,
            success: true
        )
    }

    private func recordThumbnailLastGoodEvent(
        request: CaptureRequest,
        outcome: String,
        entry: LastGoodEntry
    ) {
        PerformanceMonitor.shared.recordThumbnailEvent(
            producer: request.producer.rawValue,
            tier: Self.tierName(request.key.tier),
            outcome: outcome,
            queueWaitMs: 0,
            captureMs: 0,
            totalMs: 0,
            byteCost: entry.byteCost,
            success: true
        )
    }

    private func recordThumbnailCaptureEvent(
        request: CaptureRequest,
        outcome: String,
        queuedAt: CFTimeInterval,
        captureStart: CFTimeInterval,
        image: NSImage?,
        success: Bool
    ) {
        let now = CACurrentMediaTime()
        let queueWaitMs = max(0, (captureStart - queuedAt) * 1000.0)
        let captureMs = max(0, (now - captureStart) * 1000.0)
        let totalMs = max(0, (now - queuedAt) * 1000.0)
        let byteCost: Int
        if let image {
            byteCost = Self.approximateByteCost(sizePoints: image.size, screenScale: request.screenScale)
        } else {
            byteCost = 0
        }
        PerformanceMonitor.shared.recordThumbnailEvent(
            producer: request.producer.rawValue,
            tier: Self.tierName(request.key.tier),
            outcome: outcome,
            queueWaitMs: queueWaitMs,
            captureMs: captureMs,
            totalMs: totalMs,
            byteCost: byteCost,
            success: success
        )
    }

    nonisolated static func tierName(_ tier: ThumbnailTier) -> String {
        switch tier {
        case .tiny:
            return "tiny"
        case .standard:
            return "standard"
        case .large:
            return "large"
        }
    }

    #if DEBUG
    func debugStoreCachedThumbnail(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        image: NSImage,
        capturedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        screenScale: CGFloat = 2.0
    ) {
        imageCacheByKey[Self.requestKey(windowId: windowId, targetSizePoints: targetSizePoints)] = CacheEntry(
            image: image,
            capturedAt: capturedAt,
            sizePoints: targetSizePoints,
            byteCost: Self.approximateByteCost(sizePoints: targetSizePoints, screenScale: screenScale)
        )
        enforceRetentionBudgets()
    }

    func debugCachedKeys(windowId: CGWindowID) -> Set<ThumbnailRequestKey> {
        Set(imageCacheByKey.keys.filter { $0.windowId == windowId })
    }

    func debugCachedWindowIds(for tier: ThumbnailTier) -> [CGWindowID] {
        imageCacheByKey.keys
            .filter { $0.tier == tier }
            .map(\.windowId)
            .sorted()
    }

    func debugStoreLastGoodThumbnail(
        windowId: CGWindowID,
        image: NSImage,
        sizePoints: CGSize,
        capturedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        screenScale: CGFloat = 2.0
    ) {
        lastGoodImageByKey[Self.requestKey(windowId: windowId, targetSizePoints: sizePoints)] = LastGoodEntry(
            image: image,
            capturedAt: capturedAt,
            sizePoints: sizePoints,
            byteCost: Self.approximateByteCost(sizePoints: sizePoints, screenScale: screenScale)
        )
        enforceRetentionBudgets()
    }

    func debugLastGoodWindowIds() -> [CGWindowID] {
        Array(Set(lastGoodImageByKey.keys.map(\.windowId))).sorted()
    }

    func debugStartInFlight(windowId: CGWindowID, targetSizePoints: CGSize) {
        let request = CaptureRequest(
            key: Self.requestKey(windowId: windowId, targetSizePoints: targetSizePoints),
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            screenScale: 2.0,
            producer: .interactive,
            generation: scheduler.currentGeneration(for: .interactive)
        )
        scheduler.debugInsertInFlight(request)
    }

    func debugInFlightKeys(windowId: CGWindowID) -> Set<ThumbnailRequestKey> {
        Set(
            scheduler.debugInFlightRequests()
                .map(\.key)
                .filter { $0.windowId == windowId }
        )
    }

    func debugInvalidateRequests(for producer: ThumbnailProducer) {
        invalidateRequests(for: producer)
    }

    func debugQueuedRequests() -> [CaptureRequest] {
        scheduler.debugQueuedRequests()
    }

    func debugPruneToLiveWindowIds(_ liveWindowIds: Set<CGWindowID>) {
        pruneToLiveWindowIds(liveWindowIds)
    }

    func debugSweepRetainedThumbnails(now: CFAbsoluteTime) {
        sweepRetainedThumbnails(now: now)
    }

    @discardableResult
    func debugEnqueueRequest(
        windowId: CGWindowID,
        targetSizePoints: CGSize,
        producer: ThumbnailProducer
    ) -> CaptureRequest? {
        let request = CaptureRequest(
            key: Self.requestKey(windowId: windowId, targetSizePoints: targetSizePoints),
            windowId: windowId,
            targetSizePoints: targetSizePoints,
            screenScale: 2.0,
            producer: producer,
            generation: scheduler.currentGeneration(for: producer)
        )
        let result = scheduler.enqueue(request)
        dropCallbacks(for: result.droppedQueued)
        return result.trackedRequest
    }
    #endif

    private func resolveSCWindow(windowId: CGWindowID, completion: @escaping (SCWindow?) -> Void) {
        let now = CFAbsoluteTimeGetCurrent()
        if let w = cachedWindowsById[windowId], (now - cachedContentAt) < contentCacheTTL {
            completion(w)
            return
        }

        pendingContentCallbacks.append((windowId: windowId, callback: completion))
        guard !isRefreshingContent else { return }
        isRefreshingContent = true

        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRefreshingContent = false

                if let error {
                    Log.event.debug("SCShareableContent fetch failed: \(String(describing: error))")
                }

                let windows = content?.windows ?? []
                var map: [CGWindowID: SCWindow] = [:]
                map.reserveCapacity(windows.count)
                for w in windows {
                    map[w.windowID] = w
                }
                self.cachedWindowsById = map
                self.cachedContentAt = CFAbsoluteTimeGetCurrent()
                self.pruneToLiveWindowIds(Set(map.keys))

                let callbacks = self.pendingContentCallbacks
                self.pendingContentCallbacks.removeAll(keepingCapacity: false)
                for entry in callbacks {
                    entry.callback(map[entry.windowId])
                }
            }
        }
    }
}

// ScreenCaptureKit types are effectively immutable value-objects for our usage
// (read-only properties, used as identifiers/filters). Marking unchecked Sendable
// avoids Swift 6 strict-concurrency errors when hopping to the main actor.
extension SCShareableContent: @retroactive @unchecked Sendable {}
extension SCWindow: @retroactive @unchecked Sendable {}
