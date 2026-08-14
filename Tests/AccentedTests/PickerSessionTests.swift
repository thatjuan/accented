@testable import Accented
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct PickerSessionTests {

    private let catalog = CharacterCatalog() // default Spanish

    @Test
    func variantModeUsesThatLetterAndNumbers() {
        let context = PickerContext(mode: .variants(base: "a", uppercase: false), caretRect: nil)
        let session = PickerSession.build(context: context, catalog: catalog)
        #expect(session?.rows.count == 1)
        #expect(session?.rows.first?.cells.map(\.glyph) == ["á"])
        #expect(session?.rows.first?.cells.first?.number == 1)
        #expect(session?.variant(forNumber: 1)?.character == "á")
        #expect(session?.selectedVariant?.character == "á")
    }

    @Test
    func variantModeUppercaseGlyphs() {
        let context = PickerContext(mode: .variants(base: "n", uppercase: true), caretRect: nil)
        let session = PickerSession.build(context: context, catalog: catalog)
        #expect(session?.rows.first?.cells.map(\.glyph) == ["Ñ"])
    }

    @Test
    func browseHasLabeledRowsAndExtrasLast() {
        let context = PickerContext(mode: .browse, caretRect: nil)
        let session = PickerSession.build(context: context, catalog: catalog)
        #expect(session?.rows.last?.label == nil)
        #expect(session?.rows.last?.cells.map(\.glyph).contains("¿") == true)
        #expect(session?.rows.dropLast().allSatisfy { $0.label != nil } == true)
    }

    @Test
    func browseLetterFiltersToThatGroup() {
        var session = PickerSession.build(
            context: PickerContext(mode: .browse, caretRect: nil),
            catalog: catalog
        )!
        let consumed = session.handleBrowseLetter("e", catalog: catalog)
        #expect(consumed)
        #expect(session.rows.count == 1)
        #expect(session.rows.first?.cells.map(\.glyph) == ["é"])
        #expect(session.filteredBase == "e")
        #expect(session.context.mode == .browse)
    }

    @Test
    func arrowsWrapWithinAndAcrossRows() {
        var session = PickerSession.build(
            context: PickerContext(mode: .browse, caretRect: nil),
            catalog: catalog
        )!
        let startRow = session.selectedRow
        session.moveVertical(1)
        #expect(session.selectedRow == startRow + 1)
        session.moveVertical(-1)
        #expect(session.selectedRow == startRow)
        session.moveHorizontal(1)
        // extras row has 2 cells (¿ ¡); first letter rows have 1 — wrapping stays valid
        #expect(session.selectedColumn >= 0)
        #expect(session.rows[session.selectedRow].cells.indices.contains(session.selectedColumn))
    }

    @Test
    func placementPrefersAboveCaretAndFlipsWhenNeeded() {
        let size = CGSize(width: 100, height: 40)
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let mid = PickerPlacement.frame(
            size: size,
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 14),
            mouse: .zero,
            screen: screen
        )
        #expect(mid.minY >= 200 + 14)
        let top = PickerPlacement.frame(
            size: size,
            caretRect: CGRect(x: 100, y: 560, width: 2, height: 14),
            mouse: .zero,
            screen: screen
        )
        #expect(top.maxY <= 560)
    }

    @Test
    func emptyCaretFallsBackToMouse() {
        let size = CGSize(width: 80, height: 40)
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = PickerPlacement.frame(
            size: size,
            caretRect: .zero,
            mouse: CGPoint(x: 400, y: 300),
            screen: screen
        )
        #expect(abs(frame.midX - 400) < 20)
    }
}

#else

enum PickerLinkCheck {
    static let gap = PickerPlacement.gap
}

#endif
