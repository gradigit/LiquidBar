enum WindowLogicalIdentity {
    private static let boundsBucketSize = 16.0
    private static let overlapThreshold = 0.92

    static func normalizedTitle(_ window: WindowInfo) -> String {
        window.title.isEmpty ? window.appName : window.title
    }

    static func isLikelySameWindow(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        if lhs.id == rhs.id { return true }
        guard lhs.bundleId.raw == rhs.bundleId.raw,
              lhs.monitorId == rhs.monitorId,
              normalizedTitle(lhs) == normalizedTitle(rhs) else {
            return false
        }

        if coarseBoundsSignature(lhs) == coarseBoundsSignature(rhs) {
            return true
        }

        let lhsArea = area(lhs.bounds)
        let rhsArea = area(rhs.bounds)
        let minArea = max(1.0, min(lhsArea, rhsArea))
        let overlapRatio = lhs.bounds.intersectionArea(with: rhs.bounds) / minArea
        return overlapRatio >= overlapThreshold
    }

    static func deduped(_ windows: [WindowInfo]) -> [WindowInfo] {
        var out: [WindowInfo] = []
        out.reserveCapacity(windows.count)

        var seenIds = Set<UInt32>()
        seenIds.reserveCapacity(windows.count)

        for window in windows {
            if !seenIds.insert(window.id.raw).inserted {
                continue
            }

            if let index = out.firstIndex(where: { isLikelySameWindow($0, window) }) {
                if prefers(window, over: out[index]) {
                    out[index] = window
                }
                continue
            }

            out.append(window)
        }

        return out
    }

    static func prefers(_ candidate: WindowInfo, over existing: WindowInfo) -> Bool {
        let candidateDimmed = candidate.isHidden || candidate.isMinimized
        let existingDimmed = existing.isHidden || existing.isMinimized
        if candidateDimmed != existingDimmed {
            return !candidateDimmed
        }

        let candidateHasTitle = !candidate.title.isEmpty
        let existingHasTitle = !existing.title.isEmpty
        if candidateHasTitle != existingHasTitle {
            return candidateHasTitle
        }

        return area(candidate.bounds) > area(existing.bounds)
    }

    static func carryingForwardTitle(from previous: WindowInfo, to observed: WindowInfo) -> WindowInfo {
        guard observed.title.isEmpty, !previous.title.isEmpty else {
            return observed
        }

        return WindowInfo(
            id: observed.id,
            bundleId: observed.bundleId,
            appName: observed.appName.isEmpty ? previous.appName : observed.appName,
            title: previous.title,
            isHidden: observed.isHidden,
            isMinimized: observed.isMinimized,
            monitorId: observed.monitorId,
            bounds: observed.bounds
        )
    }

    private static func coarseBoundsSignature(_ window: WindowInfo) -> String {
        let bounds = window.bounds
        let bx = Int((bounds.x / boundsBucketSize).rounded())
        let by = Int((bounds.y / boundsBucketSize).rounded())
        let bw = Int((bounds.width / boundsBucketSize).rounded())
        let bh = Int((bounds.height / boundsBucketSize).rounded())
        return "\(bx),\(by),\(bw),\(bh)"
    }

    private static func area(_ bounds: WindowBounds) -> Double {
        max(0.0, bounds.width) * max(0.0, bounds.height)
    }
}
