/// Resolves enabled presets + user customization into the lists the picker shows.
///
/// Pure decision type: no AppKit, no persistence. `SettingsStore` (#8) owns the
/// configuration and the usage-count map; this type just answers questions.
///
/// Load-time validation of the bundled presets runs on first `init` (debug assert)
/// so a typo in `LanguagePresets` fails tests rather than shipping a broken row.
struct CharacterCatalog: Equatable, Sendable {

    var configuration: CatalogConfiguration
    /// Lowercase glyph → commit count. Only consulted when `orderingMode == .mostUsed`.
    var usageCounts: [String: Int]

    init(
        configuration: CatalogConfiguration = .default,
        usageCounts: [String: Int] = [:],
        presets: [LanguagePreset] = LanguagePresets.all
    ) {
        #if DEBUG
        let errors = LanguagePresets.validationErrors()
        assert(errors.isEmpty, "LanguagePresets invalid: \(errors.joined(separator: "; "))")
        #endif
        self.configuration = configuration
        self.usageCounts = usageCounts
        self.presetsByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
        self.presetOrder = presets
    }

    private let presetsByID: [String: LanguagePreset]
    private let presetOrder: [LanguagePreset]

    // MARK: - Queries

    /// Variants for a base letter (case-insensitive). Empty if nothing is enabled for it.
    /// Returned `AccentVariant`s always carry both cases; the picker uses
    /// `glyph(uppercase:)` when the context character is uppercase.
    func variants(forBase rawBase: Character) -> [AccentVariant] {
        guard let base = Self.foldedBase(rawBase) else { return [] }
        return ordered(union(for: base), inBase: base)
    }

    /// Browse-mode rows: enabled letter groups in native base order, extras last.
    /// Empty groups (everything disabled) are omitted.
    func allGroups() -> [BaseGroup] {
        var bases: [Character] = []
        var seen = Set<Character>()
        for (base, _) in LanguagePresets.nativeHoldKeyOrder {
            if !seen.contains(base) {
                seen.insert(base)
                bases.append(base)
            }
        }
        for preset in enabledPresets() {
            for group in preset.groups {
                if let base = group.base, seen.insert(base).inserted {
                    bases.append(base)
                }
            }
        }
        for base in configuration.customVariants.keys {
            if let folded = Self.foldedBase(base), seen.insert(folded).inserted {
                bases.append(folded)
            }
        }

        var rows: [BaseGroup] = []
        for base in bases {
            let variants = ordered(union(for: base), inBase: base)
            if !variants.isEmpty {
                rows.append(BaseGroup(base: base, variants: variants))
            }
        }
        let extras = orderedExtras()
        if !extras.isEmpty {
            rows.append(BaseGroup(base: nil, variants: extras))
        }
        return rows
    }

    // MARK: - Union

    private func enabledPresets() -> [LanguagePreset] {
        configuration.enabledPresetIDs.compactMap { presetsByID[$0] }
    }

    private func disabledSet() -> Set<String> {
        Set(configuration.disabledCharacters.map { $0.lowercased() })
    }

    /// Union of enabled presets + customs for `base`, disabled glyphs removed, deduped
    /// by lowercase character. Order is first-seen (preset enable order, then native
    /// listing, then customs); `ordered(_:inBase:)` applies the user-facing sort.
    private func union(for base: Character) -> [AccentVariant] {
        let disabled = disabledSet()
        var seen = Set<String>()
        var result: [AccentVariant] = []

        func append(_ variant: AccentVariant) {
            let key = variant.character.lowercased()
            guard !key.isEmpty, !disabled.contains(key), seen.insert(key).inserted else { return }
            result.append(variant)
        }

        for preset in enabledPresets() {
            if let group = preset.groups.first(where: { $0.base == base }) {
                group.variants.forEach(append)
            }
        }

        let customKey = configuration.customVariants.keys.first { Self.foldedBase($0) == base }
        if let customKey, let glyphs = configuration.customVariants[customKey] {
            for glyph in glyphs {
                let trimmed = glyph.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard trimmed.lowercased() != String(base) else { continue }
                append(LanguagePresets.variant(trimmed, base: base))
            }
        }
        return result
    }

    private func orderedExtras() -> [AccentVariant] {
        let disabled = disabledSet()
        var seen = Set<String>()
        var result: [AccentVariant] = []
        for preset in enabledPresets() {
            for extra in preset.extras {
                let key = extra.character.lowercased()
                guard !disabled.contains(key), seen.insert(key).inserted else { continue }
                result.append(extra)
            }
        }
        for glyph in configuration.customExtras {
            let trimmed = glyph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !disabled.contains(key), seen.insert(key).inserted else { continue }
            result.append(LanguagePresets.variant(trimmed, base: nil))
        }
        return ordered(result, inBase: nil)
    }

    // MARK: - Ordering

    private func ordered(_ variants: [AccentVariant], inBase base: Character?) -> [AccentVariant] {
        variants.enumerated().sorted { a, b in
            if configuration.orderingMode == .mostUsed {
                let ac = usageCounts[a.element.character] ?? 0
                let bc = usageCounts[b.element.character] ?? 0
                if ac != bc { return ac > bc }
            }
            let ar = nativeRank(a.element, base: base)
            let br = nativeRank(b.element, base: base)
            if ar != br { return ar < br }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Native hold-key index when known; otherwise after every native glyph, in first-seen order
    /// (offset baked in by leaving the input sequence and using a high rank).
    private func nativeRank(_ variant: AccentVariant, base: Character?) -> Int {
        if let base, let index = LanguagePresets.nativeIndex(of: variant.character, inBase: base) {
            return index
        }
        return 1_000
    }

    private static func foldedBase(_ character: Character) -> Character? {
        character.lowercased().first
    }
}
