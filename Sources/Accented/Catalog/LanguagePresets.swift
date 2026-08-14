/// Curated language packs + the native macOS hold-key set.
///
/// One Swift file, literal data, no JSON. Within a group, variants follow the native
/// press-and-hold order (`NativeHoldKeyOrder`) so Spanish `e` is just `é` and French `e`
/// is `è é ê ë` — the same sequence the system menu uses, minus the letters that language
/// does not use.
enum LanguagePresets {

    static let all: [LanguagePreset] = [spanish, french, portuguese, german, italian, catalan, allDiacritics]

    static let byID: [String: LanguagePreset] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    /// Load-time checks (unique ids, non-empty glyphs, base consistency). Empty = valid.
    static func validationErrors() -> [String] {
        var errors: [String] = []
        var seen = Set<String>()
        for preset in all {
            if preset.id.isEmpty { errors.append("empty preset id") }
            if !seen.insert(preset.id).inserted { errors.append("duplicate preset id \(preset.id)") }
            for group in preset.groups {
                guard let base = group.base else {
                    errors.append("\(preset.id): letter group missing base")
                    continue
                }
                if group.variants.isEmpty { errors.append("\(preset.id): empty group \(base)") }
                for variant in group.variants {
                    if variant.character.isEmpty { errors.append("\(preset.id): empty glyph in \(base)") }
                    if variant.base != base {
                        errors.append("\(preset.id): \(variant.character) base \(String(describing: variant.base)) != \(base)")
                    }
                }
            }
            for extra in preset.extras {
                if extra.character.isEmpty { errors.append("\(preset.id): empty extra") }
                if extra.base != nil { errors.append("\(preset.id): extra \(extra.character) has a base") }
            }
        }
        return errors
    }

    // MARK: - Native hold-key order (US English macOS press-and-hold)

    /// The system accent menu order. Used as the "All diacritics" preset and as the
    /// within-group sort for `presetOrder` so overlapping unions (Spanish+French `é`)
    /// stay in native sequence rather than "whichever preset was enabled first".
    static let nativeHoldKeyOrder: [(base: Character, glyphs: [String])] = [
        ("a", ["à", "á", "â", "ä", "æ", "ã", "å", "ā"]),
        ("c", ["ç", "ć", "č"]),
        ("e", ["è", "é", "ê", "ë", "ē", "ė", "ę"]),
        ("i", ["ì", "í", "î", "ï", "ī"]),
        ("l", ["ł"]),
        ("n", ["ñ", "ń"]),
        ("o", ["ò", "ó", "ô", "ö", "œ", "õ", "ø", "ō"]),
        ("s", ["ß", "ś", "š"]),
        ("u", ["ù", "ú", "û", "ü", "ū"]),
        ("y", ["ÿ"]),
        ("z", ["ź", "ž", "ż"]),
    ]

    static func nativeIndex(of glyph: String, inBase base: Character) -> Int? {
        let key = glyph.lowercased()
        guard let glyphs = nativeHoldKeyOrder.first(where: { $0.base == base.lowercased().first })?.glyphs else {
            return nil
        }
        return glyphs.firstIndex(of: key)
    }

    // MARK: - Presets

    static let spanish = LanguagePreset(
        id: "es",
        name: "Spanish",
        groups: groups([
            ("a", ["á"]),
            ("e", ["é"]),
            ("i", ["í"]),
            ("n", ["ñ"]),
            ("o", ["ó"]),
            ("u", ["ú", "ü"]),
        ]),
        extras: extras(["¿", "¡"])
    )

    static let french = LanguagePreset(
        id: "fr",
        name: "French",
        groups: groups([
            ("a", ["à", "â", "æ"]),
            ("c", ["ç"]),
            ("e", ["è", "é", "ê", "ë"]),
            ("i", ["î", "ï"]),
            ("o", ["ô", "œ"]),
            ("u", ["ù", "û", "ü"]),
            ("y", ["ÿ"]),
        ]),
        extras: extras(["«", "»"])
    )

    static let portuguese = LanguagePreset(
        id: "pt",
        name: "Portuguese",
        groups: groups([
            ("a", ["à", "á", "â", "ã"]),
            ("c", ["ç"]),
            ("e", ["é", "ê"]),
            ("i", ["í"]),
            ("o", ["ó", "ô", "õ"]),
            ("u", ["ú"]),
        ]),
        extras: []
    )

    static let german = LanguagePreset(
        id: "de",
        name: "German",
        groups: groups([
            ("a", ["ä"]),
            ("o", ["ö"]),
            ("s", ["ß"]),
            ("u", ["ü"]),
        ]),
        extras: []
    )

    static let italian = LanguagePreset(
        id: "it",
        name: "Italian",
        groups: groups([
            ("a", ["à"]),
            ("e", ["è", "é"]),
            ("i", ["ì"]),
            ("o", ["ò", "ó"]),
            ("u", ["ù"]),
        ]),
        extras: []
    )

    /// `ŀ` is Catalan ela geminada (written `l·l`). Modeled as an `l` variant; the middle
    /// dot itself is an extra so it can also be inserted alone.
    static let catalan = LanguagePreset(
        id: "ca",
        name: "Catalan",
        groups: groups([
            ("a", ["à"]),
            ("c", ["ç"]),
            ("e", ["è", "é"]),
            ("i", ["í", "ï"]),
            ("l", ["ŀ"]),
            ("o", ["ò", "ó"]),
            ("u", ["ú", "ü"]),
        ]),
        extras: extras(["·"])
    )

    static let allDiacritics = LanguagePreset(
        id: "all",
        name: "All diacritics",
        groups: nativeHoldKeyOrder.map { groups([( $0.base, $0.glyphs )]).first! },
        extras: extras(["¿", "¡", "«", "»", "·"])
    )

    // MARK: - Builders

    /// Pair each glyph with its uppercase form and attach `base`. Within a group, keep the
    /// caller’s order (presets already list glyphs in native relative order).
    static func groups(_ specs: [(Character, [String])]) -> [BaseGroup] {
        specs.map { base, glyphs in
            let folded = base.lowercased().first ?? base
            return BaseGroup(
                base: folded,
                variants: glyphs.map { variant($0, base: folded) }
            )
        }
    }

    static func extras(_ glyphs: [String]) -> [AccentVariant] {
        glyphs.map { variant($0, base: nil) }
    }

    static func variant(_ glyph: String, base: Character?) -> AccentVariant {
        AccentVariant(character: glyph, uppercase: uppercasePair(for: glyph), base: base)
    }

    /// `ß` → `ẞ` (capital sharp s). Everything else uses `String.uppercased()`.
    static func uppercasePair(for glyph: String) -> String {
        if glyph == "ß" { return "ẞ" }
        return glyph.uppercased()
    }
}
