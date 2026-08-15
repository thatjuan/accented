import AppKit

/// Draws the picker: optional degraded banner, then a horizontal strip of cells
/// (glyph + 1…9). Browse and variant modes are both one row. Sized to content —
/// no transparent hit-testing margin (diarc #15).
@MainActor
final class PickerContentView: NSView {

    enum Layout {
        static let cellWidth: CGFloat = 28
        static let cellHeight: CGFloat = 38
        static let cellSpacing: CGFloat = 1
        static let rowSpacing: CGFloat = 2
        static let padding: CGFloat = 6
        static let labelWidth: CGFloat = 14
        static let bannerHeight: CGFloat = 22
        static let cornerRadius: CGFloat = 8
        static let cellRadius: CGFloat = 5
    }

    var session: PickerSession = PickerSession(
        context: PickerContext(mode: .browse, caretRect: nil),
        rows: [],
        selectedRow: 0,
        selectedColumn: 0,
        filteredBase: nil
    ) {
        didSet { needsDisplay = true }
    }

    var showsDegradedBanner = false {
        didSet { needsDisplay = true; invalidateIntrinsicContentSize() }
    }

    var onSelectCell: ((Int, Int) -> Void)?
    var onCommitCell: ((Int, Int) -> Void)?
    var onBannerClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        Self.size(for: session, banner: showsDegradedBanner)
    }

    static func size(for session: PickerSession, banner: Bool) -> NSSize {
        let rows = session.rows
        guard !rows.isEmpty else {
            return NSSize(width: 80, height: Layout.padding * 2 + Layout.cellHeight)
        }
        let showLabels = rows.contains { $0.label != nil }
        var maxRowWidth: CGFloat = 0
        for row in rows {
            let cells = CGFloat(row.cells.count)
            var width = Layout.padding * 2
                + cells * Layout.cellWidth
                + max(0, cells - 1) * Layout.cellSpacing
            if showLabels { width += Layout.labelWidth }
            maxRowWidth = max(maxRowWidth, width)
        }
        let rowCount = CGFloat(rows.count)
        var height = Layout.padding * 2
            + rowCount * Layout.cellHeight
            + max(0, rowCount - 1) * Layout.rowSpacing
        if banner { height += Layout.bannerHeight }
        return NSSize(width: maxRowWidth, height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (row, col) = hitTestCell(point) {
            onSelectCell?(row, col)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsDegradedBanner, point.y < Layout.bannerHeight {
            onBannerClick?()
            return
        }
        if let (row, col) = hitTestCell(point) {
            onSelectCell?(row, col)
            onCommitCell?(row, col)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = effectiveAppearance
        NSAppearance.withAppKitAppearance(appearance) {
            drawChrome()
            var y = Layout.padding
            if showsDegradedBanner {
                drawBanner(in: NSRect(x: 0, y: 0, width: bounds.width, height: Layout.bannerHeight))
                y += Layout.bannerHeight
            }
            let showLabels = session.rows.contains { $0.label != nil }
            for (rowIndex, row) in session.rows.enumerated() {
                drawRow(row, index: rowIndex, y: y, showLabel: showLabels)
                y += Layout.cellHeight + Layout.rowSpacing
            }
        }
    }

    private func drawChrome() {
        // Vibrancy comes from the NSVisualEffectView behind us. A hairline keeps
        // the popover readable on busy backgrounds.
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Layout.cornerRadius, yRadius: Layout.cornerRadius)
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawBanner(in rect: NSRect) {
        let text = "Accessibility needed — click to grant"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: (rect.width - size.width) / 2,
            y: (rect.height - size.height) / 2
        )
        text.draw(at: origin, withAttributes: attrs)
    }

    private func drawRow(_ row: PickerSession.Row, index rowIndex: Int, y: CGFloat, showLabel: Bool) {
        var x = Layout.padding
        if showLabel {
            if let label = row.label {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
                let size = label.size(withAttributes: attrs)
                label.draw(
                    at: NSPoint(x: x, y: y + (Layout.cellHeight - size.height) / 2 - 4),
                    withAttributes: attrs
                )
            }
            x += Layout.labelWidth
        }
        for (col, cell) in row.cells.enumerated() {
            let rect = NSRect(x: x, y: y, width: Layout.cellWidth, height: Layout.cellHeight)
            let selected = rowIndex == session.selectedRow && col == session.selectedColumn
            drawCell(cell, in: rect, selected: selected)
            x += Layout.cellWidth + Layout.cellSpacing
        }
    }

    private func drawCell(_ cell: PickerSession.Cell, in rect: NSRect, selected: Bool) {
        if selected {
            let inset = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: inset, xRadius: Layout.cellRadius, yRadius: Layout.cellRadius)
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            path.fill()
        }
        let glyphColor: NSColor = selected ? .white : .labelColor
        let glyphAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: glyphColor,
        ]
        let glyphSize = cell.glyph.size(withAttributes: glyphAttrs)
        cell.glyph.draw(
            at: NSPoint(
                x: rect.midX - glyphSize.width / 2,
                y: rect.minY + 5
            ),
            withAttributes: glyphAttrs
        )
        if let number = cell.number {
            let indexColor: NSColor = selected
                ? NSColor.white.withAlphaComponent(0.85)
                : NSColor.secondaryLabelColor
            let indexAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: indexColor,
            ]
            let text = "\(number)"
            let size = text.size(withAttributes: indexAttrs)
            text.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 3),
                withAttributes: indexAttrs
            )
        }
    }

    private func hitTestCell(_ point: NSPoint) -> (Int, Int)? {
        var y = Layout.padding
        if showsDegradedBanner { y += Layout.bannerHeight }
        let showLabels = session.rows.contains { $0.label != nil }
        for (rowIndex, row) in session.rows.enumerated() {
            var x = Layout.padding
            if showLabels { x += Layout.labelWidth }
            for col in row.cells.indices {
                let rect = NSRect(x: x, y: y, width: Layout.cellWidth, height: Layout.cellHeight)
                if rect.contains(point) { return (rowIndex, col) }
                x += Layout.cellWidth + Layout.cellSpacing
            }
            y += Layout.cellHeight + Layout.rowSpacing
        }
        return nil
    }
}

private extension NSAppearance {
    static func withAppKitAppearance(_ appearance: NSAppearance, _ body: () -> Void) {
        appearance.performAsCurrentDrawingAppearance(body)
    }
}
