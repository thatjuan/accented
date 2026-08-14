/// Pure picker state: which cells are showing, which is selected, how keys move.
///
/// No AppKit. `PickerWindowController` renders this and feeds it key/mouse events.
struct PickerSession: Equatable {

    struct Cell: Equatable {
        let variant: AccentVariant
        let glyph: String
        /// 1…9 when this cell is reachable by a number key; nil past the ninth.
        let number: Int?
    }

    struct Row: Equatable {
        /// Base letter label in browse mode. `nil` for extras, and for variant/filtered rows
        /// (the whole panel is already that letter).
        let label: String?
        let cells: [Cell]
    }

    /// Why commit will insert vs replace — frozen at open, even if the user filters browse.
    var context: PickerContext
    var rows: [Row]
    var selectedRow: Int
    var selectedColumn: Int
    /// Browse mode after the user typed a base letter. Commit still inserts.
    var filteredBase: Character?

    var selectedVariant: AccentVariant? {
        guard rows.indices.contains(selectedRow),
              rows[selectedRow].cells.indices.contains(selectedColumn) else { return nil }
        return rows[selectedRow].cells[selectedColumn].variant
    }

    static func build(context: PickerContext, catalog: CharacterCatalog) -> PickerSession? {
        switch context.mode {
        case .variants(let base, let uppercase):
            let variants = catalog.variants(forBase: base)
            guard !variants.isEmpty else { return buildBrowse(context: context, catalog: catalog) }
            return PickerSession(
                context: context,
                rows: [row(variants: variants, uppercase: uppercase, label: nil)],
                selectedRow: 0,
                selectedColumn: 0,
                filteredBase: nil
            )
        case .browse:
            return buildBrowse(context: context, catalog: catalog)
        }
    }

    private static func buildBrowse(context: PickerContext, catalog: CharacterCatalog) -> PickerSession? {
        let groups = catalog.allGroups()
        guard !groups.isEmpty else { return nil }
        let rows: [Row] = groups.map { group in
            let upper = false
            let label: String?
            if let base = group.base {
                label = String(base)
            } else {
                label = nil
            }
            return row(variants: group.variants, uppercase: upper, label: label)
        }
        return PickerSession(
            context: context,
            rows: rows,
            selectedRow: 0,
            selectedColumn: 0,
            filteredBase: nil
        )
    }

    private static func row(variants: [AccentVariant], uppercase: Bool, label: String?) -> Row {
        Row(
            label: label,
            cells: variants.enumerated().map { index, variant in
                Cell(
                    variant: variant,
                    glyph: variant.glyph(uppercase: uppercase),
                    number: index < 9 ? index + 1 : nil
                )
            }
        )
    }

    /// Number key 1–9 against the **selected row**.
    func variant(forNumber number: Int) -> AccentVariant? {
        guard (1...9).contains(number), rows.indices.contains(selectedRow) else { return nil }
        return rows[selectedRow].cells.first { $0.number == number }?.variant
    }

    mutating func moveHorizontal(_ delta: Int) {
        guard rows.indices.contains(selectedRow) else { return }
        let count = rows[selectedRow].cells.count
        guard count > 0 else { return }
        selectedColumn = (selectedColumn + delta + count) % count
    }

    mutating func moveVertical(_ delta: Int) {
        guard rows.count > 1 else { return }
        selectedRow = (selectedRow + delta + rows.count) % rows.count
        let count = rows[selectedRow].cells.count
        if count == 0 {
            selectedColumn = 0
        } else {
            selectedColumn = min(selectedColumn, count - 1)
        }
    }

    mutating func select(row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].cells.indices.contains(column) else { return }
        selectedRow = row
        selectedColumn = column
    }

    /// Type a letter in browse mode: jump to that group's row, or filter to a single variant row.
    /// Returns `true` if the letter was consumed.
    mutating func handleBrowseLetter(_ character: Character, catalog: CharacterCatalog) -> Bool {
        guard case .browse = context.mode else { return false }
        guard let base = character.lowercased().first else { return false }
        let uppercase = character.isUppercase
        let variants = catalog.variants(forBase: base)
        guard !variants.isEmpty else { return false }
        filteredBase = base
        rows = [Self.row(variants: variants, uppercase: uppercase, label: nil)]
        selectedRow = 0
        selectedColumn = 0
        return true
    }
}
