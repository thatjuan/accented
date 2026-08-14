/// Pure context-mode decision: preceding character + catalog → picker mode.
/// AX and CGEvent stay out of this type so #7's acceptance tests don't need a live app.
enum InsertionContextDecision {

    /// Character immediately before an empty caret, or `nil` if there isn't one
    /// (location 0, a non-empty selection, or an empty string).
    static func precedingCharacter(in value: String, caretLocation: Int, selectedLength: Int = 0) -> Character? {
        guard selectedLength == 0, caretLocation > 0 else { return nil }
        guard caretLocation <= value.count else { return nil }
        let index = value.index(value.startIndex, offsetBy: caretLocation - 1)
        return value[index]
    }

    /// `.variants` when `preceding` is an enabled base letter; otherwise `.browse`.
    /// Fail open: missing/unknown preceding never blocks the picker.
    static func mode(preceding: Character?, selectedLength: Int = 0, catalog: CharacterCatalog) -> PickerContext.Mode {
        guard selectedLength == 0, let preceding else { return .browse }
        let variants = catalog.variants(forBase: preceding)
        guard !variants.isEmpty else { return .browse }
        return .variants(base: preceding, uppercase: preceding.isUppercase)
    }
}
