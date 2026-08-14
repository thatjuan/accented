@testable import Accented

#if canImport(Testing)
import Testing

/// Resolution tests for `CharacterCatalog` (#3). Pure data: no AppKit, no AX.
@Suite
struct CharacterCatalogTests {

    private func catalog(
        presets: [String],
        disabled: [String] = [],
        custom: [Character: [String]] = [:],
        order: OrderingMode = .presetOrder,
        usage: [String: Int] = [:]
    ) -> CharacterCatalog {
        CharacterCatalog(
            configuration: CatalogConfiguration(
                enabledPresetIDs: presets,
                disabledCharacters: disabled,
                customVariants: custom,
                orderingMode: order
            ),
            usageCounts: usage
        )
    }

    private func glyphs(_ variants: [AccentVariant], upper: Bool = false) -> [String] {
        variants.map { $0.glyph(uppercase: upper) }
    }

    // MARK: - Bundled data

    @Test
    func bundledPresetsValidate() {
        #expect(LanguagePresets.validationErrors().isEmpty)
    }

    @Test
    func defaultConfigurationIsSpanish() {
        #expect(CatalogConfiguration.default.enabledPresetIDs == ["es"])
        let groups = CharacterCatalog().allGroups()
        #expect(groups.map(\.base) == ["a", "e", "i", "n", "o", "u", nil])
        #expect(glyphs(CharacterCatalog().variants(forBase: "n")) == ["ñ"])
    }

    // MARK: - Union + dedupe

    @Test
    func spanishAndFrenchUnionDedupesOverlaps() {
        let cat = catalog(presets: ["es", "fr"])
        // Native e-order: è é ê ë. Spanish é ∪ French è é ê ë.
        #expect(glyphs(cat.variants(forBase: "e")) == ["è", "é", "ê", "ë"])
        // ü appears in both; once.
        let u = glyphs(cat.variants(forBase: "u"))
        #expect(u.filter { $0 == "ü" }.count == 1)
        #expect(u.contains("ú"))
        #expect(u.contains("ù"))
        #expect(u.contains("û"))
    }

    @Test
    func unknownPresetIDsAreIgnored() {
        let cat = catalog(presets: ["es", "nope", "fr"])
        #expect(!cat.variants(forBase: "e").isEmpty)
        #expect(cat.variants(forBase: "y").map(\.character) == ["ÿ"])
    }

    // MARK: - Disable

    @Test
    func perCharacterDisableRemovesGlyph() {
        let cat = catalog(presets: ["es", "fr"], disabled: ["é", "ü"])
        #expect(!glyphs(cat.variants(forBase: "e")).contains("é"))
        #expect(glyphs(cat.variants(forBase: "e")) == ["è", "ê", "ë"])
        #expect(!glyphs(cat.variants(forBase: "u")).contains("ü"))
    }

    @Test
    func disableIsCaseInsensitive() {
        let cat = catalog(presets: ["es"], disabled: ["É", "Ñ"])
        #expect(cat.variants(forBase: "e").isEmpty)
        #expect(cat.variants(forBase: "n").isEmpty)
    }

    @Test
    func disablingEveryVariantDropsTheGroup() {
        let cat = catalog(presets: ["es"], disabled: ["á", "é", "í", "ó", "ú", "ü", "ñ", "¿", "¡"])
        #expect(cat.allGroups().isEmpty)
    }

    // MARK: - Custom

    @Test
    func customCharacterIsInjected() {
        let cat = catalog(presets: ["es"], custom: ["e": ["ə"]])
        #expect(glyphs(cat.variants(forBase: "e")) == ["é", "ə"])
        #expect(cat.variants(forBase: "e").last?.uppercase == "Ə")
        #expect(cat.variants(forBase: "e").last?.base == "e")
    }

    @Test
    func customOnNewBaseCreatesAGroup() {
        let cat = catalog(presets: ["es"], custom: ["k": ["ḱ"]])
        let row = cat.allGroups().first { $0.base == "k" }
        #expect(row?.variants.map(\.character) == ["ḱ"])
    }

    @Test
    func customSkipsEmptyAndBareBase() {
        let cat = catalog(presets: ["es"], custom: ["e": ["", "  ", "e", "ə"]])
        #expect(glyphs(cat.variants(forBase: "e")) == ["é", "ə"])
    }

    @Test
    func customDoesNotDuplicateExisting() {
        let cat = catalog(presets: ["es"], custom: ["e": ["é", "É"]])
        #expect(glyphs(cat.variants(forBase: "e")) == ["é"])
    }

    // MARK: - Case

    @Test
    func casePairingLowerAndUpper() {
        let cat = catalog(presets: ["es"])
        let a = cat.variants(forBase: "a")
        #expect(glyphs(a) == ["á"])
        #expect(glyphs(a, upper: true) == ["Á"])
        let A = cat.variants(forBase: "A")
        #expect(glyphs(A) == ["á"])
        #expect(glyphs(A, upper: true) == ["Á"])
    }

    @Test
    func sharpSUppercaseIsCapitalSharpS() {
        let cat = catalog(presets: ["de"])
        let ess = cat.variants(forBase: "s").first { $0.character == "ß" }
        #expect(ess?.uppercase == "ẞ")
        #expect(ess?.glyph(uppercase: true) == "ẞ")
    }

    // MARK: - Extras

    @Test
    func extrasSitOnTheLastRow() {
        let cat = catalog(presets: ["es"])
        let rows = cat.allGroups()
        #expect(rows.last?.base == nil)
        #expect(rows.last?.variants.map(\.character) == ["¿", "¡"])
        #expect(rows.last?.variants.allSatisfy { $0.base == nil } == true)
        #expect(rows.dropLast().allSatisfy { $0.base != nil })
    }

    @Test
    func extrasUnionAcrossPresets() {
        let cat = catalog(presets: ["es", "fr"])
        #expect(cat.allGroups().last?.variants.map(\.character) == ["¿", "¡", "«", "»"])
    }

    @Test
    func extrasCanBeDisabled() {
        let cat = catalog(presets: ["es"], disabled: ["¿"])
        #expect(cat.allGroups().last?.variants.map(\.character) == ["¡"])
    }

    // MARK: - Ordering

    @Test
    func presetOrderFollowsNativeHoldKey() {
        let cat = catalog(presets: ["pt"])
        // Portuguese a-set in native order: à á â ã (not the source-list à á â ã wait —
        // spec lists ã á â à; native is à á â … ã).
        #expect(glyphs(cat.variants(forBase: "a")) == ["à", "á", "â", "ã"])
    }

    @Test
    func mruPutsMostUsedFirst() {
        let cat = catalog(
            presets: ["fr"],
            order: .mostRecentlyUsed,
            usage: ["ê": 5, "è": 1]
        )
        #expect(glyphs(cat.variants(forBase: "e")) == ["ê", "è", "é", "ë"])
    }

    @Test
    func mruTiesKeepNativeOrder() {
        let cat = catalog(
            presets: ["fr"],
            order: .mostRecentlyUsed,
            usage: ["è": 3, "ê": 3, "é": 3, "ë": 3]
        )
        #expect(glyphs(cat.variants(forBase: "e")) == ["è", "é", "ê", "ë"])
    }

    @Test
    func mruDoesNotMoveUnusedCustomsAheadOfUsedNative() {
        let cat = catalog(
            presets: ["es"],
            custom: ["e": ["ə"]],
            order: .mostRecentlyUsed,
            usage: ["é": 2]
        )
        #expect(glyphs(cat.variants(forBase: "e")) == ["é", "ə"])
    }
}

#else

enum CatalogLinkCheck {
    static let spanishID = LanguagePresets.spanish.id
}

#endif
