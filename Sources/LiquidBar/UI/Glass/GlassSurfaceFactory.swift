import AppKit

/// Where a glass surface is used (tokens can diverge later).
enum GlassSurfaceKind: Sendable {
    case bar
    case overlay
    case preview
}

struct GlassSurface {
    let view: NSView
    /// True if the background samples the live backdrop (i.e., can flash if installed too early).
    let isLiveBackdrop: Bool
}

enum GlassSurfaceFactory {
    @MainActor
    private static func configureGlassView(_ glass: NSGlassEffectView, kind: GlassSurfaceKind, cornerRadiusOverride: CGFloat?) {
        // Keep geometry consistent with our container masking.
        let radius: CGFloat = cornerRadiusOverride ?? {
            switch kind {
            case .bar:
                return GlassTokens.barCornerRadius
            case .overlay, .preview:
                return GlassTokens.overlayCornerRadius
            }
        }()
        glass.cornerRadius = radius
        // Neutral treatment by default.
        glass.tintColor = nil
    }

    @MainActor
    static func makeBackground(
        kind: GlassSurfaceKind,
        style: GlassStyle,
        reduceTransparency: Bool,
        testSolidBackgroundLuma: CGFloat?,
        cornerRadiusOverride: CGFloat? = nil
    ) -> GlassSurface {
        if let luma = testSolidBackgroundLuma {
            let bg = NSView()
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(calibratedWhite: luma, alpha: 1.0).cgColor
            if let r = cornerRadiusOverride {
                bg.layer?.cornerRadius = r
                bg.layer?.masksToBounds = true
            }
            return GlassSurface(view: bg, isLiveBackdrop: false)
        }

        if reduceTransparency {
            let effect = NSVisualEffectView()
            effect.state = .active
            effect.material = .windowBackground
            effect.blendingMode = .withinWindow
            if let r = cornerRadiusOverride {
                effect.wantsLayer = true
                effect.layer?.cornerRadius = r
                effect.layer?.masksToBounds = true
            }
            return GlassSurface(view: effect, isLiveBackdrop: false)
        }

        switch style {
        case .publicRegular:
            let glass = NSGlassEffectView()
            glass.style = .regular
            configureGlassView(glass, kind: kind, cornerRadiusOverride: cornerRadiusOverride)
            return GlassSurface(view: glass, isLiveBackdrop: true)

        case .publicClear:
            let glass = NSGlassEffectView()
            glass.style = .clear
            configureGlassView(glass, kind: kind, cornerRadiusOverride: cornerRadiusOverride)
            return GlassSurface(view: glass, isLiveBackdrop: true)
        }
    }
}
