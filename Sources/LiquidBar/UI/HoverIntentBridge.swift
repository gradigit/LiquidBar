import CoreGraphics

enum HoverIntentBridge {
    static func contains(
        cursor: CGPoint,
        anchorRect: CGRect,
        panelRect: CGRect,
        padding: CGFloat = 8
    ) -> Bool {
        guard cursor.x.isFinite, cursor.y.isFinite else { return false }
        guard anchorRect.isFiniteNonEmpty, panelRect.isFiniteNonEmpty else { return false }

        let anchor = anchorRect.insetBy(dx: -padding, dy: -padding)
        let panel = panelRect.insetBy(dx: -padding, dy: -padding)

        if anchor.contains(cursor) || panel.contains(cursor) {
            return true
        }

        let dx = panel.midX - anchor.midX
        let dy = panel.midY - anchor.midY

        let bridgePoints: [CGPoint]
        if abs(dy) >= abs(dx) {
            if dy >= 0 {
                bridgePoints = [
                    CGPoint(x: anchor.minX, y: anchor.maxY),
                    CGPoint(x: anchor.maxX, y: anchor.maxY),
                    CGPoint(x: panel.maxX, y: panel.minY),
                    CGPoint(x: panel.minX, y: panel.minY),
                ]
            } else {
                bridgePoints = [
                    CGPoint(x: anchor.minX, y: anchor.minY),
                    CGPoint(x: anchor.maxX, y: anchor.minY),
                    CGPoint(x: panel.maxX, y: panel.maxY),
                    CGPoint(x: panel.minX, y: panel.maxY),
                ]
            }
        } else if dx >= 0 {
            bridgePoints = [
                CGPoint(x: anchor.maxX, y: anchor.minY),
                CGPoint(x: anchor.maxX, y: anchor.maxY),
                CGPoint(x: panel.minX, y: panel.maxY),
                CGPoint(x: panel.minX, y: panel.minY),
            ]
        } else {
            bridgePoints = [
                CGPoint(x: anchor.minX, y: anchor.minY),
                CGPoint(x: anchor.minX, y: anchor.maxY),
                CGPoint(x: panel.maxX, y: panel.maxY),
                CGPoint(x: panel.maxX, y: panel.minY),
            ]
        }

        let path = CGMutablePath()
        path.addLines(between: bridgePoints)
        path.closeSubpath()
        return path.contains(cursor, using: .winding, transform: .identity)
    }
}

private extension CGRect {
    var isFiniteNonEmpty: Bool {
        width.isFinite
            && height.isFinite
            && minX.isFinite
            && minY.isFinite
            && width > 0
            && height > 0
    }
}
