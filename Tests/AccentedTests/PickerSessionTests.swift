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
    func browseIsOneHorizontalRowWithExtrasLast() {
        let context = PickerContext(mode: .browse, caretRect: nil)
        let session = PickerSession.build(context: context, catalog: catalog)
        #expect(session?.rows.count == 1)
        #expect(session?.rows.first?.label == nil)
        let glyphs = session?.rows.first?.cells.map(\.glyph) ?? []
        #expect(glyphs.contains("á"))
        #expect(glyphs.suffix(2) == ["¿", "¡"])
        #expect(session?.rows.first?.cells.first?.number == 1)
    }

    @Test
    func browseLetterFiltersWhenSeveralVariants() {
        var session = PickerSession.build(
            context: PickerContext(mode: .browse, caretRect: nil),
            catalog: catalog
        )!
        // Spanish `u` is ú + ü. A single-option letter commits instead (see below).
        let result = session.handleBrowseLetter("u", catalog: catalog)
        #expect(result == .filtered)
        #expect(session.rows.count == 1)
        #expect(session.rows.first?.cells.map(\.glyph) == ["ú", "ü"])
        #expect(session.filteredBase == "u")
        #expect(session.context.mode == .browse)
    }

    @Test
    func browseLetterCommitsWhenOnlyOneVariant() {
        var session = PickerSession.build(
            context: PickerContext(mode: .browse, caretRect: nil),
            catalog: catalog
        )!
        let result = session.handleBrowseLetter("a", catalog: catalog)
        #expect(result == .commit(catalog.variants(forBase: "a")[0]))
        #expect(session.filteredBase == nil)
        #expect(session.rows.first?.cells.map(\.glyph).contains("á") == true)
    }

    @Test
    func variantModeWithOneOptionIsSingleChoice() {
        let session = PickerSession.build(
            context: PickerContext(mode: .variants(base: "a", uppercase: false), caretRect: nil),
            catalog: catalog
        )
        #expect(session?.isSingleChoice == true)
        #expect(session?.selectedVariant?.character == "á")
    }

    @Test
    func pressingTheSameLetterInVariantModeCommitsTheOnlyOption() {
        var session = PickerSession.build(
            context: PickerContext(mode: .variants(base: "a", uppercase: false), caretRect: nil),
            catalog: catalog
        )!
        #expect(session.handleBrowseLetter("a", catalog: catalog) == .commit(catalog.variants(forBase: "a")[0]))
    }

    @Test
    func arrowsWrapAlongTheSingleRow() {
        var session = PickerSession.build(
            context: PickerContext(mode: .browse, caretRect: nil),
            catalog: catalog
        )!
        #expect(session.rows.count == 1)
        let last = session.rows[0].cells.count - 1
        session.moveVertical(1)
        #expect(session.selectedRow == 0)
        session.moveHorizontal(1)
        #expect(session.selectedColumn == 1)
        session.selectedColumn = last
        session.moveHorizontal(1)
        #expect(session.selectedColumn == 0)
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
    func offScreenCaretIsRejected() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        #expect(PickerPlacement.usableCaret(CGRect(x: 100, y: 200, width: 2, height: 14), screens: screens) != nil)
        #expect(PickerPlacement.usableCaret(CGRect(x: -11614, y: -1437, width: 20, height: 16), screens: screens) == nil)
        #expect(PickerPlacement.usableCaret(.zero, screens: screens) == nil)
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
