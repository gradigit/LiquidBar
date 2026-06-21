import AppKit

enum LiquidBarLogo {
    private static let appIconResourceName = "LiquidBar"
    private static let menuBarTemplateResourceName = "liquidbar-menubar-template"
    private static let brandBarResourceName = "liquidbar-brand-bar-transparent"
    static let menuBarStatusItemLength: CGFloat = 28
    static let menuBarTemplateSize = NSSize(width: 26, height: 17)
    static let brandBarAspectRatio: CGFloat = 1562.0 / 376.0

    @MainActor
    static func makeApplicationIcon(
        bundle: Bundle = .main,
        fallbackSize: NSSize = NSSize(width: 256, height: 256)
    ) -> NSImage {
        if let image = loadBundledAppIcon(from: bundle) {
            image.accessibilityDescription = "LiquidBar"
            return image
        }

        let image = makeAppIcon(size: fallbackSize)
        image.accessibilityDescription = "LiquidBar"
        return image
    }

    static func loadBundledAppIcon(from bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(forResource: appIconResourceName, withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    @MainActor
    static func makeAppIcon(size: NSSize = NSSize(width: 256, height: 256)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            drawAppIcon(in: rect)
            return true
        }
    }

    @MainActor
    static func makeMenuBarTemplateImage(
        bundle: Bundle = .main,
        size: NSSize = menuBarTemplateSize
    ) -> NSImage {
        if let image = loadBundledMenuBarTemplate(from: bundle, size: size) {
            return image
        }

        let image = NSImage(size: size, flipped: false) { rect in
            drawMenuBarGlyph(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LiquidBar"
        return image
    }

    @MainActor
    static func makeBrandBarImage(
        bundle: Bundle = .main,
        displaySize: NSSize = NSSize(width: 280, height: 68)
    ) -> NSImage {
        if let image = loadBundledBrandBar(from: bundle, displaySize: displaySize) {
            return image
        }

        let image = NSImage(size: displaySize, flipped: false) { rect in
            drawBrandBar(in: rect)
            return true
        }
        image.accessibilityDescription = "LiquidBar"
        return image
    }

    static func loadBundledBrandBar(
        from bundle: Bundle = .main,
        displaySize: NSSize? = nil
    ) -> NSImage? {
        guard let url = bundle.url(forResource: brandBarResourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        if let displaySize {
            image.size = displaySize
        }
        image.accessibilityDescription = "LiquidBar"
        return image
    }

    static func loadBundledMenuBarTemplate(
        from bundle: Bundle = .main,
        size: NSSize = menuBarTemplateSize
    ) -> NSImage? {
        guard let url = bundle.url(forResource: menuBarTemplateResourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = size
        image.isTemplate = true
        image.accessibilityDescription = "LiquidBar"
        return image
    }

    static func drawAppIcon(in rect: NSRect) {
        let scale = min(rect.width, rect.height) / 256.0

        let backgroundRect = rect.insetBy(dx: 8 * scale, dy: 8 * scale)
        let backgroundPath = NSBezierPath(
            roundedRect: backgroundRect,
            xRadius: 50 * scale,
            yRadius: 50 * scale
        )
        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()
        NSGradient(
            starting: NSColor(srgbRed: 0.11, green: 0.13, blue: 0.16, alpha: 1),
            ending: NSColor(srgbRed: 0.015, green: 0.02, blue: 0.028, alpha: 1)
        )?.draw(in: backgroundPath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.12).setStroke()
        backgroundPath.lineWidth = 1.25 * scale
        backgroundPath.stroke()

        let barRect = NSRect(
            x: rect.minX + 42 * scale,
            y: rect.midY - 24 * scale,
            width: rect.width - 84 * scale,
            height: 48 * scale
        )
        let barPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: barRect.height / 2,
            yRadius: barRect.height / 2
        )

        NSGraphicsContext.saveGraphicsState()
        barPath.addClip()
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.44),
            ending: NSColor(srgbRed: 0.35, green: 0.58, blue: 0.82, alpha: 0.16)
        )?.draw(in: barPath, angle: -90)

        let waveCurve = NSBezierPath()
        waveCurve.move(to: NSPoint(x: barRect.minX, y: barRect.midY - 2 * scale))
        waveCurve.curve(
            to: NSPoint(x: barRect.minX + barRect.width * 0.47, y: barRect.midY - 10 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.16, y: barRect.midY - 4 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.31, y: barRect.midY - 18 * scale)
        )
        waveCurve.curve(
            to: NSPoint(x: barRect.minX + barRect.width * 0.69, y: barRect.midY - 5 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.55, y: barRect.midY - 5 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.60, y: barRect.midY + 2 * scale)
        )
        waveCurve.curve(
            to: NSPoint(x: barRect.maxX, y: barRect.midY - 1 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.78, y: barRect.midY - 13 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.88, y: barRect.midY - 3 * scale)
        )
        let wave = waveCurve.copy() as! NSBezierPath
        wave.line(to: NSPoint(x: barRect.maxX, y: barRect.minY))
        wave.line(to: NSPoint(x: barRect.minX, y: barRect.minY))
        wave.close()
        NSGradient(
            starting: NSColor(srgbRed: 0.70, green: 0.88, blue: 1.0, alpha: 0.40),
            ending: NSColor(srgbRed: 0.05, green: 0.16, blue: 0.26, alpha: 0.18)
        )?.draw(in: wave, angle: -90)

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.70).setStroke()
        barPath.lineWidth = 2.0 * scale
        barPath.stroke()

        let topSheen = NSBezierPath()
        topSheen.move(to: NSPoint(x: barRect.minX + 16 * scale, y: barRect.maxY - 9 * scale))
        topSheen.curve(
            to: NSPoint(x: barRect.maxX - 20 * scale, y: barRect.maxY - 8 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.34, y: barRect.maxY - 3 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.68, y: barRect.maxY - 7 * scale)
        )
        NSColor.white.withAlphaComponent(0.72).setStroke()
        topSheen.lineWidth = 1.6 * scale
        topSheen.stroke()

        NSColor(srgbRed: 0.52, green: 0.82, blue: 1.0, alpha: 0.38).setStroke()
        waveCurve.lineWidth = 1.2 * scale
        waveCurve.stroke()
    }

    static func drawBrandBar(in rect: NSRect) {
        let barRect = rect.insetBy(dx: rect.width * 0.035, dy: rect.height * 0.13)
        let scale = barRect.height / 48.0
        let barPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: barRect.height / 2,
            yRadius: barRect.height / 2
        )

        NSGraphicsContext.saveGraphicsState()
        barPath.addClip()
        NSGradient(
            starting: NSColor.white.withAlphaComponent(0.38),
            ending: NSColor(srgbRed: 0.03, green: 0.08, blue: 0.13, alpha: 0.76)
        )?.draw(in: barPath, angle: -90)

        let waveCurve = NSBezierPath()
        waveCurve.move(to: NSPoint(x: barRect.minX, y: barRect.midY - 2 * scale))
        waveCurve.curve(
            to: NSPoint(x: barRect.minX + barRect.width * 0.49, y: barRect.midY - 8 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.18, y: barRect.midY - 4 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.32, y: barRect.midY - 17 * scale)
        )
        waveCurve.curve(
            to: NSPoint(x: barRect.minX + barRect.width * 0.68, y: barRect.midY - 3 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.56, y: barRect.midY - 4 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.62, y: barRect.midY + 2 * scale)
        )
        waveCurve.curve(
            to: NSPoint(x: barRect.maxX, y: barRect.midY - 1 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.78, y: barRect.midY - 12 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.88, y: barRect.midY - 2 * scale)
        )

        let wave = waveCurve.copy() as! NSBezierPath
        wave.line(to: NSPoint(x: barRect.maxX, y: barRect.minY))
        wave.line(to: NSPoint(x: barRect.minX, y: barRect.minY))
        wave.close()
        NSGradient(
            starting: NSColor(srgbRed: 0.55, green: 0.82, blue: 1.0, alpha: 0.34),
            ending: NSColor(srgbRed: 0.02, green: 0.10, blue: 0.18, alpha: 0.22)
        )?.draw(in: wave, angle: -90)

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.74).setStroke()
        barPath.lineWidth = 1.8 * scale
        barPath.stroke()

        let topSheen = NSBezierPath()
        topSheen.move(to: NSPoint(x: barRect.minX + 16 * scale, y: barRect.maxY - 8 * scale))
        topSheen.curve(
            to: NSPoint(x: barRect.maxX - 20 * scale, y: barRect.maxY - 8 * scale),
            controlPoint1: NSPoint(x: barRect.minX + barRect.width * 0.34, y: barRect.maxY - 3 * scale),
            controlPoint2: NSPoint(x: barRect.minX + barRect.width * 0.68, y: barRect.maxY - 7 * scale)
        )
        NSColor.white.withAlphaComponent(0.66).setStroke()
        topSheen.lineWidth = 1.35 * scale
        topSheen.stroke()

        NSColor(srgbRed: 0.54, green: 0.82, blue: 1.0, alpha: 0.36).setStroke()
        waveCurve.lineWidth = 1.05 * scale
        waveCurve.stroke()
    }

    static func drawMenuBarGlyph(in rect: NSRect, color: NSColor) {
        let scale = rect.height / 18.0
        color.setFill()

        let barHeight = 10.2 * scale
        let barRect = NSRect(
            x: rect.minX + 1.1 * scale,
            y: rect.midY - barHeight / 2,
            width: rect.width - 2.2 * scale,
            height: barHeight
        )
        let glyph = NSBezierPath(
            roundedRect: barRect,
            xRadius: barRect.height / 2,
            yRadius: barRect.height / 2
        )
        glyph.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.clear.setFill()
        NSColor.clear.setStroke()

        let pocket = NSBezierPath()
        pocket.move(to: point(in: barRect, x: 0.61, y: 0.43))
        pocket.curve(
            to: point(in: barRect, x: 0.91, y: 0.47),
            controlPoint1: point(in: barRect, x: 0.70, y: 0.37),
            controlPoint2: point(in: barRect, x: 0.83, y: 0.37)
        )
        pocket.curve(
            to: point(in: barRect, x: 0.76, y: 0.10),
            controlPoint1: point(in: barRect, x: 0.88, y: 0.22),
            controlPoint2: point(in: barRect, x: 0.89, y: 0.03)
        )
        pocket.curve(
            to: point(in: barRect, x: 0.61, y: 0.43),
            controlPoint1: point(in: barRect, x: 0.69, y: 0.15),
            controlPoint2: point(in: barRect, x: 0.64, y: 0.28)
        )
        pocket.close()
        pocket.fill()

        let seam = NSBezierPath()
        seam.move(to: point(in: barRect, x: 0.02, y: 0.31))
        seam.curve(
            to: point(in: barRect, x: 0.54, y: 0.46),
            controlPoint1: point(in: barRect, x: 0.17, y: 0.22),
            controlPoint2: point(in: barRect, x: 0.37, y: 0.26)
        )
        seam.curve(
            to: point(in: barRect, x: 0.98, y: 0.47),
            controlPoint1: point(in: barRect, x: 0.68, y: 0.64),
            controlPoint2: point(in: barRect, x: 0.82, y: 0.53)
        )
        seam.lineWidth = 1.55 * scale
        seam.lineCapStyle = .round
        seam.lineJoinStyle = .round
        seam.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func point(in rect: NSRect, x: CGFloat, y: CGFloat) -> NSPoint {
        NSPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
    }
}
