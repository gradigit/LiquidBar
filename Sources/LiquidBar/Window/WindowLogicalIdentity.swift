enum WindowLogicalIdentity {
    private static let boundsBucketSize = 16.0
    private static let overlapThreshold = 0.92
    private static let lowInformationTitleOverlapThreshold = 0.98
    private static let containedAuxiliaryOverlapThreshold = 0.70
    private static let containedAuxiliaryMaxAreaRatio = 0.35

    static func normalizedTitle(_ window: WindowInfo) -> String {
        window.title.isEmpty ? window.appName : window.title
    }

    static func isLikelySameWindow(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        if lhs.id == rhs.id { return true }
        let sameBundle = lhs.bundleId.raw == rhs.bundleId.raw
        let relatedChromeWrapper = isRelatedChromeWrapperBundle(lhs.bundleId.raw, rhs.bundleId.raw)

        guard (sameBundle || relatedChromeWrapper),
              lhs.monitorId == rhs.monitorId else {
            return false
        }

        let titlesMatch = normalizedTitle(lhs) == normalizedTitle(rhs)
        if sameBundle && titlesMatch && coarseBoundsSignature(lhs) == coarseBoundsSignature(rhs) {
            return true
        }

        let lhsArea = area(lhs.bounds)
        let rhsArea = area(rhs.bounds)
        let minArea = max(1.0, min(lhsArea, rhsArea))
        let overlapRatio = lhs.bounds.intersectionArea(with: rhs.bounds) / minArea
        if titlesMatch {
            return overlapRatio >= overlapThreshold ||
                isContainedAuxiliarySurfaceDuplicate(lhs, rhs, overlapRatio: overlapRatio)
        }

        // Chrome web apps and some AppKit/SwiftUI apps can briefly expose a
        // duplicate compositor surface whose title is empty or only the app name
        // while the real surface has the document/page title. Treat only
        // near-identical geometry as the same window so genuinely stacked
        // same-app windows with different real titles remain distinct.
        guard hasLowInformationTitle(lhs, pairedWith: rhs) || hasLowInformationTitle(rhs, pairedWith: lhs) else {
            return false
        }
        return overlapRatio >= lowInformationTitleOverlapThreshold ||
            isContainedAuxiliarySurfaceDuplicate(lhs, rhs, overlapRatio: overlapRatio)
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

        let candidateTitleScore = titleInformationScore(candidate, pairedWith: existing)
        let existingTitleScore = titleInformationScore(existing, pairedWith: candidate)
        if candidateTitleScore != existingTitleScore {
            return candidateTitleScore > existingTitleScore
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

    private static func isContainedAuxiliarySurfaceDuplicate(
        _ lhs: WindowInfo,
        _ rhs: WindowInfo,
        overlapRatio: Double
    ) -> Bool {
        guard overlapRatio >= containedAuxiliaryOverlapThreshold else {
            return false
        }

        let lhsArea = area(lhs.bounds)
        let rhsArea = area(rhs.bounds)
        let maxArea = max(lhsArea, rhsArea)
        guard maxArea > 0 else { return false }

        let areaRatio = min(lhsArea, rhsArea) / maxArea
        return areaRatio <= containedAuxiliaryMaxAreaRatio
    }

    private static func hasLowInformationTitle(_ window: WindowInfo, pairedWith other: WindowInfo) -> Bool {
        window.title.isEmpty ||
            (!window.appName.isEmpty && window.title == window.appName) ||
            (!other.appName.isEmpty && window.title == other.appName)
    }

    private static func titleInformationScore(_ window: WindowInfo, pairedWith other: WindowInfo) -> Int {
        if window.title.isEmpty { return 0 }
        if (!window.appName.isEmpty && window.title == window.appName) ||
            (!other.appName.isEmpty && window.title == other.appName) {
            return 1
        }
        return 2
    }

    private static func isRelatedChromeWrapperBundle(_ lhs: String, _ rhs: String) -> Bool {
        let chromeBundle = "com.google.Chrome"
        let chromeAppPrefix = "com.google.Chrome.app."
        return (lhs == chromeBundle && rhs.hasPrefix(chromeAppPrefix)) ||
            (rhs == chromeBundle && lhs.hasPrefix(chromeAppPrefix))
    }
}
