import Foundation

/// Where the picker sits. Caret first (Cocoa coords); mouse if the caret is missing
/// or has an empty rect (Chrome/Terminal from the spike). Flips below the caret when
/// there is no room above; clamps to the visible screen.
enum PickerPlacement {

    static let gap: CGFloat = 6

    /// AX sometimes hands back a real-looking rect that is nowhere on a display
    /// (menu-bar managers, stale frames). Those must not win over the mouse.
    static func usableCaret(_ caret: CGRect?, screens: [CGRect]) -> CGRect? {
        guard let caret, !caret.isNull, !caret.isInfinite,
              caret.width + caret.height > 0 else { return nil }
        let slop: CGFloat = 40
        if screens.contains(where: { $0.insetBy(dx: -slop, dy: -slop).intersects(caret) }) {
            return caret
        }
        return nil
    }

    static func frame(
        size: CGSize,
        caretRect: CGRect?,
        mouse: CGPoint,
        screen: CGRect
    ) -> CGRect {
        let anchor: CGPoint
        let preferAbove: Bool
        if let caret = caretRect, !caret.isEmpty, caret.width + caret.height > 0 {
            anchor = CGPoint(x: caret.midX, y: caret.maxY)
            preferAbove = true
            var frame = centered(size: size, at: anchor, above: preferAbove)
            if frame.maxY > screen.maxY - 2, preferAbove {
                // Flip below the caret.
                frame.origin.y = caret.minY - gap - size.height
            }
            return clamp(frame, to: screen)
        }
        // Near the mouse: just above the pointer so it does not sit under the cursor.
        anchor = CGPoint(x: mouse.x, y: mouse.y + gap)
        return clamp(centered(size: size, at: anchor, above: true), to: screen)
    }

    private static func centered(size: CGSize, at point: CGPoint, above: Bool) -> CGRect {
        let x = point.x - size.width / 2
        let y = above ? point.y + gap : point.y - gap - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        var f = frame
        if f.minX < screen.minX { f.origin.x = screen.minX + 4 }
        if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width - 4 }
        if f.minY < screen.minY { f.origin.y = screen.minY + 4 }
        if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height - 4 }
        return f
    }
}
