import Foundation
import CoreGraphics

struct OverlayAnimationTuning: Sendable {
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval
    let springStiffness: CGFloat
    let springDamping: CGFloat
    let initialScale: CGFloat
    let hideScale: CGFloat
}

struct RendererAnimationTuning: Sendable {
    let stiffnessScale: Float
    let dampingScale: Float
    let alphaRateScale: Float
}

extension AnimationProfile {
    var overlayTuning: OverlayAnimationTuning {
        switch self {
        case .balancedSpring:
            return OverlayAnimationTuning(
                fadeInDuration: 0.14,
                fadeOutDuration: 0.10,
                springStiffness: 520,
                springDamping: 34,
                initialScale: 0.96,
                hideScale: 0.985
            )
        case .snappyMinimal:
            return OverlayAnimationTuning(
                fadeInDuration: 0.10,
                fadeOutDuration: 0.08,
                springStiffness: 640,
                springDamping: 40,
                initialScale: 0.98,
                hideScale: 0.99
            )
        case .richExpressive:
            return OverlayAnimationTuning(
                fadeInDuration: 0.18,
                fadeOutDuration: 0.12,
                springStiffness: 430,
                springDamping: 28,
                initialScale: 0.94,
                hideScale: 0.982
            )
        }
    }

    var rendererTuning: RendererAnimationTuning {
        switch self {
        case .balancedSpring:
            return RendererAnimationTuning(stiffnessScale: 1.0, dampingScale: 1.0, alphaRateScale: 1.0)
        case .snappyMinimal:
            return RendererAnimationTuning(stiffnessScale: 1.2, dampingScale: 1.08, alphaRateScale: 1.18)
        case .richExpressive:
            return RendererAnimationTuning(stiffnessScale: 0.86, dampingScale: 0.9, alphaRateScale: 0.88)
        }
    }
}

