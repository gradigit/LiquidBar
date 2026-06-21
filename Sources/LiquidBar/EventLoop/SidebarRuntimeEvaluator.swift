import CoreGraphics
import Foundation

enum SidebarPresentation: String, Sendable, Equatable {
    case expanded
    case compact
    case hidden
}

enum SidebarRuntimeEvaluator {
    static let revealDuration: CFAbsoluteTime = 1.4

    static func updatedRevealUntil(
        currentRevealUntil: CFAbsoluteTime,
        now: CFAbsoluteTime,
        defaultState: SidebarDefaultState,
        trigger: SidebarExpandTrigger,
        edgeHover: Bool,
        hoveringPanel: Bool,
        hasOverlay: Bool
    ) -> CFAbsoluteTime {
        guard defaultState != .expanded else { return now + revealDuration }

        var revealUntil = currentRevealUntil

        // Keep a revealed sidebar open while an anchored overlay is visible.
        if hasOverlay {
            revealUntil = max(revealUntil, now + revealDuration)
        }

        let hoverTriggerEnabled = (trigger == .hover || trigger == .hybrid)
        if hoverTriggerEnabled && (edgeHover || hoveringPanel) {
            revealUntil = max(revealUntil, now + revealDuration)
        }

        return revealUntil
    }

    static func presentation(
        defaultState: SidebarDefaultState,
        now: CFAbsoluteTime,
        revealUntil: CFAbsoluteTime
    ) -> SidebarPresentation {
        switch defaultState {
        case .expanded:
            return .expanded
        case .compactIcons:
            return now <= revealUntil ? .expanded : .compact
        case .hiddenPeek:
            return now <= revealUntil ? .expanded : .hidden
        }
    }

    static func barThickness(
        for presentation: SidebarPresentation,
        config: Config
    ) -> CGFloat {
        let compact = max(24, CGFloat(config.effectiveTaskbarHeight))

        switch presentation {
        case .compact:
            return compact
        case .hidden:
            // Keep a thin edge strip for trigger detection while minimizing reserved space.
            return min(compact, 4)
        case .expanded:
            let textRun = min(config.maxTitleWidth, config.maxItemWidth)
            let requiredForLabel = CGFloat(config.iconSize + 28 + textRun)
            let baseline = CGFloat(max(config.maxItemWidth, Int(ceil(requiredForLabel))))
            return max(compact, min(420, baseline))
        }
    }
}
