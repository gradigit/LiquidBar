struct TaskbarOverflowPlan: Sendable {
    let items: [TaskbarItem]
    /// The original taskbar item index for each planned item. The overflow tile
    /// has no original index because it represents multiple removed windows.
    let sourceIndices: [Int?]
    let overflowWindowIds: [WindowId]

    var hasOverflow: Bool { !overflowWindowIds.isEmpty }
}

enum TaskbarOverflowPlanner {
    static func plan(
        items: [TaskbarItem],
        displayId: UInt32,
        focusedWindowId: UInt32?,
        fits: ([TaskbarItem]) -> Bool
    ) -> TaskbarOverflowPlan {
        let identity = TaskbarOverflowPlan(
            items: items,
            sourceIndices: items.indices.map(Optional.some),
            overflowWindowIds: []
        )
        guard !items.isEmpty, !fits(items) else { return identity }

        let removable: [(index: Int, id: WindowId)] = items.enumerated().compactMap { index, item in
            guard case .window(let id, _, _, _, _, _, _) = item else { return nil }
            return (index, id)
        }
        guard removable.count >= 2 else { return identity }

        let removalOrder = Array(removable
            .filter { $0.id.raw != focusedWindowId }
            .reversed())
        guard !removalOrder.isEmpty else { return identity }

        // Every additional removal shrinks the regular-item partition by at
        // least one minimum tile width, so fit is monotonic. Binary search keeps
        // text measurement/layout work logarithmic for very crowded bars.
        var lowerBound = 1
        var upperBound = removalOrder.count
        var bestPlan: TaskbarOverflowPlan?
        while lowerBound <= upperBound {
            let removalCount = lowerBound + (upperBound - lowerBound) / 2
            let removed = Set(removalOrder.prefix(removalCount).map(\.index))
            let candidatePlan = makePlan(
                items: items,
                removedIndices: removed,
                displayId: displayId
            )
            if fits(candidatePlan.items) {
                bestPlan = candidatePlan
                upperBound = removalCount - 1
            } else {
                lowerBound = removalCount + 1
            }
        }

        if let bestPlan { return bestPlan }

        // Keeping the focused window visible is more useful than forcing the bar
        // into a mathematically perfect fit when fixed custom/indicator items alone
        // consume the available width.
        return makePlan(
            items: items,
            removedIndices: Set(removalOrder.map(\.index)),
            displayId: displayId
        )
    }

    private static func makePlan(
        items: [TaskbarItem],
        removedIndices: Set<Int>,
        displayId: UInt32
    ) -> TaskbarOverflowPlan {
        let hiddenWindowIds = items.enumerated().compactMap { index, item -> WindowId? in
            guard removedIndices.contains(index),
                  case .window(let id, _, _, _, _, _, _) = item else {
                return nil
            }
            return id
        }

        guard let insertionIndex = removedIndices.min(), !hiddenWindowIds.isEmpty else {
            return TaskbarOverflowPlan(
                items: items,
                sourceIndices: items.indices.map(Optional.some),
                overflowWindowIds: []
            )
        }

        var plannedItems: [TaskbarItem] = []
        var sourceIndices: [Int?] = []
        plannedItems.reserveCapacity(items.count - removedIndices.count + 1)
        sourceIndices.reserveCapacity(plannedItems.capacity)

        for (index, item) in items.enumerated() {
            if index == insertionIndex {
                plannedItems.append(.windowOverflow(windows: hiddenWindowIds, screenId: displayId))
                sourceIndices.append(nil)
            }
            guard !removedIndices.contains(index) else { continue }
            plannedItems.append(item)
            sourceIndices.append(index)
        }

        return TaskbarOverflowPlan(
            items: plannedItems,
            sourceIndices: sourceIndices,
            overflowWindowIds: hiddenWindowIds
        )
    }
}
