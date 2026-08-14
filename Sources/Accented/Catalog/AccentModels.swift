/// One accented (or extra) character and its case pair.
///
/// `base` is the letter #7 matches for replace mode (`a` → pick `á` replaces the `a`).
/// Extras (`¿`, `«`) have `base == nil` and insert rather than replace.
struct AccentVariant: Equatable, Hashable, Sendable {
    /// Canonical (lowercase / uncased) glyph shown when the context character is lowercase.
    let character: String
    /// Glyph shown when the context character is uppercase (`á` → `Á`, `ß` → `ẞ`).
    let uppercase: String
    /// Base letter for replace-mode matching. `nil` for extras with no base.
    let base: Character?

    /// The glyph the picker / insertion engine should commit for this context case.
    func glyph(uppercase useUpper: Bool) -> String {
        useUpper ? uppercase : character
    }
}

/// One picker row: a base letter and its enabled variants. `base == nil` is the extras row
/// (browse-mode last row: `¿ ¡ « » ·`).
struct BaseGroup: Equatable, Sendable {
    let base: Character?
    let variants: [AccentVariant]
}

/// A language (or "all diacritics") pack. Data is compile-time literals in `LanguagePresets.swift`.
struct LanguagePreset: Equatable, Sendable {
    let id: String
    let name: String
    let groups: [BaseGroup]
    let extras: [AccentVariant]
}

/// How `CharacterCatalog` orders variants inside a group. Persistence lives in `SettingsStore` (#8);
/// the catalog is handed the mode and a usage-count map, it does not read defaults itself.
enum OrderingMode: String, Equatable, Sendable, CaseIterable, Identifiable {
    /// Native macOS hold-key order (then first-seen across enabled presets, then customs).
    case presetOrder
    /// Higher `usageCounts` first; ties keep `presetOrder` (stable).
    case mostUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .presetOrder: return "Preset order"
        case .mostUsed: return "Most used"
        }
    }
}

/// User configuration the catalog resolves against. Default-on Spanish matches Settings v1 (#8).
struct CatalogConfiguration: Equatable, Sendable {
    var enabledPresetIDs: [String]
    var disabledCharacters: [String]
    /// Extra glyphs the user attached to a base letter (`e` → `["ə"]`).
    var customVariants: [Character: [String]]
    /// Custom extras (no base), e.g. extra punctuation.
    var customExtras: [String]
    var orderingMode: OrderingMode

    static let `default` = CatalogConfiguration(
        enabledPresetIDs: ["es"],
        disabledCharacters: [],
        customVariants: [:],
        customExtras: [],
        orderingMode: .presetOrder
    )
}
