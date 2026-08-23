import Foundation

/// Curated language packs + the native macOS hold-key set.
///
/// One Swift file, literal data, no JSON. Within a group, variants follow the native
/// press-and-hold order (`NativeHoldKeyOrder`) so Spanish `e` is just `é` and French `e`
/// is `è é ê ë` — the same sequence the system menu uses, minus the letters that language
/// does not use.
extension LanguagePreset {
    /// Compact sample for Settings language rows: "á é í ó ú ü ñ ¿ ¡"
    var sample: String {
        let letters = groups.flatMap { $0.variants.map(\.character) }
        let extra = extras.map(\.character)
        return (letters + extra).joined(separator: " ")
    }
}

enum LanguagePresets {

    static let all: [LanguagePreset] = [spanish, french, portuguese, german, italian, catalan, turkish, allDiacritics]

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

    /// The system accent menu order, plus bases macOS has no hold menu for (`g`) that a
    /// preset needs a row for. Used as the "All diacritics" preset, as the base order for
    /// browse mode and the custom-character dropdown, and as the within-group sort for
    /// `presetOrder` so overlapping unions (Spanish+French `é`) stay in native sequence
    /// rather than "whichever preset was enabled first".
    static let nativeHoldKeyOrder: [(base: Character, glyphs: [String])] = [
        ("a", ["à", "á", "â", "ä", "æ", "ã", "å", "ā"]),
        ("c", ["ç", "ć", "č"]),
        ("e", ["è", "é", "ê", "ë", "ē", "ė", "ę"]),
        ("g", ["ğ"]),
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

    /// Turkish. `ı` is the dotless i: the picker slot means "the other i", so it pairs
    /// with `İ` (dotted capital) rather than with Swift's `"ı".uppercased()`, which is `I`.
    /// See `uppercasePair(for:)`.
    static let turkish = LanguagePreset(
        id: "tr",
        name: "Turkish",
        groups: groups([
            ("c", ["ç"]),
            ("g", ["ğ"]),
            ("i", ["ı"]),
            ("o", ["ö"]),
            ("s", ["ş"]),
            ("u", ["ü"]),
        ]),
        extras: []
    )

    static let allDiacritics = LanguagePreset(
        id: "all",
        name: "All diacritics",
        groups: nativeHoldKeyOrder.map { groups([( $0.base, $0.glyphs )]).first! },
        extras: extras(["¿", "¡", "«", "»", "·"])
    )

    // MARK: - Custom palettes

    /// Text field → glyph list, the one definition of "what counts as a glyph in a palette".
    ///
    /// Whitespace and commas are separators, everything else is a glyph. Case is folded
    /// (`Á` → `á`), duplicates collapse, and bare ASCII letters (`a`) are dropped because
    /// `CharacterCatalog` already skips a glyph equal to its own base. Glyphs whose lowercase
    /// form is more than one `Character` are dropped too — `İ` is the only such glyph in
    /// practice, and `ı` is the slot that pairs with it (see `uppercasePair(for:)`).
    static func normalizeGlyphs(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for character in text {
            if character.isWhitespace || character == "," { continue }
            let folded = String(character).lowercased()
            guard folded.count == 1 else { continue }
            if let scalar = folded.unicodeScalars.first, scalar.isASCII, CharacterSet.letters.contains(scalar) {
                continue
            }
            guard seen.insert(folded).inserted else { continue }
            result.append(folded)
        }
        return result
    }

    /// The base letter a glyph belongs under in the picker, or `nil` if it is an extra.
    ///
    /// Native hold-key table first, then every bundled preset (catches `ŀ`, `ı`, `ş`), then
    /// Unicode decomposition (catches anything else the user pastes: `ő`, `ǎ`, `ṕ`).
    static func inferBase(for glyph: String) -> Character? {
        let key = glyph.lowercased()
        guard !key.isEmpty else { return nil }

        if let entry = nativeHoldKeyOrder.first(where: { $0.glyphs.contains(key) }) {
            return entry.base
        }
        for preset in all {
            for group in preset.groups where group.variants.contains(where: { $0.character == key }) {
                return group.base
            }
        }
        if let scalar = key.decomposedStringWithCanonicalMapping.unicodeScalars.first,
           scalar.isASCII,
           CharacterSet.letters.contains(scalar) {
            return Character(scalar)
        }
        return nil
    }

    /// Resolve a user palette into a preset so it unions with the bundled languages unchanged.
    /// Groups follow native base order; bases macOS has no hold menu for come after, alphabetical.
    static func preset(for palette: CustomPalette) -> LanguagePreset {
        var byBase: [Character: [String]] = [:]
        var baseOrder: [Character] = []
        var extraGlyphs: [String] = []

        for glyph in normalizeGlyphs(palette.glyphs.joined()) {
            guard let base = inferBase(for: glyph) else {
                extraGlyphs.append(glyph)
                continue
            }
            if byBase[base] == nil { baseOrder.append(base) }
            byBase[base, default: []].append(glyph)
        }

        let nativeBases = nativeHoldKeyOrder.map { $0.base }
        let sortedBases = baseOrder.sorted { a, b in
            switch (nativeBases.firstIndex(of: a), nativeBases.firstIndex(of: b)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a < b
            }
        }

        return LanguagePreset(
            id: palette.id,
            name: palette.name,
            groups: sortedBases.map { base in
                BaseGroup(base: base, variants: (byBase[base] ?? []).map { variant($0, base: base) })
            },
            extras: extras(extraGlyphs)
        )
    }

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

    /// Hand-picked case pairs, then `String.uppercased()`.
    ///
    /// `ß` → `ẞ` (capital sharp s).
    ///
    /// `ı` → `İ`: not a Unicode case pair (`"ı".uppercased()` is `I`), but the picker slot
    /// means "the other i", so a lowercase context offers dotless `ı` and an uppercase one
    /// offers dotted `İ`. `character` stays `ı` so lowercase-keyed lookups (disabled set, usage
    /// counts, union dedupe) never see `İ`, whose `lowercased()` is two scalars (`i` + U+0307).
    static func uppercasePair(for glyph: String) -> String {
        if glyph == "ß" { return "ẞ" }
        if glyph == "ı" { return "İ" }
        return glyph.uppercased()
    }
}
